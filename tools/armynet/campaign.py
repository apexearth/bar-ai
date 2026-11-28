#!/usr/bin/env python3
"""Train the army model without end and give him a watch game for every N steps (his 11-18).

    python tools/armynet/campaign.py [--every 10000] [--init <model.pt>] [--minutes 40]

Three loops: the datasets of new recordings are built every 10 minutes (overnight.py --build-only); one training
run goes on (train.py --constant-lr --refresh --save-every N: the game list re-read every 10 minutes, a numbered
checkpoint every N steps); each new checkpoint gets a watch game (watch.py: the lane AI both sides, side A's army
the checkpoint's), never while his own game runs and one at a time. Every game writes one line to
runtime/armynet/campaign-<stamp>/campaign.log: the step, the last held-out eval, the winner and length, and side A's
contract numbers against side B's (raider repeat kills /10 min, ground given up).
"""
import glob
import json
import re
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools"))
import contract  # noqa: E402
import mp_archive  # noqa: E402


def score(match_dir):
    res = (json.loads((match_dir / "result.json").read_text()).get("result") or {}) if (match_dir / "result.json").exists() else {}
    seats = {s.team: s for s in contract.load(match_dir)} if (match_dir / "infolog.txt").exists() else {}
    def num(team, fn):
        s = seats.get(team)
        v = fn(s) if s else None
        return None if v is None else round(v, 2)
    return {"winners": res.get("winners"), "minutes": res.get("game_minutes") or res.get("minutes"),
            "reason": res.get("reason"),
            "raider_repeats_A": num(0, contract.raider_repeat_kills), "raider_repeats_B": num(1, contract.raider_repeat_kills),
            "ground_given_up_A": num(0, contract.ground_given_up), "ground_given_up_B": num(1, contract.ground_given_up)}


def last_eval(log):
    try:
        lines = [l for l in log.read_text(errors="replace").splitlines() if l.startswith("eval ")]
    except OSError:
        return None
    return lines[-1][5:] if lines else None


def main(a):
    def opt(name, default):
        return a[a.index(name) + 1] if name in a else default
    every = int(opt("--every", "10000"))
    out = REPO / "runtime" / "armynet" / ("campaign-" + time.strftime("%Y%m%d-%H%M"))
    out.mkdir(parents=True, exist_ok=True)
    clog = open(out / "campaign.log", "a", buffering=1)
    builder = subprocess.Popen([sys.executable, "-u", str(REPO / "tools" / "armynet" / "overnight.py"), "--build-only"],
                               stdout=open(out / "build.log", "w"), stderr=subprocess.STDOUT)
    cmd = [sys.executable, "-u", str(REPO / "tools" / "armynet" / "train.py"), "--steps", "100000000", "--constant-lr",
           "--refresh", "--save-every", str(every), "--batch", "32", "--workers", opt("--workers", "4"),
           "--out", str(out)]
    if "--init" in a:
        cmd += ["--init", opt("--init", ""), "--start-step", opt("--start-step", "0")]
    if "--mirror" in a:
        cmd += ["--mirror"]
    if "--late" in a:
        cmd += ["--late"]
    if "--rounds" in a:
        cmd += ["--rounds"]
    trainer = subprocess.Popen(cmd, stdout=open(out / "train.log", "w"), stderr=subprocess.STDOUT)
    clog.write("campaign %s: a watch game every %d steps\n" % (out.name, every))
    watched = set()
    try:
        while trainer.poll() is None:
            ckpts = sorted(glob.glob(str(out / "model-*.pt")))
            new = [c for c in ckpts if c not in watched]
            if new and not mp_archive.his_game_running():
                ck = new[-1]
                watched.update(new)
                step = int(re.search(r"model-(\d+)", ck).group(1))
                # his 11-19: "stop the watch games for now" -- with --headless N each checkpoint plays N games with no
                # window (seeds alternate the faction), for tools/armynet/gaps.py
                games = int(opt("--headless", "0")) or 1
                for gi in range(games):
                    seed = step // every * games + gi
                    clog.write("step %d: game %d starting (seed %d)\n" % (step, gi + 1, seed))
                    wlog = out / ("watch-%06d-%d.log" % (step, gi))
                    subprocess.run([sys.executable, str(REPO / "tools" / "armynet" / "watch.py"), "--model", ck,
                                    "--minutes", opt("--minutes", "40"), "--seed", str(seed),
                                    *(["--headless"] if "--headless" in a else []),
                                    *(["--rounds"] if "--rounds" in a else []), "--speed", opt("--speed", "4")], check=False,
                                   stdout=open(wlog, "w"), stderr=subprocess.STDOUT)
                    # the game's own folder, from the write dir watch.py printed (11-19: "the newest new folder"
                    # took another run's game when two overlapped)
                    m = re.search(r"watch-armynet-engine-([\d-]+)", wlog.read_text(errors="replace"))
                    made = [str(REPO / "matches" / ("armynet-watch-" + m.group(1)))] if m else []
                    row = {"step": step, "game": gi + 1, "seed": seed, "eval": last_eval(out / "train.log")}
                    if made:
                        row.update(score(Path(made[-1])))
                        row["match"] = Path(made[-1]).name
                        # report.md, lane.png, film-N.png, timelapse.gif beside the match (his 11-19)
                        subprocess.run([sys.executable, str(REPO / "tools" / "armynet" / "game_report.py"), made[-1]],
                                       check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    clog.write("RESULT " + json.dumps(row) + "\n")
            time.sleep(60)
    finally:
        builder.terminate()
    clog.write("trainer exited %s\n" % trainer.returncode)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
