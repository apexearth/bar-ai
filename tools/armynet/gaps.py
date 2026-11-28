#!/usr/bin/env python3
"""Where the army model falls short in its games, against our own AI on the other side (his 11-19: "run some on
your own and figure out where the gaps in our training are", "do this periodically").

    python tools/armynet/gaps.py [campaign dir | match dirs ...]   # default: the newest campaign's games

Per game, side A (team 0, the model's army) against side B (team 1, our AI's army), same AI otherwise:
  result and length; mexes, metal income and army metal at 6/10/14 min (result.json stats);
  their extractors each side killed by 10 min and in all ([BARAI_DEATH]); raider repeat kills, ground given up
  (tools/contract.py); first radar; how far forward the model's orders went in play, minute by minute, and the
  share past 0.7 (serve.log), beside the held-out evaluation's figure for the same checkpoint (campaign.log).
"""
import glob
import json
import re
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools"))
import contract  # noqa: E402

DEATH = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\w+) .*? atkteam=(-?\d+)")
BUILD = re.compile(r"\[BARAI_BUILD\] team=(\d+) ally=\d+ frame=\d+ min=([\d.]+) unit=(\w+)")
MINUTE = re.compile(r"minute (\d+) orders (\d+) forward median ([-\d.]+) deep (\d+)%(?: deep mass mean ([\d.]+))?")
RADAR = re.compile(r"^(arm|cor|leg)(rad|arad)$")


def engine_dir(match):
    """The watch run's engine write dir (serve.log, barai-gadgets.log) beside its matches/armynet-watch-<stamp>."""
    stamp = match.name.replace("armynet-watch-", "")
    for d in (REPO / "matches" / ("watch-armynet-engine-" + stamp), REPO / "matches" / ("_engine-armynet-watch-" + stamp)):
        if d.exists():
            return d
    return None


def at_minute(stats, team, minute, key):
    rows = [r for r in stats if int(r["team"]) == team and r["frame"] <= minute * 1800 + 1]
    return rows[-1].get(key) if rows else None


def one(match, eval_line=None):
    res = json.loads((match / "result.json").read_text())
    r, stats = res.get("result") or {}, res.get("stats") or []
    eng = engine_dir(match)
    out = {"match": match.name, "won": 0 in (r.get("winners") or []), "draw": not r.get("winners"),
           "minutes": r.get("game_minutes"),
           "faction": res.get("sides")}
    for m in (6, 10, 14):
        out["m%d" % m] = tuple((at_minute(stats, t, m, "mex"), round(at_minute(stats, t, m, "mInc") or 0),
                               round(at_minute(stats, t, m, "armyReal") or 0)) for t in (0, 1))
    eco_kills = {0: [0, 0], 1: [0, 0]}
    radar = {0: None, 1: None}
    gl = eng / "barai-gadgets.log" if eng else None
    if gl and gl.exists():
        for ln in open(gl, errors="replace"):
            d = DEATH.search(ln)
            if d and ("mex" in d.group(3) or "moho" in d.group(3)):
                victim, killer = int(d.group(2)), int(d.group(4))
                if killer in eco_kills and killer != victim:
                    eco_kills[killer][1] += 1
                    if int(d.group(1)) < 18000:
                        eco_kills[killer][0] += 1
            b = BUILD.search(ln)
            if b and RADAR.match(b.group(3)) and int(b.group(1)) in radar and radar[int(b.group(1))] is None:
                radar[int(b.group(1))] = float(b.group(2))
    out["their_mex_killed_by_10_and_all"] = {"A": eco_kills[0], "B": eco_kills[1]}
    out["first_radar_min"] = radar
    seats = {s.team: s for s in contract.load(match)}
    for name, fn in (("raider_repeats", contract.raider_repeat_kills), ("ground_given_up", contract.ground_given_up)):
        out[name] = tuple(None if t not in seats or fn(seats[t]) is None else round(fn(seats[t]), 2) for t in (0, 1))
    sl = eng / "serve.log" if eng else None
    if sl and sl.exists():
        mins = [MINUTE.search(l) for l in open(sl, errors="replace")]
        mins = [(int(m.group(1)), int(m.group(2)), float(m.group(3)), int(m.group(4))) for m in mins if m]
        if mins:
            n = sum(m[1] for m in mins)
            out["play_orders"] = n
            out["play_forward_median_by_minute"] = [(m[0], m[2]) for m in mins[::3]]
            out["play_deep_share"] = round(sum(m[1] * m[3] / 100 for m in mins) / max(n, 1), 3)
            masses = [float(x.group(5)) for x in (MINUTE.search(l) for l in open(sl, errors="replace"))
                      if x and x.group(5)]
            if masses:
                out["play_deep_mass_mean"] = round(float(np.mean(masses)), 3)
    if eval_line:
        out["eval_deep_model"], out["eval_deep_player"] = eval_line.get("deep_model"), eval_line.get("deep_player")
    return out


def main(a):
    if a and all(Path(x).name.startswith("armynet-watch-") for x in a):
        rows = [(Path(x), None) for x in a]
    else:
        camp = Path(a[0]) if a else Path(sorted(glob.glob(str(REPO / "runtime" / "armynet" / "campaign-2*")))[-1])
        rows = []
        for ln in open(camp / "campaign.log", errors="replace"):
            if ln.startswith("RESULT "):
                r = json.loads(ln[7:])
                ev = None
                try:
                    import ast
                    ev = ast.literal_eval(r.get("eval") or "None")
                except (ValueError, SyntaxError):
                    pass
                if r.get("match"):
                    rows.append((REPO / "matches" / r["match"], dict(ev or {}, step=r.get("step"))))
    for m, ev in rows:
        if (m / "result.json").exists():
            o = one(m, ev)
            if ev:
                o["step"] = ev.get("step")
            print(json.dumps(o))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
