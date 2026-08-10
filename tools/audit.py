#!/usr/bin/env python3
"""Every complaint apexearth has made, as a check that passes or fails on a game.

    python tools/audit.py matches/watch-1v1d
    python tools/audit.py tournaments/2026...-fast-baseline
    python tools/audit.py matches/watch-1v1d --verbose

The point: he keeps finding things by watching that the tools do not report --
a constructor cap, five reactors at once, mex upgrades never happening, a nuke
silo on a thin grid. Each one is written here once, so the next run says so
without anyone watching. A check that cannot be evaluated (no telemetry, no log
line) reports SKIP rather than PASS, because "no evidence" is not "fine".

Add a check when a new complaint lands. That is the whole workflow.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

WASTE_LIMIT = 15.0        # % of metal produced thrown away
COMM_VETO_LIMIT = 2       # comm-hold vetoes before the 10-minute mark
NUKE_MIN_ENERGY = 2500.0  # must match statics.as
DUP_LIMIT = 2             # simultaneous builds of one expensive structure


class Game:
    def __init__(self, d: Path):
        self.dir = d
        self.result = json.load(open(d / "result.json"))
        log = d / "infolog.txt"
        self.log = log.read_text(errors="replace") if log.exists() else ""
        self.samples = defaultdict(lambda: defaultdict(float))
        for s in self.result.get("stats") or []:
            for k, v in s.items():
                if isinstance(v, (int, float)) and k not in ("team", "ally", "frame"):
                    self.samples[(s["ally"], s["frame"])][k] += v
        self.frames = sorted({f for _, f in self.samples}) or [0]
        # Ally 0 is the --a side; run_match writes it first.
        self.us = 0.0

    def at(self, frame: float) -> dict:
        return self.samples[(self.us, frame)]

    def final(self) -> dict:
        return self.at(self.frames[-1])

    def series(self, key: str) -> list[tuple[float, float]]:
        return [(f / 1800.0, self.at(f).get(key, 0.0)) for f in self.frames]

    def count(self, pattern: str) -> int:
        return len(re.findall(pattern, self.log))

    def before(self, pattern: str, minutes: float) -> int:
        n = 0
        for m in re.finditer(r"\[f=(\d+)\][^\n]*?" + pattern, self.log):
            if int(m.group(1)) / 1800.0 <= minutes:
                n += 1
        return n


def check_no_as_errors(g: Game):
    if not g.log:
        return None, "no infolog"
    n = g.count(r"\.as \(\d+, \d+\) : ERR")
    return n == 0, f"{n} AngelScript compile errors (a variant that does not compile plays as stock)"


def check_no_ai_crash(g: Game):
    if not g.log:
        return None, "no infolog"
    n = g.count(r"problem with a skirmish AI")
    return n == 0, f"{n} skirmish-AI crashes"


def check_no_desync(g: Game):
    if not g.log:
        return None, "no infolog"
    n = g.count(r"Sync error for")
    return n == 0, f"{n} sync errors"


def check_metal_not_wasted(g: Game):
    fin = g.final()
    prod = fin.get("metalProduced", 0.0)
    if prod <= 0:
        return None, "no metal telemetry"
    pct = 100 * fin.get("metalExcess", 0.0) / prod
    return pct <= WASTE_LIMIT, f"{pct:.1f}% of metal produced was wasted (limit {WASTE_LIMIT}%)"


def check_mex_upgrades_happen(g: Game):
    """apexearth, five times: 'we don't mexup at all'."""
    peak_mex = max((v for _, v in g.series("mex")), default=0)
    t2 = max((v for _, v in g.series("t2Mex")), default=0)
    if peak_mex < 8:
        return None, "too few mexes to expect upgrades"
    return t2 >= peak_mex * 0.25, f"{t2:.0f} T2 mexes against {peak_mex:.0f} mexes held (want >= 25%)"


def check_mex_upgrades_start_early(g: Game):
    """A moho at minute 25 is not 'we upgrade mexes'."""
    first = next((m for m, v in g.series("t2Mex") if v > 0), None)
    if max((v for _, v in g.series("mex")), default=0) < 8:
        return None, "too few mexes to expect upgrades"
    if first is None:
        return False, "no T2 mex was ever built"
    return first <= 15.0, f"first T2 mex at {first:.1f} min (want <= 15)"


def check_adv_cons_scale(g: Game):
    """One advanced constructor at any income was a gate bug; keep it fixed."""
    fin = g.final()
    peak_t2 = max((v for _, v in g.series("conT2")), default=0)
    prod_per_min = fin.get("metalProduced", 0.0) / max(g.result.get("result", {}).get("game_minutes", 1), 1)
    if prod_per_min < 600:      # ~10 metal/s, too poor to want more than one
        return None, "economy too small to expect several advanced constructors"
    return peak_t2 >= 3, f"peak {peak_t2:.0f} advanced constructors on {prod_per_min/60:.0f} metal/s"


def check_no_duplicate_reactors(g: Game):
    """apexearth: 'I am actively seeing us build 5 AFUS at the same time'."""
    if not g.log:
        return None, "no infolog"
    starts = re.findall(r"apex: home energy (\w+)", g.log)
    afus = [u for u in starts if u.endswith("afus") or u.endswith("fus")]
    joins = g.count(r"con-join\(direct\)")
    if not afus:
        return None, "no reactors built"
    # Not exact -- a reactor may legitimately be replaced -- so this flags the
    # shape (many starts, no joins) rather than any single start.
    return not (len(afus) > DUP_LIMIT and joins == 0), \
        f"{len(afus)} reactor starts with {joins} direct joins"


def check_commander_not_idle(g: Game):
    """apexearth: 'the commander stands around after making the first mex'."""
    if not g.log:
        return None, "no infolog"
    n = g.before(r"con-veto comm-hold", 10.0)
    return n <= COMM_VETO_LIMIT, f"{n} comm-hold vetoes in the first 10 min (limit {COMM_VETO_LIMIT})"


def check_no_solo_team_roles(g: Game):
    """Team machinery must not run with no allies."""
    if not g.log:
        return None, "no infolog"
    teams = {int(s["team"]) for s in (g.result.get("stats") or []) if s["ally"] == g.us}
    if len(teams) > 1:
        return None, "team game; roles are legitimate"
    n = g.count(r"apex: (?:ECO LEAD|designated T2 rusher)")
    return n == 0, f"{n} team-role activations in a solo game"


def check_nuke_affordable(g: Game):
    """apexearth: 'no energy because we have a nuke launcher at 1500 income'."""
    if not g.log:
        return None, "no infolog"
    if not re.search(r"(?i)nuke|silo", g.log):
        return None, "no nuke silo built"
    incomes = [float(m.group(1)) for m in re.finditer(r"eInc=(\d+)", g.log)]
    peak = max(incomes) if incomes else 0.0
    return peak >= NUKE_MIN_ENERGY, \
        f"a silo was built with peak energy income {peak:.0f} (floor {NUKE_MIN_ENERGY:.0f})"


def check_army_keeps_up(g: Game):
    """The standing complaint: we out-produce and under-field."""
    ours = max((v for _, v in g.series("armyReal")), default=0)
    theirs = 0.0
    for f in g.frames:
        theirs = max(theirs, self_other(g, f))
    if theirs <= 0:
        return None, "no opponent telemetry"
    return ours >= theirs * 0.9, f"peak army {ours:,.0f} against {theirs:,.0f} ({ours/theirs:.2f}x)"


def self_other(g: Game, frame: float) -> float:
    return g.samples[(1.0 - g.us, frame)].get("armyReal", 0.0)



# ---------------------------------------------------------------------------
# The standing brief, as checks. Each is a line from USER-FEEDBACK.md or
# ISSUES.md that has been raised and could not be seen from a tournament
# summary. The source is named so a check can be argued with.
# ---------------------------------------------------------------------------

def check_no_duplicate_expensive_plants(g):
    """USER-FEEDBACK: 'never build two of the same expensive plant' (two T2 shipyards)."""
    if not g.log:
        return None, "no infolog"
    starts = re.findall(r"apex: (?:building advanced plant|T1 lab on field:) (\w+)", g.log)
    dupes = {u for u in starts if starts.count(u) > 1}
    return not dupes, "repeat plant starts: " + (", ".join(sorted(dupes)) or "none")


def check_expensive_built_serially(g):
    """USER-FEEDBACK: 'build expensive structures ONE AT A TIME, assisted' (five LRPCs)."""
    if not g.log:
        return None, "no infolog"
    starts = len(re.findall(r"apex: home energy \w*fus", g.log, re.I))
    joins = g.count(r"con-join")
    if starts == 0:
        return None, "no reactors started"
    return joins >= starts, f"{starts} reactor starts against {joins} assist-joins"


def check_constructors_not_reclaiming(g):
    """USER-FEEDBACK: 'constructors should not be reclaiming. Rez bots exist for that.'"""
    fin = g.final()
    prod = fin.get("metalProduced", 0.0)
    if prod <= 0:
        return None, "no metal telemetry"
    rec = fin.get("mReclaim", 0.0)
    return rec <= prod * 0.10, f"reclaim was {100*rec/prod:.1f}% of metal produced"


def check_defences_arrive_early(g):
    """USER-FEEDBACK: 'defences arrive far too late. At 17 minutes there is not much.'"""
    at17 = next((g.at(f) for f in g.frames if f / 1800.0 >= 17.0), None)
    if at17 is None:
        return None, "game shorter than 17 min"
    d, m = at17.get("mDefence", 0.0), at17.get("metalProduced", 1.0)
    return d >= m * 0.05, f"static defence {d:,.0f} at 17 min ({100*d/m:.1f}% of metal produced)"


def check_we_take_mexes_as_fast(g):
    """USER-FEEDBACK: 'the enemy takes map-wide mexes far faster than we do.'"""
    if not g.frames:
        return None, "no telemetry"
    i = min(range(len(g.frames)), key=lambda k: abs(g.frames[k] / 1800.0 - 10.0))
    f = g.frames[i]
    ours = g.at(f).get("mex", 0.0)
    theirs = g.samples[(1.0 - g.us, f)].get("mex", 0.0)
    if theirs <= 0:
        return None, "no opponent mex telemetry"
    return ours >= theirs, f"at 10 min we held {ours:.0f} mexes to their {theirs:.0f}"


def check_we_harass_their_economy(g):
    """USER-FEEDBACK: 'we never harass their economy while they constantly harass ours.'"""
    fin = g.final()
    if fin.get("mKillReal", 0.0) <= 0:
        return None, "no kill telemetry"
    static = fin.get("mKillStatic", 0.0)
    return static > 0, f"killed {static:,.0f} metal of enemy structures"


def check_air_not_idle_while_losing(g):
    """USER-FEEDBACK: 'do not run air-assassin strategies while clearly losing.'"""
    if not g.log:
        return None, "no infolog"
    held = g.count(r"air assassin holding off")
    return held < 10, f"air assassin held off {held} times"


def check_one_t1_air_lab(g):
    """USER-FEEDBACK: 'one T1 air lab in the T1 phase, not two.'"""
    if not g.log:
        return None, "no infolog"
    air = [u for u in re.findall(r"apex: T1 lab on field: (\w+)", g.log) if u.endswith("ap")]
    return len(air) <= 1, f"{len(air)} T1 air labs started"


def check_front_is_known(g):
    """USER-FEEDBACK, largest unresolved: 'units are not positioned on the front line.'"""
    if not g.log:
        return None, "no infolog"
    m = re.findall(r"apex: frontline perim=(\d+) front=(\d+) back=(\d+)", g.log)
    if not m:
        return None, "no frontline telemetry"
    known = sum(1 for _, f, _ in m if int(f) > 0)
    return known >= len(m) * 0.5, f"front known in {known}/{len(m)} samples"


def check_unblock_not_repeating(g):
    """ISSUES 5: one unit needed six clearing orders and stayed stuck."""
    if not g.log:
        return None, "no infolog"
    ids = re.findall(r"apex: unblock \w+ #(\d+)", g.log)
    worst = max((ids.count(i) for i in set(ids)), default=0)
    if not ids:
        return None, "unblock never fired"
    return worst <= 2, f"worst unit needed {worst} clearing orders"


def check_engagements_are_pushes(g):
    """ISSUES 1: median engagement was five units against a 46,000-metal army."""
    if not g.log:
        return None, "no infolog"
    units = sorted(int(m.group(1)) for m in re.finditer(r"apex: engage \w+ units=(\d+)", g.log))
    if len(units) < 10:
        return None, "too few engagements"
    med = units[len(units) // 2]
    return med >= 8, f"median engagement {med} units over {len(units)} engagements"


def check_kill_per_metal(g):
    """ISSUES 1c: we destroy half as much enemy metal per metal produced as medium does."""
    fin = g.final()
    theirs = g.samples[(1.0 - g.us, g.frames[-1])]
    prod, tprod = fin.get("metalProduced", 0.0), theirs.get("metalProduced", 0.0)
    if prod <= 0 or tprod <= 0:
        return None, "no metal telemetry"
    ours = (fin.get("mKillReal", 0.0) + fin.get("mKillCheap", 0.0)) / prod
    other = (theirs.get("mKillReal", 0.0) + theirs.get("mKillCheap", 0.0)) / tprod
    return ours >= other, f"kill per metal {ours:.3f} against their {other:.3f}"


CHECKS = [
    ("ran at all", check_no_as_errors),
    ("no AI crash", check_no_ai_crash),
    ("no desync", check_no_desync),
    ("metal not wasted", check_metal_not_wasted),
    ("mex upgrades happen", check_mex_upgrades_happen),
    ("mex upgrades start early", check_mex_upgrades_start_early),
    ("advanced cons scale", check_adv_cons_scale),
    ("no duplicate reactors", check_no_duplicate_reactors),
    ("commander not idle", check_commander_not_idle),
    ("no solo team roles", check_no_solo_team_roles),
    ("nuke silo affordable", check_nuke_affordable),
    ("army keeps up", check_army_keeps_up),
    ("kill per metal", check_kill_per_metal),
    ("engagements are pushes", check_engagements_are_pushes),
    ("no duplicate plants", check_no_duplicate_expensive_plants),
    ("expensive built serially", check_expensive_built_serially),
    ("constructors not reclaiming", check_constructors_not_reclaiming),
    ("defences by 17 min", check_defences_arrive_early),
    ("mexes as fast as theirs", check_we_take_mexes_as_fast),
    ("we harass their economy", check_we_harass_their_economy),
    ("air not idle while losing", check_air_not_idle_while_losing),
    ("one T1 air lab", check_one_t1_air_lab),
    ("front is known", check_front_is_known),
    ("unblock not repeating", check_unblock_not_repeating),
]


def match_dirs(root: Path) -> list[Path]:
    if (root / "result.json").exists():
        return [root]
    inner = root / "matches"
    base = inner if inner.is_dir() else root
    return sorted(p for p in base.iterdir() if (p / "result.json").exists())


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--verbose", action="store_true", help="show every game, not just totals")
    args = ap.parse_args()

    tally = defaultdict(lambda: [0, 0, 0])   # pass, fail, skip
    failed_any = False
    for p in args.paths:
        for d in match_dirs(Path(p)):
            g = Game(d)
            rows = []
            for name, fn in CHECKS:
                try:
                    ok, detail = fn(g)
                except Exception as exc:                     # a broken check must not hide the rest
                    ok, detail = None, f"check error: {exc}"
                idx = 2 if ok is None else (0 if ok else 1)
                tally[name][idx] += 1
                rows.append((name, ok, detail))
                if ok is False:
                    failed_any = True
            if args.verbose or len(match_dirs(Path(p))) == 1:
                print(f"\n{d.name}")
                for name, ok, detail in rows:
                    mark = "SKIP" if ok is None else ("PASS" if ok else "FAIL")
                    print(f"  [{mark}] {name:26s} {detail}")

    print(f"\n{'check':28s} {'pass':>5s} {'fail':>5s} {'skip':>5s}")
    for name, _ in CHECKS:
        p_, f_, s_ = tally[name]
        print(f"{name:28s} {p_:5d} {f_:5d} {s_:5d}")
    return 1 if failed_any else 0


if __name__ == "__main__":
    raise SystemExit(main())
