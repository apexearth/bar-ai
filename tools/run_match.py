"""Run a headless AI-vs-AI match and record the result.

    python tools/run_match.py --a BARb:apex --b BARb:stable --map "Comet Catcher"
    python tools/run_match.py --a BARb:apex:hard_aggressive --b BARb:stable:hard \
        --map "Red Comet Remake 1.8" --minutes 30 --seed 7

AI spec format:  ShortName[:Version[:profile]]      e.g. BARb:apex:hard_aggressive
LuaAI spec:      lua:Name                           e.g. lua:SimpleAI

Each run produces matches/<stamp>-<slug>/ containing script.txt, infolog.txt,
result.json and the replay. The engine's write dir is shared across runs
(matches/_engine) so its archive cache is built once rather than per match --
a cold scan of 250+ maps takes minutes.

Two things end a run. BAR's own `debugcommands=<frame>:quitforce` modoption is the
hard cap at --minutes of game time and needs nothing installed. The optional
dev_autoquit gadget ends it earlier, at actual game over, and prints the winner:

    python tools/deploy_ai.py gadgets

Without the gadget every match reports reason=timelimit and no winner.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import bar_env
from bar_env import REPO

MATCHES = REPO / "matches"
ENGINE_WRITE_DIR = MATCHES / "_engine"

# Faction names as they appear in BAR's sidedata.
SIDES = ["Armada", "Cortex"]
COLORS = ["0.15 0.45 0.90", "0.90 0.20 0.10", "0.20 0.80 0.30", "0.90 0.75 0.15"]


@dataclass
class AISpec:
    short_name: str
    version: str = "stable"
    profile: str | None = None
    is_lua: bool = False

    @classmethod
    def parse(cls, text: str) -> "AISpec":
        parts = text.split(":")
        if parts[0].lower() == "lua":
            if len(parts) < 2:
                raise SystemExit(f"lua AI spec needs a name: {text!r}")
            return cls(short_name=parts[1], is_lua=True)
        return cls(
            short_name=parts[0],
            version=parts[1] if len(parts) > 1 and parts[1] else "stable",
            profile=parts[2] if len(parts) > 2 and parts[2] else None,
        )

    def label(self) -> str:
        if self.is_lua:
            return f"lua-{self.short_name}"
        bits = [self.short_name, self.version]
        if self.profile:
            bits.append(self.profile)
        return "-".join(bits)


@dataclass
class MatchResult:
    winners: list[int] = field(default_factory=list)
    reason: str = "unknown"
    game_frames: int = 0
    wall_seconds: float = 0.0
    exit_code: int | None = None
    desync: bool = False
    ai_errors: list[str] = field(default_factory=list)

    @property
    def game_minutes(self) -> float:
        return round(self.game_frames / (30 * 60), 2)


def _script_section(name: str, body: dict, indent: int = 1) -> str:
    pad = "\t" * indent
    lines = [f"{pad}[{name}]", pad + "{"]
    for k, v in body.items():
        if isinstance(v, dict):
            lines.append(_script_section(k, v, indent + 1))
        else:
            lines.append(f"{pad}\t{k}={v};")
    lines.append(pad + "}")
    return "\n".join(lines)


def _ai_and_team(ai: AISpec, team_id: int, ally: int, side: str) -> str:
    """One [AI]/[TEAM] pair (or a LuaAI [TEAM]) for the given ally team."""
    team = {
        "TeamLeader": 0,
        "AllyTeam": ally,
        "RGBColor": COLORS[ally % len(COLORS)],
        "Side": side,
        "Handicap": 0,
    }
    if ai.is_lua:
        # LuaAI is selected on the TEAM, not via an [AI] section.
        team["LuaAI"] = ai.short_name
        return _script_section(f"TEAM{team_id}", team)

    ai_body: dict = {
        "Name": f"{ai.label()}_{team_id}",
        "ShortName": ai.short_name,
        "Version": ai.version,
        "Team": team_id,
        "Host": 0,  # player number that runs this AI
    }
    if ai.profile:
        ai_body["OPTIONS"] = {"profile": ai.profile}
    return "\n".join([
        _script_section(f"AI{team_id}", ai_body),
        _script_section(f"TEAM{team_id}", team),
    ])


def build_script(
    ais: list[AISpec],
    map_name: str,
    game_name: str,
    minutes: int,
    seed: int | None,
    host_name: str = "BenchHost",
    record_demo: bool = False,
    speed: int = 9999,
    per_side: int = 1,
    sides: list[str] | None = None,
    extra_modoptions: dict[str, str] | None = None,
) -> str:
    """Emit a Spring start script for N AIs, each alone on its own ally team.

    Format reference: RecoilEngine/doc/StartScriptFormat.txt
    """
    # Field names and shape follow BAR's own harness script,
    # BAR.sdd/tools/headless_testing/startscript.txt.
    body: list[str] = []
    body.append(f"\tMapName={map_name};")
    body.append(f"\tGameType={game_name};")
    # 0 = fixed: engine hands out the map's own start positions in team order,
    # which keeps repeated runs on the same map comparable.
    body.append("\tStartPosType=0;")
    body.append("\tGameStartDelay=0;")
    body.append("\tIsHost=1;")
    body.append("\tHostIP=127.0.0.1;")
    body.append("\tHostPort=0;")
    body.append("\tNumPlayers=1;")
    body.append("\tNumUsers=1;")
    body.append("\tNoHelperAIs=0;")
    body.append(f"\tMyPlayerName={host_name};")
    body.append(f"\tRecordDemo={1 if record_demo else 0};")
    if seed is not None:
        # BAR/Recoil spells this FixedRNGSeed, not RandomSeed.
        body.append(f"\tFixedRNGSeed={seed};")

    # One non-playing human slot: the engine needs a host player, and every AI
    # has to name a player that hosts it.
    body.append(_script_section("PLAYER0", {"Name": host_name, "Spectator": 1}))

    # Each entry in `ais` is one SIDE. per_side copies of it share an ally team,
    # so --a X --b Y --per-side 4 is a 4v4 of X against Y.
    # Faction per ally team. Default alternates Armada/Cortex, but for A/B
    # testing both sides should normally be the SAME faction: otherwise the
    # faction matchup is confounded with the variant under test, and any
    # faction-specific unit (Cortex Dragons, Armada Liche) only appears in
    # half the games.
    side_for = list(sides) if sides else [SIDES[i % len(SIDES)] for i in range(len(ais))]
    while len(side_for) < len(ais):
        side_for.append(side_for[-1])

    team_id = 0
    for ally, ai in enumerate(ais):
        for _ in range(per_side):
            body.append(_ai_and_team(ai, team_id, ally, side_for[ally]))
            team_id += 1
        body.append(_script_section(f"ALLYTEAM{ally}", {"NumAllies": 0}))

    cap_frames = minutes * 60 * 30  # 30 sim frames per second

    modoptions = {
        # Speed. The non-obvious part: GameServer::UserSpeedChange clamps the
        # starting speed into [MinSpeed, MaxSpeed], so raising MaxSpeed alone does
        # nothing -- MinSpeed is what actually pushes the sim above 1x. The
        # adaptive throttle then runs as fast as the CPU allows up to MaxSpeed.
        "MinSpeed": speed,
        "MaxSpeed": speed,
        # BAR's own dev hook (see modoptions.lua "debugcommands", implemented by
        # luarules/gadgets/cmd_dev_helpers.lua): "<frame>:<command>|<frame>:<command>".
        # This is the guaranteed cap and needs nothing installed into the game.
        "debugcommands": f"{cap_frames}:quitforce",
        # Read by game-patches/gadgets/dev_autoquit.lua if it is installed, which
        # ends the run at game over instead of at the cap and prints the winner.
        # Harmless when the gadget is absent.
        "dev_autoquit": 1,
        "dev_maxgameminutes": minutes,
    }
    modoptions.update(extra_modoptions or {})
    body.append(_script_section("MODOPTIONS", modoptions))

    return "[GAME]\n{\n" + "\n".join(body) + "\n}\n"


RESULT_RE = re.compile(r"\[BARAI_RESULT\]\s+reason=(\w+)\s+frame=(\d+)\s+winners=([\d,]*)")
FRAME_RE = re.compile(r"\[f=(\d+)\]")


def parse_infolog(text: str, result: MatchResult) -> MatchResult:
    m = RESULT_RE.search(text)
    if m:
        result.reason = m.group(1)
        result.game_frames = int(m.group(2))
        result.winners = [int(x) for x in m.group(3).split(",") if x.strip()]
    else:
        frames = FRAME_RE.findall(text)
        if frames:
            result.game_frames = int(frames[-1])

    if "Sync error" in text or "desync" in text.lower():
        result.desync = True
    for line in text.splitlines():
        if "SkirmishAI" in line and ("error" in line.lower() or "exception" in line.lower()):
            result.ai_errors.append(line.strip()[:300])
    return result


def run(args) -> int:
    env = bar_env.load(args.engine)
    ais = [AISpec.parse(s) for s in args.ai]
    if len(ais) < 2:
        raise SystemExit("need at least two --a/--b/--ai entries")

    # Resolve names through the engine's own scanner rather than guessing.
    from unitsync import UnitSync, resolve_map

    with UnitSync(env) as us:
        map_name = resolve_map(args.map, us)
        games = us.games()
        if args.game:
            game_name = args.game
        else:
            sdd = [g for g in games if g.get("archive", "").endswith(".sdd")]
            if not sdd:
                raise SystemExit(
                    "no .sdd game found; pass --game with an exact name from "
                    "`python tools/unitsync.py games`"
                )
            game_name = sdd[0]["name"]

    # Both directories are overridable so run_tournament.py can drive several
    # matches at once: concurrent runs must not share a write dir (they would
    # clobber each other's infolog and race on the archive cache) and must not
    # race on an auto-generated output name.
    if args.out:
        outdir = Path(args.out)
    else:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        slug = "_vs_".join(a.label() for a in ais)[:60]
        outdir = MATCHES / f"{stamp}-{slug}"
    write_dir = Path(args.write_dir) if args.write_dir else ENGINE_WRITE_DIR

    outdir.mkdir(parents=True, exist_ok=True)
    write_dir.mkdir(parents=True, exist_ok=True)

    script = build_script(
        ais, map_name, game_name, args.minutes, args.seed,
        record_demo=args.replay, speed=args.speed, per_side=args.per_side,
        sides=[x.strip() for x in args.sides.split(',')] if args.sides else None,
    )
    script_path = outdir / "script.txt"
    script_path.write_text(script, encoding="utf-8")

    print(f"map      {map_name}")
    print(f"game     {game_name}")
    print(f"engine   {env.engine_version}")
    for i, a in enumerate(ais):
        print(f"team {i}   {a.label()}")
    print(f"out      {outdir}")

    if args.dry_run:
        print("\n--- script.txt ---")
        print(script)
        return 0

    exe = env.spring if args.windowed else env.headless
    # BAR's tools/headless_testing/start.sh removes this before every run:
    # stale widget config silently enables/disables widgets between runs.
    shutil.rmtree(write_dir / "LuaUI" / "Config", ignore_errors=True)

    cmd = [str(exe), "--write-dir", str(write_dir)]
    cfg = REPO / "tools" / "headless.cfg"
    if cfg.exists():
        cmd += ["--config", str(cfg)]
    cmd.append(str(script_path))

    # SPRING_DATADIR keeps maps/games/pool discoverable while the engine writes
    # its logs, cache and demos into our own directory instead of the user's.
    proc_env = {
        **_os_environ(),
        "SPRING_DATADIR": str(env.data),
    }

    started = time.time()
    # Wall-clock cap is deliberately generous: at max sim speed a 30 game-minute
    # match usually finishes in a few minutes, but a stuck AI must not hang the
    # batch forever.
    timeout = args.timeout or max(600, args.minutes * 60)
    try:
        proc = subprocess.run(
            cmd,
            env=proc_env,
            cwd=str(env.engine_dir),
            capture_output=True,
            text=True,
            errors="replace",
            timeout=timeout,
        )
        exit_code = proc.returncode
        stdout = proc.stdout
    except subprocess.TimeoutExpired as e:
        exit_code = None
        stdout = (e.stdout or "") if isinstance(e.stdout, str) else ""
        print(f"\nWALL-CLOCK TIMEOUT after {timeout}s -- killed")

    wall = time.time() - started

    infolog_src = write_dir / "infolog.txt"
    infolog_text = ""
    if infolog_src.exists():
        infolog_text = infolog_src.read_text("utf-8", errors="replace")
        shutil.copy2(infolog_src, outdir / "infolog.txt")
    if stdout:
        (outdir / "stdout.txt").write_text(stdout, encoding="utf-8")
        if not infolog_text:
            infolog_text = stdout

    result = MatchResult(exit_code=exit_code, wall_seconds=round(wall, 1))
    parse_infolog(infolog_text, result)
    if result.reason == "unknown" and exit_code is None:
        result.reason = "walltimeout"

    demo = _latest_demo(write_dir / "demos", started)
    if demo:
        shutil.copy2(demo, outdir / demo.name)

    payload = {
        "engine": env.engine_version,
        "map": map_name,
        "game": game_name,
        "seed": args.seed,
        "minutes_cap": args.minutes,
        "teams": [
            {"team": i, "spec": a.label(), "shortName": a.short_name,
             "version": a.version, "profile": a.profile, "lua": a.is_lua}
            for i, a in enumerate(ais)
        ],
        "result": {
            "winners": result.winners,
            "winner_specs": [ais[w].label() for w in result.winners if w < len(ais)],
            "reason": result.reason,
            "game_frames": result.game_frames,
            "game_minutes": result.game_minutes,
            "wall_seconds": result.wall_seconds,
            "exit_code": result.exit_code,
            "desync": result.desync,
            "ai_errors": result.ai_errors[:10],
        },
        "replay": demo.name if demo else None,
    }
    (outdir / "result.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")

    print()
    print(f"reason   {result.reason}")
    print(f"winners  {payload['result']['winner_specs'] or '(none)'}")
    print(f"game     {result.game_minutes} min ({result.game_frames} frames)")
    print(f"wall     {result.wall_seconds}s")
    if result.desync:
        print("DESYNC detected")
    for e in result.ai_errors[:3]:
        print(f"ai error {e}")
    return 0


def _os_environ() -> dict:
    import os

    return dict(os.environ)


def _latest_demo(demos: Path, since: float) -> Path | None:
    if not demos.is_dir():
        return None
    files = [p for p in demos.rglob("*.sdfz") if p.stat().st_mtime >= since - 5]
    return max(files, key=lambda p: p.stat().st_mtime) if files else None


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--a", dest="ai", action="append", default=[],
                    help="AI spec, repeatable (alias of --ai)")
    ap.add_argument("--b", dest="ai", action="append",
                    help="second AI spec (same list as --a)")
    ap.add_argument("--ai", dest="ai", action="append", help=argparse.SUPPRESS)
    ap.add_argument("--map", required=True, help="display name, filename or substring")
    ap.add_argument("--game", help="exact game name (default: the .sdd checkout)")
    ap.add_argument("--engine", help="engine version dir (default: launcher's active)")
    ap.add_argument("--minutes", type=int, default=30, help="in-game minute cap")
    ap.add_argument("--timeout", type=int, help="wall-clock seconds before kill")
    ap.add_argument("--seed", type=int, help="RandomSeed for reproducibility")
    ap.add_argument("--sides",
                    help="comma-separated faction per side, e.g. 'Cortex,Cortex'. "
                         "Default alternates Armada/Cortex; same-faction is preferred "
                         "for A/B tests")
    ap.add_argument("--per-side", dest="per_side", type=int, default=1,
                    help="AIs per side; --per-side 4 with two specs is a 4v4")
    ap.add_argument("--speed", type=int, default=9999,
                    help="sim speed cap; MinSpeed is what actually raises it (default 9999)")
    ap.add_argument("--replay", action="store_true",
                    help="record a .sdfz replay (off by default: large and slows batches)")
    ap.add_argument("--windowed", action="store_true",
                    help="use spring.exe instead of spring-headless.exe to watch it")
    ap.add_argument("--out", help="output directory (default: matches/<stamp>-<slug>)")
    ap.add_argument("--write-dir", dest="write_dir",
                    help="engine write dir; give concurrent runs separate ones "
                         "(default: matches/_engine)")
    ap.add_argument("--dry-run", action="store_true", help="print the script and stop")
    return run(ap.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
