#!/usr/bin/env python3
"""Extractor losses to raids, us against BARb, and whether the raider paid.

    python tools/mexraid.py <tournament|match> [...] [--to 12] [--all]

Per side, per game: extractors standing at minutes 5/7/9/11 (legmext15 counts:
it replaces a legmex on its spot), finished ones an enemy killed and unfinished
ones killed, and for every enemy unit that killed one of a side's extractors
whether it was still alive at the end and how many more it took. Last, the
summed `apex: raid-answer-stat` of our seats (raidanswer.as) and the intercept
counters of their `apex: hunt-stat` (nnhunt.as).
Games with `apex: nn-explore t=` are skipped unless --all.
"""
import collections
import glob
import os
import re
import sys

BUILD = re.compile(r"\[BARAI_BUILD\] team=(\d+) ally=\d+ frame=(\d+) min=\S+ unit=(\S+) cost=\d+ x=\d+ z=\d+ uid=(\d+)")
DEATH = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\S+) .*?built=(\d) mob=\d atkteam=(-?\d+) atk=\S* .*?uid=(\d+) atkid=(-?\d+)")
OURS = re.compile(r"apex: (?:mexguns|hold|posts) t=(\d+)")
STAT = re.compile(r"apex: raid-answer-stat t=(\d+) (.*)")
HSTAT = re.compile(r"apex: hunt-stat t=(\d+) .*?(ic=\d+ .*)")
MEX = re.compile(r"(mex|moho|mme)(t\d+)?\d*$")
FPM = 1800


def matches(args):
    for a in args:
        if os.path.isfile(os.path.join(a, "infolog.txt")):
            yield a
        else:
            for m in sorted(glob.glob(os.path.join(a, "matches", "*"))):
                if os.path.isfile(os.path.join(m, "infolog.txt")):
                    yield m


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    to = 12
    if "--to" in sys.argv:
        to = int(sys.argv[sys.argv.index("--to") + 1])
        args = [a for a in args if a != str(to)]
    end = to * FPM
    games = 0
    stand = {s: collections.defaultdict(int) for s in ("us", "barb")}
    c = {s: collections.Counter() for s in ("us", "barb")}
    ans = collections.Counter()
    icp = collections.Counter()
    for m in matches(args):
        txt = open(os.path.join(m, "infolog.txt"), errors="replace").read()
        if ("apex: nn-explore t=" in txt) and ("--all" not in sys.argv):
            continue
        ours = {int(x) for x in OURS.findall(txt)}
        if not ours:
            continue
        games += 1
        side = lambda t: "us" if t in ours else "barb"
        born = [(int(b[1]), int(b[0]), b[3]) for b in BUILD.findall(txt) if MEX.search(b[2])]
        deaths = DEATH.findall(txt)
        died = {d[5]: int(d[0]) for d in deaths}
        for mn in (5, 7, 9, 11):
            if mn > to:
                continue
            for f, t, uid in born:
                if f <= mn * FPM and not (uid in died and died[uid] <= mn * FPM):
                    stand[side(t)][mn] += 1
        killer = collections.defaultdict(int)
        for f, t, unit, built, at, uid, aid in deaths:
            f, t, at = int(f), int(t), int(at)
            if f > end or at < 0 or at == t or not MEX.search(unit):
                continue
            s = side(t)
            c[s]["lost" if built == "1" else "unfinished"] += 1
            if aid != "-1":
                killer[(s, aid)] += 1
        for (s, aid), n in killer.items():
            c[s]["killers"] += 1
            c[s]["followon"] += n - 1
            if aid not in died:
                c[s]["killer_lived"] += 1
        last = {}
        for t, rest in STAT.findall(txt):
            last[t] = rest
        for rest in last.values():
            for k, v in re.findall(r"(\w+)=(\d+)", rest):
                ans[k] += int(v)
        last = {}
        for t, rest in HSTAT.findall(txt):
            last[t] = rest
        for rest in last.values():
            for k, v in re.findall(r"(\w+)=(\d+)", rest):
                icp[k] += int(v)
    if not games:
        print("no games")
        return
    print(f"games={games} to minute {to}")
    for s in ("us", "barb"):
        st = " ".join(f"m{mn}={stand[s][mn] / games:.1f}" for mn in sorted(stand[s]))
        k = c[s]
        print(f"{s:4}  standing {st} | lost {k['lost'] / games:.2f}/g unfinished {k['unfinished'] / games:.2f}/g"
              f" | killers {k['killers']} lived {k['killer_lived']} ({100 * k['killer_lived'] / max(1, k['killers']):.0f}%)"
              f" follow-on kills {k['followon']}")
    for mn in sorted(stand["us"]):
        print(f"  mex edge m{mn}: {stand['us'][mn] / max(1, stand['barb'][mn]):.2f}")
    if ans:
        print("raid-answer (our seats, summed):", " ".join(f"{k}={v}" for k, v in ans.items()))
    else:
        print("raid-answer: no apex: raid-answer-stat lines (not deployed in these games)")
    if icp:
        print("intercept (our seats, summed):", " ".join(f"{k}={v}" for k, v in icp.items()))


if __name__ == "__main__":
    main()
