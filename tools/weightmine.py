"""Which parts of the policy network go with winning, and new networks merged from them (his 10-11).

The network comes in whole blocks (neuro.blocks): 16 shared-layer neurons, then one block per head. For
each block it asks: across the random-search networks with an honest record (games on varied seeds; every
game before 10-11 15:15 was seed 1), does a network whose block sits close to the WINNERS' version of that
block win more? The winners' version is the centroid of the block over networks that beat the average,
weighted by how far they beat it and how many games say so; closeness is scored leave-one-out, so a
network's own block never counts toward its own score. A block with a clearly positive score is one where
winners agree; a block near zero is one where the record says nothing.

Merges: a head reads the shared layer's neurons, so a head moved onto a different shared layer means
something else. The merged networks therefore take the shared layer from one parent (the best honest
record) and only the HEADS from the winners' centroids where the score says the winners agree.

    python tools/weightmine.py                  # the block table
    python tools/weightmine.py --min 6          # networks with at least 6 varied-seed games
    python tools/weightmine.py --write 3        # also write 3 merged networks to runtime/nn/merge-inbox/,
                                                # which randsearch adopts at the 4-game rung
"""
import glob, json, math, os, sys, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
import cem, neuro, randsearch


def honest_records(st, min_games):
    """{net id: [wins, games]} over games played on a seed other than 1 (a time-limit lead counts as cem calls it)."""
    rec = {}
    for rj in glob.glob(os.path.join(st["dir"], "matches", "c*-g*", "result.json")):
        d = os.path.dirname(rj)
        try:
            seed = json.load(open(rj, encoding="utf-8")).get("seed")
        except Exception:
            continue
        if seed in (None, 1):
            continue
        sc = cem.score(d)
        if sc is None:
            continue
        nid = int(os.path.basename(d).split("-g")[0][1:])
        r = rec.setdefault(nid, [0.0, 0])
        r[0] += {"W": 1.0, "D": 0.5}.get(sc[1], 0.0)
        r[1] += 1
    return {k: v for k, v in rec.items() if v[1] >= min_games}


def corr(xs, ys):
    n = len(xs)
    if n < 3:
        return 0.0
    mx, my = sum(xs) / n, sum(ys) / n
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    sxx = sum((x - mx) ** 2 for x in xs)
    syy = sum((y - my) ** 2 for y in ys)
    return sxy / math.sqrt(sxx * syy) if sxx > 0 and syy > 0 else 0.0


def main(argv):
    min_games = int(argv[argv.index("--min") + 1]) if "--min" in argv else 4
    n_write = int(argv[argv.index("--write") + 1]) if "--write" in argv else 0
    st = randsearch.load()
    lay = neuro.load()["layout"]
    blocks = neuro.blocks(lay)
    names = ["shared%02d" % i for i in range(neuro.H1)] + [h.get("name", h["key"]) for h in lay["heads"]]
    rec = honest_records(st, min_games)
    # one family only: networks that are the shared middle plus noise, so weight k means the same in each
    fam = {int(k) for k, n in st["nets"].items() if n.get("family") == randsearch.FAMILY}
    fam |= {int(k) for k, n in st["nets"].items() if "middle" in str(n.get("label", ""))}
    if "--all" not in argv:
        if len([i for i in rec if i in fam]) < 6:
            print("the %s family has %d networks with %d+ varied-seed games -- too few yet; --all reads every network "
                  "(but their neurons do not line up)" % (randsearch.FAMILY, len([i for i in rec if i in fam]), min_games))
            return 1
        rec = {i: v for i, v in rec.items() if i in fam}
    W = {}
    for nid in rec:
        f = os.path.join(st["dir"], "c%02d.weights" % nid)
        if os.path.exists(f):
            W[nid] = [float(x) for x in open(f, encoding="utf-8").read().split()]
    ids = sorted(W)
    if len(ids) < 6:
        print("only %d networks with %d+ varied-seed games -- too few to read anything" % (len(ids), min_games))
        return 1
    games = sum(rec[i][1] for i in ids)
    base = sum(rec[i][0] for i in ids) / games
    # win rate shrunk toward the base by 4 games' worth: one lucky game is not a winner
    p = {i: (rec[i][0] + 4 * base) / (rec[i][1] + 4) for i in ids}
    print("%d networks, %d varied-seed games, base win rate %.0f%%" % (len(ids), games, 100 * base))

    def centroid(b, skip=None):
        lo, hi = blocks[b]
        acc, wsum = [0.0] * (hi - lo), 0.0
        for i in ids:
            if i == skip:
                continue
            w = max(0.0, p[i] - base) * rec[i][1]
            if w <= 0.0:
                continue
            wsum += w
            for k in range(hi - lo):
                acc[k] += w * W[i][lo + k]
        return [a / wsum for a in acc] if wsum > 0 else None

    rows = []
    for b, (lo, hi) in enumerate(blocks):
        xs, ys = [], []
        for i in ids:
            c = centroid(b, skip=i)
            if c is None:
                continue
            d = math.sqrt(sum((W[i][lo + k] - c[k]) ** 2 for k in range(hi - lo)) / (hi - lo))
            xs.append(-d)
            ys.append(p[i])
        rows.append((corr(xs, ys), b, names[b], lo, hi))
    rows.sort(reverse=True)
    print("\nblock                         weights      score  (closer to the winners' version -> wins more; >0.3 notable)")
    for r, b, name, lo, hi in rows[:15]:
        print("  %-28s %5d-%-5d  %+.2f" % (name[:28], lo, hi - 1, r))
    print("  ...")
    for r, b, name, lo, hi in rows[-5:]:
        print("  %-28s %5d-%-5d  %+.2f" % (name[:28], lo, hi - 1, r))
    best = max(ids, key=lambda i: p[i])
    print("\nbest honest record: net %d, %.1f of %d" % (best, rec[best][0], rec[best][1]))

    # PER WEIGHT: where the winners' values bunch much tighter than everyone's, in runs of neighbours
    wts = {i: max(0.0, p[i] - base) * rec[i][1] for i in ids}
    wsum = sum(wts.values())
    nW = len(W[ids[0]])
    tight, wmean = [], [0.0] * nW
    if wsum > 0:
        for k in range(nW):
            allv = [W[i][k] for i in ids]
            ma = sum(allv) / len(allv)
            sa = math.sqrt(sum((v - ma) ** 2 for v in allv) / len(allv))
            mw = sum(wts[i] * W[i][k] for i in ids) / wsum
            sw = math.sqrt(sum(wts[i] * (W[i][k] - mw) ** 2 for i in ids) / wsum)
            wmean[k] = mw
            if sa > 1e-6 and sw < 0.5 * sa:
                tight.append(k)
    runs, start = [], None
    for j, k in enumerate(tight):
        if start is None:
            start = k
        if (j + 1 == len(tight)) or (tight[j + 1] != k + 1):
            runs.append((start, k))
            start = None
    owner = lambda k: next(names[b] for b, (lo, hi) in enumerate(blocks) if lo <= k < hi)
    long_runs = sorted([r for r in runs if r[1] - r[0] >= 2], key=lambda r: -(r[1] - r[0]))
    print("\nweights where the winners bunch (spread under half of everyone's): %d of %d, %d runs of 3+"
          % (len(tight), nW, len(long_runs)))
    for a, z in long_runs[:12]:
        print("  %5d-%-5d  %-24s %d weights" % (a, z, owner(a), z - a + 1))

    if n_write and "--all" not in argv:
        # within one family weight k is the same weight everywhere, so blocks and single weights move freely:
        # the best record's network, the bunched weights set to the winners' mean, and the top share of the
        # blocks where winners agree set to their centroid
        agree = [(r, b) for r, b, *_ in rows if r > 0.0]
        inbox = os.path.join(REPO, "runtime", "nn", "merge-inbox")
        os.makedirs(inbox, exist_ok=True)
        stamp = time.strftime("%m%d-%H%M")
        for m in range(1, n_write + 1):
            take = agree[: int(round(len(agree) * m / n_write))]
            w = list(W[best])
            for k in tight:
                w[k] = wmean[k]
            for r, b in take:
                lo, hi = blocks[b]
                w[lo:hi] = centroid(b)
            f = os.path.join(inbox, "merge-%s-%d.weights" % (stamp, m))
            with open(f, "w", encoding="utf-8") as fh:
                fh.write(" ".join("%.6g" % x for x in w))
            print("wrote %s: net %d + %d bunched weights + %d agreeing block(s): %s" % (
                os.path.basename(f), best, len(tight), len(take),
                ", ".join(names[b] for _, b in take[:6]) + (" ..." if len(take) > 6 else "")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
