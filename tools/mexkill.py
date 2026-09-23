"""What kills our extractors in the opening, and how far from home.

    python tools/mexkill.py <tournament-dir> [...] [--minute 6]

openloop reads our standing extractors FALLING between minute 4 and 6 while
theirs rise. That is a different problem from building too few, and it has a
different fix, so this separates them: per side, how many extractors died by
minute N, what killed them, and their distance from that side's start.
"""
import collections
import glob
import math
import os
import re
import sys

MEXES = ('armmex', 'armmoho', 'cormex', 'cormoho')

minute = 6
args = []
skip = False
for i, a in enumerate(sys.argv[1:]):
    if skip:
        skip = False
        continue
    if a == '--minute':
        minute = int(sys.argv[i + 2])
        skip = True
    elif not a.startswith('--'):
        args.append(a)
cap = minute * 1800

for T in args:
    killer = collections.defaultdict(collections.Counter)
    died = collections.Counter()
    dist = collections.defaultdict(list)
    n = 0
    for M in sorted(glob.glob(os.path.join(T, 'matches', 't*'))):
        info = os.path.join(M, 'infolog.txt')
        if not os.path.exists(info):
            continue
        n += 1
        script = open(os.path.join(M, 'script.txt')).read()
        ap0 = 'Apex' in re.search(r'\[AI0\](.*?)\[AI1\]', script, re.S).group(1)
        starts = {}
        for m in re.finditer(r'\[TEAM(\d)\]\s*\{?[^}]*?StartPosX=(\d+);\s*'
                             r'StartPosZ=(\d+);', script, re.S):
            starts[int(m.group(1))] = (float(m.group(2)), float(m.group(3)))
        txt = open(info, encoding='utf-8', errors='replace').read()
        for m in re.finditer(r'\[BARAI_DEATH\] frame=(\d+) team=(\d) unit=(\S+) '
                             r'cost=\d+ x=([-\d.]+) z=([-\d.]+) .*?built=(\d) '
                             r'.*?atk=(\S+)', txt):
            if int(m.group(1)) > cap or m.group(3) not in MEXES:
                continue
            team = int(m.group(2))
            side = 'us' if (team < 2) == ap0 else 'them'
            # built=0 is an extractor killed as a nanoframe: it never reaches the
            # standing count at all, which is a different loss from losing one.
            died[side + ('' if m.group(6) == '1' else ' frame')] += 1
            killer[side][m.group(7)] += 1
            if team in starts:
                sx, sz = starts[team]
                dist[side].append(math.hypot(float(m.group(4)) - sx,
                                             float(m.group(5)) - sz))
    print('==', os.path.basename(os.path.normpath(T)), '(%d games, by minute %d)' % (n, minute))
    for side in ('us', 'them'):
        d = dist[side]
        med = sorted(d)[len(d) // 2] if d else -1
        print('  %-5s extractors lost %5.2f per game (+%.2f killed as a frame)'
              '   median %s from own start'
              % (side, died[side] / max(n, 1), died[side + ' frame'] / max(n, 1),
                 ('%.0f' % med) if d else 'n/a'))
        top = ' '.join('%s %d%%' % (k, 100 * v // max(sum(killer[side].values()), 1))
                       for k, v in killer[side].most_common(6))
        print('        killed by: %s' % (top or '(none)'))
