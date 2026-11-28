#!/usr/bin/env python3
"""Time each part of one live decision the way serve.py makes it (budget at 10x and STEP=10: 33 ms).

    python tools/armynet/bench_serve.py <dataset.npz> --model <model.pt> [--minute 18] [--n 10]
"""
import sys
import time
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import G, RECENT_S, STEP, Game, collate, fold_history, history_rows  # noqa: E402
from model import ArmyNet, arch_of, load_widened  # noqa: E402


def main(a):
    path = a[0]
    opt = lambda k, d: a[a.index(k) + 1] if k in a else d
    minute, n = float(opt("--minute", "18")), int(opt("--n", "10"))
    dev = "cpu" if "--cpu" in a else ("cuda" if torch.cuda.is_available() else "cpu")
    if "--threads" in a:
        torch.set_num_threads(int(opt("--threads", "1")))
    model = ArmyNet(*arch_of(opt("--model", ""))).to(dev)
    load_widened(model, opt("--model", ""), dev, log=lambda *_: None)
    model.eval()
    z = np.load(path)
    u = z["units"]
    team = int(z["teams"][0][0])
    t = {k: [] for k in ("history", "live", "example", "forward x3", "regions", "total")}
    f0 = int(minute * 1800) // STEP * STEP
    stores = {}
    for i in range(n):
        f = f0 + i * STEP
        t0 = time.perf_counter()
        sd = np.array(sorted(int(r[0]) for r in z["defs"] if int(r[1]) == 0), np.int64)
        old = u[(u[:, 0] < f - RECENT_S * 30) & (u[:, 0] >= f - RECENT_S * 30 - STEP)]  # one step folded, as serve
        store = fold_history(stores.setdefault("s", fold_history({}, u[u[:, 0] < f - RECENT_S * 30 - STEP],
                                                                  len(z["allies"]))), old, len(z["allies"]))
        hist = history_rows(store, u[(u[:, 0] <= f) & (u[:, 0] >= f - RECENT_S * 30)], f, sd)
        t1 = time.perf_counter()
        g = Game.live(hist, z["defs"], z["map"], z["allies"], z["teams"], z["spots"], z["heights"],
                      orders=z["decisions"][z["decisions"][:, 0] < f], task_starts=None,
                      hits=z["hits"] if "hits" in z.files else None)
        t2 = time.perf_counter()
        ex = g.example(team, f)
        t3 = time.perf_counter()
        for _ in range(3):
            b = collate([ex])
            with torch.no_grad():
                o = model(b["grid"].to(dev), b["scal"].to(dev), b["tok"].to(dev), b["mask"].to(dev),
                          b["etok"].to(dev), b["emask"].to(dev))
                c = o["cells"][0].argmax(-1)
                model.offset_at(o["h"], o["u64"], c[None])
                probs = torch.softmax(o["cells"][0].float(), -1).cpu().numpy()
        t4 = time.perf_counter()
        from train import base_axis
        sx, sz = float(z["map"][0]) / G, float(z["map"][1]) / G
        axis = base_axis(ex["grid"], sx, sz, float(z["map"][0]), float(z["map"][1]))
        cz_, cx_ = np.mgrid[0:G, 0:G]
        cell_fwd = axis((cx_ + .5) * sx, (cz_ + .5) * sz).ravel()
        fu = np.asarray(axis(ex["tok"][:, 10] * float(z["map"][0]), ex["tok"][:, 11] * float(z["map"][1])))
        back = cell_fwd[None, :] < fu[:, None] - 0.1
        fwd = cell_fwd[None, :] > fu[:, None] + 0.1
        regions = np.stack([back, fwd, ~(back | fwd)], 1)
        (probs[:, None, :] * regions).sum(-1)
        t5 = time.perf_counter()
        for k, v in zip(t, (t1 - t0, t2 - t1, t3 - t2, t4 - t3, t5 - t4, t5 - t0)):
            t[k].append(v)
    print("units in the window %d, tokens %d" % (len(hist), len(ex["tok"])))
    for k, v in t.items():
        print("%-12s %6.1f ms" % (k, 1000 * np.median(v[1:] if len(v) > 1 else v)))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
