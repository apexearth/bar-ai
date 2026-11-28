#!/usr/bin/env python3
"""How much of an army's time is spent at the other side's metal spots, players against the model (his 11-19: "are we
aware of how often the units in training are going near a mex spot or geo? those are general POI areas for raiding").

    python tools/armynet/poi_rate.py --players [N]                 # the duel datasets (public + local recordings)
    python tools/armynet/poi_rate.py --campaign runtime/armynet/campaign-<stamp>   # our games, both sides

Per side and phase (3-10, 10-20, 20+ min), from every sample of every ground army unit:
  far    share of samples past the middle (place > 0.5 on the line from its own start to theirs)
  spot   share within 500 of a metal spot past the middle
  spots  how many different far spots the side's army visited per 10 minutes (spread: one blob visits few)
and for players, the share of new orders to army units that target a far spot (orders).
Geo vents are not in the recordings or the model's inputs; a built geo shows only as an economy building.
"""
import glob
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
R = 500.0
BANDS = ((3, 10), (10, 20), (20, 999))


def along(x, z, home, away):
    ax, az = away[0] - home[0], away[1] - home[1]
    return ((x - home[0]) * ax + (z - home[1]) * az) / max(ax * ax + az * az, 1.0)


def near_spot(x, z, spots):
    """index of the nearest spot within R, else -1"""
    out = np.full(len(x), -1, np.int64)
    for k in range(0, len(x), 20000):
        dx = x[k:k + 20000, None] - spots[None, :, 0]
        dz = z[k:k + 20000, None] - spots[None, :, 1]
        d2 = dx * dx + dz * dz
        j = d2.argmin(1)
        ok = d2[np.arange(len(j)), j] < R * R
        out[k:k + 20000] = np.where(ok, j, -1)
    return out


class Acc:
    def __init__(self):
        self.n = defaultdict(float)
        self.far = defaultdict(float)
        self.spot = defaultdict(float)
        self.visits = defaultdict(float)
        self.minutes = defaultdict(float)
        self.orders = defaultdict(float)
        self.orders_far = defaultdict(float)

    def add(self, minute, x, z, home, away, spots, frames_span):
        if not len(x):
            return
        f = along(x, z, home, away)
        sf = along(spots[:, 0], spots[:, 1], home, away)
        j = near_spot(x, z, spots)
        far_spot = (j >= 0) & (sf[np.maximum(j, 0)] > 0.5)
        for b in BANDS:
            m = (minute >= b[0]) & (minute < b[1])
            if not m.any():
                continue
            self.n[b] += m.sum()
            self.far[b] += (f[m] > 0.5).sum()
            self.spot[b] += far_spot[m].sum()
            # spots visited per 10 minutes: distinct (spot, 2-minute slot) pairs, a revisit later counts again
            slots = set(zip(j[m & far_spot].tolist(), (minute[m & far_spot] // 2).astype(int).tolist()))
            self.visits[b] += len(slots)
        for b in BANDS:
            lo, hi = b[0], min(b[1], frames_span / 1800.0)
            if hi > lo:
                self.minutes[b] += hi - lo

    def rows(self, name):
        out = []
        for b in BANDS:
            if not self.n[b]:
                continue
            o = ("  orders %.3f" % (self.orders_far[b] / self.orders[b])) if self.orders[b] else ""
            out.append("%-22s %2d-%-3s far %.3f  spot %.3f  far spots per 10 min %5.1f%s" % (
                name, b[0], "" if b[1] == 999 else b[1], self.far[b] / self.n[b], self.spot[b] / self.n[b],
                10 * self.visits[b] / max(self.minutes[b], 1e-9), o))
        return out


def players(limit):
    import replay_dataset as rd
    files = sorted(glob.glob("G:/bar-ai-archive/public-replays/recordings/*/*.npz")) + \
        sorted(glob.glob("G:/bar-ai-archive/replay-orders/*/*.npz"))
    if limit:
        files = files[::max(1, len(files) // limit)][:limit]
    acc = {"winner": Acc(), "loser": Acc()}
    used = 0
    for p in files:
        try:
            z = np.load(p)
            units, defs, spots, allies = z["units"], z["defs"], z["spots"], z["allies"]
            dec = z["decisions"]
            res = z["result"]
        except Exception:
            continue
        if len(allies) != 2 or len(set(allies.tolist())) != 2 or not len(spots):
            continue
        cls = {int(r[0]): int(r[1]) for r in defs}
        com = np.array([cls.get(int(d), -1) == 2 for d in units[:, 2]])
        first = units[com & (units[:, 0] <= units[0, 0] + 300)]
        starts = {}
        for r in first:
            starts.setdefault(int(r[3]), (r[4], r[5]))
        if len(starts) != 2:
            continue
        t0, t1 = sorted(starts)
        army = np.array([cls.get(int(d), -1) == 3 for d in units[:, 2]]) & (units[:, 9] >= 1)
        span = units[:, 0].max()
        for t, o in ((t0, t1), (t1, t0)):
            r = res[(dec[:, 2] == t) & (res >= 0)]
            if not len(r):
                continue
            a = acc["winner" if r.mean() > 0.5 else "loser"]
            m = army & (units[:, 3] == t)
            u = units[m]
            a.add(u[:, 0] / 1800.0, u[:, 4], u[:, 5], starts[t], starts[o], spots, span)
            def_of = dict(zip(units[:, 1].astype(int).tolist(), units[:, 2].astype(int).tolist()))
            dm = dec[(dec[:, 2] == t) & np.array([cls.get(def_of.get(int(uid), -1), -1) == 3 for uid in dec[:, 3]])]
            if len(dm):
                j = near_spot(dm[:, 5], dm[:, 6], spots)
                sf = along(spots[:, 0], spots[:, 1], starts[t], starts[o])
                far = (j >= 0) & (sf[np.maximum(j, 0)] > 0.5)
                mins = dm[:, 0] / 1800.0
                for b in BANDS:
                    mm = (mins >= b[0]) & (mins < b[1])
                    a.orders[b] += mm.sum()
                    a.orders_far[b] += far[mm].sum()
        used += 1
    print("players: %d duels with a result" % used)
    for k, a in acc.items():
        print("\n".join(a.rows("players, " + k)))


def ours(camp):
    import battles
    log = Path(camp) / "campaign.log"
    matches = [REPO / "matches" / json.loads(ln[7:])["match"] for ln in open(log)
               if ln.startswith("RESULT ") and "match" in json.loads(ln[7:])]
    acc = {0: Acc(), 1: Acc()}
    for md in matches:
        eng = REPO / "matches" / md.name.replace("armynet-watch-", "watch-armynet-engine-")
        st = eng / "armynet_static.txt"
        if not st.exists():
            continue
        spots, cls = [], {}
        for ln in open(st, errors="replace"):
            s = ln.split()
            if s and s[0] == "S":
                spots.append((float(s[2]), float(s[3])))
            elif s and s[0] == "D":
                cls[s[2]] = s[3]
        spots = np.array(spots, np.float32)
        text = (md / "infolog.txt").read_text(errors="replace")
        _d, starts, _c, snaps = battles.parse(text)
        if len(starts) != 2 or not len(spots):
            continue
        span = max(snaps) if snaps else 0
        for t in (0, 1):
            rows = [(f, x, z) for f in snaps for (_u, n, x, z, _h) in snaps[f].get(t, []) if cls.get(n) == "army"]
            if rows:
                r = np.array(rows, np.float64)
                acc[t].add(r[:, 0] / 1800.0, r[:, 1], r[:, 2], starts[t], starts[1 - t], spots, span)
    print("our games: %d" % len(matches))
    print("\n".join(acc[0].rows("A (the model)")))
    print("\n".join(acc[1].rows("B (our AI's army)")))


def main(a):
    if "--campaign" in a:
        ours(a[a.index("--campaign") + 1])
    if "--players" in a:
        i = a.index("--players")
        players(int(a[i + 1]) if len(a) > i + 1 and a[i + 1].isdigit() else 0)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
