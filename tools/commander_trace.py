"""Reconstruct the opening/commander timeline from a match infolog, per team.

    python tools/commander_trace.py matches/<run>/
    python tools/commander_trace.py matches/<run>/ --team 0
    python tools/commander_trace.py matches/<run>/ --raw     # also dump every matched line

Pulls together the apex: tags that already exist in the log (opening, home
energy, request, expand-diag, comm-why/comm-diag, T1 lab, facqueue) into one
per-team timeline, plus a one-line summary: time to first factory, how many
mexes/energy buildings went in before it, and how idle the commander was.

Everything here is read from log lines the AngelScript already writes -- no
new instrumentation. If a line format changes, the matching regex needs to
change with it; this tool does not invent numbers.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

LINE = re.compile(
    r"Skirmish AI <[^>]+>: \[(?P<min>[\d.]+)m t(?P<team>\d+)\] apex: (?P<rest>.*)"
)

TAGS = [
    ("opening", re.compile(r"^opening (.*)$")),
    ("home energy", re.compile(r"^home energy (\S+) standing=(\d+) .*mInc=([\d.]+) eInc=([\d.]+)")),
    ("request", re.compile(r"^request (\S+) (\S+) cap=(\d+) live=(\d+) new=(\d+)")),
    ("lab", re.compile(r"^T1 lab on field: (\S+)")),
    ("expand", re.compile(r"^expand-diag .*mex=(\d+) workers=(\d+) mInc=(\S+)")),
    ("comm-why", re.compile(r"^comm-why samples=(\d+) noTask=(\d+) waiting=(\d+) ordered=(\d+) other=(\d+)")),
    ("comm-diag", re.compile(r"^comm-diag offers=(\d+) offerNull=(\d+)")),
    ("mex-sentry", re.compile(r"^mex sentry #(\d+) (\S+)")),
    ("home-tower", re.compile(r"^home tower (\S+) #(\d+)")),
    ("commander", re.compile(r"^commander (.*)$")),
]


def parse(infolog: Path):
    events = defaultdict(list)  # team -> list of (minute, tag, text)
    for line in infolog.read_text(errors="replace").splitlines():
        m = LINE.search(line)
        if not m:
            continue
        team = int(m.group("team"))
        minute = float(m.group("min"))
        rest = m.group("rest")
        for tag, pat in TAGS:
            if pat.match(rest):
                events[team].append((minute, tag, rest))
                break
    return events


def summarize(team, events):
    lab_time = None
    mex_at_lab = None
    workers_at_lab = None
    for minute, tag, text in events:
        if tag == "lab" and lab_time is None:
            lab_time = minute
        if tag == "expand":
            m = re.search(r"mex=(\d+) workers=(\d+)", text)
            if m and (lab_time is None):
                mex_at_lab, workers_at_lab = int(m.group(1)), int(m.group(2))

    last_why = None
    last_diag = None
    for minute, tag, text in events:
        if tag == "comm-why":
            last_why = text
        if tag == "comm-diag":
            last_diag = text

    print(f"--- team {team} ---")
    if lab_time is None:
        print("  T1 factory: NEVER landed in this match")
    else:
        print(f"  T1 factory landed at {lab_time:.1f}m "
              f"(mex={mex_at_lab} workers={workers_at_lab} at that point)")
    if last_why:
        m = re.search(r"samples=(\d+) noTask=(\d+) waiting=(\d+) ordered=(\d+) other=(\d+)", last_why)
        if m:
            s, no, wait, ordered, other = (int(x) for x in m.groups())
            pct = lambda x: f"{100*x/s:.0f}%" if s else "n/a"
            print(f"  commander samples={s}: noTask={pct(no)} waiting={pct(wait)} "
                  f"ordered={pct(ordered)} other={pct(other)}")
    if last_diag:
        m = re.search(r"offers=(\d+) offerNull=(\d+)", last_diag)
        if m:
            o, on = int(m.group(1)), int(m.group(2))
            print(f"  DefaultMakeTask offers={o}, null={on} "
                  f"({100*on/o:.0f}%)" if o else "  no offers logged")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir")
    ap.add_argument("--team", type=int, default=None)
    ap.add_argument("--raw", action="store_true", help="also dump every matched line")
    args = ap.parse_args()

    run_dir = Path(args.run_dir)
    infolog = run_dir / "infolog.txt" if run_dir.is_dir() else run_dir
    if not infolog.exists():
        print(f"no infolog at {infolog}", file=sys.stderr)
        sys.exit(1)

    events = parse(infolog)
    teams = [args.team] if args.team is not None else sorted(events)
    for team in teams:
        ev = events.get(team, [])
        if args.raw:
            print(f"--- team {team} raw ---")
            for minute, tag, text in ev:
                print(f"  [{minute:5.1f}m] {tag:12s} {text}")
        summarize(team, ev)


if __name__ == "__main__":
    main()
