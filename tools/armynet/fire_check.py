#!/usr/bin/env python3
"""Are the incoming-fire layers (25: hits on our units, 26: where they came from) filled, and do they tell retreats
apart? For units the player ordered: those sent back 0.1+ toward their own buildings against the rest, the layers'
value at the unit's cell.

    python tools/armynet/fire_check.py <dataset .npz> ...
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import G, Game  # noqa: E402
from train import base_axis  # noqa: E402

ret, rest, filled = [], [], []
for p in sys.argv[1:]:
    g = Game(p)
    for t, f in g.examples[::3]:
        ex = g.example(t, f)
        filled.append(((ex["grid"][25] > 0).any(), (ex["grid"][26] > 0).any()))
        if not (ex["act"] > 0).any():
            continue
        axis = base_axis(ex["grid"], g.mapx / G, g.mapz / G, g.mapx, g.mapz)
        for j in np.where(ex["act"] > 0)[0]:
            c = ex["tcell"][j]
            tx = (c % G + ex["toff"][j, 0]) / G * g.mapx
            tz = (c // G + ex["toff"][j, 1]) / G * g.mapz
            ux, uz = ex["tok"][j, 10] * g.mapx, ex["tok"][j, 11] * g.mapz
            cx, cz = int(min(ex["tok"][j, 10] * G, G - 1)), int(min(ex["tok"][j, 11] * G, G - 1))
            near = ex["grid"][25][max(cz - 1, 0):cz + 2, max(cx - 1, 0):cx + 2].max()
            (ret if axis(tx, tz) < axis(ux, uz) - 0.1 else rest).append(near)
f = np.array(filled)
print("examples with hits on us: %.0f%%, with a known shooter: %.0f%%" % (100 * f[:, 0].mean(), 100 * f[:, 1].mean()))
print("hits landing within one cell of the ordered unit: retreats %.3f (n=%d), others %.3f (n=%d)" % (
    np.mean(ret), len(ret), np.mean(rest), len(rest)))
