#!/usr/bin/env python3
"""What sets a seat's economy apart when the code is the same (his 11-22: "some of our games online seem unusually easy.
It's just a matter of whether it played good eco on that particular game or not. I wish we could identify what causes
that ECO to perform worse").

    python tools/eco_variance.py <match dir> ... [--ai Apex] [--outcome-min 20]

Every Apex seat of every game (result.json stats, dev_stats) is one row: its metal income at --outcome-min (metal
produced over the two minutes before it) and its early state at minutes 4/6/8/10/12 -- extractors, builders, metal in
economy / build power / army / defence / factories, metal lost, reclaimed and wasted (excess), the T2 lab start, the
commander's idle share. Printed: for each early measure, Spearman's rank correlation with the outcome over all seats,
and the same within games (each seat against the mean of the game's other Apex seats, which takes the map and the
opponent out); the strongest first. Then the five best and five worst seats side by side on the strongest measures.
"""
import json
import math
import sys
from pathlib import Path

FEATS = ("mex", "ownBuilders", "mEco", "mBP", "mArmy", "mDefence", "mFactories", "mLostReal", "mLostCheap", "mReclaim",
         "metalExcess", "conT1", "passive", "commIdle")
MINS = (4, 6, 8, 10, 12)


def rank(v):
    o = sorted(range(len(v)), key=lambda i: v[i])
    r = [0.0] * len(v)
    i = 0
    while i < len(o):
        j = i
        while j + 1 < len(o) and v[o[j + 1]] == v[o[i]]:
            j += 1
        for k in range(i, j + 1):
            r[o[k]] = (i + j) / 2.0
        i = j + 1
    return r


def spearman(x, y):
    if len(x) < 4:
        return 0.0
    rx, ry = rank(x), rank(y)
    mx, my = sum(rx) / len(rx), sum(ry) / len(ry)
    sxy = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    sx = math.sqrt(sum((a - mx) ** 2 for a in rx))
    sy = math.sqrt(sum((b - my) ** 2 for b in ry))
    return sxy / (sx * sy) if sx > 0 and sy > 0 else 0.0


def seats(match, ai_prefix, out_min):
    rj = Path(match) / "result.json"
    if not rj.exists():
        return []
    d = json.loads(rj.read_text())
    specs = {}
    for t in (d.get("teams") or []):
        try:
            specs[int(t.get("team", -1))] = str(t.get("ai", t.get("spec", "")))
        except (TypeError, ValueError):
            pass
    rows = {}
    for r in d.get("stats") or []:
        rows.setdefault(int(r["team"]), []).append(r)
    out = []
    for t, rs in rows.items():
        rs.sort(key=lambda r: r["frame"])

        def at(m):
            best = None
            for r in rs:
                if r["frame"] <= m * 1800 + 1:
                    best = r
            return best
        end, before = at(out_min), at(out_min - 2)
        if end is None or before is None or end["frame"] < (out_min - 0.5) * 1800:
            continue
        dt = (end["frame"] - before["frame"]) / 30.0
        if dt <= 0:
            continue
        inc = (end.get("metalProduced", 0) - before.get("metalProduced", 0)) / dt
        row = {"match": Path(match).name, "team": t, "ally": int(end.get("ally", -1)), "spec": specs.get(t, ""),
               "inc": inc}
        for m in MINS:
            r = at(m)
            if r is None:
                continue
            for f in FEATS:
                row["%s@%d" % (f, m)] = float(r.get(f, 0) or 0)
            ts = float(r.get("techStart", -1) or -1)
            row["t2start@%d" % m] = 1.0 if 0 < ts <= m * 1800 else 0.0
            cs = float(r.get("commSamp", 0) or 0)
            row["commIdleShare@%d" % m] = float(r.get("commIdle", 0) or 0) / cs if cs else 0.0
        out.append(row)
    if ai_prefix:
        out = [r for r in out if not r["spec"] or r["spec"].startswith(ai_prefix)] or out
    return out


def main(a):
    def opt(name, default):
        return a[a.index(name) + 1] if name in a else default
    out_min = int(opt("--outcome-min", "20"))
    ai = opt("--ai", "")
    paths = [x for i, x in enumerate(a) if not x.startswith("--") and (i == 0 or a[i - 1] not in ("--ai", "--outcome-min"))]
    rows = []
    for p in paths:
        rows += seats(p, ai, out_min)
    print("seats %d from %d games; income at %d min: median %.0f, range %.0f-%.0f" % (
        len(rows), len(paths), out_min, sorted(r["inc"] for r in rows)[len(rows) // 2] if rows else 0,
        min((r["inc"] for r in rows), default=0), max((r["inc"] for r in rows), default=0)))
    keys = sorted({k for r in rows for k in r if "@" in k})
    by_game = {}
    for r in rows:
        by_game.setdefault(r["match"], []).append(r)
    res = []
    for k in keys:
        have = [r for r in rows if k in r]
        x = [r[k] for r in have]
        y = [r["inc"] for r in have]
        if len(set(x)) < 3:
            continue
        # within games: each seat minus the mean of the game's other seats
        wx, wy = [], []
        for g in by_game.values():
            g = [r for r in g if k in r]
            if len(g) < 2:
                continue
            for r in g:
                o = [q for q in g if q is not r]
                wx.append(r[k] - sum(q[k] for q in o) / len(o))
                wy.append(r["inc"] - sum(q["inc"] for q in o) / len(o))
        res.append((abs(spearman(wx, wy)), spearman(x, y), spearman(wx, wy), k))
    res.sort(reverse=True)
    print("early measure        all seats   within games   (Spearman rho with income at %d)" % out_min)
    for _, rho, wrho, k in res[:20]:
        print("  %-20s %+.2f       %+.2f" % (k, rho, wrho))
    top = [k for _, _, _, k in res[:5]]
    srt = sorted(rows, key=lambda r: r["inc"])
    print("\nworst and best seats on the top measures:")
    print("  %-34s %6s  " % ("game/team", "inc") + "  ".join("%14s" % k for k in top))
    for r in srt[:5] + srt[-5:]:
        print("  %-34s %6.0f  " % ((r["match"][:28] + "/t%d" % r["team"]), r["inc"])
              + "  ".join("%14.0f" % r.get(k, float("nan")) for k in top))


if __name__ == "__main__":
    main(sys.argv[1:])
