"""Why a build we started was abandoned.

    python tools/abortwhy.py <tournament-dirs...>

`apex: abort` carries the state of the task at the moment it died:

  workers=0        nobody was on it -- the hand was re-elected or peeled away
  builderToSite    how far the nearest worker still was; large means nobody
                   ever arrived, so the walk was the whole cost
  cover/unitCover  if a guard arriving raised cover and zeroed the want that
                   sent the builder (apexearth's own hypothesis, 2026-09-07)

Only the first 30 aborts of each game are logged, so this is a sample of the
opening, not a census.
"""
import collections
import glob
import os
import re
import sys

AB = re.compile(r"apex: abort t=(\d+) (\S+) workers=(\d+) "
                r"siteFromHome=(-?\d+) builderToSite=(-?\d+) "
                r"cover=(-?[\d.]+) unitCover=(-?[\d.]+)")

rows = collections.defaultdict(lambda: collections.Counter())
far = collections.defaultdict(list)
n = 0
uncov = 0

for T in sys.argv[1:]:
    for M in sorted(glob.glob(os.path.join(T, "matches", "t*"))):
        info = os.path.join(M, "infolog.txt")
        if not os.path.exists(info):
            continue
        script = open(os.path.join(M, "script.txt")).read()
        ap0 = "Apex" in re.search(r"\[AI0\](.*?)\[AI1\]", script, re.S).group(1)
        for ln in open(info, encoding="utf-8", errors="replace"):
            m = AB.search(ln)
            if not m:
                continue
            if (int(m.group(1)) < 2) != ap0:
                continue
            n += 1
            d, w = m.group(2), int(m.group(3))
            toSite = int(m.group(5))
            cov, ucov = float(m.group(6)), float(m.group(7))
            rows[d]["n"] += 1
            rows[d]["noworker" if w == 0 else "worker"] += 1
            if toSite >= 0:
                far[d].append(toSite)
            if ucov > 0:
                uncov += 1

if not n:
    print("no apex: abort lines")
    raise SystemExit(0)
print("%d sampled aborts (first 30 a game)" % n)
tot_now = sum(r["noworker"] for r in rows.values())
print("  NOBODY was on the task when it died: %d (%.0f%%)"
      % (tot_now, 100.0 * tot_now / n))
print("  a worker was still on it:            %d (%.0f%%)" % (n - tot_now, 100.0 * (n - tot_now) / n))
print("  unit cover > 0 at the site:          %d (%.0f%%)  <- a guard arriving can zero the want"
      % (uncov, 100.0 * uncov / n))
print()
print("  %-14s %6s %10s %10s   %s" % ("def", "n", "no worker", "med walk left", ""))
for d, c in sorted(rows.items(), key=lambda kv: -kv[1]["n"])[:12]:
    v = sorted(far[d])
    med = v[len(v) // 2] if v else -1
    print("  %-14s %6d %9.0f%% %10d" % (d, c["n"], 100.0 * c["noworker"] / c["n"], med))
