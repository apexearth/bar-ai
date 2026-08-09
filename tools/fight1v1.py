#!/usr/bin/env python3
"""Army trade efficiency across a set of 1v1 games, for A/B-ing combat changes.

The arena isolates a symmetric fight and found us at parity there, so it cannot
see the thing that actually costs us games: WHICH fights we take. That only
shows up in a real match, where army K/D in metal is the direct measure -- over
six 20-minute 1v1 games our metal production was at parity while army K/D was
0.47 against stock's 1.42.

Reads the same [BARAI_STATS] lines everything else does. Cumulative counters are
taken at each side's OWN last sample, because a dead team stops reporting and
the global last frame would contain only the survivor.

    python tools/fight1v1.py <run-dir> [more dirs...]
    python tools/fight1v1.py matches/ab-engage-*      # aggregate one arm
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

CUM = ("mKillReal", "mLostReal", "mKillMobile", "mLostMobile", "metalProduced",
       "mKillStatic")


def read(log: Path):
    """ally -> last-seen cumulative totals, summed over that ally's teams."""
    per_team = {}
    for m in re.finditer(r"\[BARAI_STATS\] (.*)", log.read_text("utf-8", errors="replace")):
        d = {}
        for tok in m.group(1).split():
            k, _, v = tok.partition("=")
            d[k] = v
        try:
            ally, team = int(d["ally"]), int(d["team"])
        except (KeyError, ValueError):
            continue
        vals = {}
        for k in CUM:
            try:
                vals[k] = float(d.get(k, 0) or 0)
            except ValueError:
                vals[k] = 0.0
        per_team[(ally, team)] = vals

    out = {}
    for (ally, _team), vals in per_team.items():
        acc = out.setdefault(ally, dict.fromkeys(CUM, 0.0))
        for k in CUM:
            acc[k] += vals[k]
    return out


def subject_ally(match_dir: Path, subject: str) -> int | None:
    """Which ally index the subject AI played, from result.json.

    A tournament SWAPS sides between pairings, so the subject is ally 0 in half
    the matches and ally 1 in the other half. Assuming ally 0 is always us mixed
    the two together and produced a trade ratio near 1.0 for every arm -- it was
    averaging us against ourselves.
    """
    rj = match_dir / "result.json"
    if not rj.exists():
        return None
    try:
        teams = json.loads(rj.read_text("utf-8")).get("teams", [])
    except (ValueError, OSError):
        return None
    for t in teams:
        if subject.lower() in str(t.get("spec", "")).lower():
            # 1v1: team index is the ally index.
            return int(t.get("team", -1))
    return None


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--subject")]
    subject = "Apex"
    for a in sys.argv[1:]:
        if a.startswith("--subject="):
            subject = a.split("=", 1)[1]
    if not args:
        print(__doc__)
        return 2

    logs = []
    for a in args:
        root = Path(a)
        if not root.is_absolute():
            root = REPO / root
        if (root / "infolog.txt").exists():
            logs.append(root / "infolog.txt")
        else:
            logs.extend(sorted(root.rglob("infolog.txt")))
    if not logs:
        print("no infologs found")
        return 2

    tot = {0: dict.fromkeys(CUM, 0.0), 1: dict.fromkeys(CUM, 0.0)}
    rows = []
    skipped = 0
    for log in logs:
        d = read(log)
        if 0 not in d or 1 not in d:
            continue
        mine = subject_ally(log.parent, subject)
        if mine is None:
            mine = 0  # plain match dirs: run_match always puts --a first
        theirs = 1 - mine
        us, them = d[mine], d[theirs]
        for k in CUM:
            tot[0][k] += us[k]
            tot[1][k] += them[k]
        kd = us["mKillReal"] / (us["mLostReal"] or 1)
        kdo = them["mKillReal"] / (them["mLostReal"] or 1)
        rows.append((log.parent.name[:34], kd, kdo,
                     us["metalProduced"] / (them["metalProduced"] or 1)))

    print(f"  {'game':36} {'ourKD':>6} {'theirKD':>8} {'metal':>6}")
    for name, kd, kdo, mr in rows:
        print(f"  {name:36} {kd:6.2f} {kdo:8.2f} {mr:6.2f}")

    ourkd = tot[0]["mKillReal"] / (tot[0]["mLostReal"] or 1)
    theirkd = tot[1]["mKillReal"] / (tot[1]["mLostReal"] or 1)
    metal = tot[0]["metalProduced"] / (tot[1]["metalProduced"] or 1)
    print(f"\n  games {len(rows)}")
    print(f"  ARMY K/D (metal)   us {ourkd:.3f}   them {theirkd:.3f}"
          f"   ratio {ourkd / (theirkd or 1):.3f}")
    print(f"  metal produced     ratio {metal:.3f}")
    print(f"  metal killed/lost  us {tot[0]['mKillReal']:.0f}/{tot[0]['mLostReal']:.0f}"
          f"   them {tot[1]['mKillReal']:.0f}/{tot[1]['mLostReal']:.0f}")
    # Enemy STATIC metal killed: mexes, energy, defences. The direct measure of
    # whether we are actually hurting their economy rather than only trading
    # armies with it.
    print(f"  enemy static killed us {tot[0]['mKillStatic']:.0f}"
          f"   them {tot[1]['mKillStatic']:.0f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
