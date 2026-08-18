"""Per-team order volume from dev_order_counter.lua's ORDERS lines.

    python tools/orders.py <infolog-or-match-dir> [more...]

One row per game-minute: total orders across all teams, the busiest team, and
the class breakdown -- the ground truth for "how many actions do the AIs put
into the sim", to correlate against tools/frametime.py's ms/frame.
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

LINE = re.compile(r"ORDERS team=(\d+) min=(\d+) total=(\d+)(.*)")
KV = re.compile(r"(\w+)=(\d+)")

CLASSES = ["move", "fight", "patrol", "build", "repair", "reclaim",
           "guard", "stop", "other"]


def analyze(path):
    per_min = defaultdict(lambda: defaultdict(int))   # min -> class/total -> n
    team_tot = defaultdict(lambda: defaultdict(int))  # min -> team -> total
    for line in open(path, encoding="utf-8", errors="replace"):
        m = LINE.search(line)
        if not m:
            continue
        team, minute, total = int(m.group(1)), int(m.group(2)), int(m.group(3))
        per_min[minute]["total"] += total
        team_tot[minute][team] += total
        for k, v in KV.findall(m.group(4)):
            if k in CLASSES:
                per_min[minute][k] += int(v)

    print(f"\n{path}")
    print(f"{'min':>4} {'orders':>7} {'worst-team':>10} " +
          " ".join(f"{c:>7}" for c in CLASSES))
    for minute in sorted(per_min):
        row = per_min[minute]
        worst = max(team_tot[minute].values(), default=0)
        print(f"{minute:>4} {row['total']:>7} {worst:>10} " +
              " ".join(f"{row.get(c, 0):>7}" for c in CLASSES))
    if per_min:
        tot = sum(r["total"] for r in per_min.values())
        print(f"  whole run: {tot} orders; by class: " + ", ".join(
            f"{c}={sum(r.get(c, 0) for r in per_min.values())}"
            for c in CLASSES
            if sum(r.get(c, 0) for r in per_min.values()) > 0))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    for arg in sys.argv[1:]:
        p = Path(arg)
        if p.is_dir():
            p = p / "infolog.txt"
        if not p.exists():
            print(f"missing: {p}")
            continue
        analyze(p)


if __name__ == "__main__":
    main()
