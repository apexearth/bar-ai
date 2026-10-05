"""Where our constructors are working, minute by minute: home vs out on the map.

    python tools/handsplit.py <tournament-or-match-dir>... [--ai v0.1.4] [--home 1200] [--to 20]

From `apex: exec` (every job a builder takes, with its site): at each minute, a
builder counts where its LATEST job was -- within --home elmos of its team's
first lab ("home"), or beyond ("out"). Alongside, from the stats rows: energy
income, the share of samples energy-stalled, converter metal and extractors --
the home work that suffers when too few hands stay home.
"""
import argparse
import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

EXEC = re.compile(r"\[f=0*(\d+)\][^\n]*?<ApexUnstable-([^>]*)>: [^\n]*?apex: exec t=(\d+) (\w+) #(\d+) (\w+):(\w*) "
                  r"pick=\d+ at=(-?[\d.]+),(-?[\d.]+)")
CONS = ("armck", "corck", "armcv", "corcv", "armack", "corack", "armacv", "coracv", "armca", "corca")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--ai", default="")
    ap.add_argument("--home", type=float, default=1200.0)
    ap.add_argument("--to", type=int, default=20)
    a = ap.parse_args()
    mins = list(range(4, a.to + 1, 2))
    acc = {m: {"home": [], "out": [], "eInc": [], "estall": [], "conv": [], "mex": [], "eco": []} for m in mins}
    games = 0
    for d in a.dirs:
        for p in Path(d).glob("**/stdout.txt"):
            txt = p.read_text("utf-8", errors="replace")
            homes, last, teamOf = {}, {}, {}
            events = []
            for m in EXEC.finditer(txt):
                f, ver, team, unit, uid, kind, dn, x, z = m.groups()
                if a.ai and a.ai not in ver:
                    continue
                if unit not in CONS:
                    if team not in homes and kind == "plant":
                        homes[team] = (float(x), float(z))
                    continue
                if team not in homes and kind == "plant":
                    homes[team] = (float(x), float(z))
                events.append((int(f), team, uid, float(x), float(z)))
            if not events or not homes:
                continue
            games += 1
            team = events[0][1]
            res = p.parent / "result.json"
            stats = json.loads(res.read_text("utf-8")).get("stats") if res.exists() else []
            ei = 0
            for m in mins:
                while ei < len(events) and events[ei][0] <= m * 1800:
                    f, t, uid, x, z = events[ei]
                    last[(t, uid)] = (x, z)
                    teamOf[(t, uid)] = t
                    ei += 1
                h = o = 0
                for key, (x, z) in last.items():
                    hp = homes.get(teamOf[key])
                    if hp is None:
                        continue
                    if math.hypot(x - hp[0], z - hp[1]) <= a.home:
                        h += 1
                    else:
                        o += 1
                acc[m]["home"].append(h)
                acc[m]["out"].append(o)
                rows = [r for r in stats or [] if str(int(r.get("team", -1))) == team
                        and r.get("reason") == "periodic" and abs(r.get("frame", 0) - m * 1800) < 300]
                if rows:
                    r = rows[0]
                    acc[m]["eInc"].append(r.get("eInc", 0.0))
                    acc[m]["estall"].append(100.0 * r.get("eStall", 0.0) / max(1.0, r.get("resSamp", 1.0)))
                    acc[m]["conv"].append(r.get("mMakeConv", 0.0))
                    acc[m]["mex"].append(r.get("mexN", 0.0))
                    acc[m]["eco"].append(r.get("mInc", 0.0) + r.get("eInc", 0.0) / 60.0)
    print(f"{games} games{' of ' + a.ai if a.ai else ''}; a hand counts where its latest job was")
    print("min  hands home  out   eInc  eStall%  convM/s  mexes   eco")
    for m in mins:
        v = acc[m]
        if not v["home"]:
            continue
        mean = lambda k: (sum(v[k]) / len(v[k])) if v[k] else float("nan")
        print(f"{m:3d}  {mean('home'):10.1f} {mean('out'):4.1f} {mean('eInc'):6.0f} {mean('estall'):8.0f} "
              f"{mean('conv'):8.1f} {mean('mex'):6.1f} {mean('eco'):5.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
