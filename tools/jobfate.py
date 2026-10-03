#!/usr/bin/env python3
"""Builder jobs by def: finished vs dropped, and why the dropped ones died.

    python tools/jobfate.py <match-dir> [...] [--defs armmex,armllt,...]

Finished/dropped from each team's last `apex: task-gone` line (cumulative);
reasons from `apex: task-die ... why=` (C++ death notes; `?` = aborted with no
note). Our side only -- BARb writes neither line.
"""
from __future__ import annotations

import collections
import re
import sys
from pathlib import Path

GONE_RE = re.compile(r"apex: task-gone t=(\d+) \|(.*)")
DEF_RE = re.compile(r"(\w+) done=(\d+) abort=(\d+)")
DIE_RE = re.compile(r"apex: task-die t=\d+ (\w+) .*?why=(\S+)")


def main() -> int:
    args = sys.argv[1:]
    defs = None
    if "--defs" in args:
        i = args.index("--defs")
        defs = set(args[i + 1].split(","))
        del args[i:i + 2]
    done, drop, why = collections.Counter(), collections.Counter(), collections.defaultdict(collections.Counter)
    for a in args:
        text = (Path(a) / "infolog.txt").read_text(encoding="utf8", errors="ignore")
        last = {}
        for m in GONE_RE.finditer(text):
            last[m.group(1)] = m.group(2)
        for body in last.values():
            for m in DEF_RE.finditer(body):
                done[m.group(1)] += int(m.group(2))
                drop[m.group(1)] += int(m.group(3))
        for m in DIE_RE.finditer(text):
            why[m.group(1)][m.group(2)] += 1
    keys = sorted(defs or done.keys(), key=lambda k: -(done[k] + drop[k]))
    n = len(args)
    print(f"per match (n={n}): finished / dropped, and the death notes of dropped jobs")
    for k in keys[:20]:
        tot = done[k] + drop[k]
        if not tot:
            continue
        w = ", ".join(f"{r} {c / n:.0f}" for r, c in why[k].most_common(4))
        print(f"  {k:<11} {done[k] / n:6.1f} / {drop[k] / n:6.1f}  ({100 * drop[k] / tot:3.0f}% dropped)  {w}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
