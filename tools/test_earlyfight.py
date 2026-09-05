#!/usr/bin/env python3
"""The early-fight test: no turrets, a tight 1v1 map, judged at five minutes.

docs/24-how-units-fight.md: "a good way to gauge how well our fighting is doing
is to not make any turret defenses... gauge our performance in fighting in the
first 5 minutes of the game. Metrics that matter are damage efficiency, units
killed/lost, count of builder interruptions, building damage received/dealt."

Runs a set of short 1v1s against stock BARb hard with `apex_def_off=1`, so
Apex proposes no ground or AA turret and radar plus units are its whole
defence. Stock keeps its turrets. Every metric is read from the combat-log
gadget's [BARAI_DEATH] and [BARAI_DMG] lines at the judge minute AND at the
end of the game, and the set is summarised by medians. There is no absolute
pass mark: a set is judged against a BASELINE set run on the AI before the
change, per metric, and a metric is flagged when its new median falls on the
wrong side of the baseline's own game-to-game spread.

    python tools/test_earlyfight.py                       # run a set, then report
    python tools/test_earlyfight.py --baseline tournaments/<stamp>-earlyfight
    python tools/test_earlyfight.py <set-dir>             # report an existing set
    python tools/test_earlyfight.py --games 8 --parallel 3 --minutes 8
    python tools/test_earlyfight.py --turrets             # control: turrets on

Runs land in tournaments/<stamp>-<name>/. `turrets=` in the per-game table is
Apex's finished static-defence metal from [BARAI_STATS]; it must read 0 when
the switch is on, and a non-zero value means the modoption never reached the
game (the gadget list, not the AI, publishes it -- CLAUDE.md).
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

SPEC_A = "Apex:Unstable:standard"
SPEC_B = "BARb:stable:hard"
MAP = "Geyser Plains BAR v1.2.1"
FPS = 30

START_RE = re.compile(r"\[BARAI_START\] team=(\d+) x=(-?\d+) z=(-?\d+)")
DEATH_RE = re.compile(r"\[BARAI_DEATH\] (.*)")
DMG_RE = re.compile(r"\[BARAI_DMG\] (.*)")
STATS_RE = re.compile(r"\[BARAI_STATS\] (.*)")
SPREAD_RE = re.compile(r"apex: engage \w+ units=(\d+) spread=(\d+)")
AI_BLOCK_RE = re.compile(r"\[AI\d+\]\s*\{(.*?)\}", re.S)

# metric -> (label, higher_is_better)
METRICS = {
    "eff": ("damage dealt / received", True),
    "effMob": ("mobile damage dealt / received", True),
    "kd": ("metal killed / lost", True),
    "kdMob": ("mobile metal killed / lost", True),
    "killedN": ("enemy units killed", True),
    "lostN": ("our units lost", False),
    "killM": ("enemy metal killed", True),
    "lostM": ("our metal lost", False),
    "bldDealt": ("damage dealt to buildings", True),
    "bldRecv": ("damage received on buildings", False),
    "interrupts": ("constructor interruptions", False),
    "interruptsBusy": ("interruptions while building", False),
    "conDeaths": ("constructors lost", False),
    "spread": ("squad spread at engage, elmo", False),
}
CORE = ("eff", "kd", "bldDealt", "bldRecv", "interrupts")


def kv(s: str) -> dict:
    out = {}
    for tok in s.split():
        k, _, v = tok.partition("=")
        out[k] = v
    return out


def apex_teams(match_dir: Path) -> set[int]:
    """Game team ids Apex played, from the start script -- result.json's
    teams[].team is the spec index, not a game team (CLAUDE.md)."""
    p = match_dir / "script.txt"
    if not p.exists():
        return set()
    out = set()
    for block in AI_BLOCK_RE.findall(p.read_text("utf-8", errors="replace")):
        m_name = re.search(r"ShortName\s*=\s*(\w+)", block)
        m_team = re.search(r"Team\s*=\s*(\d+)", block)
        if m_name and m_team and m_name.group(1) == "Apex":
            out.add(int(m_team.group(1)))
    return out


def gadget_text(match_dir: Path) -> str:
    """The engine's stdout, or the infolog when a run kept only that. Never
    both: Spring.Echo lands in each, so reading the pair double-counts every
    death and every wave."""
    for name in ("stdout.txt", "infolog.txt"):
        p = match_dir / name
        if p.exists():
            return p.read_text("utf-8", errors="replace")
    return ""


def read_logs(match_dir: Path):
    text = gadget_text(match_dir)
    # The `apex: engage` spread samples are AiLog lines, in the infolog only.
    info = match_dir / "infolog.txt"
    if info.exists() and (match_dir / "stdout.txt").exists():
        text += "\n" + "\n".join(l for l in info.read_text("utf-8", errors="replace").splitlines()
                                  if "apex: engage" in l)
    teams, deaths, dmg, stats, spreads = set(), [], [], [], []
    for line in text.splitlines():
        m = START_RE.search(line)
        if m:
            teams.add(int(m.group(1)))
            continue
        m = DEATH_RE.search(line)
        if m:
            d = kv(m.group(1))
            try:
                deaths.append((int(d["frame"]), int(d["team"]), float(d["cost"]),
                               d["built"] == "1", d["mob"] == "1"))
            except (KeyError, ValueError):
                pass
            continue
        m = DMG_RE.search(line)
        if m:
            d = kv(m.group(1))
            try:
                dmg.append((int(d["frame"]), int(d["team"]),
                            {k: float(v) for k, v in d.items() if k not in ("frame", "team")}))
            except (KeyError, ValueError):
                pass
            continue
        m = STATS_RE.search(line)
        if m:
            d = kv(m.group(1))
            try:
                stats.append((int(d.get("frame", 0)), int(d["team"]), d))
            except (KeyError, ValueError):
                pass
            continue
        m = SPREAD_RE.search(line)
        if m:
            spreads.append((int(m.group(1)), int(m.group(2))))
    return teams, deaths, dmg, stats, spreads


def window(match_dir: Path, until_frame: int | None):
    """One row of metrics for Apex's side, counting everything up to
    until_frame (None = whole game)."""
    us = apex_teams(match_dir)
    teams, deaths, dmg, stats, spreads = read_logs(match_dir)
    them = teams - us
    if not us or not them:
        return None
    lim = until_frame if until_frame is not None else 10 ** 9

    lost_m = lost_mob = kill_m = kill_mob = 0.0
    lost_n = kill_n = 0
    for frame, team, cost, built, mob in deaths:
        if frame > lim or not built:
            continue
        if team in us:
            lost_m += cost
            lost_n += 1
            if mob:
                lost_mob += cost
        elif team in them:
            kill_m += cost
            kill_n += 1
            if mob:
                kill_mob += cost

    # The DMG line is cumulative; keep the latest one per Apex team and sum teams.
    latest = {}
    for frame, team, d in dmg:
        if frame <= lim and team in us:
            latest[team] = d
    tot = {}
    for d in latest.values():
        for k, v in d.items():
            tot[k] = tot.get(k, 0.0) + v

    turrets = 0.0
    for frame, team, d in stats:
        if frame <= lim and team in us:
            try:
                turrets = float(d.get("mDefence", 0)) + float(d.get("mDefAA", 0))
            except ValueError:
                pass

    def ratio(a, b):
        # 0/0 is "nothing happened", not parity; a None stays out of the medians
        return a / b if b > 0 else None

    dealt = tot.get("dm", 0) + tot.get("ds", 0)
    recv = tot.get("rm", 0) + tot.get("rs", 0)
    row = {
        "eff": ratio(dealt, recv),
        "effMob": ratio(tot.get("dm", 0), tot.get("rm", 0)),
        "kd": ratio(kill_m, lost_m),
        "kdMob": ratio(kill_mob, lost_mob),
        "killedN": kill_n,
        "lostN": lost_n,
        "killM": kill_m,
        "lostM": lost_m,
        "bldDealt": tot.get("ds", 0),
        "bldRecv": tot.get("rs", 0),
        "recvFromStatic": tot.get("rfs", 0),
        "interrupts": tot.get("bi", 0),
        "interruptsBusy": tot.get("bib", 0),
        "conDeaths": tot.get("bd", 0),
        "spread": statistics.mean(s for _n, s in spreads) if spreads else 0.0,
        "engages": len(spreads),
        "turrets": turrets,
        "dealt": dealt,
        "recv": recv,
    }
    return row


def outcome(match_dir: Path):
    p = match_dir / "result.json"
    if not p.exists():
        return None, None
    try:
        r = json.loads(p.read_text("utf-8"))
    except (OSError, ValueError):
        return None, None
    res = r.get("result", {})
    specs = res.get("winner_specs") or []
    won = any(s.startswith("Apex") for s in specs) if specs else None
    return won, res.get("game_minutes")


def run_set(out: Path, games: int, parallel: int, minutes: int, handicap: int,
            map_name: str, sides: str, turrets: bool):
    out.mkdir(parents=True, exist_ok=True)
    (out / "matches").mkdir(exist_ok=True)
    pending = list(range(1, games + 1))
    live = []
    slots = list(range(parallel))
    while pending or live:
        while pending and slots:
            seed = pending.pop(0)
            slot = slots.pop(0)
            mdir = out / "matches" / f"s{seed}"
            wdir = ROOT / "matches" / f"_engine_ef{slot}"
            cmd = [sys.executable, "-u", str(HERE / "run_match.py"),
                   "--a", SPEC_A, "--b", SPEC_B, "--map", map_name,
                   "--minutes", str(minutes), "--seed", str(seed),
                   "--sides", sides, "--handicap", str(handicap),
                   "--out", str(mdir), "--write-dir", str(wdir)]
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


def fmt(v):
    if v is None:
        return "-"
    return f"{v:.2f}" if isinstance(v, float) and abs(v) < 100 else f"{v:.0f}"


def median(vals):
    vals = [v for v in vals if v is not None]
    return statistics.median(vals) if vals else None


def report(out: Path, judge_min: int, baseline: Path | None):
    dirs = sorted(p for p in (out / "matches").iterdir() if (p / "result.json").exists())
    lim = judge_min * 60 * FPS
    rows = {"at": [], "end": []}
    print(f"== {out.name}: {len(dirs)} games, judged at {judge_min} min ==")
    cols = ["eff", "kd", "killM", "lostM", "bldDealt", "bldRecv", "interrupts",
            "interruptsBusy", "conDeaths", "spread", "turrets"]
    print("  game   " + " ".join(f"{c:>9}" for c in cols) + "   outcome")
    for d in dirs:
        at = window(d, lim)
        end = window(d, None)
        if at is None or end is None:
            print(f"  {d.name:<6} (no combat log -- gadget not installed, or the AI never loaded)")
            continue
        won, mins = outcome(d)
        how = "won" if won else ("lost" if won is False else "timelimit")
        rows["at"].append(at)
        rows["end"].append(end)
        print(f"  {d.name:<6} " + " ".join(f"{fmt(at[c]):>9}" for c in cols)
              + f"   {how} at {mins}m")
        print(f"  {'(end)':<6} " + " ".join(f"{fmt(end[c]):>9}" for c in cols))

    if not rows["at"]:
        print("nothing to judge")
        return False

    med = {}
    for when in ("at", "end"):
        med[when] = {}
        for k in METRICS:
            med[when][k] = median(r[k] for r in rows[when])
    print(f"\n== MEDIANS (n={len(rows['at'])}) ==")
    print(f"  {'metric':<32} {'@' + str(judge_min) + 'm':>9} {'end':>9}")
    for k, (label, _hib) in METRICS.items():
        print(f"  {label:<32} {fmt(med['at'][k]):>9} {fmt(med['end'][k]):>9}")
    bad_turrets = [r["turrets"] for r in rows["end"] if r["turrets"] > 0]
    if bad_turrets:
        print(f"\n  WARNING: Apex finished static defence in {len(bad_turrets)} game(s) -- "
              "either --turrets was set, or apex_def_off never reached the game "
              "(check dev_tunables.lua is deployed: deploy_ai.py gadgets)")

    summary = {"games": len(rows["at"]), "judge_min": judge_min,
               "rows_at": rows["at"], "rows_end": rows["end"], "medians": med}
    (out / "earlyfight_summary.json").write_text(json.dumps(summary, indent=2))

    ok = True
    if baseline is not None:
        bp = baseline / "earlyfight_summary.json"
        if not bp.exists():
            print(f"\nbaseline {baseline} has no earlyfight_summary.json -- run it with this tool first")
            return False
        base = json.loads(bp.read_text("utf-8"))
        print(f"\n== AGAINST BASELINE {baseline.name} (n={base['games']}) at {judge_min} min ==")
        print("  a metric is flagged when the new median lands past the baseline's own\n"
              "  game-to-game quartile on the bad side; n is small, so read it as a\n"
              "  pointer to look at, not a verdict")
        for k in CORE:
            label, hib = METRICS[k]
            bvals = sorted(r[k] for r in base["rows_at"] if r[k] is not None)
            new = med["at"][k]
            if len(bvals) < 4 or new is None:
                print(f"  {label:<32} not enough games with data")
                continue
            q1 = bvals[len(bvals) // 4]
            q3 = bvals[(3 * len(bvals)) // 4]
            bmed = base["medians"]["at"][k]
            worse = (new < q1) if hib else (new > q3)
            better = (new > q3) if hib else (new < q1)
            tag = "WORSE " if worse else ("better" if better else "same  ")
            ok &= not worse
            print(f"  {tag} {label:<32} {fmt(bmed):>9} -> {fmt(new):>9}   (baseline q1..q3 {fmt(q1)}..{fmt(q3)})")
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("set_dir", nargs="?", help="report an existing set instead of running one")
    ap.add_argument("--games", type=int, default=8)
    ap.add_argument("--parallel", type=int, default=3)
    ap.add_argument("--minutes", type=int, default=8)
    ap.add_argument("--judge-min", dest="judge_min", type=int, default=5)
    ap.add_argument("--handicap", type=int, default=50)
    ap.add_argument("--map", default=MAP)
    ap.add_argument("--sides", default="Armada,Armada")
    ap.add_argument("--turrets", action="store_true", help="leave apex_def_off unset (control)")
    ap.add_argument("--baseline", help="set dir to judge against")
    ap.add_argument("--name", default="earlyfight")
    args = ap.parse_args()

    if args.set_dir:
        out = Path(args.set_dir)
    else:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        out = ROOT / "tournaments" / f"{stamp}-{args.name}"
        print(f"running {args.games} games -> {out}")
        run_set(out, args.games, args.parallel, args.minutes, args.handicap,
                args.map, args.sides, args.turrets)
    ok = report(out, args.judge_min, Path(args.baseline) if args.baseline else None)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
