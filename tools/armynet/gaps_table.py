#!/usr/bin/env python3
"""gaps.py's JSON lines as one short row per game.

    python tools/armynet/gaps.py [...] | python tools/armynet/gaps_table.py
"""
import json
import sys

print("step  fac  result  min  | mex/inc/army@10 A vs B          | their mex killed A, B (by10,all) | radar A/B | "
      "ground A/B | play deep, mass | eval deep")
for line in sys.stdin:
    try:
        r = json.loads(line)
    except ValueError:
        continue
    a, b = r["m10"]
    k = r["their_mex_killed_by_10_and_all"]
    rad = r["first_radar_min"]
    print("%5s %-4s %-6s %5.1f | %s vs %s | %s %s | %s/%s | %s | %s, %s | %s" % (
        r.get("step"), (r.get("faction") or ["?"])[0][:3],
        "won" if r["won"] else ("draw" if r.get("draw") else "lost"), r["minutes"] or 0,
        "/".join(str(round(x)) if x is not None else "-" for x in a), "/".join(str(round(x)) if x is not None else "-" for x in b),
        k["A"], k["B"], rad.get("0", rad.get(0)), rad.get("1", rad.get(1)), r["ground_given_up"],
        r.get("play_deep_share"), r.get("play_deep_mass_mean"), r.get("eval_deep_model")))
