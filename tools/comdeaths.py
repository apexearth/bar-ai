"""How commanders die in a tournament of Apex versions.

    python tools/comdeaths.py <tournament-dir>...

Per commander death: the AI that lost it, the minute, how far forward
(fwd: 0 at its own home, 1 at the enemy's), what it was doing last
(curTask and the tail of its order history), and its own vs the enemy's army
metal at the nearest stats sample.
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

LINE = re.compile(r"Skirmish AI <[^>]*?-([\w.]+)>: \[[\d.]+m t(\d+)\] apex: unit-destroyed (\w*com\w*) acts=(\S*) .*?frame=(\d+) .*?curTask=(\S+) cost=\d+ fwd=([\d.-]+) thr=([\d.]+)")


def army_at(stats, team, frame):
    rows = [r for r in stats if int(r.get("team", -1)) == team and r.get("reason") == "periodic"
            and r.get("frame", 0) <= frame]
    return rows[-1].get("mArmy", 0.0) if rows else 0.0


def main():
    by = Counter()
    fwds = {}
    for d in sys.argv[1:]:
        for res in sorted(Path(d).glob("matches/*/result.json")):
            r = json.loads(res.read_text("utf-8"))
            txt = (res.parent / "stdout.txt").read_text("utf-8", errors="replace")
            stats = r.get("stats") or []
            for m in LINE.finditer(txt):
                ver, team, unit, acts, frame, task, fwd, thr = m.groups()
                t, f = int(team), int(frame)
                mine, theirs = army_at(stats, t, f), army_at(stats, 1 - t, f)
                tail = ">".join(acts.split(">")[:4])
                print(f"{ver:8s} t{t} {f / 1800:5.1f}m fwd {float(fwd):4.2f} thr {float(thr):6.1f} "
                      f"army {mine / 1000:5.1f}k vs {theirs / 1000:5.1f}k  task {task:14s} acts {tail}")
                by[ver] += 1
                fwds.setdefault(ver, []).append(float(fwd))
    print()
    for v, n in by.items():
        fw = fwds[v]
        print(f"{v}: {n} commander deaths, fwd median {sorted(fw)[len(fw) // 2]:.2f}, "
              f"past midfield {sum(x > 0.5 for x in fw)}, at home (<0.2) {sum(x < 0.2 for x in fw)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
