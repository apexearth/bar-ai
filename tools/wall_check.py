#!/usr/bin/env python3
"""Did the towers form a WALL? Geometry of static defence vs the base hull.

apexearth 2026-08-30: "we create a long wall of towers wrapping around our
base... the wall pushes outwards as we expand, older towers in the back are
reclaimed." This measures exactly that, from [BARAI_POS] snapshots:

  - the base hull: per-bearing max reach of NON-defence structures from their
    worth-agnostic centroid (24 wedges, one smoothing pass -- the same shape
    protect_field.as calls the rim);
  - each tower's rim distance (negative = inside the hull);
  - the ON-WALL band share: towers within [-300, +700] of the hull;
  - angular closure: share of the 24 bearings holding an on-wall tower;
  - nearest-neighbour tower spacing (a wall is contiguous, a blob is dense,
    scattered singles are sparse).

Usage:
    python tools/wall_check.py <match-dir> [--team 0] [--every 5]
"""
from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from defence_pos import defence_defs  # noqa: E402

POS_RE = re.compile(r"\[BARAI_POS\] team=(\d+) ally=(\d+) frame=(\d+) n=(\d+) (\S*)")
RAYS = 24
BAND_IN = -300.0
BAND_OUT = 700.0


def snapshots(stdout: Path, team: int):
    for line in stdout.read_text(errors="replace").splitlines():
        m = POS_RE.search(line)
        if not m or int(m.group(1)) != team:
            continue
        units = []
        for tok in m.group(5).split(','):
            parts = tok.split(':')
            if len(parts) >= 3:
                units.append((parts[0], float(parts[1]), float(parts[2])))
        yield int(m.group(3)), units


def bearing(cx, cz, x, z):
    a = math.atan2(z - cz, x - cx)
    if a < 0:
        a += 2 * math.pi
    b = int(a / (2 * math.pi / RAYS))
    return min(max(b, 0), RAYS - 1)


def analyse(units, ddefs):
    towers = [(n, x, z) for n, x, z in units if n in ddefs]
    base = [(n, x, z) for n, x, z in units if n not in ddefs]
    if len(base) < 3:
        return None
    cx = sum(x for _, x, _ in base) / len(base)
    cz = sum(z for _, _, z in base) / len(base)
    # The same lobe cap the wall itself applies (protect_wall.as): one far mex
    # must not balloon the hull, or every tower on the real wall reads
    # interior. Buildings only, as the AI does -- mex sprawl must not carry
    # the cap with it.
    core = [(x, z) for n, x, z in base if 'mex' not in n and 'moho' not in n]
    if len(core) < 3:
        core = [(x, z) for _, x, z in base]
    rms = math.sqrt(sum((x - cx) ** 2 + (z - cz) ** 2 for x, z in core)
                    / len(core))
    cap = rms * 2.5
    rim = [0.0] * RAYS
    for _, x, z in base:
        b = bearing(cx, cz, x, z)
        d = min(math.hypot(x - cx, z - cz), cap)
        rim[b] = max(rim[b], d)
    sm = rim[:]
    for b in range(RAYS):
        nb = max(rim[(b - 1) % RAYS], rim[(b + 1) % RAYS]) * 0.85
        sm[b] = max(sm[b], nb)
    rim = sm
    rimd = []
    onwall_bearings = set()
    for _, x, z in towers:
        b = bearing(cx, cz, x, z)
        rd = math.hypot(x - cx, z - cz) - rim[b]
        rimd.append(rd)
        if BAND_IN <= rd <= BAND_OUT:
            onwall_bearings.add(b)
    nn = []
    for i, (_, x, z) in enumerate(towers):
        best = None
        for j, (_, x2, z2) in enumerate(towers):
            if i == j:
                continue
            d = math.hypot(x - x2, z - z2)
            best = d if best is None else min(best, d)
        if best is not None:
            nn.append(best)
    rimd.sort()
    med = rimd[len(rimd) // 2] if rimd else 0.0
    inband = sum(1 for r in rimd if BAND_IN <= r <= BAND_OUT)
    return {
        "towers": len(towers),
        "medRimD": med,
        "onWallPct": (100.0 * inband / len(rimd)) if rimd else 0.0,
        "closure": len(onwall_bearings) / RAYS,
        "nnMed": sorted(nn)[len(nn) // 2] if nn else 0.0,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("match")
    ap.add_argument("--team", type=int, default=0)
    ap.add_argument("--every", type=int, default=5, help="minutes between rows")
    args = ap.parse_args()
    stdout = Path(args.match) / "stdout.txt"
    if not stdout.exists():
        sys.exit(f"no stdout.txt under {args.match}")
    ddefs = defence_defs()
    step = args.every * 60 * 30
    nxt = step
    print(f"{'min':>5} {'twr':>4} {'medRimD':>8} {'onWall%':>8} {'closure':>8} {'nnMed':>6}")
    last = None
    for frame, units in snapshots(stdout, args.team):
        last = (frame, units)
        if frame < nxt:
            continue
        nxt += step
        r = analyse(units, ddefs)
        if r:
            print(f"{frame/1800:5.1f} {r['towers']:4d} {r['medRimD']:8.0f} "
                  f"{r['onWallPct']:8.1f} {r['closure']:8.2f} {r['nnMed']:6.0f}")
    if last:
        r = analyse(last[1], ddefs)
        if r:
            print(f"{last[0]/1800:5.1f} {r['towers']:4d} {r['medRimD']:8.0f} "
                  f"{r['onWallPct']:8.1f} {r['closure']:8.2f} {r['nnMed']:6.0f}  <- final")


if __name__ == "__main__":
    main()
