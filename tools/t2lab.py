#!/usr/bin/env python3
"""The first T2 plant and the plant types, per game, us against BARb.

    python tools/t2lab.py <tournament|match dir> [...] [--all] [--rows]

Per side: when the first T2 plant was started and finished (gadget
[BARAI_T2START]/[BARAI_T2DONE]), never-finished starts, the first factory's
type, vehicle plants (T1+T2) standing by minute 16, and the army metal
produced by plant type ([BARAI_PROD]). For our side it also reads the build
window from our own log: distinct hands that assisted it, the peak and final
progress of any frame-stalled report (decay shows as done falling), and how
many minutes read metal-path starved. Games where our seat explored
(`apex: nn-explore t=<us> on`) are skipped unless --all.
"""
import glob
import os
import re
import statistics
import sys

NAME_RE = re.compile(r"\[BARAI_NAME\] team=(\d+) name=\[([^\]]+)\]")
T2S_RE = re.compile(r"\[BARAI_T2START\] team=(\d+) ally=\d+ frame=(\d+) min=[\d.]+ unit=(\w+)")
T2D_RE = re.compile(r"\[BARAI_T2DONE\] team=(\d+) ally=\d+ frame=(\d+) min=[\d.]+ unit=(\w+)")
BUILD_RE = re.compile(r"\[BARAI_BUILD\] team=(\d+) ally=\d+ frame=(\d+) min=[\d.]+ unit=(\w+) cost=(\d+)")
PROD_RE = re.compile(r"\[BARAI_PROD\] team=(\d+) ally=\d+ frame=(\d+) min=[\d.]+ unit=(\w+) cost=(\d+) fac=(\w+)")
RES_RE = re.compile(r"\[BARAI_RESULT\] reason=\S+ frame=(\d+) winners=(\S+)")
STATS_RE = re.compile(r"\[BARAI_STATS\] team=(\d+) .*?frame=(\d+) .*?techFrame=(-?\d+) techStart=(-?\d+)")
FRAME_RE = re.compile(r"\[f=(\d+)\]")

PLANT_RE = re.compile(r"^(arm|cor|leg)(a?lab|a?vp|a?ap|hp|fhp|a?sy|amsub|plat|gant|shltx|ha\w+)$")


def ptype(u):
    m = PLANT_RE.match(u)
    if not m:
        return None
    s = m.group(2)
    if s in ("gant", "shltx") or s.startswith("ha"):
        return "T3"
    tier = "T2" if s.startswith("a") and s not in ("amsub",) else "T1"
    if s.endswith("lab"):
        k = "bot"
    elif s.endswith("vp"):
        k = "veh"
    elif s.endswith("ap"):
        k = "air"
    elif s in ("hp", "fhp"):
        k = "hover"
    else:
        k = "sea"
    return tier + k


def one(mdir, allg):
    p = os.path.join(mdir, "infolog.txt")
    if not os.path.exists(p):
        return None
    txt = open(p, encoding="utf-8", errors="replace").read()
    names = {int(t): n for t, n in NAME_RE.findall(txt)}
    us = [t for t, n in names.items() if n != "STABLE"]
    them = [t for t, n in names.items() if n == "STABLE"]
    if not us or not them:
        return None
    if not allg and any(re.search(r"apex: nn-explore t=%d on" % t, txt) for t in us):
        return "explore"
    rm = RES_RE.search(txt)
    winners = rm.group(2) if rm else "?"
    endf = int(rm.group(1)) if rm else 0
    # ally == team in 1v1; winners lists allies
    won = None
    if rm:
        won = str(us[0]) in winners.split(",")
    sides = {}
    for side, teams in (("us", us), ("them", them)):
        d = {"t2s": None, "t2d": None, "t2unit": None, "first": None, "veh16": 0,
             "plants": [], "prod": {}}
        for t, f, u in T2S_RE.findall(txt):
            if int(t) in teams and d["t2s"] is None:
                d["t2s"], d["t2unit"] = int(f), u
        for t, f, u in T2D_RE.findall(txt):
            if int(t) in teams and d["t2d"] is None:
                d["t2d"] = int(f)
        seen = set()
        for t, f, u, c in BUILD_RE.findall(txt):
            if int(t) not in teams:
                continue
            pt = ptype(u)
            if pt is None:
                continue
            if d["first"] is None:
                d["first"] = pt
            d["plants"].append((int(f), u, pt))
            if pt.endswith("veh") and int(f) <= 16 * 1800:
                d["veh16"] += 1
        for t, f, u, c, fac in PROD_RE.findall(txt):
            if int(t) not in teams or int(f) > 16 * 1800:
                continue
            pt = ptype(fac) or "other"
            d["prod"][pt] = d["prod"].get(pt, 0) + int(c)
        last = {}
        for m in re.finditer(r"\[BARAI_STATS\] team=(\d+) .*?mLostReal=([\d.]+) .*?mKillReal=([\d.]+) .*?mBuiltReal=([\d.]+)", txt):
            if int(m.group(1)) in teams:
                last[int(m.group(1))] = (float(m.group(4)), float(m.group(3)), float(m.group(2)))
        d["built"] = sum(v[0] for v in last.values())
        d["kill"] = sum(v[1] for v in last.values())
        d["lost"] = sum(v[2] for v in last.values())
        sides[side] = d
    if rm is None and sides["us"]["built"] and sides["them"]["built"]:
        won = None   # timelimit: rows print built and kill/lost instead
    # our build window from our own log
    w = sides["us"]
    w["hands"] = None
    if w["t2s"] is not None and w["t2unit"]:
        u = w["t2unit"]
        f0 = w["t2s"] - 1800
        f1 = w["t2d"] if w["t2d"] is not None else endf
        hands = set()
        dones = []
        starved = 0
        decide = {}
        for line in txt.splitlines():
            if "apex: " not in line:
                continue
            fm = FRAME_RE.search(line)
            if not fm:
                continue
            fr = int(fm.group(1))
            if fr < f0 or fr > f1:
                continue
            if "assist-own" in line and ("-> " + u + " ") in line:
                m = re.search(r"#(\d+)", line)
                if m:
                    hands.add(m.group(1))
            elif ("frame-stalled " + u + " ") in line:
                m = re.search(r"done=([\d.]+) idle=(\d+)", line)
                if m:
                    dones.append(float(m.group(1)))
            elif "metal-path starved" in line:
                starved += 1
            elif "apex: decide t=" in line and " -> " in line:
                m = re.search(r" -> (\w+)/", line)
                if m:
                    decide[m.group(1)] = decide.get(m.group(1), 0) + 1
        w["hands"] = len(hands)
        w["dones"] = dones
        w["starved"] = starved
        w["decide"] = decide
    return {"dir": os.path.basename(mdir), "won": won, "sides": sides}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    allg = "--all" in sys.argv
    rows = "--rows" in sys.argv
    mdirs = []
    for a in args:
        if os.path.exists(os.path.join(a, "infolog.txt")):
            mdirs.append(a)
        else:
            mdirs += sorted(glob.glob(os.path.join(a, "matches", "*"))) or sorted(glob.glob(os.path.join(a, "*")))
    res = []
    skipped = 0
    for m in mdirs:
        r = one(m, allg)
        if r == "explore":
            skipped += 1
        elif r:
            res.append(r)
    print("games %d (explore skipped %d)  won %d" % (len(res), skipped, sum(1 for r in res if r["won"])))
    for side in ("us", "them"):
        for label, sel in (("all", lambda r: True), ("win", lambda r: r["won"]), ("loss", lambda r: r["won"] is False)):
            g = [r for r in res if sel(r)]
            if not g:
                continue
            S = [r["sides"][side] for r in g]
            st = [s["t2s"] / 1800 for s in S if s["t2s"] is not None]
            dur = [(s["t2d"] - s["t2s"]) / 1800 for s in S if s["t2s"] is not None and s["t2d"] is not None]
            never = sum(1 for s in S if s["t2s"] is not None and s["t2d"] is None)
            first = {}
            for s in S:
                first[s["first"]] = first.get(s["first"], 0) + 1
            veh = sum(s["veh16"] for s in S) / len(S)
            med = lambda x: ("%.1f" % statistics.median(x)) if x else "-"
            print("%-4s %-4s n=%-3d T2 started %d/%d start=%s dur=%s never=%d  first=%s  veh<=16m=%.2f/game"
                  % (side, label, len(g), len(st), len(S), med(st), med(dur), never,
                     ",".join("%s:%d" % kv for kv in sorted(first.items(), key=lambda kv: -kv[1])), veh))
        prod = {}
        for r in res:
            for k, v in r["sides"][side]["prod"].items():
                prod[k] = prod.get(k, 0) + v
        tot = sum(prod.values()) or 1
        print("     %s produced by plant type <=16m: %s" % (side, " ".join("%s=%d%%" % (k, 100 * v // tot) for k, v in sorted(prod.items(), key=lambda kv: -kv[1]))))
    hs = [r["sides"]["us"] for r in res if r["sides"]["us"].get("hands") is not None]
    if hs:
        print("us build window: distinct assisting hands median %s; frame-stalled games %d (decayed %d); starved-log median %s"
              % (statistics.median([h["hands"] for h in hs]),
                 sum(1 for h in hs if h["dones"]),
                 sum(1 for h in hs if len(h["dones"]) > 1 and min(h["dones"][1:]) < max(h["dones"][:-1])),
                 statistics.median([h["starved"] for h in hs])))
        dec = {}
        for h in hs:
            for k, v in h["decide"].items():
                dec[k] = dec.get(k, 0) + v
        tot = sum(dec.values()) or 1
        print("us decisions in the window: " + " ".join("%s=%d%%" % (k, 100 * v // tot) for k, v in sorted(dec.items(), key=lambda kv: -kv[1])))
    if rows:
        for r in res:
            u, t = r["sides"]["us"], r["sides"]["them"]
            f = lambda x: ("%.1f" % (x / 1800)) if x is not None else "-"
            print("%-5s us %s->%s %s hands=%s first=%s built=%dk k/l=%.2f | them %s->%s %s first=%s built=%dk veh=%d  %s" % (
                {True: "WIN", False: "loss", None: "time"}[r["won"]], f(u["t2s"]), f(u["t2d"]), u["t2unit"] or "", u.get("hands"),
                u["first"], u["built"] / 1000, u["kill"] / max(u["lost"], 1.0),
                f(t["t2s"]), f(t["t2d"]), t["t2unit"] or "", t["first"], t["built"] / 1000, t["veh16"], r["dir"][:40]))


if __name__ == "__main__":
    main()
