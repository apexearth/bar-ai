"""The training loop for learning from our own choices (his 10-28, option A; the random search is stopped).

Keeps up to `workers` games running (runtime/nn/workers-cem; 1 while his game runs), each on its own random setup
(randsearch.draw_setup: any map, 1-8 a side, factions, opponent, handicap, length), playing the newest network with
the training push on. Every BATCH finished games: one cautious policy-gradient step (tools/pgtrain.py) and a new
version, which the next games play. A game that did not play its own weights pauses the loop.

    python tools/pgloop.py            # runs while runtime/pg/pg_on exists (runtime/nn_keepalive.sh restarts it)
    python tools/pgloop.py --status

State: runtime/pg/state.json, weights runtime/pg/v<N>.weights, history runtime/pg/history.jsonl, games in
tournaments/<stamp>-pg/matches/c<version>-g<game>.
"""
from __future__ import annotations

import json
import os
import random
import re
import sys
import threading
import time
import traceback
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
import cem  # noqa: E402
import neuro  # noqa: E402
import pgtrain  # noqa: E402
import randsearch  # noqa: E402

PG = os.path.join(REPO, "runtime", "pg")
STATE = os.path.join(PG, "state.json")
HISTORY = os.path.join(PG, "history.jsonl")
LOG = os.path.join(PG, "pg.log")
ON = os.path.join(PG, "pg_on")
BATCH = 16
SIGMA, SIGMA_TILT = 0.15, 0.05
LR, MAX_SHIFT = 3e-3, 0.02
POLICY_RX = re.compile(r"apex: policy ON t=\d+ src=(\w+) n=(\d+) given=(\d+)")


def log(msg):
    line = time.strftime("%m-%d %H:%M ") + msg
    print(line, flush=True)
    with open(LOG, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def wpath(v):
    return os.path.join(PG, "v%d.weights" % v)


def opts_path(st, v):
    p = os.path.join(st["dir"], "v%d.json" % v)
    if not os.path.exists(p):
        with open(p, "w", encoding="utf-8") as fh:
            json.dump({"apex_pw_file": wpath(v).replace("\\", "/"), "apex_pn_explore": str(SIGMA),
                       "apex_pn_explore_tilt": str(SIGMA_TILT)}, fh)
    return p


def load_state(lay):
    if os.path.exists(STATE):
        return json.load(open(STATE, encoding="utf-8"))
    os.makedirs(PG, exist_ok=True)
    pgtrain.write_weights(wpath(0), pgtrain.init_weights(lay, seed=1))
    d = os.path.join(REPO, "tournaments", time.strftime("%Y%m%d-%H%M%S") + "-pg")
    os.makedirs(os.path.join(d, "matches"), exist_ok=True)
    st = {"dir": d, "version": 0, "next_game": 0, "pending": [], "started": time.strftime("%Y-%m-%d %H:%M")}
    save(st)
    log("new run: v0 at the rule, games in %s" % d)
    return st


def save(st):
    tmp = STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(st, fh, indent=1)
    os.replace(tmp, STATE)


def play(st, v, gi, slot):
    seed = randsearch.game_seed(10000 + v, gi)
    setup = randsearch.draw_setup(seed)
    setup["version"] = v
    with open(os.path.join(st["dir"], "c%02d-g%d.setup.json" % (v, gi)), "w", encoding="utf-8") as fh:
        json.dump(setup, fh)
    _, _, sc = neuro.play((st["dir"], v, gi, setup["per_side"], setup["map"], seed, opts_path(st, v), slot,
                           setup["foe"], setup))
    out = os.path.join(st["dir"], "matches", "c%02d-g%d" % (v, gi))
    if sc is None:
        randsearch.note_bad_map(setup["map"])
    return out, sc


def own_weights(out):
    try:
        m = POLICY_RX.search(open(os.path.join(out, "infolog.txt"), encoding="utf-8", errors="replace").read())
    except OSError:
        return True
    return (m is None) or (m.group(1) == "file")


def pause(why):
    log("PAUSED: " + why)
    try:
        os.replace(ON, ON + ".paused")
    except OSError:
        pass


def step(st, lay):
    games = []
    for p in st["pending"]:
        g = pgtrain.read_match(p["dir"], lay)
        if g and g["rows"]:
            c = pgtrain.check(pgtrain.read_weights(wpath(p["version"]), lay), [g], lay)
            if c["maxAbs"] > 0.01:
                pause("%s: the trainer's copy differs from what the game did (%s)" % (p["dir"], json.dumps(c)))
                return
            g["score"], g["version"] = p.get("score"), p["version"]
            games.append(g)
    v = st["version"]
    w = pgtrain.read_weights(wpath(v), lay)
    try:
        w2, rep = pgtrain.train(w, games, lay, LR, MAX_SHIFT)
    except SystemExit as e:
        log("no step: %s" % e)
        return
    scores = [g["score"] for g in games if g["score"] is not None]
    rep.update({"version": v + 1, "at": time.strftime("%Y-%m-%d %H:%M"),
                "meanScore": round(sum(scores) / len(scores), 3) if scores else None,
                "wins": sum(1 for g in games if g["result"] == "W"), "losses": sum(1 for g in games if g["result"] == "L"),
                "playedBy": sorted({g["version"] for g in games})})
    pgtrain.write_weights(wpath(v + 1), w2)
    with open(HISTORY, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(rep) + "\n")
    st["version"] = v + 1
    st["pending"] = []
    save(st)
    top = sorted(rep["heads"], key=lambda q: -max(abs(t) for t in q["t"]))[:4]
    log("v%d: %d games, %d decisions, score %s, W%d L%d, %d steps, shift %.3f; strongest signal %s" % (
        v + 1, rep["games"], rep["decisions"], rep["meanScore"], rep["wins"], rep["losses"], rep["steps"],
        rep["meanShift"], ", ".join("%s t=%s" % (q["name"], q["t"]) for q in top)))


def status():
    st = json.load(open(STATE, encoding="utf-8")) if os.path.exists(STATE) else None
    if not st:
        print("no run yet")
        return
    print("version %d, %d games launched, %d waiting for the next step, games in %s" % (
        st["version"], st["next_game"], len(st["pending"]), st["dir"]))
    if os.path.exists(HISTORY):
        for line in open(HISTORY, encoding="utf-8").read().splitlines()[-10:]:
            r = json.loads(line)
            print("  v%-3d %s  games %2d  decisions %5d  score %s  W%d L%d  shift %.3f" % (
                r["version"], r["at"], r["games"], r["decisions"], r["meanScore"], r["wins"], r["losses"],
                r["meanShift"]))


def main(argv):
    if "--status" in argv:
        status()
        return 0
    lay = pgtrain.Layout()
    st = load_state(lay)
    lock = threading.Lock()
    running = {}
    with ThreadPoolExecutor(max_workers=16) as ex:
        while True:
            if not os.path.exists(ON):
                log("pg_on gone: finishing the running games, then stopping")
                wait(list(running))
                return 0
            w = cem.workers()
            while len(running) < w:
                with lock:
                    gi = st["next_game"]
                    st["next_game"] += 1
                    v = st["version"]
                    save(st)
                slot = 100 + (gi % 64)
                running[ex.submit(play, st, v, gi, slot)] = (v, gi)
            done, _ = wait(list(running), timeout=30, return_when=FIRST_COMPLETED)
            for fut in done:
                v, gi = running.pop(fut)
                try:
                    out, sc = fut.result()
                except Exception:
                    log("game c%02d-g%d raised: %s" % (v, gi, traceback.format_exc().strip().replace("\n", " | ")))
                    continue
                if not own_weights(out):
                    pause("c%02d-g%d did not play its own weights" % (v, gi))
                    continue
                with lock:
                    st["pending"].append({"dir": out, "version": v, "score": sc})
                    save(st)
                    if len(st["pending"]) >= BATCH:
                        step(st, lay)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
