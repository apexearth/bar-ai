#!/usr/bin/env python3
"""Of the things that DIED, how many were actually covered when they died?

Every defence measurement in this repo so far has answered "is there a tower
near our stuff", and that number was already 77-85% on runs where apexearth
watched mexes die anyway. An average over all structures hides the only thing
that matters: the ones that die are systematically the naked ones, and a
covered rear mex tells you nothing.

This asks the question that separates the three failure modes that have been
indistinguishable all session:

  NEVER      no tower within reach at any point, before or after -- the
             turret was never built at all
  TOO LATE   no tower at the moment of death, but one appears later -- the
             AI knew, and arrived after the funeral
  USELESS    a tower WAS within reach when it died -- so the problem is not
             placement or timing, it is that the cover does not fight

Usage:
    python tools/death_cover.py <match-dir> [--reach 520] [--teams 0,1,2,3]
"""
from __future__ import annotations

import argparse
import io
import math
import re
import sys
from pathlib import Path

POS = re.compile(r"\[BARAI_POS\] team=(\d+) ally=\d+ frame=(\d+) n=\d+ (?:part=\d+/\d+ )?(\S*)")
DEAD = re.compile(r"apex: unit-destroyed (\w+) .*?frame=(\d+) at=(-?\d+),(-?\d+)")
TOWER_PREFIX = ("armllt", "armbeam", "armclaw", "armguard", "armhlt", "armanni",
                "armpb", "armmaw", "corllt", "corhllt", "corhlt", "corvipe",
                "cordoom", "corpun", "cormaw")


def is_tower(name: str) -> bool:
    return name.startswith(TOWER_PREFIX)


def is_eco(name: str) -> bool:
    return name.endswith(("mex", "moho", "solar", "wind", "fus", "afus",
                          "mmkr", "makr", "lab", "vp", "ap"))


def snapshots(stdout: Path, teams):
    """frame -> {team: [(name,x,z)]}, in frame order."""
    out = []
    for line in io.open(stdout, errors="replace"):
        m = POS.search(line)
        if not m:
            continue
        t = int(m.group(1))
        if t not in teams:
            continue
        units = []
        for tok in m.group(3).split(','):
            p = tok.split(':')
            if len(p) >= 3:
                try:
                    units.append((p[0].lower(), float(p[1]), float(p[2])))
                except ValueError:
                    pass
        if out and out[-1][0] == int(m.group(2)) and out[-1][1] == t:
            out[-1][2].extend(units)          # a further part= line
        else:
            out.append((int(m.group(2)), t, units))
    out.sort(key=lambda r: r[0])
    return out


def covered_at(snaps, team, frame, x, z, reach, after=False):
    """Was a tower of `team` within `reach` of (x,z) at/before `frame`?
    With after=True, look only at snapshots AFTER the frame instead."""
    best = None
    for f, t, units in snaps:
        if t != team:
            continue
        if (not after and f <= frame) or (after and f > frame):
            if best is None or (not after and f > best[0]) or (after and best is None):
                best = (f, units)
            if after:
                break
    if best is None:
        return False
    return any(is_tower(n) and math.hypot(x - ux, z - uz) < reach
               for n, ux, uz in best[1])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("--reach", type=float, default=520.0)
    ap.add_argument("--teams", default="0,1,2,3")
    args = ap.parse_args()
    run = Path(args.run)
    teams = {int(x) for x in args.teams.split(',')}
    snaps = snapshots(run / "stdout.txt", teams)
    if not snaps:
        sys.exit("no [BARAI_POS] snapshots for those teams")

    never = late = useless = 0
    rows = []
    for line in io.open(run / "infolog.txt", errors="replace"):
        m = DEAD.search(line)
        if not m:
            continue
        name, frame, x, z = m.group(1).lower(), int(m.group(2)), float(m.group(3)), float(m.group(4))
        if not is_eco(name):
            continue
        # which team owned it: the snapshot team whose units include this spot
        owner = None
        for f, t, units in snaps:
            if f > frame:
                continue
            if any(abs(ux - x) < 32 and abs(uz - z) < 32 for _, ux, uz in units):
                owner = t
        if owner is None:
            continue
        if covered_at(snaps, owner, frame, x, z, args.reach):
            useless += 1
            verdict = "USELESS"
        elif covered_at(snaps, owner, frame, x, z, args.reach, after=True):
            late += 1
            verdict = "TOO LATE"
        else:
            never += 1
            verdict = "NEVER"
        rows.append((frame / 1800.0, name, verdict))

    tot = never + late + useless
    if tot == 0:
        print("no economic structures died in this run")
        return
    print("%s -- %d economic structures died\n" % (run.name, tot))
    print("  NEVER covered   %3d  (%3.0f%%)   the turret was never built" % (never, 100 * never / tot))
    print("  TOO LATE        %3d  (%3.0f%%)   built, but after it died" % (late, 100 * late / tot))
    print("  USELESS         %3d  (%3.0f%%)   a tower was in reach and it died anyway" % (useless, 100 * useless / tot))
    print("\n  first 12 deaths:")
    for mn, name, verdict in rows[:12]:
        print("    %5.1f min  %-10s %s" % (mn, name, verdict))


if __name__ == "__main__":
    main()
