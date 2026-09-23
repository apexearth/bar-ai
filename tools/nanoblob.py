"""Are our nano turrets a few rings, or one blob? And what were they fed by?

    python tools/nanoblob.py <match-or-tournament-dir> [...]

apexearth 2026-09-22: "Does the act of building a nano turret incentivize us
to make more nano turrets in an area? Sometimes we make huge nano blobs for
little reason." The want's own law subtracts the lathe already standing at a
site, so each turret should make the next one worth LESS. This measures what
actually went up: how many, how tightly grouped, and what stood at the centre
of each group.
"""
import collections
import glob
import math
import os
import re
import sys

NANO = ("armnanotc", "cornanotc", "legnanotc",
        "armnanotcplat", "cornanotcplat", "legnanotcplat")
ANCHOR = re.compile(r"(lab|vp|ap|hp|gant|shltx|sy)$")
# What a group RINGS decides what to do about it, and the four cases pull in
# opposite directions -- a bound that is right at a plant is wrong at a gun
# (apexearth 2026-09-22: where the turrets are massed, build the fortress).
GUN = re.compile(r"(anni|amb|guard|llt|hlt|pb|claw|brtha|bertha|amd|"
                 r"gate|shield|flak|mercury|screamer|cir|rl|targ)$")
BIGECO = re.compile(r"(fus|afus|mmkr|mmkrb|geo|moho|ageo)$")
R = 250.0


def classify(inside):
    """Which of the four cases is this group -- plant, gun, big eco, nothing."""
    kinds = []
    if any(ANCHOR.search(n) for n in inside):
        kinds.append("PLANT")
    if any(GUN.search(n) for n in inside):
        kinds.append("GUN")
    if any(BIGECO.search(n) for n in inside):
        kinds.append("ECO")
    return "+".join(kinds) if kinds else "NOTHING"

for T in sys.argv[1:]:
    logs = sorted(glob.glob(os.path.join(T, "**", "infolog.txt"), recursive=True))
    for f in logs:
        text = open(f, encoding="utf-8", errors="replace").read()
        pos = collections.defaultdict(list)
        # last full position sample per team
        for m in re.finditer(r"\[BARAI_POS\] team=(\d) ally=\d frame=(\d+) "
                             r"n=\d+ part=\d+/\d+ (\S*)", text):
            for e in m.group(3).split(","):
                p = e.split(":")
                if len(p) >= 3:
                    try:
                        pos[(m.group(1), int(m.group(2)))].append(
                            (p[0], float(p[1]), float(p[2])))
                    except ValueError:
                        pass
        if not pos:
            continue
        team, frame = max(pos, key=lambda k: k[1])
        units = pos[(team, frame)]
        nanos = [(x, z) for n, x, z in units if n in NANO]
        anchors = [(n, x, z) for n, x, z in units if ANCHOR.search(n)]
        if not nanos:
            continue
        # single-link grouping at R
        groups = []
        for x, z in nanos:
            hit = None
            for g in groups:
                if any(math.hypot(x - a, z - b) <= R for a, b in g):
                    hit = g
                    break
            if hit is None:
                groups.append([(x, z)])
            else:
                hit.append((x, z))
        groups.sort(key=len, reverse=True)
        print("%s  team %s at %.0f min: %d nano turrets in %d group(s)"
              % (os.path.basename(os.path.dirname(f)), team, frame / 1800.0,
                 len(nanos), len(groups)))
        for g in groups[:6]:
            cx = sum(p[0] for p in g) / len(g)
            cz = sum(p[1] for p in g) / len(g)
            rad = max(math.hypot(cx - a, cz - b) for a, b in g)
            near = sorted(((math.hypot(cx - x, cz - z), n) for n, x, z in anchors))
            what = "%s @%.0f" % (near[0][1], near[0][0]) if near else "nothing"
            # The turret's own reach past the group's rim: what it can serve.
            inside = collections.Counter(
                n for n, x, z in units
                if n not in NANO and math.hypot(cx - x, cz - z) <= rad + 400.0)
            print("    group of %-3d centred %5.0f,%-5.0f   %-9s nearest plant: %s"
                  % (len(g), cx, cz, classify(inside), what))
            print("        rings: %s" % ", ".join(
                "%s x%d" % (k, v) for k, v in inside.most_common(10)))
