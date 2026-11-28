#!/usr/bin/env python3
"""Paired arms on the same checkpoint and seeds (runtime/armynet/<prefix>-<arm>-<seed>.log from watch.py): mobile
kill/loss at 10 and 20 min and at the end for side A, length and result, per seed and in total.

    python tools/armynet/paired.py ga2 [arms: plain group]
"""
import glob
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def stats_of(log):
    m = re.search(r"watch-armynet-engine-([\d-]+)", Path(log).read_text(errors="replace"))
    if not m:
        return None
    rj = REPO / "matches" / ("armynet-watch-" + m.group(1)) / "result.json"
    if not rj.exists():
        return None
    d = json.loads(rj.read_text())
    st, res = d.get("stats") or [], d.get("result") or {}

    def kl(minute):
        rows = [r for r in st if int(r["team"]) == 0 and (minute is None or r["frame"] <= minute * 1800 + 1)]
        if not rows:
            return None
        k, l = rows[-1].get("mKillMobile", 0), rows[-1].get("mLostMobile", 0)
        return k / l if l else None
    w = res.get("winners") or []
    return {"k10": kl(10), "k20": kl(20), "kend": kl(None), "min": res.get("game_minutes"),
            "res": "won" if 0 in w else ("draw" if not w else "lost")}


def main(a):
    prefix = a[0]
    arms = a[1:] or ["plain", "group"]
    seeds = sorted({int(re.search(r"-(\d+)\.log$", p).group(1)) for p in glob.glob(str(REPO / "runtime" / "armynet" / (prefix + "-*.log")))})
    tot = {arm: [] for arm in arms}
    for s in seeds:
        cells = []
        for arm in arms:
            r = stats_of(REPO / "runtime" / "armynet" / ("%s-%s-%d.log" % (prefix, arm, s)))
            if r:
                tot[arm].append(r)
                f = lambda v: "%.2f" % v if v is not None else "-"
                cells.append("%s: %s/%s/%s %s %.1f" % (arm, f(r["k10"]), f(r["k20"]), f(r["kend"]), r["res"], r["min"] or 0))
            else:
                cells.append("%s: (not done)" % arm)
        print("seed %d  " % s + "  |  ".join(cells))
    for arm, rs in tot.items():
        if rs:
            mean = lambda k: sum(r[k] for r in rs if r[k] is not None) / max(1, sum(r[k] is not None for r in rs))
            print("%-6s n=%d  kill/loss@10 %.2f  @20 %.2f  end %.2f  minutes %.1f  wins %d" % (
                arm, len(rs), mean("k10"), mean("k20"), mean("kend"), mean("min"), sum(r["res"] == "won" for r in rs)))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
