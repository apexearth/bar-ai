"""Did the base tile?  The lattice census, from `apex: placed` lines.

    python tools/tiling.py <run|tournament|infolog> [--team N] [--show]

Three questions, per team, every one of which the `apex: tiling flush=` line
cannot answer (its FLUSH bar accepts a neighbour a whole build square off):

  ALIGNED  a structure and its nearest kin (same def) sit on ONE lattice of
           the def's own pitch: both axis offsets are whole multiples of it.
           "To the right and then down by one" is a miss, and is listed.
  PHASE    all of one def, one team, share one residue mod the pitch -- the
           share on the dominant residue.  Two clusters on two phases can
           never grow into each other.
  FOREIGN  edge gap to the nearest structure of another def, in build squares:
           0 is flush, 1-2 is ground nothing will ever use, an aisle is meant.

A positive `dx,dz` is printed in world axes.  Mexes and geos are never in the
census (they sit on their spot), nor is anything mobile.
"""
from __future__ import annotations

import argparse
import collections
import re
import sys
from pathlib import Path

CELL = 16.0
TOL = 1.0   # elmos; the log prints ints
PLACED = re.compile(r"apex: placed t=(\d+) (\S+) at=(-?\d+),(-?\d+) foot=(\d+)x(\d+)")


def infologs(target: Path) -> list[Path]:
    if target.is_file():
        return [target]
    if (target / "infolog.txt").exists():
        return [target / "infolog.txt"]
    logs = sorted(target.glob("matches/*/infolog.txt"))
    if not logs:
        sys.exit(f"no infolog under {target}")
    return logs


def load(path: Path) -> dict[int, list[tuple]]:
    teams: dict[int, list[tuple]] = collections.defaultdict(list)
    for line in path.read_text(errors="replace").splitlines():
        m = PLACED.search(line)
        if m:
            t, d, x, z, fx, fz = m.groups()
            teams[int(t)].append((d, float(x), float(z), int(fx), int(fz)))
    return teams


def residue(v: float, pitch: float) -> float:
    r = v % pitch
    return min(r, pitch - r)


def census(rows: list[tuple], show: bool) -> dict:
    by_def: dict[str, list[tuple]] = collections.defaultdict(list)
    for r in rows:
        by_def[r[0]].append(r)
    out = {"n": len(rows), "paired": 0, "aligned": 0, "phase_n": 0, "phase_dom": 0,
           "foreign": collections.Counter(), "miss": []}
    for d, rs in by_def.items():
        fx, fz = rs[0][3], rs[0][4]
        pitch = max(fx, fz) * CELL
        # PHASE: residue class of every member, on both axes.
        cls = collections.Counter((round(r[1] % pitch), round(r[2] % pitch)) for r in rs)
        if len(rs) >= 2:
            out["phase_n"] += len(rs)
            out["phase_dom"] += cls.most_common(1)[0][1]
        # ALIGNED against the nearest kin within two pitches.
        for r in rs:
            best = None
            for k in rs:
                if k is r:
                    continue
                dx, dz = r[1] - k[1], r[2] - k[2]
                dist = max(abs(dx), abs(dz))
                if dist < TOL:
                    continue
                if best is None or dist < best[0]:
                    best = (dist, dx, dz, k)
            if best is None or best[0] > 2 * pitch + TOL:
                continue
            out["paired"] += 1
            _, dx, dz, k = best
            ok = residue(dx, pitch) <= TOL and residue(dz, pitch) <= TOL
            if ok:
                out["aligned"] += 1
            else:
                out["miss"].append((d, r[1], r[2], dx, dz, pitch))
    # FOREIGN: nearest other-def structure, edge gap in build squares.
    for r in rows:
        best = None
        for k in rows:
            if k[0] == r[0]:
                continue
            gx = abs(r[1] - k[1]) - (r[3] + k[3]) * CELL / 2
            gz = abs(r[2] - k[2]) - (r[4] + k[4]) * CELL / 2
            gap = max(gx, gz)   # Chebyshev edge gap; < 0 would be an overlap
            if best is None or gap < best:
                best = gap
        if best is None or best > 20 * CELL:
            continue
        sq = int(round(max(best, 0) / CELL))
        out["foreign"][min(sq, 8)] += 1
    return out


def report(path: Path, only: int | None, show: bool) -> None:
    teams = load(path)
    if not teams:
        print(f"{path}: no `apex: placed` lines (script older than the census?)")
        return
    text = path.read_text(errors="replace")
    off = text.count("apex: off-lattice ")
    fail = text.count("apex: site-fail ")
    print(f"# {path}  (off-lattice {off}, site-fail {fail})")
    for t in sorted(teams):
        if only is not None and t != only:
            continue
        c = census(teams[t], show)
        al = f"{c['aligned']}/{c['paired']}"
        alp = (100 * c["aligned"] // c["paired"]) if c["paired"] else 0
        php = (100 * c["phase_dom"] // c["phase_n"]) if c["phase_n"] else 0
        fo = " ".join(f"{k}sq:{v}" for k, v in sorted(c["foreign"].items()))
        print(f"t{t}: {c['n']} structures  ALIGNED {al} ({alp}%)  "
              f"PHASE {php}% on the dominant residue  FOREIGN gap {fo}")
        if show:
            for d, x, z, dx, dz, pitch in c["miss"][:40]:
                print(f"    miss {d:12s} at {int(x)},{int(z)}  kin off by {int(dx)},{int(dz)}"
                      f"  (pitch {int(pitch)}: residue {int(residue(dx, pitch))},{int(residue(dz, pitch))})")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run")
    ap.add_argument("--team", type=int, default=None)
    ap.add_argument("--show", action="store_true", help="list the misaligned structures")
    a = ap.parse_args()
    for log in infologs(Path(a.run)):
        report(log, a.team, a.show)
    return 0


if __name__ == "__main__":
    sys.exit(main())
