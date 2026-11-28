#!/usr/bin/env python3
"""Turn new recordings into datasets as they land; start training once enough games exist.

    python tools/armynet/overnight.py [--min-games 300] [--steps 30000]

Builds .npz for every finished recording (public first) every 10 minutes; when at least --min-games public
games have datasets, runs train.py once (runtime/armynet/<stamp>/, its log beside it) and keeps building.
Pauses while his game runs.
"""
import glob
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools"))
import mp_archive  # noqa: E402

PUBLIC = "G:/bar-ai-archive/public-replays/recordings"
LOCAL = "G:/bar-ai-archive/replay-orders"


def main(a):
    min_games = int(a[a.index("--min-games") + 1]) if "--min-games" in a else 300
    steps = a[a.index("--steps") + 1] if "--steps" in a else "30000"
    trainer = None
    while True:
        if mp_archive.his_game_running():
            time.sleep(300)
            continue
        for root in (PUBLIC, LOCAL):
            subprocess.run([sys.executable, str(REPO / "tools" / "replay_dataset.py"), root], check=False)
        n = len(glob.glob(PUBLIC + "/*/*.npz"))
        print(time.strftime("%H:%M"), "public games with datasets:", n, flush=True)
        if "--build-only" in a:
            time.sleep(600)
            continue
        if trainer is None and n >= min_games:
            out = REPO / "runtime" / "armynet" / time.strftime("%Y%m%d-%H%M")
            out.mkdir(parents=True, exist_ok=True)
            log = open(out / "train.log", "w")
            trainer = subprocess.Popen([sys.executable, "-u", str(REPO / "tools" / "armynet" / "train.py"),
                                        "--steps", steps, "--batch", "32", "--workers", "6", "--out", str(out)],
                                       stdout=log, stderr=subprocess.STDOUT)
            print("training started:", out, flush=True)
        if trainer is not None and trainer.poll() is not None:
            print("training finished, exit", trainer.returncode, flush=True)
            return 0
        time.sleep(600)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
