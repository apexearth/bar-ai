#!/usr/bin/env python3
"""The offline bar for in-contact learning (roadmap item 3, the Fable session 11-27): on held-out rules games
(contact_data.held_out_contact), the rules army's in-contact choices against a model's, on the same moments.

- Target choice: of the rules army's in-contact attacks on a building, with the buildings within the unit's reach
  (weapon range + 200) as candidates, how often the pick is the most metal / the weakest (lowest health now) / the
  nearest; for the rules army (its label) and for the model: the pointer's best enemy token when the model has a
  trained pointer (--pointer), else what serve does with the model's place (the visible enemy nearest the chosen
  point, within 400).
- Pull-out: of the rules army's in-contact orders, the share whose point is away from their armed units near the unit
  (farther from their centre within 1,000 by over 100); the same for the model's place on the same units.

    python tools/armynet/contact_bar.py --model runtime/armynet/enemy1-absent/model-010000.pt [--pointer] [--per-game 300]
"""
import argparse
import sys
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from contact_data import held_out_contact, sets_games, contact_example, K_ATTACK, PAD  # noqa: E402
from data import STAT_F, G, Game, collate  # noqa: E402
from model import ArmyNet, arch_of, load_widened  # noqa: E402

SETS = "mvr-a,mvr-a2,mvr-b,mvr-cabs,mvr-cctl,mvr-e1,mvr-e2,mvr-e3,mvr-g0,mvr-g1,mvr-g2,mvr-t,mvr-tb,rules-r2"
CLS_STATIC, CLS_ARMY, CLS_AIR = 0, 3, 4


def point(cell, off, g):
    return (cell % G + off[0]) / G * g.mapx, (cell // G + off[1]) / G * g.mapz


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--pointer", action="store_true", help="the model has a trained target pointer")
    ap.add_argument("--per-game", type=int, default=300)
    ap.add_argument("--sets", default=SETS)
    ap.add_argument("--device", default="cpu")
    a = ap.parse_args()
    net = ArmyNet(*arch_of(a.model)).to(a.device)
    load_widened(net, a.model, a.device, log=lambda s: None)
    net.eval()
    games = [x for x in sets_games(a.sets.split(",")) if held_out_contact(x[0])]
    pick = {"rules": [0, 0, 0, 0], "model": [0, 0, 0, 0]}   # n, most metal, weakest, nearest
    pull = {"rules": [0, 0], "model": [0, 0], "mass": [0, 0.0]}  # n, away (mass: the model's probability away)
    for path, rules in games:
        g = Game(path, rng=np.random.default_rng(0))
        picks = [e for e in g.examples if e[0] in rules]
        picks = picks[:: max(1, len(picks) // a.per_game)]
        for t, f in picks:
            ex = contact_example(g, t, f)
            if ex is None:
                continue
            lab = ~ex["revealed"] & (ex["act"] > 0) & (ex["tcell"] >= 0)
            if not lab.any():
                continue
            b = {k: torch.from_numpy(v).to(a.device) for k, v in collate([ex], numpy=True).items()}
            with torch.no_grad():
                o = net(b["grid"], b["scal"], b["tok"], b["mask"], b.get("etok"), b.get("emask"))
                mc = o["cells"][0].argmax(-1)
                moff = net.offset_at(o["h"], o["u64"], mc[None])[0].cpu().numpy()
                cprob = torch.softmax(o["cells"][0].float(), -1).cpu().numpy()
            mc = mc.cpu().numpy()
            gz_, gx_ = np.mgrid[0:G, 0:G]
            cxs, czs = ((gx_ + .5) / G * g.mapx).ravel(), ((gz_ + .5) / G * g.mapz).ravel()
            et = ex["etok"]
            ex_, ez_ = et[:, STAT_F + 8] * g.mapx, et[:, STAT_F + 9] * g.mapz
            is_b = et[:, STAT_F + 15] > 0
            army = (et[:, STAT_F + 3] > 0) & (et[:, STAT_F + 13] > 0) & ~is_b
            rows = g.rows_near(f)
            ru = g.units[rows]
            foe_b = (g.ually[rows] != g.ally_of[t]) & (g.ually[rows] >= 0) & (g.ucls[rows] == CLS_STATIC) & (ru[:, 9] >= 1)
            bx, bz = ru[foe_b, 4], ru[foe_b, 5]
            bhp = ru[foe_b, 8] * g.d_hp[g.udef[rows][foe_b]]
            bm = g.d_metal[g.udef[rows][foe_b]]
            pos = {int(u): i for i, u in enumerate(g.uid[rows])}
            for j in np.nonzero(lab)[0]:
                ux, uz = ex["tok"][j, 10] * g.mapx, ex["tok"][j, 11] * g.mapz
                lx, lz = point(int(ex["tcell"][j]), ex["toff"][j], g)
                px, pz = point(int(mc[j]), moff[j], g)
                # pull-out, label and model on the same unit
                na = army & ((ex_ - ux) ** 2 + (ez_ - uz) ** 2 <= 1000 ** 2)
                if na.any():
                    cx, cz = ex_[na].mean(), ez_[na].mean()
                    d0 = np.hypot(ux - cx, uz - cz)
                    for who, (x_, z_) in (("rules", (lx, lz)), ("model", (px, pz))):
                        pull[who][0] += 1
                        pull[who][1] += int(np.hypot(x_ - cx, z_ - cz) > d0 + 100)
                    # how serve plays the unit heads (direction first, by the mass on each side): the model's
                    # probability on cells away from their armed units
                    pull["mass"][0] += 1
                    pull["mass"][1] += float(cprob[j][np.hypot(cxs - cx, czs - cz) > d0 + 100].sum())
                # target choice on the rules army's attacks on a building
                k = int(ex["ttgt"][j])
                if int(ex["kind"][j]) != K_ATTACK or k < 0 or not is_b[k] or not len(bx):
                    continue
                i = pos.get(int(ex["uid"][j]))
                reach = (float(g.d_range[g.udef[rows][i]]) if i is not None else 0.0) + PAD
                cand = np.nonzero((bx - ux) ** 2 + (bz - uz) ** 2 <= reach * reach)[0]
                if len(cand) < 2:
                    continue

                def bld_of(x_, z_):
                    d2 = (bx - x_) ** 2 + (bz - z_) ** 2
                    q = int(np.argmin(d2))
                    return q if d2[q] <= 100 ** 2 else -1
                lab_b = bld_of(ex_[k], ez_[k])
                if a.pointer and "tgt" in o:
                    tk = int(o["tgt"][0, j, 1:].argmax().item())
                    mod_b = bld_of(ex_[tk], ez_[tk])
                else:
                    vis = et[:, STAT_F + 13] > 0
                    d2 = np.where(vis, (ex_ - px) ** 2 + (ez_ - pz) ** 2, np.inf)
                    tk = int(np.argmin(d2))
                    mod_b = bld_of(ex_[tk], ez_[tk]) if d2[tk] <= 400 ** 2 else -1
                best_m = cand[int(np.argmax(bm[cand]))]
                weak = cand[int(np.argmin(bhp[cand]))]
                near = cand[int(np.argmin((bx[cand] - ux) ** 2 + (bz[cand] - uz) ** 2))]
                for who, q in (("rules", lab_b), ("model", mod_b)):
                    pick[who][0] += 1
                    pick[who][1] += int(q == best_m)
                    pick[who][2] += int(q == weak)
                    pick[who][3] += int(q == near)
    print("%d held-out rules games; model %s%s" % (len(games), a.model, " (pointer)" if a.pointer else ""))
    for who in ("rules", "model"):
        n = max(pick[who][0], 1)
        print("  %-5s attacks on a building with 2+ in reach %d: most metal %.3f  weakest %.3f  nearest %.3f | "
              "in-contact orders %d, pulling out %.3f" % (who, pick[who][0], pick[who][1] / n, pick[who][2] / n,
                                                          pick[who][3] / n, pull[who][0], pull[who][1] / max(pull[who][0], 1)))
    print("  model probability on pulling-out places, mean over the same orders: %.3f" % (pull["mass"][1] / max(pull["mass"][0], 1)))


if __name__ == "__main__":
    main()
