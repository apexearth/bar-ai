"""Deploy a BARb AI variant from this repo into the live BAR installation.

A variant has two halves. Both are keyed on the shortName declared in the
variant's own AIInfo.lua -- 'BARbApex', not 'BARb' -- because a variant must be a
distinct AI, not a distinct version of BARb. The lobby's ADDBOT carries no
version field, so in multiplayer a version-only variant resolves to stock BARb.

  engine-side   engine/<ver>/AI/Skirmish/<ShortName>/<variant>/
                AIInfo.lua (version = '<variant>'), AIOptions.lua, SkirmishAI.dll,
                plus a baseline config/ and script/ tree.
  game-side     BAR.sdd/luarules/configs/<ShortName>/<variant>/{config,script}
                Loaded through the engine VFS because BARb's `game_config`
                option defaults to true. Convenient for local iteration; a hosted
                game has no such folder and falls back to the engine-side copy.

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
import re
import shutil
import subprocess
import sys
from pathlib import Path

import bar_env
from bar_env import REPO, BarEnvError

AI_DIR = REPO / "ai"
PATCH_DIR = REPO / "game-patches"

# The engine's own BARb folder. Only ever a SOURCE: every deploy derives the
# variant from BARb/stable so the bundled SkirmishAI.dll matches the installed
# engine. A variant is never written under this name -- see short_name().
BASE_SHORT_NAME = "BARb"


def variants() -> list[str]:
    if not AI_DIR.is_dir():
        return []
    return sorted(p.name for p in AI_DIR.iterdir() if (p / "game-side").is_dir())


def short_name(variant: str) -> str:
    """The variant's own shortName, read from its AIInfo.lua.

    A variant must own a distinct shortName rather than be a version of 'BARb'.
    The lobby protocol's ADDBOT carries only `aiLib` and has no version field, so
    a multiplayer start script arrives with Version empty; the engine then keeps
    every key matching the shortName and picks the highest by VersionCompare,
    which is "stable". Shipping as a version loads stock BARb in every hosted
    game, silently. Keying the deploy paths off shortName is what keeps the
    engine-side folder, the game-side folder and CircuitAI's own
    GetAIDataGameDir() ("LuaRules/Configs/<shortName>/<version>/") in agreement.
    """
    info = AI_DIR / variant / "engine-side" / "AIInfo.lua"
    if info.is_file():
        m = re.search(r"key\s*=\s*'shortName'\s*,\s*\n\s*value\s*=\s*'([^']*)'",
                      info.read_text("utf-8", errors="replace"))
        if m:
            return m.group(1)
    return BASE_SHORT_NAME


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


# Anything that holds an open handle on engine/<ver>/AI/Skirmish/**/SkirmishAI.dll.
LOCKERS = ("spring.exe", "spring-headless.exe", "spring-dedicated.exe",
           "Beyond-All-Reason.exe")


def _running_lockers() -> list[str]:
    """BAR processes that will make the engine-side deploy fail halfway.

    Windows refuses to replace a loaded DLL. deploy() removes the target folder
    first and then rewrites it, so a lock does not merely abort the deploy -- it
    leaves the variant with its AIInfo.lua deleted and only the stale DLL
    behind, and every subsequent match reports
    'FetchSkirmishAILibrary: unknown skirmish AI'. That reads as the variant
    scoring zero on everything, which looks exactly like a catastrophic
    regression and is not one. Refuse up front instead.
    """
    if sys.platform != "win32":
        return []
    try:
        out = subprocess.run(["tasklist", "/fo", "csv", "/nh"],
                             capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return []   # cannot tell; do not block on a broken probe
    wanted = {n.lower() for n in LOCKERS}
    found = {line.split('","')[0].lstrip('"')
             for line in out.splitlines()
             if line.split('","')[0].lstrip('"').lower() in wanted}
    return sorted(found)


def deploy(env: bar_env.BarEnv, variant: str, allow_running: bool = False) -> None:
    src = AI_DIR / variant
    if not (src / "game-side").is_dir():
        raise SystemExit(
            f"no variant '{variant}' in {AI_DIR} (have: {', '.join(variants()) or 'none'})"
        )

    busy = _running_lockers()
    if busy and not allow_running:
        raise SystemExit(
            f"{', '.join(busy)} is running -- refusing to deploy.\n"
            f"Windows will not let the loaded SkirmishAI.dll be replaced, and this\n"
            f"deploy deletes the engine-side folder before rewriting it, so going\n"
            f"ahead would leave '{variant}' unloadable.\n"
            f"Close BAR (and any running match) and retry, or pass --allow-running\n"
            f"if you are certain nothing has the engine directory open."
        )

    stable = env.skirmish_dir(BASE_SHORT_NAME, "stable")
    if not (stable / "SkirmishAI.dll").exists():
        raise SystemExit(
            f"engine {env.engine_version} has no BARb/stable to derive from:\n  {stable}"
        )

    short = short_name(variant)
    target = env.skirmish_dir(short, variant)

    # A variant that used to ship as a version of BARb leaves BARb/<variant>
    # behind. Left in place it is a second lobby entry for the same AI that still
    # loses the empty-version resolution to stable, i.e. the exact bug this
    # rename fixes, still selectable.
    # Never fatal. Windows can hold a directory handle open well after the
    # process that owned it exits, and rmtree deletes as it walks -- so a lock
    # here once emptied the old folder and then aborted the deploy, leaving no
    # working AI at all. An emptied folder is harmless: the engine's scan does
    # FindFiles(dir, "AIInfo.lua") and skips a directory that has none, so it
    # never reaches the lobby. Getting the new folder written is what matters.
    if short != BASE_SHORT_NAME:
        for stale in (env.skirmish_dir(BASE_SHORT_NAME, variant),
                      env.game_config_dir(BASE_SHORT_NAME, variant)):
            if not stale.exists():
                continue
            try:
                shutil.rmtree(stale)
                print(f"  removed      stale {stale}")
            except OSError as e:
                print(f"  WARNING      could not remove stale {stale}: {e}")
                print(f"               harmless if it has no AIInfo.lua; delete it later")

    # 1. Engine side: fresh copy of stable (DLL + baseline config/script), then
    #    overlay this repo's AIInfo/AIOptions so the version string says <variant>.
    if target.exists():
        print(f"  engine-side  refreshing {target}")
        shutil.rmtree(target)
    _copy_tree(stable, target)

    engine_side = src / "engine-side"
    overlaid = []
    # A variant may ship its own SkirmishAI.dll (a custom C++ build). It must be
    # built against the SAME engine tag that is installed -- the AI boundary is a
    # raw struct of ~596 function pointers with no version negotiation, so a
    # mismatch fails at runtime with no diagnostic.
    # A locally built DLL wins over the repo copy. The repo carries a stripped
    # build for convenience, but it goes stale the moment the C++ is touched --
    # and a deploy silently reinstating it looked exactly like the C++ fix never
    # working.
    # This used to compare mtimes, which inverts in a fresh clone or worktree:
    # git stamps checked-out files with the checkout time, so the repo copy
    # always looks newer than any earlier build and always won -- the stale-DLL
    # trap, back again and hardest to spot on a machine set up from scratch. The
    # build output is generated from vendor/ as it stands, so prefer it whenever
    # it exists and say which one went out.
    built_dll = REPO / "vendor/engine/build-amd64-windows/AI/Skirmish/BARb/data/SkirmishAI.dll"
    for name in ("AIInfo.lua", "AIOptions.lua", "SkirmishAI.dll"):
        f = engine_side / name
        if name == "SkirmishAI.dll" and built_dll.exists():
            f = built_dll
            name += " (local build)"
        elif name == "SkirmishAI.dll":
            name += " (repo copy -- no local build in vendor/)"
        if f.exists():
            shutil.copy2(f, target / name.split(" ")[0])
            overlaid.append(name)

    for required in ("AIInfo.lua", "SkirmishAI.dll"):
        if not (target / required).exists():
            raise SystemExit(
                f"engine-side deploy incomplete: {target / required} is missing.\n"
                f"The variant will not load. Close BAR and redeploy."
            )
    _assert_version_matches(target / "AIInfo.lua", variant)

    # The variant must also run with NO game-archive support at all. In a real
    # multiplayer game every client is on the released BAR, which has no
    # LuaRules/Configs/<shortName>/<variant>/ -- CircuitAI logs "Game-side config:
    # missing!" and falls back to LocatePath("config/") over the AI data dirs,
    # which resolves here. Verified against a packaged .sdp archive: config and
    # script both load from this directory and the AngelScript runs.
    for sub in ("config", "script"):
        s_dir = src / "game-side" / sub
        if s_dir.is_dir():
            for f in s_dir.rglob("*"):
                if f.is_file():
                    q = target / sub / f.relative_to(s_dir)
                    q.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(f, q)
    print(f"  engine-side  {target}")
    print(f"               + config/ and script/ overlaid for archive-free play")
    print(f"               derived from BARb/stable, overlaid {', '.join(overlaid)}")

    # 2. Game side: the actual tuning. Replace wholesale so deletions propagate.
    game_target = env.game_config_dir(short, variant)
    if game_target.exists():
        shutil.rmtree(game_target)
    for sub in ("config", "script"):
        s = src / "game-side" / sub
        if s.is_dir():
            _copy_tree(s, game_target / sub)
    print(f"  game-side    {game_target}")
    print(f"               digest {_tree_digest(game_target)}")

    print(
        f"\nDeployed '{variant}' to engine {env.engine_version} as shortName '{short}'.\n"
        f"It should appear in the lobby AI list as the name in AIInfo.lua.\n"
        f"Harness spec: {short}:{variant}"
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
    live = env.game_config_dir(short_name(variant), variant)
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
        live_game = env.game_config_dir(short_name(v), v)
        engine_ok = (env.skirmish_dir(short_name(v), v) / "SkirmishAI.dll").exists()

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
        print(f"               shortName {short_name(v)}   spec {short_name(v)}:{v}")


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


def deploy_gadgets(env: bar_env.BarEnv, remove: bool = False) -> None:
    """Install the dev gadgets used by the match harness into BAR.sdd.

    These are additive files (not patches) and each one self-disables unless the
    start script asks for it, so leaving them installed is harmless.
    """
    src_dir = PATCH_DIR / "gadgets"
    dst_dir = env.game_sdd / "luarules" / "gadgets"
    if not dst_dir.is_dir():
        raise SystemExit(f"not a BAR checkout: {dst_dir} missing")
    for src in sorted(src_dir.glob("*.lua")):
        dst = dst_dir / src.name
        if remove:
            if dst.exists():
                dst.unlink()
                print(f"  removed {dst}")
            continue
        if dst.exists() and filecmp.cmp(src, dst, shallow=False):
            print(f"  {src.name}: up to date")
            continue
        shutil.copy2(src, dst)
        print(f"  installed {dst}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--engine", help="engine version dir name (default: launcher's active engine)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status", help="show what is deployed and whether it matches the repo")
    sub.add_parser("list", help="list variants in this repo")

    d = sub.add_parser("deploy", help="repo -> live install")
    d.add_argument("variant")
    d.add_argument("--allow-running", dest="allow_running", action="store_true",
                   help="deploy even though BAR appears to be running (it will "
                        "probably fail on the locked SkirmishAI.dll)")

    p = sub.add_parser("pull", help="live install -> repo")
    p.add_argument("variant")

    pt = sub.add_parser("patches", help="apply game-patches/*.patch to BAR.sdd")
    pt.add_argument("--revert", action="store_true")

    g = sub.add_parser("gadgets", help="install dev gadgets (autoquit) into BAR.sdd")
    g.add_argument("--remove", action="store_true")

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
        deploy(env, args.variant, args.allow_running)
    elif args.cmd == "pull":
        pull(env, args.variant)
    elif args.cmd == "patches":
        apply_patches(env, args.revert)
    elif args.cmd == "gadgets":
        deploy_gadgets(env, args.remove)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
