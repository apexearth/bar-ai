#!/usr/bin/env python3
"""Step 2 of todo/armynet-objectives.md, per unit of ARMY (not per order): what the army's standing orders point at,
where it stands, what ends an order aimed at the enemy, how it finishes an enemy cluster, and how often its direction
reverses. Offline, from recorded games (units are sampled every 10 frames with their standing command and target).

    python tools/armynet/objectives_army.py --who own runtime/armynet/own-games/rules-r2
    python tools/armynet/objectives_army.py --who players --winners --top-quartile G:/bar-ai-archive/public-replays/recordings
    add --shuffle for the baseline: every standing target replaced by a uniform random point (commitment only)

Labels come from the side's own view (data.Game's memory: buildings once seen stay known, moving enemies while seen in
the last FRESH_S); ground truth is used only where named (ghosts, live clusters, kills). The base axis runs from our
commander's start to theirs; depth 0 is our start, 1 theirs.

commitment  every STEP_S, each armed mobile unit weighs metal x STEP_S, classed by its standing order:
            cluster  within reach of a known enemy building whose cluster (known enemy building metal within CL_R)
                     clears --floor, or within BASE_R of a presumed base (their start, while nothing is known there)
            lone     within reach of a known enemy building below the floor (a lone extractor or turret)
            army     within reach of a moving enemy seen in the last FRESH_S
            own      within reach of one of our buildings;  other  any other point
            idle:target  its order's target is within half its reach (it stands where it was sent)
            idle:home / idle:fwd  no order, standing in our half / their half
their half  the share of army standing at depth > 0.5, by unit count and by metal, per window of minutes (the gate
            pages counted units over 5-15 and 15-25 min from the in-game army log, which holds the same units)
ghosts      of the metal-time standing within reach of a known cluster: the share with no living enemy building in
            reach (ground truth): remembered buildings that died unseen
finishing   standing within reach of a known cluster with a living enemy building in reach: enemy building metal that
            died within reach of such units per 1,000 army metal-minutes there; each unit's stint there ends cleared
            (every building it had in reach died), left, or died; time to clear; and the order after it clears:
            deeper / sideways / back along the axis, or none; and there, the share with an enemy building inside the
            unit's true weapon range, and the standing order kind (move / fight / attack / patrol / none)
funnel      each run of samples a unit spends on one target aimed at enemy buildings or base ends as arrived (within
            reach), replaced (forward = another enemy target, back = a target behind where it stands, else sideways),
            died, stood (the order ended short) or open at game end. Weighted by metal; median covered / asked.
flips       a unit's direction along the axis (target depth minus its own, beyond DIR_EPS) reversing within FLIP_S with
            no new enemy seen within KNOW_R, per unit-minute of army, metal-weighted.
"""
from __future__ import annotations

import argparse
import bisect
import os
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import Game  # noqa: E402
from objectives_offline import files  # noqa: E402

STEP_S = 10.0
FRESH_S = 30.0
REACH_PAD = 200.0
CL_R = 800.0
BASE_R = 1500.0
ADV_RATIO = 1.5
KNOW_R = 1500.0
FLIP_S = 60.0
DIR_EPS = 0.05
SAME_T = 64.0
FLOOR = 2000.0   # Otsu on log cluster metal gave 1975-2075 on players and model (11-27); printed per run
NONE_WAIT_S = 30.0  # "none" after clearing: an order inside this is the window, a death inside it is dead
ORDER_CMDS = (10, 15, 16, 20)  # move, patrol, fight, attack
SPOT_R = 48.0        # a building this close to a metal spot is its extractor
ALONE_R = 1000.0     # "none of our army near" a death, and "our army matching" a raid, within this
RAID_M = 200.0       # enemy armed metal in the middle third that counts as a raid
HELD_AT = (6, 9, 12)
MID_START_F, MID_END_F = 4 * 1800, 12 * 1800
ODDS_R = 1000.0       # ours and theirs armed metal around a unit in contact
ODDS_MOVE = 100.0     # an order this much closer to (farther from) their armed units near it goes toward (away)
FIGHT_R = 600.0       # a fight's metal: ours and theirs within this of its first contact
FIGHT_NEW_R = 1500.0  # a contact this far from any contact of ours in the last FIGHT_GAP_S starts a fight
FIGHT_GAP_S = 30.0
JOIN_R = 2000.0       # "a larger force of ours" counts within this of a fight's first contact
LOSS_R = 1000.0       # a fight's losses: armed units dying within this of its first contact in its 70 s
RANGE_EDGE = 50.0     # out-ranging the killer by more than this, and dying within its range plus this
FAR_R = 1500.0        # army standing this far from a unit when it dies is "away"
ARRIVE_A_S, ARRIVE_B_S = 10.0, 60.0
TGT_R = 64.0          # an attack order this close to a live enemy building is on that building
ODDS_FORGET_S = 20.0  # a death this long after the unit's last contact still counts at that contact's odds
CLS_STATIC, CLS_COM, CLS_ARMY, CLS_AIR = 0, 2, 3, 4
CLASSES = ("cluster", "lone", "army", "own", "other", "idle:target", "idle:home", "idle:fwd")
WINDOWS = (("5-15", 5, 15), ("15-25", 15, 25), ("25+", 25, 1e9), ("all", 0, 1e9))


def otsu(v):
    v = np.sort(np.asarray(v, float))
    if len(v) < 4:
        return float(np.median(v)) if len(v) else 0.0
    best, cut = -1.0, v[len(v) // 2]
    for q in np.unique(np.quantile(v, np.linspace(0.05, 0.95, 91))):
        a, b = v[v <= q], v[v > q]
        if not len(a) or not len(b):
            continue
        s = len(a) * len(b) * (a.mean() - b.mean()) ** 2
        if s > best:
            best, cut = s, q
    return float(cut)


def pick_sides(g, teams, who, top_q, winners, skill_cut):
    res = {}
    d = g.decisions
    for t in teams:
        r = g.result[d[:, 2] == t] if len(d) else []
        res[t] = int(r[0]) if len(r) else -1
    sides = []
    for ally in g.allies:
        ts = [t for t, (a, is_ai, sk) in teams.items() if a == ally]
        if who == "players" and any(teams[t][1] for t in ts):
            continue
        if top_q and not all(teams[t][2] >= skill_cut for t in ts):
            continue
        if winners and not any(res.get(t, -1) == 1 for t in ts):
            continue
        sides.append(ally)
    return sides


def within(x, z, xs, zs, r):
    return ((xs - x) ** 2 + (zs - z) ** 2) <= r * r


def read_game(path, who, top_q, winners, skill_cut, shuffle, floor, model_team=None, side=""):
    g = Game(path, rng=np.random.default_rng(0))
    z = np.load(path)
    teams = {int(t[0]): (int(t[1]), bool(t[2]), float(t[3])) for t in z["teams"]}
    msize = z["map"].astype(float)
    sides = pick_sides(g, teams, who, top_q, winners, skill_cut)
    if side and model_team is not None:
        mal = teams[model_team][0]
        sides = [s_ for s_ in sides if (s_ == mal) == (side == "model")]
    if not sides:
        return None
    com = g.ucls == CLS_COM
    start = {}
    for t in np.unique(g.uteam[com]):
        m = com & (g.uteam == t)
        j = int(np.argmin(g.frames[m]))
        start[int(t)] = np.array([g.units[m][j, 4], g.units[m][j, 5]], float)
    rng = np.random.default_rng(1)
    end_f = int(g.frames.max())
    step = int(STEP_S * 30)
    out = {"recs": [], "funnel": [], "stints": [], "cms": [], "flips": defaultdict(float), "kills": 0.0, "lost_cl": 0.0, "mid": [], "odds": [], "odds_lost": defaultdict(float), "atcl": [], "fights": [], "lost6": [], "outranged": [], "deaths_o": 0.0, "deaths_known": 0.0}
    dfr = defaultdict(list)  # uid -> frames of its recorded orders (any issuer: the model, a player, the AI)
    for fr_, u_ in zip(g.decisions[:, 0].astype(np.int64).tolist(), g.decisions[:, 3].astype(np.int64).tolist()):
        dfr[u_].append(fr_)
    dfr = {u_: np.array(sorted(v)) for u_, v in dfr.items()}
    hb = defaultdict(list)  # victim uid -> [(frame, attacker uid)] of the hits it took
    for fr_, a_, v_ in zip(g.hits[:, 0].astype(np.int64).tolist(), g.hits[:, 1].astype(np.int64).tolist(),
                           g.hits[:, 2].astype(np.int64).tolist()):
        if a_ >= 0:
            hb[v_].append((fr_, a_))
    hit_by = {v_: ([h[0] for h in hs], [h[1] for h in hs]) for v_, hs in hb.items()}
    for ally in sides:
        k = g.allies.index(ally)
        ours_t = [t for t, v in teams.items() if v[0] == ally and t in start]
        foe_t = [t for t, v in teams.items() if v[0] != ally and t in start]
        if not ours_t or not foe_t:
            continue
        o = np.mean([start[t] for t in ours_t], 0)
        ax = np.mean([start[t] for t in foe_t], 0) - o
        L2 = float(ax @ ax) or 1.0

        def depth(x, z_):
            return float(((x - o[0]) * ax[0] + (z_ - o[1]) * ax[1]) / L2)

        bases = [start[t] for t in foe_t]
        if not shuffle:
            out["mid"].append(middle(g, ally, depth, end_f))
        ep, lastdir, stint = {}, {}, {}
        odds_last = {}  # uid -> (odds class, metal, frame) at its last sample in contact
        tgt_last = {}   # uid -> the building it was last told to attack at a live cluster
        prev_o, prev_f = {}, {}  # uid -> (x, z, metal, def) of our and their armed units at the last sample
        fights, recent = [], []  # open fights (first contact, arrivals); our contacts of the last FIGHT_GAP_S
        pend, last_seen = [], {}
        prev_live, prev_cover = {}, set()
        for f in range(step, end_f + 1, step):
            rows = g.rows_at(f)
            if not len(rows):
                continue
            mx, mz, md, mage, mst, _vx, _vz = g._memory(k, f, ally)
            fresh = mst | (mage <= FRESH_S)
            bx, bz, bm = mx[mst], mz[mst], g.d_metal[md[mst]]
            fx, fz = mx[fresh & ~mst], mz[fresh & ~mst]
            their_army = float(g.d_metal[md[~mst & np.isin(g.d_cls[md], (CLS_ARMY, CLS_AIR))]].sum())
            clm = ((bx[:, None] - bx[None, :]) ** 2 + (bz[:, None] - bz[None, :]) ** 2 <= CL_R * CL_R) @ bm \
                if len(bx) else np.zeros(0)
            pres = [b for b in bases if not len(bx) or not within(b[0], b[1], bx, bz, BASE_R).any()]
            ru = g.units[rows]
            rcls, rally, rdef, ruid = g.ucls[rows], g.ually[rows], g.udef[rows], g.uid[rows]
            built = ru[:, 9] >= 1.0
            mine = rally == ally
            ob = mine & (rcls == CLS_STATIC) & built
            ox, oz = ru[ob, 4], ru[ob, 5]
            le = (rally != ally) & (rally >= 0) & (rcls == CLS_STATIC) & built
            lx, lz, luid = ru[le, 4], ru[le, 5], ruid[le].astype(np.int64)
            live = {int(u): float(g.d_metal[d_]) for u, d_ in zip(luid, rdef[le])}
            lhp = ru[le, 8] * g.d_hp[rdef[le]]   # each live enemy building's health now
            lmetal = g.d_metal[rdef[le]]
            died = [u for u in prev_live if u not in live]
            if not shuffle:
                out["kills"] += sum(prev_live[u] for u in died if u in prev_cover)
            dead = set(died)
            arm = mine & built & np.isin(rcls, (CLS_ARMY, CLS_AIR)) & ((g.d_g[rdef] + g.d_a[rdef]) > 0)
            ahead = float(g.d_metal[rdef[arm]].sum()) > ADV_RATIO * max(their_army, 1.0)
            # odds in contact (ground truth): an armed enemy unit within our unit's reach; ours and theirs armed metal
            # within ODDS_R of our unit; the order measured against their armed units' centre there
            odds = {}
            oj = np.nonzero(arm)[0]
            fj = np.nonzero((rally != ally) & (rally >= 0) & built & np.isin(rcls, (CLS_ARMY, CLS_AIR))
                            & ((g.d_g[rdef] + g.d_a[rdef]) > 0))[0]
            if len(oj) and len(fj) and not shuffle:
                ox_, oz_, fx_, fz_ = ru[oj, 4], ru[oj, 5], ru[fj, 4], ru[fj, 5]
                fm = g.d_metal[rdef[fj]]
                d2f = (ox_[:, None] - fx_[None]) ** 2 + (oz_[:, None] - fz_[None]) ** 2
                near_f = d2f <= ODDS_R * ODDS_R
                om = g.d_metal[rdef[oj]]
                d2o = (ox_[:, None] - ox_[None]) ** 2 + (oz_[:, None] - oz_[None]) ** 2
                ours_n = (d2o <= ODDS_R * ODDS_R) @ om
                theirs_n = near_f @ fm
                ours6, theirs6 = (d2o <= FIGHT_R * FIGHT_R) @ om, (d2f <= FIGHT_R * FIGHT_R) @ fm
                tot = float(om.sum())
                far = ((d2o > FAR_R * FAR_R) @ om) / max(tot, 1.0)
                reach_o = g.d_range[rdef[oj]] + REACH_PAD
                touch = (d2f <= reach_o[:, None] ** 2).any(1)
                for q in np.nonzero(touch)[0]:
                    r_ = ours_n[q] / max(theirs_n[q], 1.0)
                    c_ = "outgunned" if r_ < 1.0 / ADV_RATIO else ("ahead" if r_ > ADV_RATIO else "even")
                    nf = d2f[q] <= max(ODDS_R, float(reach_o[q])) ** 2
                    odds[int(oj[q])] = (c_, float((fx_[nf] * fm[nf]).sum() / fm[nf].sum()),
                                        float((fz_[nf] * fm[nf]).sum() / fm[nf].sum()),
                                        float(ours6[q] / max(theirs6[q], 1.0)), float(far[q]))
                    # a fight's first contact: no unit of ours in contact within FIGHT_NEW_R in the last FIGHT_GAP_S
                    x_, z_ = float(ox_[q]), float(oz_[q])
                    if any(f - fr_ <= FIGHT_GAP_S * 30 and (x_ - px_) ** 2 + (z_ - pz_) ** 2 <= FIGHT_NEW_R ** 2
                           for fr_, px_, pz_ in recent):
                        continue
                    at0 = d2o[q] <= FIGHT_R * FIGHT_R
                    fights.append({"f": f, "x": x_, "z": z_, "ours": float(ours6[q]), "theirs": float(theirs6[q]),
                                   "tot": tot, "seen": set(ruid[oj[at0]].astype(np.int64).tolist()), "a10": 0.0, "a60": 0.0,
                                   "near": float(((d2o[q] <= JOIN_R * JOIN_R) @ om)), "lost_o": 0.0, "lost_f": 0.0})
                    recent.append((f, x_, z_))
                recent[:] = [r for r in recent if f - r[0] <= FIGHT_GAP_S * 30] + \
                    [(f, float(ox_[q]), float(oz_[q])) for q in np.nonzero(touch)[0]]
            # deaths since the last sample (ground truth: every unit is in the rows): each fight's losses on both sides
            # within LOSS_R, and our units that out-ranged their killer and died inside its range
            cur_o = {int(ruid[j_]): (float(ru[j_, 4]), float(ru[j_, 5]), float(g.d_metal[rdef[j_]]), int(rdef[j_]))
                     for j_ in oj}
            cur_f = {int(ruid[j_]): (float(ru[j_, 4]), float(ru[j_, 5]), float(g.d_metal[rdef[j_]]), int(rdef[j_]))
                     for j_ in fj}
            if not shuffle:
                for side_, prev_, cur_ in (("o", prev_o, cur_o), ("f", prev_f, cur_f)):
                    for u_ in [u for u in prev_ if u not in cur_]:
                        x_, z_, m_, df_ = prev_[u_]
                        for ft in fights:
                            if (x_ - ft["x"]) ** 2 + (z_ - ft["z"]) ** 2 <= LOSS_R * LOSS_R:
                                ft["lost_" + side_] += m_
                        if side_ != "o":
                            continue
                        out["deaths_o"] += m_
                        hs = hit_by.get(u_)
                        if not hs:
                            continue
                        k_ = bisect.bisect_right(hs[0], f) - 1
                        if k_ < 0 or f - hs[0][k_] > 2 * step:
                            continue
                        kp = g._pos(hs[1][k_], hs[0][k_])
                        if kp is None:
                            continue
                        out["deaths_known"] += m_
                        kr, ur = float(g.d_range[kp[3]]), float(g.d_range[df_])
                        if ur > kr + RANGE_EDGE and np.hypot(x_ - kp[0], z_ - kp[1]) <= kr + RANGE_EDGE:
                            out["outranged"].append(m_)
            prev_o, prev_f = cur_o, cur_f
            # arrivals at each open fight: our armed metal coming within FIGHT_R in the next 10 s, then the next 60 s
            if len(oj) and not shuffle:
                for ft in [x for x in fights if x["f"] < f]:
                    if f - ft["f"] > (ARRIVE_A_S + ARRIVE_B_S) * 30:
                        out["fights"].append((ft["ours"], ft["theirs"], ft["tot"], ft["a10"], ft["a60"], ft["f"],
                                              ft["near"], ft["lost_o"], ft["lost_f"]))
                        fights.remove(ft)
                        continue
                    inn = (ru[oj, 4] - ft["x"]) ** 2 + (ru[oj, 5] - ft["z"]) ** 2 <= FIGHT_R * FIGHT_R
                    for j_ in oj[inn]:
                        u_ = int(ruid[j_])
                        if u_ not in ft["seen"]:
                            ft["seen"].add(u_)
                            ft["a10" if f - ft["f"] <= ARRIVE_A_S * 30 else "a60"] += float(g.d_metal[rdef[j_]])
            cover = set()
            alive = set()
            mnt = f / 1800.0
            for j in np.nonzero(arm)[0]:
                uid, df = int(ruid[j]), int(rdef[j])
                alive.add(uid)
                w = float(g.d_metal[df])
                ux, uz = float(ru[j, 4]), float(ru[j, 5])
                reach = float(g.d_range[df]) + REACH_PAD
                udep = depth(ux, uz)
                cmd, tx, tz = int(ru[j, 11]), float(ru[j, 12]), float(ru[j, 13])
                ordered = cmd in ORDER_CMDS and tx >= 0
                has = ordered and (tx - ux) ** 2 + (tz - uz) ** 2 > (0.5 * reach) ** 2
                if has and shuffle:
                    tx, tz = float(rng.uniform(0, msize[0])), float(rng.uniform(0, msize[1]))
                cm = 0.0
                if has:
                    if len(bx):
                        nb = within(tx, tz, bx, bz, reach)
                        cm = float(clm[nb].max()) if nb.any() else 0.0
                    if any(within(tx, tz, b[0], b[1], BASE_R) for b in pres):
                        tag = "cluster"
                    elif cm > 0:
                        tag = "cluster" if cm >= floor else "lone"
                    elif len(fx) and within(tx, tz, fx, fz, reach).any():
                        tag = "army"
                    elif len(ox) and within(tx, tz, ox, oz, reach).any():
                        tag = "own"
                    else:
                        tag = "other"
                else:
                    tag = "idle:target" if ordered else ("idle:fwd" if udep > 0.5 else "idle:home")
                ucm = 0.0
                if len(bx):
                    nb = within(ux, uz, bx, bz, reach)
                    ucm = float(clm[nb].max()) if nb.any() else 0.0
                    if ucm > 0:
                        out["cms"].append(ucm)
                at_cl = ucm >= floor
                inreach = set(luid[within(ux, uz, lx, lz, reach)].tolist()) if len(lx) else set()
                at_live = at_cl and bool(inreach)
                in_range = bool(len(lx)) and bool(within(ux, uz, lx, lz, float(g.d_range[df])).any())
                kind = {10: "move", 15: "patrol", 16: "fight", 20: "attack"}.get(cmd, "none") if ordered else "none"
                out["recs"].append((w * STEP_S, tag, ahead, udep, at_cl, at_cl and not inreach, at_live, mnt, in_range, kind))
                if j in odds:
                    c_, cx_, cz_, r6_, far_ = odds[j]
                    if has:
                        d0_, d1_ = np.hypot(ux - cx_, uz - cz_), np.hypot(tx - cx_, tz - cz_)
                        dn_ = "toward" if d1_ < d0_ - ODDS_MOVE else ("away" if d1_ > d0_ + ODDS_MOVE else "hold")
                    else:
                        dn_ = "hold"
                    out["odds"].append((w * STEP_S, c_, dn_))
                    odds_last[uid] = (c_, w, f, r6_, far_)
                elif uid in odds_last and f - odds_last[uid][2] > ODDS_FORGET_S * 30:
                    del odds_last[uid]
                if shuffle:
                    continue
                if has:
                    dv = depth(tx, tz) - udep
                    dr = 1 if dv > DIR_EPS else (-1 if dv < -DIR_EPS else 0)
                else:
                    dr = 0
                # finishing: a stint within reach of a live known cluster
                if at_live:
                    of_ = dfr.get(uid)
                    out["flips"]["cl_orders"] += int(np.searchsorted(of_, f, "right") - np.searchsorted(of_, f - step, "right")) if of_ is not None else 0
                    out["flips"]["cl_min"] += STEP_S / 60.0
                    cover |= inreach
                    s = stint.setdefault(uid, {"f": f, "w": w, "had": set()})
                    s["had"] |= inreach
                    s["now"] = inreach
                    if rcls[j] == CLS_ARMY:
                        # what a ground unit at a live cluster is told: an attack on a building (which one, of those in
                        # its reach: the nearest, the weakest, the most metal), an attack on something else, or the kind
                        tb, flags = -1, (False, False, False, 0)
                        if ordered and cmd == 20 and len(lx):
                            d2t = (lx - tx) ** 2 + (lz - tz) ** 2
                            tb = int(np.argmin(d2t)) if float(d2t.min()) <= TGT_R ** 2 else -1
                        if tb >= 0:
                            ci = np.nonzero(within(ux, uz, lx, lz, reach))[0]
                            if tb not in ci:
                                ci = np.append(ci, tb)
                            dd = np.hypot(lx[ci] - ux, lz[ci] - uz)
                            flags = (int(ci[np.argmin(dd)]) == tb, int(ci[np.argmin(lhp[ci])]) == tb,
                                     int(ci[np.argmax(lmetal[ci])]) == tb, len(ci))
                            tcl = "building"
                            b_ = int(luid[tb])
                            if tgt_last.get(uid, b_) != b_:
                                out["flips"]["retarget"] += 1
                            tgt_last[uid] = b_
                        else:
                            tcl = "attack:other" if (ordered and cmd == 20) else kind
                        out["flips"]["cl_ground_min"] += STEP_S / 60.0
                        out["atcl"].append((w * STEP_S, tcl) + flags)
                elif uid in stint:
                    s = stint.pop(uid)
                    nxt = "none" if not has else ("deeper" if dr > 0 else ("back" if dr < 0 else "sideways"))
                    why = "cleared" if s["now"] and s["now"] <= dead else "left"
                    # what a "none" is made of: an order to where it stands (same spot), a remembered cluster with
                    # nothing alive (ghost), an order that comes within NONE_WAIT_S (window), or idle; dead is
                    # settled after the game (the unit gone within NONE_WAIT_S)
                    sub = ""
                    if nxt == "none":
                        of_ = dfr.get(uid)
                        nxt_o = of_ is not None and (np.searchsorted(of_, f + NONE_WAIT_S * 30, "right")
                                                     - np.searchsorted(of_, f, "right")) > 0
                        sub = ("same" if ordered else "ghost" if (at_cl and not inreach) else
                               "window" if nxt_o else "idle")
                        pend.append((len(out["stints"]), uid, f))
                    out["stints"].append((s["w"], why, (f - s["f"]) / 30.0, nxt, sub))
                # funnel
                cur = ep.get(uid)
                same = cur is not None and has and (tx - cur["t"][0]) ** 2 + (tz - cur["t"][1]) ** 2 <= SAME_T ** 2
                if cur is not None and not same:
                    if within(ux, uz, cur["t"][0], cur["t"][1], cur["reach"]):
                        why = "arrived"
                    elif not has:
                        why = "stood"
                    elif tag == "cluster" or tag == "lone":
                        why = "replaced:forward"
                    elif dr < 0:
                        why = "replaced:back"
                    else:
                        why = "replaced:sideways"
                    out["funnel"].append(_close(ep.pop(uid), why, ux, uz))
                    cur = None
                if cur is None and has and tag in ("cluster", "lone"):
                    ep[uid] = {"t": (tx, tz), "s": (ux, uz), "w": w, "reach": reach, "last": (ux, uz)}
                elif cur is not None:
                    cur["last"] = (ux, uz)
                    if within(ux, uz, tx, tz, cur["reach"]):
                        out["funnel"].append(_close(ep.pop(uid), "arrived", ux, uz))
                # flips
                known = int(within(ux, uz, fx, fz, KNOW_R).sum()) if len(fx) else 0
                out["flips"]["unit_s"] += w * STEP_S
                if dr:
                    lp = lastdir.get(uid)
                    if lp and lp[1] == -dr and (f - lp[0]) <= FLIP_S * 30 and known <= lp[2]:
                        out["flips"]["rev"] += w
                    lastdir[uid] = (f, dr, known)
            for u_ in alive:
                last_seen[u_] = f
            for u_ in [u for u in odds_last if u not in alive]:
                c_, w_, _f, r6_, far_ = odds_last.pop(u_)
                out["odds_lost"][c_] += w_
                out["lost6"].append((w_, r6_, far_))
            for uid in [u for u in ep if u not in alive]:
                cur = ep.pop(uid)
                out["funnel"].append(_close(cur, "died", *cur["last"]))
            for uid in [u for u in stint if u not in alive]:
                s = stint.pop(uid)
                out["stints"].append((s["w"], "died", (f - s["f"]) / 30.0, "-", ""))
                out["lost_cl"] += s["w"]
            prev_live, prev_cover = live, cover
        for cur in ep.values():
            out["funnel"].append(_close(cur, "open", *cur["last"]))
        for s in stint.values():
            out["stints"].append((s["w"], "open", (end_f - s["f"]) / 30.0, "-", ""))
        for i_, u_, f_ in pend:
            ls_ = last_seen.get(u_, f_)
            if ls_ < f_ + NONE_WAIT_S * 30 and ls_ < end_f - step:
                st_ = out["stints"][i_]
                out["stints"][i_] = st_[:4] + ("dead",)
    return out


def middle(g, ally, depth, end_f):
    """The middle third (spots and units with depth 1/3..2/3 on the start-to-start axis), ground truth:
    extractors held there at 6 / 9 / 12 min (ours, theirs); army metal-time at 4-12 min within reach of a middle spot,
    by the nearest such spot's holder; our middle extractors and builders killed before 12 min, and whether any of our
    army stood within ALONE_R at the last sample; enemy armed metal entering the middle at 4-12 min (RAID_M or more)
    until ours within ALONE_R of it matches it (matched / left / open, seconds)."""
    sp = np.asarray(g.spots, float).reshape(-1, 2)[:, :2] if len(g.spots) else np.zeros((0, 2))
    sd = np.array([depth(x, z) for x, z in sp])
    ms = sp[(sd >= 1 / 3) & (sd <= 2 / 3)] if len(sp) else sp
    res = {"held": {}, "bt": defaultdict(float), "kill": [], "raid": []}
    step = int(STEP_S * 30)
    prev, ep = {}, None
    last = min(MID_END_F, end_f - step)
    for f in range(step, last + 1, step):
        rows = g.rows_at(f)
        if not len(rows):
            continue
        ru = g.units[rows]
        rcls, rally, rdef, ruid = g.ucls[rows], g.ually[rows], g.udef[rows], g.uid[rows]
        built = ru[:, 9] >= 1.0
        mine, foe = rally == ally, (rally != ally) & (rally >= 0)
        st = (rcls == CLS_STATIC) & built
        armed = built & np.isin(rcls, (CLS_ARMY, CLS_AIR)) & ((g.d_g[rdef] + g.d_a[rdef]) > 0)
        ax_, az_ = ru[armed & mine, 4], ru[armed & mine, 5]
        aw = g.d_metal[rdef[armed & mine]]
        hold = np.zeros(len(ms), int)  # 1 ours, -1 theirs, 0 empty
        on_spot = np.zeros(len(ru), bool)
        if len(ms) and st.any():
            si = np.nonzero(st)[0]
            d2 = (ru[si, 4][:, None] - ms[:, 0][None]) ** 2 + (ru[si, 5][:, None] - ms[:, 1][None]) ** 2
            near = d2 <= SPOT_R * SPOT_R
            on_spot[si[near.any(1)]] = True
            hold[(near & mine[si][:, None]).any(0)] = 1
            hold[(near & foe[si][:, None]).any(0) & (hold == 0)] = -1
        for mnt_ in HELD_AT:
            if f == mnt_ * 1800:
                res["held"][mnt_] = (int((hold == 1).sum()), int((hold == -1).sum()))
        if f >= MID_START_F:
            for x, z, w, df in zip(ax_, az_, aw, rdef[armed & mine]):
                r = float(g.d_range[df]) + REACH_PAD
                if len(ms):
                    d2 = (ms[:, 0] - x) ** 2 + (ms[:, 1] - z) ** 2
                    j = int(np.argmin(d2))
                    key = {1: "ours", -1: "theirs", 0: "empty"}[int(hold[j])] if d2[j] <= r * r else "away"
                else:
                    key = "away"
                res["bt"][key] += float(w) * STEP_S
        # (c) our middle extractors and builders, and deaths since the last sample
        udep = np.array([depth(x, z) for x, z in ru[:, 4:6]]) if len(ru) else np.zeros(0)
        ours = mine & ((on_spot & st) | ((rcls == 1) & built & (udep >= 1 / 3) & (udep <= 2 / 3)))
        cur = {}
        for j in np.nonzero(ours)[0]:
            x, z = ru[j, 4], ru[j, 5]
            cur[int(ruid[j])] = ("extractor" if rcls[j] == CLS_STATIC else "builder",
                                 bool(len(ax_)) and bool(within(x, z, ax_, az_, ALONE_R).any()))
        present = set(ruid.tolist())
        for u, (kind, near_) in prev.items():
            if u not in present:
                res["kill"].append((kind, near_))
        prev = cur
        # (d) raids into the middle
        if f >= MID_START_F:
            em_m = foe & armed & (udep >= 1 / 3) & (udep <= 2 / 3)
            em = float(g.d_metal[rdef[em_m]].sum())
            if em < RAID_M:
                if ep is not None and ep >= 0:
                    res["raid"].append(("left", (f - ep) / 30.0))
                ep = None
            elif ep is None:
                ep = f
            if ep is not None and ep >= 0:
                cx, cz = ru[em_m, 4].mean(), ru[em_m, 5].mean()
                have = float(aw[within(cx, cz, ax_, az_, ALONE_R)].sum()) if len(ax_) else 0.0
                if have >= em:
                    res["raid"].append(("matched", (f - ep) / 30.0))
                    ep = -1  # matched: no new raid until their metal in the middle falls under RAID_M
    if ep is not None and ep >= 0:
        res["raid"].append(("open", (last - ep) / 30.0))
    return res


def _close(cur, why, ux, uz):
    tx, tz = cur["t"]
    sx, sz = cur["s"]
    asked = float(np.hypot(tx - sx, tz - sz))
    left = float(np.hypot(tx - ux, tz - uz))
    return (cur["w"], why, (asked - left) / asked if asked > 1 else 1.0, left)


def shares(items, key, keys, w=lambda x: x[0]):
    tot = sum(w(x) for x in items) or 1.0
    by = defaultdict(float)
    for x in items:
        by[key(x)] += w(x)
    return "  ".join("%s %.3f" % (kk, by[kk] / tot) for kk in keys)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("roots", nargs="+")
    ap.add_argument("--who", choices=("own", "players", "all"), default="all")
    ap.add_argument("--top-quartile", action="store_true")
    ap.add_argument("--winners", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--match", default="", help="only files whose name contains one of these, comma list")
    ap.add_argument("--shuffle", action="store_true")
    ap.add_argument("--floor", type=float, default=FLOOR, help="cluster metal floor (default %(default)s)")
    ap.add_argument("--mvr-log", default="", help="model_vs_rules.sh run log(s), comma list: which team the model had")
    ap.add_argument("--side", choices=("", "model", "rules"), default="", help="with --mvr-log: read only that side")
    a = ap.parse_args()
    fs = files(a.roots)
    if a.match:
        keys = a.match.split(",")
        fs = [p for p in fs if any(k in os.path.basename(p) for k in keys)]
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
    mt = {}
    for lg in filter(None, a.mvr_log.split(",")):
        for ln in open(lg, encoding="utf-8"):
            p_ = ln.split()
            if len(p_) >= 7 and p_[0] == "seed":
                mt[Path(p_[6]).name] = int(p_[3].lstrip("t"))
    A = {"recs": [], "funnel": [], "stints": [], "cms": [], "flips": defaultdict(float), "kills": 0.0, "lost_cl": 0.0, "mid": [], "odds": [], "odds_lost": defaultdict(float), "atcl": [], "fights": [], "lost6": [], "outranged": [], "deaths_o": 0.0, "deaths_known": 0.0}
    games = 0
    for p in fs:
        try:
            o = read_game(p, a.who, a.top_quartile, a.winners, skill_cut, a.shuffle, a.floor, mt.get(Path(p).stem), a.side)
        except Exception as ex:  # noqa: BLE001
            print("skip", os.path.basename(p), type(ex).__name__, ex, file=sys.stderr)
            continue
        if o is None:
            continue
        games += 1
        for kk, v in o["odds_lost"].items():
            A["odds_lost"][kk] += v
        A["deaths_o"] += o["deaths_o"]
        A["deaths_known"] += o["deaths_known"]
        for kk in ("recs", "funnel", "stints", "cms", "mid", "odds", "atcl", "fights", "lost6", "outranged"):
            A[kk] += o[kk]
        A["kills"] += o["kills"]
        A["lost_cl"] += o["lost_cl"]
        for kk, v in o["flips"].items():
            A["flips"][kk] += v
    R = A["recs"]
    if not R:
        print("no states")
        return
    der = 10 ** otsu(np.log10(np.maximum(A["cms"], 1.0))) if A["cms"] else 0.0
    print("games %d  army samples %d  cluster floor %.0f (Otsu on this set: %.0f)%s" % (
        games, len(R), a.floor, der, "  SHUFFLED targets" if a.shuffle else ""))
    for name, sel in (("all", lambda r: True), ("ahead", lambda r: r[2])):
        rs = [r for r in R if sel(r)]
        print("commitment %-5s (%.2f of metal-time)  %s" % (name, sum(r[0] for r in rs) / sum(r[0] for r in R),
                                                          shares(rs, lambda r: r[1], CLASSES)))
    if a.shuffle:
        return
    parts = []
    for wn, lo, hi in WINDOWS:
        rs = [r for r in R if lo <= r[7] < hi]
        if not rs:
            continue
        c = sum(1 for r in rs if r[3] > 0.5) / len(rs)
        m = sum(r[0] for r in rs if r[3] > 0.5) / (sum(r[0] for r in rs) or 1)
        parts.append("%s units %.3f metal %.3f" % (wn, c, m))
    print("their half " + "  |  ".join(parts))
    at = [r for r in R if r[4]]
    atm = sum(r[0] for r in at)
    print("at a known cluster %.3f of metal-time; of it ghosts (no living building in reach) %.3f" % (
        atm / sum(r[0] for r in R), sum(r[0] for r in at if r[5]) / (atm or 1)))
    lm = sum(r[0] for r in R if r[6]) / 60.0
    S = A["stints"]
    clr = [x for x in S if x[1] == "cleared"]
    print("finishing  at a live cluster %.3f of metal-time; building metal killed there %.0f per 1,000 army metal-min" % (
        lm * 60 / sum(r[0] for r in R), 1000 * A["kills"] / lm if lm else float("nan")))
    if A["flips"]["cl_min"]:
        print("           orders per unit-minute at a live cluster %.2f (recorded orders, any issuer)" % (
            A["flips"]["cl_orders"] / A["flips"]["cl_min"]))
    lv = [r for r in R if r[6]]
    if lv:
        lt = sum(r[0] for r in lv)
        print("           there: an enemy building inside weapon range %.3f; standing order %s; in range by order %s" % (
            sum(r[0] for r in lv if r[8]) / lt, shares(lv, lambda r: r[9], ("move", "fight", "attack", "patrol", "none")),
            "  ".join("%s %.2f" % (kd, sum(r[0] for r in lv if r[9] == kd and r[8]) / (sum(r[0] for r in lv if r[9] == kd) or 1))
                      for kd in ("move", "fight", "attack", "none"))))
    if S:
        print("           %d stints: %s; median to clear %.0f s; after clearing: %s" % (
            len(S), shares(S, lambda x: x[1], ("cleared", "left", "died", "open")),
            np.median([x[2] for x in clr]) if clr else float("nan"),
            shares(clr, lambda x: x[3], ("deeper", "sideways", "back", "none")) if clr else "-"))
        nn = [x for x in clr if x[3] == "none"]
        if nn:
            print("           'none' after clearing is: %s (of %d)" % (
                shares(nn, lambda x: x[4], ("same", "ghost", "window", "idle", "dead")), len(nn)))
        print("           our army metal lost at a live cluster %.0f per building metal killed there %.0f: %.2f" % (
            A["lost_cl"], A["kills"], A["lost_cl"] / A["kills"] if A["kills"] else float("nan")))
    F = A["funnel"]
    if F:
        print("funnel     %d orders at enemy buildings or base: %s" % (len(F), shares(F, lambda x: x[1], (
            "arrived", "replaced:forward", "replaced:sideways", "replaced:back", "died", "stood", "open"))))
        st = [x[3] for x in F if x[1] == "stood"]
        print("           median covered/asked %.2f; stood short by a median %.0f elmos" % (
            np.median([x[2] for x in F]), np.median(st) if st else float("nan")))
    if A["flips"]["unit_s"]:
        print("flips      %.3f direction reversals per unit-minute (metal-weighted), no new enemy in view"
              % (A["flips"]["rev"] / (A["flips"]["unit_s"] / 60.0)))
    AC = A["atcl"]
    if AC:
        bt_ = [x for x in AC if x[1] == "building"]
        bw = sum(x[0] for x in bt_) or 1.0
        print("at-cluster ground units at a live cluster, order: %s" % shares(
            AC, lambda x: x[1], ("building", "attack:other", "fight", "move", "patrol", "none")))
        print("           of the attacks on a building, it was the nearest %.3f  the weakest %.3f  the most metal %.3f"
              " of those in reach (median %.0f in reach); re-targets %.2f per unit-minute there" % (
                  sum(x[0] for x in bt_ if x[2]) / bw, sum(x[0] for x in bt_ if x[3]) / bw,
                  sum(x[0] for x in bt_ if x[4]) / bw, np.median([x[5] for x in bt_]) if bt_ else float("nan"),
                  A["flips"]["retarget"] / (A["flips"]["cl_ground_min"] or 1.0)))
        lf = [x for x in A["stints"] if x[1] == "left"]
        print("           pulled out (left with a building there alive) %.3f of stints, after a median %.0f s" % (
            len(lf) / (len(A["stints"]) or 1), np.median([x[2] for x in lf]) if lf else float("nan")))
    O = A["odds"]
    if O:
        ot = sum(x[0] for x in O)
        parts = []
        for c_ in ("outgunned", "even", "ahead"):
            oc = [x for x in O if x[1] == c_]
            parts.append("%s %.3f (%s)" % (c_, sum(x[0] for x in oc) / ot,
                                           shares(oc, lambda x: x[2], ("toward", "hold", "away")) if oc else "-"))
        lt = sum(A["odds_lost"].values()) or 1.0
        print("odds       in contact (an armed enemy within reach) %.3f of metal-time; ours / theirs within %.0f: %s" % (
            ot / sum(r[0] for r in R), ODDS_R, "  ".join(parts)))
        print("           our army metal lost within %.0f s of a contact, by its odds: %s (%.0f metal)" % (
            ODDS_FORGET_S, "  ".join("%s %.3f" % (c_, A["odds_lost"][c_] / lt) for c_ in ("outgunned", "even", "ahead")),
            lt))
    FT = [x for x in A["fights"] if x[2] > 0]
    if FT:
        rat = [x[0] / max(x[1], 1.0) for x in FT]
        shr = [x[0] / x[2] for x in FT]
        arr = sum(x[0] + x[3] + x[4] for x in FT) or 1.0
        print("fights     %d first contacts: ours / theirs within %.0f median %.2f (under 0.7 in %.3f); that is %.3f of"
              " our army (median; q75 %.3f)" % (len(FT), FIGHT_R, float(np.median(rat)),
                                               sum(1 for v in rat if v < 0.7) / len(rat), float(np.median(shr)),
                                               float(np.percentile(shr, 75))))
        print("           our metal at the fight within 70 s: there at contact %.3f, arriving in the first %.0f s %.3f,"
              " over the next %.0f s %.3f" % (sum(x[0] for x in FT) / arr, ARRIVE_A_S, sum(x[3] for x in FT) / arr,
                                              ARRIVE_B_S, sum(x[4] for x in FT) / arr))
    if FT:
        fought = [x for x in FT if x[7] + x[8] > 0]
        lost = [x for x in fought if x[7] > x[8]]
        og = [x for x in FT if x[0] / max(x[1], 1.0) < 0.7]
        fix = [x for x in og if x[6] >= x[1]]
        print("           fights with losses within %.0f in their 70 s: %d, lost (ours lost over theirs) %.3f, our metal"
              " lost in lost fights %.0f per game | entered outgunned (under 0.7) %.1f per game, of them with ours"
              " within %.0f at least their metal (correction: join or hold) %.1f per game" % (
                  LOSS_R, len(fought), len(lost) / max(len(fought), 1), sum(x[7] for x in lost) / max(games, 1),
                  len(og) / max(games, 1), JOIN_R, len(fix) / max(games, 1)))
    if A["deaths_o"]:
        orr = A["outranged"]
        print("           our army deaths that out-ranged their killer and died inside its range (correction: stop at"
              " our own range): %.1f per game, %.3f of our army metal lost (killer known for %.3f of it)" % (
                  len(orr) / max(games, 1), sum(orr) / A["deaths_o"], A["deaths_known"] / A["deaths_o"]))
    L6 = A["lost6"]
    if L6:
        lw = sum(x[0] for x in L6) or 1.0
        bad = [x for x in L6 if x[1] < 0.7]
        bw = sum(x[0] for x in bad)
        print("           our army metal lost within %.0f s of a contact with ours / theirs within %.0f under 0.7: %.3f;"
              " then %.3f of our army stood over %.0f away (metal-weighted)" % (
                  ODDS_FORGET_S, FIGHT_R, bw / lw, sum(x[0] * x[2] for x in bad) / (bw or 1.0), FAR_R))
    M = A["mid"]
    if M:
        held = []
        for mn in HELD_AT:
            hs = [m["held"][mn] for m in M if mn in m["held"]]
            if hs:
                held.append("%d min %.1f / %.1f (n %d)" % (mn, np.mean([h[0] for h in hs]), np.mean([h[1] for h in hs]), len(hs)))
        print("middle     extractors held in the middle third, ours / theirs per side: " + "  ".join(held))
        bt = defaultdict(float)
        for m in M:
            for kk, v in m["bt"].items():
                bt[kk] += v
        tb = sum(bt.values()) or 1.0
        print("           army metal-time at 4-12 min within reach of a middle spot: ours %.3f  theirs %.3f  empty %.3f"
              "  (away %.3f)" % tuple(bt[kk] / tb for kk in ("ours", "theirs", "empty", "away")))
        K = [x for m in M for x in m["kill"]]
        for kind in ("extractor", "builder"):
            ks = [x for x in K if x[0] == kind]
            if ks:
                print("           our middle %ss killed before 12 min: %d, none of our army within %.0f %.3f" % (
                    kind, len(ks), ALONE_R, sum(1 for x in ks if not x[1]) / len(ks)))
        RD = [x for m in M for x in m["raid"]]
        if RD:
            mt_ = [x[1] for x in RD if x[0] == "matched"]
            print("           raids into the middle at 4-12 min (%.0f+ armed metal): %d; matched %.3f (median %.0f s, "
                  "within 60 s %.3f)  left unmatched %.3f  open at 12 %.3f" % (
                      RAID_M, len(RD), len(mt_) / len(RD), np.median(mt_) if mt_ else float("nan"),
                      sum(1 for v in mt_ if v <= 60) / len(RD), sum(1 for x in RD if x[0] == "left") / len(RD),
                      sum(1 for x in RD if x[0] == "open") / len(RD)))


if __name__ == "__main__":
    main()
