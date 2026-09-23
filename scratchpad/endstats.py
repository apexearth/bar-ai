"""Game-over ledger per side, and the minute the first commander dies.

Answers the questions ecoside.py cannot: where the metal went, what each side
killed and lost, how much came back as reclaim, and when the commanders died.
Ally resolution copied from ecoside.py (S16: teams[].team is the spec index).
"""
import collections
import glob
import os
import re
import statistics
import sys

FIELDS = ("mBuiltReal", "mArmy", "mEco", "mBP", "mDefence", "mFactories",
          "mLostReal", "mLostMobile", "mKillReal", "mKillStatic",
          "mKillMobile", "mReclaim", "mRezSpend", "mex", "t2Mex",
          "spamCost", "commLost", "techFrame")

acc = collections.defaultdict(list)
lens = []

for T in sys.argv[1:]:
    for M in sorted(glob.glob(os.path.join(T, "**", "script.txt"), recursive=True)):
        d = os.path.dirname(M)
        info = os.path.join(d, "infolog.txt")
        if not os.path.exists(info):
            continue
        ours = set()
        for m in re.finditer(r"\[AI(\d+)\][\s\S]{0,400}?ShortName=(\w+);"
                             r"[\s\S]{0,400}?Team=(\d+);", open(M).read()):
            if m.group(2).startswith("Apex"):
                ours.add(int(m.group(3)))
        if not ours:
            continue
        txt = open(info, encoding="utf-8", errors="replace").read()
        per = collections.defaultdict(lambda: collections.defaultdict(float))
        last = 0
        for m in re.finditer(r"\[BARAI_STATS\] team=(\d+) ally=\d+ "
                             r"reason=(periodic|gameover) frame=(\d+) [^\n]*", txt):
            kv = dict(re.findall(r"(\w+)=(-?[\d.]+)", m.group(0)))
            team = int(m.group(1))
            side = "us" if team in ours else "them"
            last = max(last, int(m.group(3)))
            for f in FIELDS:
                if f in kv:
                    per[(side, team)][f] = float(kv[f])
        if not per:
            continue
        lens.append(last / 1800.0)
        agg = collections.defaultdict(lambda: collections.defaultdict(float))
        comdeath = collections.defaultdict(list)
        for (side, team), v in per.items():
            for f in FIELDS:
                agg[side][f] += v.get(f, 0.0)
            cl = v.get("commLost", -1)
            comdeath[side].append(cl)
        for side in ("us", "them"):
            for f in FIELDS:
                acc[(side, f)].append(agg[side][f])
            # commLost is a frame, -1 when it never died
            dead = [c for c in comdeath[side] if c and c > 0]
            acc[(side, "comDeaths")].append(float(len(dead)))
            acc[(side, "comFirstMin")].append(
                min(dead) / 1800.0 if dead else float("nan"))

n = len(lens)
print("games=%d  median length %.1f min" % (n, statistics.median(lens)))
print("%-14s %10s %10s %8s" % ("field", "us", "them", "us/them"))
for f in list(FIELDS) + ["comDeaths", "comFirstMin"]:
    a = [x for x in acc[("us", f)] if x == x]
    b = [x for x in acc[("them", f)] if x == x]
    if not a or not b:
        continue
    ma, mb = statistics.mean(a), statistics.mean(b)
    r = ("%8.2f" % (ma / mb)) if mb else "       -"
    print("%-14s %10.1f %10.1f %s" % (f, ma, mb, r))
