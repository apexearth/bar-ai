"""The army model: the side's map grid and its units in, per unit keep-or-new-order, kind and place out."""
import torch
import torch.nn as nn
import torch.nn.functional as F

from data import CHANNELS, E_TOKEN_F, G, N_KIND, SCALARS, STAT_F, TOKEN_F, VALUE_H


def load_widened(model, path, dev, log=print):
    """Load a checkpoint into a model that may have more inputs than it did (map layers into the first
    convolution, unit features into the first unit layer): the old weights kept, the new inputs' weights zero, so
    it plays exactly as before until those inputs are learned."""
    state = torch.load(path, map_location=dev)
    own = model.state_dict()
    for k, v in state.items():
        if k in own and v.dim() in (2, 4) and own[k].shape[1] > v.shape[1] and own[k].shape[0] == v.shape[0]:
            pad = torch.zeros_like(own[k])
            pad[:, :v.shape[1]] = v
            state[k] = pad
            log("init: %s widened %d -> %d inputs" % (k, v.shape[1], own[k].shape[1]))
    missing = [k for k in own if k not in state]
    if missing:
        log("init: %d new parameters start fresh (%s)" % (len(missing), ", ".join(sorted({k.split(".")[0] for k in missing}))))
    unknown = [k for k in state if k not in own]
    if unknown:
        raise KeyError("checkpoint has parameters this model lacks: %s" % unknown[:5])
    model.load_state_dict(state, strict=False)
    return model


def arch_of(path):
    """(d, c, layers) of a checkpoint, read from its weight shapes; the defaults when there is no file."""
    if not path:
        return 128, 64, 3
    state = torch.load(path, map_location="cpu")
    layers = len({k.split(".")[2] for k in state if k.startswith("units.layers.")})
    return state["scal.weight"].shape[0], state["query.weight"].shape[0], layers


def conv(i, o, s=1):
    return nn.Sequential(nn.Conv2d(i, o, 3, s, 1), nn.GroupNorm(8, o), nn.GELU())


class ArmyNet(nn.Module):
    def __init__(self, d=128, c=64, layers=3, heads=4):
        super().__init__()
        self.enc64 = nn.Sequential(conv(CHANNELS, c), conv(c, c))
        self.enc32 = nn.Sequential(conv(c, 2 * c, 2), conv(2 * c, 2 * c))
        self.enc16 = nn.Sequential(conv(2 * c, d, 2), conv(d, d), conv(d, d))
        self.up32 = conv(d + 2 * c, 2 * c)
        self.up64 = conv(2 * c + c, c)
        self.scal = nn.Linear(SCALARS, d)
        self.tok = nn.Sequential(nn.Linear(TOKEN_F, d), nn.GELU(), nn.Linear(d, d))
        self.at_unit = nn.Linear(d + c, d)
        self.map_tokens = nn.Linear(d, d)
        layer = nn.TransformerEncoderLayer(d, heads, 4 * d, 0.1, batch_first=True, norm_first=True)
        self.units = nn.TransformerEncoder(layer, layers)
        self.cross = nn.MultiheadAttention(d, heads, batch_first=True)
        # the enemy units this side sees or remembers (his 11-22: the model must see enemy units and their stats):
        # each enemy token reads the map where it stands, then our units attend to them. A learned "none" token keeps
        # the attention defined with no enemy in view; the output projection starts at zero, so a checkpoint from
        # before this plays exactly as it did until the enemy inputs are learned.
        self.etok = nn.Sequential(nn.Linear(E_TOKEN_F, d), nn.GELU(), nn.Linear(d, d))
        self.at_enemy = nn.Linear(d + c, d)
        self.e_none = nn.Parameter(torch.zeros(1, 1, d))
        self.cross_e = nn.MultiheadAttention(d, heads, batch_first=True)
        nn.init.zeros_(self.cross_e.out_proj.weight)
        nn.init.zeros_(self.cross_e.out_proj.bias)
        # the attack's target (roadmap item 3, 11-27: the AI's fight logic picks which building or unit; the cell head
        # can only name a place): a pointer over the embedded enemy tokens, index 0 = the "none" token; asked only when
        # the kind is attack, learned from the rules army's in-contact attacks (contact_data.py ttgt)
        self.t_query = nn.Linear(d, d)
        self.act = nn.Linear(d, 1)
        self.kind = nn.Linear(d, N_KIND)
        self.query = nn.Linear(d, c)
        self.offset = nn.Sequential(nn.Linear(d + c, d), nn.GELU(), nn.Linear(d, 2))
        # forces (his 11-20: one order per group, as a player clicks it): a force reads its members' mean and the most
        # pressing member (max), then decides click / kind / place / point-or-line and the line's shape, and where it
        # will be in 60 s (the hindsight goal)
        self.f_in = nn.Sequential(nn.Linear(2 * d, d), nn.GELU(), nn.Linear(d, d))
        self.f_act = nn.Linear(d, 1)
        self.f_kind = nn.Linear(d, N_KIND)
        self.f_query = nn.Linear(d, c)
        self.f_goalq = nn.Linear(d, c)
        # the move judge (his 11-25 "let the model propose"): per cell, how the click would score if this force went
        # there (the order's rating against the side's other orders in the same window), so proposals can be ranked
        self.f_judgeq = nn.Linear(d, c)
        self.f_judge_b = nn.Parameter(torch.zeros(1))
        self.f_spread = nn.Linear(d, 1)
        self.f_shape = nn.Linear(d, 3)
        self.f_alive = nn.Linear(d, 1)
        # which members a force's click takes (his 11-22; players' clicks on a force of 10+ in a fight order a median
        # 62% of it): per member, from the member and its force
        self.f_member = nn.Sequential(nn.Linear(2 * d, d), nn.GELU(), nn.Linear(d, 1))
        # how this side does from here (VALUE_H trades and map-share changes, then the result): a label head, the base
        # for crediting a click by what followed it
        self.v_head = nn.Sequential(nn.Linear(2 * d, d), nn.GELU(), nn.Linear(d, 2 * len(VALUE_H) + 1))
        # where the enemy's economy stands now, seen or not (his 11-21: players assume it); a label head
        self.b_eco = nn.Conv2d(c, 1, 1)

    def forces(self, h, u64, force):
        """force: (B, n) member's force index, -1 for none. Returns per force (B, F): its features and heads."""
        B, n, d = h.shape
        nf = int(force.max().item()) + 1 if force.numel() else 0
        nf = max(nf, 1)
        idx = torch.where(force >= 0, force, torch.full_like(force, nf))[..., None].expand(B, n, d)  # nf: no force
        hf = h.float()
        sm = torch.zeros(B, nf + 1, d, device=h.device).scatter_add_(1, idx, hf)
        cnt = torch.zeros(B, nf + 1, 1, device=h.device).scatter_add_(1, idx[..., :1], torch.ones_like(hf[..., :1]))
        mx = torch.full((B, nf + 1, d), -1e4, device=h.device).scatter_reduce_(1, idx, hf, "amax", include_self=True)
        sm, cnt, mx = sm[:, :nf], cnt[:, :nf], mx[:, :nf]
        mean = sm / cnt.clamp(min=1)
        mx = torch.where(cnt > 0, mx, torch.zeros_like(mx))
        fh = self.f_in(torch.cat([mean, mx], -1))
        c = u64.shape[1]
        cells = torch.einsum("bfc,bchw->bfhw", self.f_query(fh), u64).reshape(B, nf, G * G) / c ** 0.5
        goal = torch.einsum("bfc,bchw->bfhw", self.f_goalq(fh), u64).reshape(B, nf, G * G) / c ** 0.5
        judge = torch.einsum("bfc,bchw->bfhw", self.f_judgeq(fh), u64).reshape(B, nf, G * G) / c ** 0.5 + self.f_judge_b
        fh_u = torch.gather(fh, 1, force.clamp(min=0).clamp(max=nf - 1)[..., None].expand(B, n, fh.shape[-1]))
        member = self.f_member(torch.cat([hf, fh_u], -1))[..., 0]
        return {"fh": fh, "act": self.f_act(fh)[..., 0], "kind": self.f_kind(fh), "cells": cells, "goal": goal,
                "judge": judge,
                "member": member,
                "spread": self.f_spread(fh)[..., 0], "shape": self.f_shape(fh), "alive": self.f_alive(fh)[..., 0],
                "present": cnt[..., 0] > 0}

    def enemies(self, h, u64, etok, emask):
        """Our unit states h attend to the enemy tokens (B, m, E_TOKEN_F) with mask (B, m); the "none" token first."""
        B = h.shape[0]
        exy = etok[:, :, STAT_F + 8:STAT_F + 10] * 2 - 1
        ehere = F.grid_sample(u64, exy[:, :, None, :], align_corners=False)[:, :, :, 0].transpose(1, 2)
        e = self.at_enemy(torch.cat([self.etok(etok), ehere], -1))
        e = torch.cat([self.e_none.expand(B, 1, -1).to(e.dtype), e], 1)
        em = torch.cat([torch.ones(B, 1, dtype=torch.bool, device=emask.device), emask], 1)
        return h + self.cross_e(h, e, e, key_padding_mask=~em, need_weights=False)[0], e, em

    def forward(self, grid, scal, tok, mask, etok=None, emask=None):
        B = grid.shape[0]
        f64 = self.enc64(grid)
        f32 = self.enc32(f64)
        f16 = self.enc16(f32) + self.scal(scal)[:, :, None, None]
        u32 = self.up32(torch.cat([F.interpolate(f16, scale_factor=2), f32], 1))
        u64 = self.up64(torch.cat([F.interpolate(u32, scale_factor=2), f64], 1))
        # each unit reads the map where it stands
        xy = tok[:, :, 10:12] * 2 - 1
        here = F.grid_sample(u64, xy[:, :, None, :], align_corners=False)[:, :, :, 0].transpose(1, 2)
        h = self.at_unit(torch.cat([self.tok(tok), here], -1))
        h = self.units(h, src_key_padding_mask=~mask)
        mt = self.map_tokens(f16.flatten(2).transpose(1, 2))
        h = h + self.cross(h, mt, mt, need_weights=False)[0]
        tgt = None
        if etok is not None and emask is not None:
            h, e, em = self.enemies(h, u64, etok, emask)
            tgt = torch.einsum("bnd,bmd->bnm", self.t_query(h), e) / h.shape[-1] ** 0.5
            tgt = tgt.masked_fill(~em[:, None, :], -1e4)
        q = self.query(h)
        cells = torch.einsum("bnc,bchw->bnhw", q, u64).reshape(B, q.shape[1], G * G) / q.shape[-1] ** 0.5
        mk = mask[..., None].to(h.dtype)
        pooled = torch.cat([(h * mk).sum(1) / mk.sum(1).clamp(min=1), mt.mean(1)], -1)
        out = {"h": h, "act": self.act(h)[..., 0], "kind": self.kind(h), "cells": cells, "u64": u64,
               "value": self.v_head(pooled), "b_eco": self.b_eco(u64)[:, 0]}
        if tgt is not None:
            out["tgt"] = tgt   # (B, n units, 1 + m enemy tokens); index 0 is "none"
        return out

    def offset_at(self, h, u64, cell):
        B, n = cell.shape
        flat = u64.flatten(2).transpose(1, 2)
        feat = torch.gather(flat, 1, cell.clamp(min=0)[..., None].expand(B, n, flat.shape[-1]))
        return torch.sigmoid(self.offset(torch.cat([h, feat], -1)))
