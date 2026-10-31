"""A release candidate against a release, game by game and summed: result, income over time, milestones, trade.

    python tools/relprofile.py matches/q1-* matches/q4-* [--cand Apexfix,Apexc9] [--rel v0.4.09]

His 10-30: "profile our performance so I can make a reasonable determination whether we should cut a release". Each
match is read from its own infolog: [BARAI_STATS] (mInc, mKillReal, mLostReal per team every 2 game-minutes) and
[BARAI_BUILD] (every finished building with its frame). Teams are summed by ALLY, and the ally index is the spec
index of result.json's teams (S16), so a 4v4's four seats are one side. Differences are candidate minus release
within a game, then averaged: the paired reading, since two games on one seed share their map and start.
"""
import argparse
import json
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

STATS = re.compile(r"\[BARAI_STATS\] team=(\d+) ally=(\d+) \S+ frame=(\d+)[^\n]*?mLostReal=(\d+)[^\n]*?mKillReal=(\d+)"
                   r"[^\n]*?mInc=([\d.]+)")
BUILD = re.compile(r"\[BARAI_BUILD\] team=(\d+) ally=(\d+) frame=(\d+) min=[\d.]+ unit=(\S+) cost=(\d+)")
FPS = 30
MINUTES = (5, 10, 15, 20, 25, 30)
MILESTONES = (
    ("T2 lab", re.compile(r"^(arm|cor|leg)(alab|avp|aap|asy|amsub|ahp)$")),
    ("moho", re.compile(r"^(arm|cor|leg)(moho|mohogeo)$")),
    ("fusion", re.compile(r"^(arm|cor|leg)(fus|ckfus|uwfus)$")),
    ("adv conv", re.compile(r"^(arm|cor|leg)(mmkr|adveconv)$")),
    ("adv fusion", re.compile(r"^(arm|cor|leg)afus$")),
    ("gantry", re.compile(r"^(arm|cor|leg)(shltx|gant|shltxuw|gantuw)$")),
)


def side_of(specs, keys):
    for i, s in enumerate(specs):
        if any(k in s for k in keys):
            return i
    return None


def read(md, cand_keys, rel_keys):
    res = json.loads((md / "result.json").read_text())
    specs = [t.get("spec", "?") for t in res.get("teams", [])]
    c, r = side_of(specs, cand_keys), side_of(specs, rel_keys)
    if c is None or r is None or c == r:
        return None
    text = (md / "infolog.txt").read_text("utf-8", errors="replace")
    inc = defaultdict(lambda: defaultdict(float))   # frame -> ally -> mInc summed
    kill = defaultdict(lambda: defaultdict(int))
    lost = defaultdict(lambda: defaultdict(int))
    for t, a, f, ml, mk, mi in STATS.findall(text):
        inc[int(f)][int(a)] += float(mi)
        kill[int(f)][int(a)] += int(mk)
        lost[int(f)][int(a)] += int(ml)
    frames = sorted(inc)
    first = defaultdict(dict)
    for t, a, f, unit, cost in BUILD.findall(text):
        for name, rx in MILESTONES:
            if rx.match(unit) and name not in first[int(a)]:
                first[int(a)][name] = int(f) / (60.0 * FPS)
    out = {"name": md.name, "c": c, "r": r}
    rr = res.get("result", {})
    win = rr.get("winner_specs") or []
    if rr.get("reason") != "gameover" or not win:
        out["result"] = "D"
    else:
        out["result"] = "W" if any(any(k in w for k in cand_keys) for w in win) else "L"
    out["end"] = (frames[-1] / (60.0 * FPS)) if frames else 0.0
    for m in MINUTES:
        fr = [f for f in frames if f <= m * 60 * FPS]
        if not fr or (frames[-1] < m * 60 * FPS - 2 * 60 * FPS):
            continue
        f = fr[-1]
        out["inc%d" % m] = (inc[f][c], inc[f][r])
    # metal earned: the income integrated over the 2-minute samples
    earned = [0.0, 0.0]
    for i in range(1, len(frames)):
        dt = (frames[i] - frames[i - 1]) / FPS
        earned[0] += inc[frames[i]][c] * dt
        earned[1] += inc[frames[i]][r] * dt
    out["earned"] = tuple(earned)
    if frames:
        f = frames[-1]
        out["trade"] = ((kill[f][c], lost[f][c]), (kill[f][r], lost[f][r]))
    out["first"] = (first[c], first[r])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("matches", nargs="+")
    ap.add_argument("--cand", default="Apexfix,Apexc9")
    ap.add_argument("--rel", default="v0.4.09")
    args = ap.parse_args()
    ck, rk = args.cand.split(","), args.rel.split(",")
    rows = []
    for m in args.matches:
        md = Path(m)
        if not (md / "result.json").exists():
            continue
        row = read(md, ck, rk)
        if row:
            rows.append(row)
    if not rows:
        print("no finished candidate-vs-release matches")
        return 1
    print("%-24s %3s %5s  %s" % ("match", "res", "end", "income cand/rel at " + ",".join(map(str, MINUTES))))
    for r in rows:
        incs = " ".join("%d/%d" % r["inc%d" % m] if ("inc%d" % m) in r else "-" for m in MINUTES)
        print("%-24s %3s %5.1f  %s" % (r["name"], r["result"], r["end"], incs))
    w = sum(r["result"] == "W" for r in rows)
    l = sum(r["result"] == "L" for r in rows)
    d = sum(r["result"] == "D" for r in rows)
    print("\nresult: %dW %dD %dL of %d (candidate vs release)" % (w, d, l, len(rows)))
    print("\nincome, candidate minus release (paired within a game; n = games still running at that minute)")
    for m in MINUTES:
        diffs = [r["inc%d" % m][0] - r["inc%d" % m][1] for r in rows if ("inc%d" % m) in r]
        ratio = [r["inc%d" % m][0] / r["inc%d" % m][1] for r in rows if ("inc%d" % m) in r and r["inc%d" % m][1] > 0]
        if diffs:
            print("  min %2d  mean %+7.1f m/s   median ratio %.2f   ahead in %d/%d" % (
                m, statistics.mean(diffs), statistics.median(ratio) if ratio else 0, sum(x > 0 for x in diffs),
                len(diffs)))
    er = [r["earned"][0] / r["earned"][1] for r in rows if r["earned"][1] > 0]
    if er:
        print("  metal earned over the game: median ratio %.2f, ahead in %d/%d" % (
            statistics.median(er), sum(x > 1 for x in er), len(er)))
    print("\nmilestones, first finished, game minute (median over games where both sides reached it; diff = cand - rel)")
    for name, _ in MILESTONES:
        pairs = [(r["first"][0][name], r["first"][1][name]) for r in rows
                 if name in r["first"][0] and name in r["first"][1]]
        only_c = sum(1 for r in rows if name in r["first"][0] and name not in r["first"][1])
        only_r = sum(1 for r in rows if name in r["first"][1] and name not in r["first"][0])
        if pairs:
            print("  %-10s cand %5.1f  rel %5.1f  diff %+5.1f  (n=%d; only cand %d, only rel %d)" % (
                name, statistics.median(p[0] for p in pairs), statistics.median(p[1] for p in pairs),
                statistics.median(p[0] - p[1] for p in pairs), len(pairs), only_c, only_r))
        elif only_c or only_r:
            print("  %-10s only cand %d, only rel %d" % (name, only_c, only_r))
    tr = [r["trade"] for r in rows if "trade" in r]
    if tr:
        print("\ntrade at the end (metal killed / lost, summed): cand %d / %d   rel %d / %d" % (
            sum(t[0][0] for t in tr), sum(t[0][1] for t in tr), sum(t[1][0] for t in tr), sum(t[1][1] for t in tr)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
