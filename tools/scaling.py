#!/usr/bin/env python3
"""Economy-scaling scorecard: us vs the enemy, per game and in aggregate.

The goal it measures (apexearth 2026-08-20): "keep going until our economy
scaling is better than Barb stable." Scaling is a curve, not an endpoint, so
each game reports metal/energy/mex ratios at 10m, 20m, and the last paired
sample; the aggregate prints medians. A ratio > 1.0 means we lead.

    python tools/scaling.py matches/<dir> [...]
    python tools/scaling.py --last 6            # newest N 1v1 match dirs
"""
import json
import sys
import glob
import os
from pathlib import Path


def ratios(d):
    try:
        r = json.load(open(Path(d) / "result.json"))
    except OSError:
        return None
    # Sides by ALLY: team games sum each side (apexearth 2026-08-20: "check
    # scaling in two v two, four v four, and eight v eight games").
    # Side split by the ALLY field: per-side games carry stats for teams the
    # result.json team list never names (it records only the two specs). Our
    # side is the ally of team 0 (--a is always team 0 in run_match).
    ally_of = {}
    for row in r["stats"]:
        ally_of[int(row["team"])] = int(row.get("ally", row["team"]))
    # r["teams"][i]["team"] is the SPEC index ('a'=0, 'b'=1), not a game team:
    # in a per-side game spec b's players are teams N..2N-1. Each spec's players
    # share the allyteam equal to its spec index, so anchor on that directly --
    # anchoring on ally_of[spec_index] read the OTHER side whenever Apex was
    # spec b (every side-swapped tournament game, measured 2026-08-21).
    apex_teams = [t["team"] for t in r["teams"] if t["shortName"].startswith("Apex")]
    if not apex_teams:
        return None
    my_ally = apex_teams[0]
    ours = set(t for t, a in ally_of.items() if a == my_ally)
    theirs = set(ally_of) - ours
    if not ours or not theirs:
        return None
    per = {}
    for s in r["stats"]:
        per.setdefault(int(s["frame"]), {})[int(s["team"])] = s
    def side_ok(f):
        row = per[f]
        return any(t in row for t in ours) and any(t in row for t in theirs)
    paired = sorted(f for f in per if side_ok(f))
    if not paired:
        return None
    marks = {}
    for label, target in (("10m", 18000), ("20m", 36000), ("end", paired[-1])):
        f = min(paired, key=lambda x: abs(x - target))
        row = {}
        for key, name in (("metalProduced", "metal"), ("energyProduced", "energy"), ("mex", "mex")):
            av = sum(per[f][t].get(key, 0) for t in ours if t in per[f])
            bv = sum(per[f][t].get(key, 0) for t in theirs if t in per[f])
            row[name] = (av / bv) if bv else None
        marks[label] = row
    w = r["result"]["winner_specs"]
    res = "D" if not w else ("W" if "Apex" in w[0] else "L")
    return r["map"], res, r["result"]["game_minutes"], marks


def main():
    args = sys.argv[1:]
    if args and args[0] == "--last":
        n = int(args[1]) if len(args) > 1 else 6
        dirs = sorted(glob.glob("matches/2*-Apex-*"), key=os.path.getmtime)[-n:]
    else:
        dirs = args
    rows = []
    for d in dirs:
        out = ratios(d)
        if out:
            rows.append(out)
    agg = {m: {k: [] for k in ("metal", "energy", "mex")} for m in ("10m", "20m", "end")}
    for mp, res, mins, marks in rows:
        cells = "  ".join(
            f"{lbl} m={v['metal']:.2f} e={v['energy']:.2f} x={v['mex']:.2f}"
            if all(v[k] is not None for k in v) else f"{lbl} -"
            for lbl, v in marks.items())
        print(f"{res} {mp[:14]:<14} {mins:5.1f}m  {cells}")
        for lbl, v in marks.items():
            for k, val in v.items():
                if val is not None:
                    agg[lbl][k].append(val)
    print("\nmedians (>1.0 = we out-scale stock):")
    for lbl in ("10m", "20m", "end"):
        parts = []
        for k in ("metal", "energy", "mex"):
            vals = sorted(agg[lbl][k])
            parts.append(f"{k}={vals[len(vals)//2]:.2f}" if vals else f"{k}=-")
        print(f"  {lbl}: " + "  ".join(parts))


if __name__ == "__main__":
    main()
