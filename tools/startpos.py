"""Which start positions the harness actually used, per tournament.

    python tools/startpos.py <tournament-dir> [...]

A start box does not fix a start POSITION: the harness picks from the map's
own starts inside the box and clamps one that falls just outside (21173316).
If the two boxes are not drawing equally good ground, every side-split number
is measuring the draw and not the AI.
"""
import collections
import glob
import os
import re
import sys

for T in sys.argv[1:]:
    seen = collections.Counter()
    for M in sorted(glob.glob(os.path.join(T, 'matches', 't*'))):
        sf = os.path.join(M, 'script.txt')
        if not os.path.exists(sf):
            continue
        script = open(sf).read()
        pos = {}
        for m in re.finditer(r'\[TEAM(\d)\]\s*\{?[^}]*?StartPosX=(\d+);\s*'
                             r'StartPosZ=(\d+);', script, re.S):
            pos[int(m.group(1))] = '%s,%s' % (m.group(2), m.group(3))
        if pos:
            seen['  '.join('T%d %-11s' % (t, pos[t]) for t in sorted(pos))] += 1
    print('==', os.path.basename(os.path.normpath(T)))
    for k, v in seen.most_common():
        print('   %3dx  %s' % (v, k))
