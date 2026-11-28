#!/usr/bin/env python3
"""Paired arms (paired_forces.sh): per seed and arm the measures that say whether force orders help, from each
game's report.md (game_report.py) and serve.log; then each arm's mean and its mean paired difference from 'unit'.

    python tools/armynet/paired_summary.py runtime/armynet/paired-forces-b.log
"""
import collections
import re
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[2]


def lost_table(md):
    rows = re.findall(r"^\| (\d+)-(\d+) \| ([AB]) lost \| (\d+) \| (\d+) \| (\d+) \| (\d+) \| (\d+) \| (\d+) \| (\d+) \|", md, re.M)
    return [(int(a), int(b), s, *map(int, r)) for a, b, s, *r in rows]


def measures(match):
    md = (REPO / match / "report.md").read_text(encoding="utf-8")
    t = lost_table(md)
    out = {}
    for upto in (12, 20):
        sel = [r for r in t if r[1] <= upto]
        a_lost = sum(r[9] for r in sel if r[2] == "A")
        b_lost = sum(r[9] for r in sel if r[2] == "B")
        out["trade%d" % upto] = b_lost / max(a_lost, 1)
        out["their_eco_killed%d" % upto] = sum(r[6] for r in sel if r[2] == "B")
        out["our_eco_lost%d" % upto] = sum(r[6] for r in sel if r[2] == "A")
        out["army_killed%d" % upto] = sum(r[3] for r in sel if r[2] == "B")
        out["army_lost%d" % upto] = sum(r[3] for r in sel if r[2] == "A")
    for mn, a_mex, b_mex, a_inc, b_inc, a_army, b_army in re.findall(
            r"^\| (\d+) \| (\d+) \| (\d+) \| (\d+) \| (\d+) \| (\d+) \| (\d+) \|$", md, re.M):
        if mn in ("8", "12", "16"):
            out["army_ratio%s" % mn] = int(a_army) / max(int(b_army), 1)
            out["income_ratio%s" % mn] = int(a_inc) / max(int(b_inc), 1)
    m = re.search(r"^4 min A ([\d.]+) B [\d.]+; 8 min A ([\d.]+) B [\d.]+; 12 min A ([\d.]+) B [\d.]+; 16 min A ([\d.]+)", md, re.M)
    if m:
        out["centre8"], out["centre12"], out["centre16"] = float(m.group(2)), float(m.group(3)), float(m.group(4))
    reach = re.findall(r"(\d+)-(\d+): A \d+ sq, (\d+) of B's mex", md)
    out["their_mex_reached_0_12"] = sum(int(n) for a, b, n in reach if int(b) <= 12)
    eng = match.replace("armynet-watch-", "watch-armynet-engine-")
    serve = (REPO / eng / "serve.log").read_text(encoding="utf-8", errors="replace")
    nn = [float(x) for mn, x in re.findall(r"^minute (\d+) task spread .*?nearest own unit (-?[\d.]+)", serve, re.M)
          if 5 <= int(mn) <= 15 and float(x) >= 0]
    out["nearest_own_5_15"] = float(np.mean(nn)) if nn else float("nan")
    fw = [float(x) for mn, x in re.findall(r"^minute (\d+) orders \d+ forward median ([\d.]+)", serve, re.M) if 5 <= int(mn) <= 15]
    out["order_forward_5_15"] = float(np.mean(fw)) if fw else float("nan")
    return out


def main(a):
    games = collections.defaultdict(dict)
    for ln in open(a[0], encoding="utf-8"):
        p = ln.split()
        games[int(p[1])][p[2]] = p[3].replace("\\", "/")
    res = {s: {arm: measures(m) for arm, m in arms.items()} for s, arms in sorted(games.items())}
    keys = list(next(iter(next(iter(res.values())).values())).keys())
    arms = list(dict.fromkeys(["unit"] + [arm for s in res for arm in res[s]]))
    print("%-24s %s   %s" % ("measure", "  ".join("%10s" % x[:10] for x in arms),
                               "  ".join("%14s" % ("%s-unit" % x[:9]) for x in arms[1:])))
    for k in keys:
        vals = {arm: [res[s][arm].get(k, np.nan) for s in res if arm in res[s]] for arm in arms}
        line = "%-24s %s" % (k, "  ".join("%10.2f" % np.nanmean(vals[arm]) for arm in arms))
        for arm in arms[1:]:
            d = [res[s][arm].get(k, np.nan) - res[s]["unit"].get(k, np.nan) for s in res if arm in res[s] and "unit" in res[s]]
            d = np.array(d, float)
            line += "  %+8.2f (%d/%d+)" % (np.nanmean(d), int(np.sum(d > 0)), len(d))
        print(line)


if __name__ == "__main__":
    main(sys.argv[1:])
