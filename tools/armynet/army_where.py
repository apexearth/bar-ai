#!/usr/bin/env python3
"""Where a side's army stands and where its orders aim (issues/army-off-axis-corner.md): metal-time of armed mobile
units every 10 s from minute 5, on a 3 x 3 grid of the map, in two frames: the map as it is, and turned so the side's
own start is bottom-left and the enemy's top-right (x flipped when our start is on the right, z when it is at the
top). Orders: the standing order's point of units that have one (move / fight / attack / patrol). Grouped by map
size and start corner. With --corner, what the side's time in that turned-frame cell is made of: the standing
order's target (an enemy building or cluster, a metal spot, our own building, none), and whether anything alive of
theirs or ours stands within 800 (ground truth).

    python tools/armynet/army_where.py --mvr-log runtime/armynet/mvr-watch-g2.log --side model runtime/armynet/own-games/watch-g2
    python tools/armynet/army_where.py --who players --winners --top-quartile --limit 60 G:/bar-ai-archive/public-replays/recordings
"""
import argparse
import os
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import Game  # noqa: E402
from objectives_army import files, pick_sides  # noqa: E402

CLS_STATIC, CLS_COM, CLS_ARMY, CLS_AIR = 0, 2, 3, 4
STEP = 300
ORDER_CMDS = (10, 15, 16, 20)
NEAR_R = 800.0
SPOT_R = 300.0
OFF_LINE = 0.3   # far off the line: over this share of the start-to-start distance from it (contract "army off the line")


def cell3(x, z):
    return min(int(z * 3), 2) * 3 + min(int(x * 3), 2)


def read(path, who, top_q, winners, cut, mt, side, corner, per_team=False):
    g = Game(path, rng=np.random.default_rng(0))
    z = np.load(path)
    teams = {int(t[0]): (int(t[1]), bool(t[2]), float(t[3])) for t in z["teams"]}
    sides = pick_sides(g, teams, who, top_q, winners, cut)
    if side and mt is not None:
        sides = [s for s in sides if (s == teams[mt][0]) == (side == "model")]
    mx, mz = g.mapx, g.mapz
    com = g.ucls == CLS_COM
    start = {}
    for t in np.unique(g.uteam[com]):
        m = com & (g.uteam == t)
        j = int(np.argmin(g.frames[m]))
        start[int(t)] = (float(g.units[m][j, 4]), float(g.units[m][j, 5]))
    spots = np.asarray(g.spots, float).reshape(-1, 2)[:, :2] if len(g.spots) else np.zeros((0, 2))
    out = []
    subjects = [(al, t) for al in sides for t in sorted(teams) if teams[t][0] == al and t in start] if per_team \
        else [(al, None) for al in sides]
    for ally, team in subjects:
        own = [start[team]] if team is not None else [start[t] for t, v in teams.items() if v[0] == ally and t in start]
        foe = [start[t] for t, v in teams.items() if v[0] != ally and v[0] in g.allies and t in start]
        if not own or not foe:
            continue
        ox, oz = np.mean([p[0] for p in own]), np.mean([p[1] for p in own])
        ex_, ez_ = np.mean([p[0] for p in foe]), np.mean([p[1] for p in foe])
        lx_, lz_ = ex_ - ox, ez_ - oz
        L = float(np.hypot(lx_, lz_)) or 1.0
        fx, fz = ox > mx / 2, oz < mz / 2   # flip so our start is bottom-left (low x, high z)
        key = "%dx%d %s%s" % (mx, mz, "top" if oz < mz / 2 else "bottom", "-right" if ox > mx / 2 else "-left")
        if team is not None:
            key = "%s t%d %s %s" % (Path(path).stem[24:44], team, "ai" if teams[team][1] else "human", key)

        def turned(x, z_):
            xn, zn = x / mx, z_ / mz
            return (1 - xn if fx else xn), (1 - zn if fz else zn)
        rec = {"key": key, "abs": np.zeros(9), "turn": np.zeros(9), "ord_abs": np.zeros(9), "ord_turn": np.zeros(9),
               "corner": defaultdict(float), "off": 0.0, "tot": 0.0}
        for f in range(9000, int(g.frames.max()) + 1, STEP):
            rows = g.rows_at(f)
            if not len(rows):
                continue
            ru = g.units[rows]
            rcls, rally, rdef = g.ucls[rows], g.ually[rows], g.udef[rows]
            built = ru[:, 9] >= 1.0
            arm = (rally == ally) & built & np.isin(rcls, (CLS_ARMY, CLS_AIR)) & ((g.d_g[rdef] + g.d_a[rdef]) > 0)
            if team is not None:
                arm &= g.uteam[rows] == team
            alive_f = (rally != ally) & (rally >= 0) & built
            alive_o = (rally == ally) & built & ~arm
            for j in np.nonzero(arm)[0]:
                w = float(g.d_metal[rdef[j]]) * 10.0
                x, z_ = float(ru[j, 4]), float(ru[j, 5])
                rec["abs"][cell3(x / mx, z_ / mz)] += w
                tx_, tz_ = turned(x, z_)
                c = cell3(tx_, tz_)
                rec["turn"][c] += w
                off_ = abs((x - ox) * lz_ - (z_ - oz) * lx_) / L > OFF_LINE * L
                rec["tot"] += w
                rec["off"] += w if off_ else 0.0
                cmd, ttx, ttz = int(ru[j, 11]), float(ru[j, 12]), float(ru[j, 13])
                has = cmd in ORDER_CMDS and ttx >= 0
                if has:
                    rec["ord_abs"][cell3(ttx / mx, ttz / mz)] += w
                    rec["ord_turn"][cell3(*turned(ttx, ttz))] += w
                if (per_team and off_) or (not per_team and corner is not None and c == corner):
                    if not has:
                        why = "no order"
                    else:
                        bf = alive_f & (rcls == CLS_STATIC)
                        d2b = (ru[bf, 4] - ttx) ** 2 + (ru[bf, 5] - ttz) ** 2
                        d2s = (spots[:, 0] - ttx) ** 2 + (spots[:, 1] - ttz) ** 2 if len(spots) else np.zeros(0)
                        bo = alive_o & (rcls == CLS_STATIC)
                        d2o = (ru[bo, 4] - ttx) ** 2 + (ru[bo, 5] - ttz) ** 2
                        why = ("order at an enemy building" if len(d2b) and d2b.min() <= NEAR_R ** 2 else
                               "order at a metal spot" if len(d2s) and d2s.min() <= SPOT_R ** 2 else
                               "order at our building" if len(d2o) and d2o.min() <= NEAR_R ** 2 else
                               "order at open ground")
                    d2f = (ru[alive_f, 4] - x) ** 2 + (ru[alive_f, 5] - z_) ** 2
                    d2o2 = (ru[alive_o, 4] - x) ** 2 + (ru[alive_o, 5] - z_) ** 2
                    near = ("theirs near" if len(d2f) and d2f.min() <= NEAR_R ** 2 else
                            "ours near" if len(d2o2) and d2o2.min() <= NEAR_R ** 2 else "nothing near")
                    rec["corner"][(why, near)] += w
        out.append(rec)
    return out


def grid(v):
    t = v.sum() or 1.0
    return " / ".join(" ".join("%.2f" % (v[r * 3 + c] / t) for c in range(3)) for r in range(3))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("roots", nargs="+")
    ap.add_argument("--who", choices=("own", "players", "all"), default="all")
    ap.add_argument("--top-quartile", action="store_true")
    ap.add_argument("--winners", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--mvr-log", default="")
    ap.add_argument("--side", choices=("", "model", "rules"), default="")
    ap.add_argument("--corner", type=int, default=0, help="turned-frame cell to break down (0 = top-left)")
    ap.add_argument("--per-team", action="store_true", help="each seat apart (team games); breaks down its time far off the line")
    a = ap.parse_args()
    fs = files(a.roots)
    if a.limit:
        fs = fs[: a.limit]
    cut = -1e9
    if a.top_quartile:
        sk = [float(t[3]) for p in fs for t in np.load(p)["teams"] if not t[2] and t[3] >= 0]
        cut = float(np.percentile(sk, 75)) if sk else -1e9
    mt = {}
    for lg in filter(None, a.mvr_log.split(",")):
        for ln in open(lg, encoding="utf-8"):
            p = ln.split()
            if len(p) >= 7 and p[0] == "seed":
                mt[Path(p[6]).name] = int(p[3].lstrip("t"))
    by = defaultdict(lambda: {"n": 0, "abs": np.zeros(9), "turn": np.zeros(9), "ord_abs": np.zeros(9),
                              "ord_turn": np.zeros(9), "corner": defaultdict(float), "off": 0.0, "tot": 0.0})
    for p in fs:
        try:
            recs = read(p, a.who, a.top_quartile, a.winners, cut, mt.get(Path(p).stem), a.side, a.corner, a.per_team)
        except Exception as ex:  # noqa: BLE001
            print("skip", os.path.basename(p), type(ex).__name__, ex, file=sys.stderr)
            continue
        for r in recs:
            b = by[r["key"]]
            b["n"] += 1
            b["off"] += r["off"]
            b["tot"] += r["tot"]
            for k in ("abs", "turn", "ord_abs", "ord_turn"):
                b[k] += r[k]
            for k, v in r["corner"].items():
                b["corner"][k] += v
    print("3 x 3 shares, rows top / middle / bottom, columns left / middle / right; from minute 5, metal-time")
    for key, b in sorted(by.items()):
        print("== %s, %d side-games" % (key, b["n"]))
        print("   stands, map frame:    " + grid(b["abs"]))
        print("   stands, turned frame: " + grid(b["turn"]) + "   (ours bottom-left, theirs top-right)")
        print("   aims,   map frame:    " + grid(b["ord_abs"]))
        print("   aims,   turned frame: " + grid(b["ord_turn"]))
        print("   far off the line between the starts (over %.1f of their distance): %.3f of metal-time" % (
            OFF_LINE, b["off"] / (b["tot"] or 1)))
        ct = sum(b["corner"].values())
        if ct:
            print("   %s (%.3f of its metal-time): %s" % (
                "far off the line" if a.per_team else "in turned cell %d" % a.corner, ct / (b["turn"].sum() or 1),
                "; ".join("%s, %s %.2f" % (k[0], k[1], v / ct) for k, v in sorted(b["corner"].items(), key=lambda x: -x[1]))))


if __name__ == "__main__":
    main()
