"""Every valuation the AI made, by item, minute by minute -- the data behind the Valuation Balance page.

    python tools/valreport.py <match dir> [--out valuations.json] [--ally 0]

Builder market: `apex: valitem` lines (each want offered in an election, by kind and def; count, min, mean,
max of its value x1000, per seat per minute). Factory lines: `apex: prodrank` (each product's value in the
lab's own ranking). Rows are summed over our side's seats per game-minute:
  {minute, market, kind, item, n, min, avg, max}
market is "builder" or "factory"; avg is weighted by n.
"""
import argparse
import json
import re
from collections import defaultdict

VI = re.compile(r"\[f=0*(\d+)\].*apex: valitem t=(\d+) (.*)$")
PR = re.compile(r"\[f=0*(\d+)\].*apex: prodrank fac=(\S+) t=(\d+) .*?n=\d+ (.*)$")
PRV = re.compile(r"([a-z0-9]+)(?::[a-z]+)?=([0-9.]+)\(")   # "armpw=307818.25(" and a con's "armck:b=91.16("


KIND_LABEL = {
    "mex": "Claim an extractor", "mexup": "Upgrade an extractor", "energy": "Energy", "convert": "Metal converter",
    "nano": "Nano turret", "sense": "Radar, jammer or sensor", "protect": "Defence tower", "airdef": "Anti-air tower",
    "plant": "Factory", "tech": "Advanced lab", "super": "Super build", "assist": "Help another build",
    "reclaim": "Reclaim wrecks", "reclobs": "Reclaim our old building", "geo": "Geothermal", "teeth": "Dragon's teeth",
    "store": "Storage", "produce": "Factory product",
}


def unit_names():
    """Display names and descriptions from the game's language/en/units.json (via tools/bar_env.py)."""
    import os
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        import bar_env
        u = json.load(open(os.path.join(str(bar_env.load().game_sdd), "language", "en", "units.json"),
                           encoding="utf-8"))["units"]
        return u.get("names", {}), u.get("descriptions", {})
    except Exception as e:
        print("unit names unavailable:", e)
        return {}, {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("match")
    ap.add_argument("--out", default="valuations.json")
    ap.add_argument("--teams", default="0-7", help="our seats, as a-b")
    a = ap.parse_args()
    lo, hi = (int(x) for x in a.teams.split("-"))
    agg = defaultdict(lambda: [0, float("inf"), 0.0, float("-inf")])   # n, min, sum, max
    for ln in open(a.match + "/infolog.txt", encoding="utf-8", errors="ignore"):
        if "apex: valitem" in ln:
            m = VI.search(ln)
            if not m or not (lo <= int(m.group(2)) <= hi):
                continue
            minute = int(m.group(1)) // 1800
            for tok in m.group(3).split():
                p = tok.split(":")
                if len(p) != 6:
                    continue
                kind, item, n, vmin, vavg, vmax = p[0], p[1], int(p[2]), float(p[3]), float(p[4]), float(p[5])
                r = agg[(minute, "builder", kind, item)]
                r[0] += n
                r[1] = min(r[1], vmin)
                r[2] += vavg * n
                r[3] = max(r[3], vmax)
        elif "apex: prodrank" in ln:
            m = PR.search(ln)
            if not m or not (lo <= int(m.group(3)) <= hi):
                continue
            minute = int(m.group(1)) // 1800
            for item, v in PRV.findall(m.group(4)):
                v = float(v)
                r = agg[(minute, "factory", "produce", item)]
                r[0] += 1
                r[1] = min(r[1], v)
                r[2] += v
                r[3] = max(r[3], v)
    names, descs = unit_names()
    rows = []
    for (minute, market, kind, item), (n, vmin, s, vmax) in sorted(agg.items()):
        base = re.sub(r"_scav$", "", item)
        rows.append({"minute": minute, "market": market, "kind": kind, "kindLabel": KIND_LABEL.get(kind, kind),
                     "item": item, "label": names.get(base, item if item != "-" else KIND_LABEL.get(kind, kind)),
                     "desc": descs.get(base, ""), "n": n,
                     "min": round(vmin, 4), "avg": round(s / n, 4), "max": round(vmax, 4)})
    json.dump(rows, open(a.out, "w"), separators=(",", ":"))
    print("rows", len(rows), "items", len({(r["kind"], r["item"]) for r in rows}),
          "minutes", (max(r["minute"] for r in rows) + 1) if rows else 0, "->", a.out)


if __name__ == "__main__":
    main()
