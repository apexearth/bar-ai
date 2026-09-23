"""Win count per arm, parsed as JSON.

A line-oriented grep for "winner_specs" silently returns nothing here: the
field is pretty-printed, so the closing bracket is on another line. That read
zero wins for every arm regardless of what happened.
"""
import glob
import json
import os
import sys

for T in sys.argv[1:]:
    n = dec = win = tl = 0
    for p in sorted(glob.glob(os.path.join(T, "matches", "*", "result.json"))):
        try:
            d = json.load(open(p))
        except Exception:
            continue
        n += 1
        r = d.get("result", d)
        reason = r.get("reason") or d.get("reason")
        specs = r.get("winner_specs") or d.get("winner_specs") or []
        if reason == "timelimit":
            tl += 1
        if reason != "gameover":
            continue
        dec += 1
        if any("Apex" in str(s) for s in specs):
            win += 1
    print("%-52s results=%2d decided=%2d timelimit=%2d APEX WINS=%d (%.1f%% of decided)"
          % (os.path.basename(os.path.normpath(T))[:52], n, dec, tl, win,
             100.0 * win / dec if dec else 0.0))
