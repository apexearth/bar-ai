#!/usr/bin/env python3
"""Radar and jammer buildings each side started, per armynet game (his 11-18: "We no longer seem to be making
radar in the early game which makes it hard to deal with raiders").

    python tools/armynet/radar_builds.py [match dirs ...]   # default: every armynet game's engine dir
"""
import glob
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LINE = re.compile(r"\[BARAI_BUILD\] team=(\d+) ally=\d+ frame=\d+ min=([\d.]+) unit=(\w+)")
SENSE = re.compile(r"^(arm|cor|leg)(rad|arad|jamt|ajam|eyes)\w*$|radar|jam", re.I)


def main(a):
    dirs = a or sorted(glob.glob(str(REPO / "matches" / "*armynet*")), key=lambda p: Path(p).stat().st_mtime)
    for d in dirs:
        log = Path(d) / "barai-gadgets.log"
        if not log.exists():
            continue
        by = {}
        for ln in open(log, errors="replace"):
            m = LINE.search(ln)
            if m and SENSE.search(m.group(3)):
                by.setdefault(int(m.group(1)), []).append((float(m.group(2)), m.group(3)))
        cells = []
        for t in sorted(by) or [0, 1]:
            rows = sorted(by.get(t, []))
            early = [r for r in rows if r[0] < 10]
            first = "%.1f" % rows[0][0] if rows else "-"
            cells.append("team %d: %d before 10 min, %d in all, first at %s min" % (t, len(early), len(rows), first))
        print("%-46s %s" % (Path(d).name[:46], " | ".join(cells)))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
