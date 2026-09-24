"""Run the canon eco-only board, N seeds per arm, and print the income curve.

    python tools/ecoboard.py --lane <spec> [--seeds 4] [--minutes 20]
                             [--arm NAME=modopt,modopt ...] [--scav]

apexearth's idea, 2026-09-23: measure economic efficiency against an inactive
AI, where no fighting confounds the curve and the game lives long enough to
reach the decisions a 2v2 never gets to.

Two warnings the canon-eco memory records and this script obeys:

  * THE BOARD IS NOT DETERMINISTIC. The AI is time-sliced against the wall
    clock, so the same tree and seed gave 700/771/845 m/s at minute 20. Four
    runs an arm is the floor and arms are read as means WITH ranges.
  * Runs are SEQUENTIAL. Two at once contend for the wall clock and the
    numbers stop meaning anything.

THE BOARD IS NOT A PROXY FOR A REAL GAME: anything priced off income over
build capacity reads true utilization here and permanently low in a game with
an army. Confirm an eco change against a real opponent before landing it.
"""
import argparse
import collections
import glob
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CANON = "Comet Catcher Remake 1.8"
# his curve, metal/s at minute -> the score is our ratio to it
HIS = {5: 65, 8: 244, 10: 352, 12: 529, 14: 900, 16: 1570}

STAT = re.compile(r"BARAI_STATS\] team=(\d+) ally=\d+ reason=\w+ frame=(\d+) ")
MINC = re.compile(r"\bmInc=([\d.]+)")
EINC = re.compile(r"\beInc=([\d.]+)")
MEX = re.compile(r"\bmex=(\d+)")


def run(lane, out, seed, minutes, modopts, mapname, handicap):
    cmd = [sys.executable, os.path.join(HERE, "run_match.py"),
           "--a", lane, "--b", "NullAI:0.1", "--map", mapname,
           "--minutes", str(minutes), "--handicap", str(handicap),
           "--speed", "5",
           "--seed", str(seed), "--out", out,
           "--modoption", "dev_stats=1", "--modoption", "apex_eco_only=1",
           # NullAI's commander dies to the map ruins and the game ends at
           # minute 9-15 with us the winner, truncating the curve.
           "--modoption", "deathmode=neverend"]
    for m in modopts:
        cmd += ["--modoption", m]
    subprocess.run(cmd, cwd=ROOT, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)


def curve(d):
    """minute -> (mInc, eInc) for our team, from this match's infolog."""
    info = os.path.join(d, "infolog.txt")
    if not os.path.exists(info):
        return {}
    out = {}
    for ln in open(info, encoding="utf-8", errors="replace"):
        m = STAT.search(ln)
        if not m or int(m.group(1)) != 0:
            continue
        mi, ei = MINC.search(ln), EINC.search(ln)
        if not (mi and ei):
            continue
        mx = MEX.search(ln)
        out[int(int(m.group(2)) / 30 / 60)] = (float(mi.group(1)),
                                               float(ei.group(1)),
                                               int(mx.group(1)) if mx else 0)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lane", required=True)
    ap.add_argument("--seeds", type=int, default=4)
    ap.add_argument("--minutes", type=int, default=20)
    ap.add_argument("--map", default=CANON,
                    help="a low-spot map measures growth with extraction capped")
    ap.add_argument("--handicap", type=int, default=50,
                    help="resource bonus; his reference game was +50% (verified in the demo)")
    ap.add_argument("--scav", action="store_true",
                    help="his regime: the scavenger pack's *t3 units")
    ap.add_argument("--arm", action="append", default=[],
                    help="NAME=modopt[,modopt] -- repeatable")
    a = ap.parse_args()

    base = ["experimentalextraunits=1", "scavunitsforplayers=1"] if a.scav else []
    arms = []
    for spec in (a.arm or ["stock="]):
        name, _, mods = spec.partition("=")
        arms.append((name, base + [m for m in mods.split(",") if m]))

    res = collections.defaultdict(lambda: collections.defaultdict(list))
    for name, mods in arms:
        for s in range(1, a.seeds + 1):
            # the map goes in the path: two boards sharing one directory
            # silently overwrote the first board's census.
            slug = "".join(c if c.isalnum() else "_" for c in a.map)[:16]
            out = os.path.join("matches", "eco-%s-%s-s%d" % (slug, name, s))
            print("  running %s seed %d ..." % (name, s), flush=True)
            run(a.lane, out, s, a.minutes, mods, a.map, a.handicap)
            c = curve(os.path.join(ROOT, out))
            if not c:
                print("    no stats (did it run?)")
                continue
            for mn, row in c.items():
                res[name][mn].append(row)

    # S3: a compile error disables the variant and the board still prints a
    # tidy table of near-zero numbers. Warnings are errors here, and as_scope
    # does not catch a shadowed local -- only a smoke test or this guard does.
    for name, _ in arms:
        peak = max((x[0] for rows in res[name].values() for x in rows),
                   default=0.0)
        if peak < 20.0:
            print("!! arm %r never built anything (peak %.0f m/s) -- the script"
                  " almost certainly did not compile." % (name, peak))
            print("   check it: python tools/smoke.py --ai %s" % a.lane)

    canon = (a.map == CANON)
    mins = (sorted(m for m in HIS if m <= a.minutes) if canon
            else [m for m in range(4, a.minutes + 1, 4)])
    print()
    print("map: %s%s" % (a.map, "" if canon else          "  (his curve is the canon map only -- no ratio shown)"))
    print()
    print("metal/s by minute -- mean [min-max] over seeds")
    print("  %-10s %6s   %s" % ("arm", "min", "m/s"))
    for name, _ in arms:
        for mn in mins:
            v = [x[0] for x in res[name].get(mn, [])]
            if not v:
                continue
            mean = sum(v) / len(v)
            mx = [x[2] for x in res[name].get(mn, [])]
            tail = ("   his %5d   %.2fx" % (HIS[mn], mean / HIS[mn])) if canon else ""
            # per-seed values, not just the range: a 4-seed arm cannot be
            # judged from a mean and two extremes.
            print("  %-10s %6d   %7.0f [%s]  n=%d   mex %2.0f%s"
                  % (name, mn, mean, " ".join("%.0f" % x for x in sorted(v)),
                     len(v), (sum(mx) / len(mx)) if mx else 0, tail))
        print()
    print("energy/s by minute")
    for name, _ in arms:
        row = []
        for mn in mins:
            v = [x[1] for x in res[name].get(mn, [])]
            if v:
                row.append("%d:%.0f" % (mn, sum(v) / len(v)))
        print("  %-10s %s" % (name, "  ".join(row)))


main()
