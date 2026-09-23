"""Per turret, not per blob: is this lathe in reach of anything it can serve?

    python tools/nanoreach.py <match-or-tournament-dir> [...]

apexearth 2026-09-22: "Still a ton of build power being created and often
outside the range of anything that it can be useful for." nanoblob.py answers
that per GROUP, at a 250-elmo grouping radius, so one plant redeems eighteen
turrets standing 3,000 elmo away from it. This asks it of each turret at its
OWN build distance: a plant, a big eco building, or a gun inside the radius the
turret can actually lathe. Anything else is build power serving nothing.
"""
import collections
import glob
import math
import os
import re
import sys

# buildDistance from the defs; the plat/T2 variants reach further.
REACH = {"armnanotc": 400.0, "cornanotc": 400.0, "legnanotc": 400.0,
         "armnanotcplat": 400.0, "cornanotcplat": 400.0, "legnanotcplat": 400.0,
         "armnanotct2": 500.0, "cornanotct2": 500.0, "legnanotct2": 500.0,
         "armnanotc2plat": 500.0, "cornanotc2plat": 500.0}
PLANT = re.compile(r"(lab|vp|ap|hp|gant|shltx|sy|plat)$")
GUN = re.compile(r"(anni|amb|guard|llt|hlt|pb|claw|brtha|bertha|amd|"
                 r"gate|shield|flak|mercury|screamer|cir|rl|targ|ferret|"
                 r"beamer|pitbull|jamt|rad)$")
BIGECO = re.compile(r"(fus|afus|mmkr|geo|moho)$")


def scan(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    pos = collections.defaultdict(list)
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
        return None
    team, frame = max(pos, key=lambda k: k[1])
    return team, frame, pos[(team, frame)]


def main(dirs):
    tot = collections.Counter()
    for d in dirs:
        for f in sorted(glob.glob(os.path.join(d, "**", "infolog.txt"),
                                  recursive=True)):
            got = scan(f)
            if got is None:
                continue
            team, frame, units = got
            nanos = [(n, x, z) for n, x, z in units if n in REACH]
            if not nanos:
                continue
            others = [(n, x, z) for n, x, z in units if n not in REACH]
            per = collections.Counter()
            for n, x, z in nanos:
                r = REACH[n]
                served = set()
                for on, ox, oz in others:
                    if math.hypot(x - ox, z - oz) > r:
                        continue
                    if PLANT.search(on):
                        served.add("PLANT")
                    if BIGECO.search(on):
                        served.add("ECO")
                    if GUN.search(on):
                        served.add("GUN")
                per["+".join(sorted(served)) or "NOTHING"] += 1
            tot.update(per)
            nothing = per["NOTHING"]
            print("%-58s t%s %4.0f min: %3d turrets, %3d serve NOTHING (%.0f%%)"
                  % (os.path.basename(os.path.dirname(f))[:58], team,
                     frame / 1800.0, len(nanos), nothing,
                     100.0 * nothing / len(nanos)))
    n = sum(tot.values())
    if n:
        print("\nTOTAL %d turrets" % n)
        for k, v in tot.most_common():
            print("  %-16s %5d  %5.1f%%  %6d metal" % (k, v, 100.0 * v / n,
                                                       v * 210))


if __name__ == "__main__":
    main(sys.argv[1:])
