"""Grep a match's infolog for apex: lines, filtered by keyword and/or team.

    python tools/trace.py latest                          # most recent matches/ run
    python tools/trace.py latest --filter=commander --team 0
    python tools/trace.py matches/<run>                    # a specific run
    python tools/trace.py tournaments/<run>/<game-dir>     # a specific game in a tournament

--filter matches against the tag word right after "apex: " (e.g. "opening",
"comm-why", "request", "home") OR anywhere in the line text -- whichever hits.
--team filters on the [X.Xm tN] prefix every apex: line already carries.

This is a thin grep, not a parser: it prints the log lines apex.as already
writes, minute-stamped and with the AI-name noise stripped, in order. For a
summarized per-team timeline (time to lab, mex/worker counts, idle split) use
tools/commander_trace.py instead.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

LINE = re.compile(
    r"Skirmish AI <[^>]+>: \[(?P<min>[\d.]+)m t(?P<team>\d+)\] apex: (?P<rest>.*)"
)


def find_latest(base: Path) -> Path:
    runs = [p for p in base.glob("*") if p.is_dir() and (p / "infolog.txt").exists()]
    if not runs:
        sys.exit(f"no run directories with an infolog.txt under {base}")
    return max(runs, key=lambda p: p.stat().st_mtime)


def resolve(run_arg: str) -> Path:
    if run_arg == "latest":
        return find_latest(Path("matches")) / "infolog.txt"
    p = Path(run_arg)
    if p.is_file():
        return p
    if (p / "infolog.txt").exists():
        return p / "infolog.txt"
    # tournaments/<run>/ with no game specified: pick its latest game dir
    if p.is_dir():
        return find_latest(p) / "infolog.txt"
    sys.exit(f"can't find an infolog under {p}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run", help='"latest", or a path to a match/tournament-game dir or infolog.txt')
    ap.add_argument("--filter", default=None, help="keyword: matched against the tag or line text")
    ap.add_argument("--team", type=int, default=None)
    args = ap.parse_args()

    infolog = resolve(args.run)
    print(f"# {infolog}", file=sys.stderr)

    needle = args.filter.lower() if args.filter else None
    shown = 0
    for line in infolog.read_text(errors="replace").splitlines():
        m = LINE.search(line)
        if not m:
            continue
        if args.team is not None and int(m.group("team")) != args.team:
            continue
        rest = m.group("rest")
        if needle and (needle not in rest.lower()):
            continue
        print(f"[{m.group('min')}m t{m.group('team')}] {rest}")
        shown += 1

    if shown == 0:
        print("(no matching lines -- check --filter spelling, or the tag may not exist in this log)",
              file=sys.stderr)


if __name__ == "__main__":
    main()
