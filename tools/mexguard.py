"""When one of our forward extractors died, did it have a gun?

His mex-guard ruling (2026-09-17) is implemented: MexGunsWanted scales the
per-mex defence floor from one light tower at home to four at the doorstep.
Our defences still stand at a forward fraction of 0.01 against BARb's 0.23.
Either the gun is never asked for, or it is asked for and arrives too late.

    gun standing when it died  -> the gun is there and loses; a placement or
                                  strength problem
    no gun                     -> the floor never bought one for that spot,
                                  which is the latch: no gun, so the spot
                                  reads unsurvivable, so no gun
"""
import bisect
import collections
import glob
import math
import os
import re
import sys

TOW = re.compile(r"(llt|beamer|hlt|guard|pb|claw|amb|anni)$")
MEX = re.compile(r"^(arm|cor|leg)(mex|moho)")
NEAR = 600.0          # a light tower reaches 430; 600 is "a gun is at this spot"
FWD = 800.0           # beyond this from our start is not the home cluster

rows = collections.Counter()
dist_no, dist_yes = [], []

for T in sys.argv[1:]:
    for M in sorted(glob.glob(os.path.join(T, "matches", "t*"))):
        info = os.path.join(M, "infolog.txt")
        if not os.path.exists(info):
            continue
        script = open(os.path.join(M, "script.txt")).read()
        ap0 = "Apex" in re.search(r"\[AI0\](.*?)\[AI1\]", script, re.S).group(1)
        txt = open(info, encoding="utf-8", errors="replace").read()
        towers, start = collections.defaultdict(list), {}
        for m in re.finditer(r"\[BARAI_POS\] team=(\d) ally=\d frame=(\d+) "
                             r"n=\d+ part=\d+/\d+ (\S*)", txt):
            team = int(m.group(1))
            if (team < 2) != ap0:
                continue
            f = int(m.group(2))
            for e in m.group(3).split(","):
                p = e.split(":")
                if len(p) < 3:
                    continue
                try:
                    x, z = float(p[1]), float(p[2])
                except ValueError:
                    continue
                if TOW.search(p[0]):
                    towers[f].append((x, z))
                if team not in start and MEX.match(p[0]):
                    start[team] = (x, z)      # first structure sample ~= home
        frames = sorted(towers)
        for m in re.finditer(r"\[BARAI_DEATH\] frame=(\d+) team=(\d) "
                             r"unit=(\S+) cost=\d+ x=([-\d.]+) z=([-\d.]+) "
                             r".*?built=(\d) .*?atk=(\S+)", txt):
            team = int(m.group(2))
            if (team < 2) != ap0 or not MEX.match(m.group(3)):
                continue
            if m.group(6) != "1" or m.group(7) == "?":
                continue          # nanoframe, or the moho-upgrade phantom
            hx, hz = start.get(team, (None, None))
            if hx is None:
                continue
            f, x, z = int(m.group(1)), float(m.group(4)), float(m.group(5))
            r = math.hypot(x - hx, z - hz)
            if r < FWD:
                rows["home death"] += 1
                continue
            i = bisect.bisect_right(frames, f) - 1
            if i < 0:
                continue
            near = any(math.hypot(x - tx, z - tz) <= NEAR
                       for tx, tz in towers[frames[i]])
            rows["forward, GUN" if near else "forward, NO GUN"] += 1
            (dist_yes if near else dist_no).append(r)

tot = rows["forward, GUN"] + rows["forward, NO GUN"]
print("our extractors killed by the enemy (moho-upgrade phantoms excluded)")
for k in ("home death", "forward, GUN", "forward, NO GUN"):
    print("   %-18s %4d" % (k, rows[k]))
if tot:
    print()
    print("of the %d that died FORWARD (>%.0f elmo from home):" % (tot, FWD))
    print("   had a gun within %.0f elmo: %d (%.0f%%)"
          % (NEAR, rows["forward, GUN"], 100.0 * rows["forward, GUN"] / tot))
    print("   had NO gun:                %d (%.0f%%)"
          % (rows["forward, NO GUN"], 100.0 * rows["forward, NO GUN"] / tot))
    for nm, v in (("with a gun", dist_yes), ("with none", dist_no)):
        if v:
            v.sort()
            print("   median distance %s: %.0f" % (nm, v[len(v) // 2]))
