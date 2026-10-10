"""Live trainer for the decision value net (docs/35-decision-net.md).

    python tools/nntrain.py            # learn from running and finished games until stopped
    python tools/nntrain.py --once     # take what is waiting, then exit
    python tools/nntrain.py --reset    # start a fresh net; the old one is archived, never deleted
    python tools/nntrain.py --export   # write the current net into the deployed AI now
    python tools/nntrain.py --migrate  # convert every legacy *buffer.npz to shards, then exit (trainer stopped)
    python tools/nntrain.py --compact  # rewrite buffers without the rows the per-regime cap drops
    python tools/nntrain.py --snapshot # copy the exported weights to runtime/nn/snapshots/<stamp>/ now

LIVE: every POLL_S it reads each RUNNING game's own log files (the engine write
dirs under matches/_engine* and runtime/engine-w*). A decision is trainable
once its 5-minute window has been played. Each batch of newly matured
decisions is predicted FIRST -- an accuracy point on data the net has never
seen -- then trained on, mixed with an equal sample of everything before it,
so the net does not drift toward whichever game is loudest. A finished game's
leftovers are taken from its match dir; nothing is counted twice (games are
keyed by their first records, the same live or finished).

Two nets learn side by side: FULL sees the state and the decision, STATE the
state alone. Full beating state is the evidence that decisions carry value
the net can learn. Every games-worth of data the FULL net is exported as
nnweights.as into the deployed AI copies listed in runtime/nn/targets.json,
so every game that starts afterwards plays with it (apex_nn_blend > 0).

Writes runtime/nn/: metrics.jsonl, status.json, model.pt, seen.json, the
buffers as append-only shards (shards/<net>_rows/, tools/nnstore.py; every row
tagged with its game's script version and regime), and every SNAPSHOT_S a copy
of the exported weights in snapshots/<stamp>/ (tools/nneval.py compares them).
"""
import copy
import json
import math
import os
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402
import decisions  # noqa: E402
import nnstore  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
# BARAI_NN_OUT: a second trainer (a rebuild on new targets) keeps its own net and buffers
OUT = Path(os.environ.get("BARAI_NN_OUT", str(REPO / "runtime" / "nn")))
NO_EXPORT = bool(os.environ.get("BARAI_NN_NOEXPORT"))   # ...and never writes the deployed weights
NO_LIVE = bool(os.environ.get("BARAI_NN_NOLIVE"))       # ...nor reads running games
FINISHED = (REPO / "tournaments", REPO / "matches")
LIVE = ((REPO / "matches", "_engine"), (REPO / "runtime", "engine-w"))
KINDS = ("mex", "mexup", "energy", "geo", "convert", "store", "plant", "tech", "nano",
         "reclaim", "assist", "protect", "sense", "airdef", "super", "teeth")
OPT_NUM = ("value", "gain", "m", "t", "cm", "ce", "bt", "walk", "risk", "eta", "dPow", "ownN",
           "tierO", "fwd", "siteLoss", "persona")   # nnlog.as NnOpt order
PER_H = ("dMInc", "dEInc", "dEco", "lnD", "eWaste", "mWaste", "dMex", "lostNear", "lostFar",
         "lostAir", "lostStatic", "lostMobile", "reclaim")
# a share of what was made: over a near-empty window it ran to the hundreds and
# put the 10-minute mWaste R2 at -9.9; clipped to [0, 1] (also on load)
WASTE = ("mWaste", "eWaste")
LOGGED = ("lostNear", "lostFar", "lostAir", "lostStatic", "lostMobile", "reclaim", "lifeS", "lifeKill")
SINGLE = ("done", "survived", "lifeS", "lifeKill", "won", "comLost", "endV", "comLostD")    # one value per decision, not per horizon
EDGE_H = ("edgeArmy", "edgeEco", "edgeLand", "edgeMex")   # 2026-10-08: did the game move our way
# Only ever appended to: a saved net and buffer then grow masked columns (adopt_targets).
TARGETS = ([(h, k) for h in decisions.HORIZONS for k in PER_H] + [(k, k) for k in SINGLE]
           + [(h, k) for h in decisions.HORIZONS for k in EDGE_H] + [("endFast", "endFast")])
# One value for every row of a game: a single game's batch has no spread to
# explain, and their R2 there ran to large negatives and swamped the headline.
GAME_LEVEL = ("won", "endV", "endFast", "comLostD")
TARGET_NAMES = np.array(["%s:%s" % t for t in TARGETS])   # saved with each buffer: what its columns hold
SCHEMA_OPT = "forced"   # an option field only the current record (v5+) carries
SCHEMA_STATE = "repairM"   # a state field only the current record carries: older rows are skipped, not a reset
Y_FLOOR = 0.1           # a rare outcome must not get a near-zero spread and swamp the loss
DECIDED = ("draw", "ladder")   # rows where an option was chosen on value, not forced
# What "better" means when the net plays, in units of each outcome's spread.
# A stated default until he picks one (docs/35).
OBJECTIVE = {(5, "dEco"): 0.5, (10, "dEco"): 1.0, (5, "dMInc"): 0.25, (5, "dEInc"): 0.25,
             (5, "lnD"): 0.25, (10, "lnD"): 0.5, (5, "lostNear"): -0.5,
             ("done", "done"): 0.25, ("survived", "survived"): 0.25,
             ("lifeS", "lifeS"): 0.25, ("lifeKill", "lifeKill"): 0.25,
             ("endV", "endV"): 1.0,   # the game result, discounted by how far ahead it came (his 2026-10-06)
             ("comLostD", "comLostD"): -2.0,   # the commander must not die (10-05), discounted the same way
             # half endV's weight: one value per game, so its credit to a decision is noisier
             ("endFast", "endFast"): 0.5,
             (5, "edgeArmy"): 0.25, (10, "edgeArmy"): 0.25, (5, "edgeLand"): 0.25, (10, "edgeLand"): 0.5,
             (10, "edgeEco"): 0.25, (10, "edgeMex"): 0.25,
             # the opening (his 10-09): mexes taken and kept, early income; short horizons label
             # decisions near a short game's end that the 5- and 10-minute ones cannot reach
             (1, "dMInc"): 0.25, (1, "dMex"): 0.25,
             (3, "dEco"): 0.5, (3, "dMInc"): 0.25, (3, "dMex"): 0.5, (3, "lostNear"): -0.25,
             (3, "edgeMex"): 0.25, (3, "edgeLand"): 0.25}
# the dashboard's headline accuracy: the per-decision outcomes the net is steered by
HEADLINE = [i for i, t in enumerate(TARGETS) if t in OBJECTIVE and t[1] not in GAME_LEVEL]
HIDDEN = 32
# What plays is a running average of the trained weights, half of it from the
# last EMA_HALF batches: one game moves it a little, a run of games moves it a
# lot.
EMA_HALF = 5
SCALER_ROWS = 100000
LR0 = 1e-3              # Adam's rate before a freeze
LR_DECAY = 2000         # batches after the freeze that halve it ...
LR_FLOOR = 0.2          # ... down to this share of LR0


def freeze_info():
    """runtime/nn/freeze.json: {at, batch, rows: {net: buffer rows at the
    freeze}} -- a stretch where the game code holds still."""
    try:
        return json.loads((OUT / "freeze.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def freeze_note(name, rows, batches):
    """The first trainer to load after a freeze is declared records where
    each net's buffer stood; returns (rows at the freeze, batch at the freeze)."""
    fz = freeze_info()
    if not fz:
        return 0, None
    if name not in fz.setdefault("rows", {}):
        fz["rows"][name] = int(rows)
        fz.setdefault("batch", {})[name] = int(batches)
        (OUT / "freeze.json").write_text(json.dumps(fz), encoding="utf-8")
    return fz["rows"][name], fz.get("batch", {}).get(name)


def lr_now(batches, freeze_batch):
    if freeze_batch is None:
        return LR0
    k = max(0, batches - freeze_batch) / float(LR_DECAY)
    return LR0 * max(LR_FLOOR, 1.0 / (1.0 + k))   # input/output scalers are fit on a sample this size
DROPOUT = 0.1
MIN_BATCH = 150        # matured decisions before a live game is learned from
# Each incoming batch (one game's rows; a live game sends a few) gets this many
# minibatches of MB rows, at most MB_NEW of them new and the rest replay.
STEPS_PER_GAME = 50
STEPS_PER_ROW = 2      # ...but never fewer than 2 looks at each new row (a big finished batch)
MB = 512
MB_NEW = 128
# Replay: half recency-weighted (row age ~ exponential, e-folding at REPLAY_TAU
# of the buffer, at least REPLAY_TAU_MIN rows), half from everything with each
# script version weighted by how many versions ago it played (VER_HALF halves
# it, VER_FLOOR the least; untagged pre-banner rows count as OLD_VER_W).
REPLAY_TAU = 0.05
REPLAY_TAU_MIN = 20000
VER_HALF = 4
VER_FLOOR = 0.1
OLD_VER_W = 0.1
RESET_ROWS = 40000     # rows learned between partial resets (shrink 0.8, perturb 0.2): ~40 builder batches
# Newest rows kept per regime (map | team sizes | minute cap) when a buffer
# loads; the rest stay on disk until --compact. Generous: nothing is dropped today.
REGIME_KEEP = int(os.environ.get("BARAI_NN_REGIME_KEEP", "10000000"))
SNAPSHOT_S = 6 * 3600  # seconds between copies of the exported weights (snapshots/<stamp>/)
EXPORT_ROWS = 800      # new rows between weight exports
POLL_S = 5
LIVE_IDLE_S = 90       # a write dir untouched this long is not a running game
SAVE_S = 120            # seconds between saves; every net is written together, and at idle
SCALER_GROW = 1.1       # refit input/target scalers when the buffer has grown this much
TRUST_KEEP = 5000       # most recent unseen decisions per kind that set its trust
TRUST_MIN = 200         # a kind with fewer gets no say (trust 0)
HUMAN_TAG = "mp-"         # matches/mp-*: his multiplayer games (tools/mp_archive.py)
HUMAN_W = 4               # their rows count this many times in training, never in trust
TRUST_RECENT = 5000     # trust is the CURRENT net's: older pairs scored weights since replaced
USED_KEEP_S = 7200      # seconds a game's used-decision list is kept after its last batch
LIVE_REREAD_S = 15     # a running game is re-read at most this often
LOGGER_SINCE = 1791160000   # 2026-10-04: no finished game before this carries apex: nn


def append_rows(obj, XF, Y, M, T):
    """Add a game's rows to obj.XF/Y/M/T without copying the whole buffer: the
    arrays are views of the first n rows of buffers with spare room (grown 25% at
    a time). An array replaced from outside (load, adopt_keys' column insert) is
    copied into fresh room once."""
    new = {"XF": XF, "Y": Y, "M": M, "T": T}
    n0, k = len(obj.Y), len(Y)
    cap = getattr(obj, "_cap", None)
    fits = cap is not None and all(
        getattr(obj, a).base is cap[a] and cap[a].shape[0] >= n0 + k
        and cap[a].shape[1:] == new[a].shape[1:] for a in new)
    if not fits:
        room = max(int((n0 + k) * 1.25), n0 + k + 1024)
        cap = {}
        for a in new:
            cur = getattr(obj, a)
            cap[a] = np.empty((room,) + cur.shape[1:], dtype=cur.dtype)
            cap[a][:n0] = cur
        obj._cap = cap
    for a in new:
        cap[a][n0:n0 + k] = new[a]
        setattr(obj, a, cap[a][:n0 + k])


def adopt_keys(obj, keys):
    """True when a game's state layout can be learned without starting over:
    the same, an older record missing fields appended since (they read 0), or
    a newer one appending fields (the net and its buffer grow zero columns)."""
    old = obj.state_keys
    if old is None or keys == old or old[:len(keys)] == keys:
        return True
    if keys[:len(old)] != old:
        return False
    at, n = len(old), len(keys) - len(old)
    if obj.XF is not None:
        obj.XF = np.insert(obj.XF, [at] * n, 0.0, axis=1)
        obj.ns += n
    for net in (obj.full, obj.st):
        if net is not None:
            net.grow(at, n)
    obj.state_keys = list(keys)
    print("%s: %d state fields appended (%s); weights kept" % (getattr(obj, "NAME", "builder"), n, ",".join(keys[at:])), flush=True)
    return True


def saved_targets(ck, buf):
    """(the targets the saved net predicts, those the saved buffer's columns hold).
    A buffer written before it recorded its own is read by its width."""
    net_t = [tuple(t) for t in ck.get("targets", [])]
    if "targets" in buf:
        buf_t = [tuple(s.split(":", 1)) for s in buf["targets"]]
        buf_t = [(int(h) if h.isdigit() else h, k) for h, k in buf_t]
    else:
        buf_t = net_t if buf["Y"].shape[1] == len(net_t) else None
    return net_t, buf_t


def adopt_targets(obj, name, net_t, buf_t):
    """True when the saved net and buffer predict TARGETS or a prefix of them:
    the buffer grows masked columns (no history for the new outcomes) and the
    nets grow zero-weighted outputs, so nothing learned is lost. False for any
    other change; the caller starts over and says so."""
    if buf_t is None or TARGETS[:len(net_t)] != net_t or TARGETS[:len(buf_t)] != buf_t:
        return False
    n = len(TARGETS) - len(buf_t)
    if n:
        obj.Y = np.concatenate([obj.Y, np.zeros((len(obj.Y), n), dtype=obj.Y.dtype)], 1)
        obj.M = np.concatenate([obj.M, np.zeros((len(obj.M), n), dtype=obj.M.dtype)], 1)
    if len(net_t) < len(TARGETS) or n:
        print("%s: %d outcomes appended (%s); weights kept, earlier rows masked for them"
              % (name, len(TARGETS) - len(net_t), ",".join("%s:%s" % t for t in TARGETS[len(net_t):])), flush=True)
    return True


def slog(x):
    return math.copysign(math.log1p(abs(x)), x)


def num(v):
    return float(v) if isinstance(v, (int, float)) else 0.0


def featurize(row, state_keys):
    s = [slog(num(row["state"].get(k, 0))) for k in state_keys]
    opts = row["opts"]
    ci = row["chosen"]
    o = opts[ci] if 0 <= ci < len(opts) else {}
    # a forced want (escort, panic, join) was inserted after the net looked and
    # carries a placeholder value: it never sets the field's best, and its own
    # value terms are masked; in game the scored options are never forced
    priced = [x for x in opts if not num(x.get("forced", 0))] or opts
    best = max((num(x.get("value", 0)) for x in priced), default=0.0)
    best_eta = min((num(x.get("eta", 0)) for x in priced), default=0.0)
    forced = bool(num(o.get("forced", 0)))
    x = [1.0 if o.get("kind") == k else 0.0 for k in KINDS]
    x += [0.0 if forced and k in ("value", "gain") else slog(num(o.get(k, 0))) for k in OPT_NUM]
    x += [0.0 if forced else slog(num(o.get("value", 0)) - best),
          slog(num(o.get("eta", 0)) - best_eta), slog(float(len(opts))), 1.0 if forced else 0.0]
    return s, s + x


RAND_P = 0.95      # a chosen option drawn at odds below this was a chance pick
RAND_W_MAX = 20.0  # inverse-odds weight cap


def rand_weight(row):
    """The inverse-odds weight of a decision taken by CHANCE -- the logged odds
    of the chosen option below RAND_P, or a discovery override of the rule --
    else None. On a decision the rule or the net made, the option is a function
    of the state, so FULL minus STATE measures how well the net reads the
    situation, not what the option is worth (the training audit, 2026-10-06)."""
    opts, ci = row.get("opts") or [], row.get("chosen", -1)
    if not (0 <= ci < len(opts)):
        return None
    pc = num(opts[ci].get("p", 1.0))
    if 0.0 < pc < RAND_P:
        return min(1.0 / pc, RAND_W_MAX)
    rule = row.get("rule")
    if row.get("explore") and rule and opts[ci].get("name") not in (None, rule):
        return RAND_W_MAX
    # A builder pick the explorer's random kind multipliers MOVED: the logged
    # value leaves the multiplier (nm) out, so it moved the pick when value x nm
    # tops at the pick and value alone does not.
    if row.get("explore") and rule is None and "nm" in opts[ci]:
        def top(vals):
            return max(range(len(vals)), key=lambda i: vals[i])
        val = [num(o.get("value", 0)) for o in opts]
        moved = [v * max(num(o.get("nm", 1)), 1e-6) for v, o in zip(val, opts)]
        if top(moved) == ci and top(val) != ci:
            return RAND_W_MAX
    return None


def wcorr(a):
    """Weighted correlation of the (pred, real, weight) rows of `a`."""
    w = a[:, 2] / a[:, 2].sum()
    x, y = a[:, 0], a[:, 1]
    mx, my = (w * x).sum(), (w * y).sum()
    vx, vy = (w * (x - mx) ** 2).sum(), (w * (y - my) ** 2).sum()
    if vx <= 0 or vy <= 0:
        return 0.0
    return float((w * (x - mx) * (y - my)).sum() / math.sqrt(vx * vy))


def target_vec(row):
    y, m = [], []
    for h, k in TARGETS:
        if isinstance(h, str):
            v = row["y"].get(k)
        else:
            hv = row["y"].get(h) or row["y"].get(str(h))
            v = None if hv is None else hv.get(k)
        if v is None or (isinstance(v, float) and not math.isfinite(v)):
            y.append(0.0)
            m.append(0.0)
            continue
        v = float(v)
        if k == "lnD":
            v = max(-4.0, min(4.0, v))
        elif k in WASTE:
            v = max(0.0, min(1.0, v))
        elif k in LOGGED:
            v = slog(v)
        y.append(v)
        m.append(1.0)
    return y, m


class Net:
    def __init__(self, n_in, n_out):
        import torch
        self.torch = torch
        self.model = torch.nn.Sequential(
            torch.nn.Linear(n_in, HIDDEN), torch.nn.ReLU(), torch.nn.Dropout(DROPOUT),
            torch.nn.Linear(HIDDEN, HIDDEN), torch.nn.ReLU(), torch.nn.Dropout(DROPOUT),
            torch.nn.Linear(HIDDEN, n_out))
        self.opt = torch.optim.Adam(self.model.parameters(), lr=1e-3, weight_decay=1e-4)
        self.slow = copy.deepcopy(self.model)   # the averaged weights: these predict and export
        self.xm = self.xs = self.ym = self.ys = None
        self.fit_n = 0

    def average(self):
        d = 0.5 ** (1.0 / EMA_HALF)
        with self.torch.no_grad():
            for ps, pf in zip(self.slow.parameters(), self.model.parameters()):
                ps.mul_(d).add_((1.0 - d) * pf)

    def fit_scalers(self, X, Y, M):
        # inputs are log-scaled; the floor stops a feature that never varied in
        # training from exploding the first time it does. A large buffer is
        # sampled: the full pass cost ~1 s a game on the builder's 800k rows.
        if len(X) > SCALER_ROWS:
            k = np.sort(np.random.default_rng(len(X)).choice(len(X), SCALER_ROWS, replace=False))
            X, Y, M = X[k], Y[k], M[k]
        # the buffer is float16/uint8: the statistics are taken in float32
        X, Y, M = X.astype(np.float32), Y.astype(np.float32), M.astype(np.float32)
        self.xm, self.xs = X.mean(0), np.maximum(X.std(0), 0.25)
        w = M.sum(0) + 1e-6
        self.ym = (Y * M).sum(0) / w
        self.ys = np.maximum(np.sqrt((((Y - self.ym) ** 2) * M).sum(0) / w), Y_FLOOR)

    def _x(self, X):
        return self.torch.tensor(np.clip((X - self.xm) / self.xs, -6, 6), dtype=self.torch.float32)

    def predict(self, X):
        self.slow.eval()
        with self.torch.no_grad():
            z = self.slow(self._x(X)).numpy()
        return z * self.ys + self.ym

    def train(self, X, Y, M, batches, lr=None):
        """One Adam step per minibatch (index arrays from `minibatches`, the
        same for both nets). Returns the mean loss."""
        t = self.torch
        if lr is not None:
            for g in self.opt.param_groups:
                g["lr"] = lr
        # Refit only as the buffer grows: one game barely moves the statistics.
        if self.xm is None or len(self.xm) != X.shape[1] or len(X) >= SCALER_GROW * self.fit_n:
            self.fit_scalers(X, Y, M)
            self.fit_n = len(X)
        if not batches:
            return 0.0
        # only the rows the minibatches touch are scaled and copied
        ri, inv = np.unique(np.concatenate(batches), return_inverse=True)
        inv = t.from_numpy(inv.astype(np.int64))
        Xt, Mt = self._x(X[ri]), t.tensor(M[ri], dtype=t.float32)
        Yt = t.tensor((Y[ri].astype(np.float32) - self.ym) / self.ys, dtype=t.float32)
        self.model.train()
        tot, cnt = 0.0, 0
        at = 0
        for b0 in batches:
            b = inv[at:at + len(b0)]
            at += len(b0)
            err = ((self.model(Xt[b]) - Yt[b]) ** 2) * Mt[b]
            loss = err.sum() / (Mt[b].sum() + 1e-6)
            self.opt.zero_grad()
            loss.backward()
            self.opt.step()
            tot += float(loss)
            cnt += 1
        self.model.eval()
        self.average()
        return tot / max(cnt, 1)

    def grow(self, at, n):
        """n new inputs at column `at`, weighted zero: the net predicts exactly
        as before until the new fields earn a weight."""
        t = self.torch
        for m in (self.model, self.slow):
            old = m[0]
            new = t.nn.Linear(old.in_features + n, old.out_features)
            with t.no_grad():
                w = old.weight.data
                new.weight.copy_(t.cat([w[:, :at], t.zeros(w.shape[0], n), w[:, at:]], 1))
                new.bias.copy_(old.bias.data)
            m[0] = new
        self.opt = t.optim.Adam(self.model.parameters(), lr=1e-3, weight_decay=1e-4)
        if self.xm is not None:
            self.xm = np.insert(self.xm, [at] * n, 0.0)
            self.xs = np.insert(self.xs, [at] * n, 1.0)

    def grow_out(self, n):
        """n new outputs after the last, weighted zero: every old output predicts
        exactly as before, and the objective folds them in at zero until trained."""
        if n <= 0:
            return
        t = self.torch
        for m in (self.model, self.slow):
            old = m[-1]
            new = t.nn.Linear(old.in_features, old.out_features + n)
            with t.no_grad():
                new.weight.copy_(t.cat([old.weight.data, t.zeros(n, old.in_features)], 0))
                new.bias.copy_(t.cat([old.bias.data, t.zeros(n)]))
            m[len(m) - 1] = new
        self.opt = t.optim.Adam(self.model.parameters(), lr=1e-3, weight_decay=1e-4)
        if self.ym is not None:
            self.ym = np.concatenate([self.ym, np.zeros(n, dtype=self.ym.dtype)])
            self.ys = np.concatenate([self.ys, np.ones(n, dtype=self.ys.dtype)])
        self.fit_n = 0   # refit the target scalers at the next batch

    def shrink_perturb(self):
        t = self.torch
        fresh = Net(self.model[0].in_features, self.model[-1].out_features).model
        with t.no_grad():
            for p, q in zip(self.model.parameters(), fresh.parameters()):
                p.mul_(0.8).add_(0.2 * q)

    def state(self):
        return {"model": self.model.state_dict(), "slow": self.slow.state_dict(), "opt": self.opt.state_dict(),
                "xm": self.xm, "xs": self.xs, "ym": self.ym, "ys": self.ys}

    def load(self, st):
        self.model.load_state_dict(st["model"])
        self.slow.load_state_dict(st.get("slow", st["model"]))
        self.opt.load_state_dict(st["opt"])
        self.xm, self.xs, self.ym, self.ys = st["xm"], st["xs"], st["ym"], st["ys"]


def minibatches(n, new_from, ver=None, vw=None, recent_from=0, rng=None):
    """The minibatches one incoming batch (rows new_from..n) trains on, as row
    index arrays: STEPS_PER_GAME of them (more for a batch too big to see each
    new row STEPS_PER_ROW times), each MB_NEW new rows round-robin plus replay
    -- half by recency, half spread over everything by script version (`ver`
    the rows' version ids, `vw` their weights). Under a freeze half the spread
    half comes from the rows since it."""
    rng = rng or np.random.default_rng()
    n_new = n - new_from
    if n_new <= 0:
        return []
    k_new = min(MB_NEW, n_new)
    steps = max(STEPS_PER_GAME, -(-STEPS_PER_ROW * n_new // k_new))
    reps = -(-steps * k_new // n_new)
    new = (np.concatenate([rng.permutation(n_new) for _ in range(reps)])[:steps * k_new] + new_from).reshape(steps, k_new)
    if new_from <= 0:
        return list(new)
    k_old = MB - k_new
    tot = steps * k_old
    n_rec = tot // 2
    tau = max(REPLAY_TAU_MIN, REPLAY_TAU * new_from)
    rec = new_from - 1 - (np.floor(rng.exponential(tau, n_rec)).astype(np.int64) % new_from)
    n_sp = tot - n_rec
    parts = [rec]
    lean = 0 < recent_from < new_from
    for lo, k in (((recent_from, n_sp // 2), (0, n_sp - n_sp // 2)) if lean else ((0, n_sp),)):
        cand = rng.integers(lo, new_from, 4 * k)
        if ver is not None and vw is not None and len(vw):
            cand = cand[rng.random(len(cand)) < vw[np.clip(ver[cand], 0, len(vw) - 1)]]
        if len(cand) < k:
            cand = np.concatenate([cand, rng.integers(lo, new_from, k - len(cand))])
        parts.append(cand[:k])
    old = np.concatenate(parts)
    rng.shuffle(old)
    old = old.reshape(steps, k_old)
    return [np.concatenate([a, b]) for a, b in zip(new, old)]


def regime_keep(T):
    """The per-regime cap: the newest REGIME_KEEP rows of each regime, or None
    when nothing goes."""
    ids, cnt = np.unique(T[:, 1], return_counts=True)
    over = ids[cnt > REGIME_KEEP]
    if not len(over):
        return None
    keep = np.ones(len(T), bool)
    for r in over:
        rows = np.flatnonzero(T[:, 1] == r)
        keep[rows[:len(rows) - REGIME_KEEP]] = False
    return keep


class Buffered:
    """A net's training rows: XF (float16; XS is its first `ns` columns), Y
    (float16), M (uint8) and T (int32: script version id, regime id, batch),
    held in RAM and appended to runtime/nn/shards/<STORE>/ on each save."""
    STORE = "builder"
    LEGACY = "buffer.npz"   # the pre-shard file, migrated once

    def buf_clear(self):
        self.XF = self.Y = self.M = self.T = None
        self.ns = 0
        self.saved_rows = 0
        self.dropped = 0
        self.tables = {"ver": [], "regime": []}
        self.reset_rows = 0

    @property
    def XS(self):
        return None if self.XF is None else self.XF[:, :self.ns]

    def store(self):
        # "<net>_rows": a bare "con" is a reserved device name on Windows
        root = OUT / "shards" / (self.STORE + "_rows")
        if getattr(self, "_store", None) is None or self._store.root != root:
            self._store = nnstore.Store(root)
        return self._store

    def buf_load(self):
        """The index of the saved buffer (migrating a legacy .npz once), its
        rows in RAM; None when there is none."""
        st = self.store()
        legacy = OUT / self.LEGACY
        if not st.exists() and legacy.is_file():
            migrate_legacy(self, legacy)
        if not st.exists():
            return None
        XF, Y, M, T, idx = st.load(keep=regime_keep)
        self.dropped = st.rows() - len(XF)
        if self.dropped:
            print("%s: %d rows over the per-regime cap left out (on disk until --compact)"
                  % (self.STORE, self.dropped), flush=True)
        for j, name in enumerate(idx.get("targets", [])[:Y.shape[1]]):
            if name.split(":", 1)[-1] in WASTE:
                np.clip(Y[:, j], 0.0, 1.0, out=Y[:, j])
        self.XF, self.Y, self.M, self.T = XF, Y, M, T
        self.ns = int(idx["ns"])
        self.saved_rows = len(XF)
        self.tables = {k: list(v) for k, v in idx.get("tables", {}).items()}
        self.tables.setdefault("ver", [])
        self.tables.setdefault("regime", [])
        return idx

    def tag_id(self, kind, name):
        tab = self.tables.setdefault(kind, [])
        if name not in tab:
            tab.append(name)
        return tab.index(name)

    def tags_for(self, g, teams, batch):
        """Per row: [script version id, regime id, batch] of its game and team."""
        reg = self.tag_id("regime", g.get("regime") or nnstore.UNKNOWN)
        vers = g.get("versions") or {}
        return np.array([[self.tag_id("ver", vers.get(t, nnstore.OLD_VER)), reg, batch] for t in teams],
                        dtype=np.int32).reshape(len(teams), 3)

    def ver_weights(self):
        """Replay weight per version id: the newest version 1, halving every
        VER_HALF versions back (by the date in the stamp, else first seen),
        never below VER_FLOOR; untagged rows OLD_VER_W."""
        import re
        tab = self.tables.get("ver", [])
        dated = sorted(((re.search(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}", v) or [""])[0], i)
                       for i, v in enumerate(tab) if v != nnstore.OLD_VER)
        w = np.full(len(tab), OLD_VER_W, dtype=np.float32)
        for rank, (_d, i) in enumerate(reversed(dated)):
            w[i] = max(VER_FLOOR, 0.5 ** (rank / VER_HALF))
        return w

    def buf_add(self, XF, Y, M, T):
        """New rows, stored at the buffer's precision. Returns the first new row's index."""
        XF, Y, M, T = nnstore.f16(XF), nnstore.f16(Y), M.astype(np.uint8), T.astype(np.int32)
        if self.XF is None:
            self.XF, self.Y, self.M, self.T = XF, Y, M, T
            return 0
        n0 = len(self.Y)
        append_rows(self, XF, Y, M, T)
        return n0

    def buf_meta(self):
        return {"k": len(self.state_keys or []), "ns": int(self.ns), "state_keys": list(self.state_keys or []),
                "post_keys": list(getattr(self, "post_keys", None) or []), "batches": int(self.batches),
                "targets": [str(t) for t in TARGET_NAMES], "tables": self.tables}

    def buf_save(self):
        """Append the rows not yet on disk; the index carries everything else."""
        if self.XF is None:
            return
        n, s = len(self.Y), self.saved_rows
        self.store().append(self.XF[s:n], self.Y[s:n], self.M[s:n], self.T[s:n], self.buf_meta())
        self.saved_rows = n

    def buf_archive(self, dest):
        self.store().archive(dest / (self.STORE + "_rows"))
        self._store = None


def migrate_legacy(obj, legacy):
    """A legacy <name>buffer.npz into shards, streaming; its rows tagged from
    metrics.jsonl where the batch records line up with them. The .npz is
    renamed *.npz.migrated, never deleted."""
    import zipfile
    with zipfile.ZipFile(legacy) as zf:
        fh, shape, _dt = nnstore._npy_member(zf, "Y")
        fh.close()
    n = int(shape[0])
    print("%s: migrating %s (%d rows) to %s" % (obj.STORE, legacy.name, n, obj.store().root), flush=True)
    tags, tables = legacy_tags(obj.STORE, n)
    nnstore.migrate(legacy, obj.store(), tags=tags, tables=tables, log=lambda s: print(s, flush=True))
    replace_retry(legacy, legacy.with_name(legacy.name + ".migrated"))


_RESOLVER = None


def _table_id(tab, name):
    if name not in tab:
        tab.append(name)
    return tab.index(name)


def legacy_tags(net, n):
    """(tags, tables) for a legacy buffer's n rows, from metrics.jsonl: every
    batch record names its source and the buffer's size after it, so walking
    back from the newest record gives each row its game. Rows before a break in
    the sizes (a reset, a record without them) stay unknown / old."""
    tags = np.zeros((n, 3), np.int32)
    tags[:, 2] = -1
    tables = {"ver": [nnstore.OLD_VER], "regime": [nnstore.UNKNOWN]}
    recs = []
    try:
        with open(OUT / "metrics.jsonl", encoding="utf-8") as fh:
            for ln in fh:
                mine = ('"net": "%s"' % net) in ln if net != "builder" else '"net":' not in ln
                if not mine:
                    continue
                try:
                    r = json.loads(ln)
                except ValueError:
                    continue
                if "total_rows" in r and "source" in r and "rows" in r:
                    added = int(r["rows"]) * (HUMAN_W if HUMAN_TAG in str(r["source"]) else 1)
                    recs.append((r["source"], int(r["total_rows"]), int(r.get("index", -1)), float(r.get("at", 0)), added))
    except OSError:
        return tags, tables
    global _RESOLVER
    if _RESOLVER is None:
        _RESOLVER = SourceResolver()   # shared by every net's migration: each game is read once
    res = _RESOLVER
    import bisect
    # The .npz was saved every few batches, so a restart reloaded it short and
    # the batches after its last save were lost: the record before the rows of
    # record i is the newest EARLIER one whose size is where i's rows start.
    at_size = {}
    for i, r in enumerate(recs):
        at_size.setdefault(r[1], []).append(i)
    end = n
    cand = at_size.get(n, [])
    i = cand[-1] if cand else -1
    while i >= 0:
        src, total, batch, at, added = recs[i]
        start = end - added
        if start < 0:
            break
        regime, ver = res.of(src, at)
        tags[start:end, 0] = _table_id(tables["ver"], ver)
        tags[start:end, 1] = _table_id(tables["regime"], regime)
        tags[start:end, 2] = batch
        end = start
        cand = at_size.get(end, [])
        k = bisect.bisect_left(cand, i) - 1
        i = cand[k] if end > 0 and k >= 0 else -1
    print("%s: %d of %d rows tagged from metrics.jsonl (%d regimes, %d versions)"
          % (net, n - end, n, len(tables["regime"]), len(tables["ver"])), flush=True)
    return tags, tables


class SourceResolver:
    """A batch record's source -> (regime, script version). A finished match
    dir is read directly; a live write dir ('live:engine-w5-30024') is the
    finished match that ran in it at the time: the first to finish after the
    batch, among the matches whose infolog names that write dir."""
    LIVE_SPAN_S = 3 * 3600   # a match finishing later than this after the batch is not its game

    def __init__(self):
        self.cache = {}
        self.by_wd = None

    def of(self, src, at=0.0):
        if src.startswith("live:"):
            d = self._live(src[5:], at)
            return self._match(d) if d is not None else (nnstore.UNKNOWN, nnstore.OLD_VER)
        return self._match(REPO / src)

    BANNER_SINCE = 1791443040   # 2026-10-08 07:04 UTC: no game before carries the version banner

    def _match(self, d):
        key = str(d)
        if key not in self.cache:
            regime, ver = decisions.script_regime(key) or nnstore.UNKNOWN, nnstore.OLD_VER
            try:
                if (d / "infolog.txt").stat().st_mtime >= self.BANNER_SINCE:
                    # the banner is logged at frame 30, ~250 KB in
                    with open(d / "infolog.txt", encoding="utf-8", errors="replace") as fh:
                        head = fh.read(2 << 20)
                    at = head.find("apex: version t=")
                    m = decisions.VERSION.search(head[at:head.find("\n", at)]) if at >= 0 else None
                    if m:
                        ver = m.group(2)
            except OSError:
                pass
            self.cache[key] = (regime, ver)
        return self.cache[key]

    def _live(self, wd, at):
        import bisect
        import re
        if self.by_wd is None:
            self.by_wd = {}
            tours, matches = FINISHED
            for d in [m for t in fresh(tours) for m in fresh(t / "matches")] + fresh(matches):
                try:
                    with open(d / "infolog.txt", encoding="utf-8", errors="replace") as fh:
                        head = fh.read(4096)
                    end = (d / "result.json").stat().st_mtime
                except OSError:
                    continue
                m = re.search(r"[/\\](engine-w[\w-]+|_engine[\w-]*)[/\\\"]", head)
                if m:
                    self.by_wd.setdefault(m.group(1), []).append((end, str(d)))
            for v in self.by_wd.values():
                v.sort()
        runs = self.by_wd.get(wd, [])
        i = bisect.bisect_left(runs, (at, ""))
        if i < len(runs) and runs[i][0] - at <= self.LIVE_SPAN_S:
            return Path(runs[i][1])
        return None


# TRUST, kind 3 (docs/35). On a game's first, unseen batch, each CHANCE
# row (rand_weight) scores d = FULL(chosen) - FULL(rule) against the realized
# a = outcome - FULL(rule), both in OBJECTIVE units, weighted 1/p; trust is the
# lower end of a game-clustered bootstrap interval of the SLOPE of a on d (the
# share of the net's claimed gain that is real), in [0, 1]. Kind 2 used their
# correlation, which outcome noise (sd(a) 10-20x sd(d)) capped near 0.1 for a
# perfect net. The PLACEBO is the same statistic on rule-following rows with
# an option NOT taken in place of the chosen one: it must read ~0.
TRUST_KIND = 3
TRUST_BOOT = 200        # bootstrap resamples (by game)
TRUST_LO_Q = 2.5        # percentile taken as the interval's lower end
TRUST_GAMES_MIN = 5     # fewer games than this: no say
PLACEBO_PER_BATCH = 64  # rule-following rows scored per batch for the placebo


def obj_units(p, ym, ys, mm):
    """Rows of predictions or outcomes in OBJECTIVE units over each row's
    labelled targets (mm: the row's mask times the objective's weights)."""
    return (((p - ym) / ys) * mm).sum(1)


def boot_corr(d, a, w, gid, b=None, seed=0, slope=False):
    """(point, lower bound) of the weighted correlation of d and a -- partial
    on b when given (d and a both carry -FULL(rule), which alone made them
    correlate) -- resampling whole games; with slope, of a's regression slope
    on d (b held fixed) instead. None when there is too little to say."""
    games, g = np.unique(np.asarray(gid), return_inverse=True)
    if len(d) < TRUST_MIN or len(games) < TRUST_GAMES_MIN:
        return None
    rng = np.random.default_rng(seed)
    cnt = rng.multinomial(len(games), np.full(len(games), 1.0 / len(games)), size=TRUST_BOOT)
    W = np.vstack([w[None, :], cnt[:, g] * w[None, :]]).astype(np.float64)
    W /= np.maximum(W.sum(1, keepdims=True), 1e-12)

    def cov(x, y):
        mx, my = W @ x, W @ y
        return (W * (x[None, :] - mx[:, None]) * (y[None, :] - my[:, None])).sum(1)

    def corr(c, vx, vy):
        return np.where((vx > 1e-24) & (vy > 1e-24), c / np.sqrt(np.maximum(vx * vy, 1e-24)), 0.0)

    vd, va = cov(d, d), cov(a, a)
    if slope:
        cda = cov(d, a)
        if b is None:
            r = np.where(vd > 1e-24, cda / np.maximum(vd, 1e-24), 0.0)
        else:
            vb, cdb, cab = cov(b, b), cov(d, b), cov(a, b)
            det = vd * vb - cdb ** 2
            r = np.where(det > 1e-24, (cda * vb - cab * cdb) / np.maximum(det, 1e-24), 0.0)
        return float(r[0]), float(np.percentile(r[1:], TRUST_LO_Q))
    r = corr(cov(d, a), vd, va)
    if b is not None:
        vb = cov(b, b)
        rdb, rab = corr(cov(d, b), vd, vb), corr(cov(a, b), va, vb)
        den = np.sqrt(np.maximum((1 - rdb ** 2) * (1 - rab ** 2), 1e-12))
        r = np.where(den > 1e-6, (r - rdb * rab) / den, 0.0)
    return float(r[0]), float(np.percentile(r[1:], TRUST_LO_Q))


def honest_trust(pairs, placebo=None):
    """Trust from (d, a, w, game, FULL(rule)) pairs: the bootstrap lower bound
    less what the same statistic reads where the decision cannot matter (the
    placebo's point value, when positive), >= 0."""
    q = [x for x in pairs if len(x) == 5][-TRUST_RECENT:]
    if len(q) < TRUST_MIN:
        return 0.0
    d, a, w, b = (np.array([x[i] for x in q], dtype=np.float64) for i in (0, 1, 2, 4))
    res = boot_corr(d, a, w, [x[3] for x in q], b, seed=len(q), slope=True)
    bias = max(0.0, (placebo or {}).get("r", 0.0))
    return 0.0 if res is None else round(min(1.0, max(0.0, res[1] - bias)), 3)


def placebo_read(pairs, partial=True):
    """{r, lo, n} of placebo pairs (d, a, game[, FULL(rule)]), for metrics.jsonl."""
    q = pairs[-TRUST_RECENT:]
    if not q:
        return None
    d, a = (np.array([x[i] for x in q], dtype=np.float64) for i in range(2))
    b = np.array([x[3] for x in q], dtype=np.float64) if partial and len(q[0]) > 3 else None
    res = boot_corr(d, a, np.ones(len(q)), [x[2] for x in q], b, seed=len(q), slope=True)
    return {"n": len(q)} if res is None else {"r": round(res[0], 3), "lo": round(res[1], 3), "n": len(q)}


def rule_of_list(row):
    """The option the market would take without chance: the top value among
    options that were priced (a forced want carries a placeholder value)."""
    opts = row.get("opts") or []
    best, bi = None, None
    for i, o in enumerate(opts):
        if num(o.get("forced", 0)):
            continue
        v = num(o.get("value", 0))
        if best is None or v > best:
            best, bi = v, i
    return bi


def alts_of_list(row, rule):
    return [i for i, o in enumerate(row.get("opts") or []) if i != rule and not num(o.get("forced", 0))]


def decision_pairs(rows, feat, rule_of, alts_of, net, XF, Y, M, rw, gid, rng):
    """Held-out decision evidence of one batch, predicted before training on
    it: ([(row, d, a, w, game)] for chance rows, [(row, d, a, game)] for the
    placebo, the rows' objective weights). `feat(row, i)` is the row's FULL
    input with option i chosen; `rule_of` / `alts_of` name the rule's option
    and the others a placebo may stand in."""
    w_obj = np.array([OBJECTIVE.get(t, 0.0) for t in TARGETS])
    ym, ys = net.ym, net.ys
    mm = M * (w_obj != 0) * w_obj
    chance, plac = [], []
    for i, r in enumerate(rows):
        rule = rule_of(r)
        if rule is None or not mm[i].any():
            continue
        if rw[i] is not None:
            chance.append((i, rule))
        elif r.get("chosen") == rule:
            alts = alts_of(r, rule)
            if alts:
                plac.append((i, rule, alts[int(rng.integers(len(alts)))]))
    if len(plac) > PLACEBO_PER_BATCH:
        plac = [plac[k] for k in sorted(rng.choice(len(plac), PLACEBO_PER_BATCH, replace=False))]
    out_c, out_p = [], []
    if chance:
        idx = [i for i, _ in chance]
        pr = net.predict(np.array([feat(rows[i], rule) for i, rule in chance], dtype=np.float32))
        pc = net.predict(XF[idx])
        b = obj_units(pr, ym, ys, mm[idx])
        d = obj_units(pc, ym, ys, mm[idx]) - b
        a = obj_units(Y[idx], ym, ys, mm[idx]) - b
        out_c = [(i, float(dd), float(aa), float(rw[i]), gid, float(bb)) for i, dd, aa, bb in zip(idx, d, a, b)]
    if plac:
        idx = [i for i, _, _ in plac]
        pa = net.predict(np.array([feat(rows[i], alt) for i, _, alt in plac], dtype=np.float32))
        pr = net.predict(XF[idx])   # chosen IS the rule here
        b = obj_units(pr, ym, ys, mm[idx])
        d = obj_units(pa, ym, ys, mm[idx]) - b
        a = obj_units(Y[idx], ym, ys, mm[idx]) - b
        out_p = [(i, float(dd), float(aa), gid, float(bb)) for i, dd, aa, bb in zip(idx, d, a, b)]
    return out_c, out_p, mm


def score_decisions(obj, rows, XF, Y, M, rw, pf, ps, gid, pairs_for, feat, rule_of, alts_of, rec):
    """A first-touch batch's decision evidence into obj's trust pairs (where
    `pairs_for(row index)` says) and its placebo lists; the readings into rec."""
    rng = np.random.default_rng(len(rows) * 7919 + obj.batches)
    chance, plac, mm = decision_pairs(rows, feat, rule_of, alts_of, obj.full, XF, Y, M, rw, gid, rng)
    for i, d, a, w, g, b in chance:
        q = pairs_for(i)
        q.append((d, a, w, g, b))
        if len(q) > TRUST_KEEP:
            del q[: len(q) - TRUST_KEEP]
    ym, ys = obj.full.ym, obj.full.ys
    for i, d, a, g, b in plac:
        obj.placebo.append((d, a, g, b))
        # the old statistic on the same rows: FULL minus STATE against outcome minus STATE
        o = lambda p: float(obj_units(p[i:i + 1], ym, ys, mm[i:i + 1])[0])
        obj.placebo_old.append((o(pf) - o(ps), o(Y) - o(ps), g))
    obj.placebo = obj.placebo[-TRUST_KEEP:]
    obj.placebo_old = obj.placebo_old[-TRUST_KEEP:]
    rec["chance_rows"] = len(chance)
    rec["placebo"] = placebo_of(obj)
    if obj.batches % 10 == 0:   # the comparisons: each is a bootstrap
        rec["placebo_old"] = placebo_read(obj.placebo_old, partial=False)
        rec["placebo_raw"] = placebo_read(obj.placebo, partial=False)   # without the partial on FULL(rule)


def placebo_of(obj):
    """placebo_read(obj.placebo), recomputed only when it has new pairs."""
    key = (len(obj.placebo), obj.placebo[-1][:2] if obj.placebo else None)
    if getattr(obj, "_placebo_memo", (None,))[0] != key:
        obj._placebo_memo = (key, placebo_read(obj.placebo))
    return obj._placebo_memo[1]


def r2(pred, y, m, base):
    out = []
    for j in range(y.shape[1]):
        k = m[:, j] > 0
        if k.sum() < 5:
            out.append(None)
            continue
        sse = float(((pred[k, j] - y[k, j]) ** 2).sum())
        sst = float(((base[j] - y[k, j]) ** 2).sum())
        out.append(None if sst <= 0 else 1.0 - sse / sst)
    return out


def game_sums(pf, ps, y, m, base):
    """Per game-level outcome [SSE full, SSE state, SST, n] of one batch: summed
    over many batches they give the R2 a single game's batch cannot."""
    out = {}
    for name in GAME_LEVEL:
        j = TARGETS.index((name, name))
        k = m[:, j] > 0
        if k.any():
            out[name] = [float(((pf[k, j] - y[k, j]) ** 2).sum()), float(((ps[k, j] - y[k, j]) ** 2).sum()),
                         float(((base[j] - y[k, j]) ** 2).sum()), int(k.sum())]
    return out


def mean_of(vals, idx):
    v = [vals[i] for i in idx if vals[i] is not None]
    return sum(v) / len(v) if v else None


def fmt_arr(vals):
    return "{" + ", ".join("%.7ff" % float(v) for v in vals) + "}"


def fold(net):
    """First layer, second layer, and the output layer folded through OBJECTIVE
    into one score (in units of target spread)."""
    sd = net.slow.state_dict()
    w1, b1 = sd["0.weight"].numpy(), sd["0.bias"].numpy()
    w2, b2 = sd["3.weight"].numpy(), sd["3.bias"].numpy()
    w3, b3 = sd["6.weight"].numpy(), sd["6.bias"].numpy()
    obj = np.array([OBJECTIVE.get(t, 0.0) for t in TARGETS])
    return w1, b1, w2, b2, obj @ w3, float(obj @ b3)


def head_block(head, p, layout=None):
    """A head's <p>_* fields (NNF factory, NNP posture); the empty net until the
    head has one. `layout` is the string the game compares before trusting it."""
    if head is None or head.full is None:
        return ["const bool %s_ON = false;" % p, 'const string %s_STATE = "";' % p,
                "const int %s_S = 0;" % p, "const int %s_O = 0;" % p, "const int %s_H = 0;" % p] + \
               ["const array<float> %s_%s = {};" % (p, k) for k in ("XM", "XS", "W1", "B1", "W2", "B2", "WO")] + \
               ["const float %s_BO = 0.f;" % p, "const float %s_TRUST = 0.f;" % p]
    w1, b1, w2, b2, wo, bo = fold(head.full)
    n_state = head.ns   # what NnPostScore/NnFacScore feed once per decision
    return ["const bool %s_ON = true;" % p,
            'const string %s_STATE = "%s";' % (p, layout or ",".join(head.state_keys)),
            "const int %s_S = %d;" % (p, n_state), "const int %s_O = %d;" % (p, w1.shape[1] - n_state),
            "const int %s_H = %d;" % (p, HIDDEN),
            "const array<float> %s_XM = %s;" % (p, fmt_arr(head.full.xm)),
            "const array<float> %s_XS = %s;" % (p, fmt_arr(head.full.xs)),
            "const array<float> %s_W1 = %s;" % (p, fmt_arr(w1.reshape(-1))),
            "const array<float> %s_B1 = %s;" % (p, fmt_arr(b1)),
            "const array<float> %s_W2 = %s;" % (p, fmt_arr(w2.reshape(-1))),
            "const array<float> %s_B2 = %s;" % (p, fmt_arr(b2)),
            "const array<float> %s_WO = %s;" % (p, fmt_arr(wo)),
            "const float %s_BO = %.7ff;" % (p, bo),
            "const float %s_TRUST = %.7ff;" % (p, head.trust())]


def fac_block(head):
    return head_block(head, "NNF")


def imit_block():
    """The BARb prior trained by tools/imitate.py (runtime/nn/imitate.npz) as NNI_*."""
    p = OUT / "imitate.npz"
    names = ("XM", "XS", "W1", "B1", "W2", "B2", "W3", "B3")
    if not p.is_file():
        return ["const bool NNI_ON = false;", 'const string NNI_FEATURES = "";', 'const string NNI_CLASSES = "";',
                "const int NNI_F = 0;", "const int NNI_C = 0;", "const int NNI_H = 0;"] + \
               ["const array<float> NNI_%s = {};" % k for k in names]
    with np.load(p, allow_pickle=True) as z:
        w = {k: z[k] for k in z.files}
    keys = {"XM": "xm", "XS": "xs", "W1": "w1", "B1": "b1", "W2": "w2", "B2": "b2", "W3": "w3", "B3": "b3"}
    return ["const bool NNI_ON = true;",
            'const string NNI_FEATURES = "%s";' % ",".join(str(f) for f in w["features"]),
            'const string NNI_CLASSES = "%s";' % ",".join(str(c) for c in w["classes"]),
            "const int NNI_F = %d;" % len(w["features"]), "const int NNI_C = %d;" % len(w["classes"]),
            "const int NNI_H = %d;" % w["w1"].shape[0]] + \
           ["const array<float> NNI_%s = %s;" % (k, fmt_arr(np.asarray(w[keys[k]]).reshape(-1))) for k in names]


def post_block(head, p="NNP"):
    # the posture fields are known only once a posture game was read since start
    if head is None or head.full is None or not head.post_keys:
        return head_block(None, p)
    return head_block(head, p, ",".join(head.state_keys) + "|" + ",".join(head.post_keys))


def val_block(head, p):
    """A continuous head's fields: post_block's, plus the value range it was
    trained on (<p>_LO / <p>_HI; the game sweeps only inside it)."""
    lo, hi = (0.0, 0.0)
    if head is not None and head.full is not None and head.post_keys and head.vrange:
        lo, hi = head.vrange
    return post_block(head, p) + ["const float %s_LO = %.7ff;" % (p, lo), "const float %s_HI = %.7ff;" % (p, hi)]


NNW_EMPTY = ["const bool NNW_ON = false;", "const int NNW_GAMES = 0;", 'const string NNW_STATE = "";',
             "const array<string> NNW_KINDS = {};", "const int NNW_S = 0;", "const int NNW_O = 0;",
             "const int NNW_H = 0;"] + \
            ["const array<float> NNW_%s = {};" % k for k in ("XM", "XS", "W1", "B1", "W2", "B2", "WO")] + \
            ["const float NNW_BO = 0.f;", "const array<float> NNW_TRUST = {};"]


def export_as(net, state_keys, games, trust, fac=None, post=None, heads=None):
    """Every net as nnweights.as: builder (NNW_*), factory (NNF_*), posture
    (NNP_*) and the BARb prior (NNI_*); a net not trained yet is the empty one."""
    tail = (["// the factory net (production.as roulette)"] + fac_block(fac) +
            ["// the static defence amount net (protect_nn.as)"] + val_block((heads or {}).get("defamt"), "NND") +
            ["// the static defence site net (protect_nn.as)"] + post_block((heads or {}).get("defsite"), "NNU") +
            ["// the static defence gun-class net (protect_nntype.as)"] + post_block((heads or {}).get("deftype"), "NNN") +
            ["// the opening order net (opennet.as)"] + post_block((heads or {}).get("open"), "NNOP") +
            ["// the posture net (military/nnpost.as)"] + post_block(post) +
            ["// the commander net (comdecide.as)"] + post_block((heads or {}).get("com"), "NNC") +
            ["// the T2 net (nntech.as)"] + post_block((heads or {}).get("tech"), "NNT") +
            ["// the raid net (military/nnraid.as)"] + post_block((heads or {}).get("raid"), "NNR") +
            ["// the air-strike net (air/)"] + post_block((heads or {}).get("air"), "NNA") +
            ["// the escort net (escnet.as)"] + val_block((heads or {}).get("esc"), "NNE") +
            ["// the constructor-floor net (econet.as)"] + val_block((heads or {}).get("con"), "NNK") +
            ["// the expansion net (econet.as)"] + val_block((heads or {}).get("mex"), "NNX") +
            ["// the ground constructor-cap net (econet.as)"] + val_block((heads or {}).get("cap"), "NNQ") +
            ["// the air constructor-cap net (econet.as)"] + val_block((heads or {}).get("acap"), "NNZ") +
            ["// the team plan net (plannet.as)"] + post_block((heads or {}).get("plan"), "NNG") +
            ["// the join-or-new net (joinnet.as)"] + post_block((heads or {}).get("join"), "NNJ") +
            ["// the air plant count net (plannet.as)"] + val_block((heads or {}).get("aplant"), "NNL") +
            ["// the join-the-fight net (military/joinfight.as)"] + post_block((heads or {}).get("reinf"), "NNV") +
            ["// the hunt-their-army net (military/nnhunt.as)"] + post_block((heads or {}).get("hunt"), "NNH") +
            ["// the scout-cap net (econet.as)"] + val_block((heads or {}).get("scap"), "NNS") +
            ["// the escort-cap net (escnet.as)"] + val_block((heads or {}).get("ecap"), "NNY") +
            ["// the timing-window strike net (military/nnstrike.as)"] + post_block((heads or {}).get("strike"), "NNB") +
            ["// the pool-size net (military/nnmassodds.as)"] + val_block((heads or {}).get("mass"), "NNM") +
            ["// the squad-odds net (military/nnmassodds.as)"] + val_block((heads or {}).get("odds"), "NNO") +
            ["// the mex-guard net (protect_nn.as)"] + val_block((heads or {}).get("mexg"), "NNMG") +
            ["// the BARb prior (tools/imitate.py)"] + imit_block() + ["", "}  // namespace Market", ""])
    head = ["namespace Market {", "", "// GENERATED by tools/nntrain.py -- the deployed copy only; do not commit.",
            "// which trust every *_TRUST below is: 2 = the decision's held-out advantage test",
            "const int NN_TRUST_KIND = %d;" % TRUST_KIND]
    if net is None:
        return "\n".join(head + NNW_EMPTY + tail)
    w1, b1, w2, b2, wo, bo = fold(net)
    s, o = len(state_keys), w1.shape[1] - len(state_keys)
    return "\n".join(head + [
        "const bool NNW_ON = true;",
        "const int NNW_GAMES = %d;" % games,
        'const string NNW_STATE = "%s";' % ",".join(state_keys),
        "const array<string> NNW_KINDS = {%s};" % ", ".join('"%s"' % k for k in KINDS),
        "const int NNW_S = %d;" % s, "const int NNW_O = %d;" % o, "const int NNW_H = %d;" % HIDDEN,
        "const array<float> NNW_XM = %s;" % fmt_arr(net.xm),
        "const array<float> NNW_XS = %s;" % fmt_arr(net.xs),
        "const array<float> NNW_W1 = %s;" % fmt_arr(w1.reshape(-1)),
        "const array<float> NNW_B1 = %s;" % fmt_arr(b1),
        "const array<float> NNW_W2 = %s;" % fmt_arr(w2.reshape(-1)),
        "const array<float> NNW_B2 = %s;" % fmt_arr(b2),
        "const array<float> NNW_WO = %s;" % fmt_arr(wo),
        "const float NNW_BO = %.7ff;" % bo,
        "// per kind, in NNW_KINDS order: how much say the net gets (0 = the market alone)",
        "const array<float> NNW_TRUST = %s;" % fmt_arr([trust.get(k, 0.0) for k in KINDS])] + tail)


def export_targets():
    p = OUT / "targets.json"
    names = json.loads(p.read_text()) if p.is_file() else ["Apexnnlog:lane-nnlog"]
    env = bar_env.load()
    rel = Path("script/standard/manager/brain/market/nnweights.as")
    out = []
    for name in names:
        short, ver = name.split(":", 1)
        for root in (env.skirmish_dir(short, ver), env.game_config_dir(short, ver)):
            if (root / rel).parent.is_dir():
                out.append(root / rel)
    return out


FAC_OPT_NUM = ("value", "gain", "cm", "ce", "bt", "tierO", "ownN", "hp", "speed", "range",
               "power", "fly", "bld", "rez", "bp", "radarR")   # nnlog.as NnFacOpt order
FAC_SCHEMA_OPT = "radarR"                # an option field only the v3 factory record carries


def featurize_fac(row, state_keys):
    """In NnFacScore's order: state, the unit's numbers, value - best, n."""
    s = [slog(num(row["state"].get(k, 0))) for k in state_keys]
    opts = row["opts"]
    ci = row["chosen"]
    o = opts[ci] if 0 <= ci < len(opts) else {}
    best = max((num(x.get("value", 0)) for x in opts), default=0.0)
    x = [slog(num(o.get(k, 0))) for k in FAC_OPT_NUM]
    x += [slog(num(o.get("value", 0)) - best), slog(float(len(opts)))]
    return s, s + x


class FacHead(Buffered):
    """The factory net: what a production order is worth. Its own nets, buffer
    and ONE trust (how well its view of what an order adds matches what the
    order actually added, on unseen games). PostHead reuses it for posture."""
    NAME = "fac"
    OPTS = FAC_OPT_NUM
    VAL = False
    rand_weight = staticmethod(rand_weight)

    @property
    def STORE(self):
        return self.NAME

    @property
    def LEGACY(self):
        return self.NAME + "_buffer.npz"

    @staticmethod
    def featurize(row, state_keys):
        return featurize_fac(row, state_keys)

    def __init__(self):
        self.state_keys = None
        self.buf_clear()
        self.full = self.st = None
        self.pairs = []
        self.placebo, self.placebo_old = [], []
        self.batches = 0
        self.load()

    @staticmethod
    def rule_of(row):
        return rule_of_list(row)

    @staticmethod
    def alts_of(row, rule):
        return alts_of_list(row, rule)

    def load(self):
        if not (OUT / (self.NAME + "_model.pt")).is_file():
            # rows without their net: the next save would append to them
            if self.store().exists():
                self.buf_archive(OUT.parent / "nn-archive" / time.strftime("%Y%m%d-%H%M%S"))
            return
        idx = self.buf_load()
        if idx is None:
            return
        import torch
        self.state_keys = list(idx["state_keys"])
        self.batches = int(idx.get("batches", 0))
        ck = torch.load(OUT / (self.NAME + "_model.pt"), weights_only=False)
        net_t, buf_t = saved_targets(ck, {"Y": self.Y, "targets": idx.get("targets", [])})
        if tuple(ck.get("opt_num", ())) != self.OPTS or not adopt_targets(self, self.NAME, net_t, buf_t):
            print("%s: saved net predicts other outcomes or reads other options; starting empty" % self.NAME,
                  flush=True)
            self.__init_empty()
            return
        self.full = Net(self.XF.shape[1], len(net_t))
        self.st = Net(self.ns, len(net_t))
        try:
            self.full.load(ck["full"])
            self.st.load(ck["state"])
        except RuntimeError:
            # a kill between the buffer save and the model save
            print("%s: saved net does not fit its buffer (%d columns); starting empty"
                  % (self.NAME, self.XF.shape[1]), flush=True)
            self.__init_empty()
            return
        for net in (self.full, self.st):
            net.grow_out(len(TARGETS) - len(net_t))
        self.pairs = ck.get("pairs", [])   # old (kind 1) 3-tuples are skipped by honest_trust
        self.placebo, self.placebo_old = list(ck.get("placebo", [])), list(ck.get("placebo_old", []))
        self.reset_rows = int(ck.get("reset_rows", 0))
        if ck.get("post_keys") is not None:
            self.post_keys = list(ck["post_keys"])
        if ck.get("range") is not None:
            self.vrange = tuple(ck["range"])

    def __init_empty(self):
        """Learn from nothing: the old buffer moves to nn-archive, never deleted."""
        if self.store().exists():
            self.buf_archive(OUT.parent / "nn-archive" / time.strftime("%Y%m%d-%H%M%S"))
        self.state_keys = None
        self.buf_clear()
        self.full = self.st = None
        self.pairs = []
        self.placebo, self.placebo_old = [], []
        self.batches = 0

    def save(self, buffer=False, force=False):
        import torch
        if self.full is None or not force:
            return
        self.buf_save()
        torch.save({"full": self.full.state(), "state": self.st.state(), "targets": TARGETS,
                    "post_keys": getattr(self, "post_keys", None), "reset_rows": self.reset_rows,
                    "opt_num": self.OPTS, "pairs": self.pairs, "placebo": self.placebo,
                    "placebo_old": self.placebo_old, "range": getattr(self, "vrange", None)},
                   OUT / (self.NAME + "_model.pt.tmp"))
        replace_retry(OUT / (self.NAME + "_model.pt.tmp"), OUT / (self.NAME + "_model.pt"))

    def trust(self):
        key = (len(self.pairs), self.pairs[-1][:2] if self.pairs else None, len(self.placebo),
               self.placebo[-1][:2] if self.placebo else None)
        if getattr(self, "_trust_memo", (None,))[0] != key:
            self._trust_memo = (key, honest_trust(self.pairs, placebo_of(self)))
        return self._trust_memo[1]

    def learn(self, source, g, first_touch, rows):
        if not adopt_keys(self, g["state_keys"]):
            self.__init_empty()
        if self.state_keys is None:
            self.state_keys = g["state_keys"]
        xs, xf, ys, ms, rw, teams, kept = [], [], [], [], [], [], []
        for r in rows:
            y, m = target_vec(r)
            if not any(m):
                continue
            s, f = self.featurize(r, self.state_keys)
            kept.append(r)
            xs.append(s)
            xf.append(f)
            ys.append(y)
            ms.append(m)
            rw.append(self.rand_weight(r))
            teams.append(r["team"])
        if not xs:
            return None
        XS, XF = np.array(xs, dtype=np.float32), np.array(xf, dtype=np.float32)
        Y, M = np.array(ys, dtype=np.float32), np.array(ms, dtype=np.float32)
        rec = {"net": self.NAME, "source": source, "at": time.time(), "rows": len(xs),
               "index": self.batches + 1, "first_touch": first_touch}
        if self.full is not None and first_touch:
            base = self.full.ym
            pf, ps = self.full.predict(XF), self.st.predict(XS)
            rec["head_full"] = mean_of(r2(pf, Y, M, base), HEADLINE)
            rec["head_state"] = mean_of(r2(ps, Y, M, base), HEADLINE)
            rec["game_sums"] = game_sums(pf, ps, Y, M, base)
            score_decisions(self, kept, XF, Y, M, rw, pf, ps, decisions.fingerprint(g) or source,
                            lambda i: self.pairs,
                            lambda r, ci: self.featurize(dict(r, chosen=ci), self.state_keys)[1],
                            self.rule_of, self.alts_of, rec)
            rec["trust"] = self.trust()
        T = self.tags_for(g, teams, self.batches + 1)
        if HUMAN_TAG in str(source):
            XF, Y, M, T = (np.repeat(a, HUMAN_W, axis=0) for a in (XF, Y, M, T))
        if self.XF is None:
            self.ns = XS.shape[1]
            self.full = Net(XF.shape[1], len(TARGETS))
            self.st = Net(self.ns, len(TARGETS))
        new_from = self.buf_add(XF, Y, M, T)
        rec.update(fit_batch(self, new_from))
        with open(OUT / "metrics.jsonl", "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec) + "\n")
        self.save()
        return rec


def fit_batch(obj, new_from):
    """Train obj's FULL and STATE nets on the rows from new_from (just added),
    count them toward the next partial reset; the metrics fields."""
    fz_rows, fz_batch = freeze_note(getattr(obj, "NAME", "builder"), new_from, obj.batches)
    lr = lr_now(obj.batches, fz_batch)
    t0 = time.time()
    bs = minibatches(len(obj.Y), new_from, obj.T[:, 0], obj.ver_weights(), fz_rows)
    out = {"lr": lr, "steps": len(bs),
           "loss_full": obj.full.train(obj.XF, obj.Y, obj.M, bs, lr),
           "loss_state": obj.st.train(obj.XS, obj.Y, obj.M, bs, lr),
           "train_s": round(time.time() - t0, 2), "total_rows": int(len(obj.Y))}
    obj.batches += 1
    obj.reset_rows += len(obj.Y) - new_from
    if obj.reset_rows >= RESET_ROWS:
        obj.reset_rows = 0
        obj.full.shrink_perturb()
        obj.st.shrink_perturb()
        out["reset"] = True
    return out


POST_OPTS = ("DEFEND", "HOLD", "ATTACK", "RAID")   # military/state.as POST_* order


def featurize_post(row, state_keys, post_keys):
    """In NnPostScore's order: state, posture fields (both slog), then the
    option one-hot and the rule's option one-hot (raw 0/1)."""
    s = [slog(num(row["state"].get(k, 0))) for k in state_keys]
    s += [slog(num(row["post"].get(k, 0))) for k in post_keys]
    ci = row["chosen"]
    rule = POST_OPTS.index(row["rule"]) if row["rule"] in POST_OPTS else -1
    x = [1.0 if i == ci else 0.0 for i in range(len(POST_OPTS))]
    x += [1.0 if i == rule else 0.0 for i in range(len(POST_OPTS))]
    return s, s + x


def featurize_head(row, state_keys, own_keys, opts):
    """A decision head's row in its score function's order: state, its own
    fields (both slog), then the option one-hot and the rule's (raw 0/1)."""
    s = [slog(num(row["state"].get(k, 0))) for k in state_keys]
    s += [slog(num(row["post"].get(k, 0))) for k in own_keys]
    ci = row["chosen"]
    rule = opts.index(row["rule"]) if row["rule"] in opts else -1
    x = [1.0 if i == ci else 0.0 for i in range(len(opts))]
    x += [1.0 if i == rule else 0.0 for i in range(len(opts))]
    return s, s + x


class PostHead(FacHead):
    """The posture net: defend / hold / attack / raid, scored by what followed."""
    NAME = "post"
    OPTS = POST_OPTS
    post_keys = None

    def featurize(self, row, state_keys):
        return featurize_post(row, state_keys, self.post_keys)

    def rule_of(self, row):
        return self.OPTS.index(row["rule"]) if row.get("rule") in self.OPTS else None

    def alts_of(self, row, rule):
        """Options offered (logged weight > 0) other than the rule's, by index."""
        out = []
        for o in row.get("opts") or []:
            n = o.get("name")
            if n in self.OPTS and self.OPTS.index(n) != rule and num(o.get("w", 0)) > 0:
                out.append(self.OPTS.index(n))
        return out


class ComHead(PostHead):
    """The commander net (comdecide.as): work / fight / turret / retreat."""
    NAME = "com"
    OPTS = ("WORK", "FIGHT", "TURRET", "RETREAT")
    PREFIX = "NNC"

    def featurize(self, row, state_keys):
        return featurize_head(row, state_keys, self.post_keys, self.OPTS)


class TechHead(ComHead):
    """The T2 net (nntech.as): is now the time for the advanced lab, or wait."""
    NAME = "tech"
    OPTS = ("WAIT", "NOW")
    PREFIX = "NNT"


class RaidHead(ComHead):
    """The raid net (military/nnraid.as): send the raiders at the best-priced target, or wait."""
    NAME = "raid"
    OPTS = ("WAIT", "GO")
    PREFIX = "NNR"


class AirHead(ComHead):
    """The air-strike net: send the bombers / gunships at the best-priced target, or wait."""
    NAME = "air"
    OPTS = ("WAIT", "GO")
    PREFIX = "NNA"


VAL_ALTS = 9   # evenly spaced values a placebo row's stand-in is drawn from


def featurize_val(row, state_keys, own_keys):
    """A continuous head's row in NnValBest's order: state and own fields (slog),
    then the value played and the rule's value, raw."""
    s = [slog(num(row["state"].get(k, 0))) for k in state_keys]
    s += [slog(num(row["post"].get(k, 0))) for k in own_keys]
    return s, s + [float(row["chosen"]), float(row["rule"])]


class ValHead(ComHead):
    """A continuous head (nnlog.as NnValDecide): `chosen` is the value played and
    `rule` the rule's. Its chance rows are the uniform draws (all at one density,
    so weight 1); trust compares FULL(drawn v) - FULL(rule) with the outcome less
    FULL(rule), and the placebo puts an evenly spaced stand-in on rule rows."""
    OPTS = ("v", "rule")
    VAL = True
    vrange = None

    def featurize(self, row, state_keys):
        return featurize_val(row, state_keys, self.post_keys)

    def rule_of(self, row):
        return float(row["rule"])

    def alts_of(self, row, rule):
        lo, hi = row["lo"], row["hi"]
        vals = [lo + (hi - lo) * k / (VAL_ALTS - 1) for k in range(VAL_ALTS)]
        return [v for v in vals if abs(v - rule) > 1e-6]

    @staticmethod
    def rand_weight(row):
        return 1.0 if row.get("rnd") else None

    def learn(self, source, g, first_touch, rows):
        if rows:
            self.vrange = (rows[-1]["lo"], rows[-1]["hi"])
        return super().learn(source, g, first_touch, rows)


class EscHead(ValHead):
    """The escort head (escnet.as): escorts per constructor and owed metal x v, 0-8."""
    NAME = "esc"
    PREFIX = "NNE"


class ConHead(ValHead):
    """The constructor-floor head (econet.as): ConsNeedAny's target x v, 0.25-8; above 1x it holds
    while the army is behind its share."""
    NAME = "con"
    PREFIX = "NNK"


class MexHead(ValHead):
    """The expansion head (econet.as): every mex want's value x v, 0-6; above 1x an open mex also
    comes before the forced guns."""
    NAME = "mex"
    PREFIX = "NNX"


class CapHead(ValHead):
    """The ground constructor-cap head (econet.as): pools x v of the base, 0.5-12."""
    NAME = "cap"
    PREFIX = "NNQ"


class AirCapHead(ValHead):
    """The air constructor-cap head (econet.as): x 4v of the base, v 1-20."""
    NAME = "acap"
    PREFIX = "NNZ"


class PlanHead(ComHead):
    """The team plan net (plannet.as): normal play, mass T3, missiles, artillery, mass and push,
    mass air, an all-in, greed, turtle."""
    NAME = "plan"
    OPTS = ("NORMAL", "T3", "MISSILE", "ARTY", "MASS", "AIR", "RUSH", "GREED", "TURTLE", "GREED_DEEP")
    PREFIX = "NNG"


class AirPlantHead(ValHead):
    """The air plant count head (plannet.as): under the AIR plan, 1-8 plants, the game takes ceil."""
    NAME = "aplant"
    PREFIX = "NNL"


class ReinfHead(ComHead):
    """The join-the-fight net (joinfight.as): march to a fight our side is already in, or stay.
    Its 'done' is whether the squad arrived while the fight still raged."""
    NAME = "reinf"
    OPTS = ("GO", "STAY")
    PREFIX = "NNV"


class JoinHead(ComHead):
    """The join-or-new net (joinnet.as): join a same-def site already rising, or open a new one."""
    NAME = "join"
    OPTS = ("JOIN", "NEW")
    PREFIX = "NNJ"


class HuntHead(ComHead):
    """The hunt net (military/nnhunt.as): send the attack squads at their biggest army, or not.
    Its 'done' is the trade near that army over the next 3 minutes (decisions.head_labels)."""
    NAME = "hunt"
    OPTS = ("NO", "HUNT")
    PREFIX = "NNH"


class ScoutCapHead(ValHead):
    """The late ground scout cap head (econet.as): x v of the flat base, 0.25-8."""
    NAME = "scap"
    PREFIX = "NNS"


class EscCapHead(ValHead):
    """The escort cap head (escnet.as): escorts at once x v of the strength-scaled cap, 0.25-10."""
    NAME = "ecap"
    PREFIX = "NNY"


class StrikeHead(ComHead):
    """The strike net (military/nnstrike.as): send the attack squads at their economy now, in a
    timing window (their army away, a fight just won, ours at a peak against theirs), or not."""
    NAME = "strike"
    OPTS = ("NO", "STRIKE")
    PREFIX = "NNB"


class MassHead(ValHead):
    """The pool-size head (military/nnmassodds.as): x v, 0.25-6, on the bar a massing pool
    must reach before it leaves. Judged by the shared targets (trade, losses, army edge)."""
    NAME = "mass"
    PREFIX = "NNM"


class OddsHead(ValHead):
    """The squad-odds head (military/nnmassodds.as): x v, 0.25-6, on the enemy influence an
    attack squad refuses against. Judged by the shared targets (lnD, losses, army edge)."""
    NAME = "odds"
    PREFIX = "NNO"


DEC_HEADS = (ComHead, TechHead, RaidHead, AirHead, EscHead, ConHead, MexHead, CapHead, AirCapHead, PlanHead, JoinHead, AirPlantHead, ReinfHead, HuntHead, ScoutCapHead, EscCapHead, StrikeHead, MassHead, OddsHead)   # decisions.head_rows_of / val_rows_of(tag)


class DefAmtHead(ValHead):
    """The static defence amount head (protect_nn.as): DefenceTarget x v, 0.25-8.
    No 'done' of its own: the team's per-horizon outcomes (lostMobile, edges, endV)."""
    NAME = "defamt"
    PREFIX = "NND"


class DefSiteHead(ComHead):
    """The static defence site net (protect_nn.as): the rule's site or the best
    slot of another kind. Its 'done' is the trade at the chosen site over 5 min."""
    NAME = "defsite"
    OPTS = ("RULE", "WALL", "MEXG", "FRONT", "FLANK", "FORT", "LEAK")
    PREFIX = "NNU"


class DefTypeHead(ComHead):
    """The static defence gun-class net (protect_nntype.as): the rule's gun or the best
    of another class this hand can build. Its 'done' is the trade at the gun's site over 5 min."""
    NAME = "deftype"
    OPTS = ("RULE", "T1Q", "T1K", "T2Q", "T2K", "T2R")
    PREFIX = "NNN"


class OpenHead(ComHead):
    """The opening order net (opennet.as): the plant first, or one / two / three extractors
    first, or two extractors and a generator. One decision per commander per game."""
    NAME = "open"
    OPTS = ("LAB", "MEX1", "MEX2", "MEX3", "MEX2E")
    PREFIX = "NNOP"


class MexGuardHead(ValHead):
    """The mex-guard head (protect_nn.as): MexGunsWanted's far term x v and the coverall
    push's loss gate / v, 0.25-8. Judged by the shared targets (dMex, lostEco, edgeMex)."""
    NAME = "mexg"
    PREFIX = "NNMG"


DEC_HEADS = DEC_HEADS + (DefAmtHead, DefSiteHead, DefTypeHead, OpenHead, MexGuardHead)


class Trainer(Buffered):
    def __init__(self):
        OUT.mkdir(parents=True, exist_ok=True)
        seen = json.loads((OUT / "seen.json").read_text()) if (OUT / "seen.json").is_file() else {}
        self.seen_dirs = set(seen.get("dirs", []))
        self.used = {k: set(map(tuple, v)) for k, v in seen.get("used", {}).items()}
        self.used_at = seen.get("used_at", {k: time.time() for k in self.used})
        self.state_keys = None
        self.buf_clear()
        self.full = self.st = None
        self.batches = 0
        self.since_export = 0
        self.exported = 0
        self.logger = {}
        self.trust_pairs = {}   # kind -> [(d, a, 1/p, game)] of held-out chance rows (honest_trust)
        self.placebo, self.placebo_old = [], []
        self.fac = FacHead()
        self.post = PostHead()
        self.heads = {h.NAME: h() for h in DEC_HEADS}
        self.parsed_at = {}
        self.load()

    def load(self):
        if not (OUT / "model.pt").is_file():
            if self.store().exists():
                self.buf_archive(OUT.parent / "nn-archive" / time.strftime("%Y%m%d-%H%M%S"))
            return
        idx = self.buf_load()
        if idx is None:
            return
        import torch
        self.state_keys = list(idx["state_keys"])
        self.batches = int(idx.get("batches", 0))
        ck = torch.load(OUT / "model.pt", weights_only=False)
        net_t, buf_t = saved_targets(ck, {"Y": self.Y, "targets": idx.get("targets", [])})
        if tuple(ck.get("opt_num", ())) != OPT_NUM or not adopt_targets(self, "builder", net_t, buf_t):
            self.fresh_start("this trainer predicts different outcomes or reads different options")
            return
        self.full = Net(self.XF.shape[1], len(net_t))
        self.st = Net(self.ns, len(net_t))
        self.full.load(ck["full"])
        self.st.load(ck["state"])
        for net in (self.full, self.st):
            net.grow_out(len(TARGETS) - len(net_t))
        # saved every batch but never read back: each restart wiped the trust evidence
        # pairs of the old (kind 1) trust are 3-tuples: honest_trust skips them
        self.trust_pairs = {k: [tuple(x) for x in v] for k, v in (ck.get("trust_pairs") or {}).items()}
        self.placebo, self.placebo_old = list(ck.get("placebo", [])), list(ck.get("placebo_old", []))
        self.reset_rows = int(ck.get("reset_rows", 0))

    def fresh_start(self, why):
        """Archive the current net and its history, then learn from nothing.
        Games already used stay used: the old rows are kept with the archive."""
        dest = reset()
        print("fresh net (%s); the old one is kept in %s" % (why, dest), flush=True)
        self.state_keys = None
        self.buf_clear()
        self._store = None
        # reset() moved the factory and posture buffers too: they write theirs whole again
        for h in (self.fac, self.post):
            h.saved_rows = 0
            h._store = None
        self.full = self.st = None
        self.batches = 0
        self.since_export = 0
        self.trust_pairs = {}
        self.placebo, self.placebo_old = [], []

    def save(self, buffer=None, force=False):
        """Model and the rows added since the last save (append-only). A game's
        used-decision list is dropped USED_KEEP_S after it was last touched: by
        then the game has finished and is in seen_dirs."""
        import torch
        now = time.time()
        # On a clock, not every game. Everything is written together, so a kill
        # loses at most SAVE_S of learning, re-read on restart.
        if buffer is None and not force and now - getattr(self, "saved_at", 0.0) < SAVE_S:
            self.dirty = True
            return
        self.saved_at, self.dirty = now, False
        for fp in [k for k, t in self.used_at.items() if now - t > USED_KEEP_S]:
            self.used.pop(fp, None)
            self.used_at.pop(fp, None)
        seen = {"dirs": sorted(self.seen_dirs), "used": {k: sorted(v) for k, v in self.used.items()},
                "used_at": self.used_at}
        tmp = OUT / "seen.json.tmp"
        tmp.write_text(json.dumps(seen))
        replace_retry(tmp, OUT / "seen.json")
        for h in [self.fac, self.post] + list(self.heads.values()):
            h.save(buffer=bool(buffer), force=True)
        if self.full is None:
            return
        self.buf_save()
        torch.save({"full": self.full.state(), "state": self.st.state(), "targets": TARGETS,
                    "post_keys": getattr(self, "post_keys", None), "reset_rows": self.reset_rows,
                    "state_keys": self.state_keys, "kinds": KINDS, "opt_num": OPT_NUM,
                    "trust_pairs": self.trust_pairs, "placebo": self.placebo, "placebo_old": self.placebo_old},
                   OUT / "model.pt.tmp")
        replace_retry(OUT / "model.pt.tmp", OUT / "model.pt")

    def status(self, phase, **kw):
        st = {"phase": phase, "at": time.time(), "pid": os.getpid(), "batches": self.batches,
              "rows": 0 if self.Y is None else int(len(self.Y)), "exported": self.exported}
        st.update(kw)
        tmp = OUT / "status.json.tmp"
        tmp.write_text(json.dumps(st))
        replace_retry(tmp, OUT / "status.json")

    # -- sources ---------------------------------------------------------

    def finished_games(self):
        found = []
        tours, matches = FINISHED
        dirs = []
        for t in fresh(tours):
            dirs += fresh(t / "matches")
        dirs += fresh(matches)
        for d in dirs:
            key = str(d.relative_to(REPO))
            res = d / "result.json"
            if key in self.seen_dirs or not res.is_file() or not (d / "infolog.txt").is_file():
                continue
            if res.stat().st_mtime >= LOGGER_SINCE:
                found.append((res.stat().st_mtime, key, d))
        return sorted(found)

    def live_games(self):
        now = time.time()
        out = []
        if NO_LIVE:
            return out
        for root, prefix in LIVE:
            try:
                wds = [d for d in root.iterdir() if d.is_dir() and d.name.startswith(prefix)]
            except OSError:
                continue
            for wd in wds:
                gl = wd / "barai-gadgets.log"
                try:
                    if now - gl.stat().st_mtime > LIVE_IDLE_S:
                        continue
                except OSError:
                    continue
                logs = [p for p in (wd / "AI" / "Skirmish").glob("*/*/apex-t*.log")
                        if not p.name.endswith(".prev.log") and now - p.stat().st_mtime < LIVE_IDLE_S
                        and self.has_logger(p)]
                if logs and now - self.parsed_at.get(wd, 0) >= LIVE_REREAD_S:
                    out.append((wd, [gl] + logs))
        return out

    def has_logger(self, p):
        """Read a live AI log's head once per game: no v3 schema line, no reread
        (his own games run a build without the recorder)."""
        st = p.stat()
        key = (str(p), st.st_ctime)
        if key not in self.logger:
            try:
                with open(p, encoding="utf-8", errors="replace") as fh:
                    head = fh.read(256 * 1024)
            except OSError:
                return False
            if "apex: nn-schema v" in head:
                self.logger[key] = True
            elif time.time() - st.st_ctime > 180:
                self.logger[key] = False
            else:
                return False
        return self.logger[key]

    # -- learning --------------------------------------------------------

    def rows_from(self, g, path, final):
        """Rows of a parsed game not yet used: matured ones, or all when final.
        A game is keyed per TEAM by that team's first records, so a live read
        that has not yet seen one team's log and the finished infolog agree.
        Returns (first_touch, [(team_fp, key, row)]): first_touch when no team
        of this game was learned from before -- the only honest accuracy point."""
        if (g["state_keys"] is None or g["opt_keys"] is None or SCHEMA_OPT not in g["opt_keys"]
                or SCHEMA_STATE not in g["state_keys"]):
            return False, []
        first = {}
        for r in sorted(g["rows"], key=lambda q: int(q[0])):
            t = int(r[1])
            if len(first.setdefault(t, [])) < 3:
                first[t].append("%s.%s" % (r[0], r[2]))
        fps = {t: "%d|%s" % (t, "|".join(v)) for t, v in first.items()}
        first_touch = not any(self.used.get(fp) for fp in fps.values())
        out = []
        for r in decisions.rows_of(str(path), g):
            fp = fps[r["team"]]
            key = (r["team"], r["f"], r["unit"])
            if key in self.used.get(fp, ()):
                continue
            if not final:
                if r["f"] + decisions.HORIZONS[-1] * decisions.FPM > g["last"]:
                    continue
                # survival needs 5 minutes after the FINISH: hold the row until known
                if r["y"].get("done") == 1 and (r["y"].get("survived") is None or r["y"].get("lifeS") is None):
                    continue
            out.append((fp, key, r))
        return first_touch, out

    def learn(self, source, g, first_touch, items):
        if not adopt_keys(self, g["state_keys"]):
            self.fresh_start("the record's state layout changed")
        if self.state_keys is None:
            self.state_keys = g["state_keys"]
        xs, xf, ys, ms, decided, kinds, rw, teams, kept = [], [], [], [], [], [], [], [], []
        for _fp, _key, r in items:
            y, m = target_vec(r)
            if not any(m):
                continue
            s, f = featurize(r, self.state_keys)
            kept.append(r)
            teams.append(r["team"])
            xs.append(s)
            xf.append(f)
            ys.append(y)
            ms.append(m)
            ci = r["chosen"]
            kinds.append(r["opts"][ci].get("kind") if 0 <= ci < len(r["opts"]) else None)
            rw.append(rand_weight(r))
            decided.append(r["dm"] in DECIDED and r["pick"] == 0 and 0 <= ci < len(r["opts"])
                           and not r["opts"][ci].get("forced"))
        if not xs:
            return None
        XS, XF = np.array(xs, dtype=np.float32), np.array(xf, dtype=np.float32)
        Y, M = np.array(ys, dtype=np.float32), np.array(ms, dtype=np.float32)
        rec = {"source": source, "at": time.time(), "rows": len(xs), "index": self.batches + 1,
               "targets": ["%s:%s" % t for t in TARGETS], "first_touch": first_touch}
        # Accuracy only on the first batch of a game: later batches of the same
        # game share 99% of their label windows with rows just trained on.
        if self.full is not None and first_touch:
            base = self.full.ym
            pf, ps = self.full.predict(XF), self.st.predict(XS)
            rec["r2_full"], rec["r2_state"] = r2(pf, Y, M, base), r2(ps, Y, M, base)
            rec["head_full"] = mean_of(rec["r2_full"], HEADLINE)
            rec["head_state"] = mean_of(rec["r2_state"], HEADLINE)
            rec["game_sums"] = game_sums(pf, ps, Y, M, base)
            # with vs without the decision, on rows where an option was CHOSEN on
            # value -- forced paths tell the net which panic fired, not what a choice is worth
            d = np.array(decided)
            if d.sum() >= 20:
                rec["decided_rows"] = int(d.sum())
                rec["head_full_d"] = mean_of(r2(pf[d], Y[d], M[d], base), HEADLINE)
                rec["head_state_d"] = mean_of(r2(ps[d], Y[d], M[d], base), HEADLINE)
            for name in ("done", "survived"):
                j = TARGETS.index((name, name))
                k = M[:, j] > 0
                if k.sum() >= 5:
                    rec[name + "_acc"] = float(((pf[k, j] > 0.5) == (Y[k, j] > 0.5)).mean())
                    rec[name + "_base"] = float(max(Y[k, j].mean(), 1 - Y[k, j].mean()))
            score_decisions(self, kept, XF, Y, M, rw, pf, ps, decisions.fingerprint(g) or source,
                            lambda i: self.trust_pairs.setdefault(kinds[i], []),
                            lambda r, ci: featurize(dict(r, chosen=ci), self.state_keys)[1],
                            rule_of_list, alts_of_list, rec)
            rec["trust"] = self.trust()
        self.status("training", source=source)
        T = self.tags_for(g, teams, self.batches + 1)
        if HUMAN_TAG in str(source):
            XF, Y, M, T = (np.repeat(a, HUMAN_W, axis=0) for a in (XF, Y, M, T))
        if self.XF is None:
            self.ns = XS.shape[1]
            self.full = Net(XF.shape[1], len(TARGETS))
            self.st = Net(self.ns, len(TARGETS))
        new_from = self.buf_add(XF, Y, M, T)
        rec.update(fit_batch(self, new_from))
        for fp, key, _r in items:
            self.used.setdefault(fp, set()).add(key)
            self.used_at[fp] = time.time()
        self.since_export += len(items)
        if self.since_export >= EXPORT_ROWS:
            rec["exported"] = self.export()
        with open(OUT / "metrics.jsonl", "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec) + "\n")
        self.write_samples(source, items)
        self.save()
        return rec

    def write_samples(self, source, items):
        """The latest few real decisions, every option with its market value,
        the net's multiplier and its draw odds: the Net tab's decision view."""
        out = []
        for _fp, _key, r in items[-40:]:
            if len(r["opts"]) < 2:
                continue
            out.append({"source": source, "f": r["f"], "con": r["con"], "why": r["why"],
                        "dm": r["dm"], "pick": r["pick"], "chosen": r["chosen"],
                        "opts": [{k: o.get(k) for k in ("kind", "def", "value", "nm", "p", "forced", "eta")}
                                 for o in r["opts"]]})
        if out:
            tmp = OUT / "samples.json.tmp"
            tmp.write_text(json.dumps(out[-8:]))
            replace_retry(tmp, OUT / "samples.json")

    def trust(self):
        """Per chosen option's kind: honest_trust of its held-out chance rows."""
        key = tuple((k, len(v), v[-1][:2] if v else None) for k, v in sorted(self.trust_pairs.items(), key=str)) + \
            (len(self.placebo), self.placebo[-1][:2] if self.placebo else None)
        if getattr(self, "_trust_memo", (None,))[0] != key:
            pl = placebo_of(self)
            self._trust_memo = (key, {kind: honest_trust(self.trust_pairs.get(kind, []), pl) for kind in KINDS})
        return self._trust_memo[1]

    def export(self):
        if NO_EXPORT:
            return 0
        text = export_as(self.full, self.state_keys, self.batches, self.trust(), self.fac, self.post, self.heads)
        n = 0
        for p in export_targets():
            tmp = p.with_suffix(".tmp")
            tmp.write_text(text, encoding="utf-8")
            replace_retry(tmp, p)
            n += 1
        self.since_export = 0
        self.exported += 1
        self.snapshot(text)
        return n

    def snapshot(self, text=None, force=False):
        """Every SNAPSHOT_S, the exported weights as they played, kept for
        tools/nneval.py: snapshots/<stamp>/nnweights.as + meta.json."""
        root = OUT / "snapshots"
        stamps = sorted(p.name for p in root.glob("*") if (p / "nnweights.as").is_file()) if root.is_dir() else []
        if stamps and not force:
            try:
                last = json.loads((root / stamps[-1] / "meta.json").read_text(encoding="utf-8")).get("at", 0)
            except (OSError, ValueError):
                last = (root / stamps[-1] / "nnweights.as").stat().st_mtime
            if time.time() - last < SNAPSHOT_S:
                return None
        if text is None:
            text = export_as(self.full, self.state_keys, self.batches, self.trust(), self.fac, self.post, self.heads)
        dest = root / time.strftime("%Y%m%d-%H%M%S")
        dest.mkdir(parents=True, exist_ok=True)
        (dest / "nnweights.as").write_text(text, encoding="utf-8")
        newest = self.tables.get("ver", [])[-1:]
        (dest / "meta.json").write_text(json.dumps({
            "at": time.time(), "batches": self.batches, "rows": 0 if self.Y is None else int(len(self.Y)),
            "exported": self.exported, "trust": self.trust(), "newest_version": newest,
            "heads": {k: {"batches": h.batches, "trust": h.trust()} for k, h in
                      [("fac", self.fac), ("post", self.post)] + list(self.heads.items())}}, indent=1), encoding="utf-8")
        print("snapshot: %s" % dest, flush=True)
        return dest

    def learn_fac(self, source, g, path, final):
        """The factory rows of one parsed game: matured (or all, when final),
        not used before, keyed per team like the builder rows."""
        if not g.get("fac_keys") or FAC_SCHEMA_OPT not in g["fac_keys"] or g["state_keys"] is None:
            return None
        if SCHEMA_STATE not in g["state_keys"]:
            return None
        first = {}
        for r in sorted(g["facrows"], key=lambda q: int(q[0])):
            t = int(r[1])
            if len(first.setdefault(t, [])) < 3:
                first[t].append("%s.%s" % (r[0], r[2]))
        fps = {t: "fac|%d|%s" % (t, "|".join(v)) for t, v in first.items()}
        first_touch = not any(self.used.get(fp) for fp in fps.values())
        rows, keys = [], []
        for r in decisions.fac_rows_of(str(path), g):
            fp = fps[r["team"]]
            key = (r["team"], r["f"], r["unit"])
            if key in self.used.get(fp, ()):
                continue
            if not final:
                if r["f"] + decisions.HORIZONS[-1] * decisions.FPM > g["last"]:
                    continue
                if r["y"].get("done") == 1 and r["y"].get("lifeS") is None:
                    continue
            rows.append(r)
            keys.append((fp, key))
        if not rows or (not final and len(rows) < MIN_BATCH):
            return None
        rec = self.fac.learn(source, g, first_touch, rows)
        for fp, key in keys:
            self.used.setdefault(fp, set()).add(key)
            self.used_at[fp] = time.time()
        self.since_export += len(rows) // 4
        return rec

    def learn_post(self, source, g, path, final):
        """The army-posture rows of one parsed game, like learn_fac."""
        return self.learn_head(self.post, g.get("post_keys"), g.get("postrows") or [],
                               decisions.post_rows_of(str(path), g), source, g, final)

    def learn_heads(self, source, g, path, final):
        out = []
        for name, head in self.heads.items():
            # a continuous head reads only `apex: nnval` rows: an old discrete row is another decision
            h = g.get("vals" if head.VAL else "heads", {}).get(name)
            if h:
                rows = (decisions.val_rows_of if head.VAL else decisions.head_rows_of)(str(path), g, name)
                out.append(self.learn_head(head, h["keys"], h["rows"], rows, source, g, final))
        return out

    def learn_head(self, head, own_keys, raw, labelled, source, g, final):
        """One decision head's rows of one parsed game: matured (or all, when
        final), not used before, keyed per team by its first three decisions."""
        if not own_keys or g["state_keys"] is None or SCHEMA_STATE not in g["state_keys"]:
            return None
        if head.post_keys is not None and head.post_keys != own_keys:
            # a game logged before the head's inputs grew: skip it, or every
            # older game in the queue would wipe the newer head again -- unless
            # today's script logs exactly this game's list, and the head holds
            # fields it no longer has (the com head kept a lane-only `evade` from
            # 10-05 and skipped every game after, off in game the whole time)
            canon = decisions.canon_head_keys(head.NAME)
            if head.post_keys[:len(own_keys)] == list(own_keys) and list(own_keys) != canon:
                return None
            print("%s: inputs changed (%d -> %d own fields); starting over" % (head.NAME, len(head.post_keys), len(own_keys)), flush=True)
            head._FacHead__init_empty()
        head.post_keys = own_keys
        first = {}
        for r in sorted(raw, key=lambda q: int(q[0])):
            t = int(r[1])
            if len(first.setdefault(t, [])) < 3:
                first[t].append(r[0])
        # clocked heads decide on the same frames every game: the game is part of the key
        gfp = decisions.fingerprint(g)
        fps = {t: "%s|%s|%d|%s" % (head.NAME, gfp, t, "|".join(v)) for t, v in first.items()}
        first_touch = not any(self.used.get(fp) for fp in fps.values())
        rows, keys = [], []
        for r in labelled:
            fp = fps[r["team"]]
            key = (r["team"], r["f"], -1)
            if key in self.used.get(fp, ()):
                continue
            if not final and r["f"] + decisions.HORIZONS[-1] * decisions.FPM > g["last"]:
                continue
            rows.append(r)
            keys.append((fp, key))
        if not rows or (not final and len(rows) < MIN_BATCH // 4):
            return None
        rec = head.learn(source, g, first_touch, rows)
        for fp, key in keys:
            self.used.setdefault(fp, set()).add(key)
            self.used_at[fp] = time.time()
        return rec

    def poll(self):
        did = []
        for key, d, g in parsed_in_order(self.finished_games()):
            first, items = self.rows_from(g, d, final=True)
            self.seen_dirs.add(key)
            if items:
                did.append(self.learn(key, g, first, items))
            did.append(self.learn_fac(key, g, d, final=True))
            did.append(self.learn_post(key, g, d, final=True))
            did.extend(self.learn_heads(key, g, d, final=True))
        live = self.live_games()
        for wd, files in live:
            self.parsed_at[wd] = time.time()
            g = decisions.parse(str(wd), files)
            first, items = self.rows_from(g, wd, final=False)
            if len(items) >= MIN_BATCH:
                did.append(self.learn("live:" + wd.name, g, first, items))
            did.append(self.learn_fac("live:" + wd.name, g, wd, final=False))
            did.append(self.learn_post("live:" + wd.name, g, wd, final=False))
            did.extend(self.learn_heads("live:" + wd.name, g, wd, final=False))
        if did:
            self.save()
        # a deploy writes the repo's empty net over ours: put it back
        if any(not stale_ok(p, self.state_keys, self.full is not None) for p in export_targets()):
            self.export()
        return [r for r in did if r], len(live)


def parsed_in_order(games):
    """(key, dir, parsed game) in the given order; with BARAI_NN_PARSE > 1 the
    parsing runs in worker processes a chunk at a time (a rebuild reads
    thousands of games; learning stays sequential)."""
    workers = int(os.environ.get("BARAI_NN_PARSE", "1"))
    if workers <= 1 or len(games) < 2 * workers:
        for _t, key, d in games:
            yield key, d, decisions.parse(str(d))
        return
    from concurrent.futures import ProcessPoolExecutor
    with ProcessPoolExecutor(max_workers=workers) as ex:
        for i in range(0, len(games), 4 * workers):
            chunk = games[i:i + 4 * workers]
            for (_t, key, d), g in zip(chunk, ex.map(decisions.parse, [str(d) for _t, _k, d in chunk])):
                yield key, d, g


def replace_retry(src, dst, tries=20):
    """os.replace that waits out a reader: on Windows the dashboard (status.json)
    or a starting engine (nnweights.as) holding the target makes it fail."""
    for i in range(tries):
        try:
            os.replace(src, dst)
            return
        except PermissionError:
            if i == tries - 1:
                raise
            time.sleep(0.25)


def stale_ok(p, state_keys, has_net=True):
    """The deployed weights are what this trainer would write: today's layout
    (a deploy writes the repo's empty net; an older trainer another layout), the
    builder net when there is one, the BARb prior when it has been trained."""
    try:
        with open(p, encoding="utf-8") as fh:
            head = fh.read()
    except OSError:
        return False
    if not all(k in head for k in ("NNW_TRUST", "NNF_TRUST", "NNP_TRUST", "NNC_TRUST", "NNT_TRUST", "NNR_TRUST", "NNA_TRUST", "NNE_TRUST", "NNK_TRUST", "NNX_TRUST", "NNQ_TRUST", "NNZ_TRUST", "NNG_TRUST", "NNJ_TRUST", "NNL_TRUST", "NNV_TRUST", "NNH_TRUST", "NNS_TRUST", "NNY_TRUST", "NNB_TRUST", "NNM_TRUST", "NNO_TRUST", "NNI_ON")):
        return False
    if not all(k in head for k in ("NND_TRUST", "NNU_TRUST", "NNN_TRUST", "NNOP_TRUST", "NNMG_TRUST")):
        return False
    if not all((h.PREFIX + "_LO") in head for h in DEC_HEADS if h.VAL):
        return False
    if ("NN_TRUST_KIND = %d;" % TRUST_KIND) not in head:
        return False
    if (OUT / "imitate.npz").is_file() and "NNI_ON = true" not in head:
        return False
    if not has_net:
        return True
    return "NNW_ON = true" in head and ('NNW_STATE = "%s"' % ",".join(state_keys or [])) in head


def fresh(root):
    try:
        return [d for d in root.iterdir() if d.is_dir() and not d.name.startswith("_")
                and d.stat().st_mtime >= LOGGER_SINCE]
    except OSError:
        return []


def reset():
    """Start a fresh net. The old one and its whole history move to
    runtime/nn-archive/<stamp>/, never deleted: copy them back to restore."""
    names = ("metrics.jsonl", "status.json", "model.pt", "buffer.npz", "seen.json",
             "fac_model.pt", "fac_buffer.npz", "post_model.pt", "post_buffer.npz", "samples.json")
    shards = ("builder_rows", "fac_rows", "post_rows")
    if not any((OUT / n).is_file() for n in names) and not any((OUT / "shards" / s).is_dir() for s in shards):
        return None
    dest = OUT.parent / "nn-archive" / time.strftime("%Y%m%d-%H%M%S")
    dest.mkdir(parents=True, exist_ok=True)
    for name in names:
        p = OUT / name
        if p.is_file():
            replace_retry(p, dest / name)
    for s in shards:
        if (OUT / "shards" / s).is_dir():
            replace_retry(OUT / "shards" / s, dest / s)
    return dest


def main(argv):
    import torch
    torch.set_num_threads(int(os.environ.get("BARAI_NN_THREADS", "2")))
    if "--reset" in argv:
        dest = reset()
        print("fresh net; the old one is kept in %s" % dest if dest else "no net to archive")
        return 0
    if "--help" in argv or "-h" in argv:
        print(__doc__)
        return 0
    # one trainer only: two would overwrite each other's net and buffer
    try:
        st = json.loads((OUT / "status.json").read_text())
        if (st.get("phase") in ("watching", "training") and time.time() - st.get("at", 0) < 60
                and st.get("pid") != os.getpid() and "--force" not in argv):
            print("another trainer (pid %s) is running; stop it first (or --force)" % st.get("pid"))
            return 1
    except (OSError, ValueError):
        pass
    tr = Trainer()   # loading migrates any legacy *buffer.npz to shards first
    if "--migrate" in argv:
        print("buffers: " + ", ".join("%s %d rows" % (h.STORE, 0 if h.Y is None else len(h.Y))
                                      for h in [tr, tr.fac, tr.post] + list(tr.heads.values())))
        return 0
    if "--compact" in argv:
        for h in [tr, tr.fac, tr.post] + list(tr.heads.values()):
            if h.dropped and h.XF is not None:
                h.store().compact(h.XF, h.Y, h.M, h.T, h.buf_meta())
                print("%s: rewritten without %d capped rows" % (h.STORE, h.dropped), flush=True)
        return 0
    if "--snapshot" in argv:
        print("snapshot in %s" % tr.snapshot(force=True))
        return 0
    if "--export" in argv:
        print("weights written to %d deployed copies" % tr.export())
        return 0
    print("learning from running and finished games; %d batches so far" % tr.batches, flush=True)
    try:
        while True:
            try:
                recs, n_live = tr.poll()
            except KeyboardInterrupt:
                raise
            except Exception as e:
                # one bad game or a locked file must not stop the training loop
                import traceback
                traceback.print_exc()
                print("poll failed (%s); retrying in %ds" % (e, POLL_S), flush=True)
                recs, n_live = [], 0
                if "--once" in argv:
                    return 1
            for rec in recs:
                h = rec.get("head_full")
                print("%s: %d decisions, unseen R2(+3min) full=%s state=%s, loss %.3f%s"
                      % (rec["source"], rec["rows"], "-" if h is None else "%.3f" % h,
                         "-" if rec.get("head_state") is None else "%.3f" % rec["head_state"],
                         rec["loss_full"], " -> exported" if rec.get("exported") else ""), flush=True)
            if "--once" in argv:
                tr.save(buffer=True)
                tr.status("stopped")
                return 0
            if not recs and getattr(tr, "dirty", False):
                tr.save(force=True)
            tr.status("watching", live=n_live)
            time.sleep(POLL_S)
    except KeyboardInterrupt:
        tr.save(buffer=True)
        tr.status("stopped")
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
