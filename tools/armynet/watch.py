#!/usr/bin/env python3
"""A watch game where the army model fights for our side.

    python tools/armynet/watch.py [--model runtime/armynet/<run>/model.pt] [--map "Comet Catcher"] [--minutes 30]
                                  [--ai Apexarmynet:lane-armynet:standard] [--vs <the same>] [--seed N]

Side A's AI keeps the economy and production; every army/air/radar/jammer unit it finishes is marked hands-off
(game-patches/gadgets/dev_armynet.lua; the lane DLL's CCircuitAI::Update drops it from its own control but still
owns and counts it) and the model commands it (tools/armynet/serve.py). Side B is the same AI with its own army.
Windowed at 10x, both AIs +50 (his watch settings). The model defaults to the newest runtime/armynet/*/model.pt.
"""
import glob
import re
import os
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def ai_scouts(ai):
    """The unit types our AI's own config gives the scout role first: the AI keeps them (his 11-20: with the model
    holding every armed unit our side made no Ticks or Rovers, ran no scout task, and saw 21 metal of their army
    at 6 min against the other side's 628, so its army, radar and production read an empty map)."""
    sys.path.insert(0, str(REPO / "tools"))
    import bar_env
    short, variant = ai.split(":")[:2]
    cfg = bar_env.load().skirmish_dir(short, variant) / "config" / "behaviour.json"
    text = re.sub(r"\s+", "", re.sub(r"//[^\n]*", "", cfg.read_text(encoding="utf-8")))
    return sorted(set(re.findall(r'"([a-z0-9_]+)":\{"role":\["scout"', text)))


def main(a):
    def opt(name, default):
        return a[a.index(name) + 1] if name in a else default
    models = sorted(glob.glob(str(REPO / "runtime" / "armynet" / "*" / "model.pt")), key=os.path.getmtime)
    model = opt("--model", models[-1] if models else "")
    if not model and "--nomodel" not in a:
        sys.exit("no model under runtime/armynet")
    stamp = time.strftime("%Y%m%d-%H%M%S") + "-%d" % os.getpid()
    # matches/watch-*: mp_archive.his_game_running() does not take our watch games for his
    wd = REPO / "matches" / ("watch-armynet-engine-" + stamp)
    wd.mkdir(parents=True, exist_ok=True)
    print("model", model, "\nwrite dir", wd, flush=True)
    log = open(wd / "serve.log", "w")
    ai = opt("--ai", "Apexarmynet:lane-armynet:standard")
    keep = ",".join(ai_scouts(ai))
    # --keep-air (his 11-22: "our air seems to mostly just act defensively, they aren't trying to attack the enemy base"):
    # our AI keeps its flyers -- its air layer strikes their economy -- and the model commands the ground army
    # --keep-aa (his 11-22: "we also send AA bots straight into an enemy army"): our AI keeps its mobile anti-air too
    if "--keep-aa" in a:
        aa = (REPO / "runtime" / "armynet" / "aa_defs.txt").read_text().split()
        keep = ",".join(sorted(set(keep.split(",")) | set(aa)))
    if "--keep-air" in a:
        air = (REPO / "runtime" / "armynet" / "air_defs.txt").read_text().split()
        keep = ",".join(sorted(set(keep.split(",")) | set(air)))
    print("our AI keeps", keep, flush=True)
    # --nomodel: the control, our AI's own army on side A, nothing hands-off
    nomodel = "--nomodel" in a
    serve = subprocess.Popen([sys.executable, "-c", "pass"]) if nomodel else subprocess.Popen(
                             [sys.executable, "-u", str(REPO / "tools" / "armynet" / "serve.py"), "--dir", str(wd),
                              "--model", model, "--keep", keep, *(["--rounds"] if "--rounds" in a else []),
                              *(["--forces"] if "--forces" in a else []), *(["--layer"] if "--layer" in a else []),
                              *(["--learned"] if "--learned" in a else []),
                              *(["--sample-place"] if "--sample-place" in a else []),
                              *(["--rally"] if "--rally" in a else []),
                              *(["--arc"] if "--arc" in a else []),
                              *(["--dumpforces"] if "--dumpforces" in a else []),
                              *(["--wake", opt("--wake", "0.34")] if "--wake" in a else []),
                              *(["--commit", opt("--commit", "0.5")] if "--commit" in a else []),
                              *[x for k in ("--arc-rows", "--range-frac", "--standoff") if k in a for x in (k, opt(k, ""))],
                              *(["--arc-inrange"] if "--arc-inrange" in a else []),
                              *(["--kind-mode", opt("--kind-mode", "model")] if "--kind-mode" in a else []),
                              *(["--place", opt("--place", "cells")] if "--place" in a else []),
                              *(["--split-defs"] if "--split-defs" in a else []),
                              *[k for k in ("--hybrid", "--unit-contact", "--gather") if k in a],
                              *(["--judge", opt("--judge", "5")] if "--judge" in a else []),
                              *(["--fbias", opt("--fbias", "0")] if "--fbias" in a else [])],
                             stdout=log, stderr=subprocess.STDOUT)
    try:
        # his 11-18: "For future games, please run same faction on both sides."
        faction = opt("--faction", ("Armada", "Cortex")[int(opt("--seed", "1")) % 2])
        subprocess.run([sys.executable, str(REPO / "tools" / "run_match.py"), "--a", ai,
                        "--b", opt("--vs", ai), "--map", opt("--map", "Comet Catcher Remake 1.8"),
                        "--minutes", opt("--minutes", "30"), "--seed", opt("--seed", "1"),
                        *(["--replay"] if "--headless" in a else ["--watch"]), "--speed", opt("--speed", "10"),
                        "--handicap", "50,50", "--sides", "%s,%s" % (faction, faction), "--ai-option", "apex_verbose=1",
                        "--modoption", "dev_armynet=%d" % (not nomodel), "--modoption", "dev_armynet_keep=" + keep,
                        # his 11-22: the arena (dev_arena.lua), armies spawned on both sides, as a fight-only test bed
                        *[x for i, v in enumerate(a) if v == "--mod" for x in ("--modoption", a[i + 1])],
                        # a scenario's scripted groups (dev_scenario.lua) belong to a NullAI holder seat
                        *[x for i, v in enumerate(a) if v == "--extra-ai" for x in ("--extra-ai", a[i + 1])],
                        "--write-dir", str(wd), "--out", str(REPO / "matches" / ("armynet-watch-" + stamp))], check=False)
    finally:
        serve.terminate()
    print("serve log:", wd / "serve.log")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
