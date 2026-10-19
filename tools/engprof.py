"""Read dev_engine_profile.lua's ENGPROF lines: what the engine spent its time on when a game slowed.

Each line is one window (150 game frames): its wall ms and the engine profiler's sections that grew most
in it. This flags windows slower than SLOW x the median and lists, for each, the sections against their
median over all windows -- the part that blew up. Then each AI's own timer (AI::{id=..}) summed over
the game, which separates our AI from BARb's.

Usage: engprof.py <match> [--slow 2.0] [--top 10]
"""
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

LINE = re.compile(r"ENGPROF f=(\d+) wallMs=([0-9.]+)(.*)$")
ITEM = re.compile(r" ((?:AI::{[^}]*})|[^ =]+)=([0-9.]+)")


def arg(name, default):
    if name in sys.argv:
        return type(default)(sys.argv[sys.argv.index(name) + 1])
    return default


def main():
    path = Path(sys.argv[1])
    log = path / "infolog.txt" if path.is_dir() else path
    slow = arg("--slow", 2.0)
    top = arg("--top", 10)
    wins = []
    with open(log, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = LINE.search(line)
            if not m:
                continue
            secs = {k: float(v) for k, v in ITEM.findall(m.group(3))}
            wins.append((int(m.group(1)), float(m.group(2)), secs))
    if not wins:
        print("no ENGPROF lines (was apex_engine_profile=1 set and the gadget deployed?)")
        return
    med_wall = statistics.median(w[1] for w in wins)
    per = defaultdict(list)
    for _, _, s in wins:
        for k, v in s.items():
            per[k].append(v)
    med = {k: statistics.median(v + [0.0] * (len(wins) - len(v))) for k, v in per.items()}
    print("%d windows of 150 frames; median wall %.0f ms (5 s of game at 1x would be 5000)" % (len(wins), med_wall))
    for f, wall, s in wins:
        if wall < slow * med_wall:
            continue
        rows = sorted(s.items(), key=lambda kv: -(kv[1] - med.get(kv[0], 0.0)))
        print("\n%5.1f min  wall %.0f ms (%.1fx)" % (f / 1800.0, wall, wall / med_wall))
        for k, v in rows[:top]:
            print("    %-58s %9.1f ms  (median %8.1f)" % (k[:58], v, med.get(k, 0.0)))
    ai = defaultdict(float)
    with open(log, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "ENGPROF-AI " in line:
                for k, v in re.findall(r" (AI::{[^ ]*})=([0-9.]+)", line):
                    ai[k] += float(v)
    if not ai:
        ai = {k: sum(v) for k, v in per.items() if k.startswith("AI::{")}
    if ai:
        print("\nper-AI engine timer over the game (ms):")
        for k, v in sorted(ai.items(), key=lambda kv: -kv[1]):
            print("    %-60s %10.0f" % (k[:60], v))


if __name__ == "__main__":
    main()
