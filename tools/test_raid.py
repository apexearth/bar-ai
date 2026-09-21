#!/usr/bin/env python3
"""The raid-defence regression test: scripted raids, no turrets, judged per wave.

docs/24-how-units-fight.md: "A player should be able to respond to radar
sightings to position units properly for defending buildings... we need to be
extremely good at detecting enemy threats in our areas, creating appropriately
sized squads, and hunting down those enemies."

Stock BARb makes first contact at 8-12 minutes on the benchmark, so a natural
game cannot test the first five. This test adds a NullAI holder team on the
enemy's side and lets dev_raid.lua spawn waves for it at fixed minutes,
fight-moved at our start. Apex runs with `apex_def_off=1` (no turrets), so
radar and units are its whole answer. Every metric is read from the gadgets'
[BARAI_RAID] / [BARAI_RAIDEND] / [BARAI_DEATH] / [BARAI_DMG] lines.

Per wave: was it wiped out, how long that took, how close it got to our start,
what we lost TO THE RAIDERS (deaths whose attacker is the holder team) against
what the wave cost, and the building damage and constructor interruptions
taken while it was alive. A game passes a metric when every wave in it does;
the set passes a metric when PASS_FRAC of games do. THRESHOLDS are calibrated
on the first baseline set and say so -- they catch a regression from that
state, not distance from an ideal.

    python tools/test_raid.py                        # run the set, then judge
    python tools/test_raid.py <set-dir>              # judge an existing set
    python tools/test_raid.py --games 8 --parallel 3 --minutes 11
    python tools/test_raid.py --waves "3:armpw*2|5:armpw*4"
    python tools/test_raid.py --turrets              # control: turrets on
    python tools/test_raid.py --level 3              # harder raids; see LEVELS

Runs land in tournaments/<stamp>-raid/.
"""
from __future__ import annotations

import argparse
import json
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import test_earlyfight as ef  # noqa: E402

SPEC_A = "Apex:Unstable:standard"
# A passive opponent: with stock BARb here its own raids landed on top of
# the scripted waves and were counted against them.
SPEC_B = "NullAI:0.1"
HOLDER = "NullAI:0.1"
MAP = ef.MAP
FPS = 30
WAVES = "3:armpw*2|5:armpw*3,armflea*2|7:armpw*5|9:armpw*4,armham*2"
WAVES_HARD = "3:armpw*3|5:armpw*4,armflea*3|7:armpw*6,armham*2|9:armpw*6,armham*3,armflea*3"
WAVES_FIVE = "3:armpw*5|5:armpw*5,armflea*5|7:armpw*10|9:armpw*10,armflea*5"
# Difficulty levels, as dev_raid.lua modoptions. Level 1 is what the bars were
# calibrated on; the others are report-only until they have a baseline.
LEVELS = {
    1: {"dev_raid_angle": "enemy", "dev_raid_split": 1, "dev_raid_stagger": 0,
        "dev_raid_target": "base", "waves": WAVES,
        "what": "one clump, straight from the enemy, at the base centre"},
    2: {"dev_raid_angle": "random", "dev_raid_split": 1, "dev_raid_stagger": 0,
        "dev_raid_target": "mex", "waves": WAVES,
        "what": "one clump from a random bearing, at the nearest extractor"},
    3: {"dev_raid_angle": "random", "dev_raid_split": 2, "dev_raid_stagger": 8,
        "dev_raid_target": "edge", "waves": WAVES,
        "what": "two groups from two bearings, 8 s apart, at the outlying buildings"},
    4: {"dev_raid_angle": "random", "dev_raid_split": 3, "dev_raid_stagger": 10,
        "dev_raid_target": "con", "waves": WAVES_HARD,
        "what": "three bigger groups from three bearings, 10 s apart, hunting constructors"},
    # apexearth: "You may have 5 different enemies from different angles
    # attacking different base buildings... Their goal is to kill a mex or a
    # solar panel."
    5: {"dev_raid_angle": "random", "dev_raid_split": 5, "dev_raid_stagger": 0,
        "dev_raid_target": "eco", "waves": WAVES_FIVE,
        "what": "five groups at once from five bearings, each at a mex or solar"},
}
PASS_FRAC = 0.75
MIN_SCORED = 3

# Calibrated 2026-09-04 on three level-1 sets of 8 games (tournaments/
# 20260904-{165223-raid-base,171135-raid-resp,174917-raid-lv-L1}): every wave
# wiped, worst wipe 50 s, worst wave K/D 0.50; closest approach on waves 2-4
# passed 8/8, 8/8 and 6/8 at 50 elmo, which is why that bar is not higher. A
# metric fails a GAME when any judged wave in it misses the bar: this catches
# a regression from that state, not distance from ideal.
THRESHOLDS = {
    "cleared": 1.0,      # fraction of the wave's raiders dead before game end
    "closest": 50.0,     # elmos from our base the wave got no nearer than
    "clear_s": 60.0,     # seconds from spawn to the last raider's death
    "kd": 0.5,           # raider metal killed / our metal lost to raiders
}

RAID_RE = re.compile(r"\[BARAI_RAID\] wave=(\d+)(?: group=(\d+)/(\d+))? frame=(\d+) n=(\d+) metal=(\d+)")
BASE_RE = re.compile(r"\[BARAI_BASE\] frame=(\d+) team=(\d+) bld=(\d+) rms=(\d+) max=(\d+) mex=(\d+) mexmax=(\d+)"
                     r"(?: army=(-?\d+) armyM=(-?\d+) armyRms=(-?\d+) raiders=(-?\d+) raidM=(-?\d+))?")
END_RE = re.compile(r"\[BARAI_RAIDEND\] wave=(\d+) frame=(\d+) spawned=(\d+) killed=(\d+) "
                    r"alive=(\d+) dur=(\d+) closest=(-?\d+)"
                    r"(?: seen=(-?\d+) engaged=(-?\d+) resp=(-?\d+) peak=(-?\d+) army=(-?\d+))?")
DEATH_RE = re.compile(r"\[BARAI_DEATH\] (.*)")


def holder_team(match_dir: Path) -> int | None:
    p = match_dir / "result.json"
    if not p.exists():
        return None
    try:
        for t in json.loads(p.read_text("utf-8")).get("teams", []):
            if t.get("extra"):
                return int(t["team"])
    except (ValueError, KeyError):
        pass
    return None


RADAR_RE = re.compile(r"\[BARAI_BUILD\] team=(\d+) ally=\d+ frame=\d+ min=([\d.]+) unit=\w*rad ")


def first_radar_min(match_dir: Path, team: int) -> float | None:
    for line in ef.gadget_text(match_dir).splitlines():
        m = RADAR_RE.search(line)
        if m and int(m.group(1)) == team:
            return float(m.group(2))
    return None


def read_raid(match_dir: Path):
    text = ef.gadget_text(match_dir)
    waves, deaths, bases = {}, [], []
    for line in text.splitlines():
        m = RAID_RE.search(line)
        if m:
            w = int(m.group(1))
            d = waves.setdefault(w, {"n": 0, "metal": 0.0, "groups": 0})
            f = int(m.group(4))
            d["start"] = min(d.get("start", f), f)
            d["n"] += int(m.group(5))
            d["metal"] += float(m.group(6))
            d["groups"] += 1
            continue
        m = BASE_RE.search(line)
        if m:
            bases.append({"frame": int(m.group(1)), "bld": int(m.group(3)), "rms": int(m.group(4)),
                          "max": int(m.group(5)), "mex": int(m.group(6)), "mexmax": int(m.group(7)),
                          "army": int(m.group(8)) if m.group(8) else None,
                          "armyM": int(m.group(9)) if m.group(9) else None,
                          "armyRms": int(m.group(10)) if m.group(10) else None,
                          "raiders": int(m.group(11)) if m.group(11) else None,
                          "raidM": int(m.group(12)) if m.group(12) else None})
            continue
        m = END_RE.search(line)
        if m:
            w = int(m.group(1))
            d = waves.setdefault(w, {})
            d.update(end=int(m.group(2)), spawned=int(m.group(3)), killed=int(m.group(4)),
                     alive=int(m.group(5)), dur=int(m.group(6)), closest=int(m.group(7)))
            if m.group(8) is not None:
                d.update(seen=int(m.group(8)), engaged=int(m.group(9)), resp=int(m.group(10)),
                         peak=int(m.group(11)), army=int(m.group(12)))
            continue
        m = DEATH_RE.search(line)
        if m:
            d = ef.kv(m.group(1))
            try:
                deaths.append((int(d["frame"]), int(d["team"]), float(d["cost"]),
                               d["built"] == "1", int(d["atkteam"]), d.get("st") == "1"))
            except (KeyError, ValueError):
                pass
    return waves, deaths, bases


def dmg_at(dmg_rows, teams, frame, before=True):
    """Summed cumulative DMG counters for `teams` at the sample nearest
    `frame` on the requested side (the gadget samples every 10 s)."""
    best = {}
    for f, team, d in dmg_rows:
        if team not in teams:
            continue
        if before and f > frame:
            continue
        if not before and f < frame:
            continue
        cur = best.get(team)
        if cur is None or (before and f > cur[0]) or (not before and f < cur[0]):
            best[team] = (f, d)
    tot = {}
    for _f, d in best.values():
        for k, v in d.items():
            tot[k] = tot.get(k, 0.0) + v
    return tot


def analyse(match_dir: Path):
    us = ef.apex_teams(match_dir)
    holder = holder_team(match_dir)
    if not us or holder is None:
        return None
    radar_mins = [m for m in (first_radar_min(match_dir, t) for t in us) if m is not None]
    radar_min = min(radar_mins) if radar_mins else None
    waves, deaths, bases = read_raid(match_dir)
    _teams, _d, dmg_rows, _s, _sp = ef.read_logs(match_dir)
    rows = []
    for w in sorted(waves):
        d = waves[w]
        if "start" not in d:
            continue
        start = d["start"]
        end = d.get("end", start + d.get("dur", 0))
        lost = sum(c for f, t, c, built, atk, st in deaths
                   if start <= f <= end and t in us and built and atk == holder)
        killed_m = sum(c for f, t, c, built, atk, st in deaths
                       if start <= f <= end and t == holder)
        bld_lost = sum(1 for f, t, c, built, atk, st in deaths
                       if start <= f <= end and t in us and atk == holder and st)
        a = dmg_at(dmg_rows, us, start, before=True)
        b = dmg_at(dmg_rows, us, end, before=False) or dmg_at(dmg_rows, us, end, before=True)
        spawned = d.get("spawned", d.get("n", 0))
        base = None
        for bs in bases:
            if bs["frame"] <= start:
                base = bs
        rows.append({
            "wave": w,
            "groups": d.get("groups", 1),
            "bld": base["bld"] if base else None,
            "baseRms": base["rms"] if base else None,
            "baseMax": base["max"] if base else None,
            "mexMax": base["mexmax"] if base else None,
            "ourArmy": base["army"] if base and base["army"] is not None and base["army"] >= 0 else None,
            "ourArmyM": base["armyM"] if base and base["armyM"] is not None and base["armyM"] >= 0 else None,
            "armyRms": base["armyRms"] if base and base["armyRms"] is not None and base["armyRms"] >= 0 else None,
            "raidM": base["raidM"] if base and base["raidM"] is not None and base["raidM"] >= 0 else None,
            "minute": round(start / FPS / 60, 1),
            "n": spawned,
            "metal": d.get("metal", 0.0),
            "cleared": (d.get("killed", 0) / spawned) if spawned else 0.0,
            "clear_s": (d["dur"] / FPS) if d.get("alive", 1) == 0 and "dur" in d else None,
            "closest": d.get("closest", -1),
            "lost": lost,
            "bldLost": bld_lost,
            "killedM": killed_m,
            "kd": (killed_m / lost) if lost > 0 else (None if killed_m == 0 else float("inf")),
            "bldRecv": max(0.0, b.get("rs", 0) - a.get("rs", 0)),
            "interrupts": max(0.0, b.get("bi", 0) - a.get("bi", 0)),
            "conDeaths": max(0.0, b.get("bd", 0) - a.get("bd", 0)),
            "dgHits": max(0.0, b.get("dg", 0) - a.get("dg", 0)),
            "dgKillM": max(0.0, b.get("dgm", 0) - a.get("dgm", 0)),
            "radar_min": radar_min,
            # detection and response, seconds from spawn / from first sighting
            "seen_s": (d["seen"] / FPS) if d.get("seen", -1) >= 0 else None,
            "react_s": ((d["engaged"] - d["seen"]) / FPS)
                       if d.get("seen", -1) >= 0 and d.get("engaged", -1) >= 0 else None,
            "resp": d.get("resp", -1) if d.get("resp", -1) >= 0 else None,
            "peak": d.get("peak", -1) if d.get("peak", -1) >= 0 else None,
            "army": d.get("army", -1) if d.get("army", -1) >= 0 else None,
            "commit": (d["peak"] / d["army"]) if d.get("army", 0) > 0 and d.get("peak", -1) >= 0 else None,
        })
    return rows


def wave_ok(r, k):
    t = THRESHOLDS[k]
    if k == "cleared":
        return r["cleared"] >= t
    if k == "closest":
        # Wave one meets a base with only the commander home and gets in
        # 30-40% of the time on the unchanged AI (three sets of eight); it is
        # reported as "wave-one intrusions", not gated, until that is fixed.
        return r["wave"] == 1 or r["closest"] >= t
    if k == "clear_s":
        return r["clear_s"] is not None and r["clear_s"] <= t
    if k == "kd":
        return r["kd"] is not None and r["kd"] >= t
    return True


def fmt(v):
    if v is None:
        return "-"
    if v == float("inf"):
        return "inf"
    return f"{v:.2f}" if isinstance(v, float) and abs(v) < 100 else f"{v:.0f}"


def judge(out: Path, level: int = 1):
    dirs = sorted(p for p in (out / "matches").iterdir() if (p / "result.json").exists())
    per_metric = {k: [] for k in THRESHOLDS}
    all_rows = []
    print(f"== {out.name}: {len(dirs)} games ==")
    for d in dirs:
        rows = analyse(d)
        if not rows:
            print(f"  {d.name}: no raid lines (gadget not installed, no holder team, or the AI never loaded)")
            continue
        won, mins = ef.outcome(d)
        how = "won" if won else ("lost" if won is False else "timelimit")
        print(f"  {d.name} ({how} at {mins}m)")
        print("    wave  min    n  metal  cleared  clear_s  closest    lost  bldLost  killedM      kd  bldRecv  interrupts"
              "   seen_s  react_s  resp/peak/army")
        for r in rows:
            print(f"    {r['wave']:>4} {r['minute']:>4} {r['n']:>4} {fmt(r['metal']):>6} "
                  f"{fmt(r['cleared']):>8} {fmt(r['clear_s']):>8} {fmt(float(r['closest'])):>8} "
                  f"{fmt(r['lost']):>7} {fmt(float(r['bldLost'])):>8} {fmt(r['killedM']):>8} {fmt(r['kd']):>7} "
                  f"{fmt(r['bldRecv']):>8} {fmt(r['interrupts']):>11}"
                  f" {fmt(r['seen_s']):>8} {fmt(r['react_s']):>8}  "
                  f"{fmt(r['resp']) if r['resp'] is not None else '-'}/"
                  f"{fmt(r['peak']) if r['peak'] is not None else '-'}/"
                  f"{fmt(r['army']) if r['army'] is not None else '-'}")
            all_rows.append(r)
        for k in THRESHOLDS:
            per_metric[k].append(all(wave_ok(r, k) for r in rows))

    if not all_rows:
        print("nothing to judge")
        return False

    def med(key):
        vals = [r[key] for r in all_rows if r[key] is not None and r[key] != float("inf")]
        return statistics.median(vals) if vals else None

    print(f"\n== PER-WAVE MEDIANS over {len(all_rows)} waves ==")
    for key, label in (("cleared", "fraction of raiders killed"),
                       ("clear_s", "seconds to wipe the wave"),
                       ("closest", "nearest approach to our start, elmo"),
                       ("lost", "our metal lost to raiders"),
                       ("bldLost", "our buildings killed by raiders"),
                       ("killedM", "raider metal killed"),
                       ("kd", "raider metal killed / ours lost"),
                       ("bldRecv", "building damage taken meanwhile"),
                       ("interrupts", "constructor interruptions meanwhile"),
                       ("dgHits", "commander D-gun hits meanwhile"),
                       ("dgKillM", "metal killed by the D-gun meanwhile"),
                       ("radar_min", "first radar finished, game minute"),
                       ("seen_s", "seconds from spawn to first sighting"),
                       ("react_s", "seconds from sighting to first hit"),
                       ("resp", "our mobile units near the wave at first hit"),
                       ("peak", "most of our mobile units near the wave"),
                       ("army", "our mobile armed units at the time"),
                       ("commit", "share of the army that went to the wave"),
                       ("ourArmy", "our mobile army when the wave spawned"),
                       ("ourArmyM", "its metal"),
                       ("armyRms", "army spread, RMS distance from base centroid"),
                       ("raidM", "raider metal the wave was sized to (ratio runs)"),
                       ("bld", "our buildings when the wave spawned"),
                       ("baseRms", "base spread, RMS distance from centroid"),
                       ("baseMax", "base spread, farthest building"),
                       ("mexMax", "farthest extractor from centroid")):
        print(f"  {label:<38} {fmt(med(key)):>9}")
    lo = sorted(r["closest"] for r in all_rows)
    print(f"  closest approach, worst quartile          {fmt(float(lo[len(lo) // 4])):>9}")

    if level != 1:
        print(f"\n== VERDICT ==  level {level} has no calibrated bars yet: reported, not judged")
        (out / "raid_summary.json").write_text(json.dumps(
            {"games": len(dirs), "level": level, "waves": all_rows, "passed": None}, indent=2))
        return True
    w1_in = sum(1 for r in all_rows if r["wave"] == 1 and r["closest"] < THRESHOLDS["closest"])
    w1_n = sum(1 for r in all_rows if r["wave"] == 1)
    print(f"\n== VERDICT ==  (wave-one intrusions inside {THRESHOLDS['closest']:.0f} elmo: "
          f"{w1_in}/{w1_n} games -- reported, not judged)")
    failed = 0
    for k, v in per_metric.items():
        if len(v) < MIN_SCORED:
            print(f"  {k:<8} only {len(v)} scored game(s); need {MIN_SCORED}")
            failed += 1
            continue
        frac = sum(v) / len(v)
        ok = frac >= PASS_FRAC
        failed += 0 if ok else 1
        tag = "ok  " if ok else "FAIL"
        print(f"  {tag}  {k:<8} {sum(v)}/{len(v)} games pass (need {PASS_FRAC:.0%}; bar {THRESHOLDS[k]})")
    summary = {"games": len(dirs), "waves": all_rows,
               "metrics": {k: (sum(v), len(v)) for k, v in per_metric.items()},
               "thresholds": THRESHOLDS, "passed": failed == 0}
    (out / "raid_summary.json").write_text(json.dumps(summary, indent=2))
    return failed == 0


def run_set(out: Path, games: int, parallel: int, minutes: int, handicap: int,
            map_name: str, sides: str, turrets: bool, waves: str, raid_from: float,
            level: int, ratio: float = 2.0,
            modoptions: list | None = None, seed0: int = 1, speed: int = 0):
    out.mkdir(parents=True, exist_ok=True)
    (out / "matches").mkdir(exist_ok=True)
    pending = list(range(seed0, seed0 + games))
    live, slots = [], list(range(parallel))
    while pending or live:
        while pending and slots:
            seed = pending.pop(0)
            slot = slots.pop(0)
            mdir = out / "matches" / f"s{seed}"
            wdir = ROOT / "matches" / f"_engine_rd{slot}"
            cmd = [sys.executable, "-u", str(HERE / "run_match.py"),
                   "--a", SPEC_A, "--b", SPEC_B, "--extra-ai", f"{HOLDER}@1",
                   "--map", map_name, "--minutes", str(minutes), "--seed", str(seed),
                   "--sides", sides, "--handicap", str(handicap),
                   "--out", str(mdir), "--write-dir", str(wdir),
                   "--modoption", "dev_raid=1", "--modoption", "dev_raid_team=2",
                   "--modoption", f"dev_raid_waves={waves}",
                   "--modoption", f"dev_raid_from={raid_from}"]
            for k, v in LEVELS[level].items():
                if k.startswith("dev_raid_"):
                    cmd += ["--modoption", f"{k}={v}"]
            if ratio > 0:
                cmd += ["--modoption", f"dev_raid_ratio={ratio}"]
            for kv in modoptions or []:
                cmd += ["--modoption", kv]
            if speed > 0:
                cmd += ["--speed", str(speed)]
            if not turrets:
                cmd += ["--modoption", "apex_def_off=1"]
            log = open(out / f"s{seed}.log", "w")
            live.append((seed, slot, subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT), log))
            print(f"  launched seed {seed}", flush=True)
            time.sleep(3)
        for item in live[:]:
            seed, slot, proc, log = item
            if proc.poll() is not None:
                log.close()
                live.remove(item)
                slots.append(slot)
                print(f"  seed {seed} finished rc={proc.returncode}", flush=True)
        time.sleep(5)


def main():
    global SPEC_A
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("set_dir", nargs="?", help="judge an existing set instead of running one")
    ap.add_argument("--games", type=int, default=8)
    ap.add_argument("--parallel", type=int, default=3)
    ap.add_argument("--minutes", type=int, default=11)
    ap.add_argument("--handicap", type=int, default=50)
    ap.add_argument("--map", default=MAP)
    ap.add_argument("--sides", default="Armada,Armada")
    ap.add_argument("--waves", default=None, help="override the level's wave list")
    ap.add_argument("--level", type=int, default=1, choices=sorted(LEVELS),
                    help="difficulty preset: " + "; ".join(f"{k}: {v['what']}" for k, v in LEVELS.items()))
    ap.add_argument("--from", dest="raid_from", type=float, default=0.6)
    ap.add_argument("--turrets", action="store_true", help="leave apex_def_off unset (control)")
    ap.add_argument("--ratio", type=float, default=2.0,
                    help="size each wave to our mobile army's metal / RATIO (0 = the roster as written)")
    ap.add_argument("--name", default="raid")
    ap.add_argument("--a", dest="spec_a", default=SPEC_A,
                    help="the Apex spec under test (a lane's Apex<name>:lane-<name>:standard for a treated arm)")
    ap.add_argument("--seed0", type=int, default=1, help="first seed; a second set on fresh seeds starts at games+1")
    ap.add_argument("--speed", type=int, default=0,
                    help="sim speed cap (default: as fast as the machine runs). Order lag scales with "
                         "speed: a D-gun aimed at a raider that dies before the order lands is dropped")
    ap.add_argument("--modoption", action="append", default=[], metavar="K=V",
                    help="extra modoption for every game, e.g. apex_intercept=0 for a control arm")
    args = ap.parse_args()
    SPEC_A = args.spec_a
    if args.set_dir:
        out = Path(args.set_dir)
        m = re.search(r"-L(\d+)", out.name)
        if m:
            args.level = int(m.group(1))
    else:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        tag = f"-R{args.ratio:g}" if args.ratio > 0 else ""
        out = ROOT / "tournaments" / f"{stamp}-{args.name}-L{args.level}{tag}"
        print(f"running {args.games} games at level {args.level} ({LEVELS[args.level]['what']}) -> {out}")
        run_set(out, args.games, args.parallel, args.minutes, args.handicap,
                args.map, args.sides, args.turrets, args.waves or LEVELS[args.level]["waves"],
                args.raid_from, args.level, args.ratio, args.modoption, args.seed0, args.speed)
    return 0 if judge(out, args.level) else 1


if __name__ == "__main__":
    raise SystemExit(main())
