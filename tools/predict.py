"""Which opening number actually predicts the win, WITHIN a start box.

    python tools/predict.py <tournament-dir> [...]

A treatment to our tree can only move OUR side of a differential, so a metric
is only useful for screening if OUR half of it predicts the outcome. Pooling
the two start boxes hides that: the box is worth 1.5-2.2 extractors by itself
and is collinear with the metric, so a pooled correlation can be almost pure
box membership. This reports AUC within each box, ours and theirs apart.
"""
import collections
import glob
import json
import os
import re
import sys

MEXES = ('armmex', 'armmoho')


def auc(pairs):
    """P(score of a win > score of a loss), ties at half."""
    wins = [s for s, w in pairs if w]
    losses = [s for s, w in pairs if not w]
    if not wins or not losses:
        return float('nan')
    better = ties = 0
    for a in wins:
        for b in losses:
            if a > b:
                better += 1
            elif a == b:
                ties += 1
    return (better + 0.5 * ties) / float(len(wins) * len(losses))


rows = []
for T in sys.argv[1:]:
    for M in sorted(glob.glob(os.path.join(T, 'matches', 't*'))):
        rj = os.path.join(M, 'result.json')
        info = os.path.join(M, 'infolog.txt')
        if not (os.path.exists(rj) and os.path.exists(info)):
            continue
        r = json.load(open(rj))
        if r['result'].get('reason') != 'gameover' or not r['result'].get('winners'):
            continue
        script = open(os.path.join(M, 'script.txt')).read()
        ap0 = 'Apex' in re.search(r'\[AI0\](.*?)\[AI1\]', script, re.S).group(1)
        won = (int(r['result']['winners'][0]) == 0) == ap0
        txt = open(info, encoding='utf-8', errors='replace').read()
        mex = collections.Counter()
        for m in re.finditer(r'\[BARAI_POS\] team=(\d) ally=\d frame=7200 '
                             r'n=\d+ part=\d+/\d+ (\S*)', txt):
            s = 'us' if (int(m.group(1)) < 2) == ap0 else 'them'
            for e in m.group(2).split(','):
                p = e.split(':')
                if len(p) >= 2 and p[0] in MEXES:
                    mex[s] += 1
        army = collections.Counter()
        for m in re.finditer(r'\[BARAI_STATS\] team=(\d) ally=\d reason=periodic '
                             r'frame=(\d+) .*?mArmy=([\d.]+)', txt):
            if int(m.group(2)) not in (7200, 10800):
                continue
            s = 'us' if (int(m.group(1)) < 2) == ap0 else 'them'
            army[(s, int(m.group(2)))] += float(m.group(3))
        rows.append(dict(box='left' if ap0 else 'right', won=won,
                         ourmex=mex['us'], theirmex=mex['them'],
                         mexgap=mex['us'] - mex['them'],
                         armygap4=army[('us', 7200)] - army[('them', 7200)],
                         armygap6=army[('us', 10800)] - army[('them', 10800)]))

print('%d games' % len(rows))
print('%-6s %5s %6s | %8s %9s %7s %9s %9s'
      % ('box', 'n', 'win%', 'our mex4', 'their mex4', 'mexgap', 'armygap4', 'armygap6'))
for box in ('left', 'right', 'both'):
    sub = [r for r in rows if box == 'both' or r['box'] == box]
    if not sub:
        continue
    n = len(sub)
    w = sum(1 for r in sub if r['won'])
    cells = []
    for key in ('ourmex', 'theirmex', 'mexgap', 'armygap4', 'armygap6'):
        a = auc([(r[key] if key != 'theirmex' else -r[key], r['won']) for r in sub])
        cells.append('%9.3f' % a)
    print('%-6s %5d %5.1f%% |%s' % (box, n, 100.0 * w / n, ' '.join(cells)))
print()
print('AUC 0.5 = the metric is a coin flip against the outcome. "their mex4" is')
print('negated, so >0.5 means fewer of theirs predicts our win.')
