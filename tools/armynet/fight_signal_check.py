#!/usr/bin/env python3
"""Do the fight inputs (columns 39-41) tell retreats apart? For units the player ordered: those sent back by 0.1+ of
the way toward their own buildings (retreats) against the rest, mean of each input.

    python tools/armynet/fight_signal_check.py <dataset .npz> ...
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import G, Game  # noqa: E402
from train import base_axis  # noqa: E402

ret, rest = [], []
for p in sys.argv[1:]:
    g = Game(p)
    for t, f in g.examples[::3]:
        ex = g.example(t, f)
        if not (ex["act"] > 0).any():
            continue
        axis = base_axis(ex["grid"], g.mapx / G, g.mapz / G, g.mapx, g.mapz)
        for j in np.where(ex["act"] > 0)[0]:
            c = ex["tcell"][j]
            tx = (c % G + ex["toff"][j, 0]) / G * g.mapx
            tz = (c // G + ex["toff"][j, 1]) / G * g.mapz
            ux, uz = ex["tok"][j, 10] * g.mapx, ex["tok"][j, 11] * g.mapz
            (ret if axis(tx, tz) < axis(ux, uz) - 0.1 else rest).append(ex["tok"][j, 39:42])
ret, rest = np.array(ret), np.array(rest)
names = ("health change 5 s", "enemy-minus-ours nearby (log)", "our recent losses nearby (log)")
print("orders: retreats %d, others %d" % (len(ret), len(rest)))
for k, n in enumerate(names):
    print("  %-32s retreats %+.3f   others %+.3f" % (n, ret[:, k].mean(), rest[:, k].mean()))
