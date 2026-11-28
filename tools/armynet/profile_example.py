#!/usr/bin/env python3
"""Where building one training example spends its time (the trainer waits on this when the GPU idles).

    python tools/armynet/profile_example.py [N games] [examples per game]
"""
import cProfile
import glob
import pstats
import random
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import Game  # noqa: E402


def main(a):
    n = int(a[0]) if a else 4
    per = int(a[1]) if len(a) > 1 else 30
    files = sorted(glob.glob("G:/bar-ai-archive/public-replays/recordings/*/*.npz"))
    random.seed(1)
    picks = random.sample(files, n)
    t0 = time.time()
    games = [Game(p) for p in picks]
    load = time.time() - t0
    pr = cProfile.Profile()
    t0 = time.time()
    pr.enable()
    count = 0
    for g in games:
        for t, f in random.sample(g.examples, min(per, len(g.examples))):
            g.example(t, f)
            count += 1
    pr.disable()
    dt = time.time() - t0
    print("load %.2f s for %d games; %d examples in %.2f s = %.1f ms each" % (load, n, count, dt, 1000 * dt / max(count, 1)))
    pstats.Stats(pr).sort_stats("cumulative").print_stats(18)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
