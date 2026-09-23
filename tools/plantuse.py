"""Every plant we built, and what it actually produced.

    python tools/plantuse.py <tournament-or-match-dir> [...]

apexearth 2026-09-22: "We made an 'Experimental Aircraft Plant' and then did
nothing with it. These plants should only be built if we actually desire to
create something out of it. If we don't genuinely want one of the units it can
produce, then we should not be making it."

A plant is capacity, and capacity nobody uses is metal thrown away. This
counts, per plant type: how many we finished, the metal that cost, and how
many units came out of that type over the rest of the game.
"""
import collections
import glob
import os
import re
import sys

PLANT = re.compile(r"(lab|vp|ap|hp|sy|gant|shltx)$")

for T in sys.argv[1:]:
    built = collections.Counter()
    cost = collections.Counter()
    made = collections.Counter()
    firstAt = {}
    games = 0
    for M in sorted(glob.glob(os.path.join(T, "**", "script.txt"), recursive=True)):
        d = os.path.dirname(M)
        info = os.path.join(d, "infolog.txt")
        if not os.path.exists(info):
            continue
        script = open(M).read()
        ours = {int(m.group(3)) for m in re.finditer(
            r"\[AI(\d+)\][\s\S]{0,400}?ShortName=(\w+);[\s\S]{0,400}?Team=(\d+);", script)
            if m.group(2).startswith("Apex")}
        if not ours:
            continue
        games += 1
        txt = open(info, encoding="utf-8", errors="replace").read()
        for m in re.finditer(r"\[BARAI_BUILD\] team=(\d+) ally=\d+ frame=\d+ "
                             r"min=([\d.]+) unit=(\w+) cost=(\d+)", txt):
            if int(m.group(1)) not in ours:
                continue
            u, c, t = m.group(3), int(m.group(4)), float(m.group(2))
            if PLANT.search(u):
                built[u] += 1
                cost[u] += c
                firstAt.setdefault(u, []).append(t)
        # what came out: the factory census names the plant each unit came from
        for m in re.finditer(r"\[BARAI_PROD\] team=(\d+) [^\n]*?fac=(\w+)", txt):
            if int(m.group(1)) in ours:
                made[m.group(2)] += 1
    print("== %s  (%d games)" % (os.path.basename(os.path.normpath(T)), games))
    print("  %-12s %6s %9s %9s %s" % ("plant", "built", "metal", "made", "first"))
    for u, n in built.most_common(12):
        t = firstAt.get(u, [])
        print("  %-12s %6.2f %9.0f %9.2f   %s"
              % (u, n / max(games, 1), cost[u] / max(games, 1),
                 made.get(u, 0) / max(games, 1),
                 ("%.0f min" % (sum(t) / len(t))) if t else "-"))
    if not made:
        print("  (no BARAI_PROD lines: output per plant is not logged -- "
              "see the note in this file)")
