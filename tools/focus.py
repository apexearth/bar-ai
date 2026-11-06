#!/usr/bin/env python3
"""Do we finish what we start? (his 11-05: builds split six ways, 75 T2 extractor frames left under 10%.)

    python tools/focus.py <tournament or match dirs, per arm> [...]

Per game, our side: frames started and never finished (BARAI_LIFE prog < 1 at death) -- all kinds and extractors --
with the metal sunk in them; the mean and peak of live build requests per seat (`apex: request ... live=`); the
doing-nothing and help lines when present (`nothing-wins`, `help-stat`).
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

import airaudit
from unitdef import trees  # noqa: F401  (airaudit loads the unit table)

LIFE = re.compile(r"\[BARAI_LIFE\] frame=\d+ team=(\d+) uid=\d+ unit=(\S+) .*?started=(-?\d+) finished=(-?\d+) "
                  r"prog=([\d.]+)")
REQ = re.compile(r"\[(\d+(?:\.\d+)?)m t(\d+)\] apex: request \S+ \S+ inFlight=\d+ cap=\d+ live=(\d+)")
HELP = re.compile(r"apex: help-stat t=\d+ starts=(\d+) helpOffered=(\d+) helpPricedHigher=(\d+) helpWon=(\d+)")


def games(p):
    p = Path(p)
    if (p / "infolog.txt").exists():
        return [p]
    return sorted(x.parent for x in p.glob("matches/*/result.json"))


def cost_of(unit):
    try:
        return float(airaudit._COST.get(unit, 0))
    except AttributeError:
        return 0.0


def one(m):
    us = airaudit.ours(m)
    unf = unf_mex = 0
    live = defaultdict(list)
    nothing = 0
    help_tot = [0, 0, 0, 0]
    for line in open(m / "infolog.txt", encoding="utf-8", errors="replace"):
        if "[BARAI_LIFE]" in line:
            x = LIFE.search(line)
            if x and int(x.group(1)) in us and int(x.group(3)) > 0 and float(x.group(5)) < 1.0:
                unf += 1
                if "mex" in x.group(2) or "moho" in x.group(2):
                    unf_mex += 1
        elif "apex: request " in line:
            x = REQ.search(line)
            if x:
                live[int(x.group(2))].append(int(x.group(3)))
        elif "apex: nothing-wins" in line:
            nothing += 1
        elif "apex: help-stat" in line:
            x = HELP.search(line)
            if x:
                for i in range(4):
                    help_tot[i] += int(x.group(i + 1))
    seat_mean = [sum(v) / len(v) for v in live.values() if v]
    seat_peak = [max(v) for v in live.values() if v]
    return {"unfinished": unf, "unfinishedMex": unf_mex,
            "liveMean": sum(seat_mean) / len(seat_mean) if seat_mean else 0.0,
            "livePeak": sum(seat_peak) / len(seat_peak) if seat_peak else 0.0,
            "nothingLines": nothing, "help": help_tot}


def main():
    for arm in sys.argv[1:]:
        rows = [one(m) for m in games(arm)]
        n = len(rows) or 1
        h = [sum(r["help"][i] for r in rows) for i in range(4)]
        print("%s: %d games -- unfinished frames %.1f a game (extractors %.1f); live requests per seat mean %.1f, "
              "peak %.1f; nothing-wins lines %d; help: starts %d, help offered %d, help priced higher %d, help won %d"
              % (Path(arm).name, len(rows), sum(r["unfinished"] for r in rows) / n,
                 sum(r["unfinishedMex"] for r in rows) / n, sum(r["liveMean"] for r in rows) / n,
                 sum(r["livePeak"] for r in rows) / n, sum(r["nothingLines"] for r in rows), *h))


if __name__ == "__main__":
    main()
