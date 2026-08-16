#!/usr/bin/env python3
"""Last major action before death, aggregated from apex unit-destroyed lines.

Usage:
    python tools/deaths.py <match-dir-or-infolog> [--team N]

Reads the `apex: unit-destroyed ... curTask=t<T>b<B>f<F> cost=<M> fwd=<W>`
lines main.as writes for every one of our units destroyed, and reports metal
lost bucketed by the unit's task at the moment it died -- the fight type for
combat units (attack, defend, raid...), the build type for constructors.
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

FIGHT = ["rally", "guard", "defend", "scout", "raid", "attack", "bomb",
         "melee", "arty", "aa", "ah", "support", "super"]
BUILD = ["factory", "nano", "store", "pylon", "energy", "geo", "geoup",
         "defence", "bunker", "big_gun", "radar", "sonar", "convert", "mex",
         "mexup", "repair", "reclaim", "resurrect", "recruit", "terraform"]

LINE = re.compile(
    r"\[(?P<min>[\d.]+)m t(?P<team>\d+)\] apex: unit-destroyed (?P<name>\S+)"
    r" id=\d+ frame=\d+ at=(?P<x>-?\d+),(?P<z>-?\d+)"
    r" curTask=t(?P<tt>-?\d+)b(?P<bt>-?\d+)f(?P<ft>-?\d+)"
    r" cost=(?P<cost>\d+) fwd=(?P<fwd>-?[\d.]+)(?: built=(?P<built>\d))?")


def label(tt, bt, ft):
    # IUnitTask::Type: NIL PLAYER IDLE WAIT RETREAT BUILDER FACTORY FIGHTER
    if tt == 7 and 0 <= ft < len(FIGHT):
        return "fight:" + FIGHT[ft]
    if tt == 5:
        if 0 <= bt < len(BUILD):
            return "build:" + BUILD[bt]
        return "build:?%d" % bt
    if tt == -1:
        return "no-task"
    return {0: "nil", 1: "player", 2: "idle", 3: "wait",
            4: "retreat", 6: "factory"}.get(tt, "t%d" % tt)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    team = None
    for i, a in enumerate(sys.argv):
        if a == "--team" and i + 1 < len(sys.argv):
            team = int(sys.argv[i + 1])
    if not args:
        sys.exit(__doc__)
    p = Path(args[0])
    if p.is_dir():
        p = p / "infolog.txt"
    text = p.read_text(errors="replace")
    # The end-of-game wipe floods destruction events for whole standing bases
    # (all on idle tasks); cut the final 90 seconds so the report reads combat.
    frames = [int(f) for f in re.findall(r" frame=(\d+)", text)]
    cutoff = (max(frames) - 90 * 30) if frames else 0
    metal = defaultdict(float)
    count = defaultdict(int)
    fwd_sum = defaultdict(float)
    per_team = defaultdict(float)
    seen = set()
    for line in text.splitlines():
        m = LINE.search(line)
        if not m:
            continue
        if team is not None and int(m["team"]) != team:
            continue
        # The engine re-reports dead units (one nano logged 2,350 deaths);
        # count each (team, id) once, at its first report.
        uid = re.search(r" id=(\d+)", line)
        key = (m["team"], uid.group(1) if uid else line)
        if key in seen:
            continue
        seen.add(key)
        frm = re.search(r" frame=(\d+)", line)
        if frm and int(frm.group(1)) >= cutoff:
            continue
        if m["built"] == "0":
            key = "under-construction"   # a nanoframe holds no task; full def
        else:                            # cost here overstates the real loss
            key = label(int(m["tt"]), int(m["bt"]), int(m["ft"]))
        c = float(m["cost"])
        metal[key] += c
        count[key] += 1
        fwd_sum[key] += float(m["fwd"])
        per_team[int(m["team"])] += c
    if not metal:
        sys.exit("no unit-destroyed lines found in %s" % p)
    total = sum(metal.values())
    print(f"{'last action':<16}{'metal':>9}{'share':>7}{'units':>7}{'avg fwd':>9}")
    for key in sorted(metal, key=metal.get, reverse=True):
        print(f"{key:<16}{metal[key]:>9.0f}{metal[key]/total:>6.0%}"
              f"{count[key]:>7}{fwd_sum[key]/count[key]:>9.2f}")
    print(f"{'TOTAL':<16}{total:>9.0f}")
    if team is None and len(per_team) > 1:
        print("\nper team:", "  ".join(
            f"t{t}={v:.0f}" for t, v in sorted(per_team.items())))


if __name__ == "__main__":
    main()
