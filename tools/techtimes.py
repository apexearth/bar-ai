#!/usr/bin/env python3
"""When each seat started and finished its first T2 lab, per side.

    python tools/techtimes.py <match-dir> [...]

From each team's last [BARAI_STATS] (techStart = first T2 plant ordered/framed,
techFrame = first T2 plant finished, -1 = never). Our eco seat is listed apart.
Prints every seat's minutes and the per-side distribution, so a median cannot
hide the seats that tech late or never.
"""
from __future__ import annotations

import re
import statistics
import sys
from pathlib import Path

STATS_RE = re.compile(r"\[BARAI_STATS\] team=(\d+) ally=(\d+) \S+ frame=(\d+) .*?techFrame=(-?\d+) techStart=(-?\d+)")
ECO_RE = re.compile(r"eco-status team=(\d+) growing=1")


def main() -> int:
    rows = {"us": [], "us-eco": [], "them": []}
    for a in sys.argv[1:]:
        text = (Path(a) / "infolog.txt").read_text(encoding="utf8", errors="ignore")
        last = {}
        for m in STATS_RE.finditer(text):
            last[int(m.group(1))] = (int(m.group(2)), int(m.group(4)), int(m.group(5)))
        eco = ECO_RE.search(text)
        ecoT = int(eco.group(1)) if eco else -1
        us = last.get(ecoT, (0,))[0]
        for t, (al, done, start) in last.items():
            kind = "them" if al != us else ("us-eco" if t == ecoT else "us")
            rows[kind].append((start / 1800 if start > 0 else None, done / 1800 if done > 0 else None))
    for kind, r in rows.items():
        if not r:
            continue
        st = sorted(x[0] for x in r if x[0] is not None)
        dn = sorted(x[1] for x in r if x[1] is not None)
        never = sum(1 for x in r if x[1] is None)
        q = lambda a, p: a[int(p * (len(a) - 1))] if a else float("nan")
        print(f"{kind:<7} n={len(r):3}  start p25/med/p75 {q(st,.25):5.1f} {q(st,.5):5.1f} {q(st,.75):5.1f}"
              f"   done p25/med/p75 {q(dn,.25):5.1f} {q(dn,.5):5.1f} {q(dn,.75):5.1f}   never done: {never}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
