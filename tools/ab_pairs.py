"""Paired A/B of two tournaments that walked the same seeds (run_tournament): each game against its own pair.

    python tools/ab_pairs.py <arm-A dir> <arm-B dir> [...more A,B pairs]

Pairs by (seed, which side we played). Per game: the result, income and extractors at minutes 8/12/16/20, army and
metal lost/killed at the end, and from the job ledger (tools/ledger.py) the build jobs that failed, the constructors
killed on a job, and the metal of frames lost. Prints each arm's mean, the paired difference B-A with its standard
error, and the sign count over pairs. Only our seats are read.
"""
import glob
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ledger  # noqa: E402

STATS = re.compile(r"\[BARAI_STATS\] team=(\d+) (.*)")
MINUTES = (8, 12, 16, 20)


def game(md):
    try:
        r = json.load(open(os.path.join(md, "result.json"), encoding="utf-8"))
    except (OSError, ValueError):
        return None
    ours = ledger.our_teams(md)
    if not ours:
        return None
    res = r.get("result") or {}
    win = " ".join(res.get("winner_specs") or [])
    g = {"seed": (r.get("seed"), r.get("map")), "W": 1.0 if "Apex" in win else 0.0, "L": 1.0 if (win and "Apex" not in win) else 0.0}
    rows = {}
    for ln in open(os.path.join(md, "infolog.txt"), encoding="utf-8", errors="replace"):
        m = STATS.search(ln)
        if m and int(m.group(1)) in ours:
            kv = dict(x.split("=", 1) for x in m.group(2).split(" ") if "=" in x)
            if kv.get("reason") == "periodic":
                rows[(int(m.group(1)), int(kv["frame"]) // 1800)] = kv
    for mi in MINUTES:
        vals = [rows.get((t, mi)) for t in ours]
        if all(v is not None for v in vals):
            g["inc%d" % mi] = sum(float(v["mInc"]) for v in vals)
            g["mex%d" % mi] = sum(float(v.get("mex", 0)) for v in vals)
    last = {}
    for (t, mi), kv in rows.items():
        if t not in last or mi > last[t][0]:
            last[t] = (mi, kv)
    for k in ("armyReal", "mLostReal", "mKillReal", "damageDealt", "damageReceived"):
        g[k] = sum(float(kv.get(k, 0)) for _, kv in last.values())
    jobs = ledger.read_game(md)
    g["jobsFailed"] = float(sum(1 for j in jobs if j.get("frameLost") or j.get("builderDied")))
    g["consKilled"] = float(sum(1 for j in jobs if j.get("builderDied")))
    g["frameM"] = float(sum(j["cost"] for j in jobs if j.get("frameLost")))
    g["mexFrames"] = float(sum(1 for j in jobs if j.get("frameLost") and j["def"].endswith("mex")))
    script = open(os.path.join(md, "script.txt"), encoding="utf-8", errors="replace").read()
    first = re.search(r"\[AI0\].*?ShortName=([^;]+);", script, re.S | re.I)
    g["side"] = bool(first and first.group(1).startswith("Apex"))
    return g


def arm(d):
    out = {}
    for md in sorted(glob.glob(os.path.join(d, "matches", "*"))):
        g = game(md)
        if g:
            out[(g["seed"], g["side"])] = g
    return out


def main(dirs):
    if len(dirs) % 2:
        raise SystemExit("give arm A and arm B dirs in pairs")
    A, B = {}, {}
    for i in range(0, len(dirs), 2):
        a, b = arm(dirs[i]), arm(dirs[i + 1])
        for k in a:
            if k in b:
                A[(i, k)], B[(i, k)] = a[k], b[k]
    keys = sorted(A)
    print("pairs: %d" % len(keys))
    cols = ["W", "L"] + ["inc%d" % m for m in MINUTES] + ["mex%d" % m for m in MINUTES] + \
           ["armyReal", "mLostReal", "mKillReal", "jobsFailed", "consKilled", "frameM", "mexFrames"]
    print("%-12s %10s %10s %12s %10s   B>A / B<A" % ("", "arm A", "arm B", "B-A", "+-se"))
    for c in cols:
        d = [(B[k][c], A[k][c]) for k in keys if c in A[k] and c in B[k]]
        if not d:
            continue
        diff = [b - a for b, a in d]
        n = len(diff)
        mean = sum(diff) / n
        se = math.sqrt(sum((x - mean) ** 2 for x in diff) / max(1, n - 1) / n) if n > 1 else 0.0
        print("%-12s %10.2f %10.2f %+12.2f %10.2f   %d / %d  (n=%d)" % (
            c, sum(a for _, a in d) / n, sum(b for b, _ in d) / n, mean, se,
            sum(1 for x in diff if x > 0), sum(1 for x in diff if x < 0), n))


if __name__ == "__main__":
    main(sys.argv[1:])
