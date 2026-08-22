"""Units made per team, by def name -- what do we overbuild?

    python tools/units.py                     # latest live engine infolog
    python tools/units.py <match-or-run-dir>  # a finished match
    python tools/units.py --live              # newest matches/_engine*/infolog.txt

Counts BARAI_BUILD lines (one per unit creation, nanoframe included), so this
is unit COUNTS with metal alongside -- allBuilt in the stats rows is metal
only, which hides "500 cheap scouts".
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def find_log(arg: str | None) -> Path:
    if arg and arg not in ("--live",):
        p = Path(arg)
        if p.is_dir():
            p = p / "infolog.txt"
        if not p.exists():
            sys.exit(f"no infolog at {p}")
        return p
    logs = sorted(ROOT.glob("matches/_engine*/infolog.txt"),
                  key=lambda p: p.stat().st_mtime, reverse=True)
    if not logs:
        sys.exit("no live engine infolog found")
    return logs[0]

def main() -> None:
    arg = sys.argv[1] if len(sys.argv) > 1 else None
    log = find_log(arg)
    rx = re.compile(
        r"\[BARAI_BUILD\] team=(\d+) .*?frame=(\d+) .*?unit=(\w+) cost=(\d+)")
    count: dict[int, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    metal: dict[int, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    last_frame = 0
    with open(log, errors="replace") as f:
        for line in f:
            m = rx.search(line)
            if m:
                team, frame, unit, cost = m.groups()
                count[int(team)][unit] += 1
                metal[int(team)][unit] += int(cost)
                last_frame = max(last_frame, int(frame))
    # BARAI_BUILD covers only constructor-built structures; factory UNITS live
    # in the stats rows' allBuilt/cheapBuilt (metal by def). Merge the LAST
    # stats row per team so scouts and army show up too. Count is derived as
    # metal/unit-cost where a BARAI_BUILD line taught us the cost; otherwise
    # metal alone still ranks the overbuild.
    rx_stats = re.compile(r"\[BARAI_STATS\] team=(\d+) .*")
    last_stats: dict[int, str] = {}
    with open(log, errors="replace") as f:
        for line in f:
            m = rx_stats.search(line)
            if m:
                last_stats[int(m.group(1))] = line
    unit_cost: dict[str, float] = {}
    for t in metal:
        for u, m in metal[t].items():
            if count[t][u]:
                unit_cost[u] = m / count[t][u]
    for t, line in last_stats.items():
        for key in ("allBuilt", "cheapBuilt"):
            m = re.search(key + r"=([\w:,]+)", line)
            if not m:
                continue
            for kv in m.group(1).split(","):
                if ":" not in kv:
                    continue
                u, mv = kv.split(":")
                mv = int(mv)
                if mv > metal[t].get(u, 0):
                    metal[t][u] = mv
                    if u in unit_cost and unit_cost[u] > 0:
                        count[t][u] = int(mv / unit_cost[u])
    if not count:
        sys.exit(f"no BARAI_BUILD lines in {log} (dev gadgets installed?)")
    print(f"{log}  (through {last_frame/1800:.1f} min)")
    for team in sorted(count):
        rows = sorted(metal[team].items(), key=lambda kv: -kv[1])
        tot_m = sum(metal[team].values())
        print(f"\nteam {team}: {tot_m} metal built")
        print(f"  {'unit':<16}{'count':>6}{'metal':>9}  share")
        for unit, m in rows[:25]:
            n = count[team].get(unit, 0)
            print(f"  {unit:<16}{(str(n) if n else '?'):>6}{m:>9}  {100*m/max(1,tot_m):.0f}%")

if __name__ == "__main__":
    main()
