#!/usr/bin/env python3
"""When our AI's first radar tower stood, per AI seat, by game date (his 11-18: "We no longer seem to be making
radar in the early game which makes it hard to deal with raiders"). Reads the replay recordings of his games
(tools/replay_orders.py; F = finished) and the AI name from each demo's start script.

    python tools/armynet/radar_history.py
"""
import collections
import glob
import gzip
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools"))
import bar_env  # noqa: E402
import replay_extract as rx  # noqa: E402

RADAR = re.compile(r"^(arm|cor|leg)(rad|arad)$|^legrad", re.I)


def main():
    env = bar_env.load()
    rows = []
    for rec in sorted(glob.glob("G:/bar-ai-archive/replay-orders/*/orders.txt.gz")):
        stem = Path(rec).parent.name
        demo = env.data / "demos" / (stem + ".sdfz")
        if not demo.exists():
            continue
        meta = rx.meta_of(rx.demo_script(demo))
        ai = {a["team"]: "%s %s" % (a["short"], a["version"]) for a in meta["ais"]}
        names, first, minutes = {}, {}, 0.0
        for ln in gzip.open(rec, "rt", errors="replace"):
            p = ln.split()
            if p[0] == "D":
                names[int(p[1])] = p[2]
            elif p[0] == "F":
                t = int(p[4])
                if t in ai and RADAR.match(names.get(int(p[3]), "")) and t not in first:
                    first[t] = int(p[1]) / 1800.0
                minutes = max(minutes, int(p[1]) / 1800.0)
        for t, name in ai.items():
            if name.startswith("Apex"):
                rows.append((stem[:10], name, first.get(t), minutes))
    by = collections.defaultdict(list)
    for date, name, f, mins in rows:
        by[(date, name)].append(f)
    print("%-11s %-24s %5s %10s %16s" % ("date", "AI", "seats", "no radar", "first radar min"))
    for (date, name), fs in sorted(by.items()):
        got = sorted(f for f in fs if f is not None)
        med = got[len(got) // 2] if got else None
        print("%-11s %-24s %5d %10d %16s" % (date, name[:24], len(fs), len(fs) - len(got),
                                             "%.1f" % med if med is not None else "-"))


if __name__ == "__main__":
    main()
