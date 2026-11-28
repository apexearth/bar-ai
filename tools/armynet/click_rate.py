#!/usr/bin/env python3
"""How fast players re-order a unit (his 11-19: "if its kiting probably can efficiently do it 2 or 3 times a second").

    python tools/armynet/click_rate.py [N recordings]

From the recordings' C lines (every click, at its frame): for army and air units, the time between one order to a unit
and the next. Split by whether an enemy army unit stood within 800 of it at the nearest 1-s sample (in a fight) or
not. Prints the share of re-orders within 0.2 / 0.33 / 0.5 / 1 / 1.5 s and the median, and the share of a unit's
in-fight seconds that hold 2+ orders.
"""
import collections
import glob
import gzip
import random
import sys

import numpy as np

FIGHT_R = 800.0


def one(path):
    cls, ally = {}, {}
    pos = collections.defaultdict(dict)   # frame -> uid -> (x, z, team)
    clicks = collections.defaultdict(list)
    for ln in gzip.open(path, "rt", errors="replace"):
        p = ln.split()
        if not p:
            continue
        k = p[0]
        if k == "D":
            cls[int(p[1])] = p[3]
        elif k == "T":
            ally[int(p[1])] = int(p[2])
        elif k == "U":
            f, uid, d, t = int(p[1]), int(p[2]), int(p[3]), int(p[4])
            if cls.get(d) in ("army", "air"):
                pos[f][uid] = (float(p[5]), float(p[6]), t)
        elif k == "C":
            f, t, uid, d, cmd = int(p[1]), int(p[2]), int(p[3]), int(p[4]), int(p[5])
            if cls.get(d) in ("army", "air") and cmd in (10, 16, 20, 15, 21, 0):
                clicks[uid].append(f)
    frames = np.array(sorted(pos))
    fight_iv, calm_iv = [], []
    for uid, fs in clicks.items():
        fs = sorted(fs)
        for a, b in zip(fs, fs[1:]):
            if b == a:
                continue
            i = int(np.searchsorted(frames, a, "right")) - 1
            if i < 0:
                continue
            snap = pos[frames[i]]
            me = snap.get(uid)
            if me is None:
                continue
            x, z, t = me
            fight = any(ally.get(t2, -1) != ally.get(t, -2) and (x2 - x) ** 2 + (z2 - z) ** 2 <= FIGHT_R ** 2
                        for x2, z2, t2 in snap.values())
            (fight_iv if fight else calm_iv).append((b - a) / 30.0)
    return fight_iv, calm_iv


def main(a):
    n = int(a[0]) if a else 20
    files = sorted(glob.glob("G:/bar-ai-archive/public-replays/recordings/*/orders.txt.gz"))
    random.seed(7)
    fight, calm = [], []
    for p in random.sample(files, min(n, len(files))):
        f, c = one(p)
        fight += f
        calm += c
    for name, v in (("in a fight", fight), ("not in a fight", calm)):
        v = np.array(v)
        if not len(v):
            continue
        print("%-15s re-orders %7d  median %.2f s  within 0.2 s %.0f%%  0.33 s %.0f%%  0.5 s %.0f%%  1 s %.0f%%  1.5 s %.0f%%"
              % (name, len(v), np.median(v), *(100 * np.mean(v <= t) for t in (0.2, 0.33, 0.5, 1.0, 1.5))))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
