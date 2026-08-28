#!/usr/bin/env python3
"""What our units were thinking before they died.

Usage:
    python tools/deaths.py <match-dir-or-infolog> [--team N]

Reads the `apex: unit-destroyed` lines and reports two tables:

1. The classic metal-lost-by-last-action summary.
2. TRANSITIONS for mobile combat units: not the terminal task ("retreat" is
   never the answer) but the story -- what the unit was doing, what it
   switched to, at what hp and map depth, and how long it survived after.
   `attack->retreat(auto)` is the engine's low-hp retreat; `(ordered)` means
   our own withdraw logic sent it back (a `W` tag precedes the switch).

Needs the enriched fight-hist entries (f5@1234:h87:w0.62) from 2026-08-21;
older logs still produce table 1 and a degraded table 2 without hp/depth.
"""
import re
import statistics
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
    r"(?: acts=(?P<acts>\S*))?"
    r" id=(?P<id>\d+) frame=(?P<frame>\d+) at=(?P<x>-?\d+),(?P<z>-?\d+)"
    r" curTask=t(?P<tt>-?\d+)b(?P<bt>-?\d+)f(?P<ft>-?\d+)"
    r" cost=(?P<cost>\d+) fwd=(?P<fwd>-?[\d.]+)(?: built=(?P<built>\d))?"
    r"(?: mob=(?P<mob>\d))?"
    r"(?: hist=\[(?P<hist>[^\]]*)\])?"
    r"(?: fhist=\[(?P<fhist>[^\]]*)\])?")

FH_ENTRY = re.compile(
    r"(?P<tag>f\d+|[WRO])@(?P<frame>\d+)(?::h(?P<hp>\d+))?(?::w(?P<w>-?[\d.]+))?")


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


def fight_name(ft):
    return FIGHT[ft] if 0 <= ft < len(FIGHT) else "f%d" % ft


def parse_fhist(s):
    out = []
    for m in FH_ENTRY.finditer(s or ""):
        out.append({
            "tag": m["tag"],
            "frame": int(m["frame"]),
            "hp": int(m["hp"]) if m["hp"] else None,
            "w": float(m["w"]) if m["w"] else None,
        })
    return out


def transition(entries, tt, ft, death_frame):
    """The story: (bucket label, hp at last switch, seconds in terminal)."""
    fights = [e for e in entries if e["tag"].startswith("f")]
    prev = fight_name(int(fights[-1]["tag"][1:])) if fights else "unknown"
    ordered = any(e["tag"] == "W" for e in entries)
    term_entry = None
    for e in reversed(entries):
        if e["tag"] in ("R", "O"):
            term_entry = e
            break
    if tt == 7:
        # Died holding a fight task: never disengaged at all.
        return ("%s->died-fighting" % fight_name(ft), None, None)
    if tt == 4:
        how = "(ordered)" if ordered else "(auto)"
        hp = term_entry["hp"] if term_entry else None
        secs = ((death_frame - term_entry["frame"]) / 30.0) if term_entry else None
        return ("%s->retreat%s" % (prev, how), hp, secs)
    hp = term_entry["hp"] if term_entry else None
    secs = ((death_frame - term_entry["frame"]) / 30.0) if term_entry else None
    return ("%s->%s" % (prev, label(tt, -1, -1)), hp, secs)


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
    tr_metal = defaultdict(float)
    tr_count = defaultdict(int)
    tr_hp = defaultdict(list)
    tr_secs = defaultdict(list)
    tr_fwd = defaultdict(list)
    seen = set()
    for line in text.splitlines():
        m = LINE.search(line)
        if not m:
            continue
        if team is not None and int(m["team"]) != team:
            continue
        # The engine re-reports dead units (one nano logged 2,350 deaths);
        # count each (team, id) once, at its first report.
        key = (m["team"], m["id"])
        if key in seen:
            continue
        seen.add(key)
        if int(m["frame"]) >= cutoff:
            continue
        if m["built"] == "0":
            key = "under-construction"   # a nanoframe holds no task; full def
        elif m["mob"] == "0":
            key = "structure"            # buildings hold NIL for life; their
        else:                            # deaths are base attrition, not army
            key = label(int(m["tt"]), int(m["bt"]), int(m["ft"]))
        c = float(m["cost"])
        metal[key] += c
        count[key] += 1
        fwd_sum[key] += float(m["fwd"])
        per_team[int(m["team"])] += c
        # Table 2: mobile finished combat units only.
        if m["built"] == "1" and m["mob"] == "1" and int(m["tt"]) in (4, 7, 2, 3, 0, -1):
            entries = parse_fhist(m["fhist"])
            if entries or int(m["tt"]) in (4, 7):
                bucket, hp, secs = transition(
                    entries, int(m["tt"]), int(m["ft"]), int(m["frame"]))
                tr_metal[bucket] += c
                tr_count[bucket] += 1
                tr_fwd[bucket].append(float(m["fwd"]))
                if hp is not None:
                    tr_hp[bucket].append(hp)
                if secs is not None:
                    tr_secs[bucket].append(secs)
    if not metal:
        sys.exit("no unit-destroyed lines found in %s" % p)
    total = sum(metal.values())
    print(f"{'last action':<16}{'metal':>9}{'share':>7}{'units':>7}{'avg fwd':>9}")
    for key in sorted(metal, key=metal.get, reverse=True):
        print(f"{key:<16}{metal[key]:>9.0f}{metal[key]/total:>6.0%}"
              f"{count[key]:>7}{fwd_sum[key]/count[key]:>9.2f}")
    print(f"{'TOTAL':<16}{total:>9.0f}")
    if tr_metal:
        ttotal = sum(tr_metal.values())
        print(f"\nWHAT THEY WERE THINKING (mobile combat, {ttotal:.0f} metal)")
        print(f"{'transition':<28}{'metal':>8}{'share':>7}{'units':>7}"
              f"{'hp@switch':>11}{'secs-after':>12}{'fwd':>7}")
        for key in sorted(tr_metal, key=tr_metal.get, reverse=True):
            hp = ("%d%%" % statistics.median(tr_hp[key])) if tr_hp[key] else "-"
            secs = ("%.0fs" % statistics.median(tr_secs[key])) if tr_secs[key] else "-"
            fwd = ("%.2f" % statistics.median(tr_fwd[key])) if tr_fwd[key] else "-"
            print(f"{key:<28}{tr_metal[key]:>8.0f}{tr_metal[key]/ttotal:>6.0%}"
                  f"{tr_count[key]:>7}{hp:>11}{secs:>12}{fwd:>7}")
    if team is None and len(per_team) > 1:
        print("\nper team:", "  ".join(
            f"t{t}={v:.0f}" for t, v in sorted(per_team.items())))


if __name__ == "__main__":
    main()
