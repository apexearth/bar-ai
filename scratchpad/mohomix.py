"""Per-side composition of the extractor and generator fleets, by minute.

ecoside.py lumps armmex+armmoho into one "mexes" column and armadvsol into
"small gens", which hides the two facts that decide late metal: the moho
fraction and the advanced-solar fraction. Same ally resolution as ecoside.py.
"""
import collections
import glob
import os
import re
import sys

WANT = ("armmex", "armmoho", "armsolar", "armwin", "armadvsol", "armfus",
        "armafus", "armgeo", "armmakr", "armmmkr", "armestor",
        "cormex", "cormoho", "corsolar", "corwin", "coradvsol", "corfus",
        "corafus", "corgeo", "cormakr", "cormmkr")
MIN = [4, 8, 12, 16, 20, 24]

acc = collections.defaultdict(lambda: collections.defaultdict(float))
# a census is split over several part= lines, so the sample is the distinct
# (game, team, frame) triple -- counting lines deflates every mean by the
# part count.
seen = collections.defaultdict(set)
games = 0

for T in sys.argv[1:]:
    for M in sorted(glob.glob(os.path.join(T, "**", "script.txt"), recursive=True)):
        d = os.path.dirname(M)
        info = os.path.join(d, "infolog.txt")
        if not os.path.exists(info):
            continue
        script = open(M).read()
        ours = set()
        for m in re.finditer(r"\[AI(\d+)\][\s\S]{0,400}?ShortName=(\w+);"
                             r"[\s\S]{0,400}?Team=(\d+);", script):
            if m.group(2).startswith("Apex"):
                ours.add(int(m.group(3)))
        if not ours:
            continue
        games += 1
        txt = open(info, encoding="utf-8", errors="replace").read()
        for m in re.finditer(r"\[BARAI_POS\] team=(\d) ally=\d frame=(\d+) "
                             r"n=\d+ part=\d+/\d+ (\S*)", txt):
            minute = int(m.group(2)) // 1800
            if minute not in MIN:
                continue
            side = "us" if int(m.group(1)) in ours else "them"
            seen[(side, minute)].add((d, m.group(1), m.group(2)))
            for e in m.group(3).split(","):
                p = e.split(":")
                if len(p) < 2:
                    continue
                if p[0] in WANT:
                    acc[(side, minute)][p[0].replace("cor", "arm")] += 1

cols = ["armmex", "armmoho", "armwin", "armsolar", "armadvsol", "armfus",
        "armafus", "armgeo", "armmakr", "armmmkr"]
print("games=%d   per SIDE (both AIs summed), mean per game" % games)
print("%-4s %-5s " % ("min", "side") + " ".join("%9s" % c[3:] for c in cols))
for minute in MIN:
    for side in ("us", "them"):
        n = len(seen[(side, minute)])
        if not n:
            continue
        # two teams a side: n is team-censuses, so a side-mean divides by n/2
        g = max(1, n // 2)
        print("%-4d %-5s " % (minute, side)
              + " ".join("%9.1f" % (acc[(side, minute)][c] / g) for c in cols))
    print()
