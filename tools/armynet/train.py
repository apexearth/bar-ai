#!/usr/bin/env python3
"""Train the army model on replay examples; evaluate on whole held-out games against plain rules.

    python tools/armynet/train.py [--roots DIR ...] [--steps 20000] [--batch 32] [--out runtime/armynet/<name>]
    python tools/armynet/train.py --eval-only <model.pt> [--roots ...]

Roots default to both recording sets on G:. Every 10th game (by name hash) is held out. The evaluation reports, on
held-out examples: the keep/new log loss against the base rate; the kind accuracy against "always move"; and the
median distance in elmos from the predicted place to the player's, against "keep the current target or stand" and
"go to the nearest enemy in sight".
"""
import functools
import hashlib
import math
import os
import random
import sys
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import G, STAT_F, VALUE_H, Game, base_axis, collate, find_games, mirror, reveal  # noqa: E402
from model import ArmyNet, arch_of, load_widened  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
ROOTS = ["G:/bar-ai-archive/public-replays/recordings", "G:/bar-ai-archive/replay-orders"]


def his_game():
    sys.path.insert(0, str(REPO / "tools"))
    import mp_archive
    return mp_archive.his_game_running()


def held_out(path):
    return int(hashlib.md5(Path(path).name.encode()).hexdigest(), 16) % 10 == 0


# Players' orders per 3-minute band in 80 public duels (players_by_minute.py, 11-19): 70,860 at 9-11 min, 24,130 at
# 18-20, 9,320 at 21-23, 5,684 at 24-26, fewer after. Our games run 25-40 min, where the held-out place error trails
# keep-or-stand by 76 elmos against 37 before minute 18. --late samples a moment at minute 18+ by how much rarer its
# band is than the peak, at most 4x (a few long games must not dominate).
LATE_BANDS = ((18, 70860 / 24130), (21, 70860 / 9320))


def late_weight(frame):
    minute = frame / 1800.0
    w = 1.0
    for start, ratio in LATE_BANDS:
        if minute >= start:
            w = ratio
    return min(w, 4.0)


class Stream(torch.utils.data.IterableDataset):
    """Examples from random training games; with roots given, the game list is re-read every 10 minutes so new
    recordings join a running training (held-out games stay out)."""

    def __init__(self, games, per_game=64, seed=0, roots=None, augment=False, late=False, rounds=False, own=(),
                 own_share=0.0):
        self.games, self.per_game, self.seed, self.roots, self.augment = games, per_game, seed, roots, augment
        self.late, self.rounds = late, rounds
        # our own games (data._pick_examples learns every side of them): drawn at own_share whatever their count
        self.own, self.own_share = list(own), own_share

    def __iter__(self):
        info = torch.utils.data.get_worker_info()
        rng = random.Random(self.seed + (info.id if info else 0) + int(time.time()))
        buf = []
        games, scanned = self.games, time.time()
        while True:
            if self.roots and time.time() - scanned > 600:
                fresh = [p for p in find_games(self.roots) if not held_out(p)]
                if fresh:
                    games = fresh
                scanned = time.time()
            path = rng.choice(self.own) if self.own and rng.random() < self.own_share else rng.choice(games)
            try:
                g = Game(path, rng=np.random.default_rng(rng.randrange(1 << 30)))
            except Exception as e:
                print("skip", path, e, flush=True)
                continue
            if not g.examples:
                continue
            if self.late:
                picks = rng.choices(g.examples, weights=[late_weight(f) for _, f in g.examples],
                                    k=min(self.per_game, len(g.examples)))
            else:
                picks = rng.sample(g.examples, min(self.per_game, len(g.examples)))
            for t, f in picks:
                ex = g.example(t, f)
                if len(ex["tok"]):
                    if self.rounds:
                        ex = reveal(ex, rng)
                    buf.append(mirror(ex, self.augment and rng.random() < 0.5, self.augment and rng.random() < 0.5))
            rng.shuffle(buf)
            while len(buf) > 256:
                yield buf.pop()


def save_atomic(state, path):
    """Write beside, then rename into place; on Windows the rename fails while a test game's serve.py has the file
    open (11-20: the trainer died at its first checkpoint), so it retries for up to a minute."""
    tmp = path.with_suffix(".tmp")
    torch.save(state, tmp)
    for _ in range(300):
        try:
            os.replace(tmp, path)
            return
        except PermissionError:
            time.sleep(0.2)
    print("could not replace %s (in use); kept %s" % (path, tmp), flush=True)


def losses(model, b, dev):
    b = {k: v.to(dev) for k, v in b.items()}
    o = model(b["grid"], b["scal"], b["tok"], b["mask"], b.get("etok"), b.get("emask"))
    m = (b["mask"] & b["lossmask"]).float()  # revealed units are inputs this time, not predictions
    wr = b["w_rating"][:, None]
    wa = b["w_act"][:, None]
    l_act = (F.binary_cross_entropy_with_logits(o["act"], b["act"], reduction="none") * m * wr * wa).sum() /         (m * wa).sum()
    new = (b["act"] > 0) & b["mask"] & b["lossmask"]
    w = (b["w_out"] * wr)[new]
    if new.any():
        l_kind = (F.cross_entropy(o["kind"][new], b["kind"][new].clamp(min=0), reduction="none") * w).sum() / w.sum()
        l_cell = (F.cross_entropy(o["cells"][new], b["tcell"][new].clamp(min=0), reduction="none") * w).sum() / w.sum()
        off = model.offset_at(o["h"], o["u64"], b["tcell"])[new]
        l_off = ((off - b["toff"][new]).abs().sum(-1) * w).sum() / w.sum()
    else:
        l_kind = l_cell = l_off = torch.zeros((), device=dev)
    total = l_act + l_kind + l_cell + l_off
    logs = {"act": l_act.item(), "kind": l_kind.item(), "cell": l_cell.item(), "off": l_off.item()}
    if "ttgt" in b and "tgt" in o:
        # the attack's target among the enemy tokens (index 0 is "none"; contact_data.py labels the rules army's)
        sel = (b["ttgt"] >= 0) & b["mask"] & b["lossmask"]
        if sel.any():
            l_t = F.cross_entropy(o["tgt"][sel].float(), b["ttgt"][sel] + 1)
            total = total + l_t
            logs["tgt"] = l_t.item()
    if "force" in b:
        fl = force_losses(model, o, b, wr, dev)
        total = total + sum(fl.values())
        logs.update({k: v.item() for k, v in fl.items()})
    if "v_t" in b:
        l_v = value_loss(o["value"], b["v_t"])
        total = total + l_v
        logs["value"] = l_v.item()
    if "b_eco" in b:
        l_b = 10.0 * F.binary_cross_entropy_with_logits(o["b_eco"].float(), b["b_eco"])
        total = total + l_b
        logs["b_eco"] = l_b.item()
    return total, logs


def belief_eval(rows):
    """Held-out: where the enemy's economy stands, on the cells out of our sight only. Per example the k cells it
    really holds there; the share of them among the head's top k unseen cells, against the same for the rule a player
    could use with no model (metal spots, ranked by how far toward the enemy side they lie: the side of the map
    facing ours across the centre) and for what the side last saw (layer 23). Plus the BCE there."""
    hit_m, hit_r, hit_s, hit_x, n, bce = 0.0, 0.0, 0.0, 0.0, 0, []
    zz, xx = np.mgrid[0:G, 0:G]
    for logit, lab, grid in rows:
        out = grid[14] <= 0
        k = int((lab[out] > 0).sum())
        if k == 0:
            continue
        lab_o = lab[out]

        def top(score):
            s = np.where(out, score, -np.inf).ravel()
            pick = np.argpartition(-s, k - 1)[:k]
            return float(lab.ravel()[pick].sum()) / k

        w = np.expm1(np.clip(grid[3], 0, 20))
        if w.sum() > 0:
            ox, oz = (xx * w).sum() / w.sum(), (zz * w).sum() / w.sum()
        else:
            ox, oz = G / 2, G / 2
        fx, fz = G - 1 - ox, G - 1 - oz
        ax, az = fx - ox, fz - oz
        fwd = ((xx - ox) * ax + (zz - oz) * az) / max(ax * ax + az * az, 1.0)
        rule = (grid[1] > 0) * (1.0 - np.abs(fwd - 1.0)) + 1e-3 * np.random.default_rng(0).random((G, G))
        hit_m += top(logit) * k
        hit_r += top(rule) * k
        hit_s += top(grid[23] + 1e-3 * np.random.default_rng(1).random((G, G))) * k
        # his 11-21: a player assumes the enemy does about what he does -- our own economy, mirrored through the centre
        # (spots near where the mirror of our economy stands: the mirror is ~800 elmos off their real start, 6 cells)
        mo = grid[24][::-1, ::-1]
        ker = np.ones(13) / 13
        mo = np.apply_along_axis(lambda v: np.convolve(v, ker, "same"), 0, mo)
        mo = np.apply_along_axis(lambda v: np.convolve(v, ker, "same"), 1, mo)
        hit_x += top((grid[1] > 0) * mo + 1e-3 * rule) * k
        n += k
        p = 1 / (1 + np.exp(-logit[out]))
        bce.append(-np.mean(lab_o * np.log(p + 1e-7) + (1 - lab_o) * np.log(1 - p + 1e-7)))
    if not n:
        return {}
    return {"b_top_model": round(hit_m / n, 3), "b_top_rule": round(hit_r / n, 3), "b_top_seen": round(hit_s / n, 3),
            "b_top_mirror": round(hit_x / n, 3),
            "b_bce_unseen": round(float(np.mean(bce)), 4), "b_cells": n}


def value_loss(pred, t):
    """Huber on the trades and map-share changes (map share x10: its changes are a tenth the trades'), BCE on the
    result; only where the label is known."""
    pred = pred.float()
    nh = (t.shape[1] - 1) // 2
    scale = torch.ones(t.shape[1] - 1, device=t.device)
    scale[nh:] = 10.0
    reg, okr = t[:, :-1] * scale, ~torch.isnan(t[:, :-1])
    l = F.smooth_l1_loss(pred[:, :-1][okr], reg[okr]) if okr.any() else pred.sum() * 0
    res, oks = t[:, -1], ~torch.isnan(t[:, -1])
    if oks.any():
        l = l + 0.3 * F.binary_cross_entropy_with_logits(pred[:, -1][oks], res[oks])
    return l


def force_losses(model, o, b, wr, dev):
    """The force heads (his 11-20, one order per group): click or not on every force (quiet steps up-weighted like the
    unit act head); for clicked forces the kind, place, offset, point-or-line and the line's shape, weighted by the
    click's rating; the 60-s hindsight goal on every force that has one."""
    fo = model.forces(o["h"], o["u64"], b["force"])
    z = torch.zeros((), device=dev)
    fm = (b["f_mask"] & fo["present"]).float()
    wa = b["w_act"][:, None]
    out = {"f_act": (F.binary_cross_entropy_with_logits(fo["act"], b["f_click"], reduction="none") * fm * wr * wa).sum()
           / (fm * wa).sum().clamp(min=1e-6)}
    # a synthetic click (data._wake_idle: own games, parked idle) teaches the click head only: it has no place
    clicked = (b["f_click"] > 0) & (fm > 0) & (b["f_cell"] >= 0)
    if clicked.any():
        w = (b["f_w"] * wr)[clicked]
        ws = w.sum().clamp(min=1e-6)
        out["f_kind"] = (F.cross_entropy(fo["kind"][clicked], b["f_kind"][clicked].clamp(min=0), reduction="none") * w).sum() / ws
        out["f_cell"] = (F.cross_entropy(fo["cells"][clicked], b["f_cell"][clicked].clamp(min=0), reduction="none") * w).sum() / ws
        off = model.offset_at(fo["fh"], o["u64"], b["f_cell"])[clicked]
        out["f_off"] = ((off - b["f_off"][clicked]).abs().sum(-1) * w).sum() / ws
        out["f_spread"] = (F.binary_cross_entropy_with_logits(fo["spread"][clicked], b["f_spread"][clicked], reduction="none") * w).sum() / ws
        line = clicked & (b["f_spread"] > 0)
        out["f_shape"] = (((fo["shape"][line] - b["f_shape"][line]) ** 2).sum(-1) * (b["f_w"] * wr)[line]).sum() \
            / (b["f_w"] * wr)[line].sum().clamp(min=1e-6) if line.any() else z
        # his 11-20, "penalize such a position hard": a clicked force whose order rated clearly bad (score under -1,
        # e.g. a minute or more parked idle) also pushes its place down, not only out of the copying
        if "f_neg" in b:
            neg = clicked & (b["f_neg"] > 0)
            if neg.any():
                pc = torch.softmax(fo["cells"][neg].float(), -1).gather(1, b["f_cell"][neg].clamp(min=0)[:, None])[:, 0]
                out["f_unlike"] = (-torch.log((1 - pc).clamp(min=1e-4)) * b["f_neg"][neg]).sum() / ws
            else:
                out["f_unlike"] = z
    else:
        out.update(f_kind=z, f_cell=z, f_off=z, f_spread=z, f_shape=z, f_unlike=z)
    # which members the click took (his 11-22: players split a force in a fight), weighted by the click's rating
    if "f_member" in b and (b["f_member"] >= 0).any():
        lab = b["f_member"] >= 0
        fw = torch.gather(b["f_w"] * wr, 1, b["force"].clamp(min=0))
        mw = fw[lab]
        out["f_member"] = (F.binary_cross_entropy_with_logits(fo["member"][lab].float(), b["f_member"][lab],
                                                              reduction="none") * mw).sum() / mw.sum().clamp(min=1e-6)
    else:
        out["f_member"] = z
    # the move judge learns the rating of the place each real click chose (synthetic clicks carry no rating: f_raw 0)
    if "f_raw" in b:
        jl = (b["f_click"] > 0) & (fm > 0) & (b["f_cell"] >= 0) & (b["f_raw"] != 0)
        if jl.any():
            jp = fo["judge"].float().gather(2, b["f_cell"].clamp(min=0)[..., None])[..., 0]
            out["f_judge"] = 0.3 * F.smooth_l1_loss(jp[jl], b["f_raw"][jl].clamp(-3, 3))
        else:
            out["f_judge"] = z
    hasg = (b["f_goal"] >= 0) & (fm > 0)
    # 0.3: the goal is an aid, and its 4,096-cell CE on every force was the largest term (11-20 review)
    out["f_goal"] = 0.3 * F.cross_entropy(fo["goal"][hasg], b["f_goal"][hasg]) if hasg.any() else z
    hasa = (b["f_alive"] >= 0) & (fm > 0)
    out["f_alive"] = 0.3 * F.binary_cross_entropy_with_logits(fo["alive"][hasa], b["f_alive"][hasa]) if hasa.any() else z
    return out




@torch.no_grad()
def force_eval(model, o, bd, b, st):
    """Held-out force measures: the click rate per force-step (players, weighted for quiet-step sampling, vs the
    model's mean chance); for clicked forces, how far the model's best place is from the player's click target
    against just staying at the force's centre; the same for the 60-s goal; point-or-line accuracy."""
    fo = model.forces(o["h"], o["u64"], bd["force"])
    fm = (b["f_mask"] & fo["present"].cpu()).numpy()
    wa = np.broadcast_to(b["w_act"].numpy()[:, None], fm.shape)
    pc = torch.sigmoid(fo["act"]).cpu().numpy()
    cl = b["f_click"].numpy()
    st.setdefault("f_rate_player", []).append(float((cl * wa)[fm].sum() / max(wa[fm].sum(), 1e-6)))
    st.setdefault("f_rate_model", []).append(float((pc * wa)[fm].sum() / max(wa[fm].sum(), 1e-6)))
    mapx = b["scal"].numpy()[:, 3] * 16000
    mapz = b["scal"].numpy()[:, 4] * 16000
    tok, force = b["tok"].numpy(), b["force"].numpy()
    best = fo["cells"].argmax(-1).cpu().numpy()
    bestg = fo["goal"].argmax(-1).cpu().numpy()
    spr = (fo["spread"] > 0).cpu().numpy()
    if "f_member" in b:
        # which members a click took: the model's accuracy against taking every member (the old play)
        lab = b["f_member"].numpy()
        pm = (fo["member"] > 0).cpu().numpy()
        ok = lab >= 0
        if ok.any():
            st.setdefault("f_member_acc", []).append(float((pm[ok] == (lab[ok] > 0)).mean()))
            st.setdefault("f_member_all", []).append(float((lab[ok] > 0).mean()))
            # 11-24: in contact the model's clicks carry ~3 units against players' ~8; the head's mean chance per labelled
            # member against the share players took
            pmem = torch.sigmoid(fo["member"].float()).cpu().numpy()
            st.setdefault("f_member_pmean", []).append(float(pmem[ok].mean()))
            if "f_contact" in b:
                # members of in-contact forces: units the model would take per click vs the player's click
                fc = np.take_along_axis(b["f_contact"].numpy(), np.clip(b["force"].numpy(), 0, None), 1) > 0
                okc = ok & fc & (b["force"].numpy() >= 0)
                if okc.any():
                    st.setdefault("f_member_p_contact", []).append(float(pmem[okc].mean()))
                    st.setdefault("f_member_lab_contact", []).append(float((lab[okc] > 0).mean()))
    if "f_raw" in b:
        # his 11-24 "what not to do": the model's log-chance of the player's kind and place, on clicks rated better
        # than the side's other orders vs worse; the gap (better minus worse) is what rating-aware training should widen
        clk = (b["f_click"] > 0) & (b["f_cell"] >= 0) & b["f_mask"]
        raw = b["f_raw"]
        lk = torch.log_softmax(fo["kind"].float(), -1).gather(2, bd["f_kind"].clamp(min=0)[..., None])[..., 0].cpu()
        lc = torch.log_softmax(fo["cells"].float(), -1).gather(2, bd["f_cell"].clamp(min=0)[..., None])[..., 0].cpu()
        pk = torch.softmax(fo["kind"].float(), -1).cpu()
        if clk.any():
            st.setdefault("f_p_fight", []).extend((pk[..., 2] + pk[..., 3])[clk].tolist())
            st.setdefault("f_fight_label", []).extend(((bd["f_kind"].cpu() == 2) | (bd["f_kind"].cpu() == 3))[clk].float().tolist())
        jsel = clk & (raw != 0)
        if jsel.any():
            jp = fo["judge"].float().gather(2, bd["f_cell"].clamp(min=0)[..., None])[..., 0].cpu()
            st.setdefault("_judge_p", []).extend(jp[jsel].tolist())
            st.setdefault("_judge_t", []).extend(raw[jsel].clamp(-3, 3).tolist())
        for name, sel in (("good", clk & (raw > 0.25)), ("bad", clk & (raw < -0.25))):
            if sel.any():
                st.setdefault("f_lk_" + name, []).extend(lk[sel].tolist())
                st.setdefault("f_lc_" + name, []).extend(lc[sel].tolist())
    for i in range(fm.shape[0]):
        sx, sz = mapx[i] / G, mapz[i] / G
        for k in np.where(fm[i])[0]:
            mem = force[i] == k
            if not mem.any():
                continue
            cx, cz = tok[i, mem, 10].mean() * mapx[i], tok[i, mem, 11].mean() * mapz[i]
            for lab, pred, key in ((b["f_cell"][i, k].item(), best[i, k], "cell"), (b["f_goal"][i, k].item(), bestg[i, k], "goal")):
                if lab < 0 or (key == "cell" and cl[i, k] <= 0):
                    continue
                lx, lz = (lab % G + .5) * sx, (lab // G + .5) * sz
                px, pz = (pred % G + .5) * sx, (pred // G + .5) * sz
                st.setdefault("d_f_%s_model" % key, []).append(float(np.hypot(px - lx, pz - lz)))
                st.setdefault("d_f_%s_stay" % key, []).append(float(np.hypot(cx - lx, cz - lz)))
            if cl[i, k] > 0:
                st.setdefault("f_spread_acc", []).append(float(spr[i, k] == (b["f_spread"][i, k].item() > 0)))
            lab = b["f_cell"][i, k].item()
            if cl[i, k] > 0 and lab >= 0 and "f_contact" in b and b["f_contact"][i, k].item() > 0:
                # 11-24 kite: an in-contact click that steps back (its target 100+ farther from the nearest enemy than
                # the force stands); the model's best cell judged the same way
                ev = np.argwhere(b["grid"][i, 7].numpy() > 0)
                if len(ev):
                    ex_ = (ev[:, 1] + .5) * sx
                    ez_ = (ev[:, 0] + .5) * sz
                    e0 = int(np.argmin((ex_ - cx) ** 2 + (ez_ - cz) ** 2))
                    d0 = math.hypot(ex_[e0] - cx, ez_[e0] - cz)
                    back = lambda c: math.hypot(ex_[e0] - (c % G + .5) * sx, ez_[e0] - (c // G + .5) * sz) > d0 + 100
                    lb, pb = back(lab), back(int(best[i, k]))
                    st.setdefault("f_back_player", []).append(float(lb))
                    st.setdefault("f_back_model", []).append(float(pb))
                    if lb:
                        st.setdefault("f_back_recall", []).append(float(pb))


def value_eval(p, t):
    """Held-out: per horizon, the share of the label's variance the value head explains (1 - MSE / variance; 0 is no
    better than the mean), trades and map share; the result's accuracy against always guessing the more common one."""
    nh = (t.shape[1] - 1) // 2
    out = {}
    for j in range(t.shape[1] - 1):
        ok = ~np.isnan(t[:, j])
        if ok.sum() < 20:
            continue
        pj = p[ok, j] / (10.0 if j >= nh else 1.0)
        var = float(np.var(t[ok, j]))
        out["v_r2_%s%d" % ("trade" if j < nh else "share", VALUE_H[j % nh])] = \
            round(1 - float(np.mean((pj - t[ok, j]) ** 2)) / max(var, 1e-9), 3)
    ok = ~np.isnan(t[:, -1])
    if ok.sum() >= 20:
        out["v_result_acc"] = round(float(np.mean((p[ok, -1] > 0) == (t[ok, -1] > 0.5))), 3)
        out["v_result_base"] = round(float(max(t[ok, -1].mean(), 1 - t[ok, -1].mean())), 3)
    return out


@torch.no_grad()
def evaluate(model, games, dev, n_games=40, per_game=40):
    model.eval()
    rng = random.Random(1)
    games = games[:]
    rng.shuffle(games)
    acts, preds, kinds_t, kinds_p = [], [], [], []
    d_model, d_keep, d_enemy, d_order = [], [], [], []
    fwd_model, fwd_player = [], []
    resp_hit = []  # per player order aimed at an enemy near our buildings: did the model aim there too
    resp_p, p_new, p_keep = [], [], []  # the model's chance of a new order then; on ordered / unordered units
    contact_p, contact_l, contact_w = [], [], []
    early_m, early_k, late_m, late_k = [], [], [], []  # place error, model / keep-or-stand, before / from minute 18
    retreat_hit, retreat_p, retreat_mass, stay_mass, back_axis = [], [], [], [], {}
    spot_player, spot_model, spot_mass_yes, spot_mass_no = [], [], [], []
    f_stats = {}
    v_pred, v_true = [], []
    b_rows = []
    for path in games[:n_games]:
        g = Game(path, rng=np.random.default_rng(7))
        if not g.examples:
            continue
        exs = [g.example(t, f) for t, f in rng.sample(g.examples, min(per_game, len(g.examples)))]
        exs = [e for e in exs if len(e["tok"])]
        if not exs:
            continue
        b = collate(exs)
        if os.environ.get("BARAI_EVAL_SKILL"):
            # ask the model to play at one skill (data.py's skill scalars), as serve --skill does
            b["scal"][:, 8], b["scal"][:, 9] = 1.0, float(os.environ["BARAI_EVAL_SKILL"]) / 50
        bd = {k: v.to(dev) for k, v in b.items()}
        o = model(bd["grid"], bd["scal"], bd["tok"], bd["mask"], bd.get("etok"), bd.get("emask"))
        if "force" in bd:
            force_eval(model, o, bd, b, f_stats)
        if "v_t" in b:
            v_pred.append(o["value"].float().cpu().numpy())
            v_true.append(b["v_t"].numpy())
        if "b_eco" in b and "b_eco" in o:
            bl, bt, bg = o["b_eco"].float().cpu().numpy(), b["b_eco"].numpy(), b["grid"].numpy()
            b_rows.extend((bl[i], bt[i], bg[i]) for i in range(len(bl)))
        msk = b["mask"].numpy()
        acts.append(b["act"].numpy()[msk])
        pact = torch.sigmoid(o["act"]).cpu().numpy()
        preds.append(pact[msk])
        p_new.extend(pact[msk & (b["act"].numpy() > 0)].tolist())
        p_keep.extend(pact[msk & (b["act"].numpy() == 0)].tolist())
        if "etok" in b:
            # in contact as serve's --unit-contact reads it: a visible enemy army unit within 600
            et, em, tk_ = b["etok"].numpy(), b["emask"].numpy(), b["tok"].numpy()
            for i in range(len(tk_)):
                ae = em[i] & (et[i, :, STAT_F + 3] > 0) & (et[i, :, STAT_F + 13] > 0) & (et[i, :, STAT_F + 15] <= 0)
                if not ae.any():
                    continue
                d2 = ((tk_[i, :, 10:11] - et[i, ae, STAT_F + 8][None]) * g.mapx) ** 2 + \
                     ((tk_[i, :, 11:12] - et[i, ae, STAT_F + 9][None]) * g.mapz) ** 2
                c_ = msk[i] & (d2.min(1) <= 600.0 ** 2)
                contact_p.extend(pact[i][c_].tolist())
                contact_l.extend(b["act"].numpy()[i][c_].tolist())
                contact_w.extend([float(b["w_act"][i])] * int(c_.sum()))
        new = (b["act"].numpy() > 0) & msk
        if not new.any():
            continue
        kinds_t.append(b["kind"].numpy()[new])
        kinds_p.append(o["kind"].argmax(-1).cpu().numpy()[new])
        cell = o["cells"].argmax(-1)
        off = model.offset_at(o["h"], o["u64"], cell).cpu().numpy()
        cell = cell.cpu().numpy()
        tok = b["tok"].numpy()
        grid = b["grid"].numpy()
        axes, threats, back_axis, far_spots, far_cells = {}, {}, {}, {}, {}
        for i, j in zip(*np.where(new)):
            sx, sz = g.mapx / G, g.mapz / G
            if i not in axes:
                axes[i] = base_axis(grid[i], sx, sz, g.mapx, g.mapz)
                # threat cells (11-19 overnight, raid answers): enemy units in sight within 1,200 of a building of ours
                foe = np.argwhere(grid[i][7] > 0)
                ours = np.argwhere((grid[i][3] > 0) | (grid[i][24] > 0))
                if len(foe) and len(ours):
                    d2 = (((foe[:, None, :] - ours[None, :, :]) * np.array([sz, sx])) ** 2).sum(-1).min(1)
                    threats[i] = (foe[d2 <= 1200 ** 2] + 0.5) * np.array([sz, sx])
                else:
                    threats[i] = np.zeros((0, 2))
            tc = int(b["tcell"][i, j])
            tx = (tc % G + float(b["toff"][i, j, 0])) * sx
            tz = (tc // G + float(b["toff"][i, j, 1])) * sz
            px = (cell[i, j] % G + off[i, j, 0]) * sx
            pz = (cell[i, j] // G + off[i, j, 1]) * sz
            ux, uz = tok[i, j, 10] * g.mapx, tok[i, j, 11] * g.mapz
            if tok[i, j, 21] > 0:
                kx, kz = ux + tok[i, j, 22] * 2000, uz + tok[i, j, 23] * 2000
            else:
                kx, kz = ux, uz
            ev = np.argwhere(np.expm1(grid[i, 7]) > 0)
            if len(ev):
                cz_, cx_ = ev[np.argmin(((ev[:, 1] + .5) * sx - ux) ** 2 + ((ev[:, 0] + .5) * sz - uz) ** 2)]
                ex_, ez_ = (cx_ + .5) * sx, (cz_ + .5) * sz
            else:
                ex_, ez_ = kx, kz
            d_model.append(math.hypot(px - tx, pz - tz))
            d_keep.append(math.hypot(kx - tx, kz - tz))
            d_enemy.append(math.hypot(ex_ - tx, ez_ - tz))
            d_order.append(math.hypot(ux - tx, uz - tz))
            late = float(b["scal"][i, 0]) * 30 >= 18  # the first scalar is game minutes / 30
            (late_m if late else early_m).append(d_model[-1])
            (late_k if late else early_k).append(d_keep[-1])
            fwd_model.append(axes[i](px, pz))
            # retreats out of fights (his 11-19: "we kept engaging when we probably should have stopped"): the player
            # sent the unit back by 0.1+ of the way while enemy weapons reached its cell
            cxu = int(min(max(tok[i, j, 10] * G, 0), G - 1))
            czu = int(min(max(tok[i, j, 11] * G, 0), G - 1))
            fu = axes[i](ux, uz)
            if grid[i][11][czu, cxu] > 0:
                # the probability the model puts behind the unit (cells 0.1+ back toward our buildings)
                if i not in back_axis:
                    zz, xx = np.mgrid[0:G, 0:G]
                    back_axis[i] = axes[i]((xx + .5) * sx, (zz + .5) * sz).ravel()
                probs = torch.softmax(o["cells"][i, j].float(), -1).cpu().numpy()
                mass = float(probs[back_axis[i] < fu - 0.1].sum())
                if axes[i](tx, tz) < fu - 0.1:
                    retreat_hit.append(axes[i](px, pz) < fu - 0.1)
                    retreat_p.append(float(pact[i, j]))
                    retreat_mass.append(mass)
                else:
                    stay_mass.append(mass)
            fwd_player.append(axes[i](tx, tz))
            # metal spots past the middle (his 11-19, raid points): players' targets there vs the model's, and the
            # probability the model puts within 500 of one
            if i not in far_spots:
                sp = np.argwhere(grid[i][1] > 0)
                sp = (sp + 0.5) * np.array([sz, sx])
                sp = sp[np.array([axes[i](c[1], c[0]) > 0.5 for c in sp], bool)] if len(sp) else sp
                far_spots[i] = sp
                zz, xx = np.mgrid[0:G, 0:G]
                cc = np.stack([(zz.ravel() + .5) * sz, (xx.ravel() + .5) * sx], 1)
                far_cells[i] = (((cc[:, None, :] - sp[None, :, :]) ** 2).sum(-1).min(1) <= 500 ** 2) if len(sp) \
                    else np.zeros(G * G, bool)
            sp = far_spots[i]
            if len(sp):
                at = lambda x_, z_: bool((((sp[:, 1] - x_) ** 2 + (sp[:, 0] - z_) ** 2) <= 500 ** 2).any())
                spot_player.append(at(tx, tz))
                spot_model.append(at(px, pz))
                sm = float(torch.softmax(o["cells"][i, j].float(), -1).cpu().numpy()[far_cells[i]].sum())
                (spot_mass_yes if spot_player[-1] else spot_mass_no).append(sm)
            th = threats[i]
            if len(th):
                near = lambda x_, z_: bool((((th[:, 1] - x_) ** 2 + (th[:, 0] - z_) ** 2) <= 600 ** 2).any())
                if near(tx, tz):
                    resp_hit.append(near(px, pz))
                    resp_p.append(float(pact[i, j]))
    model.train()
    a, p = np.concatenate(acts), np.clip(np.concatenate(preds), 1e-6, 1 - 1e-6)
    base = a.mean()
    ll = -np.mean(a * np.log(p) + (1 - a) * np.log(1 - p))
    ll0 = -np.mean(a * np.log(base) + (1 - a) * np.log(1 - base))
    kt, kp = np.concatenate(kinds_t), np.concatenate(kinds_p)
    med = lambda v: float(np.median(v)) if v else float("nan")
    fs = {k: round(float(np.median(v)), 3) if k.startswith("d_") else round(float(np.mean(v)), 4)
          for k, v in f_stats.items() if v and not k.startswith("_")}
    if len(f_stats.get("_judge_p", [])) > 20:
        jp, jt = np.array(f_stats["_judge_p"]), np.array(f_stats["_judge_t"])
        fs["judge_r"] = round(float(np.corrcoef(jp, jt)[0, 1]), 4)
        good, bad = jp[jt > 0.25][:4000], jp[jt < -0.25][:4000]
        if len(good) and len(bad):
            # chance a better-rated click is judged above a worse-rated one (0.5 = no skill)
            fs["judge_auc"] = round(float((good[:, None] > bad[None, :]).mean()), 4)
        fs["judge_n"] = len(jp)
    for h in ("lk", "lc"):
        if "f_%s_good" % h in fs and "f_%s_bad" % h in fs:
            fs["f_%s_gap" % h] = round(fs["f_%s_good" % h] - fs["f_%s_bad" % h], 4)
    if v_pred:
        fs.update(value_eval(np.concatenate(v_pred), np.concatenate(v_true)))
    if b_rows:
        fs.update(belief_eval(b_rows))
    return {**fs, "tokens": len(a), "new_rate": round(float(base), 4), "act_logloss": round(float(ll), 4),
            "act_logloss_base": round(float(ll0), 4), "kind_acc": round(float((kt == kp).mean()), 3),
            "kind_acc_always_move": round(float((kt == 1).mean()), 3), "orders": len(d_model),
            "dist_model": round(med(d_model)), "dist_keep_or_stand": round(med(d_keep)),
            "dist_nearest_enemy": round(med(d_enemy)), "order_length": round(med(d_order)),
            "forward_model": round(med(fwd_model), 2), "forward_player": round(med(fwd_player), 2),
            "forward_model_q75": round(float(np.percentile(fwd_model, 75)), 2) if fwd_model else None,
            "forward_player_q75": round(float(np.percentile(fwd_player, 75)), 2) if fwd_player else None,
            # raids (his 11-19): of the players' orders past 0.7 of the way to their base, the share the model also
            # sends past 0.7; and how often each sends units that deep at all
            "deep_recall": round(float(np.mean([m > 0.7 for m, p in zip(fwd_model, fwd_player) if p > 0.7])), 3)
            if any(p > 0.7 for p in fwd_player) else None,
            "deep_model": round(float(np.mean(np.array(fwd_model) > 0.7)), 3) if fwd_model else None,
            "deep_player": round(float(np.mean(np.array(fwd_player) > 0.7)), 3) if fwd_player else None,
            "response_orders": len(resp_hit),
            "response_recall": round(float(np.mean(resp_hit)), 3) if resp_hit else None,
            "p_act_response": round(float(np.mean(resp_p)), 3) if resp_p else None,
            "p_act_ordered": round(float(np.mean(p_new)), 3) if p_new else None,
            "p_act_unordered": round(float(np.mean(p_keep)), 3) if p_keep else None,
            "contact_p_act": round(float(np.average(contact_p, weights=contact_w)), 4) if contact_p else None,
            "contact_act_rate": round(float(np.average(contact_l, weights=contact_w)), 4) if contact_l else None,
            "contact_n": len(contact_p),
            "dist_early": [len(early_m), round(med(early_m)), round(med(early_k))] if early_m else None,
            "dist_late": [len(late_m), round(med(late_m)), round(med(late_k))] if late_m else None,
            "retreat_orders": len(retreat_hit),
            "retreat_recall": round(float(np.mean(retreat_hit)), 3) if retreat_hit else None,
            "p_act_retreat": round(float(np.mean(retreat_p)), 3) if retreat_p else None,
            "retreat_mass": round(float(np.mean(retreat_mass)), 3) if retreat_mass else None,
            "far_spot_player": round(float(np.mean(spot_player)), 3) if spot_player else None,
            "far_spot_model": round(float(np.mean(spot_model)), 3) if spot_model else None,
            "far_spot_mass_when_player": round(float(np.mean(spot_mass_yes)), 3) if spot_mass_yes else None,
            "far_spot_mass_when_not": round(float(np.mean(spot_mass_no)), 3) if spot_mass_no else None,
            "retreat_mass_when_not": round(float(np.mean(stay_mass)), 3) if stay_mass else None}


def main(a):
    def opt(name, default):
        return a[a.index(name) + 1] if name in a else default
    roots = [a[i + 1] for i, x in enumerate(a) if x == "--roots"] or ROOTS
    games = find_games(roots)
    train = [g for g in games if not held_out(g)]
    test = [g for g in games if held_out(g)] or train[:2]
    dev = opt("--device", "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu"))
    print("games: %d train, %d held out; device %s" % (len(train), len(test), dev), flush=True)
    model = ArmyNet(*arch_of(opt("--init", "") or opt("--eval-only", ""))).to(dev)
    if "--eval-only" in a:
        load_widened(model, opt("--eval-only", ""), dev)
        print(evaluate(model, games if "--eval-all" in a else test, dev, per_game=int(opt("--per-game", "40"))))
        return 0
    steps = int(opt("--steps", "20000"))
    out = Path(opt("--out", str(REPO / "runtime" / "armynet" / time.strftime("%Y%m%d-%H%M"))))
    out.mkdir(parents=True, exist_ok=True)
    if "--init" in a:
        load_widened(model, opt("--init", ""), dev, log=lambda s: print(s, flush=True))
    save_every = int(opt("--save-every", "0"))
    start = int(opt("--start-step", "0"))  # a continued run keeps its place on the rate's decay
    dl = torch.utils.data.DataLoader(Stream(train, roots=roots if "--refresh" in a else None, augment="--mirror" in a, late="--late" in a,
                                            rounds="--rounds" in a, own=find_games(opt("--own", "").split(",")) if "--own" in a else (),
                                            own_share=float(opt("--own-share", "0.25"))),
                                     batch_size=int(opt("--batch", "32")), collate_fn=functools.partial(collate, numpy=True),
                                     num_workers=int(opt("--workers", "4")), persistent_workers=int(opt("--workers", "4")) > 0)
    contact_it, contact_share = None, float(opt("--contact-share", "0.0"))
    if "--contact" in a:
        # roadmap item 3 (11-27): the rules army's in-contact orders teach the unit heads only (contact_data.py);
        # every other head keeps learning from player batches
        from contact_data import ContactExamples, held_out_contact, sets_games
        cg = sets_games(opt("--contact", "").split(","))
        ctrain = [x for x in cg if not held_out_contact(x[0])]
        print("contact games: %d train, %d held out; share %.2f" % (len(ctrain), len(cg) - len(ctrain), contact_share),
              flush=True)
        contact_it = iter(torch.utils.data.DataLoader(
            ContactExamples(ctrain), batch_size=int(opt("--batch", "32")), collate_fn=functools.partial(collate, numpy=True),
            num_workers=int(opt("--contact-workers", "2")), persistent_workers=int(opt("--contact-workers", "2")) > 0))
    crng = random.Random(7)
    # --learn-only: these parameter prefixes learn at the full rate, the rest at --rest-lr times it, 0 = frozen
    learn = tuple(filter(None, opt("--learn-only", "").split(",")))
    groups = [{"params": list(model.parameters()), "lr": 3e-4}]
    if learn:
        rest_lr = float(opt("--rest-lr", "0"))
        named = list(model.named_parameters())
        groups = [{"params": [p_ for k, p_ in named if k.startswith(learn)], "lr": 3e-4}]
        rest = [p_ for k, p_ in named if not k.startswith(learn)]
        for p_ in rest:
            p_.requires_grad_(rest_lr > 0)
        if rest_lr > 0:
            groups.append({"params": rest, "lr": 3e-4 * rest_lr})
        print("learning %d tensors (%d weights) at the full rate, %d at x%g" % (
            len(groups[0]["params"]), sum(p_.numel() for p_ in groups[0]["params"]), len(rest), rest_lr), flush=True)
    optim = torch.optim.AdamW(groups, lr=3e-4, weight_decay=0.01)
    if "--constant-lr" in a:  # an open-ended run: warm up, then decay as 1/sqrt(steps) past 5000
        # (11-19: at a held 2e-4 the held-out place error drifted 668 -> 680 -> 701 over 30k steps)
        sched = torch.optim.lr_scheduler.LambdaLR(
            optim, lambda s: min(1.0, (s + 1) / 500) * 0.67 / math.sqrt(max(1.0, (s + start) / 5000.0)))
    else:
        sched = torch.optim.lr_scheduler.OneCycleLR(optim, [g["lr"] for g in groups], total_steps=steps, pct_start=0.05)
    t0, agg = time.time(), {}
    # heads new to a checkpoint learn alone first: their early errors would otherwise reach the trained trunk (11-20:
    # 30 steps of fresh force heads raised the unit act loss 0.06 -> 0.23)
    fresh_steps = int(opt("--fresh-steps", "0"))
    fresh = [p_ for k, p_ in model.named_parameters() if k.startswith(tuple(opt("--fresh-prefix", "f_").split(",")))]
    # workers hand back numpy arrays: on Windows a batch of ~30 tensors through the worker queue cost more than
    # building it (6 workers: 1.9 batches/s as tensors, 3.3 as arrays)
    for step, b in enumerate(dl, 1):
        if contact_it is not None and crng.random() < contact_share:
            b = next(contact_it)   # this step learns from the rules army in contact instead of the player batch
            b = {k: torch.from_numpy(v) for k, v in b.items()}
            loss, parts = losses(model, b, dev)
            parts = {"c_" + k: v for k, v in parts.items()}
        else:
            b = {k: torch.from_numpy(v) for k, v in b.items()}
            loss, parts = losses(model, b, dev)
        optim.zero_grad()
        loss.backward()
        if step <= fresh_steps:
            keep = {id(p_) for p_ in fresh}
            for p_ in model.parameters():
                if id(p_) not in keep:
                    p_.grad = None
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        optim.step()
        sched.step()
        for k, v in parts.items():
            agg[k] = agg.get(k, 0) + v
        if step % 200 == 0 and his_game():
            print("his game is running: paused", flush=True)
            while his_game():
                time.sleep(120)
        if step % 200 == 0:
            print("step %d %.0fs " % (step, time.time() - t0) + " ".join("%s %.3f" % (k, v / 200) for k, v in agg.items()),
                  flush=True)
            agg = {}
        if step % 2000 == 0 or step == steps:
            save_atomic(model.state_dict(), out / "model.pt")
            print("eval", evaluate(model, test, dev), flush=True)
        if save_every and step % save_every == 0:
            save_atomic(model.state_dict(), out / ("model-%06d.pt" % step))
            print("checkpoint", step, flush=True)
        if step >= steps:
            break
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
