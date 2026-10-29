"""Training by held leans (10-29, after learning from single pushes found no signal in 883 games).

Every output of the policy network carries a LEAN (the auction one per want kind, production one per kind of unit):
a constant added to the output for the whole game. Games are played in PAIRS on one random setup and seed
(randsearch.draw_setup): one game at lean + p, the other at lean - p, p drawn fresh for each pair over every live
slot at once. The pair's score difference over 2p is the slope of the game's result along each slot, with the setup's
own luck cancelled; a slot's lean moves half a push, by the sign of its slope, only when that slope is 3 standard
errors from zero over the pairs since the slot last moved.

    python tools/leanloop.py            # runs while runtime/lean/lean_on exists (runtime/nn_keepalive.sh restarts it)
    python tools/leanloop.py --status

State: runtime/lean/state.json (leans, moves), runtime/lean/pairs.jsonl (every finished pair: push, scores),
games in tournaments/<stamp>-lean/matches/c<pair>-g<0|1>.
"""
from __future__ import annotations

import glob
import json
import math
import os
import random
import re
import shutil
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

LEAN = os.path.join(REPO, "runtime", "lean")
STATE = os.path.join(LEAN, "state.json")
PAIRS = os.path.join(LEAN, "pairs.jsonl")
LOG = os.path.join(LEAN, "lean.log")
ON = os.path.join(LEAN, "lean_on")
BASE = os.path.join(LEAN, "base.weights")
# an amount's output 1 is the top of its range; a tilt's output x moves the odds by exp(8x)
SIGMA_AMOUNT, SIGMA_TILT = 0.25, 0.1
LIMIT_AMOUNT, LIMIT_TILT = 1.0, 0.5
T_MOVE, MIN_PAIRS, STEP_PAIRS = 3.0, 24, 12
POLICY_RX = re.compile(r"apex: policy ON t=\d+ src=(\w+)")
LEAN_RX = re.compile(r"apex: pn-lean t=\d+ slots=(\d+)")
PNX_RX = re.compile(r"apex: pnx h=(\d+) ")


def wk_teeth():
    p = os.path.join(REPO, "ai", "Unstable", "game-side", "script", "standard", "manager", "brain", "market", "kinds.as")
    return int(re.search(r"const int WK_TEETH = (\d+);", open(p, encoding="utf-8").read()).group(1))


def slots(lay):
    """(head, slot name, amount?) per lean slot, in the order policy.as reads them"""
    out, teeth = [], wk_teeth()
    for h, hk in enumerate(lay.hk):
        name = pgtrain.head_name(lay, h)
        if hk >= 0:
            for k in range(max(1, hk)):
                out.append((h, name if hk == 0 else "%s/%d" % (name, k), hk == 0))
        elif lay.heads[h] == "builder":
            for k in range(teeth + 1):
                out.append((h, "builder/%d" % k, False))
        else:
            for k, c in enumerate(("other", "constructor", "rezbot", "aircraft")):
                out.append((h, "factory/%s" % c, False))
    return out


def kind_names():
    p = os.path.join(REPO, "ai", "Unstable", "game-side", "script", "standard", "manager", "brain", "market", "kinds.as")
    names = {}
    for m in re.finditer(r"const int WK_(\w+) = (\d+);", open(p, encoding="utf-8").read()):
        names.setdefault(int(m.group(2)), m.group(1).lower())
    return names


def live_heads(n_games=120):
    """heads the AI asks at all: those with a logged push in the last learning-from-pushes run"""
    st = os.path.join(REPO, "runtime", "pg", "state.json")
    d = json.load(open(st, encoding="utf-8"))["dir"]
    seen = set()
    logs = sorted(glob.glob(os.path.join(d, "matches", "c*-g*", "infolog.txt")))
    for p in logs[-n_games:]:
        for m in PNX_RX.finditer(open(p, encoding="utf-8", errors="replace").read()):
            seen.add(int(m.group(1)))
    return sorted(seen)


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


def load_state(lay):
    if os.path.exists(STATE):
        return json.load(open(STATE, encoding="utf-8"))
    os.makedirs(LEAN, exist_ok=True)
    if not os.path.exists(BASE):
        shutil.copy(os.path.join(REPO, "runtime", "pg", "v0.weights"), BASE)
    sl = slots(lay)
    live = set(live_heads())
    d = os.path.join(REPO, "tournaments", time.strftime("%Y%m%d-%H%M%S") + "-lean")
    os.makedirs(os.path.join(d, "matches"), exist_ok=True)
    st = {"dir": d, "started": time.strftime("%Y-%m-%d %H:%M"), "next_pair": 0, "steps": 0,
          "names": [s[1] for s in sl], "amount": [s[2] for s in sl], "live": [s[0] in live for s in sl],
          "lean": [0.0] * len(sl), "since": [0] * len(sl), "moves": [], "running": {}}
    save(st)
    log("new run: %d lean slots, %d live (heads %s), base %s, games in %s" % (
        len(sl), sum(st["live"]), sorted(live), BASE, d))
    return st


def sigma(st, i):
    return SIGMA_AMOUNT if st["amount"][i] else SIGMA_TILT


def write_game(st, base, j, sign, push):
    vals = [st["lean"][i] + sign * push[i] for i in range(len(push))]
    wp = os.path.join(st["dir"], "c%04d-g%d.weights" % (j, 0 if sign > 0 else 1))
    with open(wp, "w", encoding="utf-8") as fh:
        fh.write(" ".join("%.6g" % x for x in list(base) + vals))
    op = wp[:-len(".weights")] + ".json"
    with open(op, "w", encoding="utf-8") as fh:
        json.dump({"apex_pw_file": wp.replace("\\", "/")}, fh)
    return op


def new_pair(st, base):
    j = st["next_pair"]
    st["next_pair"] += 1
    rng = random.Random(9001 + j)
    push = [round(rng.gauss(0.0, sigma(st, i)), 4) if st["live"][i] else 0.0 for i in range(len(st["lean"]))]
    seed = randsearch.game_seed(20000 + j, 0)
    setup = randsearch.draw_setup(seed)
    setup["pair"] = j
    with open(os.path.join(st["dir"], "c%04d.setup.json" % j), "w", encoding="utf-8") as fh:
        json.dump(setup, fh)
    st["running"][str(j)] = {"push": push, "seed": seed, "setup": setup, "lean": list(st["lean"]),
                             "opts": [write_game(st, base, j, s, push) for s in (1, -1)], "score": [None, None],
                             "done": [False, False]}
    return j


def play(st, j, g, slot):
    r = st["running"][str(j)]
    _, _, sc = neuro.play((st["dir"], j, g, r["setup"]["per_side"], r["setup"]["map"], r["seed"], r["opts"][g], slot,
                           r["setup"]["foe"], r["setup"]))
    out = os.path.join(st["dir"], "matches", "c%02d-g%d" % (j, g))
    sc = sc[0] if isinstance(sc, (list, tuple)) else sc
    if sc is None:
        randsearch.note_bad_map(r["setup"]["map"])
    return out, sc


def played_leans(out, n_slots):
    try:
        text = open(os.path.join(out, "infolog.txt"), encoding="utf-8", errors="replace").read()
    except OSError:
        return True
    m, ml = POLICY_RX.search(text), LEAN_RX.search(text)
    if m is None:
        return True
    return m.group(1) == "file" and ml is not None and int(ml.group(1)) == n_slots


def pause(why):
    log("PAUSED: " + why)
    try:
        os.replace(ON, ON + ".paused")
    except OSError:
        pass


def read_pairs():
    if not os.path.exists(PAIRS):
        return []
    return [json.loads(x) for x in open(PAIRS, encoding="utf-8").read().splitlines() if x.strip()]


def slopes(st, pairs):
    """per slot over the pairs since it last moved: (slope of the score per unit of lean, its t, pairs)"""
    out = []
    for i in range(len(st["lean"])):
        if not st["live"][i]:
            out.append((0.0, 0.0, 0))
            continue
        xs = [(2.0 * p["push"][i], p["score"][0] - p["score"][1]) for p in pairs if p["n"] >= st["since"][i]]
        sxx = sum(x * x for x, _ in xs)
        if len(xs) < 3 or sxx <= 0:
            out.append((0.0, 0.0, len(xs)))
            continue
        g = sum(x * d for x, d in xs) / sxx
        res = sum((d - g * x) ** 2 for x, d in xs) / (len(xs) - 1)
        se = math.sqrt(res / sxx)
        out.append((g, g / se if se > 0 else 0.0, len(xs)))
    return out


def step(st):
    pairs = read_pairs()
    sl = slopes(st, pairs)
    moved = []
    for i, (g, t, n) in enumerate(sl):
        if n >= MIN_PAIRS and abs(t) >= T_MOVE:
            lim = LIMIT_AMOUNT if st["amount"][i] else LIMIT_TILT
            new = max(-lim, min(lim, st["lean"][i] + math.copysign(0.5 * sigma(st, i), g)))
            if new != st["lean"][i]:
                moved.append("%s %+.3f->%+.3f (t=%+.1f, %d pairs)" % (st["names"][i], st["lean"][i], new, t, n))
                st["moves"].append({"at": time.strftime("%Y-%m-%d %H:%M"), "slot": st["names"][i],
                                    "from": st["lean"][i], "to": new, "t": round(t, 2), "pairs": n})
                st["lean"][i] = new
                st["since"][i] = len(pairs)
    st["steps"] += 1
    top = sorted(((abs(t), st["names"][i], t, n) for i, (g, t, n) in enumerate(sl) if n), reverse=True)[:5]
    mean = [0.5 * (p["score"][0] + p["score"][1]) for p in pairs[-STEP_PAIRS:]]
    log("step %d: %d pairs; recent mean score %+.2f; %s; strongest %s" % (
        st["steps"], len(pairs), sum(mean) / max(1, len(mean)), ("MOVED " + "; ".join(moved)) if moved else "no move",
        ", ".join("%s t=%+.1f/%d" % (nm, t, n) for _, nm, t, n in top)))


def finish(st, j):
    r = st["running"].pop(str(j))
    if r["score"][0] is None or r["score"][1] is None:
        log("pair %d dropped: a game had no score (%s)" % (j, r["setup"]["map"]))
        return False
    pairs = read_pairs()
    with open(PAIRS, "a", encoding="utf-8") as fh:
        fh.write(json.dumps({"n": len(pairs), "pair": j, "at": time.strftime("%Y-%m-%d %H:%M"), "push": r["push"],
                             "lean": r["lean"], "score": [round(s, 4) for s in r["score"]],
                             "setup": {k: r["setup"][k] for k in ("per_side", "map", "foe", "sides", "minutes",
                                                                   "handicap") if k in r["setup"]}}) + "\n")
    return True


def status():
    if not os.path.exists(STATE):
        print("no run yet")
        return
    st = json.load(open(STATE, encoding="utf-8"))
    pairs = read_pairs()
    print("%d pairs finished, %d running, %d steps, games in %s" % (len(pairs), len(st["running"]), st["steps"],
                                                                   st["dir"]))
    sl = slopes(st, pairs)
    rows = sorted(((abs(t), i) for i, (g, t, n) in enumerate(sl) if n), reverse=True)[:12]
    for _, i in rows:
        g, t, n = sl[i]
        print("  %-28s lean %+.3f  slope %+.2f  t %+.1f  over %d pairs" % (st["names"][i], st["lean"][i], g, t, n))
    for m in st["moves"][-8:]:
        print("  moved %s %s %+.3f -> %+.3f (t %+.1f, %d pairs)" % (m["at"], m["slot"], m["from"], m["to"], m["t"],
                                                                    m["pairs"]))


def main(argv):
    if "--status" in argv:
        status()
        return 0
    lay = pgtrain.Layout()
    st = load_state(lay)
    base = pgtrain.read_weights(BASE, lay)
    n_slots = len(st["lean"])
    lock = threading.Lock()
    running = {}
    queue = []
    for j, r in sorted(st["running"].items(), key=lambda kv: int(kv[0])):
        for g in (0, 1):
            if not r["done"][g]:
                queue.append((int(j), g))
    finished_since = 0
    with ThreadPoolExecutor(max_workers=16) as ex:
        while True:
            if not os.path.exists(ON):
                log("lean_on gone: finishing the running games, then stopping")
                wait(list(running))
                return 0
            w = cem.workers()
            while len(running) < w:
                with lock:
                    if not queue:
                        j = new_pair(st, base)
                        queue += [(j, 0), (j, 1)]
                        save(st)
                    j, g = queue.pop(0)
                slot = 100 + ((2 * j + g) % 64)
                running[ex.submit(play, st, j, g, slot)] = (j, g)
            done, _ = wait(list(running), timeout=30, return_when=FIRST_COMPLETED)
            for fut in done:
                j, g = running.pop(fut)
                try:
                    out, sc = fut.result()
                except Exception:
                    log("game c%04d-g%d raised: %s" % (j, g, traceback.format_exc().strip().replace("\n", " | ")))
                    sc, out = None, None
                with lock:
                    r = st["running"].get(str(j))
                    if r is None:
                        continue
                    if out and not played_leans(out, n_slots):
                        pause("c%04d-g%d did not play its leans" % (j, g))
                    r["done"][g], r["score"][g] = True, sc
                    if all(r["done"]):
                        if finish(st, j):
                            finished_since += 1
                    save(st)
                    if finished_since >= STEP_PAIRS:
                        finished_since = 0
                        step(st)
                        save(st)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
