"""Constructor and extractor deaths per AI, by minute and by how far forward.

    python tools/condeaths.py <tournament-or-match-dir> [--to 16]

From `apex: unit-destroyed` (each Apex AI logs its own losses). fwd is the
death's forward fraction: 0 at our home, 1 at theirs. The AI is named by the
log prefix (`Skirmish AI <ApexUnstable-v0.1.2>`), so a head-to-head of two
Apex versions separates cleanly.
"""
import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

LINE = re.compile(r"Skirmish AI <[^>]*?-([\w.]+)>: \[[\d.]+m t(\d+)\] apex: unit-destroyed (\w+) .*?frame=(\d+) .*?cost=(\d+) fwd=([\d.-]+)")
CONS = {"armck", "corck", "armcv", "corcv", "armca", "corca", "legck", "legcv", "legca"}
MEX = {"armmex", "cormex", "legmex", "armmoho", "cormoho"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--to", type=float, default=16.0)
    a = ap.parse_args()
    files = sorted(f for p in a.paths for f in Path(p).glob("**/stdout.txt"))
    agg = defaultdict(lambda: defaultdict(list))
    games = defaultdict(set)
    for f in files:
        for m in LINE.finditer(f.read_text("utf-8", errors="replace")):
            ver, team, unit, frame, cost, fwd = m.groups()
            minute = int(frame) / 1800.0
            if minute > a.to:
                continue
            games[ver].add(f.parent.name)
            kind = "con" if unit in CONS else ("mex" if unit in MEX else None)
            if kind:
                agg[ver][kind].append((minute, float(fwd)))
    for ver in sorted(agg):
        n = max(1, len(games[ver]))
        print(f"\n{ver}  ({len(games[ver])} games, to minute {a.to:g})")
        for kind in ("con", "mex"):
            v = agg[ver][kind]
            far = [x for x in v if x[1] > 0.35]
            early = [x for x in v if x[0] <= 10]
            print(f"  {kind}: {len(v) / n:5.1f} lost/game   by minute 10: {len(early) / n:4.1f}   "
                  f"past 35% of the way to them: {len(far) / n:4.1f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
