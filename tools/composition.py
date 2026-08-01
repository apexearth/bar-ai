#!/usr/bin/env python3
"""What each side actually SPENT its metal on, aggregated over many games.

Win rate over a handful of games is noise in this repo -- a 10-game tournament
once swung 60% to 10% on an unchanged AI. Composition is not: "we built 3x the
nano turrets and half the army" is a fact about behaviour that survives a small
sample, because it is the same answer in every game rather than one coin flip.

Reads a tournament directory (or any tree of result.json), takes each player's
final stats row, and reports per side:

  * where the metal went, as a share of everything built
  * the units that ate the most metal, pooled across games
  * economy reach -- mex upgrades, advanced constructors, energy thrown away

Usage:
    python tools/composition.py                     # newest tournament
    python tools/composition.py tournaments/<run>   # a specific one
    python tools/composition.py matches/<match>     # a single match
"""

from __future__ import annotations

import collections
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Metal buckets that together account for what was built. mBuiltReal is the
# total; these are the parts worth separating when asking "did priorities slip".
BUCKETS = [
    ("factories", "mFactories"),
    ("constructors", "mCon"),
    ("army (real)", "armyReal"),
    ("army (cheap)", "armyCheap"),
]

REACH = [
    ("metal produced", "metalProduced"),
    ("metal built", "mBuiltReal"),
    ("T1 spend", "mT1"),
    ("T2 spend", "mT2"),
    ("T3 spend", "mT3"),
    ("mex upgrades", "t2Mex"),
    ("cons T1", "conT1"),
    ("cons T2", "conT2"),
    ("energy wasted", "energyExcess"),
    ("reclaimed", "mReclaim"),
]


def newest_tournament() -> Path | None:
    root = REPO / "tournaments"
    if not root.is_dir():
        return None
    runs = sorted((p for p in root.iterdir() if p.is_dir()),
                  key=lambda p: p.stat().st_mtime, reverse=True)
    return runs[0] if runs else None


def load(root: Path):
    """spec -> list of final stats rows, one per player per game."""
    per_spec: dict[str, list[dict]] = collections.defaultdict(list)
    games = 0
    for rj in sorted(root.rglob("result.json")):
        try:
            data = json.loads(rj.read_text(encoding="utf-8"))
        except Exception:
            continue
        res = data.get("result", {})
        if res.get("valid") is False:
            continue  # a run whose AngelScript did not compile says nothing
        teams = data.get("teams") or []
        stats = data.get("stats") or []
        if not teams or not stats:
            continue
        games += 1
        # teams[i] describes ALLY i, which is what makes side-swapped games
        # attribute correctly -- the tournament plays each pairing both ways.
        spec_of_ally = {i: t.get("spec", f"ally{i}") for i, t in enumerate(teams)}
        last: dict[tuple, dict] = {}
        for row in stats:
            last[(row["ally"], row["team"])] = row
        for (ally, _team), row in last.items():
            spec = spec_of_ally.get(int(ally))
            if spec:
                per_spec[spec].append(row)
    return per_spec, games


def top_units(rows: list[dict]) -> collections.Counter:
    """Pool the per-player `top` strings: 'armnanotc:2940,armavp:2900,...'."""
    c: collections.Counter = collections.Counter()
    for r in rows:
        for part in str(r.get("top", "")).split(","):
            if ":" not in part:
                continue
            name, _, val = part.partition(":")
            try:
                c[name.strip()] += float(val)
            except ValueError:
                pass
    return c


def main() -> int:
    arg = sys.argv[1] if len(sys.argv) > 1 else None
    root = Path(arg) if arg else newest_tournament()
    if root is None or not root.exists():
        print("no tournament or match directory found", file=sys.stderr)
        return 2

    per_spec, games = load(root)
    if not per_spec:
        print(f"no valid results under {root}", file=sys.stderr)
        return 2

    specs = sorted(per_spec)
    print(f"{root}  --  {games} valid game(s), "
          f"{sum(len(v) for v in per_spec.values())} player-games\n")

    w = 22
    print("WHERE THE METAL WENT (share of metal built, mean per player)")
    print("  " + "category".ljust(w) + "".join(s[:26].rjust(28) for s in specs))
    for label, key in BUCKETS:
        cells = []
        for s in specs:
            rows = per_spec[s]
            built = sum(r.get("mBuiltReal", 0) for r in rows) or 1
            share = sum(r.get(key, 0) for r in rows) / built
            cells.append(f"{share*100:26.1f}%")
        print("  " + label.ljust(w) + "".join(cells))

    print("\nECONOMY REACH (mean per player)")
    print("  " + "metric".ljust(w) + "".join(s[:26].rjust(28) for s in specs))
    for label, key in REACH:
        cells = []
        for s in specs:
            rows = per_spec[s]
            mean = sum(r.get(key, 0) for r in rows) / max(len(rows), 1)
            cells.append(f"{mean:27,.0f} ")
        print("  " + label.ljust(w) + "".join(cells))

    for s in specs:
        c = top_units(per_spec[s])
        total = sum(c.values()) or 1
        print(f"\nTOP METAL SINKS -- {s}")
        for name, val in c.most_common(12):
            print(f"  {name:<18} {val:10,.0f}  {val/total*100:5.1f}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
