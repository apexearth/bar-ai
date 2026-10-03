#!/usr/bin/env python3
"""Every seat of a team game, side by side: does each player scale, or only one?

    python tools/seats.py <match-dir> [<match-dir> ...] [--at 8,12,16,20,24]

Per engine team at each minute: metal income (m/s, over the minute before),
energy income, energy wasted %, extractors standing (T2 of them; finished minus
destroyed -- BARAI_STATS mex= only counts up), T2 start
minute, and cumulative metal built split army / eco / defence / build power.
Our eco seat (the team whose `apex: eco-status` says growing=1 most often) is
marked E. With several matches, the last block is the median per side and
seat kind (us-normal, us-eco, them) -- the number the scaling work moves.

Sources, all in the infolog: [BARAI_WASTE] (cumulative mMade/eMade/eWaste,
once a minute), [BARAI_STATS] (cumulative spend, mex, t2Mex, techStart, every
2 minutes), [BARAI_BUILD]/[BARAI_PROD] (team -> ally).
"""
from __future__ import annotations

import re
import statistics
import sys
from pathlib import Path

FPM = 1800
WASTE_RE = re.compile(r"\[BARAI_WASTE\] frame=(\d+) team=(\d+) mWaste=([\d.]+) mMade=([\d.]+) eWaste=([\d.]+) eMade=([\d.]+)")
STATS_RE = re.compile(r"\[BARAI_STATS\] team=(\d+) ally=(\d+) \S+ frame=(\d+) (.*)")
ALLY_RE = re.compile(r"\[BARAI_(?:BUILD|PROD)\] team=(\d+) ally=(\d+)")
BUILD_RE = re.compile(r"\[BARAI_BUILD\] team=(\d+) ally=\d+ frame=(\d+) min=[\d.]+ unit=(\S+)")
DEATH_RE = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\S+) .*? built=1")
MEX = re.compile(r"mex|moho|uwmme")
T2MEX = re.compile(r"moho|uwmme")
ECO_RE = re.compile(r"eco-status team=(\d+) growing=(\d)")


def kv(s: str) -> dict:
    out = {}
    for tok in s.split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            try:
                out[k] = float(v)
            except ValueError:
                pass
    return out


def load(d: Path):
    text = (d / "infolog.txt").read_text(encoding="utf8", errors="ignore")
    ally = {}
    for m in ALLY_RE.finditer(text):
        ally.setdefault(int(m.group(1)), int(m.group(2)))
    waste = {}   # team -> {minute: (mMade, eMade, eWaste)}
    for m in WASTE_RE.finditer(text):
        f, t = int(m.group(1)), int(m.group(2))
        if f % FPM == 0:
            waste.setdefault(t, {})[f // FPM] = (float(m.group(4)), float(m.group(6)), float(m.group(5)))
    stats = {}   # team -> {minute: dict}
    for m in STATS_RE.finditer(text):
        t, f = int(m.group(1)), int(m.group(3))
        ally.setdefault(t, int(m.group(2)))
        stats.setdefault(t, {})[f // FPM] = kv(m.group(4))
    # Standing extractors per team: finished minus destroyed, as events by frame.
    # (BARAI_STATS mex= only ever counts up -- it is extractors BUILT.)
    mexev = {}
    for m in BUILD_RE.finditer(text):
        if MEX.search(m.group(3)):
            mexev.setdefault(int(m.group(1)), []).append((int(m.group(2)), 1, bool(T2MEX.search(m.group(3)))))
    for m in DEATH_RE.finditer(text):
        if MEX.search(m.group(3)):
            mexev.setdefault(int(m.group(2)), []).append((int(m.group(1)), -1, bool(T2MEX.search(m.group(3)))))
    for t, ev in mexev.items():
        ev.sort()
        st = stats.setdefault(t, {})
        for minute in range(0, 121):
            f = minute * FPM
            n = sum(d for fr, d, _ in ev if fr <= f)
            n2 = sum(d for fr, d, up in ev if fr <= f and up)
            st.setdefault(minute, {})["standMex"] = n
            st[minute]["standT2"] = n2
    grow = {}
    for m in ECO_RE.finditer(text):
        t = int(m.group(1))
        grow[t] = grow.get(t, 0) + int(m.group(2))
    eco = max(grow, key=grow.get) if grow and max(grow.values()) > 0 else -1
    # "us" is the alliance that is not BARb: the one carrying apex lines' teams.
    us = ally.get(eco, 0) if eco >= 0 else 0
    return ally, waste, stats, eco, us


def row(t, minute, waste, stats):
    w = waste.get(t, {})
    a, b = w.get(minute), w.get(minute - 1)
    if a and b:
        mInc = a[0] - b[0]
        eInc = a[1] - b[1]
        eW = 100.0 * (a[2] - b[2]) / eInc if eInc > 0 else 0.0
        mInc /= 60.0
        eInc /= 60.0
    else:
        mInc = eInc = eW = float("nan")
    s = stats.get(t, {})
    sm = dict(s.get(minute - 1) or {})
    sm.update(s.get(minute) or {})
    ts = sm.get("techStart", -1)
    return {
        "mInc": mInc, "eInc": eInc, "eW": eW,
        "mex": sm.get("standMex", 0), "t2": sm.get("standT2", 0),
        "tech": (ts / FPM) if ts and ts > 0 else float("nan"),
        "army": sm.get("mArmy", 0) / 1000, "eco": sm.get("mEco", 0) / 1000,
        "def": sm.get("mDefence", 0) / 1000, "bp": sm.get("mBP", 0) / 1000,
    }


COLS = ("mInc", "eInc", "eW", "mex", "t2", "tech", "army", "eco", "def", "bp")
HDR = "  seat     m/s    E/s  eW%  mex  t2  T2@  | army   eco   def    bp (k metal, cumulative)"


def fmt(tag, r):
    def n(x, w, p=0):
        return f"{x:{w}.{p}f}" if x == x else " " * (w - 1) + "-"
    return (f"  {tag:<6} {n(r['mInc'], 6)} {n(r['eInc'], 6)} {n(r['eW'], 4)} {n(r['mex'], 4)} {n(r['t2'], 3)} "
            f"{n(r['tech'], 4, 1)}  | {n(r['army'], 5, 1)} {n(r['eco'], 5, 1)} {n(r['def'], 5, 1)} {n(r['bp'], 5, 1)}")


def main() -> int:
    args = sys.argv[1:]
    at = [8, 12, 16, 20, 24]
    if "--at" in args:
        i = args.index("--at")
        at = [int(x) for x in args[i + 1].split(",")]
        del args[i:i + 2]
    pooled = {}   # (minute, kind) -> list of rows
    for a in args:
        d = Path(a)
        ally, waste, stats, eco, us = load(d)
        teams = sorted(ally)
        print(f"== {d.name}  (E = our eco seat t{eco})")
        for minute in at:
            if not any(minute in waste.get(t, {}) for t in teams):
                continue
            print(f" minute {minute}")
            print(HDR)
            for side in (us, 1 - us):
                for t in teams:
                    if ally[t] != side:
                        continue
                    r = row(t, minute, waste, stats)
                    kind = "them" if side != us else ("us-eco" if t == eco else "us")
                    tag = ("E" if t == eco else ("t" if side == us else "b")) + str(t)
                    print(fmt(tag, r))
                    pooled.setdefault((minute, kind), []).append(r)
                print()
    if len(args) > 1:
        print(f"== median over {len(args)} matches")
        for minute in at:
            print(f" minute {minute}")
            print(HDR)
            for kind in ("us", "us-eco", "them"):
                rows = pooled.get((minute, kind), [])
                if not rows:
                    continue
                med = {c: statistics.median([r[c] for r in rows if r[c] == r[c]] or [float("nan")]) for c in COLS}
                print(fmt(kind[:6], med) + f"   n={len(rows)}")
            print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
