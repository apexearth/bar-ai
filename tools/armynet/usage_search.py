#!/usr/bin/env python3
"""Search how serve uses the army net (his 11-22: "come up with a spread of strategies ... a ton of A/B testing, some
hill climbing, some annealing ... to find the right way to use the network").

    python tools/armynet/usage_search.py run [--hours 6] [--jobs 3] [--model <pt>] [--out runtime/armynet/usage-search]
    python tools/armynet/usage_search.py show [--out ...]

A config is one setting of serve's usage choices (click mode and bias, commit, wake, range arcs, rows, range share,
standoff, place draw, our AI flying the air). Each evaluation plays two arena games (dev_arena.lua, pure mode, the
same fixed roster both sides, sides swapping each round) at a fresh seed: one against our AI's own fight logic, one
against BARb's. A game's score is log(their metal lost / ours) over its rounds; an evaluation's is the mean of its two.
A config's score is the mean over all its evaluations, so a lucky one is pulled back by its re-tests.

The search: successive halving over --n random configs (the baseline and the current setting among them; each stage
played once more, the better half kept, down to one), then annealed hill climbing -- a parent drawn from the leaders
(a worse child accepted as the next parent with probability exp(delta / T), T falling over the run), one or two
settings changed; every 4th evaluation re-tests a leader on a new seed. Ledger: <out>/ledger.jsonl, one line per
evaluation (config, seed, per game rounds, trade, score).
"""
import json
import math
import random
import re
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ROSTER = "armpw*12,armham*6,armrock*6,armwar*4"
OPPONENTS = ("", "BARb:stable:hard")   # "" = our AI's own fight logic (watch.py's default side B)
MODE = "arena"   # --mode arena|game; game plays whole 20-min games against v0.5.17 and BARb
END = re.compile(r"BARAI_ARENA_END\] round=(\d+) .*?metal0=(\d+) metal1=(\d+) .*?spawnM0=(\d+) spawnM1=(\d+)")

SPACE = {
    "fbias": [-0.19, 0.5, 1.5, 20.0],
    "commit": [0.0, 0.3, 0.5, 0.7, 0.9],
    "wake": [0.0, 0.34, 0.7],
    "arc": [0, 1],
    "arc_rows": [1, 2, 3, 4],
    "range_frac": [0.7, 0.8, 0.9, 0.95, 1.0],
    "standoff": [0.0, 0.6, 0.8, 0.95],
    "sample_place": [0, 1],
    "keep_air": [0, 1],
    "arc_inrange": [0, 1],
    "kind_mode": ["model", "fight", "fightnear"],
    "place": ["cells", "goal"],
    "split_defs": [0, 1],
    "keep_aa": [0, 1],
}
BASELINE = {"fbias": -0.19, "commit": 0.0, "wake": 0.0, "arc": 1, "arc_rows": 3, "range_frac": 0.95, "standoff": 0.0,
            "sample_place": 0, "keep_air": 0}
CURRENT = {"fbias": 20.0, "commit": 0.5, "wake": 0.0, "arc": 1, "arc_rows": 3, "range_frac": 0.95, "standoff": 0.0,
           "sample_place": 0, "keep_air": 1}


def norm(cfg):
    """a ledger row from before a setting existed reads as its default (the first listed: off)"""
    return {k: cfg.get(k, v[0] if k in ("arc_inrange", "kind_mode", "place", "split_defs", "keep_aa") else cfg.get(k)) for k, v in SPACE.items()}


def key(cfg):
    return json.dumps(norm(cfg), sort_keys=True)


def flags(cfg):
    f = ["--forces", "--learned", "--rally", "--fbias", str(cfg["fbias"])]
    if cfg["commit"] > 0:
        f += ["--commit", str(cfg["commit"])]
    if cfg["wake"] > 0:
        f += ["--wake", str(cfg["wake"])]
    if cfg["arc"]:
        f += ["--arc", "--arc-rows", str(cfg["arc_rows"]), "--range-frac", str(cfg["range_frac"]),
              "--standoff", str(cfg["standoff"])]
    if cfg["sample_place"]:
        f += ["--sample-place"]
    if cfg["keep_air"]:
        f += ["--keep-air"]
    if cfg.get("keep_aa"):
        f += ["--keep-aa"]
    if cfg.get("split_defs"):
        f += ["--split-defs"]
    if cfg.get("place", "cells") != "cells":
        f += ["--place", cfg["place"]]
    if cfg.get("kind_mode", "model") != "model":
        f += ["--kind-mode", cfg["kind_mode"]]
    if cfg.get("arc_inrange") and cfg["arc"]:
        f += ["--arc-inrange"]
    return f


def engines():
    if sys.platform == "darwin":
        out = subprocess.run(["pgrep", "-f", "spring-headless"], capture_output=True, text=True).stdout
        return len([x for x in out.splitlines() if x.strip()])
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq spring-headless.exe"], capture_output=True, text=True).stdout
    return out.count("spring-headless")


def launch(cfg, seed, vs, model, logdir):
    log = logdir / ("g-%d-%s-%d.log" % (seed, "barb" if vs else "self", time.time_ns() % 10 ** 9))   # stages share seeds
    if MODE == "game":
        # a whole game (his 11-22 watches judged where the army goes, which the arena cannot): Comet Catcher 1v1,
        # +50, the new layout, 20 min; faction by seed as watch.py does
        cmd = [sys.executable, "-u", str(REPO / "tools" / "armynet" / "watch.py"), "--model", model, *flags(cfg),
               "--seed", str(seed), "--minutes", "20", "--speed", "4", "--headless",
               "--mod", "apex_flush_place=2", "--mod", "apex_streets=2"]
    else:
        cmd = [sys.executable, "-u", str(REPO / "tools" / "armynet" / "watch.py"), "--model", model, *flags(cfg),
               "--seed", str(seed), "--faction", "Armada", "--minutes", "10", "--speed", "4", "--headless",
               "--mod", "dev_arena=1", "--mod", "dev_arena_pure=1", "--mod", "dev_arena_def=" + ROSTER,
               "--mod", "dev_arena_round=2700"]   # 90-s rounds: twice the rounds a game, the trade still read per round
    if vs:
        cmd += ["--vs", vs]
    return subprocess.Popen(cmd, stdout=open(log, "w"), stderr=subprocess.STDOUT, cwd=str(REPO)), log


def read_full_game(log):
    """--mode game: a whole game's mobile kill/loss for side 0 from result.json, plus 0.5 for a win, -0.5 a loss"""
    txt = log.read_text(errors="replace")
    m = re.search(r"watch-armynet-engine-([\d-]+)", txt)
    if not m:
        return None
    rj = REPO / "matches" / ("armynet-watch-" + m.group(1)) / "result.json"
    if not rj.exists():
        return None
    d = json.loads(rj.read_text())
    st = [r for r in (d.get("stats") or []) if int(r["team"]) == 0]
    if not st:
        return None
    k, l = float(st[-1].get("mKillMobile", 0)), float(st[-1].get("mLostMobile", 0))
    w = (d.get("result") or {}).get("winners") or []
    res = 0.5 if 0 in w else (0.0 if not w else -0.5)
    return {"rounds": 1, "lost_ours": l, "lost_theirs": k, "result": res,
            "score": math.log((k + 200.0) / (l + 200.0)) + res}


def read_game(log):
    if MODE == "game":
        return read_full_game(log)
    txt = log.read_text(errors="replace")
    m = re.search(r"write dir (\S+)", txt)
    if not m:
        return None
    info = Path(m.group(1)) / "infolog.txt"
    if not info.exists():
        return None
    ours = theirs = 0.0
    rounds = 0
    for r in END.finditer(info.read_text(errors="replace")):
        m0, m1, s0, s1 = (float(r.group(k)) for k in (2, 3, 4, 5))
        ours += s0 - m0
        theirs += s1 - m1
        rounds += 1
    if rounds == 0:
        return None
    return {"rounds": rounds, "lost_ours": ours, "lost_theirs": theirs,
            "score": math.log((theirs + 50.0) / (ours + 50.0))}


def load(out):
    led = out / "ledger.jsonl"
    rows = [json.loads(x) for x in led.read_text().splitlines() if x.strip()] if led.exists() else []
    return rows


def table(rows):
    by = {}
    for r in rows:
        by.setdefault(key(r["cfg"]), []).append(r["score"])
    return sorted(((sum(v) / len(v), len(v), k) for k, v in by.items()), reverse=True)


def mutate(cfg, rng):
    c = norm(cfg)
    for name in rng.sample(list(SPACE), rng.choice((1, 2))):
        opts = [v for v in SPACE[name] if v != c[name]]
        c[name] = rng.choice(opts)
    return c


def run(a):
    def opt(name, default):
        return a[a.index(name) + 1] if name in a else default
    global MODE, OPPONENTS
    MODE = opt("--mode", "arena")
    if MODE == "game":
        OPPONENTS = ("Apex:v0.5.17:standard", "BARb:stable:hard")
    out = Path(opt("--out", str(REPO / "runtime" / "armynet" / "usage-search")))
    out.mkdir(parents=True, exist_ok=True)
    model = opt("--model", str(REPO / "runtime" / "armynet" / "cap-wide40" / "model-040000.pt"))
    jobs = int(opt("--jobs", "3"))
    stop_at = time.time() + float(opt("--hours", "6")) * 3600
    rng = random.Random(int(time.time()))
    rows = load(out)
    seed = int(opt("--seed0", "1000")) + len(rows) * 2   # the Mac runs with --seed0 500000: no shared seeds
    # SUCCESSIVE HALVING first (his 11-22: "I rely a little bit on dumb luck, because you may have 100,000 potential
    # good options ... some sort of binary search"): N configs drawn at random (the baseline and the current setting
    # among them) are played once each; the better half by mean score is played again, and so on down to two; then
    # annealed hill climbing around the leaders for the rest of the time
    n0 = int(opt("--n", "32"))
    inject = [norm(json.loads(x)) for x in Path(opt("--inject", "")).read_text().splitlines() if x.strip()] if "--inject" in a else []
    stage = [] if rows else ([norm(BASELINE), norm(CURRENT)] + inject
                             + [{k: rng.choice(v) for k, v in SPACE.items()} for _ in range(max(n0 - 2 - len(inject), 0))])
    stage_left = list(stage)
    seed += 2
    stage_seed = seed
    queue = []
    running = []   # (cfg, seed, [(proc, log, vs)])
    n_eval = len(rows)
    parent = None
    t0 = time.time()
    while time.time() < stop_at or running:
        for item in list(running):
            cfg, s, games = item
            if all(p.poll() is not None for p, _, _ in games):
                running.remove(item)
                res = [read_game(log) for _, log, _ in games]
                if any(r is None for r in res):
                    print("eval seed %d failed to read; skipped" % s, flush=True)
                    continue
                score = sum(r["score"] for r in res) / len(res)
                row = {"cfg": cfg, "seed": s, "games": res, "score": score, "at": time.time()}
                with open(out / "ledger.jsonl", "a") as f:
                    f.write(json.dumps(row) + "\n")
                rows.append(row)
                n_eval += 1
                best = table(rows)[:3]
                print("eval %d seed %d score %.3f (self %.2f, barb %.2f) | leader %.3f over %d: %s" % (
                    n_eval, s, score, math.exp(res[0]["score"]), math.exp(res[1]["score"]), best[0][0], best[0][1],
                    best[0][2]), flush=True)
                # annealing: the next parent
                T = max(0.02, 0.3 * (1 - (time.time() - t0) / max(stop_at - t0, 1)))
                if parent is None or score >= parent[1] or rng.random() < math.exp((score - parent[1]) / T):
                    parent = (cfg, score)
        if stage and not stage_left and not running:
            # the stage is played: keep the better half by each config's mean over everything it has played
            means = {k: s for s, _, k in table(rows)}
            stage = sorted(stage, key=lambda c: means.get(key(c), -9.0), reverse=True)[:max(len(stage) // 2, 1)]
            print("halving: %d left, best %.3f" % (len(stage), means.get(key(stage[0]), -9.0)), flush=True)
            if len(stage) <= 1:
                parent = (stage[0], means.get(key(stage[0]), 0.0))
                stage = []
            else:
                stage_left = list(stage)
                seed += 2
                stage_seed = seed
        if time.time() < stop_at and len(running) < jobs and engines() + 2 <= 4:
            from_stage = bool(stage_left)
            if stage_left:
                cfg = stage_left.pop(0)
            elif stage:
                time.sleep(15)   # the stage's last evaluations are still running
                continue
            elif queue:
                cfg = queue.pop(0)
            elif rows and n_eval % 4 == 3:
                lead = table(rows)[:3]
                cfg = json.loads(rng.choice(lead)[2])   # re-test a leader on a new seed
            else:
                lead = table(rows)[:5]
                base = parent[0] if (parent and rng.random() < 0.5) else json.loads(rng.choice(lead)[2])
                cfg = mutate(base, rng)
            if from_stage:
                use_seed = stage_seed   # one seed for the whole stage: its configs are compared on the same games
            else:
                seed += 2
                use_seed = seed
            games = []
            for vs in OPPONENTS:
                p, log = launch(cfg, use_seed, vs, model, out)
                games.append((p, log, vs))
                time.sleep(20)
            running.append((cfg, use_seed, games))
            continue
        time.sleep(15)
    show(rows)


def show(rows):
    print("evaluations %d" % len(rows))
    for s, n, k in table(rows)[:15]:
        print("  %.3f (trade x%.2f) over %d: %s" % (s, math.exp(s), n, k))


if __name__ == "__main__":
    if sys.argv[1] == "run":
        run(sys.argv[2:])
    else:
        a = sys.argv[2:]
        out = Path(a[a.index("--out") + 1]) if "--out" in a else REPO / "runtime" / "armynet" / "usage-search"
        show(load(out))
