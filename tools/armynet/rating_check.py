#!/usr/bin/env python3
"""What the order rating encodes (11-19 review): how much of the score is explained by side and 30-s window (who was
ahead, not what the order did), and the mean training weight of winners' and losers' orders.

    python tools/armynet/rating_check.py [N games]
"""
import glob
import random
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import Game  # noqa: E402


def main(a):
    n = int(a[0]) if a and a[0].isdigit() else 40
    root = a[a.index("--dir") + 1] if "--dir" in a else "G:/bar-ai-archive/public-replays/recordings/*"
    files = sorted(glob.glob(root + "/*.npz"))
    random.seed(5)
    within, total, w_win, w_lose, below = 0.0, 0.0, [], [], []
    for p in random.sample(files, min(n, len(files))):
        try:
            g = Game(p)
        except Exception:
            continue
        s = getattr(g, "dec_score", None)
        if s is None or not len(s):
            continue
        d = g.decisions
        key = d[:, 2].astype(np.int64) * 100000 + (d[:, 1] // 900).astype(np.int64)
        means = {k: s[key == k].mean() for k in np.unique(key)}
        fitted = np.array([means[k] for k in key])
        total += ((s - s.mean()) ** 2).sum()
        within += ((s - fitted) ** 2).sum()
        w = np.exp(0.5 * s)
        res = g.result
        w_win.extend(w[res == 1].tolist())
        w_lose.extend(w[res == 0].tolist())
        below.extend((s < 0).tolist())
    print("score variance explained by side x 30-s window: %.0f%%" % (100 * (1 - within / max(total, 1e-9))))
    print("mean weight: winners' orders %.2f, losers' %.2f; orders scored below 0: %.1f%%" % (
        np.mean(w_win), np.mean(w_lose), 100 * np.mean(below)))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
