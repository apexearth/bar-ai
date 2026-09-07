"""How often a unit's DESTINATION changes, and how long each one survived.

Companion to tools/orders.py. That tool reads the per-ORDER trace, which is the
wrong grain for "is anyone changing their mind": a unit walking a curved path
issues a stream of waypoints and revisits map squares, and counting those as
indecision produced a "travel -> travel bouncing" figure that measured nothing
but the shape of the road.

A GOAL change is somebody deciding the unit should be somewhere else. It is
logged from ITravelAction::SetPath -- the one place a new path, and therefore a
new destination, is handed to a unit. The goal is remembered on the UNIT, not on
the travel action, so being handed to a different task counts as the
redirection it is.

Needs apex_order_trace=1:

    python tools/run_match.py ... --modoption apex_order_trace=1
    python tools/goals.py <run>
    python tools/goals.py <run> --unit 18796
"""

import argparse
import collections
import pathlib
import re
import sys

GOAL_RE = re.compile(
    r"apex: goal t=(?P<team>-?\d+) u=(?P<uid>\d+) (?P<def>\S+) f=(?P<frame>\d+) "
    r"to=(?P<x>-?\d+),(?P<z>-?\d+) moved=(?P<moved>-?\d+) held=(?P<held>-?[\d.]+) "
    r"task=(?P<task>-?\d+)")

FRAMES_PER_MIN = 1800.0
# Under this a destination barely outlived the order that set it: the unit
# cannot have walked anywhere meaningful before being sent elsewhere.
CHURN_SECS = 5.0


def find_log(arg):
    p = pathlib.Path(arg)
    if p.is_dir():
        cand = p / "infolog.txt"
        if cand.exists():
            return cand
        raise SystemExit("no infolog.txt in %s" % p)
    if p.exists():
        return p
    here = pathlib.Path(__file__).resolve().parent.parent
    cand = here / "matches" / arg / "infolog.txt"
    if cand.exists():
        return cand
    raise SystemExit("cannot find a log for %r" % arg)


def load(path, team):
    per = collections.OrderedDict()
    with open(path, "r", errors="replace") as fh:
        for line in fh:
            if "apex: goal " not in line:
                continue
            m = GOAL_RE.search(line)
            if m is None:
                continue
            g = m.groupdict()
            if (team is not None) and (int(g["team"]) != team):
                continue
            per.setdefault(int(g["uid"]), []).append({
                "frame": int(g["frame"]), "def": g["def"],
                "x": int(g["x"]), "z": int(g["z"]),
                "moved": int(g["moved"]), "held": float(g["held"]),
                "task": int(g["task"])})
    return per


def summarise(per, limit):
    held = sorted(o["held"] for v in per.values() for o in v if o["held"] >= 0)
    moved = sorted(o["moved"] for v in per.values() for o in v if o["moved"] >= 0)
    n = sum(len(v) for v in per.values())
    print("%d destination changes over %d units" % (n, len(per)))
    if held:
        quick = sum(1 for h in held if h < CHURN_SECS)
        print("")
        print("  how long a destination lasted before it was replaced:")
        print("    median %.1fs    mean %.1fs" % (held[len(held) // 2],
                                                 sum(held) / len(held)))
        print("    under %.0fs: %d (%.0f%%)   under 15s: %d (%.0f%%)"
              % (CHURN_SECS, quick, 100.0 * quick / len(held),
                 sum(1 for h in held if h < 15),
                 100.0 * sum(1 for h in held if h < 15) / len(held)))
    if moved:
        print("")
        print("  how far the destination jumped when it changed:")
        print("    median %d elmos   mean %d   over 1000: %.0f%%"
              % (moved[len(moved) // 2], sum(moved) // len(moved),
                 100.0 * sum(1 for d in moved if d > 1000) / len(moved)))
    rows = sorted(((len(v),
                    sum(1 for o in v if 0 <= o["held"] < CHURN_SECS),
                    uid, v[0]["def"]) for uid, v in per.items()), reverse=True)
    print("")
    print("  worst:  changes  lasted<%.0fs  unit       def" % CHURN_SECS)
    for c, quick, uid, udef in rows[:limit]:
        print("    %11d %11d  %-10d %s" % (c, quick, uid, udef))
    if rows:
        print("")
        print("  python tools/goals.py <run> --unit %d   for the sequence" % rows[0][2])


def one_unit(per, uid):
    v = per.get(uid)
    if not v:
        raise SystemExit("no goal changes traced for unit %d" % uid)
    print("unit %d  %s  -- %d destination changes" % (uid, v[0]["def"], len(v)))
    print("")
    print("   min  destination      jumped  previous lasted  task")
    for o in v:
        print("%6.2f  %6d,%-6d %7s %14s  %d"
              % (o["frame"] / FRAMES_PER_MIN, o["x"], o["z"],
                 ("%d" % o["moved"]) if o["moved"] >= 0 else "-",
                 ("%.1fs" % o["held"]) if o["held"] >= 0 else "-",
                 o["task"]))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run", help="match dir, infolog path, or run name")
    ap.add_argument("--unit", type=int, help="one unit's destination sequence")
    ap.add_argument("--team", type=int, default=0)
    ap.add_argument("--worst", type=int, default=12)
    args = ap.parse_args()

    per = load(find_log(args.run), args.team)
    if not per:
        print("No `apex: goal` lines in that log.")
        print("The trace is off by default -- re-run the match with:")
        print("    --modoption apex_order_trace=1")
        return 1
    if args.unit is not None:
        one_unit(per, args.unit)
    else:
        summarise(per, args.worst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
