#!/usr/bin/env python3
"""In-contact examples from the rules army (roadmap item 3, the Fable session 11-27: learn the small details of a fight
from the AI's own fight logic). Every built model_vs_rules game has a rules side with its orders recorded; rules-r2
has two. An example is a second at which the rules side gave orders (Game.examples: the AI's own order times); only
its armed units IN CONTACT (an armed enemy unit within the unit's weapon range + 200, ground truth) are predictions;
the rest of the side is input only (the `revealed` loss mask, inputs unchanged). The force, value and economy labels
are dropped: those heads keep learning from players only. `ttgt` is the attack's target: the index of the enemy token
nearest the order's point (within TGT_R), -1 when the order is no attack or the target is not among the tokens.

    python tools/armynet/contact_data.py --stats --mvr-log runtime/armynet/mvr-mvr-g2.log runtime/armynet/own-games/mvr-g2
    python tools/armynet/contact_data.py --stats --both runtime/armynet/own-games/rules-r2
"""
import argparse
import glob
import os
import random
import sys
import time
from collections import Counter
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import STAT_F, Game, G  # noqa: E402

CLS_ARMY, CLS_AIR = 3, 4
PAD = 200.0
RANGE_EDGE = 50.0  # out-ranging an enemy by more than this
TGT_R = 100.0     # an attack's point this close to an enemy token's position is on that enemy (a grid cell is ~96)
K_ATTACK = 3      # the kind index of an attack (serve.py KIND_CMD)
DROP = ("force", "f_cell", "f_off", "f_goal", "f_shape", "f_alive", "f_member", "f_judge", "v_t", "b_eco")


def rules_games(roots, mvr_logs="", both=False):
    """[(npz path, set of rules-side teams)]: the side the model did not play (from the run logs), or every side."""
    mt = {}
    for lg in filter(None, mvr_logs.split(",")):
        for ln in open(lg, encoding="utf-8"):
            p = ln.split()
            if len(p) >= 7 and p[0] == "seed":
                mt[Path(p[6]).name] = int(p[3].lstrip("t"))
    out = []
    for root in roots:
        for p in sorted(glob.glob(os.path.join(root, "**", "*.npz"), recursive=True)):
            z = np.load(p)
            play = {int(v) for v in z["allies"]}
            teams = {int(t[0]): int(t[1]) for t in z["teams"] if int(t[1]) in play}
            if both:
                out.append((p, set(teams)))
            elif Path(p).stem in mt:
                m = mt[Path(p).stem]
                out.append((p, {t for t, al in teams.items() if al != teams[m]}))
    return out


REPO = Path(__file__).resolve().parents[2]
HELD_SEEDS = ("-s6", "-s12")   # the rules sides of every set's seeds 6 and 12 are held out (the offline bar)


def sets_games(names):
    """Rules games of the named own-games sets: 'rules-*' sets have rules on every side; any other set is a
    model_vs_rules set whose run log (runtime/armynet/mvr-<set>.log) names the model's team."""
    out = []
    for nm in filter(None, names):
        root = str(REPO / "runtime" / "armynet" / "own-games" / nm)
        if nm.startswith("rules-"):
            out += rules_games([root], both=True)
        else:
            out += rules_games([root], str(REPO / "runtime" / "armynet" / ("mvr-%s.log" % nm)))
    return out


def held_out_contact(path):
    return Path(path).stem.endswith(HELD_SEEDS)


def contact_example(g, t, f):
    """The example for team t at frame f with only its in-contact armed units as predictions, or None."""
    ex = g.example(t, f)
    if not len(ex["tok"]):
        return None
    rows = g.rows_near(f)
    if not len(rows):
        return None
    ru = g.units[rows]
    rally, rcls, rdef = g.ually[rows], g.ucls[rows], g.udef[rows]
    built = ru[:, 9] >= 1.0
    foe = (rally != g.ally_of[t]) & (rally >= 0) & built & np.isin(rcls, (CLS_ARMY, CLS_AIR)) \
        & ((g.d_g[rdef] + g.d_a[rdef]) > 0)
    if not foe.any():
        return None
    pos = {int(u): i for i, u in enumerate(g.uid[rows])}
    n = len(ex["uid"])
    contact = np.zeros(n, bool)
    c_air = np.zeros(n, bool)    # the unit flies
    c_outr = np.zeros(n, bool)   # it out-ranges the nearest armed enemy (by more than RANGE_EDGE)
    fr_ = g.d_range[rdef[foe]]
    for j, u in enumerate(ex["uid"]):
        i = pos.get(int(u))
        if i is None:
            continue
        reach = float(g.d_range[rdef[i]]) + PAD
        d2 = (ru[foe, 4] - ru[i, 4]) ** 2 + (ru[foe, 5] - ru[i, 5]) ** 2
        k = int(np.argmin(d2))
        contact[j] = d2[k] <= reach * reach
        c_air[j] = rcls[i] == CLS_AIR
        c_outr[j] = float(g.d_range[rdef[i]]) > float(fr_[k]) + RANGE_EDGE
    if not contact.any():
        return None
    ttgt = np.full(n, -1, np.int64)
    et = ex.get("etok")
    hit = np.nonzero(contact & (ex["act"] > 0) & (ex["kind"] == K_ATTACK) & (ex["tcell"] >= 0))[0]
    if et is not None and len(et) and len(hit):
        ex_ = et[:, STAT_F + 8] * g.mapx
        ez_ = et[:, STAT_F + 9] * g.mapz
        for j in hit:
            c = int(ex["tcell"][j])
            tx = (c % G + float(ex["toff"][j, 0])) / G * g.mapx
            tz = (c // G + float(ex["toff"][j, 1])) / G * g.mapz
            d2 = (ex_ - tx) ** 2 + (ez_ - tz) ** 2
            k = int(np.argmin(d2))
            if d2[k] <= TGT_R * TGT_R:
                ttgt[j] = k
    out = {k: v for k, v in ex.items() if k not in DROP}
    out["revealed"] = ~contact | ex.get("revealed", np.zeros(n, bool))
    out["ttgt"] = ttgt
    out["c_air"], out["c_outr"] = c_air, c_outr
    out["n_attack"] = int(len(hit))
    # plain imitation of the rules army: no per-decision rating, no outcome weight (those judge players' choices)
    out["w_out"] = np.ones(n, np.float32)
    out["w_rating"] = 1.0
    out["w_act"] = 1.0
    return out


class ContactExamples(torch.utils.data.IterableDataset):
    """An endless stream of in-contact examples, `per_game` from each rules game drawn."""

    def __init__(self, games, per_game=32, seed=0):
        self.games, self.per_game, self.seed = list(games), per_game, seed

    def __iter__(self):

        info = torch.utils.data.get_worker_info()
        rng = random.Random(self.seed + (info.id if info else 0) + int(time.time()))
        while True:
            path, rules = rng.choice(self.games)
            try:
                g = Game(path, rng=np.random.default_rng(rng.randrange(1 << 30)))
            except Exception as e:  # noqa: BLE001
                print("skip", path, e, flush=True)
                continue
            picks = [e for e in g.examples if e[0] in rules]
            rng.shuffle(picks)
            got = 0
            for t, f in picks:
                if got >= self.per_game:
                    break
                ex = contact_example(g, t, f)
                if ex is not None:
                    got += 1
                    yield ex


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("roots", nargs="+")
    ap.add_argument("--mvr-log", default="")
    ap.add_argument("--both", action="store_true")
    ap.add_argument("--stats", action="store_true")
    ap.add_argument("--per-game", type=int, default=0, help="examples read per game for --stats (0: all)")
    a = ap.parse_args()
    games = rules_games(a.roots, a.mvr_log, a.both)
    c = Counter()
    for p, rules in games:
        g = Game(p, rng=np.random.default_rng(0))
        picks = [e for e in g.examples if e[0] in rules]
        if a.per_game:
            picks = picks[:: max(1, len(picks) // a.per_game)]
        c["sides"] += len(rules)
        for t, f in picks:
            ex = contact_example(g, t, f)
            c["seconds"] += 1
            if ex is None:
                continue
            lab = ~ex["revealed"]
            c["examples"] += 1
            c["units"] += int(lab.sum())
            c["ordered"] += int((lab & (ex["act"] > 0)).sum())
            for k in np.unique(ex["kind"][lab & (ex["act"] > 0)]):
                c["k%d" % k] += int((ex["kind"][lab & (ex["act"] > 0)] == k).sum())
            c["targets"] += int((ex["ttgt"] >= 0).sum())
            c["attacks"] += ex["n_attack"]
            od = lab & (ex["act"] > 0)
            for nm, m_ in (("ground", ~ex["c_air"]), ("air", ex["c_air"])):
                c["u_" + nm] += int((lab & m_).sum())
                c["o_" + nm] += int((od & m_).sum())
                c["o_%s_outr" % nm] += int((od & m_ & ex["c_outr"]).sum())
    o = c["ordered"] or 1
    print("%d games, %d rules sides; order seconds read %d, with units in contact %d; in-contact unit predictions %d, "
          "of them ordered %d (%s); attacks %d, their target an enemy token %d (%.3f)" % (
              len(games), c["sides"], c["seconds"], c["examples"], c["units"], c["ordered"],
              "  ".join("kind%s %.3f" % (k[1:], v / o) for k, v in sorted(c.items()) if k[0] == "k" and k[1:].isdigit()),
              c["attacks"], c["targets"], c["targets"] / max(c["attacks"], 1)))
    for nm in ("ground", "air"):
        print("  %-6s unit predictions %d, ordered %d, of the ordered out-ranging the nearest armed enemy %.3f" % (
            nm, c["u_" + nm], c["o_" + nm], c["o_%s_outr" % nm] / max(c["o_" + nm], 1)))


if __name__ == "__main__":
    main()
