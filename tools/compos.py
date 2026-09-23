"""Where the commander spends the game, and where he is when he dies.

    python tools/compos.py <tournament-dirs...>

`apex: com-pos` samples him every 30 s with the leash's own verdict attached
(`far=1` means ComFar said he was outside it). So this can ask the question
that a distance alone cannot: when he dies, does the LEASH think he is home?

  far=1 at death -> the leash saw it and did not stop him
  far=0 at death -> the leash is drawn in the wrong place
"""
import bisect
import collections
import glob
import os
import re
import sys

POS = re.compile(r"\[f=(\d+)\].*?apex: com-pos t=(\d+) at=(-?\d+),(-?\d+) "
                 r"fwd=([\d.-]+) home=(-?\d+) far=(\d)")
DEATH = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d) "
                   r"unit=(?:arm|cor|leg)com\w* cost=\d+ "
                   r"x=([-\d.]+) z=([-\d.]+)")

all_home, all_far, n_samp = [], 0, 0
die_home, die_far, n_die = [], 0, 0
die_fwd = []
by_min = collections.defaultdict(list)

for T in sys.argv[1:]:
    for M in sorted(glob.glob(os.path.join(T, "matches", "t*"))):
        info = os.path.join(M, "infolog.txt")
        if not os.path.exists(info):
            continue
        script = open(os.path.join(M, "script.txt")).read()
        ap0 = "Apex" in re.search(r"\[AI0\](.*?)\[AI1\]", script, re.S).group(1)
        # our commander samples, per team, in frame order
        samp = collections.defaultdict(list)
        for ln in open(info, encoding="utf-8", errors="replace"):
            m = POS.search(ln)
            if m:
                team = int(m.group(2))
                if (team < 2) != ap0:
                    continue
                f, home, far = int(m.group(1)), int(m.group(6)), int(m.group(7))
                if home < 0:
                    continue
                samp[team].append((f, home, far, float(m.group(5))))
                all_home.append(home)
                all_far += far
                n_samp += 1
                by_min[min(f // 1800 // 4 * 4, 24)].append((home, far))
            else:
                d = DEATH.search(ln)
                if not d:
                    continue
                team = int(d.group(2))
                if (team < 2) != ap0:
                    continue
                rows = samp.get(team)
                if not rows:
                    continue
                i = bisect.bisect_right([r[0] for r in rows], int(d.group(1))) - 1
                if i < 0:
                    continue
                n_die += 1
                die_home.append(rows[i][1]); die_fwd.append(rows[i][3])
                die_far += rows[i][2]


def q(v, p):
    v = sorted(v)
    return v[int(p * (len(v) - 1))] if v else 0


if not n_samp:
    print("no com-pos samples -- is the log older than the instrument?")
    raise SystemExit(0)
print("%d commander samples over the arm" % n_samp)
print("  distance from home: median %d  p75 %d  p90 %d"
      % (q(all_home, .5), q(all_home, .75), q(all_home, .9)))
print("  leash says FAR in %.0f%% of samples" % (100.0 * all_far / n_samp))
print()
print("  minute   samples   median home   p90 home   far=1")
for k in sorted(by_min):
    rows = by_min[k]
    h = [r[0] for r in rows]
    print("  %3d-%-3d  %7d   %11d   %8d   %3.0f%%"
          % (k, k + 3, len(rows), q(h, .5), q(h, .9),
             100.0 * sum(r[1] for r in rows) / len(rows)))
if n_die:
    print()
    print("%d commander deaths with a preceding sample" % n_die)
    print("  distance from home at death: median %d  p25 %d  p75 %d"
          % (q(die_home, .5), q(die_home, .25), q(die_home, .75)))
    print("  forward fraction at death: median %.2f  p25 %.2f  p75 %.2f"
          % (q(die_fwd, .5), q(die_fwd, .25), q(die_fwd, .75)))
    print("  the LEASH said he was far: %d (%.0f%%)"
          % (die_far, 100.0 * die_far / n_die))
