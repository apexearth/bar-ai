"""Energy and metal, minute by minute, averaged over the games of a run.

    python tools/ecotimeline.py <tournament dir|substring|match dir> [--minutes N]

Two sources, both already in every infolog:
  * ``apex: energy`` -- our AI's own ledger every 30 s (bank, income, pull).
  * ``[BARAI_STATS]`` -- the stats gadget, every 2 min, for EVERY team, with the
    cumulative stall counter (``eStall``/``resSamp``) that gives a per-bin
    stalled share.

One row per minute per (map, spec): bank fill, income, pull and the stalled
share of samples in the bin ending at that minute. A bank pinned near zero with
pull over income IS the e-stall apexearth watches for; a bank pinned full is
wasted generation. Read the whole curve, not one minute of it.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from statistics import mean

REPO = Path(__file__).resolve().parent.parent
ENERGY = re.compile(r"\[f=(\d+)\] Skirmish AI <[^>]*>: \[[\d.]+m t(\d+)\] apex: energy "
                    r"cur=(-?\d+)/(\d+) inc=(-?\d+) pull=(-?\d+)")
STATS = re.compile(r"\[f=(\d+)\] \[BARAI_STATS\] (.*)")
DUTY = re.compile(r"\[f=(\d+)\] \[BARAI_DUTY\] (.*)")


def find_runs(key: str) -> list[Path]:
    p = Path(key)
    if p.is_dir():
        if (p / "infolog.txt").exists():
            return [p]
        return sorted(d for d in p.rglob("infolog.txt"))
    hits = sorted(d for d in (REPO / "tournaments").glob(f"*{key}*") if d.is_dir())
    if hits:
        return sorted(hits[-1].rglob("infolog.txt"))
    hits = sorted(d for d in (REPO / "matches").glob(f"*{key}*") if d.is_dir())
    return [h / "infolog.txt" for h in hits if (h / "infolog.txt").exists()]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run")
    ap.add_argument("--minutes", type=int, default=15)
    ap.add_argument("--poor", type=float, default=400.0,
                    help="energy income below which a stall counts as the real failure")
    args = ap.parse_args()
    bands: dict[tuple, list[float]] = defaultdict(lambda: [0.0, 0.0])
    logs = find_runs(args.run)
    logs = [l if l.name == "infolog.txt" else l / "infolog.txt" for l in logs]
    logs = [l for l in logs if l.exists()]
    if not logs:
        print("no infolog found for", args.run)
        return 1
    # (map, spec, minute) -> metric -> [values over games]
    acc: dict[tuple, dict[str, list[float]]] = defaultdict(lambda: defaultdict(list))
    games = 0
    duty: dict[tuple, tuple[float, float, float]] = {}
    for log in logs:
        res = log.parent / "result.json"
        if not res.exists():
            continue
        r = json.loads(res.read_text(encoding="utf-8"))
        specs = {t["team"]: t["spec"] for t in r["teams"]}
        mapname = r.get("map", "?")
        games += 1
        prev: dict[int, tuple[float, float]] = {}
        for ln in log.read_text(encoding="utf-8", errors="replace").splitlines():
            m = ENERGY.search(ln)
            if m:
                frame, team = int(m.group(1)), int(m.group(2))
                minute = round(frame / 1800.0, 1)
                if minute != int(minute) or minute < 1 or minute > args.minutes:
                    continue
                cur, store, inc, pull = (float(m.group(i)) for i in (3, 4, 5, 6))
                a = acc[(mapname, specs.get(team, f"t{team}"), int(minute))]
                a["bank%"].append(100.0 * cur / store if store > 0 else 0.0)
                a["eInc"].append(inc)
                a["ePull"].append(pull)
                continue
            m = DUTY.search(ln)
            if m:
                # Cumulative per team; the last line of the game is the total.
                kv = dict(p.split("=", 1) for p in m.group(2).split(" ") if "=" in p)
                t = int(kv.get("team", -1))
                duty[(mapname, specs.get(t, f"t{t}"), log)] = (
                    float(kv.get("conSamp", 0)), float(kv.get("conIdle", 0)),
                    float(kv.get("conGuardFin", 0)))
                continue
            m = STATS.search(ln)
            if not m:
                continue
            frame = int(m.group(1))
            kv = dict(p.split("=", 1) for p in m.group(2).split(" ") if "=" in p)
            minute = frame / 1800.0
            if abs(minute - round(minute)) > 0.02 or round(minute) > args.minutes:
                continue
            team = int(kv["team"])
            spec = specs.get(team, f"t{team}")
            a = acc[(mapname, spec, int(round(minute)))]
            es, samp = float(kv.get("eStall", 0)), float(kv.get("resSamp", 0))
            pes, psamp = prev.get(team, (0.0, 0.0))
            if samp > psamp:
                a["stall%"].append(100.0 * (es - pes) / (samp - psamp))
                # A stall on a small energy income is the failure he watches
                # for; a stall at 2k e/s is the fleet asking for more than
                # income can feed. Split by the bin's income (apexearth).
                band = "poor" if float(kv.get("eInc", 0)) < args.poor else "rich"
                bands[(mapname, spec, band)][0] += es - pes
                bands[(mapname, spec, band)][1] += samp - psamp
            prev[team] = (es, samp)
            est = float(kv.get("eStore", 0))
            if est > 0:
                a["gBank%"].append(100.0 * float(kv.get("eNow", 0)) / est)
            a["gEInc"].append(float(kv.get("eInc", 0)))
            a["gEPull"].append(float(kv.get("ePull", 0)))
            for k in ("eAskFac", "eAskCon", "eAskNano", "eUseOther"):
                if k in kv:
                    a[k[1:]].append(float(kv[k]))
            mst = float(kv.get("mStore", 0))
            if mst > 0:
                a["mBank%"].append(100.0 * float(kv.get("mNow", 0)) / mst)
            a["mInc"].append(float(kv.get("mInc", 0)))
            a["mProd"].append(float(kv.get("metalProduced", 0)))
    print(f"games={games}  (bank/inc/pull from the AI's 30 s ledger where it logs one; "
          f"g* columns from the 2-minute stats gadget, every team)")
    cols = ["bank%", "eInc", "ePull", "gBank%", "gEInc", "gEPull", "AskFac", "AskCon", "AskNano",
            "UseOther", "stall%", "mBank%", "mInc", "mProd"]
    keys = sorted({(m_, s) for (m_, s, _) in acc})
    for mapname, spec in keys:
        print(f"\n== {mapname}  {spec}")
        print(f"{'min':>4}" + "".join(f"{c:>8}" for c in cols))
        for minute in range(1, args.minutes + 1):
            a = acc.get((mapname, spec, minute))
            if not a:
                continue
            row = f"{minute:>4}"
            for c in cols:
                v = a.get(c)
                row += f"{mean(v):>8.0f}" if v else f"{'':>8}"
            print(row)
        parts = []
        for band, label in (("poor", f"eInc<{args.poor:.0f}"), ("rich", f"eInc>={args.poor:.0f}")):
            st, n = bands.get((mapname, spec, band), [0.0, 0.0])
            parts.append(f"{label}: {100.0 * st / n:.0f}% of {n:.0f} samples" if n > 0
                         else f"{label}: no samples")
        print("   stalled while " + "  |  ".join(parts))
        # Mobile constructors with nothing to do, or guarding a finished
        # building (apexearth 2026-09-08: cons parked on a completed afus).
        cs = ci = cg = 0.0
        for (m_, s_, _), (a1, a2, a3) in duty.items():
            if (m_, s_) == (mapname, spec):
                cs, ci, cg = cs + a1, ci + a2, cg + a3
        if cs > 0:
            print(f"   constructor samples idle {100.0 * ci / cs:.1f}%, "
                  f"guarding a finished building {100.0 * cg / cs:.1f}%  (n={cs:.0f})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
