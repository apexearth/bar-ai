"""The map's metal spots, recovered from where extractors were ever built.

    python tools/spotmap.py <tournament-dir> [...]

Answers the question a start-box asymmetry raises first: does each box have
the same economy within reach? Every extractor either side ever finished is
collected, rounded onto a grid so the same spot from different games counts
once, and then counted by distance from each of the four start positions.
"""
import collections
import glob
import json
import os
import re
import sys

MEXES = ('armmex', 'armmoho', 'cormex', 'cormoho')
GRID = 64.0

spots = set()
starts = {}
for T in sys.argv[1:]:
    for M in sorted(glob.glob(os.path.join(T, 'matches', 't*'))):
        info = os.path.join(M, 'infolog.txt')
        if not os.path.exists(info):
            continue
        if not starts:
            script = open(os.path.join(M, 'script.txt')).read()
            for m in re.finditer(r'\[TEAM(\d)\]\s*\{?[^}]*?StartPosX=(\d+);\s*'
                                 r'StartPosZ=(\d+);', script, re.S):
                starts[int(m.group(1))] = (float(m.group(2)), float(m.group(3)))
        txt = open(info, encoding='utf-8', errors='replace').read()
        for m in re.finditer(r'\[BARAI_POS\] team=\d ally=\d frame=\d+ '
                             r'n=\d+ part=\d+/\d+ (\S*)', txt):
            for e in m.group(1).split(','):
                p = e.split(':')
                if len(p) >= 3 and p[0] in MEXES:
                    try:
                        spots.add((round(float(p[1]) / GRID), round(float(p[2]) / GRID)))
                    except ValueError:
                        pass

pts = [(x * GRID, z * GRID) for x, z in spots]
print('%d distinct extractor sites over %d game(s) of input' % (len(pts), len(sys.argv) - 1))
if not pts:
    raise SystemExit(0)
xs = [p[0] for p in pts]
zs = [p[1] for p in pts]
print('extent  x %.0f..%.0f   z %.0f..%.0f' % (min(xs), max(xs), min(zs), max(zs)))
mid = (min(xs) + max(xs)) / 2.0
print('sites left of centre %d   right of centre %d'
      % (sum(1 for x in xs if x < mid), sum(1 for x in xs if x >= mid)))
print()
print('start            within 1000   1500   2000   nearest')
for t in sorted(starts):
    sx, sz = starts[t]
    d = sorted(((x - sx) ** 2 + (z - sz) ** 2) ** 0.5 for x, z in pts)
    box = 'left ' if t < 2 else 'right'
    print('TEAM%d %s %5.0f,%-5.0f %4d %6d %6d   %.0f'
          % (t, box, sx, sz,
             sum(1 for v in d if v <= 1000), sum(1 for v in d if v <= 1500),
             sum(1 for v in d if v <= 2000), d[0] if d else -1))
