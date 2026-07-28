"""Coordinate search over BARb's config parameters, scored by win rate.

Sixteen hand-picked variants all landed near parity, but that is sixteen points
in a space of hundreds of numbers. This searches systematically instead: perturb
one parameter at a time from the current best, screen it, keep it if it wins.

    python tools/search_config.py --base apexdll --rounds 20 --games 40

Screening is deliberately cheap and therefore noisy. A 40-game screen has a CI
around +/-15 points, so it cannot confirm a small gain -- it is a filter, not a
verdict. Anything that survives the search must be re-run at n>=200 across
multiple maps before it is believed. See docs/07-headless-testing.md.

The parameters below are the ones with a documented meaning in the shipped
config comments, so a perturbation has an interpretable effect rather than being
a blind poke at a magic number.
"""

from __future__ import annotations

import argparse
import json
import random
import re
import shutil
import subprocess
import sys
from pathlib import Path

from bar_env import REPO

# (file, json path, kind, candidate values). Ranges bracket the shipped value.
KNOBS = [
    ("behaviour.json", ["quota", "attack"],            "num",  [8.0, 12.0, 15.0, 20.0, 26.0]),
    ("behaviour.json", ["quota", "scout"],             "int",  [2, 4, 8, 14]),
    ("behaviour.json", ["quota", "thr_mod", "attack"], "pair", [[0.35,0.55],[0.6,0.8],[1.0,1.0],[1.4,1.8]]),
    ("behaviour.json", ["quota", "num_batch"],         "int",  [3, 5, 8, 12]),
    ("behaviour.json", ["defence", "base_rad"],        "pair", [[600.,1100.],[800.,1400.],[1100.,1900.]]),
    ("economy.json",   ["economy", "buildpower"],      "num",  [0.9, 1.05, 1.2, 1.4, 1.6]),
    ("economy.json",   ["economy", "mex_up"],          "int",  [2, 3, 4, 6]),
    ("economy.json",   ["economy", "goal_exec"],       "num",  [30.0, 42.0, 55.0, 70.0]),
    ("economy.json",   ["economy", "eps_step"],        "num",  [0.1, 0.2, 0.35]),
    ("economy.json",   ["economy", "cluster_range"],   "num",  [600.0, 800.0, 1100.0, 1500.0]),
]

PROFILE = "hard_aggressive"


def cfg_path(variant: str, fname: str) -> Path:
    return REPO / "ai" / variant / "game-side" / "config" / PROFILE / fname


def read_value(variant: str, fname: str, path: list[str]):
    """Read a value out of the comment-tolerant JSON without reformatting it."""
    txt = cfg_path(variant, fname).read_text(encoding="utf-8")
    t = re.sub(r"//[^\n]*", "", txt)
    t = re.sub(r",(\s*[}\]])", r"\1", t)
    node = json.loads(t)
    for k in path:
        node = node[k]
    return node


def write_value(variant: str, fname: str, path: list[str], value) -> bool:
    """Textual surgery on the last key in `path`, preserving comments/layout.

    Scopes the search to the parent object first so a common leaf name (e.g.
    "attack", which appears in several blocks) is not replaced in the wrong one.
    """
    p = cfg_path(variant, fname)
    txt = p.read_text(encoding="utf-8")
    start, end = 0, len(txt)
    for key in path[:-1]:
        m = re.search(rf'"{re.escape(key)}"\s*:\s*\{{', txt[start:end])
        if not m:
            return False
        start = start + m.end() - 1
        depth, i = 0, start
        while i < end:
            if txt[i] == "{":
                depth += 1
            elif txt[i] == "}":
                depth -= 1
                if depth == 0:
                    end = i + 1
                    break
            i += 1
    leaf = path[-1]
    m = re.search(rf'("{re.escape(leaf)}"\s*:\s*)(\[[^\]]*\]|[-0-9.]+|true|false)', txt[start:end])
    if not m:
        return False
    rendered = json.dumps(value) if isinstance(value, list) else repr(value)
    abs_s = start + m.start(2)
    abs_e = start + m.end(2)
    p.write_text(txt[:abs_s] + rendered + txt[abs_e:], encoding="utf-8")
    return True


def make_variant(base: str, name: str) -> None:
    dst = REPO / "ai" / name
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(REPO / "ai" / base, dst)
    info = dst / "engine-side" / "AIInfo.lua"
    txt = info.read_text(encoding="utf-8")
    txt = re.sub(r"(key\s*=\s*'version',\s*\n\s*value\s*=\s*)'[^']*'", rf"\1'{name}'", txt)
    txt = re.sub(r"(key\s*=\s*'name',\s*\n\s*value\s*=\s*)'[^']*'", rf"\1'BARb {name}'", txt)
    info.write_text(txt, encoding="utf-8")


def evaluate(name: str, games: int, maps: str, minutes: int, workers: int) -> tuple[int, int]:
    subprocess.run([sys.executable, str(REPO / "tools" / "deploy_ai.py"), "deploy", name],
                   capture_output=True, text=True)
    tag = f"search-{name}"
    r = subprocess.run(
        [sys.executable, "-u", str(REPO / "tools" / "run_tournament.py"),
         "--a", f"BARb:{name}:{PROFILE}", "--b", f"BARb:stable:{PROFILE}",
         "--maps", maps, "--games", str(games), "--minutes", str(minutes),
         "--workers", str(workers), "--sides", "Cortex,Cortex", "--name", tag],
        capture_output=True, text=True)
    run_dirs = sorted((REPO / "tournaments").glob(f"*{tag}"))
    if not run_dirs:
        print(r.stdout[-400:] or r.stderr[-400:])
        return (0, 0)
    ledger = run_dirs[-1] / "ledger.jsonl"
    if not ledger.exists():
        return (0, 0)
    rows = [json.loads(l) for l in ledger.read_text("utf-8").splitlines() if l.strip()]
    dec = [r for r in rows if r["result"].get("reason") == "gameover"]
    wins = sum(1 for r in dec if name in ((r["result"].get("winner_specs") or ["-"])[0]))
    return (wins, len(dec))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default="apexdll", help="starting variant (its DLL is inherited)")
    ap.add_argument("--rounds", type=int, default=20)
    ap.add_argument("--games", type=int, default=40, help="screen size per candidate")
    ap.add_argument("--maps", default="Comet Catcher Remake 1.8,Quicksilver Remake 1.24")
    ap.add_argument("--minutes", type=int, default=45)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    random.seed(args.seed)
    best = args.base
    make_variant(args.base, "srchbest")
    best = "srchbest"

    w, n = evaluate(best, args.games, args.maps, args.minutes, args.workers)
    best_rate = w / n if n else 0.0
    print(f"baseline {best}: {w}-{n-w} = {100*best_rate:.1f}% (n={n})\n", flush=True)

    history = []
    for rnd in range(1, args.rounds + 1):
        fname, path, kind, values = random.choice(KNOBS)
        cur = read_value(best, fname, path)
        choices = [v for v in values if v != cur]
        if not choices:
            continue
        val = random.choice(choices)

        cand = "srchcand"
        make_variant(best, cand)
        if not write_value(cand, fname, path, val):
            print(f"[{rnd}] could not set {'.'.join(path)} -- skipping", flush=True)
            continue

        w, n = evaluate(cand, args.games, args.maps, args.minutes, args.workers)
        rate = w / n if n else 0.0
        keep = rate > best_rate
        print(f"[{rnd}] {'.'.join(path):<24} {cur} -> {val:<14} "
              f"{w}-{n-w} = {100*rate:>5.1f}%  {'KEEP' if keep else 'drop'}", flush=True)
        history.append({"round": rnd, "param": ".".join(path), "from": cur, "to": val,
                        "wins": w, "decided": n, "rate": rate, "kept": keep})
        if keep:
            make_variant(cand, "srchbest")
            best_rate = rate
        (REPO / "tournaments" / "search_history.json").write_text(
            json.dumps(history, indent=2), encoding="utf-8")

    print(f"\nbest screen rate {100*best_rate:.1f}% -- variant 'srchbest'")
    print("Screens are noisy at this n; re-run the winner at n>=200 before believing it.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
