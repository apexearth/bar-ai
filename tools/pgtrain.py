"""Learning from our own choices (his 10-28: "I chose to make the mex and it increased my metal income ... we value
it"; "the result is reinforcing a good decision").

Training games push every policy-network output by N(0, sigma) (apex_pn_explore) and log the push with the inputs
that made the output (`apex: pnx`). A push followed by a better move in our standing than expected is reinforced, a
worse one weakened: the policy gradient of a Gaussian push, A * (e / sigma^2) * d(output)/d(weights). Standing is
our economy, army and trade against theirs, per minute (progress.series_of, ground truth -- labels only); A is its
move over the next HORIZON minutes after the decision minus what a regression on the decision's inputs expected.

The network is rebuilt here from policydata.as (layout) and policy.as's order of weights, and checked against the
outputs each game logged before any step is taken.

    python tools/pgtrain.py --init W.weights                       # a fresh net: output layer 0 = the rule
    python tools/pgtrain.py --check W.weights <match dirs>         # the copy reproduces the game's outputs
    python tools/pgtrain.py --train W.weights --out W2.weights <match dirs> [--report r.json]
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys

import numpy as np
import torch

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
import progress  # noqa: E402

PD = os.path.join(REPO, "ai", "Unstable", "game-side", "script", "standard", "manager", "brain", "market",
                  "policydata.as")
HORIZON = 2
CLIP = 2.3
PNX = re.compile(r"apex: pnx h=(\d+) t=(\d+) f=(-?\d+) \|([^|]*)\|([^|]*)\|(.*)$")
SCHEMA = re.compile(r"apex: pnx-schema t=\d+ sigma=([\d.]+)(?: sigmaTilt=([\d.]+))?")


def pd_array(name):
    rx = re.compile(r"^const array<(\w+)> " + re.escape(name) + r" = \{(.*)\};")
    for line in open(PD, encoding="utf-8"):
        m = rx.match(line)
        if m:
            body = m.group(2)
            if m.group(1) == "string":
                return re.findall(r'"([^"]*)"', body)
            return [float(v.rstrip("f")) for v in body.split(",") if v.strip()]
    raise KeyError(name)


def pd_int(name):
    rx = re.compile(r"^const int " + re.escape(name) + r" = (\d+);")
    for line in open(PD, encoding="utf-8"):
        m = rx.match(line)
        if m:
            return int(m.group(1))
    raise KeyError(name)


class Layout:
    def __init__(self):
        self.N = len(pd_array("PN_IDX"))
        self.H1, self.H2 = pd_int("PN_H1"), pd_int("PN_H2")
        self.heads = pd_array("PN_HEADS")
        self.hk = [int(k) for k in pd_array("PN_HK")]
        self.K = [max(1, k) for k in self.hk]
        self.F = [int(f) for f in pd_array("PN_HF")]
        self.off = []
        n = self.H1 * (self.N + 1)
        for h in range(len(self.heads)):
            self.off.append(n)
            n += self.H2 * (self.H1 + self.F[h] + 1) + self.K[h] * (self.H2 + 1)
        self.n = n

    def out_rows(self, h):
        """the output layer's slice of head h: zero it and the head says the rule"""
        a = self.off[h] + self.H2 * (self.H1 + self.F[h] + 1)
        return a, a + self.K[h] * (self.H2 + 1)

    def forward(self, w, h, z, x):
        H1, H2, N, F, K = self.H1, self.H2, self.N, self.F[h], self.K[h]
        t = w[:H1 * (N + 1)].view(H1, N + 1)
        a1 = torch.tanh(z @ t[:, :N].T + t[:, N])
        o0 = self.off[h]
        b = w[o0:o0 + H2 * (H1 + F + 1)].view(H2, H1 + F + 1)
        a2 = torch.tanh(a1 @ b[:, :H1].T + (x @ b[:, H1:H1 + F].T if F else 0.0) + b[:, H1 + F])
        o1 = o0 + H2 * (H1 + F + 1)
        c = w[o1:o1 + K * (H2 + 1)].view(K, H2 + 1)
        return torch.tanh(a2 @ c[:, :H2].T + c[:, H2])


def read_weights(path, lay):
    w = np.array([float(v) for v in open(path, encoding="utf-8").read().split()], dtype=np.float64)
    if len(w) != lay.n:
        raise SystemExit("%s has %d weights, the network takes %d" % (path, len(w), lay.n))
    return w


def write_weights(path, w):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(" ".join("%.6g" % v for v in w))


def init_weights(lay, seed=1, scale=0.5):
    """hidden layers small and random so learning can flow through them; every output layer 0, so each head
    starts exactly at the rule (TUNE_PN_RULE_CENTRE)"""
    rng = np.random.default_rng(seed)
    w = np.zeros(lay.n)
    w[:lay.H1 * (lay.N + 1)] = rng.normal(0, scale / math.sqrt(lay.N + 1), lay.H1 * (lay.N + 1))
    for h in range(len(lay.heads)):
        a = lay.off[h]
        nb = lay.H2 * (lay.H1 + lay.F[h] + 1)
        w[a:a + nb] = rng.normal(0, scale / math.sqrt(lay.H1 + lay.F[h] + 1), nb)
    return w


def floats(s):
    s = s.strip()
    return [float(v) for v in s.split(",")] if s else []


def read_match(mdir, lay):
    """the pushed decisions of one game, with the standing series of our side"""
    try:
        txt = open(os.path.join(mdir, "infolog.txt"), encoding="utf-8", errors="replace").read()
    except OSError:
        return None
    m = SCHEMA.search(txt)
    if not m:
        return None
    g = progress.read_game(mdir)
    if g is None:
        return None
    rows = []
    for line in txt.splitlines():
        if "apex: pnx h=" not in line:
            continue
        p = PNX.search(line)
        if not p:
            continue
        h = int(p.group(1))
        z, x = floats(p.group(4)), floats(p.group(5))
        oe = [tuple(float(u) for u in pair.split(":")) for pair in p.group(6).split(",") if ":" in pair]
        if h >= len(lay.heads) or len(z) != lay.N or len(x) != lay.F[h] or len(oe) != lay.K[h]:
            continue
        rows.append((h, int(p.group(3)), z, x, [a for a, _ in oe], [b for _, b in oe]))
    return {"dir": mdir, "sigma": float(m.group(1)), "sigmaTilt": float(m.group(2) or m.group(1)), "rows": rows, "series": g["series"], "result": g["result"]}


def standing(series):
    def lg(v):
        return max(-CLIP, min(CLIP, math.log(v))) if (v is not None and v > 0) else 0.0
    n = len(series.get("eco", []))
    return [lg(series["eco"][i]) + lg(series["army"][i]) + lg(series["trade"][i]) for i in range(n)]


def head_name(lay, h):
    n = lay.heads[h]
    return n if len(n) <= 12 else "choice%d:%s" % (h, n.split(",")[0])


def gather(games, lay):
    """per head: inputs, the action taken (output + push), the push and its size; plus each row's baseline features"""
    per = {}
    feats, rewards = [], []
    for g in games:
        u = standing(g["series"])
        if len(u) < 2:
            continue
        last = len(u) - 1
        for (h, f, z, x, o, e) in g["rows"]:
            m = min(max(f // 1800, 0), last)
            d = per.setdefault(h, {"z": [], "x": [], "act": [], "e": [], "s": [], "i": []})
            d["z"].append(z)
            d["x"].append(x)
            d["act"].append([a + b for a, b in zip(o, e)])
            d["e"].append(e)
            d["s"].append(g["sigma"] if lay.hk[h] == 0 else g["sigmaTilt"])
            d["i"].append(len(rewards))
            feats.append(z + [m / 30.0, 1.0])
            rewards.append(u[min(m + HORIZON, last)] - u[m])
    return per, np.array(feats), np.array(rewards)


def baseline(feats, rewards, lam=1.0):
    """what the position alone predicts: ridge regression, fitted on one half and applied to the other"""
    n = len(rewards)
    b = np.zeros(n)
    idx = np.arange(n)
    for fold in (0, 1):
        tr, te = idx[idx % 2 != fold], idx[idx % 2 == fold]
        if len(tr) < feats.shape[1] + 2:
            b[te] = rewards[tr].mean() if len(tr) else 0.0
            continue
        X = feats[tr]
        coef = np.linalg.solve(X.T @ X + lam * np.eye(X.shape[1]), X.T @ rewards[tr])
        b[te] = feats[te] @ coef
    return b


def check(w, games, lay):
    wt = torch.tensor(w, dtype=torch.float64)
    worst, total, n = 0.0, 0.0, 0
    for g in games:
        for (h, _f, z, x, o, _e) in g["rows"]:
            with torch.no_grad():
                out = lay.forward(wt, h, torch.tensor([z], dtype=torch.float64),
                                  torch.tensor([x], dtype=torch.float64)).numpy()[0]
            d = float(np.max(np.abs(out - np.array(o))))
            worst = max(worst, d)
            total += d
            n += 1
    return {"rows": n, "meanAbs": total / n if n else None, "maxAbs": worst}


def train(w, games, lay, lr=3e-3, max_shift=0.05, steps=200):
    """one cautious step: the policy gradient of the pushes taken, at the CURRENT weights (a game played by an
    older version still counts: its action is output + push, scored against what the network says now), stopped
    once the outputs on these decisions have moved max_shift on average"""
    per, feats, rewards = gather(games, lay)
    if len(rewards) < 50:
        raise SystemExit("only %d decisions -- not enough to learn from" % len(rewards))
    adv = rewards - baseline(feats, rewards)
    adv = adv / (adv.std() + 1e-9)
    wt = torch.tensor(w, dtype=torch.float64, requires_grad=True)
    heads = {}
    for h, d in per.items():
        z = torch.tensor(d["z"], dtype=torch.float64)
        x = torch.tensor(d["x"], dtype=torch.float64)
        with torch.no_grad():
            o_now = lay.forward(wt, h, z, x)
        s = torch.tensor(d["s"], dtype=torch.float64)[:, None]
        a = torch.tensor(adv[np.array(d["i"])], dtype=torch.float64)[:, None]
        push = torch.tensor(d["act"], dtype=torch.float64) - o_now
        sig = (a * push / s).numpy()
        t = (sig.mean(0) / (sig.std(0) / math.sqrt(len(sig)) + 1e-12)) if len(sig) >= 8 else np.zeros(sig.shape[1])
        heads[h] = {"name": head_name(lay, h), "n": len(sig), "t": [round(float(v), 2) for v in t],
                    "z": z, "x": x, "o0": o_now, "c": a * push / (s * s)}
    total = sum(v["n"] for v in heads.values())
    opt = torch.optim.Adam([wt], lr=lr)
    shift, done = 0.0, 0
    for step in range(steps):
        opt.zero_grad()
        loss = 0.0
        for h, v in heads.items():
            loss = loss - (v["c"] * lay.forward(wt, h, v["z"], v["x"])).sum()
        (loss / total).backward()
        opt.step()
        with torch.no_grad():
            sh, cnt = 0.0, 0
            for h, v in heads.items():
                o = lay.forward(wt, h, v["z"], v["x"])
                sh += float((o - v["o0"]).abs().sum())
                cnt += o.numel()
            shift = sh / cnt
        done = step + 1
        if shift >= max_shift:
            break
    rep = {"games": len(games), "decisions": int(total), "steps": done, "meanShift": round(shift, 4),
           "rewardMean": round(float(rewards.mean()), 4), "rewardStd": round(float(rewards.std()), 4),
           "heads": [{k: v[k] for k in ("name", "n", "t")} for v in sorted(heads.values(), key=lambda q: -q["n"])]}
    return wt.detach().numpy(), rep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--init")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--check")
    ap.add_argument("--train")
    ap.add_argument("--out")
    ap.add_argument("--report")
    ap.add_argument("--lr", type=float, default=3e-3)
    ap.add_argument("--max-shift", type=float, default=0.05)
    ap.add_argument("matches", nargs="*")
    a = ap.parse_args()
    lay = Layout()
    if a.init:
        write_weights(a.init, init_weights(lay, a.seed))
        print("wrote %d weights to %s (every head at the rule)" % (lay.n, a.init))
        return
    games = [g for g in (read_match(m, lay) for m in a.matches) if g and g["rows"]]
    if not games:
        raise SystemExit("no game with pushed decisions")
    if a.check:
        print(json.dumps(check(read_weights(a.check, lay), games, lay)))
        return
    if a.train:
        c = check(read_weights(a.train, lay), games, lay)
        if c["maxAbs"] is None or c["maxAbs"] > 0.01:
            raise SystemExit("the copy does not reproduce the games' outputs: %s" % json.dumps(c))
        w2, rep = train(read_weights(a.train, lay), games, lay, a.lr, a.max_shift)
        rep["check"] = c
        if a.out:
            write_weights(a.out, w2)
        if a.report:
            json.dump(rep, open(a.report, "w", encoding="utf-8"), indent=1)
        print(json.dumps({k: rep[k] for k in rep if k != "heads"}))
        for hrow in rep["heads"]:
            print("  %-10s n=%5d  t=%s" % (hrow["name"], hrow["n"], hrow["t"]))


if __name__ == "__main__":
    main()
