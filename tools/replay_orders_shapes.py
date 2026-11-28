#!/usr/bin/env python3
"""The shape of human group orders in an orders.txt (tools/replay_orders.py).

    python tools/replay_orders_shapes.py <orders.txt>

A group order: one human team, one frame, one move/fight order, 5+ army/air units. Its targets'
spread along their main axis (length) and across it (width): a line is long and thin, a point
order has every target in one spot. The line's facing is compared with the direction to the
nearest enemy mass (5 s position samples): a line held against them stands across that direction.
"""
import collections
import math
import sys

FOCUS = {"army", "air", "radar", "jammer"}


def main(path):
    defs, teams, groups, samples = {}, {}, collections.defaultdict(list), collections.defaultdict(list)
    for ln in open(path, encoding="utf-8", errors="replace"):
        p = ln.split()
        if not p:
            continue
        if p[0] == "D":
            defs[int(p[1])] = p[3]
        elif p[0] == "T":
            teams[int(p[1])] = (int(p[2]), p[3] == "true")
        elif p[0] == "C" and len(p) > 9 and int(p[5]) in (10, 16):
            t = int(p[2])
            if teams.get(t, (0, True))[1] or defs.get(int(p[4])) not in FOCUS:
                continue
            ps = [float(v) for v in p[-1].split(",")]
            if len(ps) >= 3:
                groups[(int(p[1]), t)].append((float(p[7]), float(p[8]), ps[0], ps[2]))
        elif p[0] == "P":
            samples[int(p[1])].append((int(p[2]), defs.get(int(p[4])), float(p[5]), float(p[6])))
    frames = sorted(samples)
    kinds = collections.Counter()
    angles = []
    for (f, t), rows in groups.items():
        if len(rows) < 5:
            continue
        tx = [r[2] for r in rows]
        tz = [r[3] for r in rows]
        mx, mz = sum(tx) / len(tx), sum(tz) / len(tz)
        sxx = sum((x - mx) ** 2 for x in tx) / len(tx)
        szz = sum((z - mz) ** 2 for z in tz) / len(tz)
        sxz = sum((x - mx) * (z - mz) for x, z in zip(tx, tz)) / len(tx)
        tr, det = sxx + szz, sxx * szz - sxz ** 2
        l1 = tr / 2 + math.sqrt(max(tr * tr / 4 - det, 0))
        l2 = max(tr - l1, 0)
        length, width = 2 * math.sqrt(l1), 2 * math.sqrt(l2)
        if length < 40:
            kinds["point (all to one spot)"] += 1
            continue
        kinds["line (long/wide > 3)" if length > 3 * max(width, 1) else "blob (2-D spread)"] += 1
        if length <= 3 * max(width, 1):
            continue
        ax = math.atan2(2 * sxz, sxx - szz) / 2
        near = min(frames, key=lambda g: abs(g - f)) if frames else None
        ally = teams[t][0]
        foes = [(x, z) for tm, c, x, z in samples.get(near, []) if c in FOCUS and teams.get(tm, (ally,))[0] != ally
                and teams.get(tm, (ally,))[0] >= 0]
        if not foes:
            continue
        foes.sort(key=lambda q: (q[0] - mx) ** 2 + (q[1] - mz) ** 2)
        fx = sum(q[0] for q in foes[:10]) / len(foes[:10])
        fz = sum(q[1] for q in foes[:10]) / len(foes[:10])
        to_foe = math.atan2(fz - mz, fx - mx)
        d = abs((to_foe - ax + math.pi / 2) % math.pi - math.pi / 2)
        angles.append((math.degrees(d), math.hypot(fx - mx, fz - mz), length))
    total = sum(kinds.values())
    print("human group orders (5+ units, one frame):", total)
    for k, n in kinds.most_common():
        print("  %-26s %5d  %.0f%%" % (k, n, 100 * n / max(total, 1)))
    if angles:
        across = [a for a in angles if a[0] >= 60]
        print("lines with an enemy mass in sight: %d; standing across the direction to it (60-90 deg): %d (%.0f%%)"
              % (len(angles), len(across), 100 * len(across) / len(angles)))
        L = sorted(a[2] for a in angles)
        D = sorted(a[1] for a in angles)
        print("  line length median %.0f elmos; distance to the enemy mass median %.0f" % (L[len(L) // 2], D[len(D) // 2]))


if __name__ == "__main__":
    main(sys.argv[1])
