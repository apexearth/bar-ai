#!/usr/bin/env python3
"""What each side's AI chose to build between two minutes (decide lines), and how often radar (sense) was the
runner-up, in armynet games -- side A's first radar comes ~14 min in every game (11-19 overnight).

    python tools/armynet/early_builds.py <engine write dir> ... [--from 3] [--to 8]
"""
import collections
import re
import sys
from pathlib import Path

DEC = re.compile(r"\[f=(\d+)\].*apex: decide t=(\d+) \S+ #\d+ -> (\w+)/(\S+?) v=([\d.]+).*?(?:over (\w+)/\S+ v=([\d.]+))?$")


def main(a):
    lo = float(a[a.index("--from") + 1]) if "--from" in a else 3
    hi = float(a[a.index("--to") + 1]) if "--to" in a else 8
    dirs = [x for i, x in enumerate(a) if not x.startswith("--") and (i == 0 or a[i - 1] not in ("--from", "--to"))]
    for d in dirs:
        base = Path(d) / "AI" / "Skirmish"
        print(Path(d).name)
        for t in (0, 1):
            logs = list(base.glob("*/*/apex-t%d.log" % t))
            won, over_sense, sense_v = collections.Counter(), collections.Counter(), []
            for lg in logs:
                for ln in open(lg, errors="replace"):
                    m = DEC.search(ln.rstrip())
                    if not m or not (lo * 1800 <= int(m.group(1)) < hi * 1800):
                        continue
                    won[m.group(3)] += 1
                    if m.group(6) == "sense":
                        over_sense[m.group(3)] += 1
                    if m.group(3) == "sense":
                        sense_v.append(float(m.group(5)))
            print("  team %d: built %s" % (t, dict(won.most_common(8))))
            print("          beat radar when radar was runner-up: %s; radar won %d times" % (
                dict(over_sense.most_common(6)), won["sense"]))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
