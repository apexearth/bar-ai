#!/usr/bin/env python3
"""Run one match as a real NETWORK game: a host process and a peer process.

The point is desync. A single-process match cannot desync -- there is nothing
to disagree with. Sync errors only appear when a second client simulates the
same game from the same net stream and reaches a different checksum, which is
what a hosted multiplayer game does and what the benchmark never did.

The asymmetry that matters is that the AI runs on ONE machine. Every [AI] block
carries `Host=0`, so the host process is the only one executing AI code; the
peer only receives its commands. Anything the AI does that touches engine state
directly, rather than by issuing a netted order, diverges on the host alone --
and the host is where "Sync error for <name>" is logged.

    python tools/run_netmatch.py --a Apex:Unstable:standard \
        --b BARb:stable:hard --map "Flats and Forests v2.2" --per-side 4 \
        --minutes 20 --seed 1

Both processes are headless and get their own write dir; sharing one would have
them fight over config and demos. The peer is a spectator, so it adds no team
and changes nothing about the game being played.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bar_env  # noqa: E402
import run_match  # noqa: E402
import apexlog  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
MATCHES = REPO / "matches"

HOST_NAME = "NetHost"
PEER_NAME = "NetPeer"


def _patch_for_two_players(script: str, port: int) -> str:
    """Turn run_match's single-process script into a host-of-two script.

    Reuses build_script rather than restating it: the AI/TEAM/ALLYTEAM/modoption
    layout has to stay identical to the benchmark's, or a desync found here is
    not about the benchmark. Every anchor is asserted -- a str.replace that does
    not match changes nothing and says nothing.
    """
    for old, new in (
        ("\tNumPlayers=1;", "\tNumPlayers=2;"),
        ("\tNumUsers=1;", "\tNumUsers=2;"),
        ("\tHostPort=0;", f"\tHostPort={port};"),
    ):
        assert old in script, f"anchor not found in start script: {old!r}"
        script = script.replace(old, new, 1)

    # The peer sits in PLAYER1 as a spectator. Inserted after PLAYER0's closing
    # brace; section order in a TDF is free, but keeping the players together
    # makes the script readable when a run goes wrong.
    marker = "[PLAYER0]"
    assert marker in script, "PLAYER0 section missing from start script"
    close = script.index("}", script.index(marker)) + 1
    peer = "\n" + run_match._script_section("PLAYER1", {"Name": PEER_NAME, "Spectator": 1})
    return script[:close] + peer + script[close:]


def _client_script(port: int) -> str:
    """All a joining client needs; the server sends the real setup.

    ClientSetup::LoadFromStartScript reads exactly these four, and warns
    "assuming this is a client" when IsHost is absent rather than defaulting
    safely -- so it is stated.
    """
    return "\n".join([
        "[GAME]",
        "{",
        "\tHostIP=127.0.0.1;",
        f"\tHostPort={port};",
        f"\tMyPlayerName={PEER_NAME};",
        "\tIsHost=0;",
        "}",
        "",
    ])


def _launch(exe: Path, write_dir: Path, script: Path) -> subprocess.Popen:
    write_dir.mkdir(parents=True, exist_ok=True)
    # BAR takes ~40s to load here, and both processes load in parallel from one
    # disk. The defaults (GlobalConfig.h: initialNetworkTimeout 30,
    # networkTimeout 120) drop a peer that connects and then waits for the host
    # to finish loading -- which reads as "no sync errors" from a game that
    # never had two participants.
    # SpeedControl is the server's throttle, and it is what caps a net game --
    # MinSpeed 9999 is only a request. 1 (the engine default) holds the MEDIAN
    # client at 60% CPU; 2 targets 75% of the fastest. Both processes are
    # headless on one box, so the ceiling is CPU either way, but 2 stops the
    # server leaving a quarter of it unused.
    (write_dir / "springsettings.cfg").write_text(
        "InitialNetworkTimeout = 600\n"
        "NetworkTimeout = 600\n"
        "ReconnectTimeout = 0\n"
        "SpeedControl = 2\n"
    )
    # Stale widget config silently changes which widgets load; the single-process
    # harness clears this for the same reason.
    shutil.rmtree(write_dir / "LuaUI" / "Config", ignore_errors=True)
    return subprocess.Popen(
        [str(exe), "--write-dir", str(write_dir), str(script)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


SYNC_RE = re.compile(r"Sync error for (\S+) in frame (\d+)")


def _report(out: Path) -> int:
    """Read the host's infolog. Sync errors are logged by the server only."""
    log = out / "host" / "infolog.txt"
    if not log.exists():
        print(f"no host infolog at {log}")
        return 2

    apexlog.merge_into(str(log))   # the AI's own log files, by frame (S31)
    text = log.read_text(errors="replace")

    # A peer that never simulated cannot disagree, so "no sync errors" from a
    # dropped peer is not a result -- it is the absence of one. Gate on it: the
    # first smoke run lost the peer at load and reported a clean game.
    peer_log = out / "peer" / "infolog.txt"
    peer_text = peer_log.read_text(errors="replace") if peer_log.exists() else ""
    peer_frames = [int(f) for f in re.findall(r"\[f=(\d+)\]", peer_text)]
    peer_last = max(peer_frames) if peer_frames else 0
    host_frames = [int(f) for f in re.findall(r"\[f=(\d+)\]", text)]
    host_last = max(host_frames) if host_frames else 0
    print(f"host reached       : frame {host_last} ({host_last / 1800:.1f} game-min)")
    print(f"peer reached       : frame {peer_last} ({peer_last / 1800:.1f} game-min)")
    if peer_last < host_last * 0.9:
        print("INVALID: the peer did not simulate the game -- nothing was compared")
        if "lost connection to server" in peer_text:
            print("         peer lost its connection; raise the network timeouts")
        return 2

    hits = SYNC_RE.findall(text)
    ai_err = len(re.findall(r"\.as \(\d+, \d+\) : ERR", text))
    crashed = "problem with a skirmish AI" in text

    print(f"AngelScript errors : {ai_err}")
    print(f"AI crash           : {'YES' if crashed else 'no'}")
    if not hits:
        print("sync errors        : none -- the two processes agreed all game")
        return 0

    who = sorted({name for name, _ in hits})
    first = min(int(frame) for _, frame in hits)
    print(f"sync errors        : {len(hits)}, first at frame {first} "
          f"({first / 1800:.1f} game-min)")
    print(f"diverged           : {', '.join(who)}")
    return 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--a", dest="a", default="Apex:Unstable:standard")
    ap.add_argument("--b", dest="b", default="BARb:stable:hard")
    ap.add_argument("--map", required=True)
    ap.add_argument("--game", default=None)
    ap.add_argument("--minutes", type=int, default=20)
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--per-side", dest="per_side", type=int, default=1)
    ap.add_argument("--sides", default=None,
                    help="comma-separated, or 'random' for a per-player draw")
    ap.add_argument("--boxes", default="lr", choices=["lr", "tb", "trbl", "tlbr"])
    ap.add_argument("--box-size", dest="box_size", type=float, default=0.0)
    ap.add_argument("--handicap", type=int, default=0)
    ap.add_argument("--speed", type=int, default=9999)
    ap.add_argument("--port", type=int, default=8460)
    ap.add_argument("--timeout", type=int, default=3600,
                    help="wall-clock seconds before both processes are killed")
    ap.add_argument("--out", default=None)
    ap.add_argument("--modoption", action="append", default=[], metavar="K=V")
    args = ap.parse_args()

    env = bar_env.load()
    exe = Path(env.headless)
    if not exe.exists():
        print(f"no spring-headless at {exe}")
        return 2

    # Same resolution path as run_match: the engine's own scanner, never a guess
    # at a display name.
    from unitsync import UnitSync, resolve_map

    with UnitSync(env) as us:
        map_name = resolve_map(args.map, us)
        if args.game:
            game_name = args.game
        else:
            sdd = [g for g in us.games() if g.get("archive", "").endswith(".sdd")]
            if not sdd:
                raise SystemExit("no .sdd game found; pass --game explicitly")
            game_name = sdd[0]["name"]

    out = Path(args.out) if args.out else MATCHES / "netmatch"
    shutil.rmtree(out, ignore_errors=True)
    (out / "host").mkdir(parents=True, exist_ok=True)
    (out / "peer").mkdir(parents=True, exist_ok=True)

    ais = [run_match.AISpec.parse(args.a), run_match.AISpec.parse(args.b)]
    sides = [s.strip() for s in args.sides.split(",")] if args.sides else None
    extra = dict(kv.split("=", 1) for kv in args.modoption)

    script = run_match.build_script(
        ais, map_name, game_name,
        args.minutes, args.seed, host_name=HOST_NAME, speed=args.speed,
        per_side=args.per_side, sides=sides, boxes=args.boxes,
        box_size=args.box_size, handicap=args.handicap, extra_modoptions=extra,
    )
    host_script = out / "host_script.txt"
    peer_script = out / "peer_script.txt"
    host_script.write_text(_patch_for_two_players(script, args.port))
    peer_script.write_text(_client_script(args.port))

    print(f"host {HOST_NAME} (runs both AIs)  peer {PEER_NAME} (spectator)")
    print(f"port {args.port}   map {args.map}   {args.per_side}v{args.per_side}"
          f"   {args.minutes} min")

    host = _launch(exe, out / "host", host_script)
    # The server has to be accepting connections before the peer dials in; a
    # peer that arrives first exits rather than retrying.
    time.sleep(8)
    peer = _launch(exe, out / "peer", peer_script)

    started = time.time()
    try:
        host.wait(timeout=args.timeout)
    except subprocess.TimeoutExpired:
        print(f"timeout after {args.timeout}s -- killing both")
        host.kill()
    finally:
        try:
            peer.wait(timeout=60)
        except subprocess.TimeoutExpired:
            peer.kill()

    print(f"wall {time.time() - started:.0f}s")
    return _report(out)


if __name__ == "__main__":
    raise SystemExit(main())
