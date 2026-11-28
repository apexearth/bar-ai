"""A narrower army model started from a trained one (his 11-24: "the best model we can ... run on most consumer
hardware"): every tensor whose shape shrinks keeps the trained one's leading slice, the rest copied whole. The map path
at c=48 instead of 96 halves one-thread CPU time per decision (11-24: 77 -> 40 ms); training then recovers the rest.

    python tools/armynet/slim_init.py <trained.pt> <out.pt> --c 48 [--d D --layers L]
"""
import sys

import torch

from model import ArmyNet, arch_of

a = sys.argv[1:]
src, out = a[0], a[1]


def opt(k, default):
    return int(a[a.index(k) + 1]) if k in a else default


d0, c0, l0 = arch_of(src)
d, c, layers = opt("--d", d0), opt("--c", c0), opt("--layers", l0)
state = torch.load(src, map_location="cpu")
own = ArmyNet(d, c, layers).state_dict()
sliced = 0
for k, v in own.items():
    if k not in state:
        continue
    w = state[k]
    if w.shape != v.shape:
        if w.dim() != v.dim() or any(s < t for s, t in zip(w.shape, v.shape)):
            continue
        w = w[tuple(slice(0, t) for t in v.shape)].clone()
        sliced += 1
    own[k] = w
torch.save(own, out)
print("arch %d,%d,%d -> %d,%d,%d: %d tensors sliced, wrote %s" % (d0, c0, l0, d, c, layers, sliced, out))
