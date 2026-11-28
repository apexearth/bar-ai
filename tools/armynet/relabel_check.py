#!/usr/bin/env python3
"""Step 3 check of todo/armynet-objectives.md, before any objective model: how many player orders map to an objective
the side could see, by hindsight, and which kinds of order they were.

    python tools/armynet/relabel_check.py [--winners] [--top-quartile] [--limit N] G:/bar-ai-archive/public-replays/recordings

One click per group (decisions sharing a group id), its first unit. The objectives listed at the click's frame, from
the side's own view (data.Game memory, moving enemies seen in the last FRESH_S):
    cluster   a known enemy building whose cluster (known enemy building metal within CL_R) clears FLOOR
    lone      a known enemy building below it (an extractor, a turret)
    spot      a metal spot in their half (depth > 0.5) with no building of ours within SPOT_R (likely theirs)
    base      a presumed enemy base: their start, while nothing of theirs is known within BASE_R
    army      a moving enemy seen in the last FRESH_S
    threat    one of our buildings with a fresh enemy within THREAT_R
    join      another of our armed units (not in this click)
The click maps to the objective class its unit spends the most time within reach of (weapon range + REACH_PAD) over
the next HORIZON_S (hindsight), at least DWELL_S, ties by the order above, "join" only when nothing else holds it;
"hold" when it never moves HOLD_D from where it stood and maps
nothing else; unmapped otherwise. The unmapped share says which candidates are missing.
"""
from __future__ import annotations

import argparse
import os
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import Game  # noqa: E402
from objectives_army import CLS_AIR, CLS_ARMY, CLS_COM, CLS_STATIC, FLOOR, pick_sides  # noqa: E402
from objectives_offline import files  # noqa: E402

FRESH_S = 30.0
CL_R = 800.0
BASE_R = 1500.0
SPOT_R = 300.0
THREAT_R = 1000.0
REACH_PAD = 200.0
HORIZON_S = 180.0
HOLD_D = 300.0
DWELL_S = 10.0
ORDER = ("cluster", "lone", "spot", "base", "army", "threat", "join")
KIND_NAMES = {0: "stop", 1: "move", 2: "fight", 3: "attack", 4: "area", 5: "patrol"}


def read_game(path, top_q, winners, skill_cut, every, shuffle=False):
    g = Game(path, rng=np.random.default_rng(0))
    z = np.load(path)
    teams = {int(t[0]): (int(t[1]), bool(t[2]), float(t[3])) for t in z["teams"]}
    sides = pick_sides(g, teams, "players", top_q, winners, skill_cut)
    d = g.decisions
    if not sides or not len(d):
        return []
    com = g.ucls == CLS_COM
    start = {}
    for t in np.unique(g.uteam[com]):
        m = com & (g.uteam == t)
        j = int(np.argmin(g.frames[m]))
        start[int(t)] = np.array([g.units[m][j, 4], g.units[m][j, 5]], float)
    spots = g.spots if len(g.spots) else np.zeros((0, 2))
    # each unit's track, for hindsight
    order = np.lexsort((g.frames, g.uid))
    tu, tf = g.uid[order], g.frames[order]
    out = []
    rng = np.random.default_rng(1)
    seen_groups = set()
    for i in np.argsort(d[:, 0], kind="stable"):
        f, t, uid, kind, gid = int(d[i, 0]), int(d[i, 2]), int(d[i, 3]), int(d[i, 4]), int(d[i, 7])
        if t not in teams or teams[t][0] not in sides:
            continue
        if gid >= 0:
            if (t, gid) in seen_groups:
                continue
            seen_groups.add((t, gid))
        if every > 1 and (len(out) + i) % every:
            continue
        ally = teams[t][0]
        k = g.allies.index(ally)
        uid_t, f_t = uid, f
        if shuffle:
            same = np.nonzero(d[:, 2] == t)[0]
            j_ = int(rng.choice(same))
            uid_t, f_t = int(d[j_, 3]), int(d[j_, 0])
        a, b = np.searchsorted(tu, [uid_t, uid_t + 1])
        if a == b:
            continue
        rows = order[a:b]
        fr = tf[a:b]
        lo = int(np.searchsorted(fr, f_t, "left"))
        hi = int(np.searchsorted(fr, f_t + HORIZON_S * 30, "right"))
        if lo >= hi:
            continue
        track = g.units[rows[lo:hi]]
        tfr = fr[lo:hi]
        df = int(g.udef[rows[lo]])
        reach = float(g.d_range[df]) + REACH_PAD
        ux, uz = float(track[0, 4]), float(track[0, 5])
        mx, mz, md, mage, mst, *_ = g._memory(k, f - f % 30, ally)
        fresh = ~mst & (mage <= FRESH_S)
        bx, bz, bm = mx[mst], mz[mst], g.d_metal[md[mst]]
        clm = ((bx[:, None] - bx[None, :]) ** 2 + (bz[:, None] - bz[None, :]) ** 2 <= CL_R * CL_R) @ bm if len(bx) \
            else np.zeros(0)
        cand = {"cluster": (bx[clm >= FLOOR], bz[clm >= FLOOR]), "lone": (bx[clm < FLOOR], bz[clm < FLOOR]),
                "army": (mx[fresh], mz[fresh])}
        rws = g.rows_at(f - f % 10)
        ru = g.units[rws]
        mine = (g.ually[rws] == ally) & (ru[:, 9] >= 1.0)
        ob = mine & (g.ucls[rws] == CLS_STATIC)
        ox, oz = ru[ob, 4], ru[ob, 5]
        if len(spots):
            o_ = np.array([((ox - s[0]) ** 2 + (oz - s[1]) ** 2 <= SPOT_R ** 2).any() if len(ox) else False
                           for s in spots])
            foe_t = [tt for tt, v in teams.items() if v[0] != ally and tt in start]
            own_t = [tt for tt, v in teams.items() if v[0] == ally and tt in start]
            if foe_t and own_t:
                o0, e0 = np.mean([start[x] for x in own_t], 0), np.mean([start[x] for x in foe_t], 0)
                ax = e0 - o0
                dep = ((spots[:, 0] - o0[0]) * ax[0] + (spots[:, 1] - o0[1]) * ax[1]) / (float(ax @ ax) or 1.0)
                sel = (dep > 0.5) & ~o_
                cand["spot"] = (spots[sel, 0], spots[sel, 1])
            pres = [start[x] for x in foe_t if not len(bx) or not
                    ((bx - start[x][0]) ** 2 + (bz - start[x][1]) ** 2 <= BASE_R ** 2).any()]
            if pres:
                cand["base"] = (np.array([p[0] for p in pres]), np.array([p[1] for p in pres]))
        if len(ox) and len(cand["army"][0]):
            thr = np.array([((cand["army"][0] - x) ** 2 + (cand["army"][1] - z_) ** 2 <= THREAT_R ** 2).any()
                            for x, z_ in zip(ox, oz)])
            cand["threat"] = (ox[thr], oz[thr])
        grp = set(d[(d[:, 2] == t) & (d[:, 7] == gid), 3].astype(int).tolist()) if gid >= 0 else {uid}
        ja = mine & np.isin(g.ucls[rws], (CLS_ARMY, CLS_AIR)) & ~np.isin(g.uid[rws], list(grp))
        cand["join"] = (ru[ja, 4], ru[ja, 5])
        # dwell: seconds of the horizon the unit spends within reach of each class (samples are 10 frames apart)
        dt = np.diff(np.append(tfr, tfr[-1] + 10)) / 30.0
        dwell = {}
        for name in ORDER:
            cx, cz = cand.get(name, (np.zeros(0), np.zeros(0)))
            if not len(cx):
                continue
            r = BASE_R if name == "base" else reach
            near = ((track[:, 4][:, None] - cx[None, :]) ** 2 + (track[:, 5][:, None] - cz[None, :]) ** 2 <= r * r).any(1)
            dwell[name] = float(dt[near].sum())
        best = max((n_ for n_ in ORDER if n_ != "join" and dwell.get(n_, 0.0) >= DWELL_S),
                   key=lambda n_: (dwell[n_], -ORDER.index(n_)), default=None)
        if best is None and dwell.get("join", 0.0) >= DWELL_S:
            best = "join"
        moved = float(np.hypot(track[:, 4] - ux, track[:, 5] - uz).max())
        lab = best or ("hold" if moved < HOLD_D else "unmapped")
        out.append((lab, KIND_NAMES.get(kind, str(kind)), float(g.d_metal[df])))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("roots", nargs="+")
    ap.add_argument("--winners", action="store_true")
    ap.add_argument("--top-quartile", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--every", type=int, default=1, help="read one click in N")
    ap.add_argument("--shuffle", action="store_true", help="baseline: each click scored on a random other click's track (same side)")
    a = ap.parse_args()
    fs = files(a.roots)[: a.limit or None]
    skill_cut = -1e9
    if a.top_quartile:
        sk = []
        for p in fs:
            try:
                sk += [float(t[3]) for t in np.load(p)["teams"] if not t[2] and t[3] >= 0]
            except Exception:  # noqa: BLE001
                pass
        skill_cut = float(np.percentile(sk, 75)) if sk else -1e9
    R, games = [], 0
    for p in fs:
        try:
            o = read_game(p, a.top_quartile, a.winners, skill_cut, a.every, a.shuffle)
        except Exception as ex:  # noqa: BLE001
            print("skip", os.path.basename(p), type(ex).__name__, ex, file=sys.stderr)
            continue
        if o:
            games += 1
            R += o
    if not R:
        print("no clicks")
        return
    labs = ORDER + ("hold", "unmapped")
    n = len(R)
    print("games %d  clicks %d" % (games, n))
    by = defaultdict(int)
    for lab, _k, _w in R:
        by[lab] += 1
    print("mapped %.3f (hold %.3f, unmapped %.3f)" % (1 - (by["unmapped"] + by["hold"]) / n, by["hold"] / n, by["unmapped"] / n))
    print("by objective  " + "  ".join("%s %.3f" % (l_, by[l_] / n) for l_ in labs))
    kinds = sorted({k_ for _l, k_, _w in R}, key=lambda s: -sum(1 for x in R if x[1] == s))
    print("%-9s %7s  %s" % ("kind", "share", "  ".join("%8s" % l_ for l_ in labs)))
    for kd in kinds:
        rk = [x for x in R if x[1] == kd]
        print("%-9s %7.3f  %s" % (kd, len(rk) / n, "  ".join("%8.3f" % (sum(1 for x in rk if x[0] == l_) / len(rk))
                                                             for l_ in labs)))


if __name__ == "__main__":
    main()
