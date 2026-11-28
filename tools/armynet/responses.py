#!/usr/bin/env python3
"""How players size their answers to raids and their own raids (his 11-19: "we chase their raiders with more than
we need to", "we pretty much aren't raiding at all").

    python tools/armynet/responses.py [--games 80]

Answers: a player order group (one team, one frame) aimed within 600 of an enemy army unit that stands within 1,200
of one of the player's buildings; its metal against the enemy army metal within 800 of the target.
Raids: an order group aimed past 0.7 of the way to the enemy's buildings; its size and the speed of its units.
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
    ratios, ans_units, raid_sizes, raid_speed = [], [], [], []
    for p in sorted(glob.glob("G:/bar-ai-archive/public-replays/recordings/*/*.npz"))[:n]:
        g = Game(p)
        if not len(g.decisions):
            continue
        static = g.ucls == 0
        cent = {}
        for t in set(int(x) for x in g.uteam):
            m = static & (g.uteam == t)
            if m.any():
                cent[t] = np.array([g.units[m, 4].mean(), g.units[m, 5].mean()])
        groups = collections.defaultdict(list)
        for d in g.decisions:
            groups[(int(d[2]), int(d[0]))].append(d)
        for (t, f), ds in groups.items():
            ally = g.ally_of.get(t)
            idx = g.rows_at(f - f % 30)
            u = g.units[idx]
            al = np.array([g.ally_of.get(int(x), -9) for x in u[:, 3]])
            foe_army = (al != ally) & (al >= 0) & np.isin(g.ucls[idx], (3, 4))
            ours_b = (al == ally) & (g.ucls[idx] == 0)
            tx, tz = np.mean([d[5] for d in ds]), np.mean([d[6] for d in ds])
            uids = {int(d[3]) for d in ds}
            mine = np.isin(u[:, 1].astype(np.int64), list(uids))
            metal = g.d_metal[g.udef[idx]]
            sent = metal[mine].sum()
            if foe_army.any() and ours_b.any():
                fx, fz = u[foe_army, 4], u[foe_army, 5]
                bx, bz = u[ours_b, 4], u[ours_b, 5]
                near_b = ((fx[:, None] - bx[None, :]) ** 2 + (fz[:, None] - bz[None, :]) ** 2).min(1) <= 1200 ** 2
                hit = ((fx - tx) ** 2 + (fz - tz) ** 2) <= 600 ** 2
                if (near_b & hit).any():
                    threat = metal[foe_army][((fx - tx) ** 2 + (fz - tz) ** 2) <= 800 ** 2].sum()
                    if threat > 0 and sent > 0:
                        ratios.append(sent / threat)
                        ans_units.append(len(uids))
                    continue
            foes = [c for tt, c in cent.items() if g.ally_of.get(tt) != ally and g.ally_of.get(tt, -9) >= 0]
            if t in cent and foes:
                ax = np.mean(foes, axis=0) - cent[t]
                fwd = float(np.dot(np.array([tx, tz]) - cent[t], ax) / max(float(np.dot(ax, ax)), 1.0))
                if fwd > 0.7:
                    raid_sizes.append(len(uids))
                    sp = g.d_speed[g.udef[idx][mine]]
                    w = metal[mine]
                    if w.sum() > 0:
                        raid_speed.append(float((sp * w).sum() / w.sum()))
    q = lambda v: "median %.2f  q25 %.2f  q75 %.2f  (n=%d)" % (np.median(v), np.percentile(v, 25), np.percentile(v, 75), len(v))
    print("answers to raids near our buildings: metal sent / enemy metal there  " + q(ratios))
    print("answers: units sent                                               " + q(ans_units))
    print("raids (orders past 0.7 of the way): units per order group           " + q(raid_sizes))
    print("raids: metal-weighted speed of the group                            " + q(raid_speed))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
