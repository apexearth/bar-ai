#!/usr/bin/env python3
"""Play a replay headless and keep the event lines the trainer reads.

    python tools/replay_extract.py <demo.sdfz> [--out DIR] [--timeout S]

His multiplayer games run on the official archive, so the dev gadgets that
write [BARAI_*] lines never ran in them. The replay, played back by
spring-headless with game-patches/widgets/barai_replay_export.lua as a
full-view spectator widget (unsynced: the replay stays valid), writes those
lines for every team. Out: DIR/replay_events.txt (the [BARAI_*] lines),
DIR/replay_meta.json (map, game version, players, AI teams, winners).
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
WIDGET = REPO / "game-patches" / "widgets" / "barai_replay_export.lua"


def demo_script(path):
    """The start script embedded in a .sdfz (gzip of a demo whose header carries it)."""
    raw = Path(path).read_bytes()
    try:
        raw = zlib.decompress(raw, 47)
    except zlib.error:
        pass
    i = raw.find(b"[game]")
    if i < 0:
        return ""
    j = raw.find(b"\x00", i)
    return raw[i:j if j > 0 else i + 200000].decode("utf-8", "replace")


def meta_of(script):
    teams, cur, sect = {}, None, None
    for ln in script.splitlines():
        s = ln.strip()
        m = re.match(r"\[(team|ai|player)(\d+)\]", s, re.I)
        if m:
            sect, cur = m.group(1).lower(), int(m.group(2))
            teams.setdefault((sect, cur), {})
            continue
        m = re.match(r"(\w+)=(.*?);", s)
        if m and cur is not None:
            teams[(sect, cur)][m.group(1).lower()] = m.group(2)
    ally = {k[1]: int(v.get("allyteam", -1)) for k, v in teams.items() if k[0] == "team"}
    ais = [{"team": int(v.get("team", -1)), "short": v.get("shortname"), "version": v.get("version"),
            "name": v.get("name")} for k, v in teams.items() if k[0] == "ai"]
    players = [{"team": int(v.get("team", -1)), "name": v.get("name"), "spec": v.get("spectator")}
               for k, v in teams.items() if k[0] == "player"]
    g = lambda key: (re.search(key + r"=(.*?);", script) or [None, None])[1]
    return {"map": g("mapname"), "game": g("gametype"), "ally": ally, "ais": ais, "players": players}


def extract(demo, out, timeout=3600):
    env = bar_env.load()
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    wd = REPO / "runtime" / ("replay-" + out.name)
    if wd.exists():
        shutil.rmtree(wd, ignore_errors=True)
    (wd / "LuaUI" / "Widgets").mkdir(parents=True)
    shutil.copy2(WIDGET, wd / "LuaUI" / "Widgets" / WIDGET.name)
    shutil.copy2(REPO / "tools" / "headless.cfg", wd / "run.cfg")
    cmd = [str(env.headless), "--write-dir", str(wd), "--config", str(wd / "run.cfg"), str(Path(demo).resolve())]
    t0 = time.time()
    with open(wd / "stdout.txt", "w") as so:
        try:
            subprocess.run(cmd, cwd=str(wd), stdout=so, stderr=subprocess.STDOUT, timeout=timeout,
                           env={**os.environ, "SPRING_DATADIR": str(env.data)})
        except subprocess.TimeoutExpired:
            pass
    lines = []
    log = wd / "infolog.txt"
    if log.is_file():
        for ln in log.read_text(encoding="utf-8", errors="replace").splitlines():
            if "[BARAI_" in ln:
                lines.append(ln)
    (out / "replay_events.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    meta = meta_of(demo_script(demo))
    res = [ln for ln in lines if "[BARAI_RESULT]" in ln]
    m = re.search(r"winners=([\d,]*)", res[-1]) if res else None
    meta.update({"demo": str(demo), "winners": [int(x) for x in m.group(1).split(",") if x] if m else None,
                 "events": len(lines), "wall_s": round(time.time() - t0)})
    (out / "replay_meta.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")
    shutil.rmtree(wd, ignore_errors=True)
    return meta


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    demo = argv[0]
    out = argv[argv.index("--out") + 1] if "--out" in argv else str(REPO / "runtime" / "replays" / Path(demo).stem)
    to = int(argv[argv.index("--timeout") + 1]) if "--timeout" in argv else 3600
    meta = extract(demo, out, to)
    print(json.dumps({k: meta[k] for k in ("map", "game", "winners", "events", "wall_s")}))
    print("ais:", meta["ais"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
