"""Build tasks we START and then ABANDON, per def, over an arm.

    python tools/aborts.py <tournament-dirs...>

`apex: task-gone` reports every builder task that ended, as done= or abort=.
An abort is a walk already paid for and a build never had. A def with a high
abort share is one the AI keeps changing its mind about -- apexearth, 2026-09-22:
"he walks all over the damn place... it's almost like he can't make up his mind."
"""
import collections
import glob
import os
import re
import sys

LINE = re.compile(r"apex: task-gone t=(\d+) \|(.*)")
PAIR = re.compile(r"(\w+) done=(\d+) abort=(\d+)")

done = collections.Counter()
abort = collections.Counter()
games = 0

for T in sys.argv[1:]:
    for M in sorted(glob.glob(os.path.join(T, "matches", "t*"))):
        info = os.path.join(M, "infolog.txt")
        if not os.path.exists(info):
            continue
        script = open(os.path.join(M, "script.txt")).read()
        ap0 = "Apex" in re.search(r"\[AI0\](.*?)\[AI1\]", script, re.S).group(1)
        games += 1
        # keep only the LAST line per team: the counters are cumulative
        last = {}
        for ln in open(info, encoding="utf-8", errors="replace"):
            m = LINE.search(ln)
            if not m:
                continue
            team = int(m.group(1))
            if (team < 2) != ap0:
                continue
            last[team] = m.group(2)
        for body in last.values():
            for d, dn, ab in PAIR.findall(body):
                done[d] += int(dn)
                abort[d] += int(ab)

if not games:
    print("no task-gone lines")
    raise SystemExit(0)
rows = [(d, done[d], abort[d]) for d in set(done) | set(abort)]
rows = [r for r in rows if r[1] + r[2] >= 20]
rows.sort(key=lambda r: -(r[2]))
print("%d games. Builder tasks that ENDED, per def (>=20 endings):" % games)
print("  %-14s %7s %7s %7s   %s" % ("def", "done", "abort", "total", "abort share"))
tot_d = tot_a = 0
for d, dn, ab in rows[:16]:
    tot_d += dn
    tot_a += ab
    print("  %-14s %7d %7d %7d   %3.0f%%"
          % (d, dn, ab, dn + ab, 100.0 * ab / max(dn + ab, 1)))
alld = sum(done.values())
alla = sum(abort.values())
print()
print("  ALL DEFS      %7d %7d %7d   %3.0f%%"
      % (alld, alla, alld + alla, 100.0 * alla / max(alld + alla, 1)))
print("  per game: %.1f finished, %.1f abandoned" % (alld / games, alla / games))
