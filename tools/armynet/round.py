#!/usr/bin/env python3
"""One self-improvement round of the army model, end to end (todo/armynet-self-play.md):

    play   self-play games, the init model vs the opponent, both exploring, spread over the lanes (selfplay.sh, one
           runner per lane: a lane's two bridge folders are shared by its games)
    build  each kept replay played back into a training file under runtime/armynet/own-games/<own-set>
           (selfplay_build.sh, one playback at a time)
    train  the candidate fine-tuned from the init model on every self-play set mixed with player replays (train.py)
    gate   candidate vs champion head-to-head over the lanes, sides swapped by seed parity
    pool   a few games against each past champion or candidate (--pool), reported, never gating
    tally  decided games by result.json, a capped game to the side with more standing metal (gate_tally.py);
           promoted at >= 60% of the planned gate games; every champion is kept in runtime/armynet/champions.txt

    python tools/armynet/round.py sp4 --champion e1=runtime/armynet/enemy1/model-010000.pt \\
        --init sp3=runtime/armynet/sp3/model-008000.pt --opponent e1=runtime/armynet/enemy1/model-010000.pt \\
        --play-seeds 121-132 --gate-seeds 133-142 --extra-gate-games 10 --own-rate-k 1.0 \\
        [--pool sp2=runtime/armynet/sp2/model-008000.pt] [--workers 6] [--extra-gate-log <the Mac half's log>] \\
        [--only play,build,...] [--dry-run]

Each step is recorded in runtime/armynet/rounds/<round>.json when it ends; a rerun skips what is done, so a stopped
round resumes where it stopped. Every step waits while his game runs (selfplay.sh, selfplay_build.sh, train.py).
"""
import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
RT = REPO / "runtime" / "armynet"
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gate_tally import tally  # noqa: E402

FLAGS = "--forces --learned --rally --arc --fbias -0.19"
STEPS = ("play", "build", "train", "gate", "pool", "tally")


def seeds(spec):
    a, _, b = spec.partition("-")
    return list(range(int(a), int(b or a) + 1))


def split(xs, n):
    """Contiguous chunks, one per lane."""
    k, r = divmod(len(xs), n)
    out, i = [], 0
    for j in range(n):
        m = k + (j < r)
        out.append(xs[i:i + m])
        i += m
    return out


def named(spec):
    name, _, path = spec.partition("=")
    p = Path(path)
    if not p.is_absolute():
        p = REPO / p
    return name, p.resolve().as_posix()


class Round:
    def __init__(self, a):
        self.a = a
        self.state_path = RT / "rounds" / ("%s.json" % a.round)
        self.state = json.loads(self.state_path.read_text()) if self.state_path.exists() else {"round": a.round}
        self.bash = shutil.which("bash") or "bash"

    def save(self):
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        self.state_path.write_text(json.dumps(self.state, indent=1))

    def log(self, msg):
        line = "%s %s: %s" % (time.strftime("%m-%d %H:%M"), self.a.round, msg)
        print(line, flush=True)
        if self.a.dry_run:
            return
        (RT / "rounds").mkdir(parents=True, exist_ok=True)
        with open(RT / "rounds" / ("%s.log" % self.a.round), "a") as f:
            f.write(line + "\n")

    def run(self, cmd, env=None, out=None):
        """Run a command from the repo root; in a dry run only print it."""
        shown = " ".join(cmd) + ((" > " + str(out)) if out else "")
        if self.a.dry_run:
            print("  would run:", shown, "(env %s)" % env if env else "")
            return None
        self.log("run " + shown)
        e = dict(os.environ, **(env or {}))
        fh = open(out, "w") if out else None
        try:
            return subprocess.Popen(cmd, cwd=REPO, env=e, stdout=fh or None, stderr=subprocess.STDOUT if fh else None)
        finally:
            if fh:
                fh.close()

    def lanes_games(self, kind, seed_list, x, y):
        """selfplay.sh on every lane at once, one runner per lane; returns the ladder logs."""
        logs, procs = [], []
        for lane, ss in zip(self.a.lanes, split(seed_list, len(self.a.lanes))):
            if not ss:
                continue
            tag = "%s-%s-%s" % (self.a.round, kind, lane)
            lg = RT / ("h2h-%s.log" % tag)
            logs.append(str(lg))
            # a resumed round plays only the seeds its ladder has no line for (a lane plays its seeds in order)
            have = {int(ln.split()[1]) for ln in open(lg) if ln.startswith("seed ")} if lg.exists() else set()
            ss = [s for s in ss if s not in have]
            if not ss:
                continue
            procs.append(self.run([self.bash, "tools/armynet/selfplay.sh", tag, str(ss[0]), str(ss[-1]), x, y],
                                  env={"LANE": lane}, out=RT / ("%s.out" % tag)))
        for p in procs:
            if p is not None and p.wait() != 0:
                raise SystemExit("a lane's runner failed (see runtime/armynet/%s-%s-*.out)" % (self.a.round, kind))
        return logs

    def matches(self, logs):
        out = []
        for lg in logs:
            if Path(lg).exists():
                out += [ln.split()[6] for ln in open(lg) if ln.startswith("seed ") and len(ln.split()) >= 7]
        return out

    def step_play(self):
        cn, cp = self.init
        on, op = self.opponent
        ex = " --explore %s" % self.a.explore
        x, y = "%s|%s|%s%s" % (cn, cp, FLAGS, ex), "%s|%s|%s%s" % (on + ("2" if on == cn else ""), op, FLAGS, ex)
        return {"logs": self.lanes_games("play", seeds(self.a.play_seeds), x, y)}

    def step_build(self):
        ms = self.matches(self.state.get("play", {}).get("logs", []))
        p = self.run([self.bash, "tools/armynet/selfplay_build.sh", self.own_set] + ms,
                     out=RT / ("%s-build.out" % self.a.round))
        if p is not None and p.wait() != 0:
            raise SystemExit("selfplay_build.sh failed")
        return {"set": self.own_set, "games": len(ms)}

    def own_sets(self):
        """What training reads: --own-sets, else the first set and every set a round has built, this one's last."""
        if self.a.own_sets:
            return self.a.own_sets.split(",")
        sets = ["selfplay-r1"]
        for f in sorted((RT / "rounds").glob("*.json")):
            s = json.loads(f.read_text()).get("build", {}).get("set")
            if s and s not in sets:
                sets.append(s)
        if self.own_set not in sets:
            sets.append(self.own_set)
        return [s for s in sets if (RT / "own-games" / s).is_dir() or s == self.own_set]

    def step_train(self):
        out = RT / self.a.round
        own = ",".join((RT / "own-games" / s).as_posix() for s in self.own_sets())
        cmd = [sys.executable, "-u", "tools/armynet/train.py", "--init", self.init[1], "--steps", str(self.a.steps),
               "--save-every", str(self.a.steps), "--workers", str(self.a.workers), "--out", out.as_posix(),
               "--own", own, "--own-share", str(self.a.own_share)]
        cmd += self.a.train_arg
        env = {"BARAI_OWN_RATE_K": str(self.a.own_rate_k)} if self.a.own_rate_k is not None else None
        p = self.run(cmd, env=env, out=RT / ("%s-train.out" % self.a.round))
        if p is not None and p.wait() != 0:
            raise SystemExit("train.py failed (runtime/armynet/%s-train.out)" % self.a.round)
        return {"model": (out / ("model-%06d.pt" % self.a.steps)).as_posix(), "init": self.init[1], "own": own,
                "own_rate_k": self.a.own_rate_k}

    def step_gate(self):
        cand = self.state.get("train", {}).get("model") or "%s/model-%06d.pt" % ((RT / self.a.round).as_posix(),
                                                                                   self.a.steps)
        cn, cp = self.champion
        x, y = "%s|%s|%s" % (self.a.round, cand, FLAGS), "%s|%s|%s" % (cn, cp, FLAGS)
        return {"logs": self.lanes_games("gate", seeds(self.a.gate_seeds), x, y), "candidate": cand}

    def step_tally(self):
        logs = self.state.get("gate", {}).get("logs", []) + self.a.extra_gate_log
        t, n = tally(logs)
        planned = len(seeds(self.a.gate_seeds)) + self.a.extra_gate_games
        bar = math.ceil(0.6 * planned)
        won = sum(t.get(self.a.round, [0, 0]))
        promoted = n >= planned and won >= bar
        verdict = ("PROMOTED" if promoted else "not promoted") + ": %s %d of %d (bar %d of %d planned; %s)" % (
            self.a.round, won, n, bar, planned,
            ", ".join("%s %d decided + %d at cap" % (k, v[0], v[1]) for k, v in sorted(t.items())))
        if n < planned:
            verdict += " -- %d games missing, verdict open" % (planned - n)
        self.log(verdict)
        # the pool is read, never gating (11-26): a clear loss to a past champion or candidate is flagged
        pool = {}
        for lg in self.state.get("pool", {}).get("logs", []):
            pt, pn = tally([lg], verbose=False)
            other = [k for k in pt if k != self.a.round]
            opp = Path(lg).stem.split("-pool-")[-1].rsplit("-", 1)[0]
            pw = sum(pt.get(self.a.round, [0, 0]))
            pool[opp] = (pw, pn)
            if pn and pw <= pn // 4:
                self.log("POOL FLAG: %s won only %d of %d against %s" % (self.a.round, pw, pn, opp))
            elif pn:
                self.log("pool: %s %d of %d against %s%s" % (self.a.round, pw, pn, opp, " (" + ",".join(other) + ")"
                                                              if other else ""))
        if promoted and not self.a.dry_run:
            with open(RT / "champions.txt", "a") as f:
                f.write("%s %s %s %d/%d\n" % (time.strftime("%Y-%m-%d %H:%M"), self.a.round,
                                               self.state["gate"]["candidate"], won, n))
        return {"won": won, "games": n, "planned": planned, "bar": bar, "promoted": promoted, "tally": t,
                "complete": n >= planned, "pool": pool}

    def step_pool(self):
        """A few games of the candidate against each pool member, for the report only."""
        cand = self.state.get("gate", {}).get("candidate") or "%s/model-%06d.pt" % ((RT / self.a.round).as_posix(),
                                                                                    self.a.steps)
        logs, s0 = [], seeds(self.a.gate_seeds)[-1] + 1
        for spec in self.a.pool:
            pn, pp = named(spec)
            ss = list(range(s0, s0 + self.a.pool_games))
            s0 += self.a.pool_games
            x, y = "%s|%s|%s" % (self.a.round, cand, FLAGS), "%s|%s|%s" % (pn, pp, FLAGS)
            logs += self.lanes_games("pool-%s" % pn, ss, x, y)
        return {"logs": logs}

    def go(self):
        a = self.a
        self.champion = named(a.champion)
        self.init = named(a.init) if a.init else self.champion
        self.opponent = named(a.opponent) if a.opponent else self.init
        self.own_set = a.own_set or a.round
        if not a.pool:
            only_pool = {"pool"}
            a.only = ",".join(s for s in (a.only.split(",") if a.only else STEPS) if s not in only_pool)
        only = set(a.only.split(",")) if a.only else set(STEPS)
        for s in STEPS:
            if s not in only:
                continue
            if s in self.state and not (s == "tally" and not self.state[s].get("complete")):
                print("%s: done (%s)" % (s, json.dumps(self.state[s])[:160]))
                continue
            print("== %s" % s, flush=True)
            res = getattr(self, "step_" + s)()
            if not a.dry_run:
                self.state[s] = res
                self.save()
                self.log("%s done: %s" % (s, json.dumps(res)[:300]))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("round")
    ap.add_argument("--champion", required=True, help="name=path of the model the gate plays (the one to beat)")
    ap.add_argument("--init", help="name=path training starts from and self-play plays as (default: the champion)")
    ap.add_argument("--opponent", help="name=path the init model plays in self-play (default: itself)")
    ap.add_argument("--pool", action="append", default=[], help="name=path of a past champion or candidate: "
                    "--pool-games against each, reported, never gating (repeatable)")
    ap.add_argument("--pool-games", type=int, default=4)
    ap.add_argument("--own-rate-k", type=float, help="BARAI_OWN_RATE_K for training (data.py _force_labels)")
    ap.add_argument("--own-sets", help="comma list of own-games sets training reads (default: selfplay-r1 and every "
                    "set a round built)")
    ap.add_argument("--lanes", type=lambda s: s.split(","), default=["armynet", "rel521"])
    ap.add_argument("--play-seeds", default="1-12")
    ap.add_argument("--gate-seeds", default="1-20")
    ap.add_argument("--extra-gate-log", action="append", default=[], help="ladder log of gate games played elsewhere")
    ap.add_argument("--extra-gate-games", type=int, default=0, help="gate games planned elsewhere (the Mac half)")
    ap.add_argument("--explore", default="1.0")
    ap.add_argument("--own-set", help="the set this round's games are built into (default: the round's name)")
    ap.add_argument("--own-share", default="0.5")
    ap.add_argument("--steps", type=int, default=8000)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--train-arg", action="append", default=[], help="passed through to train.py (repeatable)")
    ap.add_argument("--only", help="comma list of steps to run (play,build,train,gate,tally)")
    ap.add_argument("--dry-run", action="store_true")
    Round(ap.parse_args()).go()


if __name__ == "__main__":
    main()
