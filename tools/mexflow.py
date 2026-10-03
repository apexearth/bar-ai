#!/usr/bin/env python3
"""Extractor flow per side: built, lost, standing, by time window.

    python tools/mexflow.py <match-dir> [...] [--step 4] [--to 20]

Answers "do we not claim, or do we not keep?" Per side (us / them) and per
window: T1 extractors finished (claims and rebuilds), T2 finished (upgrades),
finished extractors destroyed (losses; a T1 removed by its own upgrade is not
counted -- it dies in the same frame its moho finishes), and standing at the
window's end. Medians are per seat, so 8v8 and 2v2 read alike.
"""
from __future__ import annotations

import re
import statistics
import sys
from pathlib import Path

FPM = 1800
BUILD_RE = re.compile(r"\[BARAI_BUILD\] team=(\d+) ally=(\d+) frame=(\d+) min=[\d.]+ unit=(\S+)")
DEATH_RE = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\S+) .*? built=1 .*?atkteam=(-?\d+)")
ECO_RE = re.compile(r"eco-status team=(\d+) growing=1")
MEX = re.compile(r"mex|moho|uwmme")
T2 = re.compile(r"moho|uwmme")


def main() -> int:
    args = sys.argv[1:]
    step, to = 4, 20
    for flag in ("--step", "--to"):
        if flag in args:
            i = args.index(flag)
            v = int(args[i + 1])
            del args[i:i + 2]
            step, to = (v, to) if flag == "--step" else (step, v)
    wins = list(range(0, to, step))
    rows = {}   # (side, window) -> list of per-seat tuples
    for a in args:
        text = (Path(a) / "infolog.txt").read_text(encoding="utf8", errors="ignore")
        ally = {}
        ev = []
        for m in BUILD_RE.finditer(text):
            t = int(m.group(1))
            ally[t] = int(m.group(2))
            if MEX.search(m.group(4)):
                ev.append((int(m.group(3)), t, "t2" if T2.search(m.group(4)) else "t1"))
        up_frames = {(f, t) for f, t, k in ev if k == "t2"}
        for m in DEATH_RE.finditer(text):
            f, t, u, atk = int(m.group(1)), int(m.group(2)), m.group(3), int(m.group(4))
            if not MEX.search(u):
                continue
            if atk < 0 and not T2.search(u) and any((f - d, t) in up_frames for d in range(0, 3)):
                continue   # the T1 under a finished moho
            ev.append((f, t, "lost"))
        eco = ECO_RE.search(text)
        us = ally.get(int(eco.group(1)), 0) if eco else 0
        ecoT = int(eco.group(1)) if eco else -1
        for t in ally:
            if t == ecoT:
                continue
            side = "us" if ally[t] == us else "them"
            for w0 in wins:
                lo, hi = w0 * FPM, (w0 + step) * FPM
                b1 = sum(1 for f, tt, k in ev if tt == t and lo < f <= hi and k == "t1")
                b2 = sum(1 for f, tt, k in ev if tt == t and lo < f <= hi and k == "t2")
                lost = sum(1 for f, tt, k in ev if tt == t and lo < f <= hi and k == "lost")
                stand = (sum(1 for f, tt, k in ev if tt == t and f <= hi and k in ("t1",))
                         - sum(1 for f, tt, k in ev if tt == t and f <= hi and k == "lost"))
                rows.setdefault((side, w0), []).append((b1, b2, lost, stand))
    print(f"per normal seat, median over {len(args)} match(es) (eco seat excluded)")
    print("  window   side   T1built  T2built   lost  standing")
    for w0 in wins:
        for side in ("us", "them"):
            r = rows.get((side, w0), [])
            if not r:
                continue
            med = [statistics.median(x[i] for x in r) for i in range(4)]
            mean = [sum(x[i] for x in r) / len(r) for i in range(3)]
            print(f"  {w0:2}-{w0 + step:<2}    {side:<5} {med[0]:5.1f} ({mean[0]:4.1f}) {med[1]:4.1f} ({mean[1]:3.1f}) "
                  f"{med[2]:4.1f} ({mean[2]:3.1f}) {med[3]:6.1f}")
    print("  (median (mean)); standing counts T1 finished minus losses -- an upgrade keeps the spot")
    return 0


if __name__ == "__main__":
    sys.exit(main())
