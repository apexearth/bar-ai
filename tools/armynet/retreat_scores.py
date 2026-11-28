#!/usr/bin/env python3
"""How the rating treats leaving a fight (his 11-19: "lack of recognition of EXITING a fight - moving away from enemies
- and preserving army/health").

    python tools/armynet/retreat_scores.py [N games]

For player orders to army units with enemy army within 800 (a fight), split by where the order sends the unit:
  back   the target is 400+ farther from the nearest enemy than the unit is now
  on     anything else (hold, press, chase)
and by the local odds (enemy army metal within 800 over ours, allies counted). Reports, per group: count, the share of
the fight's orders, the mean training score (what weights the example), and the unit group's own trade 15 s and 60 s
later (outcome measure 8, damage dealt minus taken, metal-valued; after minus before).
"""
import glob
import random
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import Game  # noqa: E402


def main(a):
    n = int(a[0]) if a and a[0].isdigit() else 200
    root = a[a.index("--dir") + 1] if "--dir" in a else "G:/bar-ai-archive/public-replays/recordings/*"
    files = sorted(glob.glob(root + "/*.npz"))
    random.seed(3)
    files = random.sample(files, min(n, len(files)))
    rows = []
    for p in files:
        try:
            g = Game(p)
        except Exception:
            continue
        if not len(g.decisions) or g.outcome.shape[2] < 9:
            continue
        u = g.units
        for i, d in enumerate(g.decisions):
            f, team, uid, tx, tz = int(d[1]), int(d[2]), int(d[3]), float(d[5]), float(d[6])
            rows_f = g.rows_at(f)
            if not len(rows_f):
                continue
            me = rows_f[g.uid[rows_f] == uid]
            if not len(me):
                continue
            ux, uz = u[me[0], 4], u[me[0], 5]
            ally = g.ally_of.get(team, -1)
            army = np.isin(g.ucls[rows_f], (3, 4)) & (u[rows_f, 9] >= 1)
            foe = army & (g.ually[rows_f] != ally) & (g.ually[rows_f] >= 0)
            own = army & (g.ually[rows_f] == ally)
            fx, fz = u[rows_f[foe], 4], u[rows_f[foe], 5]
            dist = np.hypot(fx - ux, fz - uz)
            near = dist <= 800
            if not near.any():
                continue
            em = g.d_metal[g.udef[rows_f[foe]][near]].sum()
            ox, oz = u[rows_f[own], 4], u[rows_f[own], 5]
            om = g.d_metal[g.udef[rows_f[own]][np.hypot(ox - ux, oz - uz) <= 800]].sum()
            k = int(np.argmin(dist))
            back = np.hypot(fx[k] - tx, fz[k] - tz) >= dist[k] + 400
            rows.append((back, em / max(om, 1.0), g.dec_score[i], g.outcome[i, 1, 8], g.outcome[i, 2, 8])
                        + tuple(g.dec_cols[:, i]) if hasattr(g, "dec_cols") else ())
    r = np.array(rows, np.float64)
    print("orders in fights: %d from %d games" % (len(r), len(files)))
    for lo, hi, name in ((0, 0.67, "ahead (they < 2/3 of us)"), (0.67, 1.5, "even"), (1.5, 1e9, "behind (they > 1.5x)")):
        m = (r[:, 1] >= lo) & (r[:, 1] < hi)
        for b, label in ((1, "back"), (0, "on  ")):
            s = m & (r[:, 0] == b)
            if s.sum() < 5:
                continue
            o15, o60 = r[s, 3], r[s, 4]
            print("%-26s %s n %5d (%4.1f%% of these)  score %.3f  trade 15 s %8.1f  60 s %8.1f" % (
                name, label, s.sum(), 100 * s.sum() / max(m.sum(), 1), r[s, 2].mean(),
                np.nanmean(o15), np.nanmean(o60)))
            if r.shape[1] > 5:
                print("    per measure (data.HORIZON_PICK order): " + " ".join("%+.2f" % v for v in r[s, 5:].mean(0)))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
