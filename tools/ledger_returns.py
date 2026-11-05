"""What each kind of asset returned over its life (todo/learn-from-each-decision.md), from [BARAI_LIFE] lines.

    python tools/ledger_returns.py <tournament-or-match dirs...>

Our seats only. Metal of damage = damage x the victim's metal / its max health (dev_combat_log.lua). Energy counts at
60 per metal (the conversion rate). Per class:
  towers      metal of damage dealt per metal spent; the share that dealt nothing
  economy     metal + energy/60 made per metal spent; the share that paid for itself
  factories   army metal they produced, and the metal of damage that army then dealt, per metal of factory
  builders    metal of build power into mobile units vs buildings; the share that built nothing
  army        metal of damage dealt and taken per metal, by unit
"""
import glob
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ledger  # noqa: E402

E_PER_M = 60.0
COST = re.compile(r"\[BARAI_(?:BUILD|PROD|DEATH)\].*?unit=(\S+) cost=([\d.]+)")
PROD = re.compile(r"\[BARAI_PROD\] team=(\d+) .*?unit=(\S+) cost=([\d.]+) fac=(\S+) uid=(\d+) facid=(\d+)")
TOWER = re.compile(r"(llt|hllt|hlt|lht|mg|guard|pun|toast|doom|vipe|maw|bastion|cluster|lupara|tl|dl|rl|madsam|flak|erad|cir)$")
ECO = re.compile(r"(mex|moho|solar|advsol|win|fus|afus|geo|tide|makr|mmkr)$")
PLANT = re.compile(r"(lab|vp|ap|hp|sy|gant|shltx|alab|avp|aap)$")


def games(dirs):
    for d in dirs:
        if os.path.exists(os.path.join(d, "infolog.txt")):
            yield d
        else:
            yield from sorted(glob.glob(os.path.join(d, "matches", "*")))


def main(dirs):
    cls = defaultdict(lambda: defaultdict(float))
    army = defaultdict(lambda: [0, 0.0, 0.0, 0.0])
    n = 0
    for md in games(dirs):
        ours = ledger.our_teams(md)
        p = os.path.join(md, "infolog.txt")
        if not ours or not os.path.exists(p):
            continue
        cost, lives, origin, fac_army = {}, {}, {}, defaultdict(float)
        for ln in open(p, encoding="utf-8", errors="replace"):
            if "[BARAI_LIFE]" in ln:
                m = ledger.LIFE.search(ln)
                if m and int(m.group(2)) in ours:
                    lives[m.group(3)] = m.groups()
                continue
            m = PROD.search(ln)
            if m and int(m.group(1)) in ours:
                origin[m.group(5)] = m.group(6)
                if not ledger.BUILDER.search(m.group(2)):
                    fac_army[m.group(6)] += float(m.group(3))
            m = COST.search(ln)
            if m:
                cost.setdefault(m.group(1), float(m.group(2)))
        if not lives:
            continue
        n += 1
        army_dealt = defaultdict(float)
        for uid, lv in lives.items():
            if uid in origin:
                army_dealt[origin[uid]] += float(lv[4])
        for uid, lv in lives.items():
            d, c = lv[3], cost.get(lv[3], 0.0)
            if c <= 0:
                continue
            base = d[3:]
            dealt, taken = float(lv[4]), float(lv[5])
            if float(lv[8]) < 1.0:
                continue          # a frame: its job is the job ledger's
            if TOWER.search(base):
                k = cls["towers"]
                k["n"] += 1
                k["cost"] += c
                k["ret"] += dealt
                k["zero"] += dealt <= 0
            elif ECO.search(base):
                k = cls["economy"]
                made = float(lv[15]) + float(lv[16]) / E_PER_M
                k["n"] += 1
                k["cost"] += c
                k["ret"] += made
                k["zero"] += made < c
            elif PLANT.search(base) and uid in fac_army:
                k = cls["factories"]
                k["n"] += 1
                k["cost"] += c
                k["ret"] += fac_army[uid]
                k["army_dealt"] += army_dealt.get(uid, 0.0)
            elif ledger.BUILDER.search(d):
                k = cls["builders"]
                gm, gs = float(lv[13]), float(lv[14])
                k["n"] += 1
                k["cost"] += c
                k["mobile"] += gm
                k["static"] += gs
                k["zero"] += (gm + gs) <= 0
            elif uid in origin:
                a = army[d]
                a[0] += 1
                a[1] += c
                a[2] += dealt
                a[3] += taken
    print("%d games with life lines\n" % n)
    t = cls["towers"]
    if t["n"]:
        print("towers     %5d  metal %8.0f  damage dealt per metal %.2f  dealt nothing %.0f%%" % (
            t["n"], t["cost"], t["ret"] / t["cost"], 100 * t["zero"] / t["n"]))
    e = cls["economy"]
    if e["n"]:
        print("economy    %5d  metal %8.0f  made per metal %.2f  did not pay for itself %.0f%%" % (
            e["n"], e["cost"], e["ret"] / e["cost"], 100 * e["zero"] / e["n"]))
    f = cls["factories"]
    if f["n"]:
        print("factories  %5d  metal %8.0f  army made per metal %.2f  that army's damage per factory metal %.2f" % (
            f["n"], f["cost"], f["ret"] / f["cost"], f["army_dealt"] / f["cost"]))
    b = cls["builders"]
    if b["n"]:
        print("builders   %5d  metal %8.0f  build power into units %.0f / buildings %.0f metal  built nothing %.0f%%" % (
            b["n"], b["cost"], b["mobile"], b["static"], 100 * b["zero"] / b["n"]))
    print("\narmy units: metal of damage dealt / taken per metal, by unit (10+ built)")
    for d, (k, c, dl, tk) in sorted(army.items(), key=lambda kv: -kv[1][1])[:20]:
        if k >= 10:
            print("  %-12s %5d  metal %8.0f  dealt %.2f  taken %.2f" % (d, k, c, dl / c, tk / c))


if __name__ == "__main__":
    main(sys.argv[1:])
