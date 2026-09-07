"""Two sessions, one repo, no clobbering.

Several Claude sessions work this repo at once. They share four things that are
not safe to share, and every one of them has already caused a wrong answer:

  1. **The C++ build source.** We edit `vendor/engine/AI/Skirmish/BARb/src`.
     Two sessions editing it build one DLL containing both sets of changes, and
     whichever measures first attributes the other's work to its own.
  2. **The build output.** One `build-amd64-windows` means the second build
     overwrites the first session's artifact between its build and its deploy.
  3. **The deploy target.** Both deploy variant `Unstable` to shortName `Apex`,
     so the live AI is whoever deployed last -- and `deploy_ai.py` refuses
     outright while any engine is running, which serialises the two sessions
     even when they would not have collided.
  4. **The engine write dir.** `matches/_engine` holds one live infolog.

Measured 2026-09-07: a session's `SquadTask.cpp` census survived only in the
deployed binary because the other session's tree was re-applied over it. The
numbers it printed were real and its source was gone.

A LANE is a private slot for all four. The 10 GB engine and the 1.6 GB ccache
stay shared -- they are read-only input and a concurrency-safe cache. Only the
12 MB we actually edit and the 719 MB of build output are copied, so a lane
costs about 0.7 GB and a few seconds.

    python tools/lane.py init mywork    # claim a lane in THIS checkout
    python tools/lane.py status         # what am I using?
    python tools/lane.py list           # what lanes exist
    python tools/lane.py clear          # back to the shared slot
    python tools/lane.py drop mywork    # delete a lane's directories

Once `init` has run, `build_dll.py`, `deploy_ai.py` and `run_match.py` pick the
lane up on their own -- there is no flag to remember and no environment variable
to re-export, because the harness does not persist shell state between calls.
The lane is recorded in `.barai-lane` at the repo root.

Everything a lane redirects:

    C++ source     vendor/engine/AI/Skirmish/BARb-<lane>
    build output   vendor/engine/build-<lane>
    deployed AI    ai/lane-<lane>, shortName Apex<Lane>, alongside Apex
    engine dir     matches/_engine-<lane>

Because the deployed AI has its own shortName, two lanes can hold a match and a
deploy at the same time: they write different folders in the engine install.
That is the whole point -- `deploy_ai.py`'s refusal to run while an engine is
alive exists because Windows will not replace a *loaded* DLL, and a lane's DLL
is never the one another lane has loaded.
"""

import argparse
import os
import pathlib
import shutil
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
ENGINE = REPO / "vendor" / "engine"
LANE_FILE = REPO / ".barai-lane"

SHARED_BARB = ENGINE / "AI" / "Skirmish" / "BARb"
SHARED_BUILD = ENGINE / "build-amd64-windows"
SHARED_WRITE = REPO / "matches" / "_engine"

# The variant every lane forks from, and the shortName it ships under.
BASE_VARIANT = "Unstable"
BASE_SHORT = "Apex"


def _clean(name: str) -> str:
    """A lane name that is safe in a path, a shortName and a Lua string."""
    out = "".join(c for c in name if c.isalnum())
    if not out:
        raise SystemExit(f"lane name {name!r} has no alphanumeric characters")
    return out


def name() -> str:
    """This checkout's lane, or "" for the shared slot.

    The environment wins so a one-off command can override, but the file is what
    normally answers: the Bash tool does not persist exported variables between
    calls, so an env-var-only design would silently fall back to shared on the
    very next command.
    """
    env = os.environ.get("BARAI_LANE", "").strip()
    if env:
        return _clean(env)
    if LANE_FILE.is_file():
        got = LANE_FILE.read_text("utf-8").strip()
        if got:
            return _clean(got)
    return ""


def barb_src(lane: str = None) -> pathlib.Path:
    lane = name() if lane is None else lane
    return SHARED_BARB if not lane else ENGINE / "AI" / "Skirmish" / f"BARb-{lane}"


def build_out(lane: str = None) -> pathlib.Path:
    lane = name() if lane is None else lane
    return SHARED_BUILD if not lane else ENGINE / f"build-{lane}"


def artifact(lane: str = None) -> pathlib.Path:
    return build_out(lane) / "AI" / "Skirmish" / "BARb" / "data" / "SkirmishAI.dll"


def write_dir(lane: str = None) -> pathlib.Path:
    lane = name() if lane is None else lane
    return SHARED_WRITE if not lane else REPO / "matches" / f"_engine-{lane}"


def variant(lane: str = None) -> str:
    """The variant name deploy_ai.py should ship for this lane.

    NO LEADING UNDERSCORE. The version is also a directory name under
    AI/Skirmish/<shortName>/, and the engine's scan skips `_`-prefixed
    directories: `_lane-x` deployed cleanly, passed every check this repo has,
    and then died at f=146 with "[FetchSkirmishAILibrary] unknown skirmish AI".
    """
    lane = name() if lane is None else lane
    return BASE_VARIANT if not lane else f"lane-{lane}"


def short(lane: str = None) -> str:
    lane = name() if lane is None else lane
    return BASE_SHORT if not lane else BASE_SHORT + lane


def sync_variant(lane: str = None) -> str:
    """Materialise `ai/lane-<lane>` from `ai/Unstable`, and return the variant.

    Refreshed on every deploy rather than kept: the lane is a SHIPPING slot, not
    a fork. The AI source we edit stays `ai/Unstable/` for every lane, so a lane
    never diverges from the work -- only the name it is installed under differs,
    which is what lets two of them sit side by side in the engine.
    """
    lane = name() if lane is None else lane
    if not lane:
        return BASE_VARIANT
    src = REPO / "ai" / BASE_VARIANT
    dst = REPO / "ai" / variant(lane)
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)

    # A lane MUST own a distinct shortName. Shipping as another version of an
    # existing shortName loads stock BARb in every multiplayer game, silently --
    # the engine keeps every key matching the shortName and picks the highest by
    # VersionCompare, and a lobby ADDBOT carries no version at all.
    info = dst / "engine-side" / "AIInfo.lua"
    text = info.read_text("utf-8")
    text = _set_lua_key(text, "shortName", short(lane))
    text = _set_lua_key(text, "version", variant(lane))
    info.write_text(text, "utf-8")
    return variant(lane)


def _set_lua_key(text: str, key: str, value: str) -> str:
    """Rewrite one `key = '<key>', value = '<v>'` pair in an AIInfo.lua table."""
    import re
    pat = re.compile(r"(key\s*=\s*'%s'\s*,\s*\n\s*value\s*=\s*')[^']*(')" % key)
    new, n = pat.subn(lambda m: m.group(1) + value + m.group(2), text, count=1)
    if n != 1:
        raise SystemExit(f"AIInfo.lua has no '{key}' entry to rewrite -- "
                         f"the lane cannot claim its own identity, refusing")
    return new


def _copy(src: pathlib.Path, dst: pathlib.Path, what: str) -> None:
    if dst.exists():
        print(f"  {what:<14} already there  {dst}")
        return
    if not src.exists():
        raise SystemExit(f"cannot create a lane: {src} does not exist.\n"
                         f"Build the shared tree once first "
                         f"(python tools/build_dll.py).")
    print(f"  {what:<14} copying {src.name} -> {dst.name} ...", flush=True)
    shutil.copytree(src, dst, symlinks=True)


def init(lane: str) -> int:
    lane = _clean(lane)
    print(f"lane '{lane}'")
    # The build directory's CMake cache holds CONTAINER paths (/build/src,
    # /build/out), which are the same for every lane, so a plain copy of a
    # configured build tree is already configured for the lane.
    _copy(SHARED_BARB, barb_src(lane), "C++ source")
    _copy(SHARED_BUILD, build_out(lane), "build output")
    write_dir(lane).mkdir(parents=True, exist_ok=True)
    LANE_FILE.write_text(lane + "\n", "utf-8")
    print(f"  engine dir     {write_dir(lane)}")
    print(f"  recorded in    {LANE_FILE}")
    print()
    print("This checkout is now isolated. Use the tools exactly as before:")
    print("  python tools/build_dll.py")
    print("  python tools/deploy_ai.py deploy")
    print("  python tools/run_match.py --a Apex%s:_lane-%s:standard ..." % (lane, lane))
    print()
    print("Edit C++ in:  %s" % barb_src(lane))
    print("Then mirror:  python tools/sync_cpp.py pull   (ALWAYS -- an unmirrored")
    print("              vendor edit exists in exactly one place and has been lost)")
    return 0


def status() -> int:
    lane = name()
    if not lane:
        print("lane: (none) -- SHARED slot, collides with every other session")
        print()
        print("  C++ source    %s" % SHARED_BARB)
        print("  build output  %s" % SHARED_BUILD)
        print("  deployed as   %s:%s" % (BASE_SHORT, BASE_VARIANT))
        print("  engine dir    %s" % SHARED_WRITE)
        print()
        print("Claim one with:  python tools/lane.py init <name>")
        return 0
    print(f"lane: {lane}")
    for what, p in (("C++ source", barb_src(lane)),
                    ("build output", build_out(lane)),
                    ("artifact", artifact(lane)),
                    ("engine dir", write_dir(lane))):
        print("  %-13s %s%s" % (what, p, "" if p.exists() else "   MISSING"))
    print("  %-13s %s:%s" % ("deployed as", short(lane), variant(lane)))
    return 0


def lanes() -> list:
    out = []
    if ENGINE.is_dir():
        for p in (ENGINE / "AI" / "Skirmish").glob("BARb-*"):
            out.append(p.name[len("BARb-"):])
    return sorted(out)


def drop(lane: str) -> int:
    lane = _clean(lane)
    if lane == name():
        LANE_FILE.unlink(missing_ok=True)
    for p in (barb_src(lane), build_out(lane), write_dir(lane),
              REPO / "ai" / variant(lane)):
        if p.exists():
            print(f"  removing {p}")
            shutil.rmtree(p, ignore_errors=True)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd")
    p = sub.add_parser("init", help="claim a private build/deploy/run lane")
    p.add_argument("name")
    sub.add_parser("status", help="what this checkout is using")
    sub.add_parser("list", help="lanes that exist")
    sub.add_parser("clear", help="return this checkout to the shared slot")
    p = sub.add_parser("drop", help="delete a lane's directories")
    p.add_argument("name")
    args = ap.parse_args()

    if args.cmd == "init":
        return init(args.name)
    if args.cmd == "list":
        got = lanes()
        print("\n".join(got) if got else "(no lanes)")
        return 0
    if args.cmd == "clear":
        LANE_FILE.unlink(missing_ok=True)
        print("back to the shared slot")
        return 0
    if args.cmd == "drop":
        return drop(args.name)
    return status()


if __name__ == "__main__":
    sys.exit(main())
