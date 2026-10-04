"""Per AI spec: army built, economy, constructors and metal lost/killed at fixed minutes.

    python tools/armyby.py <tournament-dir>... [--minutes 4 8 12]

The per-version companion of whowins.py: same game, same minute, which version
fielded more, regardless of who won.
"""
import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

CONS = ("armck", "corck", "armcv", "corcv", "armca", "corca")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--minutes", type=int, nargs="+", default=[4, 8, 12])
    a = ap.parse_args()
    acc = defaultdict(lambda: defaultdict(list))
    for d in a.dirs:
        for p in Path(d).glob("matches/*/result.json"):
            r = json.loads(p.read_text("utf-8"))
            specs = [t["spec"] for t in r["teams"]]
            for ally, spec in enumerate(specs):
                for m in a.minutes:
                    rows = [x for x in r.get("stats") or [] if int(x.get("ally", -1)) == ally
                            and x.get("reason") == "periodic" and abs(x.get("frame", 0) - m * 1800) < 300]
                    if rows:
                        x = rows[0]
                        uc = dict((kv.split(":")[0], int(kv.split(":")[1]))
                                  for kv in str(x.get("unitCount", "")).split(",") if ":" in kv)
                        acc[spec][m].append((x.get("mArmy", 0.0), x.get("mInc", 0.0) + x.get("eInc", 0.0) / 60.0,
                                             sum(uc.get(k, 0) for k in CONS), x.get("mLostReal", 0.0),
                                             x.get("mKillReal", 0.0)))
    print("spec                               min    army    eco   cons   lost  killed    n")
    for spec in sorted(acc):
        for m in a.minutes:
            v = acc[spec][m]
            if v:
                mean = [sum(t[i] for t in v) / len(v) for i in range(5)]
                print(f"{spec[:34]:34s} {m:3d} {mean[0]:7.0f} {mean[1]:6.0f} {mean[2]:6.1f} {mean[3]:6.0f} {mean[4]:7.0f} {len(v):4d}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
