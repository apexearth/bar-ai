#!/usr/bin/env python3
"""End-to-end regression tests: run real matches, assert on invariants.

Read tests/README.md before adding a check. The short version: assert on
deadlock signatures, zero-counts and floors across players -- never on medians
or win rates, because this benchmark's same-config spread is ~20%.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

BASELINES = Path(__file__).resolve().parent / "baselines.json"
OUTROOT = REPO / "matches"

DIE_RE = re.compile(
    r"apex: task-die t=(\d+) (\w+) .*? at=(-?\d+,-?\d+).*?why=(\S+)")
EXEC_RE = re.compile(r"apex: exec t=(\d+) \S+ \S+ (\w+):(\w+)")
ERR_RE = re.compile(r"\(\d+, \d+\) : ERR|Fix compilation errors", re.I)


# --------------------------------------------------------------- gathering
def scan_log(path):
    """One pass over the infolog: compile errors, task deaths, elections."""
    out = {
        "compile_errors": 0,
        "deaths": {},      # (team, def) -> {"n": int, "pos": {pos: n}, "why": {}}
        "elected": {},     # kind:def -> count
    }
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "ERR" in line or "compilation" in line:
                if ERR_RE.search(line):
                    out["compile_errors"] += 1
            if "apex: task-die" in line:
                m = DIE_RE.search(line)
                if m:
                    team, dname, pos, why = m.groups()
                    d = out["deaths"].setdefault(
                        (team, dname), {"n": 0, "pos": {}, "why": {}})
                    d["n"] += 1
                    d["pos"][pos] = d["pos"].get(pos, 0) + 1
                    d["why"][why] = d["why"].get(why, 0) + 1
            elif "apex: exec t=" in line:
                m = EXEC_RE.search(line)
                if m:
                    key = "%s:%s" % (m.group(2), m.group(3))
                    out["elected"][key] = out["elected"].get(key, 0) + 1
    return out


def team_finals(result):
    """Last periodic sample per team."""
    finals = {}
    for s in result.get("stats", []):
        t = int(s["team"])
        if t not in finals or s["frame"] > finals[t]["frame"]:
            finals[t] = s
    return finals


# ----------------------------------------------------------------- checks
def chk_ran_clean(ctx, _arg):
    r = ctx["result"]["result"]
    if r["crashed"]:
        return "engine crashed"
    if not r["valid"]:
        return "run marked invalid"
    if r["ai_errors"]:
        return "AI errors: %s" % r["ai_errors"][:2]
    if ctx["log"]["compile_errors"]:
        return ("%d AngelScript compile error line(s) -- the variant played as "
                "near-stock" % ctx["log"]["compile_errors"])
    return None


def chk_no_deadlock(ctx, arg):
    """No (team, def) may lose most of its tasks at a single position.

    THE fusion signature: 21 of 21 dead, all at one spot. A healthy run retries
    elsewhere, so a high death count spread over several positions is fine and a
    high count at ONE position is a loop.
    """
    min_n = arg.get("min_deaths", 8)
    frac = arg.get("max_at_one_pos", 0.7)
    bad = []
    for (team, dname), d in ctx["log"]["deaths"].items():
        if d["n"] < min_n:
            continue
        worst_pos, worst_n = max(d["pos"].items(), key=lambda kv: kv[1])
        if worst_n >= frac * d["n"]:
            bad.append("t=%s %s: %d/%d deaths at %s (%s)"
                       % (team, dname, worst_n, d["n"], worst_pos,
                          ",".join(sorted(d["why"]))))
    return "; ".join(bad) if bad else None


def chk_min_across_teams(ctx, arg):
    """A floor on the WORST player, which is what a deadlock destroys."""
    key, floor = arg["stat"], arg["floor"]
    vals = [s.get(key, 0) or 0 for s in ctx["finals"].values()]
    if not vals:
        return "no team samples"
    if min(vals) < floor:
        worst = min(ctx["finals"].items(),
                    key=lambda kv: kv[1].get(key, 0) or 0)[0]
        return ("min %s across teams = %.0f (floor %.0f), worst is t=%d"
                % (key, min(vals), floor, worst))
    return None


def chk_nonzero(ctx, arg):
    """Something that must happen at all -- the zero-count class of bug."""
    missing = []
    for want in arg["any_of"]:
        n = sum(v for k, v in ctx["log"]["elected"].items()
                if k.startswith(want))
        if n > 0:
            return None
        missing.append(want)
    return "nothing elected matching: %s" % ", ".join(missing)


def chk_median_at_least(ctx, arg):
    """A GENEROUS floor on the median -- catches a collapse, not a regression."""
    import statistics
    key, floor = arg["stat"], arg["floor"]
    vals = sorted(s.get(key, 0) or 0 for s in ctx["finals"].values())
    if not vals:
        return "no team samples"
    med = statistics.median(vals)
    if med < floor:
        return "median %s = %.0f (floor %.0f)" % (key, med, floor)
    return None


CHECKS = {
    "ran_clean": chk_ran_clean,
    "no_deadlock": chk_no_deadlock,
    "min_across_teams": chk_min_across_teams,
    "nonzero": chk_nonzero,
    "median_at_least": chk_median_at_least,
}


# ------------------------------------------------------------------ driver
def run_scenario(name, spec, keep):
    out = OUTROOT / ("e2e-%s" % name)
    if out.exists() and not keep:
        import shutil
        shutil.rmtree(out, ignore_errors=True)
    if not (out / "result.json").is_file():
        cmd = [sys.executable, "-u", str(REPO / "tools" / "run_match.py"),
               "--out", str(out)] + spec["match"]
        print("    running: %s" % " ".join(spec["match"]))
        t0 = time.time()
        p = subprocess.run(cmd, capture_output=True, text=True,
                           cwd=str(REPO))
        if not (out / "result.json").is_file():
            return None, "match did not produce result.json:\n%s" % p.stdout[-1500:]
        print("    (%.0fs)" % (time.time() - t0))
    result = json.loads((out / "result.json").read_text())
    log = scan_log(out / "infolog.txt")
    return {"result": result, "log": log, "finals": team_finals(result),
            "dir": out}, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true",
                    help="run only the first scenario")
    ap.add_argument("--only", help="run one scenario by name")
    ap.add_argument("--keep", action="store_true",
                    help="reuse an existing run instead of re-running")
    ap.add_argument("--update", action="store_true",
                    help="re-record floors from this run (review the diff!)")
    args = ap.parse_args()

    base = json.loads(BASELINES.read_text())
    names = list(base["scenarios"])
    if args.only:
        names = [n for n in names if n == args.only]
        if not names:
            print("no scenario named %r" % args.only)
            return 2
    elif args.quick:
        names = names[:1]

    failures = 0
    for name in names:
        spec = base["scenarios"][name]
        print("\n== %s -- %s" % (name, spec.get("what", "")))
        ctx, err = run_scenario(name, spec, args.keep)
        if ctx is None:
            print("  FAIL  could not run: %s" % err)
            failures += 1
            continue
        for chk in spec["checks"]:
            fn = CHECKS.get(chk["check"])
            if fn is None:
                print("  ????  unknown check %r" % chk["check"])
                failures += 1
                continue
            if args.update and "floor" in chk:
                cur = _observed(ctx, chk)
                if cur is not None:
                    chk["floor"] = round(cur * base.get("update_margin", 0.5))
                    print("  set   %s floor -> %s" % (chk["stat"], chk["floor"]))
                    continue
            why = fn(ctx, chk)
            label = chk.get("name", chk["check"])
            if why:
                print("  FAIL  %-22s %s" % (label, why))
                failures += 1
            else:
                print("  ok    %s" % label)

    if args.update:
        BASELINES.write_text(json.dumps(base, indent=2) + "\n")
        print("\nbaselines updated -- review the diff before committing")
        return 0
    print("\n%s" % ("%d check(s) failed" % failures if failures else "all checks passed"))
    return 1 if failures else 0


def _observed(ctx, chk):
    import statistics
    key = chk.get("stat")
    if not key:
        return None
    vals = [s.get(key, 0) or 0 for s in ctx["finals"].values()]
    if not vals:
        return None
    return min(vals) if chk["check"] == "min_across_teams" else statistics.median(vals)


if __name__ == "__main__":
    sys.exit(main())
