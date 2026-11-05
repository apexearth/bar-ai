"""Learn the chance a job fails from what was known when it was chosen (todo/learn-from-each-decision.md).

    python tools/ledger_risk.py runtime/ledger/<run>.jsonl

A job fails when its frame dies unfinished or its builder is killed on it. Three predictors, scored on games held out
of the fit (split by game, so no game is in both):
  price      1 - exp(-rate x seconds exposed), the market's own risk as it stands (its AUC ranks by the rate alone)
  price-fit  a logistic on log(rate) and the job type: the price, recalibrated (no exposure: it would leak the outcome)
  context    the same plus every decision-time state feature and the chosen option's features
Log-loss (lower is better) and AUC (higher is better); then the context model's predictions by the cases he named.
"""
import json
import math
import random
import re
import sys

import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import log_loss, roc_auc_score

sys.path.insert(0, __file__.rsplit("\\", 1)[0].rsplit("/", 1)[0])
import ledger_calib as lc  # noqa: E402

OPT_NUM = ["value", "gain", "m", "t", "cm", "ce", "bt", "walk", "risk", "eta", "dPow", "ownN", "tierO", "fwd", "siteLoss"]


def load(path):
    rows = []
    with open(path, encoding="utf-8") as fh:
        names = json.loads(fh.readline())["schema"]
        for ln in fh:
            r = json.loads(ln)
            d = r.get("decision") or {}
            o = d.get("opt")
            if not o or "state" not in d or d.get("kind") not in lc.BUILD_KINDS:
                continue
            k = lc.cls(r["def"])
            if k is None or float(r.get("cost") or 0) < 1:
                continue
            secs, failed = lc.exposure(r, d)
            if secs is None or secs < 0:
                continue
            try:
                opt = [float(o[n]) for n in OPT_NUM]
            except (KeyError, ValueError):
                continue
            rate = max(0.0, float(o["risk"])) / max(1.0, float(o["m"]))
            rows.append((r["game"], k, rate, secs, failed, d["state"], opt, d.get("builderCost", 0.0)))
    return names, rows


def main(path):
    names, rows = load(path)
    classes = [c for c, _ in lc.CLASSES]
    games = sorted({r[0] for r in rows})
    random.Random(7).shuffle(games)
    test_g = set(games[: len(games) // 5])
    y = np.array([r[4] for r in rows], dtype=np.int32)
    rate = np.array([r[2] for r in rows])
    secs = np.array([r[3] for r in rows])
    onehot = np.array([[1.0 if r[1] == c else 0.0 for c in classes] for r in rows])
    base = np.column_stack([np.log(rate + 1e-6), onehot])   # no exposure: a failure ends it, so it would leak the outcome
    full = np.column_stack([base, np.array([r[5] for r in rows]), np.array([r[6] for r in rows]),
                            np.log1p(np.array([r[7] for r in rows]))])
    te = np.array([r[0] in test_g for r in rows])
    tr = ~te
    print("jobs %d (train %d, test %d games / %d jobs), failed %.1f%%" % (
        len(rows), int(tr.sum()), len(test_g), int(te.sum()), 100 * y.mean()))
    p_price = np.clip(1 - np.exp(-rate * secs), 1e-4, 1 - 1e-4)
    m1 = LogisticRegression(max_iter=2000).fit(base[tr], y[tr])
    p_fit = m1.predict_proba(base[te])[:, 1]
    m2 = HistGradientBoostingClassifier(max_iter=300, learning_rate=0.08, max_leaf_nodes=31, l2_regularization=1.0,
                                        random_state=7).fit(full[tr], y[tr])
    p_ctx = m2.predict_proba(full[te])[:, 1]
    print("\n held-out games      log-loss   AUC    mean predicted (observed %.1f%%)" % (100 * y[te].mean()))
    print("  %-12s      %8s   %.3f   (the rate alone, ranked)" % ("price rate", "-", roc_auc_score(y[te], rate[te])))
    for name, p in (("price", p_price[te]), ("price-fit", p_fit), ("context", p_ctx)):
        print("  %-12s      %.4f   %.3f   %.1f%%" % (name, log_loss(y[te], p), roc_auc_score(y[te], p), 100 * p.mean()))

    si = {n: i for i, n in enumerate(names["state"])}
    oi = {n: i for i, n in enumerate(OPT_NUM)}
    test_rows = [r for r, t in zip(rows, te) if t]
    print("\n the context model on held-out jobs, by his cases (observed / context model / the price)")
    groups = {}
    for r, pc, pp in zip(test_rows, p_ctx, p_price[te]):
        s, o = r[5], r[6]
        fwd = o[oi["fwd"]] > 0.2
        behind = s[si["army"]] < s[si["foeArmy"]]
        for key in ((r[1], "forward" if fwd else "home", "army behind" if behind else "army ahead"),):
            g = groups.setdefault(key, [0, 0.0, 0.0, 0.0])
            g[0] += 1
            g[1] += r[4]
            g[2] += pc
            g[3] += pp
    for key in sorted(groups):
        n, f, pc, pp = groups[key]
        if n >= 150:
            print("  %-10s %-8s %-12s n=%5d  failed %4.0f%%   model %4.0f%%   price %4.0f%%" % (
                key[0], key[1], key[2], n, 100 * f / n, 100 * pc / n, 100 * pp / n))


if __name__ == "__main__":
    main(sys.argv[1])
