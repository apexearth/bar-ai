#!/usr/bin/env python3
"""His multiplayer games become training games.

    python tools/mp_archive.py            # one pass: archive new games, build what has a replay
    python tools/mp_archive.py --watch    # every 60 s, while no windowed game of his is running

1. ARCHIVE. Our AI writes its decisions to data/AI/Skirmish/<short>/<version>/
   apex-tN.log, and the next game overwrites them (one .prev.log is kept). A
   game is kept only when its logs carry decision records (apex: nn rows --
   v0.1.5 and older have none): the logs are copied to
   runtime/mpgames/<stamp>-<version>/ with the replay written within minutes
   of them (data/demos) and data/infolog.txt when it belongs to that game.
2. BUILD. The replay is played back headless with the export widget
   (tools/replay_extract.py), which writes the [BARAI_*] outcome lines the dev
   gadgets never wrote online. Our AI's log lines plus those lines become
   matches/mp-<stamp>/infolog.txt with a result.json -- a finished game the
   trainer reads like any other, weighted HUMAN_W times (tools/nntrain.py).
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402
import replay_extract  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
ARCH = REPO / "runtime" / "mpgames"
STATE = ARCH / "state.json"
DEMO_WINDOW_S = 900     # the replay is written when the game ends, as the logs stop
MARK = (b"apex: nn-schema", b"apex: nn t=")


def his_game_running():
    try:
        out = subprocess.run(["powershell", "-NoProfile", "-Command",
                              "(Get-Process spring -ErrorAction SilentlyContinue | Measure-Object).Count"],
                             capture_output=True, text=True, timeout=30).stdout.strip()
        return out not in ("", "0")
    except (OSError, subprocess.SubprocessError):
        return True


def has_decisions(path):
    with open(path, "rb") as fh:
        while True:
            chunk = fh.read(1 << 22)
            if not chunk:
                return False
            if any(m in chunk for m in MARK):
                return True


def load_state():
    try:
        return json.loads(STATE.read_text())
    except (OSError, ValueError):
        return {"seen": []}


def archive(env, state):
    new = []
    for vdir in sorted((env.data / "AI" / "Skirmish").glob("Apex*/*")):
        for kind, pat in (("cur", "apex-t*.log"), ("prev", "apex-t*.prev.log")):
            files = [p for p in vdir.glob(pat) if (kind == "prev") == p.name.endswith(".prev.log")]
            if not files:
                continue
            sig = "|".join(sorted("%s:%d:%d" % (p.name, p.stat().st_size, int(p.stat().st_mtime)) for p in files))
            if sig in state["seen"]:
                continue
            state["seen"].append(sig)
            keep = [p for p in files if has_decisions(p)]
            if not keep:
                continue
            end = max(p.stat().st_mtime for p in keep)
            stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(end))
            dest = ARCH / ("%s-%s" % (stamp, vdir.name))
            dest.mkdir(parents=True, exist_ok=True)
            for p in keep:
                shutil.copy2(p, dest / p.name.replace(".prev", ""))
            demos = sorted((env.data / "demos").glob("*.sdfz"), key=lambda q: abs(q.stat().st_mtime - end))
            demo = demos[0] if demos and abs(demos[0].stat().st_mtime - end) < DEMO_WINDOW_S else None
            info = env.data / "infolog.txt"
            if info.is_file() and abs(info.stat().st_mtime - end) < DEMO_WINDOW_S:
                shutil.copy2(info, dest / "infolog.game.txt")
            (dest / "game.json").write_text(json.dumps({
                "version": vdir.name, "short": vdir.parent.name, "ended": stamp,
                "logs": [p.name for p in keep], "demo": str(demo) if demo else None}, indent=1))
            new.append(dest)
            print("archived %s (%d logs, demo %s)" % (dest.name, len(keep), demo.name if demo else "none"), flush=True)
    return new


def build(gdir):
    """runtime/mpgames/<g> with a replay -> matches/mp-<g> the trainer reads."""
    meta = json.loads((gdir / "game.json").read_text())
    out = REPO / "matches" / ("mp-" + gdir.name)
    if (out / "result.json").is_file() or not meta.get("demo") or not Path(meta["demo"]).is_file():
        return None
    rep = replay_extract.extract(meta["demo"], gdir / "replay")
    events = (gdir / "replay" / "replay_events.txt").read_text(encoding="utf-8", errors="replace")
    if "[BARAI_" not in events:
        print("no events from %s" % meta["demo"], flush=True)
        return None
    out.mkdir(parents=True, exist_ok=True)
    with open(out / "infolog.txt", "w", encoding="utf-8") as fo:
        for name in meta["logs"]:
            p = gdir / name.replace(".prev", "")
            with open(p, encoding="utf-8", errors="replace") as fi:
                for ln in fi:
                    if "apex:" in ln:
                        fo.write(ln)
        fo.write(events)
    frames = [int(m) for m in re.findall(r"\[BARAI_RESULT\] reason=\w+ frame=(\d+)", events)] \
        or [int(m) for m in re.findall(r"frame=(\d+)", events[-4000:])]
    result = {"winners": rep.get("winners") or [], "reason": "replay",
              "game_minutes": round((max(frames) if frames else 0) / 1800.0, 2)}
    (out / "result.json").write_text(json.dumps({
        "map": rep.get("map"), "game": rep.get("game"), "source": "multiplayer", "demo": meta["demo"],
        "ais": rep.get("ais"), "players": rep.get("players"), "result": result}, indent=1))
    print("built %s: %d event lines, winners %s, %.1f min" % (out.name, events.count("\n"), result["winners"],
                                                             result["game_minutes"]), flush=True)
    return out


def one_pass(env):
    state = load_state()
    ARCH.mkdir(parents=True, exist_ok=True)
    archive(env, state)
    STATE.write_text(json.dumps(state))
    for g in sorted(ARCH.glob("*")):
        if g.is_dir() and (g / "game.json").is_file():
            build(g)


def main(argv):
    env = bar_env.load()
    if "--watch" not in argv:
        one_pass(env)
        return 0
    while True:
        if not his_game_running():
            one_pass(env)
        time.sleep(60)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
