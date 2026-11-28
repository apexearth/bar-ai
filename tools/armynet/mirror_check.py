#!/usr/bin/env python3
"""Checks data.mirror: mirroring twice gives the example back, and a mirrored place label lands at the mirrored point.

    python tools/armynet/mirror_check.py
"""
import glob
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import G, Game, mirror  # noqa: E402

g = Game(sys.argv[1] if len(sys.argv) > 1 else sorted(glob.glob("G:/bar-ai-archive/public-replays/recordings/*/*.npz"))[3])
checked = 0
in_task = []
for t, f in g.examples[100:400]:
    ex = g.example(t, f)
    in_task.extend(ex["tok"][:, 28].tolist())
    if not (ex["tcell"] >= 0).any():
        continue
    for fx, fz in ((1, 0), (0, 1), (1, 1)):
        back = mirror(mirror(ex, fx, fz), fx, fz)
        assert np.allclose(back["grid"], ex["grid"], atol=1e-6) and np.allclose(back["tok"], ex["tok"], atol=1e-6)
        assert (back["tcell"] == ex["tcell"]).all() and np.allclose(back["toff"], ex["toff"])
        m = mirror(ex, fx, fz)
        j = int(np.where(ex["tcell"] >= 0)[0][0])
        x = (ex["tcell"][j] % G + ex["toff"][j, 0]) / G
        z = (ex["tcell"][j] // G + ex["toff"][j, 1]) / G
        mx = (m["tcell"][j] % G + m["toff"][j, 0]) / G
        mz = (m["tcell"][j] // G + m["toff"][j, 1]) / G
        assert abs(mx - (1 - x if fx else x)) < 1e-5 and abs(mz - (1 - z if fz else z)) < 1e-5
        ux, uz = ex["tok"][j, 10], ex["tok"][j, 11]
        assert abs(m["tok"][j, 10] - (1 - ux if fx else ux)) < 1e-6
        checked += 1
print("mirror ok on %d labelled examples x 3 flips; units in a task: %.0f%%" % (checked // 3, 100 * np.mean(in_task)))
