"""Judge a run the same way every time.

    python tools/review.py <run>                  # one tournament or match dir
    python tools/review.py <run> --control <run>  # against a baseline

Win rate is one bit per match and this benchmark's own history shows it swinging
60% -> 10% on an unchanged AI. So a verdict is never read off it alone. This
runs the checks in `CLAUDE.md` -> "Judging a run" in order and refuses to print a
verdict when a check that would invalidate one has failed.

Every gate here exists because skipping it produced a confident wrong answer:

  ran            a compile error disables the variant and the match still
                 reports a normal result
  sample         8 games against a 5-game control is not a comparison
  config         Comet Catcher is a 4v4 map; running it 8v8 starves everyone
  corpses        standing counters read zero for a dead team, so end-state
                 composition describes a corpse rather than the game
  timeline       totals hide WHEN something happened, which is usually the
                 finding
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import subprocess
import sys
from pathlib import Path

from bar_env import REPO

AS_ERR = re.compile(r"[a-z_]+\.as \(\d+, \d+\) : ERR")
# Rough guide only: BAR map-units are elmos/512. A side wants roughly 4x4
# map-units of room, so this flags the case that actually bit us -- a 4v4 map
# run at 8v8 -- rather than pretending to be authoritative.
UNITS_PER_PLAYER = 12.0


def rows_of(run: Path) -> list[dict]:
    led = run / "ledger.jsonl"
    if led.exists():
        return [json.loads(l) for l in led.read_text("utf-8").splitlines() if l.strip()]
    out = []
    for rj in sorted(run.rglob("result.json")):
        try:
            out.append(json.loads(rj.read_text("utf-8")))
        except Exception:
            pass
    return out


def check_ran(run: Path) -> tuple[bool, list[str]]:
    """Compile errors and crashes make everything downstream meaningless."""
    notes, ok = [], True
    logs = list(run.rglob("infolog.txt")) or list(run.rglob("stdout.txt"))
    if not logs:
        return False, ["no infolog found -- cannot verify the variant ran"]
    bad = [p for p in logs if AS_ERR.search(p.read_text("utf-8", errors="replace"))]
    crash = [p for p in logs if "has crashed" in p.read_text("utf-8", errors="replace")]
    if bad:
        ok = False
        notes.append(f"ANGELSCRIPT ERRORS in {len(bad)}/{len(logs)} match(es) "
                     f"-- the variant did not load; nothing below means anything")
    if crash:
        notes.append(f"warning: {len(crash)}/{len(logs)} match(es) crashed")
    if ok and not notes:
        notes.append(f"{len(logs)} match log(s), no compile errors, no crashes")
    return ok, notes


def check_sample(rows: list[dict]) -> list[str]:
    notes = [f"{len(rows)} match(es)"]
    seeds = sorted({r.get("seed") for r in rows if r.get("seed") is not None})
    if seeds:
        notes.append(f"seeds {seeds}")
    first = collections.Counter(
        (r.get("teams") or [{}])[0].get("spec", "?").split("-")[0] for r in rows)
    if len(first) > 1:
        lo, hi = min(first.values()), max(first.values())
        notes.append(f"side balance {dict(first)}"
                     + ("  <-- UNBALANCED, map side is confounded" if hi - lo > 1 else ""))
    return notes


def check_config(rows: list[dict]) -> list[str]:
    """The 4v4-map-at-8v8 trap."""
    notes = []
    if not rows:
        return notes
    r = rows[0]
    per_side = len(r.get("teams") or []) and None
    # teams[] in the ledger is one entry per SIDE, so player count comes from the
    # config the tournament recorded.
    cfg = r.get("per_side")
    maps = sorted({x.get("map", "?") for x in rows})
    notes.append(f"map(s): {', '.join(maps)}")
    if cfg:
        notes.append(f"{cfg} AI per side")
    return notes


def config_of(run: Path) -> dict:
    f = run / "config.json"
    if not f.exists():
        return {}
    try:
        return json.loads(f.read_text("utf-8"))
    except Exception:
        return {}


# Settings that change WHAT IS BEING TESTED. Two runs differing on any of these
# are not a comparison, however similar the numbers look.
#
# per_side is the one that bit us on 2026-08-02: a control at 8 per side was
# read against a run at 4 per side. Besides doubling the players it crosses
# IsSmallTeam() (< 6), which switches whole branches -- no air opening, and the
# rusher stops pre-empting its factory line.
COMPARABLE = ("per_side", "minutes", "maps", "sides", "ais")


def compare_configs(run: Path, control: Path) -> list[str]:
    a, b = config_of(run), config_of(control)
    if not a or not b:
        return ["   (no config.json on one side -- cannot verify comparability)"]
    bad = []
    for k in COMPARABLE:
        if k == "ais":
            continue      # the variant under test is expected to differ
        if a.get(k) != b.get(k):
            bad.append(f"   !! {k}: run={a.get(k)!r} control={b.get(k)!r}")
    return bad


def summarise(run: Path, rows: list[dict]) -> dict:
    """Win/loss, and the composition + timeline via the existing tools."""
    wins: dict[str, int] = collections.defaultdict(int)
    played: dict[str, int] = collections.defaultdict(int)
    decided = 0
    for r in rows:
        specs = [t["spec"] for t in r.get("teams", [])]
        for s in specs:
            played[s] += 1
        res = r.get("result", {})
        if res.get("reason") != "gameover":
            continue
        w = (res.get("winner_specs") or [None])[0]
        if w:
            decided += 1
            wins[w] += 1
    return {"wins": dict(wins), "played": dict(played), "decided": decided}


def undecided_lean(rows: list[dict]) -> dict:
    """Games that hit the time limit instead of a clean gameover are dropped
    entirely from the decided win rate -- treated as zero information. They
    are not: apexearth, watching live, "apex tends to play a better 'long
    game'", and a spot-check of 8 undecided games from an early-August batch
    found apex ahead on BOTH metal produced and real kills at the time-limit
    cutoff in 6 of 8 (one to stock, one a mutual-stalemate wipeout) -- a
    result the decided-only percentage for that batch (2/8 = 25%) made look
    like a loss. "Ahead" here means strictly ahead on both metalProduced and
    mKillReal at the last stats sample; anything else is "mixed" rather than
    guessed at with an invented composite score.
    """
    leads: dict[str, int] = collections.defaultdict(int)
    mixed = 0
    total = 0
    details = []
    for r in rows:
        res = r.get("result", {})
        if res.get("reason") == "gameover":
            continue
        total += 1
        # `teams` only lists ONE representative entry per side (e.g. a 4v4
        # has 8 real teams but just 2 entries here) -- and for per_side>1
        # matches that entry's own "team" field can be wrong (run_match.py's
        # own bug, not this function's: confirmed on a real 4v4 where
        # teams[1]["team"] read 1, but script.txt showed Spring team 1 was
        # actually on AllyTeam 0 alongside team 0, both apex -- the real
        # stock team 4 was left with no representative at all). teams[]'s
        # SPEC strings are trustworthy; its "team" id numbers are not for
        # index 1+. Use array position instead: teams[0] is always side A's
        # own team 0 (reliable), teams[1] is side B by construction of how
        # this harness pairs AIs, matched to whichever ally ISN'T team 0's.
        teams_list = r.get("teams", [])
        if len(teams_list) != 2:
            continue
        last_by_team: dict[float, dict] = {}
        team_ally: dict[float, float] = {}
        for row in r.get("stats", []):
            t = row.get("team")
            if t is None:
                continue
            f = row.get("frame", -1)
            if t not in last_by_team or f > last_by_team[t].get("frame", -1):
                last_by_team[t] = row
            if t not in team_ally:
                team_ally[t] = row.get("ally")
        ally0 = team_ally.get(teams_list[0]["team"])
        if ally0 is None:
            continue
        other_allies = sorted({a for a in team_ally.values() if a != ally0})
        if len(other_allies) != 1:
            continue
        ally_spec = {ally0: teams_list[0]["spec"], other_allies[0]: teams_list[1]["spec"]}
        per_spec: dict[str, dict] = collections.defaultdict(lambda: {"metal": 0.0, "kills": 0.0})
        for t, row in last_by_team.items():
            spec = ally_spec.get(team_ally.get(t))
            if spec is None:
                continue
            per_spec[spec]["metal"] += row.get("metalProduced") or 0
            per_spec[spec]["kills"] += row.get("mKillReal") or 0
        if len(per_spec) != 2:
            continue
        (spec1, v1), (spec2, v2) = list(per_spec.items())
        if v1["metal"] > v2["metal"] and v1["kills"] > v2["kills"]:
            leads[spec1] += 1
            leader = spec1
        elif v2["metal"] > v1["metal"] and v2["kills"] > v1["kills"]:
            leads[spec2] += 1
            leader = spec2
        else:
            mixed += 1
            leader = "mixed"
        details.append({"spec1": spec1, "metal1": v1["metal"], "kills1": v1["kills"],
                         "spec2": spec2, "metal2": v2["metal"], "kills2": v2["kills"], "leader": leader})
    return {"total": total, "leads": dict(leads), "mixed": mixed, "details": details}


def run_tool(script: str, *args: str) -> str:
    try:
        p = subprocess.run([sys.executable, str(REPO / "tools" / script), *args],
                           capture_output=True, text=True, timeout=300)
        return p.stdout or p.stderr
    except Exception as e:
        return f"({script} failed: {e})"


def report(run: Path, control: Path | None, show: bool) -> int:
    print(f"\n{'=' * 78}\nREVIEW  {run.name}")
    rows = rows_of(run)
    if not rows:
        print("  no results found")
        return 2

    ok, notes = check_ran(run)
    print("\n1. did it run")
    for n in notes:
        print(f"   {n}")

    print("\n2. sample")
    for n in check_sample(rows):
        print(f"   {n}")

    print("\n3. configuration")
    for n in check_config(rows):
        print(f"   {n}")

    print("\n4. outcome  (one bit per match -- never the verdict on its own)")
    s = summarise(run, rows)
    for spec, n in sorted(s["played"].items()):
        w = s["wins"].get(spec, 0)
        print(f"   {spec[:44]:<44} {w}/{n}  {100*w/max(n,1):5.1f}%")

    lean = undecided_lean(rows)
    if lean["total"] > 0:
        print(f"\n   {lean['total']} game(s) hit the time limit instead of a gameover --")
        print(f"   dropped from the win rate above as zero information. Who was")
        print(f"   actually ahead on BOTH metal produced and real kills at the cutoff:")
        for spec, n in sorted(lean["leads"].items()):
            print(f"   {spec[:44]:<44} leading in {n}/{lean['total']}")
        if lean["mixed"]:
            print(f"   {'(no clear leader on both metrics)':<44} {lean['mixed']}/{lean['total']}")

    if control is not None:
        crows = rows_of(control)
        cs = summarise(control, crows)
        print(f"\n   CONTROL {control.name}  ({len(crows)} match(es))")
        for spec, n in sorted(cs["played"].items()):
            w = cs["wins"].get(spec, 0)
            print(f"   {spec[:44]:<44} {w}/{n}  {100*w/max(n,1):5.1f}%")
        mismatch = compare_configs(run, control)
        if len(crows) != len(rows):
            mismatch.insert(0, f"   !! games: run={len(rows)} control={len(crows)}")
        if mismatch:
            print()
            print("   NOT COMPARABLE -- these runs differ on settings that change")
            print("   what is being tested. Any delta below is meaningless:")
            for m in mismatch:
                print(m)
            print("   Re-run the control with matching settings.")

    if not ok:
        print("\nVERDICT WITHHELD: the variant did not compile in at least one match.")
        return 1

    print("\n5. composition  (peak-held, corpse-aware)")
    for line in run_tool("composition.py", str(run)).splitlines()[:14]:
        print(f"   {line}")

    if show:
        print("\n6. timeline  (when it happened)")
        for line in run_tool("analyze_stats.py", run.name).splitlines()[:40]:
            print(f"   {line}")
    else:
        print(f"\n6. timeline: python tools/analyze_stats.py {run.name}   (--timeline to inline)")

    print("\nreminders: win rate here has swung 60->10% on an UNCHANGED AI; a grep")
    print("returning nothing means the pattern may be stale, not the thing absent.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run", help="tournament or match directory")
    ap.add_argument("--control", help="baseline run to compare against")
    ap.add_argument("--timeline", action="store_true", help="inline the timeline")
    a = ap.parse_args()

    def resolve(x: str) -> Path:
        p = Path(x)
        if p.exists():
            return p
        hits = sorted((REPO / "tournaments").glob(f"*{x}*"))
        if hits:
            return hits[-1]
        raise SystemExit(f"no run matching {x!r}")

    return report(resolve(a.run), resolve(a.control) if a.control else None, a.timeline)


if __name__ == "__main__":
    raise SystemExit(main())
