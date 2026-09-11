#!/usr/bin/env python3
"""The reactor-order test: no advanced fusion before a fusion on a conversion map.

apexearth, raised on 2026-09-08, 2026-09-09 and three times on 2026-09-10:
"we make an AFUS before trying to make a fusion... it doesn't end well pretty
much every time." "There should be no contest between these two items. Unless
you have enough metal that the AFUS doesn't take so long to build, it's pretty
much never worth going for." Fixed twice by adding a term, and twice it came
back, because it was verified on Supreme Isthmus and he watches Greenest
Fields -- a no-mex map where the economy is energy conversion, which is where
the AFUS's 69,000 E bill and 312,500 build time hurt most.

Runs Greenest Fields 2v2 against BARb hard, reads every reactor election and
every reactor finished from the log, and FAILS if either of our players elects
or finishes an advanced fusion before its first fusion. Also prints the
`apex: epick` reactor lines, which are the simulator's own reasoning, so a
failure says WHY.

    python tools/test_reactor_order.py                 # 2 games, 30 min
    python tools/test_reactor_order.py --games 3 --minutes 35
    python tools/test_reactor_order.py --ai Apexfoo:lane-foo:standard
    python tools/test_reactor_order.py <run-dir> ...   # judge existing runs

Runs land in matches/reactor-<stamp>-s<seed>/. Read `python tools/lane.py
status` first: a session with no lane must name BARAI_LANE=shared on purpose.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

AFUS = ("armafus", "corafus", "legafus")
FUS = ("armfus", "corfus", "legfus", "armckfus", "corckfus")

DECIDE = re.compile(r"\[f=0*(\d+)\].*apex: decide t=(\d+) \S+ #\d+ -> energy/energy:(\w+) ")
EPICK = re.compile(r"\[f=0*(\d+)\].*apex: epick t=(\d+) \S+ (mkt=\S+ v=\S+ eta=\S+ s=\S+ mktS=\S+)")
STATS = re.compile(r"\[BARAI_STATS\] team=(\d+) .*?frame=(\d+) .*?unitCount=(\S+)")


def judge(run: Path, our_teams: set[int]) -> tuple[bool, list[str]]:
    log = run / "infolog.txt"
    if not log.exists():
        return False, [f"{run.name}: no infolog"]
    first_fus: dict[int, int] = {}
    first_afus: dict[int, int] = {}
    first_fus_done: dict[int, int] = {}
    first_afus_done: dict[int, int] = {}
    epicks: list[str] = []
    with log.open(encoding="utf8", errors="ignore") as fh:
        for line in fh:
            m = DECIDE.search(line)
            if m:
                f, t, d = int(m.group(1)), int(m.group(2)), m.group(3)
                if t not in our_teams:
                    continue
                if d in AFUS:
                    first_afus.setdefault(t, f)
                elif d in FUS:
                    first_fus.setdefault(t, f)
                continue
            m = EPICK.search(line)
            if m and int(m.group(2)) in our_teams and "fus" in m.group(3):
                epicks.append(f"  {int(m.group(1)) / 1800:5.1f}m t{m.group(2)} {m.group(3)}")
                continue
            m = STATS.search(line)
            if m and int(m.group(1)) in our_teams:
                t, f = int(m.group(1)), int(m.group(2))
                for part in m.group(3).split(","):
                    if ":" not in part:
                        continue
                    name, n = part.rsplit(":", 1)
                    if name in AFUS and n != "0":
                        first_afus_done.setdefault(t, f)
                    elif name in FUS and n != "0":
                        first_fus_done.setdefault(t, f)
    ok = True
    out = [f"{run.name}"]
    for t in sorted(our_teams):
        fe, ae = first_fus.get(t), first_afus.get(t)
        fd, ad = first_fus_done.get(t), first_afus_done.get(t)
        fmt = lambda f: "-" if f is None else f"{f / 1800:.1f}m"
        bad = (ae is not None and (fe is None or ae < fe)) or (ad is not None and (fd is None or ad < fd))
        ok &= not bad
        out.append(f"  t{t}: fusion elected {fmt(fe)} finished {fmt(fd)} | AFUS elected {fmt(ae)} finished {fmt(ad)}"
                   + ("   <<< AFUS FIRST" if bad else ""))
    if epicks:
        out.append("  simulator's reactor picks (mkt = old price, eta = ladder):")
        out.extend(epicks[:12])
        if len(epicks) > 12:
            out.append(f"  ... {len(epicks) - 12} more")
    return ok, out


def run_one(ai: str, seed: int, minutes: int, out: Path) -> Path:
    cmd = [sys.executable, "-u", str(HERE / "run_match.py"),
           "--a", ai, "--b", "BARb:stable:hard", "--map", "Greenest Fields",
           "--minutes", str(minutes), "--per-side", "2", "--sides", "Armada,Armada",
           "--boxes", "trbl", "--box-size", "0.45", "--handicap", "100",
           "--seed", str(seed), "--out", str(out), "--modoption", "dev_stats=1"]
    subprocess.run(cmd, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("runs", nargs="*", help="existing run dirs to judge instead of playing")
    ap.add_argument("--ai", default="Apex:Unstable:standard")
    ap.add_argument("--games", type=int, default=2)
    ap.add_argument("--minutes", type=int, default=30)
    a = ap.parse_args()
    runs = [Path(r) for r in a.runs]
    if not runs:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        for s in range(1, a.games + 1):
            out = ROOT / "matches" / f"reactor-{stamp}-s{s}"
            print(f"playing seed {s} -> {out.name}", flush=True)
            runs.append(run_one(a.ai, s, a.minutes, out))
    all_ok = True
    for r in runs:
        ok, lines = judge(r, {0, 1})
        all_ok &= ok
        print("\n".join(lines))
    print("\nPASS: fusion before advanced fusion in every game" if all_ok
          else "\nFAIL: an advanced fusion was elected or finished before a fusion")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
