"""Where the metal actually COMES FROM, per side, over the game.

    python tools/ecoside.py <tournament-or-match-dir> [...]

apexearth 2026-09-22: "Late in the game you could have like a thousand metal
income. There's a limited number of mex spots in the game. So where does this
thousand metal come from? It comes entirely from your energy generation and
conversion. That's where it all comes from."

So extractor COUNT is the opening, not the economy, and a per-team energy
table is not the answer either: in a 2v2 both of our AIs are our side, and
`teams[].team` in result.json is the SPEC index, not the engine team (S16) --
reading it that way labels our own second AI as the enemy. This sums by ALLY,
resolving which ally is ours from the start script, and reports the two
engines that make late metal: generation and conversion.
"""
import collections
import glob
import os
import re
import sys

MEX = ("armmex", "armmoho", "cormex", "cormoho")
CONV = ("armmakr", "armmmkr", "cormakr", "cormmkr", "legmakr", "legadvconv",
        "armmmkrt3", "cormmkrt3", "legmmkrt3")
GEN = ("armsolar", "armwin", "armadvsol", "armfus", "armafus", "armgeo",
       "corsolar", "corwin", "coradvsol", "corfus", "corafus", "corgeo",
       "armafust3", "corafust3")
MIN = [4, 8, 12, 16, 20]

acc = collections.defaultdict(lambda: collections.defaultdict(float))
seen = collections.defaultdict(lambda: collections.defaultdict(int))

for T in sys.argv[1:]:
    for M in sorted(glob.glob(os.path.join(T, "**", "script.txt"), recursive=True)):
        d = os.path.dirname(M)
        info = os.path.join(d, "infolog.txt")
        if not os.path.exists(info):
            continue
        script = open(M).read()
        ours = set()
        # NOT [^\[] as a guard: the block's own Name=[LANE-WINRATE] holds a
        # literal bracket, so that form matches nothing at all.
        for m in re.finditer(r"\[AI(\d+)\][\s\S]{0,400}?ShortName=(\w+);"
                             r"[\s\S]{0,400}?Team=(\d+);", script):
            if m.group(2).startswith("Apex"):
                ours.add(int(m.group(3)))
        if not ours:
            continue
        txt = open(info, encoding="utf-8", errors="replace").read()
        # income by team, sampled from the stats gadget
        for m in re.finditer(r"\[BARAI_STATS\] team=(\d+) ally=\d+ reason=periodic "
                             r"frame=(\d+) [^\n]*", txt):
            minute = int(m.group(2)) // 1800
            if minute not in MIN:
                continue
            kv = dict(re.findall(r"(\w+)=(-?[\d.]+)", m.group(0)))
            side = "us" if int(m.group(1)) in ours else "them"
            acc[(side, minute)]["mInc"] += float(kv.get("mInc", 0))
            acc[(side, minute)]["mEco"] += float(kv.get("mEco", 0))
            seen[(side, minute)]["n"] += 1
        # standing structures
        for m in re.finditer(r"\[BARAI_POS\] team=(\d) ally=\d frame=(\d+) "
                             r"n=\d+ part=\d+/\d+ (\S*)", txt):
            minute = int(m.group(2)) // 1800
            if minute not in MIN:
                continue
            side = "us" if int(m.group(1)) in ours else "them"
            for e in m.group(3).split(","):
                p = e.split(":")
                if len(p) < 2:
                    continue
                if p[0] in MEX:
                    acc[(side, minute)]["mex"] += 1
                elif p[0] in CONV:
                    acc[(side, minute)]["conv"] += 1
                elif p[0] in GEN:
                    acc[(side, minute)]["gen"] += 1
                    # Count is not capacity: forty solars are not four fusions.
                    acc[(side, minute)]["genBig" if re.search(
                        r"(fus|afus|geo)$", p[0]) else "genSmall"] += 1

games = max(1, seen[("us", MIN[0])]["n"] // 2) if seen else 1
print("per SIDE (both AIs summed), averaged over games")
print("%-5s %-5s %8s %8s %8s %8s %8s %8s" %
      ("min", "side", "mInc", "mEco", "mexes", "convs", "gensSm", "gensBig"))
for minute in MIN:
    for side in ("us", "them"):
        n = seen[(side, minute)]["n"]
        if not n:
            continue
        g = max(n / 2.0, 1.0)      # two teams a side per game
        a = acc[(side, minute)]
        print("%-5d %-5s %8.0f %8.0f %8.1f %8.1f %8.1f %8.1f"
              % (minute, side, a["mInc"] / g, a["mEco"] / g,
                 a["mex"] / g, a["conv"] / g,
                 a["genSmall"] / g, a["genBig"] / g))
