#!/usr/bin/env python3
"""Train/play parity: the same moment of a recorded game through the training path (Game.example on the .npz) and
through the live path serve.py uses (Game.live on the units seen so far, our team as its own holder), compared
input by input and prediction by prediction.

    python tools/armynet/parity.py [--model model.pt] [--games 3]

Only frames on the 10 s grid are compared: recordings sample buildings every 10 s, the live state every second.
"""
import glob
import sys
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from data import ABSENT_ON, CHANNELS, RECENT_S, Game, absence_ctx, absent_of, collate, fold_history, history_rows  # noqa: E402
from model import ArmyNet, arch_of, load_widened  # noqa: E402


def main(a):
    def opt(name, default):
        return a[a.index(name) + 1] if name in a else default
    paths = [x for x in a if x.endswith(".npz")] or \
        sorted(glob.glob("G:/bar-ai-archive/public-replays/recordings/*/*.npz"))[:int(opt("--games", "3"))]
    model = None
    if "--model" in a:
        model = ArmyNet(*arch_of(opt("--model", "")))
        load_widened(model, opt("--model", ""), "cpu")
        model.eval()
    for p in paths:
        z = np.load(p)
        g = Game(p)
        frames = sorted({f for t, f in g.examples if f % 300 == 0 and f > 3 * 1800})
        frames = frames[::max(1, len(frames) // 6)][:6]  # spread over the game: memory differs late, not early
        teams = sorted({t for t, f in g.examples})
        for f in frames:
            t = teams[0]
            a_ex = g.example(t, f)
            u = z["units"]
            # as serve.py keeps it: every sample of the last RECENT_S, older ones folded (data.fold_history)
            static_defs = np.array(sorted(int(r[0]) for r in z["defs"] if int(r[1]) == 0), np.int64)
            uu = u[u[:, 0] <= f]
            uu = uu[np.argsort(uu[:, 0], kind="stable")]
            actx = absence_ctx(z["defs"], z["teams"], z["allies"]) if ABSENT_ON else None
            store = {}
            old = uu[uu[:, 0] < f - RECENT_S * 30]
            # serve folds a step at a time: fold the old rows in the same steps, so the marks see what serve sees
            for fo in np.unique(old[:, 0] // 300):
                fold_history(store, old[old[:, 0] // 300 == fo], len(z["allies"]), actx)
            hist = history_rows(store, uu[uu[:, 0] >= f - RECENT_S * 30], f, static_defs)
            live = Game.live(hist, z["defs"], z["map"], z["allies"], z["teams"], z["spots"], z["heights"],
                             orders=z["decisions"], task_starts=z["task_starts"] if "task_starts" in z.files else None,
                             hits=z["hits"] if "hits" in z.files else None,
                             names=z["def_names"] if "def_names" in z.files else None, absent=absent_of(store))
            b_ex = live.example(t, f)
            diffs = [c for c in range(CHANNELS) if not np.allclose(a_ex["grid"][c], b_ex["grid"][c], atol=1e-4)]
            same_tok = a_ex["tok"].shape == b_ex["tok"].shape and np.allclose(a_ex["tok"], b_ex["tok"], atol=1e-4)
            ea, eb = a_ex.get("etok", np.zeros((0, 1))), b_ex.get("etok", np.zeros((0, 1)))
            same_e = ea.shape == eb.shape and np.allclose(ea, eb, atol=1e-4)
            same_force = np.array_equal(a_ex.get("force", []), b_ex.get("force", []))
            line = "%s f=%d grid channels differing %s tokens %s" % (Path(p).stem[:28], f, diffs or "none",
                                                                  "same" if same_tok else "DIFFER")
            line += " enemies %s (%d vs %d)" % ("same" if same_e else "DIFFER", len(ea), len(eb))
            line += " forces %s" % ("same" if same_force else "DIFFER")
            if model is not None and len(a_ex["tok"]) and len(b_ex["tok"]):
                with torch.no_grad():
                    oa = model(*[collate([a_ex])[k] for k in ("grid", "scal", "tok", "mask", "etok", "emask")])
                    ob = model(*[collate([b_ex])[k] for k in ("grid", "scal", "tok", "mask", "etok", "emask")])
                line += " | act max diff %.4f, same best cell %.0f%%" % (
                    float((torch.sigmoid(oa["act"]) - torch.sigmoid(ob["act"])).abs().max()),
                    100 * float((oa["cells"].argmax(-1) == ob["cells"].argmax(-1)).float().mean()))
            print(line, flush=True)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
