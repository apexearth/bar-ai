#!/usr/bin/env python3
"""Dead-mex rebuild lag, per game and summarised.

For every infolog under the given paths: each of our extractors that died
(`apex: unit-destroyed armmex/cormex/legmex ... at=x,z`) is matched to the
next mex order at that spot (`apex: exec ... mex:<def> pick=N at=x,z`, within
64 elmo). Prints the lag per death, the `apex: rebuild` pricing lines for the
spot when present, and a summary: median lag, share never re-ordered, and
army counts from [BARAI_ARMY] at fixed minutes.

    python tools/rebuild_lag.py tournaments/<run>          # every game in it
    python tools/rebuild_lag.py matches/<run>/infolog.txt  # one game
"""
import os
import re
import statistics
import sys

MEX = ("armmex", "cormex", "legmex", "armamex", "coramex", "armmoho", "cormoho", "legmoho")
DEATH = re.compile(r"apex: unit-destroyed (\w+) .*?frame=(\d+) at=(\d+),(\d+)")
EXEC = re.compile(r"\[f=0*(\d+)\].*apex: exec t=(\d+) (\w+) #\d+ mex:\S* pick=(\d+) at=(\d+),(\d+)")
REBUILD = re.compile(r"apex: rebuild \w+ #\d+ spot=(\d+),(\d+) (.*)")
ARMY = re.compile(r"\[BARAI_ARMY\] frame=(\d+) team=(\d) n=(\d+)")
RESULT = re.compile(r"\[BARAI_RESULT\] reason=\S+ frame=(\d+) winners=(\S*)")
LAB = re.compile(r"\[([0-9.]+)m t\d\] apex: unit-destroyed (armlab|corlab|leglab|armvp|corvp|legvp)")
FRAME = re.compile(r"\[f=0*(\d+)\]")
NEAR = 64


def logs_under(paths):
    for p in paths:
        if os.path.isfile(p):
            yield p
            continue
        for root, _dirs, files in os.walk(p):
            if "infolog.txt" in files:
                yield os.path.join(root, "infolog.txt")


def analyse(path):
    deaths, execs, rebuilds, army, labs = [], [], {}, {}, []
    result = None
    us = None          # our team id: the `t=` of our own exec lines (S16: never the spec index)
    last_frame = 0
    with open(path, encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            mf = FRAME.search(ln)
            if mf:
                last_frame = max(last_frame, int(mf.group(1)))
            m = DEATH.search(ln)
            if m and m.group(1) in MEX:
                deaths.append((int(m.group(2)) / 1800.0, int(m.group(3)), int(m.group(4))))
                continue
            m = EXEC.search(ln)
            if m:
                if us is None:
                    us = int(m.group(2))
                if int(m.group(2)) == us:
                    execs.append((int(m.group(1)) / 1800.0, m.group(3), int(m.group(4)),
                                  int(m.group(5)), int(m.group(6))))
                continue
            m = REBUILD.search(ln)
            if m:
                rebuilds.setdefault((int(m.group(1)), int(m.group(2))), []).append(m.group(3))
                continue
            m = ARMY.search(ln)
            if m:
                army[(int(m.group(1)), int(m.group(2)))] = int(m.group(3))
                continue
            m = LAB.search(ln)
            if m:
                labs.append(float(m.group(1)))
                continue
            m = RESULT.search(ln)
            if m:
                result = (int(m.group(1)) / 1800.0, m.group(2))
    rows = []
    end_min = last_frame / 1800.0
    for t, x, z in deaths:
        later = [e for e in execs if e[0] > t and abs(e[3] - x) <= NEAR and abs(e[4] - z) <= NEAR]
        lag = (later[0][0] - t) if later else None
        who = f"{later[0][1]} pick={later[0][2]}" if later else "-"
        priced = [r for k, v in rebuilds.items() if abs(k[0] - x) <= NEAR and abs(k[1] - z) <= NEAR for r in v]
        late = (lag is None) and (end_min - t < 2.0)   # no time left to re-order: not a refusal
        rows.append((t, x, z, lag, who, priced[-1] if priced else "", late))
    return rows, army, labs, result, (us if us is not None else 0)


def main(argv):
    paths = argv[1:] or ["matches"]
    lags, never, total = [], 0, 0
    army_us, army_them = {6: [], 10: [], 14: []}, {6: [], 10: [], 14: []}
    late_n = 0
    for log in sorted(logs_under(paths)):
        rows, army, labs, result, us = analyse(log)
        name = os.path.relpath(os.path.dirname(log))
        res = f"end {result[0]:.1f}m winners={result[1]}" if result else "no result"
        lab = f"lab died {labs[0]:.1f}m" if labs else "lab alive"
        print(f"== {name}: {len(rows)} mex deaths, {res}, {lab}, we are team {us}")
        for t, x, z, lag, who, priced, late in rows:
            if late:
                late_n += 1
                s = "late (game ended)"
            elif lag is None:
                total += 1
                never += 1
                s = "NEVER"
            else:
                total += 1
                lags.append(lag)
                s = f"+{lag:4.1f} min by {who}"
            extra = f"   [{priced}]" if priced else ""
            print(f"   {t:5.1f}m  {x:4d},{z:4d}  {s}{extra}")
        for minute in army_us:
            f = minute * 1800
            if (f, us) in army:
                army_us[minute].append(army[(f, us)])
            if (f, 1 - us) in army:
                army_them[minute].append(army[(f, 1 - us)])
    print(f"         (late deaths with under 2 min of game left, excluded: {late_n})")
    print()
    print(f"SUMMARY  deaths={total}  never re-ordered={never}"
          f"  median lag={statistics.median(lags):.1f} min" if lags else f"SUMMARY  deaths={total}  never={never}")
    if lags:
        print(f"         lag quartiles={sorted(lags)[len(lags)//4]:.1f}/{statistics.median(lags):.1f}/{sorted(lags)[3*len(lags)//4]:.1f}"
              f"  over 2 min={sum(1 for l in lags if l > 2)}")
    for minute in army_us:
        if army_us[minute]:
            print(f"         army n @{minute}m  us median {statistics.median(army_us[minute]):.0f}"
                  f"  them median {statistics.median(army_them[minute]):.0f}" if army_them[minute] else "")


if __name__ == "__main__":
    main(sys.argv)
