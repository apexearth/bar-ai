"""Watched training games, one after another (his 10-29: "a 9th game in watch mode so I can see the training live"):
a random training setup (at most 4 a side, at least 25 minutes, its own handicaps), 10x, playing this moment's leans plus a
fresh push. The AI says in chat what the game tries and what training has found (policy.as PnWatchSay). Not counted
by the training. Runs while runtime/lean/watch_on exists.

    python tools/watchlean.py
"""
import os
import random
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
import leanloop  # noqa: E402
import randsearch  # noqa: E402

ON = os.path.join(leanloop.LEAN, "watch_on")


def main():
    while os.path.exists(ON):
        seed = random.randrange(1, 1000000)
        s = randsearch.draw_setup(seed)
        s["per_side"] = min(s["per_side"], 4)
        s["minutes"] = max(s["minutes"], 25)
        out = os.path.join(REPO, "matches", "watch-lean-%d" % seed)
        os.makedirs(out, exist_ok=True)
        w = os.path.join(out, "watch.weights")
        leanloop.watch_file(w)
        print(time.strftime("%m-%d %H:%M"), "watch game", seed, s, flush=True)
        subprocess.run([sys.executable, os.path.join(REPO, "tools", "run_match.py"), "--a", leanloop.neuro.AI,
                        "--b", s["foe"], "--per-side", str(s["per_side"]), "--map", s["map"], "--minutes",
                        str(s["minutes"]), "--seed", str(seed), "--sides", "%s,%s" % tuple(s["sides"]), "--watch",
                        "--speed", "10", "--handicap", "%d,%d" % tuple(s["handicap"]), "--ai-options-file", w[:-len(".weights")] + ".json",
                        "--out", out], cwd=REPO, env=dict(os.environ, BARAI_LANE="nnlog"),
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
