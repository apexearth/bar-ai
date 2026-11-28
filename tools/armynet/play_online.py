#!/usr/bin/env python3
"""Run the army model for an Apex bot in a game you play or host (AI option "Army model (experimental)" on).

    python tools/armynet/play_online.py [--model runtime/armynet/<run>/model.pt] [--previous] [--root <Apex folder>]

The default is G2 (11-27, results/armynet/2026-11-27-head-to-head-H2.md): the memory-fix model with his flags plus
--cluster-fight --force-idle and --absent. --previous plays what ran before it (enemy1 with his flags), one step back.

Start it before or during the game. It waits for the bot to write its armynet-t<team>/ folder under BAR's
AI/Skirmish/Apex/, then answers it every step (tools/armynet/serve.py). With the option on and this not running, the
bot keeps its army under its own control (ArmyNetBridge.inc: no orders for 20 s, nothing held). Stop it with Ctrl+C;
the bot takes its army back 20 s later. One bot per run: enable the option on one Apex seat.
"""
import glob
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools"))
FLAGS = ["--forces", "--learned", "--rally", "--arc", "--fbias", "-0.19"]
CURRENT = ("enemy1-absent", FLAGS + ["--cluster-fight", "--force-idle", "--absent"])
PREVIOUS = ("enemy1", FLAGS)   # before 11-27


def main(a):
    import bar_env
    env = bar_env.load()
    data = Path(str(getattr(env, "data", "") or os.environ.get("BAR_DATA", "")))
    if not data.exists():
        data = Path(os.environ["LOCALAPPDATA"]) / "Programs" / "Beyond-All-Reason" / "data"
    root = Path(a[a.index("--root") + 1]) if "--root" in a else data / "AI" / "Skirmish" / "Apex"
    run, flags = PREVIOUS if "--previous" in a else CURRENT
    model = a[a.index("--model") + 1] if "--model" in a else ""
    if not model:
        cands = sorted(glob.glob(str(REPO / "runtime" / "armynet" / run / "model-*.pt")))
        model = cands[-1] if cands else ""
    if not model:
        raise SystemExit("no model found; pass --model")
    print("model %s\nwatching %s" % (model, root), flush=True)
    extra = [x for i, x in enumerate(a) if x not in ("--model", model, "--install", "--uninstall", "--previous", "--root")
             and not (i and a[i - 1] == "--root")]
    if not extra:
        extra = list(flags)
    print("flags %s" % " ".join(extra), flush=True)
    launch = root / "armynet-launch.txt"
    if "--install" in a:
        # his 11-24: every bot with the option starts its own server (ArmyNetLaunch, a DLL with the launch); this
        # script is then not needed and must not also run, or two servers command one bot
        launch.write_text("\n".join([sys.executable, "-u", str(REPO / "tools" / "armynet" / "serve.py"),
                                     "--model", str(Path(model).resolve()), *extra]) + "\n", encoding="utf-8")
        print("wrote %s: each bot with the option starts its own server" % launch)
        return 0
    if "--uninstall" in a:
        if launch.exists():
            os.replace(launch, launch.with_suffix(".off"))
        print("auto-launch off (%s)" % launch.with_suffix(".off"))
        return 0
    if launch.exists():
        raise SystemExit("%s is installed: the bots start their own servers (--uninstall to use this instead)" % launch)
    while True:
        rc = subprocess.call([sys.executable, "-u", str(REPO / "tools" / "armynet" / "serve.py"), "--find", str(root),
                              "--model", model, *extra])
        if rc != 3:   # 3: serve.py saw a new game begin; start fresh for it
            return rc
        print("next game: waiting for its bot", flush=True)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
