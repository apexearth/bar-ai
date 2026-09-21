#!/usr/bin/env python3
"""The allies of an 8v8, read as one side: income, spend split and count alive
per two minutes, the eco seat set apart, against the enemy side.
apexearth 2026-09-21: "our eco-player does really, really well... but all of
our allies, they just suck throughout the entire game... they just never
scale." The seat's curve is his reference; this is the other seven's.
    python tools/allies.py <match-dir | run-dir> [--seat N] [--every 2]
    python tools/allies.py matches/_engine            # his live game
Reads [BARAI_STATS] periodic rows (barai-gadgets.log or infolog.txt). The seat
is the team seat.py names (eco-status growing=1 longest); pass --seat to
override. The 'allies' column sums every ally-0 team but the seat; 'alive'
counts teams with income > 0.
"""
import argparse
import collections
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def stats_path(d):
    for name in ("barai-gadgets.log", "infolog.txt"):
        p = os.path.join(d, name)
        if os.path.isfile(p) and "BARAI_STATS" in open(p, errors="replace").read(4_000_000):
            return p
    return os.path.join(d, "infolog.txt")


def seat_of(d):
    try:
        out = subprocess.run([sys.executable, os.path.join(HERE, "seat.py"), d],
                             capture_output=True, text=True, timeout=120).stdout
        m = re.search(r"seat=t(\d+)", out)
        return int(m.group(1)) if m else None
    except Exception:
        return None


def rows_of(path):
    rows = collections.defaultdict(dict)
    for line in open(path, errors="replace"):
        if "[BARAI_STATS]" not in line:
            continue
        kv = dict(re.findall(r" (\w+)=([^ ]*)", line))
        if kv.get("reason") != "periodic":
            continue
        rows[int(kv["frame"]) // 1800][int(kv["team"])] = kv
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run")
    ap.add_argument("--seat", type=int, default=None)
    ap.add_argument("--every", type=int, default=2)
    args = ap.parse_args()
    rows = rows_of(stats_path(args.run))
    if not rows:
        sys.exit("no [BARAI_STATS] rows under %s" % args.run)
    seat = args.seat if args.seat is not None else seat_of(args.run)
    print("seat=t%s" % seat if seat is not None else "seat: none found")
    fields = ("mInc", "mEco", "mArmy", "mBP")
    print("%4s | %-10s %7s %7s %7s %5s | %8s | %-10s %7s %7s %7s %5s"
          % ("min", "allies inc", "eco", "army", "bp", "alive", "seat inc",
             "enemy inc", "eco", "army", "bp", "alive"))
    for m in sorted(rows):
        if m % args.every:
            continue
        r = rows[m]

        def agg(sel):
            ts = [t for t in r if sel(t)]
            return ([sum(float(r[t].get(f, 0)) for t in ts) for f in fields]
                    + [sum(1 for t in ts if float(r[t].get("mInc", 0)) > 0)])
        a = agg(lambda t: r[t]["ally"] == "0" and t != seat)
        s = agg(lambda t: t == seat)
        b = agg(lambda t: r[t]["ally"] == "1")
        print("%4d | %10.0f %7.0f %7.0f %7.0f %5d | %8.0f | %10.0f %7.0f %7.0f %7.0f %5d"
              % (m, a[0], a[1], a[2], a[3], a[4], s[0], b[0], b[1], b[2], b[3], b[4]))


if __name__ == "__main__":
    main()
