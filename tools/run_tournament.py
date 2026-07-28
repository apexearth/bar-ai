"""Run many AI-vs-AI matches and report win rates.

    python tools/run_tournament.py --a BARb:apex:hard_aggressive --b BARb:stable:hard \
        --maps "Comet Catcher,Supreme Isthmus" --games 10

Each pairing is played twice per map/seed with the sides swapped, because team 0
and team 1 do not get equivalent start positions on most maps -- without the
swap you are measuring the map, not the AI.

Results append to matches/tournament.jsonl so runs accumulate; --report
re-summarises that file without playing anything.
"""

from __future__ import annotations

import argparse
import itertools
import json
import subprocess
import sys
import time
from collections import defaultdict
from pathlib import Path

import bar_env
from bar_env import REPO

LEDGER = REPO / "matches" / "tournament.jsonl"


def play(a: str, b: str, map_name: str, minutes: int, seed: int, engine: str | None) -> dict | None:
    """Run one match by shelling out to run_match.py and read back its result.json."""
    cmd = [
        sys.executable, str(REPO / "tools" / "run_match.py"),
        "--a", a, "--b", b, "--map", map_name,
        "--minutes", str(minutes), "--seed", str(seed),
    ]
    if engine:
        cmd += ["--engine", engine]

    before = _match_dirs()
    proc = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    new = _match_dirs() - before
    if not new:
        print(f"    no output dir produced; stderr tail:\n{proc.stderr[-500:]}")
        return None

    result_file = max(new, key=lambda p: p.stat().st_mtime) / "result.json"
    if not result_file.exists():
        return None
    return json.loads(result_file.read_text("utf-8"))


def _match_dirs() -> set[Path]:
    root = REPO / "matches"
    return {p for p in root.iterdir() if p.is_dir() and not p.name.startswith("_")}


def summarise(rows: list[dict]) -> None:
    wins: dict[str, int] = defaultdict(int)
    played: dict[str, int] = defaultdict(int)
    draws = 0
    unfinished = 0
    durations: list[float] = []
    head_to_head: dict[tuple[str, str], list[int]] = defaultdict(lambda: [0, 0])

    for r in rows:
        specs = [t["spec"] for t in r["teams"]]
        for s in specs:
            played[s] += 1
        res = r["result"]
        durations.append(res.get("game_minutes", 0))
        winners = res.get("winner_specs") or []
        if res.get("reason") != "gameover":
            unfinished += 1
            continue
        if len(winners) != 1:
            draws += 1
            continue
        w = winners[0]
        wins[w] += 1
        if len(specs) == 2:
            loser = specs[0] if specs[1] == w else specs[1]
            key = tuple(sorted((w, loser)))
            head_to_head[key][0 if key[0] == w else 1] += 1

    print()
    print(f"{len(rows)} match(es); {unfinished} did not reach game over; {draws} draw(s)")
    if durations:
        print(f"median game length {sorted(durations)[len(durations) // 2]:.1f} min")
    print()
    print(f"{'AI':<38} {'played':>7} {'won':>5} {'win%':>7}")
    for spec in sorted(played, key=lambda s: -wins[s] / max(played[s], 1)):
        n, w = played[spec], wins[spec]
        print(f"{spec:<38} {n:>7} {w:>5} {100 * w / n if n else 0:>6.1f}%")

    if head_to_head:
        print()
        print("head to head (decided games only)")
        for (x, y), (wx, wy) in sorted(head_to_head.items()):
            print(f"  {x} {wx} - {wy} {y}")


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--a", dest="ais", action="append", default=[],
                    help="AI spec, repeatable; every pair plays each other")
    ap.add_argument("--b", dest="ais", action="append")
    ap.add_argument("--maps", default="Comet Catcher Remake 1.8",
                    help="comma-separated map names or substrings")
    ap.add_argument("--games", type=int, default=4,
                    help="matches per pairing per map (rounded up to an even number "
                         "so sides stay balanced)")
    ap.add_argument("--minutes", type=int, default=60, help="in-game minute cap")
    ap.add_argument("--engine", help="engine version dir")
    ap.add_argument("--report", action="store_true",
                    help="summarise the existing ledger without playing")
    args = ap.parse_args()

    LEDGER.parent.mkdir(parents=True, exist_ok=True)

    if args.report:
        if not LEDGER.exists():
            raise SystemExit(f"no ledger at {LEDGER}")
        summarise([json.loads(l) for l in LEDGER.read_text("utf-8").splitlines() if l.strip()])
        return 0

    if len(args.ais) < 2:
        raise SystemExit("need at least two --a/--b entries")

    maps = [m.strip() for m in args.maps.split(",") if m.strip()]
    pairs = list(itertools.combinations(args.ais, 2))
    per_pair = args.games + (args.games % 2)  # keep side swaps balanced
    total = len(pairs) * len(maps) * per_pair

    print(f"{len(pairs)} pairing(s) x {len(maps)} map(s) x {per_pair} game(s) = {total} matches")
    print(f"ledger: {LEDGER}\n")

    rows: list[dict] = []
    started = time.time()
    n = 0
    for a, b in pairs:
        for map_name in maps:
            for i in range(per_pair):
                # Swap sides on odd iterations; seed advances every full swap pair
                # so both orders see identical starting conditions.
                first, second = (a, b) if i % 2 == 0 else (b, a)
                seed = 1000 + i // 2
                n += 1
                print(f"[{n}/{total}] {first} vs {second} on {map_name} (seed {seed})")
                row = play(first, second, map_name, args.minutes, seed, args.engine)
                if row is None:
                    print("    FAILED")
                    continue
                rows.append(row)
                with LEDGER.open("a", encoding="utf-8") as fh:
                    fh.write(json.dumps(row) + "\n")
                res = row["result"]
                print(f"    -> {res['reason']}  winner={res['winner_specs'] or '-'}  "
                      f"{res['game_minutes']}min  {res['wall_seconds']}s")

    print(f"\ntotal wall time {time.time() - started:.0f}s")
    summarise(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
