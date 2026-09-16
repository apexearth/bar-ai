#!/usr/bin/env python3
"""The deploy gate: no commit reaches his slot without a green expect.py run.

    python tools/gate.py run            # play the gate set on YOUR lane, then judge it
    python tools/gate.py check [sha]    # is this commit (default HEAD) cleared?
    python tools/gate.py judge <dirs>   # judge existing games for HEAD and record

apexearth 2026-09-15, after four regressions shipped in one day (builders
walking off their sites, converters not built under 10k E/s overflow, home
mexes priced as half-lost, a penned commander): "add validation for that to
our scripts so we don't make this mistake again." The validation is
expect.py -- his complaints as assertions -- and this is what makes it bind:
`deploy_ai.py deploy` to the shared slot refuses a commit with no green
record here. A lane deploy never asks.

The gate set is small enough to run after every behaviour change (three
games in parallel at full speed, ~12 min wall): two Frozen Ford 2v2 (the
map the walk-away, the converter and the pen were watched on) and one
Greenest 8v8 (what he watches), all +100%. The record is tournaments/gate/<sha>.json; a RED
records too, so `check` can say why it refused.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
# Records live in the MAIN checkout whatever worktree runs the deploy (the
# shared deploy runs from a clean worktree of the same repository).
def _main_root() -> Path:
    r = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=ROOT,
                       capture_output=True, text=True).stdout.strip()
    return (ROOT / r).resolve().parent if r else ROOT


GATE_DIR = _main_root() / "tournaments" / "gate"
GAMES = [
    # (map, per-side, minutes, seed)
    ("Frozen_Ford_V2", 2, 25, 5),
    ("Frozen_Ford_V2", 2, 25, 6),
    ("Greenest Fields 1.3.1", 8, 30, 22),
]


def head_sha() -> str:
    return subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip()


def tree_dirty() -> bool:
    out = subprocess.run(["git", "status", "--porcelain", "ai/Unstable", "cpp", "tools"],
                         cwd=ROOT, capture_output=True, text=True).stdout
    return bool(out.strip())


def record_path(sha: str) -> Path:
    return GATE_DIR / f"{sha}.json"


def lane_spec() -> str:
    sys.path.insert(0, str(HERE))
    import lane as _lane  # type: ignore
    lane = _lane.name()
    if not lane:
        sys.exit("gate: run it on your own lane (BARAI_LANE=<lane> or lane.py init), never on his slot")
    return f"Apex{lane}:lane-{lane}:standard"


def run(argv: list[str]) -> int:
    sha = head_sha()
    if tree_dirty():
        print("gate: the working tree differs from HEAD -- commit first, the record is per commit")
        return 2
    spec = lane_spec()
    stamp = time.strftime("%Y%m%d-%H%M%S")
    out_root = ROOT / "tournaments" / f"gate-{sha}-{stamp}"
    out_root.mkdir(parents=True, exist_ok=True)
    # ALL AT ONCE, AT FULL SPEED: one engine write dir per game (run_tournament's
    # pool -- never two games in one write dir), no --speed cap. Sequential at
    # 6x was 35 minutes for three games; the battery plays 18 in five.
    sys.path.insert(0, str(HERE))
    import run_tournament as _rt  # type: ignore
    pool = _rt.worker_dirs(len(GAMES))
    procs = []
    dirs = []
    for mp, per_side, minutes, seed in GAMES:
        slug = mp.split()[0].lower().replace("_", "")[:8]
        out = out_root / f"{slug}-s{seed}"
        wd = pool.get()
        cmd = [sys.executable, str(HERE / "run_match.py"), "--a", spec, "--b", "BARb:stable:hard",
               "--map", mp, "--per-side", str(per_side), "--sides", "Armada,Armada",
               "--minutes", str(minutes), "--seed", str(seed), "--handicap", "100",
               "--out", str(out), "--write-dir", str(wd)]
        print(f"gate: {mp} {per_side}v{per_side} {minutes} min seed {seed} -> {out.name}")
        procs.append(subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        dirs.append(str(out))
    for pr in procs:
        pr.wait()
    return judge(dirs, sha)


def judge(dirs: list[str], sha: str | None = None) -> int:
    sha = sha or head_sha()
    cmd = [sys.executable, str(HERE / "expect.py"), "--min-minutes", "15"] + dirs
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    print(r.stdout)
    red = [l.strip() for l in r.stdout.splitlines() if l.strip().startswith("RED")]
    GATE_DIR.mkdir(parents=True, exist_ok=True)
    record_path(sha).write_text(json.dumps({
        "sha": sha, "at": time.strftime("%Y-%m-%d %H:%M"), "green": not red,
        "red": red, "dirs": dirs}, indent=1), encoding="utf-8")
    print(f"gate: {sha} {'GREEN' if not red else 'RED (' + str(len(red)) + ')'} -> {record_path(sha)}")
    return 0 if not red else 1


def check(sha: str | None = None, quiet: bool = False) -> bool:
    sha = sha or head_sha()
    p = record_path(sha)
    if not p.is_file():
        if not quiet:
            print(f"gate: no record for {sha} -- run `python tools/gate.py run` on your lane first")
        return False
    rec = json.loads(p.read_text(encoding="utf-8"))
    if not rec.get("green"):
        if not quiet:
            print(f"gate: {sha} is RED ({rec['at']}):")
            for l in rec.get("red", []):
                print("   " + l)
        return False
    if not quiet:
        print(f"gate: {sha} GREEN ({rec['at']})")
    return True


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in ("run", "check", "judge"):
        print(__doc__)
        return 2
    if sys.argv[1] == "run":
        return run(sys.argv[2:])
    if sys.argv[1] == "check":
        return 0 if check(sys.argv[2] if len(sys.argv) > 2 else None) else 1
    return judge(sys.argv[2:])


if __name__ == "__main__":
    raise SystemExit(main())
