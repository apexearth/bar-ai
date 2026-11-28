#!/usr/bin/env python3
"""How far forward players send their army, minute by minute (0 own buildings, 1 theirs; deep = past 0.7), and the
metal-weighted speed of their army units, to set against the model in play (serve.log, gaps.py).

    python tools/armynet/players_by_minute.py [--games 80]
"""
import collections
import glob
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import Game  # noqa: E402


def main(a):
    n = int(a[a.index("--games") + 1]) if "--games" in a else 80
    fwd = collections.defaultdict(list)
    spd = collections.defaultdict(list)
    for p in sorted(glob.glob("G:/bar-ai-archive/public-replays/recordings/*/*.npz"))[:n]:
        g = Game(p)
        static = g.ucls == 0
        cents = {}
        for t in set(int(x) for x in g.uteam):
            m = static & (g.uteam == t)
            if m.any():
                cents[t] = np.array([g.units[m, 4].mean(), g.units[m, 5].mean()])
        for d in g.decisions:
            t = int(d[2])
            foes = [c for tt, c in cents.items() if g.ally_of.get(tt) != g.ally_of.get(t) and g.ally_of.get(tt, -9) >= 0]
            if t not in cents or not foes:
                continue
            ax = np.mean(foes, axis=0) - cents[t]
            f = float(np.dot(np.array([d[5], d[6]]) - cents[t], ax) / max(float(np.dot(ax, ax)), 1.0))
            fwd[int(d[0]) // 1800 // 3 * 3].append(f)
        army = np.isin(g.ucls, (3, 4)) & (g.units[:, 9] >= 1)
        for minute in range(3, 30, 3):
            m = army & (g.frames == minute * 1800)
            for t in set(int(x) for x in g.uteam[m]):
                if g.is_ai.get(t):
                    continue
                mm = m & (g.uteam == t)
                w = g.d_metal[g.udef[mm]]
                if w.sum() > 0:
                    spd[minute].append(float((g.d_speed[g.udef[mm]] * w).sum() / w.sum()))
    print("minute  orders  forward-median  deep%  | army speed (metal-weighted, median over sides)")
    for m in sorted(fwd):
        v = np.array(fwd[m])
        s = np.median(spd[m]) if spd.get(m) else float("nan")
        print("%5d-%-2d %7d %10.2f %8.1f%%  | %6.1f" % (m, m + 2, len(v), np.median(v), 100 * np.mean(v > 0.7), s))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
