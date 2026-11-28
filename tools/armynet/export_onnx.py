#!/usr/bin/env python3
"""Export an army model to ONNX, so it runs with no PyTorch (his 11-24: easy for anyone who downloads it, CPU is fine).

    python tools/armynet/export_onnx.py <model.pt> <out_dir> [--check <dataset.npz>]

Writes main.onnx (the step's forward), forces.onnx (the force heads) and offset.onnx (the offset head). --check runs
one live example through both and prints the largest difference per output, and the CPU time of each.
"""
import sys
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

sys.path.insert(0, str(Path(__file__).resolve().parent))
from model import ArmyNet, arch_of, load_widened  # noqa: E402

MAIN_OUT = ["h", "act", "kind", "cells", "u64", "value", "b_eco"]
FORCE_OUT = ["fh", "act", "kind", "cells", "goal", "member", "spread", "shape", "alive", "present"]


class Main(nn.Module):
    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, grid, scal, tok, mask, etok, emask):
        o = self.m(grid, scal, tok, mask, etok, emask)
        return tuple(o[k] for k in MAIN_OUT)


class Forces(nn.Module):
    """force (B, n) indices; slots (B, nf) zeros whose width is the number of forces (a traced shape, not a value)."""

    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, h, u64, force, slots):
        B, n, d = h.shape
        nf = slots.shape[1]
        m = self.m
        hf = h.float()
        # the scatter form crashes the exporter; a one-hot membership gives the same sums and maxima
        ar = torch.cumsum(torch.ones_like(slots), 1) - 1  # (B, nf): 0..nf-1
        oh = (force[:, :, None].float() == ar[:, None, :]).float()  # (B, n, nf)
        sm = torch.matmul(oh.transpose(1, 2), hf)
        cnt = oh.sum(1)[..., None]
        mx = (hf[:, :, None, :] * oh[..., None] + (oh[..., None] - 1) * 1e4).amax(1)
        mean = sm / cnt.clamp(min=1)
        mx = torch.where(cnt > 0, mx, torch.zeros_like(mx))
        fh = m.f_in(torch.cat([mean, mx], -1))
        c = u64.shape[1]
        g2 = u64.shape[2] * u64.shape[3]
        cells = torch.einsum("bfc,bchw->bfhw", m.f_query(fh), u64).reshape(B, nf, g2) / c ** 0.5
        goal = torch.einsum("bfc,bchw->bfhw", m.f_goalq(fh), u64).reshape(B, nf, g2) / c ** 0.5
        fi = torch.minimum(force.clamp(min=0), torch.full_like(force, nf - 1))
        fh_u = torch.gather(fh, 1, fi[..., None].expand(B, n, fh.shape[-1]))
        member = m.f_member(torch.cat([hf, fh_u], -1))[..., 0]
        extra = ()
        if hasattr(m, "f_judgeq"):  # the move judge, when the model has one (older graphs stay as they were)
            extra = (torch.einsum("bfc,bchw->bfhw", m.f_judgeq(fh), u64).reshape(B, nf, g2) / c ** 0.5 + m.f_judge_b,)
        return (fh, m.f_act(fh)[..., 0], m.f_kind(fh), cells, goal, member, m.f_spread(fh)[..., 0], m.f_shape(fh),
                m.f_alive(fh)[..., 0], cnt[..., 0] > 0) + extra


class Offset(nn.Module):
    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, h, u64, cell):
        return self.m.offset_at(h, u64, cell)


def example_inputs(npz, minute=18.0):
    """One live step's model inputs from a dataset, built as serve.py builds them."""
    from data import RECENT_S, STEP, Game, collate, fold_history, history_rows
    z = np.load(npz)
    u = z["units"]
    team = int(z["teams"][0][0])
    f = int(minute * 1800) // STEP * STEP
    sd = np.array(sorted(int(r[0]) for r in z["defs"] if int(r[1]) == 0), np.int64)
    store = fold_history({}, u[u[:, 0] < f - RECENT_S * 30], len(z["allies"]))
    hist = history_rows(store, u[(u[:, 0] <= f) & (u[:, 0] >= f - RECENT_S * 30)], f, sd)
    g = Game.live(hist, z["defs"], z["map"], z["allies"], z["teams"], z["spots"], z["heights"],
                  orders=z["decisions"][z["decisions"][:, 0] < f], task_starts=None,
                  hits=z["hits"] if "hits" in z.files else None)
    b = collate([g.example(team, f)])
    return tuple(b[k] for k in ("grid", "scal", "tok", "mask", "etok", "emask"))


def main(a):
    src, out = a[0], Path(a[1])
    out.mkdir(parents=True, exist_ok=True)
    m = ArmyNet(*arch_of(src))
    load_widened(m, src, "cpu", log=lambda *_: None)
    m.eval()
    for mod in m.modules():
        if isinstance(mod, nn.TransformerEncoder):
            mod.enable_nested_tensor = False
    torch.backends.mha.set_fastpath_enabled(False)
    inp = example_inputs(a[a.index("--check") + 1])
    with torch.no_grad():
        o = m(*inp)
        n = inp[2].shape[1]
        force = torch.tensor([[i % 3 if i % 4 else -1 for i in range(n)]])
        slots = torch.zeros(1, 3)
        cell = torch.zeros(1, n, dtype=torch.long)
        # the older tracer bakes the unit count into the attention's reshapes; the export tracer keeps it a symbol
        Dn, Dk = torch.export.Dim("n", min=2, max=4096), torch.export.Dim("k", min=2, max=4096)
        torch.onnx.export(Main(m), inp, out / "main.onnx", opset_version=18, input_names=
                          ["grid", "scal", "tok", "mask", "etok", "emask"], output_names=MAIN_OUT,
                          dynamic_shapes=(None, None, {1: Dn}, {1: Dn}, {1: Dk}, {1: Dk}),
                          dynamo=True, optimize=True)
        torch.onnx.export(Forces(m), (o["h"], o["u64"], force, slots), out / "forces.onnx", opset_version=18,
                          input_names=["h", "u64", "force", "slots"], output_names=FORCE_OUT + (["judge"] if hasattr(m, "f_judgeq") else []),
                          dynamic_axes={"h": {1: "n"}, "force": {1: "n"}, "slots": {1: "nf"}, "member": {1: "n"},
                                        **{k: {1: "nf"} for k in FORCE_OUT + ["judge"] if k != "member"}}, dynamo=False)
        torch.onnx.export(Offset(m), (o["h"], o["u64"], cell), out / "offset.onnx", opset_version=18,
                          input_names=["h", "u64", "cell"], output_names=["offset"],
                          dynamic_axes={"h": {1: "n"}, "cell": {1: "n"}, "offset": {1: "n"}}, dynamo=False)
    import json
    (out / "meta.json").write_text(json.dumps({
        "source": str(Path(src).resolve()),
        "has_member": any(k.startswith("f_member.") for k in torch.load(src, map_location="cpu"))}))
    print("wrote", ", ".join(str(p) for p in sorted(out.glob("*.onnx"))))

    import onnxruntime as ort
    so = ort.SessionOptions()
    so.intra_op_num_threads = 2
    sess = {k: ort.InferenceSession(str(out / (k + ".onnx")), so, providers=["CPUExecutionProvider"])
            for k in ("main", "forces", "offset")}
    # the reference from a fresh load: exporting leaves the exported module's state changed
    m = ArmyNet(*arch_of(src))
    load_widened(m, src, "cpu", log=lambda *_: None)
    m.eval()
    # a second, different size: the dynamic axes must really be dynamic
    for scale in (1, 2):
        ii = list(inp)
        if scale == 2:
            ii[2] = torch.cat([ii[2], ii[2]], 1)
            ii[3] = torch.cat([ii[3], ii[3]], 1)
        with torch.no_grad():
            o = m(*ii)
            nn_ = ii[2].shape[1]
            force = torch.tensor([[i % 5 if i % 4 else -1 for i in range(nn_)]])
            slots = torch.zeros(1, int(force.max()) + 1)  # as many slots as forces used (7 units used only 4 of 5)
            fo = Forces(m)(o["h"], o["u64"], force, slots)
            ref_f = m.forces(o["h"], o["u64"], force)
            cell = o["cells"][0].argmax(-1)[None]
            off = m.offset_at(o["h"], o["u64"], cell)
        t0 = time.perf_counter()
        r = sess["main"].run(None, {k: v.numpy() for k, v in zip(["grid", "scal", "tok", "mask", "etok", "emask"], ii)})
        t1 = time.perf_counter()
        rf = sess["forces"].run(None, {"h": r[0], "u64": r[4], "force": force.numpy(), "slots": slots.numpy()})
        t2 = time.perf_counter()
        ro = sess["offset"].run(None, {"h": r[0], "u64": r[4], "cell": cell.numpy()})[0]
        t3 = time.perf_counter()
        dm = {k: float(np.abs(r[i] - o[k].numpy()).max()) for i, k in enumerate(MAIN_OUT)}
        df = {k: float(np.abs(rf[i].astype(np.float32) - fo[i].float().numpy()).max()) for i, k in enumerate(FORCE_OUT + (["judge"] if hasattr(m, "f_judgeq") else []))}
        dr = {k: float(np.abs(fo[i].float().numpy() - ref_f[k].float().numpy()).max()) for i, k in enumerate(FORCE_OUT + (["judge"] if hasattr(m, "f_judgeq") else []))}
        print("units %d: main max diff %s" % (nn_, {k: round(v, 5) for k, v in dm.items()}))
        print("  forces (onnx vs export wrapper) %s" % {k: round(v, 5) for k, v in df.items()})
        print("  forces (export wrapper vs model.forces) %s" % {k: round(v, 5) for k, v in dr.items()})
        print("  offset %.5f | cpu ms main %.1f forces %.1f offset %.1f" % (
            float(np.abs(ro - off.numpy()).max()), 1000 * (t1 - t0), 1000 * (t2 - t1), 1000 * (t3 - t2)))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
