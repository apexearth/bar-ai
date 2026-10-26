#!/usr/bin/env python3
"""The economy test: how fast do we eco up, against his own reference game.

    python tools/ecotest.py                         # lane c9, 20 min, seed 1
    python tools/ecotest.py --lane watch --minutes 16
    python tools/ecotest.py --ai-option apex_lab_rate=1 --out matches/eco/lab-rate
    python tools/ecotest.py --read matches/eco/canon20b   # re-read a finished run

His reference (memory canon-eco-game, from his 2026-09-08 demo): 1v1 vs NullAI on Comet Catcher Remake 1.8,
+50% for him. The test runs at +0 by default (his 10-20: "i want to do +0 here"; --bonus 50 to match it),
no defence needed. NullAI plays at 0, apex_eco_only=1 (labs make
constructors only, no towers, sensors or super weapons), deathmode=neverend so killing NullAI's commander does
not end it, --speed 5 (trap S24: eco runs go capped). Prints per two minutes our metal and energy income,
extractors, mohos, nano turrets, factories and constructors beside his curve, and how long the metal bank sat
full (metal nobody could spend).
"""
import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# His reference, read from the demo (canon-eco-game): metal income m/s by minute, energy e/s, and the census.
REF_M = {5: 65, 7: 133, 8: 244, 10: 352, 12: 529, 14: 900, 16: 1570}
REF_E = {10: 4800, 14: 30000}
REF_CENSUS = {4: "15 mex, 7 nano", 5: "21 mex, 10 nano", 7: "32 mex, 3 moho, 16 nano", 8: "38 mex, 6 moho",
              10: "15 moho, 62 nano", 12: "22 moho, 119 nano", 14: "28 moho, 265 nano", 16: "31+ moho, 325 nano"}

STATS = re.compile(r"BARAI_STATS\] team=(\d+) .*?frame=(\d+) .*?mexN=(\d+)")
FIELD = re.compile(r"\b(mInc|eInc|mNow|mStore)=([-0-9.]+)")
BUILD = re.compile(r"BARAI_BUILD\] team=(\d+) .*?frame=(\d+) .*?unit=([a-z0-9_]+) ")
PROD = re.compile(r"\[f=0*(\d+)\].*apex: decide t=(\d+) \w+ #\d+ -> produce:([a-z0-9_]+)")
CON = re.compile(r"(ck|cv|ca|cs|ch|ack|acv|aca)$")
LAB = re.compile(r"(lab|vp|hp|ap|sy|alab|avp|aap|asy|gant|shltx|fhp|amsub|plat)$")


def run(args) -> Path:
    out = REPO / (args.out or f"matches/eco/ecotest-{args.lane}-s{args.seed}")
    spec = args.spec or f"Apex{args.lane}:lane-{args.lane}:standard"
    cmd = [sys.executable, str(REPO / "tools" / "run_match.py"), "--a", spec, "--b", "NullAI:0.1",
           "--map", "Comet Catcher Remake 1.8", "--minutes", str(args.minutes), "--handicap", f"{args.bonus},0",
           "--speed", str(args.speed), "--seed", str(args.seed), "--modoption", "dev_stats=1",
           "--modoption", "apex_eco_only=1", "--modoption", "deathmode=neverend", "--out", str(out)]
    for kv in args.modoption or []:
        cmd += ["--modoption", kv]
    for kv in args.ai_option or []:
        cmd += ["--ai-option", kv]
    env = dict(os.environ)
    env.setdefault("BARAI_LANE", args.lane)
    print("running:", " ".join(cmd[2:]))
    subprocess.run(cmd, env=env, check=False, stdout=subprocess.DEVNULL)
    return out


def read(out: Path) -> None:
    log = out / "infolog.txt"
    if not log.exists():
        sys.exit(f"no infolog in {out}")
    stats, builds, prods = {}, [], []
    full_s, samples = 0, 0
    for line in log.open(encoding="utf-8", errors="replace"):
        m = STATS.search(line)
        if m and m.group(1) == "0":
            f = dict((k, float(v)) for k, v in FIELD.findall(line))
            stats[int(m.group(2)) // 1800] = (f.get("mInc", 0.0), f.get("eInc", 0.0), int(m.group(3)))
            if f.get("mStore", 0.0) > 0:
                samples += 1
                full_s += 1 if f.get("mNow", 0.0) >= 0.95 * f["mStore"] else 0
            continue
        m = BUILD.search(line)
        if m and m.group(1) == "0":
            builds.append((int(m.group(2)) / 1800.0, m.group(3)))
            continue
        m = PROD.search(line)
        if m and m.group(2) == "0":
            prods.append((int(m.group(1)) / 1800.0, m.group(3)))

    def upto(mn, rows, pred):
        return sum(1 for t, u in rows if t < mn and pred(u))

    print(f"\n{out}")
    print(" min |  metal m/s (his) | energy e/s (his) | mex moho nano labs cons army | his census")
    for mn in range(2, 21, 2):
        if mn not in stats:
            continue
        mi, ei, mx = stats[mn]
        rm = REF_M.get(mn) or REF_M.get(mn - 1)
        re_ = REF_E.get(mn)
        moho = upto(mn, builds, lambda u: "moho" in u)
        nano = upto(mn, builds, lambda u: "nanotc" in u)
        labs = upto(mn, builds, lambda u: bool(LAB.search(u)))
        cons = upto(mn, prods, lambda u: bool(CON.search(u)))
        army = upto(mn, prods, lambda u: not CON.search(u))
        cen = REF_CENSUS.get(mn) or REF_CENSUS.get(mn - 1) or ""
        print(f" {mn:3d} | {mi:6.0f} ({rm if rm else '-':>5}) | {ei:6.0f} ({re_ if re_ else '-':>6}) |"
              f" {mx:3d} {moho:4d} {nano:4d} {labs:4d} {cons:4d} {army:4d} | {cen}")
    if samples:
        print(f" metal bank full (>=95%) in {100 * full_s // samples}% of the stats samples")
    print(" (mohos, nanos and labs are counted as built; cons and army as ordered)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lane", default="c9")
    ap.add_argument("--spec", help="AI spec instead of the lane's, e.g. Apex:v0.3.3:standard")
    ap.add_argument("--minutes", type=int, default=20)
    ap.add_argument("--bonus", type=int, default=0, help="our resource bonus %%; his reference game was +50 (default 0, his 10-20)")
    ap.add_argument("--speed", type=float, default=5)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--ai-option", action="append")
    ap.add_argument("--modoption", action="append", help="game option k=v, e.g. experimentalextraunits=1 (his scavenger pack)")
    ap.add_argument("--out")
    ap.add_argument("--read", help="re-read a finished run instead of playing one")
    args = ap.parse_args()
    read(Path(args.read) if args.read else run(args))


if __name__ == "__main__":
    main()
