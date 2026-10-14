"""Carry every policy network into a layout with more heads, by head key (his 10-14 army heads).

The trunk and every head the old layout has are copied as they are. A head the old layout lacks gets
neuro.middle()'s weights for one head -- small random hidden weights, every output weight 0 -- drawn
once per head (--seed) and shared by every network, so a migrated network plays exactly as before:
a continuous head at output 0 plays the log-middle of its range, which for the army heads is 1x.

Reads the old layout from neuro.json (or any JSON with a "layout" key, or a bare layout); the new one
is neuro.extend_layout(old) unless --new names a layout JSON. Writes ONLY under --out, and only with
--write (the default is a dry run that says what it would write):

    python tools/pn_migrate.py --out G:/tmp/pnmig                       # dry run
    python tools/pn_migrate.py --out G:/tmp/pnmig --write \\
        --state runtime/nn/neuro.json --best runtime/nn/neuro_best.json \\
        --weights tournaments/20261014-020717-nn-rand

Under --out: layout.json; neuro.json / neuro_best.json (every weight vector in them mapped, the
layout replaced); policydata.as (the new layout with the best -- "watch", else "best" -- network)
and policydata.repo.as (the same with no weights, for the repo); and each weights file as
<out>/<its folder name>/<file name>.
"""
import argparse, json, math, os, random, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
import neuro


def load_layout(path):
    d = json.load(open(path, encoding="utf-8"))
    if "layout" in d:
        d = d["layout"]
    if "heads" not in d or "idx" not in d:
        raise SystemExit("%s holds no layout" % path)
    return d


def offsets(lay):
    """key -> (start, end) of each head's block, and the trunk's end."""
    N = len(lay["idx"])
    at = neuro.H1 * (N + 1)
    trunk = at
    out = {}
    for h in lay["heads"]:
        n = neuro.head_size(h)
        out[h["key"]] = (at, at + n)
        at += n
    return trunk, out, at


def middle_head(h, rng):
    """neuro.middle() for one head."""
    v = []
    fan = neuro.H1 + h["F"]
    for _ in range(neuro.H2):
        v += [rng.gauss(0, 1 / math.sqrt(fan)) for _ in range(fan)] + [0.0]
    K = h["K"] if h["K"] > 0 else 1
    return v + [0.0] * (K * (neuro.H2 + 1))


class Mapper:
    def __init__(self, old, new, seed):
        if old["idx"] != new["idx"] or old["state"] != new["state"]:
            raise SystemExit("the trunk's inputs differ between the layouts: nothing maps")
        self.trunk, self.old_at, self.n_old = offsets(old)
        _, self.new_at, self.n_new = offsets(new)
        self.new = new
        oldh = {h["key"]: h for h in old["heads"]}
        self.added, self.reshaped, self.fresh = [], [], {}
        for k, h in enumerate(new["heads"]):
            o = oldh.get(h["key"])
            if o is not None and neuro.head_size(o) == neuro.head_size(h):
                continue
            (self.added if o is None else self.reshaped).append(h.get("name") or h["key"])
            self.fresh[h["key"]] = middle_head(h, random.Random(seed * 1000003 + k))

    def map(self, w):
        if len(w) != self.n_old:
            raise ValueError("%d weights, the old layout has %d" % (len(w), self.n_old))
        out = list(w[:self.trunk])
        for h in self.new["heads"]:
            if h["key"] in self.fresh:
                out += self.fresh[h["key"]]
            else:
                a, b = self.old_at[h["key"]]
                out += w[a:b]
        assert len(out) == self.n_new
        return out


def map_json(x, m, count):
    """Every list of n_old numbers anywhere in x, mapped."""
    if isinstance(x, list):
        if len(x) == m.n_old and all(isinstance(v, (int, float)) for v in x):
            count[0] += 1
            return m.map(x)
        return [map_json(v, m, count) for v in x]
    if isinstance(x, dict):
        return {k: map_json(v, m, count) for k, v in x.items()}
    return x


def weight_files(paths):
    for p in paths:
        if os.path.isdir(p):
            for name in sorted(os.listdir(p)):
                if name.endswith(".weights"):
                    yield os.path.join(p, name)
        elif os.path.isfile(p):
            yield p
        else:
            print("  skip %s: not found" % p)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, help="the only directory written to")
    ap.add_argument("--write", action="store_true", help="write (the default is a dry run)")
    ap.add_argument("--old", default=os.path.join(neuro.NN, "neuro.json"), help="the old layout")
    ap.add_argument("--new", help="the new layout (default: neuro.extend_layout(old))")
    ap.add_argument("--state", help="a neuro.json to carry over")
    ap.add_argument("--best", help="a neuro_best.json to carry over")
    ap.add_argument("--weights", nargs="*", default=[], help=".weights files or folders of them")
    ap.add_argument("--seed", type=int, default=1, help="draws the new heads' hidden weights")
    a = ap.parse_args(argv)

    old = load_layout(a.old)
    new = load_layout(a.new) if a.new else neuro.extend_layout(old)
    m = Mapper(old, new, a.seed)
    out = os.path.abspath(a.out)
    print("layout: %d -> %d weights, %d -> %d heads; added %s; reshaped %s" % (
        m.n_old, m.n_new, len(old["heads"]), len(new["heads"]), ",".join(m.added) or "-",
        ",".join(m.reshaped) or "-"))
    if m.reshaped:
        print("  WARNING: a reshaped head's own features changed; it restarts at its middle in every network")
    writes = []   # (path, text)

    def emit(rel, text):
        p = os.path.join(out, rel)
        if os.path.commonpath([out, os.path.abspath(p)]) != out:
            raise SystemExit("refusing to write outside --out: %s" % p)
        writes.append((p, text))

    emit("layout.json", json.dumps(new))
    best_w = None
    if a.best:
        b = json.load(open(a.best, encoding="utf-8"))
        n = [0]
        b2 = map_json(b, m, n)
        emit("neuro_best.json", json.dumps(b2))
        pick = b2.get("watch") or b2.get("best")
        best_w = pick["w"] if pick else None
        print("  %s: %d weight vectors" % (a.best, n[0]))
    if a.state:
        s = json.load(open(a.state, encoding="utf-8"))
        n = [0]
        s2 = map_json({k: v for k, v in s.items() if k != "layout"}, m, n)
        if "layout" in s:
            s2["layout"] = new
        emit("neuro.json", json.dumps(s2))
        print("  %s: %d weight vectors" % (a.state, n[0]))
    nf = nskip = 0
    for f in weight_files(a.weights):
        w = [float(x) for x in open(f, encoding="utf-8").read().split()]
        try:
            w2 = m.map(w)
        except ValueError as e:
            nskip += 1
            print("  skip %s: %s" % (f, e))
            continue
        rel = os.path.join(os.path.basename(os.path.dirname(os.path.abspath(f))), os.path.basename(f))
        emit(rel, " ".join("%.6g" % x for x in w2))
        nf += 1
    if a.weights:
        print("  weights files: %d mapped, %d skipped" % (nf, nskip))
    pd = os.path.join(out, "policydata.as")
    print("  policydata.as with %s" % ("the best network" if best_w else "no weights (every head at its middle)"))

    if not a.write:
        print("DRY RUN: would write %d files under %s (and policydata.as); pass --write" % (len(writes), out))
        return 0
    for p, text in writes:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
    os.makedirs(out, exist_ok=True)
    neuro.write_data(pd, new, best_w)
    neuro.write_data(os.path.join(out, "policydata.repo.as"), new, None)
    print("wrote %d files, policydata.as and policydata.repo.as (no weights) under %s" % (len(writes), out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
