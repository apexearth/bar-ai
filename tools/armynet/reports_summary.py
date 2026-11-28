#!/usr/bin/env python3
"""One line per game from the report.md files game_report.py wrote: result, length, whose army reached the other's
extractors, how much ground each stood on, and B's top killers.

    python tools/armynet/reports_summary.py <match-dir>...      or      --campaign runtime/armynet/campaign-<stamp>
"""
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def line(md):
    p = md / "report.md"
    if not p.exists():
        return "%s: no report.md" % md.name
    s = p.read_text(encoding="utf-8")
    res = re.search(r"Result: (.*?) at ([\d.]+) min", s)
    r = re.findall(r"A (\d+) sq, (\d+) of B's mex \| B (\d+) sq, (\d+) of A's mex", s)
    n = max(len(r), 1)
    kb = re.search(r"^- B's: (.*)$", s, re.M)
    eco = re.search(r"A's economy (\d+) vs B's (\d+)", s)
    return "%s  %-6s %5s min | near mex A %3d B %3d | squares A %4.1f B %4.1f | eco lost A %6s B %6s | B killers: %s" % (
        md.name[-15:], res.group(1) if res else "?", res.group(2) if res else "?",
        sum(int(x[1]) for x in r), sum(int(x[3]) for x in r), sum(int(x[0]) for x in r) / n,
        sum(int(x[2]) for x in r) / n, eco.group(1) if eco else "-", eco.group(2) if eco else "-",
        ", ".join(kb.group(1).split(", ")[:3]) if kb else "-")


def main(a):
    if "--campaign" in a:
        log = Path(a[a.index("--campaign") + 1]) / "campaign.log"
        dirs = [REPO / "matches" / json.loads(ln[7:])["match"] for ln in open(log) if ln.startswith("RESULT ")
                and "match" in json.loads(ln[7:])]
    else:
        dirs = [Path(x) for x in a]
    for d in dirs:
        print(line(d))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
