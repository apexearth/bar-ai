"""Did we build several expensive energy buildings AT THE SAME TIME?

    python tools/energy_parallel.py <match-dir|tournament-dir> [...]
    python tools/energy_parallel.py tournaments/<run> --max 1

apexearth has raised this four times, most recently watching two fusions and
an advanced fusion rise together: "there's no reason we should ever make two
identical, really expensive things right next to each other at the same
time... they should all focus their efforts on the most efficient energy
project."

WHY NOT READ THE AI'S OWN LOG. `apex: request ... inFlight=N` is per DEF and
reports what one rule decided, so it reads clean for the failure that
actually happens -- advsol + fusion + afus, three different defs, three
different rules. This reads the GROUND TRUTH instead: dev_stats_export's
[BARAI_EFRAMES] census counts UNFINISHED energy structures standing at once,
per team, every 3 game-seconds, whoever ordered them (script rule, Brain
want, or C++ build_chain).

A finding is one CONTIGUOUS episode of 2+ frames standing, so a 40-second
overlap is one violation and not thirteen samples. Brief overlaps are real
but harmless -- one site finishing as the next starts -- so an episode must
last --min-seconds to count.

Geothermal plants are excluded at the census (dev_stats_export): a vent is a
specific piece of ground, so two geos are two different things wanted for
their own sake, exactly like two extractors. The AI founds them through the
spot path, which the class gate does not govern.
"""
import argparse
import os
import re
import sys
from collections import defaultdict

SAMPLE_FRAMES = 90          # must match EFRAME_SAMPLE in dev_stats_export.lua
FPS = 30

EFRAMES_RE = re.compile(
    r"\[BARAI_EFRAMES\] team=(\d+) ally=(\d+) frame=(\d+) min=[\d.]+"
    r" n=(\d+) defs=(\S+)")
EPEAK_RE = re.compile(
    r"\[BARAI_EPEAK\] team=(\d+) ally=\d+ reason=(\w+) peak=(\d+)"
    r" badSamples=(\d+) samples=(\d+) costBar=(\d+)")
# WHOSE TEAMS ARE OURS. Not [BARAI_NAME] (it carries player names, not AI
# identity) and not result.json's teams[].team (the spec-index trap). Only our
# variant emits "apex:" lines, and it stamps its own team on them, so the set
# of team ids seen there IS the set of teams running our AI.
OURS_RE = re.compile(r"apex: (?:decide|exec) t=(\d+) ")
OURS_T_RE = re.compile(r"\[[\d.]+m t(\d+)\] apex: ")


def infologs(path):
    """Every infolog under a match dir or a tournament dir."""
    direct = os.path.join(path, "infolog.txt")
    if os.path.isfile(direct):
        return [direct]
    found = []
    for root, _dirs, files in os.walk(path):
        if "infolog.txt" in files:
            found.append(os.path.join(root, "infolog.txt"))
    return sorted(found)


def episodes(text, min_seconds, apex_teams=None):
    """Contiguous runs of 2+ big-energy frames, per team.

    A gap of more than one sample interval closes an episode: the census only
    speaks when n>=2, so consecutive lines a sample apart are one overlap
    continuing, and a longer gap is a new one.
    """
    per_team = defaultdict(list)
    for m in EFRAMES_RE.finditer(text):
        team = int(m.group(1))
        if apex_teams is not None and team not in apex_teams:
            continue
        per_team[team].append((int(m.group(3)), int(m.group(4)), m.group(5)))
    out = []
    for team, rows in per_team.items():
        rows.sort()
        start = prev = None
        peak, defs = 0, ""
        for frame, n, names in rows:
            if start is None or frame - prev > SAMPLE_FRAMES * 2:
                if start is not None:
                    out.append((team, start, prev, peak, defs))
                start, peak, defs = frame, n, names
            if n > peak:
                peak, defs = n, names
            prev = frame
        if start is not None:
            out.append((team, start, prev, peak, defs))
    span = min_seconds * FPS
    return [e for e in out if (e[2] - e[1]) >= span]


def apex_team_ids(text):
    """Teams running our AI. Stock BARb overlapping its own energy is not our
    bug and must not be counted against us."""
    ids = {int(m.group(1)) for m in OURS_RE.finditer(text)}
    ids |= {int(m.group(1)) for m in OURS_T_RE.finditer(text)}
    return ids or None


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+", help="match or tournament directories")
    ap.add_argument("--min-seconds", type=float, default=10.0,
                    help="an overlap shorter than this is a handover, not a"
                         " violation (default 10)")
    ap.add_argument("--max", type=int, default=0,
                    help="allowed violations before FAIL (default 0)")
    ap.add_argument("--all-teams", action="store_true",
                    help="include the opponent's teams (default: ours only)")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="list every violation, not just the first few")
    args = ap.parse_args()

    logs = []
    for p in args.paths:
        logs.extend(infologs(p))
    if not logs:
        print("no infolog.txt found under: " + ", ".join(args.paths))
        return 2

    total_games, censused, violations = 0, 0, []
    peak_hist = defaultdict(int)
    for log in logs:
        total_games += 1
        with open(log, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        if "[BARAI_EFRAMES]" not in text and "[BARAI_EPEAK]" not in text:
            continue
        censused += 1
        ours = None if args.all_teams else apex_team_ids(text)
        game = os.path.basename(os.path.dirname(log))
        for team, f0, f1, peak, defs in episodes(text, args.min_seconds, ours):
            violations.append((game, team, f0 / 1800.0,
                               (f1 - f0) / FPS, peak, defs))
        for m in EPEAK_RE.finditer(text):
            if ours is None or int(m.group(1)) in ours:
                peak_hist[int(m.group(3))] += 1

    if not censused:
        print(f"{total_games} game(s) read, NONE carry the [BARAI_EFRAMES]"
              " census -- redeploy the gadgets (python tools/deploy_ai.py"
              " gadgets) and rerun. No verdict.")
        return 2

    violations.sort(key=lambda v: (-v[4], -v[3]))
    print(f"games censused   {censused} of {total_games}")
    print(f"episodes >= {args.min_seconds:.0f}s with 2+ big-energy frames"
          f" standing: {len(violations)}")
    if peak_hist:
        print("per-team peak concurrency: "
              + ", ".join(f"{k}x:{v}" for k, v in sorted(peak_hist.items())))
    shown = violations if args.verbose else violations[:12]
    for game, team, at, dur, peak, defs in shown:
        print(f"  t{team} {at:5.1f}m for {dur:5.1f}s peak={peak} {defs}"
              f"   [{game}]")
    if len(violations) > len(shown):
        print(f"  ... {len(violations) - len(shown)} more (-v for all)")

    ok = len(violations) <= args.max
    print(("PASS" if ok else "FAIL")
          + f": {len(violations)} violation(s), allowed {args.max}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
