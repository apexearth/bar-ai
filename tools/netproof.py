"""The AI as a networked bot: a server, a windowless client that owns the AI,
and a human who joins like any player.

    python tools/netproof.py server            # dedicated server + bot client
    python tools/netproof.py join              # your windowed client joins it
    python tools/netproof.py server --fake-me  # a headless stand-in joins as you

Everything binds to 127.0.0.1. The bot is a spectator in the game script
that hosts the AI -- the same shape a lobby bot would take in someone
else's autohost room.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402
from run_match import _script_section  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
ROOT = REPO / "matches" / "_netproof"
PORT = 8452
ME, BOT = "Player", "ApexBot"
PASS = {ME: "me", BOT: "bot"}


def resolve(env, map_query: str) -> tuple[str, str]:
    from unitsync import UnitSync, resolve_map
    with UnitSync(env) as us:
        map_name = resolve_map(map_query, us)
        sdd = [g for g in us.games() if g.get("archive", "").endswith(".sdd")]
        if not sdd:
            raise SystemExit("no .sdd game found")
        return map_name, sdd[0]["name"]


def host_script(map_name: str, game: str, ai: str, side_me: str, side_ai: str) -> str:
    short, _, version = ai.partition(":")
    body = [
        f"\tMapName={map_name};",
        f"\tGameType={game};",
        "\tStartPosType=1;",
        "\tIsHost=1;",
        "\tHostIP=127.0.0.1;",
        f"\tHostPort={PORT};",
        f"\tMyPlayerName={BOT};",
        _script_section("PLAYER0", {"Name": ME, "Password": PASS[ME], "Spectator": 0, "Team": 0}),
        _script_section("PLAYER1", {"Name": BOT, "Password": PASS[BOT], "Spectator": 1}),
        _script_section("TEAM0", {"TeamLeader": 0, "AllyTeam": 0, "Side": side_me,
                                  "RGBColor": "0.1 0.4 1"}),
        _script_section("TEAM1", {"TeamLeader": 1, "AllyTeam": 1, "Side": side_ai,
                                  "RGBColor": "1 0.2 0.1"}),
        _script_section("AI0", {"Name": f"Apex ({BOT})", "ShortName": short,
                                "Version": version or "Unstable", "Team": 1,
                                "Host": 1}),
        _script_section("ALLYTEAM0", {"NumAllies": 0}),
        _script_section("ALLYTEAM1", {"NumAllies": 0}),
        _script_section("MODOPTIONS", {"maxunits": 2000}),
    ]
    return "[GAME]\n{\n" + "\n".join(body) + "\n}\n"


def client_script(name: str) -> str:
    return ("[GAME]\n{\n\tHostIP=127.0.0.1;\n"
            f"\tHostPort={PORT};\n\tIsHost=0;\n"
            f"\tMyPlayerName={name};\n\tMyPasswd={PASS[name]};\n}}\n")


def launch(env, exe: Path, role: str, script: str, cfg: str | None) -> subprocess.Popen:
    # kept between runs: its archive cache is what makes the join fast enough
    # to beat the server's timeout
    wd = ROOT / role
    wd.mkdir(parents=True, exist_ok=True)
    sp = wd / "script.txt"
    sp.write_text(script, encoding="utf-8")
    # the dedicated server has no --write-dir; it reads SPRING_WRITEDIR
    dedicated = exe == env.dedicated
    cmd = [str(exe)] if dedicated else [str(exe), "--write-dir", str(wd)]
    run_cfg = wd / "run.cfg"
    if cfg:
        shutil.copy2(REPO / "tools" / cfg, run_cfg)
    else:
        run_cfg.write_text("", encoding="utf-8")
    with open(run_cfg, "a", encoding="utf-8") as f:
        f.write("\nInitialNetworkTimeout = 300\nNetworkTimeout = 300\n")
    cmd += ["-config" if dedicated else "--config", str(run_cfg)]
    cmd.append(str(sp))
    log = open(wd / "stdout.txt", "w", encoding="utf-8", errors="replace")
    print(f"{role:9s} {exe.name}  write-dir {wd}")
    penv = {**os.environ, "SPRING_DATADIR": str(env.data)}
    if dedicated:
        penv["SPRING_WRITEDIR"] = str(wd)
    return subprocess.Popen(cmd, cwd=str(env.engine_dir), stdout=log, stderr=subprocess.STDOUT,
                            env=penv)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["server", "join"])
    ap.add_argument("--map", default="Comet Catcher Remake")
    ap.add_argument("--ai", default="Apex:Unstable", help="ShortName:Version the bot hosts")
    ap.add_argument("--sides", default="Armada,Armada", help="your side, the AI's side")
    ap.add_argument("--fake-me", action="store_true",
                    help="a headless client joins as you, to prove the game starts")
    ap.add_argument("--engine")
    args = ap.parse_args()
    env = bar_env.load(args.engine)

    if args.mode == "join":
        p = launch(env, env.spring, "me", client_script(ME), "watch.cfg")
        print(f"joining 127.0.0.1:{PORT} as {ME} (pid {p.pid})")
        return 0

    side_me, _, side_ai = args.sides.partition(",")
    map_name, game = resolve(env, args.map)
    print(f"map      {map_name}\ngame     {game}\nai       {args.ai} hosted by {BOT}")
    procs = [launch(env, env.dedicated, "server", host_script(map_name, game, args.ai,
                                                               side_me, side_ai or side_me), None)]
    time.sleep(3)
    procs.append(launch(env, env.headless, "bot", client_script(BOT), "headless.cfg"))
    if args.fake_me:
        time.sleep(2)
        procs.append(launch(env, env.headless, "me", client_script(ME), "headless.cfg"))
    else:
        print(f"\nserver up on 127.0.0.1:{PORT}. Join with:\n    python tools/netproof.py join")
    print("\nCtrl+C stops the server and the bot.")
    try:
        while all(p.poll() is None for p in procs[:2]):
            time.sleep(2)
    except KeyboardInterrupt:
        pass
    for p in procs:
        if p.poll() is None:
            p.terminate()
    for p, role in zip(procs, ["server", "bot", "me"]):
        print(f"{role:9s} exit {p.poll()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
