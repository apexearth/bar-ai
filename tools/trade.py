"""Metal traded per side: what our army kills against what it costs us.

    python tools/trade.py <tournament-dirs...>

Win rate cannot resolve a change at a 12.5% base rate, but the trade ratio
can: it is a metal quantity summed over every fight in every game. BARb trades
at ~1.6 and we trade at ~0.4 in this regime, and that gap is larger than any
economic gap measured.

mKillMobile / mLostMobile, cumulative, read at each side's last sample.
"""
import collections
import glob
import os
import re
import sys

STAT = re.compile(r"BARAI_STATS\] team=(\d+) ally=\d+ reason=\w+ frame=(\d+) ")
KM = re.compile(r"mKillMobile=(\d+)")
LM = re.compile(r"mLostMobile=(\d+)")
KS = re.compile(r"mKillStatic=(\d+)")

for T in sys.argv[1:]:
    side = {True: collections.Counter(), False: collections.Counter()}
    last = {}
    games = 0
    for M in sorted(glob.glob(os.path.join(T, "matches", "t*"))):
        info = os.path.join(M, "infolog.txt")
        if not os.path.exists(info):
            continue
        script = open(os.path.join(M, "script.txt")).read()
        ap0 = "Apex" in re.search(r"\[AI0\](.*?)\[AI1\]", script, re.S).group(1)
        games += 1
        last.clear()
        for ln in open(info, encoding="utf-8", errors="replace"):
            m = STAT.search(ln)
            if not m:
                continue
            km, lm, ks = KM.search(ln), LM.search(ln), KS.search(ln)
            if not (km and lm):
                continue
            last[int(m.group(1))] = (int(km.group(1)), int(lm.group(1)),
                                     int(ks.group(1)) if ks else 0)
        for team, (k, l, s) in last.items():
            ours = (team < 2) == ap0
            side[ours]["kill"] += k
            side[ours]["lost"] += l
            side[ours]["killStatic"] += s
    if not games:
        continue
    print("== %s (%d games)" % (os.path.basename(os.path.normpath(T)), games))
    for ours in (True, False):
        c = side[ours]
        r = c["kill"] / c["lost"] if c["lost"] else 0.0
        print("   %-5s mobile killed %8d   mobile lost %8d   TRADE %.2f   static killed %7d"
              % ("us" if ours else "them", c["kill"], c["lost"], r, c["killStatic"]))
