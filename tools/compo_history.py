"""Our army's composition across games, in order: does it change with play?

    python tools/compo_history.py [--since YYYYMMDD] [--block N] [--top N] [--side NAME]

Every match under matches/ since the date (default 20260916, the day the
track record went live), chronological, our sides only (`--side` substring of
the spec, default Apex). Per block of N games: army metal share per unit
type for the top types, and the share held by the record's low readers
against its high readers. Army = mobile, armed, not a builder, read off the
game tree once. Games differ (maps, 1v1 vs 2v2, lanes), so a block is a
mixed bag; read the trend, not one block.
"""
import argparse
import collections
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bar_env  # noqa: E402
import unitdef  # noqa: E402

MOBILE_RE = re.compile(r"^\s*speed\s*=\s*([0-9.]+)", re.I | re.M)
BUILDER_RE = re.compile(r"\bbuilder\s*=\s*true", re.I)
WEAPON_RE = re.compile(r"\bweapondefs\s*=", re.I)
_army = {}


def is_army(tree, name):
    if name in _army:
        return _army[name]
    p = tree.find(name)
    ok = False
    if p is not None:
        t = p.read_text(encoding="utf-8", errors="replace")
        m = MOBILE_RE.search(t)
        ok = bool(m) and float(m.group(1)) > 0 and bool(WEAPON_RE.search(t)) and not BUILDER_RE.search(t)
    _army[name] = ok
    return ok


def built(row):
    out = collections.Counter()
    for key in ("allBuilt", "cheapBuilt"):
        for p in str(row.get(key, "")).split(","):
            if ":" in p:
                n, v = p.split(":", 1)
                try:
                    out[n] += float(v)
                except ValueError:
                    pass
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="20260916")
    ap.add_argument("--block", type=int, default=30)
    ap.add_argument("--top", type=int, default=14)
    ap.add_argument("--side", default="Apex")
    a = ap.parse_args()
    env = bar_env.load()
    tree = unitdef.trees(env)[0]
    games = []
    dirs = [(os.path.basename(d), d) for d in glob.glob(str(bar_env.REPO / "matches" / "2026*"))]
    for t in glob.glob(str(bar_env.REPO / "tournaments" / "2026*")):
        for d in glob.glob(os.path.join(t, "matches", "*")):
            dirs.append((os.path.basename(t) + "/" + os.path.basename(d), d))
    for stamp, d in sorted(dirs):
        if stamp[:8] < a.since:
            continue
        try:
            res = json.load(open(os.path.join(d, "result.json")))
        except Exception:
            continue
        stats = res.get("stats") or []
        specs = res.get("teams", [])
        if not stats or not specs:
            continue
        # a 2v2 has four engine teams for two specs: the first half is side A
        per = max(1, len(stats) // len(specs))
        for row in stats:
            si = int(row.get("team", 0)) // per
            if si >= len(specs) or a.side not in specs[si].get("spec", ""):
                continue
            b = built(row)
            army = collections.Counter({n: v for n, v in b.items() if is_army(tree, n)})
            if sum(army.values()) > 0:
                games.append((stamp, specs[si]["spec"], army))
    if not games:
        print("no games")
        return 1
    pooled = collections.Counter()
    for _, _, army in games:
        tot = sum(army.values())
        for n, v in army.items():
            pooled[n] += v / tot
    top = [n for n, _ in pooled.most_common(a.top)]
    blocks = [games[i:i + a.block] for i in range(0, len(games), a.block)]
    print("%d player-games since %s, blocks of %d. Army metal share (%%) per block, top %d types by mean share:"
          % (len(games), a.since, a.block, a.top))
    print("%-10s %5s " % ("type", "mean") + " ".join("%6s" % ("b%d" % i) for i in range(len(blocks))))
    rows = []
    for n in top:
        shares = []
        for blk in blocks:
            s = [army[n] / sum(army.values()) for _, _, army in blk]
            shares.append(100 * sum(s) / len(s))
        rows.append((n, 100 * pooled[n] / len(games), shares))
    for n, mean, shares in rows:
        print("%-10s %5.1f " % (n, mean) + " ".join("%6.1f" % s for s in shares))
    print()
    print("blocks: " + "  ".join("b%d=%s..%s (%d)" % (i, blk[0][0][:13], blk[-1][0][:13], len(blk)) for i, blk in enumerate(blocks)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
