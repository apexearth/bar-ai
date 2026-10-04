"""Learn the economy's valuation weights: perturb, regress, climb, confirm.

    python tools/ecoclimb.py noise --name eco2            # 2 rounds of identical configs
    python tools/ecoclimb.py run   --name eco2 [--rounds 60]
    python tools/ecoclimb.py read  --name eco2            # model, steps, incumbent
    python tools/ecoclimb.py validate --name eco2         # incumbent vs defaults, real games

Inner loop: our full AI (army obligation and all) vs NullAI on Comet Catcher
Remake 1v1, deathmode=neverend so every game runs to minute 20. Self-play cannot
rank build orders: identical configs read a pair sd of 0.44 in ln(economy)
because the first fight snowballs. Score of one game: the mean over minutes
8/12/16/20 of ln(eco), eco = (metal income - converter metal) + energy income/60.

A ROUND is --parallel games on one cell (handicap 0/50/100, mirror faction,
seed), so cell and machine load cancel inside it. EXPLORE rounds play the
incumbent twice and the rest as perturbations: most move several knobs by
+-step (a design the regression can separate), some are far OFF-SHOOTS. After
each round a ridge regression of y on knob position, within round, estimates
each knob's slope. Every --climb-every rounds the climber proposes either a step
along the slopes that clear |t| >= --model-t or the best recent off-shoot, and
plays it head-to-head with the incumbent for --confirm rounds; it is accepted
only at t >= --accept-t. Confirm games feed the model too.

Values reach the AI as per-AI options; `apex: tunable-opt` logs each first read.
State in tournaments/ecoclimb-<name>/, resumable.
"""
import argparse
import glob
import json
import math
import os
import random
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import lane as _lane  # noqa: E402

# name: (default, lo, hi, log-scale)
PARAMS = {
    # gain side and horizons
    "apex_payback_h":            (900.0, 300.0, 2700.0, True),
    "apex_energy_growth":        (8.0,   2.0,   24.0,   True),
    "apex_mex_growth":           (8.0,   2.0,   24.0,   True),
    "apex_mexup_boost":          (1.0,   0.5,   2.0,    True),
    "apex_conv_horizon":         (300.0, 100.0, 900.0,  True),
    "apex_e_waste_worth":        (0.25,  0.05,  0.75,   True),
    "apex_m_waste_worth":        (0.25,  0.05,  0.75,   True),
    "apex_pipe_latency_h":       (60.0,  20.0,  180.0,  True),
    "apex_tech_pipe":            (2.0,   0.7,   6.0,    True),
    "apex_plant_pipe":           (2.0,   0.7,   6.0,    True),
    "apex_plant_income_per":     (50.0,  20.0,  150.0,  True),
    "apex_spot_m":               (2.0,   0.7,   6.0,    True),
    # cost side: ValueOf term weights
    "apex_vw_walk":              (1.0,   0.25,  4.0,    True),
    "apex_vw_build":             (1.0,   0.25,  4.0,    True),
    "apex_vw_disp":              (1.0,   0.25,  4.0,    True),
    "apex_vw_late":              (1.0,   0.25,  4.0,    True),
    "apex_vw_flow":              (1.0,   0.25,  4.0,    True),
    "apex_vw_ecost":             (1.0,   0.25,  4.0,    True),
    "apex_vw_feed_bank":         (0.5,   0.0,   1.0,    False),
    "apex_vw_mcs_from":          (0.35,  0.1,   0.7,    False),
    "apex_vw_mcs_span":          (0.45,  0.1,   0.8,    False),
    "apex_vw_mcs_depth":         (0.8,   0.0,   0.95,   False),
    "apex_space_m":              (1.0,   0.3,   3.0,    True),
    "apex_lockup":               (0.5,   0.1,   1.5,    True),
    # energy price
    "apex_e_headroom":           (1.75,  1.15,  3.0,    True),
    "apex_e_lookahead":          (30.0,  10.0,  90.0,   True),
    "apex_e_response":           (45.0,  15.0,  135.0,  True),
    # the draw
    "apex_draw_sharp":           (2.0,   0.5,   6.0,    True),
    "apex_commit_sharp":         (12.0,  3.0,   36.0,   True),
    # hands and build power
    "apex_assist_share":         (0.5,   0.2,   1.0,    True),
    "apex_bp_headroom":          (1.0,   0.5,   2.0,    True),
    "apex_bp_lookahead":         (60.0,  20.0,  180.0,  True),
    "apex_con_base":             (2.7,   1.0,   6.0,    True),
    "apex_con_per_m":            (44.0,  15.0,  130.0,  True),
    "apex_con_feed_headroom":    (1.5,   0.75,  3.0,    True),
    "apex_request_drain":        (7.0,   3.0,   15.0,   True),
    "apex_site_cost_per_worker": (300.0, 100.0, 900.0,  True),
    "apex_join_min_m":           (500.0, 150.0, 1500.0, True),
    "apex_dup_bank":             (1.0,   0.3,   3.0,    True),
    "apex_mobile_bp_eff":        (0.6,   0.3,   1.0,    True),
    "apex_nano_sink_m":          (1000., 300.0, 3000.0, True),
    "apex_t2_con_per_m":         (25.0,  10.0,  60.0,   True),
    # tech and big energy
    "apex_t2_metal":             (30.0,  12.0,  60.0,   True),
    "apex_t2_energy":            (1200., 400.0, 2400.0, True),
    "apex_fusion_min_energy":    (1000., 400.0, 2500.0, True),
    "apex_obsolete_ratio":       (4.0,   2.0,   8.0,    True),
}
KEYS = sorted(PARAMS)
MAP = "Comet Catcher Remake"
OPPONENT = "NullAI:0.1"
HANDICAPS = (0, 50, 100)
FACTIONS = ("Armada", "Cortex")
CHECK_MIN = (8, 12, 16, 20)
OPT_RE = re.compile(r"apex: tunable-opt t=(\d+) (apex_\w+)=")


def to_u(name, v):
    d, lo, hi, lg = PARAMS[name]
    return (math.log(max(v, 1e-9) / lo) / math.log(hi / lo)) if lg else (v - lo) / (hi - lo)


def from_u(name, u):
    d, lo, hi, lg = PARAMS[name]
    u = min(1.0, max(0.0, u))
    v = lo * (hi / lo) ** u if lg else lo + u * (hi - lo)
    return float(f"{v:.4g}")


def defaults():
    return {k: PARAMS[k][0] for k in KEYS}


def reflect(u):
    while u < 0 or u > 1:
        u = -u if u < 0 else 2 - u
    return u


def move(cfg, du: dict):
    out = dict(cfg)
    for k, d in du.items():
        out[k] = from_u(k, reflect(to_u(k, cfg[k]) + d))
    return out


def uvec(cfg):
    return [to_u(k, cfg[k]) for k in KEYS]


def diff(a, b):
    return {k: (b[k], a[k]) for k in KEYS if a[k] != b[k]}


def fmt_changes(ch):
    return ", ".join(f"{k[5:]} {old:g}->{new:g}" for k, (old, new) in ch.items())


def his_game_running():
    try:
        out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq spring.exe", "/NH"],
                             capture_output=True, text=True, timeout=20).stdout
    except Exception:
        return False
    return "spring.exe" in out.lower()


def launch(spec, cfg, seed, handicap, faction, args, out, slot):
    wdir = ROOT / "matches" / f"_engine_eco{slot}"
    for rec in glob.glob(str(wdir / "AI" / "Skirmish" / "**" / "apex-record.txt"), recursive=True):
        os.remove(rec)
    cmd = [sys.executable, "-u", str(HERE / "run_match.py"),
           "--a", spec, "--b", getattr(args, "opponent", OPPONENT), "--map", getattr(args, "map", MAP),
           "--minutes", str(args.minutes),
           "--sides", f"{faction},{faction}", "--handicap", str(handicap),
           "--speed", str(args.speed), "--seed", str(seed), "--out", str(out),
           "--write-dir", str(wdir), "--modoption", "dev_stats=1"]
    if getattr(args, "neverend", True):
        cmd += [
           "--modoption", "deathmode=neverend"]
    # Eight engines on one machine fall behind the asked speed late in a big game, and the
    # lag ladder reads that as host lag and starves the elections (worst wait 70-150 s).
    for k, v in {"apex_lag_speed": 0, **cfg}.items():
        cmd += ["--ai-option", f"{k}={v}"]
    log = open(f"{out}.log", "w")
    return subprocess.Popen(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT), log


def eco_of(row):
    return max(0.0, row.get("mInc", 0.0) - row.get("mMakeConv", 0.0)) + row.get("eInc", 0.0) / 60.0


def at_minute(stats, minute):
    rows = [r for r in stats if int(r.get("ally", -1)) == 0 and r.get("reason") == "periodic"
            and abs(r.get("frame", 0) - minute * 1800) < 300]
    return rows[0] if rows else None


def score_game(outdir: Path, mins=CHECK_MIN):
    try:
        r = json.loads((outdir / "result.json").read_text("utf-8"))
    except Exception:
        return None
    res = r.get("result", {})
    if not res.get("valid", False) or res.get("crashed") or res.get("ai_errors"):
        return None
    stats = r.get("stats") or []
    ecos, rows, mexes = [], [], []
    for m in mins:
        row = at_minute(stats, m)
        if row is None:
            if (res.get("game_minutes") or 0) >= m + 0.2 or not rows:
                return None
            ecos.append(0.5)   # the game ended before m: a dead side's economy
            mexes.append(0)
            continue
        ecos.append(eco_of(row))
        rows.append(row)
        mexes.append(row.get("mexN"))
    fired = set()
    try:
        for t, name in OPT_RE.findall((outdir / "stdout.txt").read_text("utf-8", errors="replace")):
            if int(t) == 0:
                fired.add(name)
    except OSError:
        pass
    last = rows[-1]
    return {"y": sum(math.log(max(e, 0.5)) for e in ecos) / len(ecos), "winners": res.get("winners") or [],
            "eco": [round(e, 1) for e in ecos], "mex": mexes,
            "mex20": last.get("mexN"), "t2": last.get("techStart"),
            "army20": last.get("mArmy"), "eco20": last.get("mEco"), "bp20": last.get("mBP"),
            "fired": sorted(fired)}


def play_round(spec, cfgs, rng, args, gdir: Path, tag: str):
    """Play every config once on one shared cell; returns [(index, game)]."""
    seed, hc, fac = rng.randrange(1, 10**6), rng.choice(getattr(args, "handicaps", HANDICAPS)), rng.choice(FACTIONS)
    jobs = list(enumerate(cfgs))
    slots = list(range(args.parallel))
    live, done = [], []
    while jobs or live:
        while jobs and slots:
            while his_game_running():
                print("  spring.exe (his game) is running; waiting", flush=True)
                time.sleep(60)
            i, cfg = jobs.pop(0)
            slot = slots.pop(0)
            out = gdir / f"{tag}-g{i}"
            if out.exists():
                shutil.rmtree(out, ignore_errors=True)
            proc, log = launch(spec, cfg, seed, hc, fac, args, out, slot)
            live.append((i, slot, proc, log, out))
            time.sleep(2)
        for item in live[:]:
            i, slot, proc, log, out = item
            if proc.poll() is None:
                continue
            log.close()
            live.remove(item)
            slots.append(slot)
            g = score_game(out, getattr(args, "check_min", CHECK_MIN))
            if g is None:
                print(f"  {out.name}: INVALID (rc={proc.returncode})", flush=True)
                continue
            g.update({"game": out.name, "round": tag, "handicap": hc, "faction": fac, "seed": seed})
            done.append((i, g))
        time.sleep(4)
    print(f"  round {tag}: hc={hc} {fac} seed={seed}, {len(done)}/{len(cfgs)} valid", flush=True)
    return done


def save(path: Path, obj):
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(obj), "utf-8")
    tmp.replace(path)


def spec_of(args):
    ln = _lane.require("ecoclimb")
    return args.spec or f"Apex{ln}:lane-{ln}:standard"


def fit(data, window, ridge):
    """Within-round ridge regression of y on knob position: slope, se per knob."""
    rows = data[-window:]
    by = {}
    for r in rows:
        by.setdefault(r["round"], []).append(r)
    X, Y = [], []
    for rs in by.values():
        if len(rs) < 2:
            continue
        U = np.array([r["u"] for r in rs])
        y = np.array([r["y"] for r in rs])
        X.append(U - U.mean(axis=0))
        Y.append(y - y.mean())
    if not X:
        return None
    X, Y = np.vstack(X), np.concatenate(Y)
    n, p = X.shape
    if n < 12:
        return None
    A = X.T @ X + ridge * np.eye(p)
    Ainv = np.linalg.inv(A)
    beta = Ainv @ X.T @ Y
    resid = Y - X @ beta
    dof = max(1, n - len(by) - p // 4)
    s2 = float(resid @ resid) / dof
    se = np.sqrt(np.maximum(np.diag(Ainv @ (X.T @ X) @ Ainv) * s2, 1e-12))
    return {"beta": beta.tolist(), "se": se.tolist(), "n": n, "sd": math.sqrt(s2)}


def explore_cfgs(inc, rng, args):
    cfgs, kinds, dus = [inc, inc], ["inc", "inc"], [{}, {}]
    for _ in range(args.parallel - 2):
        if rng.random() < args.offshoot:
            ks = rng.sample(KEYS, args.off_k)
            du = {k: rng.gauss(0.0, args.off_sigma) for k in ks}
            kinds.append("off")
        else:
            ks = rng.sample(KEYS, args.probe_k)
            du = {k: rng.choice((-1, 1)) * args.step for k in ks}
            kinds.append("probe")
        cfgs.append(move(inc, du))
        dus.append(du)
    return cfgs, kinds, dus


def propose(st, data, model, args):
    inc = st["incumbent"]
    if model:
        t = [b / s for b, s in zip(model["beta"], model["se"])]
        sig = sorted([(abs(tk), k, tk) for k, tk in zip(KEYS, t) if abs(tk) >= args.model_t],
                     reverse=True)[:args.climb_k]
        tried = set(json.dumps(x, sort_keys=True) for x in st.get("tried", []))
        if sig:
            du = {k: (args.climb_step if tk > 0 else -args.climb_step) for _, k, tk in sig}
            cand = move(inc, du)
            if diff(cand, inc) and json.dumps(cand, sort_keys=True) not in tried:
                return "model", cand
    # best recent off-shoot or probe that beat its round's incumbent games
    best, best_d = None, args.offshoot_bar
    rounds = {}
    for r in data[-args.window:]:
        rounds.setdefault(r["round"], []).append(r)
    for rs in rounds.values():
        base = [r["y"] for r in rs if r["kind"] == "inc"]
        if not base:
            continue
        b = sum(base) / len(base)
        for r in rs:
            if r["kind"] in ("off", "probe") and r["y"] - b > best_d and r["cfg"] != inc:
                best, best_d = r["cfg"], r["y"] - b
    if best:
        return "offshoot", best
    return None, None


def blocked_gap(blocks):
    """Mean of per-round (cand - inc) gaps and its se, from the pooled within-group variance."""
    blocks = [(c, i) for c, i in blocks if c and i]
    if not blocks:
        return 0.0, float("inf")
    ss, dof = 0.0, 0
    for grp in [g for b in blocks for g in b]:
        mg = sum(grp) / len(grp)
        ss += sum((y - mg) ** 2 for y in grp)
        dof += len(grp) - 1
    s2 = ss / dof if dof > 0 else 0.04
    gaps = [sum(c) / len(c) - sum(i) / len(i) for c, i in blocks]
    var = sum(s2 * (1 / len(c) + 1 / len(i)) for c, i in blocks) / len(blocks) ** 2
    return sum(gaps) / len(gaps), math.sqrt(var)


def record(data, pairs, kinds, cfgs, dus):
    for i, g in pairs:
        data.append({"round": g["round"], "kind": kinds[i], "cfg": cfgs[i], "u": uvec(cfgs[i]),
                     "du": dus[i] if dus else {}, **{k: g[k] for k in
                     ("y", "eco", "mex20", "t2", "army20", "eco20", "bp20", "handicap", "faction")},
                     "unread": [k for k in diff(cfgs[i], defaults()) if k not in g["fired"]]})


def cmd_run(args):
    spec = spec_of(args)
    d = ROOT / "tournaments" / f"ecoclimb-{args.name}"
    (d / "games").mkdir(parents=True, exist_ok=True)
    sp, dp = d / "state.json", d / "data.json"
    st = json.loads(sp.read_text("utf-8")) if sp.exists() else {
        "round": 0, "rounds": args.rounds, "incumbent": defaults(), "since_climb": 0,
        "accepted": [], "tried": [], "seed": args.seed, "spec": spec}
    data = json.loads(dp.read_text("utf-8")) if dp.exists() else []
    while st["round"] < st["rounds"]:
        rng = random.Random(st["seed"] * 7919 + st["round"])
        tag = f"r{st['round']:03d}"
        inc = st["incumbent"]
        if st["since_climb"] >= args.climb_every:
            model = fit(data, args.window, args.ridge)
            kind, cand = propose(st, data, model, args)
            st["since_climb"] = 0
            if cand:
                print(f"\n== {tag} CONFIRM [{kind}] {fmt_changes(diff(cand, inc))}", flush=True)
                h = args.parallel // 2
                cfgs = [cand] * h + [inc] * (args.parallel - h)
                kinds = ["cand"] * h + ["inc"] * (args.parallel - h)
                blocks = []
                for c in range(args.confirm):
                    pairs = play_round(spec, cfgs, rng, args, d / "games", f"{tag}c{c}")
                    record(data, pairs, kinds, cfgs, None)
                    blocks.append(([g["y"] for i, g in pairs if kinds[i] == "cand"],
                                   [g["y"] for i, g in pairs if kinds[i] == "inc"]))
                    save(dp, data)
                m, se = blocked_gap(blocks)
                t = m / se if se > 0 else 0.0
                unread = [k for k in diff(cand, inc)
                          if all(k in r["unread"] for r in data[-args.confirm * args.parallel:]
                                 if r["kind"] == "cand")]
                ok = t >= args.accept_t and not unread
                print(f"  -> cand vs inc {m:+.3f} (x{math.exp(m):.3f}) se {se:.3f} t {t:.2f}: "
                      f"{'ACCEPT' if ok else 'reject'}" + (f" unread {unread}" if unread else ""),
                      flush=True)
                st["tried"].append(cand)
                if ok:
                    st["accepted"].append({"round": st["round"], "kind": kind, "gain": m, "t": t,
                                           "changes": diff(cand, inc)})
                    st["incumbent"] = cand
                st["round"] += 1
                save(sp, st)
                continue
        cfgs, kinds, dus = explore_cfgs(inc, rng, args)
        print(f"\n== {tag} explore: {kinds.count('probe')} probes, {kinds.count('off')} off-shoots",
              flush=True)
        pairs = play_round(spec, cfgs, rng, args, d / "games", tag)
        record(data, pairs, kinds, cfgs, dus)
        base = [g["y"] for i, g in pairs if kinds[i] == "inc"]
        b = sum(base) / len(base) if base else float("nan")
        for i, g in sorted(pairs):
            print(f"    {kinds[i]:5s} {g['y'] - b:+.3f}  eco8..20 {g['eco']}  mex20 {g['mex20']} "
                  f"t2 {g['t2']}  {fmt_changes(diff(cfgs[i], inc))[:110]}", flush=True)
        st["round"] += 1
        st["since_climb"] += 1
        save(dp, data)
        save(sp, st)
    return cmd_read(args)


def cmd_read(args):
    d = ROOT / "tournaments" / f"ecoclimb-{args.name}"
    nz = d / "noise.json"
    if nz.exists():
        rs = json.loads(nz.read_text("utf-8"))
        for tag, ys in rs.items():
            m = sum(ys) / len(ys)
            sd = (sum((y - m) ** 2 for y in ys) / max(1, len(ys) - 1)) ** 0.5
            print(f"noise {tag}: mean ln eco {m:.3f}  sd/game {sd:.3f}  n={len(ys)}")
    sp, dp = d / "state.json", d / "data.json"
    if not sp.exists():
        return 0
    st = json.loads(sp.read_text("utf-8"))
    data = json.loads(dp.read_text("utf-8")) if dp.exists() else []
    print(f"round {st['round']}/{st['rounds']}, {len(data)} games, {len(st['accepted'])} accepted")
    for a in st["accepted"]:
        print(f"  r{a['round']} [{a['kind']}] x{math.exp(a['gain']):.3f} t {a['t']:.2f}: "
              f"{fmt_changes(a['changes'])}")
    model = fit(data, args.window, args.ridge)
    if model:
        print(f"model over {model['n']} games, residual sd {model['sd']:.3f}; slope per full knob range:")
        rows = sorted(zip(KEYS, model["beta"], model["se"]), key=lambda x: -abs(x[1] / x[2]))
        for k, b, s in rows[:15]:
            print(f"  {k:28s} {b:+.3f} se {s:.3f} t {b / s:+.2f}")
    never = set(KEYS)
    for r in data:
        never -= set(diff(r["cfg"], defaults())) - set(r["unread"])
    moved = {k for r in data for k in diff(r["cfg"], defaults())}
    if moved & never:
        print(f"moved but never read: {sorted(moved & never)}")
    print("incumbent vs default:")
    for k, v in st["incumbent"].items():
        if v != PARAMS[k][0]:
            print(f"  {k:28s} {v:<8g} default {PARAMS[k][0]:g}")
    return 0


def cmd_noise(args):
    spec = spec_of(args)
    d = ROOT / "tournaments" / f"ecoclimb-{args.name}"
    (d / "games").mkdir(parents=True, exist_ok=True)
    rng = random.Random(args.seed + 99)
    out = {}
    for r in range(2):
        pairs = play_round(spec, [defaults()] * args.parallel, rng, args, d / "games", f"noise{r}")
        out[f"noise{r}"] = [g["y"] for _, g in pairs]
        for _, g in pairs:
            print(f"    y {g['y']:.3f} eco {g['eco']} mex20 {g['mex20']} t2 {g['t2']} "
                  f"army20 {g['army20']}", flush=True)
    save(d / "noise.json", out)
    return cmd_read(args)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["run", "read", "noise"])
    ap.add_argument("--name", required=True)
    ap.add_argument("--spec", default="")
    ap.add_argument("--rounds", type=int, default=60)
    ap.add_argument("--parallel", type=int, default=8)
    ap.add_argument("--minutes", type=int, default=21)
    ap.add_argument("--speed", type=int, default=5)
    ap.add_argument("--step", type=float, default=0.15, help="probe size in [0,1] knob space")
    ap.add_argument("--probe-k", dest="probe_k", type=int, default=8)
    ap.add_argument("--offshoot", type=float, default=0.3)
    ap.add_argument("--off-k", dest="off_k", type=int, default=12)
    ap.add_argument("--off-sigma", dest="off_sigma", type=float, default=0.35)
    ap.add_argument("--offshoot-bar", dest="offshoot_bar", type=float, default=0.15)
    ap.add_argument("--climb-every", dest="climb_every", type=int, default=3)
    ap.add_argument("--climb-k", dest="climb_k", type=int, default=5)
    ap.add_argument("--climb-step", dest="climb_step", type=float, default=0.12)
    ap.add_argument("--model-t", dest="model_t", type=float, default=2.0)
    ap.add_argument("--confirm", type=int, default=2)
    ap.add_argument("--accept-t", dest="accept_t", type=float, default=2.0)
    ap.add_argument("--window", type=int, default=320)
    ap.add_argument("--ridge", type=float, default=2.0)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    return {"run": cmd_run, "read": cmd_read, "noise": cmd_noise}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
