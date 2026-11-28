#!/usr/bin/env python3
"""How much of the training data is navy, hovers and amphibious units (his 11-19: "for army what about navy?").

    python tools/armynet/navy_share.py

Per duel dataset, the army metal finished by kind of movement (ships and subs, hovers, amphibious, land, air), from
the movement columns replay_dataset.py writes (defs columns 12-16); games with any ship count as naval games.
"""
import glob
import sys

import numpy as np

KINDS = ("ship", "sub", "hover", "amphibious", "land", "air")


def kind(move, cls):
    land, water, under, _slope, _wade = move
    if cls == 4:
        return "air"
    if not land and water:
        return "sub" if under else "ship"
    if land and water:
        return "hover"
    if land and under:
        return "amphibious"
    return "land"


def main(a):
    files = sorted(glob.glob("G:/bar-ai-archive/public-replays/recordings/*/*.npz")) + \
        sorted(glob.glob("G:/bar-ai-archive/replay-orders/*/*.npz"))
    tot = dict.fromkeys(KINDS, 0.0)
    naval_games = games = 0
    for p in files:
        try:
            z = np.load(p)
            units, defs = z["units"], z["defs"]
        except Exception:
            continue
        if defs.shape[1] < 17:
            continue
        games += 1
        row = {int(r[0]): r for r in defs}
        first = {}
        for r in units:
            uid = int(r[1])
            if uid not in first and r[9] >= 1:
                first[uid] = int(r[2])
        game = dict.fromkeys(KINDS, 0.0)
        for d in first.values():
            r = row.get(d)
            if r is None or int(r[1]) not in (3, 4):
                continue
            game[kind(r[12:17], int(r[1]))] += r[2]
        if game["ship"] + game["sub"] > 0:
            naval_games += 1
        for k in KINDS:
            tot[k] += game[k]
    s = sum(tot.values()) or 1
    print("duels %d, with ships or subs %d (%.0f%%)" % (games, naval_games, 100 * naval_games / max(games, 1)))
    print("army metal finished: " + ", ".join("%s %.1f%%" % (k, 100 * tot[k] / s) for k in KINDS))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
