#!/usr/bin/env python3
"""Tasks: units a player keeps ordering together (his 11-19: "the same set of units are continuously being moved so
you kind of know, like, 'All right, those units are on a task together.' And there may be a moment where all of a
sudden those units are broken off or they start getting used separately ... macro vision").

    python tools/armynet/tasks.py <dataset .npz> ...     # what the tasks of those games look like

An order group (one team, one frame, one kind of order) continues the task holding most of its units when those
units are at least half the group; otherwise it starts a new task. Units go with their latest group, so a group
that takes some of a task's units splits it, and one that takes units from two tasks merges them. A task ends when
none of its units has had an order for QUIET seconds. The same rules run on the live order stream in serve.py.
"""
import collections
import glob
import sys

import numpy as np

QUIET = 120.0
GROUP_R = 600.0  # orders of one moment and kind whose targets lie this close form one group (lines are ~250 long)


def cluster_targets(rows, tx_i, tz_i, radius=GROUP_R):
    """Split one moment's orders (same team and kind) into groups by target: each row joins the first group whose
    target centre lies within radius, else starts one. The same rule for players' clicks and the model's orders."""
    groups, cent = [], []
    for r in rows:
        x, z = float(r[tx_i]), float(r[tz_i])
        for k, (cx, cz, n) in enumerate(cent):
            if (cx - x) ** 2 + (cz - z) ** 2 <= radius * radius:
                groups[k].append(r)
                cent[k] = ((cx * n + x) / (n + 1), (cz * n + z) / (n + 1), n + 1)
                break
        else:
            groups.append([r])
            cent.append((x, z, 1))
    return groups


def forces_at(task, x, z):
    """The forces at one moment (his 11-20, one order per group): the units of each live task are one force; units in
    none are grouped by where they stand, as a player box-selects, by the radius that groups clicks. task: per unit its
    task id or -1. Returns per unit its force index 0..F-1. The same in training (data.py) and play (serve.py)."""
    task = np.asarray(task)
    out = np.full(len(task), -1, np.int64)
    ids = {}
    for j, t in enumerate(task.tolist()):
        if t >= 0:
            out[j] = ids.setdefault(t, len(ids))
    free = [j for j in range(len(task)) if task[j] < 0]
    n = len(ids)
    for k, grp in enumerate(cluster_targets([[j, x[j], z[j]] for j in free], 1, 2)):
        for r in grp:
            out[int(r[0])] = n + k
    return out


class Tracker:
    """Feed order groups in frame order; read each unit's task and each task's state at any time after."""

    def __init__(self):
        self.task_of = {}          # unit -> task id
        self.last_order = {}       # unit -> frame of its last order
        self.tasks = {}            # task id -> dict(team, start, x0, z0, units, splits, merges, last)
        self.next_id = 0
        self.events = []           # (frame, kind, task id, n units)
        self.starts = {}           # task id -> (team, frame, x, z), kept after the task ends

    def _prune(self, frame):
        for tid, t in list(self.tasks.items()):
            live = {u for u in t["units"] if frame - self.last_order.get(u, -1e9) <= QUIET * 30}
            for u in t["units"] - live:
                if self.task_of.get(u) == tid:
                    del self.task_of[u]
            t["units"] = live
            if not live:
                self.events.append((frame, "end", tid, 0))
                del self.tasks[tid]

    def group(self, frame, team, units, xy):
        """units: the group's unit ids; xy: their (x, z) mean at the order. Returns the group's task id."""
        self._prune(frame)
        units = set(units)
        counts = collections.Counter(self.task_of[u] for u in units if u in self.task_of)
        tid = None
        if counts:
            best, n = counts.most_common(1)[0]
            if n * 2 >= len(units) and self.tasks[best]["team"] == team:
                tid = best
        if tid is None:
            tid = self.next_id
            self.next_id += 1
            self.tasks[tid] = {"team": team, "start": frame, "x0": xy[0], "z0": xy[1], "units": set(),
                               "splits": 0, "merges": 0, "last": frame}
            self.events.append((frame, "new", tid, len(units)))
            self.starts[tid] = (team, frame, xy[0], xy[1])
        donors = {self.task_of[u] for u in units if u in self.task_of and self.task_of[u] != tid}
        for d in donors:
            if d in self.tasks:
                left = self.tasks[d]["units"] - units
                if left:
                    self.tasks[d]["splits"] += 1
                    self.events.append((frame, "split", d, len(left)))
                self.tasks[tid]["merges"] += 1
                self.events.append((frame, "merge", tid, len(units)))
        for u in units:
            old = self.task_of.get(u)
            if old is not None and old != tid and old in self.tasks:
                self.tasks[old]["units"].discard(u)
            self.task_of[u] = tid
            self.last_order[u] = frame
        self.tasks[tid]["units"] |= units
        self.tasks[tid]["last"] = frame
        return tid


def tasks_of_game(decisions, units_xy):
    """Group a game's decisions (rows: frame, first, team, uid, kind, tx, tz, ...) by moment, kind and target, run the
    tracker over the groups in order; returns (group id per decision, task id per decision, tracker).
    units_xy(uid, frame) -> x, z."""
    gid = np.full(len(decisions), -1, np.int64)
    tid = np.full(len(decisions), -1, np.int64)
    tr = Tracker()
    by = collections.defaultdict(list)
    for i in np.argsort(decisions[:, 0], kind="stable"):
        d = decisions[i]
        by[(int(d[0]), int(d[2]), int(d[4]))].append(i)
    n = 0
    for (f, team, kind), idx in sorted(by.items()):
        for grp in cluster_targets([[i, decisions[i, 5], decisions[i, 6]] for i in idx], 1, 2):
            rows = [int(r[0]) for r in grp]
            uids = [int(decisions[i, 3]) for i in rows]
            pts = [units_xy(u, f) for u in uids]
            xy = (float(np.mean([p[0] for p in pts])), float(np.mean([p[1] for p in pts])))
            t = tr.group(f, team, uids, xy)
            gid[rows] = n
            tid[rows] = t
            n += 1
    return gid, tid, tr


def main(a):
    sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
    from data import Game
    paths = [p for x in a for p in glob.glob(x)]
    sizes, lives, splits, merges, per_min, orders_per = [], [], [], [], [], []
    share_big, big_sizes, big_groups = [], [], []
    for p in paths:
        g = Game(p)
        pos = {}
        for r in g.units:
            pos.setdefault(int(r[1]), []).append((r[0], r[4], r[5]))

        def xy(u, f):
            rows = pos.get(u)
            if not rows:
                return 0.0, 0.0
            i = min(range(len(rows)), key=lambda j: abs(rows[j][0] - f))
            return rows[i][1], rows[i][2]
        _, tid, tr = tasks_of_game(g.decisions, xy)
        c = collections.Counter(tid.tolist())
        orders_per += list(c.values())
        groups_per = collections.Counter()
        units_per = collections.defaultdict(set)
        for i, t in enumerate(tid):
            groups_per[(t, int(g.decisions[i, 0]))] += 1
            units_per[t].add(int(g.decisions[i, 3]))
        n_groups = collections.Counter(t for t, _ in groups_per)
        big = {t for t in c if len(units_per[t]) >= 3 and n_groups[t] >= 3}
        share_big.append(sum(c[t] for t in big) / max(1, len(tid)))
        big_sizes.extend(len(units_per[t]) for t in big)
        big_groups.extend(n_groups[t] for t in big)
        new = [e for e in tr.events if e[1] == "new"]
        ends = {e[2]: e[0] for e in tr.events if e[1] == "end"}
        for e in new:
            sizes.append(e[3])
            if e[2] in ends:
                lives.append((ends[e[2]] - e[0]) / 30.0)
        splits.append(sum(1 for e in tr.events if e[1] == "split"))
        merges.append(sum(1 for e in tr.events if e[1] == "merge"))
        mins = (g.frames.max() / 1800.0) if len(g.frames) else 1
        per_min.append(len(new) / max(mins, 1) / max(1, len(set(int(x) for x in g.decisions[:, 2]))))
    q = lambda v: "median %.1f q25 %.1f q75 %.1f" % (np.median(v), np.percentile(v, 25), np.percentile(v, 75))
    print("%d games: tasks started per player-minute %s" % (len(paths), q(per_min)))
    print("units at a task's start: %s" % q(sizes))
    print("task life (s, start to quiet): %s" % q(lives))
    print("orders (unit decisions) per task: %s" % q(orders_per))
    print("splits per game: %s; merges per game: %s" % (q(splits), q(merges)))
    print("share of unit orders in tasks of 3+ units and 3+ order groups: %s" % q(share_big))
    print("  those tasks: units %s; order groups %s" % (q(big_sizes), q(big_groups)))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
