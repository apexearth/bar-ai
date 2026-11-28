#!/usr/bin/env python3
"""How much in-contact data the rules army gives: per built game, the rules side's recorded orders (decisions) by its
armed mobile units while in contact (an armed enemy unit within the unit's weapon range + 200, ground truth at the
10-s sample at or before the order), by kind, and how many attacks resolve to a target enemy (a unit or building
within 64 of the order's point at that sample).

    python tools/armynet/contact_inventory.py --mvr-log runtime/armynet/mvr-mvr-g2.log runtime/armynet/own-games/mvr-g2
    python tools/armynet/contact_inventory.py --both runtime/armynet/own-games/rules-r2      (rules on both sides)
"""
import argparse
import glob
import os
import sys
from collections import Counter
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import Game  # noqa: E402

CLS_STATIC, CLS_ARMY, CLS_AIR = 0, 3, 4
KINDS = {0: "stop", 1: "move", 2: "fight", 3: "attack", 4: "fight2", 5: "patrol"}
PAD, TGT_R, STEP = 200.0, 64.0, 300


def side_counts(path, rules_allies):
    g = Game(path, rng=np.random.default_rng(0))
    d = g.decisions
    c = Counter()
    if not len(d):
        return c
    steps = (d[:, 0].astype(np.int64) // STEP) * STEP
    for f in np.unique(steps):
        rows = g.rows_at(int(f))
        if not len(rows):
            continue
        ru = g.units[rows]
        rcls, rally, rdef, ruid = g.ucls[rows], g.ually[rows], g.udef[rows], g.uid[rows].astype(np.int64)
        built = ru[:, 9] >= 1.0
        armed = built & np.isin(rcls, (CLS_ARMY, CLS_AIR)) & ((g.d_g[rdef] + g.d_a[rdef]) > 0)
        pos = {int(u): i for i, u in enumerate(ruid)}
        for i in np.nonzero(steps == f)[0]:
            uid, kind = int(d[i, 3]), int(d[i, 4])
            j = pos.get(uid)
            if j is None or not armed[j] or int(rally[j]) not in rules_allies:
                continue
            c["orders"] += 1
            foe = (rally != rally[j]) & (rally >= 0) & built
            fa = foe & armed
            reach = float(g.d_range[rdef[j]]) + PAD
            if not fa.any() or ((ru[fa, 4] - ru[j, 4]) ** 2 + (ru[fa, 5] - ru[j, 5]) ** 2).min() > reach * reach:
                continue
            c["contact"] += 1
            c["k:" + KINDS.get(kind, str(kind))] += 1
            if kind == 3:
                dd = (ru[foe, 4] - d[i, 5]) ** 2 + (ru[foe, 5] - d[i, 6]) ** 2
                if len(dd) and dd.min() <= TGT_R * TGT_R:
                    c["attack:" + ("building" if rcls[foe][int(np.argmin(dd))] == CLS_STATIC else "unit")] += 1
                else:
                    c["attack:ground"] += 1
    return c


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("roots", nargs="+")
    ap.add_argument("--mvr-log", default="")
    ap.add_argument("--both", action="store_true", help="every side is the rules army")
    a = ap.parse_args()
    mt = {}
    for lg in filter(None, a.mvr_log.split(",")):
        for ln in open(lg, encoding="utf-8"):
            p = ln.split()
            if len(p) >= 7 and p[0] == "seed":
                mt[Path(p[6]).name] = int(p[3].lstrip("t"))
    tot, sides = Counter(), 0
    for root in a.roots:
        for p in sorted(glob.glob(os.path.join(root, "**", "*.npz"), recursive=True)):
            z = np.load(p)
            play = {int(v) for v in z["allies"]}
            teams = {int(t[0]): int(t[1]) for t in z["teams"] if int(t[1]) in play}
            if a.both:
                rules = set(teams.values())
            else:
                m = mt.get(Path(p).stem)
                if m is None:
                    continue
                rules = {al for t, al in teams.items() if al != teams[m]}
            c = side_counts(p, rules)
            sides += len(rules)
            tot.update(c)
    n = tot["contact"] or 1
    print("%d rules side-games; armed-unit orders %d, in contact %d (%.3f); in contact by kind: %s" % (
        sides, tot["orders"], tot["contact"], tot["contact"] / max(tot["orders"], 1),
        "  ".join("%s %.3f" % (k[2:], v / n) for k, v in sorted(tot.items()) if k.startswith("k:"))))
    print("attacks in contact: on a building %d, on a unit %d, on the ground / unresolved %d" % (
        tot["attack:building"], tot["attack:unit"], tot["attack:ground"]))


if __name__ == "__main__":
    main()
