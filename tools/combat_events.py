#!/usr/bin/env python3
"""Auto-flag the two patterns this project keeps finding by hand-grepping.

spending_timeline.py turns periodic stats into a CSV you can read a story out
of; composition.py aggregates that story across many games. Both still need a
human to notice "army went to zero" or "that lab got placed six times" by
scanning rows. This tool does the noticing:

  1. COLLAPSE events -- a team's armyReal (or mCon) drops by a large fraction,
     or fully wipes, between two consecutive periodic samples. Reports the
     time window, before/after values, and the `top` metal-sink string at the
     after-sample for context. This is exactly the by-hand pattern used this
     session to find team 0's ~10-11.5min collapse and team 1's ~14-16min
     death-spiral in matches/watch-comet-catcher-4v4-8.

  2. DUPLICATE-BUILD events -- the same factory unit type getting freshly
     placed more than once within a short time window for one player. Prefers
     parsing "<label> on field: <unit>" AiLog lines straight out of
     infolog.txt (exact unit names, exact frames) when the match directory
     has one; falls back to clustering mFactories jumps of similar size when
     it does not (tournament games rarely keep infologs). This is exactly the
     by-hand pattern used to find team 2's six corlab placements.

Reads the same result.json tree composition.py and spending_timeline.py do
(a single match dir or a tournament dir of many), so it works on either.

Usage:
    python tools/combat_events.py matches/<match>                # one match
    python tools/combat_events.py tournaments/<run> --spec Apex
    python tools/combat_events.py matches/<match> --out events.csv
    python tools/combat_events.py matches/<match> --collapse-frac 0.5
"""

from __future__ import annotations

import argparse
import collections
import csv
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# STANDING fields worth collapse-checking: current-state counters, not
# cumulative totals (see composition.py's STANDING set for why that split
# matters -- a cumulative field never "collapses", it just stops growing).
COLLAPSE_FIELDS = ["armyReal", "mCon"]

# "T1 lab on field: corlab" is the only label this AI logs today
# (factory.as:1613), but the pattern is written generic ("<label> on field:
# <unit>") so a future "T2 lab on field" or similar needs no change here.
FIELD_LINE_RE = re.compile(
    r"\[t=(?P<clock>[\d:.]+)]\[f=(?P<frame>\d+)]\s*"
    r"Skirmish AI <(?P<ainame>[^>]+)>:\s*"
    r"\[(?P<gm>[\d.]+)m t(?P<local>\d+)]\s*\w+:\s*"
    r"(?P<label>[\w ]+?) on field:\s*(?P<unit>\S+)"
)


def newest_tournament() -> Path | None:
    root = REPO / "tournaments"
    if not root.is_dir():
        return None
    runs = sorted((p for p in root.iterdir() if p.is_dir()),
                  key=lambda p: p.stat().st_mtime, reverse=True)
    return runs[0] if runs else None


def frame_to_min(frame: float) -> float:
    return round(frame / 1800.0, 2)  # 30 fps


def local_team_map(stats: list[dict]) -> dict[tuple[int, int], int]:
    """(ally, local index within that ally, sorted by team id) -> team id.

    infolog AiLog lines carry "tN" local to one AI instance (0..per-side-1),
    not the global 0-7 team id the stats rows use. Deriving the mapping from
    the *observed* team ids per ally (rather than assuming ally*4+local)
    survives per-side counts other than 4.
    """
    by_ally: dict[int, set[int]] = collections.defaultdict(set)
    for row in stats:
        ally = row.get("ally")
        team = row.get("team")
        if ally is None or team is None:
            continue
        by_ally[int(ally)].add(int(team))
    out = {}
    for ally, teams in by_ally.items():
        for local, team in enumerate(sorted(teams)):
            out[(ally, local)] = team
    return out


def ally_for_ainame(ainame: str, teams_meta: list[dict]) -> int | None:
    """Match an infolog 'Skirmish AI <...>' name to an ally index via the
    AI's own version string (e.g. 'apex', 'stable') -- the one substring both
    the log identity and result.json's teams[].version agree on."""
    low = ainame.lower()
    for i, t in enumerate(teams_meta):
        v = str(t.get("version", "")).lower()
        if v and v in low:
            return i
    return None


def find_collapses(stats_by_team: dict[int, list[dict]], spec_of_team: dict[int, str],
                    collapse_frac: float, min_before: float) -> list[dict]:
    events = []
    for team, rows in stats_by_team.items():
        rows = sorted(rows, key=lambda r: r.get("frame", 0))
        for field in COLLAPSE_FIELDS:
            prev = None
            for row in rows:
                cur = row.get(field)
                if cur is None:
                    continue
                if prev is not None:
                    before, before_row = prev
                    if before >= min_before:
                        drop = (before - cur) / before if before else 0
                        if drop >= collapse_frac:
                            events.append({
                                "kind": "collapse",
                                "team": team,
                                "spec": spec_of_team.get(team, "?"),
                                "field": field,
                                "t_before": frame_to_min(before_row.get("frame", 0)),
                                "t_after": frame_to_min(row.get("frame", 0)),
                                "val_before": before,
                                "val_after": cur,
                                "drop_pct": round(drop * 100, 1),
                                "top_after": row.get("top", ""),
                            })
                prev = (cur, row)
    return events


def find_duplicate_builds_from_stats(stats_by_team: dict[int, list[dict]],
                                      spec_of_team: dict[int, str],
                                      dup_window_min: float) -> list[dict]:
    """Fallback when no infolog is available: cluster mFactories jumps of
    similar size within a short window. Coarser than infolog parsing -- it
    cannot name the unit, only flag "something factory-ish was bought
    repeatedly" -- but it works from result.json alone."""
    events = []
    for team, rows in stats_by_team.items():
        rows = sorted(rows, key=lambda r: r.get("frame", 0))
        jumps = []  # (minute, delta)
        prev = None
        for row in rows:
            cur = row.get("mFactories")
            if cur is None:
                continue
            if prev is not None and cur > prev[0]:
                jumps.append((frame_to_min(row.get("frame", 0)), cur - prev[0]))
            prev = (cur, row)
        # group jumps of similar magnitude (within 15%) inside the window
        used = [False] * len(jumps)
        for i, (t_i, d_i) in enumerate(jumps):
            if used[i] or d_i <= 0:
                continue
            group = [(t_i, d_i)]
            used[i] = True
            for j in range(i + 1, len(jumps)):
                if used[j]:
                    continue
                t_j, d_j = jumps[j]
                if t_j - group[0][0] > dup_window_min:
                    break
                if d_i and abs(d_j - d_i) / d_i <= 0.15:
                    group.append((t_j, d_j))
                    used[j] = True
            if len(group) >= 2:
                events.append({
                    "kind": "duplicate_build_approx",
                    "team": team,
                    "spec": spec_of_team.get(team, "?"),
                    "unit": "(unknown -- no infolog; mFactories jump ~%.0f)" % d_i,
                    "count": len(group),
                    "times": [round(t, 1) for t, _ in group],
                })
    return events


def find_duplicate_builds_from_infolog(infolog: Path, teams_meta: list[dict],
                                        team_map: dict[tuple[int, int], int],
                                        spec_of_team: dict[int, str],
                                        dup_window_min: float) -> list[dict]:
    try:
        text = infolog.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return []
    # (team, unit) -> list of minute timestamps
    placements: dict[tuple[int, str], list[float]] = collections.defaultdict(list)
    for m in FIELD_LINE_RE.finditer(text):
        ainame = m.group("ainame")
        ally = ally_for_ainame(ainame, teams_meta)
        if ally is None:
            continue
        local = int(m.group("local"))
        team = team_map.get((ally, local))
        if team is None:
            continue
        unit = m.group("unit")
        placements[(team, unit)].append(float(m.group("gm")))

    events = []
    for (team, unit), times in placements.items():
        times = sorted(times)
        # sliding window: any run of >=2 placements within dup_window_min
        i = 0
        while i < len(times):
            j = i
            while j + 1 < len(times) and times[j + 1] - times[i] <= dup_window_min:
                j += 1
            if j > i:
                events.append({
                    "kind": "duplicate_build",
                    "team": team,
                    "spec": spec_of_team.get(team, "?"),
                    "unit": unit,
                    "count": j - i + 1,
                    "times": times[i:j + 1],
                })
            i = j + 1
    return events


def process_match(rj: Path, args) -> list[dict]:
    try:
        data = json.loads(rj.read_text(encoding="utf-8"))
    except Exception:
        return []
    res = data.get("result", {})
    if res.get("valid") is False:
        return []
    teams_meta = data.get("teams") or []
    stats = data.get("stats") or []
    if not teams_meta or not stats:
        return []

    spec_of_ally = {i: t.get("spec", f"ally{i}") for i, t in enumerate(teams_meta)}
    version_of_ally = {i: t.get("version", "") for i, t in enumerate(teams_meta)}

    stats_by_team: dict[int, list[dict]] = collections.defaultdict(list)
    spec_of_team: dict[int, str] = {}
    for row in stats:
        ally = row.get("ally")
        team = row.get("team")
        if ally is None or team is None:
            continue
        ally, team = int(ally), int(team)
        spec = spec_of_ally.get(ally)
        if args.spec and (not spec or args.spec.lower() not in spec.lower()):
            continue
        stats_by_team[team].append(row)
        spec_of_team[team] = spec or f"ally{ally}"

    if not stats_by_team:
        return []

    events = find_collapses(stats_by_team, spec_of_team, args.collapse_frac, args.min_army)

    infolog = rj.parent / "infolog.txt"
    if infolog.exists() and not args.no_infolog:
        team_map = local_team_map(stats)
        dup_events = find_duplicate_builds_from_infolog(
            infolog, teams_meta, team_map, spec_of_team, args.dup_window)
    else:
        dup_events = find_duplicate_builds_from_stats(
            stats_by_team, spec_of_team, args.dup_window)
    events.extend(dup_events)

    match_name = str(rj.parent.relative_to(rj.parent.parent)) if rj.parent.name else str(rj.parent)
    for e in events:
        e["match"] = match_name
    return events


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run", nargs="?", help="match or tournament directory; default: newest tournament")
    ap.add_argument("--spec", help="only players whose spec contains this substring (e.g. Apex)")
    ap.add_argument("--collapse-frac", type=float, default=0.6,
                     help="fraction drop in one sample window to flag as a collapse (default 0.6)")
    ap.add_argument("--min-army", type=float, default=300.0,
                     help="ignore collapses where the BEFORE value is under this (default 300; "
                          "an army of 40 dropping to 0 is not a finding)")
    ap.add_argument("--dup-window", type=float, default=3.0,
                     help="minutes within which repeat factory placements count as duplicate-build (default 3.0)")
    ap.add_argument("--no-infolog", action="store_true",
                     help="skip infolog.txt parsing even if present; use the mFactories-jump heuristic")
    ap.add_argument("--out", help="also write all events as CSV to this path")
    args = ap.parse_args()

    root = Path(args.run) if args.run else newest_tournament()
    if root is None or not root.exists():
        print("no matching run", file=sys.stderr)
        return 1

    all_events: list[dict] = []
    n_matches = 0
    for rj in sorted(root.rglob("result.json")):
        evs = process_match(rj, args)
        if evs:
            n_matches += 1
        all_events.extend(evs)

    if not all_events:
        print(f"no result.json with usable stats under {root} (or nothing crossed the thresholds)",
              file=sys.stderr)
        return 1

    collapses = [e for e in all_events if e["kind"] == "collapse"]
    dups = [e for e in all_events if e["kind"].startswith("duplicate_build")]

    print(f"{root}  --  {n_matches} match(es) scanned, "
          f"{len(collapses)} collapse event(s), {len(dups)} duplicate-build event(s)")
    print()

    if collapses:
        print("COLLAPSE EVENTS (>= %.0f%% drop in one sample, before >= %.0f)"
              % (args.collapse_frac * 100, args.min_army))
        for e in sorted(collapses, key=lambda e: (e["match"], e["t_before"])):
            wipe = " [FULL WIPE]" if e["val_after"] == 0 else ""
            print(f"  {e['match']}  team {e['team']} ({e['spec'][:32]})  {e['field']}"
                  f"  {e['val_before']:.0f} -> {e['val_after']:.0f}  (-{e['drop_pct']:.0f}%)"
                  f"  @ {e['t_before']:.1f}min -> {e['t_after']:.1f}min{wipe}")
            print(f"      top after: {e['top_after']}")
        print()

    if dups:
        print("DUPLICATE-BUILD EVENTS (same unit placed >1x within %.1f min)" % args.dup_window)
        for e in sorted(dups, key=lambda e: (e["match"], e["team"])):
            src = "infolog" if e["kind"] == "duplicate_build" else "mFactories-approx"
            times = ", ".join(f"{t:.1f}m" for t in e["times"])
            print(f"  {e['match']}  team {e['team']} ({e['spec'][:32]})  "
                  f"{e['unit']} x{e['count']}  [{src}]")
            print(f"      at: {times}")
        print()

    if args.out:
        fieldnames = ["match", "kind", "team", "spec", "field", "unit",
                      "t_before", "t_after", "val_before", "val_after",
                      "drop_pct", "top_after", "count", "times"]
        with open(args.out, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
            w.writeheader()
            for e in all_events:
                row = dict(e)
                if "times" in row:
                    row["times"] = " ".join(f"{t:.1f}" for t in row["times"])
                w.writerow(row)
        print(f"{len(all_events)} events -> {args.out}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
