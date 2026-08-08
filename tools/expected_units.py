#!/usr/bin/env python3
"""Do the units this AI is configured to build actually get built?

apexearth: "make sure that the units we expect to be created are actually
created." A build-weight table can carry a nonzero share for a unit that
never once gets constructed -- a disabled factory selected anyway
(legehovertank/leghp, both found this session by watching a game), a
resurrect-only unit gated behind a condition that never fires, a name that
no longer matches a unit in the current game tree. `tools/composition.py`'s
`top=` field only ever shows the 4 biggest spenders per sample, so a cheap
or rare unit never surfaces there even when something is structurally wrong.

This reads the `allBuilt=` field (every unit type with any metal spent,
added to `game-patches/gadgets/dev_stats_export.lua` alongside `top=` --
redeploy gadgets for it to appear in new matches; older result.json files
won't have it) and cross-references it against every unit with a nonzero
weight anywhere in that faction's factory.json/factory_leg.json tables.

Scope: only checks per-unit build weights INSIDE a chosen factory (the
"unit"/"land"/"air"/"water" tables). It does not check whether the factory
itself gets selected at all -- that is a separate mechanism (`importance`)
and a separate class of bug, the one behind the leghp fix earlier this
session (importance left nonzero on a land map for a water-only factory).
A unit reported "never built" here could also mean its OWN factory was
never chosen, not just that the unit lost out to its factory-mates.

Usage:
    python tools/expected_units.py <tournament-or-match-dir> --faction legion
    python tools/expected_units.py <run> --faction armada --spec BARbApex

--spec filters to specs containing that substring (default: BARbApex, i.e.
our own AI, not stock) so a mixed-faction batch only checks the side that
was actually configured to be that faction.
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CONFIG_DIR = REPO / "ai" / "apex" / "game-side" / "config" / "hard_aggressive"

FACTION_FILES = {
    "armada": ["factory.json"],
    "cortex": ["factory.json"],
    "legion": ["factory_leg.json"],
}
FACTION_PREFIX = {"armada": "arm", "cortex": "cor", "legion": "leg"}


def strip_comments(text: str) -> str:
    lines = []
    for line in text.split("\n"):
        idx = line.find("//")
        lines.append(line[:idx] if idx != -1 else line)
    return "\n".join(lines)


def load_json(path: Path) -> dict:
    return json.loads(strip_comments(path.read_text(encoding="utf-8")))


def configured_units(faction: str) -> dict[str, set[str]]:
    """unit name -> set of "<file>::<table>" locations where it carries nonzero weight."""
    prefix = FACTION_PREFIX[faction]
    found: dict[str, set[str]] = collections.defaultdict(set)
    for fname in FACTION_FILES[faction]:
        data = load_json(CONFIG_DIR / fname)
        for table_name, tbl in data.get("factory", {}).items():
            if not isinstance(tbl, dict) or "unit" not in tbl:
                continue
            units = tbl["unit"]
            for map_type in ("land", "air", "water"):
                rows = tbl.get(map_type)
                if not rows:
                    continue
                for tier_name, weights in rows.items():
                    for i, u in enumerate(units):
                        if not u.startswith(prefix):
                            continue
                        if i < len(weights) and weights[i] > 0:
                            found[u].add(f"{fname}::{table_name}.{map_type}.{tier_name}")
    return found


def newest_run(root: Path) -> Path:
    return root


def observed_units(root: Path, spec_filter: str) -> tuple[collections.Counter, int, int]:
    """unit name -> games it appeared in at least once; also (games_with_data, games_total)."""
    seen_per_game: collections.Counter = collections.Counter()
    games_total = 0
    games_with_data = 0
    for rj in sorted(root.rglob("result.json")):
        try:
            data = json.loads(rj.read_text(encoding="utf-8"))
        except Exception:
            continue
        teams = data.get("teams") or []
        stats = data.get("stats") or []
        if not teams or not stats:
            continue
        games_total += 1
        spec_of_ally = {i: t.get("spec", "") for i, t in enumerate(teams)}
        has_data = False
        game_units: set[str] = set()
        for row in stats:
            spec = spec_of_ally.get(int(row.get("ally", -1)), "")
            if spec_filter and spec_filter not in spec:
                continue
            raw = row.get("allBuilt", "")
            if not raw:
                continue
            has_data = True
            for part in str(raw).split(","):
                if ":" not in part:
                    continue
                name, _, _ = part.partition(":")
                game_units.add(name.strip())
        if has_data:
            games_with_data += 1
        for u in game_units:
            seen_per_game[u] += 1
    return seen_per_game, games_with_data, games_total


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run", type=Path, help="tournament or match directory")
    ap.add_argument("--faction", required=True, choices=list(FACTION_FILES))
    ap.add_argument("--spec", default="Apex", help="only count players whose spec contains this (default: Apex)")
    args = ap.parse_args()

    if not args.run.is_dir():
        print(f"not a directory: {args.run}", file=sys.stderr)
        return 1

    expected = configured_units(args.faction)
    seen, games_with_data, games_total = observed_units(args.run, args.spec)

    print(f"{args.run}  --  {games_total} game(s), {games_with_data} with allBuilt= data, spec filter '{args.spec}'")
    if games_with_data == 0:
        print("  No allBuilt= data found. Redeploy gadgets (tools/deploy_ai.py gadgets) and")
        print("  re-run matches -- older result.json files predate this field.")
        return 0

    missing = sorted(u for u in expected if seen.get(u, 0) == 0)
    present = sorted(u for u in expected if seen.get(u, 0) > 0)

    print(f"\n{len(expected)} unit(s) carry nonzero configured weight for {args.faction}:")
    print(f"  {len(present)} observed built at least once")
    print(f"  {len(missing)} NEVER observed built, despite nonzero weight\n")

    if missing:
        print("NEVER BUILT (check these first):")
        for u in missing:
            locs = ", ".join(sorted(expected[u])[:2])
            more = "" if len(expected[u]) <= 2 else f" (+{len(expected[u]) - 2} more)"
            print(f"  {u:20s}  weighted in: {locs}{more}")

    print("\nbuilt at least once, games seen in (out of %d):" % games_with_data)
    for u in present:
        print(f"  {u:20s}  {seen[u]}/{games_with_data}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
