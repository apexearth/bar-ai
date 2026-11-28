#!/usr/bin/env python3
"""Fight trades per side in armynet games: mobile metal killed per mobile metal lost, at 10, 15 and 20 minutes and
at the end (result.json stats: mKillMobile, mLostMobile, cumulative).

    python tools/armynet/trades.py [campaign dir]
"""
import glob
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def at(stats, team, minute, key):
    rows = [r for r in stats if int(r["team"]) == team and (minute is None or r["frame"] <= minute * 1800 + 1)]
    return rows[-1].get(key, 0) if rows else 0


def matches(a):
    if a and all(Path(x).name.startswith("armynet-watch-") for x in a):
        return [(Path(x), "") for x in a]
    camp = Path(a[0]) if a else Path(sorted(glob.glob(str(REPO / "runtime" / "armynet" / "campaign-2*")))[-1])
    out = []
    for ln in open(camp / "campaign.log", errors="replace"):
        if ln.startswith("RESULT "):
            r = json.loads(ln[7:])
            out.append((REPO / "matches" / r.get("match", ""), "step %s seed %s" % (r.get("step"), r.get("seed"))))
    return out


def main(a):
    print("match                          | kill/loss of mobile metal, A then B, at 10 / 15 / 20 min / end | result")
    for m, label in matches(a):
        if not (m / "result.json").exists():
            continue
        rj = json.loads((m / "result.json").read_text())
        st = rj.get("stats") or []
        res = rj.get("result") or {}
        cells = []
        for minute in (10, 15, 20, None):
            pair = []
            for t in (0, 1):
                k, l = at(st, t, minute, "mKillMobile"), at(st, t, minute, "mLostMobile")
                pair.append("%.2f" % (k / l) if l else "-")
            cells.append("/".join(pair))
        print("%-30s | %s | %s %.1f min %s" % (m.name[:30], "   ".join(cells),
                                              "won" if 0 in (res.get("winners") or [])
                                              else ("draw" if not res.get("winners") else "lost"),
                                              res.get("game_minutes") or 0, label))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
