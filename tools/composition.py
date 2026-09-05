#!/usr/bin/env python3
"""What each side actually SPENT its metal on, aggregated over many games.

Win rate over a handful of games is noise in this repo -- a 10-game tournament
once swung 60% to 10% on an unchanged AI. Composition is not: "we built 3x the
nano turrets and half the army" is a fact about behaviour that survives a small
sample, because it is the same answer in every game rather than one coin flip.

Reads a tournament directory (or any tree of result.json), takes each player's
final stats row, and reports per side:

  * where the metal went, as a share of everything built
  * the units that ate the most metal, pooled across games -- EVERY def, cheap
    ones included; see top_units() for the faction-sized hole that fixed
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
# Counters that only ever go UP. The last sample is the whole game, so reading
# it at game end is correct.
CUMULATIVE = {
    "metalProduced", "metalUsed", "metalExcess", "energyProduced", "energyUsed",
    "energyExcess", "damageDealt", "damageReceived", "mBuiltReal", "mFactories",
    "mDefence", "mLostReal", "mLostCheap", "mKillReal", "mKillCheap", "mReclaim",
    "mRezSpend", "mT1", "mT2", "mT3", "t2Mex",
}

# Counters that describe what a player is HOLDING right now. These go to zero
# when a team dies, so the last sample of a lost game is a corpse, not a story.
#
# This cost a wrong conclusion on 2026-08-02: end-state read "cons T1 1 vs 10,
# army 4.4% vs 26.1%" and was reported as "apex builds almost nothing". The
# 2-minute timeline showed the opposite -- apex held MORE constructors than
# stock all game (11.1 vs 7.1 at minute 20) and a comparable army. It lost on
# trading, not production, and the diagnosis was backwards for an hour.
#
# So these are reported at their PEAK across the game, never at the end.
STANDING = {"conT1", "conT2", "mCon", "armyReal", "armyCheap"}

BUCKETS = [
    ("factories", "mFactories"),
    ("static defence", "mDefence"),
    ("constructors", "mCon"),
    ("army (real)", "armyReal"),
    ("army (cheap)", "armyCheap"),
]

REACH = [
    ("metal produced", "metalProduced"),
    ("metal built", "_mBuiltAll"),
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
        peak: dict[tuple, dict] = {}
        for row in stats:
            key = (row["ally"], row["team"])
            last[key] = row
            acc = peak.setdefault(key, {})
            for k in STANDING:
                v = row.get(k)
                if v is not None:
                    acc[k] = max(acc.get(k, 0), v)
        for key, row in last.items():
            spec = spec_of_ally.get(int(key[0]))
            if not spec:
                continue
            merged = dict(row)
            merged.update(peak.get(key, {}))   # STANDING -> peak, not final
            # A player holding no army and no constructors at the end was wiped;
            # its final row is a corpse. Recorded so the report can say so.
            merged["_died"] = (row.get("armyReal", 0) == 0
                               and row.get("conT1", 0) == 0
                               and row.get("mBuiltReal", 0) > 0)
            # EVERYTHING BUILT, not just the defs over spamCost. mBuiltReal is
            # the exporter's >= 120-metal total, so using it as the share
            # denominator silently drops Grunts, Ticks, Pawns and the Cortex
            # rocket bot out of "what did we spend on" -- and then reports
            # "army (cheap)" as a share of a total that does not contain it.
            # apexearth: "Those are still valid numbers of the army."
            merged["_cheapM"] = sum(
                float(p.partition(":")[2] or 0)
                for p in str(row.get("cheapBuilt", "")).split(",") if ":" in p)
            merged["_mBuiltAll"] = row.get("mBuiltReal", 0) + merged["_cheapM"]
            per_spec[spec].append(merged)
    return per_spec, games


def _pool(rows: list[dict], key: str, into: collections.Counter) -> None:
    """Add one 'name:metal,name:metal,...' field of every row into a counter."""
    for r in rows:
        for part in str(r.get(key, "")).split(","):
            if ":" not in part:
                continue
            name, _, val = part.partition(":")
            try:
                into[name.strip()] += float(val)
            except ValueError:
                pass


def top_units(rows: list[dict]) -> tuple[collections.Counter, set[str]]:
    """Pool every def a side spent metal on. Returns (metal per def, cheap names).

    THREE fields, because one of them alone is a lie in two different ways.
    `top=` is the top FOUR defs per player-game, so pooling it across games
    over-weights whatever happened to place in each game's top four. And the
    exporter splits by cost: `dev_stats_export.lua` diverts every def under
    `spamCost` (120 metal) into `cheapBuilt=` and out of `allBuilt=`/`top=`
    entirely.

    That split deleted a whole faction's main combat unit from this report.
    corstorm (Aggravator, the Cortex T1 rocket bot) is 110 metal and armrock
    (Rocketeer, the Armada one) is 120 -- so the same unit class was visible for
    one faction and invisible for the other, and on 2026-09-05 this table was
    read as "Cortex builds no rocket bots" when corstorm was outspending the
    Thug 4.6:1 and winning 129 produce elections to 53.
    """
    c: collections.Counter = collections.Counter()
    # allBuilt is the complete >= spamCost list; top is its truncated top-4 and
    # is only the fallback for runs recorded before allBuilt existed.
    _pool(rows, "allBuilt" if any(r.get("allBuilt") for r in rows) else "top", c)
    cheap: collections.Counter = collections.Counter()
    _pool(rows, "cheapBuilt", cheap)
    c.update(cheap)
    return c, set(cheap)


def unit_counts(rows: list[dict]) -> collections.Counter:
    """Pool `unitCount=` -- how MANY of each def were made, chaff included.

    apexearth: "Why don't we want to see how many grunts and ticks we make and
    stuff like that? Those are still valid numbers of the army." Metal alone
    answers a different question: 40 Ticks and one Sheldon are the same number
    of metal and nothing like the same army.
    """
    c: collections.Counter = collections.Counter()
    for r in rows:
        for part in str(r.get("unitCount", "")).split(","):
            if ":" not in part:
                continue
            name, _, val = part.partition(":")
            try:
                c[name.strip()] += int(float(val))
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
          f"{sum(len(v) for v in per_spec.values())} player-games")

    # How many players ended the game dead. Their FINAL standing counters are
    # zero, which is why the tables below use peaks for those.
    for _sp in specs:
        _rows = per_spec[_sp]
        _dead = sum(1 for r in _rows if r.get("_died"))
        if _dead:
            print(f"  note: {_dead}/{len(_rows)} {_sp[:30]} player-games ended wiped out")
    print("  standing counters (constructors, army) are PEAK held;"
          " cumulative (metal, kills) are end-state.")
    print()

    w = 22
    print("WHERE THE METAL WENT (PEAK army/cons over cumulative built,"
          " cheap units included)")
    print("  " + "category".ljust(w) + "".join(s[:26].rjust(28) for s in specs))
    for label, key in BUCKETS:
        cells = []
        for s in specs:
            rows = per_spec[s]
            built = sum(r.get("_mBuiltAll", 0) for r in rows) or 1
            share = sum(r.get(key, 0) for r in rows) / built
            cells.append(f"{share*100:26.1f}%")
        print("  " + label.ljust(w) + "".join(cells))

    print("\nECONOMY REACH (mean per player; cons/army = PEAK held)")
    print("  " + "metric".ljust(w) + "".join(s[:26].rjust(28) for s in specs))
    for label, key in REACH:
        cells = []
        for s in specs:
            rows = per_spec[s]
            mean = sum(r.get(key, 0) for r in rows) / max(len(rows), 1)
            cells.append(f"{mean:27,.0f} ")
        print("  " + label.ljust(w) + "".join(cells))

    print("\nUNITS MADE (total across all games; every def, chaff included)")
    for s in specs:
        n = unit_counts(per_spec[s])
        line = ", ".join(f"{k} {v:,}" for k, v in n.most_common(16))
        print(f"  {s[:30]}: {line if line else '(no unitCount= in these runs)'}")

    for s in specs:
        c, cheap = top_units(per_spec[s])
        total = sum(c.values()) or 1
        spam = next((r.get("spamCost") for r in per_spec[s] if r.get("spamCost")), 0)
        print(f"\nTOP METAL SINKS -- {s}")
        for name, val in c.most_common(14):
            mark = " *" if name in cheap else ""
            print(f"  {name:<18} {val:10,.0f}  {val/total*100:5.1f}%{mark}")
        if cheap:
            print(f"  * under spamCost {spam:,.0f} metal -- counted as"
                  " 'army (cheap)' above, not in mBuiltReal")
    return 0


if __name__ == "__main__":
    sys.exit(main())
