#!/usr/bin/env python3
"""What a seat does once its gantry (the T3 plant) starts producing: income, economy spending and air in the minutes
before and after, ours and the opponent's seats (his 11-05: players saw us stop scaling the economy and make far
less air once the gantry runs).

    python tools/gantrystory.py <match|tournament> [...] [--window 10]

Per seat whose gantry produced: t0 = its first gantry unit. Rates are metal per minute over [t0-window, t0) and
[t0, t0+window); income is the seat's mInc at the window's ends.
"""
from __future__ import annotations

import argparse
import re
from collections import defaultdict
from pathlib import Path

import airaudit
import story

KV = re.compile(r"(\w+)=(\S+)")
GANTRY = {"armshltx", "corgant", "leggant", "armshltxuw", "corgantuw"}
FPS = 30


def matches(paths):
    for p in map(Path, paths):
        if (p / "infolog.txt").exists():
            yield p
        else:
            yield from sorted(x.parent for x in p.glob("matches/*/result.json"))


def at(series, frame):
    """the value at the last sample at or before frame"""
    best = None
    for f in sorted(series):
        if f > frame:
            break
        best = series[f]
    return best


def seats(m: Path, W: float):
    us = airaudit.ours(m)
    _, _, _, _, ally, inc, spent, _, _, _ = story.load(m)
    inc_t, spent_t = defaultdict(dict), defaultdict(dict)
    for f, d in inc.items():
        for t, v in d.items():
            inc_t[t][f] = v
    for f, d in spent.items():
        for t, v in d.items():
            spent_t[t][f] = v
    first_g, prod = {}, defaultdict(list)
    with open(m / "infolog.txt", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "[BARAI_PROD]" not in line:
                continue
            kv = dict(KV.findall(line))
            t, f = int(kv["team"]), int(kv["frame"])
            prod[t].append((f, kv["unit"], float(kv.get("cost", 0)), kv.get("fac", "")))
            if kv.get("fac") in GANTRY and t not in first_g:
                first_g[t] = f
    w = int(W * 60 * FPS)
    out = []
    for t, f0 in first_g.items():
        lo, hi = f0 - w, f0 + w
        if lo < 0 or hi > max(inc_t[t] or {0: 0}):
            continue

        def rate(pred, a, b):
            return sum(c for f, u, c, fac in prod[t] if a <= f < b and pred(u, fac)) / W
        air = lambda u, fac: airaudit.cls(u) in ("bomber", "gunship", "fighter")  # noqa: E731
        gan = lambda u, fac: fac in GANTRY  # noqa: E731
        sp0, sp1, sp2 = at(spent_t[t], lo), at(spent_t[t], f0), at(spent_t[t], hi)
        eco = lambda a, b: ((b[1] - a[1]) / W) if (a and b) else float("nan")  # noqa: E731
        out.append({"game": m.name, "team": t, "ours": t in us, "t0": round(f0 / 1800, 1),
                    "incBefore": at(inc_t[t], lo), "incAt": at(inc_t[t], f0), "incAfter": at(inc_t[t], hi),
                    "ecoBefore": eco(sp0, sp1), "ecoAfter": eco(sp1, sp2),
                    "airBefore": rate(air, lo, f0), "airAfter": rate(air, f0, hi), "gantryAfter": rate(gan, f0, hi)})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--window", type=float, default=10)
    a = ap.parse_args()
    rows = []
    for m in matches(a.paths):
        rows += seats(m, a.window)
    for side in (True, False):
        r = [x for x in rows if x["ours"] == side]
        if not r:
            continue
        n = len(r)
        mean = lambda k: sum(x[k] for x in r if x[k] == x[k]) / max(1, sum(1 for x in r if x[k] == x[k]))  # noqa: E731
        print("%s: %d seats whose gantry produced (first unit at minute %.1f on average); window %g min" % (
            "ours" if side else "theirs", n, mean("t0"), a.window))
        print("  income   before %.0f  at %.0f  after %.0f   (growth before %+.0f, after %+.0f)" % (
            mean("incBefore"), mean("incAt"), mean("incAfter"), mean("incAt") - mean("incBefore"),
            mean("incAfter") - mean("incAt")))
        print("  economy spent per minute  before %.0f  after %.0f" % (mean("ecoBefore"), mean("ecoAfter")))
        print("  air built per minute      before %.0f  after %.0f" % (mean("airBefore"), mean("airAfter")))
        print("  gantry output per minute  after %.0f" % mean("gantryAfter"))


if __name__ == "__main__":
    main()
