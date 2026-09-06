"""One unit's control lifecycle: every order it got, and which logic centre sent it.

apexearth 2026-09-06: "imagine if you can just grep a unit's command history and
see the source of those commands... then you can know whats really happening."

The order census (`apex: order-src`) says how much churn there is and which call
site made it, then throws away WHO it happened to -- so a unit being pulled
between two logic centres is invisible in the aggregate. This reads the
per-order trace instead.

Needs `apex_order_trace=1`, which is off by default (~4k lines a minute):

    python tools/run_match.py ... --modoption apex_order_trace=1

Usage:
    python tools/orders.py <run>                  # the worst-controlled units
    python tools/orders.py <run> --unit 8925      # one unit's whole history
    python tools/orders.py <run> --pairs          # which centres fight each other
    python tools/orders.py <run> --def armsnipe   # worst units of one type

A CONTRADICTION is the thing he described: a different logic centre moving the
unit somewhere else, far away, while the previous order was plausibly still
running. Both halves matter -- a re-send of the same goal is waste, but a far
jump from a different source is two pieces of code disagreeing about what the
unit is for.
"""

import argparse
import collections
import pathlib
import re
import sys

ORD_RE = re.compile(
    r"apex: ord t=(?P<team>-?\d+) u=(?P<uid>\d+) (?P<def>\S+) f=(?P<frame>\d+) "
    r"src=(?P<src>\S+) kind=(?P<kind>\S+) to=(?P<x>-?\d+),(?P<z>-?\d+) "
    r"tgt=(?P<tgt>-?\d+) jump=(?P<jump>-?\d+) gap=(?P<gap>-?\d+) "
    r"task=(?P<task>-?\d+)/(?P<taskframe>-?\d+) dup=(?P<dup>\d)"
    r"(?: q=(?P<q>\d))?"
)

FRAMES_PER_MIN = 1800.0
# Inside this the previous order is plausibly still running -- the same window
# the C++ census uses to call a re-send a repeat.
CONTRADICT_GAP = 90      # frames (3s)
# A goal that moved less than this is a nudge, not a change of mind. One
# building footprint, matching the census's own lt128 bucket edge.
CONTRADICT_JUMP = 128.0


class Order(object):
    __slots__ = ("team", "uid", "udef", "frame", "src", "kind", "x", "z",
                 "tgt", "jump", "gap", "task", "taskframe", "dup", "queued")

    def __init__(self, m):
        g = m.groupdict()
        self.team = int(g["team"])
        self.uid = int(g["uid"])
        self.udef = g["def"]
        self.frame = int(g["frame"])
        self.src = g["src"]
        self.kind = g["kind"]
        self.x = int(g["x"])
        self.z = int(g["z"])
        self.tgt = int(g["tgt"])
        self.jump = float(g["jump"])
        self.gap = int(g["gap"])
        self.task = int(g["task"])
        self.taskframe = int(g["taskframe"])
        self.dup = g["dup"] == "1"
        # Absent in logs from before the q= field: assume a replacement, which
        # is what the old analysis silently assumed anyway.
        self.queued = g.get("q") == "1"


def find_log(arg):
    p = pathlib.Path(arg)
    if p.is_dir():
        cand = p / "infolog.txt"
        if cand.exists():
            return cand
        raise SystemExit("no infolog.txt in %s" % p)
    if p.exists():
        return p
    # bare run name
    here = pathlib.Path(__file__).resolve().parent.parent
    for base in (here / "matches" / arg, here / "matches" / arg / "infolog.txt"):
        if base.is_dir() and (base / "infolog.txt").exists():
            return base / "infolog.txt"
        if base.is_file():
            return base
    raise SystemExit("cannot find a log for %r" % arg)


def load(path, team=None):
    per_unit = collections.OrderedDict()
    n = 0
    with open(path, "r", errors="replace") as fh:
        for line in fh:
            if "apex: ord " not in line:
                continue
            m = ORD_RE.search(line)
            if m is None:
                continue
            o = Order(m)
            if (team is not None) and (o.team != team):
                continue
            per_unit.setdefault(o.uid, []).append(o)
            n += 1
    return per_unit, n


def has_pos(o):
    """An attack/settarget order names a UNIT, not a point -- it logs to=0,0.

    Comparing that to a real map position measures the distance from the map
    corner, which read as a mean 9,267-elmo "jump" on the first run and meant
    nothing. Those handoffs are still contradictions (told to shoot that unit,
    then told to walk elsewhere) -- they just cannot be scored in elmos.
    """
    return not (o.tgt > 0 and o.x == 0 and o.z == 0)


def contradictions(orders):
    """Consecutive orders where a DIFFERENT centre redirected the unit, fast.

    Returns (prev, cur, dist) with dist None when one side named a target
    instead of a point.
    """
    out = []
    for prev, cur in zip(orders, orders[1:]):
        if cur.src == prev.src:
            continue
        # A SHIFT order is APPENDED to the queue -- adding a waypoint, not
        # disagreeing about where the unit is going. MoveAction queues a
        # lookahead waypoint on every step by design.
        if cur.queued:
            continue
        if (cur.frame - prev.frame) > CONTRADICT_GAP:
            continue
        if not (has_pos(prev) and has_pos(cur)):
            out.append((prev, cur, None))
            continue
        dist = ((cur.x - prev.x) ** 2 + (cur.z - prev.z) ** 2) ** 0.5
        if dist < CONTRADICT_JUMP:
            continue
        out.append((prev, cur, dist))
    return out


def cmd_unit(per_unit, uid):
    orders = per_unit.get(uid)
    if not orders:
        raise SystemExit("no orders traced for unit %d" % uid)
    cons = contradictions(orders)
    bad = {id(c): d for _, c, d in cons}
    prevframe = {id(c): p.frame for p, c, _ in cons}
    print("unit %d  %s  (team %d)  %d orders, %d sources"
          % (uid, orders[0].udef, orders[0].team, len(orders),
             len(set(o.src for o in orders))))
    print()
    print("   min  src        kind    destination      jump   gap  task")
    for o in orders:
        mark = ""
        if id(o) in bad:
            d = bad[id(o)]
            mark = ("  << redirected, %.1fs after the last order" % (
                        (o.frame - prevframe[id(o)]) / 30.0)
                    if d is None else
                    "  << %.0f elmos from the last order, %.1fs after it" % (
                        d, (o.frame - prevframe[id(o)]) / 30.0))
        tgt = ("  tgt=%d" % o.tgt) if o.tgt > 0 else ""
        print("%6.2f  %-10s %-7s %5d,%-5d %7s %5s  %d/%d%s%s"
              % (o.frame / FRAMES_PER_MIN, o.src, o.kind, o.x, o.z,
                 ("%.0f" % o.jump) if o.jump >= 0 else "-",
                 o.gap if o.gap >= 0 else "-",
                 o.task, o.taskframe, tgt, mark))
    print()
    srcs = collections.Counter(o.src for o in orders)
    print("by source: " + ", ".join("%s=%d" % kv for kv in srcs.most_common()))
    print("contradictions: %d of %d orders (%.0f%%)"
          % (len(bad), len(orders), 100.0 * len(bad) / len(orders)))


def cmd_worst(per_unit, total, limit, want_def=None):
    rows = []
    for uid, orders in per_unit.items():
        if want_def and orders[0].udef != want_def:
            continue
        con = contradictions(orders)
        rows.append((len(con), len(orders), len(set(o.src for o in orders)),
                     uid, orders[0].udef,
                     orders[0].frame / FRAMES_PER_MIN,
                     orders[-1].frame / FRAMES_PER_MIN))
    if not rows:
        raise SystemExit("no traced units matched")
    rows.sort(reverse=True)
    print("%d orders traced over %d units" % (total, len(per_unit)))
    print()
    print("WORST-CONTROLLED UNITS  (a contradiction = another centre REPLACING")
    print("the order with one >=%d elmos away, within %.0fs. Queued waypoints"
          % (CONTRADICT_JUMP, CONTRADICT_GAP / 30.0))
    print("are appends, not arguments, and are excluded.)")
    print()
    print("  contra  orders   src  unit      def            alive")
    for con, n, nsrc, uid, udef, t0, t1 in rows[:limit]:
        print("  %6d  %6d  %4d  %-9d %-14s %.1f-%.1fmin  %s"
              % (con, n, nsrc, uid, udef, t0, t1,
                 "%.0f%%" % (100.0 * con / n) if n else ""))
    print()
    print("  python tools/orders.py <run> --unit %d   for the full history"
          % rows[0][3])


def cmd_pairs(per_unit, limit):
    pairs = collections.Counter()
    dist = collections.Counter()
    measured = collections.Counter()
    for orders in per_unit.values():
        for prev, cur, d in contradictions(orders):
            key = (prev.src, cur.src)
            pairs[key] += 1
            if d is not None:
                dist[key] += d
                measured[key] += 1
    if not pairs:
        raise SystemExit("no contradictions found")
    print("WHICH CENTRES FIGHT OVER THE SAME UNITS")
    print("(count, and the mean distance the goal jumped)")
    print()
    print("  count   mean jump  handoff")
    for (a, b), n in pairs.most_common(limit):
        m = measured[(a, b)]
        jump = ("%8.0f" % (dist[(a, b)] / m)) if m else "       -"
        print("  %5d  %s   %s -> %s%s"
              % (n, jump, a, b,
                 "" if m == n else "   (%d name a target, not a point)" % (n - m)))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run", help="match dir, infolog path, or run name")
    ap.add_argument("--unit", type=int, help="print this unit's whole history")
    ap.add_argument("--worst", type=int, default=20, help="how many units to rank")
    ap.add_argument("--pairs", action="store_true",
                    help="which pairs of logic centres contradict each other")
    ap.add_argument("--def", dest="udef", help="only units of this def")
    ap.add_argument("--team", type=int, help="only this team")
    args = ap.parse_args()

    path = find_log(args.run)
    per_unit, total = load(path, args.team)
    if not per_unit:
        print("No `apex: ord` lines in %s." % path)
        print("The trace is off by default -- re-run with:")
        print("    --modoption apex_order_trace=1")
        return 1

    if args.unit is not None:
        cmd_unit(per_unit, args.unit)
    elif args.pairs:
        cmd_pairs(per_unit, args.worst)
    else:
        cmd_worst(per_unit, total, args.worst, args.udef)
    return 0


if __name__ == "__main__":
    sys.exit(main())
