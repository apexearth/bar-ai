"""Random search over the policy network's weights, winners re-tested (his 10-11: annealing was not finding
anything; randomize every network, take the wins, rerun them several times to see if they are genuinely
good, and end with a list of viable weight sets that can later play each other).

Every new network is the middle network (neuro.py) with EVERY weight nudged by N(0, s), s drawn per
network log-uniformly from S_RANGE, so mild and wild networks are both tried. It plays one game. A
network climbs the ladder while it keeps winning: at LADDER[i] games it needs NEED[i] wins (a draw is
half) to be owed games up to LADDER[i+1]. Networks that reach the top are the viable list. Re-tests
are played before new networks. A network is stored as its seed and s, so it can be rebuilt exactly.

ANNEALING (his 10-11, once net 99 proved out): with a centre set, most new networks are the centre's
played weights plus N(0, s), s log-uniform in [T/4, T], T halving every ANNEAL_HALF children down to
ANNEAL_FLOOR; the rest stay random. The centre is owed CENTRE_GAMES games so children are judged
against a firm record, and a child that clears the ladder with a better win rate takes its place.

Same game as neuro.py -- 1v1, Comet Catcher, against BARb -- but every game its own seed (game_seed), so
the engine RNG and the faction draw vary; games before 10-11 15:00 were all seed 1.

    python tools/randsearch.py            # play until EXPLORE networks are tried and every re-test is done
    python tools/randsearch.py --status
    python tools/randsearch.py --anneal 99   # (while stopped) anneal around net 99
State: runtime/nn/rand.json; log: runtime/nn/rand.log; games: tournaments/<stamp>-nn-rand/.
"""
import json, math, os, random, sys, threading, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
import neuro

STATE = os.path.join(neuro.NN, "rand.json")
LOG = os.path.join(neuro.NN, "rand.log")
RESTART = os.path.join(neuro.NN, "rand_restart")
EXPLORE = 1000
S_RANGE = (0.1, 0.8)
LADDER = [1, 4, 12, 24]
NEED = [1, 2, 5]
MAX_FAILS = 3
MAX_WORKERS = 10
ANNEAL_SHARE = 1.0
ANNEAL_CHILDREN = 450
ANNEAL_T0 = 0.2
ANNEAL_HALF = 150
ANNEAL_FLOOR = 0.03
CENTRE_GAMES = 48

lock = threading.Lock()


def log(msg):
    line = time.strftime("%m-%d %H:%M ") + msg
    print(line, flush=True)
    with open(LOG, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def weights(lay, seed, s):
    rng = random.Random(seed)
    return [x + rng.gauss(0, s) for x in neuro.middle(lay, rng)]


def played_weights(st, nid):
    """The exact weights a network's games played."""
    return [float(x) for x in open(os.path.join(st["dir"], "c%02d.weights" % nid), encoding="utf-8").read().split()]


def temperature(st):
    a = st.get("anneal") or {}
    return max(ANNEAL_FLOOR, ANNEAL_T0 * 0.5 ** (a.get("born", 0) / ANNEAL_HALF))


def game_seed(nid, gi):
    """Every game its own seed (his 10-11: not only the same seeds) -- the engine RNG and the faction draw --
    fixed by network and game number, so any game can be replayed."""
    return (nid * 7919 + gi * 104729) % 1000003 + 2


def wins(n):
    return sum({"W": 1.0, "D": 0.5}.get(r, 0.0) for _, r in n["games"])


def rate(n):
    return wins(n) / len(n["games"]) if n["games"] else 0.0


def load():
    if os.path.exists(STATE):
        return json.load(open(STATE, encoding="utf-8"))
    return {"dir": os.path.join(REPO, "tournaments", time.strftime("%Y%m%d-%H%M%S") + "-nn-rand"), "nets": {}, "next": 0}


def save(st):
    tmp = STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(st, fh)
    os.replace(tmp, STATE)


def owed(n):
    return n["status"] == "live" and len(n["games"]) + n["busy"] < n["target"]


def next_job(st, lay, rng):
    """A re-test first (highest rung, then oldest), else a new random network."""
    a = st.get("anneal")
    if a and a.get("born", 0) >= ANNEAL_CHILDREN and not any(
            "base" in n and (owed(n) or n["busy"]) for n in st["nets"].values()):
        # his 10-11: find the best version, deploy it if it is better, then back to searching
        c = st["nets"][str(a["centre"])]
        log("ANNEAL DONE after %d children: best is net %d, %.1f wins of %d (%.0f%%) -- random search resumes" % (
            a["born"], c["id"], wins(c), len(c["games"]), 100 * rate(c)))
        st.setdefault("anneal_done", []).append(dict(a, at=time.strftime("%Y-%m-%d %H:%M")))
        del st["anneal"]
    live = [n for n in st["nets"].values() if owed(n)]
    if live:
        n = max(live, key=lambda n: (n["target"], -n["id"]))
    elif st["next"] < EXPLORE:
        i = st["next"]
        st["next"] += 1
        a = st.get("anneal")
        if a and a.get("born", 0) < ANNEAL_CHILDREN and rng.random() < ANNEAL_SHARE:
            t = temperature(st)
            s = math.exp(rng.uniform(math.log(t / 4), math.log(t)))
            n = {"id": i, "seed": rng.randrange(1 << 30), "s": round(s, 4), "base": a["centre"], "games": [],
                 "busy": 0, "tries": 0, "fails": 0, "target": LADDER[0], "status": "live"}
            a["born"] = a.get("born", 0) + 1
            child = random.Random(n["seed"])
            w = [x + child.gauss(0, n["s"]) for x in played_weights(st, a["centre"])]
        else:
            s = math.exp(rng.uniform(math.log(S_RANGE[0]), math.log(S_RANGE[1])))
            n = {"id": i, "seed": rng.randrange(1 << 30), "s": round(s, 4), "games": [], "busy": 0, "tries": 0,
                 "fails": 0, "target": LADDER[0], "status": "live"}
            w = weights(lay, n["seed"], n["s"])
        st["nets"][str(i)] = n
        neuro.opt_file(st["dir"], i, w)
    else:
        return None
    gi = n["tries"]
    n["tries"] += 1
    n["busy"] += 1
    return n, gi


def finish(st, n, gi, sc):
    n["busy"] -= 1
    if sc is None:
        n["fails"] += 1
        if n["fails"] >= MAX_FAILS:
            n["status"] = "failed"
        return
    n["games"].append([round(sc[0], 4), sc[1]])
    if len(n["games"]) < n["target"] or n["busy"]:
        return
    a = st.get("anneal")
    if n["target"] not in LADDER:   # the centre's extra games
        n["status"] = "viable"
        log("centre net %d: %.1f wins of %d (%.0f%%)" % (n["id"], wins(n), len(n["games"]), 100 * rate(n)))
        return
    rung = LADDER.index(n["target"])
    if rung == len(LADDER) - 1:
        n["status"] = "viable"
        log("net %d VIABLE: %.1f wins of %d, s %.2f%s" % (n["id"], wins(n), len(n["games"]), n["s"],
                                                         (" (child of %d)" % n["base"]) if "base" in n else ""))
        c = st["nets"].get(str(a["centre"])) if a else None
        if c is not None and c is not n and len(c["games"]) >= LADDER[-1] and rate(n) > rate(c):
            log("ANNEAL: net %d takes the centre from net %d (%.0f%% of %d vs %.0f%% of %d)" % (
                n["id"], c["id"], 100 * rate(n), len(n["games"]), 100 * rate(c), len(c["games"])))
            a["centre"] = n["id"]
            n["target"] = CENTRE_GAMES
            n["status"] = "live"
    elif wins(n) >= NEED[rung]:
        n["target"] = LADDER[rung + 1]
        if rung:
            log("net %d up to %d games: %.1f wins of %d, s %.2f" % (n["id"], n["target"], wins(n), len(n["games"]), n["s"]))
    else:
        n["status"] = "out"


def workers():
    """runtime/nn/workers-cem, at most MAX_WORKERS (his 10-11: 8-10 headless games at once)."""
    try:
        return max(1, min(MAX_WORKERS, int(open(os.path.join(neuro.NN, "workers-cem")).read().strip())))
    except (OSError, ValueError):
        return 4


def worker(slot, st, lay, rng):
    while not os.path.exists(neuro.STOP) and not os.path.exists(RESTART):
        if slot >= workers():
            time.sleep(60)
            continue
        with lock:
            job = next_job(st, lay, rng)
            save(st)
        if job is None:
            time.sleep(30)
            with lock:
                if not any(n["busy"] or owed(n) for n in st["nets"].values()) and st["next"] >= EXPLORE:
                    return
            continue
        n, gi = job
        f = os.path.join(st["dir"], "c%02d.json" % n["id"])
        _, _, sc = neuro.play((st["dir"], n["id"], gi, neuro.GAME[0], neuro.GAME[1], game_seed(n["id"], gi), f, slot))
        with lock:
            finish(st, n, gi, sc)
            save(st)


def status(st):
    nets = list(st["nets"].values())
    played = [n for n in nets if n["games"]]
    first = [n["games"][0][1] for n in played]
    print("networks tried %d of %d, games %d; first games W %d D %d L %d" % (
        st["next"], EXPLORE, sum(len(n["games"]) for n in nets), first.count("W"), first.count("D"), first.count("L")))
    for t in LADDER[1:]:
        at = [n for n in nets if n["target"] >= t or n["status"] == "viable"]
        print("  reached the %2d-game rung: %d (still playing %d)" % (t, len(at), sum(1 for n in at if n["status"] == "live" and n["target"] == t)))
    ranked = sorted([n for n in nets if len(n["games"]) >= LADDER[1]], key=lambda n: (-(wins(n) / len(n["games"])), -sum(x for x, _ in n["games"]) / len(n["games"])))
    print("  best re-tested (a time-limit game goes to the side ahead on eco and army; the middle network wins 23%, the watch network 46%):")
    for n in ranked[:12]:
        print("    net %4d  %4.1f wins of %2d (%3.0f%%)  mean score %+.2f  s %.2f  %s" % (
            n["id"], wins(n), len(n["games"]), 100 * wins(n) / len(n["games"]),
            sum(x for x, _ in n["games"]) / len(n["games"]), n["s"], n["status"]))
    a = st.get("anneal")
    if a:
        c = st["nets"][str(a["centre"])]
        kids = [n for n in nets if "base" in n]
        print("  annealing around net %d (%.1f wins of %d, %.0f%%): T %.3f, %d children, %d past one game, %d viable" % (
            c["id"], wins(c), len(c["games"]), 100 * rate(c), temperature(st), len(kids),
            sum(1 for n in kids if len(n["games"]) > 1), sum(1 for n in kids if n["status"] == "viable")))
    played = [n for n in played if "base" not in n]   # the noise-size split below is for random networks
    lo = [n for n in played if n["s"] < 0.28]
    hi = [n for n in played if n["s"] >= 0.28]
    for tag, grp in (("s < 0.28", lo), ("s >= 0.28", hi)):
        if grp:
            print("  first-game win rate, %s: %.0f%% of %d" % (tag, 100 * sum(1 for n in grp if n["games"][0][1] == "W") / len(grp), len(grp)))


def main(argv):
    st = load()
    if "--status" in argv:
        status(st)
        return 0
    if "--anneal" in argv:
        c = st["nets"][argv[argv.index("--anneal") + 1]]
        st["anneal"] = {"centre": c["id"], "born": (st.get("anneal") or {}).get("born", 0)}
        if len(c["games"]) < CENTRE_GAMES:
            c["target"] = CENTRE_GAMES
            c["status"] = "live"
        save(st)
        log("annealing around net %d (%.1f wins of %d), owed up to %d games" % (c["id"], wins(c), len(c["games"]), CENTRE_GAMES))
        return 0
    lay = neuro.load()["layout"]
    neuro.publish(neuro.load())
    os.makedirs(os.path.join(st["dir"], "matches"), exist_ok=True)
    for n in st["nets"].values():
        n["busy"] = 0
    save(st)
    log("random search: %d of %d networks tried, games in %s" % (st["next"], EXPLORE, os.path.basename(st["dir"])))
    rng = random.Random()
    ts = [threading.Thread(target=worker, args=(i, st, lay, rng)) for i in range(MAX_WORKERS)]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    if os.path.exists(RESTART):
        os.remove(RESTART)
        log("restart asked: exiting")
    else:
        log("random search done")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
