"""The learned job risk (todo/learn-from-each-decision.md): fit, test and export the chance a build job fails.

    python tools/risknet.py fit <ledger.jsonl> [...]           # fit, report on held-out games, write runtime/risk/model.json
    python tools/risknet.py export [--out <riskweights.as>]    # the fitted model as AngelScript arrays

Two heads from what the AI knows when it prices a want: P(frame) -- the building dies before it is finished -- and
P(builder) -- the constructor is killed on the job. Inputs are only what the game has before the exposure charge:
the want's kind, the state vector (NnState, 101 features), the site's loss rate (ExpectedLossAt / metal), the walk,
how far forward, the site's loss history, the def's metal, energy and build time, its defensive power, how many we own,
its tier, and the builder's metal. The model is logistic per head: one dot product per want plus the state's share
once per tick (an election calls it; docs/working.md prices that).
"""
import argparse
import json
import math
import os
import random
import sys

import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import log_loss, roc_auc_score

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ledger_calib as lc  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "runtime", "risk")
KINDS = ["mex", "mexup", "energy", "protect", "nano", "plant", "convert", "sense", "airdef", "tech", "geo", "super"]
OPT = ["m", "cm", "ce", "bt", "walk", "dPow", "ownN", "tierO", "fwd", "siteLoss"]
LOGS = {"m", "cm", "ce", "bt", "walk", "siteLoss"}


def opt_feats(o, rate, builder_m):
    v = []
    for n in OPT:
        x = max(0.0, float(o[n])) if n in LOGS else float(o[n])
        v.append(math.log1p(x) if n in LOGS else x)
    v.append(math.log(rate + 1e-6))
    v.append(math.log1p(builder_m))
    return v


def load(paths):
    X, yf, yb, games, names = [], [], [], [], None
    for path in paths:
        with open(path, encoding="utf-8") as fh:
            nm = json.loads(fh.readline())["schema"]
            if names is None:
                names = nm
            elif nm["state"] != names["state"]:
                raise SystemExit("%s: a different state layout" % path)
            for ln in fh:
                r = json.loads(ln)
                d = r.get("decision") or {}
                o = d.get("opt")
                k = d.get("kind")
                if not o or "state" not in d or k not in KINDS:
                    continue
                secs, failed = lc.exposure(r, d)
                if secs is None or secs < 0:
                    continue
                try:
                    rate = max(0.0, float(o["risk"])) / max(1.0, float(o["m"]))
                    of = opt_feats(o, rate, d.get("builderCost", 0.0))
                except (KeyError, ValueError):
                    continue
                X.append([1.0 if k == q else 0.0 for q in KINDS] + of + list(d["state"]))
                # danger only: a frame we reclaimed or left to decay was not taken by the enemy (11-04: 42% of them)
                how = r.get("frameHow") or ("own" if r.get("own") else ("decayed" if r.get("by") in ("?", None) else "enemy"))
                yf.append(1 if (r.get("frameLost") and how == "enemy") else 0)
                yb.append(1 if r.get("builderDied") else 0)
                games.append(os.path.basename(path) + "/" + r["game"])
    return names, np.array(X), np.array(yf), np.array(yb), games


def split(games, seed=7):
    g = sorted(set(games))
    random.Random(seed).shuffle(g)
    test = set(g[: max(1, len(g) // 5)])
    return np.array([x in test for x in games])


def fit(paths):
    names, X, yf, yb, games = load(paths)
    te = split(games)
    tr = ~te
    mu = X[tr].mean(0)
    sd = X[tr].std(0)
    sd[sd < 1e-6] = 1.0
    nk = len(KINDS)
    mu[:nk], sd[:nk] = 0.0, 1.0
    Z = np.clip((X - mu) / sd, -8, 8)
    print("jobs %d (held out %d in %d games); frame lost %.1f%%, builder killed %.1f%%" % (
        len(X), int(te.sum()), len(set(np.array(games)[te])), 100 * yf.mean(), 100 * yb.mean()))
    model = {"kinds": KINDS, "opt": OPT + ["logRate", "logBuilderM"], "state": names["state"],
             "mu": mu.tolist(), "sd": sd.tolist(), "heads": {}}
    print("\nhead     held-out    logistic (in game)      boosted trees (reference)   base rate")
    for head, y in (("frame", yf), ("builder", yb)):
        lr = LogisticRegression(max_iter=4000, C=0.3).fit(Z[tr], y[tr])
        p = lr.predict_proba(Z[te])[:, 1]
        gb = HistGradientBoostingClassifier(max_iter=250, learning_rate=0.08, random_state=7).fit(Z[tr], y[tr])
        q = gb.predict_proba(Z[te])[:, 1]
        print("%-8s AUC/loss   %.3f / %.4f         %.3f / %.4f              %.1f%%" % (
            head, roc_auc_score(y[te], p), log_loss(y[te], p), roc_auc_score(y[te], q), log_loss(y[te], q),
            100 * y[te].mean()))
        model["heads"][head] = {"w": lr.coef_[0].tolist(), "b": float(lr.intercept_[0]),
                                "auc": round(float(roc_auc_score(y[te], p)), 4),
                                "loss": round(float(log_loss(y[te], p)), 5)}
    os.makedirs(OUT, exist_ok=True)
    model["fitted"] = {"jobs": int(len(X)), "from": [os.path.basename(p) for p in paths]}
    with open(os.path.join(OUT, "model.json"), "w", encoding="utf-8") as fh:
        json.dump(model, fh)
    print("\nwrote", os.path.join(OUT, "model.json"))
    return model


def fit_model(paths):
    """the in-game model on every job in paths, no held-out split and no reference: what the loop exports"""
    names, X, yf, yb, games = load(paths)
    mu = X.mean(0)
    sd = X.std(0)
    sd[sd < 1e-6] = 1.0
    nk = len(KINDS)
    mu[:nk], sd[:nk] = 0.0, 1.0
    Z = np.clip((X - mu) / sd, -8, 8)
    model = {"kinds": KINDS, "opt": OPT + ["logRate", "logBuilderM"], "state": names["state"],
             "mu": mu.tolist(), "sd": sd.tolist(), "heads": {},
             "fitted": {"jobs": int(len(X)), "games": len(set(games)), "from": [os.path.basename(p) for p in paths]}}
    for head, y in (("frame", yf), ("builder", yb)):
        lr = LogisticRegression(max_iter=4000, C=0.3).fit(Z, y)
        model["heads"][head] = {"w": lr.coef_[0].tolist(), "b": float(lr.intercept_[0])}
    return model


def score(model, paths):
    """log-loss and AUC of a model on the jobs in paths (games it was not fitted on)"""
    _, X, yf, yb, games = load(paths)
    if len(X) == 0:
        return None
    nk = len(model["kinds"])
    Z = np.array(X, dtype=np.float64)
    Z[:, nk:] = np.clip((Z[:, nk:] - np.array(model["mu"][nk:])) / np.array(model["sd"][nk:]), -8, 8)
    out = {"jobs": int(len(X)), "games": len(set(games))}
    for head, y in (("frame", yf), ("builder", yb)):
        h = model["heads"][head]
        p = np.clip(1.0 / (1.0 + np.exp(-(h["b"] + Z @ np.array(h["w"])))), 1e-5, 1 - 1e-5)
        out[head] = {"loss": round(float(log_loss(y, p, labels=[0, 1])), 5),
                     "auc": round(float(roc_auc_score(y, p)), 4) if 0 < y.sum() < len(y) else None,
                     "rate": round(float(y.mean()), 4), "pred": round(float(p.mean()), 4)}
    return out


def fnum(x):
    """an AngelScript float literal: it rejects `0f` and `1e-05f`, so a mantissa always carries a point"""
    if not math.isfinite(x):
        raise SystemExit("non-finite weight %r" % x)
    s = "%.7g" % x
    if "e" in s:
        mant, exp = s.split("e")
        s = (mant if "." in mant else mant + ".0") + "e" + exp
    elif "." not in s:
        s += ".0"
    return s + "f"


def fa(xs):
    return "{" + ", ".join(fnum(x) for x in xs) + "}"


def export(out, m=None):
    if m is None:
        m = json.load(open(os.path.join(OUT, "model.json"), encoding="utf-8"))
    nk, no, ns = len(m["kinds"]), len(m["opt"]), len(m["state"])
    lines = ["namespace Market {", "",
             "// Generated by tools/risknet.py export from runtime/risk/model.json (%d jobs). Do not edit." % m["fitted"]["jobs"],
             'const string RISK_STATE = "%s";' % ",".join(m["state"]),
             'const string RISK_KINDS = "%s";' % ",".join(m["kinds"]),
             "const int RISK_NK = %d;" % nk, "const int RISK_NO = %d;" % no, "const int RISK_NS = %d;" % ns,
             "const array<float> RISK_MU = %s;" % fa(m["mu"]), "const array<float> RISK_SD = %s;" % fa(m["sd"])]
    for head in ("frame", "builder"):
        h = m["heads"][head]
        lines.append("const array<float> RISK_W_%s = %s;" % (head.upper(), fa(h["w"])))
        lines.append("const float RISK_B_%s = %s;" % (head.upper(), fnum(h["b"])))
    lines += ["", "}  // namespace Market", ""]
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))
    print("wrote %s (%d + %d + %d inputs per head)" % (out, nk, no, ns))


def predict(model, x):
    nk = len(model["kinds"])
    z = np.array(x, dtype=np.float64)
    z[nk:] = np.clip((z[nk:] - np.array(model["mu"][nk:])) / np.array(model["sd"][nk:]), -8, 8)
    out = []
    for head in ("frame", "builder"):
        h = model["heads"][head]
        out.append(1.0 / (1.0 + math.exp(-(h["b"] + float(np.dot(h["w"], z))))))
    return out


def check(paths):
    """the game's risk-x samples recomputed from their own inputs: the export is exact or it is wrong"""
    import re
    model = json.load(open(os.path.join(OUT, "model.json"), encoding="utf-8"))
    rx = re.compile(r"apex: risk-x t=\d+ p=([-\d.]+),([-\d.]+) \| (\S+)")
    worst, n = 0.0, 0
    for p in paths:
        for ln in open(os.path.join(p, "infolog.txt") if os.path.isdir(p) else p, encoding="utf-8", errors="replace"):
            m = rx.search(ln)
            if not m:
                continue
            x = [float(v) for v in m.group(3).split(",")]
            if len(x) != len(model["mu"]):
                raise SystemExit("risk-x has %d inputs, the model %d" % (len(x), len(model["mu"])))
            q = predict(model, x)
            worst = max(worst, abs(q[0] - float(m.group(1))), abs(q[1] - float(m.group(2))))
            n += 1
    print("risk-x samples %d, largest |game - model| %.5f %s" % (n, worst, "OK" if (n and worst < 0.002) else "MISMATCH"))
    return n > 0 and worst < 0.002


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["fit", "export", "check"])
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--out", default=os.path.join(REPO, "ai", "Unstable", "game-side", "script", "standard", "manager",
                                                  "brain", "market", "riskweights.as"))
    a = ap.parse_args()
    if a.cmd == "fit":
        fit(a.paths)
    elif a.cmd == "check":
        sys.exit(0 if check(a.paths) else 1)
    else:
        export(a.out)


if __name__ == "__main__":
    main()
