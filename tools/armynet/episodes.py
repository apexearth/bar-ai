#!/usr/bin/env python3
"""Step 3, the label's unit (the Fable session, 11-27): cut each armed unit's track into EPISODES and label each by
what it then fought, killed or held, for three columns: top players, our rules army, the army model.

    python tools/armynet/episodes.py --who players --winners --top-quartile G:/bar-ai-archive/public-replays/recordings
    python tools/armynet/episodes.py --who own runtime/armynet/own-games/rules-r2
    python tools/armynet/episodes.py --who all --mvr-log runtime/armynet/mvr-mvr-a.log --side model|rules runtime/armynet/own-games/mvr-a
    add --shuffle for the baseline: each episode's travel heading replaced by a random other episode's (same side)

Every STEP_S each armed mobile unit is MOVING (over MOVE_D since the last sample, no contact) or HELD (standing, or in
contact: it dealt or took damage in the last STEP_S). An episode is a run of moving samples and the held run after it;
it ends when the unit moves off again (after holding at least MIN_HOLD_S; a shorter pause is part of the trip) or dies. One label per episode, decided at its start (when an objective model
would decide). Labels are hindsight, so they may use ground truth (the game as it was, never a model input):
    contact   damage the unit dealt and took over the episode, metal-weighted (damage / health x metal of the unit
              hit): enemy buildings in a cluster (living enemy building metal within CL_R over FLOOR) -> cluster, other
              enemy buildings -> lone, enemy units within THREAT_R of one of our buildings -> threat, other enemy
              units -> army. The label is the class with the most.
    no contact, held within SPOT_R of a metal spot and, by the episode's end + SPOT_WAIT_S, a building of ours rose there
              or one of theirs died there -> spot; held within BASE_R of an enemy start -> base; held within JOIN_R of
              other armed units of ours -> join; else none.
    aligned   the travel heading (start -> where it was held) within ALIGN_COS of the direction to the labelled
              objective (the damage-weighted centre of its contacts, the spot, the base, the units it joined).
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

STEP_S = 10.0
MOVE_D = 150.0
MIN_HOLD_S = 30.0
CL_R = 800.0
THREAT_R = 1000.0
SPOT_R = 200.0
SPOT_WAIT_S = 60.0
BASE_R = 1500.0
JOIN_R = 400.0
GROUP_R = 600.0
ALIGN_COS = 0.5
FWD_D = 0.05      # a force episode gaining this much depth on the start-to-start axis goes forward
FWD_BINS = ((0, 8), (8, 16), (16, 24), (24, 1e9))
CLASSES = ("cluster", "lone", "army", "threat", "spot", "base", "join", "none")


def read_game(path, who, top_q, winners, skill_cut, shuffle, model_team=None, side=""):
    g = Game(path, rng=np.random.default_rng(0))
    z = np.load(path)
    teams = {int(t[0]): (int(t[1]), bool(t[2]), float(t[3])) for t in z["teams"]}
    sides = pick_sides(g, teams, who, top_q, winners, skill_cut)
    if side and model_team is not None:
        mal = teams[model_team][0]
        sides = [s_ for s_ in sides if (s_ == mal) == (side == "model")]
    if not sides:
        return None
    step = int(STEP_S * 30)
    end_f = int(g.frames.max())
    com = g.ucls == CLS_COM
    start = {}
    for t in np.unique(g.uteam[com]):
        m = com & (g.uteam == t)
        j = int(np.argmin(g.frames[m]))
        start[int(t)] = (float(g.units[m][j, 4]), float(g.units[m][j, 5]))
    spots = g.spots if len(g.spots) else np.zeros((0, 2))
    # per step: every unit's position, def, alliance; living buildings per alliance with their cluster metal
    snap = {}
    for f in range(step, end_f + 1, step):
        r = g.rows_at(f)
        if not len(r):
            continue
        ru = g.units[r]
        built = ru[:, 9] >= 1.0
        st = (g.ucls[r] == CLS_STATIC) & built
        bl = {}
        for al in g.allies:
            m = st & (g.ually[r] == al)
            bx, bz, bm = ru[m, 4], ru[m, 5], g.d_metal[g.udef[r][m]]
            clm = ((bx[:, None] - bx[None, :]) ** 2 + (bz[:, None] - bz[None, :]) ** 2 <= CL_R ** 2) @ bm if len(bx) \
                else np.zeros(0)
            bl[al] = (g.uid[r][m], bx, bz, clm)
        snap[f] = (g.uid[r], ru[:, 4], ru[:, 5], g.udef[r], g.ually[r], built, bl)
    # hits per unit, as dealer and as the one hit: (frame, other uid, metal-weighted damage)
    dealt, taken = defaultdict(list), defaultdict(list)
    for fr, a, v, dmg in g.hits:
        vi = g._pos(int(v), fr)
        if vi is None:
            continue
        val = min(float(dmg) / max(float(g.d_hp[vi[3]]), 1.0), 1.0) * float(g.d_metal[vi[3]])
        if a >= 0:
            dealt[int(a)].append((int(fr), int(v), val, vi[0], vi[1], vi[3]))
            ai = g._pos(int(a), fr)
            if ai is not None:
                taken[int(v)].append((int(fr), int(a), val, ai[0], ai[1], ai[3]))
    for dct in (dealt, taken):
        for u in dct:
            dct[u].sort()
    rng = np.random.default_rng(1)
    eps = []
    for ally in sides:
        foe_starts = [start[t] for t, v in teams.items() if v[0] != ally and t in start]
        own_starts = [start[t] for t, v in teams.items() if v[0] == ally and t in start]
        if not foe_starts or not own_starts:
            continue
        o_ = np.mean(own_starts, 0)
        ax_ = np.mean(foe_starts, 0) - o_
        L2_ = float(ax_ @ ax_) or 1.0

        def depth(x, z_, o_=o_, ax_=ax_, L2_=L2_):
            return float(((x - o_[0]) * ax_[0] + (z_ - o_[1]) * ax_[1]) / L2_)
        tracks = defaultdict(list)  # uid -> [(f, x, z, def)]
        army_m = {}  # frame -> this side's armed metal
        for f, (uids, xs, zs, ds, als, built, _bl) in snap.items():
            m = (als == ally) & built & np.isin(g.d_cls[ds], (CLS_ARMY, CLS_AIR)) & ((g.d_g[ds] + g.d_a[ds]) > 0)
            army_m[f] = float(g.d_metal[ds[m]].sum())
            for u, x, z_, d in zip(uids[m].tolist(), xs[m].tolist(), zs[m].tolist(), ds[m].tolist()):
                tracks[u].append((f, x, z_, d))
        side_eps = []
        for u, tr in tracks.items():
            if len(tr) < 2:
                continue
            fr = np.array([t_[0] for t_ in tr])
            xs = np.array([t_[1] for t_ in tr])
            zs = np.array([t_[2] for t_ in tr])
            dfu = tr[0][3]
            moved = np.r_[False, np.hypot(np.diff(xs), np.diff(zs)) > MOVE_D]
            dl, tk = dealt.get(u, []), taken.get(u, [])
            dlf = np.array([h[0] for h in dl]) if dl else np.zeros(0)
            tkf = np.array([h[0] for h in tk]) if tk else np.zeros(0)
            contact = np.array([(np.searchsorted(dlf, f_, "right") - np.searchsorted(dlf, f_ - step, "right")
                                 + np.searchsorted(tkf, f_, "right") - np.searchsorted(tkf, f_ - step, "right")) > 0
                                for f_ in fr])
            moving = moved & ~contact
            # a pause shorter than MIN_HOLD_S does not end the trip
            i_ = 0
            while i_ < len(moving):
                if not moving[i_]:
                    j_ = i_
                    while j_ < len(moving) and not moving[j_]:
                        j_ += 1
                    if (j_ - i_) * STEP_S < MIN_HOLD_S and i_ > 0 and j_ < len(moving):
                        moving[i_:j_] = True
                    i_ = j_
                else:
                    i_ += 1
            # episode boundaries: a moving sample after a held one (and the first sample)
            starts = [0] + [i for i in range(1, len(fr)) if moving[i] and not moving[i - 1]]
            for si, a0 in enumerate(starts):
                b0 = starts[si + 1] if si + 1 < len(starts) else len(fr)
                held = np.nonzero(~moving[a0:b0])[0]
                hold_i = a0 + int(held[0]) if len(held) else b0 - 1
                if not moving[a0:b0].any():
                    continue  # no trip: a unit that only stood
                f0, f1 = int(fr[a0]), int(fr[b0 - 1])
                side_eps.append({"u": u, "f0": f0, "f1": f1, "x0": float(xs[a0]), "z0": float(zs[a0]),
                                 "hx": float(xs[hold_i]), "hz": float(zs[hold_i]), "def": dfu,
                                 "dl": [h for h in dl if f0 - step < h[0] <= f1],
                                 "tk": [h for h in tk if f0 - step < h[0] <= f1]})
        for e in side_eps:
            lab, ox, oz = label(e, snap, step, ally, spots, foe_starts, g.d_cls)
            hx, hz = e["hx"], e["hz"]
            if shuffle and len(side_eps) > 1:
                o_ = side_eps[int(rng.integers(len(side_eps)))]
                hx, hz = e["x0"] + (o_["hx"] - o_["x0"]), e["z0"] + (o_["hz"] - o_["z0"])
            tv = np.array([hx - e["x0"], hz - e["z0"]])
            ov = np.array([ox - e["x0"], oz - e["z0"]]) if ox is not None else None
            if ov is None or np.hypot(*tv) < MOVE_D or np.hypot(*ov) < 1.0:
                al = None
            else:
                al = float(tv @ ov / (np.hypot(*tv) * np.hypot(*ov))) >= ALIGN_COS
            e["lab"], e["al"], e["w"] = lab, al, float(g.d_metal[e["def"]])
        # one force episode per group of unit episodes that start in the same step within GROUP_R of each other
        by_f = defaultdict(list)
        for e in side_eps:
            by_f[e["f0"]].append(e)
        for f0, es in by_f.items():
            left = list(es)
            while left:
                seed_ = left.pop(0)
                grp = [seed_] + [e for e in left if (e["x0"] - seed_["x0"]) ** 2 + (e["z0"] - seed_["z0"]) ** 2 <= GROUP_R ** 2]
                left = [e for e in left if e not in grp]
                wl = defaultdict(float)
                for e in grp:
                    wl[e["lab"]] += e["w"] + 1e-6
                lab = max(wl, key=wl.get)
                als = [e["al"] for e in grp if e["lab"] == lab and e["al"] is not None]
                al = (sum(als) * 2 >= len(als)) if als else None
                # forward (its members' mean heading gains depth on the start-to-start axis) and its share of the army
                gx0 = np.mean([e["x0"] for e in grp]), np.mean([e["z0"] for e in grp])
                gh = np.mean([e["hx"] for e in grp]), np.mean([e["hz"] for e in grp])
                fwd = depth(*gh) - depth(*gx0) > FWD_D
                eps.append((lab, al, max((e["f1"] - e["f0"]) / 30.0 for e in grp), sum(e["w"] for e in grp), len(grp),
                            f0, fwd, army_m.get(f0, 0.0)))
    return eps, len(sides)


def label(e, snap, step, ally, spots, foe_starts, d_cls):
    val = defaultdict(float)
    px = defaultdict(float)
    pz = defaultdict(float)
    for hs in (e["dl"], e["tk"]):
        for fr, other, v, x, z_, d in hs:
            f_ = fr - fr % step + step
            sn = snap.get(f_) or snap.get(f_ - step)
            if sn is None:
                continue
            uids, xs, zs, ds, als, built, bl = sn
            from_static = bool(np.isin(other, np.concatenate([bl[a_][0] for a_ in bl if a_ != ally]))) if bl else False
            if from_static:
                cl = 0.0
                for a_, (bu, bx, bz, clm) in bl.items():
                    if a_ == ally:
                        continue
                    i = np.nonzero(bu == other)[0]
                    if len(i):
                        cl = float(clm[i[0]])
                c = "cluster" if cl >= FLOOR else "lone"
            else:
                ob = bl.get(ally)
                near_ours = ob is not None and len(ob[1]) and bool(((ob[1] - x) ** 2 + (ob[2] - z_) ** 2 <= THREAT_R ** 2).any())
                c = "threat" if near_ours else "army"
            val[c] += v
            px[c] += v * x
            pz[c] += v * z_
    if val:
        c = max(val, key=val.get)
        return c, px[c] / val[c], pz[c] / val[c]
    hx, hz = e["hx"], e["hz"]
    if len(spots):
        d2 = (spots[:, 0] - hx) ** 2 + (spots[:, 1] - hz) ** 2
        i = int(np.argmin(d2))
        if d2[i] <= SPOT_R ** 2:
            sx_, sz_ = float(spots[i, 0]), float(spots[i, 1])
            fa = e["f1"] - e["f1"] % step
            fb = fa + int(SPOT_WAIT_S * 30)
            before = snap.get(fa) or snap.get(fa + step)
            after = snap.get(fb - fb % step) or snap.get(fb - fb % step - step)
            if before is not None and after is not None:
                def near_set(sn, mine):
                    out = set()
                    for a_, (bu, bx, bz, _c) in sn[6].items():
                        if (a_ == ally) == mine and len(bx):
                            out |= set(bu[(bx - sx_) ** 2 + (bz - sz_) ** 2 <= (2 * SPOT_R) ** 2].tolist())
                    return out
                rose = near_set(after, True) - near_set(before, True)
                fell = near_set(before, False) - near_set(after, False)
                if rose or fell:
                    return "spot", sx_, sz_
    for bx_, bz_ in foe_starts:
        if (hx - bx_) ** 2 + (hz - bz_) ** 2 <= BASE_R ** 2:
            return "base", bx_, bz_
    sn = snap.get(e["f1"] - e["f1"] % step)
    if sn is not None:
        uids, xs, zs, ds, als, built, _bl = sn
        m = (als == ally) & built & (uids != e["u"]) & np.isin(d_cls[ds], (CLS_ARMY, CLS_AIR))
        near = m & ((xs - hx) ** 2 + (zs - hz) ** 2 <= JOIN_R ** 2)
        if near.any():
            return "join", float(xs[near].mean()), float(zs[near].mean())
    return "none", None, None




def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("roots", nargs="+")
    ap.add_argument("--who", choices=("own", "players", "all"), default="all")
    ap.add_argument("--top-quartile", action="store_true")
    ap.add_argument("--winners", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--match", default="")
    ap.add_argument("--shuffle", action="store_true")
    ap.add_argument("--mvr-log", default="")
    ap.add_argument("--side", choices=("", "model", "rules"), default="")
    a = ap.parse_args()
    fs = files(a.roots)
    if a.match:
        keys = a.match.split(",")
        fs = [p for p in fs if any(k in os.path.basename(p) for k in keys)]
    fs = fs[: a.limit or None]
    mt = {}
    for lg in filter(None, a.mvr_log.split(",")):
        for ln in open(lg, encoding="utf-8"):
            p_ = ln.split()
            if len(p_) >= 7 and p_[0] == "seed":
                mt[Path(p_[6]).name] = int(p_[3].lstrip("t"))
    skill_cut = -1e9
    if a.top_quartile:
        sk = []
        for p in fs:
            try:
                sk += [float(t[3]) for t in np.load(p)["teams"] if not t[2] and t[3] >= 0]
            except Exception:  # noqa: BLE001
                pass
        skill_cut = float(np.percentile(sk, 75)) if sk else -1e9
    E, n_sides, games = [], 0, 0
    for p in fs:
        try:
            o = read_game(p, a.who, a.top_quartile, a.winners, skill_cut, a.shuffle, mt.get(Path(p).stem), a.side)
        except Exception as ex:  # noqa: BLE001
            print("skip", os.path.basename(p), type(ex).__name__, ex, file=sys.stderr)
            continue
        if not o:
            continue
        games += 1
        E += o[0]
        n_sides += o[1]
    if not E:
        print("no episodes")
        return
    n = len(E)
    print("games %d  sides %d  episodes %d (%.0f per side-game; median length %.0f s)%s" % (
        games, n_sides, n, n / max(n_sides, 1), float(np.median([e[2] for e in E])), "  SHUFFLED headings" if a.shuffle else ""))
    by = defaultdict(int)
    for e in E:
        by[e[0]] += 1
    print("label      " + "  ".join("%s %.3f" % (c, by[c] / n) for c in CLASSES))
    al = [e for e in E if e[1] is not None]
    print("aligned    %.3f of the %d episodes with a heading and a place  | by label: %s" % (
        sum(1 for e in al if e[1]) / max(len(al), 1), len(al),
        "  ".join("%s %.2f" % (c, sum(1 for e in al if e[0] == c and e[1]) / max(sum(1 for e in al if e[0] == c), 1))
                  for c in CLASSES if c != "none")))
    lab_al = defaultdict(int)
    for e in E:
        if e[0] != "none" and e[1] is not False:
            lab_al[e[0]] += 1
    print("aligned label (contact/stand label whose heading agrees, or no heading needed): " +
          "  ".join("%s %.3f" % (c, lab_al[c] / n) for c in CLASSES if c != "none"))
    fw = [e for e in E if e[6] and e[7] > 0]
    parts = []
    for lo, hi in FWD_BINS:
        sh = [e[3] / e[7] for e in fw if lo <= e[5] / 1800.0 < hi]
        if sh:
            parts.append("%g-%s min %.2f (q75 %.2f, n %d)" % (lo, "%g" % hi if hi < 1e9 else "", float(np.median(sh)),
                                                         float(np.percentile(sh, 75)), len(sh)))
    print("forward    force metal at the start of a forward episode, share of the side's army (median): " + "  ".join(parts))


if __name__ == "__main__":
    main()
