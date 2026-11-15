"""Broken decision logic, per seat, from finished matches (his 11-14: randomized games find the flaws).

    python tools/pathology.py matches/rnd1-*            # one row per seat and a total per check
    python tools/pathology.py matches/rnd1-* --by-ai     # totals split by AI

Each check names a state a player would call broken, whatever the units' stats:
  bank-idle      metal storage >= 80% while the army holds < 50% of its target, 3+ minutes after minute 5
                 (needs the `apex: metal` line, 11-14 on; older builds read n/a)
  cons-over-cap  constructors standing above the fleet cap (maxunits/50 = 40)
  army-starved   at the last sample after minute 10, army < 20% of all metal built
  energy-dead    energy under 5% of storage with pull > income, 3+ samples in a row (30 s each) after minute 3
  wing-wiped     3+ bomber runs in a row with no survivor

A flag is a lead: read the seat's log around it. Randomizer games stay out of version comparisons.
"""
from __future__ import annotations

import argparse
import collections
import glob
import json
import re
import sys
from pathlib import Path

CON_CAP = 40
ARMY_SHARE_MIN = 0.20
LINE_RE = re.compile(r"\[f=(\d+)\] Skirmish AI <([^>]+)>: (?:\[[\d.]+m t(\d+)\] )?apex: (.*)")
TIER_RE = re.compile(r"\[BaRandom Tiers\] T(\d)")


def seat_name(spec: str) -> str:
    return spec.replace("-standard", "")


def scan(match: Path) -> list[dict]:
    res = json.loads((match / "result.json").read_text())
    specs = {t["team"]: seat_name(t["spec"]) for t in res.get("teams", [])}   # keyed by side (ally team)
    tier = None
    metal = collections.defaultdict(dict)    # team -> minute -> frac
    army = collections.defaultdict(dict)     # team -> minute -> have/target
    energy = collections.defaultdict(list)   # team -> [(minute, dead)]
    runs = collections.defaultdict(list)     # team -> [survived?]
    with open(match / "infolog.txt", errors="replace") as fh:
        for raw in fh:
            if "[BaRandom Tiers]" in raw:
                m = TIER_RE.search(raw)
                if m:
                    tier = int(m.group(1))
                continue
            if "apex: " not in raw:
                continue
            m = LINE_RE.search(raw)
            if not m:
                continue
            frame, _ai, tpre, body = int(m.group(1)), m.group(2), m.group(3), m.group(4)
            minute = frame / 1800.0
            tm = re.search(r"\bt=(\d+)", body)
            team = int(tpre) if tpre is not None else (int(tm.group(1)) if tm else None)
            if team is None:
                continue
            if body.startswith("metal cur="):
                mm = re.match(r"metal cur=(\d+)/(\d+) inc=([\d.]+) pull=([\d.]+)", body)
                if mm and int(mm.group(2)) > 0:
                    metal[team][int(minute)] = int(mm.group(1)) / int(mm.group(2))
            elif body.startswith("energy cur="):
                em = re.match(r"energy cur=(\d+)/(\d+) inc=(-?\d+) pull=(-?\d+)", body)
                if em and int(em.group(2)) > 0:
                    dead = (int(em.group(1)) < 0.05 * int(em.group(2))) and (int(em.group(4)) > int(em.group(3)))
                    energy[team].append((minute, dead))
            elif body.startswith("targets t="):
                am = re.search(r"army=(\d+)/(\d+)", body)
                if am and int(am.group(2)) > 0:
                    army[team][int(minute)] = int(am.group(1)) / int(am.group(2))
            elif body.startswith("air run scored"):
                sm = re.search(r"surv=([\d.]+)", body)
                if sm:
                    runs[team].append(float(sm.group(1)) > 0.0)
    stats = collections.defaultdict(list)
    for row in res.get("stats") or []:
        if row.get("reason") == "periodic":
            stats[int(row["team"])].append(row)

    allyOf = {}
    for team, rows in stats.items():
        allyOf[team] = int(rows[0].get("ally", team))
    seats = []
    for team in sorted(allyOf):
        spec = specs.get(allyOf[team], "?")
        flags = {}
        if metal.get(team):
            idle = [mi for mi, f in metal[team].items()
                    if mi >= 5 and f >= 0.8 and army[team].get(mi, army[team].get(mi - 1, 1.0)) < 0.5]
            flags["bank-idle"] = (len(idle) >= 3, "%d min" % len(idle))
        else:
            flags["bank-idle"] = (None, "n/a")
        rows = stats.get(team, [])
        cons = max((int(r.get("conT1", 0) + r.get("conT2", 0)) for r in rows), default=0)
        flags["cons-over-cap"] = (cons > CON_CAP, "max %d" % cons)
        late = [r for r in rows if r["frame"] >= 10 * 1800 and r.get("mBuiltReal", 0) > 0]
        if late:
            share = late[-1].get("mArmy", 0) / late[-1]["mBuiltReal"]
            flags["army-starved"] = (share < ARMY_SHARE_MIN, "army %.0f%% of spend" % (100 * share))
        else:
            flags["army-starved"] = (None, "n/a")
        run, longest = 0, 0
        for mi, dead in energy.get(team, []):
            run = run + 1 if (dead and mi >= 3) else 0
            longest = max(longest, run)
        flags["energy-dead"] = (longest >= 3, "longest %d" % longest)
        run, wiped = 0, 0
        for ok in runs.get(team, []):
            run = 0 if ok else run + 1
            wiped = max(wiped, run)
        flags["wing-wiped"] = (wiped >= 3, "%d in a row of %d" % (wiped, len(runs.get(team, []))))
        seats.append({"match": match.name, "team": team, "ai": spec, "tier": tier, "flags": flags})
    return seats


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("matches", nargs="+")
    ap.add_argument("--by-ai", action="store_true")
    a = ap.parse_args(argv)
    paths = []
    for p in a.matches:
        paths += [Path(x) for x in glob.glob(p)] or [Path(p)]
    seats = []
    for p in sorted(set(paths)):
        if (p / "result.json").exists() and (p / "infolog.txt").exists():
            seats += scan(p)
    if not seats:
        print("no finished matches")
        return 1
    checks = list(seats[0]["flags"].keys())
    for s in seats:
        bad = [k for k in checks if s["flags"][k][0]]
        tier = "" if s["tier"] is None else " T%d" % s["tier"]
        print("%-28s t%-2d %-24s%s  %s" % (s["match"], s["team"], s["ai"], tier,
              ("FLAG " + ", ".join("%s(%s)" % (k, s["flags"][k][1]) for k in bad)) if bad else "ok"))
    groups = collections.defaultdict(list)
    for s in seats:
        groups[s["ai"] if a.by_ai else "all"].append(s)
    print()
    for g, ss in sorted(groups.items()):
        cells = []
        for k in checks:
            known = [s for s in ss if s["flags"][k][0] is not None]
            cells.append("%s %d/%d" % (k, sum(1 for s in known if s["flags"][k][0]), len(known)))
        print("%-24s %s" % (g, "  ".join(cells)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
