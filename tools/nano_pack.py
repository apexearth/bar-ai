#!/usr/bin/env python3
"""How much GROUND do our nano turrets take?

apexearth 2026-08-31: "We tend to space our nano turrets too much. They use too
much room. Nanos can be placed right next to the back and sides of all
factories, and all sides of air factories. Nano turrets should prefer to be
placed right next to each other."

That is a claim about geometry, and looking at a replay cannot settle it. This
reads [BARAI_POS] and reports, per team:

  n        nano turrets standing
  nnMed    median nearest-neighbour distance between them, elmos.
           A nano's footprint is 3 build cells = 48 elmos, so 48 is
           shoulder-to-shoulder and anything near 100+ is a compass rose.
  touch%   share whose nearest neighbour is within one pitch and a half --
           i.e. actually adjacent rather than merely nearby
  facMed   median distance to the nearest factory of ours
  areaPer  the ground the turrets occupy: the area of their bounding box per
           turret, in footprint areas. This is "they use too much room" as a
           number -- a packed block reads near 1, a scatter reads many times it.

And the reactor block, for "we should prefer to build our AFUS/fusion nearby
each other so they can take advantage of nearby nano turrets":

  rN       fusions + advanced fusions standing
  rNN      median nearest-neighbour distance between them. A fusion is 96x80,
           so ~96 is touching and 700+ is a blast aisle apart.
  lathe    median turrets within a nano's 400-elmo reach of a reactor -- the
           lathe each one can actually draw on
  shared   mean reactors within reach of each TURRET. 1.0 means every turret
           serves exactly one reactor and the packing buys nothing; above 1
           is the sharing he is asking for.

Usage:
    python tools/nano_pack.py <match-dir> [--control <match-dir>] [--pitch 48]
"""
from __future__ import annotations

import argparse
import re
import statistics
import sys
from pathlib import Path

POS_RE = re.compile(r"\[BARAI_POS\] team=(\d+) ally=(\d+) frame=(\d+) n=(\d+) (\S*)")
# A nano turret is a structure that assists and builds nothing of its own. The
# game names them consistently across all three factions.
NANO_RE = re.compile(r"nanotc", re.I)
# Factory suffixes in the pinned tree -- lab/vp/ap plus the advanced and
# experimental plants and the shipyards.
FAC_RE = re.compile(r"(lab|vp|ap|sy|hp|gant|shltx|plat)$", re.I)
# The big reactors. apexearth 2026-08-31: "We should prefer to build our
# AFUS/fusion nearby each other so they can take advantage of nearby nano
# turrets to build even faster." armnanotc reaches 400 elmos and a fusion is
# 96x80, so two adjacent reactors are trivially inside one turret's reach --
# the only question is whether they are actually adjacent.
REACTOR_RE = re.compile(r"(fus|afus)$", re.I)
NANO_REACH = 400.0


def parse_units(blob):
    out = []
    for tok in blob.split(','):
        parts = tok.split(':')
        if len(parts) >= 3:
            try:
                out.append((parts[0], float(parts[1]), float(parts[2])))
            except ValueError:
                pass
    return out


def last_snapshots(stdout: Path):
    """team -> the final [BARAI_POS] unit list for that team."""
    latest = {}
    for line in stdout.read_text(errors="replace").splitlines():
        m = POS_RE.search(line)
        if not m:
            continue
        team = int(m.group(1))
        frame = int(m.group(3))
        prev = latest.get(team)
        if (prev is None) or (frame >= prev[0]):
            latest[team] = (frame, parse_units(m.group(5)))
    return latest


def dist(a, b):
    return ((a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5


def team_row(units, pitch):
    nanos = [u for u in units if NANO_RE.search(u[0])]
    facs = [u for u in units if FAC_RE.search(u[0])]
    if len(nanos) < 2:
        return None
    nn = []
    for i, a in enumerate(nanos):
        best = min(dist(a, b) for j, b in enumerate(nanos) if j != i)
        nn.append(best)
    facd = []
    for a in nanos:
        if facs:
            facd.append(min(dist(a, f) for f in facs))
    # THE REACTOR BLOCK. Its nearest-neighbour distance says whether the
    # reactors cluster at all; lathePer says how much of the turret fleet each
    # one can actually draw on, which is the thing the packing buys.
    reactors = [u for u in units if REACTOR_RE.search(u[0])]
    rnn = []
    lathe = []
    for i, a in enumerate(reactors):
        if len(reactors) > 1:
            rnn.append(min(dist(a, b) for j, b in enumerate(reactors) if j != i))
        lathe.append(sum(1 for t in nanos if dist(a, t) <= NANO_REACH))
    shared = []
    for t in nanos:
        shared.append(sum(1 for a in reactors if dist(a, t) <= NANO_REACH))
    # DISTANCE TO THE NEAREST THING WORTH ASSISTING. facMed alone cannot
    # separate "the block sits far from everything" from "the block is packed
    # against a reactor frame rather than a lab" -- and the nano executor sites
    # at lines AND at big build frames, so both are legitimate anchors.
    served = facs + reactors
    asst = []
    for a in nanos:
        if served:
            asst.append(min(dist(a, f) for f in served))

    xs = [u[1] for u in nanos]
    zs = [u[2] for u in nanos]
    box = max(1.0, (max(xs) - min(xs))) * max(1.0, (max(zs) - min(zs)))
    return {
        "n": len(nanos),
        "nnMed": statistics.median(nn),
        "touch": 100.0 * sum(1 for d in nn if d <= pitch * 1.5) / len(nn),
        "facMed": statistics.median(facd) if facd else float("nan"),
        "areaPer": box / len(nanos) / (pitch * pitch),
        "rN": len(reactors),
        "rNN": statistics.median(rnn) if rnn else float("nan"),
        "lathe": statistics.median(lathe) if lathe else float("nan"),
        "shared": statistics.mean(shared) if shared else float("nan"),
        "asstMed": statistics.median(asst) if asst else float("nan"),
    }


def report(run: Path, pitch: float, label: str):
    stdout = run / "stdout.txt"
    if not stdout.exists():
        sys.exit(f"no stdout.txt in {run}")
    rows = []
    for team, (_frame, units) in sorted(last_snapshots(stdout).items()):
        r = team_row(units, pitch)
        if r:
            r["team"] = team
            rows.append(r)
    if not rows:
        print(f"{label}: no team had two nano turrets standing")
        return None
    print(f"\n{label}  ({run})")
    cols = ("n", "nnMed", "touch", "facMed", "asstMed", "areaPer",
            "rN", "rNN", "lathe", "shared")
    print("  team    n   nnMed  touch%  facMed  asstMed  areaPer |  rN    rNN  lathe  shared")
    for r in rows:
        print("  %4d %4d  %6.0f  %6.1f  %6.0f  %7.0f  %7.1f | %3d %6.0f %6.0f  %6.2f"
              % (r["team"], r["n"], r["nnMed"], r["touch"], r["facMed"],
                 r["asstMed"], r["areaPer"], r["rN"], r["rNN"], r["lathe"],
                 r["shared"]))
    agg = {}
    for k in cols:
        vals = [r[k] for r in rows if r[k] == r[k]]   # drop NaN
        agg[k] = statistics.median(vals) if vals else float("nan")
    print("  MEDIAN %4.0f  %6.0f  %6.1f  %6.0f  %7.0f  %7.1f | %3.0f %6.0f %6.0f  %6.2f"
          % (agg["n"], agg["nnMed"], agg["touch"], agg["facMed"],
             agg["asstMed"], agg["areaPer"], agg["rN"], agg["rNN"],
             agg["lathe"], agg["shared"]))
    return agg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("--control")
    ap.add_argument("--pitch", type=float, default=48.0,
                    help="nano footprint pitch in elmos (armnanotc is 3 cells = 48)")
    args = ap.parse_args()
    now = report(Path(args.run), args.pitch, "run")
    if args.control:
        before = report(Path(args.control), args.pitch, "control")
        if now and before:
            print("\n  delta (run vs control), medians")
            for k in ("n", "nnMed", "touch", "facMed", "asstMed",
                      "areaPer", "rN", "rNN", "lathe", "shared"):
                print("    %-8s %8.1f -> %8.1f" % (k, before[k], now[k]))


if __name__ == "__main__":
    main()
