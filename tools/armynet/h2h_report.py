#!/usr/bin/env python3
"""Head-to-head read: two army-model versions command the two sides of the same game (11-25: win-loss alone is not
enough; the battle is read per side).

    python tools/armynet/h2h_report.py runtime/armynet/h2h-<tag>.log

The log has "seed <s> t0 <name> t1 <name> <match dir>" lines (scratchpad h2h.sh). Per game and per version, from the
infolog: the result; the army trade (mobile metal killed / lost) and the army standing at 8/12/16/20/30 min
(BARAI_STATS); their buildings killed; the share of army units in the enemy's half (BARAI_ARMY positions along our
start -> their start) over 5-15 and 15-25 min; the commander's death minute. Each row is the same game seen from both
sides, so the per-seed difference is paired by construction.
"""
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

MARKS = (8, 12, 16, 20, 30)
STATS = re.compile(r"\[BARAI_STATS\] team=(\d+) .*?reason=periodic frame=(\d+) (.*)")
ARMY = re.compile(r"\[BARAI_ARMY\] frame=(\d+) team=(\d+) n=\d+ part=\S+ (.*)")
START = re.compile(r"\[BARAI_START\] team=(\d+) x=(-?\d+) z=(-?\d+)")
DEATH = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\w+) .*?built=1")


def read(match):
    stats = defaultdict(list)
    starts = {}
    fwd = defaultdict(lambda: defaultdict(list))   # team -> window -> per-snapshot share
    com = {}
    snaps = defaultdict(lambda: defaultdict(list))  # team -> frame -> [(x, z)]
    for ln in open(Path(match) / "infolog.txt", errors="replace"):
        if "[BARAI_" not in ln:
            continue
        m = STATS.search(ln)
        if m:
            kv = dict(p.split("=", 1) for p in m.group(3).split() if "=" in p)
            stats[int(m.group(1))].append((int(m.group(2)), kv))
            continue
        m = START.search(ln)
        if m:
            starts[int(m.group(1))] = (float(m.group(2)), float(m.group(3)))
            continue
        m = ARMY.search(ln)
        if m:
            for it in m.group(3).split():
                p = it.split(":")
                if len(p) >= 4 and not p[1].endswith("com"):
                    try:
                        snaps[int(m.group(2))][int(m.group(1))].append((float(p[2]), float(p[3])))
                    except ValueError:
                        pass
            continue
        m = DEATH.search(ln)
        if m and m.group(3).endswith("com") and int(m.group(2)) not in com:
            com[int(m.group(2))] = int(m.group(1)) / 1800.0
    teams = sorted(starts)
    for t in teams:
        others = [o for o in teams if o != t]
        if not others:
            continue
        (ax, az), (bx, bz) = starts[t], starts[others[0]]
        dx, dz = bx - ax, bz - az
        L2 = dx * dx + dz * dz or 1.0
        for fr, pts in snaps[t].items():
            mnt = fr / 1800.0
            w = "5-15" if 5 <= mnt < 15 else ("15-25" if 15 <= mnt < 25 else None)
            if w is None or not pts:
                continue
            share = sum(1 for x, z in pts if ((x - ax) * dx + (z - az) * dz) / L2 > 0.5) / len(pts)
            fwd[t][w].append(share)
    return stats, fwd, com


def at(rows, minute, key):
    best = None
    for fr, kv in rows:
        if fr <= minute * 1800 + 900:
            best = kv
    if best is None or key not in best:
        return None
    try:
        return float(best[key])
    except ValueError:
        return None


def side(stats, fwd, com, t):
    rows = sorted(stats[t])
    out = {}
    for mk in MARKS:
        k, l = at(rows, mk, "mKillMobile"), at(rows, mk, "mLostMobile")
        out["trade%d" % mk] = (k / l) if (k is not None and l) else None
        out["army%d" % mk] = at(rows, mk, "mArmy")
        out["bldkill%d" % mk] = at(rows, mk, "mKillStatic")
    for w in ("5-15", "15-25"):
        v = fwd[t].get(w, [])
        out["their_half_" + w] = sum(v) / len(v) if v else None
    out["com_dead_min"] = com.get(t)
    return out


def main():
    games = []
    for ln in open(sys.argv[1]):
        p = ln.split()
        if len(p) < 6:
            continue
        seed, n0, n1, d = int(p[1]), p[3], p[5], Path(p[6].replace("\\", "/")) if len(p) > 6 else None
        if d is None or not (d / "infolog.txt").exists():
            continue
        r = json.loads((d / "result.json").read_text()).get("result") or {}
        stats, fwd, com = read(d)
        games.append((seed, {n0: side(stats, fwd, com, 0), n1: side(stats, fwd, com, 1)},
                      {0: n0, 1: n1}, r))
    if not games:
        print("no finished games")
        return
    names = sorted({n for _, s, _, _ in games for n in s})
    a, b = names[0], names[-1]
    wins = defaultdict(int)
    print(f"{'seed':>4} {'winner':>8} {'min':>5}  per game: {a} vs {b}")
    for seed, s, tm, r in sorted(games):
        specs = r.get("winners") or []
        w = tm.get(specs[0]) if specs else None
        wins[w or "draw"] += 1
        print(f"{seed:>4} {str(w or 'draw'):>8} {r.get('game_minutes', 0):5.1f}  trade12 {s[a]['trade12'] or 0:.2f}/{s[b]['trade12'] or 0:.2f}"
              f"  trade20 {s[a]['trade20'] or 0:.2f}/{s[b]['trade20'] or 0:.2f}  their half 5-15 "
              f"{s[a]['their_half_5-15'] or 0:.2f}/{s[b]['their_half_5-15'] or 0:.2f}  com dead {s[a]['com_dead_min'] or '-'}/{s[b]['com_dead_min'] or '-'}")
    print("results:", dict(wins))
    keys = [k for k in games[0][1][a]]
    print(f"\n{'measure':22} {a:>9} {b:>9}  {a}>{b}")
    for k in keys:
        va = [s[a][k] for _, s, _, _ in games if s[a][k] is not None and s[b][k] is not None]
        vb = [s[b][k] for _, s, _, _ in games if s[a][k] is not None and s[b][k] is not None]
        if not va:
            continue
        better = sum(1 for x, y in zip(va, vb) if x > y)
        print(f"{k:22} {sum(va) / len(va):9.2f} {sum(vb) / len(vb):9.2f}  {better}/{len(va)}")


if __name__ == "__main__":
    main()
