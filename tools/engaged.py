#!/usr/bin/env python3
"""How much of each army actually fights: his 10-16 question ("maybe they have ALL their army
shooting while we go in small chunks and the rest is not even engaged").

Per [BARAI_ARMY] snapshot (every 10 s; field 6 = damaged an enemy in the last 10 s, from
dev_combat_log.lua), per side:
  contact   own armed mobiles within CONTACT elmos of an enemy armed mobile
  shooting  share of those that hit an enemy in the last 10 s
  committed contact / own armed mobiles within NEAR elmos of any contact unit -- low means the
            squad arrived piecemeal or spread out while the fight went on
Snapshots where both sides have contact are averaged per side, and the per-unit sums give
the army-wide shares. "us" is the Apex alliance (--us <shortName> as in minutes.py).

usage: python tools/engaged.py <match-dir...> [--from 2] [--to 10] [--us Apex]
"""
import math
import re
import sys
from pathlib import Path

CONTACT = 600.0
NEAR = 2000.0
RA = re.compile(r"\[BARAI_ARMY\] frame=(\d+) team=(\d+) n=\d+ part=\d+/\d+ (.*)$")


def sides(match, us_name):
    script = ""
    for n in ("script.txt", "_script.txt"):
        p = match / n
        if p.exists():
            script = p.read_text(encoding="utf-8", errors="replace")
            break
    ally, ours = {}, set()
    for block in re.findall(r"\[team(\d+)\]\s*\{(.*?)\}", script, re.S | re.I):
        a = re.search(r"allyteam=(\d+);", block[1], re.I)
        if a:
            ally[int(block[0])] = int(a.group(1))
    for block in re.findall(r"\[ai\d+\]\s*\{(.*?)\}", script, re.S | re.I):
        tm = re.search(r"team=(\d+);", block, re.I)
        sn = re.search(r"shortname=([^;]+);", block, re.I)
        if tm and sn and re.fullmatch(us_name, sn.group(1), re.I):
            ours.add(ally.get(int(tm.group(1)), -1))
    return {t: ("us" if a in ours else "them") for t, a in ally.items()}


def read(match, lo, hi, us_name):
    side = sides(match, us_name)
    snaps = {}
    for line in open(match / "infolog.txt", encoding="utf-8", errors="replace"):
        m = RA.search(line)
        if not m:
            continue
        f, t = int(m.group(1)), int(m.group(2))
        if not (lo * 1800 <= f < hi * 1800):
            continue
        s = side.get(t)
        if s is None:
            continue
        for tok in m.group(3).split(","):
            p = tok.split(":")
            if len(p) < 6:
                continue
            snaps.setdefault(f, {"us": [], "them": []})[s].append((float(p[2]), float(p[3]), p[5] == "1"))
    return snaps


def measure(snaps):
    acc = {s: {"snaps": 0, "contact": 0, "shoot": 0, "near": 0, "fshoot": 0.0, "fcommit": 0.0} for s in ("us", "them")}
    for f, d in snaps.items():
        if not d["us"] or not d["them"]:
            continue
        cont = {}
        for s, o in (("us", "them"), ("them", "us")):
            cont[s] = [u for u in d[s] if any(math.hypot(u[0] - e[0], u[1] - e[1]) < CONTACT for e in d[o])]
        if not cont["us"] or not cont["them"]:
            continue
        for s in ("us", "them"):
            c = cont[s]
            near = [u for u in d[s] if any(math.hypot(u[0] - k[0], u[1] - k[1]) < NEAR for k in c)]
            a = acc[s]
            a["snaps"] += 1
            a["contact"] += len(c)
            a["shoot"] += sum(1 for u in c if u[2])
            a["near"] += len(near)
            a["fshoot"] += sum(1 for u in c if u[2]) / len(c)
            a["fcommit"] += len(c) / max(1, len(near))
    return acc


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    lo = float(argv[argv.index("--from") + 1]) if "--from" in argv else 2.0
    hi = float(argv[argv.index("--to") + 1]) if "--to" in argv else 10.0
    us_name = argv[argv.index("--us") + 1] if "--us" in argv else "Apex[^;]*"
    skip = {argv[i + 1] for i, a in enumerate(argv) if a in ("--from", "--to", "--us")}
    total = {s: {"snaps": 0, "contact": 0, "shoot": 0, "near": 0, "fshoot": 0.0, "fcommit": 0.0} for s in ("us", "them")}
    for a in argv:
        if a.startswith("--") or a in skip:
            continue
        match = Path(a)
        if not (match / "infolog.txt").exists():
            continue
        acc = measure(read(match, lo, hi, us_name))
        for s in acc:
            for k in acc[s]:
                total[s][k] += acc[s][k]
    print("minutes %g-%g, snapshots with contact on both sides" % (lo, hi))
    print(" side | snaps | in contact/snap | shooting (units) | shooting (mean) | committed (units) | committed (mean)")
    for s in ("us", "them"):
        a = total[s]
        n = max(1, a["snaps"])
        print(" %-4s | %5d | %15.1f | %15.0f%% | %14.0f%% | %16.0f%% | %15.0f%%" % (
            s, a["snaps"], a["contact"] / n, 100.0 * a["shoot"] / max(1, a["contact"]), 100.0 * a["fshoot"] / n,
            100.0 * a["contact"] / max(1, a["near"]), 100.0 * a["fcommit"] / n))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
