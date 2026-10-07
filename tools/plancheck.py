#!/usr/bin/env python3
"""Team plan and push, game by game: did the plan net, the team push and the
ally-gantry help fire, and what did each side play?

    python tools/plancheck.py <tournament-dir> [--last N]

Per game: map, minutes, winner side, the explorer's side, each side's plans
over time (minute:PLAN), push go count, gather peaks, ally-gantry assists and
nuke volleys banked at the line. Sides are ally teams from the game's own
script.txt (result.json winners are ally indices).
"""
import collections
import json
import re
import sys
from pathlib import Path

PLAN_ROW = re.compile(r"\[f=(\d+)\].*apex: nnplan t=(\d+) .* chosen=(\d)")
FOLLOW = re.compile(r"\[f=(\d+)\].*apex: plan t=(\d+) follows (\w+)")
PUSH = re.compile(r"apex: push t=(\d+) plan=(\w+) .* foe=([\d.]+) team=([\d.]+) mine=([\d.]+) all=([\d.]+) go=(\d)")
GO = re.compile(r"\[f=(\d+)\].*apex: push go t=(\d+) plan=(\w+)")
NAMES = ("NORMAL", "T3", "MISSILE", "ARTY", "MASS")


def ally_of(script):
    out, team = {}, None
    for ln in script.splitlines():
        m = re.match(r"\s*\[TEAM(\d+)\]", ln)
        if m:
            team = int(m.group(1))
        m = re.match(r"\s*AllyTeam=(\d+);", ln)
        if m and team is not None:
            out[team] = int(m.group(1))
            team = None
    return out


def one(m):
    try:
        r = json.loads((m / "result.json").read_text())
        log = (m / "infolog.txt").read_text(encoding="utf-8", errors="replace")
        ally = ally_of((m / "script.txt").read_text(encoding="utf-8", errors="replace"))
    except (OSError, ValueError):
        return None
    res = r.get("result") or {}
    ex = sorted({int(x) for x in re.findall(r"nn-explore t=(\d+) on", log)})
    plans = collections.defaultdict(list)
    for f, t, c in PLAN_ROW.findall(log):
        plans[ally.get(int(t), -1)].append("%d:%s" % (int(f) // 1800, NAMES[int(c)]))
    goes = collections.Counter(ally.get(int(t), -1) for _f, t, _p in GO.findall(log))
    peak = collections.defaultdict(float)
    foe = collections.defaultdict(float)
    for t, _p, fo, team, _mine, _all, _go in PUSH.findall(log):
        a = ally.get(int(t), -1)
        peak[a] = max(peak[a], float(team))
        foe[a] = max(foe[a], float(fo))
    agan = collections.Counter(ally.get(int(t), -1) for t in re.findall(r"apex: ally-gantry t=(\d+)", log))
    line = log.count("(the line, plan MISSILE)")
    return {"map": r.get("map", "?")[:18], "min": res.get("game_minutes"), "win": res.get("winners"),
            "ex": [ally.get(t, -1) for t in ex], "plans": dict(plans), "goes": dict(goes),
            "peak": dict(peak), "foe": dict(foe), "agan": dict(agan), "line": line}


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    root = Path(argv[0])
    last = int(argv[argv.index("--last") + 1]) if "--last" in argv else 0
    ms = sorted((root / "matches").glob("*"), key=lambda p: p.stat().st_mtime)
    if last:
        ms = ms[-last:]
    tot = collections.Counter()
    for m in ms:
        g = one(m)
        if g is None:
            continue
        tot["games"] += 1
        exs = g["ex"][0] if g["ex"] else -1
        won = (g["win"] or [None])[0]
        tot["ex_won" if won == exs else ("ex_lost" if won is not None else "draw")] += 1
        for a in (0, 1):
            ps = g["plans"].get(a, [])
            nn = sum(1 for p in ps if not p.endswith("NORMAL"))
            tot["side_rows"] += len(ps)
            tot["side_rows_siege"] += nn
            tot["goes"] += g["goes"].get(a, 0)
            tot["agan"] += g["agan"].get(a, 0)
        tot["line"] += g["line"]
        print("%-18s %5.1fm win=%s ex=%s goes=%s gather=%s foe=%s allyGantry=%s line=%d" % (
            g["map"], g["min"] or 0, g["win"], g["ex"], g["goes"],
            {k: round(v) for k, v in g["peak"].items()}, {k: round(v) for k, v in g["foe"].items()},
            g["agan"], g["line"]))
        for a in sorted(g["plans"]):
            print("    side %d: %s" % (a, " ".join(g["plans"][a])))
    print(dict(tot))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
