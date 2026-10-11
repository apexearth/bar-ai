"""Evolve the policy network's weights by playing games (his 10-10: a real network with enough depth
to find relationships, started in the middle; randomize the weights, play, keep the best, randomize
around them, anneal; every net part of it).

The network (policy.as): the live state -> a shared hidden layer -> per head, that head's own
decision features join through a hidden layer of its own -> its outputs. Heads: every continuous
value (log-middle of its range at output 0), every fixed-choice call (the rule's odds at output 0),
the builder auction and factory production (each option scored from its own numbers; the market's
value at output 0).

Each round: CANDS weight vectors, each played in the same GAMES (1v1, Comet Catcher, one seed) through
per-AI options apex_pw_<i>. The ELITE are kept whole and re-tested; the rest are an elite with
some of its weights nudged (each weight chosen at random with chance pm, nudged by N(0, sig)) or two
elites crossed by whole neurons and whole heads. sig and pm fall each round. A run ends after
GENS_PER_RUN rounds: its best meets the all-time best in VALID games and the better is kept. Every
run's answer is kept (neuro_best.json). The all-time best is written into the deployed AI's
policydata.as, so a game with no options plays it.

    python tools/neuro.py --init     # freeze the layout and input scaling, write the repo policydata.as
    python tools/neuro.py            # run rounds until runtime/nn_stop exists
    python tools/neuro.py --status
State: runtime/nn/neuro.json; log: runtime/nn/neuro.log; games: tournaments/<stamp>-nn-neuro-g<N>/.
"""
import glob, json, math, os, random, re, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
import bar_env
import cem

NN = os.path.join(REPO, "runtime", "nn")
STATE = os.path.join(NN, "neuro.json")
BEST = os.path.join(NN, "neuro_best.json")
LOG = os.path.join(NN, "neuro.log")
STOP = os.path.join(REPO, "runtime", "nn_stop")
MARKET = os.path.join(REPO, "ai", "Unstable", "game-side", "script", "standard", "manager", "brain", "market")
DATA_REL = Path("script/standard/manager/brain/market/policydata.as")
AI = cem.AI
FOE = cem.FOE
MINUTES = cem.MINUTES
# his 10-10: 1v1, Comet Catcher only, always the same seed. One seed still does not replay the same game
# (two runs of one network: 48 and 58 deaths), so a network plays it several times.
GAME = (1, "Comet Catcher Remake 1.8", 1)
GAMES = [GAME] * 4
VALID = [GAME] * 12

H1 = 16              # the shared layer
H2 = 6               # each head's own layer
FLOOR = 0.05         # log floor of a range that starts at 0
LGAIN = 8.0          # a choice's or list option's weight moves by up to e^LGAIN either way
CANDS = 8
ELITE = 3
SHRINK = 2
SIG0, SIG_END = 0.35, 0.03
PM0, PM_END = 0.3, 0.05
DECAY = 0.92
GENS_PER_RUN = 30
FRESH_EVERY = 3

# The shared layer's inputs: what a player can see of the economy, the armies and the danger.
INPUTS = ["min", "mInc", "eInc", "mCur", "mStor", "eCur", "eStor", "eStall", "mWasting", "tier",
          "army", "teamArmy", "foeArmy", "foeMass", "losing", "outmassed", "trade", "mex", "raidP",
          "airSeen", "foeT2", "foeHeavy", "foeArty", "foeRaider", "foeStatic", "ourQual", "foeQual",
          "homeStr", "dgA120", "foeEta", "convCap", "defM", "nanoBP", "allies", "foeTeam", "mapArea"]

# (key the game looks the head up by, the trained net whose input scaling it borrows, kind)
# kind: "val" = continuous (key = its tag), "pick" = fixed choice (key = its own-feature layout),
# "list" = builder/factory.
CONT = [("esc", "NNE"), ("ecap", "NNY"), ("cfear", "NNCF"), ("con", "NNK"), ("cap", "NNQ"),
        ("acap", "NNZ"), ("scap", "NNS"), ("mex", "NNX"), ("aplant", "NNL"), ("defamt", "NND"),
        ("mexg", "NNMG"), ("gunp", "NNGP"), ("mass", "NNM"), ("odds", "NNO"), ("tmix", "NNTM"),
        ("aa", "NNAD")]
PICK = [("plan", "NNG"), ("tech", "NNT"), ("open", "NNOP"), ("hunt", "NNH"), ("strike", "NNB"),
        ("reinf", "NNV"), ("join", "NNJ"), ("raid", "NNR"), ("air", "NNA"), ("com", "NNC"),
        ("defsite", "NNU"), ("deftype", "NNN"), ("post", "NNP")]
WK_KINDS = 17        # kinds.as WK_TEETH + 1


def log(msg):
    line = time.strftime("%m-%d %H:%M ") + msg
    print(line, flush=True)
    with open(LOG, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def nn_state_source():
    """NN_STATE exactly as nnlog.as builds it from its string pieces."""
    src = open(os.path.join(MARKET, "nnlog.as"), encoding="utf-8").read()
    m = re.search(r'const string NN_STATE = (.*?);\n', src, re.S)
    return "".join(re.findall(r'"([^"]*)"', m.group(1)))


def deployed_weights():
    env = bar_env.load()
    root = env.skirmish_dir("Apexnnlog", "lane-nnlog")
    return (root / "script/standard/manager/brain/market/nnweights.as").read_text(encoding="utf-8")


def as_const(txt, name):
    m = re.search(r"const (?:array<float>|int|string|bool) %s = (.*?);\n" % re.escape(name), txt, re.S)
    if not m:
        raise SystemExit("deployed nnweights.as has no %s" % name)
    v = m.group(1).strip()
    if v.startswith("{"):
        return [float(x.rstrip("f")) for x in re.findall(r"-?[\d.]+(?:e-?\d+)?f?", v)]
    if v.startswith('"'):
        return v.strip('"')
    return int(v) if re.fullmatch(r"-?\d+", v) else v


def build_layout():
    """Freeze which inputs, which heads, and every input's scaling (the trained nets' slog means and
    spreads over thousands of games)."""
    state = nn_state_source()
    names = state.split(",")
    w = deployed_weights()
    if as_const(w, "NNW_STATE") != state:
        raise SystemExit("the deployed builder net was laid out against another NN_STATE")
    S0 = len(names)
    xm, xs = as_const(w, "NNW_XM"), as_const(w, "NNW_XS")
    idx = [names.index(n) for n in INPUTS]
    lay = {"state": state, "idx": idx, "m": [xm[i] for i in idx], "s": [max(xs[i], 0.05) for i in idx],
           "heads": []}

    def own_scaling(px):
        st = as_const(w, px + "_STATE")
        if not st.startswith(state + "|"):
            raise SystemExit("%s was laid out against another NN_STATE" % px)
        S = as_const(w, px + "_S")
        m, s = as_const(w, px + "_XM"), as_const(w, px + "_XS")
        return st[len(state) + 1:], S - S0, m[S0:S], [max(v, 0.05) for v in s[S0:S]], as_const(w, px + "_O")
    for tag, px in CONT:
        own, F, m, s, _ = own_scaling(px)
        lay["heads"].append({"key": tag, "kind": "val", "K": 0, "F": F, "m": m, "s": s})
    for tag, px in PICK:
        own, F, m, s, O = own_scaling(px)
        lay["heads"].append({"key": own, "name": tag, "kind": "pick", "K": O // 2, "F": F, "m": m, "s": s})
    # builder: kind one-hot, then NnOpt's 16 numbers, value - best, eta - best eta, n (nnlog.as NnScore)
    S = as_const(w, "NNW_S")
    m, s = as_const(w, "NNW_XM"), as_const(w, "NNW_XS")
    nk = as_const(w, "NNW_O") - 20
    o = S + nk
    lay["heads"].append({"key": "builder", "kind": "list", "K": -1, "F": WK_KINDS + 19,
                         "m": [0.0] * WK_KINDS + m[o:o + 19], "s": [1.0] * WK_KINDS + [max(v, 0.05) for v in s[o:o + 19]]})
    # factory: NnFacOpt's 16 numbers, value - best, n (nnlog.as NnFacScore)
    S = as_const(w, "NNF_S")
    m, s = as_const(w, "NNF_XM"), as_const(w, "NNF_XS")
    lay["heads"].append({"key": "factory", "kind": "list", "K": -1, "F": 18,
                         "m": m[S:S + 18], "s": [max(v, 0.05) for v in s[S:S + 18]]})
    return lay


def head_size(h):
    K = h["K"] if h["K"] > 0 else 1
    return H2 * (H1 + h["F"] + 1) + K * (H2 + 1)


def n_weights(lay):
    return H1 * (len(lay["idx"]) + 1) + sum(head_size(h) for h in lay["heads"])


def blocks(lay):
    """Whole neurons of the shared layer, then whole heads: what a crossover swaps."""
    out, at = [], 0
    N = len(lay["idx"])
    for _ in range(H1):
        out.append((at, at + N + 1))
        at += N + 1
    for h in lay["heads"]:
        out.append((at, at + head_size(h)))
        at += head_size(h)
    return out


def middle(lay, rng):
    """Small random hidden weights (so the neurons differ), every output weight 0: each value at the
    log-middle of its range, each choice the rule's, each list the market's."""
    v = []
    N = len(lay["idx"])
    for _ in range(H1):
        v += [rng.gauss(0, 1 / math.sqrt(N)) for _ in range(N)] + [0.0]
    for h in lay["heads"]:
        fan = H1 + h["F"]
        for _ in range(H2):
            v += [rng.gauss(0, 1 / math.sqrt(fan)) for _ in range(fan)] + [0.0]
        K = h["K"] if h["K"] > 0 else 1
        v += [0.0] * (K * (H2 + 1))
    return v


def aslit(x):
    """An AngelScript float literal: it needs a decimal point (8f does not parse)."""
    s = "%.6g" % x
    if "." not in s:
        s = s.replace("e", ".0e") if "e" in s else s + ".0"
    return s + "f"


def fmt(xs, fl=True):
    if fl:
        return "{" + ", ".join(aslit(x) for x in xs) + "}"
    return "{" + ", ".join(str(x) for x in xs) + "}"


def write_data(path, lay, best):
    heads = lay["heads"]
    fm = [x for h in heads for x in h["m"]]
    fs = [x for h in heads for x in h["s"]]
    keys = ", ".join('"%s"' % h["key"] for h in heads)
    txt = "\n".join([
        "namespace Market {",
        "",
        "// The policy net's layout, input scaling and all-time best weights: written by tools/neuro.py.",
        "// The repo copy carries no weights (every head at its middle); the deployed copy carries the best.",
        'const string PN_STATE = "%s";' % lay["state"],
        "const array<int> PN_IDX = %s;" % fmt(lay["idx"], False),
        "const array<float> PN_M = %s;" % fmt(lay["m"]),
        "const array<float> PN_S = %s;" % fmt(lay["s"]),
        "const int PN_H1 = %d;" % H1,
        "const int PN_H2 = %d;" % H2,
        "const float PN_FLOOR = %s;" % aslit(FLOOR),
        "const float PN_LGAIN = %s;" % aslit(LGAIN),
        "const array<string> PN_HEADS = {%s};" % keys,
        "// outputs per head: 0 = a continuous value, -1 = a list (one score per option)",
        "const array<int> PN_HK = %s;" % fmt([h["K"] for h in heads], False),
        "const array<int> PN_HF = %s;" % fmt([h["F"] for h in heads], False),
        "const array<float> PN_FM = %s;" % fmt(fm),
        "const array<float> PN_FS = %s;" % fmt(fs),
        "const array<float> PN_BEST = %s;" % (fmt(best) if best else "{}"),
        "",
        "}  // namespace Market",
        ""])
    tmp = str(path) + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(txt)
    os.replace(tmp, path)


def deployed_data_paths():
    env = bar_env.load()
    out = []
    for root in (env.skirmish_dir("Apexnnlog", "lane-nnlog"), env.game_config_dir("Apexnnlog", "lane-nnlog")):
        if (root / DATA_REL).parent.is_dir():
            out.append(root / DATA_REL)
    return out


def bests():
    try:
        return json.load(open(BEST, encoding="utf-8"))
    except (OSError, ValueError):
        return {"best": None, "runs": []}


def publish(st):
    """The all-time best into every deployed copy (redeploys overwrite it with the empty repo copy)."""
    b = bests()["best"]
    for p in deployed_data_paths():
        write_data(p, st["layout"], b["w"] if b else None)


def load():
    return json.load(open(STATE, encoding="utf-8"))


def save(st):
    tmp = STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(st, fh)
    os.replace(tmp, STATE)


def play(job):
    gen_dir, ci, gi, per_side, mapn, seed, opt_file, slot = job
    out = os.path.join(gen_dir, "matches", "c%02d-g%d" % (ci, gi))
    if os.path.exists(os.path.join(out, "result.json")):
        return ci, gi, cem.score(out)
    cmd = [sys.executable, "-u", os.path.join(REPO, "tools", "run_match.py"), "--a", AI, "--b", FOE,
           "--map", mapn, "--minutes", str(MINUTES), "--seed", str(seed), "--speed", "20",
           "--per-side", str(per_side), "--sides", "random,random", "--out", out,
           "--write-dir", os.path.join("runtime", "engine-cem-%d" % slot),
           "--modoption", "apex_lag_speed=0", "--modoption", "apex_nn_explore=0",
           "--ai-options-file", opt_file]
    with open(os.path.join(gen_dir, "c%02d-g%d.log" % (ci, gi)), "w", encoding="utf-8") as fh:
        subprocess.run(cmd, cwd=REPO, stdout=fh, stderr=subprocess.STDOUT, timeout=3600)
    return ci, gi, cem.score(out)


def opt_file(gen_dir, ci, w):
    """The weights go in a file the AI reads (a start script cannot hold thousands of options)."""
    wp = os.path.abspath(os.path.join(gen_dir, "c%02d.weights" % ci)).replace("\\", "/")
    with open(wp, "w", encoding="utf-8") as fh:
        fh.write(" ".join("%.6g" % x for x in w))
    p = os.path.join(gen_dir, "c%02d.json" % ci)
    with open(p, "w", encoding="utf-8") as fh:
        json.dump({"apex_pw_file": wp}, fh)
    return p


def mutate(w, rng, sig, pm):
    return [x + rng.gauss(0, sig) if rng.random() < pm else x for x in w]


def cross(a, b, rng, blks):
    c = list(a)
    for lo, hi in blks:
        if rng.random() < 0.5:
            c[lo:hi] = b[lo:hi]
    return c


def sample(st, rng):
    rnd = st["round"]
    sig = max(SIG_END, SIG0 * DECAY ** rnd)
    pm = max(PM_END, PM0 * DECAY ** rnd)
    elite = [e["w"] for e in st["elite"]]
    if not elite:
        return [st["start"]] + [mutate(st["start"], rng, sig, pm) for _ in range(CANDS - 1)], sig, pm
    cands = [list(e) for e in elite]
    blks = blocks(st["layout"])
    while len(cands) < CANDS:
        if len(cands) % 3 == 2 and len(elite) > 1:
            a, b = rng.sample(elite, 2)
            cands.append(mutate(cross(a, b, rng, blks), rng, sig * 0.5, pm))
        else:
            wts = [len(elite) - i for i in range(len(elite))]
            cands.append(mutate(rng.choices(elite, weights=wts)[0], rng, sig, pm))
    return cands, sig, pm


def workers():
    return cem.workers()


def run_games(gen_dir, cands, games):
    w = workers()
    files = [opt_file(gen_dir, ci, x) for ci, x in enumerate(cands)]
    jobs = []
    for ci in range(len(cands)):
        for gi, (ps, mapn, seed) in enumerate(games):
            jobs.append((gen_dir, ci, gi, ps, mapn, seed, files[ci], len(jobs) % w))
    scores, results = {}, {}
    with ThreadPoolExecutor(max_workers=w) as ex:
        for ci, gi, sc in ex.map(play, jobs):
            if sc is not None:
                scores.setdefault(ci, []).append(sc[0])
                results.setdefault(ci, []).append(sc[1])
    return scores, results, w


def generation(st):
    gen = st["gen"] + 1
    rng = random.Random(gen * 7919 + 17)
    games = list(GAMES)
    old = sorted(glob.glob(os.path.join(REPO, "tournaments", "*-nn-neuro-g%d" % gen)))
    cfg = None
    if old:
        try:
            cfg = json.load(open(os.path.join(old[-1], "config.json"), encoding="utf-8"))
        except (OSError, ValueError):
            cfg = None
    if cfg and len(cfg.get("cands", [])) == CANDS:
        gen_dir, cands, games = old[-1], cfg["cands"], [tuple(g) for g in cfg["games"]]
        sig, pm = cfg["sig"], cfg["pm"]
        log("gen %d: resuming %s" % (gen, os.path.basename(gen_dir)))
    else:
        cands, sig, pm = sample(st, rng)
        gen_dir = os.path.join(REPO, "tournaments", time.strftime("%Y%m%d-%H%M%S") + "-nn-neuro-g%d" % gen)
        os.makedirs(os.path.join(gen_dir, "matches"), exist_ok=True)
        with open(os.path.join(gen_dir, "config.json"), "w", encoding="utf-8") as fh:
            json.dump({"gen": gen, "run": st["run"], "round": st["round"] + 1, "sig": sig, "pm": pm,
                       "games": games, "cands": cands}, fh)
    log("gen %d (run %d round %d): %d networks x %d games, nudge %.3f on %.0f%% of weights -> %s" % (
        gen, st["run"], st["round"] + 1, CANDS, len(games), sig, 100 * pm, os.path.basename(gen_dir)))
    scores, results, w = run_games(gen_dir, cands, games)
    # a carried elite is judged on all its games, every mean pulled SHRINK games toward the round's
    prev = [e.get("scores") or [] for e in st["elite"]]
    done = {ci: v for ci, v in scores.items() if len(v) == len(games)}
    flat = [s for v in done.values() for s in v]
    avg = sum(flat) / len(flat) if flat else 0.0
    allsc = {ci: (prev[ci] if ci < len(prev) else []) + v for ci, v in done.items()}
    ranked = sorted(((sum(v) + SHRINK * avg) / (len(v) + SHRINK), ci) for ci, v in allsc.items())
    ranked.reverse()
    st["gen"] = gen
    if len(ranked) < ELITE:
        log("gen %d: only %d networks scored -- round repeated" % (gen, len(ranked)))
        return st
    st["round"] += 1
    st["elite"] = [{"w": cands[ci], "score": round(s, 4), "scores": [round(x, 4) for x in allsc[ci]][-24:]}
                   for s, ci in ranked[:ELITE]]
    res = "".join("".join(results.get(ci, [])) for _, ci in ranked)
    st["history"].append({"gen": gen, "run": st["run"], "round": st["round"], "dir": os.path.basename(gen_dir),
                          "best": round(ranked[0][0], 3), "avg": round(avg, 3),
                          "elite": [round(s, 3) for s, _ in ranked[:ELITE]], "results": res, "sig": sig, "pm": pm})
    st["history"] = st["history"][-400:]
    log("gen %d: best %.3f, round average %.3f, elite %s, results by rank %s" % (
        gen, ranked[0][0], avg, [round(s, 2) for s, _ in ranked[:ELITE]], res))
    return st


def mean_score(gen_dir, ci, wts, games, tag):
    w = workers()
    f = opt_file(gen_dir, ci, wts)
    jobs = [(gen_dir, ci, gi, ps, mapn, seed, f, gi % w) for gi, (ps, mapn, seed) in enumerate(games)]
    with ThreadPoolExecutor(max_workers=w) as ex:
        got = [sc for _, _, sc in ex.map(play, jobs) if sc is not None]
    log("validate %s: %d/%d games, results %s, score %s" % (
        tag, len(got), len(games), "".join(r for _, r in got),
        "%.3f" % (sum(s for s, _ in got) / len(got)) if got else "-"))
    return (sum(s for s, _ in got) / len(got)) if len(got) >= len(games) // 2 + 1 else None


def finish_run(st):
    final = st["elite"][0]["w"]
    games = list(VALID)
    gen_dir = os.path.join(REPO, "tournaments", time.strftime("%Y%m%d-%H%M%S") + "-nn-neuro-run%d-valid" % st["run"])
    os.makedirs(os.path.join(gen_dir, "matches"), exist_ok=True)
    bs = bests()
    sf = mean_score(gen_dir, 0, final, games, "run %d final" % st["run"])
    other = bs["best"]["w"] if bs["best"] else st["middle"]
    sb = mean_score(gen_dir, 1, other, games, "all-time best" if bs["best"] else "the middle")
    rec = {"run": st["run"], "at": time.strftime("%Y-%m-%d %H:%M"), "rounds": st["round"], "score": sf,
           "vs": sb, "valid_dir": os.path.basename(gen_dir), "w": final}
    bs["runs"].append(rec)
    if sf is not None and (sb is None or sf > sb):
        bs["best"] = {"w": final, "score": sf, "run": st["run"], "at": rec["at"]}
        log("run %d: NEW ALL-TIME BEST (%.3f vs %s)" % (st["run"], sf, "-" if sb is None else "%.3f" % sb))
    else:
        log("run %d: all-time best kept (%s vs final %s)" % (st["run"], "-" if sb is None else "%.3f" % sb,
                                                            "-" if sf is None else "%.3f" % sf))
    tmp = BEST + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(bs, fh)
    os.replace(tmp, BEST)
    nxt = st["run"] + 1
    fresh = (nxt % FRESH_EVERY == 0) or bs["best"] is None
    if fresh:
        st["start"] = middle(st["layout"], random.Random(nxt * 31337))
        st["elite"] = []
    else:
        st["start"] = bs["best"]["w"]
        st["elite"] = [{"w": bs["best"]["w"], "score": None, "scores": []}]
    st["run"], st["round"] = nxt, 0
    log("run %d starts from %s" % (nxt, "a fresh middle network" if fresh else "the all-time best"))
    return st


def init():
    lay = build_layout()
    mid = middle(lay, random.Random(1))
    st = {"layout": lay, "gen": 0, "run": 1, "round": 0, "elite": [], "history": [], "middle": mid, "start": mid}
    write_data(os.path.join(MARKET, "policydata.as"), lay, None)
    if os.path.exists(STATE):
        os.replace(STATE, STATE + ".%s.bak" % time.strftime("%m%d-%H%M"))
    save(st)
    log("init: %d inputs -> %d shared -> %d heads (%d values, %d choices, %d lists), %d weights" % (
        len(lay["idx"]), H1, len(lay["heads"]), sum(h["kind"] == "val" for h in lay["heads"]),
        sum(h["kind"] == "pick" for h in lay["heads"]), sum(h["kind"] == "list" for h in lay["heads"]),
        n_weights(lay)))


def status(st):
    lay = st["layout"]
    print("run %d round %d/%d  gen %d  weights %d" % (st["run"], st["round"], GENS_PER_RUN, st["gen"], n_weights(lay)))
    b = bests()
    if b["best"]:
        print("  ALL-TIME BEST: run %d (%s), score %.3f" % (b["best"]["run"], b["best"]["at"], b["best"]["score"]))
    for r in b["runs"][-6:]:
        print("  run %d final %s vs %s" % (r["run"], r["score"], r["vs"]))
    for e in st["history"][-10:]:
        print("  gen %d r%d.%d best %.3f avg %.3f nudge %.3f/%.0f%% %s" % (
            e["gen"], e["run"], e["round"], e["best"], e["avg"], e["sig"], 100 * e["pm"], e["results"]))


def main(argv):
    if "--init" in argv:
        init()
        return 0
    st = load()
    if "--status" in argv:
        status(st)
        return 0
    if st["layout"]["state"] != nn_state_source():
        raise SystemExit("NN_STATE changed since --init: the weights no longer mean what they did")
    publish(st)
    while not os.path.exists(STOP):
        st = generation(st)
        save(st)
        if st["round"] >= GENS_PER_RUN:
            st = finish_run(st)
            save(st)
            publish(st)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
