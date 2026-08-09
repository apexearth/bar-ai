#!/usr/bin/env python3
"""Economic composition and ORGANISATIONAL QUALITY of a run.

Top-line metal is not the question this answers. A base can produce well for a
while and still be laid out so badly that it runs out of room, walls itself off
from its own mexes, or spends its constructors walking. Those cost income later
and are invisible in a total.

Two families of metric:

  ORGANISATION -- from [BARAI_POS], the per-building positions gadget. Packing
  efficiency (footprint area actually used vs the hull it occupies), nearest
  neighbour spacing against the block-map's own adjacency pitch, and how much of
  the base sits on a shared row or column, which is what "built in rows" means
  mechanically.

  EXPANSION -- mex count and income as RATES over time, not totals, plus the
  share of mexes upgraded. A base that stops expanding at minute 12 and one that
  never stopped look identical at minute 30 if you only read the total.

Usage:
    python tools/eco.py <run-dir> [--control <run-dir>] [--ally 0]
"""
from __future__ import annotations

import argparse
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Engine build square. Footprints are quantised to this, so it is the unit that
# "touching" is measured in -- two buildings are adjacent when the gap between
# their footprint edges is one of these, not zero elmos.
SQUARE = 8.0

POS_RE = re.compile(r"\[BARAI_POS\] team=(\d+) ally=(\d+) frame=(\d+) n=(\d+) (.*)")
STAT_RE = re.compile(r"\[BARAI_STATS\] (.*)")


def read_infolog(run: Path) -> str:
    for name in ("infolog.txt", "infolog.log"):
        p = run / name
        if p.exists():
            return p.read_text("utf-8", errors="replace")
    raise SystemExit(f"no infolog in {run}")


def parse_positions(text: str):
    """frame -> ally -> team -> [(name, x, z, xsize, zsize)]"""
    out = defaultdict(lambda: defaultdict(dict))
    for line in text.splitlines():
        m = POS_RE.search(line)
        if not m:
            continue
        team, ally, frame, _n, blob = m.groups()
        rows = []
        for item in blob.split(","):
            bits = item.split(":")
            if len(bits) != 5:
                continue
            try:
                rows.append((bits[0], float(bits[1]), float(bits[2]),
                             int(bits[3]), int(bits[4])))
            except ValueError:
                continue
        if rows:
            out[int(frame)][int(ally)][int(team)] = rows
    return out


def parse_stats(text: str):
    """frame -> ally -> list of dicts"""
    out = defaultdict(lambda: defaultdict(list))
    for line in text.splitlines():
        m = STAT_RE.search(line)
        if not m:
            continue
        d = {}
        for tok in m.group(1).split():
            if "=" not in tok:
                continue
            k, v = tok.split("=", 1)
            d[k] = v
        try:
            frame = int(d.get("frame", -1))
            ally = int(d.get("ally", -1))
        except ValueError:
            continue
        if frame >= 0 and ally >= 0:
            out[frame][ally].append(d)
    return out


def convex_hull_area(pts):
    """Area the base actually occupies. Bounding box overstates an L-shaped base
    badly, and an L is exactly what a base grown along two lanes looks like."""
    pts = sorted(set(pts))
    if len(pts) < 3:
        return 0.0

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper = []
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    hull = lower[:-1] + upper[:-1]
    area = 0.0
    for i in range(len(hull)):
        x1, y1 = hull[i]
        x2, y2 = hull[(i + 1) % len(hull)]
        area += x1 * y2 - x2 * y1
    return abs(area) / 2.0


def organisation(rows):
    """Layout quality for one player at one sample."""
    if len(rows) < 4:
        return None
    pts = [(x, z) for _n, x, z, _xs, _zs in rows]
    footprint = sum((xs * SQUARE) * (zs * SQUARE) for _n, _x, _z, xs, zs in rows)
    hull = convex_hull_area(pts)

    # Packing: how much of the ground the base spans is actually built on. A
    # solid block approaches 1.0; confetti scattered over the same span is near 0.
    packing = (footprint / hull) if hull > 0 else 0.0

    # Nearest-neighbour EDGE gap, not centre distance -- centre distance is
    # dominated by how big the buildings are, which says nothing about layout.
    gaps = []
    for i, (_n1, x1, z1, xs1, zs1) in enumerate(rows):
        best = None
        for j, (_n2, x2, z2, xs2, zs2) in enumerate(rows):
            if i == j:
                continue
            dx = abs(x1 - x2) - (xs1 + xs2) * SQUARE / 2.0
            dz = abs(z1 - z2) - (zs1 + zs2) * SQUARE / 2.0
            gap = max(dx, dz, 0.0)
            if best is None or gap < best:
                best = gap
        if best is not None:
            gaps.append(best)
    gaps.sort()
    median_gap = gaps[len(gaps) // 2] if gaps else 0.0
    touching = sum(1 for g in gaps if g <= SQUARE) / len(gaps) if gaps else 0.0

    # Alignment: share of buildings sharing an x or z with another, within one
    # build square. This is what "rows and blocks" is, mechanically.
    xs_bucket = defaultdict(int)
    zs_bucket = defaultdict(int)
    for _n, x, z, _xs, _zs in rows:
        xs_bucket[round(x / SQUARE)] += 1
        zs_bucket[round(z / SQUARE)] += 1
    aligned = sum(c for c in xs_bucket.values() if c > 1) + \
              sum(c for c in zs_bucket.values() if c > 1)
    alignment = aligned / (2.0 * len(rows))

    xs_all = [p[0] for p in pts]
    zs_all = [p[1] for p in pts]
    span_w = max(xs_all) - min(xs_all)
    span_d = max(zs_all) - min(zs_all)
    elong = (max(span_w, span_d) / min(span_w, span_d)) if min(span_w, span_d) > 1 else 99.0

    return {
        "n": len(rows),
        "packing": packing,
        "median_gap": median_gap,
        "touching": touching,
        "alignment": alignment,
        "elongation": elong,
        "hull": hull,
    }


def f2m(frame):
    return frame / 1800.0


def summarise(run: Path, ally: int):
    text = read_infolog(run)
    pos = parse_positions(text)
    stats = parse_stats(text)

    err = len(re.findall(r"\.as \(\d+, \d+\) : ERR", text))
    frames = sorted(pos.keys())

    org_rows = []
    for frame in frames:
        per_team = pos[frame].get(ally, {})
        vals = [organisation(rows) for rows in per_team.values()]
        vals = [v for v in vals if v]
        if not vals:
            continue
        org_rows.append((frame, {
            k: sum(v[k] for v in vals) / len(vals)
            for k in ("packing", "median_gap", "touching", "alignment", "elongation")
        } | {"n": sum(v["n"] for v in vals)}))

    exp_rows = []
    for frame in sorted(stats.keys()):
        recs = stats[frame].get(ally, [])
        if not recs:
            continue

        def total(key):
            return sum(float(r.get(key, 0) or 0) for r in recs)

        exp_rows.append((frame, {
            "mex": total("mex"),
            "t2Mex": total("t2Mex"),
            "metal": total("metalProduced"),
            "energy": total("energyProduced"),
            "excess": total("metalExcess"),
        }))

    return {"err": err, "org": org_rows, "exp": exp_rows}


def print_report(name, s, minutes_cap=None):
    print(f"\n=== {name} ===")
    print(f"AngelScript errors: {s['err']}"
          + ("   <-- VARIANT WAS DISABLED" if s["err"] else ""))

    print("\nORGANISATION  (packing 1.0=solid block, touching=share at <=1 square,")
    print("               alignment=share sharing a row/column, elong=aspect ratio)")
    print(f"  {'min':>5} {'bldgs':>6} {'packing':>8} {'gap':>7} {'touching':>9} {'align':>7} {'elong':>7}")
    for frame, o in s["org"]:
        if minutes_cap and f2m(frame) > minutes_cap:
            break
        print(f"  {f2m(frame):5.0f} {o['n']:6.0f} {o['packing']:8.3f} "
              f"{o['median_gap']:7.0f} {o['touching']:9.2f} {o['alignment']:7.2f} "
              f"{min(o['elongation'], 99):7.1f}")

    print("\nEXPANSION  (mex and income as RATES; d/min is the last interval)")
    print(f"  {'min':>5} {'mex':>5} {'d/min':>7} {'t2Mex':>6} {'up%':>5} "
          f"{'metal':>9} {'m/s':>7} {'energy':>10} {'waste':>7}")
    prev = None
    for frame, e in s["exp"]:
        if minutes_cap and f2m(frame) > minutes_cap:
            break
        m = f2m(frame)
        if prev:
            dt = m - prev[0]
            dmex = (e["mex"] - prev[1]["mex"]) / dt if dt > 0 else 0
            dmetal = (e["metal"] - prev[1]["metal"]) / (dt * 60.0) if dt > 0 else 0
        else:
            dmex = dmetal = 0
        up = (100.0 * e["t2Mex"] / e["mex"]) if e["mex"] else 0
        print(f"  {m:5.0f} {e['mex']:5.0f} {dmex:7.1f} {e['t2Mex']:6.0f} {up:4.0f}% "
              f"{e['metal']:9.0f} {dmetal:7.0f} {e['energy']:10.0f} {e['excess']:7.0f}")
        prev = (m, e)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("--control")
    ap.add_argument("--ally", type=int, default=0, help="0 = us")
    ap.add_argument("--enemy-ally", type=int, default=1)
    ap.add_argument("--minutes", type=float, default=None)
    args = ap.parse_args()

    run = Path(args.run)
    if not run.is_absolute():
        run = REPO / run
    ours = summarise(run, args.ally)
    print_report(f"{run.name}  (ally {args.ally} = us)", ours, args.minutes)

    theirs = summarise(run, args.enemy_ally)
    if theirs["exp"]:
        print_report(f"{run.name}  (ally {args.enemy_ally} = opponent)", theirs, args.minutes)

    if args.control:
        c = Path(args.control)
        if not c.is_absolute():
            c = REPO / c
        print_report(f"CONTROL {c.name} (ally {args.ally})",
                     summarise(c, args.ally), args.minutes)


if __name__ == "__main__":
    main()
