#!/usr/bin/env python3
"""Profile ONE player in a match against its own allies.

The question this answers is "why is that guy not doing much" — the sort of
thing apexearth asks while watching. A team-wide average cannot answer it, and
neither can a win/loss: the comparison that matters is this player against the
seven others running the same AI on the same side of the same map.

    python tools/player.py matches/watch-isthmus --team 0
    python tools/player.py matches/watch-isthmus --name Master_Conquest

Reads result.json for telemetry and infolog.txt for the AI's own log lines,
which are tagged `[<min>m t<team>]`. Standing counters (army, constructors) are
reported as PEAK as well as final, because they go to zero on death.
"""

import argparse
import json
import re
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path

# Cumulative counters are meaningful at the end; standing ones need a peak.
CUMULATIVE = [
    "metalProduced", "metalUsed", "metalExcess", "energyProduced",
    "energyExcess", "mBuiltReal", "mT1", "mT2", "mT3", "mFactories",
    "mDefence", "mReclaim", "mKillReal", "mLostReal", "damageDealt",
    "damageReceived", "cmds",
]
STANDING = [
    "mex", "t2Mex", "armyReal", "conT1", "conT2", "mCon", "ownUnits",
    "ownBuilders", "aaT1",
]

TAG_RE = re.compile(r"\[(\d+\.\d+)m t(\d+)\] (\w+): (.*)")
NAME_RE = re.compile(r"\[BARAI_NAME\] team=(\d+) name=(.*)$")
POOL_RE = re.compile(r"expand-diag pool\[(.*?)\]")
DEF_RE = re.compile(r"\b((?:arm|cor|leg)[a-z0-9]{2,})\b")

# IBuilderTask::BuildType, from CircuitAI src/circuit/task/builder/BuilderTask.h.
# expand-diag prints unnamed types as `t<n>`, which is unreadable without this.
BUILD_TYPE = [
    "FACTORY", "NANO", "STORE", "PYLON", "ENERGY", "GEO", "GEOUP", "DEFENCE",
    "BUNKER", "BIG_GUN", "RADAR", "SONAR", "CONVERT", "MEX", "MEXUP", "REPAIR",
    "RECLAIM", "RESURRECT", "RECRUIT", "TERRAFORM", "_SIZE_", "PATROL",
    "GUARD", "COMBAT", "WAIT",
]


def build_type(n: int) -> str:
    return BUILD_TYPE[n] if 0 <= n < len(BUILD_TYPE) else f"t{n}"


def load(run: Path):
    res = json.loads((run / "result.json").read_text())
    rows = defaultdict(list)
    for r in res["stats"]:
        rows[int(r["team"])].append(r)
    for v in rows.values():
        v.sort(key=lambda r: r["frame"])
    return res, rows


def names_and_sides(run: Path):
    """in-game display names from the infolog, sides/colors from the script."""
    names = {}
    log = run / "infolog.txt"
    if log.exists():
        with log.open(errors="replace") as fh:
            for line in fh:
                m = NAME_RE.search(line)
                if m:
                    names[int(m.group(1))] = m.group(2).strip()
                if len(names) and "took over control of team" in line:
                    break
    sides, allies, specs = {}, {}, {}
    script = run / "script.txt"
    if script.exists():
        txt = script.read_text(errors="replace")
        for blk in re.finditer(r"\[TEAM(\d+)\]\s*\{(.*?)\}", txt, re.S):
            t, body = int(blk.group(1)), blk.group(2)
            for key, store in (("Side", sides), ("AllyTeam", allies)):
                m = re.search(rf"{key}=(.*?);", body)
                if m:
                    store[t] = m.group(1).strip()
        for blk in re.finditer(r"\[AI\d+\]\s*\{(.*?)\n\t\t\}", txt, re.S):
            body = blk.group(1)
            t = re.search(r"Team=(\d+);", body)
            sn = re.search(r"ShortName=(.*?);", body)
            ver = re.search(r"Version=(.*?);", body)
            if t:
                specs[int(t.group(1))] = f"{sn.group(1) if sn else '?'}:{ver.group(1) if ver else '?'}"
    return names, sides, allies, specs


def ai_log_tags(run: Path, teams):
    """count AI log lines per team, bucketed by the message's leading phrase."""
    per_team = Counter()
    per_tag = defaultdict(Counter)
    last_min = {}
    log = run / "infolog.txt"
    if not log.exists():
        return per_team, per_tag, last_min
    with log.open(errors="replace") as fh:
        for line in fh:
            m = TAG_RE.search(line)
            if not m:
                continue
            minute, team, ns, msg = float(m.group(1)), int(m.group(2)), m.group(3), m.group(4)
            if team not in teams:
                continue
            tag = f"{ns}:{msg.split()[0] if msg.split() else '?'}"
            per_team[team] += 1
            per_tag[team][tag] += 1
            last_min[team] = max(last_min.get(team, 0.0), minute)
    return per_team, per_tag, last_min


def pool_and_defs(run: Path, team: int):
    """Task pool by decoded BuildType, and every unit def this team's log names.

    The defs matter because of the failure mode in CLAUDE.md: asking a unit to
    build something no constructor of ours can build is a silent no-op. A def
    the log asks for repeatedly that never reaches allBuilt is that bug.
    """
    pool = defaultdict(int)
    samples = 0
    asked = Counter()
    log = run / "infolog.txt"
    if not log.exists():
        return pool, samples, asked
    tag = f"] apex"
    want = f"m t{team}] "
    with log.open(errors="replace") as fh:
        for line in fh:
            if want not in line or tag not in line:
                continue
            m = POOL_RE.search(line)
            if m:
                samples += 1
                for part in m.group(1).split():
                    if "=" not in part:
                        continue
                    k, _, v = part.partition("=")
                    if k.startswith("t") and k[1:].isdigit():
                        k = build_type(int(k[1:]))
                    try:
                        pool[k] += int(v)
                    except ValueError:
                        pass
            for d in DEF_RE.findall(line):
                asked[d] += 1
    return pool, samples, asked


def fmt(v):
    if isinstance(v, float):
        if abs(v) >= 10000:
            return f"{v/1000:.1f}k"
        return f"{v:.0f}" if abs(v) >= 10 else f"{v:.1f}"
    return str(v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run", type=Path)
    ap.add_argument("--team", type=int)
    ap.add_argument("--name", help="in-game display name, substring match")
    ap.add_argument("--tags", type=int, default=18, help="log tags to show")
    args = ap.parse_args()

    run = args.run
    if not (run / "result.json").exists():
        sys.exit(f"no result.json in {run}")
    res, rows = load(run)
    names, sides, allies, specs = names_and_sides(run)

    team = args.team
    if team is None and args.name:
        hits = [t for t, n in names.items() if args.name.lower() in n.lower()]
        if len(hits) != 1:
            sys.exit(f"--name matched {len(hits)} teams: "
                     + ", ".join(f"{t}={names[t]}" for t in hits))
        team = hits[0]
    if team is None:
        print("teams in this match:")
        for t in sorted(rows):
            print(f"  t{t:<3} {specs.get(t,'?'):<14} ally={allies.get(t,'?')} "
                  f"{sides.get(t,'?'):<7} {names.get(t,'')}")
        return

    ally = allies.get(team)
    peers = [t for t in rows if t != team and allies.get(t) == ally]
    foes = [t for t in rows if allies.get(t) != ally]

    r = res["result"]
    print(f"== {names.get(team, f'team {team}')}  t{team}  {specs.get(team,'?')}  "
          f"{sides.get(team,'?')}  ally {ally}")
    print(f"   {res['map']}  {r['game_minutes']:.1f} game-min  "
          f"winners={r['winners'] or 'none'}  valid={r['valid']}")
    print(f"   compared against {len(peers)} allies: {peers}")

    def series(t, k):
        return [row.get(k, 0.0) or 0.0 for row in rows[t]]

    print(f"\n{'metric':<16}{'this':>10}{'ally med':>10}{'ratio':>8}"
          f"{'ally min':>10}{'ally max':>10}  rank")
    for k in CUMULATIVE + [f"{x}(peak)" for x in STANDING]:
        peak = k.endswith("(peak)")
        key = k[:-6] if peak else k
        pick = (lambda t: max(series(t, key))) if peak else (lambda t: series(t, key)[-1])
        try:
            mine = pick(team)
            pv = sorted(pick(t) for t in peers)
        except (KeyError, ValueError):
            continue
        med = statistics.median(pv) if pv else 0.0
        ratio = (mine / med) if med else float("nan")
        rank = 1 + sum(1 for v in pv if v > mine)
        flag = "  <<<" if med and (ratio < 0.6 or ratio > 1.7) else ""
        print(f"{k:<16}{fmt(mine):>10}{fmt(med):>10}{ratio:>8.2f}"
              f"{fmt(pv[0]) if pv else '-':>10}{fmt(pv[-1]) if pv else '-':>10}"
              f"  {rank}/{len(pv)+1}{flag}")

    print("\ntimeline (this player | ally median)")
    hdr = ["mProd", "armyReal", "mex", "mCon", "conT1", "mDefence", "dmgDealt"]
    keys = ["metalProduced", "armyReal", "mex", "mCon", "conT1", "mDefence", "damageDealt"]
    print(f"{'min':>5}" + "".join(f"{h:>15}" for h in hdr))
    for i, row in enumerate(rows[team]):
        cells = []
        for k in keys:
            mine = row.get(k, 0.0) or 0.0
            pv = [rows[t][i].get(k, 0.0) or 0.0 for t in peers if i < len(rows[t])]
            med = statistics.median(pv) if pv else 0.0
            cells.append(f"{fmt(mine)}|{fmt(med)}")
        print(f"{row['frame']/1800:>5.0f}" + "".join(f"{c:>15}" for c in cells))

    print(f"\ntop units built (final): {rows[team][-1].get('top','')}")
    for t in peers[:3]:
        print(f"  ally t{t}: {rows[t][-1].get('top','')}")

    built = {}
    for part in (rows[team][-1].get("allBuilt") or "").split(","):
        if ":" in part:
            n, _, v = part.rpartition(":")
            try:
                built[n] = float(v)
            except ValueError:
                pass

    pool, samples, asked = pool_and_defs(run, team)
    if samples:
        print(f"\nbuilder task pool, mean over {samples} samples (decoded BuildType)")
        for k, v in sorted(pool.items(), key=lambda kv: -kv[1])[:10]:
            print(f"  {k:<12}{v/samples:>7.1f}")

    noop = [(d, c) for d, c in asked.items()
            if c >= 3 and d not in built and d in asked]
    if noop:
        print("\ndefs this player's log ASKS FOR but that never reach allBuilt")
        print("  CANDIDATES ONLY -- allBuilt counts 'real' units, so cheap spam")
        print("  (scouts, fodder, light AA) lands here having actually been built.")
        print("  Confirm each with `unitdef.py <def> --builders` before believing it.")
        for d, c in sorted(noop, key=lambda x: -x[1])[:12]:
            print(f"  {d:<16}named {c:>4}x, built 0")

    per_team, per_tag, last_min = ai_log_tags(run, set(rows))
    if per_team:
        print(f"\nAI log lines: this={per_team.get(team,0)}  "
              f"ally median={statistics.median([per_team.get(t,0) for t in peers]):.0f}"
              f"  last logged minute: this={last_min.get(team,0):.1f}"
              f" ally max={max((last_min.get(t,0) for t in peers), default=0):.1f}")
        allytags = Counter()
        for t in peers:
            allytags.update(per_tag[t])
        universe = set(per_tag[team]) | set(allytags)
        print(f"\n{'log tag':<34}{'this':>7}{'ally avg':>10}   note")
        scored = sorted(universe, key=lambda g: -(allytags[g] / max(len(peers), 1) + per_tag[team][g]))
        for g in scored[:args.tags]:
            mine = per_tag[team][g]
            avg = allytags[g] / max(len(peers), 1)
            note = ""
            if mine == 0 and avg >= 2:
                note = "NEVER FIRED for this player"
            elif avg and mine / avg > 3 and mine > 10:
                note = "much more than allies"
            elif avg >= 2 and mine / avg < 0.34:
                note = "far less than allies"
            print(f"{g:<34}{mine:>7}{avg:>10.1f}   {note}")


if __name__ == "__main__":
    main()
