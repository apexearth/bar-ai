"""Search the continuous heads' values by iteration (his 10-10: "do some big tests on random values
and then take the best N results and test those, then the next big batch ... values randomized
some ... find the good net values like this through simple iteration").

A cross-entropy search over ONE joint vector of every continuous head's value (they balance each
other, so they are tried together). Each generation: CANDS value sets drawn around the current mean
(candidate 0 is the mean itself), each played in the same GAMES (same maps and seeds for every
candidate, so they are compared fairly) with the AI's per-head option apex_fix_<head> (nnlog.as
NnValDecide). Score = mean economy/army/mex edge over the game plus the result. The ELITE best re-centre
the mean; the spread narrows toward theirs and by DECAY each round, down to SIG_END, when the run ends:
its answer meets the all-time best in VALID games and the better is kept (cem_best.json); that best
is published as the policy centres while runtime/nn/cem_on exists. Every game still trains the nets.

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
SIG0 = 0.35          # log-space spread at a run's start: about +-40%
SIG_END = 0.06       # a run ends once every head's spread is down to this (about +-6%)
SIG_KEEP = 0.6       # the new spread is this much of the old plus the rest of the elite's
DECAY = 0.85         # ...and never above SIG0 * DECAY^round: the randomness falls as the run goes on
GENS_PER_RUN = 12
FRESH_EVERY = 3      # every third run starts from the rule values, the rest from the all-time best
VALID = [(1, "Comet Catcher Remake 1.8"), (1, "Comet Catcher Remake 1.8"), (1, "Comet Catcher Remake 1.8"),
         (2, "Frozen_Ford_V2"), (2, "Glacier Pass"), (2, "Comet Catcher Remake 1.8")]
BEST = os.path.join(NN, "cem_best.json")
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


def bests():
    try:
        return json.load(open(BEST, encoding="utf-8"))
    except (OSError, ValueError):
        return {"best": None, "runs": []}


def publish(st):
    """The ALL-TIME BEST as the policy centres the game clamps the nets to (the running mean is noisy);
    the mean until a first run has finished. nntrain reads, never writes, while cem_on."""
    try:
        cs = json.load(open(CENTRE, encoding="utf-8"))
    except (OSError, ValueError):
        cs = {}
    b = bests()["best"]
    for name, h in st["heads"].items():
        bs_ = st.get("best_set") or {}
        cs[name] = b["vals"][name] if b and name in b["vals"] else bs_.get(name, value(h, h["mu"]))
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


# Heads that balance each other move as one block in a crossover (his 10-10: "some of the nets strongly
# depend on each other as they are a balance of each other"); a head in no group is its own block.
GROUPS = [("con", "mex", "cap", "acap", "scap", "aplant"),
          ("esc", "ecap", "cfear", "mexg", "defamt", "gunp", "aa"),
          ("mass", "odds", "tmix")]


def sample(st, rng, names):
    """WHOLE SETS, never a head-by-head average of them: the elites come back as they are (re-tested),
    most candidates are an elite plus a little noise on every head, some cross two elites by whole
    groups, a few explore around the mean. Before a first round has an elite, the mean plus noise."""
    def noisy(base, scale=1.0):
        return {n: base[n] + rng.gauss(0, st["heads"][n]["sig"] * scale) for n in names}
    mean = {n: st["heads"][n]["mu"] for n in names}
    elite = [e["x"] for e in st.get("elite", []) if all(n in e["x"] for n in names)]
    if not elite:
        return [mean] + [noisy(mean) for _ in range(CANDS - 1)]
    cands = [dict(e) for e in elite]
    blocks = [list(g) for g in GROUPS] + [[n] for n in names if not any(n in g for g in GROUPS)]
    while len(cands) < CANDS:
        k = len(cands)
        if k % 4 == 3:
            cands.append(noisy(mean))
        elif k % 4 == 2 and len(elite) > 1:
            a, b = rng.sample(elite, 2)
            child = {}
            for blk in blocks:
                src = a if rng.random() < 0.5 else b
                child.update({n: src[n] for n in blk if n in src})
            cands.append(noisy(child, 0.5))
        else:
            # rank-weighted: the best elite is the most common parent
            w = [len(elite) - i for i in range(len(elite))]
            cands.append(noisy(rng.choices(elite, weights=w)[0], 0.6))
    return cands[:CANDS]


def generation(st):
    gen = st["gen"] + 1
    rng = random.Random(gen * 7919)
    names = sorted(st["heads"])
    cands = sample(st, rng, names)
    games = [(ps, m or MAPS_2V2[gen % len(MAPS_2V2)], rng.randrange(1, 10 ** 6)) for ps, m in GAMES]
    # a restart resumes this generation's own dir: its candidates and finished games are kept
    old = sorted(glob.glob(os.path.join(REPO, "tournaments", "*-nn-cem-g%d" % gen)))
    cfg = None
    if old:
        try:
            cfg = json.load(open(os.path.join(old[-1], "config.json"), encoding="utf-8"))
        except (OSError, ValueError):
            cfg = None
    if cfg and len(cfg.get("cands", [])) == CANDS and all(n in cfg["cands"][0] for n in names):
        gen_dir = old[-1]
        cands = [{n: math.log(max(c[n], FLOOR)) for n in names} for c in cfg["cands"]]
        games = [tuple(g) for g in cfg["games"]]
        log("gen %d: resuming %s" % (gen, os.path.basename(gen_dir)))
    else:
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
    rnd = st.get("round", 0) + 1
    cap = SIG0 * DECAY ** rnd
    for n in names:
        xs = [cands[ci][n] for ci in elite]
        m = sum(xs) / len(xs)
        sd = math.sqrt(sum((x - m) ** 2 for x in xs) / len(xs))
        h = st["heads"][n]
        h["mu"] = m
        h["sig"] = max(SIG_END, min(cap, SIG_KEEP * h["sig"] + (1 - SIG_KEEP) * sd))
    st["round"] = rnd
    st["elite"] = [{"x": cands[ci], "score": round(s, 4)} for s, ci in ranked[:ELITE]]
    st["best_set"] = {n: value(st["heads"][n], cands[ranked[0][1]][n]) for n in names}
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


def run_over(st):
    return st.get("round", 0) >= GENS_PER_RUN or all(h["sig"] <= SIG_END * 1.05 for h in st["heads"].values())


def mean_score(gen_dir, ci, vals, games, tag):
    w = workers()
    jobs = [(gen_dir, ci, gi, ps, mapn, seed, vals, gi % w) for gi, (ps, mapn, seed) in enumerate(games)]
    with ThreadPoolExecutor(max_workers=w) as ex:
        got = [sc for _, _, sc in ex.map(play, jobs) if sc is not None]
    log("validate %s: %d/%d games, results %s, score %s" % (tag, len(got), len(games), "".join(r for _, r in got),
                                                            "%.3f" % (sum(s for s, _ in got) / len(got)) if got else "-"))
    return (sum(s for s, _ in got) / len(got)) if len(got) >= len(games) // 2 + 1 else None


def finish_run(st):
    """The run's answer against the all-time best in the same validation games; the better is kept."""
    names = sorted(st["heads"])
    # the best WHOLE set of the last round, never the average of sets (it can break a balance)
    final = dict(st.get("best_set") or {n: value(st["heads"][n], st["heads"][n]["mu"]) for n in names})
    rng = random.Random(st.get("run", 1) * 104729)
    games = [(ps, m, rng.randrange(1, 10 ** 6)) for ps, m in VALID]
    gen_dir = os.path.join(REPO, "tournaments", time.strftime("%Y%m%d-%H%M%S") + "-nn-cem-run%d-valid" % st.get("run", 1))
    os.makedirs(os.path.join(gen_dir, "matches"), exist_ok=True)
    bs = bests()
    sf = mean_score(gen_dir, 0, final, games, "run %d final" % st.get("run", 1))
    sb = None
    if bs["best"] is not None:
        sb = mean_score(gen_dir, 1, {n: bs["best"]["vals"].get(n, final[n]) for n in names}, games, "all-time best")
    rec = {"run": st.get("run", 1), "at": time.strftime("%Y-%m-%d %H:%M"), "rounds": st.get("round", 0),
           "vals": final, "score": sf, "vs_best": sb, "valid_dir": os.path.basename(gen_dir)}
    bs["runs"].append(rec)
    if sf is not None and (bs["best"] is None or sb is None or sf > sb):
        bs["best"] = {"vals": final, "score": sf, "run": rec["run"], "at": rec["at"]}
        log("run %d: NEW ALL-TIME BEST (%.3f vs %s): %s" % (rec["run"], sf, "-" if sb is None else "%.3f" % sb,
                                                           " ".join("%s=%.2f" % kv for kv in sorted(final.items()))))
    else:
        log("run %d: kept the all-time best (%s vs final %s)" % (rec["run"], "-" if sb is None else "%.3f" % sb,
                                                                 "-" if sf is None else "%.3f" % sf))
    tmp = BEST + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(bs, fh, indent=1)
    os.replace(tmp, BEST)
    # the next run: wide again, around the all-time best -- or the rule values every FRESH_EVERY runs
    nxt = st.get("run", 1) + 1
    fresh = (nxt % FRESH_EVERY == 0) or bs["best"] is None
    for n, h in st["heads"].items():
        start = h["rule"] if fresh else bs["best"]["vals"].get(n, h["rule"])
        h["mu"] = math.log(max(start, FLOOR))
        h["sig"] = SIG0
    st["run"], st["round"] = nxt, 0
    st["elite"] = [] if fresh else [{"x": {n: h["mu"] for n, h in st["heads"].items()}, "score": None}]
    st["best_set"] = None
    log("run %d starts from %s, spread x%.2f" % (nxt, "the rule values" if fresh else "the all-time best", math.exp(SIG0)))
    return st


def main(argv):
    st = load()
    st.setdefault("run", 1)
    st.setdefault("round", st.get("gen", 0))
    if "--status" in argv:
        print("gen %d  run %d round %d/%d" % (st["gen"], st.get("run", 1), st.get("round", 0), GENS_PER_RUN))
        b = bests()
        if b["best"]:
            print("  ALL-TIME BEST (run %d, %s, score %.3f): %s" % (b["best"]["run"], b["best"]["at"], b["best"]["score"],
                  " ".join("%s=%.2f" % kv for kv in sorted(b["best"]["vals"].items()))))
        for r in b["runs"][-5:]:
            print("  run %d final score %s vs best %s" % (r["run"], r["score"], r["vs_best"]))
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
        if run_over(st):
            st = finish_run(st)
            save(st)
        publish(st)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
