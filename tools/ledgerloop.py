"""The training loop that learns from what each decision did (his 11-04, todo/learn-from-each-decision.md).

    python tools/ledgerloop.py            # runs while runtime/risk/loop_on exists (runtime/nn_keepalive.sh restarts it)
    python tools/ledgerloop.py --status

Keeps up to `workers` games running (runtime/nn/workers-cem; 1 while his game runs) on lane nnlog, each on its own random
setup (randsearch.draw_setup: any map, 1-8 a side, factions, opponent, handicap, length). The learned job risk prices
those games only while runtime/risk/play_on exists (11-04: as first wired it lost income and constructors in a paired
test, so it learns without steering until a wiring beats the old price).
Every BATCH finished games: the jobs they hold go into the ledger (tools/ledger.py); the model the games played is scored
on them (it never saw them); a candidate is fitted on the window of earlier ledgers and scored on the same games; it
replaces the current model only if it predicts them better, both heads summed. An accepted model is written into the
lane's deployed copies (riskweights.as), never through a deploy of the shared tree, so the games after it play it.
State: runtime/risk/loop.json, models runtime/risk/v<N>.json, ledgers runtime/ledger/loop-<N>.jsonl, games in
tournaments/<stamp>-ledger/matches/c<version>-g<game>.
"""
from __future__ import annotations

import json
import os
import sys
import threading
import time
import traceback
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
import bar_env  # noqa: E402
import cem  # noqa: E402
import ledger  # noqa: E402
import neuro  # noqa: E402
import randsearch  # noqa: E402
import risknet  # noqa: E402

RISK = os.path.join(REPO, "runtime", "risk")
LEDGERS = os.path.join(REPO, "runtime", "ledger")
STATE = os.path.join(RISK, "loop.json")
LOG = os.path.join(RISK, "loop.log")
ON = os.path.join(RISK, "loop_on")
BATCH = 48
WINDOW = 12                      # ledgers fitted on: the seed ledger plus the newest batches
SEED_LEDGER = os.path.join(LEDGERS, "20261104-pg.jsonl")
REL = "script/standard/manager/brain/market/riskweights.as"
lock = threading.Lock()


def log(msg):
    line = time.strftime("%m-%d %H:%M ") + msg
    print(line, flush=True)
    with open(LOG, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def save(st):
    tmp = STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(st, fh, indent=1)
    os.replace(tmp, STATE)


def deployed_paths():
    env = bar_env.load()
    out = []
    for root in (env.skirmish_dir("Apexnnlog", "lane-nnlog"), env.game_config_dir("Apexnnlog", "lane-nnlog")):
        if (root / REL).parent.is_dir():
            out.append(str(root / REL))
    return out


def install(model, version):
    """the model into the lane's deployed copies, and kept as v<N>"""
    with open(os.path.join(RISK, "v%d.json" % version), "w", encoding="utf-8") as fh:
        json.dump(model, fh)
    paths = deployed_paths()
    if len(paths) != 2:
        raise SystemExit("lane nnlog is not deployed with riskweights.as (found %s); deploy it first" % paths)
    for p in paths:
        risknet.export(p, model)


PLAY = os.path.join(RISK, "play_on")   # present: the learned risk prices the games; absent: it only learns from them


def playing():
    return os.path.exists(PLAY)


def opts_path(st):
    on = playing()
    p = os.path.join(st["dir"], "options-%s.json" % ("on" if on else "off"))
    if not os.path.exists(p):
        with open(p, "w", encoding="utf-8") as fh:
            json.dump({"apex_learned_risk": "1" if on else "0"}, fh)
    return p


def load_state():
    if os.path.exists(STATE):
        return json.load(open(STATE, encoding="utf-8"))
    os.makedirs(RISK, exist_ok=True)
    model = json.load(open(os.path.join(RISK, "model.json"), encoding="utf-8"))
    d = os.path.join(REPO, "tournaments", time.strftime("%Y%m%d-%H%M%S") + "-ledger")
    os.makedirs(os.path.join(d, "matches"), exist_ok=True)
    st = {"dir": d, "version": 0, "next_game": 0, "pending": [], "ledgers": [SEED_LEDGER], "history": [],
          "started": time.strftime("%Y-%m-%d %H:%M")}
    install(model, 0)
    save(st)
    log("new run: v0 = runtime/risk/model.json (%d jobs), games in %s" % (model["fitted"]["jobs"], d))
    return st


def risk_was_on(out):
    try:
        txt = open(os.path.join(out, "infolog.txt"), encoding="utf-8", errors="replace").read()
    except OSError:
        return False
    return "apex: risk t=" in txt and " on=1" in txt


def play(st, v, gi, slot):
    seed = randsearch.game_seed(20000 + v, gi)
    setup = randsearch.draw_setup(seed)
    setup["version"] = v
    with open(os.path.join(st["dir"], "c%02d-g%d.setup.json" % (v, gi)), "w", encoding="utf-8") as fh:
        json.dump(setup, fh)
    neuro.play((st["dir"], v, gi, setup["per_side"], setup["map"], seed, opts_path(st), slot, setup["foe"], setup))
    return os.path.join(st["dir"], "matches", "c%02d-g%d" % (v, gi))


def step(st):
    v = st["version"]
    batch, rest = st["pending"][:BATCH], st["pending"][BATCH:]
    games = [p for p in batch if os.path.exists(os.path.join(p, "result.json"))]
    off = [p for p in games if not risk_was_on(p)] if playing() else []
    if off:
        log("PAUSED: %d games did not play the learned risk (first %s)" % (len(off), off[0]))
        os.replace(ON, ON + ".paused")
        return
    path = os.path.join(LEDGERS, "loop-%d.jsonl" % v)
    rows = []
    for g in games:
        rows += ledger.read_game(g)
    names = next((r.pop("_names") for r in rows if "_names" in r), None)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps({"schema": names}) + "\n")
        for r in rows:
            r.pop("_names", None)
            fh.write(json.dumps(r) + "\n")
    cur = json.load(open(os.path.join(RISK, "v%d.json" % v), encoding="utf-8"))
    window = st["ledgers"][-WINDOW:]
    cand = risknet.fit_model(window)
    s_cur, s_cand = risknet.score(cur, [path]), risknet.score(cand, [path])
    loss = lambda s: s["frame"]["loss"] + s["builder"]["loss"]  # noqa: E731
    take = loss(s_cand) < loss(s_cur)
    rec = {"version": v, "at": time.strftime("%Y-%m-%d %H:%M"), "games": len(games), "current": s_cur,
           "candidate": s_cand, "accepted": take}
    st["history"].append(rec)
    st["ledgers"].append(path)
    st["pending"] = rest
    if take:
        st["version"] = v + 1
        install(cand, v + 1)
    save(st)
    log("v%d on %d new games (%d jobs): current frame %.4f/%.3f builder %.4f/%.3f | candidate frame %.4f/%.3f "
        "builder %.4f/%.3f (fit on %d ledgers) -> %s" % (
            v, len(games), s_cur["jobs"], s_cur["frame"]["loss"], s_cur["frame"]["auc"] or 0, s_cur["builder"]["loss"],
            s_cur["builder"]["auc"] or 0, s_cand["frame"]["loss"], s_cand["frame"]["auc"] or 0,
            s_cand["builder"]["loss"], s_cand["builder"]["auc"] or 0, len(window),
            ("v%d accepted" % (v + 1)) if take else "kept v%d" % v))


def status():
    if not os.path.exists(STATE):
        print("no run yet")
        return
    st = json.load(open(STATE, encoding="utf-8"))
    print("version %d, %d games launched, %d waiting, games in %s" % (
        st["version"], st["next_game"], len(st["pending"]), st["dir"]))
    for r in st["history"][-10:]:
        c, d = r["current"], r["candidate"]
        print("  %s v%-3d games %2d  current %.4f+%.4f  candidate %.4f+%.4f  %s" % (
            r["at"], r["version"], r["games"], c["frame"]["loss"], c["builder"]["loss"], d["frame"]["loss"],
            d["builder"]["loss"], "accepted" if r["accepted"] else "kept"))


def main(argv):
    if "--status" in argv:
        status()
        return
    st = load_state()
    running = {}
    with ThreadPoolExecutor(max_workers=16) as ex:
        while True:
            on = os.path.exists(ON)
            w = cem.workers()
            slots = [s for s in range(16) if s not in {r[1] for r in running.values()}]
            while on and len(running) < w and slots:
                gi = st["next_game"]
                st["next_game"] += 1
                save(st)
                slot = slots.pop(0)
                running[ex.submit(play, st, st["version"], gi, slot)] = (gi, slot)
            if len(st["pending"]) >= BATCH:
                try:
                    step(st)
                except Exception:
                    log("step failed:\n" + traceback.format_exc())
                    os.replace(ON, ON + ".paused")
                    return
                continue
            if not running:
                if not on:
                    log("loop_on gone: stopped")
                    return
                time.sleep(5)
                continue
            done, _ = wait(list(running), timeout=30, return_when=FIRST_COMPLETED)
            for f in done:
                gi, slot = running.pop(f)
                try:
                    out = f.result()
                    st["pending"].append(out)
                except Exception:
                    log("game %d failed:\n%s" % (gi, traceback.format_exc()))
                save(st)


if __name__ == "__main__":
    main(sys.argv[1:])
