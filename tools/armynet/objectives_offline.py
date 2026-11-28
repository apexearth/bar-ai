#!/usr/bin/env python3
"""Step 2 of todo/armynet-objectives.md: the offline army instrument, from recorded games (no engine).

    python tools/armynet/objectives_offline.py --who own  runtime/armynet/own-games/selfplay-r1
    python tools/armynet/objectives_offline.py --who players [--top-quartile] [--winners] G:/bar-ai-archive/public-replays/recordings
    python tools/armynet/objectives_offline.py --who all <dir with rules-army games>

Every unit order of the chosen teams is read against what that side saw or remembered at the order's frame (data.Game's
own memory: no hidden information), and three numbers come out per column:
  advance  orders given while our army metal is over ADV_RATIO x theirs (seen + remembered) and an enemy building is
           known or their base presumed: the share aimed within reach (the unit's weapon range + REACH_PAD) of an enemy building or extractor, or within
           BASE_R of a presumed base. The presumed base is the enemy start (their commander's first position, which the
           start boxes make public) while no enemy building is known.
  aimless  the share of all orders whose target has no enemy building known, or moving enemy seen in the last FRESH_S,
           within reach, no building of ours
           within reach (nothing to guard), no metal spot within SPOT_R and no presumed base within BASE_R.
  advance and aimless weigh each order by its unit's metal (order mass); flips count orders.
  flips    a unit's two orders within FLIP_S seconds whose targets lie over FLIP_D apart while the enemy it knows of
           within KNOW_R of the unit did not change: the share of order pairs that flip with nothing new in view.
"""
from __future__ import annotations

import argparse
import glob
import os
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import Game  # noqa: E402

ADV_RATIO = 1.5
REACH_PAD = 200.0   # beyond the ordered unit's own weapon range: the approach
SPOT_R = 100.0      # an order onto a metal spot
BASE_R = 1500.0
FLIP_S = 30.0
FLIP_D = 800.0
KNOW_R = 1500.0
FRESH_S = 30.0
CLS_STATIC, CLS_COM, CLS_ARMY, CLS_AIR = 0, 2, 3, 4
KEYS = ("orders", "adv_n", "adv_hit", "n", "aimless", "pairs", "flips", "by_enemy", "by_guard", "by_spot", "by_base")


def files(roots):
    out = []
    for r in roots:
        p = Path(r)
        out += sorted(glob.glob(str(p / "*.npz"))) + sorted(glob.glob(str(p / "*" / "*.npz")))
    return out


def near(px, pz, xs, zs, r):
    if not len(xs):
        return False
    return bool((((xs - px) ** 2 + (zs - pz) ** 2) <= r * r).any())


def read_game(path, who, top_q, winners, skill_cut, shuffle=False):
    g = Game(path, rng=np.random.default_rng(0))
    d = g.decisions
    if not len(d):
        return None
    teams = {int(t[0]): (int(t[1]), bool(t[2]), float(t[3])) for t in np.load(path)["teams"]}
    res = {}
    for t in np.unique(d[:, 2]).astype(int):
        r = g.result[d[:, 2] == t]
        res[t] = int(r[0]) if len(r) else -1
    pick = []
    for t, (ally, is_ai, skill) in teams.items():
        if who == "players" and is_ai:
            continue
        if top_q and not (skill >= skill_cut):
            continue
        if winners and res.get(t, -1) != 1:
            continue
        if ally in g.allies:
            pick.append(t)
    if not pick:
        return None
    # presumed bases: each team's commander at its first sample (the start boxes are public)
    first = {}
    com = g.ucls == CLS_COM
    for t in np.unique(g.uteam[com]):
        m = com & (g.uteam == t)
        j = int(np.argmin(g.frames[m]))
        first[int(t)] = (float(g.units[m][j, 4]), float(g.units[m][j, 5]))
    spots = g.spots if len(g.spots) else np.zeros((0, 2), np.float32)
    msize = np.load(path)["map"].astype(float)
    rng = np.random.default_rng(1)
    stats = dict.fromkeys(KEYS, 0)
    mem_cache = {}
    last_by_uid = {}
    order = np.argsort(d[:, 0], kind="stable")
    for i in order:
        t = int(d[i, 2])
        if t not in pick:
            continue
        f, uid, tx, tz = int(d[i, 0]), int(d[i, 3]), float(d[i, 5]), float(d[i, 6])
        if shuffle and tx >= 0:
            tx, tz = float(rng.uniform(0, msize[0])), float(rng.uniform(0, msize[1]))
        if tx < 0 or tz < 0:
            continue
        ally = teams[t][0]
        k = g.allies.index(ally)
        fb = f - f % 30
        key = (k, fb)
        if key not in mem_cache:
            mx, mz, md, mage, mst, _vx, _vz = g._memory(k, fb, ally)
            fresh = mst | (mage <= FRESH_S)  # a moving enemy counts while its sighting is fresh; buildings stay
            mx, mz, md, mage, mst = mx[fresh], mz[fresh], md[fresh], mage[fresh], mst[fresh]
            rows = g.rows_at(fb)
            ru = g.units[rows]
            rcls = g.ucls[rows]
            rally = g.ually[rows]
            built = ru[:, 9] >= 1.0
            ours = rally == ally
            our_army = float(g.d_metal[g.udef[rows][ours & np.isin(rcls, (CLS_ARMY, CLS_AIR)) & built]].sum())
            mob = ~mst & np.isin(g.d_cls[md], (CLS_ARMY, CLS_AIR))
            their_army = float(g.d_metal[md[mob]].sum())
            bx, bz = mx[mst], mz[mst]
            ob = ours & (rcls == CLS_STATIC) & built
            enemy_teams = [tt for tt, (aa, _a, _s) in teams.items() if aa != ally]
            base = [first[tt] for tt in enemy_teams if tt in first] if not len(bx) else []
            ex_spots = spots[[near(s[0], s[1], bx, bz, SPOT_R) for s in spots]] if len(bx) and len(spots) else np.zeros((0, 2))
            mem_cache[key] = (mx, mz, our_army, their_army, bx, bz, ru[ob, 4], ru[ob, 5], base, ex_spots,
                              dict(zip(g.uid[rows].tolist(),
                                       zip(ru[:, 4].tolist(), ru[:, 5].tolist(), g.udef[rows].tolist()))))
        mx, mz, our_army, their_army, bx, bz, ox, oz, base, ex_spots, pos = mem_cache[key]
        up = pos.get(uid)
        if up is None:
            continue
        reach = float(g.d_range[up[2]]) + REACH_PAD
        w = float(g.d_metal[up[2]])  # order MASS: each order weighs its unit's metal
        stats["orders"] += 1
        stats["n"] += w
        at_base = any(((tx - b[0]) ** 2 + (tz - b[1]) ** 2) <= BASE_R * BASE_R for b in base)
        if our_army > ADV_RATIO * max(their_army, 1.0) and (len(bx) or base):
            stats["adv_n"] += w
            if near(tx, tz, bx, bz, reach) or (len(ex_spots) and near(tx, tz, ex_spots[:, 0], ex_spots[:, 1], reach)) \
                    or at_base:
                stats["adv_hit"] += w
        why = ("enemy" if near(tx, tz, mx, mz, reach) else "guard" if near(tx, tz, ox, oz, reach)
               else "spot" if (len(spots) and near(tx, tz, spots[:, 0], spots[:, 1], SPOT_R))
               else "base" if at_base else "")
        if why:
            stats["by_" + why] += w
        else:
            stats["aimless"] += w
        if True:
            known = int((((mx - up[0]) ** 2 + (mz - up[1]) ** 2) <= KNOW_R * KNOW_R).sum())
            prev = last_by_uid.get(uid)
            if prev is not None and (f - prev[0]) <= FLIP_S * 30:
                stats["pairs"] += 1
                if ((tx - prev[1]) ** 2 + (tz - prev[2]) ** 2) > FLIP_D * FLIP_D and known == prev[3]:
                    stats["flips"] += 1
            last_by_uid[uid] = (f, tx, tz, known)
    return stats


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("roots", nargs="+")
    ap.add_argument("--who", choices=("own", "players", "all"), default="all")
    ap.add_argument("--top-quartile", action="store_true", help="players: skill in the top quartile of the set")
    ap.add_argument("--winners", action="store_true", help="only teams that won the game")
    ap.add_argument("--limit", type=int, default=0, help="at most this many games")
    ap.add_argument("--shuffle", action="store_true", help="baseline: every target replaced by a uniform random point on the map")
    a = ap.parse_args()
    fs = files(a.roots)
    if a.limit:
        fs = fs[: a.limit]
    skill_cut = -1e9
    if a.top_quartile:
        sk = []
        for p in fs:
            try:
                sk += [float(t[3]) for t in np.load(p)["teams"] if not t[2] and t[3] >= 0]
            except Exception:  # noqa: BLE001
                pass
        skill_cut = float(np.percentile(sk, 75)) if sk else -1e9
    tot = dict.fromkeys(KEYS, 0)
    games = 0
    for p in fs:
        try:
            s = read_game(p, a.who, a.top_quartile, a.winners, skill_cut, a.shuffle)
        except Exception as e:  # noqa: BLE001
            print("skip", os.path.basename(p), type(e).__name__, e, file=sys.stderr)
            continue
        if s is None:
            continue
        games += 1
        for k in tot:
            tot[k] += s[k]
    def sh(a_, b_):
        return (a_ / b_) if b_ else float("nan")
    print("games %d  orders %d  skill cut %s" % (games, tot["orders"], ("%.1f" % skill_cut) if a.top_quartile else "-"))
    print("advance  %.3f  (%.0f of %.0f metal of orders given with the army clearly ahead)" % (sh(tot["adv_hit"], tot["adv_n"]), tot["adv_hit"], tot["adv_n"]))
    print("aimless  %.3f  (%.0f of %.0f metal of orders)" % (sh(tot["aimless"], tot["n"]), tot["aimless"], tot["n"]))
    print("aimed at  enemy %.3f  guard %.3f  spot %.3f  base %.3f" % tuple(
        sh(tot["by_" + w], tot["n"]) for w in ("enemy", "guard", "spot", "base")))
    print("flips    %.3f  (%d of %d order pairs within %.0f s)" % (sh(tot["flips"], tot["pairs"]), tot["flips"], tot["pairs"], FLIP_S))


if __name__ == "__main__":
    main()
