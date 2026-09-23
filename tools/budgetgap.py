"""Holdings against target, per category, and whether the corrector is railed.

apexearth, 2026-09-23: "our target would be like 0.35 on economy and we would
only be at 0.12. I don't think we ever managed to balance that out."

`apex: budget` prints held/target per category and the multiplier that is
supposed to close the gap. If a category sits far from its target WHILE its
multiplier is pinned at the clamp, the corrector is saturated: it is already
asking for everything it is allowed to ask for and the gap is decided
somewhere else.
"""
import collections
import glob
import os
import re
import sys

CATS = ["army", "def", "aa", "eco", "bp"]
LINE = re.compile(r"\[f=(\d+)\].*?apex: budget "
                  r"army=([\d.]+)/([\d.]+) def=([\d.]+)/([\d.]+) "
                  r"aa=([\d.]+)/([\d.]+) eco=([\d.]+)/([\d.]+) "
                  r"bp=([\d.]+)/([\d.]+) mult=([\d./]+)")

held = collections.defaultdict(list)
targ = collections.defaultdict(list)
mult = collections.defaultdict(list)
bymin = collections.defaultdict(lambda: collections.defaultdict(list))

for T in sys.argv[1:]:
    for M in sorted(glob.glob(os.path.join(T, "matches", "t*"))):
        info = os.path.join(M, "infolog.txt")
        if not os.path.exists(info):
            continue
        script = open(os.path.join(M, "script.txt")).read()
        ap0 = "Apex" in re.search(r"\[AI0\](.*?)\[AI1\]", script, re.S).group(1)
        # budget lines are ours only when the emitting team is ours; the line
        # carries no team, so only read logs where our AI is the one logging
        if not ap0:
            pass
        for ln in open(info, encoding="utf-8", errors="replace"):
            m = LINE.search(ln)
            if not m:
                continue
            b = min(int(m.group(1)) // 1800 // 4 * 4, 20)
            ms = m.group(12).split("/")
            for i, c in enumerate(CATS):
                h, t = float(m.group(2 + i * 2)), float(m.group(3 + i * 2))
                held[c].append(h)
                targ[c].append(t)
                bymin[b][c].append((h, t))
                if i < len(ms):
                    try:
                        mult[c].append(float(ms[i]))
                    except ValueError:
                        pass


def mean(v):
    return sum(v) / len(v) if v else 0.0


if not held["def"]:
    print("no apex: budget lines")
    raise SystemExit(0)
n = len(held["def"])
print("%d budget samples" % n)
print()
print("  cat    held   target    gap    mult   at clamp(2.0)")
for c in CATS:
    ms = mult[c]
    rail = 100.0 * sum(1 for x in ms if x >= 1.99) / len(ms) if ms else 0.0
    print("  %-5s  %.3f   %.3f   %+.3f   %.2f      %3.0f%%"
          % (c, mean(held[c]), mean(targ[c]),
             mean(held[c]) - mean(targ[c]), mean(ms), rail))
print()
print("  minute  " + "  ".join("%-13s" % c for c in CATS))
for b in sorted(bymin):
    cells = []
    for c in CATS:
        v = bymin[b][c]
        cells.append("%.2f/%.2f" % (mean([x[0] for x in v]),
                                    mean([x[1] for x in v])))
    print("  %3d-%-3d " % (b, b + 3) + "  ".join("%-13s" % x for x in cells))
