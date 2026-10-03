#!/usr/bin/env python3
"""What each seat of a team game built by a minute: eco structures counted per seat.

    python tools/seatbuilds.py <match-dir> [--by 20] [--units armmakr,armmmkr,...]

From [BARAI_BUILD] (finished structures) and [BARAI_PROD] (factory units) in
the infolog. One row per engine team, our side first; the default columns are
the economy: extractors, converters, generators, nanos, T2 constructors.
"""
from __future__ import annotations

import collections
import re
import sys
from pathlib import Path

LINE_RE = re.compile(r"\[BARAI_(?:BUILD|PROD)\] team=(\d+) ally=(\d+) frame=(\d+) min=[\d.]+ unit=(\S+) cost=(\d+)")
ECO_RE = re.compile(r"eco-status team=(\d+) growing=(\d)")
DEFAULT = ("armmex,armmoho,armmakr,armmmkr,armsolar,armadvsol,armwin,armfus,armafus,armnanotc,armack,armacv,armaca")


def main() -> int:
    args = sys.argv[1:]
    by = 20.0
    units = DEFAULT
    if "--by" in args:
        i = args.index("--by")
        by = float(args[i + 1])
        del args[i:i + 2]
    if "--units" in args:
        i = args.index("--units")
        units = args[i + 1]
        del args[i:i + 2]
    cols = units.split(",")
    for a in args:
        text = (Path(a) / "infolog.txt").read_text(encoding="utf8", errors="ignore")
        ally = {}
        n = collections.defaultdict(collections.Counter)
        for m in LINE_RE.finditer(text):
            t = int(m.group(1))
            ally[t] = int(m.group(2))
            if int(m.group(3)) <= by * 1800:
                n[t][m.group(4)] += 1
        grow = collections.Counter()
        for m in ECO_RE.finditer(text):
            grow[int(m.group(1))] += int(m.group(2))
        eco = grow.most_common(1)[0][0] if grow else -1
        us = ally.get(eco, 0)
        print(f"== {Path(a).name}  built by minute {by:g} (E = our eco seat)")
        print("  seat  " + " ".join(f"{c[3:] if c.startswith('arm') else c:>7}" for c in cols))
        for side in (us, 1 - us):
            for t in sorted(ally):
                if ally[t] != side:
                    continue
                tag = ("E" if t == eco else ("t" if side == us else "b")) + str(t)
                print(f"  {tag:<5} " + " ".join(f"{n[t][c]:>7}" for c in cols))
            print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
