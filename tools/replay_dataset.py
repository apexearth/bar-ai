#!/usr/bin/env python3
"""Turn a replay recording (tools/replay_orders.py) into training rows: decisions and their outcomes.

    python tools/replay_dataset.py <orders.txt.gz | dir of recordings> [--out DIR]

Per recording, <name>.npz beside it (or in --out):
    units      every U sample: frame uid def team x z vx vz hp build sight cmd tx tz
    defs       def -> class code, metal, hp, speed, range, ground_dps, aa_dps, sight, radar, jam
    teams      team -> ally, is_ai, skill
    decisions  frame first_frame team uid kind tx tz group n_orders shift
    outcome    per decision, per horizon in HORIZONS: [own, area, team, control, near, eco_near, eco_side, eco_traced, own_change]
    result     per decision: 1 the team's side won, 0 lost, -1 unknown
    spots, heights, map, allies, desync_frame (data after it is not the game that was played)

A decision: a human team's move/fight/attack/patrol/area-attack/stop to an army, air, radar or jammer
unit, one per unit per STEP frames (the last non-queued click in the step sets the target); shift-queued waypoints
within BURST frames extend the route they follow (its end is the target). Since 11-19 (his: "under 500 milliseconds")
clicks are no longer merged over BURST: in fights players re-order a unit every 0.23 s median, and those clicks are
the footwork (kiting, dodging, pulling a hurt unit back). A group: the decisions of one team set by
the same frame's order of the same kind.

Outcomes over each horizon after the decision, in metal:
    own   damage the group's units dealt to enemies minus damage they took (damage x metal / health)
    area  enemy metal destroyed within AREA of the target minus our side's metal destroyed there
    team  enemy metal destroyed anywhere minus our side's, the whole side
and in map control (his 11-18: "one 'pro' can be measured in increasing the map control we have"), from the
whole-game view (a label, never an input): on a CONTROL_G grid a cell is a side's when its buildings and armed
ground units there outweigh the other side's in metal;
    control  the change in the side's share of owned cells
    near     the change in (ours - theirs) among the cells within NEAR of the target, over the cells there
"""
import bisect
import collections
import gzip
import os
import re
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent / "armynet"))
from tasks import QUIET, tasks_of_game  # noqa: E402
from movement import movement  # noqa: E402
from economy import income  # noqa: E402

HORIZONS = (5, 15, 60, 180, 600)
BURST = 45
FIGHT_R = 800.0
STAY_S = 5
STEP = 10  # frames per decision step (a third of a second); the model decides at this rate
AREA = 1000.0
FOCUS = ("army", "air", "radar", "jammer")
CLASSES = ("static", "builder", "com", "army", "air", "radar", "jammer", "other")
KINDS = {0: 0, 10: 1, 16: 2, 20: 3, 21: 4, 15: 5}
# economy buildings by name: extractors, solar, wind, tidal, fusion, geothermal, metal makers
ECO = re.compile(r"^(arm|cor|leg)\w*(mex|moho|sol|win|tide|fus|geo|makr|mmkr)", re.I)
CONTROL_G = 32
NEAR = 1500.0
CONTROL_STEP = 300  # frames between control samples (buildings are sampled every 10 s)


def control_series(units, defs, ally_of, allies, mapxz):
    """frame -> {ally: owned cell mask} every CONTROL_STEP frames: buildings and armed ground units, by metal."""
    if not len(units) or not mapxz[0]:
        return np.zeros(0), {}
    holds = np.zeros(int(max(defs) + 1) if defs else 1, bool)
    metal = np.zeros(len(holds), np.float32)
    for d, v in defs.items():
        c = CLASSES[int(v[0])]
        metal[d] = v[1]
        holds[d] = c == "static" or (c in ("army", "com") and v[5] > 0)
    fr = units[:, 0].astype(np.int64)
    out_f, out = [], {a: [] for a in allies}
    for f in np.unique(fr[fr % CONTROL_STEP == 0]):
        rows = units[fr == f]
        d = np.clip(rows[:, 2].astype(np.int64), 0, len(holds) - 1)
        ok = holds[d] & (rows[:, 9] >= 1.0)
        rows, d = rows[ok], d[ok]
        cx = np.clip((rows[:, 4] / mapxz[0] * CONTROL_G).astype(np.int64), 0, CONTROL_G - 1)
        cz = np.clip((rows[:, 5] / mapxz[1] * CONTROL_G).astype(np.int64), 0, CONTROL_G - 1)
        al = np.array([ally_of.get(int(t), -9) for t in rows[:, 3]])
        w = {}
        for a in allies:
            g = np.zeros((CONTROL_G, CONTROL_G), np.float32)
            m = al == a
            np.add.at(g, (cz[m], cx[m]), metal[d[m]])
            w[a] = g
        for a in allies:
            others = np.max([w[b] for b in allies if b != a], axis=0) if len(allies) > 1 else 0
            out[a].append((w[a] > others) & (w[a] > 0))
        out_f.append(int(f))
    return np.array(out_f), {a: np.array(v) for a, v in out.items()}


def demo_skills(rec_dir):
    """team -> skill from the demo's start script, when the batch log names the demo (the dir is its stem)."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import bar_env
    import replay_extract as rx
    name = Path(rec_dir).name + ".sdfz"
    demo = next((d / name for d in (bar_env.load().data / "demos", Path("G:/bar-ai-archive/public-replays/demos"))
                 if (d / name).exists()), None)
    if demo is None:
        return {}
    script = rx.demo_script(demo)
    out, cur, team, skill = {}, None, None, None
    for ln in script.splitlines() + ["[end]"]:
        s = ln.strip()
        if s.startswith("["):
            if cur and team is not None and skill is not None:
                out[team] = max(out.get(team, -1), skill)
            cur = s.lower().startswith("[player")
            team, skill = None, None
            continue
        if cur:
            m = re.match(r"(\w+)=(.*?);", s)
            if m and m.group(1).lower() == "team":
                team = int(m.group(2))
            elif m and m.group(1).lower() == "skill":
                v = re.findall(r"[\d.]+", m.group(2))
                skill = float(v[0]) if v else None
    return out


def recover_victims(X, units, defs, team_of, ally_of):
    """Recordings from 11-18 19:14 to 11-19 14:30 packed each hit as one number, attacker * 2^20 + victim, in Lua's
    float32: with the attacker known, the victim's low bits were rounded away (victims read 2048, 3072, 768 ...). The
    attacker survived exactly; the victim is the enemy unit sampled that second whose id lies within one rounding step
    of the recorded one, nearest the attacker (within its weapon range + 500). Returns (rows, recovered, ambiguous,
    dropped); a recording without the packing (its known-attacker victims not mostly multiples of 128) is returned
    as it is."""
    known = [r for r in X if r[1] >= 0]
    if not known or np.mean([r[2] % 128 == 0 for r in known]) < 0.5:
        return X, 0, 0, 0
    fr = units[:, 0].astype(np.int64)
    by_frame = {}
    for f in np.unique(fr):
        m = fr == f
        by_frame[int(f)] = (units[m, 1].astype(np.int64), units[m, 4], units[m, 5], units[m, 3].astype(np.int64))
    last = {}
    for r in units:
        last.setdefault(int(r[1]), []).append((r[0], r[4], r[5]))
    rng = {d: v[4] for d, v in defs.items()}
    def_of_uid = {}
    for r in units:
        def_of_uid.setdefault(int(r[1]), int(r[2]))
    out, rec, amb, drop = [], 0, 0, 0
    for f, a, v, amt in X:
        if a < 0:
            out.append((f, a, v, amt))
            continue
        step = float(np.spacing(np.float32(float(a) * 1048576.0 + v)))
        snap = by_frame.get(int(f))
        rows = last.get(int(a))
        if snap is None or not rows:
            drop += 1
            continue
        k = min(range(len(rows)), key=lambda j: abs(rows[j][0] - f))
        axx, azz = rows[k][1], rows[k][2]
        a_ally = ally_of.get(team_of.get(int(a), -9), -9)
        uids, xs, zs, ts = snap
        al = np.array([ally_of.get(int(t), -9) for t in ts])
        cand = (np.abs(uids - v) <= step) & (al != a_ally) & (al >= 0)
        if not cand.any():
            drop += 1
            continue
        d2 = (xs[cand] - axx) ** 2 + (zs[cand] - azz) ** 2
        order = np.argsort(d2)
        reach = rng.get(def_of_uid.get(int(a), -1), 0.0) + 500.0
        if d2[order[0]] > reach * reach:
            drop += 1
            continue
        if len(order) > 1 and d2[order[1]] <= reach * reach:
            amb += 1
        out.append((f, a, int(uids[cand][order[0]]), amt))
        rec += 1
    return out, rec, amb, drop


def attribute_damage(X, units, defs, def_of, team_of, ally_of, metal, hp, slack=100.0):
    """BAR gives widgets no attacker: a victim's damage in a second is shared among the enemy units that
    had it in weapon reach at that second's sample, by their damage a second against its kind (air or not).
    Returns (frame, attacker, victim, metal value, attacker ally, victim ally); attacker -1 when nobody was in reach."""
    if not len(units):
        return []
    frames = units[:, 0].astype(np.int64)
    order = np.argsort(frames, kind="stable")
    units, frames = units[order], frames[order]
    starts = {}
    uniq, first = np.unique(frames, return_index=True)
    bounds = list(first) + [len(frames)]
    for i, fr in enumerate(uniq):
        starts[int(fr)] = (bounds[i], bounds[i + 1])
    static_frames = np.array(sorted(fr for fr in starts if fr % 300 == 0))
    rng = np.array([defs.get(int(d), (0,) * 10)[4] for d in range(int(max(defs) + 1))] if defs else [0.0])
    gdps = np.array([defs.get(int(d), (0,) * 10)[5] for d in range(len(rng))])
    adps = np.array([defs.get(int(d), (0,) * 10)[6] for d in range(len(rng))])
    is_air = {d for d, v in defs.items() if CLASSES[v[0]] == "air"}
    team_ally = np.full(int(max(ally_of) + 1) if ally_of else 1, -9)
    for t, a in ally_of.items():
        team_ally[t] = a

    def snapshot(f):
        rows = []
        if f in starts:
            a, b = starts[f]
            rows.append(units[a:b])
        if len(static_frames):
            j = np.searchsorted(static_frames, f, "right") - 1
            if j >= 0 and int(static_frames[j]) != f:
                a, b = starts[int(static_frames[j])]
                blk = units[a:b]
                rows.append(blk[np.array([defs.get(int(d), (0,))[0] == 0 for d in blk[:, 2]], bool)])
        return np.concatenate(rows) if rows else np.zeros((0, 14), np.float32)

    out, cache_f, snap, pos = [], None, None, None
    for f, a, v, amt in X:
        dv = def_of.get(v)
        if dv is None:
            continue
        val = min(amt / hp[dv], 1.0) * metal[dv]
        va = ally_of.get(team_of.get(v, -9), -9)
        if a >= 0:
            out.append((f, a, v, val, ally_of.get(team_of.get(a, -9), -9), va))
            continue
        if f != cache_f:
            cache_f, snap = f, snapshot(f)
            pos = {int(r[1]): (r[4], r[5]) for r in snap}
        if v not in pos or not len(snap):
            out.append((f, -1, v, val, -9, va))
            continue
        vx, vz = pos[v]
        d = snap[:, 2].astype(np.int64)
        al = team_ally[np.clip(snap[:, 3].astype(np.int64), 0, len(team_ally) - 1)]
        power = adps[d] if dv in is_air else gdps[d]
        reach = (snap[:, 4] - vx) ** 2 + (snap[:, 5] - vz) ** 2 <= (rng[d] + slack) ** 2
        ok = (al != va) & (al >= 0) & reach & (power > 0) & (snap[:, 9] >= 1.0)
        if not ok.any():
            out.append((f, -1, v, val, -9, va))
            continue
        w = power[ok] / power[ok].sum()
        for uid, share, ally in zip(snap[ok, 1].astype(np.int64), w, al[ok]):
            out.append((f, int(uid), v, val * float(share), int(ally), va))
    return out


ECO_REBUILT_R = 150.0
ECO_HORIZON_S = 600.0


def eco_values(K, units, eco, names, metal, ally_of):
    """An economy building's kill is worth its price plus the income its owner goes without until a finished
    economy building of theirs stands within ECO_REBUILT_R again (or the game ends), up to the 10-minute horizon
    (economy.py: an extractor earns its price back in ~25 s). Returns {death index: value} and, per economy def, the
    factor its hits are scaled by: this game's mean kill value over price for that def, or the price plus 300 s of
    income where none died."""
    end = float(units[:, 0].max()) if len(units) else 0.0
    built = units[np.isin(units[:, 2].astype(np.int64), list(eco)) & (units[:, 9] >= 1)] if eco else units[:0]
    first = {}
    for r in built:
        uid = int(r[1])
        if uid not in first:
            first[uid] = (r[0], ally_of.get(int(r[3]), -9), r[4], r[5])
    stands = collections.defaultdict(list)
    for f, a, x, z in first.values():
        stands[a].append((f, x, z))
    stands = {a: np.array(v, np.float64) for a, v in stands.items()}
    value, ratios = {}, collections.defaultdict(list)
    for i, (f, u, d, t, x, z, au, at) in enumerate(K):
        if d not in eco:
            continue
        a = ally_of.get(t, -9)
        later = f + ECO_HORIZON_S * 30
        st = stands.get(a)
        if st is not None and len(st):
            m = (st[:, 0] > f) & ((st[:, 1] - x) ** 2 + (st[:, 2] - z) ** 2 <= ECO_REBUILT_R ** 2)
            if m.any():
                later = min(later, st[m, 0].min())
        down = max(min(later, end) - f, 0.0) / 30.0
        price = metal.get(d, 0.0)
        value[i] = price + income(names.get(d, "")) * down
        if price > 0:
            ratios[d].append(value[i] / price)
    scale = {}
    for d in eco:
        price = metal.get(d, 0.0)
        if ratios.get(d):
            scale[d] = float(np.mean(ratios[d]))
        elif price > 0:
            scale[d] = (price + income(names.get(d, "")) * 300.0) / price
    return value, scale


def side_series(units, defs, ally_of, allies, death_f, side_cum, cf, owned):
    """Each side's state every 10 s, for a value label at any moment (a label, never an input): rows of
    [frame, ally, metal lost so far, standing finished metal, standing finished army metal, share of owned cells]."""
    if not len(units):
        return np.zeros((0, 6), np.float32)
    nd = int(max(defs) + 1)
    metal = np.zeros(nd, np.float32)
    army = np.zeros(nd, bool)
    for d, v in defs.items():
        metal[d] = v[1]
        army[d] = CLASSES[int(v[0])] in ("army", "air")
    fr = units[:, 0].astype(np.int64)
    out = []
    for f in np.unique(fr[fr % 300 == 0]):
        rows = units[fr == f]
        d = np.clip(rows[:, 2].astype(np.int64), 0, nd - 1)
        built = rows[:, 9] >= 1.0
        al = np.array([ally_of.get(int(t), -9) for t in rows[:, 3]])
        k = int(np.searchsorted(cf, f, "right")) - 1 if len(cf) else -1
        tot = sum(int(owned[a][k].sum()) for a in allies if a in owned) if k >= 0 else 0
        lo = int(np.searchsorted(death_f, f, "right"))
        for a in allies:
            m = built & (al == a)
            share = owned[a][k].sum() / tot if k >= 0 and tot and a in owned else 0.0
            out.append([f, a, side_cum[a][lo] if a in side_cum else 0.0, metal[d[m]].sum(), metal[d[m & army[d]]].sum(),
                        share])
    return np.array(out, np.float32).reshape(-1, 6)


def factory_rallies(C, Fin, cls, human, focus, ordered):
    """A unit leaving a factory takes the factory's queued move/fight/patrol orders inside the engine, with no order
    of its own in the replay (his 11-20, "factory waypoints"): without these the players never sent a new unit
    anywhere and the model learned to leave it at home. One decision per new army unit of a human team at the frame
    it finished, toward the last waypoint of the rally of the factory it came out of (the nearest one within 200 that
    was given build orders), unless the player ordered the unit in that step himself."""
    static = CLASSES.index("static")
    fac_pos = {}
    for f, u, d, t, x, z in Fin:
        if cls.get(d) == static:
            fac_pos[u] = (t, x, z)
    builds = {u for f, t, u, d, c, o, ps in C if c < 0 and cls.get(d) == static}
    events = [(f, 0, u, c, o, ps) for f, t, u, d, c, o, ps in C if u in builds] + \
             [(f, 1, u, d, t, (x, z)) for f, u, d, t, x, z in Fin]
    events.sort(key=lambda e: (e[0], e[1]))
    rally = collections.defaultdict(list)
    out = []
    for e in events:
        if e[1] == 0:
            f, _, u, c, o, ps = e
            if c in (10, 15, 16) and len(ps) >= 3:
                if "s" not in o:
                    rally[u] = []
                rally[u].append((c, float(ps[0]), float(ps[2])))
            elif c == 0:
                rally[u] = []
            continue
        f, _, u, d, t, (x, z) = e
        if t not in human or d not in focus or (u, f // STEP) in ordered:
            continue
        best, bd = None, 200.0 ** 2
        for fu, (ft, fx, fz) in fac_pos.items():
            dd = (fx - x) ** 2 + (fz - z) ** 2
            if ft == t and fu in builds and dd < bd:
                best, bd = fu, dd
        if best is None or not rally[best]:
            continue
        c, tx, tz = rally[best][-1]
        out.append([f, f, t, u, KINDS[c], tx, tz, -1, len(rally[best]), int(len(rally[best]) > 1), -1])
    return out


def build(path, out_dir=None):
    path = Path(path)
    defs, teams, allies, spots, heights, moves, names = {}, {}, [], [], None, {}, {}
    eco = set()
    mapxz = (0, 0)
    U, C, K, X, Fin = [], [], [], [], []
    winners = None
    for ln in gzip.open(path, "rt", errors="replace"):
        k = ln[:1]
        p = ln.split()
        if k == "U":
            U.append([float(v) for v in p[1:15]])
        elif k == "C":
            # split on single spaces: an order with no modifier keys (widget and factory orders) has an empty field
            q = ln.rstrip("\r\n").split(" ")
            ps = q[9].split(",") if len(q) >= 10 and q[9] else []
            C.append((int(q[1]), int(q[2]), int(q[3]), int(q[4]), int(q[5]), q[6] if len(q) > 6 else "", ps))
        elif k == "F":
            Fin.append((int(p[1]), int(p[2]), int(p[3]), int(p[4]), float(p[5]), float(p[6])))
        elif k == "X":
            X.append((int(p[1]), int(p[2]), int(p[3]), float(p[4])))
        elif k == "K":
            K.append((int(p[1]), int(p[2]), int(p[3]), int(p[4]), float(p[5]), float(p[6]), int(p[7]), int(p[9])))
        elif k == "D":
            defs[int(p[1])] = (CLASSES.index(p[3]) if p[3] in CLASSES else 7,) + tuple(float(v) for v in p[4:13])
            moves[int(p[1])] = movement(p[2])
            names[int(p[1])] = p[2]
            if p[3] == "static" and ECO.search(p[2]):
                eco.add(int(p[1]))
        elif k == "T":
            teams[int(p[1])] = (int(p[2]), p[3] == "true")
        elif k == "A":
            allies = [int(v) for v in p[1:]]
        elif k == "S":
            spots.append((float(p[2]), float(p[3])))
        elif k == "H":
            heights = np.array([float(v) for v in p[2:]], dtype=np.float32)
            step = int(p[1])
        elif k == "V":
            mapxz = (int(p[2]), int(p[3]))
        elif k == "W":
            winners = [int(v) for v in p[2].split(",")] if len(p) > 2 and p[2] else []
    units = np.array(U, dtype=np.float32) if U else np.zeros((0, 14), np.float32)
    if heights is not None and mapxz[0]:
        nx = len(range(step // 2, mapxz[0] + 1, step))
        heights = heights[: (len(heights) // nx) * nx].reshape(-1, nx)

    desync = None
    dfile = path.parent / "desync.txt"
    if dfile.exists():
        fr = [int(m) for m in re.findall(r"frame-number (\d+)", dfile.read_text(errors="replace"))]
        desync = min(fr) if fr else None

    skills = demo_skills(path.parent)
    ally_of = {t: a for t, (a, ai) in teams.items()}
    # BARAI_ALL_TEAMS=1: our own games, whose side is an AI (11-20: to replay the live model on its own orders)
    human = {t for t, (a, ai) in teams.items() if (not ai or os.environ.get("BARAI_ALL_TEAMS") == "1") and a in allies}
    cls = {d: v[0] for d, v in defs.items()}
    metal = {d: v[1] for d, v in defs.items()}
    hp = {d: max(v[2], 1.0) for d, v in defs.items()}
    focus = {d for d, c in cls.items() if CLASSES[c] in FOCUS}

    # unit id -> def and team (last known), and positions by uid for target-unit lookups
    def_of, team_of = {}, {}
    pos_by_uid = collections.defaultdict(list)
    for r in units:
        uid = int(r[1])
        def_of[uid] = int(r[2])
        team_of[uid] = int(r[3])
        pos_by_uid[uid].append((r[0], r[4], r[5]))
    for f, t, u, d, c, o, ps in C:
        def_of.setdefault(u, d)
        team_of.setdefault(u, t)
    X, n_rec, n_amb, n_drop = recover_victims(X, units, defs, team_of, ally_of)
    if n_rec or n_drop:
        print("  %s: victims recovered %d (ambiguous %d), dropped %d" % (path.parent.name[:40], n_rec, n_amb, n_drop),
              flush=True)

    for rows in pos_by_uid.values():
        rows.sort(key=lambda r: r[0])
    frames_by_uid = {u: [r[0] for r in rows] for u, rows in pos_by_uid.items()}

    def where(uid, frame):
        """the sample nearest in time (the earlier one on a tie)"""
        rows = pos_by_uid.get(uid)
        if not rows:
            return -1.0, -1.0
        fs = frames_by_uid[uid]
        i = bisect.bisect_left(fs, frame)
        if i == len(fs) or (i > 0 and abs(fs[i - 1] - frame) <= abs(fs[i] - frame)):
            i -= 1
            while i > 0 and fs[i - 1] == fs[i]:
                i -= 1
        return rows[i][1], rows[i][2]

    # decisions
    per_unit = collections.defaultdict(list)
    for f, t, u, d, c, o, ps in C:
        if t in human and d in focus and c in KINDS:
            per_unit[u].append((f, t, c, o, ps))
    dec = []
    for u, rows in per_unit.items():
        rows.sort()
        burst = [rows[0]]
        for r in rows[1:] + [None]:
            if r is not None and ((r[0] // STEP == burst[0][0] // STEP)
                                  or ("s" in r[3] and r[0] - burst[-1][0] <= BURST)):
                burst.append(r)
                continue
            plain = [b for b in burst if "s" not in b[3]] or burst
            last = plain[-1]
            f, t, c, o, ps = last
            # A queued route's destination is its last waypoint, not the first leg (his 11-19, raiding: 4.7% of
            # bursts, the end a median 1,259 elmos past the first leg and 0.81 of the way to their base vs 0.63).
            routed = burst[-1] is not last and "s" in burst[-1][3] and len(burst[-1][4]) >= 3
            src = burst[-1] if routed else last
            sps = src[4]
            if len(sps) >= 3:
                tx, tz = float(sps[0]), float(sps[2])
            elif len(sps) == 1 and src[2] == 20:
                tx, tz = where(int(sps[0]), f)
            else:
                tx, tz = where(u, f)
            dec.append([f, burst[0][0], t, u, KINDS[c], tx, tz, -1, len(burst), int(routed), -1])
            burst = [r] if r is not None else []
    dec += factory_rallies(C, Fin, cls, human, focus, {(int(r[3]), int(r[0]) // STEP) for r in dec})
    dec.sort()
    decisions = np.array(dec, dtype=np.float64) if dec else np.zeros((0, 11))
    # groups (one moment, kind and target area) and tasks (units ordered together over time): tools/armynet/tasks.py
    gid, tid, tracker = tasks_of_game(decisions, where) if len(dec) else (np.zeros(0), np.zeros(0), None)
    for i, row in enumerate(dec):
        row[7], row[10] = int(gid[i]), int(tid[i])
    decisions[:, 7], decisions[:, 10] = gid, tid
    task_starts = np.array([[k, *v] for k, v in sorted(tracker.starts.items())], dtype=np.float64).reshape(-1, 5) \
        if tracker else np.zeros((0, 5))

    # outcome inputs: damage in metal by attacker/victim, deaths in metal
    dmg = attribute_damage(X, units, defs, def_of, team_of, ally_of, metal, hp)
    total = sum(r[3] for r in dmg)
    attributed = sum(r[3] for r in dmg if r[1] >= 0) / total if total else 0.0
    # only what the enemy destroyed (11-19: about half of extractor removals and most other economy removals have no
    # attacker -- upgrades to moho, reclaimed solars -- and counted as economy lost): a known enemy attacker, or none
    # recorded but enemy hits on it within the last 10 s (a shot landing after its shooter died)
    last_hit = {}
    for f, a, v, val, aa, va in dmg:
        if aa != va:
            last_hit[v] = max(last_hit.get(v, -1e9), f)
    K = [k for k in K if (k[7] >= 0 and ally_of.get(k[7], -1) != ally_of.get(k[3], -2))
         or (k[7] < 0 and k[0] - last_hit.get(k[1], -1e9) <= 300)]
    kill_value, hit_scale = eco_values(K, units, eco, names, metal, ally_of)
    if kill_value:
        r = [kill_value[i] / max(metal.get(K[i][2], 1.0), 1.0) for i in kill_value]
        rm = [kill_value[i] / max(metal.get(K[i][2], 1.0), 1.0) for i in kill_value
              if re.search("mex|moho", names.get(K[i][2], ""))]
        print("  %s: economy kills %d, value over price median %.1f, max %.1f; extractors %d, median %.1f" % (
            path.parent.name[:40], len(r), float(np.median(r)), float(np.max(r)), len(rm),
            float(np.median(rm)) if rm else 0.0), flush=True)
    deaths = [(f, kill_value.get(i, metal.get(d, 0.0)), ally_of.get(t, -9), x, z, float(d in eco))
              for i, (f, u, d, t, x, z, au, at) in enumerate(K)]
    dmg = [(f, a, v, val * hit_scale.get(def_of.get(v), 1.0), aa, va) for f, a, v, val, aa, va in dmg]
    # running totals: per unit, damage dealt to enemies and taken from enemies (frames, cumulative metal)
    dealt, taken = collections.defaultdict(list), collections.defaultdict(list)
    for f, a, v, val, aa, va in dmg:
        if a >= 0 and aa != va:
            dealt[a].append((f, val))
        if aa != va:
            taken[v].append((f, val))

    def cum(d):
        out = {}
        for u, rows in d.items():
            arr = np.array(rows, dtype=np.float64)
            out[u] = (arr[:, 0], np.concatenate([[0.0], np.cumsum(arr[:, 1])]))
        return out

    dealt, taken = cum(dealt), cum(taken)

    # TRACED BACK (his 11-19: "trace that back ... all the steps that it took to get them there ... all the planning
    # and all the foresight that goes into the final victory of an action"): every hit a unit lands on an enemy
    # economy building credits each order that unit was given before it, halving per HALF seconds back -- the
    # march across the map and the waypoints around their army, not only the last order. HALF is the time to cross
    # the map (its mean side) at the players' median raid speed (85 elmos/s, responses.py): ~84 s on Comet
    # Catcher; credited out to 3 x HALF.
    eco_hits = collections.defaultdict(list)
    for f, a, v, val, aa, va in dmg:
        if a >= 0 and aa != va and def_of.get(v) in eco:
            eco_hits[a].append((f, val))
    eco_hits = {u: np.array(r, dtype=np.float64) for u, r in eco_hits.items()}
    half_frames = (mapxz[0] + mapxz[1]) / 2 / 85.0 * 30 if mapxz[0] else 3000.0

    def traced(u, f0):
        r = eco_hits.get(u)
        if r is None:
            return 0.0
        dt = r[:, 0] - f0
        m = (dt > 0) & (dt <= 3 * half_frames)
        return float((r[m, 1] * 0.5 ** (dt[m] / half_frames)).sum())

    def window(c, u, f0, f1):
        if u not in c:
            return 0.0
        fr, cs = c[u]
        return cs[np.searchsorted(fr, f1, "right")] - cs[np.searchsorted(fr, f0, "right")]

    dth = np.array(deaths, dtype=np.float64).reshape(-1, 6)
    death_f = dth[:, 0]
    side_cum = {a: np.concatenate([[0.0], np.cumsum(np.where(dth[:, 2] == a, dth[:, 1], 0.0))]) for a in allies}
    all_cum = np.concatenate([[0.0], np.cumsum(dth[:, 1])])

    groups = collections.defaultdict(set)
    for row in dec:
        groups[row[7]].add(row[3])
    # an order's own span ends when half its units have a newer order: what follows is the next order's work (his
    # 11-20: a group parked 2.6 min trading nothing was credited for a raid made under later orders)
    order_frames = collections.defaultdict(list)
    for row in dec:
        order_frames[int(row[3])].append(row[0])
    for v in order_frames.values():
        v.sort()

    def span_end(members, f):
        nxt = []
        for u in members:
            fr = order_frames.get(int(u), [])
            k = bisect.bisect_right(fr, f)
            nxt.append(fr[k] if k < len(fr) else 1e12)
        nxt.sort()
        return nxt[(len(nxt) - 1) // 2]

    # IDLE COST (his 11-20: "training should penalize such a position hard because its worthless"): over an order's
    # span, up to 3 minutes, every 10 s the group stands (centre moved under 100), trades nothing, has nothing of ours
    # within 1,000 to guard and sees no enemy within 1,500 costs its metal x 10 s; in metal-minutes
    ufr = units[:, 0].astype(np.int64)
    if len(ufr) > 1 and (np.diff(ufr) < 0).any():
        raise ValueError("U samples out of frame order")
    unit_metal = {u: metal.get(d, 0.0) for u, d in def_of.items()}
    cls_arr = np.array([cls.get(int(d), 7) for d in units[:, 2]]) if len(units) else np.zeros(0, np.int64)
    al_arr = np.array([ally_of.get(int(t), -9) for t in units[:, 3]]) if len(units) else np.zeros(0, np.int64)
    frame_cache = {}

    def at_frame(t):
        if t not in frame_cache:
            a_, b_ = np.searchsorted(ufr, [t, t + 1])
            frame_cache[t] = np.arange(a_, b_)
            if len(frame_cache) > 4000:
                frame_cache.clear()
        return frame_cache[t]
    last_seen = {u: fr[-1] for u, fr in frames_by_uid.items()}

    def idle_cost(members, f, se, ally):
        k = allies.index(ally) if ally in allies else -1
        if k < 0:
            return 0.0
        cost = 0.0
        prev = None
        t = (int(f) // 300 + 1) * 300
        stop = min(se, f + 180 * 30)
        while t + 300 <= stop:
            if any(last_seen.get(int(u), -1) < t - 300 for u in members):
                break
            ps = [where(int(u), t) for u in members]
            cx, cz = np.mean([p[0] for p in ps]), np.mean([p[1] for p in ps])
            if prev is not None and np.hypot(cx - prev[0], cz - prev[1]) < 100:
                traded = sum(window(dealt, u, t - 300, t) + window(taken, u, t - 300, t) for u in members)
                ix = at_frame(t)
                own = ix[(cls_arr[ix] == 0) & (al_arr[ix] == ally)]
                guard = len(own) and (np.hypot(units[own, 4] - cx, units[own, 5] - cz) < 1000).any()
                foe = ix[(al_arr[ix] != ally) & (al_arr[ix] >= 0)]
                if len(foe):
                    foe = foe[((units[foe, 10].astype(np.int64) >> (2 * k)) & 3) > 0]
                seen = len(foe) and (np.hypot(units[foe, 4] - cx, units[foe, 5] - cz) < 1500).any()
                if traded <= 0 and not guard and not seen:
                    cost += sum(unit_metal.get(int(u), 0.0) for u in members) * 10.0 / 60.0
            prev = (cx, cz)
            t += 300
        return cost

    # AFK COST (his 11-22: "their units aren't standing still when there's an active battle going on but our units
    # are"): the same 10-s grid over the order's span, the group standing and trading nothing while a unit of its side
    # within 1,500 trades (a fight on); a separate array (data.py wakes our own games' groups with it), so the players'
    # order ratings are as before
    fighters_at = {}

    def fighters(team, t):
        """(uid, x, z) of the team's army and commanders at t that dealt or took damage in the 10 s before it"""
        if (team, t) not in fighters_at:
            ix = at_frame(t)
            side = ix[np.isin(cls_arr[ix], (2, 3, 4)) & (units[ix, 3] == team)]
            hit = [k for k in side if window(dealt, int(units[k, 1]), t - 300, t)
                   + window(taken, int(units[k, 1]), t - 300, t) > 0]
            fighters_at[(team, t)] = (units[hit, 1].astype(np.int64), units[hit, 4], units[hit, 5])
            if len(fighters_at) > 20000:
                fighters_at.clear()
        return fighters_at[(team, t)]

    def afk_cost(members, f, se, team):
        """(cost, first frame, last frame) of the stand beside a fight: the window data.py wakes in"""
        cost = 0.0
        f0 = f1 = -1
        prev = None
        t = (int(f) // 300 + 1) * 300
        stop = min(se, f + 180 * 30)
        mem = set(int(u) for u in members)
        while t + 300 <= stop:
            if any(last_seen.get(int(u), -1) < t - 300 for u in members):
                break
            ps = [where(int(u), t) for u in members]
            cx, cz = np.mean([p[0] for p in ps]), np.mean([p[1] for p in ps])
            if prev is not None and np.hypot(cx - prev[0], cz - prev[1]) < 100:
                traded = sum(window(dealt, u, t - 300, t) + window(taken, u, t - 300, t) for u in members)
                if traded <= 0:
                    fu, fx, fz = fighters(team, t)
                    near = (np.hypot(fx - cx, fz - cz) < 1500) & ~np.isin(fu, list(mem))
                    if near.any():
                        cost += sum(unit_metal.get(int(u), 0.0) for u in members) * 10.0 / 60.0
                        f0 = t - 300 if f0 < 0 else f0
                        f1 = t
            prev = (cx, cz)
            t += 300
        return cost, f0, f1
    # a task's members at a frame: units whose latest order before it (within QUIET) put them in that task
    stays = collections.defaultdict(list)   # task -> [(unit, from frame, until frame)]
    per_unit = collections.defaultdict(list)
    for row in dec:
        per_unit[row[3]].append((row[0], row[10]))
    for u, rows in per_unit.items():
        rows.sort()
        for k, (f0, t0) in enumerate(rows):
            until = min(rows[k + 1][0] if k + 1 < len(rows) else 1e12, f0 + QUIET * 30)
            stays[t0].append((u, f0, until))

    def task_members(t, f):
        return {u for u, a, b in stays.get(t, ()) if a <= f < b} or set()

    outcome = np.zeros((len(dec), len(HORIZONS), 9), dtype=np.float32)
    outcome_span = np.full((len(dec), len(HORIZONS), 9), np.nan, dtype=np.float32)
    span_s = np.full(len(dec), -1, dtype=np.float32)
    idle_m = np.zeros(len(dec), dtype=np.float32)
    afk_m = np.zeros(len(dec), dtype=np.float32)
    afk_w = np.full((len(dec), 2), -1, dtype=np.int64)  # the stand's first and last frame
    is_eco = dth[:, 5] > 0
    result = np.full(len(dec), -1, dtype=np.int8)
    cache = {}
    cf, owned = control_series(units, defs, ally_of, allies, mapxz)
    cell_x = (np.arange(CONTROL_G) + 0.5) * (mapxz[0] / CONTROL_G)
    cell_z = (np.arange(CONTROL_G) + 0.5) * (mapxz[1] / CONTROL_G)

    def control_at(ally, f, tx, tz):
        """(share of owned cells, (ours - theirs) near the target / cells there) at the last sample at or before f"""
        if not len(cf) or ally not in owned:
            return 0.0, 0.0
        k = int(np.searchsorted(cf, f, "right")) - 1
        if k < 0:
            return 0.0, 0.0
        ours = owned[ally][k]
        theirs = np.zeros_like(ours)
        for b, m in owned.items():
            if b != ally:
                theirs |= m[k]
        tot = ours.sum() + theirs.sum()
        near = ((cell_x[None, :] - tx) ** 2 + (cell_z[:, None] - tz) ** 2) <= NEAR * NEAR
        n = max(int(near.sum()), 1)
        return (ours.sum() / tot if tot else 0.0), float((ours & near).sum() - (theirs & near).sum()) / n
    for i, row in enumerate(dec):
        f, team, g, tx, tz = row[0], row[2], row[7], row[5], row[6]
        ally = ally_of[team]
        if winners is not None:
            result[i] = 1 if ally in winners else 0
        members = groups[g]
        span_end_f = span_end(members, f)
        span_s[i] = (span_end_f - f) / 30.0 if span_end_f < 1e11 else -1
        if g in cache:
            outcome[i], outcome_span[i], idle_m[i], afk_m[i], afk_w[i] = cache[g]
            continue
        near = (dth[:, 3] - tx) ** 2 + (dth[:, 4] - tz) ** 2 <= AREA * AREA
        c0, n0 = control_at(ally, f, tx, tz)
        # the whole task's later hits on their economy (his 11-19: decoys and escorts share the raid's credit)
        eco_traced = sum(traced(u, f) for u in (task_members(row[10], f) | members))
        for j, h in enumerate(HORIZONS):
            end = f + h * 30
            if desync is not None and end > desync:
                outcome[i, j] = np.nan
                continue
            own = sum(window(dealt, u, f, end) - window(taken, u, f, end) for u in members)
            # what the order changed (his 11-19: "we kept engaging when we probably should have stopped engaging"):
            # the units' trade after the order minus their trade over the same span before it, so a retreat that
            # cuts a losing fight's bleeding scores well instead of looking like the losses it was escaping
            before = sum(window(dealt, u, f - h * 30, f) - window(taken, u, f - h * 30, f) for u in members)
            own_change = own - before
            lo, hi = np.searchsorted(death_f, f, "right"), np.searchsorted(death_f, end, "right")
            ours = side_cum[ally][hi] - side_cum[ally][lo] if ally in side_cum else 0.0
            team_d = (all_cum[hi] - all_cum[lo] - ours) - ours
            sl = slice(lo, hi)
            nm = near[sl]
            mine = dth[sl, 2] == ally
            area = dth[sl, 1][nm & ~mine].sum() - dth[sl, 1][nm & mine].sum()
            c1, n1 = control_at(ally, end, tx, tz)
            ec = is_eco[sl]
            eco_near = dth[sl, 1][nm & ec & ~mine].sum() - dth[sl, 1][nm & ec & mine].sum()
            eco_side = dth[sl, 1][ec & ~mine].sum() - dth[sl, 1][ec & mine].sum()
            outcome[i, j] = (own, area, team_d, c1 - c0, n1 - n0, eco_near, eco_side, eco_traced, own_change)
            # the same measures over the order's own span only
            se = min(end, span_end_f)
            own_s = sum(window(dealt, u, f, se) - window(taken, u, f, se) for u in members)
            hi_s = np.searchsorted(death_f, se, "right")
            sl_s = slice(lo, hi_s)
            nm_s, mine_s, ec_s = near[sl_s], dth[sl_s, 2] == ally, is_eco[sl_s]
            area_s = dth[sl_s, 1][nm_s & ~mine_s].sum() - dth[sl_s, 1][nm_s & mine_s].sum()
            eco_near_s = dth[sl_s, 1][nm_s & ec_s & ~mine_s].sum() - dth[sl_s, 1][nm_s & ec_s & mine_s].sum()
            _, n1s = control_at(ally, se, tx, tz)
            outcome_span[i, j] = (own_s, area_s, np.nan, np.nan, n1s - n0, eco_near_s, np.nan, np.nan,
                                  own_s - before if se >= end else np.nan)
        idle_m[i] = idle_cost(members, f, span_end_f, ally)
        afk_m[i], afk_w[i, 0], afk_w[i, 1] = afk_cost(members, f, span_end_f, team)
        cache[g] = (outcome[i].copy(), outcome_span[i].copy(), idle_m[i], afk_m[i], afk_w[i].copy())

    # what staying got (his 11-19: "lack of recognition of EXITING a fight ... preserving army/health"): every 30
    # frames, each human army unit in a fight (enemy army within FIGHT_R) that gets no new order in the next STAY_S
    # is a unit that stayed; its own trade over the first three horizons, with the local odds, is the baseline an
    # order in the same situation is rated against (data.py), so a retreat earns the loss it avoided
    dec_unit_frames = collections.defaultdict(list)
    for row in dec:
        dec_unit_frames[int(row[3])].append(row[0])
    dec_unit_frames = {u: np.array(sorted(v)) for u, v in dec_unit_frames.items()}
    army_defs = np.array(sorted(d for d, c in cls.items() if CLASSES[c] in ("army", "air")), np.int64)
    mob = units[np.isin(units[:, 2].astype(np.int64), army_defs) & (units[:, 9] >= 1)]
    mob = mob[mob[:, 0] % 30 == 0]
    ally_arr = np.array([ally_of.get(int(t), -9) for t in mob[:, 3]])
    met = np.array([metal.get(int(d), 0.0) for d in mob[:, 2]], np.float64)
    order_m = np.argsort(mob[:, 0], kind="stable")
    mob, ally_arr, met = mob[order_m], ally_arr[order_m], met[order_m]
    bounds = np.searchsorted(mob[:, 0], np.unique(mob[:, 0]))
    bounds = list(bounds) + [len(mob)]
    stays_rows, odds_at = [], {}
    for a_, b_ in zip(bounds[:-1], bounds[1:]):
        fr_ = mob[a_:b_]
        if not len(fr_):
            continue
        f = int(fr_[0, 0])
        al, mm = ally_arr[a_:b_], met[a_:b_]
        dx = fr_[:, None, 4] - fr_[None, :, 4]
        dz = fr_[:, None, 5] - fr_[None, :, 5]
        near = dx * dx + dz * dz <= FIGHT_R ** 2
        same = al[:, None] == al[None, :]
        enemy = (near & ~same) @ mm
        ours = (near & same) @ mm
        for j in range(len(fr_)):
            uid, team = int(fr_[j, 1]), int(fr_[j, 3])
            if enemy[j] <= 0:
                odds_at[(uid, f)] = -1.0
                continue
            odds = float(enemy[j] / max(ours[j], 1.0))
            odds_at[(uid, f)] = odds
            if team not in human:
                continue
            uf = dec_unit_frames.get(uid)
            if uf is not None and np.any((uf > f) & (uf <= f + STAY_S * 30)):
                continue
            own = []
            for h in HORIZONS[:3]:
                end = f + h * 30
                own.append(window(dealt, uid, f, end) - window(taken, uid, f, end)
                           if desync is None or end <= desync else np.nan)
            # under fire: metal taken in the last 5 s (players pull back the units being hit; compare like with like)
            stays_rows.append([f, team, uid, odds] + own + [window(taken, uid, f - 150, f)])
    stays = np.array(stays_rows, np.float32).reshape(-1, 8)
    # the local odds at each decision (enemy army metal within FIGHT_R over ours; -1 not in a fight), from the
    # nearest 30-frame sample at or before it
    dec_odds = np.array([odds_at.get((int(row[3]), int(row[0]) // 30 * 30), -1.0) for row in dec], np.float32)
    dec_hit = np.array([window(taken, int(row[3]), row[0] - 150, row[0]) for row in dec], np.float32)

    defs_arr = np.array([[d] + list(v) + [float(d in eco)] + list(moves.get(d, (0.0,) * 5))
                         + [income(names.get(d, ""))] for d, v in sorted(defs.items())], dtype=np.float32)
    teams_arr = np.array([[t, a, int(ai), skills.get(t, -1)] for t, (a, ai) in sorted(teams.items())],
                         dtype=np.float32)
    out_dir = Path(out_dir) if out_dir else path.parent
    out_dir.mkdir(parents=True, exist_ok=True)
    dest = out_dir / (path.parent.name + ".npz")
    sides = side_series(units, defs, ally_of, allies, death_f, side_cum, cf, owned)
    # unit names, one per defs row (the army model looks up full stats by name: tools/armynet/unitstats.py)
    def_names = np.array([names.get(d, "") for d, _ in sorted(defs.items())])
    np.savez_compressed(dest, units=units, defs=defs_arr, def_names=def_names, teams=teams_arr, decisions=decisions, outcome=outcome,
                        sides=sides, outcome_span=outcome_span, span_s=span_s, idle_m=idle_m, afk_m=afk_m, afk_w=afk_w,
                        result=result, spots=np.array(spots, np.float32), heights=heights if heights is not None
                        else np.zeros((0, 0), np.float32), map=np.array(mapxz), allies=np.array(allies),
                        desync_frame=np.array(desync if desync is not None else -1), horizons=np.array(HORIZONS),
                        attributed=np.array(attributed), task_starts=task_starts,
                        # every hit as the recording has it (frame, attacker or -1, victim, damage) for the
                        # incoming-fire layers (his 11-19: players "certainly see the shots")
                        hits=np.array(X, dtype=np.float32).reshape(-1, 4),
                        # units that stayed in fights (frame, team, uid, odds, own trade at the first 3 horizons) and
                        # each decision's local odds: the baseline an order is rated against (data.py)
                        stays=stays, dec_odds=dec_odds, dec_hit=dec_hit)
    return dest, len(dec), len(groups), attributed


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    target = Path(argv[0])
    out = Path(argv[argv.index("--out") + 1]) if "--out" in argv else None
    # a recording queued to be recorded again (requeue_packed.py) builds from its kept orders.packed.txt.gz, with
    # recover_victims, until the new orders.txt.gz arrives
    # a recording queued to be recorded again builds from the file it kept (requeue_rate.py: orders.1hz.txt.gz,
    # requeue_packed.py: orders.packed.txt.gz) until the new orders.txt.gz arrives
    kinds = ("orders.txt.gz", "orders.1hz.txt.gz", "orders.packed.txt.gz")
    paths = [target] if target.is_file() else sorted(
        next(d / k for k in kinds if (d / k).exists())
        for d in target.iterdir() if d.is_dir() and any((d / k).exists() for k in kinds))
    todo = [p for p in paths if "--force" in argv or not ((out or p.parent) / (p.parent.name + ".npz")).exists()
            or ((out or p.parent) / (p.parent.name + ".npz")).stat().st_mtime <= p.stat().st_mtime]
    jobs = int(argv[argv.index("--jobs") + 1]) if "--jobs" in argv else 1
    if jobs > 1:
        from concurrent.futures import ProcessPoolExecutor
        with ProcessPoolExecutor(jobs) as ex:
            for p, r in zip(todo, ex.map(_build_safe, todo, [out] * len(todo))):
                print(r, flush=True)
    else:
        for p in todo:
            print(_build_safe(p, out), flush=True)
    return 0


def _build_safe(p, out):
    try:
        d, n, g, att = build(p, out)
        return "%s decisions %d groups %d damage with an attacker in reach %.0f%%" % (d.name, n, g, 100 * att)
    except Exception as e:  # one bad recording must not stop a rebuild of hundreds
        return "FAILED %s: %r" % (p, e)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
