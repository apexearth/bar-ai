#!/usr/bin/env python3
"""Extractor-upgrade jobs per match: how many finished, how many were aborted,
and how many of the picks were an ally's extractor.

    python tools/upjobs.py <match-dir> [...]

Reads the last `apex: task-gone` line per team (cumulative done/abort per def)
and the `apex: mexup ... ally=` picks, both in the infolog. Defs counted as
upgrades: the T2 extractors (moho, uwmme, and the Legion/Cortex names).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

UP = ("armmoho", "cormoho", "legmoho", "armuwmme", "coruwmme")
GONE_RE = re.compile(r"apex: task-gone t=(\d+) \|(.*)")
DEF_RE = re.compile(r"(\w+) done=(\d+) abort=(\d+)")
PICK_RE = re.compile(r"apex: mexup t=\d+ .* ally=([01])")


def main() -> int:
    tot_d = tot_a = tot_own = tot_ally = 0
    for a in sys.argv[1:]:
        text = (Path(a) / "infolog.txt").read_text(encoding="utf8", errors="ignore")
        last = {}
        for m in GONE_RE.finditer(text):
            last[int(m.group(1))] = m.group(2)
        d = ab = 0
        for body in last.values():
            for m in DEF_RE.finditer(body):
                if m.group(1) in UP:
                    d += int(m.group(2))
                    ab += int(m.group(3))
        picks = PICK_RE.findall(text)
        own, ally = picks.count("0"), picks.count("1")
        tot_d += d
        tot_a += ab
        tot_own += own
        tot_ally += ally
        print(f"{Path(a).name[:60]:<60} upgrades done={d:3} abort={ab:3}  picks own={own:3} ally={ally:3}")
    if len(sys.argv) > 2:
        rate = 100.0 * tot_a / max(1, tot_d + tot_a)
        share = 100.0 * tot_ally / max(1, tot_own + tot_ally)
        print(f"{'total':<60} upgrades done={tot_d:3} abort={tot_a:3} ({rate:.0f}% aborted)  ally picks {share:.0f}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
