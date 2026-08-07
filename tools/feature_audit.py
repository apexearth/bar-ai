#!/usr/bin/env python3
"""Which of this AI's special strategies actually FIRED, across a whole run.

Every strategy in this variant is a rule that can silently never fire -- a gate
whose threshold the benchmark never reaches, a latch that never opens, a
customparam whose name the game does not use. This repo has shipped all three.
A win rate cannot see any of it: the AI plays a perfectly normal-looking game
with the feature dead.

So this reads the infologs and answers one question per feature: did it fire,
and in how many of the games. Coverage matters more than the raw count -- a
feature that fires 300 times in one game and never again is not working, it is
stuck.

Usage:
    python tools/feature_audit.py                    # newest tournament
    python tools/feature_audit.py <run-substring>    # a specific one
    python tools/feature_audit.py matches/<match>    # a single match

Reading the output:
    OK       fired in most games -- working
    RARE     fired in a few games -- may be threshold-gated; check the gate
    DEAD     never fired anywhere -- either unreachable here, or broken
    n/a      not expected under these conditions (noted per feature)
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# (label, regex, note explaining when absence is legitimate)
FEATURES: list[tuple[str, str, str]] = [
    ("T2 rush elected",      r"designated T2 rusher",            ""),
    ("tech lead assigned",   r"apex: tech lead = team",          ""),
    ("tech lead handover",   r"apex: tech lead CHANGED",         "only if a lead loses its plant"),
    ("metal slinging",       r"apex: sent .* to lead",           ""),
    ("T2 gate passed",       r"T2GATE reached",                  ""),
    ("T2 gate blocked",      r"T2GATE blocked",                  "healthy to be absent"),
    ("air assassin armed",   r"air assassin armed",              "needs AIR_FROM + income"),
    ("air strike released",  r"apex: air strike --",             "needs time to mass"),
    ("air role stood down",  r"air assassin STANDING DOWN",      "healthy to be absent"),
    ("eco lead active",      r"apex: ECO LEAD",                  "off under 6 per side by design"),
    ("T3 gantry started",    r"building T3 gantry",              "needs a long game"),
    ("army push (losing)",   r"behind on the field",             "absent when winning"),
    ("obsolete reclaim",     r"obsolete-reclaim",                "needs T2/T3 or a blocked build"),
    ("blocked-build clear",  r"obsolete-reclaim \w+ \(blocked",  "needs a failed large placement"),
    ("rez bots wanted",      r"apex: rez-diag",                  ""),
    ("wreck reclaim (rich)", r"rich-wreck reclaim",              "needs a real corpse pile"),
    ("con build-site veto",  r"apex: con-veto",                  ""),
    ("con rerouted",         r"apex: con-reroute",               ""),
    ("commander retreat",    r"commander retreating",            "absent if never threatened"),
    ("commander lost",       r"COMMANDER LOST",                  "GOOD to be absent"),
    ("converter built",      r"apex: converter",                 ""),
    # Checked 2026-08-07 against 16 games vs BARb medium: the gate read
    # enemyAir=0.0 in all 2,215 samples, and the telemetry confirms why --
    # every air unit in those games was OURS. Medium builds no air at all, so
    # this feature CANNOT be validated against it. Use BARb hard, or an
    # opponent that actually flies, before calling it broken.
    ("cheap AA standing",    r"apex: cheap-aa",                  "medium builds no air; needs a flying opponent"),
    ("metal-full fallback",  r"metal-full-fallback",             "only when idle with spare metal"),
]

# Errors that mean the run is not measuring what you think it is.
FATAL = [
    ("AngelScript compile errors", r"\.as \(\d+, \d+\) : ERR"),
]


def logs_for(arg: str) -> tuple[str, list[Path]]:
    if arg and Path(arg).exists() and (Path(arg) / "infolog.txt").exists():
        p = Path(arg)
        return p.name, [p / "infolog.txt"]
    runs = sorted(p for p in (REPO / "tournaments").glob(f"*{arg}*") if p.is_dir())
    if not runs:
        raise SystemExit("no matching tournament (and not a match dir)")
    run = runs[-1]
    return run.name, sorted(run.glob("matches/*/infolog.txt"))


def main() -> int:
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    name, logs = logs_for(arg)
    if not logs:
        raise SystemExit(f"{name}: no infologs found")

    texts = [p.read_text("utf-8", errors="replace") for p in logs]
    games = len(texts)
    print(f"FEATURE AUDIT  {name}   {games} game(s)\n")

    for label, pat in FATAL:
        rx = re.compile(pat)
        hits = sum(len(rx.findall(t)) for t in texts)
        bad = sum(1 for t in texts if rx.search(t))
        flag = "FAIL" if hits else "ok"
        print(f"  [{flag}] {label}: {hits} across {bad}/{games} games")
        if hits:
            print("         -> the variant was DISABLED; nothing below is meaningful")
    print()

    print(f"  {'feature':<24} {'games':>7}  {'fires':>6}  status")
    print(f"  {'-'*24} {'-'*7}  {'-'*6}  ------")
    for label, pat, note in FEATURES:
        rx = re.compile(pat)
        fires = sum(len(rx.findall(t)) for t in texts)
        cover = sum(1 for t in texts if rx.search(t))
        frac = cover / games if games else 0
        if fires == 0:
            status = "DEAD"
        elif frac >= 0.5:
            status = "OK"
        else:
            status = "RARE"
        line = f"  {label:<24} {cover:>3}/{games:<3} {fires:>6}  {status}"
        if status != "OK" and note:
            line += f"   ({note})"
        print(line)

    print("\n  DEAD with no note is the one to chase: a rule that never ran.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
