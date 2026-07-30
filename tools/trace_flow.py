"""Reconstruct what the pooling strategy actually did, from a match infolog.

    python tools/trace_flow.py matches/<run>/            # one match
    python tools/trace_flow.py tournaments/<run>/        # every match in a run
    python tools/trace_flow.py <dir> --timeline          # also print every event

The apex strategy is a sequence of steps that depend on each other: elect one
lead, pool metal behind it, tech it early, hand advanced constructors out, then
let followers tech. When it goes wrong, the win rate says only that it did. The
infolog holds the whole causal chain -- but four AI instances write to it behind
one identical prefix, so reading it by eye is impractical.

This checks the chain, step by step, per ally team, and names the first link
that broke. The intended flow, and what breaks it:

  1 elect     exactly ONE lead per ally team
              two leads => both idle army production, both pool, both tech
  2 pool      followers sling metal to the lead, and STOP once they get a con
              never stops => followers donate their economy away all game
  3 rush      lead reaches energy target, reclaims its T1 lab, places the plant
  4 tech      lead owns an advanced factory, and does so BEFORE its followers
              lead later than followers => the pooling bought nothing
  5 share     lead builds advanced constructors and gifts one to each follower
              no gifts => everyone eventually pays for their own plant
  6 follow    followers tech from ~10 min once their own economy carries it

Also reports constructors held against the cap the script believes it enforces
(conT1 from dev_stats_export), because that cap counts finished builders only.

Needs the team-id log prefix ("[3.9m t2]"). Older logs lack it; those lines are
reported as unattributed rather than silently dropped.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

from bar_env import REPO

FRAME = re.compile(r"\[f=(-?\d+)\]")
# "[3.9m t2] apex: ..." -- the team id is what makes four instances separable.
TEAMED = re.compile(r"\[(\d+\.\d+)m t(\d+)\]\s*(.*)")

LEAD_GADGET = re.compile(r"\[BARAI_LEAD\] ally=(\d+) team=(\d+) inc=([\d.-]+) .*min=([\d.]+)")
T2START = re.compile(r"\[BARAI_T2START\] team=(\d+) ally=(\d+) .*min=([\d.]+) unit=(\S+)")
T2DONE = re.compile(r"\[BARAI_T2DONE\] team=(\d+) ally=(\d+) .*min=([\d.]+) unit=(\S+)")
STATS = re.compile(r"\[BARAI_STATS\] (.*)")
AS_ERROR = re.compile(r"([a-z_]+\.as) \((\d+), (\d+)\) : (ERR|WARN)\s*:?\s*(.{0,90})")


class Match:
    def __init__(self, name: str) -> None:
        self.name = name
        self.as_errors: list[str] = []
        self.ally_of: dict[int, int] = {}         # team -> ally
        self.elected: dict[int, tuple] = {}       # ally -> (team, inc, minute)
        self.claims: dict[int, set] = defaultdict(set)   # team -> leads it named
        self.role: dict[int, str] = {}            # team -> LEAD | follower
        self.t2start: dict[int, float] = {}       # team -> minute placed
        self.t2done: dict[int, float] = {}        # team -> minute finished
        self.gifts: list[tuple] = []              # (minute, giver, recipient)
        self.received: dict[int, float] = {}      # team -> minute
        self.slings: dict[int, list] = defaultdict(list)  # team -> [(minute, amt)]
        self.last_stats: dict[int, dict] = {}     # team -> last stats row
        self.series: dict[int, list] = defaultdict(list)  # team -> [(minute, row)]
        self.events: list[tuple] = []             # (minute, team, text)

    def apex_allies(self) -> set[int]:
        """Ally teams running this strategy, i.e. the ones these rules apply to.

        A match is normally apex vs stock. Stock neither elects a lead nor gifts
        constructors, so grading it against this flow reports failures that are
        simply the other AI being a different AI. Only teams that emitted a
        team-tagged apex line are ours.
        """
        return {self.ally_of.get(t, -1) for t, _, _ in
                ((t, m, x) for m, t, x in self.events)} - {-1}


def parse(path: Path) -> Match:
    # Name the match by its directory: every log file is called infolog.txt.
    m = Match(path.parent.name or path.name)
    text = path.read_text("utf-8", errors="replace")

    for e in AS_ERROR.finditer(text):
        if e.group(4) == "ERR":
            line = f"{e.group(1)} ({e.group(2)},{e.group(3)}): {e.group(5).strip()}"
            if line not in m.as_errors:
                m.as_errors.append(line)

    for g in LEAD_GADGET.finditer(text):
        ally, team, inc, minute = int(g.group(1)), int(g.group(2)), float(g.group(3)), float(g.group(4))
        m.elected[ally] = (team, inc, minute)

    for g in T2START.finditer(text):
        team, ally, minute = int(g.group(1)), int(g.group(2)), float(g.group(3))
        m.ally_of[team] = ally
        m.t2start.setdefault(team, minute)
    for g in T2DONE.finditer(text):
        team, ally, minute = int(g.group(1)), int(g.group(2)), float(g.group(3))
        m.ally_of[team] = ally
        m.t2done.setdefault(team, minute)

    for g in STATS.finditer(text):
        row: dict = {}
        for tok in g.group(1).split():
            k, _, v = tok.partition("=")
            try:
                row[k] = float(v)
            except ValueError:
                row[k] = v
        if "team" in row:
            t = int(row["team"])
            m.ally_of.setdefault(t, int(row.get("ally", 0)))
            m.last_stats[t] = row
            m.series[t].append((row.get("frame", 0) / 1800.0, row))

    for line in text.splitlines():
        hit = TEAMED.search(line)
        if not hit:
            continue
        minute, team, rest = float(hit.group(1)), int(hit.group(2)), hit.group(3)
        m.events.append((minute, team, rest))

        lead = re.search(r"tech lead (?:= team|CHANGED team \d+ -> ) ?(\d+)", rest)
        if lead:
            m.claims[team].add(int(lead.group(1)))
        role = re.search(r"rush team=(\d+) (LEAD|follower)", rest)
        if role:
            m.role[int(role.group(1))] = role.group(2)
        gift = re.search(r"gave adv con to team (\d+)", rest)
        if gift:
            m.gifts.append((minute, team, int(gift.group(1))))
        if "received adv con" in rest:
            m.received.setdefault(team, minute)
        sling = re.search(r"sent ([\d.]+) (?:metal )?to lead", rest)
        if sling:
            m.slings[team].append((minute, float(sling.group(1))))

    return m


def allies(m: Match) -> dict[int, list[int]]:
    out: dict[int, list[int]] = defaultdict(list)
    for team, ally in sorted(m.ally_of.items()):
        out[ally].append(team)
    return out


def report(m: Match, show_timeline: bool = False, _raw: str = "") -> int:
    """Returns the number of broken links found."""
    print(f"\n{'=' * 78}\n{m.name}")
    broken = 0

    if "has crashed" in _raw or "problem with a skirmish AI" in _raw:
        print(chr(10) + "  *** THIS MATCH CRASHED -- results below are "
              "truncated and must not be compared against clean runs")
    if m.as_errors:
        # This one outranks everything: a compile error disables the variant and
        # the match still runs and reports a normal result.
        print("\n  ANGELSCRIPT ERRORS -- the variant did not load; nothing below is meaningful")
        for e in m.as_errors[:6]:
            print(f"    {e}")
        return 1

    teamed = any(True for _ in m.events)
    if not teamed:
        print("\n  no team-tagged log lines -- this log predates the 't<id>' prefix,"
              "\n  so per-AI attribution is unavailable. Re-run after deploying.")

    ours = m.apex_allies()
    for ally, teams in sorted(allies(m).items()):
        if ours and ally not in ours:
            print(f"\n  ally {ally}   teams {teams}   (not running this strategy -- skipped)")
            continue
        print(f"\n  ally {ally}   teams {teams}")

        # 1 elect
        elected = m.elected.get(ally)
        claimed = {t: c for t, c in m.claims.items() if t in teams and c}
        distinct = {v for c in claimed.values() for v in c}
        if elected:
            print(f"    1 elect    team {elected[0]} at {elected[1]:.1f} m/s, "
                  f"{elected[2]:.1f}m  (gadget)")
        if len(distinct) > 1:
            print(f"    1 elect    BROKEN: {len(distinct)} different leads claimed "
                  f"{sorted(distinct)} -- by teams {sorted(claimed)}")
            broken += 1
        elif distinct:
            believers = sorted(claimed)
            print(f"    1 elect    team {sorted(distinct)[0]} agreed by "
                  f"{len(believers)} instance(s) {believers}")
        elif not elected:
            print("    1 elect    no election recorded (gadget absent, or match "
                  "ended before the decision frame)")

        lead = elected[0] if elected else (sorted(distinct)[0] if distinct else None)
        followers = [t for t in teams if t != lead]

        # 2 pool
        slingers = {t: v for t, v in m.slings.items() if t in teams}
        if slingers:
            total = sum(a for v in slingers.values() for _, a in v)
            last = max(mi for v in slingers.values() for mi, _ in v)
            got = {t: mi for t, mi in m.received.items() if t in teams}
            late = [t for t, v in slingers.items()
                    if t in got and max(mi for mi, _ in v) > got[t] + 1.0]
            print(f"    2 pool     {len(slingers)} slinger(s), {total:.0f} metal, "
                  f"last at {last:.1f}m")
            if late:
                print(f"               BROKEN: teams {late} kept slinging >1 min "
                      f"after receiving their constructor")
                broken += 1
        else:
            print("    2 pool     no slinging recorded")

        # 3/4 rush + tech
        if lead is not None:
            placed, done = m.t2start.get(lead), m.t2done.get(lead)
            if placed is None:
                print(f"    3 rush     BROKEN: lead (team {lead}) never placed an "
                      f"advanced plant")
                broken += 1
            else:
                built = f"{done:.1f}m" if done else "never finished"
                print(f"    3 rush     lead placed at {placed:.1f}m, finished {built}")
            f_done = [(t, m.t2done[t]) for t in followers if t in m.t2done]
            if done and f_done:
                earlier = [t for t, mi in f_done if mi < done]
                if earlier:
                    print(f"    4 tech     BROKEN: follower(s) {earlier} reached T2 "
                          f"before the lead -- the pooling bought nothing")
                    broken += 1
                else:
                    print(f"    4 tech     lead first at {done:.1f}m; followers "
                          f"{sorted(mi for _, mi in f_done)}")

        # 5 share
        gifts = [g for g in m.gifts if g[1] in teams]
        if lead is not None and followers:
            if not gifts:
                print(f"    5 share    BROKEN: 0 advanced constructors gifted "
                      f"({len(followers)} follower(s) needed one)")
                broken += 1
            else:
                who = sorted({g[2] for g in gifts})
                print(f"    5 share    {len(gifts)} gift(s) to teams {who} at "
                      f"{[f'{g[0]:.1f}m' for g in gifts]}")
                missing = [t for t in followers if t not in who]
                if missing:
                    print(f"               partial: teams {missing} never received one")

        # 6 follow
        f_done = sorted((m.t2done[t], t) for t in followers if t in m.t2done)
        if followers:
            print(f"    6 follow   {len(f_done)}/{len(followers)} followers teched"
                  + (f", first {f_done[0][0]:.1f}m last {f_done[-1][0]:.1f}m"
                     if f_done else ""))

        # Constructors, judged against the cap ONLY while the cap applies.
        #
        # RUSH_CON_CAP gates the rush branch, which stops the moment the lead
        # owns an advanced factory. Reading the end-of-game count instead --
        # which an earlier version of this tool did -- reports every match as
        # over the cap, because normal production resumes afterwards and every
        # player, stock included, drifts to 8-13 constructors by minute 20.
        cutoff = m.t2done.get(lead) if lead is not None else None
        if lead is not None and lead in m.series:
            during = [(mi, r) for mi, r in m.series[lead]
                      if cutoff is None or mi <= cutoff]
            peak = max((int(r.get("conT1", 0)) for _, r in during), default=0)
            window = f"to {cutoff:.1f}m" if cutoff else "whole match"
            print(f"    cap        lead peaked at {peak} T1 constructors "
                  f"during the rush ({window}, cap 6)")
            if peak > 6:
                print(f"               BROKEN: cap exceeded while it was in force")
                broken += 1
        end = [(t, m.last_stats[t]) for t in teams if t in m.last_stats]
        if end and any("conT1" in r for _, r in end):
            bits = [f"t{t}{'*' if t == lead else ' '}"
                    f"{int(r.get('conT1', 0))}/{int(r.get('conT2', 0))}"
                    for t, r in end]
            mcon = sum(r.get("mCon", 0) for _, r in end)
            mprod = sum(r.get("metalProduced", 0) for _, r in end) or 1
            print(f"    end T1/T2  {'  '.join(bits)}   "
                  f"({mcon:.0f} metal = {100 * mcon / mprod:.1f}% of economy)")

    if show_timeline:
        print("\n  timeline")
        for minute, team, text in sorted(m.events):
            print(f"    {minute:>6.1f}m t{team}  {text[:96]}")

    return broken


def find_logs(root: Path) -> list[Path]:
    if root.is_file():
        return [root]
    hits = []
    for d in sorted([root] + [p for p in root.rglob("*") if p.is_dir()]):
        for name in ("infolog.txt", "stdout.txt"):
            if (d / name).exists():
                hits.append(d / name)
                break
    return hits


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("path", help="a match dir, a tournament dir, or an infolog")
    ap.add_argument("--timeline", action="store_true",
                    help="print every team-tagged event, not just the verdict")
    ap.add_argument("--limit", type=int, default=8, help="max matches to report")
    args = ap.parse_args()

    root = Path(args.path)
    if not root.exists():
        root = REPO / args.path
    if not root.exists():
        raise SystemExit(f"no such path: {args.path}")

    logs = find_logs(root)
    if not logs:
        raise SystemExit(f"no infolog.txt or stdout.txt under {root}")

    total = 0
    for log in logs[: args.limit]:
        total += report(parse(log), args.timeline,
                        log.read_text('utf-8', errors='replace'))
    if len(logs) > args.limit:
        print(f"\n({len(logs) - args.limit} more matches not shown; --limit to raise)")
    print(f"\n{total} broken link(s) across {min(len(logs), args.limit)} match(es)\n")
    return 1 if total else 0


if __name__ == "__main__":
    raise SystemExit(main())
