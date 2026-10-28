"""How far each policy network has moved from neutral, read from what it DID in its games (his 10-28: "see how our
neural nets have shifted from neutral"). The dashboard's Net tab draws this live; the CLI prints a summary.

Neutral is the rule. Per continuous head (`apex: nnval head=X v= rule=`), the geometric mean of the net's value over
the rule's, and the share of decisions where it asked for more. Per builder-auction kind (`apex: pricecard`, the
winner and the runner-up), the geometric mean of the net's tilt `nn=` (1 = no lean). Per finished game of the
current search (runtime/nn/rand.json): its net, score, result and random setup (c<NN>-g<G>.setup.json).

    python tools/nnshift.py [--out shift.json]
        groups: shipped (v0.4.09's built-in net, the c9 control games), the current search's nets, the first fresh
        run (random middle), the old search's best viable nets (rand-oldprices-20261028.json)
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import os
import re
from collections import defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NN = os.path.join(REPO, "runtime", "nn")
SHIPPED_GLOBS = ("yof-*", "ycf-*")
OLD = os.path.join(NN, "rand-oldprices-20261028.json")

HEADS = {
    "con": "Constructors (floor)", "cap": "Constructors (cap)", "acap": "Air constructors",
    "scap": "Scouts", "mex": "Extractor claims", "esc": "Escort strength", "ecap": "Escorts (cap)",
    "cfear": "Constructor caution", "defamt": "Defence amount", "mexg": "Extractor guards", "gunp": "Guns per post",
}
VAL = re.compile(r"apex: nnval head=(\w+) .*? v=(-?[\d.]+) rule=(-?[\d.]+) lo=(-?[\d.]+) hi=(-?[\d.]+)")
CARD = re.compile(r"\| (?:win|2nd) (\w+):(\w+) .*? nn=([\d.]+)")
PW = re.compile(r"apex_pw_file=([^;\s]+)")
GAME_DIR = re.compile(r"c(\d+)-g(\d+)$")


def read_game(path):
    """{heads: {h: [sum log(v/rule), n, n above]}, kinds: {k: [sum log nn, n]}} for one infolog, or None"""
    heads, kinds = defaultdict(lambda: [0.0, 0, 0]), defaultdict(lambda: [0.0, 0])
    try:
        f = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return None
    with f:
        for line in f:
            if "apex: nnval head=" in line:
                m = VAL.search(line)
                if m and m.group(1) in HEADS:
                    v, r = float(m.group(2)), float(m.group(3))
                    if v > 0 and r > 0:
                        h = heads[m.group(1)]
                        h[0] += math.log(v / r)
                        h[1] += 1
                        h[2] += v > r * 1.001
            elif "apex: pricecard" in line:
                for kind, _d, nn in CARD.findall(line):
                    x = float(nn)
                    if x > 0:
                        k = kinds[kind]
                        k[0] += math.log(x)
                        k[1] += 1
    return {"heads": {h: [round(v[0], 4), v[1], v[2]] for h, v in heads.items()},
            "kinds": {k: [round(v[0], 4), v[1]] for k, v in kinds.items()}}


def game_acc(path, cache):
    """read_game, memoised on the file's size and mtime"""
    try:
        st = os.stat(path)
    except OSError:
        return None
    key = (st.st_size, st.st_mtime)
    hit = cache.get(path)
    if hit and hit[0] == key:
        return hit[1]
    acc = read_game(path)
    cache[path] = (key, acc)
    return acc


def summarise(accs):
    heads, kinds, games = defaultdict(lambda: [0.0, 0, 0]), defaultdict(lambda: [0.0, 0]), 0
    for a in accs:
        if not a:
            continue
        games += 1
        for h, v in a["heads"].items():
            for i in range(3):
                heads[h][i] += v[i]
        for k, v in a["kinds"].items():
            kinds[k][0] += v[0]
            kinds[k][1] += v[1]
    return {
        "games": games,
        "heads": {h: {"gm": round(math.exp(v[0] / v[1]), 4), "above": round(v[2] / v[1], 3), "n": v[1]}
                  for h, v in heads.items() if v[1]},
        "kinds": {k: {"gm": round(math.exp(v[0] / v[1]), 4), "n": v[1]} for k, v in kinds.items() if v[1] >= 5},
    }


def net_games(tour_glob):
    """weights file -> infologs, from each game's start script"""
    out = defaultdict(list)
    for s in glob.glob(tour_glob):
        try:
            m = PW.search(open(s, encoding="utf-8", errors="replace").read())
        except OSError:
            continue
        if m:
            out[os.path.normcase(os.path.abspath(m.group(1)))].append(os.path.join(os.path.dirname(s), "infolog.txt"))
    return out


def mean_score(n):
    g = [x[0] for x in n.get("games", []) if x and x[0] is not None]
    return (sum(g) / len(g)) if g else None


def progress(state):
    rows = []
    for k, n in state.get("nets", {}).items():
        g = n.get("games", [])
        sc = mean_score(n)
        wins = sum(1.0 if x[1] == "W" else (0.5 if x[1] == "D" else 0.0) for x in g if len(x) > 1)
        rows.append({"id": int(k), "games": len(g), "score": None if sc is None else round(sc, 3),
                     "wins": wins, "s": n.get("s"), "status": n.get("status", "")})
    return sorted(rows, key=lambda r: r["id"])


def load_state(path):
    try:
        return json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        return {"nets": {}}


def _mtime(p):
    try:
        return os.stat(p).st_mtime
    except OSError:
        return None


def archive_groups(cache, old_top=3):
    """The fixed references: the shipped net, the first fresh run, the old search's best viable nets.
    Their games no longer change, so the result is memoised on the state files' mtimes."""
    key = (_mtime(OLD), old_top)
    hit = cache.get("_archive")
    if hit and hit[0] == key:
        return hit[1]
    groups = {}
    files = []
    for pat in SHIPPED_GLOBS:
        files += sorted(glob.glob(os.path.join(REPO, "matches", pat, "infolog.txt")))
    groups["shipped"] = {"label": "Shipped net (v0.4.09)", "kind": "shipped",
                         **summarise(game_acc(f, cache) for f in files)}

    old = load_state(OLD)
    viable = [n for n in old["nets"].values() if n.get("status") == "viable" and len(n.get("games", [])) >= 12]
    viable.sort(key=lambda n: -(mean_score(n) or -9))
    if viable:
        byw = net_games(os.path.join(REPO, "tournaments", "*-nn-rand*", "matches", "*", "script.txt"))
        for n in viable[:old_top]:
            w = os.path.normcase(os.path.abspath(n["file"])) if n.get("file") else \
                os.path.normcase(os.path.abspath(os.path.join(old.get("dir", ""), "c%02d.weights" % n["id"])))
            fs = byw.get(w, [])[:24]
            if fs:
                groups[f"old{n['id']}"] = {"label": f"Old search net {n['id']}", "kind": "old",
                                           "score": mean_score(n), **summarise(game_acc(f, cache) for f in fs)}
    cache["_archive"] = (key, groups)
    return groups


def search_games(state, cache):
    """One row per finished game of the search in `state`: net, game, score, result, setup and its decisions"""
    tdir = state.get("dir") or ""
    scored = {}
    for k, n in state.get("nets", {}).items():
        for x in n.get("games", []):
            if len(x) > 3:
                scored[(int(k), int(x[3]))] = x
    rows = []
    for mdir in sorted(glob.glob(os.path.join(tdir, "matches", "c*-g*"))):
        m = GAME_DIR.search(os.path.basename(mdir))
        if not m or not os.path.exists(os.path.join(mdir, "result.json")):
            continue
        net, g = int(m.group(1)), int(m.group(2))
        acc = game_acc(os.path.join(mdir, "infolog.txt"), cache)
        if acc is None:
            continue
        try:
            setup = json.load(open(os.path.join(tdir, "c%02d-g%d.setup.json" % (net, g)), encoding="utf-8"))
        except (OSError, ValueError):
            setup = None
        x = scored.get((net, g))
        rows.append({"net": net, "g": g, "score": None if x is None else x[0], "res": None if x is None else x[1],
                     "setup": setup, **acc})
    return rows


PG_STATE = os.path.join(REPO, "runtime", "pg", "state.json")


def game_score(mdir, cache):
    """cem.score of a finished game, (score, result), memoised on its result.json"""
    p = os.path.join(mdir, "result.json")
    try:
        key = ("score", os.stat(p).st_mtime)
    except OSError:
        return None, None
    hit = cache.get(p)
    if hit and hit[0] == key:
        return hit[1]
    import cem
    sc = cem.score(mdir)
    v = (sc[0], sc[1]) if isinstance(sc, (list, tuple)) else (sc, None)
    cache[p] = (key, v)
    return v


def version_progress(games):
    """the training's games by the version that played them"""
    by = defaultdict(list)
    for g in games:
        by[g["net"]].append(g)
    rows = []
    for v, gs in sorted(by.items()):
        sc = [g["score"] for g in gs if g["score"] is not None]
        rows.append({"id": v, "games": len(gs), "score": round(sum(sc) / len(sc), 3) if sc else None,
                     "wins": sum(1 for g in gs if g["res"] == "W"), "losses": sum(1 for g in gs if g["res"] == "L")})
    return rows


def collect(cache=None, old_top=3):
    """the training's games (learning from our choices, runtime/pg) when it has a run, else the random search's;
    in training a game's `net` is the version of the network that played it"""
    cache = {} if cache is None else cache
    pg = load_state(PG_STATE)
    training = bool(pg.get("dir"))
    state = pg if training else load_state(os.path.join(NN, "rand.json"))
    games = search_games(state, cache)
    for g in games:
        if g["score"] is None:
            g["score"], g["res"] = game_score(os.path.join(state["dir"], "matches", "c%02d-g%d" % (g["net"], g["g"])), cache)
    label = "Training, all versions" if training else "Current search, all nets"
    groups = {"current": {"label": label, "kind": "current", **summarise(games)}}
    if training and games:
        vs = sorted({g["net"] for g in games})
        early = [g for g in games if g["net"] <= vs[0] + 1]
        late = [g for g in games if g["net"] >= vs[-1] - 1]
        groups["early"] = {"label": "Training v%d-v%d" % (vs[0], min(vs[0] + 1, vs[-1])), "kind": "early", **summarise(early)}
        if vs[-1] - 1 > vs[0] + 1:
            groups["latest"] = {"label": "Training v%d-v%d" % (vs[-1] - 1, vs[-1]), "kind": "latest", **summarise(late)}
    groups.update(archive_groups(cache, old_top))
    return {"heads": HEADS, "mode": "training" if training else "search",
            "search_dir": os.path.basename(os.path.normpath(state.get("dir") or "")),
            "groups": groups, "games": games,
            "progress": {"current": version_progress(games) if training else progress(state),
                         "old": progress(load_state(OLD))}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out")
    ap.add_argument("--min-games", type=int, default=4)
    ap.add_argument("--old-top", type=int, default=3)
    a = ap.parse_args()
    d = collect(old_top=a.old_top)
    if a.out:
        json.dump(d, open(a.out, "w", encoding="utf-8"), indent=1)
    bynet = defaultdict(list)
    for r in d["games"]:
        bynet[r["net"]].append(r)
    rows = [(f"net{k}", summarise(v)) for k, v in sorted(bynet.items()) if len(v) >= a.min_games]
    for name, v in list(d["groups"].items()) + rows:
        lean = " ".join(f"{h}=x{x['gm']:.2f}" for h, x in sorted(v["heads"].items()))
        print(f"{name:10} games={v['games']:4} {lean}")


if __name__ == "__main__":
    main()
