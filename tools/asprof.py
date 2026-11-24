"""Where the script time goes, line by line: aggregates the `apex: asprof` lines (apex_asprof=K, ScriptManager.cpp).

    python tools/asprof.py <run> [--top 40] [--from-min M] [--to-min M]

One Exec in K runs under a line callback; times are scaled by K to whole-game estimates, summed over every
Apex player. `line`/`self` are a line's or function's own time (callees excluded), `incl` counts a function
once however deep it recurses. The callback itself slows the script ~2-4x and the election slices react to
that, so read shares, not absolute ms.
"""
import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

WIN = re.compile(r"apex: asprof win k=(\d+) execs=(\d+) totalMs=([\d.]+) frame=(\d+)")
ROW = re.compile(r"apex: asprof (line|self|incl) ([\d.]+) (\d+) (.+)$")


def logs(run: Path):
    files = sorted(run.glob("**/apex-t*.log"))
    return files or [p for p in [run / "infolog.txt"] if p.exists()]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run")
    ap.add_argument("--top", type=int, default=40)
    ap.add_argument("--from-min", type=float, default=0.0)
    ap.add_argument("--to-min", type=float, default=1e9)
    ap.add_argument("--overhead-ns", type=float, default=95.0,
                    help="callback cost per line hit, taken off `line` and `self` (default 95: the cheapest lines "
                         "measured ~100 ns/hit while the VM runs a trivial line in ~10, 11-24 8v8)")
    a = ap.parse_args()
    run = Path(a.run)
    files = logs(run)
    if not files:
        print("no logs under", run)
        return 2
    acc = {k: defaultdict(lambda: [0.0, 0]) for k in ("line", "self", "incl")}
    total = 0.0
    wins = 0
    k = 1
    for f in files:
        take = False
        for raw in f.open(encoding="utf-8", errors="replace"):
            m = WIN.search(raw)
            if m:
                k = int(m.group(1))
                minute = int(m.group(4)) / 1800.0
                take = a.from_min <= minute <= a.to_min
                if take:
                    total += float(m.group(3)) * k
                    wins += 1
                continue
            if not take:
                continue
            m = ROW.search(raw)
            if m:
                e = acc[m.group(1)][m.group(4).strip()]
                e[0] += float(m.group(2)) * k
                e[1] += int(m.group(3)) * k
    if wins == 0:
        print("no asprof windows (was apex_asprof set, and is apex_asprof in dev_tunables.lua?)")
        return 1
    oh = a.overhead_ns / 1e6
    lineHits = sum(h for _, h in acc["line"].values())
    print("%d windows, %.0f ms of script (est., all players), of it ~%.0f ms callback overhead on listed lines"
          % (wins, total, lineHits * oh))
    for kind, title in (("incl", "inclusive by function (raw: overhead included)"),
                        ("self", "self by function, overhead taken off"), ("line", "self by line, overhead taken off")):
        print("\n%s" % title)
        print("  %9s %9s %12s  %s" % ("ms", "raw ms", "hits", "where"))
        net = lambda v: v[0] - (v[1] * oh if kind != "incl" else 0.0)
        rows = sorted(acc[kind].items(), key=lambda kv: -net(kv[1]))[:a.top]
        for name, v in rows:
            print("  %9.0f %9.0f %12d  %s" % (net(v), v[0], v[1], name))
    print("\n(each window lists its own top 40 only, so a long tail is under-counted)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
