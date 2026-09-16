"""The mex economy over time, per side: how many extractors stand, what they
make, what the converters make -- the untapped-mex question.

    python tools/mexeco.py <run|tournament> [--every 4]

Reads the stats gadget's periodic [BARAI_STATS] samples (every 2 game-minutes,
every team): mexN / mMakeMex / mMakeConv / mMakeAll per team, summed per ally
side, with the per-seat spread of standing mexes.  A map's spot total is not
in the log; `python tools/unitsync.py` or the AI's own CacheSpots knows it.
"""
from __future__ import annotations

import argparse
import collections
import re
import sys
from pathlib import Path

LINE = re.compile(r"\[BARAI_STATS\] (.*)")


def infologs(target: Path) -> list[Path]:
    if target.is_file():
        return [target]
    if (target / "infolog.txt").exists():
        return [target / "infolog.txt"]
    logs = sorted(target.glob("matches/*/infolog.txt"))
    if not logs:
        sys.exit(f"no infolog under {target}")
    return logs


def parse(path: Path) -> dict[tuple[int, int], dict[int, dict]]:
    """(ally, minute) -> team -> fields"""
    out: dict[tuple[int, int], dict[int, dict]] = collections.defaultdict(dict)
    names: dict[int, str] = {}
    for line in path.read_text(errors="replace").splitlines():
        m = LINE.search(line)
        if not m:
            continue
        kv = {}
        for tok in m.group(1).split():
            if "=" in tok:
                k, v = tok.split("=", 1)
                kv[k] = v
        if kv.get("reason") not in ("periodic", "gameover", "wiped", "final"):
            pass
        try:
            team = int(kv["team"]); ally = int(kv["ally"]); frame = int(kv["frame"])
        except (KeyError, ValueError):
            continue
        minute = round(frame / 1800)
        out[(ally, minute)][team] = kv
    return out


def f(kv: dict, k: str) -> float:
    try:
        return float(kv.get(k, 0))
    except ValueError:
        return 0.0


def report(path: Path, every: int) -> None:
    data = parse(path)
    if not data:
        print(f"{path}: no [BARAI_STATS] lines")
        return
    print(f"# {path}")
    allies = sorted({a for a, _ in data})
    minutes = sorted({mn for _, mn in data})
    print(f"{'min':>4} | " + " | ".join(f"ally{a}: mexes(seat spread)  mex m/s  conv m/s  all m/s" for a in allies))
    for mn in minutes:
        if mn % every:
            continue
        cells = []
        for a in allies:
            teams = data.get((a, mn), {})
            if not teams:
                cells.append(" " * 44)
                continue
            n = [int(f(kv, "mexN")) for kv in teams.values()]
            mex = sum(f(kv, "mMakeMex") for kv in teams.values())
            conv = sum(f(kv, "mMakeConv") for kv in teams.values())
            allm = sum(f(kv, "mMakeAll") for kv in teams.values())
            spread = "/".join(str(x) for x in sorted(n))
            cells.append(f"{sum(n):3d} ({spread:<20s}) {mex:6.0f} {conv:8.0f} {allm:8.0f}")
        print(f"{mn:>4} | " + " | ".join(cells))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run")
    ap.add_argument("--every", type=int, default=4, help="print every N game-minutes (default 4)")
    a = ap.parse_args()
    for log in infologs(Path(a.run)):
        report(log, a.every)
    return 0


if __name__ == "__main__":
    sys.exit(main())
