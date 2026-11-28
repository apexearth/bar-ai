#!/usr/bin/env python3
"""How players order groups (his 11-20: "we right-click and we drag a line on the map ... the frontline guys drawn in
the line and then ... the longer range guys right behind them"). Per click of 3+ units (one moment, kind and target
cluster, tasks.cluster_targets): how far it sends them, how the targets are laid out (a point or a line, its length,
its angle to the direction of travel), and whether longer-range units are placed further back.

    python tools/armynet/group_orders.py [games]
"""
import random
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import Game, find_games  # noqa: E402
from tasks import tasks_of_game  # noqa: E402

ROOTS = ["G:/bar-ai-archive/public-replays/recordings"]


def main(a):
    n = int(a[0]) if a else 40
    games = find_games(ROOTS)
    random.Random(2).shuffle(games)
    dist, length, angle, depth_corr, sizes, single_pt, all_rows, grp_rows = [], [], [], [], [], [], 0, 0
    for path in games[:n]:
        g = Game(path)
        dec = g.decisions
        if not len(dec):
            continue

        def xy(u, f):
            p = g._pos(u, f)
            return (p[0], p[1]) if p else (0.0, 0.0)
        gid, _, _ = tasks_of_game(dec, xy)
        all_rows += len(dec)
        for k in np.unique(gid):
            rows = dec[gid == k]
            if len(rows) < 3 or int(rows[0, 4]) == 0:
                continue
            pos = [g._pos(int(r[3]), int(r[0])) for r in rows]
            keep = [i for i, p in enumerate(pos) if p is not None]
            if len(keep) < 3:
                continue
            rows = rows[keep]
            P = np.array([[pos[i][0], pos[i][1]] for i in keep])
            T = rows[:, 5:7].astype(np.float64)
            rng = g.d_range[[pos[i][3] for i in keep]]
            grp_rows += len(rows)
            sizes.append(len(rows))
            travel = T.mean(0) - P.mean(0)
            dist.append(float(np.linalg.norm(travel)))
            c = T - T.mean(0)
            spread = float(np.sqrt((c ** 2).sum(1).max()))
            if spread < 24:
                single_pt.append(1)
                continue
            single_pt.append(0)
            w, v = np.linalg.eigh(c.T @ c)
            axis = v[:, -1]
            proj = c @ axis
            length.append(float(proj.max() - proj.min()))
            if np.linalg.norm(travel) > 50:
                tu = travel / np.linalg.norm(travel)
                angle.append(float(np.degrees(np.arccos(min(1.0, abs(float(axis @ tu)))))))
                along = c @ tu
                if np.std(rng) > 1 and np.std(along) > 1:
                    depth_corr.append(float(np.corrcoef(rng, along)[0, 1]))
    q = lambda v: "median %.0f q25 %.0f q75 %.0f (n %d)" % (np.median(v), np.percentile(v, 25), np.percentile(v, 75), len(v))
    print("unit orders in clicks of 3+ units: %.0f%% of %d" % (100 * grp_rows / max(all_rows, 1), all_rows))
    print("units per click: %s" % q(sizes))
    print("how far a click sends the group (elmos, unit centre to target centre): %s" % q(dist))
    print("clicks to one point: %.0f%%; to a spread of targets: %.0f%%" % (100 * np.mean(single_pt), 100 - 100 * np.mean(single_pt)))
    print("spread clicks: line length %s" % q(length))
    print("  angle between the line and the direction of travel (90 = across it): %s" % q(angle))
    print("  range vs position along travel (negative = longer range placed further back): median %.2f, %.0f%% negative (n %d)"
          % (np.median(depth_corr), 100 * np.mean(np.array(depth_corr) < 0), len(depth_corr)))


if __name__ == "__main__":
    main(sys.argv[1:])
