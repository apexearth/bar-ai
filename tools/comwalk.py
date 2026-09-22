"""How far each side's commanders walk in the opening, and how much of that is
back and forth. His 2026-09-22 item: "Minimizing walk time. If your commander
walked in to mid to build a mex he should spend some time defending and
fortifying that mid position so we don't lose it."

    python tools/comwalk.py <tournament-dir> [--until 6]

Read from the army snapshots (every 2 minutes, both sides), so it needs no AI
logging and compares us against BARb on the same axis:

    walked    total elmos the commander moved, per commander
    net       distance from its start position at the end of the window
    churn     walked / net -- 1.0 is a straight line out, high is pacing
"""
import collections
import glob
import math
import os
import re
import sys


def one(match_dir, until):
    with open(os.path.join(match_dir, 'infolog.txt'), encoding='utf-8', errors='replace') as fh:
        txt = fh.read()
    with open(os.path.join(match_dir, 'script.txt')) as fh:
        script = fh.read()
    ai0 = re.search(r'\[AI0\](.*?)\[AI1\]', script, re.S).group(1)
    ap0 = 'Apex' in ai0
    track = collections.defaultdict(list)
    for m in re.finditer(r'\[BARAI_ARMY\] frame=(\d+) team=(\d) n=\d+ part=\d+/\d+ (\S*)', txt):
        frame = int(m.group(1))
        if frame > until * 1800:
            continue
        team = int(m.group(2))
        for e in m.group(3).split(','):
            p = e.split(':')
            if len(p) >= 4 and p[1] == 'armcom':
                track[(team, p[0])].append((frame, float(p[2]), float(p[3])))
    out = collections.Counter()
    for (team, uid), pts in track.items():
        pts.sort()
        walked = sum(math.hypot(pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2])
                     for i in range(1, len(pts)))
        net = math.hypot(pts[-1][1] - pts[0][1], pts[-1][2] - pts[0][2]) if pts else 0.0
        side = 'us' if (team < 2) == ap0 else 'them'
        out[(side, 'walked')] += walked
        out[(side, 'net')] += net
        out[(side, 'n')] += 1
    return out


def main():
    until = 6
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if '--until' in sys.argv:
        until = int(sys.argv[sys.argv.index('--until') + 1])
    for T in args:
        acc = collections.Counter()
        for M in sorted(glob.glob(os.path.join(T, 'matches', 't*'))):
            if os.path.exists(os.path.join(M, 'infolog.txt')):
                acc.update(one(M, until))
        print('==', os.path.basename(os.path.normpath(T)), 'to minute', until)
        for side in ('us', 'them'):
            n = max(acc[(side, 'n')], 1)
            w = acc[(side, 'walked')] / n
            net = acc[(side, 'net')] / n
            print('  %-5s walked %6.0f   net %5.0f   churn %4.1f   (%d commanders)'
                  % (side, w, net, w / max(net, 1.0), n))


if __name__ == '__main__':
    main()
