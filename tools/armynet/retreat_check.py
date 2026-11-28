#!/usr/bin/env python3
"""How the rating treats retreats out of fights, scored by the absolute trade after the order (before 11-19) and by
the change the order made (measure 8): orders sending units back toward their own buildings (forward falls by 0.1
or more) whose units took damage in the 15 s before.

    python tools/armynet/retreat_check.py <dataset .npz> ...
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import data  # noqa: E402

OLD = ((0, 0), (1, 0), (2, 0)) + data.HORIZON_PICK[3:]


def score(o, res, picks):
    cols = []
    for h, m in picks:
        if m >= o.shape[2]:
            continue
        v = o[:, h, m].astype(np.float64)
        ok = ~np.isnan(v)
        z = np.zeros_like(v)
        if ok.sum() > 2:
            z[ok] = v[ok] / (np.sqrt(np.mean(v[ok] ** 2)) + 1e-6)
        cols.append(np.clip(z, -3, 3))
    s = np.mean(cols, axis=0)
    s = np.where(s < -1, s + 1, np.maximum(s, 0.0))
    s = s + np.where(res == 1, 0.5, 0.0)
    return np.exp(0.5 * np.clip(s, -2, 2))


for p in sys.argv[1:]:
    g = data.Game(p)
    d, o = g.decisions, g.outcome
    if o.shape[2] < 9:
        print(p, "built before measure 8")
        continue
    static = g.ucls == 0
    cent = {t: np.array([g.units[static & (g.uteam == t), 4].mean(), g.units[static & (g.uteam == t), 5].mean()])
            for t in set(int(x) for x in g.uteam) if (static & (g.uteam == t)).any()}
    pos = {}
    for r in g.units:
        pos.setdefault(int(r[1]), []).append((r[0], r[4], r[5]))
    retreat = np.zeros(len(d), bool)
    for i, row in enumerate(d):
        t = int(row[2])
        foes = [c for tt, c in cent.items() if g.ally_of.get(tt) != g.ally_of.get(t) and g.ally_of.get(tt, -9) >= 0]
        rows = pos.get(int(row[3]))
        if t not in cent or not foes or not rows:
            continue
        ax = np.mean(foes, axis=0) - cent[t]
        n2 = max(float(np.dot(ax, ax)), 1.0)
        k = min(range(len(rows)), key=lambda j: abs(rows[j][0] - row[0]))
        f_unit = float(np.dot(np.array(rows[k][1:]) - cent[t], ax)) / n2
        f_tgt = float(np.dot(np.array([row[5], row[6]]) - cent[t], ax)) / n2
        retreat[i] = f_tgt < f_unit - 0.1
    # units that were in a fight: the change measure differs from the after-only one when there was trade before
    fighting = np.abs(o[:, 1, 8] - o[:, 1, 0]) > 1e-3
    sel = retreat & fighting
    w_old, w_new = score(o, g.result, OLD), score(o, g.result, data.HORIZON_PICK)
    print("%s: retreats out of fights %d; mean weight old %.2f -> new %.2f; share marked down old %.0f%% -> new %.0f%%"
          % (Path(p).stem[:30], sel.sum(), w_old[sel].mean(), w_new[sel].mean(),
             100 * np.mean(w_old[sel] < 0.999), 100 * np.mean(w_new[sel] < 0.999)))
