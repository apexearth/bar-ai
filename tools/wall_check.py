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
    python tools/wall_check.py <match-dir> --ally 0     # the TEAM hull
"""
from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from defence_pos import defence_defs  # noqa: E402

POS_RE = re.compile(r"\[BARAI_POS\] team=(\d+) ally=(\d+) frame=(\d+) n=(\d+) (?:part=\d+/\d+ )?(\S*)")
RAYS = 24
BAND_IN = -300.0
BAND_OUT = 700.0


def parse_units(blob):
    units = []
    for tok in blob.split(','):
        parts = tok.split(':')
        if len(parts) >= 3:
            units.append((parts[0], float(parts[1]), float(parts[2])))
    return units


def snapshots(stdout: Path, team: int):
    # A large base is split over several part=i/n rows of one frame.
    cur = None
    units = []
    for line in stdout.read_text(errors="replace").splitlines():
        m = POS_RE.search(line)
        if not m or int(m.group(1)) != team:
            continue
        f = int(m.group(3))
        if cur is not None and f != cur:
            yield cur, units
            units = []
        cur = f
        units = units + parse_units(m.group(5))
    if cur is not None:
        yield cur, units


def enemy_start(stdout: Path, team: int):
    """Centroid of the FIRST snapshot of every team on another allyteam --
    where the enemy actually started, for the facing columns."""
    ally_of = {}
    first = {}
    for line in stdout.read_text(errors="replace").splitlines():
        m = POS_RE.search(line)
        if not m:
            continue
        t = int(m.group(1))
        ally_of[t] = int(m.group(2))
        if t not in first:
            first[t] = parse_units(m.group(5))
    if team not in ally_of:
        return None
    pts = []
    for t, units in first.items():
        if ally_of[t] == ally_of[team]:
            continue
        pts.extend((x, z) for _, x, z in units)
    if not pts:
        return None
    return (sum(x for x, _ in pts) / len(pts), sum(z for _, z in pts) / len(pts))


def bearing(cx, cz, x, z):
    a = math.atan2(z - cz, x - cx)
    if a < 0:
        a += 2 * math.pi
    b = int(a / (2 * math.pi / RAYS))
    return min(max(b, 0), RAYS - 1)


def analyse(units, ddefs, foe=None):
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
    # Facing: each tower's angular offset from the enemy-start bearing. The
    # wall must wrap, but the enemy-facing arc has to fill FIRST -- a wall
    # grown by builder convenience reads fine on every radial metric and
    # still leaves the war-side open (measured 2026-08-30: median offset
    # 116 degrees in one normal-play game).
    med_off = -1.0
    front_pct = -1.0
    if foe and towers:
        ea = math.atan2(foe[1] - cz, foe[0] - cx)
        offs = sorted(
            abs((math.atan2(z - cz, x - cx) - ea + math.pi) % (2 * math.pi)
                - math.pi) * 180.0 / math.pi
            for _, x, z in towers)
        med_off = offs[len(offs) // 2]
        front_pct = 100.0 * sum(1 for o in offs if o <= 90.0) / len(offs)
    return {
        "towers": len(towers),
        "medRimD": med,
        "onWallPct": (100.0 * inband / len(rimd)) if rimd else 0.0,
        "closure": len(onwall_bearings) / RAYS,
        "nnMed": sorted(nn)[len(nn) // 2] if nn else 0.0,
        "medOff": med_off,
        "frontPct": front_pct,
    }


def team_snapshot(stdout: Path, ally: int):
    """The whole allyteam's last snapshot as one unit list, plus which team
    owns each unit -- the team hull, for the closure the enemy actually
    faces (one player's ring says nothing about the gap beside its ally)."""
    last = {}
    for line in stdout.read_text(errors="replace").splitlines():
        m = POS_RE.search(line)
        if not m or int(m.group(2)) != ally:
            continue
        t = int(m.group(1))
        f = int(m.group(3))
        if t not in last or f > last[t][0]:
            last[t] = (f, [])
        if f == last[t][0]:
            last[t][1].extend(parse_units(m.group(5)))
    units = []
    owner = []
    for t, (_, us) in sorted(last.items()):
        units.extend(us)
        owner.extend([t] * len(us))
    return units, owner


def team_report(stdout: Path, ally: int, ddefs):
    units, owner = team_snapshot(stdout, ally)
    r = analyse(units, ddefs)
    if r is None:
        print("team hull: no snapshot")
        return
    print(f"allyteam {ally} hull: towers={r['towers']} onWall%={r['onWallPct']:.0f} "
          f"closure={r['closure']:.2f} nnMed={r['nnMed']:.0f}")
    base = [(x, z) for n, x, z in units if n not in ddefs]
    cx = sum(x for x, _ in base) / len(base)
    cz = sum(z for _, z in base) / len(base)
    per = {}
    for (n, x, z), t in zip(units, owner):
        if n not in ddefs:
            continue
        per.setdefault(bearing(cx, cz, x, z), set()).add(t)
    print("  bearing: owners of guns on it (24 bearings, 0 = +x, counter-clockwise)")
    print("  " + " ".join(f"{b:>2}:{''.join(str(t) for t in sorted(per.get(b, ())))or '-'}"
                          for b in range(RAYS)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("match")
    ap.add_argument("--team", type=int, default=0)
    ap.add_argument("--every", type=int, default=5, help="minutes between rows")
    ap.add_argument("--ally", type=int, default=None,
                    help="report the whole allyteam's hull instead of one team")
    args = ap.parse_args()
    stdout = Path(args.match) / "stdout.txt"
    if not stdout.exists():
        sys.exit(f"no stdout.txt under {args.match}")
    ddefs = defence_defs()
    if args.ally is not None:
        team_report(stdout, args.ally, ddefs)
        return
    foe = enemy_start(stdout, args.team)
    step = args.every * 60 * 30
    nxt = step
    print(f"{'min':>5} {'twr':>4} {'medRimD':>8} {'onWall%':>8} {'closure':>8} "
          f"{'nnMed':>6} {'medOff':>7} {'front%':>7}")

    def row(frame, units, tag=""):
        r = analyse(units, ddefs, foe)
        if r:
            print(f"{frame/1800:5.1f} {r['towers']:4d} {r['medRimD']:8.0f} "
                  f"{r['onWallPct']:8.1f} {r['closure']:8.2f} {r['nnMed']:6.0f} "
                  f"{r['medOff']:7.0f} {r['frontPct']:7.1f}{tag}")

    last = None
    for frame, units in snapshots(stdout, args.team):
        last = (frame, units)
        if frame < nxt:
            continue
        nxt += step
        row(frame, units)
    if last:
        row(last[0], last[1], "  <- final")


if __name__ == "__main__":
    main()
