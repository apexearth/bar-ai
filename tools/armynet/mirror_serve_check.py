#!/usr/bin/env python3
"""Does the model follow the map or the frame at serve time (issues/army-off-axis-corner.md)? From a recording, the
live example serve builds (Game.live on the units seen so far, as parity.py), and the same raw game with every
position mirrored left-right (x -> map width - x) or top-bottom, rebuilt through the same path. A model that
follows the map puts each force's best place, and each unit's, on the mirrored cell; one that follows the frame
does not. Reports the share of forces and units whose best cell lands within one cell of the mirror.

    BARAI_ABSENT=1 python tools/armynet/mirror_serve_check.py --model runtime/armynet/enemy1-absent/model-010000.pt \
        --team 0 runtime/armynet/own-games/watch-g2/watch-g2.npz
"""
import argparse
import os
import sys
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import ABSENT_ON, RECENT_S, G, Game, absence_ctx, absent_of, collate, fold_history, history_rows, mirror  # noqa: E402
from model import ArmyNet, arch_of, load_widened  # noqa: E402


def live_example(z, units, spots, heights, decisions, t, f):
    static_defs = np.array(sorted(int(r[0]) for r in z["defs"] if int(r[1]) == 0), np.int64)
    uu = units[units[:, 0] <= f]
    uu = uu[np.argsort(uu[:, 0], kind="stable")]
    actx = absence_ctx(z["defs"], z["teams"], z["allies"]) if ABSENT_ON else None
    store = {}
    old = uu[uu[:, 0] < f - RECENT_S * 30]
    for fo in np.unique(old[:, 0] // 300):
        fold_history(store, old[old[:, 0] // 300 == fo], len(z["allies"]), actx)
    hist = history_rows(store, uu[uu[:, 0] >= f - RECENT_S * 30], f, static_defs)
    live = Game.live(hist, z["defs"], z["map"], z["allies"], z["teams"], spots, heights, orders=decisions,
                     task_starts=z["task_starts"] if "task_starts" in z.files else None,
                     hits=z["hits"] if "hits" in z.files else None,
                     names=z["def_names"] if "def_names" in z.files else None, absent=absent_of(store))
    return live.example(t, f)


def flipped(z, axis):
    """The recording's raw units, spots, heights and orders mirrored on one axis (0: x, 1: z)."""
    mx, mz = float(z["map"][0]), float(z["map"][1])
    size = (mx, mz)[axis]
    u = z["units"].copy()
    u[:, 4 + axis] = size - u[:, 4 + axis]
    u[:, 6 + axis] = -u[:, 6 + axis]
    has = u[:, 12 + axis] >= 0
    u[has, 12 + axis] = size - u[has, 12 + axis]
    sp = np.array(z["spots"], dtype=float, copy=True)
    if len(sp):
        sp[:, axis] = size - sp[:, axis]
    h = np.array(z["heights"], copy=True)
    if h.ndim == 2:
        h = h[:, ::-1] if axis == 0 else h[::-1, :]
    d = z["decisions"].copy()
    if len(d):
        ok = d[:, 5 + axis] >= 0
        d[ok, 5 + axis] = size - d[ok, 5 + axis]
    return u, sp, h, d


def best_cells(net, ex):
    b = collate([ex])
    with torch.no_grad():
        o = net(b["grid"], b["scal"], b["tok"], b["mask"], b.get("etok"), b.get("emask"))
        uc = o["cells"][0].argmax(-1).numpy()
        fc = None
        if "force" in ex and len(ex["force"]):
            fo = net.forces(o["h"], o["u64"], torch.from_numpy(np.asarray(ex["force"], np.int64))[None])
            fc = fo["cells"][0].argmax(-1).numpy()
    return uc, fc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("npz", nargs="+")
    ap.add_argument("--model", required=True)
    ap.add_argument("--team", type=int, default=0)
    ap.add_argument("--frames", type=int, default=8)
    a = ap.parse_args()
    net = ArmyNet(*arch_of(a.model))
    load_widened(net, a.model, "cpu", log=lambda s: None)
    net.eval()
    tot = {0: [0, 0, 0, 0], 1: [0, 0, 0, 0]}   # axis -> units n, units mirrored, forces n, forces mirrored
    lean = {0: [], 1: []}   # axis -> (original coordinate, mirrored run's coordinate mirrored back) of force cells
    base = {0: [0, 0], 1: [0, 0]}  # the same on training's own mirror (data.mirror of the example)
    for p in a.npz:
        z = np.load(p)
        g = Game(p)
        frames = sorted({f for t, f in g.examples if t == a.team and f % 300 == 0 and f > 5 * 1800})
        frames = frames[::max(1, len(frames) // a.frames)][:a.frames]
        for f in frames:
            ex0 = live_example(z, z["units"], z["spots"], z["heights"], z["decisions"], a.team, f)
            if not len(ex0["tok"]):
                continue
            uc0, fc0 = best_cells(net, ex0)
            for axis in (0, 1):
                u, sp, h, d = flipped(z, axis)
                ex1 = live_example(z, u, sp, h, d, a.team, f)
                if len(ex1["tok"]) != len(ex0["tok"]):
                    continue
                uc1, fc1 = best_cells(net, ex1)

                def mirror_ok(c0, c1):
                    x0, z0, x1, z1 = c0 % G, c0 // G, c1 % G, c1 // G
                    if axis == 0:
                        return (abs((G - 1 - x0) - x1) <= 1) & (abs(z0 - z1) <= 1)
                    return (abs(x0 - x1) <= 1) & (abs((G - 1 - z0) - z1) <= 1)
                # units in the same order (by uid) on both sides
                o0 = {int(u_): i for i, u_ in enumerate(ex0["uid"])}
                pairs = [(o0[int(u_)], j) for j, u_ in enumerate(ex1["uid"]) if int(u_) in o0]
                if pairs:
                    i0, i1 = np.array(pairs).T
                    ok = mirror_ok(uc0[i0], uc1[i1])
                    tot[axis][0] += len(ok)
                    tot[axis][1] += int(ok.sum())
                if fc0 is not None and fc1 is not None and len(fc0) == len(fc1):
                    ok = mirror_ok(fc0, fc1)
                    tot[axis][2] += len(ok)
                    tot[axis][3] += int(ok.sum())
                    c0 = (fc0 % G) if axis == 0 else (fc0 // G)
                    c1 = (fc1 % G) if axis == 0 else (fc1 // G)
                    lean[axis] += list(zip(c0.tolist(), (G - 1 - c1).tolist()))
                exm = mirror(ex0, axis == 0, axis == 1)
                ucm, fcm = best_cells(net, exm)
                if fc0 is not None and fcm is not None and len(fcm) == len(fc0):
                    okm = mirror_ok(fc0, fcm)
                    base[axis][0] += len(okm)
                    base[axis][1] += int(okm.sum())
        print("read %s (%d frames)" % (os.path.basename(p), len(frames)), flush=True)
    for axis, nm in ((0, "left-right"), (1, "top-bottom")):
        t = tot[axis]
        print("mirrored %s: units' best cell on the mirror (within 1 cell) %d of %d (%.3f); forces' %d of %d (%.3f)" % (
            nm, t[1], t[0], t[1] / max(t[0], 1), t[3], t[2], t[3] / max(t[2], 1)))
        if lean[axis]:
            l_ = np.array(lean[axis], float)
            print("   forces: mean cell %s %.1f in the game, %.1f in the mirrored game mirrored back (of %d); training's mirror"
                  " puts %.3f of forces on the mirror" % ("x" if axis == 0 else "z", l_[:, 0].mean(), l_[:, 1].mean(),
                                                         G, base[axis][1] / max(base[axis][0], 1)))


if __name__ == "__main__":
    main()
