"""Training examples for the army model from replay_dataset.py's .npz files.

One example = one human team at one second (a frame on the 1 s sample grid): the side's view as a map grid
plus a token per own army/air/radar/jammer unit, and per token the label: keep its order, or the new order
it was given in the next second (kind, cell on the grid, offset inside the cell).
"""
import glob
import os
import math
from pathlib import Path

import numpy as np

from tasks import QUIET, forces_at
from unitstats import STAT_F, UnitStats

G = 64
CLASSES = ("static", "builder", "com", "army", "air", "radar", "jammer", "other")
FOCUS = (3, 4, 5, 6)
CMD_SLOTS = {-1: 0, 10: 1, 16: 2, 20: 3, 15: 4}
N_CMD = 6
N_KIND = 6
CHANNELS = 31
REACH_S = 60.0  # risk / advantage fields: metal arriving within about a minute counts most (channels 29, 30)
REACH_ROWS = 1500  # _reach_rows cache, 32 KB a row
TOKEN_BASE = 48
# 48..: the unit's full stats from defs.json (unitstats.py; his 11-22: hp, range, damage, fire rate, speed, "all the
# factors"); zeros when a game has no names or no stats file, so old data reads as before
TOKEN_F = TOKEN_BASE + STAT_F
# enemy units the side sees now or remembers (his 11-22: the model must see enemy units): stats, class, where, how fast,
# how long ago, in sight / radar only / remembered, a building, health while in sight, metal
E_EXTRA = 18
E_TOKEN_F = STAT_F + E_EXTRA
MAX_ETOKENS = 160
_STATS = None


def unit_stats():
    """The stats table (runtime/armynet/defs.json), loaded once; empty when the file is missing."""
    global _STATS
    if _STATS is None:
        _STATS = UnitStats.load(os.environ.get("ARMYNET_DEFS") or None)
    return _STATS


MAX_TOKENS = 160
MEMORY_S = 300
STEP = 10  # frames per decision (replay_dataset.STEP; his 11-19: under 500 ms)
SHOT_DIR = 500.0
SCALARS = 10
# (horizon index, measure): own 5/15/60 s, area 3/10 min, side 10 min; map control near the target 3/10 min and the
# side's share 10 min (his 11-18: "one 'pro' can be measured in increasing the map control we have")
# and economy buildings destroyed, theirs minus ours, near the target 3/10 min and the side's 10 min (his 11-19:
# "they are hurting our economy but we are never hurting their economy")
# and the economy damage the order's units went on to do, traced back to every order before it (his 11-19: "trace
# that back ... all the steps that it took to get them there"; replay_dataset.py `eco_traced`, horizon-free)
# The units' own trade is counted as the change the order made (measure 8: after minus before over the same span)
# since 11-19: in absolute terms a retreat out of a losing fight still bled and was marked down ("we kept engaging
# when we probably should have stopped engaging").
# Side-wide 10-min totals (team trade, map-control share, eco_side) are left out since 11-19: they are the same for
# every order of a side at a time and measured who was ahead, not what the order did (the review: 85% of the score's
# variance was explained by side and 30-s window).
HORIZON_PICK = ((0, 8), (1, 8), (2, 8), (3, 1), (4, 1), (3, 4), (4, 4), (3, 5), (4, 5), (4, 7))
WINDOW_S = 30
VALUE_H = (10, 60, 180, 600)  # seconds: the value head's horizons
RATING_PARTS = {"span", "idle", "chain"}  # order rating: span-only credit near the target, idle cost, chain credit
CONTACT_W = float(os.environ.get("BARAI_CONTACT_W", "1"))  # 11-24 A/B: weight of in-contact clicks' place/member labels


def _stay_key(t, w, b):
    """One int64 per (team, window, band) for _stay_baseline's group means: team -2.., window under 2^24, band -3..12."""
    t, w, b = np.asarray(t, np.int64), np.asarray(w, np.int64), np.asarray(b, np.int64)
    assert (t >= -2).all() and (t < 1 << 20).all() and (w >= 0).all() and (w < 1 << 24).all() \
        and (b >= -3).all() and (b < 13).all()
    return ((t + 2) * (1 << 24) + w) * 16 + (b + 3)


def _group_means(keys, xs):
    """Sorted distinct keys and the mean of xs over each, every mean over its values in their original order (what
    np.mean of the list built row by row gives, to the bit)."""
    if not len(keys):
        return np.zeros(0, np.int64), np.zeros(0)
    o = np.argsort(keys, kind="stable")
    ks, xo = keys[o], xs[o]
    cuts = (np.flatnonzero(np.diff(ks)) + 1).tolist()
    starts = [0] + cuts
    return ks[starts], np.array([np.mean(xo[a:b]) for a, b in zip(starts, cuts + [len(ks)])])


def _disk(r):
    r = int(r)
    ys, xs = np.mgrid[-r:r + 1, -r:r + 1]
    m = xs * xs + ys * ys <= r * r + r
    return ys[m], xs[m]


DISKS = [_disk(r) for r in range(0, 9)]


class Game:
    def __init__(self, path, neg_share=0.1, rng=None):
        z = np.load(path)
        self.path = Path(path)
        self.decisions = z["decisions"]
        self.outcome = z["outcome"]
        self.outcome_span = z["outcome_span"] if "outcome_span" in z.files else None
        self.idle_m = z["idle_m"] if "idle_m" in z.files else None
        self.afk_m = z["afk_m"] if "afk_m" in z.files else None
        self.afk_w = z["afk_w"] if "afk_w" in z.files else None
        self.span_s = z["span_s"] if "span_s" in z.files else None
        self.result = z["result"]
        self.desync = int(z["desync_frame"])
        self.stays = z["stays"] if "stays" in z.files else None
        self.dec_odds = z["dec_odds"] if "dec_odds" in z.files else None
        self.dec_hit = z["dec_hit"] if "dec_hit" in z.files else None
        self._setup(z["units"], z["defs"], z["map"], z["allies"], z["teams"], z["spots"], z["heights"],
                    names=z["def_names"] if "def_names" in z.files else None)
        self._index_tasks(self.decisions, z["task_starts"] if "task_starts" in z.files else np.zeros((0, 5)))
        self._index_hits(z["hits"] if "hits" in z.files else np.zeros((0, 4)))
        self.rating_parts = RATING_PARTS
        self._index_decisions()
        self._index_sides(z["sides"] if "sides" in z.files else None)
        self.neg_share = neg_share
        self.examples = self._pick_examples(neg_share, rng or np.random.default_rng(0))

    @classmethod
    def live(cls, units, defs, mapxz, allies, teams, spots, heights, orders=None, task_starts=None, hits=None,
             names=None, absent=None):
        """A game being played: no labels, just the view (tools/armynet/serve.py); `orders` are the model's own past
        orders in the decisions layout (task id in column 10) and `task_starts` their tasks, for the task inputs;
        `absent` the folded store's absence marks (absent_of)."""
        g = cls.__new__(cls)
        g.path, g.desync, g.is_live = None, -1, True
        g._absent_prior = {key: np.array([v], np.int64) for key, v in (absent or {}).items()}
        g.decisions = np.zeros((0, 11))
        g.dec_by = {}
        g._setup(units, defs, mapxz, allies, teams, spots, heights, names=names)
        g._index_hits(hits if hits is not None else np.zeros((0, 4)))
        g._index_tasks(orders if orders is not None else np.zeros((0, 11)),
                       task_starts if task_starts is not None else np.zeros((0, 5)))
        g.examples = []
        return g

    def _index_hits(self, hits):
        """Hits in frame order (frame, attacker or -1, victim, damage), for the incoming-fire layers."""
        self.hits = hits[np.argsort(hits[:, 0], kind="stable")] if len(hits) else np.zeros((0, 4), np.float32)

    def _fire_layers(self, grid, f, ally):
        """Layers 25-26 (his 11-19: "they might not see enemy artillery that's hitting them or defensive emplacements
        that are hitting them, but they certainly see the shots"): over the last 10 s, the metal value of hits on
        our side's units where they landed (25), and where those shots came from, smeared over 300 elmos -- a shot's
        trail shows its direction, not the shooter's exact spot (26). Positions from the unit samples."""
        if not len(self.hits):
            return
        lo, hi = np.searchsorted(self.hits[:, 0], [f - 300, f], "right")
        h = self.hits[lo:hi]
        if not len(h):
            return
        vx, vz, vv, ax_, az_, av = [], [], [], [], [], []
        for fr, a, v, dmg in h:
            vi = self._pos(int(v), fr)
            if vi is None or self.ally_of.get(vi[2], -9) != ally:
                continue
            d = vi[3]
            val = min(dmg / max(self.d_hp[d], 1.0), 1.0) * self.d_metal[d]
            vx.append(vi[0]); vz.append(vi[1]); vv.append(val)
            if a >= 0:
                ai = self._pos(int(a), fr)
                if ai is not None and self.ally_of.get(ai[2], -9) != ally:
                    sx_, sz_ = ai[0], ai[1]
                    # a shooter this side cannot see (sight or radar) shows only as the direction its shots come
                    # from: placed SHOT_DIR elmos from the hit unit that way, not where it stands
                    if not (ai[4] >> (2 * self.allies.index(ally))) & 3:
                        dx, dz = sx_ - vi[0], sz_ - vi[1]
                        dn = max(float(np.hypot(dx, dz)), 1.0)
                        sx_, sz_ = vi[0] + dx / dn * min(dn, SHOT_DIR), vi[1] + dz / dn * min(dn, SHOT_DIR)
                    ax_.append(sx_); az_.append(sz_); av.append(val)
        if vv:
            self._splat(grid, 25, np.array(vx), np.array(vz), np.array(vv, np.float32))
        if av:
            self._splat_disk(grid, 26, np.array(ax_), np.array(az_), np.array(av, np.float32),
                             np.full(len(av), 300.0))
        grid[25] = np.log1p(grid[25])
        grid[26] = np.log1p(grid[26])

    def _pos(self, uid, frame):
        """(x, z, team, def) of a unit at its sample nearest at or before frame, within 10 s; None if not sampled."""
        if not hasattr(self, "_pos_idx"):
            order = np.lexsort((self.frames, self.uid))
            self._pos_idx = (self.uid[order], self.frames[order], order)
        uids, frs, order = self._pos_idx
        a, b = np.searchsorted(uids, [uid, uid + 1])
        if a == b:
            return None
        k = a + int(np.searchsorted(frs[a:b], frame, "right")) - 1
        if k < a or frame - frs[k] > 300:
            return None
        r = order[k]
        return self.units[r, 4], self.units[r, 5], int(self.uteam[r]), int(self.udef[r]), int(self.units[r, 10])

    def _index_tasks(self, decisions, starts):
        """Per unit, its orders' frames and tasks in time order; per task, where and when it started."""
        self.unit_orders = {}
        if len(decisions) and decisions.shape[1] > 10:
            order = np.argsort(decisions[:, 0], kind="stable")
            u = decisions[order, 3].astype(np.int64)
            rows = order[np.argsort(u, kind="stable")]
            us = decisions[rows, 3].astype(np.int64)
            fr, tk = decisions[rows, 0], decisions[rows, 10].astype(np.int64)
            cuts = (np.flatnonzero(np.diff(us)) + 1).tolist()
            for a, b in zip([0] + cuts, cuts + [len(us)]):
                self.unit_orders[int(us[a])] = (fr[a:b], tk[a:b])
        self.task_start = {int(r[0]): (r[2], r[3], r[4]) for r in starts}

    def _fight_features(self, tok, rows, idx, f, friend, vis, army, metal):
        """Columns 39-41 (his 11-19: "we kept engaging when we probably should have stopped"; players pulled units
        back where the model sent them on, retreat_recall 0.32): what a player sees of a fight turning. 39: this
        unit's health now minus 5 s ago; 40: log enemy army metal in sight within 800 minus log ours (allies too);
        41: log metal of ours (allies too) within 800 at f-10 s that no longer exists at f."""
        u = self.units
        ux, uz = u[rows, 4], u[rows, 5]
        prev = self.rows_near(f - 150) if f >= 150 else np.zeros(0, np.int64)
        hp_then = {int(self.uid[k]): u[k, 8] for k in prev}
        tok[:, 39] = [u[r, 8] - hp_then.get(int(self.uid[r]), u[r, 8]) for r in rows]
        fx, fz, fm = u[idx[vis & army], 4], u[idx[vis & army], 5], metal[vis & army]
        ox, oz, om = u[idx[friend & army], 4], u[idx[friend & army], 5], metal[friend & army]
        # 11-24: a unit with an enemy army unit in sight within 600 is in contact (the Mac's contact split: players
        # re-order such units 20-26 times a minute, the model 8.7); CONTACT_W weighs those clicks' labels
        self._contact = np.zeros(len(rows), bool)
        for j in range(len(rows)):
            d2 = (fx - ux[j]) ** 2 + (fz - uz[j]) ** 2
            self._contact[j] = bool((d2 <= 600 ** 2).any())
            e = fm[d2 <= 800 ** 2].sum()
            o = om[(ox - ux[j]) ** 2 + (oz - uz[j]) ** 2 <= 800 ** 2].sum()
            tok[j, 40] = np.log1p(e) - np.log1p(o)
        if f >= 300:
            then = self.rows_near(f - 300)
            ally = self.ually[idx[friend]][0] if friend.any() else None
            now_ids = set(self.uid[idx].tolist())
            gone = [k for k in then if self.ually[k] == ally and int(self.uid[k]) not in now_ids
                    and self.ucls[k] != 0]
            if gone:
                gx, gz = u[gone, 4], u[gone, 5]
                gm = self.d_metal[self.udef[gone]]
                for j in range(len(rows)):
                    tok[j, 41] = np.log1p(gm[(gx - ux[j]) ** 2 + (gz - uz[j]) ** 2 <= 800 ** 2].sum())

    def _task_features(self, tok, uids, ux, uz, f):
        """Columns 28-35 (his 11-19, tasks): in a task; its size (log); its age; how far it has travelled since it
        formed (x, z, over the map); its members' centre relative to this unit (x, z); time since this unit's last
        order. Only orders before frame f count: those at f are what is being predicted."""
        n = len(uids)
        task = np.full(n, -1, np.int64)
        since = np.full(n, 3.0, np.float32)
        for j, uid in enumerate(uids):
            fr = self.unit_orders.get(int(uid))
            if fr is None:
                continue
            k = int(np.searchsorted(fr[0], f, "left")) - 1
            if k >= 0 and f - fr[0][k] <= QUIET * 30:
                task[j] = fr[1][k]
                since[j] = min((f - fr[0][k]) / 30.0 / 60.0, 3.0)
        tok[:, 35] = since
        for t in set(task.tolist()) - {-1}:
            m = task == t
            cx, cz = float(ux[m].mean()), float(uz[m].mean())
            st = self.task_start.get(t)
            tok[m, 28] = 1
            tok[m, 29] = np.log1p(m.sum())
            if st is not None:
                tok[m, 30] = min((f - st[0]) / 30.0 / 120.0, 3.0)
                tok[m, 31] = (cx - st[1]) / max(self.mapx, 1)
                tok[m, 32] = (cz - st[2]) / max(self.mapz, 1)
            tok[m, 33] = (cx - ux[m]) / 2000
            tok[m, 34] = (cz - uz[m]) / 2000
        return task

    def worthless_groups(self):
        """Per decision: 1 when its order put its units somewhere worthless (his 11-20 watch game: 7 units sent to an
        empty expansion stood 2.6 min, guarding nothing, seeing nothing, while the enemy built there unseen):
        30-90 s after the order the group is alive, has moved under 150 (standing), had no new order, our side has no
        building within 1,000 of it, it sees no enemy within 1,500, and its own trade is 0 at 60 s and 3 min."""
        d = self.decisions
        out = np.zeros(len(d), np.int8)
        if not len(d):
            return out
        by_uid = {}
        for i in np.argsort(d[:, 0], kind="stable"):
            by_uid.setdefault(int(d[i, 3]), []).append(float(d[i, 0]))
        last = int(self.frames.max())
        groups = {}
        for i, r in enumerate(d):
            groups.setdefault(int(r[7]), []).append(i)
        static_idx = {}
        for gid, ii in groups.items():
            r = d[ii[0]]
            f0, team = float(r[0]), int(r[2])
            if r[4] not in (1, 2) or f0 + 90 * 30 > last or (self.desync >= 0 and f0 + 90 * 30 > self.desync):
                continue
            if np.isnan(self.outcome[ii, 2, 0]).any() or np.abs(self.outcome[ii, 2, 0]).max() >= 1 \
                    or np.isnan(self.outcome[ii, 3, 0]).any() or np.abs(self.outcome[ii, 3, 0]).max() >= 1:
                continue
            members = [int(d[i, 3]) for i in ii]
            if any(any(f0 < x <= f0 + 90 * 30 for x in by_uid.get(u, ())) for u in members):
                continue
            ally = self.ally_of.get(team)
            k = self.allies.index(ally)
            cs, ok = [], True
            for s in (30, 60, 90):
                ps = [self._pos(u, f0 + s * 30) for u in members]
                if any(p is None for p in ps):
                    ok = False
                    break
                cs.append((np.mean([p[0] for p in ps]), np.mean([p[1] for p in ps])))
            if not ok or np.hypot(cs[2][0] - cs[0][0], cs[2][1] - cs[0][1]) >= 150:
                continue
            cx, cz = cs[1]
            sf = int(f0 + 60 * 30) // 300 * 300
            if sf not in static_idx:
                a_, b_ = np.searchsorted(self.frames, [sf, sf + 1])
                ix = np.arange(a_, b_)
                static_idx[sf] = ix[self.ucls[ix] == 0]
            ix = static_idx[sf]
            own = ix[self.ually[ix] == ally]
            if len(own) and (np.hypot(self.units[own, 4] - cx, self.units[own, 5] - cz) < 1000).any():
                continue
            seen = False
            for s in (30, 60, 90):
                f = int(f0 + s * 30) // 10 * 10
                a_, b_ = np.searchsorted(self.frames, [f, f + 1])
                ix = np.arange(a_, b_)
                foe = ix[(self.ually[ix] != ally) & (self.ually[ix] >= 0)]
                vis = ((self.units[foe, 10].astype(np.int64) >> (2 * k)) & 3) > 0
                foe = foe[vis]
                if len(foe) and (np.hypot(self.units[foe, 4] - cs[s // 30 - 1][0],
                                          self.units[foe, 5] - cs[s // 30 - 1][1]) < 1500).any():
                    seen = True
                    break
            if not seen:
                out[ii] = 1
        return out

    def _last_pos(self, uid, frame):
        """(x, z, team, def, sight, sample frame) of a unit's last sample at or before frame, however old; None if
        never sampled by then."""
        if not hasattr(self, "_pos_idx"):
            order = np.lexsort((self.frames, self.uid))
            self._pos_idx = (self.uid[order], self.frames[order], order)
        uids, frs, order = self._pos_idx
        a, b = np.searchsorted(uids, [uid, uid + 1])
        if a == b:
            return None
        k = a + int(np.searchsorted(frs[a:b], frame, "right")) - 1
        if k < a:
            return None
        r = order[k]
        return (self.units[r, 4], self.units[r, 5], int(self.uteam[r]), int(self.udef[r]), int(self.units[r, 10]),
                int(frs[k]))

    def _last_rows(self, uq, fq):
        """_last_pos for many (uid, frame) at once: the unit row of each one's last sample at or before its frame, -1
        if none. One search over (uid, frame) keys finds the same sample _last_pos's two searches do."""
        if not hasattr(self, "_pos_idx"):
            order = np.lexsort((self.frames, self.uid))
            self._pos_idx = (self.uid[order], self.frames[order], order)
        uids, frs, order = self._pos_idx
        out = np.full(len(uq), -1, np.int64)
        if not len(uids) or not len(uq):
            return out
        if not hasattr(self, "_pos_key"):
            f0 = int(frs.min())
            span = int(frs.max()) - f0 + 3
            self._pos_key = ((uids - int(uids.min())) * span + (frs - f0 + 1), int(uids.min()), f0, span)
        key, u0, f0, span = self._pos_key
        q = (uq - u0) * span + np.clip(fq - f0 + 1, 0, span - 1)
        k = np.searchsorted(key, q, "right") - 1
        hit = (k >= 0) & (uids[np.maximum(k, 0)] == uq)
        out[hit] = order[k[hit]]
        return out

    def _cell_off(self, x, z):
        gx, gz = x / max(self.mapx, 1) * G, z / max(self.mapz, 1) * G
        cx, cz = int(np.clip(gx, 0, G - 1)), int(np.clip(gz, 0, G - 1))
        return cz * G + cx, (float(np.clip(gx - cx, 0, 1)), float(np.clip(gz - cz, 0, 1)))

    def _wake_idle(self, out, force, uids, f):
        """Our own games only (his 11-20, "we shouldn't see this as valued behavior"): a force not clicked this step
        whose units' latest order put them somewhere idle (its group carries idle cost) and is 30 s or more into that
        order's span is labelled as clicked -- standing there was the mistake -- for the click head alone (f_cell -1:
        no place, kind or shape is taught). Players are left as they played."""
        if getattr(self, "idle_m", None) is None or getattr(self, "span_s", None) is None or "own-games" not in \
                str(self.path).replace("\\", "/"):
            return
        if not hasattr(self, "_dec_uid"):
            d = self.decisions
            order = np.lexsort((d[:, 0], d[:, 3]))
            self._dec_uid = (d[order, 3].astype(np.int64), d[order, 0], order)
        du, df, di = self._dec_uid
        jobs = {}
        for fi in np.where((out["f_click"] == 0) & out["f_mask"])[0]:
            idle = []
            for j in np.where(force == fi)[0]:
                a, b = np.searchsorted(du, [int(uids[j]), int(uids[j]) + 1])
                k = a + int(np.searchsorted(df[a:b], f, "left")) - 1
                if k < a:
                    idle.append(False)
                    continue
                i = di[k]
                into = (f - df[k]) / 30.0
                # his 11-22: standing while a fight is on within 1,500 wakes from 10 s into that stand, inside it only
                # (replay_dataset afk_w: its first and last frame on the 10-s grid)
                aw = getattr(self, "afk_w", None)
                afk = aw is not None and aw[i, 0] >= 0 and aw[i, 0] + 300 <= f <= aw[i, 1]
                idle.append(bool((self.idle_m[i] > 0 and 30.0 <= into or afk) and into <= max(self.span_s[i], 0)))
            if idle and np.mean(idle) > 0.5:
                out["f_click"][fi] = 1
                out["f_w"][fi] = 1.0
                if os.environ.get("BARAI_WAKE_PLACE") == "jobs":
                    t = self._job_target(f, [int(uids[j]) for j in np.where(force == fi)[0]])
                    if t is not None:
                        jobs[fi] = t
                elif os.environ.get("BARAI_WAKE_PLACE") == "1":
                    mem = np.where(force == fi)[0]
                    ps = [self._pos(int(uids[j]), f) for j in mem]
                    ps = [p for p in ps if p is not None]
                    if ps:
                        t = self._needed_at(f, float(np.mean([p[0] for p in ps])), float(np.mean([p[1] for p in ps])),
                                            self.ally_of.get(ps[0][2], -9))
                        if t is not None:
                            out["f_kind"][fi] = 2
                            out["f_cell"][fi], out["f_off"][fi] = self._cell_off(t[0], t[1])
        for fi, t in jobs.items():
            if t["block"] is not None and (t["hit"] is None or t["b"] >= t["h"]):
                (x, z), job = t["block"], "block"
            elif t["hit"] is not None:
                (x, z), job = t["hit"], "hit"
            else:
                continue
            out["f_kind"][fi] = 2
            out["f_cell"][fi], out["f_off"][fi] = self._cell_off(x, z)
            self.job_log.append((f, job, t["b"], t["h"], t["g"], t["r"], float(np.hypot(x - t["base"][0], z - t["base"][1]))))

    def _job_target(self, f, members):
        """The place for a parked force (BARAI_WAKE_PLACE=jobs, own games; his 11-21: the army's two jobs are to block
        their army from our base and to hurt their base, economy first). Both are priced in metal and the bigger
        wins:
        - block: the enemy ground army this side sees or remembered in the last 20 s, moving toward our buildings'
          centre, worth min(its metal, ours). The place is the first point on its line to our base that we reach no
          later than it does, else the base itself.
        - hit: the enemy's economy as it truly stands, outside their static ground guns' reach, by 1,000-elmo square,
          worth its metal; the square with the most metal per second of our travel.
        A label (the economy's truth is used, never an input). Returns {block, hit: (x, z) or None, b: block metal,
        h: hit metal, g: the force's metal, r: the raid's metal} or None."""
        if not hasattr(self, "job_log"):
            self.job_log = []
        ally0 = None
        idx = self.rows_at(f)
        u = self.units
        uid = self.uid[idx]
        mine = np.isin(uid, members)
        if not mine.any():
            return None
        al, cls, d = self.ually[idx], self.ucls[idx], self.udef[idx]
        ally0 = int(al[mine][0])
        k = self.allies.index(ally0)
        ux, uz = u[idx, 4], u[idx, 5]
        gx, gz = float(ux[mine].mean()), float(uz[mine].mean())
        g_metal = float(self.d_metal[d[mine]].sum())
        g_speed = max(float(self.d_speed[d[mine]].min()), 1.0)
        built = u[idx, 9] >= 1.0
        ob = (al == ally0) & (cls == 0) & built
        if not ob.any():
            return None
        w = self.d_metal[d[ob]] + 1.0
        bx, bz = float((ux[ob] * w).sum() / w.sum()), float((uz[ob] * w).sum() / w.sum())

        block = None
        mx, mz, md, mage, mstatic, mvx, mvz = self._memory(k, f, ally0)
        inc = ~mstatic & (self.d_cls[md] == 3) & (mage <= 20) & ((mvx * (bx - mx) + mvz * (bz - mz)) > 0)
        b_metal = 0.0
        if inc.any():
            wm = self.d_metal[md[inc]]
            b_metal = min(float(wm.sum()), g_metal)
            cx, cz = float((mx[inc] * wm).sum() / wm.sum()), float((mz[inc] * wm).sum() / wm.sum())
            v = max(float((np.hypot(mvx[inc], mvz[inc]) * wm).sum() / wm.sum()), 1.0)
            span = float(np.hypot(bx - cx, bz - cz))
            block = (bx, bz)
            for s in np.linspace(0.1, 1.0, 10):
                px, pz = cx + s * (bx - cx), cz + s * (bz - cz)
                if np.hypot(px - gx, pz - gz) / g_speed <= s * span / v:
                    block = (px, pz)
                    break

        foe = (al != ally0) & (al >= 0) & built & (cls == 0)
        eco = foe & self.d_eco[d]
        h_metal, hit = 0.0, None
        if eco.any():
            ex, ez, em = ux[eco], uz[eco], self.d_metal[d[eco]]
            gun = foe & (self.d_g[d] > 0)
            if gun.any():
                dd = np.hypot(ex[:, None] - ux[gun][None, :], ez[:, None] - uz[gun][None, :])
                free = ~(dd <= self.d_range[d[gun]][None, :]).any(1)
                ex, ez, em = ex[free], ez[free], em[free]
            sq = {}
            for x_, z_, m_ in zip(ex, ez, em):
                s = sq.setdefault((int(x_ // 1000), int(z_ // 1000)), [0.0, 0.0, 0.0])
                s[0] += m_
                s[1] += m_ * x_
                s[2] += m_ * z_
            best = -1.0
            for s in sq.values():
                cx, cz = s[1] / s[0], s[2] / s[0]
                rate = s[0] / (np.hypot(cx - gx, cz - gz) / g_speed + STEP / 30.0)
                if rate > best:
                    best, hit, h_metal = rate, (cx, cz), s[0]
        if block is None and hit is None:
            return None
        r_metal = float(self.d_metal[md[inc]].sum()) if inc.any() else 0.0
        return {"block": block, "hit": hit, "b": b_metal, "h": h_metal, "g": g_metal, "r": r_metal, "base": (bx, bz)}

    def _needed_at(self, f, x, z, ally, horizon_s=60, reach=4000.0, least=200.0):
        """A place teacher for a parked force (BARAI_WAKE_PLACE=1, own games): where our side was in the fight over the
        next horizon -- the metal value of hits our units or buildings took plus hits they dealt, at the victim's spot,
        within reach of the force -- the heaviest 1,000-elmo square's weighted centre, or None under `least` metal.
        A label from the game's future (never an input), the way f_goal is."""
        h = self.hits
        if not len(h):
            return None
        a, b = np.searchsorted(h[:, 0], [f, f + horizon_s * 30])
        acc = {}
        for fr, att, vic, dmg in h[a:b]:
            pv = self._pos(int(vic), int(fr))
            if pv is None:
                continue
            va = self.ally_of.get(pv[2], -9)
            pa = self._pos(int(att), int(fr)) if att >= 0 else None
            aa = self.ally_of.get(pa[2], -9) if pa is not None else -9
            if va != ally and aa != ally:
                continue
            if np.hypot(pv[0] - x, pv[1] - z) > reach:
                continue
            k = (int(pv[0] // 1000), int(pv[1] // 1000))
            s = acc.setdefault(k, [0.0, 0.0, 0.0])
            s[0] += dmg
            s[1] += dmg * pv[0]
            s[2] += dmg * pv[1]
        if not acc:
            return None
        s = max(acc.values(), key=lambda v: v[0])
        if s[0] < least:
            return None
        return s[1] / s[0], s[2] / s[0]

    def _force_labels(self, task, ux, uz, uids, pos, decided, grid, f):
        """Per force (tasks.forces_at; his 11-20: the order is the click, not the unit -- 90% of players' unit orders
        are clicks of 3+ units): clicked this step; the click's kind, place, rating weight; point or line, and the
        line's length (log1p / 7) and angle to the enemy direction there (cos 2a, sin 2a: a line has no head); and
        where the force's units were 60 s later (a hindsight goal, our own side's future only)."""
        force = forces_at(task, ux, uz)
        nf = int(force.max()) + 1 if len(force) else 0
        own_g = "own-games" in str(getattr(self, "path", "")).replace("\\", "/")
        own_k = float(os.environ.get("BARAI_OWN_RATE_K", "0")) if own_g else 0.0
        own_flat = own_g and os.environ.get("BARAI_OWN_WINNER") == "1"   # the winner's clicks, unweighted
        out = {"force": force, "f_click": np.zeros(nf, np.float32), "f_kind": np.full(nf, -1, np.int64),
               "f_cell": np.full(nf, -1, np.int64), "f_off": np.zeros((nf, 2), np.float32),
               "f_spread": np.zeros(nf, np.float32), "f_shape": np.zeros((nf, 3), np.float32),
               "f_w": np.zeros(nf, np.float32), "f_neg": np.zeros(nf, np.float32), "f_raw": np.zeros(nf, np.float32), "f_contact": np.zeros(nf, np.float32), "f_goal": np.full(nf, -1, np.int64), "f_mask": np.ones(nf, bool),
               "f_alive": np.full(nf, -1.0, np.float32),
               # per unit: in a clicked force, 1 if the click ordered it, 0 if the click left it; -1 no label
               "f_member": np.full(len(force), -1.0, np.float32)}
        clicks = {}
        for i in decided:
            j = pos.get(int(self.decisions[i, 3]))
            if j is not None:
                clicks.setdefault(int(self.decisions[i, 7]), []).append((i, j))
        ax = None
        best_n = np.zeros(nf, np.int64)
        for cl in clicks.values():
            held = np.bincount(force[[j for _, j in cl]], minlength=nf)
            fi = int(held.argmax())
            # forces holding part of a click they did not win were clicked too: no label either way (11-20 review)
            for other in np.where(held > 0)[0]:
                if other != fi:
                    out["f_mask"][other] = False
            if len(cl) <= best_n[fi]:
                continue
            best_n[fi] = len(cl)
            took = {j for _, j in cl}
            for j in np.where(force == fi)[0]:
                out["f_member"][j] = 1.0 if int(j) in took else 0.0
            ii = np.array([i for i, _ in cl])
            T = self.decisions[ii][:, 5:7].astype(np.float64)
            c = T.mean(0)
            out["f_click"][fi] = 1
            out["f_kind"][fi] = int(np.bincount(self.decisions[ii, 4].astype(np.int64)).argmax())
            out["f_cell"][fi], out["f_off"][fi] = self._cell_off(c[0], c[1])
            if own_flat:
                out["f_w"][fi] = 1.0
                out["f_neg"][fi] = 0.0
            elif own_k > 0.0:
                # own games, BARAI_OWN_RATE_K (11-26, two self-play rounds tied): the raw rating weighs the copy both
                # ways, and an order clearly worse than the side's others (raw under -0.5) is also pushed down
                out["f_w"][fi] = float(np.mean(np.exp(own_k * np.clip(self.dec_raw[ii], -2, 2))))
                out["f_neg"][fi] = float(np.mean(self.dec_raw[ii] < -0.5))
            else:
                out["f_w"][fi] = float(np.mean(np.exp(0.5 * np.clip(self.dec_score[ii], -2, 2))))
                out["f_neg"][fi] = float(np.mean(self.dec_neg[ii]))
            out["f_raw"][fi] = float(np.mean(self.dec_raw[ii]))
            dv = T - c
            if len(ii) >= 2 and float(np.sqrt((dv ** 2).sum(1).max())) >= 24:
                _, v = np.linalg.eigh(dv.T @ dv)
                a = v[:, -1]
                proj = dv @ a
                if ax is None:
                    ax = base_axis(grid, self.mapx / G, self.mapz / G, self.mapx, self.mapz)
                h = 64.0
                ex_ = float(ax(c[0] + h, c[1])) - float(ax(c[0] - h, c[1]))
                ez_ = float(ax(c[0], c[1] + h)) - float(ax(c[0], c[1] - h))
                ang = math.atan2(a[1], a[0]) - math.atan2(ez_, ex_)
                out["f_spread"][fi] = 1
                out["f_shape"][fi] = (math.log1p(float(proj.max() - proj.min())) / 7, math.cos(2 * ang),
                                      math.sin(2 * ang))
        contact = getattr(self, "_contact", None)
        if contact is not None and len(contact) == len(force):
            for fi in range(nf):
                if contact[force == fi].any():
                    out["f_contact"][fi] = 1.0
                    if out["f_click"][fi] > 0:
                        out["f_w"][fi] *= CONTACT_W
        self._wake_idle(out, force, uids, f)
        for fi in range(0 if getattr(self, "is_live", False) else nf):
            # the dead count where they fell (11-20 review: survivors only taught "attacks end where the cowards
            # stood"); and the share of the force's metal still alive then
            xs, zs, alive, total = [], [], 0.0, 0.0
            for j in np.where(force == fi)[0]:
                q = self._last_pos(int(uids[j]), f + 1800)
                if q is None:
                    continue
                xs.append(q[0])
                zs.append(q[1])
                m = float(self.d_metal[q[3]])
                total += m
                alive += m if q[5] >= f + 1800 - 300 else 0.0
            if xs:
                out["f_goal"][fi] = self._cell_off(float(np.mean(xs)), float(np.mean(zs)))[0]
                out["f_alive"][fi] = alive / max(total, 1e-6)
        return out

    def _setup(self, units, defs, mapxz, allies, teams, spots, heights, names=None):
        self.units = units
        self.defs = {int(r[0]): r[1:] for r in defs}
        # names: one per defs row, in the same order (replay_dataset.py def_names; serve.py from the D lines)
        self.d_names = {int(r[0]): str(names[i]) for i, r in enumerate(defs)} if names is not None and len(names) == len(defs) else {}
        self.mapx, self.mapz = [float(v) for v in mapxz]
        self.allies = [int(a) for a in allies]
        self.ally_of = {int(t[0]): int(t[1]) for t in teams}
        self.is_ai = {int(t[0]): bool(t[2]) for t in teams}
        self.skill = {int(t[0]): float(t[3]) for t in teams}
        self.spots = spots
        self.height = self._grid_heights(heights)
        nd = max(self.defs) + 1
        self.d_cls = np.zeros(nd, np.int64)
        self.d_metal, self.d_hp, self.d_speed, self.d_range, self.d_g, self.d_a, self.d_sight, self.d_radar = (
            np.zeros(nd, np.float32) for _ in range(8))
        self.d_eco = np.zeros(nd, bool)
        self.d_move = np.zeros((nd, 5), np.float32)
        self.d_income = np.zeros(nd, np.float32)
        for d, v in self.defs.items():
            self.d_cls[d] = int(v[0])
            self.d_metal[d], self.d_hp[d], self.d_speed[d], self.d_range[d] = v[1], v[2], v[3], v[4]
            self.d_g[d], self.d_a[d], self.d_sight[d], self.d_radar[d] = v[5], v[6], v[7], v[8]
            self.d_eco[d] = v[10] > 0 if len(v) > 10 else False
            if len(v) >= 16:
                self.d_move[d] = v[11:16]
            if len(v) >= 17:
                self.d_income[d] = v[16]
        st = unit_stats()
        self.d_stat = np.zeros((nd, STAT_F), np.float32)
        if st and self.d_names:
            for d, n in self.d_names.items():
                if 0 <= d < nd:
                    self.d_stat[d] = st.vector(n)
        u = self._fill_steps(self.units)
        order = np.argsort(u[:, 0], kind="stable")
        self.units = u = u[order]
        self.frames = u[:, 0].astype(np.int64)
        self.uid = u[:, 1].astype(np.int64)
        self.udef = np.clip(u[:, 2].astype(np.int64), 0, nd - 1)
        self.uteam = u[:, 3].astype(np.int64)
        lut = np.full(max(max(self.ally_of, default=0), int(self.uteam.max()) if len(self.uteam) else 0) + 1, -9,
                      np.int64)
        for t_, a_ in self.ally_of.items():
            if t_ >= 0:
                lut[t_] = a_
        self.ually = np.where(self.uteam >= 0, lut[np.clip(self.uteam, 0, len(lut) - 1)], -9)
        self.ucls = self.d_cls[self.udef]

    def _fill_steps(self, u):
        """Recordings made before 11-19 sample mobile units once a second; decisions come every STEP frames. Fill the
        steps between with each mobile unit moved along its recorded velocity (the past only: no look at the next
        sample, which the order being predicted shaped). Recordings at STEP and live play pass through unchanged."""
        if not len(u):
            return u
        cls = self.d_cls[np.clip(u[:, 2].astype(np.int64), 0, len(self.d_cls) - 1)]
        mob = cls != 0
        if not mob.any() or np.any(u[mob, 0] % 30 != 0):
            return u
        extra = []
        for k in range(STEP, 30, STEP):
            r = u[mob].copy()
            r[:, 0] += k
            r[:, 4] += r[:, 6] * k / 30.0
            r[:, 5] += r[:, 7] * k / 30.0
            extra.append(r)
        return np.concatenate([u] + extra)

    def _grid_heights(self, h):
        """Mean height per cell (scaled per map), the share under water, and the steepest step inside the cell
        (from the 64-elmo samples), so a cliff or ramp narrower than a cell still shows."""
        if h.size == 0:
            return np.zeros((3, G, G), np.float32)
        h = h.astype(np.float32)
        gy = np.abs(np.diff(h, axis=0, append=h[-1:]))
        gx = np.abs(np.diff(h, axis=1, append=h[:, -1:]))
        steep = np.maximum(gx, gy) / 64.0
        ry = np.minimum((np.arange(h.shape[0]) * G) // h.shape[0], G - 1)
        rx = np.minimum((np.arange(h.shape[1]) * G) // h.shape[1], G - 1)
        cell = (ry[:, None] * G + rx[None, :]).ravel()
        cnt = np.maximum(np.bincount(cell, minlength=G * G), 1)
        mean = np.bincount(cell, h.ravel(), G * G) / cnt
        water = np.bincount(cell, (h < 0).ravel().astype(np.float32), G * G) / cnt
        mx = np.zeros(G * G, np.float32)
        np.maximum.at(mx, cell, steep.ravel())
        mean = mean.reshape(G, G)
        return np.stack([(mean - mean.mean()) / (mean.std() + 1.0), water.reshape(G, G),
                         np.minimum(mx.reshape(G, G), 3.0)]).astype(np.float32)

    def _index_decisions(self):
        d = self.decisions
        self.dec_by = {}
        self.dec_neg = np.zeros(len(d), bool)
        self.dec_raw = np.zeros(len(d))
        if not len(d):
            return
        # His 11-18: a player's order is reasonable unless it was clearly bad. Each picked (horizon, measure) is taken
        # against the same side's orders in the same window and scaled by its spread in the game; better than them
        # adds, a little worse is neutral, the mean counts against an order only past one spread worse. No win bonus
        # (11-19: it taught "copy the side that was ahead").
        cols = []
        key = d[:, 2].astype(np.int64) * 100000 + (d[:, 1] // (WINDOW_S * 30)).astype(np.int64)
        base = self._stay_baseline() if self.stays is not None and self.dec_odds is not None else None
        for h, m in HORIZON_PICK:
            if m >= self.outcome.shape[2]:  # built before the map-control measures
                continue
            if m == 8 and base is not None:
                # the units' own trade per unit against what units that stayed got (same side, window, odds band): a
                # retreat out of a losing fight earns the loss it avoided (his 11-19: "EXITING a fight")
                v = self.outcome[:, h, 0].astype(np.float64) / self.group_n - base[h]
                ok = ~np.isnan(v)
            else:
                # near the target: over the order's own span (until half its units have a newer order), so later
                # orders' work is theirs; chained back below
                src = self.outcome_span if (self.outcome_span is not None and m in (1, 4, 5) and "span" in self.rating_parts) else self.outcome
                v = src[:, h, m].astype(np.float64)
                ok = ~np.isnan(v)
                # against the same side's other orders in the same WINDOW_S: what this order did better or worse than
                # theirs, not whether the side was ahead then (11-19 review)
                ii = np.flatnonzero(ok)
                ii = ii[np.argsort(key[ii], kind="stable")]
                for grp in (np.split(ii, np.flatnonzero(np.diff(key[ii])) + 1) if len(ii) else ()):
                    v[grp] -= v[grp].mean()
            z = np.zeros_like(v)
            if ok.sum() > 2:
                z[ok] = v[ok] / (np.sqrt(np.mean(v[ok] ** 2)) + 1e-6)
            cols.append(np.clip(z, -3, 3))
        self.dec_cols = np.array(cols)  # per picked measure, for the rating checks
        score = np.mean(cols, axis=0)
        if self.idle_m is not None and "idle" in self.rating_parts:
            # his 11-20 "penalize such a position hard": a point per minute the group stood idle after the order
            # (replay_dataset idle_cost: standing, trading nothing, nothing of ours within 1,000, no enemy seen), at
            # most 3; before the chain, so the order that set it up shares it
            score = score - np.minimum(self.idle_m / self._group_metal(), 3.0)
        if self.outcome_span is not None and "chain" in self.rating_parts:
            score = self._chain(score)
        self.dec_neg = score < -1
        self.dec_raw = score
        self.dec_score = np.where(score < -1, score + 1, np.maximum(score, 0.0))
        k1, k2 = d[:, 2].astype(np.int64), d[:, 1].astype(np.int64) // STEP
        o = np.lexsort((np.arange(len(d)), k2, k1))
        cuts = (np.flatnonzero((np.diff(k1[o]) != 0) | (np.diff(k2[o]) != 0)) + 1).tolist()
        ol = o.tolist()
        for a, b in zip([0] + cuts, cuts + [len(o)]):
            self.dec_by[(int(k1[o[a]]), int(k2[o[a]]))] = ol[a:b]

    def _group_metal(self):
        """Per decision: the metal of its order group's units (their defs at the order), at least 1."""
        d = self.decisions
        m = np.zeros(len(d))
        r = self._last_rows(d[:, 3].astype(np.int64), d[:, 0].astype(np.int64))
        ok = r >= 0
        m[ok] = self.d_metal[self.udef[r[ok]]]
        gid = d[:, 7].astype(np.int64)
        _, inv = np.unique(gid, return_inverse=True)
        tot = np.bincount(inv, weights=m)
        return np.maximum(tot[inv], 1.0)

    def _chain(self, score, tau_s=60.0):
        """Each order also earns what the orders after it in the same task earned (his 11-20, "webbing actions
        together"): its own score plus w x the discounted mean of the later orders' scores, w = exp(-gap to the next
        order / tau), each later order weighted by exp(-its delay / tau). A mean, not a sum: players re-order a task
        several times a second in fights. Per order group; every decision of a group gets its group's score."""
        d = self.decisions
        gid, tid = d[:, 7].astype(np.int64), d[:, 10].astype(np.int64)
        first = {}
        for i in range(len(d)):
            first.setdefault(int(gid[i]), i)
        by_task = {}
        for g_, i in first.items():
            if tid[i] >= 0:
                by_task.setdefault(int(tid[i]), []).append((d[i, 0], g_))
        own = {g_: float(score[i]) for g_, i in first.items()}
        chained = dict(own)
        for seq in by_task.values():
            seq.sort()
            num = den = 0.0  # discounted sums over the orders after position k, as seen from order k+1
            w_next = 0.0     # the decay from order k+1 to order k+2
            for k in range(len(seq) - 2, -1, -1):
                f, g_ = seq[k]
                f2, g2 = seq[k + 1]
                num, den = own[g2] + w_next * num, 1.0 + w_next * den
                w = float(np.exp(-(f2 - f) / 30.0 / tau_s))
                chained[g_] = own[g_] + w * num / den
                w_next = w
        return np.array([chained[int(g_)] for g_ in gid])

    def _stay_baseline(self):
        """Per decision and horizon 0-2: the mean own trade of units that stayed (no new order for 5 s) in the same
        odds band (ahead < 0.67 < even < 1.5 < behind, enemy over ours within 800), side and WINDOW_S window, else
        the same band and side over the game; 0 for decisions outside a fight (staying there trades nothing)."""
        d, st = self.decisions, self.stays
        _, inv, cnt = np.unique(d[:, 7], return_inverse=True, return_counts=True)
        self.group_n = np.maximum(cnt[inv], 1).astype(np.float64)
        band = lambda o: np.where(o < 0, -1, np.where(o < 0.67, 0, np.where(o < 1.5, 1, 2)))
        db, sb = band(self.dec_odds), band(st[:, 3]) if len(st) else np.zeros(0, np.int64)
        # and under fire or not (metal taken in the last 5 s): players pull back the units being hit
        if self.dec_hit is not None and st.shape[1] >= 8:
            db = np.where(db >= 0, db * 2 + (self.dec_hit > 0), db)
            sb = sb * 2 + (st[:, 7] > 0) if len(st) else sb
        dw = (d[:, 1] // (WINDOW_S * 30)).astype(np.int64)
        sw = (st[:, 0] // (WINDOW_S * 30)).astype(np.int64) if len(st) else np.zeros(0, np.int64)
        out = np.zeros((3, len(d)), np.float64)
        for h in range(3):
            v = st[:, 4 + h].astype(np.float64) if len(st) else np.zeros(0)
            okv = ~np.isnan(v)
            ts, ws, bs, xs = st[okv, 1].astype(np.int64), sw[okv], sb[okv], v[okv]
            dt_ = d[:, 2].astype(np.int64)
            fq, cq = _stay_key(dt_, dw, db), _stay_key(dt_, 0, db)
            fk, fm = _group_means(_stay_key(ts, ws, bs), xs)
            ck, cm = _group_means(_stay_key(ts, 0, bs), xs)
            got = np.zeros(len(d))
            j = np.minimum(np.searchsorted(ck, cq), max(len(ck) - 1, 0))
            hit = (ck[j] == cq) if len(ck) else np.zeros(len(d), bool)
            got[hit] = cm[j[hit]]
            j = np.minimum(np.searchsorted(fk, fq), max(len(fk) - 1, 0))
            hit = (fk[j] == fq) if len(fk) else np.zeros(len(d), bool)
            got[hit] = fm[j[hit]]
            sel = db >= 0
            out[h, sel] = got[sel]
        return out

    def _pick_examples(self, neg_share, rng):
        out = []
        # our own games (a path under an "own-games" folder): every side learns, ours and the opponent alike, the
        # ratings (idle cost, f_unlike) pushing down what went wrong (his 11-20: our parked group, which players never do)
        own = "own-games" in str(self.path).replace("\\", "/")
        human = [t for t, ai in self.is_ai.items() if (own or not ai) and self.ally_of.get(t, -9) in self.allies]
        if own and os.environ.get("BARAI_OWN_TEAM"):
            # 11-24 A/B: learn only our model's side of an own game (its own failures), not the stock opponent's
            human = [t for t in human if t == int(os.environ["BARAI_OWN_TEAM"])]
        if own and os.environ.get("BARAI_OWN_WINNER") == "1":
            # 11-26: the per-decision rating ran against winning (higher-rated side won 12 of 64 own games); learn
            # only the side that won the game
            won = []
            for t in human:
                m = self.decisions[:, 2] == t if len(self.decisions) else np.zeros(0, bool)
                if m.any() and int(self.result[m][0]) == 1:
                    won.append(t)
            human = won
        last = int(self.frames.max()) if len(self.frames) else 0
        if self.desync >= 0:
            last = min(last, self.desync)
        for t in human:
            secs_with = {s for (tt, s) in self.dec_by if tt == t}
            for s in range(1, last // STEP):
                if s in secs_with or rng.random() < neg_share:
                    out.append((t, s * STEP))
        return out

    # ---- one example ----
    def rows_near(self, f, tol=60):
        """rows_at the latest sampled frame at or before f, within tol frames: in play serve can skip seconds, so the
        exact frame may be missing (training has every second, where this is rows_at(f))"""
        k = int(np.searchsorted(self.frames, f, "right")) - 1
        if k < 0 or f - self.frames[k] > tol:
            return np.zeros(0, np.int64)
        return self.rows_at(int(self.frames[k]))

    def rows_at(self, f):
        a, b = np.searchsorted(self.frames, [f, f + 1])
        idx = np.arange(a, b)
        sf = f - f % 300
        if sf != f and self.path is not None:
            a2, b2 = np.searchsorted(self.frames, [sf, sf + 1])
            st = np.arange(a2, b2)
            st = st[self.ucls[st] == 0]
            idx = np.concatenate([idx, st])
        return idx

    def cell(self, x, z):
        cx = np.clip((x / max(self.mapx, 1) * G).astype(np.int64), 0, G - 1)
        cz = np.clip((z / max(self.mapz, 1) * G).astype(np.int64), 0, G - 1)
        return cx, cz

    def _reach(self, grid, ch, x, z, metal, speed):
        """log1p of sum(metal * exp(-t / REACH_S)) per cell, t the straight-line travel time at the unit's speed.
        Units sharing a cell and a speed are merged first (an 8v8 army is a few hundred cells, not thousands)."""
        if not len(x):
            return
        cx, cz = self.cell(x, z)
        sp = np.maximum(np.round(speed / 10.0) * 10.0, 10.0)
        key = (cz * G + cx) * 10000 + sp.astype(np.int64)
        uk, inv = np.unique(key, return_inverse=True)
        m = np.bincount(inv, weights=metal, minlength=len(uk))
        grid[ch] = np.log1p((m[:, None] * self._reach_rows(uk)).sum(0).reshape(G, G)).astype(np.float32)

    def _reach_rows(self, uk):
        """exp(-t / REACH_S) over the grid for each (cell, speed) key; a game's examples ask the same rows again (half
        to four in five of them), so each row is kept with the game, up to REACH_ROWS of them."""
        cache = self.__dict__.setdefault("_reach_cache", {})
        keys = uk.tolist()
        miss = [k for k in keys if k not in cache]
        if len(cache) + len(miss) > REACH_ROWS:
            cache.clear()
            miss = keys
        if miss:
            mk = np.array(miss, np.int64)
            cell, spd = mk // 10000, (mk % 10000).astype(np.float64)
            sx, sz = self.mapx / G, self.mapz / G
            gx, gz = (cell % G + .5) * sx, (cell // G + .5) * sz
            zz, xx = np.mgrid[0:G, 0:G]
            px, pz = ((xx + .5) * sx).ravel(), ((zz + .5) * sz).ravel()
            t = np.hypot(px[None, :] - gx[:, None], pz[None, :] - gz[:, None]) / spd[:, None]
            for k, row in zip(miss, np.exp(-t / REACH_S)):
                cache[k] = row
        return np.stack([cache[k] for k in keys])

    def _splat(self, grid, ch, x, z, val):
        cx, cz = self.cell(x, z)
        np.add.at(grid[ch], (cz, cx), val)

    def _splat_disk(self, grid, ch, x, z, val, radius_elmo):
        if not len(x):
            return
        cx, cz = self.cell(x, z)
        cellsize = max(self.mapx, self.mapz) / G
        rc = np.clip(np.round(radius_elmo / cellsize).astype(np.int64), 0, len(DISKS) - 1)
        for r in np.unique(rc):
            m = rc == r
            dy, dx = DISKS[r]
            yy = (cz[m][:, None] + dy[None, :]).ravel()
            xx = (cx[m][:, None] + dx[None, :]).ravel()
            vv = np.repeat(val[m], len(dy))
            ok = (yy >= 0) & (yy < G) & (xx >= 0) & (xx < G)
            np.add.at(grid[ch], (yy[ok], xx[ok]), vv[ok])

    def _index_sides(self, sides):
        """replay_dataset.side_series per ally, and each ally's result (1 won, 0 lost, -1 unknown)."""
        self.sides = {}
        if sides is not None and len(sides):
            for a in np.unique(sides[:, 1]).astype(np.int64):
                r = sides[sides[:, 1] == a]
                self.sides[int(a)] = r[np.argsort(r[:, 0])]
        self.side_result = {}
        for t_, a_ in self.ally_of.items():
            m = self.decisions[:, 2] == t_ if len(self.decisions) else np.zeros(0, bool)
            if m.any():
                self.side_result[a_] = int(self.result[m][0])

    def value_labels(self, team, f):
        """How this side does from frame f (labels from the whole game, never inputs): per horizon in VALUE_H, the
        trade (their metal lost minus ours) over the standing metal of both sides at f, and the change in our share of
        owned map cells; then the result. NaN where unknown (past the recording's end or its desync)."""
        out = np.full(2 * len(VALUE_H) + 1, np.nan, np.float32)
        ally = self.ally_of.get(team)
        if ally not in getattr(self, "sides", {}) or len(self.sides) < 2:  # live games have no labels
            return out
        others = [a for a in self.sides if a != ally]
        last = min(float(s[-1, 0]) for s in self.sides.values())
        if self.desync >= 0:
            last = min(last, self.desync)

        def at(a, fr):
            s = self.sides[a]
            i = int(np.searchsorted(s[:, 0], fr, "right")) - 1
            return s[max(i, 0)]
        s0 = at(ally, f)
        o0 = [at(a, f) for a in others]
        scale = 0.5 * (s0[3] + sum(o[3] for o in o0)) + 1000.0
        for j, h in enumerate(VALUE_H):
            f1 = f + h * 30
            if f1 > last:
                continue
            s1 = at(ally, f1)
            o1 = [at(a, f1) for a in others]
            trade = sum(b[2] - a[2] for a, b in zip(o0, o1)) - (s1[2] - s0[2])
            out[j] = np.clip(trade / scale, -3, 3)
            out[len(VALUE_H) + j] = s1[5] - s0[5]
        r = self.side_result.get(ally, -1)
        if r >= 0:
            out[-1] = r
        return out

    def example(self, team, f):
        ally = self.ally_of[team]
        k = self.allies.index(ally)
        u = self.units
        idx = self.rows_at(f)
        sight = u[idx, 10].astype(np.int64)
        bits = (sight >> (2 * k)) & 3
        mine = self.uteam[idx] == team
        friend = self.ually[idx] == ally
        foe = (self.ually[idx] != ally) & (self.ually[idx] >= 0)
        vis = foe & ((bits & 1) > 0)
        radar = foe & ((bits & 3) == 2)
        cls = self.ucls[idx]
        d = self.udef[idx]
        metal = self.d_metal[d]
        x, z = u[idx, 4], u[idx, 5]
        built = u[idx, 9] >= 1.0
        mobile_army = np.isin(cls, (3, 4))

        grid = np.zeros((CHANNELS, G, G), np.float32)
        grid[0] = self.height[0]
        if len(self.spots):
            self._splat(grid, 1, self.spots[:, 0], self.spots[:, 1], np.ones(len(self.spots), np.float32))
        sel = mine & mobile_army & built
        self._splat(grid, 2, x[sel], z[sel], metal[sel])
        sel = mine & (cls == 0)
        self._splat(grid, 3, x[sel], z[sel], metal[sel])
        sel = mine & np.isin(cls, (1, 2))
        self._splat(grid, 4, x[sel], z[sel], metal[sel])
        sel = friend & ~mine & (cls != 0)
        self._splat(grid, 5, x[sel], z[sel], metal[sel])
        sel = friend & ~mine & (cls == 0)
        self._splat(grid, 6, x[sel], z[sel], metal[sel])
        sel = vis & (cls != 0)
        self._splat(grid, 7, x[sel], z[sel], metal[sel])
        self._splat(grid, 9, x[radar], z[radar], np.ones(radar.sum(), np.float32))

        # memory: the enemy as this side last saw it (within MEMORY_S; buildings for the whole game)
        mx, mz, md, mage, mstatic, mvx, mvz = self._memory(k, f, ally)
        fade = np.exp(-mage / 60.0).astype(np.float32)
        mmetal = self.d_metal[md]
        s = mstatic
        self._splat(grid, 8, mx[s], mz[s], mmetal[s])
        nm = ~s & (mage > 0)
        self._splat(grid, 10, mx[nm], mz[nm], mmetal[nm] * fade[nm])
        w = np.where(s, 1.0, fade).astype(np.float32)
        self._splat_disk(grid, 11, mx, mz, self.d_g[md] * w, self.d_range[md])
        self._splat_disk(grid, 12, mx, mz, self.d_a[md] * w, np.maximum(self.d_range[md], 500))
        sel = friend & built & (self.d_g[d] > 0)
        self._splat_disk(grid, 13, x[sel], z[sel], self.d_g[d][sel], self.d_range[d][sel])
        sel = friend & built
        self._splat_disk(grid, 14, x[sel], z[sel], np.ones(sel.sum(), np.float32), self.d_sight[d][sel])
        sel = friend & built & (self.d_radar[d] > 0)
        self._splat_disk(grid, 15, x[sel], z[sel], np.ones(sel.sum(), np.float32), self.d_radar[d][sel])
        for c in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13):
            grid[c] = np.log1p(grid[c])
        grid[14] = np.minimum(grid[14], 1)
        grid[15] = np.minimum(grid[15], 1)
        grid[16] = np.linspace(0, 1, G)[None, :]
        grid[17] = np.linspace(0, 1, G)[:, None]
        grid[18] = self.height[1]
        grid[19] = self.height[2]
        # which way the enemy was going: metal-weighted mean velocity per cell (in sight, on radar or remembered),
        # and where each remembered mover would be now had it kept going (up to 20 s on), fading with age
        mob = ~mstatic
        if mob.any():
            wm = (mmetal * fade)[mob]
            tmp = np.zeros((3, G, G), np.float32)
            self._splat(tmp, 0, mx[mob], mz[mob], wm)
            self._splat(tmp, 1, mx[mob], mz[mob], wm * mvx[mob])
            self._splat(tmp, 2, mx[mob], mz[mob], wm * mvz[mob])
            grid[20] = np.clip(tmp[1] / (tmp[0] + 1.0) / 100.0, -3, 3)
            grid[21] = np.clip(tmp[2] / (tmp[0] + 1.0) / 100.0, -3, 3)
            ahead = np.minimum(mage[mob], 20.0)
            px = np.clip(mx[mob] + mvx[mob] * ahead, 0, self.mapx - 1)
            pz = np.clip(mz[mob] + mvz[mob] * ahead, 0, self.mapz - 1)
            moving = mage[mob] > 0
            self._splat(grid, 22, px[moving], pz[moving], wm[moving])
            grid[22] = np.log1p(grid[22])
        # economy buildings by count (an extractor is cheap; by metal it vanished beside a plant): theirs as this
        # side last saw them, ours
        se = mstatic & self.d_eco[md]
        self._splat(grid, 23, mx[se], mz[se], np.ones(se.sum(), np.float32))
        sel = mine & (cls == 0) & self.d_eco[d]
        self._splat(grid, 24, x[sel], z[sel], np.ones(sel.sum(), np.float32))
        grid[23] = np.log1p(grid[23])
        grid[24] = np.log1p(grid[24])
        self._fire_layers(grid, f, ally)
        # (11-19 reviews: bombers among B's top killers in 4 of 7 games, air indistinguishable from ground) 27: enemy
        # air by metal, in sight now plus remembered while it fades; 28: where our anti-air reaches
        sel = vis & (cls == 4)
        self._splat(grid, 27, x[sel], z[sel], metal[sel])
        air_m = ~mstatic & (mage > 0) & (self.d_cls[md] == 4)
        self._splat(grid, 27, mx[air_m], mz[air_m], (mmetal * fade)[air_m])
        grid[27] = np.log1p(grid[27])
        sel = friend & built & (self.d_a[d] > 0)
        self._splat_disk(grid, 28, x[sel], z[sel], self.d_a[d][sel], np.maximum(self.d_range[d][sel], 500))
        grid[28] = np.log1p(grid[28])
        # risk and advantage (his 11-21: a group coming at our base can destroy so much of it, and the closer it
        # gets the bigger the risk; advantage is the same applied to them): armed mobile metal by how soon it can
        # be at each cell, exp(-travel time / REACH_S). 29: the enemy's as this side knows it (seen now or
        # remembered, fading), 30: our side's
        em = ~mstatic & (self.d_g[md] > 0)
        self._reach(grid, 29, mx[em], mz[em], (mmetal * fade)[em], self.d_speed[md][em])
        sel = friend & built & (cls != 0) & (self.d_g[d] > 0)
        self._reach(grid, 30, x[sel], z[sel], metal[sel], self.d_speed[d][sel])

        # tokens: own focus units, the most valuable first
        ti = np.where(mine & np.isin(cls, FOCUS) & built)[0]
        ti = ti[np.argsort(-metal[ti], kind="stable")][:MAX_TOKENS]
        rows = idx[ti]
        tok = np.zeros((len(ti), TOKEN_F), np.float32)
        for j, c in enumerate(FOCUS):
            tok[:, j] = cls[ti] == c
        dd = d[ti]
        tok[:, 4] = np.log1p(self.d_metal[dd])
        tok[:, 5] = np.log1p(self.d_hp[dd])
        tok[:, 6] = self.d_speed[dd] / 100
        tok[:, 7] = self.d_range[dd] / 1000
        tok[:, 8] = np.log1p(self.d_g[dd])
        tok[:, 9] = np.log1p(self.d_a[dd])
        tok[:, 10] = u[rows, 4] / max(self.mapx, 1)
        tok[:, 11] = u[rows, 5] / max(self.mapz, 1)
        tok[:, 12] = u[rows, 6] / 100
        tok[:, 13] = u[rows, 7] / 100
        tok[:, 14] = u[rows, 8]
        cmd = u[rows, 11].astype(np.int64)
        slot = np.array([CMD_SLOTS.get(int(c), 5) for c in cmd], dtype=np.int64)
        tok[np.arange(len(ti)), 15 + slot] = 1
        has_t = u[rows, 12] >= 0
        tok[:, 21] = has_t
        tok[:, 22] = np.where(has_t, (u[rows, 12] - u[rows, 4]) / 2000, 0)
        tok[:, 23] = np.where(has_t, (u[rows, 13] - u[rows, 5]) / 2000, 0)
        tok[:, 24] = self.d_sight[dd] / 1000
        tok[:, 25] = self.d_radar[dd] / 1000
        tok[:, 26] = (cls[ti] == 3) & (self.d_range[dd] > 700)
        tok[:, 27] = 1
        # 42-46 (his 11-19, navy): where it can go -- land, water surface, under water, steepest slope, wading depth
        tok[:, 42:47] = self.d_move[dd]
        tok[:, TOKEN_BASE:TOKEN_BASE + STAT_F] = self.d_stat[dd]
        etok = self._enemy_tokens(mx, mz, md, mage, mstatic, mvx, mvz)
        task = self._task_features(tok, self.uid[rows], u[rows, 4], u[rows, 5], f)
        self._fight_features(tok, rows, idx, f, friend, vis, mobile_army & built, metal)

        scal = np.array([f / 30 / 60 / 30, math.log1p(metal[mine & mobile_army].sum()) / 10,
                         math.log1p(metal[vis & (cls != 0)].sum()) / 10, self.mapx / 16000, self.mapz / 16000,
                         len(ti) / 100,
                         # income in metal/s (economy.py): ours from our finished economy buildings, theirs from their
                         # economy buildings as last seen (11-19 reviews: players read the resource bar)
                         math.log1p(self.d_income[d][mine & (cls == 0) & built].sum()) / 5,
                         math.log1p(self.d_income[md][mstatic].sum()) / 5,
                         # the player's skill (AlphaStar's MMR input; 11-25: the model stood its army like the bottom
                         # quartile, 17-23% in their half vs Q2-Q4's 27-36%): learned from every player, asked for a
                         # rating in play (serve --skill). Unknown (AIs, unrated) is its own case
                         float(self.skill.get(team, -1.0) >= 0.0), max(self.skill.get(team, -1.0), 0.0) / 50], np.float32)

        # labels
        act = np.zeros(len(ti), np.float32)
        kind = np.full(len(ti), -1, np.int64)
        tcell = np.full(len(ti), -1, np.int64)
        toff = np.zeros((len(ti), 2), np.float32)
        wt = np.zeros(len(ti), np.float32)
        # no rating weight (his 11-21: "even good players play bad sometimes, and bad players good ... learn from the
        # best moments"): over 240 player-games the rating explained 1% of the spread in a game's 60-s trade (corr
        # -0.05), while the old weight clip((OS-15)/20, .25, 2) gave a best moment at OS 30-35 0.99 and at 45+ 2.38.
        # The order's own score (f_w, dec_score) weighs the moment
        w_r = 1.0
        uids = self.uid[rows]
        pos = {int(v): j for j, v in enumerate(uids)}
        decided = self.dec_by.get((team, f // STEP), [])
        for i in decided:
            row = self.decisions[i]
            j = pos.get(int(row[3]))
            if j is None:
                continue
            act[j] = 1
            kind[j] = int(row[4])
            tx, tz = float(row[5]), float(row[6])
            gx, gz = tx / max(self.mapx, 1) * G, tz / max(self.mapz, 1) * G
            cx, cz = int(np.clip(gx, 0, G - 1)), int(np.clip(gz, 0, G - 1))
            tcell[j] = cz * G + cx
            toff[j] = (np.clip(gx - cx, 0, 1), np.clip(gz - cz, 0, 1))
            wt[j] = math.exp(0.5 * float(np.clip(self.dec_score[i], -2, 2)))
        fl = self._force_labels(task, u[rows, 4], u[rows, 5], uids, pos, decided, grid, f)
        # (his 11-21: players assume where the enemy base is and that they hold the spots around it) where the enemy's
        # economy stands now, seen or not: a label from the replay's truth, never an input
        b_eco = np.zeros((1, G, G), np.float32)
        sel = foe & built & (cls == 0) & self.d_eco[d]
        self._splat(b_eco, 0, x[sel], z[sel], np.ones(sel.sum(), np.float32))
        return {"grid": grid, "tok": tok, "etok": etok, "scal": scal, "act": act, "kind": kind, "tcell": tcell, "toff": toff,
                "w_out": wt, "w_rating": w_r, "uid": uids, "revealed": np.zeros(len(ti), bool), **fl,
                "v_t": self.value_labels(team, f), "b_eco": np.minimum(b_eco[0], 1.0),
                # quiet steps are sampled at neg_share: each stands for 1 / neg_share of them in the act loss, so the
                # chance of a new order matches the players' per-step rate (11-19 review: 2.4x too high otherwise)
                "w_act": 1.0 if decided else 1.0 / max(getattr(self, "neg_share", 1.0), 1e-3)}


    def _enemy_tokens(self, mx, mz, md, mage, mstatic, mvx, mvz):
        """One token per enemy unit this side sees now or remembers (_memory's rows, the last _memory call): its stats,
        class, where it is (x, z as map shares), velocity, age (fading over a minute), in sight now, radar only now,
        a building, health while in sight (-1 otherwise), metal. In sight first, then by metal x freshness; at most
        MAX_ETOKENS. Hidden information stays out: what _memory holds is what the side saw (types only once seen)."""
        insight, hp, _ = getattr(self, "_mem_last", (np.zeros(0, bool), np.zeros(0), np.zeros(0, np.int64)))
        n = len(mx)
        if not n or len(insight) != n:
            return np.zeros((0, E_TOKEN_F), np.float32)
        metal = self.d_metal[md]
        now = mage < 0.5   # its latest sample is this step (samples come every STEP frames)
        vis_now = now & insight
        fade = np.where(mstatic, 1.0, np.exp(-mage / 60.0))
        order = np.lexsort((-(metal * fade), ~vis_now))
        order = order[:MAX_ETOKENS]
        e = np.zeros((len(order), E_TOKEN_F), np.float32)
        e[:, :STAT_F] = self.d_stat[md[order]]
        b = STAT_F
        cls = self.d_cls[md[order]]
        for c in range(8):
            e[:, b + c] = cls == c
        e[:, b + 8] = mx[order] / max(self.mapx, 1)
        e[:, b + 9] = mz[order] / max(self.mapz, 1)
        e[:, b + 10] = mvx[order] / 100
        e[:, b + 11] = mvz[order] / 100
        e[:, b + 12] = fade[order]
        e[:, b + 13] = vis_now[order]
        e[:, b + 14] = now[order] & ~insight[order]
        e[:, b + 15] = mstatic[order]
        e[:, b + 16] = np.where(vis_now[order], hp[order], -1.0)
        e[:, b + 17] = np.log1p(metal[order]) / 10
        return e

    def _memory(self, k, f, ally):
        if not hasattr(self, "_vis"):
            self._vis = {}
        if k not in self._vis:
            u = self.units
            bits = (u[:, 10].astype(np.int64) >> (2 * k)) & 3
            foe = (self.ually != ally) & (self.ually >= 0)
            # a radar contact's type is known only once it has been in sight (a blip shows nothing else; no hidden
            # information): radar-only samples count from the unit's first sighting on
            seen = foe & ((bits & 1) > 0)
            uq, at = np.unique(self.uid[seen], return_index=True)  # frames ascend: the first row is the first sighting
            ff = self.frames[seen][at]
            pos_ = np.clip(np.searchsorted(uq, self.uid), 0, max(len(uq) - 1, 0))
            known = (len(uq) > 0) & (uq[pos_] == self.uid) & (self.frames >= ff[pos_]) if len(uq) else                 np.zeros(len(self.uid), bool)
            m = foe & (((bits & 1) > 0) | ((bits > 0) & known))
            # in sight at that sample, and its health then (a player sees a health bar only in sight)
            self._vis[k] = (self.frames[m], self.uid[m], u[m, 4], u[m, 5], self.udef[m], self.ucls[m] == 0,
                            u[m, 6], u[m, 7], (bits[m] & 1) > 0, np.where((bits[m] & 1) > 0, u[m, 8], -1.0))
        fr, ui, x, z, d, st, vx, vz, insight, hp = self._vis[k]
        lo = np.searchsorted(fr, f - MEMORY_S * 30)
        hi = np.searchsorted(fr, f, "right")
        # buildings remembered for the whole game
        sl = np.concatenate([np.where(st[:lo])[0], np.arange(lo, hi)])
        if not len(sl):
            e = np.zeros(0)
            self._mem_last = (np.zeros(0, bool), e, np.zeros(0, np.int64))
            return e, e, np.zeros(0, np.int64), e, np.zeros(0, bool), e, e
        rev = sl[::-1]
        _, first = np.unique(ui[rev], return_index=True)
        keep = rev[first]
        keep = keep[~self._absent_now(k, f, ui[keep], fr[keep], st[keep], x[keep], z[keep])]
        age = (f - fr[keep]) / 30.0
        # for the enemy tokens (_enemy_tokens): in sight at its last sample, health then, its id
        self._mem_last = (insight[keep], hp[keep], ui[keep])
        return x[keep], z[keep], d[keep], age.astype(np.float32), st[keep], vx[keep], vz[keep]

    def _absent_now(self, k, f, uids, last, static, xs, zs):
        """Remembered buildings this side has since seen to be gone: a spot in our sight after the building's last
        sample with nothing there (absence_marks). A player sees a building die, or finds the spot empty."""
        drop = np.zeros(len(uids), bool)
        if not ABSENT_ON:
            return drop
        if not hasattr(self, "_absent"):
            u = self.units
            self._absent = absence_marks(self.frames, self.uid, u[:, 4], u[:, 5], u[:, 10].astype(np.int64),
                                         self.ually, self.ucls == 0, self.d_sight[self.udef], list(self.allies))
            for key, v in getattr(self, "_absent_prior", {}).items():
                self._absent[key] = np.union1d(self._absent.get(key, np.zeros(0, np.int64)), v)
        if not self._absent:
            return drop
        for i in np.nonzero(static)[0]:
            a = self._absent.get((k, int(uids[i]), int(xs[i]), int(zs[i])))
            if a is not None:
                j = int(np.searchsorted(a, f, "right"))
                drop[i] = j > 0 and a[j - 1] > last[i]
        return drop



RECENT_S = 20  # live play keeps every sample this long; older ones only as memory reads them (fold_history)
ABSENT_SIGHT = 0.7  # share of a unit's sight radius trusted as clear ground (terrain hides some of the rest)
# forgetting buildings seen gone (todo/armynet-objectives.md B, 11-27): on with BARAI_ABSENT=1 in training and serve
# alike until it is measured; parity.py proves the two agree either way
ABSENT_ON = os.environ.get("BARAI_ABSENT", "") == "1"


def absence_marks(frames, uid, x, z, bits, row_ally, row_static, row_sight, allies, known=None):
    """{(side index k, building uid, x, z): sorted frames at which one of that side's units had the building's spot
    within ABSENT_SIGHT of its sight radius and the building was not seen there}. Game._memory forgets a remembered
    building once such a frame is newer than its last sighting: what a player sees when a building dies in view or a
    scout finds its spot empty. Keyed by position too: the engine reuses a dead unit's id. `known` ({k: {(uid, x, z)}})
    adds buildings remembered from earlier rows (serve's folded store). Training reads it over the whole game, serve
    and parity over each folded chunk (fold_history) and the rows it keeps; the rule (a mark counts only when newer
    than the last sighting) makes the two agree."""
    out = {}
    for k, ally in enumerate(allies):
        b = (bits >> (2 * k)) & 3
        seen = row_static & (row_ally != ally) & (row_ally >= 0) & (b > 0)
        su = uid[seen].astype(np.int64)
        sx, sz = x[seen].astype(np.int64), z[seen].astype(np.int64)
        sf = frames[seen]
        pos = set((known or {}).get(k, set()))
        pos.update(zip(su.tolist(), sx.tolist(), sz.tolist()))
        # whole seconds only: older recordings sample once a second and training fills the steps between
        # (_fill_steps), which live play never has
        own = (row_ally == ally) & (row_sight > 0) & (frames % 30 == 0)
        if not pos or not own.any():
            continue
        o = np.argsort(x[own], kind="stable")
        of, ox, oz, orr = frames[own][o], x[own][o], z[own][o], (row_sight[own] * ABSENT_SIGHT)[o]
        maxr = float(orr.max())
        so = np.argsort(su, kind="stable")
        su, sx, sz, sf = su[so], sx[so], sz[so], sf[so]
        for B, bx, bz in pos:
            lo, hi = np.searchsorted(ox, [bx - maxr, bx + maxr])
            if hi <= lo:
                continue
            m = (ox[lo:hi] - bx) ** 2 + (oz[lo:hi] - bz) ** 2 <= orr[lo:hi] ** 2
            if not m.any():
                continue
            fs = np.unique(of[lo:hi][m])
            a, c = np.searchsorted(su, [B, B + 1])
            if c > a:
                here = (sx[a:c] == bx) & (sz[a:c] == bz)
                fs = fs[~np.isin(fs, sf[a:c][here])]
            if len(fs):
                out[(k, int(B), int(bx), int(bz))] = fs.astype(np.int64)
    return out


def absence_ctx(defs, teams, allies):
    """What fold_history needs to mark absences: the team -> alliance lookup, and per def whether it is a building and
    its sight (the defs and teams arrays as Game.live takes them)."""
    defs = np.asarray(defs)
    nd = int(defs[:, 0].max()) + 1 if len(defs) else 1
    static, sight = np.zeros(nd, bool), np.zeros(nd, np.float32)
    static[defs[:, 0].astype(np.int64)] = defs[:, 1] == 0
    sight[defs[:, 0].astype(np.int64)] = defs[:, 8]
    teams = np.asarray(teams)
    lut = np.full(int(teams[:, 0].max()) + 1 if len(teams) else 1, -9, np.int64)
    for t in teams:
        if t[0] >= 0:
            lut[int(t[0])] = int(t[1])
    return {"lut": lut, "static": static, "sight": sight, "allies": [int(a) for a in allies]}


def base_axis(grid, sx, sz, mapx, mapz):
    """How far forward a point is: 0 at our buildings' centre, 1 at theirs (the enemy buildings the side has seen; the
    mirror of ours through the map centre when it has seen none)."""
    def centre(ch):
        w = np.expm1(np.clip(ch, 0, 20))
        if w.sum() <= 0:
            return None
        zz, xx = np.mgrid[0:G, 0:G]
        return ((xx + .5) * w).sum() / w.sum() * sx, ((zz + .5) * w).sum() / w.sum() * sz
    own = centre(grid[3]) or (mapx / 2, mapz / 2)
    foe = centre(grid[8]) or (mapx - own[0], mapz - own[1])
    ax, az = foe[0] - own[0], foe[1] - own[1]
    n2 = max(ax * ax + az * az, 1.0)
    return lambda x, z: ((x - own[0]) * ax + (z - own[1]) * az) / n2


def face_dir(grid, x, z, sx, sz, axis, reach=2500.0, point=False):
    """What a line at (x, z) faces: the enemy near it, the first of seen units (7), remembered buildings (8),
    remembered ground guns (11) found within reach, 1/d weighted; else the axis. A unit vector; with `point`, also
    the weighted centre of what it faces (None on the axis fallback), which serve's range arcs stand around.
    (As the line-angle label's reference, face-1, 11-21: level with the axis in gate 3, 6/6 and 5/5, the angle
    not learned; dropped.)"""
    zz, xx = np.mgrid[0:G, 0:G]
    dx, dz = (xx + .5) * sx - x, (zz + .5) * sz - z
    d2 = dx * dx + dz * dz
    near = (d2 < reach * reach) & (d2 > 1)
    for ch in (7, 8, 11):
        m = near & (grid[ch] > 0)
        if m.any():
            w = grid[ch][m] / d2[m]
            vx, vz = float((w * dx[m]).sum()), float((w * dz[m]).sum())
            n = (vx * vx + vz * vz) ** 0.5
            if n > 0:
                if point:
                    return vx / n, vz / n, x + float((w * dx[m]).sum() / w.sum()), z + float((w * dz[m]).sum() / w.sum())
                return vx / n, vz / n
    h = 64.0
    vx, vz = float(axis(x + h, z)) - float(axis(x - h, z)), float(axis(x, z + h)) - float(axis(x, z - h))
    n = (vx * vx + vz * vz) ** 0.5
    v = (vx / n, vz / n) if n > 0 else (1.0, 0.0)
    return v + (None, None) if point else v


def fold_history(store, old, n_allies, ctx=None):
    """Live play keeps every sample for RECENT_S (health 5 s back, losses 10 s back, hits 10 s); past that only what
    Game._memory reads: per side index k, each unit's last row that side saw (sight or radar) -- enemy buildings all
    game, movers while within MEMORY_S (history_rows drops older) -- and each unit's first sighting by that side (a
    radar contact's type counts as known from then on). serve.py and parity.py both use this, so parity proves it.
    With `ctx` (absence_ctx), also the newest frame each side saw a remembered building's spot empty (absence_marks),
    kept as ("absent", k, uid, x, z) and handed to Game.live by absent_of."""
    bits = old[:, 10].astype(np.int64)
    if ctx is not None and len(old):
        d = np.clip(old[:, 2].astype(np.int64), 0, len(ctx["static"]) - 1)
        t = old[:, 3].astype(np.int64)
        row_ally = np.where(t >= 0, ctx["lut"][np.clip(t, 0, len(ctx["lut"]) - 1)], -9)
        known = {}
        for key, r in store.items():
            if len(key) == 2 and ctx["static"][min(int(r[2]), len(ctx["static"]) - 1)]:
                known.setdefault(key[0], set()).add((int(r[1]), int(r[4]), int(r[5])))
        marks = absence_marks(old[:, 0].astype(np.int64), old[:, 1].astype(np.int64), old[:, 4], old[:, 5], bits,
                              row_ally, ctx["static"][d], ctx["sight"][d], ctx["allies"], known)
        for mk, fs in marks.items():
            key = ("absent",) + mk
            store[key] = max(store.get(key, -1), int(fs[-1]))
    for k in range(n_allies):
        b = (bits >> (2 * k)) & 3
        for r in old[b > 0]:
            store[(k, int(r[1]))] = r
        for r in old[(b & 1) > 0]:
            store.setdefault(("seen", k, int(r[1])), r)
    return store


def absent_of(store):
    """fold_history's absence marks as Game.live takes them: {(k, uid, x, z): newest frame}."""
    return {key[1:]: v for key, v in store.items() if key[0] == "absent"}


def history_rows(store, recent, f, static_defs):
    """The folded store and the recent samples, as one units array: last sightings of movers only while within
    MEMORY_S (with one 30-frame sample of slack, whose filled steps can fall inside it), buildings and first sightings
    whatever their age (a radar contact's type stays known)."""
    rows = {k_: v for k_, v in store.items() if k_[0] != "absent"}
    if rows:
        first = np.array([k_[0] == "seen" for k_ in rows], bool)
        kept = np.array(list(rows.values()), np.float32)
        old_mover = (kept[:, 0] < f - MEMORY_S * 30 - 30) & ~np.isin(kept[:, 2].astype(np.int64), static_defs)
        kept = kept[first | ~old_mover]
    else:
        kept = np.zeros((0, recent.shape[1] if recent.ndim == 2 else 14), np.float32)
    return np.concatenate([kept, recent]) if len(recent) else kept


def reveal(ex, rng):
    """Rounds (his 11-19: "we chase their raiders with more than we need to"): a random share of the units the player
    ordered this second are shown as already decided -- columns 36-38: ordered, and where (x, z from the unit, /2000)
    -- and are left out of the loss; the model learns the others' orders given theirs (who already went for the
    raider, who was just sent deep). serve.py decides in rounds the same way. Training only.
    The shown units are a random share of ALL units, column 47 marking each as decided (11-20: drawn from the ordered
    ones only, "nobody shown" meant a quiet step and taught a 0.6% order rate against the players' 5.1%; live, the
    first round shows nobody, so the model barely ordered)."""
    share = rng.random()
    if "force" in ex and len(ex["force"]):
        # whole forces are shown (11-20 review: showing single units masked any force with one shown member, so a
        # 7-unit force kept its label 1 time in 8); serve decides forces in rounds the same way
        nf = int(ex["force"].max()) + 1
        picked = np.array([rng.random() < share for _ in range(nf)])
        shown = np.where(picked[ex["force"]])[0]
    else:
        shown = np.where([rng.random() < share for _ in range(len(ex["act"]))])[0]
    if not len(shown):
        return ex
    tok = ex["tok"].copy()
    tok[shown, 47] = 1
    G_ = G
    for j in shown[ex["act"][shown] > 0]:
        c = ex["tcell"][j]
        tx = (c % G_ + ex["toff"][j, 0]) / G_
        tz = (c // G_ + ex["toff"][j, 1]) / G_
        tok[j, 36] = 1
        tok[j, 37] = (tx - tok[j, 10]) * ex["scal"][3] * 16000 / 2000
        tok[j, 38] = (tz - tok[j, 11]) * ex["scal"][4] * 16000 / 2000
    rev = ex["revealed"].copy()
    rev[shown] = True
    out = dict(ex)
    out.update(tok=tok, revealed=rev)
    if "force" in ex:
        # a shown force has its click in the inputs: not a force label this time
        fm = ex["f_mask"].copy()
        fm[np.unique(ex["force"][shown])] = False
        out["f_mask"] = fm
    return out


def mirror(ex, fx, fz):
    """The example on the map mirrored left-right (fx) and/or top-bottom (fz): training only (11-19 overnight: the
    held-out place error rose 597 -> ~700 while the training loss fell -- ~300 duels memorized). Positions, headings,
    targets and the place labels follow the flip; the position layers are laid anew in the mirrored frame."""
    if not (fx or fz):
        return ex
    g = ex["grid"]
    tok = ex["tok"].copy()
    tcell, toff = ex["tcell"].copy(), ex["toff"].copy()
    has = tcell >= 0
    cx, cz = tcell % G, tcell // G
    if fx:
        g = g[:, :, ::-1]
        tok[:, 10] = 1 - tok[:, 10]
        tok[:, 12] = -tok[:, 12]
        tok[:, 22] = -tok[:, 22]
        tok[:, 31] = -tok[:, 31]
        tok[:, 37] = -tok[:, 37]
        tok[:, 33] = -tok[:, 33]
        cx = G - 1 - cx
        toff[:, 0] = np.where(has, 1 - toff[:, 0], toff[:, 0])
    if fz:
        g = g[:, ::-1, :]
        tok[:, 11] = 1 - tok[:, 11]
        tok[:, 13] = -tok[:, 13]
        tok[:, 23] = -tok[:, 23]
        tok[:, 32] = -tok[:, 32]
        tok[:, 38] = -tok[:, 38]
        tok[:, 34] = -tok[:, 34]
        cz = G - 1 - cz
        toff[:, 1] = np.where(has, 1 - toff[:, 1], toff[:, 1])
    g = np.ascontiguousarray(g)
    if fx:
        g[20] = -g[20]
    if fz:
        g[21] = -g[21]
    g[16] = np.linspace(0, 1, G)[None, :]
    g[17] = np.linspace(0, 1, G)[:, None]
    out = dict(ex)
    out.update(grid=g, tok=tok, tcell=np.where(has, cz * G + cx, -1), toff=toff)
    if "etok" in ex and len(ex["etok"]):
        e = ex["etok"].copy()
        b = STAT_F
        if fx:
            e[:, b + 8] = 1 - e[:, b + 8]
            e[:, b + 10] = -e[:, b + 10]
        if fz:
            e[:, b + 9] = 1 - e[:, b + 9]
            e[:, b + 11] = -e[:, b + 11]
        out["etok"] = e
    if "b_eco" in ex:
        be = ex["b_eco"]
        be = be[:, ::-1] if fx else be
        be = be[::-1, :] if fz else be
        out["b_eco"] = np.ascontiguousarray(be)
    if "force" in ex:
        fc, fo, fg, fs = ex["f_cell"].copy(), ex["f_off"].copy(), ex["f_goal"].copy(), ex["f_shape"].copy()
        hc, hg = fc >= 0, fg >= 0
        if fx:
            fc = np.where(hc, fc // G * G + (G - 1 - fc % G), fc)
            fg = np.where(hg, fg // G * G + (G - 1 - fg % G), fg)
            fo[:, 0] = np.where(hc, 1 - fo[:, 0], fo[:, 0])
            fs[:, 2] = -fs[:, 2]   # a reflection turns the line's angle to the enemy direction the other way
        if fz:
            fc = np.where(hc, (G - 1 - fc // G) * G + fc % G, fc)
            fg = np.where(hg, (G - 1 - fg // G) * G + fg % G, fg)
            fo[:, 1] = np.where(hc, 1 - fo[:, 1], fo[:, 1])
            fs[:, 2] = -fs[:, 2]
        out.update(f_cell=fc, f_off=fo, f_goal=fg, f_shape=fs)
    return out


def collate(batch, numpy=False):
    """numpy=True: arrays, no torch (serve.py on ONNX Runtime)."""
    n =max(1, max(len(b["tok"]) for b in batch))
    B = len(batch)
    tok = np.zeros((B, n, TOKEN_F), np.float32)
    mask = np.zeros((B, n), bool)
    act = np.zeros((B, n), np.float32)
    kind = np.full((B, n), -1, np.int64)
    tcell = np.full((B, n), -1, np.int64)
    toff = np.zeros((B, n, 2), np.float32)
    w_out = np.zeros((B, n), np.float32)
    w_r = np.zeros((B,), np.float32)
    w_a = np.ones((B,), np.float32)
    lossmask = np.zeros((B, n), bool)
    ne = max([len(b["etok"]) for b in batch if "etok" in b] or [0])
    etok = np.zeros((B, max(ne, 1), E_TOKEN_F), np.float32)
    emask = np.zeros((B, max(ne, 1)), bool)
    for i, b in enumerate(batch):
        e = b.get("etok")
        if e is not None and len(e):
            etok[i, :len(e), :e.shape[1]], emask[i, :len(e)] = e, True
    for i, b in enumerate(batch):
        m = len(b["tok"])
        tok[i, :m, :b["tok"].shape[1]], mask[i, :m] = b["tok"], True
        act[i, :m], kind[i, :m], tcell[i, :m], toff[i, :m], w_out[i, :m] = b["act"], b["kind"], b["tcell"], b["toff"], b["w_out"]
        w_r[i] = b["w_rating"]
        w_a[i] = b.get("w_act", 1.0)
        lossmask[i, :m] = ~b.get("revealed", np.zeros(m, bool))
    T = (lambda x: x) if numpy else __import__("torch").from_numpy
    return {"grid": T(np.stack([b["grid"] for b in batch])), "scal": T(np.stack([b["scal"] for b in batch])),
            "tok": T(tok), "mask": T(mask), "etok": T(etok), "emask": T(emask),
            "act": T(act), "kind": T(kind), "tcell": T(tcell), "toff": T(toff),
            "w_out": T(w_out), "w_rating": T(w_r), "w_act": T(w_a), "lossmask": T(lossmask), **_collate_forces(batch, n, numpy),
            **({"ttgt": T(np.stack([np.pad(b["ttgt"], (0, n - len(b["ttgt"])), constant_values=-1)
                                    for b in batch]))} if all("ttgt" in b for b in batch) else {}),
            **({"v_t": T(np.stack([b["v_t"] for b in batch]))} if all("v_t" in b for b in batch) else {}),
            **({"b_eco": T(np.stack([b["b_eco"] for b in batch]))} if all("b_eco" in b for b in batch) else {})}


def _collate_forces(batch, n, numpy=False):
    """Force labels padded to the most forces in the batch; force index -1 on padding and units of no force."""
    if not all("force" in b for b in batch):
        return {}
    B = len(batch)
    nf = max(1, max(len(b["f_click"]) for b in batch))
    force = np.full((B, n), -1, np.int64)
    out = {"f_click": np.zeros((B, nf), np.float32), "f_kind": np.full((B, nf), -1, np.int64),
           "f_cell": np.full((B, nf), -1, np.int64), "f_off": np.zeros((B, nf, 2), np.float32),
           "f_spread": np.zeros((B, nf), np.float32), "f_shape": np.zeros((B, nf, 3), np.float32),
           "f_w": np.zeros((B, nf), np.float32), "f_neg": np.zeros((B, nf), np.float32), "f_raw": np.zeros((B, nf), np.float32), "f_contact": np.zeros((B, nf), np.float32),
           "f_goal": np.full((B, nf), -1, np.int64),
           "f_mask": np.zeros((B, nf), bool), "f_alive": np.full((B, nf), -1.0, np.float32)}
    member = np.full((B, n), -1.0, np.float32)
    for i, b in enumerate(batch):
        force[i, :len(b["force"])] = b["force"]
        if "f_member" in b:
            member[i, :len(b["f_member"])] = b["f_member"]
        k = len(b["f_click"])
        for key in out:
            out[key][i, :k] = b[key]
    T = (lambda x: x) if numpy else __import__("torch").from_numpy
    return {"force": T(force), "f_member": T(member), **{key: T(v) for key, v in out.items()}}


def find_games(roots):
    out = []
    for r in roots:
        out += sorted(glob.glob(str(Path(r) / "*" / "*.npz")))
    return out
