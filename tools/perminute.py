"""One game, minute by minute, both sides -- the read his 2026-09-22 rule asks
for: "analyze each game minute by minute rather than just by the end state,
because if you're losing you make less metal BECAUSE you're being bossed
around the entire game". An average over games conflates cause with
consequence; this does not.

    python tools/perminute.py <match-dir> [<match-dir> ...] [--until 16]

Per minute, per side (ours = whichever is not BARb): standing extractors,
standing army metal, and metal lost so far. `first blood` marks the first
minute either side loses anything: before it the numbers are causal, after
it they are contested. Compare a game we won against one we lost in the
same batch rather than reading either alone.
"""
import os
import re
import sys
import collections


def read(match_dir):
    with open(os.path.join(match_dir, 'infolog.txt'), encoding='utf-8', errors='replace') as fh:
        txt = fh.read()
    with open(os.path.join(match_dir, 'script.txt')) as fh:
        script = fh.read()
    ai0 = re.search(r'\[AI0\](.*?)\[AI1\]', script, re.S).group(1)
    side01 = 'them' if 'BARb' in ai0 else 'us'
    other = 'us' if side01 == 'them' else 'them'
    side = lambda team: side01 if team < 2 else other

    mex = collections.Counter()
    army = collections.Counter()
    lost = collections.Counter()

    for m in re.finditer(r'\[BARAI_POS\] team=(\d) ally=\d frame=(\d+) n=\d+ part=\d+/\d+ (\S*)', txt):
        minute = int(m.group(2)) // 1800
        for entry in m.group(3).split(','):
            parts = entry.split(':')
            if len(parts) >= 2 and parts[0] in ('armmex', 'armmoho'):
                mex[(minute, side(int(m.group(1))))] += 1

    for m in re.finditer(r'\[BARAI_STATS\] team=(\d) ally=\d reason=periodic frame=(\d+) .*?mArmy=([\d.]+)', txt):
        army[(int(m.group(2)) // 1800, side(int(m.group(1))))] += float(m.group(3))

    # built=0 is a NANOFRAME and `cost` is the def's full cost, not what was
    # invested: an abandoned T2 lab at done=0.02 reports 2900 and is worth 58.
    # Finished units only, or the loss column reads the plan instead of the loss.
    for m in re.finditer(r'\[BARAI_DEATH\] frame=(\d+) team=(\d) unit=\S+ cost=(\d+) .*?built=(\d) ', txt):
        if m.group(4) == '1':
            lost[(int(m.group(1)) // 1800, side(int(m.group(2))))] += int(m.group(3))

    return mex, army, lost


def main():
    until = 16
    argv = sys.argv[1:]
    if '--until' in argv:
        i = argv.index('--until')
        until = int(argv[i + 1])
        del argv[i:i + 2]
    args = [a for a in argv if not a.startswith('--')]

    for match_dir in args:
        mex, army, lost = read(match_dir)
        cum = collections.Counter()
        first = None
        name = os.path.basename(os.path.normpath(match_dir))
        print('==', name)
        print(' min |  us: mex  army   lost | them: mex  army   lost')
        for minute in range(0, until + 1):
            for sd in ('us', 'them'):
                cum[sd] += lost[(minute, sd)]
                if lost[(minute, sd)] and first is None:
                    first = minute
            if minute % 2:
                continue
            print('%4d | %8d %5.0f %6.0f | %9d %5.0f %6.0f'
                  % (minute,
                     mex[(minute, 'us')], army[(minute, 'us')], cum['us'],
                     mex[(minute, 'them')], army[(minute, 'them')], cum['them']))
        print('     first blood at minute', first)


if __name__ == '__main__':
    main()
