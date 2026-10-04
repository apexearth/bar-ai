"""Army losses by the fight task the unit last held before it retreated.

    python tools/fhist.py <tournament-or-match-dir>... [--to 16] [--ai anneal] [--fwd 0.5]

Reads `fhist=[f<type>@frame:h<hp>:w<fwd>;R@...]` on `apex: unit-destroyed`:
the last f-entry is the task that took the unit where it died (R entries are
retreats, which is what nearly every unit is doing when it dies). Fight types:
1 guard 2 defend 3 scout 4 raid 5 attack 7 melee 8 arty.
"""
import argparse
import re
import sys
from collections import Counter
from pathlib import Path

LINE = re.compile(r"Skirmish AI <[^>]*?-([\w.]+)>: \[[\d.]+m t\d+\] apex: unit-destroyed (\w+) .*?frame=(\d+) .*?"
                  r"cost=(\d+) fwd=([\d.-]+) .*?mob=1 .*?fhist=\[([^\]]*)\]")
NAMES = {"1": "guard", "2": "defend", "3": "scout", "4": "raid", "5": "attack", "7": "melee", "8": "arty",
         "9": "aa", "11": "support", "12": "super"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--to", type=float, default=16.0)
    ap.add_argument("--ai", default="")
    ap.add_argument("--fwd", type=float, default=0.5)
    a = ap.parse_args()
    metal, units, total = Counter(), Counter(), 0
    for p in a.paths:
        for f in Path(p).glob("**/stdout.txt"):
            for m in LINE.finditer(f.read_text("utf-8", errors="replace")):
                ver, unit, frame, cost, fwd, hist = m.groups()
                if (a.ai and a.ai not in ver) or int(frame) / 1800.0 > a.to or float(fwd) <= a.fwd:
                    continue
                fs = [h.split("@")[0][1:] for h in hist.split(";") if h.startswith("f")]
                task = NAMES.get(fs[-1], "f" + fs[-1]) if fs else "(none)"
                metal[task] += int(cost)
                units[(task, unit)] += 1
                total += int(cost)
    print(f"army metal lost past fwd {a.fwd} by minute {a.to:g}: {total}")
    for k, v in metal.most_common():
        top = ", ".join(f"{u}x{n}" for (t, u), n in units.most_common() if t == k)[:80]
        print(f"  {v:7d} {100.0 * v / max(1, total):4.0f}%  {k:8s} {top}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
