#!/usr/bin/env python3
"""Flank guards per minute (flankguard.as, TUNE_FLANK_GUARD).

    python tools/flankstat.py <match|tournament|run> [...] [--step 2]

One match: per seat, a row per minute from `apex: flank-stat` -- sectors,
eligible sectors, groups, units and metal standing in them, the raid wave they
are sized for, and per-interval deltas of orders, engagements, enemy metal we
killed in guarded sectors, our economy lost in them, and our economy lost on
any open (untowered) approach. A tournament: one line per match, final totals.
No flank-stat lines means the switch was off (or the script did not compile).
"""
import glob
import os
import re
import sys

LINE = re.compile(r"\[(\d+(?:\.\d+)?)m t\d+\] apex: flank-stat t=(\d+) (.*)")
KV = re.compile(r"(\w+)=(-?\d+)")
CUM = ("orders", "formed", "resite", "disband", "short", "eng", "killedM", "lostM", "lostOpenM")


def matches(args):
    for a in args:
        if os.path.isfile(os.path.join(a, "infolog.txt")):
            yield a
        else:
            for m in sorted(glob.glob(os.path.join(a, "matches", "*"))):
                if os.path.isfile(os.path.join(m, "infolog.txt")):
                    yield m


def read(m):
    seats = {}
    with open(os.path.join(m, "infolog.txt"), errors="replace") as f:
        for line in f:
            if "flank-stat" not in line:
                continue
            g = LINE.search(line)
            if not g:
                continue
            row = {k: int(v) for k, v in KV.findall(g.group(3))}
            row["min"] = float(g.group(1))
            seats.setdefault(int(g.group(2)), []).append(row)
    return seats


def per_minute(m, step):
    seats = read(m)
    if not seats:
        print(f"{os.path.basename(m)}: no flank-stat lines (switch off?)")
        return
    for t, rows in sorted(seats.items()):
        print(f"\n{os.path.basename(m)} seat t{t}")
        print(f"{'min':>5} {'sec':>3} {'elig':>4} {'grp':>3} {'units':>5} {'metal':>6} {'wave':>5}"
              f" {'orders':>6} {'eng':>3} {'killM':>6} {'lostM':>6} {'openM':>6}")
        prev = {k: 0 for k in CUM}
        last = -1e9
        for r in rows + [None]:
            if r is not None and r["min"] - last < step:
                continue
            if r is None:
                break
            d = {k: r.get(k, 0) - prev[k] for k in CUM}
            prev = {k: r.get(k, 0) for k in CUM}
            last = r["min"]
            print(f"{r['min']:5.1f} {r.get('sectors', 0):3d} {r.get('eligible', 0):4d} {r.get('groups', 0):3d}"
                  f" {r.get('units', 0):5d} {r.get('metal', 0):6d} {r.get('wave', 0):5d}"
                  f" {d['orders']:6d} {d['eng']:3d} {d['killedM']:6d} {d['lostM']:6d} {d['lostOpenM']:6d}")
        f = rows[-1]
        print(f"  total: formed={f.get('formed', 0)} resite={f.get('resite', 0)} disband={f.get('disband', 0)}"
              f" short={f.get('short', 0)} orders={f.get('orders', 0)} eng={f.get('eng', 0)}"
              f" killedM={f.get('killedM', 0)} lostM={f.get('lostM', 0)} lostOpenM={f.get('lostOpenM', 0)}")


def summary(ms):
    print(f"{'match':<28} {'seat':>4} {'min':>5} {'formed':>6} {'orders':>6} {'eng':>4}"
          f" {'killM':>6} {'lostM':>6} {'openM':>6}")
    for m in ms:
        for t, rows in sorted(read(m).items()):
            f = rows[-1]
            print(f"{os.path.basename(m):<28} {t:>4} {f['min']:5.1f} {f.get('formed', 0):6d} {f.get('orders', 0):6d}"
                  f" {f.get('eng', 0):4d} {f.get('killedM', 0):6d} {f.get('lostM', 0):6d} {f.get('lostOpenM', 0):6d}")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    step = 1.0
    if "--step" in sys.argv:
        step = float(sys.argv[sys.argv.index("--step") + 1])
        args = [a for a in args if a != sys.argv[sys.argv.index("--step") + 1]]
    if not args:
        print(__doc__)
        return 2
    ms = list(matches(args))
    if len(ms) == 1:
        per_minute(ms[0], step)
    else:
        summary(ms)
    return 0


if __name__ == "__main__":
    sys.exit(main())
