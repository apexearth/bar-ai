#!/usr/bin/env python3
"""Metal-weighted speed of the army units each side made, by minute, in an armynet game (from barai-gadgets.log
[BARAI_PROD] and the bridge's armynet_static.txt speeds) -- to set against players' (players_by_minute.py).

    python tools/armynet/army_speed.py <engine write dir> ...
"""
import collections
import re
import sys
from pathlib import Path

PROD = re.compile(r"\[BARAI_PROD\] team=(\d+) ally=\d+ frame=(\d+) min=[\d.]+ unit=(\w+) cost=([\d.]+)")


def main(a):
    for d in a:
        d = Path(d)
        speed, cls = {}, {}
        for ln in open(d / "armynet_static.txt", errors="replace"):
            p = ln.split()
            if p and p[0] == "D":
                speed[p[2]], cls[p[2]] = float(p[6]), p[3]
        made = collections.defaultdict(list)
        for ln in open(d / "barai-gadgets.log", errors="replace"):
            m = PROD.search(ln)
            if m and cls.get(m.group(3)) in ("army", "air"):
                made[(int(m.group(1)), int(m.group(2)) // 1800 // 4 * 4)].append((m.group(3), float(m.group(4))))
        print(d.name)
        for t in (0, 1):
            cells = []
            for mins in range(0, 24, 4):
                rows = made.get((t, mins), [])
                w = sum(c for _, c in rows)
                s = sum(speed.get(u, 0) * c for u, c in rows) / w if w else float("nan")
                top = collections.Counter(u for u, _ in rows).most_common(2)
                cells.append("%2d-%2d: %5.1f %s" % (mins, mins + 3, s, ",".join("%s x%d" % kv for kv in top)))
            print("  team %d  " % t + " | ".join(cells))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
