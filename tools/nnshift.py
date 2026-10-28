"""How far each policy network has moved from neutral, read from what it DID in its games (his 10-28: "see how our
neural nets have shifted from neutral").

Neutral is the rule. Per continuous head (`apex: nnval head=X v= rule=`), the geometric mean of the net's value over
the rule's, and the share of decisions where it asked for more. Per builder-auction kind (`apex: pricecard`, the
winner and the runner-up), the geometric mean of the net's tilt `nn=` (1 = no lean). Plus the search's progress per
network from runtime/nn/rand.json (and an archived state for comparison).

    python tools/nnshift.py --out shift.json
        groups: shipped (v0.4.09's built-in net, the c9 control games), fresh search nets with >= MIN games,
        old search's viable nets (rand-oldprices-20261028.json)
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

HEADS = {
    "con": "Constructors (floor)", "cap": "Constructors (cap)", "acap": "Air constructors",
    "scap": "Scouts", "mex": "Extractor claims", "esc": "Escort strength", "ecap": "Escorts (cap)",
    "cfear": "Constructor caution", "defamt": "Defence amount", "mexg": "Extractor guards", "gunp": "Guns per post",
}
VAL = re.compile(r"apex: nnval head=(\w+) .*? v=(-?[\d.]+) rule=(-?[\d.]+) lo=(-?[\d.]+) hi=(-?[\d.]+)")
CARD = re.compile(r"\| (?:win|2nd) (\w+):(\w+) .*? nn=([\d.]+)")
PW = re.compile(r"apex_pw_file=([^;\s]+)")


def read_game(path, acc):
    try:
        f = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return False
    with f:
        for line in f:
            if "apex: nnval head=" in line:
                m = VAL.search(line)
                if m and m.group(1) in HEADS:
                    v, r = float(m.group(2)), float(m.group(3))
                    if v > 0 and r > 0:
                        h = acc["heads"][m.group(1)]
                        h[0] += math.log(v / r)
                        h[1] += 1
                        h[2] += v > r * 1.001
            elif "apex: pricecard" in line:
                for kind, _d, nn in CARD.findall(line):
                    x = float(nn)
                    if x > 0:
                        k = acc["kinds"][kind]
                        k[0] += math.log(x)
                        k[1] += 1
    acc["games"] += 1
    return True


def new_acc():
    return {"heads": defaultdict(lambda: [0.0, 0, 0]), "kinds": defaultdict(lambda: [0.0, 0]), "games": 0}


def summarise(acc):
    return {
        "games": acc["games"],
        "heads": {h: {"gm": round(math.exp(v[0] / v[1]), 4), "above": round(v[2] / v[1], 3), "n": v[1]}
                  for h, v in acc["heads"].items() if v[1]},
        "kinds": {k: {"gm": round(math.exp(v[0] / v[1]), 4), "n": v[1]} for k, v in acc["kinds"].items() if v[1] >= 5},
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


def group_kind(key):
    for p in ("shipped", "biased", "neutral", "old", "fresh"):
        if key.startswith(p):
            return p
    return key


def write_rows(d, groups, fresh, old):
    """row arrays for the Net Drift dashboard: one row per (group, head), (group, kind) and network"""
    os.makedirs(d, exist_ok=True)
    heads, kinds = [], []
    for key, g in groups.items():
        base = {"group": key, "groupLabel": g["label"], "groupKind": group_kind(key), "games": g["games"]}
        for h, v in g["heads"].items():
            heads.append({**base, "head": h, "headLabel": HEADS[h], "ratio": v["gm"], "above": v["above"], "n": v["n"]})
        for k, v in g["kinds"].items():
            kinds.append({**base, "kind": k, "ratio": v["gm"], "n": v["n"]})
    prog = [{"search": "Neutral search (10-28)", **r} for r in progress(fresh)] \
        + [{"search": "Old search (10-11 to 10-15)", **r} for r in progress(old)]
    for name, rows in (("heads", heads), ("kinds", kinds), ("progress", prog)):
        json.dump(rows, open(os.path.join(d, name + ".json"), "w", encoding="utf-8"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--min-games", type=int, default=4)
    ap.add_argument("--old-top", type=int, default=3)
    ap.add_argument("--rows-dir", help="also write heads.json, kinds.json, progress.json as row arrays")
    a = ap.parse_args()
    groups = {}

    acc = new_acc()
    for f in sorted(glob.glob(os.path.join(REPO, "matches", "yof-*", "infolog.txt"))
                    + glob.glob(os.path.join(REPO, "matches", "ycf-*", "infolog.txt"))):
        read_game(f, acc)
    groups["shipped"] = {"label": "Shipped net (v0.4.09)", **summarise(acc)}

    fresh = json.load(open(os.path.join(NN, "rand.json"), encoding="utf-8"))
    tdir = fresh.get("dir") or ""
    byw = net_games(os.path.join(tdir, "matches", "*", "script.txt"))
    for k, n in sorted(fresh["nets"].items(), key=lambda kv: int(kv[0])):
        w = os.path.normcase(os.path.abspath(os.path.join(tdir, "c%02d.weights" % int(k))))
        files = byw.get(w, [])
        if len(files) < a.min_games:
            continue
        acc = new_acc()
        for f in files:
            read_game(f, acc)
        groups[f"fresh{k}"] = {"label": f"Fresh net {k}", "score": mean_score(n), **summarise(acc)}
    acc = new_acc()
    for f in glob.glob(os.path.join(tdir, "matches", "*", "infolog.txt")):
        read_game(f, acc)
    if acc["games"]:
        groups["neutral"] = {"label": "Neutral search, all nets", **summarise(acc)}

    for p, key, label in ((os.path.join(NN, "rand-familymid-20261028.json"), "biased",
                           "First fresh run (random middle)"),):
        if not os.path.exists(p):
            continue
        st = json.load(open(p, encoding="utf-8"))
        acc = new_acc()
        for f in glob.glob(os.path.join(st.get("dir", ""), "matches", "*", "infolog.txt")):
            read_game(f, acc)
        if acc["games"]:
            groups[key] = {"label": label, **summarise(acc)}

    oldp = os.path.join(NN, "rand-oldprices-20261028.json")
    old = json.load(open(oldp, encoding="utf-8")) if os.path.exists(oldp) else {"nets": {}}
    viable = [n for n in old["nets"].values() if n.get("status") == "viable" and len(n.get("games", [])) >= 12]
    viable.sort(key=lambda n: -(mean_score(n) or -9))
    if viable:
        byw_old = net_games(os.path.join(REPO, "tournaments", "*-nn-rand*", "matches", "*", "script.txt"))
        for n in viable[:a.old_top]:
            w = os.path.normcase(os.path.abspath(n["file"])) if n.get("file") else \
                os.path.normcase(os.path.abspath(os.path.join(old.get("dir", ""), "c%02d.weights" % n["id"])))
            files = byw_old.get(w, [])
            if not files:
                continue
            acc = new_acc()
            for f in files[:24]:
                read_game(f, acc)
            groups[f"old{n['id']}"] = {"label": f"Old search net {n['id']}", "score": mean_score(n), **summarise(acc)}

    json.dump({"heads": HEADS, "groups": groups,
               "progress": {"fresh": progress(fresh), "old": progress(old)}},
              open(a.out, "w", encoding="utf-8"), indent=1)
    if a.rows_dir:
        write_rows(a.rows_dir, groups, fresh, old)
    for g, v in groups.items():
        print(f"{g:10} games={v['games']:3} heads={len(v['heads'])} kinds={len(v['kinds'])}")


if __name__ == "__main__":
    main()
