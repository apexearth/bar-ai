"""When the commander died, was he inside ANY of our guns' range?

The naive version measured distance to the nearest gun of any kind, which conflates
a Sentry (430) with an Annihilator (1400). This asks the question that
actually separates the explanations:

  inside some gun's envelope and died  -> wrong IDEA (the gun was there)
  outside every envelope               -> wrong PLACE (shortfall = by how much)
"""
import bisect
import collections
import glob
import math
import os
import re
import sys

RANGE = {
    "armllt": 430, "armclaw": 430, "armbeamer": 480, "armhlt": 620,
    "armpb": 730, "armguard": 1220, "armamb": 1380, "armanni": 1400,
}
TOW = re.compile(r"(llt|beamer|hlt|guard|pb|claw|amb|anni)$")

covered, shortfall, n_deaths = 0, [], 0
cover_kind = collections.Counter()
miss_kind = collections.Counter()

for T in sys.argv[1:]:
    for M in sorted(glob.glob(os.path.join(T, "matches", "t*"))):
        info = os.path.join(M, "infolog.txt")
        if not os.path.exists(info):
            continue
        script = open(os.path.join(M, "script.txt")).read()
        ap0 = "Apex" in re.search(r"\[AI0\](.*?)\[AI1\]", script, re.S).group(1)
        txt = open(info, encoding="utf-8", errors="replace").read()
        towers = collections.defaultdict(list)
        for m in re.finditer(r"\[BARAI_POS\] team=(\d) ally=\d frame=(\d+) "
                             r"n=\d+ part=\d+/\d+ (\S*)", txt):
            if (int(m.group(1)) < 2) != ap0:
                continue
            f = int(m.group(2))
            for e in m.group(3).split(","):
                p = e.split(":")
                if len(p) >= 3 and TOW.search(p[0]):
                    try:
                        towers[f].append((p[0], float(p[1]), float(p[2])))
                    except ValueError:
                        pass
        frames = sorted(towers)
        for m in re.finditer(r"\[BARAI_DEATH\] frame=(\d+) team=(\d) "
                             r"unit=(?:arm|cor|leg)com\w* cost=\d+ "
                             r"x=([-\d.]+) z=([-\d.]+)", txt):
            if (int(m.group(2)) < 2) != ap0:
                continue
            f, cx, cz = int(m.group(1)), float(m.group(3)), float(m.group(4))
            if not frames:
                continue
            i = bisect.bisect_right(frames, f) - 1
            if i < 0:
                continue
            n_deaths += 1
            # best = smallest (distance - that gun's own range)
            best = None
            for name, tx, tz in towers[frames[i]]:
                r = RANGE.get(name)
                if r is None:
                    continue
                gap = math.hypot(cx - tx, cz - tz) - r
                if best is None or gap < best[0]:
                    best = (gap, name)
            if best is None:
                continue
            if best[0] <= 0:
                covered += 1
                cover_kind[best[1]] += 1
            else:
                shortfall.append(best[0])
                miss_kind[best[1]] += 1

if not n_deaths:
    print("no commander deaths with a tower sample")
    raise SystemExit(0)
print("%d commander deaths with a standing-tower sample" % n_deaths)
print("  INSIDE a gun's range when he died: %d (%.0f%%)"
      % (covered, 100.0 * covered / n_deaths))
print("    that gun: %s"
      % ", ".join("%s %d" % kv for kv in cover_kind.most_common(4)))
shortfall.sort()
if shortfall:
    s, k = shortfall, len(shortfall)
    print("  OUTSIDE every gun's range:         %d (%.0f%%)"
          % (k, 100.0 * k / n_deaths))
    print("    elmo beyond the nearest envelope: median %.0f  p25 %.0f  p75 %.0f"
          % (s[k // 2], s[k // 4], s[3 * k // 4]))
    print("    nearest (still short) gun: %s"
          % ", ".join("%s %d" % kv for kv in miss_kind.most_common(4)))
