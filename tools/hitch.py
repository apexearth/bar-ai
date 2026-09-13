"""Find a hitch the AI's own clock cannot see.

`frametime.py` times what the AI does; a freeze in the engine or in LuaUI
(which headless loads too) never appears in any section. This reads the wall
stamps the engine puts on every infolog line and reports the largest gaps
between consecutive lines, what frame period they sit on, and the line before
and after each -- which is how the 10-second freeze of 2026-09-12 (S31) was
traced to one 25 KB console line.

    python tools/hitch.py <run-dir|infolog> [--top 8] [--min 0.3]
"""
import argparse
import collections
import os
import re
import sys

STAMP = re.compile(r'^\[t=(\d+):(\d+):(\d+\.\d+)\]\[f=(-?\d+)\]')
PERIODS = (300, 900, 1800, 150, 90, 60, 30, 15)


def scan(path):
    # The AI's own lines carry its own clock, a few hundred ms off the engine's
    # (tools/apexlog.py), so a gap is only measured between lines of one source.
    prev = {}
    gaps = []
    with open(path, encoding='utf-8', errors='replace') as fh:
        for line in fh:
            m = STAMP.match(line)
            if not m:
                continue
            t = int(m[1]) * 3600 + int(m[2]) * 60 + float(m[3])
            f = int(m[4])
            src = 'Skirmish AI <' in line
            p = prev.get(src)
            if p is not None and f > 0 and 0 <= f - p[1] <= 2:
                gaps.append((t - p[0], p[1], f, p[2], line.rstrip()))
            prev[src] = (t, f, line.rstrip())
    return gaps


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('run')
    ap.add_argument('--top', type=int, default=8)
    ap.add_argument('--min', type=float, default=0.3, help='seconds; gaps below are not counted')
    a = ap.parse_args()
    path = a.run if os.path.isfile(a.run) else os.path.join(a.run, 'infolog.txt')
    if not os.path.isfile(path):
        sys.exit(f'missing: {path}')
    gaps = scan(path)
    if not gaps:
        sys.exit('no stamped lines')
    big = [g for g in gaps if g[0] >= a.min and g[2] < max(x[2] for x in gaps) - 30]
    print(f'{path}: {len(gaps)} line pairs, {len(big)} gaps >= {a.min:.2f}s (game-over tail excluded)')
    if not big:
        return
    # which frame period the gaps sit on: a phase-locked stall names its owner
    # a console line is processed a frame or three after it was echoed
    for p in PERIODS:
        near = sum(1 for g in big if g[2] % p <= 3) / len(big)
        if near >= 0.7 and len(big) >= 3:
            print(f'  {near:.0%} of them sit within 3 frames after a frame % {p} == 0 boundary'
                  f' -- look for work scheduled every {p} frames ({p / 30:.0f}s)')
            break
    permin = collections.Counter(g[2] // 1800 for g in big)
    print('  per minute: ' + ' '.join(f'm{k}:{v}' for k, v in sorted(permin.items())))
    for g in sorted(big, reverse=True)[:a.top]:
        print(f'\n  {g[0]:.2f}s  frame {g[1]} -> {g[2]}  ({g[2] / 1800:.1f} min)')
        print(f'    before: {g[3][:140]}')
        print(f'    after:  {g[4][:140]}')


if __name__ == '__main__':
    main()
