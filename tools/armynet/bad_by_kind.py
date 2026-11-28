"""How training rates orders, by order kind: count, share clearly bad (raw score under -1, the f_neg / f_unlike set),
share rated better than the side's other orders, and the mean copy weight (exp(0.5 * score), the f_w the trainer
uses). Own games (every team) beside players (humans only), so "what not to do" can be sized before it is trained.

    python tools/armynet/bad_by_kind.py [--public N] [--own DIR ...]
"""
import glob
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from data import Game  # noqa: E402

KIND = ["stop", "move", "fight", "attack", "patrol", "other"]


def tally(paths, humans_only):
    n, bad, good, w = (np.zeros(len(KIND)) for _ in range(4))
    games = 0
    for p in paths:
        try:
            g = Game(p, rng=np.random.default_rng(0))
        except Exception as e:  # noqa: BLE001
            print("skip", p, e)
            continue
        d, s = g.decisions, g.dec_score
        if not len(d):
            continue
        keep = np.ones(len(d), bool)
        if humans_only:
            keep = np.array([not g.is_ai.get(int(t), True) for t in d[:, 2]])
        k = np.clip(d[keep, 4].astype(np.int64), 0, len(KIND) - 1)
        sk = s[keep]
        n += np.bincount(k, minlength=len(KIND))
        bad += np.bincount(k, sk < 0, minlength=len(KIND))
        good += np.bincount(k, sk > 0, minlength=len(KIND))
        w += np.bincount(k, np.exp(0.5 * np.clip(sk, -2, 2)), minlength=len(KIND))
        games += 1
    return games, n, bad, good, w


def show(name, r):
    games, n, bad, good, w = r
    print("%s: %d games, %d orders" % (name, games, int(n.sum())))
    for i, k in enumerate(KIND):
        if n[i]:
            print("  %-7s %6.1f%% of orders  bad %5.1f%%  better %5.1f%%  copy weight %.2f"
                  % (k, 100 * n[i] / n.sum(), 100 * bad[i] / n[i], 100 * good[i] / n[i], w[i] / n[i]))


if __name__ == "__main__":
    a = sys.argv[1:]
    npub = int(a[a.index("--public") + 1]) if "--public" in a else 40
    own = [a[i + 1] for i, x in enumerate(a) if x == "--own"] or ["runtime/armynet/own-games"]
    pub = sorted(glob.glob("G:/bar-ai-archive/public-replays/recordings/*/*.npz"))[-npub:]
    show("players (public, humans)", tally(pub, True))
    for o in own:
        show("own games %s (every team)" % o, tally(sorted(glob.glob(o + "/*/*.npz")), False))
