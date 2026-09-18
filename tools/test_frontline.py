#!/usr/bin/env python3
"""The front-line and mex-guard regression test.

Runs a fixed set of 1v1s against stock BARb hard and scores every Apex team
with tools/frontline_check.py's THRESHOLDS: early mexes guarded by their own
gun (and not stacked), and a line of towers standing between us and them by
the line minute. One command, pass/fail:

    python tools/test_frontline.py                 # run the set, then judge
    python tools/test_frontline.py --report <dir>  # judge an existing set
    python tools/test_frontline.py --games 4 --parallel 2 --minutes 20

A metric passes when at least PASS_FRAC of the games pass it. Two seeds cannot
resolve a change, so the default set is eight games; the verdict is per metric
so a regression names what broke. A game Apex wins before a metric's minute
is skipped for that metric (the enemy was dead); an early loss is not. Runs
land in tournaments/<stamp>-frontline/.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import frontline_check as fc  # noqa: E402

SPEC_A = "Apex:Unstable:standard"
SPEC_B = "BARb:stable:hard"
MAP = "Comet Catcher"
PASS_FRAC = 0.75
MIN_SCORED = 3      # a metric with fewer scored games (early wins skip it) is undecided
# Reported but not judged: the first-factory check trips on an opening wedge
# that is not a defence regression (the (1460,2976) Comet Catcher start, the
# commander idle in range of his own site -- ISSUES.md 2026-09-02). Judge it
# again once that is fixed.
WARN_ONLY = {"plant"}


def run_set(out: Path, games: int, parallel: int, minutes: int, handicap: int,
            per_side: int = 1, spec_a: str = SPEC_A):
    out.mkdir(parents=True, exist_ok=True)
    (out / "matches").mkdir(exist_ok=True)
    pending = list(range(1, games + 1))
    live = []
    # One engine write dir per parallel slot: two engines on one dir corrupt
    # each other's infolog (CLAUDE.md, harness discipline).
    slots = list(range(parallel))
    while pending or live:
        while pending and slots:
            seed = pending.pop(0)
            slot = slots.pop(0)
            mdir = out / "matches" / f"s{seed}"
            wdir = ROOT / "matches" / f"_engine_fl{slot}"
            cmd = [sys.executable, "-u", str(HERE / "run_match.py"),
                   "--a", spec_a, "--b", SPEC_B, "--map", MAP,
                   "--minutes", str(minutes), "--seed", str(seed),
                   "--sides", "Armada,Armada", "--handicap", str(handicap),
                   "--per-side", str(per_side),
                   "--out", str(mdir), "--write-dir", str(wdir)]
            log = open(out / f"s{seed}.log", "w")
            live.append((seed, slot, subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT), log))
            print(f"  launched seed {seed}", flush=True)
            time.sleep(3)
        for item in live[:]:
            seed, slot, proc, log = item
            if proc.poll() is not None:
                log.close()
                live.remove(item)
                slots.append(slot)
                print(f"  seed {seed} finished rc={proc.returncode}", flush=True)
        time.sleep(5)


def judge(out: Path):
    dirs = sorted(p for p in (out / "matches").iterdir() if (p / "stdout.txt").exists())
    per_metric = {"plant": [], "guard": [], "stack": [], "line": []}
    wins = 0
    for d in dirs:
        rep = fc.analyse(d)
        fc.show(rep, d)
        won, mins = fc.outcome(d)
        wins += 1 if won else 0
        how = "Apex won" if won else ("lost" if won is False else "timelimit")
        print(f"   outcome: {how} at {mins}m")
        for team, (ok, reasons, skipped) in fc.verdict(rep, won).items():
            per_metric["plant"].append(not any(r.startswith("plant") for r in reasons))
            if "guard" not in skipped:
                per_metric["guard"].append(not any(r.startswith("guard") for r in reasons))
                per_metric["stack"].append(not any(r.startswith("stack") for r in reasons))
            if "line" not in skipped:
                per_metric["line"].append(not any(r.startswith("line") for r in reasons))
    print(f"\n== VERDICT ==  ({wins}/{len(dirs)} won -- not a metric, the noise floor is too high)")
    failed = 0
    for k, v in per_metric.items():
        if k in WARN_ONLY:
            print(f"  warn  {k:<6} {sum(v)}/{len(v)} games pass (reported, not judged -- see WARN_ONLY)")
            continue
        if len(v) < MIN_SCORED:
            print(f"  {k:<6} only {len(v)} scored game(s); need {MIN_SCORED}")
            failed += 1
            continue
        frac = sum(v) / len(v)
        ok = frac >= PASS_FRAC
        failed += 0 if ok else 1
        tag = "ok  " if ok else "FAIL"
        print(f"  {tag}  {k:<6} {sum(v)}/{len(v)} games pass (need {PASS_FRAC:.0%})")
    summary = {"games": len(dirs), "wins": wins,
               "metrics": {k: (sum(v), len(v)) for k, v in per_metric.items()},
               "thresholds": fc.THRESHOLDS, "passed": failed == 0}
    (out / "frontline_summary.json").write_text(json.dumps(summary, indent=2))
    return failed == 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--games", type=int, default=8)
    ap.add_argument("--parallel", type=int, default=3)
    ap.add_argument("--minutes", type=int, default=20)
    ap.add_argument("--handicap", type=int, default=50)
    ap.add_argument("--per-side", type=int, default=1,
                    help="AIs per side; 4 is a 4v4 (every Apex team is scored)")
    ap.add_argument("--report", help="judge this set instead of running one")
    ap.add_argument("--name", default="frontline")
    ap.add_argument("--a", default=SPEC_A, help="the AI under test (a lane spec)")
    a = ap.parse_args()
    if a.report:
        out = Path(a.report)
    else:
        out = ROOT / "tournaments" / f"{time.strftime('%Y%m%d-%H%M%S')}-{a.name}"
        print(f"== {out}")
        run_set(out, a.games, a.parallel, a.minutes, a.handicap, a.per_side, a.a)
    ok = judge(out)
    print(f"\n{'PASS' if ok else 'FAIL'}  {out}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
