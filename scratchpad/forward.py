"""How far forward each side puts its extractors and its guns.

f = 0 at own start, 1 at the enemy start, along the home->enemy axis.
apexearth's mex-guard ruling says the guns belong ON the outside mexes; this
prints whether they are, per side, so the two distributions can be compared
directly instead of through a tower COUNT.
"""
import collections
import glob
import math
import os
import re
import sys

MEX = ("armmex", "armmoho", "cormex", "cormoho")
DEF = ("armllt", "armbeamer", "armhlt", "armguard", "armpb", "armclaw",
       "armdl", "armfrt", "armrl", "armferret", "armcir", "armmercury",
       "corllt", "corhlt", "corexp", "corpun", "corvipe", "corrl",
       "corerad", "cormadsam", "corflak", "armflak", "armamb", "armanni")
MIN = [4, 8, 12, 16]

acc = collections.defaultdict(lambda: [0.0, 0])

for T in sys.argv[1:]:
    for M in sorted(glob.glob(os.path.join(T, "**", "script.txt"), recursive=True)):
        d = os.path.dirname(M)
        info = os.path.join(d, "infolog.txt")
        if not os.path.exists(info):
            continue
        script = open(M).read()
        ours = set()
        for m in re.finditer(r"\[AI(\d+)\][\s\S]{0,400}?ShortName=(\w+);"
                             r"[\s\S]{0,400}?Team=(\d+);", script):
            if m.group(2).startswith("Apex"):
                ours.add(int(m.group(3)))
        start = {}
        for m in re.finditer(r"\[TEAM(\d+)\][\s\S]{0,300}?StartPosX=([\d.]+);"
                             r"[\s\S]{0,60}?StartPosZ=([\d.]+);", script):
            start[int(m.group(1))] = (float(m.group(2)), float(m.group(3)))
        if not ours or len(start) < 4:
            continue
        # the enemy anchor for a team is the mean of the other ally's starts
        foe = {}
        for t in start:
            other = [start[u] for u in start
                     if (u in ours) != (t in ours)]
            foe[t] = (sum(p[0] for p in other) / len(other),
                      sum(p[1] for p in other) / len(other))
        txt = open(info, encoding="utf-8", errors="replace").read()
        for m in re.finditer(r"\[BARAI_POS\] team=(\d) ally=\d frame=(\d+) "
                             r"n=\d+ part=\d+/\d+ (\S*)", txt):
            minute = int(m.group(2)) // 1800
            if minute not in MIN:
                continue
            team = int(m.group(1))
            if team not in start:
                continue
            side = "us" if team in ours else "them"
            hx, hz = start[team]
            ex, ez = foe[team]
            axis = math.hypot(ex - hx, ez - hz)
            if axis < 1.0:
                continue
            ux, uz = (ex - hx) / axis, (ez - hz) / axis
            for e in m.group(3).split(","):
                p = e.split(":")
                if len(p) < 3:
                    continue
                try:
                    x, z = float(p[1]), float(p[2])
                except ValueError:
                    continue
                kind = ("mex" if p[0] in MEX else
                        "def" if p[0] in DEF else None)
                if kind is None:
                    continue
                f = ((x - hx) * ux + (z - hz) * uz) / axis
                k = (side, minute, kind)
                acc[k][0] += f
                acc[k][1] += 1
                # A RING AROUND HOME PROJECTS TO f=0 AT ANY RADIUS, so the
                # projection alone cannot say whether we are forward or just
                # symmetric. Carry the radius too.
                acc[k].append(math.hypot(x - hx, z - hz))

print("mean forward fraction f (0 = own start, 1 = enemy start), and count/game")
print("%-4s %-5s %26s %26s" % ("min", "side", "MEX", "DEFENCE"))
games = max(1, len(sys.argv) - 1)
for minute in MIN:
    for side in ("us", "them"):
        row = []
        for kind in ("mex", "def"):
            v = acc[(side, minute, kind)]
            s, n, rad = v[0], v[1], v[2:]
            rad.sort()
            row.append("f%.3f r%4d/p90 %4d (%4d)"
                       % (s / n, sum(rad) / n, rad[int(0.9 * (n - 1))], n)
                       if n else "        -           ")
        print("%-4d %-5s %26s %26s" % (minute, side, row[0], row[1]))
    print()
