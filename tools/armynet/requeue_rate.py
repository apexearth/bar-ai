#!/usr/bin/env python3
"""Queue every recording sampled once a second to be recorded again at STEP (11-19: mobile units every 10 frames, his
"under 500 milliseconds"): orders.txt.gz becomes orders.1hz.txt.gz (kept, not deleted), so the recorder sees the
replay as not done and replay_dataset.py builds from the kept file until the new recording arrives.

    python tools/armynet/requeue_rate.py [--dry]
"""
import glob
import gzip
import os
import sys


def sampled_per_second(path):
    """True when the first 400 distinct mobile-sample frames all fall on 30-frame marks (the old recorder)"""
    frames = set()
    with gzip.open(path, "rt", errors="replace") as fh:
        for ln in fh:
            if ln.startswith("U "):
                frames.add(int(ln.split()[1]))
                if len(frames) >= 400:
                    break
    return bool(frames) and all(f % 30 == 0 for f in frames) and max(frames) > 900


def main(a):
    n = 0
    for root in ("G:/bar-ai-archive/public-replays/recordings", "G:/bar-ai-archive/replay-orders"):
        for p in glob.glob(root + "/*/orders.txt.gz"):
            if sampled_per_second(p):
                n += 1
                kept = p.replace("orders.txt.gz", "orders.1hz.txt.gz")
                if "--dry" not in a and not os.path.exists(kept):
                    os.replace(p, kept)
    print("%s %d recordings sampled once a second" % ("would requeue" if "--dry" in a else "requeued", n))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
