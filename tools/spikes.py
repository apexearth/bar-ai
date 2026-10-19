"""Where a game suddenly slows: sim speed in short windows, and what the AI logged in the slow ones.

The per-minute frame times hide a burst. This reads the [t=wall][f=frame] stamps, takes the wall seconds
each WINDOW frames took, flags windows slower than SLOW x the game's median, and for each flagged window
prints the `apex: <kind>` line counts that are most over-represented against the windows around it.

Usage: spikes.py <match> [--window 300] [--slow 2.0] [--top 8]
"""
import re
import statistics
import sys
from collections import Counter
from pathlib import Path

STAMP = re.compile(r"^\[t=(\d+):(\d+):([0-9.]+)\]\[f=(-?\d+)\]")
KIND = re.compile(r"apex: ([a-z][a-z0-9-]*)")


def arg(name, default):
    if name in sys.argv:
        return type(default)(sys.argv[sys.argv.index(name) + 1])
    return default


def main():
    path = Path(sys.argv[1])
    log = path / "infolog.txt" if path.is_dir() else path
    win = arg("--window", 300)
    slow = arg("--slow", 2.0)
    top = arg("--top", 8)
    first_wall = {}
    kinds = {}
    with open(log, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = STAMP.match(line)
            if not m:
                continue
            f = int(m.group(4))
            if f < 0:
                continue
            w = f // win
            wall = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))
            first_wall.setdefault(w, wall)
            k = KIND.search(line)
            if k:
                kinds.setdefault(w, Counter())[k.group(1)] += 1
    ws = sorted(first_wall)
    dur = {w: first_wall[w + 1] - first_wall[w] for w in ws if (w + 1) in first_wall}
    if not dur:
        print("no windows")
        return
    med = statistics.median(dur.values())
    print("window %d frames (%.0f s of game): median %.2f s wall; slow >= %.1fx" % (win, win / 30.0, med, slow))
    for w in sorted(dur):
        if dur[w] < slow * med:
            continue
        around = Counter()
        n = 0
        for o in (w - 3, w - 2, w - 1, w + 1, w + 2, w + 3):
            if o in kinds and o in dur and dur[o] < slow * med:
                around.update(kinds[o])
                n += 1
        here = kinds.get(w, Counter())
        score = []
        for k, c in here.items():
            base = (around[k] / n) if n else 0.0
            score.append(((c + 1.0) / (base + 1.0), c, base, k))
        score.sort(reverse=True)
        print("\n%5.1f min  %.2f s wall (%.1fx median)" % (w * win / 1800.0, dur[w], dur[w] / med))
        for ratio, c, base, k in score[:top]:
            print("    %-24s %6d  vs %8.1f around  (x%.1f)" % (k, c, base, ratio))


if __name__ == "__main__":
    main()
