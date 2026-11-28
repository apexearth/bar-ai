#!/usr/bin/env python3
"""Does the outcome weighting favour orders near home? Players' orders by how far forward they send units, with the
mean training weight and the mean z-scored outcome of each measure.

    python tools/armynet/weight_by_front.py [--games 80]

Forward: 0 at the side's own buildings' centre (over the game), 1 at the other side's.
"""
import glob
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import HORIZON_PICK, Game  # noqa: E402

NAMES = ["own 5s", "own 15s", "own 60s", "area 3m", "area 10m", "side 10m"]


def main(a):
    n = int(a[a.index("--games") + 1]) if "--games" in a else 80
    paths = sorted(glob.glob("G:/bar-ai-archive/public-replays/recordings/*/*.npz"))[:n]
    bins = np.array([-1e9, 0.2, 0.4, 0.6, 0.8, 1e9])
    rows = []
    for p in paths:
        g = Game(p)
        if not len(g.decisions):
            continue
        static = g.ucls == 0
        cents = {}
        for t in set(int(x) for x in g.uteam):
            m = static & (g.uteam == t)
            if m.any():
                cents[t] = (g.units[m, 4].mean(), g.units[m, 5].mean())
        cols = []
        for h, mm in HORIZON_PICK:
            v = g.outcome[:, h, mm].astype(np.float64)
            ok = ~np.isnan(v)
            z = np.zeros_like(v)
            if ok.sum() > 2:
                z[ok] = (v[ok] - v[ok].mean()) / (v[ok].std() + 1e-6)
            cols.append(np.clip(z, -3, 3))
        cols = np.array(cols).T
        for i, d in enumerate(g.decisions):
            t = int(d[2])
            foes = [c for tt, c in cents.items() if g.ally_of.get(tt) != g.ally_of.get(t) and g.ally_of.get(tt, -9) >= 0]
            if t not in cents or not foes:
                continue
            o, e = np.array(cents[t]), np.mean(foes, axis=0)
            ax = e - o
            fwd = float(np.dot(np.array([d[5], d[6]]) - o, ax) / max(np.dot(ax, ax), 1.0))
            w = float(np.exp(0.5 * np.clip(g.dec_score[i], -2, 2)))
            rows.append((fwd, w, *cols[i]))
    r = np.array(rows)
    print("%d orders from %d games" % (len(r), len(paths)))
    w = r[:, 1]
    print("weights: below 1 (marked down) %.1f%%, exactly 1 (neutral) %.1f%%, above 1 %.1f%%" % (
        100 * np.mean(w < 0.999), 100 * np.mean(np.abs(w - 1) < 0.001), 100 * np.mean(w > 1.001)))
    print("%-12s %7s %7s %7s  %s" % ("forward", "orders", "weight", "down%", "  ".join("%8s" % x for x in NAMES)))
    idx = np.digitize(r[:, 0], bins) - 1
    for b in range(len(bins) - 1):
        m = idx == b
        lo, hi = bins[b], bins[b + 1]
        label = ("<%.1f" % hi) if lo < -1e8 else (">%.1f" % lo) if hi > 1e8 else "%.1f-%.1f" % (lo, hi)
        print("%-12s %7d %7.3f %6.1f%%  %s" % (label, m.sum(), r[m, 1].mean(), 100 * np.mean(r[m, 1] < 0.999),
                                               "  ".join("%8.3f" % v for v in r[m, 2:].mean(0))))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
