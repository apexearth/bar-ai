"""Where the metal actually went, and how much of the army bill was replacement.

    python tools/sharesrc.py <tournament-dirs...>

The budget controller measures SPEND, so an army that dies is charged again
every time it is rebuilt. If mLostMobile is a large fraction of mArmy, the army
row is over target because the army is DYING, not because we chose to buy more
of it -- and the fix is the fighting, not the production rate.

Cumulative fields, read at each side's last sample. Our side only.
"""
import collections
import glob
import os
import re
import sys

STAT = re.compile(r"BARAI_STATS\] team=(\d+) ")
CATS = ["mArmy", "mEco", "mDefence", "mDefAA", "mBP", "mOther",
        "mLostMobile", "mKillMobile", "mSpend"]
FIELD = {c: re.compile(r"\b%s=(\d+)" % c) for c in CATS}

for T in [a for a in sys.argv[1:] if not a.startswith("--")]:
    tot = collections.Counter()
    games = 0
    for M in sorted(glob.glob(os.path.join(T, "matches", "t*"))):
        info = os.path.join(M, "infolog.txt")
        if not os.path.exists(info):
            continue
        script = open(os.path.join(M, "script.txt")).read()
        ap0 = "Apex" in re.search(r"\[AI0\](.*?)\[AI1\]", script, re.S).group(1)
        games += 1
        last = {}
        for ln in open(info, encoding="utf-8", errors="replace"):
            m = STAT.search(ln)
            if not m:
                continue
            team = int(m.group(1))
            if ((team < 2) != ap0) != ("--enemy" in sys.argv):
                continue
            row = {}
            for c in CATS:
                f = FIELD[c].search(ln)
                if f:
                    row[c] = int(f.group(1))
            if row:
                last[team] = row
        for row in last.values():
            for c, v in row.items():
                tot[c] += v
    if not games:
        continue
    base = sum(tot[c] for c in ("mArmy", "mEco", "mDefence", "mDefAA", "mBP"))
    print("== %s (%d games)" % (os.path.basename(os.path.normpath(T)), games))
    if base <= 0:
        print("   no category totals")
        continue
    for c in ("mArmy", "mEco", "mDefence", "mDefAA", "mBP"):
        print("   %-9s %10d   %5.1f%% of built metal" % (c, tot[c], 100.0 * tot[c] / base))
    print("   %-9s %10d   mobile metal LOST" % ("mLostMobile", tot["mLostMobile"]))
    print("   %-9s %10d   mobile metal KILLED" % ("mKillMobile", tot["mKillMobile"]))
    if tot["mArmy"] > 0:
        print()
        print("   army lost / army built = %.2f   <- this much of the army bill was replacement"
              % (tot["mLostMobile"] / tot["mArmy"]))
        surv = tot["mArmy"] - tot["mLostMobile"]
        if surv > 0:
            print("   army that SURVIVED = %d (%.1f%% of built metal)"
                  % (surv, 100.0 * surv / base))
