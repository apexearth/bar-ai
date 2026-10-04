"""Which task our army units were in when they died, split by where they died.

    python tools/deathtasks.py <tournament-or-match-dir>... [--to 16] [--ai anneal]

From `apex: unit-destroyed ... curTask=t<type>b<build>f<fight> ... fwd=`. Type
4 RETREAT, 7 FIGHTER; fight 1 GUARD, 2 DEFEND, 3 SCOUT, 4 RAID, 5 ATTACK,
7 MELEE, 8 ARTY. Builders and buildings are left out: this is the army.
"""
import argparse
import re
import sys
from collections import Counter
from pathlib import Path

LINE = re.compile(r"Skirmish AI <[^>]*?-([\w.]+)>: \[[\d.]+m t\d+\] apex: unit-destroyed (\w+) .*?frame=(\d+) .*?"
                  r"curTask=t(-?\d+)b(-?\d+)f(-?\d+) cost=(\d+) fwd=([\d.-]+) .*?mob=(\d)")
TYPES = {"4": "RETREAT", "7": "FIGHT", "2": "IDLE", "5": "BUILDER"}
FIGHT = {"0": "rally", "1": "guard", "2": "defend", "3": "scout", "4": "raid", "5": "attack", "6": "bomb",
         "7": "melee", "8": "arty", "9": "aa", "10": "ah", "11": "support", "12": "super", "-1": "-"}
CONS = ("ck", "cv", "ca", "com", "rectr", "necro", "fark", "fast", "consul")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--to", type=float, default=16.0)
    ap.add_argument("--ai", default="")
    a = ap.parse_args()
    zones = {"enemy side (fwd>0.5)": Counter(), "middle": Counter(), "our side (fwd<0.2)": Counter()}
    metal = {k: 0 for k in zones}
    for p in a.paths:
        for f in Path(p).glob("**/stdout.txt"):
            for m in LINE.finditer(f.read_text("utf-8", errors="replace")):
                ver, unit, frame, tt, bt, ft, cost, fwd, mob = m.groups()
                if (a.ai and a.ai not in ver) or mob != "1" or int(frame) / 1800.0 > a.to:
                    continue
                if any(unit.endswith(c) or c in unit[3:] for c in CONS):
                    continue
                fw = float(fwd)
                z = "enemy side (fwd>0.5)" if fw > 0.5 else ("our side (fwd<0.2)" if fw < 0.2 else "middle")
                zones[z][f"{TYPES.get(tt, 't' + tt)}/{FIGHT.get(ft, ft)}"] += int(cost)
                metal[z] += int(cost)
    for z, c in zones.items():
        print(f"{z}: {metal[z]} metal of army lost")
        for k, v in c.most_common(6):
            print(f"  {v:7d}  {100.0 * v / max(1, metal[z]):4.0f}%  {k}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
