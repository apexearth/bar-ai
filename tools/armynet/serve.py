#!/usr/bin/env python3
"""Run the army model for a local game through game-patches/gadgets/dev_armynet.lua.

    python tools/armynet/serve.py --dir <the game's write dir> --model runtime/armynet/<run>/model.pt [--seed 1]

Reads armynet_static.txt once and armynet_state.txt each time its frame advances; answers in armynet_orders.txt
(written whole, then renamed). Our AI's units count as ours in the view, as a player's own units did in training;
orders go to the holder's units only. Each unit takes a new order with the probability the model gives (players
give one about every ten seconds per unit); the kind and place are the model's best.
"""
import os
from collections import defaultdict
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import ABSENT_ON, CLASSES, G, MEMORY_S, RECENT_S, STAT_F, STEP, Game, absence_ctx, absent_of, base_axis, collate, face_dir, fold_history, history_rows, unit_stats  # noqa: E402
import netrun  # noqa: E402
from netrun import sigmoid, softmax  # noqa: E402
from tasks import GROUP_R, Tracker, cluster_targets  # noqa: E402

KIND_CMD = {0: 0, 1: 10, 2: 16, 3: 20, 4: 16, 5: 15}
# players' line drags: median 415 elmos for a median 7-unit click (group_orders.py, 40 games), ~64 between units
LINE_GAP = 64.0
SHAPES = {"point": 0, "line": 0, "arc": 0}  # force orders by shape, logged each minute
COMMIT = {"kept": 0, "changed": 0}  # --commit: decisions that kept the force's order or changed it, logged each minute
ROWS = {"forces": 0, "rows": 0}  # arc formations and their rows (his 11-22: not 7-8 deep)
ARC_ROWS = 3          # --arc-rows
RANGE_FRAC = 0.95     # --range-frac: how far back past the front a unit may stand, as a share of its range
STANDOFF = 0.0        # --standoff F: the front arc no further than F x the shortest armed range from what it faces (0 off)
KIND_MODE = "model"   # --kind-mode model|fight|fightnear
CLUSTER_FIGHT = False  # --cluster-fight: a move aimed within reach of a known enemy cluster or their presumed base goes as a fight order (todo/armynet-objectives.md E1)
FORCE_IDLE = False     # --force-idle: a force standing idle at its target is asked every decision, no click roll (E2)
CLUSTER_FLOOR = 2000.0  # metal of known enemy buildings within CLUSTER_R that makes a cluster (objectives_army.FLOOR)
CLUSTER_R = 800.0
E_DETAIL = defaultdict(int)  # (force size, place, new/old, answer) -> E2 forced answers
SRC_LOG = False              # orders by source and aimed cell (issues/army-off-axis-corner.md); on in test games
SRC_COUNT = defaultdict(int)  # (source, turned-frame cell 0-8) -> orders
TURN = [None]                 # (flip x, flip z) so our buildings' centre is bottom-left
POINTER = False               # --pointer: an attack goes to the enemy the target head picks (model with t_query)
PTR_LOG = [0, 0]              # attacks sent by the pointer, attacks that fell back to the nearest rule
E_LOG = {"fight": 0, "moves": 0, "forced": 0, "same": 0, "deeper": 0, "sideways": 0, "back": 0, "released": 0}
FORCE_THREAT = False   # --force-threat: when an enemy armed unit is newly seen within reach of our buildings or builders, every force is asked that step
T_LOG = {"steps": 0, "answers": []}  # (answer, force metal / raid metal) per forced force
FORCE_FIRE = False     # --force-fire: a force with a member newly hurt (hp lost in the last 5 s) is asked that step
FORCE_SEEN = False     # --force-seen: a known enemy cluster that was not there at the last step: every force is asked
V_LOG = {"fire": {"events": 0, "answers": []}, "seen": {"events": 0, "answers": []}}


def answer_to(tx, tz, fx, fz, pt, axis):
    """Where a forced answer went: stay (within 300), toward / away from `pt` (300 closer / farther), else by the
    start-to-start axis forward / back / sideways."""
    if np.hypot(tx - fx, tz - fz) < 300.0:
        return "stay"
    if pt is not None:
        d0, d1 = np.hypot(fx - pt[0], fz - pt[1]), np.hypot(tx - pt[0], tz - pt[1])
        if d1 < d0 - 300.0:
            return "toward"
        if d1 > d0 + 300.0:
            return "away"
    dv = float(axis(tx, tz)) - float(axis(fx, fz))
    return "forward" if dv > 0.05 else ("back" if dv < -0.05 else "sideways")


def cluster_cells(grid, sx, sz):
    """Positions of remembered enemy buildings whose metal within CLUSTER_R reaches CLUSTER_FLOOR (grid channel 8)."""
    w = np.expm1(np.clip(grid[8], 0, 20))
    zz, xx = np.nonzero(w > 0)
    if not len(zz):
        return np.zeros((0, 2))
    px, pz, m = (xx + .5) * sx, (zz + .5) * sz, w[zz, xx]
    d2 = (px[:, None] - px[None]) ** 2 + (pz[:, None] - pz[None]) ** 2
    over = (d2 <= CLUSTER_R ** 2) @ m >= CLUSTER_FLOOR
    return np.stack([px[over], pz[over]], 1)
HYB_CLUSTER = False    # --hybrid-cluster: units at a live known enemy cluster go to the AI's own attack until no building is in view (E3)
PLACE_SRC = "cells"   # --place cells|goal
SPLIT_DEFS = 0        # --split-defs: ground forces split by unit def
GATHER = 0            # --gather: a ground force of 1-2 units joins a force with a unit of the same def within GROUP_R (11-24)
GATHER_LOG = [0, 0]   # forces gathered, decisions
UNIT_CONTACT = 0      # --unit-contact: units within 600 of a visible enemy army unit follow the unit heads (11-24)
UC_LOG = [0, 0, 0.0, 0.0]   # in-contact unit-steps, unit orders given, sum of one-step p, unit-steps x gap
HYBRID = 0           # --hybrid: units in contact go back to the AI's own fight logic (11-24)
HYB_HOLD = 90        # frames a released unit stays the AI's, renewed each step it is in contact
HYB_LOG = [0, 0]     # released unit-steps, release lines sent
JUDGE_K = 0          # --judge K: of the place head's top K cells the move judge picks one (11-25: the model proposes, the judge chooses)
JUDGE_LOG = [0, 0]   # force-steps judged, picks that differ from the place head's best
EXPLORE_T = 0.0      # --explore T: self-play only, never his games: a share of force-steps take a place sampled at temperature T
EXPLORE_P = 0.2      # --explore-p: that share
EXPLORE_K = 8        # among the place head's top K cells
EXPLORE_LOG = [0, 0]  # force-steps explored, of those a cell other than the head's best
ARC_INRANGE = 0       # --arc-inrange: the front within the shortest range, no row pushed past its units' range
ARC = {"slots": 0, "in_range": 0, "in_range_old": 0}  # armed units placed on range arcs, and those standing within their range of what the arc faces


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from replay_dataset import ECO  # noqa: E402
from movement import movement  # noqa: E402
from economy import income  # noqa: E402


def force_orders(members, p, kind_probs, cell_probs, off, ux, uz, rng_of, cell_fwd, axis, sx, sz, rng, layer):
    """One order for a force, the way a player clicks a group (his 11-20): one draw on the members' mean chance, one
    kind and one place from their summed distributions (direction first, as for a unit), then a line across the enemy
    direction at the target. With `layer` (his 11-20, measured as its own arm: players do not do it) the shortest-range
    armed units stand on the line and each longer-range one is set back toward our side by its extra range, so every
    gun reaches the same front; units with no gun stand one row behind the last. Returns None, or (kind, [(member,
    x, z)])."""
    if rng.random() >= float(np.mean(p[members])):
        return None
    k = int(kind_probs[members].mean(0).argmax())
    cx, cz = float(ux[members].mean()), float(uz[members].mean())
    probs = cell_probs[members].mean(0)
    fu = float(axis(cx, cz))
    back, fwd = cell_fwd < fu - 0.1, cell_fwd > fu + 0.1
    regions = [back, fwd, ~(back | fwd)]
    mass = np.array([probs[r].sum() for r in regions])
    if mass.sum() <= 0:
        return None
    pick = int(min((rng.random() > np.cumsum(mass / mass.sum())).sum(), 2))
    c = int(np.where(regions[pick], probs, -1.0).argmax())
    j0 = members[int(np.argmax(p[members]))]
    tx, tz = (c % G + off[j0, 0]) * sx, (c // G + off[j0, 1]) * sz
    if k in (0, 3) or len(members) == 1:
        return k, [(j, tx, tz) for j in members]
    # toward the enemy at the target: the way the forward axis rises
    h = 64.0
    ex_, ez_ = float(axis(tx + h, tz)) - float(axis(tx - h, tz)), float(axis(tx, tz + h)) - float(axis(tx, tz - h))
    n = (ex_ * ex_ + ez_ * ez_) ** 0.5
    if n <= 0:
        dx, dz = tx - cx, tz - cz
        n = (dx * dx + dz * dz) ** 0.5
        if n < 1.0:
            return k, [(j, tx, tz) for j in members]
        ex_, ez_ = dx, dz
    ex_, ez_ = ex_ / n, ez_ / n
    lx, lz = -ez_, ex_
    rngs = np.array([rng_of.get(int(j), 0.0) for j in members])
    armed = rngs > 0
    if layer and armed.any():
        depth = np.where(armed, rngs - rngs[armed].min(), 0.0)
        depth[~armed] = depth[armed].max() + LINE_GAP
    else:
        depth = np.zeros(len(members))
    rows = {}
    for j, dpt in zip(members, depth):
        rows.setdefault(int(round(dpt / LINE_GAP)), []).append(int(j))
    out = []
    for r, js in rows.items():
        js = sorted(js, key=lambda j: (ux[j] - cx) * lx + (uz[j] - cz) * lz)
        for i, j in enumerate(js):
            s = (i - (len(js) - 1) / 2.0) * LINE_GAP
            out.append((j, tx - ex_ * r * LINE_GAP + lx * s, tz - ez_ * r * LINE_GAP + lz * s))
    return k, out


def arc_slots(members, tx, tz, pt, length, rngs, armed, ux, uz):
    """Range arcs (his 11-21: "you can draw curves", which units stand in front or behind): the force stands on arcs
    around what it faces (pt), the front arc through the model's chosen place, each unit stepped back by how much
    its range exceeds the shortest (unarmed ones a row behind all), spread along its arc by the learned length,
    never wider than a half circle. Players don't draw these (2% curved, no range layering), so this is a design."""
    px, pz = pt
    r0 = float(np.hypot(tx - px, tz - pz))
    if ((STANDOFF > 0.0) or ARC_INRANGE) and armed.any():
        r0 = min(r0, (STANDOFF if STANDOFF > 0.0 else RANGE_FRAC) * float(rngs[armed].min()))   # the front at fighting range
    th0 = float(np.arctan2(tz - pz, tx - px))
    if armed.any():
        depth = np.where(armed, rngs - rngs[armed].min(), 0.0)
        # his 11-22 watch: Centurions in front, Thugs and Rocket bots stepped so far back they only watched -- the steps
        # were added to the chosen place, which may already stand off. No unit stands back past its own range from what
        # it faces, and none in front of the front arc
        ARC["in_range_old"] += int(((r0 + depth[armed]) <= rngs[armed]).sum())
        depth = np.where(armed, np.maximum(np.minimum(r0 + depth, RANGE_FRAC * rngs) - r0, 0.0), depth)
        depth[~armed] = depth[armed].max() + LINE_GAP
        ARC["slots"] += int(armed.sum())
        ARC["in_range"] += int(((r0 + depth[armed]) <= rngs[armed]).sum())
    else:
        depth = np.zeros(len(members))
    # AT MOST ARC_ROWS ROWS (his 11-22: "formations 7 or 8 lines deep ... totally inefficient for keeping units within
    # fighting range to concentrate their fire"): a row per distinct range stacked one row per type; the units are now
    # cut by their wanted depth into at most ARC_ROWS rows of equal count, each row standing at the shallowest depth any
    # of its units wants -- so every unit stays inside its range -- and the rows widen instead of deepening
    order = sorted(range(len(members)), key=lambda q: depth[q])
    nrow = min(ARC_ROWS, len(set(np.round(depth / LINE_GAP).astype(int).tolist())))
    per = int(np.ceil(len(members) / max(nrow, 1)))
    rows = {}
    for q_i, q in enumerate(order):
        rows.setdefault(q_i // per, []).append((int(members[q]), float(depth[q])))
    ROWS["forces"] += 1
    ROWS["rows"] += len(rows)
    widest = max(len(v) for v in rows.values())
    gap = max(length / max(widest - 1, 1), 40.0)
    out = []
    for r, jd in rows.items():
        js = [j for j, _ in jd]
        rad = r0 + min(d for _, d in jd)
        if out:
            rad = max(rad, prev_rad + LINE_GAP)   # a row never stands on the one before it...
            if ARC_INRANGE:
                # ...unless that takes one of its armed units out of its range (his 11-22: arcs, but every unit that
                # has to fire within range): then it shares the arc before it, spread along it
                lim = min((RANGE_FRAC * rngs[members.tolist().index(j)] for j, _ in jd if armed[members.tolist().index(j)]),
                          default=rad)
                rad = min(rad, max(lim, r0))
        prev_rad = rad
        rel = {j: (float(np.arctan2(uz[j] - pz, ux[j] - px)) - th0 + np.pi) % (2 * np.pi) - np.pi for j in js}
        js = sorted(js, key=rel.get)
        dphi = min(gap / rad, np.pi / max(len(js) - 1, 1))
        for i, j in enumerate(js):
            phi = th0 + (i - (len(js) - 1) / 2.0) * dphi
            out.append((j, px + rad * float(np.cos(phi)), pz + rad * float(np.sin(phi))))
    return out


def learned_force_order(members, pf, kind_p, cell_p, off_f, spread_p, shape, ux, uz, rng_of, cell_fwd, axis, sx, sz,
                        rng, layer, dirfirst=True, grid=None, arc=False, commit=0.0, cur=None, fight_near=False):
    """One force's order from the force heads (11-20): the click chance, kind and place are the model's for the force;
    point or line and the line's length and angle to the enemy direction too (learned from players' drags), so the
    hand geometry above is only the switch's fallback. With `layer` the rows step back by range as in force_orders.
    `dirfirst` picks back / hold / forward first as for units; without it the place is drawn from the force's own
    distribution (11-20 review: the hold band is ~600-900 elmos, and players' median click of 650 falls inside it)."""
    if rng.random() >= pf:
        return None
    k = int(kind_p.argmax())
    # --kind-mode (his 11-22: "a fight order so that you will move as close as you need to to get into range"; some
    # units gain from dodging on a plain move): fight = every move a fight order; fightnear = a fight order while a
    # fight is on within 1,500 of the force, else the model's kind
    if (k == 1) and ((KIND_MODE == "fight") or ((KIND_MODE == "fightnear") and fight_near)):
        k = 2
    cx, cz = float(ux[members].mean()), float(uz[members].mean())
    if commit > 0.0:
        # his 11-22 ("this is what you're currently doing, would you change it?"): keep the order the force has while
        # the place head rates its destination at least `commit` of its best place (3x3 cells each); otherwise go to
        # the best place itself -- no region draw, which re-drawn every decision zigzagged back, hold and forward
        def around(c0):
            r0, c_ = divmod(int(c0), G)
            return float(cell_p.reshape(G, G)[max(r0 - 1, 0):r0 + 2, max(c_ - 1, 0):c_ + 2].sum())
        best = int(cell_p.argmax())
        if cur is not None:
            cc = int(np.clip(cur[1] / sz, 0, G - 1)) * G + int(np.clip(cur[0] / sx, 0, G - 1))
            if around(cc) >= commit * around(best):
                COMMIT["kept"] += 1
                return None
        COMMIT["changed"] += 1
        c = best
    elif dirfirst:
        fu = float(axis(cx, cz))
        back, fwd = cell_fwd < fu - 0.1, cell_fwd > fu + 0.1
        regions = [back, fwd, ~(back | fwd)]
        mass = np.array([cell_p[r].sum() for r in regions])
        if mass.sum() <= 0:
            return None
        pick = int(min((rng.random() > np.cumsum(mass / mass.sum())).sum(), 2))
        c = int(np.where(regions[pick], cell_p, -1.0).argmax())
    else:
        pp = cell_p / max(float(cell_p.sum()), 1e-12)
        c = int(min(np.searchsorted(np.cumsum(pp), rng.random()), len(pp) - 1))
    tx, tz = (c % G + off_f[0]) * sx, (c // G + off_f[1]) * sz
    if k in (0, 3) or len(members) == 1 or ((spread_p < 0.5) if commit > 0.0 else (rng.random() >= spread_p)):
        SHAPES["point"] += 1
        return k, c, [(int(j), tx, tz) for j in members]
    h = 64.0
    ex_, ez_ = float(axis(tx + h, tz)) - float(axis(tx - h, tz)), float(axis(tx, tz + h)) - float(axis(tx, tz - h))
    n = (ex_ * ex_ + ez_ * ez_) ** 0.5
    if n <= 0:
        return k, c, [(int(j), tx, tz) for j in members]
    ex_, ez_ = ex_ / n, ez_ / n
    ang = 0.5 * float(np.arctan2(shape[2], shape[1]))
    ca, sa = float(np.cos(ang)), float(np.sin(ang))
    lx, lz = ex_ * ca - ez_ * sa, ex_ * sa + ez_ * ca    # the line's own direction
    length = float(np.expm1(np.clip(shape[0], 0, 1.2) * 7))
    rngs = np.array([rng_of.get(int(j), 0.0) for j in members])
    armed = rngs > 0
    pt = face_dir(grid, tx, tz, sx, sz, axis, point=True)[2:] if arc and grid is not None else (None, None)
    if pt[0] is not None and np.hypot(tx - pt[0], tz - pt[1]) > 100:
        SHAPES["arc"] += 1
        return k, c, arc_slots(members, tx, tz, pt, length, rngs, armed, ux, uz)
    if layer and armed.any():
        depth = np.where(armed, rngs - rngs[armed].min(), 0.0)
        depth[~armed] = depth[armed].max() + LINE_GAP
    else:
        depth = np.zeros(len(members))
    rows = {}
    for j, dpt in zip(members, depth):
        rows.setdefault(int(round(dpt / LINE_GAP)), []).append(int(j))
    widest = max(len(v) for v in rows.values())
    gap = max(length / max(widest - 1, 1), 24.0)
    out = []
    for r, js in rows.items():
        js = sorted(js, key=lambda j: (ux[j] - cx) * lx + (uz[j] - cz) * lz)
        for i, j in enumerate(js):
            s = (i - (len(js) - 1) / 2.0) * gap
            out.append((j, tx - ex_ * r * LINE_GAP + lx * s, tz - ez_ * r * LINE_GAP + lz * s))
    SHAPES["line"] += 1
    return k, c, out


def cluster_near(grid, tx, tz, reach, sx, sz, axis):
    """The largest known enemy building cluster (metal within CLUSTER_R of a remembered building) among the buildings
    within `reach` of (tx, tz), from the model's own input (grid channel 8 = log1p of remembered building metal per
    cell); with nothing of theirs known anywhere, their presumed base (the far end of the axis) counts as a cluster."""
    w = np.expm1(np.clip(grid[8], 0, 20))
    if w.sum() <= 0:
        return CLUSTER_FLOOR if float(axis(tx, tz)) > 0.8 else 0.0
    zz, xx = np.nonzero(w > 0)
    px, pz = (xx + .5) * sx, (zz + .5) * sz
    inr = (px - tx) ** 2 + (pz - tz) ** 2 <= reach * reach
    if not inr.any():
        return 0.0
    best = 0.0
    for x_, z_ in zip(px[inr], pz[inr]):
        best = max(best, float(w[zz, xx][(px - x_) ** 2 + (pz - z_) ** 2 <= CLUSTER_R ** 2].sum()))
    return best


DEF_NAMES = []  # one per D line, in the defs order (the army model's full stats are looked up by name)


def read_static(d):
    defs, teams, allies, spots, holders, heights, mapxz = [], [], [], [], [], None, (0, 0)
    for ln in open(d / "armynet_static.txt", encoding="utf-8", errors="replace"):
        p = ln.split()
        if not p:
            continue
        if p[0] == "D":
            DEF_NAMES.append(p[2])
            # the AI-side bridge (ArmyNetBridge.cpp) writes id, name, class only: the stats come from defs.json by the
            # recorder's own formula, so live inputs match the recordings
            stats = [float(v) for v in p[4:13]] if len(p) >= 13 else [float(v) for v in unit_stats().d_line(p[2])]
            defs.append([float(p[1]), float(CLASSES.index(p[3]) if p[3] in CLASSES else 7)] + stats
                        + [float(p[3] == "static" and bool(ECO.search(p[2])))] + list(movement(p[2]))
                        + [income(p[2])])
        elif p[0] == "T":
            teams.append([int(p[1]), int(p[2]), p[3] == "true", -1.0])  # skill unknown (an AI), unless --skill
        elif p[0] == "A":
            allies = [int(v) for v in p[1:]]
        elif p[0] == "Q":
            holders.append((int(p[1]), int(p[2])))
        elif p[0] == "S":
            spots.append((float(p[2]), float(p[3])))
        elif p[0] == "V":
            mapxz = (int(p[2]), int(p[3]))
        elif p[0] == "H":
            step = int(p[1])
            h = np.array([float(v) for v in p[2:]], np.float32)
            nx = len(range(step // 2, mapxz[0] + 1, step))
            heights = h[: (len(h) // nx) * nx].reshape(-1, nx)
    return (np.array(defs, np.float32), teams, allies, np.array(spots, np.float32).reshape(-1, 2), holders,
            heights if heights is not None else np.zeros((0, 0), np.float32), mapxz)


def read_state(d, last):
    try:
        if last >= 0 and time.time() - (d / "armynet_state.txt").stat().st_mtime > 60:
            # his 11-24 game: the next game's bots were other teams, so this folder went still and serve waited on it
            print("state file still for 60 s: the game ended; exiting for a restart", flush=True)
            raise SystemExit(3)
        text = (d / "armynet_state.txt").read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None, None
    lines = text.splitlines()
    if len(lines) < 2 or not lines[0].startswith("F ") or not lines[-1].startswith("E "):
        return None, None
    frame = int(lines[0].split()[1])
    if last >= 0 and frame + 900 < last:
        # the frame went back 30 s or more: a new game in the same folder (play_online.py starts a fresh serve)
        print("new game (frame %d after %d): exiting for a restart" % (frame, last), flush=True)
        raise SystemExit(3)
    if frame <= last:
        return None, None
    rows = [[float(v) for v in ln.split()[1:15]] for ln in lines[1:-1] if ln.startswith("U ")]
    hits = [[float(v) for v in ln.split()[1:5]] for ln in lines[1:-1] if ln.startswith("X ")]
    return frame, (np.array(rows, np.float32).reshape(-1, 14), np.array(hits, np.float32).reshape(-1, 4))


def main(a):
    def opt(name, default):
        return a[a.index(name) + 1] if name in a else default
    d = Path(opt("--dir", "."))
    if "--log" in a:
        # started by the bot itself (ArmyNetLaunch), with no console to print to
        sys.stdout = sys.stderr = open(opt("--log", ""), "w", buffering=1, encoding="utf-8")
    if "--find" in a:
        # the AI-side bridge (ArmyNetBridge.inc) writes armynet-t<team>/ under the AI's own folder, and its team number
        # is not known before the game: wait for the first armynet-t*/armynet_static.txt written after this start
        root, t0 = Path(opt("--find", ".")), time.time()
        print("waiting for an armynet-t* folder under %s" % root, flush=True)
        while True:
            # the state file is rewritten every 10 frames, so a game already running is found too
            fresh = [p for p in root.rglob("armynet-t*/armynet_state.txt")
                     if p.stat().st_mtime >= t0 - 5 and (p.parent / "armynet_static.txt").exists()]
            if fresh:
                d = max(fresh, key=lambda p: p.stat().st_mtime).parent
                break
            time.sleep(1)
        print("bridge folder %s" % d, flush=True)
    # one server per bot (ArmyNetLaunch): a few threads each on CPU, so several bots share the cores instead of fighting
    net = netrun.load(opt("--model", ""), cpu="--cpu" in a, threads=int(opt("--threads", "2")))
    dev = net.name
    print("device %s" % dev, flush=True)
    # a checkpoint trained with the member head picks which members a click takes; an older one moves them all
    has_member = net.has_member
    print("member head: %s" % ("picks the click's members" if has_member else "absent, a click takes every member"), flush=True)
    rounds = "--rounds" in a
    forces = "--forces" in a
    layer = "--layer" in a
    learned = "--learned" in a  # the force heads decide (needs a model trained with them)
    dirfirst = "--sample-place" not in a
    # 11-20: replays have no factory rally (a factory's order, not a unit's), so the force head almost never clicks a
    # lone new unit at home (players 0.5% a step); live our factories have none, and 19% of the army stood at home.
    # --rally sends each never-ordered unit to the main force's last click, as a player's rally point would.
    rally_on = "--rally" in a
    arc = "--arc" in a  # range arcs around what the line faces (arc_slots); serve-side geometry, any model (11-21 gate 3: 7/5 up/down in both matchups vs plain lines, kept)
    # the force click chance runs low against players' on held-out games (size 4-8: 3.2% vs 5.7%); a logit bias of
    # 0.39 matches their overall rate (force_rate_diag, model-020000)
    fbias = float(opt("--fbias", "0"))
    # --wake P (his 11-22, "make the random draws situation smarter"): the click head learned a player's per-step chance,
    # which is a human's attention spread over every group; ours has none of that limit. A force standing with no order
    # for WAKE_IDLE_S while one of our units within 1,500 is fighting (hurt in the last 5 s, or ours lost near it: tok 39,
    # 41) clicks at least at P a step; where it goes is still the model's
    wake_p = float(opt("--wake", "0"))
    commit_a = float(opt("--commit", "0"))
    global ARC_ROWS, RANGE_FRAC, STANDOFF, ARC_INRANGE
    ARC_INRANGE = int("--arc-inrange" in a)
    global KIND_MODE
    KIND_MODE = opt("--kind-mode", "model")
    global ABSENT_ON
    if "--absent" in a:
        # the memory fix (data.py absence_marks) as a flag, for launches that pass no environment (ArmyNetLaunch)
        import data as _data
        _data.ABSENT_ON = ABSENT_ON = True
    global CLUSTER_FIGHT, FORCE_IDLE
    CLUSTER_FIGHT, FORCE_IDLE = "--cluster-fight" in a, "--force-idle" in a
    global HYB_CLUSTER, FORCE_THREAT
    HYB_CLUSTER = "--hybrid-cluster" in a
    FORCE_THREAT = "--force-threat" in a
    global SRC_LOG, POINTER
    POINTER = "--pointer" in a
    # on in every test game (a bridge folder under this repo's matches/), off in his own installs; --src-log /
    # --no-src-log override
    SRC_LOG = ("--src-log" in a) or ("--no-src-log" not in a and "matches" in str(opt("--dir", opt("--find", ""))))
    global FORCE_FIRE, FORCE_SEEN
    FORCE_FIRE, FORCE_SEEN = "--force-fire" in a, "--force-seen" in a
    global PLACE_SRC
    PLACE_SRC = opt("--place", "cells")
    global SPLIT_DEFS
    SPLIT_DEFS = int("--split-defs" in a)
    global GATHER
    GATHER = int("--gather" in a)
    global UNIT_CONTACT, HYBRID, JUDGE_K
    JUDGE_K = int(opt("--judge", "0"))
    global EXPLORE_T, EXPLORE_P, EXPLORE_K
    EXPLORE_T = float(opt("--explore", "0"))
    EXPLORE_P = float(opt("--explore-p", str(EXPLORE_P)))
    EXPLORE_K = int(opt("--explore-k", str(EXPLORE_K)))
    HYBRID = int("--hybrid" in a)
    UNIT_CONTACT = int("--unit-contact" in a)
    ARC_ROWS = int(opt("--arc-rows", str(ARC_ROWS)))
    RANGE_FRAC = float(opt("--range-frac", str(RANGE_FRAC)))
    STANDOFF = float(opt("--standoff", str(STANDOFF)))
    print("usage fbias=%.2f commit=%.2f wake=%.2f arc-rows=%d range-frac=%.2f standoff=%.2f dirfirst=%d" % (
        float(opt("--fbias", "0")), commit_a, float(opt("--wake", "0")), ARC_ROWS, RANGE_FRAC, STANDOFF,
        int("--sample-place" not in a)), flush=True)
    WAKE_IDLE_S, WAKE_R = 5.0, 1500.0
    wake_log = []
    rng = np.random.default_rng(int(opt("--seed", "1")))
    while not (d / "armynet_static.txt").exists():
        time.sleep(1)
    time.sleep(1)
    defs, teams, allies, spots, holders, heights, mapxz = read_static(d)
    # the stats table names every unit's stats; without it (or for another game version) the model plays blind
    st = unit_stats()
    if not st:
        raise SystemExit("no unit stats: runtime/armynet/defs.json is missing (run a game with dev_defs_dump=1)")
    known = sum(1 for n in DEF_NAMES if n in st.units)
    print("unit stats for %d of %d unit types" % (known, len(DEF_NAMES)), flush=True)
    if known < 0.8 * max(len(DEF_NAMES), 1):
        print("WARNING: many unit types have no stats -- defs.json is from another game version", flush=True)
    range_by_def = {int(r[0]): float(r[5]) for r in defs}
    cls_by_def = {int(r[0]): int(r[1]) for r in defs}
    metal_by_def = {int(r[0]): float(r[2]) for r in defs}
    armed_by_def = {int(r[0]): float(r[6]) + float(r[7]) > 0 for r in defs}
    ally_by_team = {int(t[0]): int(t[1]) for t in teams}
    threat_prev = {}  # holder -> enemy uids within reach of our buildings or builders at the last step
    hurt_prev, seen_prev = {}, {}  # holder -> our uids hurt at the last step; known cluster positions at the last step
    if not holders:
        sys.exit("no holder seat in the game: add --extra-ai NullAI@<our ally> and --modoption dev_armynet=1")
    team_arr = np.array(teams, np.float32)
    actx = absence_ctx(defs, team_arr, allies) if ABSENT_ON else None
    if "--skill" in a:
        # the skill the model is asked to play at (the data's player rating; data.py scalars), for every side it commands
        for holder_, _src in holders:
            team_arr[team_arr[:, 0] == holder_, 3] = float(a[a.index("--skill") + 1])
    print("map %s, holders %s, device %s" % (mapxz, holders, dev), flush=True)
    history, last = [], -1
    # enemy buildings as each side last saw them, kept past MEMORY_S: training remembers them all game (data.py
    # _memory); without this, by minute 18 most of what it remembers was gone in play (11-19 review)
    seen_static = {}
    static_defs = np.array(sorted(int(r[0]) for r in defs if int(r[1]) == 0), np.int64)
    # unit types our AI keeps (watch.py --keep, the gadget's dev_armynet_keep): never ordered by the model
    keep_names = set(opt("--keep", "").split(","))
    keep_ids = np.array([int(ln.split()[1]) for ln in open(d / "armynet_static.txt", encoding="utf-8", errors="replace")
                         if ln.startswith("D ") and ln.split()[2] in keep_names], np.int64)
    print("mode forces=%d layer=%d learned=%d dirfirst=%d rounds=%d rally=%d fbias=%.2f keep=%d types absent=%d" % (forces, layer, learned, dirfirst, rounds, rally_on, fbias, len(keep_ids), ABSENT_ON),
          flush=True)
    # steps the model did not see: serve reads only the newest state, so a slow decision skips STEP-frame steps; the
    # act head is a per-step chance, so a decision after k steps acts with 1 - (1 - p)^k
    gaps, spent, logged = [], [], -1
    fwd_log, deep_mass_log, spread_log, nn_log = [], [], [], []
    ev_seen = 0
    tracker, order_log = Tracker(), []
    hit_log = []
    fp_log, fkind_log, last_order, rally, rallied, boxed_log = [], [], {}, None, set(), []
    member_log = []  # (force size, members the click took) per click with the member head
    # his 11-22 "maybe you just have bugs": every 5 s, each unit's force as the model sees it, to set against the screen
    dumpf = open(d / "forces_dump.txt", "w") if "--dumpforces" in a else None
    while True:
        frame, rows = read_state(d, last)
        if frame is None:
            time.sleep(0.05)
            continue
        gap = 1.0 if last < 0 else min(max((frame - last) / float(STEP), 1.0), 90.0)
        last = frame
        t0 = time.time()
        rows, new_hits = rows
        # hits over the last 10 s, the window the incoming-fire layers read (data.py _fire_layers)
        if len(new_hits) and (not hit_log or hit_log[-1][0, 0] != new_hits[0, 0]):
            hit_log.append(new_hits)
        while hit_log and hit_log[0][0, 0] <= frame - 300:
            hit_log.pop(0)
        history.append(rows)
        while len(history) > 1 and (not len(history[0]) or history[0][0, 0] < frame - RECENT_S * 30):
            fold_history(seen_static, history.pop(0), len(allies), actx)
        units = history_rows(seen_static, np.concatenate(history), frame, static_defs)
        out = ["O %d" % frame]
        for holder, source in holders:
            u = units.copy()
            u[u[:, 3] == source, 3] = holder
            # the model's own past orders and their tasks, built by the rules training's tasks were (tasks.py)
            past = np.array(order_log, np.float64).reshape(-1, 11)
            starts = np.array([[k, *v] for k, v in tracker.starts.items()], np.float64).reshape(-1, 5)
            hits = np.concatenate(hit_log) if hit_log else np.zeros((0, 4), np.float32)
            g = Game.live(u, defs, mapxz, allies, team_arr, spots, heights, orders=past, task_starts=starts, hits=hits,
                          names=DEF_NAMES, absent=absent_of(seen_static))
            ex = g.example(holder, frame)
            issued = []  # (uid, kind index, x, z, unit x, unit z) of this second's orders
            if not len(ex["tok"]):
                continue
            draws = rng.random(len(ex["uid"]))
            def_of = dict(zip(u[u[:, 0] == frame, 1].astype(np.int64).tolist(), u[u[:, 0] == frame, 2].astype(np.int64).tolist()))
            kept = np.isin(np.array([def_of.get(int(v), -1) for v in ex["uid"]], np.int64), keep_ids)
            sx, sz = mapxz[0] / G, mapxz[1] / G
            n_tok = len(ex["uid"])
            p = np.zeros(n_tok)
            hyb = np.zeros(n_tok, bool)
            kind = np.zeros(n_tok, np.int64)
            cell = np.zeros(n_tok, np.int64)
            off = np.zeros((n_tok, 2))
            # rounds (his 11-19, over-chasing): a third of the units decide, their new orders are shown to the rest as
            # columns 36-38 (training's `reveal`), then the next third; one round when the model predates rounds
            n_rounds = 3 if (rounds and not forces) else 1
            part = rng.integers(0, n_rounds, n_tok)
            o = None
            axis = base_axis(ex["grid"], sx, sz, mapxz[0], mapxz[1])
            cz_, cx_ = np.mgrid[0:G, 0:G]
            cell_fwd = axis((cx_ + .5) * sx, (cz_ + .5) * sz).ravel()
            for rr in range(n_rounds):
                b = collate([ex], numpy=True)
                if True:
                    o_r = net.step(b)
                    # direction first (his 11-19, "kept engaging"): pick back / hold / forward by the probability the
                    # model puts on each, then its best cell there. When players retreated it put 31.5% behind the
                    # unit (10.7% when not) but its single best cell was nearly always forward. Paired, 4 seeds:
                    # 10-min trades 0.57 vs 0.29 for the single best cell, games 32.8 vs 24.6 min.
                    probs = softmax(o_r["cells"][0])
                    fu = np.asarray(axis(ex["tok"][:, 10] * mapxz[0], ex["tok"][:, 11] * mapxz[1]), np.float64)
                    back = cell_fwd[None, :] < fu[:, None] - 0.1
                    fwd = cell_fwd[None, :] > fu[:, None] + 0.1
                    regions = np.stack([back, fwd, ~(back | fwd)], 1)  # unit x (back, forward, hold) x cell
                    mass = (probs[:, None, :] * regions).sum(-1)
                    tot = mass.sum(1, keepdims=True)
                    cum = np.cumsum(mass / np.maximum(tot, 1e-12), 1)
                    pick = np.minimum((rng.random(n_tok)[:, None] > cum).sum(1), 2)
                    sel = regions[np.arange(n_tok), pick] | (tot <= 0)
                    c_np = np.where(sel, probs, -1.0).argmax(1)
                    c_r = c_np.astype(np.int64)
                    off_r = net.offset_at(o_r["h"], o_r["u64"], c_r[None])[0]
                    p_r = 1.0 - (1.0 - sigmoid(o_r["act"][0])) ** gap
                    p_r[kept] = 0.0
                    k_r = o_r["kind"][0].argmax(-1)
                    kp_r = softmax(o_r["kind"][0])
                o = o if o is not None else o_r
                sel = part == rr
                p[sel], kind[sel], cell[sel], off[sel] = p_r[sel], k_r[sel], c_r[sel], off_r[sel]
                if rr + 1 < n_rounds:
                    tok = ex["tok"].copy()
                    tok[sel, 47] = 1
                    for j in np.where(sel)[0]:
                        if draws[j] < p[j] and kind[j] != 0:
                            tx = (cell[j] % G + off[j, 0]) / G
                            tz = (cell[j] // G + off[j, 1]) / G
                            tok[j, 36] = 1
                            tok[j, 37] = (tx - tok[j, 10]) * mapxz[0] / 2000
                            tok[j, 38] = (tz - tok[j, 11]) * mapxz[1] / 2000
                    ex = dict(ex, tok=tok)
            ux_all, uz_all = ex["tok"][:, 10] * mapxz[0], ex["tok"][:, 11] * mapxz[1]
            act = draws < p
            src = np.full(n_tok, "roll", object)   # which part of serve gave each order (SRC_LOG)
            X = (cell % G + off[:, 0]) * sx
            Z = (cell // G + off[:, 1]) * sz
            if forces and learned:
                act[:] = False
                if UNIT_CONTACT and len(ex.get("etok", [])):
                    # 11-24 (Mac, gate 3 + gather): in contact, players order each fighting unit 20-26 times a minute
                    # (hurt pull-backs 14-16), the force clicks 9-11; a unit with a visible enemy army unit within 600
                    # follows the unit heads every step (keep-or-order, kind, back/hold/forward place), not its force
                    et = ex["etok"]
                    bE = STAT_F
                    army_e = (et[:, bE + 3] > 0) & (et[:, bE + 13] > 0) & (et[:, bE + 15] <= 0)
                    if army_e.any():
                        exx, ezz = et[army_e, bE + 8] * mapxz[0], et[army_e, bE + 9] * mapxz[1]
                        ux0, uz0 = ex["tok"][:, 10] * mapxz[0], ex["tok"][:, 11] * mapxz[1]
                        d2 = (ux0[:, None] - exx[None, :]) ** 2 + (uz0[:, None] - ezz[None, :]) ** 2
                        contact = (d2.min(1) <= 600.0 ** 2) & ~kept
                        act = contact & (draws < p) & (kind != 0)
                        src[act] = "unit"
                        # a contact unit that misses its draw stays its force's to click: barring that (vBARb, 11-24)
                        # cut hurt pull-backs 18.4 -> 6.1 a hurt unit-minute and contact damage 1.50 -> 1.31
                        UC_LOG[0] += int(contact.sum())
                        UC_LOG[1] += int(act.sum())
                        UC_LOG[2] += float((1.0 - (1.0 - p[contact]) ** (1.0 / gap)).sum())
                        UC_LOG[3] += float(contact.sum()) * gap
                if HYBRID and len(ex.get("etok", [])):
                    # his 11-24 (the AlphaStar lesson): the model decides where the army goes, the AI's own fight logic
                    # fights. A ground unit with a visible enemy army unit within 600 goes back to the AI for HYB_HOLD
                    # frames, renewed each step it stays in contact; out of contact it returns to the model
                    et = ex["etok"]
                    bE = STAT_F
                    army_e = (et[:, bE + 3] > 0) & (et[:, bE + 13] > 0) & (et[:, bE + 15] <= 0)
                    if army_e.any():
                        exx, ezz = et[army_e, bE + 8] * mapxz[0], et[army_e, bE + 9] * mapxz[1]
                        ux0, uz0 = ex["tok"][:, 10] * mapxz[0], ex["tok"][:, 11] * mapxz[1]
                        d2 = (ux0[:, None] - exx[None, :]) ** 2 + (uz0[:, None] - ezz[None, :]) ** 2
                        air_h = np.array([cls_by_def.get(def_of.get(int(v), -1), 7) == 4 for v in ex["uid"]], bool)
                        hyb = (d2.min(1) <= 600.0 ** 2) & ~kept & ~air_h
                        act &= ~hyb
                        HYB_LOG[0] += int(hyb.sum())
                if HYB_CLUSTER and len(ex.get("etok", [])):
                    # E3 (todo/armynet-objectives.md): a ground unit with a living enemy building in sight within its
                    # reach, at a known cluster, goes to the AI's own attack until none is in view; then back to the
                    # model (with --force-idle, which then must answer)
                    et = ex["etok"]
                    bE = STAT_F
                    bl = (et[:, bE + 13] > 0) & (et[:, bE + 15] > 0)
                    if bl.any():
                        bxx, bzz = et[bl, bE + 8] * mapxz[0], et[bl, bE + 9] * mapxz[1]
                        ux0, uz0 = ex["tok"][:, 10] * mapxz[0], ex["tok"][:, 11] * mapxz[1]
                        reach0 = np.array([range_by_def.get(def_of.get(int(v), -1), 0.0) for v in ex["uid"]]) + 200.0
                        d2 = (ux0[:, None] - bxx[None, :]) ** 2 + (uz0[:, None] - bzz[None, :]) ** 2
                        air_c = np.array([cls_by_def.get(def_of.get(int(v), -1), 7) == 4 for v in ex["uid"]], bool)
                        cand = np.where((d2 <= reach0[:, None] ** 2).any(1) & ~kept & ~air_c & ~hyb)[0]
                        hc = np.zeros(n_tok, bool)
                        for j in cand:
                            hc[j] = cluster_near(ex["grid"], ux0[j], uz0[j], reach0[j], sx, sz, axis) >= CLUSTER_FLOOR
                        hyb |= hc
                        act &= ~hc
                        HYB_LOG[0] += int(hc.sum())
                        E_LOG["released"] += int(hc.sum())
                fidx = np.asarray(ex["force"], np.int64).copy()
                # air and ground never share an order (his 11-22: "they move at very different speeds"): a force's
                # flyers become a force of their own, which the force heads then decide for alone
                # ...and flyers by their def (his 11-22: fighters, bombers, gunships and EMP bombers each apart --
                # "usually group by unit class/type/def is the best choice")
                if len(fidx):
                    dj = np.array([def_of.get(int(v), -1) for v in ex["uid"]], np.int64)
                    air_j = np.array([cls_by_def.get(int(d_), 7) == 4 for d_ in dj], bool)
                    nxt = int(fidx.max()) + 1
                    for fk0 in range(nxt):
                        m0 = fidx == fk0
                        air_defs = sorted(set(dj[m0 & air_j].tolist()))
                        first = not (m0 & ~air_j).any()   # an all-air force keeps its index for its first def
                        for d_ in air_defs:
                            if first:
                                first = False
                                continue
                            fidx[m0 & air_j & (dj == d_)] = nxt
                            nxt += 1
                        # --split-defs (his 11-22: "we keep ALL our army in one line ... each unit type a member of
                        # its own group or subgroup", placed by its own strengths): a force's ground members split
                        # by def too, each decided by the force heads alone
                        if SPLIT_DEFS:
                            g_defs = sorted(set(dj[m0 & ~air_j].tolist()))
                            for d_ in g_defs[1:]:
                                fidx[m0 & ~air_j & (dj == d_)] = nxt
                                nxt += 1
                    if GATHER:
                        # 11-24 (Mac, gate 3): half our army stood in 1-unit forces (players 11-16%), 4 in 5 with a force
                        # of ours within 600, and a click takes only its own force's units; players box-select their
                        # small groups together, by type (his 11-24: "grouped up more by like unit type")
                        GATHER_LOG[1] += 1
                        parent, merged = list(range(nxt)), 0

                        def root(q):
                            while parent[q] != q:
                                parent[q] = parent[parent[q]]
                                q = parent[q]
                            return q
                        size = np.bincount(fidx[fidx >= 0], minlength=nxt)
                        ground = (fidx >= 0) & ~air_j
                        for j in np.where(ground & (size[np.clip(fidx, 0, None)] <= 2))[0]:
                            near = np.where(ground & (dj == dj[j]) & (fidx != fidx[j])
                                            & (np.hypot(ux_all - ux_all[j], uz_all - uz_all[j]) < GROUP_R))[0]
                            for q in near:
                                a_, b_ = root(int(fidx[j])), root(int(fidx[q]))
                                if a_ != b_:
                                    parent[a_] = b_
                                    merged += 1
                        GATHER_LOG[0] += merged
                        if merged:
                            fidx = np.array([root(int(v)) if v >= 0 else v for v in fidx], np.int64)
                            _, fidx_c = np.unique(np.where(fidx >= 0, fidx, nxt + 1), return_inverse=True)
                            fidx = np.where(fidx >= 0, fidx_c, -1).astype(np.int64)
                if True:
                    fo = net.forces(o["h"], o["u64"], fidx[None])
                    pf_all = 1.0 - (1.0 - sigmoid(fo["act"][0] + fbias)) ** gap
                    kp_all = softmax(fo["kind"][0])
                    # --place goal (his 11-22, "train a little differently ... as we discover new ways to use the model"):
                    # always-order asks the place every decision, but the place head learned only clicked steps; the
                    # 60-s goal head learned every force at every step (where it will be), so it can stand in
                    cp_all = softmax(fo["goal" if PLACE_SRC == "goal" else "cells"][0])
                    if JUDGE_K > 1 and "judge" in fo:
                        jg = np.asarray(fo["judge"][0], np.float32)
                        for fk_ in range(cp_all.shape[0]):
                            top = np.argpartition(cp_all[fk_], -JUDGE_K)[-JUDGE_K:]
                            pick = int(top[int(np.argmax(jg[fk_, top]))])
                            JUDGE_LOG[0] += 1
                            JUDGE_LOG[1] += int(pick != int(cp_all[fk_].argmax()))
                            cp_all[fk_] = 0.0
                            cp_all[fk_, pick] = 1.0
                    if EXPLORE_T > 0.0:
                        for fk_ in range(cp_all.shape[0]):
                            if rng.random() >= EXPLORE_P:
                                continue
                            top = np.argpartition(cp_all[fk_], -EXPLORE_K)[-EXPLORE_K:]
                            w = np.power(np.maximum(cp_all[fk_, top], 1e-12), 1.0 / EXPLORE_T)
                            pick = int(top[rng.choice(len(top), p=w / w.sum())])
                            EXPLORE_LOG[0] += 1
                            EXPLORE_LOG[1] += int(pick != int(cp_all[fk_].argmax()))
                            cp_all[fk_] = 0.0
                            cp_all[fk_, pick] = 1.0
                    sp_all = sigmoid(fo["spread"][0])
                    pm_all = sigmoid(fo["member"][0]) if has_member else None
                    sh_all = np.asarray(fo["shape"][0], np.float32)
                raid = None
                if FORCE_THREAT:
                    # a visible enemy armed mobile unit within its weapon range + 200 of one of our buildings or
                    # builders, not there at the last step: every force answers this step
                    cur = rows[rows[:, 0] == frame]
                    cd = cur[:, 2].astype(np.int64)
                    ccls = np.array([cls_by_def.get(int(v), 7) for v in cd], np.int64)
                    mine_ = cur[:, 3] == source
                    foe_ = np.array([int(t) >= 0 and ally_by_team.get(int(t), -1) != ally_by_team.get(int(source), -2)
                                     for t in cur[:, 3]], bool)
                    asset = mine_ & np.isin(ccls, (0, 1))
                    raider = foe_ & np.isin(ccls, (3, 4)) & np.array([armed_by_def.get(int(v), False) for v in cd], bool)
                    now_t = set()
                    if asset.any() and raider.any():
                        rr_ = np.array([range_by_def.get(int(v), 0.0) for v in cd[raider]]) + 200.0
                        d2 = ((cur[raider, 4][:, None] - cur[asset, 4][None]) ** 2
                              + (cur[raider, 5][:, None] - cur[asset, 5][None]) ** 2)
                        now_t = set(cur[raider, 1][(d2 <= rr_[:, None] ** 2).any(1)].astype(np.int64).tolist())
                        if now_t - threat_prev.get(holder, set()):
                            sel_ = np.isin(cur[:, 1].astype(np.int64), list(now_t))
                            raid = (float(cur[sel_, 4].mean()), float(cur[sel_, 5].mean()),
                                    sum(metal_by_def.get(int(v), 0.0) for v in cd[sel_]))
                            T_LOG["steps"] += 1
                    threat_prev[holder] = now_t
                new_hurt = np.zeros(n_tok, bool)
                if FORCE_FIRE:
                    hurt_now = ex["tok"][:, 39] < -0.01
                    was = hurt_prev.get(holder, set())
                    new_hurt = hurt_now & np.array([int(v) not in was for v in ex["uid"]], bool)
                    hurt_prev[holder] = set(ex["uid"][hurt_now].astype(np.int64).tolist())
                new_cl = None
                if FORCE_SEEN:
                    cl_now = cluster_cells(ex["grid"], sx, sz)
                    old = seen_prev.get(holder)
                    if old is not None and len(cl_now):
                        fresh_ = (np.ones(len(cl_now), bool) if not len(old) else
                                  ((cl_now[:, None, 0] - old[None, :, 0]) ** 2
                                   + (cl_now[:, None, 1] - old[None, :, 1]) ** 2 > CLUSTER_R ** 2).all(1))
                        if fresh_.any():
                            new_cl = (float(cl_now[fresh_, 0].mean()), float(cl_now[fresh_, 1].mean()))
                            V_LOG["seen"]["events"] += 1
                    seen_prev[holder] = cl_now
                # the enemy army a force answers when under fire: visible armed mobile units within 1,500 of it
                e_army = None
                if FORCE_FIRE and new_hurt.any() and len(ex.get("etok", [])):
                    et_ = ex["etok"]
                    ae_ = (et_[:, STAT_F + 3] > 0) & (et_[:, STAT_F + 13] > 0) & (et_[:, STAT_F + 15] <= 0)
                    e_army = (et_[ae_, STAT_F + 8] * mapxz[0], et_[ae_, STAT_F + 9] * mapxz[1],
                              np.expm1(et_[ae_, STAT_F + 17] * 10))
                rng_of = {j: range_by_def.get(def_of.get(int(ex["uid"][j]), -1), 0.0) for j in range(n_tok)}
                big = max(np.bincount(fidx[~kept & (fidx >= 0)]).max(initial=0) if len(fidx) else 0, 1)
                rallied_j = np.array([rally_on and int(u_) in rallied for u_ in ex["uid"]], bool)
                if dumpf is not None and frame % 150 == 0:
                    for j in range(n_tok):
                        fk_ = int(fidx[j])
                        dumpf.write("%d %d %d %d %d %.0f %.0f %.0f %d %.4f %d %.3f %.3f %.3f\n" % (
                            frame, int(ex["uid"][j]), def_of.get(int(ex["uid"][j]), -1), fk_,
                            int((fidx == fk_).sum()), ux_all[j], uz_all[j],
                            (frame - last_order.get(int(ex["uid"][j]), 0)) / 30.0,
                            int(tracker.task_of.get(int(ex["uid"][j]), -1)),
                            float(pf_all[fk_]) / gap if fk_ >= 0 else -1.0, int(kept[j]),
                            float(ex["tok"][j, 39]), float(ex["tok"][j, 41]), float(axis(ux_all[j], uz_all[j]))))
                    dumpf.flush()
                for fk in range(int(fidx.max()) + 1 if len(fidx) else 0):
                    members = np.where((fidx == fk) & ~kept & ~act & ~hyb)[0]
                    if not len(members):
                        continue
                    fp_log.append((float(pf_all[fk]) / gap, len(members),
                                   float(axis(ux_all[members].mean(), uz_all[members].mean())),
                                   int(np.mean([frame - last_order.get(int(ex["uid"][j]), 0) > 1800 for j in members]) > 0.5)))
                    if rallied_j.any() and len(members) >= 2:
                        # a unit that only walked to the rally is in the box when this force is clicked
                        mx_, mz_ = ux_all[members].mean(), uz_all[members].mean()
                        near = np.where(rallied_j & ~kept & ~act & ~hyb & (fidx != fk)
                                        & (np.hypot(ux_all - mx_, uz_all - mz_) < GROUP_R))[0]
                        members_x = np.concatenate([members, near])
                    else:
                        near, members_x = np.zeros(0, np.int64), members
                    if pm_all is not None and len(members) >= 2:
                        # the click takes the members the head picks, at least its likeliest one
                        take = rng.random(len(members)) < pm_all[members]
                        if not take.any():
                            take[int(np.argmax(pm_all[members]))] = True
                        members_x = np.concatenate([members[take], near])
                        took_n = (len(members), int(take.sum()))
                    pf_k = float(pf_all[fk])
                    if wake_p > 0.0:
                        tk = ex["tok"]
                        idle = np.mean([frame - last_order.get(int(ex["uid"][j]), 0) >= WAKE_IDLE_S * 30
                                        for j in members]) > 0.5
                        still = float(np.hypot(tk[members, 12], tk[members, 13]).mean()) * 100.0 < 5.0  # elmos a second
                        if idle and still:
                            cx_, cz_ = ux_all[members].mean(), uz_all[members].mean()
                            hurt = (tk[:, 39] < -0.01) | (tk[:, 41] > 0)
                            hurt[members] = False
                            near_fight = bool((hurt & (np.hypot(ux_all - cx_, uz_all - cz_) <= WAKE_R)).any())
                            if near_fight and pf_k < wake_p:
                                pf_k = wake_p
                                wake_log.append(len(members))
                    forced = False
                    if FORCE_IDLE:
                        # E2: a force standing still with no order, or at the place it was sent, must answer now
                        tk3 = ex["tok"]
                        ranges = np.array([rng_of.get(int(j), 0.0) for j in members])
                        to_t = np.hypot(tk3[members, 22], tk3[members, 23]) * 2000.0
                        at_t = (tk3[members, 21] <= 0) | (to_t < 0.5 * np.maximum(ranges, 200.0))
                        still3 = float(np.hypot(tk3[members, 12], tk3[members, 13]).mean()) * 100.0 < 5.0
                        if still3 and at_t.mean() > 0.5:
                            forced, pf_k = True, 1.0
                    fire_ev = FORCE_FIRE and bool(new_hurt[members].any())
                    if raid is not None or fire_ev or new_cl is not None:
                        pf_k = 1.0
                    fight_near = False
                    if KIND_MODE == "fightnear":
                        tk2 = ex["tok"]
                        hurt2 = (tk2[:, 39] < -0.01) | (tk2[:, 41] > 0)
                        fight_near = bool((hurt2 & (np.hypot(ux_all - ux_all[members].mean(), uz_all - uz_all[members].mean()) <= WAKE_R)).any())
                    cur_t = None   # no order standing: where it stands is what it is doing
                    if commit_a > 0.0:
                        cur_t = (float(ux_all[members].mean()), float(uz_all[members].mean()))
                    if commit_a > 0.0:
                        tk_ = ex["tok"]
                        ht = members[tk_[members, 21] > 0]
                        if len(ht):
                            cur_t = (float((ux_all[ht] + tk_[ht, 22] * 2000.0).mean()), float((uz_all[ht] + tk_[ht, 23] * 2000.0).mean()))
                    res = learned_force_order(members_x, pf_k, kp_all[fk], cp_all[fk], (0.5, 0.5),
                                              float(sp_all[fk]), sh_all[fk], ux_all, uz_all, rng_of, cell_fwd, axis,
                                              sx, sz, rng, layer, dirfirst, ex["grid"], arc, commit_a, cur_t, fight_near)
                    if res is None:
                        continue
                    if pm_all is not None and len(members) >= 2:
                        member_log.append(took_n)
                    k_f, c_f, slots = res
                    tx_ = float(np.mean([s_[1] for s_ in slots]))
                    tz_ = float(np.mean([s_[2] for s_ in slots]))
                    if CLUSTER_FIGHT and k_f == 1:
                        E_LOG["moves"] += 1
                        reach_ = max(rng_of.get(int(j), 0.0) for j in members) + 200.0
                        if cluster_near(ex["grid"], tx_, tz_, reach_, sx, sz, axis) >= CLUSTER_FLOOR:
                            k_f = 2
                            E_LOG["fight"] += 1
                    if forced:
                        E_LOG["forced"] += 1
                        fx_, fz_ = float(ux_all[members].mean()), float(uz_all[members].mean())
                        dv = float(axis(tx_, tz_)) - float(axis(fx_, fz_))
                        ans_ = ("same" if np.hypot(tx_ - fx_, tz_ - fz_) < 300.0 else
                                ("deeper" if dv > 0.05 else ("back" if dv < -0.05 else "sideways")))
                        E_LOG[ans_] += 1
                        # by force size, where it stands (thirds of the axis) and whether its members are new to the
                        # model (most never ordered by it): is E2 asking small new forces at home and sending them on?
                        n_ = len(members)
                        ax_f = float(axis(fx_, fz_))
                        E_DETAIL[("1-2" if n_ <= 2 else "3-5" if n_ <= 5 else "6-10" if n_ <= 10 else "11+",
                                  "home" if ax_f < 1 / 3 else ("middle" if ax_f < 2 / 3 else "forward"),
                                  "new" if np.mean([int(ex["uid"][j]) not in last_order for j in members]) > 0.5 else "old",
                                  ans_)] += 1
                    if raid is not None:
                        fx_, fz_ = float(ux_all[members].mean()), float(uz_all[members].mean())
                        dv = float(axis(tx_, tz_)) - float(axis(fx_, fz_))
                        if np.hypot(tx_ - fx_, tz_ - fz_) < 300.0:
                            ans = "stay"
                        elif np.hypot(tx_ - raid[0], tz_ - raid[1]) < np.hypot(fx_ - raid[0], fz_ - raid[1]) - 300.0:
                            ans = "toward"
                        else:
                            ans = "forward" if dv > 0.05 else ("back" if dv < -0.05 else "sideways")
                        fm_ = sum(metal_by_def.get(def_of.get(int(ex["uid"][j]), -1), 0.0) for j in members)
                        T_LOG["answers"].append((ans, fm_ / max(raid[2], 1.0)))
                    if fire_ev or new_cl is not None:
                        fx_, fz_ = float(ux_all[members].mean()), float(uz_all[members].mean())
                        fm_ = sum(metal_by_def.get(def_of.get(int(ex["uid"][j]), -1), 0.0) for j in members)
                    if fire_ev:
                        V_LOG["fire"]["events"] += 1
                        pt_, ratio_ = None, -1.0
                        if e_army is not None and len(e_army[0]):
                            nr_ = np.hypot(e_army[0] - fx_, e_army[1] - fz_) <= 1500.0
                            if nr_.any():
                                pt_ = (float(e_army[0][nr_].mean()), float(e_army[1][nr_].mean()))
                                ratio_ = fm_ / max(float(e_army[2][nr_].sum()), 1.0)
                        V_LOG["fire"]["answers"].append((answer_to(tx_, tz_, fx_, fz_, pt_, axis), ratio_))
                    if new_cl is not None:
                        V_LOG["seen"]["answers"].append((answer_to(tx_, tz_, fx_, fz_, new_cl, axis), -1.0))
                    fkind_log.append(k_f)
                    of = net.offset_at(fo["fh"][:, fk:fk + 1], o["u64"], np.array([[c_f]], np.int64))[0, 0]
                    src_ = ("threat" if raid is not None else "fire" if fire_ev else "seen" if new_cl is not None
                            else "idle" if forced else "force")
                    for j, x_, z_ in slots:
                        act[j], kind[j] = True, k_f
                        X[j], Z[j] = x_ + (of[0] - 0.5) * sx, z_ + (of[1] - 0.5) * sz
                        src[j] = src_
                    for j in near:
                        rallied.discard(int(ex["uid"][j]))
                    boxed_log.append(len(near))
                    if len(members) >= max(2, 0.5 * big):
                        rally = (float(np.mean([s_[1] for s_ in slots])), float(np.mean([s_[2] for s_ in slots])))
                if rally_on and rally is not None:
                    for j in np.where(~kept & ~act & ~hyb)[0]:
                        if int(ex["uid"][j]) not in last_order:
                            act[j], kind[j] = True, 1
                            src[j] = "rally"
                            X[j] = rally[0] + rng.normal(0, LINE_GAP)
                            Z[j] = rally[1] + rng.normal(0, LINE_GAP)
                            rallied.add(int(ex["uid"][j]))
            elif forces:
                # forces (his 11-20): the units of one live task are one force; units in none are grouped by where
                # they stand, as a player box-selects, by the radius that groups clicks (tasks.GROUP_R)
                act[:] = False
                free = [j for j in range(n_tok) if not kept[j] and int(ex["uid"][j]) not in tracker.task_of]
                groups = {}
                for j in range(n_tok):
                    if not kept[j] and int(ex["uid"][j]) in tracker.task_of:
                        groups.setdefault(("t", tracker.task_of[int(ex["uid"][j])]), []).append(j)
                for gi, grp in enumerate(cluster_targets([[j, ux_all[j], uz_all[j]] for j in free], 1, 2)):
                    groups[("f", gi)] = [int(r[0]) for r in grp]
                rng_of = {j: range_by_def.get(def_of.get(int(ex["uid"][j]), -1), 0.0) for j in range(n_tok)}
                for members in groups.values():
                    # air and ground move apart: a gunship wing does not take a tank force's pace or place
                    is_air = np.array([cls_by_def.get(def_of.get(int(ex["uid"][j]), -1), 7) == 4 for j in members])
                    for part_ in (np.array(members)[is_air], np.array(members)[~is_air]):
                        if not len(part_):
                            continue
                        res = force_orders(part_.astype(np.int64), p, kp_r, probs, off, ux_all, uz_all, rng_of,
                                           cell_fwd, axis, sx, sz, rng, layer)
                        if res is None:
                            continue
                        k_f, slots = res
                        for j, x_, z_ in slots:
                            act[j], kind[j], X[j], Z[j] = True, k_f, x_, z_
                            src[j] = "force"
            if frame % 300 == 0:
                # the whole army's spacing, free of how tasks happen to be cut: mean distance to the nearest own unit
                own = np.where(~kept)[0]
                if len(own) >= 2:
                    dd_ = np.hypot(ux_all[own, None] - ux_all[None, own], uz_all[own, None] - uz_all[None, own])
                    np.fill_diagonal(dd_, np.inf)
                    nn_log.append(float(dd_.min(1).mean()))
                # how tight the live tasks of 3+ units are (both modes): their members' mean distance to the centre
                tj = {}
                for j in range(n_tok):
                    t_ = tracker.task_of.get(int(ex["uid"][j]))
                    if t_ is not None:
                        tj.setdefault(t_, []).append(j)
                for js in tj.values():
                    if len(js) >= 3:
                        spread_log.append(float(np.mean(np.hypot(ux_all[js] - ux_all[js].mean(),
                                                                 uz_all[js] - uz_all[js].mean()))))
            here = units[units[:, 0] == frame]
            # the probability the model puts on places past 0.7 of the way to their base, per unit (its best place
            # may never be deep while deep places still carry real weight)
            cz_, cx_ = np.mgrid[0:G, 0:G]
            deep_cells = (axis((cx_ + .5) * sx, (cz_ + .5) * sz) > 0.7).ravel().astype(np.float32)
            deep_mass_log.extend((softmax(o["cells"][0]) * deep_cells).sum(-1).tolist())
            for j, uid in enumerate(ex["uid"]):
                if not act[j]:
                    continue
                k = int(kind[j])
                x, z = float(X[j]), float(Z[j])
                cmd = KIND_CMD[k]
                if SRC_LOG:
                    if TURN[0] is None:
                        # the frame turned so our buildings' centre is bottom-left (as tools/armynet/army_where.py)
                        w_ = np.expm1(np.clip(ex["grid"][3], 0, 20))
                        if w_.sum() > 0:
                            zz_, xx_ = np.mgrid[0:G, 0:G]
                            TURN[0] = (float(((xx_ + .5) * w_).sum() / w_.sum() * sx) > mapxz[0] / 2,
                                       float(((zz_ + .5) * w_).sum() / w_.sum() * sz) < mapxz[1] / 2)
                    if TURN[0] is not None:
                        xn_, zn_ = x / mapxz[0], z / mapxz[1]
                        xn_, zn_ = (1 - xn_ if TURN[0][0] else xn_), (1 - zn_ if TURN[0][1] else zn_)
                        SRC_COUNT[(str(src[j]), min(max(int(zn_ * 3), 0), 2) * 3 + min(max(int(xn_ * 3), 0), 2))] += 1
                issued.append((int(uid), k, x, z, ex["tok"][j, 10] * mapxz[0], ex["tok"][j, 11] * mapxz[1]))
                last_order[int(uid)] = frame
                if cmd == 0:
                    out.append("%d,0" % uid)
                    continue
                if cmd == 20:
                    # only an enemy this side can see (no hidden information)
                    kk = g.allies.index(g.ally_of[holder])
                    seen = ((here[:, 10].astype(np.int64) >> (2 * kk)) & 1) > 0
                    foe = here[(np.array([g.ally_of.get(int(t), -9) for t in here[:, 3]]) != g.ally_of[holder]) & seen]
                    if len(foe) and POINTER and "tgt" in o and len(ex.get("etok", [])):
                        # the target pointer (roadmap item 3): the enemy token the model picks, the visible enemy there
                        tk_ = int(np.argmax(o["tgt"][0, j]))
                        if tk_ > 0 and tk_ - 1 < len(ex["etok"]):
                            px_ = float(ex["etok"][tk_ - 1, STAT_F + 8]) * mapxz[0]
                            pz_ = float(ex["etok"][tk_ - 1, STAT_F + 9]) * mapxz[1]
                            dp = (foe[:, 4] - px_) ** 2 + (foe[:, 5] - pz_) ** 2
                            ip = int(np.argmin(dp))
                            if dp[ip] < 150 ** 2:
                                PTR_LOG[0] += 1
                                out.append("%d,20,%d" % (uid, int(foe[ip, 1])))
                                continue
                        PTR_LOG[1] += 1
                    if len(foe):
                        dd = (foe[:, 4] - x) ** 2 + (foe[:, 5] - z) ** 2
                        i = int(np.argmin(dd))
                        if dd[i] < 400 ** 2:
                            out.append("%d,20,%d" % (uid, int(foe[i, 1])))
                            continue
                    cmd = 16
                out.append("%d,%d,%.0f,%.0f" % (uid, cmd, x, z))
                fwd_log.append(axis(x, z))
            for j in np.where(hyb)[0]:
                out.append("%d,-1,%d" % (ex["uid"][j], HYB_HOLD))
                HYB_LOG[1] += 1
            # this second's orders into groups (kind, then target area) and tasks, as replay_dataset.py groups clicks
            by_kind = {}
            for r in issued:
                by_kind.setdefault(r[1], []).append(r)
            for k, rows_k in sorted(by_kind.items()):
                for grp in cluster_targets(rows_k, 2, 3):
                    xy = (float(np.mean([r[4] for r in grp])), float(np.mean([r[5] for r in grp])))
                    tid = tracker.group(frame, holder, [r[0] for r in grp], xy)
                    for r in grp:
                        order_log.append([frame, frame, holder, r[0], k, r[2], r[3], -1, 1, 0, tid])
            gaps.append(gap)
            spent.append(time.time() - t0)
            if frame // 300 != logged // 300:
                print("frame %d units %d new orders %d mean p %.2f tasks %d" % (
                    frame, len(ex["uid"]), len(out) - 1, p.mean(), len(tracker.tasks)), flush=True)
            if frame // 1800 != logged // 1800 and gaps:
                print("decisions %d, steps between them mean %.2f max %.0f, compute mean %.3f s" % (
                    len(gaps), float(np.mean(gaps)), float(np.max(gaps)), float(np.mean(spent))), flush=True)
                gaps.clear()
                spent.clear()
            if frame // 1800 != logged // 1800 and fp_log:
                fa = np.array(fp_log, float)
                idle = fa[:, 3] > 0
                print("minute %d forces: per-step click p mean %.3f (size>=4 %.3f, at home %.3f) | idle forces (most "
                      "members unordered 60 s) %.0f%% p %.3f size %.1f axis %.2f | kinds %s | rally units boxed in %d | shapes %s | commit %s | arc in range %s | arc rows %s" % (
                          frame // 1800, fa[:, 0].mean(), fa[fa[:, 1] >= 4, 0].mean() if (fa[:, 1] >= 4).any() else -1,
                          fa[fa[:, 2] < 0.08, 0].mean() if (fa[:, 2] < 0.08).any() else -1, 100 * idle.mean(),
                          fa[idle, 0].mean() if idle.any() else -1, fa[idle, 1].mean() if idle.any() else 0,
                          fa[idle, 2].mean() if idle.any() else -1, np.bincount(fkind_log, minlength=6).tolist(), sum(boxed_log), dict(SHAPES), dict(COMMIT), dict(ARC), dict(ROWS)),
                      flush=True)
                sz_ = fa[:, 1]
                print("minute %d army shape: forces %.1f a decision, mean size %.1f, units in forces of 2 or fewer %.0f%% "
                      "| gather merges %d over %d decisions | unit-contact %d unit-steps, %d orders, one-step p %.3f, orders per 10 frames %.3f (players .143, their p .155)" % (frame // 1800, len(sz_) / max(GATHER_LOG[1], 1) if GATHER else -1,
                                                              sz_.mean(), 100 * sz_[sz_ <= 2].sum() / max(sz_.sum(), 1),
                                                              GATHER_LOG[0], GATHER_LOG[1], UC_LOG[0], UC_LOG[1], UC_LOG[2] / max(UC_LOG[0], 1), UC_LOG[1] / max(UC_LOG[3], 1)), flush=True)
                if JUDGE_K > 1:
                    print("minute %d judge: %d force-steps judged among the top %d places, %d picks differ from the place "
                          "head's best" % (frame // 1800, JUDGE_LOG[0], JUDGE_K, JUDGE_LOG[1]), flush=True)
                if EXPLORE_T > 0.0:
                    print("minute %d explore: %d force-steps sampled at T=%.2f among the top %d, %d off the head's best" % (
                        frame // 1800, EXPLORE_LOG[0], EXPLORE_T, EXPLORE_K, EXPLORE_LOG[1]), flush=True)
                if HYBRID:
                    print("minute %d hybrid: %d unit-steps released to the AI's fight logic, %d release lines" % (
                        frame // 1800, HYB_LOG[0], HYB_LOG[1]), flush=True)
                if FORCE_THREAT:
                    # running totals: steps a new threat reached our buildings or builders, and every force's answer
                    tl = T_LOG["answers"]
                    cnt = {k_: sum(1 for x in tl if x[0] == k_) for k_ in ("toward", "forward", "sideways", "stay", "back")}
                    tw = [x[1] for x in tl if x[0] == "toward"]
                    print("minute %d objectives-T: threat steps %d, answers %d: toward %d forward %d sideways %d stay %d back %d"
                          " | toward with force >= raid metal %d, median force/raid toward %.2f all %.2f" % (
                              frame // 1800, T_LOG["steps"], len(tl), cnt["toward"], cnt["forward"], cnt["sideways"],
                              cnt["stay"], cnt["back"], sum(1 for v in tw if v >= 1.0),
                              float(np.median(tw)) if tw else -1.0, float(np.median([x[1] for x in tl])) if tl else -1.0),
                          flush=True)
                if POINTER:
                    print("minute %d pointer: attacks sent to the enemy the target head picked %d, fell back to the "
                          "nearest %d" % (frame // 1800, PTR_LOG[0], PTR_LOG[1]), flush=True)
                if SRC_LOG and SRC_COUNT:
                    # running totals: orders by the part of serve that gave them, and the turned-frame cell they aim at
                    # (ours bottom-left; rows top / middle / bottom, columns left / middle / right)
                    print("minute %d objectives-S orders by source, aimed cell: %s" % (frame // 1800, " | ".join(
                        "%s %d: %s" % (s_, sum(SRC_COUNT.get((s_, c_), 0) for c_ in range(9)),
                                       " ".join(str(SRC_COUNT.get((s_, c_), 0)) for c_ in range(9)))
                        for s_ in sorted({k_[0] for k_ in SRC_COUNT}))), flush=True)
                for nm_, on_ in (("fire", FORCE_FIRE), ("seen", FORCE_SEEN)):
                    if not on_:
                        continue
                    # running totals: forced answers to the event, where they went, force metal / enemy army near it
                    vl = V_LOG[nm_]["answers"]
                    cnt = {k_: sum(1 for x in vl if x[0] == k_) for k_ in ("toward", "away", "forward", "sideways", "stay", "back")}
                    rs_ = [x[1] for x in vl if x[1] >= 0]
                    print("minute %d objectives-V %s: %s%d answers: toward %d away %d forward %d sideways %d stay %d back %d"
                          " | median force/enemy near %.2f" % (
                              frame // 1800, nm_, ("new clusters %d, " % V_LOG["seen"]["events"]) if nm_ == "seen" else "",
                              len(vl), cnt["toward"], cnt["away"], cnt["forward"], cnt["sideways"], cnt["stay"], cnt["back"],
                              float(np.median(rs_)) if rs_ else -1.0), flush=True)
                if CLUSTER_FIGHT or FORCE_IDLE or HYB_CLUSTER:
                    # running totals: moves turned to fight at a cluster (E1); forced answers and where they went (E2)
                    print("minute %d objectives-E: moves %d -> fight at a cluster %d | released at a cluster %d | forced %d: same %d deeper %d "
                          "sideways %d back %d" % (frame // 1800, E_LOG["moves"], E_LOG["fight"], E_LOG["released"],
                                                   E_LOG["forced"], E_LOG["same"], E_LOG["deeper"], E_LOG["sideways"], E_LOG["back"]),
                          flush=True)
                    if E_DETAIL:
                        # running totals by (size, place, new/old): answers same/deeper/sideways/back
                        keys_ = sorted({k_[:3] for k_ in E_DETAIL})
                        print("minute %d objectives-E2 by force: %s" % (frame // 1800, " | ".join(
                            "%s %s %s %d/%d/%d/%d" % (k_ + tuple(E_DETAIL.get(k_ + (a_,), 0) for a_ in
                                                             ("same", "deeper", "sideways", "back"))) for k_ in keys_)),
                              flush=True)
                fp_log.clear()
                fkind_log.clear()
                boxed_log.clear()
                if member_log:
                    ml = np.array(member_log, float)
                    big = ml[:, 0] >= 10
                    print("minute %d members: clicks %d, share of the force taken mean %.2f (forces of 10+: %d clicks, %.2f)"
                          % (frame // 1800, len(ml), (ml[:, 1] / ml[:, 0]).mean(), big.sum(),
                             (ml[big, 1] / ml[big, 0]).mean() if big.any() else -1), flush=True)
                    member_log.clear()
                if wake_p > 0.0:
                    print("minute %d wake: idle forces beside a fight raised to p %.2f: %d force-steps, size mean %.1f" % (
                        frame // 1800, wake_p, len(wake_log), float(np.mean(wake_log)) if wake_log else 0.0), flush=True)
                    wake_log.clear()
            if frame // 1800 != logged // 1800:
                ev = tracker.events[ev_seen:]
                ev_seen = len(tracker.events)
                sizes = [len(t["units"]) for t in tracker.tasks.values()]
                print("minute %d task spread mean %.0f median %.0f (n %d) | nearest own unit %.0f | tasks %d mean size "
                      "%.1f | new %d split %d merge %d" % (
                          frame // 1800, float(np.mean(spread_log)) if spread_log else -1,
                          float(np.median(spread_log)) if spread_log else -1, len(spread_log),
                          float(np.mean(nn_log)) if nn_log else -1, len(sizes), float(np.mean(sizes)) if sizes else 0,
                          sum(e[1] == "new" for e in ev), sum(e[1] == "split" for e in ev),
                          sum(e[1] == "merge" for e in ev)), flush=True)
                spread_log.clear()
                nn_log.clear()
            if frame // 1800 != logged // 1800 and fwd_log:
                # how far forward the orders of the last minute went (0 our buildings, 1 theirs); deep = past 0.7
                fw = np.array(fwd_log)
                dm = np.array(deep_mass_log) if deep_mass_log else np.zeros(1)
                print("minute %d orders %d forward median %.2f deep %.0f%% deep mass mean %.3f q90 %.3f" % (
                    frame // 1800, len(fw), float(np.median(fw)), 100 * float(np.mean(fw > 0.7)),
                    float(dm.mean()), float(np.percentile(dm, 90))), flush=True)
                fwd_log.clear()
                deep_mass_log.clear()
            logged = frame
        out.append("E")
        tmp = d / "armynet_orders.tmp"
        tmp.write_text("\n".join(out) + "\n", encoding="utf-8")
        for _ in range(50):
            try:
                os.replace(tmp, d / "armynet_orders.txt")
                break
            except PermissionError:  # the game has the file open for a moment
                time.sleep(0.01)
            except OSError as e:  # the folder went away or another writer took the file: skip this step, not the game
                print("orders not written: %s" % e, flush=True)
                break


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
