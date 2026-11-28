#!/usr/bin/env python3
"""How much of a player's order lies in its shift-queued waypoints (his 11-19: "we're still not raiding well at all").
replay_dataset.py keeps the last NOT-queued order of a burst as the target; for a queued route that is the first
leg, not where the units were sent. Per human army/air burst with queued points: how far the route's last point is
from the kept target, and how far forward each is (0 own buildings, 1 theirs).

    python tools/armynet/queued_routes.py [--games 40]
"""
import collections
import glob
import gzip
import math
import sys

import numpy as np

FOCUS = {"army", "air", "radar", "jammer"}
POS = {10, 15, 16, 20, 21}


def main(a):
    n = int(a[a.index("--games") + 1]) if "--games" in a else 40
    recs = sorted(glob.glob("G:/bar-ai-archive/public-replays/recordings/*/orders.txt.gz"))[:n]
    total = queued = 0
    gaps, fwd_kept, fwd_end, speed_q, speed_all = [], [], [], [], []
    for rec in recs:
        cls, speed, teams, statics = {}, {}, {}, collections.defaultdict(list)
        orders = collections.defaultdict(list)
        for ln in gzip.open(rec, "rt", errors="replace"):
            p = ln.split()
            if p[0] == "D":
                cls[int(p[1])], speed[int(p[1])] = p[3], float(p[6])
            elif p[0] == "T":
                teams[int(p[1])] = (int(p[2]), p[3] == "true")
            elif p[0] == "U" and int(p[1]) % 3000 == 0 and cls.get(int(p[3])) == "static":
                statics[int(p[4])].append((float(p[5]), float(p[6])))
            elif p[0] == "C" and len(p) >= 10 and int(p[5]) in POS:
                t, d = int(p[2]), int(p[4])
                if teams.get(t, (0, True))[1] or cls.get(d) not in FOCUS:
                    continue
                ps = p[9].split(",")
                if len(ps) >= 3:
                    orders[int(p[3])].append((int(p[1]), t, d, "s" in p[6], float(ps[0]), float(ps[2])))
        cent = {t: np.mean(v, axis=0) for t, v in statics.items() if v}
        for uid, rows in orders.items():
            rows.sort()
            burst = [rows[0]]
            for r in rows[1:] + [None]:
                if r is not None and r[0] - burst[-1][0] <= 45:
                    burst.append(r)
                    continue
                total += 1
                speed_all.append(speed.get(burst[0][2], 0))
                plain = [b for b in burst if not b[3]] or burst
                kept, end = plain[-1], burst[-1]
                if end[3] and end is not kept:
                    queued += 1
                    gaps.append(math.hypot(end[4] - kept[4], end[5] - kept[5]))
                    speed_q.append(speed.get(burst[0][2], 0))
                    t = kept[1]
                    own = cent.get(t)
                    foes = [c for tt, c in cent.items() if teams.get(tt, (-1,))[0] != teams[t][0]]
                    if own is not None and foes:
                        ax = np.mean(foes, axis=0) - own
                        n2 = max(float(np.dot(ax, ax)), 1.0)
                        fwd_kept.append(float(np.dot(np.array(kept[4:6]) - own, ax)) / n2)
                        fwd_end.append(float(np.dot(np.array(end[4:6]) - own, ax)) / n2)
                burst = [r] if r is not None else []
    q = lambda v, p: np.percentile(v, p) if v else float("nan")
    print("%d games, %d bursts; %d (%.1f%%) end in queued waypoints past the kept target" % (
        len(recs), total, queued, 100 * queued / max(total, 1)))
    print("route end to kept target: median %.0f elmos, q75 %.0f" % (q(gaps, 50), q(gaps, 75)))
    print("forward of kept target: median %.2f; of the route's end: median %.2f, q75 %.2f" % (
        q(fwd_kept, 50), q(fwd_end, 50), q(fwd_end, 75)))
    deep = sum(1 for f in fwd_end if f > 0.7)
    deep_kept = sum(1 for k, f in zip(fwd_kept, fwd_end) if f > 0.7 and k <= 0.7)
    print("routes ending past 0.7 of the way to their base: %d; of them the kept target short of 0.7: %d" % (deep, deep_kept))
    print("unit speed: queued bursts median %.0f, all bursts median %.0f" % (q(speed_q, 50), q(speed_all, 50)))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
