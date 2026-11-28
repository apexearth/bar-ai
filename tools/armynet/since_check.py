#!/usr/bin/env python3
"""Does the model learn "a unit nobody has ordered for a while will not be ordered"? Live, the model gives the first
order to every unit, so a unit it leaves alone ages, and that age (unit feature 35, minutes since its last order,
3 = none within 2 minutes) lowers its chance again. Per bucket of that age on held-out player games: the players'
per-step order rate, the model's mean chance, and the model's chance with the age set to 0.25 min.

    python tools/armynet/since_check.py <model.pt> [games] [examples per game]
"""
import random
import sys
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import Game, collate, find_games  # noqa: E402
from model import ArmyNet, load_widened  # noqa: E402
from train import held_out  # noqa: E402

ROOTS = ["G:/bar-ai-archive/public-replays/recordings", "G:/bar-ai-archive/replay-orders"]
EDGES = [0, 0.1, 0.5, 1.0, 2.0, 2.99, 3.01]


def main(a):
    dev = "cpu"
    model = ArmyNet()
    load_widened(model, a[0], dev, log=lambda s: None)
    model.eval()
    n = int(a[1]) if len(a) > 1 else 30
    per = int(a[2]) if len(a) > 2 else 40
    games = [p for p in find_games(ROOTS) if held_out(p)]
    rng = random.Random(1)
    rng.shuffle(games)
    s, act, w, p, p_cf = [], [], [], [], []
    for path in games[:n]:
        g = Game(path, rng=np.random.default_rng(7))
        if not g.examples:
            continue
        exs = [g.example(t, f) for t, f in rng.sample(g.examples, min(per, len(g.examples)))]
        exs = [e for e in exs if len(e["tok"])]
        if not exs:
            continue
        b = collate(exs)
        m = (b["mask"] & b["lossmask"]).numpy() if "lossmask" in b else b["mask"].numpy()
        with torch.no_grad():
            o = torch.sigmoid(model(b["grid"], b["scal"], b["tok"], b["mask"], b["etok"], b["emask"])["act"]).numpy()
            tok = b["tok"].clone()
            tok[..., 35] = torch.where(tok[..., 35] > 2.99, torch.full_like(tok[..., 35], 0.25), tok[..., 35])
            ocf = torch.sigmoid(model(b["grid"], b["scal"], tok, b["mask"], b["etok"], b["emask"])["act"]).numpy()
        wa = np.broadcast_to(b["w_act"].numpy()[:, None], m.shape)
        s.append(b["tok"][..., 35].numpy()[m])
        act.append(b["act"].numpy()[m])
        w.append(wa[m])
        p.append(o[m])
        p_cf.append(ocf[m])
    s, act, w, p, p_cf = (np.concatenate(v) for v in (s, act, w, p, p_cf))
    print("units sampled %d (weighted %.0f)" % (len(s), w.sum()))
    print("minutes since last order | share of unit-steps | players' order rate | model chance | with age 0.25")
    for lo, hi in zip(EDGES[:-1], EDGES[1:]):
        k = (s >= lo) & (s < hi)
        if not k.any():
            continue
        ww = w[k]
        print("%4.2f-%4.2f  %5.1f%%  %.4f  %.4f  %.4f" % (lo, min(hi, 3), 100 * ww.sum() / w.sum(),
                                                       (act[k] * ww).sum() / ww.sum(), (p[k] * ww).sum() / ww.sum(),
                                                       (p_cf[k] * ww).sum() / ww.sum()))


if __name__ == "__main__":
    main(sys.argv[1:])
