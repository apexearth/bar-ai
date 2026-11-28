"""After breaking a defensive line, does the army go and see what is behind it? (his 11-24: "they killed the entire front
line and then they couldn't see anymore ... it should know that I just destroyed a defensive position, I should
really go see what's behind it")

A break: a team's units kill 3+ enemy static guns within 800 of each other inside 60 s. Behind = away from the
breaking team's start, through the broken line. For each break, the breaking team's army units within 1,200 of the
line then are followed for 120 s: how far past the line they go (mean, and the furthest), whether any of them gets
1,000 past it, and whether enemy buildings stood behind it (ground truth, within 2,500 behind and 1,500 aside).

    python tools/breakthrough.py <replay-orders dir> [...]    (orders.txt.gz from tools/replay_orders.py)
"""
import gzip
import sys
from array import array
from collections import defaultdict
from pathlib import Path

import numpy as np

WIN, MIN_GUNS, LINE_R, NEAR_R, FOLLOW = 60 * 30, 3, 800.0, 1200.0, (30, 60, 120)


def load(d):
    defs, team_ally, is_ai = {}, {}, {}
    cols = {k: array("d") for k in ("f", "uid", "def", "team", "x", "z")}
    kills = []
    with gzip.open(Path(d) / "orders.txt.gz", "rt", errors="replace") as fh:
        for ln in fh:
            t = ln[:2]
            if t == "U ":
                p = ln.split(None, 7)
                for k, v in zip(("f", "uid", "def", "team", "x", "z"), p[1:7]):
                    cols[k].append(float(v))
            elif t == "K ":
                p = ln.split()
                kills.append((int(p[1]), int(p[3]), int(p[4]), float(p[5]), float(p[6]), int(p[9])))
            elif t == "D ":
                p = ln.split()
                defs[int(p[1])] = (p[3], float(p[4]), float(p[6]), float(p[8]), p[2])  # class, metal, speed, gdps, name
            elif t == "T ":
                p = ln.split()
                team_ally[int(p[1])] = int(p[2])
                is_ai[int(p[1])] = p[3] == "true"
    u = {k: np.frombuffer(v, np.float64) for k, v in cols.items()}
    return defs, team_ally, is_ai, u, kills


def breaks(defs, team_ally, kills):
    """(frame, team, x, z, guns) for each line broken, one per cluster of gun kills."""
    by_team = defaultdict(list)
    for f, defid, team, x, z, ateam in kills:
        d = defs.get(defid)
        if ateam < 0 or d is None or team_ally.get(ateam) == team_ally.get(team):
            continue
        if d[2] == 0.0 and d[3] > 0.0:
            by_team[ateam].append((f, x, z, team))
    out = []
    for t, ks in by_team.items():
        ks.sort()
        used = set()
        for i, (f, x, z, _) in enumerate(ks):
            if i in used:
                continue
            grp = [j for j in range(i, len(ks)) if ks[j][0] - f <= WIN and (ks[j][1] - x) ** 2 + (ks[j][2] - z) ** 2 <= LINE_R ** 2]
            if len(grp) >= MIN_GUNS:
                used.update(grp)
                owner = max(set(ks[j][3] for j in grp), key=[ks[j][3] for j in grp].count)
                out.append((ks[grp[-1]][0], t, float(np.mean([ks[j][1] for j in grp])), float(np.mean([ks[j][2] for j in grp])),
                            len(grp), owner))
    return out


def at(u, frame, tol=45):
    """the row slice of the latest sampled second at or before frame (u sorted by frame)"""
    fs = u["f"]
    k = int(np.searchsorted(fs, frame, "right")) - 1
    if k < 0 or fs[k] < frame - tol:
        return slice(0, 0)
    return slice(int(np.searchsorted(fs, fs[k], "left")), k + 1)


def span(u, a, b):
    fs = u["f"]
    return slice(int(np.searchsorted(fs, a, "left")), int(np.searchsorted(fs, b, "right")))


def main(dirs):
    rows = []
    for d in dirs:
        try:
            defs, ta, ai, u, kills = load(d)
        except (OSError, EOFError):
            continue
        o = np.argsort(u["f"], kind="stable")
        u = {k: v[o] for k, v in u.items()}
        speed = {k: v[2] for k, v in defs.items()}
        gdps = {k: v[3] for k, v in defs.items()}
        metal = {k: v[1] for k, v in defs.items()}
        dd = np.array([speed.get(int(v), 0.0) for v in u["def"]])
        army = np.array([gdps.get(int(v), 0.0) > 0 for v in u["def"]]) & (dd > 0)
        static = dd == 0
        ally_of = np.array([ta.get(int(v), -1) for v in u["team"]])
        start = {}
        for t in ta:
            m = u["team"] == t
            if m.any():
                f0 = u["f"][m].min()
                mm = m & (u["f"] == f0)
                start[t] = (u["x"][mm].mean(), u["z"][mm].mean())
        for f, t, x, z, guns, owner in breaks(defs, ta, kills):
            # behind = toward the start of the team whose guns these were; the breaker's own start if that is the line
            home = start.get(owner)
            ax = np.array([home[0] - x, home[1] - z]) if home is not None else np.zeros(2)
            if np.hypot(*ax) < 300.0 and t in start:
                ax = np.array([x - start[t][0], z - start[t][1]])
            if np.hypot(*ax) < 1.0:
                continue
            ax /= np.hypot(*ax)
            s0 = at(u, f)
            mine = army[s0] & (u["team"][s0] == t) & (np.hypot(u["x"][s0] - x, u["z"][s0] - z) <= NEAR_R)
            uids = np.unique(u["uid"][s0][mine])
            if not len(uids):
                continue
            # the odds there: our army metal near the line against theirs within 1,500 of it (ground truth)
            theirs_m = army[s0] & (ally_of[s0] != ta.get(t)) & (np.hypot(u["x"][s0] - x, u["z"][s0] - z) <= 1500.0)
            ours = float(sum(metal.get(int(v), 0.0) for v in u["def"][s0][mine]))
            theirs = float(sum(metal.get(int(v), 0.0) for v in u["def"][s0][theirs_m]))
            sb = span(u, f - 330, f)
            bm = static[sb] & (ally_of[sb] != ta.get(t))
            bu, bi = np.unique(u["uid"][sb][bm], return_index=True)
            dx, dz = u["x"][sb][bm][bi] - x, u["z"][sb][bm][bi] - z
            along, aside = dx * ax[0] + dz * ax[1], np.abs(-dx * ax[1] + dz * ax[0])
            behind = int(((along > 0) & (along <= 2500) & (aside <= 1500)).sum())
            res = {}
            for s in FOLLOW:
                sl = at(u, f + s * 30)
                later = np.isin(u["uid"][sl], uids)
                if not later.any():
                    res[s] = (np.nan, np.nan, 0)
                    continue
                pr = (u["x"][sl][later] - x) * ax[0] + (u["z"][sl][later] - z) * ax[1]
                res[s] = (float(pr.mean()), float(pr.max()), int((pr >= 1000).any()))
            rows.append((Path(d).name[:16], t, ai.get(t, False), f // 1800, guns, len(uids), behind, res, ours, theirs))
    for r in rows:
        print("%s t%-2d %-5s min %2d guns %d units %3d (%5.0f m vs their %5.0f m) enemy buildings behind %3d | past the line, "
              "mean/max at 30 s %5.0f/%5.0f  60 s %5.0f/%5.0f  120 s %5.0f/%5.0f  1000+ by 120 s %d" % (
                  r[0], r[1], "AI" if r[2] else "human", r[3], r[4], r[5], r[8], r[9], r[6], *r[7][30][:2], *r[7][60][:2],
                  *r[7][120][:2], r[7][120][2]))
    for who, open_ in ((True, True), (True, False), (False, True), (False, False)):
        # open: our army there at least twice theirs, so nothing on the ground forced a turn
        sel = [r for r in rows if r[2] == who and (r[8] >= 2 * r[9]) == open_]
        if not sel:
            continue
        print("%s:" % ("open (ours >= 2x theirs)" if open_ else "contested"), end=" ")
        def med(s, i):
            v = [r[7][s][i] for r in sel if not np.isnan(r[7][s][i])]
            return float(np.median(v)) if v else float("nan")
        print("%-5s breaks %d (with enemy buildings behind %d): median mean-advance 30/60/120 s %.0f/%.0f/%.0f, "
              "median furthest %.0f/%.0f/%.0f, a unit 1000+ past by 120 s in %.0f%%" % (
                  "AI" if who else "human", len(sel), sum(r[6] > 0 for r in sel), med(30, 0), med(60, 0), med(120, 0),
                  med(30, 1), med(60, 1), med(120, 1), 100 * np.mean([r[7][120][2] for r in sel])))


if __name__ == "__main__":
    main(sys.argv[1:])
