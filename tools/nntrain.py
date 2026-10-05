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
LOGGED = ("lostNear", "lostFar", "lostAir", "lostStatic", "lostMobile", "reclaim")
SINGLE = ("done", "survived")    # one value per decision, not per horizon
TARGETS = [(h, k) for h in (1, 3, 5) for k in PER_H] + [(k, k) for k in SINGLE]
SCHEMA_OPT = "forced"   # an option field only the current record (v5) carries
Y_FLOOR = 0.1           # a rare outcome must not get a near-zero spread and swamp the loss
DECIDED = ("draw", "ladder")   # rows where an option was chosen on value, not forced
# What "better" means when the net plays, in units of each outcome's spread.
# A stated default until he picks one (docs/35).
OBJECTIVE = {(5, "dEco"): 1.0, (5, "dMInc"): 0.25, (5, "dEInc"): 0.25, (5, "lnD"): 0.5,
             (5, "lostNear"): -0.5, ("done", "done"): 0.25, ("survived", "survived"): 0.25}
# the dashboard's headline accuracy: the outcomes the net is steered by
HEADLINE = [i for i, t in enumerate(TARGETS) if t in OBJECTIVE]
HIDDEN = 32
DROPOUT = 0.1
MIN_BATCH = 150        # matured decisions before a live game is learned from
STEPS_PER_ROW = 2      # passes over each new batch (each mixed with as many old rows)
RESET_EVERY = 40       # batches between partial resets (shrink 0.8, perturb 0.2)
EXPORT_ROWS = 800      # new rows between weight exports
POLL_S = 5
LIVE_IDLE_S = 90       # a write dir untouched this long is not a running game
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
        self.xm = self.xs = self.ym = self.ys = None

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
        self.model.eval()
        with self.torch.no_grad():
            z = self.model(self._x(X)).numpy()
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
                    b = t.cat([b, t.randint(0, new_from, (len(b),))])
                err = ((self.model(Xt[b]) - Yt[b]) ** 2) * Mt[b]
                loss = err.sum() / (Mt[b].sum() + 1e-6)
                self.opt.zero_grad()
                loss.backward()
                self.opt.step()
                tot += float(loss)
                cnt += 1
        self.model.eval()
        return tot / max(cnt, 1)

    def shrink_perturb(self):
        t = self.torch
        fresh = Net(self.model[0].in_features, self.model[-1].out_features).model
        with t.no_grad():
            for p, q in zip(self.model.parameters(), fresh.parameters()):
                p.mul_(0.8).add_(0.2 * q)

    def state(self):
        return {"model": self.model.state_dict(), "opt": self.opt.state_dict(),
                "xm": self.xm, "xs": self.xs, "ym": self.ym, "ys": self.ys}

    def load(self, st):
        self.model.load_state_dict(st["model"])
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


def export_as(net, state_keys, games):
    """The FULL net as nnweights.as: first layer, second layer, and the output
    layer folded through OBJECTIVE into one score (in units of target spread)."""
    sd = net.model.state_dict()
    w1, b1 = sd["0.weight"].numpy(), sd["0.bias"].numpy()
    w2, b2 = sd["3.weight"].numpy(), sd["3.bias"].numpy()
    w3, b3 = sd["6.weight"].numpy(), sd["6.bias"].numpy()
    obj = np.array([OBJECTIVE.get(t, 0.0) for t in TARGETS])
    wo, bo = obj @ w3, float(obj @ b3)
    s, o = len(state_keys), w1.shape[1] - len(state_keys)
    return "\n".join([
        "namespace Market {", "",
        "// GENERATED by tools/nntrain.py -- the deployed copy only; do not commit.",
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
        "const float NNW_BO = %.7ff;" % bo, "",
        "}  // namespace Market", ""])


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


class Trainer:
    def __init__(self):
        OUT.mkdir(parents=True, exist_ok=True)
        seen = json.loads((OUT / "seen.json").read_text()) if (OUT / "seen.json").is_file() else {}
        self.seen_dirs = set(seen.get("dirs", []))
        self.used = {k: set(map(tuple, v)) for k, v in seen.get("used", {}).items()}
        self.state_keys = None
        self.XS = self.XF = self.Y = self.M = None
        self.full = self.st = None
        self.batches = 0
        self.since_export = 0
        self.exported = 0
        self.logger = {}
        self.parsed_at = {}
        self.load()

    def load(self):
        if (OUT / "buffer.npz").is_file() and (OUT / "model.pt").is_file():
            import torch
            # closed before anything can archive it: Windows will not move an open file
            with np.load(OUT / "buffer.npz", allow_pickle=True) as b:
                self.XS, self.XF, self.Y, self.M = b["XS"], b["XF"], b["Y"], b["M"]
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

    def save(self):
        import torch
        seen = {"dirs": sorted(self.seen_dirs), "used": {k: sorted(v) for k, v in self.used.items()}}
        (OUT / "seen.json").write_text(json.dumps(seen))
        if self.full is None:
            return
        np.savez(OUT / "buffer.tmp.npz", XS=self.XS, XF=self.XF, Y=self.Y, M=self.M,
                 state_keys=np.array(self.state_keys), batches=self.batches)
        replace_retry(OUT / "buffer.tmp.npz", OUT / "buffer.npz")
        torch.save({"full": self.full.state(), "state": self.st.state(), "targets": TARGETS,
                    "state_keys": self.state_keys, "kinds": KINDS, "opt_num": OPT_NUM}, OUT / "model.pt.tmp")
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
        if g["state_keys"] is None or g["opt_keys"] is None or SCHEMA_OPT not in g["opt_keys"]:
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
                if r["f"] + 5 * decisions.FPM > g["last"]:
                    continue
                # survival needs 5 minutes after the FINISH: hold the row until known
                if r["y"].get("done") == 1 and r["y"].get("survived") is None:
                    continue
            out.append((fp, key, r))
        return first_touch, out

    def learn(self, source, g, first_touch, items):
        if self.state_keys is not None and g["state_keys"] != self.state_keys:
            self.fresh_start("the record's state layout changed")
        if self.state_keys is None:
            self.state_keys = g["state_keys"]
        xs, xf, ys, ms, decided = [], [], [], [], []
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
            decided.append(r["dm"] in DECIDED and r["pick"] == 0 and 0 <= ci < len(r["opts"])
                           and not r["opts"][ci].get("forced"))
        if not xs:
            return None
        XS, XF = np.array(xs), np.array(xf)
        Y, M = np.array(ys), np.array(ms)
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
        self.since_export += len(items)
        if self.since_export >= EXPORT_ROWS:
            rec["exported"] = self.export()
        with open(OUT / "metrics.jsonl", "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec) + "\n")
        self.save()
        return rec

    def export(self):
        text = export_as(self.full, self.state_keys, self.batches)
        n = 0
        for p in export_targets():
            tmp = p.with_suffix(".tmp")
            tmp.write_text(text, encoding="utf-8")
            replace_retry(tmp, p)
            n += 1
        self.since_export = 0
        self.exported += 1
        return n

    def poll(self):
        did = []
        for _t, key, d in self.finished_games():
            g = decisions.parse(str(d))
            first, items = self.rows_from(g, d, final=True)
            self.seen_dirs.add(key)
            if items:
                did.append(self.learn(key, g, first, items))
        live = self.live_games()
        for wd, files in live:
            self.parsed_at[wd] = time.time()
            g = decisions.parse(str(wd), files)
            first, items = self.rows_from(g, wd, final=False)
            if len(items) >= MIN_BATCH:
                did.append(self.learn("live:" + wd.name, g, first, items))
        if did:
            self.save()
        # a deploy writes the repo's empty net over ours: put it back
        if self.full is not None and any(not stale_ok(p, self.state_keys) for p in export_targets()):
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


def stale_ok(p, state_keys):
    """The deployed weights are this net's layout (a deploy writes the empty net;
    an older trainer may have left a net for another record)."""
    try:
        with open(p, encoding="utf-8") as fh:
            head = fh.read(4000)
    except OSError:
        return False
    return "NNW_ON = true" in head and ('NNW_STATE = "%s"' % ",".join(state_keys)) in head


def fresh(root):
    try:
        return [d for d in root.iterdir() if d.is_dir() and not d.name.startswith("_")
                and d.stat().st_mtime >= LOGGER_SINCE]
    except OSError:
        return []


def reset():
    """Start a fresh net. The old one and its whole history move to
    runtime/nn-archive/<stamp>/, never deleted: copy them back to restore."""
    names = ("metrics.jsonl", "status.json", "model.pt", "buffer.npz", "seen.json")
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
    tr = Trainer()
    if "--export" in argv:
        if tr.full is None:
            print("no net yet")
            return 1
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
                tr.status("stopped")
                return 0
            tr.status("watching", live=n_live)
            time.sleep(POLL_S)
    except KeyboardInterrupt:
        tr.status("stopped")
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
