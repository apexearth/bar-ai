"""Live trainer for the decision value net (docs/35-decision-net.md).

    python tools/nntrain.py            # learn from running and finished games until stopped
    python tools/nntrain.py --once     # take what is waiting, then exit
    python tools/nntrain.py --reset    # start a fresh net; the old one is archived, never deleted
    python tools/nntrain.py --export   # write the current net into the deployed AI now

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

Writes runtime/nn/: metrics.jsonl, status.json, model.pt, buffer.npz, seen.json.
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

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "runtime" / "nn"
FINISHED = (REPO / "tournaments", REPO / "matches")
LIVE = ((REPO / "matches", "_engine"), (REPO / "runtime", "engine-w"))
KINDS = ("mex", "mexup", "energy", "geo", "convert", "store", "plant", "tech", "nano",
         "reclaim", "assist", "protect", "sense", "airdef", "super", "teeth")
OPT_NUM = ("value", "gain", "m", "t", "cm", "ce", "bt", "walk", "risk", "eta", "dPow", "ownN",
           "tierO", "fwd", "siteLoss", "persona")   # nnlog.as NnOpt order
PER_H = ("dMInc", "dEInc", "dEco", "lnD", "eWaste", "mWaste", "dMex", "lostNear", "lostFar",
         "lostAir", "lostStatic", "lostMobile", "reclaim")
LOGGED = ("lostNear", "lostFar", "lostAir", "lostStatic", "lostMobile", "reclaim", "lifeS", "lifeKill")
SINGLE = ("done", "survived", "lifeS", "lifeKill", "won", "comLost")    # one value per decision, not per horizon
TARGETS = [(h, k) for h in decisions.HORIZONS for k in PER_H] + [(k, k) for k in SINGLE]
SCHEMA_OPT = "forced"   # an option field only the current record (v5+) carries
SCHEMA_STATE = "foeBaseD"   # a state field only the current record carries: older rows are skipped, not a reset
Y_FLOOR = 0.1           # a rare outcome must not get a near-zero spread and swamp the loss
DECIDED = ("draw", "ladder")   # rows where an option was chosen on value, not forced
# What "better" means when the net plays, in units of each outcome's spread.
# A stated default until he picks one (docs/35).
OBJECTIVE = {(5, "dEco"): 0.5, (10, "dEco"): 1.0, (5, "dMInc"): 0.25, (5, "dEInc"): 0.25,
             (5, "lnD"): 0.25, (10, "lnD"): 0.5, (5, "lostNear"): -0.5,
             ("done", "done"): 0.25, ("survived", "survived"): 0.25,
             ("lifeS", "lifeS"): 0.25, ("lifeKill", "lifeKill"): 0.25,
             ("won", "won"): 1.0,   # the game result is the longest horizon
             ("comLost", "comLost"): -2.0}   # his ruling 10-05: the commander must not die
# the dashboard's headline accuracy: the outcomes the net is steered by
HEADLINE = [i for i, t in enumerate(TARGETS) if t in OBJECTIVE]
HIDDEN = 32
# What plays is a running average of the trained weights, half of it from the
# last EMA_HALF batches: one game moves it a little, a run of games moves it a
# lot. Each minibatch of new rows carries REPLAY_OLD times as many old ones.
EMA_HALF = 5
REPLAY_OLD = 3
DROPOUT = 0.1
MIN_BATCH = 150        # matured decisions before a live game is learned from
STEPS_PER_ROW = 2      # passes over each new batch (each mixed with as many old rows)
RESET_EVERY = 40       # batches between partial resets (shrink 0.8, perturb 0.2)
EXPORT_ROWS = 800      # new rows between weight exports
POLL_S = 5
LIVE_IDLE_S = 90       # a write dir untouched this long is not a running game
BUFFER_EVERY = 10       # batches between saves of the training buffer (it grows large)
TRUST_KEEP = 5000       # most recent unseen decisions per kind that set its trust
TRUST_MIN = 200         # a kind with fewer gets no say (trust 0)
USED_KEEP_S = 7200      # seconds a game's used-decision list is kept after its last batch
LIVE_REREAD_S = 15     # a running game is re-read at most this often
LOGGER_SINCE = 1791160000   # 2026-10-04: no finished game before this carries apex: nn


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


def target_vec(row):
    y, m = [], []
    for h, k in TARGETS:
        if h in SINGLE:
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

    def average(self):
        d = 0.5 ** (1.0 / EMA_HALF)
        with self.torch.no_grad():
            for ps, pf in zip(self.slow.parameters(), self.model.parameters()):
                ps.mul_(d).add_((1.0 - d) * pf)

    def fit_scalers(self, X, Y, M):
        # inputs are log-scaled; the floor stops a feature that never varied in
        # training from exploding the first time it does
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

    def train(self, X, Y, M, new_from, steps):
        """Minibatches of the new rows, each paired with as many rows drawn from
        everything before them. Returns the mean loss."""
        t = self.torch
        self.fit_scalers(X, Y, M)
        Xt, Mt = self._x(X), t.tensor(M, dtype=t.float32)
        Yt = t.tensor((Y - self.ym) / self.ys, dtype=t.float32)
        n_new = len(X) - new_from
        self.model.train()
        tot, cnt = 0.0, 0
        for _ in range(steps):
            perm = t.randperm(n_new) + new_from
            for i in range(0, n_new, 128):
                b = perm[i:i + 128]
                if new_from > 0:
                    b = t.cat([b, t.randint(0, new_from, (len(b) * REPLAY_OLD,))])
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
    n_state = head.XS.shape[1]   # what NnPostScore/NnFacScore feed once per decision
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


NNW_EMPTY = ["const bool NNW_ON = false;", "const int NNW_GAMES = 0;", 'const string NNW_STATE = "";',
             "const array<string> NNW_KINDS = {};", "const int NNW_S = 0;", "const int NNW_O = 0;",
             "const int NNW_H = 0;"] + \
            ["const array<float> NNW_%s = {};" % k for k in ("XM", "XS", "W1", "B1", "W2", "B2", "WO")] + \
            ["const float NNW_BO = 0.f;", "const array<float> NNW_TRUST = {};"]


def export_as(net, state_keys, games, trust, fac=None, post=None, heads=None):
    """Every net as nnweights.as: builder (NNW_*), factory (NNF_*), posture
    (NNP_*) and the BARb prior (NNI_*); a net not trained yet is the empty one."""
    tail = (["// the factory net (production.as roulette)"] + fac_block(fac) +
            ["// the posture net (military/nnpost.as)"] + post_block(post) +
            ["// the commander net (comdecide.as)"] + post_block((heads or {}).get("com"), "NNC") +
            ["// the T2 net (nntech.as)"] + post_block((heads or {}).get("tech"), "NNT") +
            ["// the BARb prior (tools/imitate.py)"] + imit_block() + ["", "}  // namespace Market", ""])
    head = ["namespace Market {", "", "// GENERATED by tools/nntrain.py -- the deployed copy only; do not commit."]
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
               "power", "fly", "bld")   # nnlog.as NnFacOpt order
FAC_SCHEMA_OPT = "fly"                   # an option field only the v2 factory record carries


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


class FacHead:
    """The factory net: what a production order is worth. Its own nets, buffer
    and ONE trust (how well its view of what an order adds matches what the
    order actually added, on unseen games). PostHead reuses it for posture."""
    NAME = "fac"
    OPTS = FAC_OPT_NUM

    @staticmethod
    def featurize(row, state_keys):
        return featurize_fac(row, state_keys)

    def __init__(self):
        self.state_keys = None
        self.XS = self.XF = self.Y = self.M = None
        self.full = self.st = None
        self.pairs = []
        self.batches = 0
        self.load()

    def load(self):
        if (OUT / (self.NAME + "_buffer.npz")).is_file() and (OUT / (self.NAME + "_model.pt")).is_file():
            import torch
            with np.load(OUT / (self.NAME + "_buffer.npz"), allow_pickle=True) as b:
                self.XS, self.XF, self.Y, self.M = (b[k].astype(np.float32) for k in ("XS", "XF", "Y", "M"))
                self.state_keys = list(b["state_keys"])
                self.batches = int(b["batches"])
            ck = torch.load(OUT / (self.NAME + "_model.pt"), weights_only=False)
            if list(ck.get("targets", [])) != TARGETS or tuple(ck.get("opt_num", ())) != self.OPTS:
                self.__init_empty()
                return
            self.full = Net(self.XF.shape[1], len(TARGETS))
            self.st = Net(self.XS.shape[1], len(TARGETS))
            self.full.load(ck["full"])
            self.st.load(ck["state"])
            self.pairs = ck.get("pairs", [])

    def __init_empty(self):
        self.state_keys = None
        self.XS = self.XF = self.Y = self.M = None
        self.full = self.st = None
        self.pairs = []
        self.batches = 0

    def save(self, buffer=False):
        import torch
        if self.full is None:
            return
        if buffer or self.batches % BUFFER_EVERY == 0:
            np.savez(OUT / (self.NAME + "_buffer.tmp.npz"), XS=self.XS, XF=self.XF, Y=self.Y, M=self.M,
                     state_keys=np.array(self.state_keys), batches=self.batches)
            replace_retry(OUT / (self.NAME + "_buffer.tmp.npz"), OUT / (self.NAME + "_buffer.npz"))
        torch.save({"full": self.full.state(), "state": self.st.state(), "targets": TARGETS,
                    "opt_num": self.OPTS, "pairs": self.pairs}, OUT / (self.NAME + "_model.pt.tmp"))
        replace_retry(OUT / (self.NAME + "_model.pt.tmp"), OUT / (self.NAME + "_model.pt"))

    def trust(self):
        if len(self.pairs) < TRUST_MIN:
            return 0.0
        a = np.array(self.pairs)
        if a[:, 0].std() == 0 or a[:, 1].std() == 0:
            return 0.0
        return round(max(0.0, float(np.corrcoef(a[:, 0], a[:, 1])[0, 1])), 3)

    def learn(self, source, g, first_touch, rows):
        if self.state_keys is not None and g["state_keys"] != self.state_keys:
            self.__init_empty()
        if self.state_keys is None:
            self.state_keys = g["state_keys"]
        xs, xf, ys, ms = [], [], [], []
        for r in rows:
            y, m = target_vec(r)
            if not any(m):
                continue
            s, f = self.featurize(r, self.state_keys)
            xs.append(s)
            xf.append(f)
            ys.append(y)
            ms.append(m)
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
            w = np.array([OBJECTIVE.get(t, 0.0) for t in TARGETS])
            ym, ysd = self.full.ym, self.full.ys
            zf, zs, zy = (pf - ym) / ysd, (ps - ym) / ysd, (Y - ym) / ysd
            for i in range(len(Y)):
                mm = M[i] * (w != 0)
                if mm.any():
                    self.pairs.append((float(((zf[i] - zs[i]) * w * mm).sum()),
                                       float(((zy[i] - zs[i]) * w * mm).sum())))
            self.pairs = self.pairs[-TRUST_KEEP:]
            rec["trust"] = self.trust()
        if self.XF is None:
            new_from = 0
            self.XS, self.XF, self.Y, self.M = XS, XF, Y, M
            self.full = Net(XF.shape[1], len(TARGETS))
            self.st = Net(XS.shape[1], len(TARGETS))
        else:
            new_from = len(self.Y)
            self.XS, self.XF = np.vstack([self.XS, XS]), np.vstack([self.XF, XF])
            self.Y, self.M = np.vstack([self.Y, Y]), np.vstack([self.M, M])
        rec["loss_full"] = self.full.train(self.XF, self.Y, self.M, new_from, STEPS_PER_ROW)
        rec["loss_state"] = self.st.train(self.XS, self.Y, self.M, new_from, STEPS_PER_ROW)
        rec["total_rows"] = int(len(self.Y))
        self.batches += 1
        if self.batches % RESET_EVERY == 0:
            self.full.shrink_perturb()
            self.st.shrink_perturb()
        with open(OUT / "metrics.jsonl", "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec) + "\n")
        self.save()
        return rec


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


DEC_HEADS = (ComHead, TechHead)   # parsed by decisions.head_rows_of(tag)


class Trainer:
    def __init__(self):
        OUT.mkdir(parents=True, exist_ok=True)
        seen = json.loads((OUT / "seen.json").read_text()) if (OUT / "seen.json").is_file() else {}
        self.seen_dirs = set(seen.get("dirs", []))
        self.used = {k: set(map(tuple, v)) for k, v in seen.get("used", {}).items()}
        self.used_at = seen.get("used_at", {k: time.time() for k in self.used})
        self.state_keys = None
        self.XS = self.XF = self.Y = self.M = None
        self.full = self.st = None
        self.batches = 0
        self.since_export = 0
        self.exported = 0
        self.logger = {}
        self.trust_pairs = {}   # kind -> [(net says the decision adds, it actually added)], unseen games
        self.fac = FacHead()
        self.post = PostHead()
        self.heads = {h.NAME: h() for h in DEC_HEADS}
        self.parsed_at = {}
        self.load()

    def load(self):
        if (OUT / "buffer.npz").is_file() and (OUT / "model.pt").is_file():
            import torch
            # closed before anything can archive it: Windows will not move an open file
            with np.load(OUT / "buffer.npz", allow_pickle=True) as b:
                self.XS, self.XF, self.Y, self.M = (b[k].astype(np.float32) for k in ("XS", "XF", "Y", "M"))
                self.state_keys = list(b["state_keys"])
                self.batches = int(b["batches"])
            ck = torch.load(OUT / "model.pt", weights_only=False)
            if list(ck.get("targets", [])) != TARGETS or tuple(ck.get("opt_num", ())) != OPT_NUM:
                self.fresh_start("this trainer predicts different outcomes or reads different options")
                return
            self.full = Net(self.XF.shape[1], len(TARGETS))
            self.st = Net(self.XS.shape[1], len(TARGETS))
            self.full.load(ck["full"])
            self.st.load(ck["state"])

    def fresh_start(self, why):
        """Archive the current net and its history, then learn from nothing.
        Games already used stay used: the old rows are kept with the archive."""
        dest = reset()
        print("fresh net (%s); the old one is kept in %s" % (why, dest), flush=True)
        self.state_keys = None
        self.XS = self.XF = self.Y = self.M = None
        self.full = self.st = None
        self.batches = 0
        self.since_export = 0
        self.trust_pairs = {}

    def save(self, buffer=None):
        """Model every call; the (large) buffer every BUFFER_EVERY batches or
        when asked. A game's used-decision list is dropped USED_KEEP_S after it
        was last touched: by then the game has finished and is in seen_dirs."""
        import torch
        now = time.time()
        for fp in [k for k, t in self.used_at.items() if now - t > USED_KEEP_S]:
            self.used.pop(fp, None)
            self.used_at.pop(fp, None)
        seen = {"dirs": sorted(self.seen_dirs), "used": {k: sorted(v) for k, v in self.used.items()},
                "used_at": self.used_at}
        tmp = OUT / "seen.json.tmp"
        tmp.write_text(json.dumps(seen))
        replace_retry(tmp, OUT / "seen.json")
        if self.full is None:
            return
        if buffer or (buffer is None and self.batches % BUFFER_EVERY == 0):
            np.savez(OUT / "buffer.tmp.npz", XS=self.XS, XF=self.XF, Y=self.Y, M=self.M,
                     state_keys=np.array(self.state_keys), batches=self.batches)
            replace_retry(OUT / "buffer.tmp.npz", OUT / "buffer.npz")
        torch.save({"full": self.full.state(), "state": self.st.state(), "targets": TARGETS,
                    "state_keys": self.state_keys, "kinds": KINDS, "opt_num": OPT_NUM,
                    "trust_pairs": self.trust_pairs}, OUT / "model.pt.tmp")
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
        if self.state_keys is not None and g["state_keys"] != self.state_keys:
            self.fresh_start("the record's state layout changed")
        if self.state_keys is None:
            self.state_keys = g["state_keys"]
        xs, xf, ys, ms, decided, kinds = [], [], [], [], [], []
        for _fp, _key, r in items:
            y, m = target_vec(r)
            if not any(m):
                continue
            s, f = featurize(r, self.state_keys)
            xs.append(s)
            xf.append(f)
            ys.append(y)
            ms.append(m)
            ci = r["chosen"]
            kinds.append(r["opts"][ci].get("kind") if 0 <= ci < len(r["opts"]) else None)
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
            self.note_trust(pf, ps, Y, M, kinds)
            rec["trust"] = self.trust()
        self.status("training", source=source)
        if self.XF is None:
            new_from = 0
            self.XS, self.XF, self.Y, self.M = XS, XF, Y, M
            self.full = Net(XF.shape[1], len(TARGETS))
            self.st = Net(XS.shape[1], len(TARGETS))
        else:
            new_from = len(self.Y)
            self.XS, self.XF = np.vstack([self.XS, XS]), np.vstack([self.XF, XF])
            self.Y, self.M = np.vstack([self.Y, Y]), np.vstack([self.M, M])
        t0 = time.time()
        rec["loss_full"] = self.full.train(self.XF, self.Y, self.M, new_from, STEPS_PER_ROW)
        rec["loss_state"] = self.st.train(self.XS, self.Y, self.M, new_from, STEPS_PER_ROW)
        rec["train_s"] = round(time.time() - t0, 2)
        rec["total_rows"] = int(len(self.Y))
        self.batches += 1
        if self.batches % RESET_EVERY == 0:
            self.full.shrink_perturb()
            self.st.shrink_perturb()
            rec["reset"] = True
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

    def note_trust(self, pf, ps, Y, M, kinds):
        """For each chosen option's kind, pair what the DECISION adds in the
        net's eyes (FULL minus STATE prediction of the objective) with what it
        actually added (outcome minus the STATE prediction). Their correlation
        is how well the net knows which option is better -- on unseen games."""
        w = np.array([OBJECTIVE.get(t, 0.0) for t in TARGETS])
        ym, ys = self.full.ym, self.full.ys
        zf, zs, zy = (pf - ym) / ys, (ps - ym) / ys, (Y - ym) / ys
        for i, kind in enumerate(kinds):
            m = M[i] * (w != 0)
            if kind is None or not m.any():
                continue
            pred = float(((zf[i] - zs[i]) * w * m).sum())
            real = float(((zy[i] - zs[i]) * w * m).sum())
            q = self.trust_pairs.setdefault(kind, [])
            q.append((pred, real))
            if len(q) > TRUST_KEEP:
                del q[: len(q) - TRUST_KEEP]

    def trust(self):
        out = {}
        for kind in KINDS:
            q = self.trust_pairs.get(kind, [])
            if len(q) < TRUST_MIN:
                out[kind] = 0.0
                continue
            a = np.array(q)
            if a[:, 0].std() == 0 or a[:, 1].std() == 0:
                out[kind] = 0.0
                continue
            out[kind] = round(max(0.0, float(np.corrcoef(a[:, 0], a[:, 1])[0, 1])), 3)
        return out

    def export(self):
        text = export_as(self.full, self.state_keys, self.batches, self.trust(), self.fac, self.post, self.heads)
        n = 0
        for p in export_targets():
            tmp = p.with_suffix(".tmp")
            tmp.write_text(text, encoding="utf-8")
            replace_retry(tmp, p)
            n += 1
        self.since_export = 0
        self.exported += 1
        return n

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
            h = g.get("heads", {}).get(name)
            if h:
                out.append(self.learn_head(head, h["keys"], h["rows"],
                                           decisions.head_rows_of(str(path), g, name), source, g, final))
        return out

    def learn_head(self, head, own_keys, raw, labelled, source, g, final):
        """One decision head's rows of one parsed game: matured (or all, when
        final), not used before, keyed per team by its first three decisions."""
        if not own_keys or g["state_keys"] is None or SCHEMA_STATE not in g["state_keys"]:
            return None
        if head.post_keys is not None and head.post_keys != own_keys:
            head._FacHead__init_empty()
        head.post_keys = own_keys
        first = {}
        for r in sorted(raw, key=lambda q: int(q[0])):
            t = int(r[1])
            if len(first.setdefault(t, [])) < 3:
                first[t].append(r[0])
        fps = {t: "%s|%d|%s" % (head.NAME, t, "|".join(v)) for t, v in first.items()}
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
        for _t, key, d in self.finished_games():
            g = decisions.parse(str(d))
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
    if not all(k in head for k in ("NNW_TRUST", "NNF_TRUST", "NNP_TRUST", "NNC_TRUST", "NNT_TRUST", "NNI_ON")):
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
    if not any((OUT / n).is_file() for n in names):
        return None
    dest = OUT.parent / "nn-archive" / time.strftime("%Y%m%d-%H%M%S")
    dest.mkdir(parents=True, exist_ok=True)
    for name in names:
        p = OUT / name
        if p.is_file():
            replace_retry(p, dest / name)
    return dest


def main(argv):
    import torch
    torch.set_num_threads(2)
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
    tr = Trainer()
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
            tr.status("watching", live=n_live)
            time.sleep(POLL_S)
    except KeyboardInterrupt:
        tr.save(buffer=True)
        tr.status("stopped")
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
