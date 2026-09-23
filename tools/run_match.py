"""Run a headless AI-vs-AI match and record the result.

    python tools/run_match.py --a Apex:Unstable --b BARb:stable --map "Comet Catcher"
    python tools/run_match.py --a Apex:Unstable:standard --b BARb:stable:hard \
        --map "Red Comet Remake 1.8" --minutes 30 --seed 7

AI spec format:  ShortName[:Version[:profile]]      e.g. Apex:Unstable:standard
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
import os
import random
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
# A LANE gets its own engine write dir so two sessions do not interleave into
# one infolog.txt (tools/lane.py); without one this is matches/_engine.
import os.path as _osp
sys.path.insert(0, _osp.dirname(_osp.abspath(__file__)))
import lane as _lane
import apexlog
ENGINE_WRITE_DIR = _lane.write_dir()

# Faction names as they appear in BAR's sidedata.
SIDES = ["Armada", "Cortex"]
# --sides random draws from all three, per player.
FACTIONS = ["Armada", "Cortex", "Legion"]
# Indexed by a player's SLOT WITHIN ITS OWN ALLY TEAM (see _ai_and_team), not
# by ally or by global team_id. Previously this was `COLORS[ally % len]`, so
# every player on the same side got the IDENTICAL RGBColor -- in an 8v8 that
# is 8 apex players all rendered as the same blue, with nothing in the game
# client to tell them apart short of the player list panel. apexearth
# repeatedly identified players live by inferred color ("blue", "purple",
# "green") that the script was never actually producing; the distinctness he
# was seeing came from some other engine-side default, not this field. Eight
# entries so every player up to an 8v8 gets its own color; if per_side ever
# exceeds this it cycles, same as before.
COLOR_NAMES = ["blue", "red", "green", "yellow", "purple", "cyan", "orange", "pink"]
COLORS = [
    "0.15 0.45 0.90",  # blue
    "0.90 0.20 0.10",  # red
    "0.20 0.80 0.30",  # green
    "0.90 0.75 0.15",  # yellow
    "0.60 0.20 0.80",  # purple
    "0.15 0.80 0.85",  # cyan
    "0.95 0.55 0.10",  # orange
    "0.95 0.35 0.65",  # pink
]


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
    crashed: bool = False
    ai_errors: list[str] = field(default_factory=list)
    script_errors: list[str] = field(default_factory=list)

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


def _ai_and_team(ai: AISpec, team_id: int, ally: int, slot: int, side: str,
                 handicap: int = 0, drop_version: bool = False,
                 start_pos: tuple | None = None,
                 ai_options: dict | None = None) -> str:
    """One [AI]/[TEAM] pair (or a LuaAI [TEAM]) for the given ally team.

    `slot` is this player's index WITHIN its own ally (0, 1, 2... per side),
    which is what picks the color -- see COLORS' own comment for why that is
    not `ally` or `team_id`.
    """
    team = {
        "TeamLeader": 0,
        "AllyTeam": ally,
        "RGBColor": COLORS[slot % len(COLORS)],
        "Side": side,
        "Handicap": handicap,
    }
    if start_pos is not None:
        team["StartPosX"] = int(start_pos[0])
        team["StartPosZ"] = int(start_pos[1])
    if ai.is_lua:
        # LuaAI is selected on the TEAM, not via an [AI] section.
        team["LuaAI"] = ai.short_name
        return _script_section(f"TEAM{team_id}", team)

    ai_body: dict = {
        # Prefix the version so the two sides are tellable apart in-game and in
        # replays -- otherwise every team just reads "BARbarIAn".
        "Name": f"[{ai.version.upper()}] {ai.label()}_{team_id}",
        "ShortName": ai.short_name,
        "Version": ai.version,
        "Team": team_id,
        "Host": 0,  # player number that runs this AI
    }
    if drop_version:
        # Reproduce a hosted multiplayer game. The lobby's ADDBOT command carries
        # only `aiLib`, so the start script the host writes has no Version at all;
        # FittingSkirmishAIKeys then filters on version only when it is non-empty
        # and ResolveSkirmishAIKey takes the highest by VersionCompare. This is
        # the ONLY local way to catch a variant that resolves to stock BARb.
        del ai_body["Version"]
    opts = dict(ai_options or {})
    if ai.profile:
        opts["profile"] = ai.profile
    if opts:
        ai_body["OPTIONS"] = opts
    return "\n".join([
        _script_section(f"AI{team_id}", ai_body),
        _script_section(f"TEAM{team_id}", team),
    ])


# PER-MAP START BOXES.
#
# A map is played on a particular axis and the AI's whole territory model
# follows from it -- the front line, which ground is forward, which water is
# reachable. The harness default (lr, thin strips) silently produced a Supreme
# Isthmus played across its short axis instead of its diagonal for a whole
# session of measurements, and every map-shaped conclusion drawn from those runs
# had to be withdrawn (apexearth: "You are doing .45 trbl boxes for isthmus
# right?" -- no, and "the starting positions will be wacky").
#
# Matched by lowercased substring against the RESOLVED map name, longest key
# first, so "supreme isthmus" covers every version suffix. An explicit --boxes
# or --box-size on the command line always wins.
MAP_BOXES = {
    # key (substring)        boxes,  size
    "supreme isthmus":      ("trbl", 0.45),
    "comet catcher":        ("lr",   0.0),
    "red comet":            ("lr",   0.0),
    "glitters":             ("tb",   0.0),
    "nine_metal_islands":   ("trbl", 0.45),
    "altair":               ("lr",   0.0),
    "altored divide":       ("lr",   0.25),   # his dashboard boxes
}


def map_boxes(map_name):
    """(boxes, box_size) for a resolved map name, or (None, None)."""
    low = (map_name or "").lower()
    for key in sorted(MAP_BOXES, key=len, reverse=True):
        if key in low:
            return MAP_BOXES[key]
    return None, None


def spread_starts(rect: dict, per_side: int, boxes: str, starts, size):
    """Start positions (elmos) for one ally's `per_side` players inside `rect`.

    CircuitAI picks its own start with StartPosType=2 and every instance on a
    side picks the same best metal cluster before any has registered occupying
    it -- measured: four commanders within 100 elmos of each other on Comet
    Catcher and on Aethermoor Creek, every wall line cut to a few slots by the
    ally-lane rule. So team games hand out positions from the script: the
    map's own start positions that fall inside the box, spread along the
    box's lateral axis, and evenly interpolated points when the map has fewer
    than the side needs.
    """
    w, h = size
    if w <= 0 or h <= 0:
        return []
    l = rect.get("StartRectLeft", 0.0) * w
    r = rect.get("StartRectRight", 1.0) * w
    t = rect.get("StartRectTop", 0.0) * h
    b = rect.get("StartRectBottom", 1.0) * h
    lateral = (lambda p: p[1]) if boxes in ("lr",) else (lambda p: p[0]) if boxes == "tb" \
        else (lambda p: p[0] - p[1])
    # A map start on this box's side of the map but just outside the box is
    # clamped in, not dropped: Glacier Pass's second right start sits at
    # x=0.77, so a 0.2 box lost it and the filler put both right players in
    # the upper half while the left pair spanned the map.
    cx, cz = w / 2.0, h / 2.0
    bx, bz = (l + r) / 2.0, (t + b) / 2.0
    inset = 64.0

    def own_side(p):
        if boxes == "lr":
            return (p[0] < cx) == (bx < cx)
        if boxes == "tb":
            return (p[1] < cz) == (bz < cz)
        return l <= p[0] <= r and t <= p[1] <= b

    def clamp(p):
        return (min(max(p[0], l + inset), r - inset), min(max(p[1], t + inset), b - inset))

    # Starts already inside the box first, so a clamped one never displaces a
    # real one; a clamped start landing on a kept one is dropped.
    kept = []
    for p in sorted((p for p in starts if own_side(p)),
                    key=lambda p: (clamp(p) != (p[0], p[1]), lateral(p))):
        c = clamp(p)
        if all(((c[0] - k[0]) ** 2 + (c[1] - k[1]) ** 2) ** 0.5 > 600 for k in kept):
            kept.append(c)
    inside = sorted(kept, key=lateral)
    if len(inside) >= per_side:
        # Evenly spaced picks along the lateral order.
        idx = [round(i * (len(inside) - 1) / max(per_side - 1, 1)) for i in range(per_side)]
        return [inside[i] for i in idx]
    # Not enough: keep what the map has and fill along the lateral axis at
    # the mean axial depth of the known positions (else the box's centre).
    out = list(inside)
    if boxes == "tb":
        axial = sum(p[1] for p in inside) / len(inside) if inside else (t + b) / 2
        lo, hi = l + 0.15 * (r - l), r - 0.15 * (r - l)
        need = per_side - len(out)
        cands = [(lo + (hi - lo) * (i + 0.5) / need, axial) for i in range(need)]
    else:
        axial = sum(p[0] for p in inside) / len(inside) if inside else (l + r) / 2
        lo, hi = t + 0.15 * (b - t), b - 0.15 * (b - t)
        need = per_side - len(out)
        cands = [(axial, lo + (hi - lo) * (i + 0.5) / need) for i in range(need)]
    # Push a filler away from a map position it would land on top of.
    for c in cands:
        if all(((c[0] - p[0]) ** 2 + (c[1] - p[1]) ** 2) ** 0.5 > 600 for p in out):
            out.append(c)
        else:
            out.append((c[0], c[1] + 700 if c[1] + 700 <= b else c[1] - 700))
    return out[:per_side]


def build_script(
    ais: list[AISpec],
    map_name: str,
    game_name: str,
    minutes: int,
    seed: int | None,
    host_name: str = "BenchHost",
    record_demo: bool = False,
    speed: int = 9999,
    max_speed: int = 0,
    per_side: int = 1,
    sides: list[str] | None = None,
    boxes: str = "lr",
    box_size: float = 0.0,
    handicap: int = 0,
    extra_modoptions: dict[str, str] | None = None,
    drop_ai_version: bool = False,
    map_starts: list | None = None,
    map_size: tuple = (0, 0),
    ai_options: dict | None = None,
    extras: list | None = None,
) -> str:
    """Emit a Spring start script for N AIs, each alone on its own ally team.

    Format reference: RecoilEngine/doc/StartScriptFormat.txt
    """
    # Field names and shape follow BAR's own harness script,
    # BAR.sdd/tools/headless_testing/startscript.txt.
    body: list[str] = []
    body.append(f"\tMapName={map_name};")
    body.append(f"\tGameType={game_name};")
    # 2 = choose in game, which respects the per-ally start boxes emitted below.
    # Type 0 hands out the map's own start positions in team order, which on a
    # large map interleaves the two ally teams -- enemies spawn beside each other
    # and the match is not a real game.
    # Team games: 3 = positions from this script (see spread_starts), because
    # type 2 lets every CircuitAI on a side pick the same spot.
    spread = (per_side > 1) and bool(map_starts) and (map_size[0] > 0)
    body.append("\tStartPosType=%d;" % (3 if spread else 2))
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
    # 'random' is per PLAYER, not per side: the point of a random side is a
    # mixed team, which is what a hosted game looks like. Drawn from the run's
    # seed so the same command replays the same factions. Any entry may be
    # 'random' independently, e.g. 'Cortex,random'; a single 'random' pads to
    # every side as before.
    side_for = list(sides) if sides else [SIDES[i % len(SIDES)] for i in range(len(ais))]
    while len(side_for) < len(ais):
        side_for.append(side_for[-1])
    # No seed = a fresh draw; Random(0) here made every seedless run the same.
    rng = random.Random(seed)
    side_of = [[rng.choice(FACTIONS) for _ in range(per_side)]
               if side_for[a].lower() == "random" else [side_for[a]] * per_side
               for a in range(len(ais))]
    side_for = [s for team in side_of for s in team]   # flat, for the Legion gate below

    # Ally boxes first: a team game's start positions are drawn from them.
    rects: list[dict] = []
    for ally in range(len(ais)):
        box = {"NumAllies": 0}
        if len(ais) == 2:
            # Opposite halves with a gap between, so allies spawn together and
            # enemies do not land beside each other. Which axis matters: Glitters
            # plays top vs bottom, Comet Catcher left vs right.
            # Depth is scaled to the team size. A box 38% of the map deep gives
            # eight players a long column strung down the map instead of a line
            # across it; a shallower box spreads them into roughly two rows, which
            # is how a human team of eight actually deploys.
            depth = box_size if box_size > 0 else (0.38 if per_side <= 4 else 0.20)
            near, far = (0.0, depth) if ally == 0 else (1.0 - depth, 1.0)
            if boxes == "tb":
                box.update({"StartRectLeft": 0.0, "StartRectRight": 1.0,
                            "StartRectTop": near, "StartRectBottom": far})
            elif boxes in ("trbl", "tlbr"):
                # Diagonal corners. Both axes are constrained, so the box is a
                # square of `depth` on a side rather than a full-width band --
                # which is why box_size wants to be larger here than for lr/tb.
                if boxes == "trbl":
                    # ally 0 top-right, ally 1 bottom-left
                    l, r = (1.0 - depth, 1.0) if ally == 0 else (0.0, depth)
                    t, b = (0.0, depth) if ally == 0 else (1.0 - depth, 1.0)
                else:
                    l, r = (0.0, depth) if ally == 0 else (1.0 - depth, 1.0)
                    t, b = (0.0, depth) if ally == 0 else (1.0 - depth, 1.0)
                box.update({"StartRectLeft": l, "StartRectRight": r,
                            "StartRectTop": t, "StartRectBottom": b})
            else:
                box.update({"StartRectTop": 0.0, "StartRectBottom": 1.0,
                            "StartRectLeft": near, "StartRectRight": far})
        rects.append(box)

    team_id = 0
    for ally, ai in enumerate(ais):
        pos = spread_starts(rects[ally], per_side, boxes, map_starts or [], map_size)             if spread else []
        for slot in range(per_side):
            body.append(_ai_and_team(ai, team_id, ally, slot, side_of[ally][slot], handicap,
                                     drop_ai_version,
                                     pos[slot] if slot < len(pos) else None,
                                     ai_options if ally == 0 else None))
            team_id += 1
    # Extra teams ride on an existing ally after the real players: a NullAI
    # holder for gadget-driven units (dev_raid.lua), never a side of its own.
    for k, (spec, ally) in enumerate(extras or []):
        body.append(_ai_and_team(spec, team_id, ally, per_side + k,
                                 side_of[ally][0], 0, drop_ai_version, None))
        team_id += 1
    for ally in range(len(ais)):
        body.append(_script_section(f"ALLYTEAM{ally}", rects[ally]))

    cap_frames = minutes * 60 * 30  # 30 sim frames per second

    modoptions = {
        # Speed. The non-obvious part: GameServer::UserSpeedChange clamps the
        # starting speed into [MinSpeed, MaxSpeed], so raising MaxSpeed alone does
        # nothing -- MinSpeed is what actually pushes the sim above 1x. The
        # adaptive throttle then runs as fast as the CPU allows up to MaxSpeed.
        # MaxSpeed must stay ABOVE MinSpeed when a human is watching, or the
        # in-game +/- keys do nothing: both bounds equal pins the sim.
        "MinSpeed": speed,
        "MaxSpeed": max(speed, max_speed),
        # BAR's own dev hook (see modoptions.lua "debugcommands", implemented by
        # luarules/gadgets/cmd_dev_helpers.lua): "<frame>:<command>|<frame>:<command>".
        # This is the guaranteed cap and needs nothing installed into the game.
        "debugcommands": f"{cap_frames}:quitforce",
        # Read by game-patches/gadgets/dev_autoquit.lua if it is installed, which
        # ends the run at game over instead of at the cap and prints the winner.
        # Harmless when the gadget is absent.
        "dev_autoquit": 1,
        # Collected by game-patches/gadgets/dev_stats_export.lua: per-team
        # metal/damage/unit counters. Continuous signal beats a win/loss bit.
        "dev_stats": 1,
        # Collected by game-patches/gadgets/dev_combat_log.lua: per-unit death
        # events and army snapshots, for tools/battles.py fight reconstruction.
        "dev_combatlog": 1,
        "dev_maxgameminutes": minutes,
        # The AI's own per-section profiler (perf.as). TUNE_PERF ships at 0 so
        # live games do not pay ~250k instrumented scope closes; every measured
        # run turns it on here, which is what tools/frametime.py reads. Published
        # in game-patches/gadgets/dev_tunables.lua -- WITHOUT THAT GADGET DEPLOYED
        # this key is ignored silently and frametime.py sees no perf lines (S8).
        "apex_perf": 1,
        # THE PER-PLAYER UNIT LIMIT, AND WE HAVE TO STATE IT.
        #
        # BAR's modoptions.lua declares "maxunits" with def=2000 ("Max Units Per
        # Player"), but a modoption default only applies when the LOBBY writes
        # it; a hand-built start script that omits the key falls through to the
        # ENGINE default, which CGameSetup.cpp:632 reads as 32000
        # (`file.GetDef(maxUnitsPerTeam, "32000", "GAME\\ModOptions\\MaxUnits")`).
        # So every run here has been played at 16x the unit limit of a real game
        # -- which is what made the facqueue quota size itself off 32000 and
        # target twenty thousand raiders. Anything that divides up the unit limit
        # is measuring a different game unless this is set.
        "maxunits": 2000,
    }
    # Legion is behind a modoption that defaults to false (modoptions.lua
    # "experimentallegionfaction"). With it off no leg* unit def exists, so a
    # Side=Legion AI logs "Ignoring Legion" and then takes an access violation
    # during init, killing the whole engine process at frame 0.
    if any(s.lower() == "legion" for s in side_for):
        modoptions["experimentallegionfaction"] = 1
    modoptions.update(extra_modoptions or {})
    body.append(_script_section("MODOPTIONS", modoptions))

    return "[GAME]\n{\n" + "\n".join(body) + "\n}\n"


RESULT_RE = re.compile(r"\[BARAI_RESULT\]\s+reason=(\w+)\s+frame=(\d+)\s+winners=([\d,]*)")
FRAME_RE = re.compile(r"\[f=(\d+)\]")


STATS_RE = re.compile(r"\[BARAI_STATS\]\s+(.*)")


def parse_stats(text: str) -> list[dict] | None:
    """Every sample the dev_stats_export gadget echoed, in order.

    The gadget emits every 2 game-minutes plus at game over, so this is a time
    series per team rather than a single end-state. Knowing *when* a match went
    wrong is far more actionable than knowing that it did.
    """
    out: list[dict] = []
    for m in STATS_RE.finditer(text):
        row: dict = {}
        for tok in m.group(1).split():
            k, _, v = tok.partition("=")
            if not k:
                continue
            try:
                row[k] = float(v)
            except ValueError:
                row[k] = v
        if "team" in row:
            out.append(row)
    return out or None


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
    # An engine crash is not the same as "the AI logged an error", and reading
    # one run's log while believing it is another's is exactly how a crash gets
    # reported as a clean run. Make it a field.
    result.crashed = ("has crashed" in text) or ("problem with a skirmish AI" in text)
    if re.search(r"Skirmish AI \S+ not found!", text):
        result.crashed = True   # a load failure seats nothing in the slot
    for line in text.splitlines():
        if "SkirmishAI" in line and ("error" in line.lower() or "exception" in line.lower()):
            result.ai_errors.append(line.strip()[:300])
    # An AngelScript compile error disables the variant while the match still
    # runs to completion and reports a normal winner. The loop above cannot see
    # it: the engine writes "Skirmish AI" with a space, and the severity is
    # "ERR", so neither substring test matches. Three 40-minute runs were read as
    # results before this was noticed.
    result.script_errors = re.findall(r"[A-Za-z_]+\.as \(\d+, \d+\) : ERR.{0,160}", text)
    return result


def run(args) -> int:
    env = bar_env.load(args.engine)
    ais = [AISpec.parse(s) for s in args.ai]
    extras = []
    for text in args.extra_ai:
        spec, _, ally = text.partition('@')
        if not ally.isdigit() or int(ally) >= len(ais):
            raise SystemExit(f"--extra-ai wants SPEC@ALLY with ALLY < {len(ais)}: {text!r}")
        extras.append((AISpec.parse(spec), int(ally)))
    if len(ais) < 2:
        raise SystemExit("need at least two --a/--b/--ai entries")

    # Resolve names through the engine's own scanner rather than guessing.
    from unitsync import UnitSync, resolve_map

    with UnitSync(env) as us:
        map_name = resolve_map(args.map, us)
        # The map's own axis, unless the caller named one. argparse cannot tell
        # "user typed the default" from "user typed nothing", so the defaults
        # are sentinels (None / 0.0) and the table fills them in.
        mb, mz = map_boxes(map_name)
        if (mb is not None) and (args.boxes is None):
            args.boxes = mb
            print("boxes    %s (map default for %s)" % (mb, map_name))
            # The size is PAIRED with the axis -- 0.45 is a corner box for trbl
            # and a half-map strip for lr -- so it only rides along when the
            # map's own axis is the one being used.
            if (args.box_size <= 0.0) and (mz > 0.0):
                args.box_size = mz
                print("box-size %.2f (map default)" % mz)
        if args.boxes is None:
            args.boxes = "lr"
        mi = us.map_index(map_name)
        map_starts = us.map_starts(mi) if mi >= 0 else []
        msz = us.map_size(mi) if mi >= 0 else (0, 0)
        map_size_elmos = (msz[0] * 512, msz[1] * 512)
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
        # Relative to the repo, not the caller's cwd: a backgrounded shell
        # resolved it somewhere else entirely and the results vanished.
        outdir = Path(args.out)
        if not outdir.is_absolute():
            outdir = REPO / outdir
    else:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        slug = "_vs_".join(a.label() for a in ais)[:60]
        outdir = MATCHES / f"{stamp}-{slug}"
    write_dir = Path(args.write_dir) if args.write_dir else ENGINE_WRITE_DIR
    if not write_dir.is_absolute():
        # The engine resolves a relative --write-dir against its own exe
        # folder, not our cwd, and the infolog vanishes into the install.
        write_dir = REPO / write_dir

    outdir.mkdir(parents=True, exist_ok=True)
    write_dir.mkdir(parents=True, exist_ok=True)

    # Two engines sharing one write-dir interleave into the same infolog.txt
    # and stomp each other's config -- measured 2026-08-15: a watch game
    # launched beside a long soak run broke the watch game's AI outright and
    # corrupted the soak's log. A pidfile marks the dir busy; if its process is
    # still alive, silently side-step to a suffixed dir instead.
    pidfile = write_dir / "engine.pid"
    try:
        other = int(pidfile.read_text().strip())
    except (OSError, ValueError):
        other = 0
    if other:
        alive = subprocess.run(
            ["tasklist", "/FI", f"PID eq {other}", "/NH"],
            capture_output=True, text=True).stdout
        if str(other) in alive:
            write_dir = write_dir.parent / f"{write_dir.name}-{os.getpid()}"
            write_dir.mkdir(parents=True, exist_ok=True)
            pidfile = write_dir / "engine.pid"
            print(f"write-dir busy (engine pid {other}); using {write_dir}")
    pidfile.write_text(str(os.getpid()))

    script = build_script(
        ais, map_name, game_name, args.minutes, args.seed,
        record_demo=args.replay, speed=args.speed,
        max_speed=args.max_speed or (20 if args.watch else args.speed),
        per_side=args.per_side,
        sides=[x.strip() for x in args.sides.split(',')] if args.sides else None,
        boxes=args.boxes, box_size=args.box_size, handicap=args.handicap,
        map_starts=map_starts, map_size=map_size_elmos,
        drop_ai_version=args.drop_ai_version,
        extra_modoptions=dict(kv.split('=', 1) for kv in args.modoption),
        extras=extras,
        ai_options=dict(o.split('=', 1) for o in args.ai_option),
    )
    script_path = outdir / "script.txt"
    script_path.write_text(script, encoding="utf-8")

    print(f"map      {map_name}")
    print(f"game     {game_name}")
    print(f"engine   {env.engine_version}")
    # Faction per team, in team order, read back from the script so a random
    # draw is visible at launch and in meta.json.
    team_sides = re.findall(r"^\s*Side=(\w+);", script, re.M)[:len(ais) * args.per_side]
    for i, a in enumerate(ais):
        print(f"team {i}   {a.label()}")
    if args.per_side > 1:
        # Per-player color legend: RGBColor is now keyed by slot-within-ally
        # (see COLORS' own comment), so with per_side > 1 each teammate gets
        # its own distinct color instead of the whole side sharing one. Print
        # the mapping so a color reported while watching ("purple did X") can
        # be looked up directly instead of reverse-engineered from stats.
        tid = 0
        for i, a in enumerate(ais):
            for slot in range(args.per_side):
                name = COLOR_NAMES[slot % len(COLOR_NAMES)]
                print(f"  team {tid} ({a.label()})   {name:8s} {team_sides[tid]}")
                tid += 1
    else:
        for i in range(len(ais)):
            print(f"  team {i}   {team_sides[i]}")
    print(f"out      {outdir}")

    if args.dry_run:
        print("\n--- script.txt ---")
        print(script)
        return 0

    watching = args.watch or args.windowed
    exe = env.spring if watching else env.headless
    # BAR's tools/headless_testing/start.sh removes this before every run:
    # stale widget config silently enables/disables widgets between runs.
    # A WATCHED run keeps it. BAR's camera_remember_mode widget stores the camera
    # here and restores it only when the handler hands SetConfigData saved data;
    # with the directory gone that call never happens, savedCamState stays nil,
    # and the camera falls back to watch.cfg's CamMode on every single game.
    if not watching:
        shutil.rmtree(write_dir / "LuaUI" / "Config", ignore_errors=True)

    # THE UNIT RECORD HIS GAMES HAVE BUILT. A worker's write dir is fresh, so
    # its first game started with an empty exchange matrix and later ones with
    # whatever that worker happened to play. Every Apex AI is seeded from the
    # live record before every match (never written back), so each game of
    # each arm starts from the same evidence his own games do.
    # OPT-IN. Seeding every match from the live record cut our army spend from
    # 12.8% of metal to 1.3% on identical code, because 26.7% of that file's
    # rows are zero-dealt and the record ranks the army around its mean. See
    # ISSUES.md; --record-seed asks for it deliberately.
    live_rec = MATCHES / "_engine" / "AI" / "Skirmish" / "Apex" / "Unstable" / "apex-record.txt"
    if (live_rec.exists() and getattr(args, "record_seed", False)
            and write_dir.resolve() != (MATCHES / "_engine").resolve()):
        for a in ais:
            if a.is_lua or not a.short_name.startswith("Apex"):
                continue
            dst = write_dir / "AI" / "Skirmish" / a.short_name / a.version / "apex-record.txt"
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(live_rec, dst)
        print(f"record   seeded from {live_rec}")


    cmd = [str(exe), "--write-dir", str(write_dir)]
    # headless.cfg forces an 8x8 window, which is right for a batch and useless
    # to watch. Spring also REWRITES whatever config it is handed -- that is what
    # kept corrupting the tracked file into keys like "ersion = 8" -- so give it
    # a throwaway copy in the write dir and leave the repo's copy alone.
    cfg = REPO / "tools" / ("watch.cfg" if watching else "headless.cfg")
    if cfg.exists():
        run_cfg = write_dir / "run.cfg"
        shutil.copy2(cfg, run_cfg)
        if watching:
            print(f"window   {_fit_window_to_desktop(run_cfg)}")
        cmd += ["--config", str(run_cfg)]
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
        shutil.copy2(infolog_src, outdir / "infolog.txt")
        # The AI logs to its own files (S31); fold them back in by frame so the
        # copies read as they always did. The write dir's own infolog too, for
        # anything pointed straight at it.
        apex_files = apexlog.apex_files(infolog_src.read_text("utf-8", errors="replace"), str(write_dir))
        apexlog.merge_into(str(outdir / "infolog.txt"), apex_files)
        apexlog.merge_into(str(infolog_src), apex_files)
        infolog_text = (outdir / "infolog.txt").read_text("utf-8", errors="replace")
    if stdout:
        (outdir / "stdout.txt").write_text(stdout, encoding="utf-8")
        apexlog.merge_into(str(outdir / "stdout.txt"), apexlog.apex_files(stdout, str(write_dir)))
        if not infolog_text:
            infolog_text = (outdir / "stdout.txt").read_text("utf-8", errors="replace")

    result = MatchResult(exit_code=exit_code, wall_seconds=round(wall, 1))
    parse_infolog(infolog_text, result)
    if result.reason == "unknown" and exit_code is None:
        result.reason = "walltimeout"

    # TELEMETRY COMES FROM stdout, NOT THE SHARED INFOLOG.
    #
    # The engine write dir is shared across runs so the archive cache is built
    # once, and `infolog.txt` in it is appended by every concurrent engine. Two
    # matches running at the same time therefore interleave their [BARAI_STATS]
    # rows into each other's parsed result, and each process's own file offset
    # means rows are also silently LOST. Audited 2026-08-11: of 22 runs, six were
    # corrupted this way -- one lost 88 of its 96 rows to its concurrent partner,
    # and a foreign row is what produced a wrong "holds 5 -> 2" in a commit
    # message.
    #
    # `stdout` is this process's own pipe and cannot be crossed. It is the
    # reference; the infolog stays for the AI's own log lines and for the case
    # where stdout was not captured.
    stats = parse_stats(stdout) if stdout else None
    if stats is None:
        stats = parse_stats(infolog_text)
    elif infolog_text:
        other = parse_stats(infolog_text) or []
        if len(other) != len(stats):
            print(f"  telemetry: infolog has {len(other)} rows, stdout {len(stats)}"
                  f" -- using stdout (shared write dir was contaminated)")

    demo = _latest_demo(write_dir / "demos", started)
    if demo:
        shutil.copy2(demo, outdir / demo.name)

    payload = {
        "engine": env.engine_version,
        "map": map_name,
        "game": game_name,
        "seed": args.seed,
        # Faction per ENGINE team id (not per spec like teams[] below).
        "sides": team_sides,
        "minutes_cap": args.minutes,
        # Which income the run actually had. Behaviours are income-gated, so a
        # run is not comparable to one at a different bonus.
        "handicap": args.handicap,
        "teams": [
            {"team": i, "spec": a.label(), "shortName": a.short_name,
             "version": a.version, "profile": a.profile, "lua": a.is_lua}
            for i, a in enumerate(ais)
        ] + [
            {"team": len(ais) * args.per_side + k, "spec": spec.label(),
             "shortName": spec.short_name, "version": spec.version,
             "profile": spec.profile, "lua": spec.is_lua, "extra": True, "ally": ally}
            for k, (spec, ally) in enumerate(extras)
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
            "crashed": result.crashed,
            "ai_errors": result.ai_errors[:10],
            "script_errors": result.script_errors[:10],
            "valid": not result.script_errors,
        },
        "replay": demo.name if demo else None,
        "stats": stats,
    }
    (outdir / "result.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")

    # The audit is the acceptance test, so every game carries its verdict:
    # printed here, and persisted as audit.json so later runs can be diffed
    # against it. Never let an audit failure eat the match result.
    try:
        import audit as audit_mod
        text = audit_mod.load(outdir)
        rep = audit_mod.Report()
        for check in audit_mod.CHECKS:
            check(text, rep)
        print()
        rep.show()
        (outdir / "audit.json").write_text(
            json.dumps({"rows": [list(r) for r in rep.rows]}, indent=2),
            encoding="utf-8")
    except Exception as e:  # noqa: BLE001 -- the match result stands regardless
        print(f"audit    failed to run: {e}")

    print()
    print(f"out      {outdir}")
    print(f"reason   {result.reason}")
    print(f"winners  {payload['result']['winner_specs'] or '(none)'}")
    print(f"game     {result.game_minutes} min ({result.game_frames} frames)")
    print(f"wall     {result.wall_seconds}s")
    if result.desync:
        print("DESYNC detected")
    if result.crashed:
        print(f"*** ENGINE/AI CRASH at frame {result.game_frames} "
              f"-- see {outdir / 'infolog.txt'}")
    for e in result.ai_errors[:3]:
        print(f"ai error {e}")
    if result.script_errors:
        print()
        print("*** RUN INVALID -- AngelScript failed to compile ***")
        print("    The variant was disabled; it played as near-stock and still")
        print("    reported a winner. Do not read any number from this run.")
        for e in result.script_errors[:5]:
            print(f"    {e}")
        return 2
    return 0


def _desktop_work_area() -> tuple[int, int, int, int] | None:
    """(x, y, w, h) of the primary monitor's work area, or None if unknown.

    Work area, not full bounds, so a borderless window fills the screen without
    hiding behind the taskbar.
    """
    if sys.platform != "win32":
        return None
    try:
        import ctypes
        from ctypes import wintypes

        user32 = ctypes.windll.user32
        try:
            user32.SetProcessDPIAware()  # else a scaled display reports scaled pixels
        except Exception:
            pass
        rect = wintypes.RECT()
        SPI_GETWORKAREA = 0x0030
        if not user32.SystemParametersInfoW(SPI_GETWORKAREA, 0, ctypes.byref(rect), 0):
            return None
        return (rect.left, rect.top,
                rect.right - rect.left, rect.bottom - rect.top)
    except Exception:
        return None


def _fit_window_to_desktop(cfg_path: Path) -> str:
    """Rewrite the watch config so the window opens filling the screen.

    Recoil has no "maximized" config tag -- maximizing is an SDL call made at
    runtime (GlobalRendering::SetWindowMinMaximized), not a setting. Sizing the
    window to the work area and dropping the border is the equivalent that can be
    expressed in a config, and unlike real fullscreen it still alt-tabs.
    """
    area = _desktop_work_area()
    if area is None:
        return "left at the configured size (desktop size unknown)"
    x, y, w, h = area
    over = {
        "XResolution": str(w),
        "YResolution": str(h),
        "WindowPosX": str(x),
        "WindowPosY": str(y),
        "WindowBorderless": "1",
    }
    lines, seen = [], set()
    for line in cfg_path.read_text(encoding="utf-8").splitlines():
        key = line.split("=", 1)[0].strip()
        if key in over:
            lines.append(f"{key} = {over[key]}")
            seen.add(key)
        else:
            lines.append(line)
    lines += [f"{k} = {v}" for k, v in over.items() if k not in seen]
    cfg_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return f"{w}x{h} borderless at {x},{y}"


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
    ap.add_argument("--boxes", choices=["lr", "tb", "trbl", "tlbr"], default=None,
                    help="start-box axis. Default comes from MAP_BOXES for a known "
                         "map (Supreme Isthmus is trbl, Glitters tb, Comet Catcher "
                         "lr), else lr. Pass one to override.")
    ap.add_argument("--sides",
                    help="comma-separated faction per side, e.g. 'Cortex,Cortex' or "
                         "'random,Legion' ('random' draws per player from the seed). "
                         "Default alternates Armada/Cortex; same-faction is preferred "
                         "for A/B tests")
    ap.add_argument("--per-side", dest="per_side", type=int, default=1,
                    help="AIs per side; --per-side 4 with two specs is a 4v4")
    ap.add_argument("--speed", type=int, default=0,
                    help="sim speed cap; MinSpeed is what actually raises it "
                         "(default 9999, or 1 with --watch)")
    ap.add_argument("--replay", action="store_true",
                    help="record a .sdfz replay (off by default: large and slows batches)")
    ap.add_argument("--max-speed", dest="max_speed", type=int, default=0,
                    help="upper bound for the in-game +/- keys. Defaults to --speed, "
                         "which pins the sim; raise it to watch at --speed but keep "
                         "the ability to fast-forward")
    ap.add_argument("--windowed", action="store_true",
                    help="use spring.exe instead of spring-headless.exe")
    ap.add_argument("--watch", action="store_true",
                    help="watch it play: fills the screen borderless, replay recorded. "
                         "Implies --windowed --speed 3; +/- adjust live up to 20x")
    ap.add_argument("--out", help="output directory (default: matches/<stamp>-<slug>)")
    ap.add_argument("--write-dir", dest="write_dir",
                    help="engine write dir; give concurrent runs separate ones "
                         "(default: matches/_engine)")
    ap.add_argument("--box-size", dest="box_size", type=float, default=0.0,
                    help="start-box size as a fraction of the map, e.g. 0.35; 0 = the "
                         "map default from MAP_BOXES (Isthmus 0.45), else auto "
                         "(0.38 for <=4 per side, 0.20 above)")
    ap.add_argument("--handicap", type=int, default=None,
                    help="percent resource bonus for EVERY AI, e.g. 50. Engine key "
                         "Handicap -> SetAdvantage(pct/100) -> income multiplier, the "
                         "same number BAR's player list shows as '+50%%'. Defaults to 50 "
                         "under --watch, because a hosted multiplayer game is always "
                         "bonused and several behaviours are income-gated; 0 otherwise, "
                         "to keep benchmarks comparable with past runs.")
    ap.add_argument("--drop-ai-version", dest="drop_ai_version", action="store_true",
                    help="omit Version from every [AI] block, as a lobby-hosted "
                         "multiplayer game does; use with --game to test the AI "
                         "exactly as a hosted match will load it")
    ap.add_argument("--ai-option", action="append", default=[], metavar="K=V",
                    help="per-AI option on the FIRST ai (side A), repeatable -- the same values the lobby's add-AI dialog sets")
    ap.add_argument("--record-seed", action="store_true",
                    help="seed each match's unit record from the live game "
                         "(off by default: it collapsed army spend, see ISSUES.md)")
    ap.add_argument("--no-record-seed", action="store_true",
                    help=argparse.SUPPRESS)
    ap.add_argument("--modoption", action="append", default=[], metavar="K=V",
                    help="extra start-script modoption, repeatable. The one that "
                         "matters for reproducing a hosted game is "
                         "ai_incomemultiplier=1.5 -- benchmarks run at 1.0, and "
                         "several behaviours only misfire on a bonused economy")
    ap.add_argument("--extra-ai", dest="extra_ai", action="append", default=[],
                    metavar="SPEC@ALLY",
                    help="an extra team on an existing ally, after the real players "
                         "(e.g. NullAI:0.1@1 to hold dev_raid.lua's raiders on side b); "
                         "its team id is sides*per_side + its index")
    ap.add_argument("--dry-run", action="store_true", help="print the script and stop")
    args = ap.parse_args()
    _lane.require("run_match")  # the shared write dir holds his live infolog
    if args.speed == 0:
        args.speed = 3 if args.watch else 9999
    if args.handicap is None:
        args.handicap = 50 if args.watch else 0
    if args.watch:
        args.replay = True
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
