#!/usr/bin/env python3
"""Time one training step of the army model under different settings, on one fixed batch (no data loading):
fp32, bf16 autocast, channels_last, both. Also times building one example (the data workers' cost).

    python tools/armynet/bench.py [--batch 32] [--iters 30]
"""
import glob
import sys
import time
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import Game, collate  # noqa: E402
from model import ArmyNet  # noqa: E402
from train import losses  # noqa: E402


def main(a):
    bs = int(a[a.index("--batch") + 1]) if "--batch" in a else 32
    iters = int(a[a.index("--iters") + 1]) if "--iters" in a else 30
    paths = sorted(glob.glob("G:/bar-ai-archive/public-replays/recordings/*/*.npz"))[:4]
    exs, t0, n = [], time.time(), 0
    for p in paths:
        t1 = time.time()
        g = Game(p)
        load = time.time() - t1
        t1 = time.time()
        for t, f in g.examples[200:200 + bs // 4 + 4]:
            e = g.example(t, f)
            n += 1
            if len(e["tok"]):
                exs.append(e)
        print("game load %.2fs, %.1f ms per example" % (load, 1000 * (time.time() - t1) / max(n, 1)))
        n = 0
    b = collate(exs[:bs])
    dev = "cuda"
    for name, bf16, cl in (("fp32", False, False), ("bf16", True, False), ("channels_last", False, True),
                           ("bf16+channels_last", True, True)):
        model = ArmyNet().to(dev)
        if cl:
            model = model.to(memory_format=torch.channels_last)
        opt = torch.optim.AdamW(model.parameters(), lr=1e-4)
        bb = dict(b)
        if cl:
            bb["grid"] = bb["grid"].contiguous(memory_format=torch.channels_last)
        for i in range(iters + 5):
            if i == 5:
                torch.cuda.synchronize()
                t1 = time.time()
            with torch.autocast("cuda", dtype=torch.bfloat16, enabled=bf16):
                loss, _ = losses(model, bb, dev)
            opt.zero_grad()
            loss.backward()
            opt.step()
        torch.cuda.synchronize()
        print("%-20s %.1f ms/step (batch %d), loss %.3f" % (name, 1000 * (time.time() - t1) / iters, bs, float(loss)))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
