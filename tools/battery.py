"""The fixed regression battery: same maps, same opponent, structural metrics.

One command, run after a session (or nightly):

    python tools/battery.py            # run 3 maps x 6 games, append trend row
    python tools/battery.py --report   # print the trend without running

Win rate is NOT a metric here -- it swung 60%->10% on an unchanged AI. The
battery tracks the structural numbers that moved every real regression this
repo has caught: mex@15m, army trade ratio, T2 start, con-retreat churn.
Each run appends one JSON line to tournaments/battery.jsonl; the trend table
is the diff between sessions. Runs land in tournaments/ like any other
tournament, so the dashboard's Games tab can open every game of every row.
"""
import json
import os
import re
import statistics
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TREND = os.path.join(ROOT, "tournaments", "battery.jsonl")

MAPS = ["Callisto", "Comet Catcher", "Glacier Pass"]
GAMES = 6
MINUTES = 25
SPEC_A = "Apex:Unstable:standard"
SPEC_B = "BARb:stable:hard"

# Team rounds (--teams): the AI's coordination layer -- eco roles, tech-lead
# election, metal slinging, team pushes -- only runs in these. His maps for
# each size. Fewer games and longer caps: team games are heavier and slower
# to decide.
TEAM_ROUNDS = [
    (2, "Archsimkats_Valley_V1"),
    (4, "Aethermoor Creek 1.0"),
    (8, "Supreme Isthmus v2.1"),
]
TEAM_GAMES = 4
TEAM_MINUTES = 40

STATS_RE = re.compile(
    r"BARAI_STATS\] team=(\d+) ally=(\d+) \S+ frame=(\d+).*?"
    r"mLostReal=(\d+) .*?mKillReal=(\d+).*? mex=(\d+)")
T2_RE = re.compile(r"\[BARAI_T2START\] team=\d+ ally=(\d+) frame=(\d+)")


def harvest(tour_dir):
    """Structural metrics for one tournament directory.

    Aggregated per SIDE (the ally field): each spec's players share the
    allyteam equal to its spec index, which is the only anchor that survives
    side-swapped and per-side games (the result.json team-index trap).
    """
    mex_a, mex_s, tech, kills, losses, conret = [], [], [], 0, 0, 0
    for match in sorted(os.listdir(os.path.join(tour_dir, "matches"))):
        log = os.path.join(tour_dir, "matches", match, "infolog.txt")
        if not os.path.isfile(log):
            continue
        text = open(log, encoding="utf-8", errors="replace").read()
        apex_ally = 1 if "hard_vs_Apex" in match else 0
        best = {}    # team -> (frame, mex, ally)
        last = {}    # team -> (lost, killed, ally)
        for m in STATS_RE.finditer(text):
            t, ally, fr = m.group(1), int(m.group(2)), int(m.group(3))
            if fr <= 28800 and (t not in best
                                or abs(fr - 27000) < abs(best[t][0] - 27000)):
                best[t] = (fr, int(m.group(6)), ally)
            last[t] = (int(m.group(4)), int(m.group(5)), ally)
        side_mex = {0: 0, 1: 0}
        seen = {0: False, 1: False}
        for fr, mex, ally in best.values():
            side_mex[ally] += mex
            seen[ally] = True
        if seen[0] and seen[1]:
            mex_a.append(side_mex[apex_ally])
            mex_s.append(side_mex[1 - apex_ally])
        for lost, killed, ally in last.values():
            if ally == apex_ally:
                losses += lost
                kills += killed
        # The rusher's own time, not a side-wide average -- a team strategy
        # that treats one player differently cannot be judged by the mean.
        ts = [int(m.group(2)) for m in T2_RE.finditer(text)
              if int(m.group(1)) == apex_ally]
        if ts:
            tech.append(min(ts) / 1800.0)
        # Every apex: line in an Apex-vs-BARb game is ours, whichever side.
        conret += len(re.findall(r"apex: con-retreat t=", text))
    return {
        "games": len(mex_a),
        "mex15_apex": statistics.median(mex_a) if mex_a else None,
        "mex15_stock": statistics.median(mex_s) if mex_s else None,
        "trade": round(kills / losses, 3) if losses else None,
        "t2_med_min": round(statistics.median(tech), 1) if tech else None,
        "con_retreats": conret,
    }


def run_round(row, key, mp, games, minutes, per_side, stamp):
    name = f"battery-{key.split()[0].lower().replace('v', '')}-{stamp}"
    cmd = [sys.executable, "-u", os.path.join(HERE, "run_tournament.py"),
           "--a", SPEC_A, "--b", SPEC_B, "--maps", mp,
           "--games", str(games), "--minutes", str(minutes),
           "--name", name]
    if per_side > 1:
        cmd += ["--per-side", str(per_side)]
    print(f"battery: {key} x{games} ...", flush=True)
    out = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    m = re.search(r"output: (\S+)", out.stdout)
    if not m:
        print(f"  FAILED to launch {key}:\n{out.stdout[-500:]}")
        return
    tour = m.group(1)
    row["maps"][key] = harvest(tour)
    row["maps"][key]["dir"] = os.path.basename(tour)
    print(f"  {key}: {row['maps'][key]}")


def run_battery(teams=False):
    stamp = time.strftime("%Y%m%d-%H%M%S")
    row = {"at": stamp, "maps": {}}
    for mp in MAPS:
        run_round(row, mp, mp, GAMES, MINUTES, 1, stamp)
    if teams:
        for size, mp in TEAM_ROUNDS:
            run_round(row, f"{size}v{size}", mp, TEAM_GAMES, TEAM_MINUTES,
                      size, stamp)
    with open(TREND, "a", encoding="utf-8") as f:
        f.write(json.dumps(row) + "\n")
    print(f"\nappended to {TREND}")
    report()


def report():
    if not os.path.isfile(TREND):
        print("no battery rows yet")
        return
    rows = [json.loads(l) for l in open(TREND, encoding="utf-8")
            if l.strip()]
    cols = []
    for r in rows:
        for k in r["maps"]:
            if k not in cols:
                cols.append(k)
    print(f"\n{'when':17}", end="")
    for mp in cols:
        print(f"  {mp.split()[0]:>22}", end="")
    print("\n" + " " * 17 + f"  {'mex a/s trade t2':>22}" * len(cols))
    for r in rows[-12:]:
        print(f"{r['at']:17}", end="")
        for mp in cols:
            d = r["maps"].get(mp)
            if not d or d.get("mex15_apex") is None:
                print(f"  {'-':>22}", end="")
                continue
            cell = (f"{d['mex15_apex']:.0f}/{d['mex15_stock']:.0f} "
                    f"{d['trade'] if d['trade'] is not None else '-'} "
                    f"{d['t2_med_min'] if d['t2_med_min'] is not None else '-'}m")
            print(f"  {cell:>22}", end="")
        print()


if __name__ == "__main__":
    if "--report" in sys.argv:
        report()
    elif "--teams-only" in sys.argv:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        row = {"at": stamp, "maps": {}}
        for size, mp in TEAM_ROUNDS:
            run_round(row, f"{size}v{size}", mp, TEAM_GAMES, TEAM_MINUTES,
                      size, stamp)
        with open(TREND, "a", encoding="utf-8") as f:
            f.write(json.dumps(row) + "\n")
        report()
    else:
        run_battery(teams="--teams" in sys.argv)
