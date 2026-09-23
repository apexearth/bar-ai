"""Damage efficiency minute by minute, both sides, with army sizes beside it.

    python tools/earlytrade.py <tournament-dirs...> [--bucket N]

A whole-game trade ratio cannot answer "do we fight worse": once we are losing
we lose the whole army, so the cumulative number reports the defeat, not the
fighting. apexearth, 2026-09-23: what matters is the exchange while the armies
are still comparably sized.

So: DELTAS inside each bucket, never cumulative, next to how much army each
side has built by then. Read the minutes where `built` is close on both sides;
the ones after that are the collapse and prove nothing about efficiency.
"""
import collections
import glob
import os
import re
import sys

STAT = re.compile(r"BARAI_STATS\] team=(\d+) ally=\d+ reason=\w+ frame=(\d+) ")
F = {k: re.compile(r"\b%s=(\d+)" % k)
     for k in ("mKillMobile", "mLostMobile", "mArmy")}

args = [a for a in sys.argv[1:] if not a.startswith("--")]
bucket = 1
if "--bucket" in sys.argv:
    bucket = int(sys.argv[sys.argv.index("--bucket") + 1])

acc = {True: collections.defaultdict(collections.Counter),
       False: collections.defaultdict(collections.Counter)}
games = 0

for T in args:
    for M in sorted(glob.glob(os.path.join(T, "matches", "t*"))):
        info = os.path.join(M, "infolog.txt")
        if not os.path.exists(info):
            continue
        script = open(os.path.join(M, "script.txt")).read()
        ap0 = "Apex" in re.search(r"\[AI0\](.*?)\[AI1\]", script, re.S).group(1)
        games += 1
        prev = {}
        for ln in open(info, encoding="utf-8", errors="replace"):
            m = STAT.search(ln)
            if not m:
                continue
            team, frame = int(m.group(1)), int(m.group(2))
            row = {}
            for k, rx in F.items():
                g = rx.search(ln)
                if g:
                    row[k] = int(g.group(1))
            if len(row) < 3:
                continue
            ours = (team < 2) == ap0
            b = int(frame / 30 / 60 / bucket) * bucket
            p = prev.get(team)
            if p is not None:
                c = acc[ours][b]
                c["kill"] += max(0, row["mKillMobile"] - p["mKillMobile"])
                c["lost"] += max(0, row["mLostMobile"] - p["mLostMobile"])
            acc[ours][b]["built"] += row["mArmy"]
            acc[ours][b]["n"] += 1
            prev[team] = row

if not games:
    print("no stats samples")
    raise SystemExit(0)


def ratio(c):
    return (c["kill"] / c["lost"]) if c["lost"] else 0.0


print("%d games, %d-minute buckets. Kill/lost are DELTAS inside the bucket,"
      % (games, bucket))
print("summed over all games; army built is the level, averaged per sample.")
print()
print("  %-6s %18s %18s %14s" % ("", "------- us -------",
                                 "------ BARb ------", "-- efficiency -"))
print("  %-6s %7s %5s %5s %7s %5s %5s %6s %6s  %s"
      % ("min", "built", "kill", "lost", "built", "kill", "lost",
         "us", "them", "army gap"))
for b in sorted(set(acc[True]) | set(acc[False])):
    u, t = acc[True][b], acc[False][b]
    if not u["n"] or not t["n"]:
        continue
    ub, tb = u["built"] / u["n"], t["built"] / t["n"]
    gap = ("%+.0f%%" % (100.0 * (ub - tb) / tb)) if tb else "-"
    print("  %-6s %7.0f %5.0f %5.0f %7.0f %5.0f %5.0f %6.2f %6.2f  %s"
          % ("%d" % b, ub, u["kill"] / games, u["lost"] / games,
             tb, t["kill"] / games, t["lost"] / games,
             ratio(u), ratio(t), gap))
