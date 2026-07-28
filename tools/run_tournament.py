"""Run many AI-vs-AI matches and report win rates.

    python tools/run_tournament.py --a BARb:apex:hard_aggressive --b BARb:stable:hard \
        --maps "Comet Catcher,Supreme Isthmus" --games 12 --workers 4

    python tools/run_tournament.py --report              # summarise the latest run
    python tools/run_tournament.py --report <run-dir>    # or a specific one

Each pairing is played twice per map/seed with the sides swapped, because team 0
and team 1 do not get equivalent start positions on most maps -- without the
swap you are measuring the map, not the AI.

Output, one self-contained directory per run:

    tournaments/<stamp>-<slug>/
        ledger.jsonl      one JSON row per completed match
        summary.txt       the printed report
        config.json       what was run, so a result is reproducible
        matches/tNNN-.../ script.txt, infolog.txt, result.json per match

Engine scratch (write dirs, archive caches, demos) lives in runtime/ and is
disposable. tournaments/ and runtime/ are both gitignored.

Parallelism: a match holds ~4.4 GB and burns ~2-3 cores while loading but only
~0.7-1.0 core in steady-state sim. IMPORTANT: this only scales with
`ThreadPinPolicy = 0` in tools/headless.cfg -- with the engine's default pinning
every instance pins to the *same* cores and they serialise on one while the rest
of the machine idles.
"""

from __future__ import annotations

import argparse
import itertools
import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path

from bar_env import REPO

TOURNAMENTS = REPO / "tournaments"
RUNTIME = REPO / "runtime"
GB = 1024 ** 3
MATCH_RSS_GB = 4.6  # measured working set of one spring-headless match

_lock = threading.Lock()


@dataclass
class Job:
    index: int
    first: str
    second: str
    map_name: str
    seed: int


def _ram_limited_workers() -> int:
    """How many concurrent matches free RAM allows. Windows only; else no limit."""
    try:
        import ctypes

        class MemStatus(ctypes.Structure):
            _fields_ = [
                ("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
                ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
                ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
            ]

        ms = MemStatus()
        ms.dwLength = ctypes.sizeof(MemStatus)
        ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(ms))
        return max(1, int(ms.ullAvailPhys / (MATCH_RSS_GB * GB)))
    except Exception:
        return 1 << 20  # unknown: don't second-guess the user


def _safe(text: str) -> str:
    """Reduce a label to characters legal in a Windows path component.

    AI specs contain ':' and map names contain spaces -- ':' in particular is
    illegal in a Windows path.
    """
    return "".join(
        ch if (ch.isalnum() or ch in "-_.") else ("_" if ch in " :" else "")
        for ch in text
    )


def worker_dirs(n: int) -> queue.Queue:
    """One engine write dir per worker, seeded with a warm archive cache.

    A cold write dir rescans 250+ maps on first use (~35 s). Copying an existing
    cache avoids paying that per worker.
    """
    q: queue.Queue = queue.Queue()
    RUNTIME.mkdir(parents=True, exist_ok=True)

    seed_cache = None
    for cand in sorted(RUNTIME.glob("engine-w*/cache")) + [REPO / "matches" / "_engine" / "cache"]:
        if cand.is_dir():
            seed_cache = cand
            break

    for i in range(n):
        d = RUNTIME / f"engine-w{i}"
        d.mkdir(parents=True, exist_ok=True)
        if seed_cache and not (d / "cache").is_dir():
            shutil.copytree(seed_cache, d / "cache")
            print(f"  seeded {d.name} with a warm archive cache")
        q.put(d)
    return q


def play(job: Job, minutes: int, engine: str | None, write_dir: Path,
         match_root: Path, per_side: int = 1,
         sides: str | None = None) -> dict | None:
    """Run one match in its own process and read back its result.json.

    Output and write dirs are passed explicitly rather than letting run_match
    auto-name them, so concurrent jobs cannot collide.
    """
    name = _safe(f"t{job.index:03d}-{job.first}_vs_{job.second}-{job.map_name}")
    outdir = match_root / name[:150]

    cmd = [
        sys.executable, str(REPO / "tools" / "run_match.py"),
        "--a", job.first, "--b", job.second, "--map", job.map_name,
        "--minutes", str(minutes), "--seed", str(job.seed),
        "--out", str(outdir), "--write-dir", str(write_dir),
        "--per-side", str(per_side),
    ]
    if sides:
        cmd += ["--sides", sides]
    if engine:
        cmd += ["--engine", engine]

    proc = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    result_file = outdir / "result.json"
    if not result_file.exists():
        with _lock:
            print(f"[{job.index}] FAILED ({job.first} vs {job.second} on {job.map_name})")
            for line in (proc.stderr or proc.stdout or "").strip().splitlines()[-4:]:
                print(f"        {line}")
        return None
    return json.loads(result_file.read_text("utf-8"))


def summarise(rows: list[dict]) -> str:
    out: list[str] = []
    wins: dict[str, int] = defaultdict(int)
    played: dict[str, int] = defaultdict(int)
    draws = unfinished = 0
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

    decided = len(rows) - unfinished - draws
    out.append("")
    out.append(f"{len(rows)} match(es); {unfinished} did not reach game over; {draws} draw(s)")
    if durations:
        out.append(f"median game length {sorted(durations)[len(durations) // 2]:.1f} min")
    out.append("")
    out.append(f"{'AI':<38} {'played':>7} {'won':>5} {'win%':>7}")
    for spec in sorted(played, key=lambda s: -wins[s] / max(played[s], 1)):
        n, w = played[spec], wins[spec]
        out.append(f"{spec:<38} {n:>7} {w:>5} {100 * w / n if n else 0:>6.1f}%")

    if head_to_head:
        out.append("")
        out.append("head to head (decided games only)")
        for (x, y), (wx, wy) in sorted(head_to_head.items()):
            out.append(f"  {x} {wx} - {wy} {y}")

    if decided and wins:
        # Normal approximation over decided games. Printed because a 36-game
        # sample routinely spans a 30-point interval -- without it a 58% result
        # reads as a finding when it is noise.
        best = max(wins, key=lambda s: wins[s])
        p = wins[best] / decided
        se = (p * (1 - p) / decided) ** 0.5
        lo, hi = max(0.0, p - 1.96 * se), min(1.0, p + 1.96 * se)
        out.append("")
        out.append(f"{best}: {wins[best]}/{decided} decided = {100*p:.1f}% "
                   f"(95% CI {100*lo:.0f}-{100*hi:.0f}%)")
        out.append("  -> interval includes 50%: NOT distinguishable from a coin flip"
                   if lo <= 0.5 <= hi else
                   "  -> interval excludes 50%: a real difference at this sample size")

    return "\n".join(out)


def latest_run() -> Path | None:
    runs = [p for p in TOURNAMENTS.glob("*") if (p / "ledger.jsonl").exists()]
    return max(runs, key=lambda p: p.stat().st_mtime) if runs else None


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
                    help="matches per pairing per map (rounded up to even for side balance)")
    ap.add_argument("--minutes", type=int, default=60, help="in-game minute cap")
    ap.add_argument("--workers", type=int, default=1,
                    help="concurrent matches; ~1 core and ~4.4 GB each in steady state")
    ap.add_argument("--sides", default="Cortex,Cortex",
                    help="faction per side; defaults to the SAME faction on both "
                         "sides so the faction matchup is not confounded with the "
                         "variant under test")
    ap.add_argument("--per-side", dest="per_side", type=int, default=1,
                    help="AIs per side; 4 makes every match a 4v4")
    ap.add_argument("--engine", help="engine version dir")
    ap.add_argument("--name", help="label for this run's output directory")
    ap.add_argument("--report", nargs="?", const="", metavar="RUN_DIR",
                    help="summarise a finished run (default: the most recent)")
    args = ap.parse_args()

    TOURNAMENTS.mkdir(parents=True, exist_ok=True)

    if args.report is not None:
        run_dir = Path(args.report) if args.report else latest_run()
        if not run_dir:
            raise SystemExit(f"no runs found under {TOURNAMENTS}")
        ledger = run_dir / "ledger.jsonl"
        if not ledger.exists():
            raise SystemExit(f"no ledger at {ledger}")
        print(f"run: {run_dir.name}")
        print(summarise([json.loads(l) for l in ledger.read_text("utf-8").splitlines() if l.strip()]))
        return 0

    if len(args.ais) < 2:
        raise SystemExit("need at least two --a/--b entries")

    cores = os.cpu_count() or 4
    sane = max(1, min(cores, _ram_limited_workers()))
    if args.workers > sane:
        why = "RAM" if _ram_limited_workers() < cores else "cores"
        print(f"warning: {args.workers} workers exceeds what this machine sustains "
              f"({sane}, limited by {why}); matches will slow down\n")

    maps = [m.strip() for m in args.maps.split(",") if m.strip()]
    pairs = list(itertools.combinations(args.ais, 2))
    per_pair = args.games + (args.games % 2)

    jobs: list[Job] = []
    for a, b in pairs:
        for map_name in maps:
            for i in range(per_pair):
                # Swap sides on odd iterations; the seed advances once per swap
                # pair so both orders see identical starting conditions.
                first, second = (a, b) if i % 2 == 0 else (b, a)
                jobs.append(Job(len(jobs), first, second, map_name, 1000 + i // 2))

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    slug = args.name or _safe("_vs_".join(args.ais))[:60]
    run_dir = TOURNAMENTS / f"{stamp}-{slug}"
    match_root = run_dir / "matches"
    match_root.mkdir(parents=True, exist_ok=True)
    ledger = run_dir / "ledger.jsonl"

    (run_dir / "config.json").write_text(json.dumps({
        "ais": args.ais, "maps": maps, "games_per_pairing": per_pair,
        "minutes": args.minutes, "workers": args.workers, "engine": args.engine,
        "per_side": args.per_side, "sides": args.sides,
        "jobs": [asdict(j) for j in jobs],
    }, indent=2), encoding="utf-8")

    print(f"{len(pairs)} pairing(s) x {len(maps)} map(s) x {per_pair} game(s) "
          f"= {len(jobs)} matches, {args.workers} at a time")
    print(f"output: {run_dir}\n")

    pool = worker_dirs(args.workers)
    rows: list[dict] = []
    started = time.time()
    done = 0

    def run_one(job: Job):
        nonlocal done
        wd = pool.get()
        try:
            row = play(job, args.minutes, args.engine, wd, match_root, args.per_side, args.sides)
        finally:
            pool.put(wd)
        with _lock:
            done += 1
            if row is not None:
                rows.append(row)
                with ledger.open("a", encoding="utf-8") as fh:
                    fh.write(json.dumps(row) + "\n")
                res = row["result"]
                print(f"[{done}/{len(jobs)}] {job.first} vs {job.second} on {job.map_name} "
                      f"-> {res['reason']} winner={(res['winner_specs'] or ['-'])[0]} "
                      f"{res['game_minutes']}min {res['wall_seconds']}s")
        return row

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        list(ex.map(run_one, jobs))

    elapsed = time.time() - started
    report = summarise(rows)
    header = (f"{len(rows)}/{len(jobs)} matches completed in {elapsed:.0f}s "
              f"({args.workers} workers)")
    print(f"\n{header}")
    print(report)
    (run_dir / "summary.txt").write_text(header + "\n" + report + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
