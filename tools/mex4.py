"""What at minute 4 actually predicts the result, pooled over tournaments:
mexes, army, metal lost (finished units only), and income."""
import glob
import json
import os
import re
import sys
import collections

rows = []
for T in sys.argv[1:]:
    for M in sorted(glob.glob(os.path.join(T, 'matches', 't*'))):
        rj = os.path.join(M, 'result.json')
        if not os.path.exists(rj):
            continue
        r = json.load(open(rj))
        specs = r['result'].get('winner_specs') or ['-']
        won = 'Apex' in specs[0]
        script = open(os.path.join(M, 'script.txt')).read()
        ai0 = re.search(r'\[AI0\](.*?)\[AI1\]', script, re.S).group(1)
        ap0 = 'Apex' in ai0
        txt = open(os.path.join(M, 'infolog.txt'), encoding='utf-8', errors='replace').read()
        mex = collections.Counter()
        army = collections.Counter()
        lost = collections.Counter()
        for m in re.finditer(r'\[BARAI_POS\] team=(\d) ally=\d frame=7200 n=\d+ part=\d+/\d+ (\S*)', txt):
            side = 'us' if (int(m.group(1)) < 2) == ap0 else 'them'
            for e in m.group(2).split(','):
                p = e.split(':')
                if len(p) >= 2 and p[0] in ('armmex', 'armmoho'):
                    mex[side] += 1
        for m in re.finditer(r'\[BARAI_STATS\] team=(\d) ally=\d reason=periodic frame=7200 .*?mArmy=([\d.]+)', txt):
            side = 'us' if (int(m.group(1)) < 2) == ap0 else 'them'
            army[side] += float(m.group(2))
        for m in re.finditer(r'\[BARAI_DEATH\] frame=(\d+) team=(\d) unit=\S+ cost=(\d+) .*?built=(\d) ', txt):
            if int(m.group(1)) <= 7200 and m.group(4) == '1':
                side = 'us' if (int(m.group(2)) < 2) == ap0 else 'them'
                lost[side] += int(m.group(3))
        rows.append((won, mex['us'] - mex['them'], army['us'] - army['them'],
                     lost['us'] - lost['them']))

wins = [r for r in rows if r[0]]
losses = [r for r in rows if not r[0]]
print('%d games: %d wins, %d losses' % (len(rows), len(wins), len(losses)))
print('at minute 4, OUR SIDE MINUS THEIRS:')
for name, g in (('wins  ', wins), ('losses', losses)):
    if not g:
        continue
    print('  %s  mex %+5.1f   army %+7.0f   metal lost %+7.0f'
          % (name,
             sum(x[1] for x in g) / len(g),
             sum(x[2] for x in g) / len(g),
             sum(x[3] for x in g) / len(g)))
ahead = [r for r in rows if r[1] >= 0]
behind = [r for r in rows if r[1] < 0]
for name, g in (('mex lead at 4 min ', ahead), ('mex behind at 4min', behind)):
    if g:
        print('  %s n=%2d  win rate %.0f%%' % (name, len(g), 100.0 * sum(1 for x in g if x[0]) / len(g)))
