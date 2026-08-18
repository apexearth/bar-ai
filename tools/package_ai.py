"""Package a variant for other players.

    python tools/package_ai.py            # packages 'apex'
    python tools/package_ai.py apex --out dist

Produces dist/<ShortName>-<variant>-<engine>-<date>-<git>.zip containing the
same self-contained engine-side folder deploy_ai.py installs locally:
BARb/stable's data files + our SkirmishAI.dll + AIInfo/AIOptions + config and
script overlaid for archive-free play (no game-archive support needed -- see
deploy_ai.py for why that works).

Who needs it: ONLY the game host. Other players in a hosted lobby need
nothing. The DLL is built against one exact engine tag (the AI boundary is a
raw struct of function pointers, no version negotiation), so the zip name
carries the engine version and the install notes say to match it.
"""
import argparse
import datetime as _dt
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bar_env
from deploy_ai import (BASE_SHORT_NAME, REPO, _assert_version_matches,
                       _copy_tree, short_name)

INSTALL = """\
{name} -- a custom AI for Beyond All Reason
Engine build: {engine}   (packaged {date}, source {git})

WHO NEEDS THIS
  Only the player HOSTING the game. Everyone else just joins the lobby.

INSTALL
  1. Find your BAR install's engine folder:
       <BAR install>\\data\\engine\\{engine}\\
     ("<BAR install>" is usually
      C:\\Users\\<you>\\AppData\\Local\\Programs\\Beyond-All-Reason)
  2. Copy the "{short}" folder from this zip into:
       <BAR install>\\data\\engine\\{engine}\\AI\\Skirmish\\
     so that this file exists:
       ...\\AI\\Skirmish\\{short}\\{variant}\\AIInfo.lua
  3. Restart BAR. In the lobby's AI list, untick "simplified AI list"
     if you do not see it; the AI appears under the name from AIInfo.lua.

IMPORTANT
  - The engine version MUST be exactly {engine}. On any other engine the AI
    fails to load with no useful error. Check yours in
    <BAR install>\\data\\engine\\ -- if it differs, ask for a matching build.
  - BAR engine updates wipe this folder. Reinstall after every update.
  - Close BAR before copying; Windows will not replace a loaded AI.
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("variant", nargs="?", default="apex")
    ap.add_argument("--out", default="dist", help="output directory (default dist/)")
    args = ap.parse_args()

    env = bar_env.load()
    variant = args.variant
    short = short_name(variant)
    src = REPO / "ai" / variant
    if not (src / "engine-side" / "AIInfo.lua").exists():
        raise SystemExit(f"no such variant: {src}")

    stable = env.skirmish_dir(BASE_SHORT_NAME, "stable")
    if not (stable / "SkirmishAI.dll").exists():
        raise SystemExit(
            f"engine {env.engine_version} has no BARb/stable to derive from:\n"
            f"  {stable}\nPackaging needs a working local install."
        )

    git = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=REPO,
                         capture_output=True, text=True).stdout.strip() or "nogit"
    dirty = subprocess.run(["git", "status", "--porcelain"], cwd=REPO,
                           capture_output=True, text=True).stdout.strip()
    if dirty:
        print("WARNING: working tree has uncommitted changes; "
              "the zip is stamped with the last commit anyway.")

    date = _dt.date.today().isoformat()
    out_dir = REPO / args.out
    out_dir.mkdir(exist_ok=True)
    zip_path = out_dir / f"{short}-{variant}-{env.engine_version}-{date}-{git}.zip"

    with tempfile.TemporaryDirectory() as tmp:
        target = Path(tmp) / short / variant
        # Same assembly deploy_ai.deploy() performs, into a staging dir:
        # stable's data files, then our AIInfo/AIOptions/DLL, then config+script
        # overlaid so the AI runs with no game-archive support at all.
        _copy_tree(stable, target)
        engine_side = src / "engine-side"
        built_dll = REPO / "vendor/engine/build-amd64-windows/AI/Skirmish/BARb/data/SkirmishAI.dll"
        for name in ("AIInfo.lua", "AIOptions.lua", "SkirmishAI.dll"):
            f = engine_side / name
            if name == "SkirmishAI.dll" and built_dll.exists():
                f = built_dll
            if f.exists():
                shutil.copy2(f, target / name)
        for required in ("AIInfo.lua", "SkirmishAI.dll"):
            if not (target / required).exists():
                raise SystemExit(f"package incomplete: {required} missing")
        _assert_version_matches(target / "AIInfo.lua", variant)
        for sub in ("config", "script"):
            s_dir = src / "game-side" / sub
            if s_dir.is_dir():
                for f in s_dir.rglob("*"):
                    if f.is_file():
                        q = target / sub / f.relative_to(s_dir)
                        q.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(f, q)

        (Path(tmp) / "INSTALL.txt").write_text(INSTALL.format(
            name=short, short=short, variant=variant,
            engine=env.engine_version, date=date, git=git), encoding="utf-8")

        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
            for f in sorted(Path(tmp).rglob("*")):
                if f.is_file():
                    z.write(f, f.relative_to(tmp))

    n_files = sum(1 for _ in zipfile.ZipFile(zip_path).namelist())
    mb = zip_path.stat().st_size / 1e6
    print(f"packaged {short}:{variant} for engine {env.engine_version}")
    print(f"  {zip_path}  ({mb:.1f} MB, {n_files} files)")
    print(f"  host-only install; engine version must match exactly.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
