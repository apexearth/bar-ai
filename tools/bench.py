"""The test bench (todo/learn-from-each-decision.md; the 11-04 reviews): a measurement we can trust.

    python tools/bench.py run --name aa1 [--foe BARb:stable:hard] [--maps ...] [--games 12] [--minutes 25]
                              [--workers 3] [--a-mod K=V ...] [--b-mod K=V ...] [--metric score]
    python tools/bench.py report <tournaments/<stamp>-bench-<name>>

Two arms of our AI against one opponent, launched at the same time with the same worker count, on the same maps and
seeds, with random start boxes mirrored between the sides (run_match --random-box: slot 0 won 50 of 70 decided Comet
games with fixed starts). Every seed is played from both slots. The primary metric is written down before the first
game (bench.json) and is the only one the verdict reads: `score` (cem.score -- a win, a loss, or a timeout judged on
eco, trade, damage and ground, earlier wins higher) or one ab_pairs column (e.g. inc12). The report gives the paired
mean difference and its standard error, the unpaired one beside it (pairing only helps if the pairs correlate), and
the games per arm a given effect would need at this noise. Run an A/A (no --a-mod/--b-mod) first: its difference
must be inside 2 standard errors, and its spread sizes every A/B after it.
"""
import argparse
import glob
import json
import math
import os
import random
import re
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))

AI = "Apexestall:lane-estall:standard"
MAPS = "Comet Catcher Remake,Altair_Crossing,Avalanche,Glacier Pass"


def run(a):
    stamp = time.strftime("%Y%m%d-%H%M%S")
    d = os.path.join(REPO, "tournaments", "%s-bench-%s" % (stamp, a.name))
    os.makedirs(d, exist_ok=True)
    reg = {"name": a.name, "registered": time.strftime("%Y-%m-%d %H:%M"), "metric": a.metric, "foe": a.foe,
           "maps": a.maps, "games": a.games, "minutes": a.minutes, "workers": a.workers, "random_box": a.random_box,
           "arms": {"a": a.a_mod, "b": a.b_mod}, "ai": a.ai, "ai_a": a.a_ai or a.ai, "ai_b": a.b_ai or a.ai,
           "per_side": a.per_side, "handicap": a.handicap}
    # a fresh base every bench, shared by both arms so the pairs still match (his 11-06: every bench replayed seeds
    # 1000-1003, so the opening -- the team strategy, the start boxes -- came out the same run after run)
    seed_base = a.seed_base if a.seed_base is not None else random.randrange(1, 1 << 30)
    reg["seed_base"] = seed_base
    with open(os.path.join(d, "bench.json"), "w", encoding="utf-8") as fh:
        json.dump(reg, fh, indent=1)
    procs = {}
    for arm, mods, ai in (("a", a.a_mod, a.a_ai or a.ai), ("b", a.b_mod, a.b_ai or a.ai)):
        cmd = [sys.executable, "-u", os.path.join(REPO, "tools", "run_tournament.py"), "--a", ai, "--b", a.foe,
               "--per-side", str(a.per_side),
               "--maps", a.maps, "--games", str(a.games), "--speed", "20", "--workers", str(a.workers),
               "--handicap", a.handicap, "--minutes", str(a.minutes), "--random-box", str(a.random_box),
               "--name", "bench-%s-%s" % (a.name, arm), "--seed-base", str(seed_base)]
        for m in mods:
            cmd += ["--modoption", m]
        log = open(os.path.join(d, "arm-%s.log" % arm), "w", encoding="utf-8")
        procs[arm] = subprocess.Popen(cmd, cwd=REPO, stdout=log, stderr=subprocess.STDOUT)
        time.sleep(20)
    print("bench %s: arms launched, registered metric %s -> %s" % (a.name, a.metric, d), flush=True)
    for arm, p in procs.items():
        p.wait()
    dirs = {}
    for arm in ("a", "b"):
        txt = open(os.path.join(d, "arm-%s.log" % arm), encoding="utf-8", errors="replace").read()
        out = [ln.split("output:", 1)[1].strip() for ln in txt.splitlines() if ln.startswith("output:")]
        dirs[arm] = out[0] if out else None
    reg["dirs"] = dirs
    with open(os.path.join(d, "bench.json"), "w", encoding="utf-8") as fh:
        json.dump(reg, fh, indent=1)
    report(d)


def metric_of(md, metric):
    if metric == "score":
        import cem
        s = cem.score(md)
        return (s[0] if isinstance(s, (list, tuple)) else s) if s is not None else None
    import ab_pairs
    g = ab_pairs.game(md)
    return None if g is None else g.get(metric)


def arm_games(tdir, metric):
    import ab_pairs
    out = {}
    for md in sorted(glob.glob(os.path.join(tdir, "matches", "*"))):
        g = ab_pairs.game(md)
        if g is None:
            continue
        v = metric_of(md, metric)
        if v is not None:
            out[(g["seed"], g["side"])] = float(v)
    return out


STATS = re.compile(r"\[BARAI_STATS\] team=(\d+) (.*)")
CARD_MIN = (8, 12, 16, 20, 30, 45, 60)


def scorecard_game(md):
    """his scorecard (11-04): ours against theirs at each minute -- damage efficiency (dealt / received), metal
    produced, army value -- from the cumulative BARAI_STATS fields"""
    import ledger
    ours = ledger.our_teams(md)
    rows = {}
    for ln in open(os.path.join(md, "infolog.txt"), encoding="utf-8", errors="replace"):
        m = STATS.search(ln)
        if m:
            kv = dict(x.split("=", 1) for x in m.group(2).split(" ") if "=" in x)
            if kv.get("reason") == "periodic":
                rows[(int(m.group(1)), int(kv["frame"]) // 1800)] = kv
    out = {}
    for mi in CARD_MIN:
        us = [rows.get((t, mi)) for t in ours]
        them = [kv for (t, m2), kv in rows.items() if m2 == mi and t not in ours]
        if not us or any(x is None for x in us) or not them:
            continue
        s = lambda xs, k: sum(float(x.get(k, 0)) for x in xs)  # noqa: E731
        out[mi] = {"dmg": (s(us, "damageDealt") + 100) / (s(us, "damageReceived") + 100),
                   "prod": (s(us, "metalProduced") + 10) / (s(them, "metalProduced") + 10),
                   "army": (s(us, "armyReal") + 100) / (s(them, "armyReal") + 100)}
    return out


def scorecard(tdir):
    import ab_pairs
    out = {}
    for md in sorted(glob.glob(os.path.join(tdir, "matches", "*"))):
        g = ab_pairs.game(md)
        if g is not None:
            out[(g["seed"], g["side"])] = scorecard_game(md)
    return out


def print_scorecard(cards, label):
    """geometric means across games: 1.00 is even with the enemy, 2.00 twice theirs"""
    print("  scorecard %s (ours / theirs, geometric mean over games; 1.00 = even)" % label)
    print("    minute   damage efficiency   metal produced   army value   games")
    for mi in CARD_MIN:
        vals = [c[mi] for c in cards.values() if mi in c]
        if len(vals) < 3:
            continue
        gm = lambda k: math.exp(sum(math.log(max(1e-6, v[k])) for v in vals) / len(vals))  # noqa: E731
        print("    %6d   %17.2f   %14.2f   %10.2f   %5d" % (mi, gm("dmg"), gm("prod"), gm("army"), len(vals)))


def report(d):
    reg = json.load(open(os.path.join(d, "bench.json"), encoding="utf-8"))
    metric = reg["metric"]
    A, B = arm_games(reg["dirs"]["a"], metric), arm_games(reg["dirs"]["b"], metric)
    keys = sorted(set(A) & set(B))
    n = len(keys)
    print("bench %s (registered %s): metric %s, arms a=%s b=%s" % (reg["name"], reg["registered"], metric,
                                                                  reg["arms"]["a"] or "-", reg["arms"]["b"] or "-"))
    print("  arm a plays %s, arm b plays %s, %d a side" % (reg.get("ai_a", reg["ai"]), reg.get("ai_b", reg["ai"]), reg.get("per_side", 1)))
    if n < 3:
        print("  only %d pairs" % n)
        return
    a = [A[k] for k in keys]
    b = [B[k] for k in keys]
    diff = [y - x for x, y in zip(a, b)]
    mean = lambda v: sum(v) / len(v)  # noqa: E731
    sd = lambda v: math.sqrt(sum((x - mean(v)) ** 2 for x in v) / (len(v) - 1))  # noqa: E731
    se_p = sd(diff) / math.sqrt(n)
    se_u = math.sqrt(sd(a) ** 2 / n + sd(b) ** 2 / n)
    r = sum((x - mean(a)) * (y - mean(b)) for x, y in zip(a, b)) / ((n - 1) * sd(a) * sd(b)) if sd(a) > 0 and sd(b) > 0 else 0
    print("  pairs %d   arm a %.3f   arm b %.3f   b-a %+.3f  se %.3f (paired) / %.3f (unpaired)   pair r %.2f" % (
        n, mean(a), mean(b), mean(diff), se_p, se_u, r))
    t = mean(diff) / se_p if se_p > 0 else 0.0
    print("  verdict: %s (t = %.2f; |t| > 2 is a difference)" % ("DIFFERENT" if abs(t) > 2 else "no difference shown", t))
    sdd = min(sd(diff), math.sqrt(2) * math.sqrt((sd(a) ** 2 + sd(b) ** 2) / 2))
    for eff in (0.05, 0.1, 0.2):
        need = math.ceil((2.8 * sdd / eff) ** 2) if eff > 0 else 0
        print("  to see a %.2f difference (80%% power, 2-sided 5%%): ~%d pairs" % (eff, need))
    print_scorecard(scorecard(reg["dirs"]["a"]), "arm a")
    print_scorecard(scorecard(reg["dirs"]["b"]), "arm b")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--name", required=True)
    r.add_argument("--ai", default=AI)
    r.add_argument("--foe", default="BARb:stable:hard")
    r.add_argument("--maps", default=MAPS)
    r.add_argument("--games", type=int, default=12, help="per map per arm; even, so each seed plays both slots")
    r.add_argument("--seed-base", type=int, default=None, help="first seed (default: random per bench, both arms share it)")
    r.add_argument("--handicap", default="0", help="resource bonus %% for every AI, or A,B per side (default 0)")
    r.add_argument("--minutes", type=int, default=25)
    r.add_argument("--workers", type=int, default=3)
    r.add_argument("--random-box", dest="random_box", type=float, default=0.2)
    r.add_argument("--a-mod", dest="a_mod", action="append", default=[])
    r.add_argument("--b-mod", dest="b_mod", action="append", default=[])
    r.add_argument("--a-ai", dest="a_ai", default=None, help="arm a plays this AI instead of --ai (a release against a candidate)")
    r.add_argument("--b-ai", dest="b_ai", default=None)
    r.add_argument("--per-side", dest="per_side", type=int, default=1)
    r.add_argument("--metric", default="score")
    p = sub.add_parser("report")
    p.add_argument("dir")
    a = ap.parse_args()
    if a.cmd == "run":
        run(a)
    else:
        report(a.dir)


if __name__ == "__main__":
    main()
