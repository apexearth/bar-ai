#!/usr/bin/env python3
"""A/B battery, run in parallel, read as per-player means.

apexearth 2026-09-11: "Your 12 game batteries take too long to run. You should
just run six games all in parallel." One engine per write-dir (docs/26), so
each parallel slot gets matches/_engine_ab<slot>; six 30-minute 2v2s finish in
the wall time of one and a half. 16 logical cores and 96 GB here; the default
of 6 leaves room for a watched game beside it.

    python tools/ab.py --a Apexctl:lane-ctl:standard --b Apexnew:lane-new:standard
    python tools/ab.py --a ... --b ... --maps "Greenest Fields" "Supreme Isthmus v2.1"
    python tools/ab.py --a ... --b ... --seeds 3 --minutes 30 --parallel 6
    python tools/ab.py --report tournaments/<stamp>-ab        # re-read an old set

Both arms play BARb:stable:hard at +100%. Default is a 1v1 on a bigger map
(apexearth 2026-09-12: "for our test games we're just doing 1v1 games on
bigger maps, usually it's a good metric and far faster than the team games");
`--per-side 2 --boxes trbl --box-size 0.45 --maps "Greenest Fields"` is his
watched 2v2. Output: per map, per arm, per-player means of [BARAI_STATS]
metal produced / eco / build power / army / defence at minutes 8/16/24/30, the
opponent's metal, the per-seed spread, and the energy wasted from
[BARAI_WASTE]. A lane must be claimed (or BARAI_LANE=shared named on purpose).

CAVEAT: the AI is time-sliced against the wall clock (memory: canon-eco-game),
so under six-way CPU contention both arms play worse than they would alone and
BARb, which is not sliced, plays the same -- BARb's metal on Greenest Fields
read 91k in a parallel set against ~45k sequential. Read the A-vs-B contrast;
do not compare absolute numbers across parallel and sequential sets.
2026-09-11: the SAME control tree made 838k metal by minute 55 with three
engines on the machine and lost to BARb by minute 30 with seven. Uncapped, the
sim speed is what the CPU allows and the AI's think budget shrinks with it;
`--speed 6` pins the sim so a game costs the same wall time whatever else runs,
and both arms play the AI they would play alone. Use it whenever another
battery shares the machine.
"""
from __future__ import annotations

import argparse
import collections
import glob
import json
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

STAT = re.compile(r"\[BARAI_STATS\] team=(\d+) .*?frame=(\d+) ")
WASTE = re.compile(r"\[BARAI_WASTE\] frame=(\d+) team=(\d+) mWaste=(\d+) mMade=(\d+) eWaste=(\d+) eMade=(\d+)")
KEYS = ["mBuiltReal", "mEco", "mBP", "mArmy", "mDefence"]
MINUTES = (8, 16, 24, 30)


def launch(spec_a: str, spec_b: str, map_name: str, seed: int, minutes: int,
           out: Path, slot: int, handicap: int, speed: int = 0,
           per_side: int = 1, sides: str = "Armada,Armada", boxes: str = "",
           box_size: float = 0.0):
    wdir = ROOT / "matches" / f"_engine_ab{slot}"
    cmd = [sys.executable, "-u", str(HERE / "run_match.py"),
           "--a", spec_a, "--b", spec_b, "--map", map_name,
           "--minutes", str(minutes), "--per-side", str(per_side), "--sides", sides,
           "--handicap", str(handicap),
           "--seed", str(seed), "--out", str(out), "--write-dir", str(wdir),
           "--modoption", "dev_stats=1"]
    if boxes:
        cmd += ["--boxes", boxes, "--box-size", str(box_size)]
    if speed > 0:
        cmd += ["--speed", str(speed)]
    log = open(out.parent / f"{out.name}.log", "w")
    return subprocess.Popen(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT), log


def run_set(setdir: Path, arms: dict[str, str], maps: list[str], seeds: int,
            minutes: int, parallel: int, handicap: int, slot_base: int = 0,
            speed: int = 0, per_side: int = 1, sides: str = "Armada,Armada",
            boxes: str = "", box_size: float = 0.0):
    setdir.mkdir(parents=True, exist_ok=True)
    jobs = [(m, tag, s) for m in maps for s in range(1, seeds + 1) for tag in arms]
    slots = list(range(slot_base, slot_base + parallel))
    live = []
    while jobs or live:
        while jobs and slots:
            m, tag, s = jobs.pop(0)
            slot = slots.pop(0)
            out = setdir / f"{slug(m)}-{tag}-s{s}"
            proc, log = launch(arms[tag], "BARb:stable:hard", m, s, minutes, out, slot,
                               handicap, speed, per_side, sides, boxes, box_size)
            live.append((out.name, slot, proc, log))
            print(f"  launched {out.name} (slot {slot})", flush=True)
            time.sleep(4)
        for item in live[:]:
            name, slot, proc, log = item
            if proc.poll() is not None:
                log.close()
                live.remove(item)
                slots.append(slot)
                print(f"  done {name} rc={proc.returncode}", flush=True)
        time.sleep(5)


def slug(m: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", m.lower())[:10]


def read_run(path: Path):
    hist = collections.defaultdict(dict)
    waste = {}
    log = path / "infolog.txt"
    if not log.exists():
        return hist, waste
    with log.open(encoding="utf8", errors="ignore") as fh:
        for line in fh:
            m = STAT.search(line)
            if m:
                t, f = int(m.group(1)), int(m.group(2))
                d = {}
                for k in KEYS:
                    mm = re.search(rf"\b{k}=(-?[\d.]+)", line)
                    if mm:
                        d[k] = float(mm.group(1))
                hist[f][t] = d
                continue
            m = WASTE.search(line)
            if m:
                waste[int(m.group(2))] = (int(m.group(4)), int(m.group(5)), int(m.group(6)))
    return hist, waste


def report(setdir: Path):
    n_side = 2
    try:
        n_side = int(json.loads((setdir / "arms.json").read_text()).get("per_side", 2))
    except (OSError, ValueError):
        pass
    runs = sorted(p for p in setdir.iterdir() if p.is_dir())
    by = collections.defaultdict(list)   # (mapslug, tag) -> runs
    for r in runs:
        m = re.match(r"([a-z0-9]+)-([A-Za-z0-9]+)-s(\d+)$", r.name)
        if m:
            by[(m.group(1), m.group(2))].append(r)
    maps = sorted({k[0] for k in by})
    for ms in maps:
        print(f"\n== {ms}")
        print(f"{'arm':>5} {'min':>4} " + " ".join(f"{k[1:]:>9}" for k in KEYS)
              + f" {'def%':>6} {'them':>9}   seeds (metal@30)   waste%")
        for tag in sorted({k[1] for k in by if k[0] == ms}):
            acc = collections.defaultdict(lambda: collections.defaultdict(list))
            them = collections.defaultdict(list)
            seeds = []
            w_e = w_w = 0
            for r in by[(ms, tag)]:
                hist, waste = read_run(r)
                for f in hist:
                    mn = round(f / 1800)
                    if mn not in MINUTES:
                        continue
                    for lo, hi, side in ((0, n_side, "us"), (n_side, 2 * n_side, "them")):
                        tot = collections.Counter(); n = 0
                        for t in range(lo, hi):
                            if t in hist[f]:
                                n += 1
                                for k in KEYS:
                                    tot[k] += hist[f][t].get(k, 0.0)
                        if not n:
                            continue
                        if side == "us":
                            for k in KEYS:
                                acc[mn][k].append(tot[k] / n)
                            if mn == 30:
                                seeds.append(int(tot["mBuiltReal"] / n))
                        else:
                            them[mn].append(tot["mBuiltReal"] / n)
                for t in range(n_side):
                    if t in waste:
                        _, ew, em = waste[t]
                        w_w += ew; w_e += em
            for mn in MINUTES:
                v = acc[mn]
                if not v[KEYS[0]]:
                    continue
                mean = {k: sum(v[k]) / len(v[k]) for k in KEYS}
                dp = 100 * mean["mDefence"] / mean["mBuiltReal"] if mean["mBuiltReal"] else 0
                th = sum(them[mn]) / len(them[mn]) if them[mn] else 0
                tail = ""
                if mn == 30:
                    tail = f"   {seeds}   {100 * w_w / w_e if w_e else 0:.1f}%"
                print(f"{tag:>5} {mn:>4} " + " ".join(f"{mean[k]:>9.0f}" for k in KEYS)
                      + f" {dp:>5.1f}% {th:>9.0f}{tail}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--a", help="control AI spec")
    ap.add_argument("--b", help="treated AI spec")
    ap.add_argument("--maps", nargs="+", default=["Comet Catcher Remake", "Supreme Isthmus v2.1"])
    ap.add_argument("--per-side", type=int, default=1,
                    help="apexearth 2026-09-12: test games are 1v1 on bigger maps -- a good "
                         "metric and far faster than the team games (2 for his watched 2v2)")
    ap.add_argument("--sides", default="Armada,Armada")
    ap.add_argument("--boxes", default="", help="e.g. trbl for the 2v2 Greenest setting")
    ap.add_argument("--box-size", type=float, default=0.0)
    ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--minutes", type=int, default=30)
    ap.add_argument("--parallel", type=int, default=6)
    ap.add_argument("--handicap", type=int, default=100)
    ap.add_argument("--speed", type=int, default=0,
                    help="sim speed cap; the AI is sliced against the wall clock, so an uncapped "
                         "sim under load plays a worse AI than the same tree alone (measured: "
                         "control metal 838k alone, 41k beside seven other engines)")
    ap.add_argument("--slot-base", type=int, default=0,
                    help="first _engine_ab<N> write-dir; a second session's battery takes another range")
    ap.add_argument("--name", default="ab")
    ap.add_argument("--report", help="existing set dir to re-read")
    a = ap.parse_args()
    if a.report:
        report(Path(a.report))
        return 0
    if not (a.a and a.b):
        ap.error("--a and --b are required unless --report")
    setdir = ROOT / "tournaments" / f"{time.strftime('%Y%m%d-%H%M%S')}-{a.name}"
    (setdir).mkdir(parents=True, exist_ok=True)
    (setdir / "arms.json").write_text(json.dumps({"A": a.a, "B": a.b, "maps": a.maps,
                                                  "seeds": a.seeds, "minutes": a.minutes,
                                                  "per_side": a.per_side}))
    t0 = time.time()
    run_set(setdir, {"A": a.a, "B": a.b}, a.maps, a.seeds, a.minutes, a.parallel, a.handicap,
            a.slot_base, a.speed, a.per_side, a.sides, a.boxes, a.box_size)
    print(f"\n{setdir}  ({(time.time() - t0) / 60:.1f} min wall)")
    report(setdir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
