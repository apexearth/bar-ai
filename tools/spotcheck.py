#!/usr/bin/env python3
"""Which of our structures stand on a metal spot.

    python tools/spotcheck.py <match-dir|infolog> [...]

Reads the `apex: spots` table each team logs once and tests every
`apex: placed` footprint against it, the same half-sum test NoteSquatter
runs in-game. Extractors are skipped. Prints one line per squatter and a
count per team; exit 1 if any.
"""
import re
import sys
from pathlib import Path

SPOTS = re.compile(r"apex: spots t=(\d+) n=(\d+)((?: -?\d+,-?\d+)*)")
PLACED = re.compile(r"apex: placed t=(\d+) (\w+) at=(-?\d+),(-?\d+) foot=(\d+)x(\d+)")
MEX = ("armmex", "cormex", "legmex", "armmoho", "cormoho", "legmoho",
       "armuwmme", "coruwmme", "armamex", "coramex", "armuwmex", "coruwmex")
MEX_FOOT = 3  # T1 mex, in 16-elmo cells


def main(paths):
    bad = 0
    for arg in paths:
        p = Path(arg)
        log = p / "infolog.txt" if p.is_dir() else p
        text = log.read_text(errors="replace")
        spots = {}
        for m in SPOTS.finditer(text):
            spots[m.group(1)] = [tuple(map(int, xy.split(","))) for xy in m.group(3).split()]
        per = {}
        for m in PLACED.finditer(text):
            t, name, x, z, fx, fz = m.groups()
            if name in MEX or t not in spots:
                continue
            x, z, fx, fz = int(x), int(z), int(fx), int(fz)
            hx = 8 * (fx + MEX_FOOT) - 8
            hz = 8 * (fz + MEX_FOOT) - 8
            for sx, sz in spots[t]:
                if abs(x - sx) < hx and abs(z - sz) < hz:
                    per[t] = per.get(t, 0) + 1
                    bad += 1
                    print(f"{log.parent.name}: t={t} {name} at={x},{z} on spot {sx},{sz}")
                    break
        n = sum(1 for _ in PLACED.finditer(text))
        print(f"{log.parent.name}: {n} placed, spots logged for teams {sorted(spots)}, squatters {per or 0}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or ["latest"]))
