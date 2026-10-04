"""Constructors that claim a far extractor and then walk home instead of on.

    python tools/walkback.py <match-or-game-dir>... [--far 1500] [--home 800]

Reads `apex: exec` (each job a builder takes, with its site) and the `apex:
decide` line of the same builder at the same frame (why it won, and what came
second). A WALK-BACK is a mex job ending more than --far elmos from home whose
very next job is within --home elmos of home. Home is our first lab's site.
"""
import argparse
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

EXEC = re.compile(r"\[f=0*(\d+)\].*apex: exec t=0 (\w+) #(\d+) (\w+):(\w*) pick=\d+ at=(-?[\d.]+),(-?[\d.]+)")
DECIDE = re.compile(r"\[f=0*(\d+)\].*apex: decide t=0 (\w+) #(\d+) -> ([a-z]+/[a-z]+):?\w* .*?why=(\w+)(?: role=\w+)?(?: over ([a-z]+/[a-z]+))?")


def read(path: Path):
    txt = (path / "stdout.txt").read_text("utf-8", errors="replace")
    jobs = defaultdict(list)
    home = None
    for m in EXEC.finditer(txt):
        f, unit, uid, kind, d, x, z = m.groups()
        if home is None and kind == "plant":
            home = (float(x), float(z))
        jobs[uid].append((int(f), unit, kind, d, float(x), float(z)))
    why = {}
    for m in DECIDE.finditer(txt):
        f, unit, uid, cat, w, over = m.groups()
        why[(uid, int(f))] = (cat, w, over or "-")
    return home, jobs, why


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--far", type=float, default=1500.0)
    ap.add_argument("--home", type=float, default=800.0)
    a = ap.parse_args()
    nextjob, reasons, units = Counter(), Counter(), Counter()
    mexfar = backs = 0
    for d in a.dirs:
        p = Path(d)
        if not (p / "stdout.txt").exists():
            continue
        home, jobs, why = read(p)
        if home is None:
            continue
        for uid, seq in jobs.items():
            for (f0, unit, k0, d0, x0, z0), (f1, _, k1, d1, x1, z1) in zip(seq, seq[1:]):
                if k0 != "mex" or math.hypot(x0 - home[0], z0 - home[1]) < a.far:
                    continue
                mexfar += 1
                if math.hypot(x1 - home[0], z1 - home[1]) <= a.home:
                    backs += 1
                    units[unit] += 1
                    nextjob[f"{k1}:{d1}"] += 1
                    w = why.get((uid, f1))
                    reasons[f"{w[0]} why={w[1]} over {w[2]}" if w else "(no decide line)"] += 1
    print(f"far extractor jobs: {mexfar}; next job back at home: {backs} ({100.0 * backs / max(1, mexfar):.0f}%)")
    print("builders:", dict(units.most_common()))
    print("what they walked home to build:")
    for k, n in nextjob.most_common(10):
        print(f"  {n:4d}  {k}")
    print("why it won (category, reason, runner-up):")
    for k, n in reasons.most_common(12):
        print(f"  {n:4d}  {k}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
