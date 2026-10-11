"""Search the continuous heads' values by iteration (his 10-10: "do some big tests on random values
and then take the best N results and test those, then the next big batch ... values randomized
some ... find the good net values like this through simple iteration").

A cross-entropy search over ONE joint vector of every continuous head's value (they balance each
other, so they are tried together). Each generation: CANDS value sets drawn around the current mean
(candidate 0 is the mean itself), each played in the same GAMES (same maps and seeds for every
candidate, so they are compared fairly) with the AI's per-head option apex_fix_<head> (nnlog.as
NnValDecide). Score = mean economy/army/mex edge over the game plus the result. The ELITE best re-centre
the mean; the spread narrows toward theirs, never below SIG_MIN. The mean is published as the policy
centres (runtime/nn/centre.json) while runtime/nn/cem_on exists; every game still trains the nets.

    python tools/cem.py            # run generations until runtime/nn_stop exists
    python tools/cem.py --status   # where the search stands
State: runtime/nn/cem.json; log: runtime/nn/cem.log; games: tournaments/<stamp>-nn-cem-g<N>/.
"""
import glob, json, math, os, random, re, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
import progress
import mp_archive

NN = os.path.join(REPO, "runtime", "nn")
STATE = os.path.join(NN, "cem.json")
LOG = os.path.join(NN, "cem.log")
CENTRE = os.path.join(NN, "centre.json")
FLAG = os.path.join(NN, "cem_on")
AI = "Apexnnlog:lane-nnlog:standard"
FOE = "BARb:stable:hard"
CANDS = 16
ELITE = 4
SIG0 = 0.35          # log-space spread at the start: about +-40%
SIG_MIN = 0.08
SIG_KEEP = 0.6       # the new spread is this much of the old plus the rest of the elite's
MINUTES = 40
GAMES = [  # (per side, map); seeds are drawn per generation and shared by every candidate
    (1, "Comet Catcher Remake 1.8"),
    (2, None),   # 2v2 map rotates per generation
]
MAPS_2V2 = ["Frozen_Ford_V2", "Glacier Pass", "Comet Catcher Remake 1.8"]
FLOOR = 0.05         # log-space floor for ranges that start at 0


def log(msg):
    line = time.strftime("%m-%d %H:%M ") + msg
    print(line, flush=True)
    with open(LOG, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def heads_from_logs():
    """{head: (lo, hi, rule)} from the newest games' nnval-schema lines."""
    out = {}
    rx = re.compile(r"apex: nnval-schema v\d+ head=(\w+) state=\S+ own=\S+ lo=([\d.]+) hi=([\d.]+) rule=([\d.]+)")
    for f in sorted(glob.glob(os.path.join(REPO, "tournaments", "*nn-open*", "matches", "*", "infolog.txt")),
                    key=os.path.getmtime, reverse=True)[:6]:
        txt = open(f, encoding="utf-8", errors="replace").read()
        for m in rx.finditer(txt):
            out.setdefault(m.group(1), (float(m.group(2)), float(m.group(3)), float(m.group(4))))
    return out


def load():
    if os.path.exists(STATE):
        return json.load(open(STATE, encoding="utf-8"))
    heads = heads_from_logs()
    if not heads:
        raise SystemExit("no nnval-schema lines in recent games: cannot learn the heads' ranges")
    return {"gen": 0, "heads": {h: {"lo": lo, "hi": hi, "rule": r, "mu": math.log(max(r, FLOOR)), "sig": SIG0}
                                for h, (lo, hi, r) in heads.items()},
            "history": []}


def save(st):
    tmp = STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(st, fh, indent=1)
    os.replace(tmp, STATE)


def value(h, x):
    return round(min(h["hi"], max(h["lo"], math.exp(x))), 4)


def publish(st):
    """The mean as the policy centres the game clamps the nets to (nntrain reads, never writes, while cem_on)."""
    try:
        cs = json.load(open(CENTRE, encoding="utf-8"))
    except (OSError, ValueError):
        cs = {}
    for name, h in st["heads"].items():
        cs[name] = value(h, h["mu"])
    tmp = CENTRE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(cs, fh)
    os.replace(tmp, CENTRE)


def workers():
    try:
        w = int(open(os.path.join(NN, "workers-cem")).read().strip())
    except (OSError, ValueError):
        w = 4
    return 1 if mp_archive.his_game_running() else max(1, w)


def score(mdir):
    g = progress.read_game(mdir)
    if g is None:
        return None
    s = g["series"]

    def mean_log(k):
        xs = [v for v in s.get(k, [])[3:] if v is not None and v > 0]
        return sum(max(-2.3, min(2.3, math.log(v))) for v in xs) / len(xs) if xs else 0.0
    res = {"W": 1.0, "L": -1.0 + 0.5 * min(g["minutes"], MINUTES) / MINUTES, "D": 0.0}[g["result"]]
    return 0.5 * mean_log("eco") + 0.5 * mean_log("army") + 0.25 * mean_log("mex") + res, g["result"]


def play(job):
    gen_dir, ci, gi, per_side, mapn, seed, vals, slot = job
    out = os.path.join(gen_dir, "matches", "c%02d-g%d" % (ci, gi))
    if os.path.exists(os.path.join(out, "result.json")):
        return ci, gi, score(out)
    cmd = [sys.executable, "-u", os.path.join(REPO, "tools", "run_match.py"), "--a", AI, "--b", FOE,
           "--map", mapn, "--minutes", str(MINUTES), "--seed", str(seed), "--speed", "20",
           "--per-side", str(per_side), "--sides", "random,random", "--out", out,
           "--write-dir", os.path.join("runtime", "engine-cem-%d" % slot),
           "--modoption", "apex_lag_speed=0", "--modoption", "apex_nn_explore=0"]
    for h, v in vals.items():
        cmd += ["--ai-option", "apex_fix_%s=%g" % (h, v)]
    with open(os.path.join(gen_dir, "c%02d-g%d.log" % (ci, gi)), "w", encoding="utf-8") as fh:
        subprocess.run(cmd, cwd=REPO, stdout=fh, stderr=subprocess.STDOUT, timeout=3600)
    return ci, gi, score(out)


def generation(st):
    gen = st["gen"] + 1
    rng = random.Random(gen * 7919)
    names = sorted(st["heads"])
    cands = []
    for ci in range(CANDS):
        xs = {n: st["heads"][n]["mu"] + (0.0 if ci == 0 else rng.gauss(0, st["heads"][n]["sig"])) for n in names}
        cands.append(xs)
    games = [(ps, m or MAPS_2V2[gen % len(MAPS_2V2)], rng.randrange(1, 10 ** 6)) for ps, m in GAMES]
    gen_dir = os.path.join(REPO, "tournaments", time.strftime("%Y%m%d-%H%M%S") + "-nn-cem-g%d" % gen)
    os.makedirs(os.path.join(gen_dir, "matches"), exist_ok=True)
    json.dump({"gen": gen, "cands": [{n: value(st["heads"][n], x[n]) for n in names} for x in cands],
               "games": games}, open(os.path.join(gen_dir, "config.json"), "w"), indent=1)
    w = workers()
    jobs = []
    for ci, x in enumerate(cands):
        vals = {n: value(st["heads"][n], x[n]) for n in names}
        for gi, (ps, mapn, seed) in enumerate(games):
            jobs.append([gen_dir, ci, gi, ps, mapn, seed, vals, 0])
    for k, j in enumerate(jobs):
        j[7] = k % w
    log("gen %d: %d candidates x %d games, %d workers -> %s" % (gen, CANDS, len(games), w, os.path.basename(gen_dir)))
    scores = {}
    results = {}
    with ThreadPoolExecutor(max_workers=w) as ex:
        for ci, gi, sc in ex.map(play, [tuple(j) for j in jobs]):
            if sc is not None:
                scores.setdefault(ci, []).append(sc[0])
                results.setdefault(ci, []).append(sc[1])
            if os.path.exists(os.path.join(REPO, "runtime", "nn_stop")):
                break
    ranked = sorted((sum(v) / len(v), ci) for ci, v in scores.items() if len(v) == len(games))
    ranked.reverse()
    if len(ranked) < ELITE:
        log("gen %d: only %d candidates scored -- mean kept" % (gen, len(ranked)))
        st["gen"] = gen
        return st
    elite = [ci for _, ci in ranked[:ELITE]]
    for n in names:
        xs = [cands[ci][n] for ci in elite]
        m = sum(xs) / len(xs)
        sd = math.sqrt(sum((x - m) ** 2 for x in xs) / len(xs))
        h = st["heads"][n]
        h["mu"] = m
        h["sig"] = max(SIG_MIN, SIG_KEEP * h["sig"] + (1 - SIG_KEEP) * sd)
    best = ranked[0]
    st["gen"] = gen
    st["history"].append({"gen": gen, "dir": os.path.basename(gen_dir), "best": round(best[0], 3),
                          "best_cand": best[1], "mean_cand_rank": [r for r, (_, ci) in enumerate(ranked) if ci == 0],
                          "elite_scores": [round(s, 3) for s, _ in ranked[:ELITE]],
                          "results": "".join("".join(results.get(ci, [])) for _, ci in ranked),
                          "mu": {n: value(st["heads"][n], st["heads"][n]["mu"]) for n in names}})
    log("gen %d: best %.3f (cand %d), elite %s, results by rank %s" % (
        gen, best[0], best[1], [round(s, 2) for s, _ in ranked[:ELITE]], st["history"][-1]["results"]))
    log("gen %d: mean now %s" % (gen, " ".join("%s=%.2f" % (n, value(st["heads"][n], st["heads"][n]["mu"])) for n in names)))
    return st


def main(argv):
    st = load()
    if "--status" in argv:
        print("gen %d" % st["gen"])
        for n, h in sorted(st["heads"].items()):
            print("  %-7s rule=%-6g mean=%-7.3f spread=x%.2f range=%g-%g" % (n, h["rule"], value(h, h["mu"]), math.exp(h["sig"]), h["lo"], h["hi"]))
        for e in st["history"][-5:]:
            print("  gen %d best %.3f elite %s results %s" % (e["gen"], e["best"], e["elite_scores"], e["results"]))
        return 0
    open(FLAG, "w").write(str(time.time()))
    save(st)
    publish(st)
    while not os.path.exists(os.path.join(REPO, "runtime", "nn_stop")):
        st = generation(st)
        save(st)
        publish(st)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
