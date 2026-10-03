#!/usr/bin/env python3
"""What each of our seats' builders chose, by want kind, in a time window.

    python tools/seatjobs.py <apex-log-dir> [--from 12] [--to 20]

Reads the per-team apex logs a lane run leaves (apex-tN.log) -- every
`apex: decide <unit> -> <cat>/<kind>` line in the window -- and prints the share
of decisions per kind for each seat, plus how many were T2 hands. Decisions,
not completed builds: read it beside seatbuilds.py.
"""
from __future__ import annotations

import collections
import re
import sys
from pathlib import Path

DEC_RE = re.compile(r"\[([0-9.]+)m t(\d+)\] apex: decide t=\d+ (\w+) #\d+ -> (\w+)/(\w+)")
DEC2_RE = re.compile(r"\[f=(\d+)\].*?apex: decide t=(\d+) (\w+) #\d+ -> (\w+)/(\w+)")
T2 = {"armack", "armacv", "armaca", "armacsub", "corack", "coracv", "coraca", "legack", "legacv", "legaca"}


def main() -> int:
    args = sys.argv[1:]
    lo, hi = 12.0, 20.0
    for flag in ("--from", "--to"):
        if flag in args:
            i = args.index(flag)
            v = float(args[i + 1])
            del args[i:i + 2]
            if flag == "--from":
                lo = v
            else:
                hi = v
    d = Path(args[0])
    kinds_all = collections.Counter()
    per = {}
    for f in sorted(d.glob("apex-t*.log")):
        if ".prev" in f.name:
            continue
        c = collections.Counter()
        t2 = 0
        n = 0
        for line in f.read_text(encoding="utf8", errors="ignore").splitlines():
            m = DEC2_RE.search(line)
            if not m:
                continue
            mins = int(m.group(1)) / 1800.0
            if not (lo <= mins < hi):
                continue
            k = m.group(5) if m.group(5) != "-" else m.group(4)
            c[k] += 1
            n += 1
            if m.group(3) in T2:
                t2 += 1
        if n:
            per[f.stem] = (c, n, t2)
            kinds_all.update(c)
    top = [k for k, _ in kinds_all.most_common(10)]
    print(f"decisions {lo:g}-{hi:g} min, % of each seat's decisions (n = count, t2 = by T2 hands)")
    print("  seat    n   t2 " + " ".join(f"{k[:7]:>7}" for k in top))
    for s, (c, n, t2) in per.items():
        print(f"  {s[5:]:<5} {n:4} {t2:4} " + " ".join(f"{100 * c[k] / n:7.0f}" for k in top))
    return 0


if __name__ == "__main__":
    sys.exit(main())
