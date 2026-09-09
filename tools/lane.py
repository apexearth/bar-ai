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

    python tools/lane.py init mywork    # claim a lane for THIS session
    python tools/lane.py status         # what am I using?
    python tools/lane.py list           # what lanes exist
    python tools/lane.py clear          # release this session's claim
    python tools/lane.py drop mywork    # delete a lane's directories

Once `init` has run, `build_dll.py`, `deploy_ai.py` and `run_match.py` pick the
lane up on their own -- there is no flag to remember and no environment variable
to re-export, because the harness does not persist shell state between calls.
The claim is recorded PER SESSION in `.barai-lanes` at the repo root, keyed by
`CLAUDE_CODE_SESSION_ID`: a session only ever sees its own claim. The shared
slot (`Apex:Unstable`) is apexearth's -- it is what the dashboard launches and
what he plays -- so a Claude session that has claimed nothing is REFUSED by
every tool that writes, instead of landing there. `BARAI_LANE=<name>` on one
command overrides the claim; `BARAI_LANE=shared` names the shared slot on
purpose (deploying it for him to watch). A shell with no session id, his own,
is the shared slot with no claim needed.

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
LANE_FILE = REPO / ".barai-lane"      # legacy: one bare name for the whole checkout
CLAIMS_FILE = REPO / ".barai-lanes"   # "<session> <lane>" per line
SHARED_KEY = "shared"                 # BARAI_LANE=shared: the shared slot, on purpose

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


def session_id() -> str:
    """The Claude session running this command, or "" for a human shell."""
    return os.environ.get("CLAUDE_CODE_SESSION_ID", "").strip()


def is_agent() -> bool:
    return bool(session_id()) or os.environ.get("CLAUDECODE", "") == "1"


def _claims() -> dict:
    out = {}
    if CLAIMS_FILE.is_file():
        for line in CLAIMS_FILE.read_text("utf-8").splitlines():
            parts = line.split()
            if len(parts) == 2:
                out[parts[0]] = parts[1]
    return out


def _write_claims(claims: dict) -> None:
    body = "".join(f"{k} {v}\n" for k, v in sorted(claims.items()))
    CLAIMS_FILE.write_text(body, "utf-8")


def _claim_key() -> str:
    return session_id() or "shell"


def name() -> str:
    """This session's lane, or "" for the shared slot.

    The environment wins so a one-off command can override (`BARAI_LANE=shared`
    is the shared slot by name). Otherwise the answer is this session's own
    claim and nothing else: the legacy checkout-wide `.barai-lane` is ignored,
    because a session that never claimed a lane read another session's there
    and wrote into its tree (docs/25, S25).
    """
    env = os.environ.get("BARAI_LANE", "").strip()
    if env:
        return "" if env.lower() == SHARED_KEY else _clean(env)
    return _claims().get(_claim_key(), "")


def require(what: str) -> str:
    """Gate for every tool that WRITES a slot: a Claude session must have claimed
    a lane, or named one. Prints the lane it resolved so a wrong slot is visible
    on the first line of the output. Returns the lane ("" = shared)."""
    lane = name()
    if lane:
        print(f"lane: {lane}")
        return lane
    if not is_agent():
        print("lane: (shared slot)")
        return ""
    if os.environ.get("BARAI_LANE", "").strip().lower() == SHARED_KEY:
        print("lane: (shared slot, BARAI_LANE=shared)")
        return ""
    legacy = LANE_FILE.read_text("utf-8").strip() if LANE_FILE.is_file() else ""
    hint = (f"\n  (the old checkout-wide .barai-lane says '{legacy}'; if that lane is"
            f" yours, init it -- claims are per session now)") if legacy else ""
    raise SystemExit(
        f"{what}: this session has claimed no lane, and the shared slot is his.\n"
        f"  python tools/lane.py init <name>      claim (or re-claim) a lane{hint}\n"
        f"  BARAI_LANE=shared python tools/...    the shared slot, on purpose")


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
    claims = _claims()
    claims[_claim_key()] = lane
    _write_claims(claims)
    LANE_FILE.unlink(missing_ok=True)
    print(f"  engine dir     {write_dir(lane)}")
    print(f"  claimed by     {_claim_key()}  ({CLAIMS_FILE.name})")
    print()
    print("This session is now isolated. Use the tools exactly as before:")
    print("  python tools/build_dll.py")
    print("  python tools/deploy_ai.py deploy")
    print("  python tools/run_match.py --a Apex%s:lane-%s:standard ..." % (lane, lane))
    print()
    print("Edit C++ in:  %s" % barb_src(lane))
    print("Then mirror:  python tools/sync_cpp.py pull   (ALWAYS -- an unmirrored")
    print("              vendor edit exists in exactly one place and has been lost)")
    return 0


def status() -> int:
    lane = name()
    if LANE_FILE.is_file():
        print(f"note: legacy {LANE_FILE.name} ('{LANE_FILE.read_text('utf-8').strip()}') "
              "is ignored; claims are per session")
    if not lane:
        print("lane: (none) -- SHARED slot, his; writing tools refuse until a lane is claimed"
              if is_agent() else "lane: (none) -- SHARED slot")
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
    print("  %-13s %s" % ("claimed by", _claim_key()))
    return 0


def lanes() -> list:
    out = []
    if ENGINE.is_dir():
        for p in (ENGINE / "AI" / "Skirmish").glob("BARb-*"):
            out.append(p.name[len("BARb-"):])
    return sorted(out)


def drop(lane: str) -> int:
    lane = _clean(lane)
    _write_claims({k: v for k, v in _claims().items() if v != lane})
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
    sub.add_parser("status", help="what this session is using")
    sub.add_parser("list", help="lanes that exist")
    sub.add_parser("clear", help="release this session's claim")
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
        claims = _claims()
        claims.pop(_claim_key(), None)
        _write_claims(claims)
        LANE_FILE.unlink(missing_ok=True)
        print("claim released; this session is on the shared slot")
        return 0
    if args.cmd == "drop":
        return drop(args.name)
    return status()


if __name__ == "__main__":
    sys.exit(main())
