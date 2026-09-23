"""Which START BOX wins, independent of which AI sat in it.

    python tools/boxwin.py <tournament-dir> [...]

`sidesplit.py` answers "how does OUR side do from each box" and so cannot be
run on a control of one AI against itself. This one keys on the box alone:
run_match gives teams 0,1 the left box and 2,3 the right, so a BARb-vs-BARb
batch here reports the map's own asymmetry with no AI difference in it.
"""
import collections
import glob
import json
import os
import sys

acc = collections.Counter()
for T in sys.argv[1:]:
    for M in sorted(glob.glob(os.path.join(T, 'matches', 't*'))):
        rj = os.path.join(M, 'result.json')
        if not os.path.exists(rj):
            continue
        r = json.load(open(rj))
        if r['result'].get('reason') != 'gameover':
            acc[r['result'].get('reason', 'none')] += 1
            continue
        # `winners` holds SPEC indices, and run_match.py gives ally 0 -- the
        # [AI0] block -- the left box for `lr` (run_match.py:383).
        winners = r['result'].get('winners') or []
        if not winners:
            acc['unreadable'] += 1
            continue
        won_left = int(winners[0]) == 0
        acc['n'] += 1
        acc['left' if won_left else 'right'] += 1

n = max(acc['n'], 1)
print('games with a winner %d   left box %d (%.1f%%)   right box %d (%.1f%%)'
      % (acc['n'], acc['left'], 100.0 * acc['left'] / n,
         acc['right'], 100.0 * acc['right'] / n))
for k, v in acc.most_common():
    if k not in ('n', 'left', 'right'):
        print('  not counted: %-12s %d' % (k, v))
