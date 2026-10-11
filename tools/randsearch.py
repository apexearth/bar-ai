"""Random search over the policy network's weights, winners re-tested (his 10-11: annealing was not finding
anything; randomize every network, take the wins, rerun them several times to see if they are genuinely
good, and end with a list of viable weight sets that can later play each other).

Every new network is the middle network (neuro.py) with EVERY weight nudged by N(0, s), s drawn per
network log-uniformly from S_RANGE, so mild and wild networks are both tried. It plays one game. A
network climbs the ladder while it keeps winning: at LADDER[i] games it needs NEED[i] wins (a draw is
half) to be owed games up to LADDER[i+1]. Networks that reach the top are the viable list. Re-tests
are played before new networks. A network is stored as its seed and s, so it can be rebuilt exactly.

Same game as neuro.py: 1v1, Comet Catcher, seed 1, against BARb.

    python tools/randsearch.py            # play until EXPLORE networks are tried and every re-test is done
    python tools/randsearch.py --status
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

lock = threading.Lock()


def log(msg):
    line = time.strftime("%m-%d %H:%M ") + msg
    print(line, flush=True)
    with open(LOG, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def weights(lay, seed, s):
    rng = random.Random(seed)
    return [x + rng.gauss(0, s) for x in neuro.middle(lay, rng)]


def wins(n):
    return sum({"W": 1.0, "D": 0.5}.get(r, 0.0) for _, r in n["games"])


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
    live = [n for n in st["nets"].values() if owed(n)]
    if live:
        n = max(live, key=lambda n: (n["target"], -n["id"]))
    elif st["next"] < EXPLORE:
        i = st["next"]
        st["next"] += 1
        s = math.exp(rng.uniform(math.log(S_RANGE[0]), math.log(S_RANGE[1])))
        n = {"id": i, "seed": rng.randrange(1 << 30), "s": round(s, 4), "games": [], "busy": 0, "tries": 0,
             "fails": 0, "target": LADDER[0], "status": "live"}
        st["nets"][str(i)] = n
        neuro.opt_file(st["dir"], i, weights(lay, n["seed"], n["s"]))
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
    rung = LADDER.index(n["target"])
    if rung == len(LADDER) - 1:
        n["status"] = "viable"
        log("net %d VIABLE: %.1f wins of %d, s %.2f" % (n["id"], wins(n), len(n["games"]), n["s"]))
    elif wins(n) >= NEED[rung]:
        n["target"] = LADDER[rung + 1]
        if rung:
            log("net %d up to %d games: %.1f wins of %d, s %.2f" % (n["id"], n["target"], wins(n), len(n["games"]), n["s"]))
    else:
        n["status"] = "out"


def workers():
    """His 10-11: 4 headless games at most, and 4 also while he plays online (not cem's drop to 1)."""
    try:
        return max(1, min(4, int(open(os.path.join(neuro.NN, "workers-cem")).read().strip())))
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
        _, _, sc = neuro.play((st["dir"], n["id"], gi, neuro.GAME[0], neuro.GAME[1], neuro.GAME[2], f, slot))
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
    ranked = sorted([n for n in nets if len(n["games"]) >= LADDER[1]], key=lambda n: -(wins(n) / len(n["games"])))
    print("  best re-tested (win rate counts a draw as half; the middle network wins about 5 of 24):")
    for n in ranked[:12]:
        print("    net %4d  %4.1f wins of %2d (%3.0f%%)  mean score %+.2f  s %.2f  %s" % (
            n["id"], wins(n), len(n["games"]), 100 * wins(n) / len(n["games"]),
            sum(x for x, _ in n["games"]) / len(n["games"]), n["s"], n["status"]))
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
    lay = neuro.load()["layout"]
    neuro.publish(neuro.load())
    os.makedirs(os.path.join(st["dir"], "matches"), exist_ok=True)
    for n in st["nets"].values():
        n["busy"] = 0
    save(st)
    log("random search: %d of %d networks tried, games in %s" % (st["next"], EXPLORE, os.path.basename(st["dir"])))
    rng = random.Random()
    ts = [threading.Thread(target=worker, args=(i, st, lay, rng)) for i in range(4)]
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
