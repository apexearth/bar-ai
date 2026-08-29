#!/usr/bin/env python3
"""Score the mirrored equal-army fights produced by dev_arena.lua.

Both sides get the same units at mirrored positions, so army size, economy and
build order are all held constant and the only thing left varying is what each
AI does with the units. That makes this the one measurement in this repo that
isolates fighting logic.

Reported per run:

  ROUNDS WON      how many rounds each side wiped the other. The headline.
  SURVIVOR EDGE   mean (ourSurvivors - theirSurvivors) per round, in units. More
                  sensitive than wins: a 6-0 and a 1-0 are both one win, but a
                  side that consistently walks away with five extra units is
                  winning fights it would also win at other army sizes.
  DRAWS           rounds that hit the frame cap with both sides alive. A high
                  draw rate means the AIs never engaged and the run says nothing
                  about fighting -- check this BEFORE reading anything else.
  BY FLIP         the same numbers split by which spawn each side used. The two
                  halves should agree; if they do not, the result is terrain,
                  not tactics.

Usage:
    python tools/arena.py <match-dir> [more dirs...]
    python tools/arena.py matches/*arena*        # aggregates across runs
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

END_RE = re.compile(r"\[BARAI_ARENA_END\] (.*)")
INIT_RE = re.compile(r"\[BARAI_ARENA\] init (.*)")
ERR_RE = re.compile(r"\[BARAI_ARENA\] ERROR (.*)")


def parse(path: Path):
    text = path.read_text("utf-8", errors="replace")
    rounds, dirty = [], []
    for m in END_RE.finditer(text):
        d = {}
        for tok in m.group(1).split():
            k, _, v = tok.partition("=")
            try:
                d[k] = float(v)
            except ValueError:
                d[k] = v
        # clean=0 marks a round decided partly by units outside the two spawned
        # sets -- the surrounding match walking in. Older logs have no clean
        # field; treat those as clean so they still parse, but they are not
        # comparable with rounds recorded after the check existed.
        if d.get("clean", 1.0) != 0.0:
            rounds.append(d)
        else:
            dirty.append(d)
    init = INIT_RE.search(text)
    errs = [m.group(1) for m in ERR_RE.finditer(text)]
    as_err = len(re.findall(r"\.as \(\d+, \d+\) : ERR", text))
    return rounds, (init.group(1) if init else None), errs, as_err, dirty


def infologs(root: Path):
    if (root / "infolog.txt").exists():
        return [root / "infolog.txt"]
    return sorted(root.rglob("infolog.txt"))


def medge(r):
    """Survival-fraction edge: fair for mixed and asymmetric rosters.
    Falls back to the unit-count edge for logs without spawnM fields."""
    if r.get("spawnM0", 0) and r.get("spawnM1", 0):
        return r["metal0"] / r["spawnM0"] - r["metal1"] / r["spawnM1"]
    return r["alive0"] - r["alive1"]


def report(rounds, label):
    if not rounds:
        print(f"  {label}: no rounds")
        return
    n = len(rounds)
    w0 = sum(1 for r in rounds if r["winner"] == 0)
    w1 = sum(1 for r in rounds if r["winner"] == 1)
    draw = n - w0 - w1
    edge = sum(medge(r) for r in rounds) / n
    frames = sum(r["frames"] for r in rounds) / n
    frac = any(r.get("spawnM0") for r in rounds)
    unit = "frac" if frac else "units"
    reasons = {}
    for r in rounds:
        k = r.get("reason", "?")
        reasons[k] = reasons.get(k, 0) + 1
    rs = " ".join(f"{k}={v}" for k, v in sorted(reasons.items()))
    print(f"  {label:14} rounds={n:3d}  us={w0:3d} them={w1:3d} draw={draw:3d}"
          f"   edge={edge:+6.3f} {unit}   mean {frames / 30:5.1f}s  [{rs}]")


def edge(rounds):
    return (sum(r["alive0"] - r["alive1"] for r in rounds) / len(rounds)) if rounds else 0.0


def wins(rounds):
    return (sum(1 for r in rounds if r["winner"] == 0),
            sum(1 for r in rounds if r["winner"] == 1))


def pair_mode(fwd_dir: str, rev_dir: str) -> int:
    """Slot-bias-cancelled comparison.

    Self-play controls showed a persistent ~1 unit advantage to ally 1 that
    survives swapping the spawn positions, so it is tied to the team slot rather
    than to terrain. Running the same matchup in both orientations and averaging
    removes it exactly, without needing to know where it comes from.
    """
    out = []
    for d in (fwd_dir, rev_dir):
        root = Path(d)
        if not root.is_absolute():
            root = REPO / root
        rounds, dropped = [], 0
        for log in infologs(root):
            r = parse(log)
            rounds.extend(r[0])
            dropped += len(r[4])
        out.append((rounds, dropped))
    (fwd, dfwd), (rev, drev) = out
    if not fwd or not rev:
        print("pair mode needs rounds in both directories")
        return 2

    # In fwd the subject is ally 0; in rev it is ally 1, so its edge flips sign.
    e = (edge(fwd) - edge(rev)) / 2.0
    fw, fl = wins(fwd)
    rl, rw = wins(rev)
    n = len(fwd) + len(rev)
    draws = sum(1 for r in fwd + rev if r["winner"] == -1)
    print(f"  forward  ({len(fwd):3d} rounds)  edge={edge(fwd):+5.2f}  "
          f"subject {fw}-{fl}")
    print(f"  reversed ({len(rev):3d} rounds)  edge={edge(rev):+5.2f}  "
          f"subject {rw}-{rl}")
    print(f"\n  SUBJECT EDGE (slot bias cancelled): {e:+.2f} units/round")
    print(f"  subject rounds won {fw + rw} / opponent {fl + rl} / draw {draws}"
          f"   over {n} rounds"
          + (f"   ({dfwd + drev} dropped as contaminated)" if (dfwd + drev) else ""))
    if draws > 0.4 * n:
        print(f"\n  WARNING: {100.0 * draws / n:.0f}% draws -- sides may be "
              f"disengaging; the edge is diluted.")
    return 0


def main() -> int:
    args = sys.argv[1:]
    if args and args[0] == "--pair":
        if len(args) != 3:
            print("usage: arena.py --pair <forward-dir> <reversed-dir>")
            return 2
        return pair_mode(args[1], args[2])
    if not args:
        print(__doc__)
        return 2

    allrounds = []
    for a in args:
        root = Path(a)
        if not root.is_absolute():
            root = REPO / root
        if not root.exists():
            print(f"missing: {root}")
            continue
        for log in infologs(root):
            rounds, init, errs, as_err, dropped = parse(log)
            name = log.parent.name
            print(f"\n=== {name} ===")
            if init:
                print(f"  setup: {init}")
            if as_err:
                print(f"  AngelScript errors: {as_err}   <-- VARIANT WAS DISABLED")
            for e in errs:
                print(f"  ARENA ERROR: {e}")
            report(rounds, "all")
            report([r for r in rounds if r["flip"] == 0], "spawn A")
            report([r for r in rounds if r["flip"] == 1], "spawn B")
            allrounds.extend(rounds)

    if len(args) > 1 or len(allrounds) > 0:
        print("\n=== TOTAL ===")
        report(allrounds, "all")
        report([r for r in allrounds if r["flip"] == 0], "spawn A")
        report([r for r in allrounds if r["flip"] == 1], "spawn B")
        drawpct = (100.0 * sum(1 for r in allrounds if r["winner"] == -1)
                   / len(allrounds)) if allrounds else 0
        if drawpct > 40:
            print(f"\n  WARNING: {drawpct:.0f}% draws -- the sides may never have "
                  f"engaged. Check spawn separation before reading the edge.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
