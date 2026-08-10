#!/usr/bin/env python3
"""Dump every game's raw numbers as CSV -- one row per side per game.

Why this exists: two ways of reading a run produced two opposite answers in one
session. `composition.py` reports spend as a share of each side's OWN metal,
which understates a side that produces more; and a hand-rolled aggregate that
grouped by ALLY INDEX compared each AI against itself, because run_tournament
swaps sides every other game -- it reported apex holding 1.56x the army when
apex actually holds 0.64x. Here every column is an absolute value, every row is
labelled with the AI that actually played it (read from that game's own start
script), and `_x` columns are per-game ratios against the opponent.

    python tools/gamecsv.py matches/watch-comet                 # one match
    python tools/gamecsv.py tournaments/2026...-fast-baseline   # a whole run
    python tools/gamecsv.py tournaments/a tournaments/b --summary
    python tools/gamecsv.py tournaments/a --out arm-a.csv

Standing counters (army, constructors, defence) are reported as PEAK, because
they go to zero when a team dies and the last sample of a lost game is a corpse.
Cumulative counters (metal, kills, losses, damage) are end-state.

Engagement columns come from the infolog's own `apex: engage` lines, so they are
only populated for runs where apex played and logged them.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import statistics as st
import sys
from collections import defaultdict
from pathlib import Path

# PEAK because a dead team's standing counters read zero; CUM is end-state.
PEAK = ["armyReal", "armyCheap", "mDefence", "mCon", "mFactories", "ownUnits"]
CUM = ["metalProduced", "metalUsed", "metalExcess", "energyProduced", "energyExcess",
       "mKillReal", "mKillCheap", "mLostReal", "mLostCheap", "mKillStatic",
       "mBuiltReal", "mReclaim", "mRezSpend",
       "mT1", "mT2", "mT3", "damageDealt", "damageReceived", "mex", "t2Mex", "commLost"]

ENGAGE_RE = re.compile(
    r"apex: engage (\w+) units=(\d+) spread=(\d+) hp=([\d.]+) coh=([\d.]+) power=(\d+) need=(\d+)")


def match_dirs(root: Path) -> list[Path]:
    """A match directory has result.json; a tournament has matches/*/result.json."""
    if (root / "result.json").exists():
        return [root]
    inner = root / "matches"
    base = inner if inner.is_dir() else root
    return sorted(p for p in base.iterdir() if (p / "result.json").exists())


def engagements(d: Path) -> dict:
    log = d / "infolog.txt"
    if not log.exists():
        return {}
    rows = ENGAGE_RE.findall(log.read_text(errors="replace"))
    if not rows:
        return {}
    units = [int(r[1]) for r in rows]
    coh = [float(r[4]) for r in rows]
    return {
        "engagements": len(rows),
        "engage_med_units": st.median(units),
        "engage_pct_le3": round(100 * sum(1 for u in units if u <= 3) / len(units), 1),
        "engage_pct_ge15": round(100 * sum(1 for u in units if u >= 15) / len(units), 1),
        "engage_med_coh": round(st.median(coh), 2),
        "engage_skipped": sum(1 for r in rows if r[0] != "TAKE"),
    }


def read_game(d: Path) -> list[dict]:
    r = json.load(open(d / "result.json"))
    res = r.get("result", {})
    stats = r.get("stats") or []
    if not stats:
        return []

    # Sum every player onto its ally team, per sample frame.
    by = defaultdict(lambda: defaultdict(float))
    names = {}
    for s in stats:
        by[(s["ally"], s["frame"])]
        for k, v in s.items():
            if isinstance(v, (int, float)) and k not in ("team", "ally", "frame"):
                by[(s["ally"], s["frame"])][k] += v
    last = max(f for _, f in by)

    # WHICH AI IS ON WHICH ALLY TEAM MUST BE READ PER GAME.
    #
    # run_tournament swaps sides every other match, so ally 0 is the --a AI in
    # half the games and the --b AI in the other half. Aggregating by ally index
    # therefore compares each AI against itself and can invert the answer
    # outright -- it read as "apex holds 1.56x the army" when apex actually holds
    # 0.64x. Every row here is labelled from this game's own start script.
    cfg = d / "script.txt"
    if cfg.exists():
        text = cfg.read_text(errors="replace")
        for m in re.finditer(r"\[AI(\d+)\]\s*\{(.*?)\}", text, re.S):
            body = m.group(2)
            sn = re.search(r"ShortName=(\w+);", body)
            ver = re.search(r"Version=(\w+);", body)
            team = re.search(r"Team=(\d+);", body)
            # The profile lives in the AI's OPTIONS block and is NOT part of
            # ShortName:Version -- without it, BARb:stable:hard and
            # BARb:stable:medium collapse into one row and a reference run reads
            # as a single mixed arm.
            prof = re.search(r"profile=(\w+);", body)
            if sn and team:
                label = f"{sn.group(1)}:{ver.group(1) if ver else ''}"
                if prof:
                    label += f":{prof.group(1)}"
                names[int(team.group(1))] = label
    team_ally = {int(s["team"]): s["ally"] for s in stats}
    ally_name = {}
    for t, nm in sorted(names.items()):
        if t in team_ally:
            ally_name.setdefault(team_ally[t], nm)

    eng = engagements(d)
    out = []
    for ally in sorted({a for a, _ in by}):
        row = {
            "run": d.parent.parent.name if d.parent.name == "matches" else d.parent.name,
            "game": d.name,
            "map": r.get("map", ""),
            "minutes": round(res.get("game_minutes", 0), 1),
            "reason": res.get("reason", ""),
            "ally": int(ally),
            "ai": ally_name.get(ally, ""),
            "won": int(bool(res.get("winners")) and ally_name.get(ally, "").split(":")[0]
                       in " ".join(str(w) for w in res.get("winners", []))),
            # Which start box. On some maps this is worth a 2x swing in army and
            # K/D, so an arm that is not paired by orientation mostly measures
            # which box it drew.
            "box": "first" if ally == 0 else "second",
        }
        peak = defaultdict(float)
        for (a, fr), g in by.items():
            if a != ally:
                continue
            for k in PEAK:
                peak[k] = max(peak[k], g.get(k, 0.0))
        fin = by[(ally, last)]
        for k in PEAK:
            row["peak_" + k] = round(peak[k])
        for k in CUM:
            row[k] = round(fin.get(k, 0.0))
        row["kd"] = round(fin.get("mKillReal", 0) / max(fin.get("mLostReal", 0), 1), 3)
        # THE LESS NOISY METRIC. K/D has a per-game sd of 0.41 on a mean of 0.67
        # (62% relative); enemy metal destroyed per metal produced has 23%, so it
        # sees a real change in ~13-30 games where K/D needs 117+. It is also the
        # question actually being asked: how much of the enemy did this economy
        # destroy? `kill_rate` is the same thing per game minute -- "kill them
        # faster" is a rate, not a ratio.
        killed = fin.get("mKillReal", 0) + fin.get("mKillCheap", 0)
        row["kill_per_metal"] = round(killed / max(fin.get("metalProduced", 0), 1), 4)
        row["kill_rate_per_min"] = round(killed / max(res.get("game_minutes", 0), 1), 1)
        # apexearth: "do you have the ability to see how many units we're
        # producing per minute?" -- and the waste beside it, because a full bank
        # with idle factories is the failure these numbers are meant to catch.
        mins = max(res.get("game_minutes", 0), 1)
        row["units_per_min"] = round(fin.get("ownUnits", 0) / mins, 2)
        row["built_per_min"] = round(fin.get("mBuiltReal", 0) / mins, 1)
        row["metal_per_min"] = round(fin.get("metalProduced", 0) / mins, 1)
        row["waste_pct"] = round(100 * fin.get("metalExcess", 0)
                                 / max(fin.get("metalProduced", 0), 1), 1)
        row["dmg_ratio"] = round(fin.get("damageDealt", 0) / max(fin.get("damageReceived", 0), 1), 3)
        # A team whose standing counters end at zero was wiped out.
        row["wiped"] = int(fin.get("ownUnits", 0) == 0)
        row.update(eng if ally == 0 else {})
        out.append(row)
    return out


def timeline(paths: list[str]) -> None:
    """Per-sample walk of one game: what we HELD, minute by minute.

    apexearth: "can that analysis also count how many cons we have and labs we
    have by minute?" conT1/conT2 are counts from the stats gadget; factories are
    reported as METAL (mFactories), the gadget has no count, so it is shown as
    spend and as an implied lab count at ~600 metal a lab.
    """
    for pth in paths:
        for d in match_dirs(Path(pth)):
            r = json.load(open(d / "result.json"))
            stats = r.get("stats") or []
            if not stats:
                continue
            by = defaultdict(lambda: defaultdict(float))
            for s in stats:
                for k, v in s.items():
                    if isinstance(v, (int, float)) and k not in ("team", "ally", "frame"):
                        by[(s["ally"], s["frame"])][k] += v
            print()
            print(f"{d.name}   {r.get('map','')}")
            print(f"{'min':>5s} | {'conT1':>5s} {'conT2':>5s} {'facM':>7s} {'~labs':>5s} "
                  f"{'units':>5s} {'army':>8s} {'metal':>9s} {'waste%':>6s} | "
                  f"{'eT1':>4s} {'eT2':>4s} {'eArmy':>8s} {'eMetal':>9s}")
            for fr in sorted({f for _, f in by}):
                a, b = by[(0.0, fr)], by[(1.0, fr)]
                w = 100 * a["metalExcess"] / max(a["metalProduced"], 1)
                print(f"{fr/1800:5.1f} | {a['conT1']:5.0f} {a['conT2']:5.0f} {a['mFactories']:7,.0f} "
                      f"{a['mFactories']/600:5.1f} {a['ownUnits']:5.0f} {a['armyReal']:8,.0f} "
                      f"{a['metalProduced']:9,.0f} {w:6.1f} | {b['conT1']:4.0f} {b['conT2']:4.0f} "
                      f"{b['armyReal']:8,.0f} {b['metalProduced']:9,.0f}")


def ratios(rows: list[dict]) -> list[dict]:
    """Add apex-over-opponent columns. Ally 0 is the --a side by convention."""
    by_game = defaultdict(list)
    for r in rows:
        by_game[(r["run"], r["game"])].append(r)
    for pair in by_game.values():
        if len(pair) != 2:
            continue
        a, b = sorted(pair, key=lambda r: r["ally"])
        for k in ("peak_armyReal", "peak_mDefence", "peak_mCon", "metalProduced",
                  "mKillReal", "mLostReal", "mT3"):
            a[k + "_x"] = round(a[k] / max(b[k], 1), 3)
            b[k + "_x"] = ""
    return rows


def summarise(rows: list[dict]) -> None:
    by_run_ally = defaultdict(list)
    for r in rows:
        by_run_ally[(r["run"], r["ai"] or f"ally{r['ally']}")].append(r)
    keys = ["peak_armyReal", "peak_mDefence", "peak_mCon", "metalProduced",
            "mKillReal", "mKillCheap", "mLostReal"]
    print(f"{'run':34s} {'ai':22s} {'n':>3s} " + " ".join(f"{k.replace('peak_',''):>13s}" for k in keys) + f" {'K/D':>6s} {'kill/m':>7s} {'wiped':>6s}")
    for (run, ai), rs in sorted(by_run_ally.items()):
        tot = {k: sum(r[k] for r in rs) for k in keys}
        kd = tot["mKillReal"] / max(tot["mLostReal"], 1)
        kpm = (tot["mKillReal"] + tot["mKillCheap"]) / max(tot["metalProduced"], 1)
        print(f"{run[:34]:34s} {ai[:22]:22s} {len(rs):3d} "
              + " ".join(f"{tot[k]:13,.0f}" for k in keys)
              + f" {kd:6.2f} {kpm:7.3f} {sum(r['wiped'] for r in rs):6d}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+", help="match or tournament directories")
    ap.add_argument("--out", help="write CSV here instead of stdout")
    ap.add_argument("--summary", action="store_true", help="totals per run instead of CSV")
    ap.add_argument("--timeline", action="store_true",
                    help="per-sample walk of each game: cons, labs, army, waste")
    args = ap.parse_args()

    if args.timeline:
        timeline(args.paths)
        return 0

    rows: list[dict] = []
    for p in args.paths:
        root = Path(p)
        if not root.exists():
            print(f"no such directory: {root}", file=sys.stderr)
            return 2
        for d in match_dirs(root):
            rows.extend(read_game(d))
    if not rows:
        print("no games found", file=sys.stderr)
        return 2
    rows = ratios(rows)

    if args.summary:
        summarise(rows)
        return 0

    cols: list[str] = []
    for r in rows:
        for k in r:
            if k not in cols:
                cols.append(k)
    fh = open(args.out, "w", newline="", encoding="utf-8") if args.out else sys.stdout
    w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
    w.writeheader()
    w.writerows(rows)
    if args.out:
        fh.close()
        print(f"{len(rows)} rows -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
