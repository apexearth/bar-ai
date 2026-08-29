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

STATS_RE = re.compile(
    r"BARAI_STATS\] team=(\d+) .*?frame=(\d+).*?"
    r"mLostReal=(\d+) .*?mKillReal=(\d+).*? mex=(\d+)")
T2_RE = re.compile(r"\[BARAI_T2START\] team=(\d+) ally=\d+ frame=(\d+)")


def harvest(tour_dir):
    """Structural metrics for one tournament directory."""
    mex_a, mex_s, tech, kills, losses, conret = [], [], [], 0, 0, 0
    for match in sorted(os.listdir(os.path.join(tour_dir, "matches"))):
        log = os.path.join(tour_dir, "matches", match, "infolog.txt")
        if not os.path.isfile(log):
            continue
        text = open(log, encoding="utf-8", errors="replace").read()
        apex = "1" if "hard_vs_Apex" in match else "0"
        best = {}
        last = {}
        for m in STATS_RE.finditer(text):
            t, fr = m.group(1), int(m.group(2))
            if fr <= 28800 and (t not in best
                                or abs(fr - 27000) < abs(best[t][0] - 27000)):
                best[t] = (fr, int(m.group(5)))
            last[t] = (int(m.group(3)), int(m.group(4)))
        if apex in best and str(1 - int(apex)) in best:
            mex_a.append(best[apex][1])
            mex_s.append(best[str(1 - int(apex))][1])
        if apex in last:
            losses += last[apex][0]
            kills += last[apex][1]
        ts = [int(m.group(2)) for m in T2_RE.finditer(text)
              if m.group(1) == apex]
        if ts:
            tech.append(min(ts) / 1800.0)
        conret += len(re.findall(r"apex: con-retreat t=" + apex, text))
    return {
        "games": len(mex_a),
        "mex15_apex": statistics.median(mex_a) if mex_a else None,
        "mex15_stock": statistics.median(mex_s) if mex_s else None,
        "trade": round(kills / losses, 3) if losses else None,
        "t2_med_min": round(statistics.median(tech), 1) if tech else None,
        "con_retreats": conret,
    }


def run_battery():
    stamp = time.strftime("%Y%m%d-%H%M%S")
    row = {"at": stamp, "maps": {}}
    for mp in MAPS:
        name = f"battery-{mp.split()[0].lower()}-{stamp}"
        cmd = [sys.executable, "-u", os.path.join(HERE, "run_tournament.py"),
               "--a", SPEC_A, "--b", SPEC_B, "--maps", mp,
               "--games", str(GAMES), "--minutes", str(MINUTES),
               "--name", name]
        print(f"battery: {mp} x{GAMES} ...", flush=True)
        out = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
        m = re.search(r"output: (\S+)", out.stdout)
        if not m:
            print(f"  FAILED to launch on {mp}:\n{out.stdout[-500:]}")
            continue
        tour = m.group(1)
        row["maps"][mp] = harvest(tour)
        row["maps"][mp]["dir"] = os.path.basename(tour)
        print(f"  {mp}: {row['maps'][mp]}")
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
    print(f"\n{'when':17}", end="")
    for mp in MAPS:
        print(f"  {mp.split()[0]:>22}", end="")
    print("\n" + " " * 17 + f"  {'mex a/s trade t2':>22}" * len(MAPS))
    for r in rows[-12:]:
        print(f"{r['at']:17}", end="")
        for mp in MAPS:
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
    else:
        run_battery()
