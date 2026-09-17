"""The opening, side by side: metal, energy, mexes, army and static defence per
side, every two game-minutes, from the stats gadget's [BARAI_STATS] samples.

    python tools/opening.py <run|tournament> [--to 10] [--every 2]

The question it answers is the one apexearth asked on 2026-09-17: "metal and
energy in the <10m timeframes... compare military sizes and defense counts
too".  Team totals; commanders are inside `army built`.
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


def load(path: Path) -> dict[tuple[int, int], dict[int, dict]]:
    out: dict[tuple[int, int], dict[int, dict]] = collections.defaultdict(dict)
    for line in path.read_text(errors="replace").splitlines():
        m = LINE.search(line)
        if not m:
            continue
        kv = dict(t.split("=", 1) for t in m.group(1).split() if "=" in t)
        try:
            team = int(kv["team"]); ally = int(kv["ally"]); minute = round(int(kv["frame"]) / 1800)
        except (KeyError, ValueError):
            continue
        out[(ally, minute)][team] = kv
    return out


def f(kv: dict, k: str) -> float:
    try:
        return float(kv.get(k, 0))
    except ValueError:
        return 0.0


def report(path: Path, to: int, every: int) -> None:
    d = load(path)
    if not d:
        print(f"{path}: no [BARAI_STATS] lines")
        return
    print(f"# {path}")
    allies = sorted({a for a, _ in d})
    hdr = "min | " + " | ".join(
        f"ally{a}: mex  m/s   e/s  eUsed | armed  army-stand  army-built  def-built   lost  killed" for a in allies)
    print(hdr)
    for mn in range(every, to + 1, every):
        cells = []
        for a in allies:
            teams = d.get((a, mn), {})
            if not teams:
                cells.append(" " * 78)
                continue
            S = lambda k: sum(f(x, k) for x in teams.values())
            eused = S("energyUsed") / max(1, mn * 60)
            cells.append(f"{int(S('mexN')):4d} {S('mInc'):5.0f} {S('eInc'):5.0f} {eused:6.0f} | "
                         f"{int(S('armed')):5d} {S('armyReal'):11.0f} {S('mArmy'):11.0f} {S('mDefence'):10.0f} "
                         f"{S('mLostReal'):6.0f} {S('mKillReal'):7.0f}")
        print(f"{mn:3d} | " + " | ".join(cells))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run")
    ap.add_argument("--to", type=int, default=10)
    ap.add_argument("--every", type=int, default=2)
    a = ap.parse_args()
    for log in infologs(Path(a.run)):
        report(log, a.to, a.every)
    return 0


if __name__ == "__main__":
    sys.exit(main())
