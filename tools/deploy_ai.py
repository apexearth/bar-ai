"""Deploy a BARb AI variant from this repo into the live BAR installation.

A BARb variant has two halves that must agree on the same version string:

  engine-side   engine/<ver>/AI/Skirmish/BARb/<variant>/
                AIInfo.lua (version = '<variant>'), AIOptions.lua, SkirmishAI.dll,
                plus a baseline config/ and script/ tree.
  game-side     BAR.sdd/luarules/configs/BARb/<variant>/{config,script}
                Loaded through the engine VFS because BARb's `game_config`
                option defaults to true. This is where the real tuning lives.

The engine-side half is derived from the engine's own BARb/stable folder every
time you deploy, so the SkirmishAI.dll always matches the engine you are
running. That is what makes this survive engine upgrades -- the old approach of
hand-copying a folder broke on every BAR update.

Usage
  python tools/deploy_ai.py status
  python tools/deploy_ai.py deploy apex
  python tools/deploy_ai.py deploy apex --engine recoil_2026.06.11
  python tools/deploy_ai.py pull apex          # live game-side -> this repo
  python tools/deploy_ai.py patches            # apply game-patches/*.patch
"""

from __future__ import annotations

import argparse
import filecmp
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

import bar_env
from bar_env import REPO, BarEnvError

AI_DIR = REPO / "ai"
PATCH_DIR = REPO / "game-patches"
SHORT_NAME = "BARb"


def variants() -> list[str]:
    if not AI_DIR.is_dir():
        return []
    return sorted(p.name for p in AI_DIR.iterdir() if (p / "game-side").is_dir())


def _tree_digest(root: Path) -> str:
    """Order-independent content hash of a directory tree."""
    if not root.is_dir():
        return "(absent)"
    h = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        if path.is_file():
            h.update(path.relative_to(root).as_posix().encode())
            h.update(path.read_bytes())
    return h.hexdigest()[:12]


def _copy_tree(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, dst, dirs_exist_ok=True)


def deploy(env: bar_env.BarEnv, variant: str, force: bool = False) -> None:
    src = AI_DIR / variant
    if not (src / "game-side").is_dir():
        raise SystemExit(
            f"no variant '{variant}' in {AI_DIR} (have: {', '.join(variants()) or 'none'})"
        )

    stable = env.skirmish_dir(SHORT_NAME, "stable")
    if not (stable / "SkirmishAI.dll").exists():
        raise SystemExit(
            f"engine {env.engine_version} has no BARb/stable to derive from:\n  {stable}"
        )

    target = env.skirmish_dir(SHORT_NAME, variant)

    # 1. Engine side: fresh copy of stable (DLL + baseline config/script), then
    #    overlay this repo's AIInfo/AIOptions so the version string says <variant>.
    if target.exists() and not force:
        print(f"  engine-side  refreshing {target}")
    if target.exists():
        shutil.rmtree(target)
    _copy_tree(stable, target)

    engine_side = src / "engine-side"
    overlaid = []
    for name in ("AIInfo.lua", "AIOptions.lua"):
        f = engine_side / name
        if f.exists():
            shutil.copy2(f, target / name)
            overlaid.append(name)

    _assert_version_matches(target / "AIInfo.lua", variant)
    print(f"  engine-side  {target}")
    print(f"               derived from BARb/stable, overlaid {', '.join(overlaid)}")

    # 2. Game side: the actual tuning. Replace wholesale so deletions propagate.
    game_target = env.game_config_dir(SHORT_NAME, variant)
    if game_target.exists():
        shutil.rmtree(game_target)
    for sub in ("config", "script"):
        s = src / "game-side" / sub
        if s.is_dir():
            _copy_tree(s, game_target / sub)
    print(f"  game-side    {game_target}")
    print(f"               digest {_tree_digest(game_target)}")

    print(
        f"\nDeployed '{variant}' to engine {env.engine_version}.\n"
        f"It should appear in the lobby AI list as the name in AIInfo.lua."
    )


def _assert_version_matches(ai_info: Path, variant: str) -> None:
    """AIInfo.lua's `version` value is what the engine uses to key the folder.

    A mismatch between the folder name and this value makes the AI either not
    load or silently load the wrong config, so fail loudly instead.
    """
    text = ai_info.read_text("utf-8", errors="replace")
    import re

    m = re.search(r"key\s*=\s*'version'\s*,\s*\n\s*value\s*=\s*'([^']*)'", text)
    if not m:
        print(f"  WARNING      could not parse version out of {ai_info}")
        return
    if m.group(1) != variant:
        raise SystemExit(
            f"AIInfo.lua declares version '{m.group(1)}' but the variant folder is "
            f"'{variant}'. Fix ai/{variant}/engine-side/AIInfo.lua so they match."
        )


def pull(env: bar_env.BarEnv, variant: str) -> None:
    """Copy live game-side config back into this repo.

    Use after editing configs directly inside BAR.sdd (e.g. while iterating
    in-game) so the repo stays the source of truth.
    """
    live = env.game_config_dir(SHORT_NAME, variant)
    if not live.is_dir():
        raise SystemExit(f"nothing deployed at {live}")
    dst = AI_DIR / variant / "game-side"
    before = _tree_digest(dst)
    for sub in ("config", "script"):
        s = live / sub
        if s.is_dir():
            if (dst / sub).exists():
                shutil.rmtree(dst / sub)
            _copy_tree(s, dst / sub)
    after = _tree_digest(dst)
    print(f"pulled {live}\n    -> {dst}")
    print("unchanged" if before == after else f"changed: {before} -> {after}")


def status(env: bar_env.BarEnv) -> None:
    print(env.describe())
    print()
    print(f"repo variants: {', '.join(variants()) or '(none)'}")
    print()
    for v in variants():
        repo_game = AI_DIR / v / "game-side"
        live_game = env.game_config_dir(SHORT_NAME, v)
        engine_ok = (env.skirmish_dir(SHORT_NAME, v) / "SkirmishAI.dll").exists()

        repo_d, live_d = _tree_digest(repo_game), _tree_digest(live_game)
        if not engine_ok and live_d == "(absent)":
            state = "NOT DEPLOYED"
        elif not engine_ok:
            state = "game-side only (engine-side missing -- AI will not appear)"
        elif live_d == "(absent)":
            state = "engine-side only (no game config -- falls back to engine defaults)"
        elif repo_d == live_d:
            state = "in sync"
        else:
            state = "DRIFTED (repo != live; use deploy or pull)"

        print(f"  {v:<12} {state}")
        print(f"               repo {repo_d}   live {live_d}")


def apply_patches(env: bar_env.BarEnv, revert: bool = False) -> None:
    """Apply the game-side patches that live outside the AI config folder.

    These touch shared BAR files (e.g. luarules/gadgets/ai_namer.lua), so they
    are kept as patches rather than whole-file copies -- that way an upstream
    change to the same file shows up as a conflict instead of being silently
    reverted.
    """
    patches = sorted(PATCH_DIR.glob("*.patch"))
    if not patches:
        print(f"no patches in {PATCH_DIR}")
        return
    if not (env.game_sdd / ".git").is_dir():
        raise SystemExit(f"{env.game_sdd} is not a git checkout; cannot apply patches")

    for p in patches:
        args = ["git", "apply", "--3way"]
        if revert:
            args.append("--reverse")
        args.append(str(p))
        check = subprocess.run(
            ["git", "apply", "--reverse", "--check", str(p)],
            cwd=env.game_sdd,
            capture_output=True,
        )
        if check.returncode == 0 and not revert:
            print(f"  {p.name}: already applied, skipping")
            continue
        r = subprocess.run(args, cwd=env.game_sdd, capture_output=True, text=True)
        verb = "reverted" if revert else "applied"
        if r.returncode == 0:
            print(f"  {p.name}: {verb}")
        else:
            print(f"  {p.name}: FAILED\n{r.stderr.strip()}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--engine", help="engine version dir name (default: launcher's active engine)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status", help="show what is deployed and whether it matches the repo")
    sub.add_parser("list", help="list variants in this repo")

    d = sub.add_parser("deploy", help="repo -> live install")
    d.add_argument("variant")
    d.add_argument("--force", action="store_true")

    p = sub.add_parser("pull", help="live install -> repo")
    p.add_argument("variant")

    pt = sub.add_parser("patches", help="apply game-patches/*.patch to BAR.sdd")
    pt.add_argument("--revert", action="store_true")

    args = ap.parse_args()

    try:
        env = bar_env.load(args.engine)
    except BarEnvError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    if args.cmd == "status":
        status(env)
    elif args.cmd == "list":
        print("\n".join(variants()) or "(none)")
    elif args.cmd == "deploy":
        deploy(env, args.variant, args.force)
    elif args.cmd == "pull":
        pull(env, args.variant)
    elif args.cmd == "patches":
        apply_patches(env, args.revert)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
