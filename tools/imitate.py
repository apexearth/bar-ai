"""Learn what BARb builds, as a prior for our builder net (docs/35).

    python tools/imitate.py [tournament or match dirs ...]   # default: every tournament vs BARb

For every structure BARb FINISHES, its situation at that moment -- minute,
metal/energy income, mexes, its finished structures by class, its mobile army
metal -- and the class of what it finished. Inputs are things our AI knows the
same way in-game (nnlog.as NnImitState), classes come from one rule applied to
the catalog dump on both sides (NnClassOf / classify). Trains a softmax MLP,
reports held-out accuracy against always-guess-the-commonest, prints BARb's
build mix next to ours by game phase, and saves runtime/nn/imitate.npz, which
nntrain.py exports as NNI_* for the game.
"""
import collections
import glob
import json
import math
import os
import re
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "runtime" / "nn"
CLASSES = ("mex", "energy", "convert", "store", "plant", "nano", "protect", "airdef", "other")
FEATURES = ("min", "mInc", "eInc", "mex", "energy", "convert", "store", "plant", "nano",
            "protect", "airdef", "army")
FPM = 1800
CAT = re.compile(r"apex: catalog (\w+) (.*)")
KV = re.compile(r"(\w+)=(-?[\d.]+)")
WASTE = re.compile(r"\[BARAI_WASTE\] frame=(\d+) team=(\d+) mWaste=\d+ mMade=(\d+) eWaste=\d+ eMade=(\d+)")
BUILD = re.compile(r"\[BARAI_BUILD\] team=(\d+) ally=\d+ frame=(\d+) min=[\d.]+ unit=(\w+)")
DEATH = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\w+) cost=\d+ .*? built=(\d)")
ARMY = re.compile(r"\[BARAI_ARMY\] frame=(\d+) team=(\d+) n=\d+ part=(\d+)/(\d+) (.*)")
NNREC = re.compile(r"apex: nn t=(\d+) ")


def slog(x):
    return math.copysign(math.log1p(abs(x)), x)


def load_catalog():
    p = OUT / "catalog_dump.log"
    if not p.is_file():
        raise SystemExit("run one game with --modoption apex_catalog_dump=1 and copy its infolog to %s" % p)
    cat = {}
    for ln in open(p, encoding="utf-8", errors="replace"):
        m = CAT.search(ln)
        if m and "=" in m.group(2):
            cat[m.group(1)] = {k: float(v) for k, v in KV.findall(m.group(2))}
    return cat


def classify(c):
    """The same rule as nnlog.as NnClassOf, on the catalog's own numbers."""
    if c is None or c.get("mob", 0) > 0:
        return None
    if c.get("builds", 0) > 0:
        return "plant"
    if c.get("bp", 0) > 0:
        return "nano"
    if c.get("extractsM", 0) > 0:
        return "mex"
    if c.get("convCap", 0) > 0:
        return "convert"
    if c.get("makeE", 0) > 0 or c.get("wind", 0) > 0:
        return "energy"
    if c.get("rng", 0) > 0 and c.get("airT", 0) > 0 and c.get("surfT", 0) <= 0:
        return "airdef"
    if c.get("rng", 0) > 0:
        return "protect"
    if c.get("storeM", 0) > 0 or c.get("storeE", 0) > 0:
        return "store"
    return "other"


def game_samples(infolog, cat):
    """Samples for every team that is NOT ours (no `apex: nn` records), plus our
    own finished-structure classes by phase for the comparison."""
    made = collections.defaultdict(list)          # team -> [(frame, mMade, eMade)]
    events = []                                   # (frame, team, unit, +1/-1)
    army = collections.defaultdict(dict)          # team -> frame -> metal
    ours = set()
    with open(infolog, encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            if "apex: nn t=" in ln:
                m = NNREC.search(ln)
                if m:
                    ours.add(int(m.group(1)))
                continue
            if "[BARAI_" not in ln:
                continue
            m = WASTE.search(ln)
            if m:
                made[int(m.group(2))].append((int(m.group(1)), float(m.group(3)), float(m.group(4))))
                continue
            m = BUILD.search(ln)
            if m:
                events.append((int(m.group(2)), int(m.group(1)), m.group(3), 1))
                continue
            m = DEATH.search(ln)
            if m and m.group(4) == "1":
                events.append((int(m.group(1)), int(m.group(2)), m.group(3), -1))
                continue
            m = ARMY.search(ln)
            if m:
                f, t = int(m.group(1)), int(m.group(2))
                tot = 0.0
                for u in m.group(5).split():
                    parts = u.split(":")
                    c = cat.get(parts[1]) if len(parts) > 1 else None
                    if c and c.get("mob", 0) > 0 and c.get("bp", 0) <= 0:
                        tot += c.get("mCost", 0)
                army[t][f] = army[t].get(f, 0.0) + tot
    if not ours:
        return [], {}
    events.sort()
    counts = collections.defaultdict(collections.Counter)
    samples, our_mix = [], collections.defaultdict(collections.Counter)

    def rate(t, f, k):
        s = [x for x in made[t] if x[0] <= f]
        if len(s) < 2:
            return 0.0
        a, b = s[-2], s[-1]
        return (b[k] - a[k]) / max(1.0, (b[0] - a[0]) / 30.0)

    def army_at(t, f):
        fr = [x for x in army[t] if x <= f]
        return army[t][max(fr)] if fr else 0.0

    for f, t, unit, d in events:
        cls = classify(cat.get(unit))
        if cls is None:
            continue
        if d > 0:
            phase = min(int(f / FPM / 4), 5)
            if t in ours:
                our_mix[phase][cls] += 1
            else:
                c = counts[t]
                x = [f / FPM, rate(t, f, 1), rate(t, f, 2), c["mex"]] + \
                    [c[k] for k in ("energy", "convert", "store", "plant", "nano", "protect", "airdef")] + \
                    [army_at(t, f)]
                samples.append((x, CLASSES.index(cls), phase))
        counts[t][cls] += d
    return samples, our_mix


def train(X, Y, G):
    import torch
    torch.manual_seed(0)
    Xs = np.array([[slog(v) for v in x] for x in X], dtype=np.float32)
    xm, xs = Xs.mean(0), np.maximum(Xs.std(0), 0.25)
    Z = np.clip((Xs - xm) / xs, -6, 6)
    Y = np.array(Y, dtype=np.int64)
    G = np.array(G)
    games = np.unique(G)
    rng = np.random.RandomState(0)
    test = set(rng.choice(games, max(1, len(games) // 5), replace=False))
    te = np.array([g in test for g in G])
    model = torch.nn.Sequential(torch.nn.Linear(Z.shape[1], 32), torch.nn.ReLU(), torch.nn.Dropout(0.1),
                                torch.nn.Linear(32, 32), torch.nn.ReLU(), torch.nn.Dropout(0.1),
                                torch.nn.Linear(32, len(CLASSES)))
    opt = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4)
    Xt, Yt = torch.tensor(Z), torch.tensor(Y)
    tr = torch.tensor(np.where(~te)[0])
    for _ in range(40):
        perm = tr[torch.randperm(len(tr))]
        for i in range(0, len(perm), 256):
            b = perm[i:i + 256]
            loss = torch.nn.functional.cross_entropy(model(Xt[b]), Yt[b])
            opt.zero_grad()
            loss.backward()
            opt.step()
    model.eval()
    with torch.no_grad():
        pred = model(Xt[torch.tensor(np.where(te)[0])]).argmax(1).numpy()
    acc = float((pred == Y[te]).mean())
    base = float((Y[te] == np.bincount(Y[~te], minlength=len(CLASSES)).argmax()).mean())
    # final fit on everything for export
    model.train()
    allidx = torch.arange(len(Xt))
    for _ in range(10):
        perm = allidx[torch.randperm(len(allidx))]
        for i in range(0, len(perm), 256):
            b = perm[i:i + 256]
            loss = torch.nn.functional.cross_entropy(model(Xt[b]), Yt[b])
            opt.zero_grad()
            loss.backward()
            opt.step()
    model.eval()
    sd = model.state_dict()
    return {"xm": xm, "xs": xs, "w1": sd["0.weight"].numpy(), "b1": sd["0.bias"].numpy(),
            "w2": sd["3.weight"].numpy(), "b2": sd["3.bias"].numpy(),
            "w3": sd["6.weight"].numpy(), "b3": sd["6.bias"].numpy()}, acc, base, len(test)


def main(argv):
    cat = load_catalog()
    targets = argv or glob.glob(str(REPO / "tournaments" / "*barb*")) + glob.glob(str(REPO / "tournaments" / "*BARb*"))
    infologs = []
    for t in targets:
        infologs += glob.glob(os.path.join(t, "matches", "*", "infolog.txt")) or glob.glob(os.path.join(t, "infolog.txt"))
    X, Y, G = [], [], []
    their_mix, our_mix = collections.defaultdict(collections.Counter), collections.defaultdict(collections.Counter)
    for gi, il in enumerate(sorted(set(infologs))):
        s, om = game_samples(il, cat)
        for x, y, phase in s:
            X.append(x)
            Y.append(y)
            G.append(gi)
            their_mix[phase][CLASSES[y]] += 1
        for ph, c in om.items():
            our_mix[ph].update(c)
    if not X:
        print("no samples")
        return 1
    print("%d games, %d BARb structures" % (len(set(G)), len(X)))
    print("build mix by phase (share of finished structures): BARb | us")
    for ph in sorted(their_mix):
        tb, ob = sum(their_mix[ph].values()), sum(our_mix[ph].values()) or 1
        print("  min %2d-%2d  " % (ph * 4, ph * 4 + 4) + "  ".join(
            "%s %2.0f|%2.0f" % (k, 100.0 * their_mix[ph][k] / tb, 100.0 * our_mix[ph][k] / ob)
            for k in CLASSES if their_mix[ph][k] or our_mix[ph][k]))
    w, acc, base, ntest = train(X, Y, G)
    print("held-out games %d: predicts BARb's next structure class %.1f%% (always-commonest %.1f%%)"
          % (ntest, 100 * acc, 100 * base))
    np.savez(OUT / "imitate.npz", features=np.array(FEATURES), classes=np.array(CLASSES), **w)
    (OUT / "imitate.json").write_text(json.dumps({"acc": acc, "base": base, "samples": len(X),
                                                  "games": len(set(G))}))
    print("saved", OUT / "imitate.npz")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
