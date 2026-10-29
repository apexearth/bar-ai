"""Per-build credit for the auction head (10-29, his "I chose to make the mex and it increased my metal income ...
the constructor dies walking out there"): every build the auction chose, joined to its own fate, teaches the policy
network's builder head what share of a build's priced worth it delivers in that state.

A build is one EPISODE: the elections of one team for one def on one 48-elmo site cell, less than 5 minutes apart
(AiMakeTask re-elects, S14). Its delivery is r = ln(0.05 + done x min(life, 600)/600): finished within 5 minutes and
how much of its first 10 minutes it stood (tools/decisions.py: done, lifeS). The head's tilt exp(8 o) multiplies an
option's value, so it is fitted to 8 o = r - mean r on the first election's state and option numbers, the trunk and
every other head frozen: an option that delivers half what an average build does in its state is valued at half.

    python tools/buildcredit.py rows/*.jsonl --base runtime/lean/base.weights --out runtime/lean/credit.weights
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import os
import random
import re
import sys

import numpy as np
import torch

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
import pgtrain  # noqa: E402

ONUM = ["value", "gain", "m", "t", "cm", "ce", "bt", "walk", "risk", "eta", "dPow", "ownN", "tierO", "fwd",
        "siteLoss", "persona"]
NOT_BUILD = {"none", "reclaim", "assist", "teeth"}
LIFE_S, CELL, GAP_F = 600.0, 48.0, 5 * 1800


def kinds():
    p = os.path.join(REPO, "ai", "Unstable", "game-side", "script", "standard", "manager", "brain", "market", "kinds.as")
    names = {}
    for m in re.finditer(r"const int WK_(\w+) = (\d+);", open(p, encoding="utf-8").read()):
        names.setdefault(int(m.group(2)), m.group(1).lower())
    return [names.get(k, "k%d" % k) for k in range(max(names) + 1)]


def slog(x):
    a = math.log(1 + abs(x))
    return -a if x < 0 else a


def norm(x, m, s):
    return max(-5.0, min(5.0, (slog(x) - m) / s))


class Head:
    def __init__(self):
        self.lay = pgtrain.Layout()
        self.h = self.lay.heads.index("builder")
        self.idx = [int(v) for v in pgtrain.pd_array("PN_IDX")]
        self.pm, self.ps = pgtrain.pd_array("PN_M"), pgtrain.pd_array("PN_S")
        fm, fs = pgtrain.pd_array("PN_FM"), pgtrain.pd_array("PN_FS")
        fo = sum(self.lay.F[:self.h])
        self.fm, self.fs = fm[fo:fo + self.lay.F[self.h]], fs[fo:fo + self.lay.F[self.h]]
        self.kinds = kinds()

    def inputs(self, row):
        st = list(row["state"].values())
        z = [norm(st[k] if k < len(st) else 0.0, self.pm[i], self.ps[i]) for i, k in enumerate(self.idx)]
        opts = row["opts"][:8]
        best = max(float(o["value"]) for o in opts)
        beta = min(float(o["eta"]) for o in opts)
        o = row["opts"][row["chosen"]]
        raw = [1.0 if self.kinds[k] == o["kind"] else 0.0 for k in range(len(self.kinds))]
        raw = raw[:17] + [0.0] * (17 - len(raw))
        raw += [float(o[k]) for k in ONUM]
        raw += [float(o["value"]) - best, float(o["eta"]) - beta, float(len(opts))]
        return z, [norm(a, self.fm[j], self.fs[j]) for j, a in enumerate(raw)]


def episodes(paths):
    """one sample per build: (match, kind, minute, row of its first election, r)"""
    out = []
    for fp in paths:
        rows = [json.loads(x) for x in open(fp, encoding="utf-8") if x.strip()]
        if not rows:
            continue
        end_f = max(r["f"] for r in rows)
        by = {}
        for r in rows:
            c = r["chosen"]
            if not (0 <= c < len(r["opts"])) or r["opts"][c]["kind"] in NOT_BUILD or r["opts"][c].get("x") is None:
                continue
            o = r["opts"][c]
            by.setdefault((r["team"], o["def"], int(float(o["x"]) // CELL), int(float(o["z"]) // CELL)), []).append(r)
        for ds in by.values():
            ds.sort(key=lambda q: q["f"])
            eps, cur = [], [ds[0]]
            for d in ds[1:]:
                if d["f"] - cur[-1]["f"] > GAP_F:
                    eps.append(cur)
                    cur = [d]
                else:
                    cur.append(d)
            eps.append(cur)
            for e in eps:
                first = e[0]
                if end_f - first["f"] < (5 * 60 + LIFE_S) * 30:
                    continue        # too near the game's end to see the build stand 10 minutes
                fin = next((d for d in e if d["y"].get("done") == 1), None)
                if fin is None and all(d["y"].get("done") is None for d in e):
                    continue
                life = 0.0
                if fin is not None:
                    life = fin["y"].get("lifeS")
                    life = LIFE_S if life is None else min(LIFE_S, float(life))
                out.append((os.path.basename(fp), first["opts"][first["chosen"]]["kind"], first["f"] / 1800.0, first,
                            math.log(0.05 + (life / LIFE_S if fin is not None else 0.0))))
    return out


def fit(head, base, samples, epochs=60, seed=1, wd=1e-3):
    lay, h = head.lay, head.h
    z = torch.tensor([s[0] for s in samples["zx"]], dtype=torch.float64)
    x = torch.tensor([s[1] for s in samples["zx"]], dtype=torch.float64)
    y = torch.tensor(samples["y"], dtype=torch.float64)
    va = torch.tensor(samples["val"], dtype=torch.bool)
    w = torch.tensor(base, dtype=torch.float64)
    lo, hi = lay.off[h], lay.off[h] + lay.H2 * (lay.H1 + lay.F[h] + 1) + lay.K[h] * (lay.H2 + 1)
    p = w[lo:hi].clone().requires_grad_(True)
    opt = torch.optim.Adam([p], lr=3e-3)
    torch.manual_seed(seed)
    best = (float("inf"), p.detach().clone(), 0)
    tr = (~va).nonzero().squeeze(1)
    for ep in range(epochs):
        perm = tr[torch.randperm(len(tr))]
        for i in range(0, len(perm), 2048):
            b = perm[i:i + 2048]
            wf = torch.cat([w[:lo], p, w[hi:]])
            out = 8.0 * lay.forward(wf, h, z[b], x[b])[:, 0]
            loss = ((out - y[b]) ** 2).mean() + wd * (p ** 2).mean()
            opt.zero_grad()
            loss.backward()
            opt.step()
        with torch.no_grad():
            wf = torch.cat([w[:lo], p, w[hi:]])
            vl = ((8.0 * lay.forward(wf, h, z[va], x[va])[:, 0] - y[va]) ** 2).mean().item()
        if vl < best[0]:
            best = (vl, p.detach().clone(), ep)
    wf = torch.cat([w[:lo], best[1], w[hi:]])
    return wf.numpy(), best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rows", nargs="+")
    ap.add_argument("--base", default=os.path.join(REPO, "runtime", "lean", "base.weights"))
    ap.add_argument("--out")
    a = ap.parse_args()
    paths = [p for g in a.rows for p in glob.glob(g)]
    head = Head()
    eps = episodes(paths)
    if not eps:
        raise SystemExit("no builds")
    mean_r = sum(e[4] for e in eps) / len(eps)
    games = sorted({e[0] for e in eps})
    rng = random.Random(7)
    held = set(rng.sample(games, max(1, len(games) // 5)))
    zx = [head.inputs(e[3]) for e in eps]
    y = [e[4] - mean_r for e in eps]
    val = [e[0] in held for e in eps]
    base = pgtrain.read_weights(a.base, head.lay)
    w, (vl, _, ep) = fit(head, base, {"zx": zx, "y": y, "val": val})
    yv = np.array([v for v, h in zip(y, val) if h])
    print("%d builds from %d games (%d held out), mean r %.3f; held-out mse %.3f against variance %.3f: R2 %.3f "
          "(best epoch %d)" % (len(eps), len(games), len(held), mean_r, vl, yv.var(), 1 - vl / yv.var(), ep))
    lay, h = head.lay, head.h
    with torch.no_grad():
        o = 8.0 * lay.forward(torch.tensor(w), h, torch.tensor([s[0] for s in zx], dtype=torch.float64),
                              torch.tensor([s[1] for s in zx], dtype=torch.float64))[:, 0].numpy()
    by = {}
    for e, oo, yy in zip(eps, o, y):
        by.setdefault(e[1], []).append((oo, yy))
    print("%-8s %6s %8s %8s %8s" % ("kind", "builds", "real r", "fit", "x value"))
    for k, v in sorted(by.items(), key=lambda kv: -len(kv[1])):
        f = sum(q[0] for q in v) / len(v)
        print("%-8s %6d %+8.3f %+8.3f %8.2f" % (k, len(v), sum(q[1] for q in v) / len(v), f, math.exp(f)))
    if a.out:
        pgtrain.write_weights(a.out, w)
        print("wrote", a.out)


if __name__ == "__main__":
    main()
