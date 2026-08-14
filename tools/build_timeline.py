#!/usr/bin/env python3
"""What buildings did we actually produce, and when.

apexearth wants to ask "in the first 10 minutes, exactly what buildings did we
produce" and get a real answer. `composition.py` and `spending_timeline.py`
report metal spent in named buckets (mFactories, mDefence, mCon...) and the
engine's own top-4 `top=` sinks -- useful for judging priorities, useless for
"list every building type, with a count, in this window", because a bucket
mixes many unit types and `top=`/`allBuilt=` only carry CUMULATIVE METAL per
type sampled every 2 game-minutes, not a count and not an exact timestamp.

This reads a NEW per-event line, `[BARAI_BUILD]`, added to
game-patches/gadgets/dev_stats_export.lua's `UnitFinished` hook: one line per
completed building (`ud.isBuilding`, so mobile army units are excluded by
construction), with the exact game frame/minute, unit name and cost. That
gives an exact answer for ANY window, not just the 2-minute snapshot grid.

Requires `python tools/deploy_ai.py gadgets` to have been run AFTER this line
was added -- older matches' infolog.txt predate it and will report zero
events; this tool says so rather than printing an empty table silently.

Usage:
    python tools/build_timeline.py matches/<match>                 # first 10 min, both sides
    python tools/build_timeline.py matches/<match> --minutes 15
    python tools/build_timeline.py matches/<match> --window 10,20   # minute 10 to 20 only
    python tools/build_timeline.py tournaments/<run> --spec Apex    # pooled across games
"""
from __future__ import annotations

import argparse
import collections
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402

REPO = Path(__file__).resolve().parent.parent

BUILD_RE = re.compile(
    r"\[BARAI_BUILD\] team=(\d+) ally=(\d+) frame=(\d+) min=([\d.]+) unit=(\S+) cost=(\d+)")


def newest_under(root: Path) -> Path | None:
    if not root.is_dir():
        return None
    runs = sorted((p for p in root.iterdir() if p.is_dir()),
                  key=lambda p: p.stat().st_mtime, reverse=True)
    return runs[0] if runs else None


def match_dirs(root: Path) -> list[Path]:
    """A single match dir, or every t*/ match under a tournament dir."""
    sub = root / "matches"
    if sub.is_dir():
        found = sorted(sub.glob("t*"))
        if found:
            return found
    return [root]


def spec_of_ally(mdir: Path) -> dict[int, str]:
    rj = mdir / "result.json"
    if not rj.exists():
        return {}
    try:
        data = json.loads(rj.read_text(encoding="utf-8"))
    except Exception:
        return {}
    teams = data.get("teams") or []
    return {i: t.get("spec", f"ally{i}") for i, t in enumerate(teams)}


def events_of(mdir: Path):
    """Every [BARAI_BUILD] event in this match, as dicts."""
    log = mdir / "infolog.txt"
    if not log.exists():
        return []
    text = log.read_text("utf-8", errors="replace")
    out = []
    for m in BUILD_RE.finditer(text):
        team, ally, frame, minute, unit, cost = m.groups()
        out.append({
            "team": int(team), "ally": int(ally), "frame": int(frame),
            "minute": float(minute), "unit": unit, "cost": int(cost),
        })
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run", nargs="?", help="match or tournament dir; default: newest under matches/")
    ap.add_argument("--minutes", type=float, default=10.0,
                     help="report window [0, MINUTES]; default 10 (ignored if --window given)")
    ap.add_argument("--window", help="explicit 'start,end' minute range, e.g. 5,15")
    ap.add_argument("--spec", help="only specs containing this substring (e.g. Apex)")
    args = ap.parse_args()

    root = Path(args.run) if args.run else newest_under(REPO / "matches")
    if root is None or not root.exists():
        print("no matching run", file=sys.stderr)
        return 1

    if args.window:
        lo_s, _, hi_s = args.window.partition(",")
        lo, hi = float(lo_s), float(hi_s)
    else:
        lo, hi = 0.0, args.minutes

    mdirs = match_dirs(root)
    # spec -> unit -> {count, cost, first, last}
    agg: dict[str, dict[str, dict]] = collections.defaultdict(
        lambda: collections.defaultdict(lambda: {"count": 0, "cost": 0, "first": None, "last": None}))
    total_events = 0
    games_with_events = 0

    for mdir in mdirs:
        smap = spec_of_ally(mdir)
        evs = events_of(mdir)
        if evs:
            games_with_events += 1
        for e in evs:
            total_events += 1
            if not (lo <= e["minute"] <= hi):
                continue
            spec = smap.get(e["ally"], f"ally{e['ally']}")
            if args.spec and args.spec.lower() not in spec.lower():
                continue
            row = agg[spec][e["unit"]]
            row["count"] += 1
            row["cost"] += e["cost"]
            row["first"] = e["minute"] if row["first"] is None else min(row["first"], e["minute"])
            row["last"] = e["minute"] if row["last"] is None else max(row["last"], e["minute"])

    print(f"{root}  --  {len(mdirs)} match(es), {games_with_events} with [BARAI_BUILD] data, "
          f"{total_events} total events")
    print(f"window: minute {lo:.1f} - {hi:.1f}"
          + (f", spec filter '{args.spec}'" if args.spec else ""))

    if games_with_events == 0:
        print("\nNo [BARAI_BUILD] events found. This telemetry line was added to")
        print("game-patches/gadgets/dev_stats_export.lua and needs")
        print("  python tools/deploy_ai.py gadgets")
        print("run, then a fresh match, before it appears -- older matches predate it.")
        return 0

    if not agg:
        print("\nNo buildings completed in this window (check --minutes / --window).")
        return 0

    for spec in sorted(agg):
        units = agg[spec]
        total_count = sum(u["count"] for u in units.values())
        total_metal = sum(u["cost"] for u in units.values())
        print(f"\n{spec}  --  {total_count} building(s), {total_metal:,} metal")
        print(f"  {'unit':<20}{'count':>6}{'metal':>10}{'first min':>11}{'last min':>11}")
        for name, u in sorted(units.items(), key=lambda kv: -kv[1]["count"]):
            print(f"  {name:<20}{u['count']:>6}{u['cost']:>10,}"
                  f"{u['first']:>11.2f}{u['last']:>11.2f}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
