"""The army model behind one interface, run by PyTorch (a .pt checkpoint) or by ONNX Runtime (a folder from
export_onnx.py: no PyTorch needed, his 11-24 "easy for anyone ... even if it was on a CPU"). Everything in and out is
numpy, so serve.py does not import torch on the ONNX path.
"""
import json
from pathlib import Path

import numpy as np

MAIN_IN = ["grid", "scal", "tok", "mask", "etok", "emask"]
MAIN_OUT = ["h", "act", "kind", "cells", "u64", "value", "b_eco"]
FORCE_OUT = ["fh", "act", "kind", "cells", "goal", "member", "spread", "shape", "alive", "present"]


def softmax(x, axis=-1):
    x = np.asarray(x, np.float64)
    e = np.exp(x - x.max(axis, keepdims=True))
    return (e / e.sum(axis, keepdims=True)).astype(np.float32)


def sigmoid(x):
    return (1.0 / (1.0 + np.exp(-np.asarray(x, np.float64)))).astype(np.float32)


class TorchNet:
    def __init__(self, path, dev, threads):
        import torch
        from model import ArmyNet, arch_of, load_widened
        self.torch = torch
        if dev == "cpu":
            torch.set_num_threads(threads)
        self.dev = dev
        self.model = ArmyNet(*arch_of(path)).to(dev)
        load_widened(self.model, path, dev)
        self.model.eval()
        self.has_member = bool(path) and any(k.startswith("f_member.") for k in torch.load(path, map_location="cpu"))
        self.name = "torch " + dev

    def _t(self, x):
        return self.torch.from_numpy(np.ascontiguousarray(x)).to(self.dev)

    def _n(self, d):
        return {k: v.float().cpu().numpy() if v.is_floating_point() else v.cpu().numpy() for k, v in d.items()}

    def step(self, b):
        with self.torch.no_grad():
            o = self.model(*[self._t(b[k]) for k in MAIN_IN])
        return self._n({k: o[k] for k in MAIN_OUT + (["tgt"] if "tgt" in o else [])})

    def forces(self, h, u64, force):
        with self.torch.no_grad():
            return self._n(self.model.forces(self._t(h), self._t(u64), self._t(force.astype(np.int64))))

    def offset_at(self, h, u64, cell):
        with self.torch.no_grad():
            return self.model.offset_at(self._t(h), self._t(u64), self._t(cell.astype(np.int64))).float().cpu().numpy()


class OnnxNet:
    def __init__(self, folder, threads):
        import onnxruntime as ort
        so = ort.SessionOptions()
        so.intra_op_num_threads = threads
        so.inter_op_num_threads = 1
        # idle worker threads spin by default: eight servers beside a game burned the cores it needed
        so.add_session_config_entry("session.intra_op.allow_spinning", "0")
        prov = ["CPUExecutionProvider"]
        folder = Path(folder)
        self.s = {k: ort.InferenceSession(str(folder / (k + ".onnx")), so, providers=prov)
                  for k in ("main", "forces", "offset")}
        meta = json.loads((folder / "meta.json").read_text()) if (folder / "meta.json").exists() else {}
        self.has_member = bool(meta.get("has_member", True))
        self.name = "onnx cpu x%d" % threads
        # a graph exported before inputs were added reads only its leading ones (a widened load's new weights are zero)
        self.n_scal = int(self.s["main"].get_inputs()[MAIN_IN.index("scal")].shape[-1])

    def step(self, b):
        b = dict(b, scal=b["scal"][..., :self.n_scal])
        r = self.s["main"].run(None, {k: np.ascontiguousarray(b[k]) for k in MAIN_IN})
        return dict(zip(MAIN_OUT, r))

    def forces(self, h, u64, force):
        force = force.astype(np.int64)
        nf = max(int(force.max()) + 1 if force.size else 0, 1)
        r = self.s["forces"].run(None, {"h": h, "u64": u64, "force": force, "slots": np.zeros((1, nf), np.float32)})
        return dict(zip([o.name for o in self.s["forces"].get_outputs()], r))

    def offset_at(self, h, u64, cell):
        return self.s["offset"].run(None, {"h": np.ascontiguousarray(h, np.float32), "u64": u64,
                                           "cell": cell.astype(np.int64)})[0]


def load(path, cpu=False, threads=2):
    """A folder (or a .onnx file's folder) runs on ONNX Runtime; a .pt on PyTorch, the GPU when there is one."""
    p = Path(path)
    if p.is_dir() or p.suffix == ".onnx":
        return OnnxNet(p if p.is_dir() else p.parent, threads)
    import torch
    dev = "cpu" if cpu else ("cuda" if torch.cuda.is_available() else "cpu")
    return TorchNet(path, dev, threads)
