"""Follow ONE constructor for a whole game and print every job it took.

    python tools/onehand.py <match-dir> [--unit armck] [--nth 1]

apexearth 2026-09-22: "If I was to pick a constructor, like the first
constructor that comes out of a lab and just analyze what that constructor
does compared to what the other teams does, that would probably be very
telling... it's almost like he can't make up his mind."

Every `apex: decide` line names the hand by id, so one hand's whole working
life reads back in order: what it was elected to, what beat what, and -- the
part his question is about -- how often the answer CHANGED. A re-election to
the same job is the hand carrying on; a re-election to a different one is the
hand walking away from work it had already started.

BARb logs nothing, so there is no opposing hand to line this up against. What
this measures is ours against itself.
"""
import collections
import os
import re
import sys

args = [a for a in sys.argv[1:] if not a.startswith("--")]
unit_pat = "armck|armcv|armch|corck|corcv|legck"
nth = 1
for i, a in enumerate(sys.argv):
    if a == "--unit":
        unit_pat = sys.argv[i + 1]
    elif a == "--nth":
        nth = int(sys.argv[i + 1])

DEC = re.compile(r"\[f=(\d+)\].*?apex: decide t=\d+ (\w+) #(\d+) -> "
                 r"(\S+?) v=[\d.eE+-]+ .*?why=(\w+)")

for d in args:
    path = os.path.join(d, "infolog.txt")
    if not os.path.exists(path):
        continue
    rows = collections.defaultdict(list)
    order = []
    for ln in open(path, encoding="utf-8", errors="replace"):
        m = DEC.search(ln)
        if not m or not re.fullmatch(unit_pat, m.group(2)):
            continue
        uid = m.group(3)
        if uid not in rows:
            order.append(uid)
        rows[uid].append((int(m.group(1)) / 1800.0, m.group(4), m.group(5)))
    if len(order) < nth:
        print("%s: no %s found" % (d, unit_pat))
        continue
    if "--all" in sys.argv:
        tot = ch = hands = 0
        per = collections.Counter()
        for uid2, js in rows.items():
            if len(js) < 2:
                continue
            hands += 1
            tot += len(js)
            prev2 = None
            for _t, what2, _why in js:
                if prev2 is not None and what2 != prev2:
                    ch += 1
                    per[what2.split(":")[0]] += 1
                prev2 = what2
        print("%-28s %4d hands  %5d elections  %5d job changes (%.0f%%)"
              % (os.path.basename(os.path.normpath(d)), hands, tot, ch,
                 100.0 * ch / max(tot, 1)))
        print("   changed TO: %s" % ", ".join(
            "%s %d" % (k, v) for k, v in per.most_common(6)))
        continue
    uid = order[nth - 1]
    jobs = rows[uid]
    print("== %s  hand #%s  (%d elections over %.1f min)"
          % (os.path.basename(d), uid, len(jobs), jobs[-1][0] - jobs[0][0]))
    changes = 0
    prev = None
    for t, what, why in jobs:
        mark = " "
        if prev is not None and what != prev:
            changes += 1
            mark = "*"          # walked away from what it was doing
        print("  %6.1fm %s %-34s why=%s" % (t, mark, what, why))
        prev = what
    print("  -- %d of %d elections CHANGED the job (%.0f%%)"
          % (changes, len(jobs), 100.0 * changes / max(len(jobs), 1)))
