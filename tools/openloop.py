"""The early-game iteration loop: short games at high speed, scored on the
state at minute 4 and 6 rather than on a winner (his 2026-09-22 direction --
"20+x speed ~6m games and rapidly iterate over improving the early game").

    python tools/openloop.py run  [--name X] [--games 16] [--minutes 6]
                                  [--speed 20] [--workers 4] [--spec S]
                                  [--modoption K=V]...
    python tools/openloop.py read <tournament-dir> [<tournament-dir> ...]

What it scores, per side, at minutes 4 and 6 (ours = whichever is not BARb):

    mex       standing extractors -- the minute-4 predictor (tools/mex4.py:
              +1 mex at minute 4 is a 44% win rate against 5% behind)
    guarded   share of our extractors with one of our guns within 350 elmo
    army      standing army metal
    lost      metal of FINISHED units lost (a nanoframe's `cost` is the def's
              full cost, so unfinished frames are excluded -- see perminute.py)
    theirCon  enemy constructors killed (the harassment read)
    theirMex  enemy extractors killed

A batch takes about a minute; compare a treatment against a control run the
same way, and read `tools/perminute.py` on one game of each before believing
a difference.
"""
import collections
import glob
import json
import os
import re
import subprocess
import sys
import math

TOWERS = ('armllt', 'armbeamer', 'armhlt', 'armguard', 'armpb', 'armclaw',
          'armamb', 'armanni', 'cordoom', 'corllt', 'corhllt', 'corpun')
CONS = ('armck', 'armcv', 'armch', 'armack', 'armacv', 'armbeaver', 'armfark',
        'armconsul', 'corck', 'corcv', 'corch', 'corack')
MEXES = ('armmex', 'armmoho', 'cormex', 'cormoho')


def run(argv):
    name = 'openloop'
    games, minutes, speed, workers = 16, 6, 20, 4
    spec = 'Apexwinrate:lane-winrate:standard'
    mods = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--name':
            name = argv[i + 1]; i += 2
        elif a == '--games':
            games = int(argv[i + 1]); i += 2
        elif a == '--minutes':
            minutes = int(argv[i + 1]); i += 2
        elif a == '--speed':
            speed = int(argv[i + 1]); i += 2
        elif a == '--workers':
            workers = int(argv[i + 1]); i += 2
        elif a == '--spec':
            spec = argv[i + 1]; i += 2
        elif a == '--modoption':
            mods += ['--modoption', argv[i + 1]]; i += 2
        else:
            i += 1
    cmd = [sys.executable, 'tools/run_tournament.py',
           '--a', spec, '--b', 'BARb:stable:hard',
           '--maps', 'Glacier Pass', '--games', str(games),
           '--minutes', str(minutes), '--speed', str(speed),
           '--per-side', '2', '--sides', 'Armada,Armada', '--handicap', '100',
           '--box-size', '0.2', '--boxes', 'lr', '--workers', str(workers),
           '--name', name] + mods
    subprocess.run(cmd, check=False)
    newest = max(glob.glob('tournaments/*-' + name), key=os.path.getmtime)
    read([newest])


def one(match_dir):
    with open(os.path.join(match_dir, 'infolog.txt'), encoding='utf-8', errors='replace') as fh:
        txt = fh.read()
    with open(os.path.join(match_dir, 'script.txt')) as fh:
        script = fh.read()
    ai0 = re.search(r'\[AI0\](.*?)\[AI1\]', script, re.S).group(1)
    ap0 = 'Apex' in ai0
    side = lambda t: ('us' if (t < 2) == ap0 else 'them')
    out = {}
    pos = collections.defaultdict(lambda: collections.defaultdict(list))
    for m in re.finditer(r'\[BARAI_POS\] team=(\d) ally=\d frame=(\d+) n=\d+ part=\d+/\d+ (\S*)', txt):
        minute = int(m.group(2)) // 1800
        for e in m.group(3).split(','):
            p = e.split(':')
            if len(p) >= 3:
                pos[(minute, side(int(m.group(1))))][p[0]].append((float(p[1]), float(p[2])))
    army = collections.Counter()
    for m in re.finditer(r'\[BARAI_STATS\] team=(\d) ally=\d reason=periodic frame=(\d+) .*?mArmy=([\d.]+)', txt):
        army[(int(m.group(2)) // 1800, side(int(m.group(1))))] += float(m.group(3))
    lost = collections.Counter()
    kill = collections.Counter()
    for m in re.finditer(r'\[BARAI_DEATH\] frame=(\d+) team=(\d) unit=(\S+) cost=(\d+) .*?built=(\d) ', txt):
        minute = int(m.group(1)) // 1800
        sd = side(int(m.group(2)))
        if m.group(5) != '1':
            continue
        lost[(minute, sd)] += int(m.group(4))
        if sd == 'them':
            if m.group(3) in CONS:
                kill[(minute, 'con')] += 1
            elif m.group(3) in MEXES:
                kill[(minute, 'mex')] += 1
    for minute in (4, 6):
        for sd in ('us', 'them'):
            p = pos[(minute, sd)]
            mex = [xz for u in MEXES for xz in p.get(u, [])]
            guns = [xz for u in TOWERS for xz in p.get(u, [])]
            covered = sum(1 for (x, z) in mex
                          if any(math.hypot(x - gx, z - gz) <= 350 for gx, gz in guns))
            cum = sum(lost[(k, sd)] for k in range(minute + 1))
            out[(minute, sd)] = dict(mex=len(mex), guarded=covered, army=army[(minute, sd)], lost=cum)
        out[(minute, 'kills')] = dict(
            con=sum(kill[(k, 'con')] for k in range(minute + 1)),
            mex=sum(kill[(k, 'mex')] for k in range(minute + 1)))
    return out


def read(dirs):
    for T in dirs:
        acc = collections.defaultdict(collections.Counter)
        n = 0
        for M in sorted(glob.glob(os.path.join(T, 'matches', 't*'))):
            if not os.path.exists(os.path.join(M, 'infolog.txt')):
                continue
            n += 1
            for k, v in one(M).items():
                for f, x in v.items():
                    acc[k][f] += x
        print('==', os.path.basename(os.path.normpath(T)), '(%d games)' % n)
        if not n:
            continue
        print('  min  side |  mex  guarded   army    lost | their cons/mexes killed')
        for minute in (4, 6):
            for sd in ('us', 'them'):
                a = acc[(minute, sd)]
                extra = ''
                if sd == 'us':
                    k = acc[(minute, 'kills')]
                    extra = '  %d / %d' % (k['con'] / n, k['mex'] / n) if n else ''
                print('  %3d  %-4s | %4.1f %6.1f %7.0f %7.0f |%s'
                      % (minute, sd, a['mex'] / n, a['guarded'] / n, a['army'] / n, a['lost'] / n, extra))


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'run':
        run(sys.argv[2:])
    else:
        read([a for a in sys.argv[1:] if not a.startswith('--')] or
             [max(glob.glob('tournaments/*'), key=os.path.getmtime)])
