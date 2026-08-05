#!/usr/bin/env python3
"""Per-player spending and composition over time, as CSV.

composition.py answers "what did we build, in total, across many games" --
good for confirming a behaviour change survives noise. It cannot answer "what
changed sixty seconds before we started losing", because it only ever reads
the LAST or PEAK sample. This tool keeps every periodic sample instead, one
CSV row per (game, player, sample), so a single match can be read as a
timeline: did army spend stop while eco spend kept climbing, did a T1->T2
transition line up with the collapse, when did mex count start falling.

Reads the same result.json tree composition.py does (a single match dir or a
tournament dir), so it works on either.

Usage:
    python tools/spending_timeline.py matches/<match>              # one match
    python tools/spending_timeline.py tournaments/<run> --spec Apex
    python tools/spending_timeline.py matches/<match> --out t.csv

Columns:
    match, frame, minute, ally, team, spec
    -- STANDING (current state, not cumulative): mex, aaT1, conT1, conT2,
       mCon, armyReal, armyCheap
    -- CUMULATIVE, raw running total: mFactories, mDefence, mT1, mT2, mT3,
       mReclaim, mRezSpend, mBuiltReal, metalProduced
    -- CUMULATIVE, delta since the previous sample for this player (the
       actual "spent in this window" answer, prefixed d_): d_mFactories,
       d_mDefence, d_mT1, d_mT2, d_mT3, d_mReclaim, d_mRezSpend, d_mBuiltReal
    -- top: the engine's own top-4 metal sinks, cumulative-to-date string
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

STANDING = ["mex", "aaT1", "conT1", "conT2", "mCon", "armyReal", "armyCheap"]
CUMULATIVE = ["mFactories", "mDefence", "mT1", "mT2", "mT3", "mReclaim",
              "mRezSpend", "mBuiltReal", "metalProduced"]


def newest_tournament() -> Path | None:
    root = REPO / "tournaments"
    if not root.is_dir():
        return None
    runs = sorted((p for p in root.iterdir() if p.is_dir()),
                  key=lambda p: p.stat().st_mtime, reverse=True)
    return runs[0] if runs else None


def rows_for(root: Path, spec_filter: str | None):
    for rj in sorted(root.rglob("result.json")):
        try:
            data = json.loads(rj.read_text(encoding="utf-8"))
        except Exception:
            continue
        res = data.get("result", {})
        if res.get("valid") is False:
            continue
        teams = data.get("teams") or []
        stats = data.get("stats") or []
        if not teams or not stats:
            continue
        spec_of_ally = {i: t.get("spec", f"ally{i}") for i, t in enumerate(teams)}
        match_name = rj.parent.relative_to(root) if rj.parent != root else rj.parent.name
        prev: dict[tuple, dict] = {}
        # Stable order: frame ascending PER PLAYER, so deltas are always
        # forward-in-time for the same player. Keying/sorting by "ally" alone
        # would interleave all 4 players on a side (ally is the 0/1 side
        # indicator; "team" is the actual per-player id, 0-7 in a 4v4) and
        # diff one player's cumulative total against a DIFFERENT player's --
        # caught by negative deltas on fields that can only go up.
        for row in sorted(stats, key=lambda r: (r.get("team", 0), r.get("frame", 0))):
            ally = row.get("ally")
            spec = spec_of_ally.get(int(ally)) if ally is not None else None
            if spec is None:
                continue
            if spec_filter and spec_filter.lower() not in spec.lower():
                continue
            key = (str(match_name), row.get("team"))
            frame = row.get("frame", 0)
            out = {
                "match": str(match_name),
                "frame": frame,
                "minute": round(frame / 1800.0, 2),  # 30 fps
                "ally": ally,
                "team": row.get("team"),
                "spec": spec,
                "reason": row.get("reason"),
            }
            for k in STANDING:
                out[k] = row.get(k)
            for k in CUMULATIVE:
                out[k] = row.get(k)
            p = prev.get(key)
            for k in CUMULATIVE:
                cur = row.get(k)
                base = p.get(k) if p else None
                out["d_" + k] = (cur - base) if (cur is not None and base is not None) else None
            out["top"] = row.get("top", "")
            prev[key] = row
            yield out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run", nargs="?", help="match or tournament directory; default: newest tournament")
    ap.add_argument("--spec", help="only rows whose spec contains this substring (e.g. Apex)")
    ap.add_argument("--out", help="CSV path; default: <run>/spending_timeline.csv")
    args = ap.parse_args()

    root = Path(args.run) if args.run else newest_tournament()
    if root is None or not root.exists():
        print("no matching run", file=sys.stderr)
        return 1

    out_rows = list(rows_for(root, args.spec))
    if not out_rows:
        print("no periodic stats found under", root, file=sys.stderr)
        return 1

    out_path = Path(args.out) if args.out else (root / "spending_timeline.csv")
    fieldnames = list(out_rows[0].keys())
    with out_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(out_rows)

    print(f"{len(out_rows)} rows -> {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
