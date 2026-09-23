"""Win rate and minute-4 extractors split by WHICH START BOX we drew.

    python tools/sidesplit.py <tournament-dir> [...]

run_match gives teams 0,1 the left box and 2,3 the right; which pair Apex
occupies alternates game to game. Pooling the two hides any map asymmetry
inside every other average, so this prints them apart.
"""
import glob
import json
import os
import re
import sys
import collections

acc = collections.defaultdict(lambda: collections.Counter())
for T in sys.argv[1:]:
    for M in sorted(glob.glob(os.path.join(T, 'matches', 't*'))):
        rj = os.path.join(M, 'result.json')
        if not os.path.exists(rj):
            continue
        r = json.load(open(rj))
        if r['result'].get('reason') != 'gameover':
            continue
        script = open(os.path.join(M, 'script.txt')).read()
        ai0 = re.search(r'\[AI0\](.*?)\[AI1\]', script, re.S).group(1)
        ap0 = 'Apex' in ai0                      # Apex holds teams 0,1 = left box
        side = 'left' if ap0 else 'right'
        specs = r['result'].get('winner_specs') or ['-']
        acc[side]['n'] += 1
        acc[side]['win'] += 1 if 'Apex' in specs[0] else 0
        txt = open(os.path.join(M, 'infolog.txt'), encoding='utf-8', errors='replace').read()
        mex = collections.Counter()
        for m in re.finditer(r'\[BARAI_POS\] team=(\d) ally=\d frame=7200 n=\d+ part=\d+/\d+ (\S*)', txt):
            s = 'us' if (int(m.group(1)) < 2) == ap0 else 'them'
            for e in m.group(2).split(','):
                p = e.split(':')
                if len(p) >= 2 and p[0] in ('armmex', 'armmoho'):
                    mex[s] += 1
        acc[side]['mex_us'] += mex['us']
        acc[side]['mex_them'] += mex['them']

print('Apex box   games   wins   win%%   mex@4 us/them   gap')
for side in ('left', 'right'):
    c = acc[side]
    n = max(c['n'], 1)
    print('%-9s %6d %6d %6.1f%%   %.2f / %.2f   %+.2f'
          % (side, c['n'], c['win'], 100.0 * c['win'] / n,
             c['mex_us'] / n, c['mex_them'] / n,
             (c['mex_us'] - c['mex_them']) / n))
