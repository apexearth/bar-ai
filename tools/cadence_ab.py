"""A/B the builder re-think cadence vs NullAI: idle gap, economy, frame cost.

    python tools/cadence_ab.py --name fast1 [--rounds 2] [--b apex_idle_settle_f=5 ...]

Arm A plays the defaults, arm B the --b overrides, half the slots each on one
shared cell per round (tools/ecoclimb.py's harness and score). Reads, per arm:
ln(economy) at 8-20 min, `apex: idlegap` (frames from idle to a real task),
and `apex: perf AiFrame avgUs` / `AiMakeTask avgUs` from apex_perf=1.
"""
import argparse
import json
import math
import random
import re
import statistics as stx
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import ecoclimb as ec  # noqa: E402

GAP = re.compile(r"apex: idlegap n=(\d+) meanF=([\d.]+) p50F=(\d+) p90F=(\d+) maxF=(\d+) refused=(\d+)")
PERF = re.compile(r"apex: perf (\w+) calls=\d+ totalMs=[\d.]+ avgUs=(\d+) maxMs=([\d.]+)")


def read_logs(out: Path):
    txt = (out / "stdout.txt").read_text("utf-8", errors="replace") if (out / "stdout.txt").exists() else ""
    gaps = [(int(n), float(m), int(p50), int(p90)) for n, m, p50, p90, mx, rf in GAP.findall(txt)]
    perf = {}
    for sec, avg, mx in PERF.findall(txt):
        perf.setdefault(sec, []).append((int(avg), float(mx)))
    return gaps, perf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--rounds", type=int, default=2)
    ap.add_argument("--b", nargs="+", default=["apex_idle_settle_f=5", "apex_idle_ask_f=5", "apex_redecide_s=0.5"])
    ap.add_argument("--parallel", type=int, default=8)
    ap.add_argument("--minutes", type=int, default=21)
    ap.add_argument("--speed", type=int, default=5)
    ap.add_argument("--spec", default="")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--map", default=ec.MAP)
    ap.add_argument("--opponent", default=ec.OPPONENT)
    ap.add_argument("--handicaps", type=int, nargs="+", default=list(ec.HANDICAPS))
    ap.add_argument("--check-min", dest="check_min", type=int, nargs="+", default=list(ec.CHECK_MIN))
    ap.add_argument("--real", action="store_true", help="a real game: commander death ends it")
    args = ap.parse_args()
    args.neverend = not args.real
    spec = ec.spec_of(args)
    d = ec.ROOT / "tournaments" / f"cadence-{args.name}"
    (d / "games").mkdir(parents=True, exist_ok=True)
    base = {"apex_perf": 1}
    over = dict(kv.split("=", 1) for kv in args.b)
    arms = {"A": dict(base), "B": {**base, **over}}
    h = args.parallel // 2
    cfgs = [arms["A"]] * h + [arms["B"]] * (args.parallel - h)
    kinds = ["A"] * h + ["B"] * (args.parallel - h)
    rng = random.Random(args.seed)
    res = {"A": [], "B": []}
    blocks = []
    for r in range(args.rounds):
        pairs = ec.play_round(spec, cfgs, rng, args, d / "games", f"r{r}")
        ys = {"A": [], "B": []}
        for i, g in pairs:
            gaps, perf = read_logs(d / "games" / g["game"])
            res[kinds[i]].append({"y": g["y"], "eco": g["eco"], "gaps": gaps, "perf": perf,
                                  "mex": g["mex"], "t2": g["t2"],
                                  "won": 0 in g["winners"], "lost": 1 in g["winners"]})
            ys[kinds[i]].append(g["y"])
        blocks.append((ys["B"], ys["A"]))
    (d / "result.json").write_text(json.dumps({"arms": arms, "res": res}), "utf-8")
    m, se = ec.blocked_gap(blocks)
    print(f"\nB vs A economy: {m:+.3f} (x{math.exp(m):.3f}) se {se:.3f} t {m / se if se else 0:.2f}")
    for arm in ("A", "B"):
        rs = res[arm]
        if not rs:
            continue
        allg = [g for x in rs for g in x["gaps"]]
        wn = sum(n for n, *_ in allg) or 1
        p50 = sum(n * p for n, _, p, _ in allg) / wn
        p90 = sum(n * p for n, _, _, p in allg) / wn
        mean = sum(n * mm for n, mm, _, _ in allg) / wn
        line = f"{arm} {json.dumps(arms[arm])}: n={len(rs)} ln eco {stx.mean(x['y'] for x in rs):.3f}  " \
               f"idle gap mean {mean:.0f}F p50 {p50:.0f}F p90 {p90:.0f}F"
        mex = [stx.mean(x["mex"][k] for x in rs) for k in range(len(args.check_min))]
        line += "  mex@" + "/".join(str(m) for m in args.check_min) + " " + "/".join(f"{v:.1f}" for v in mex)
        line += f"  W{sum(x['won'] for x in rs)} L{sum(x['lost'] for x in rs)}"
        for sec in ("AiFrame", "AiMakeTask"):
            v = [a for x in rs for a, _ in x["perf"].get(sec, [])[10:]]
            mx = [b for x in rs for _, b in x["perf"].get(sec, [])[10:]]
            if v:
                line += f"  {sec} avgUs {stx.mean(v):.0f} maxMs {max(mx):.1f}"
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
