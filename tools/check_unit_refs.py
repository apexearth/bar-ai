#!/usr/bin/env python3
"""Find unit-def names referenced in AngelScript that BAR does not ship.

check.py already does this for the JSON configs. It does not read `script/**.as`,
and that is where the expensive mistakes have been: asking for a unit no def
exists for is a silent no-op -- no error, no log line, the request is simply
dropped. This session referenced `armfmkr` as the T1 energy converter: a REAL
def, so no name check would object, but built only by commanders and ship/hover
constructors. The ground constructors doing the asking carry `armmakr` instead,
so 95 build requests produced nothing while a player wasted 1.34M energy.

Reports, per reference:

  MISSING     nothing named that ships with BAR -- a typo or an invented name.
  UNREACHABLE a real unit, but nothing this AI can field builds it, even
              transitively. Asking for it is equally a no-op, and this is the
              class that looks correct in every check until you watch a game.

Usage:
    python tools/check_unit_refs.py                 # all variants
    python tools/check_unit_refs.py apex            # one variant
    python tools/check_unit_refs.py --builders      # also do the buildoptions pass
    python tools/check_unit_refs.py --json          # machine-readable
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bar_env  # noqa: E402
from check import UNITISH, NOT_UNITS, is_unit, load_units, strip_jsonc  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
AI_DIR = REPO / "ai"

# A string literal in AngelScript. Unit names reach the engine only as strings --
# ai.GetCircuitDef("armmakr") or the `string armmakr("armmakr")` globals the
# scripts use because GetCircuitDef takes a const string& in.
# Spawned at game start, so "nothing builds it" is true and uninteresting.
SPAWNED = {"armcom", "corcom", "legcom"}

AS_STRING = re.compile(r'"([^"\n]{3,40})"')

# Comments, so a name discussed in prose is not reported as a live reference.
# These files are heavily commented and most mention unit names.
AS_LINE_COMMENT = re.compile(r"//.*$", re.M)
AS_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)


def rel_to_repo(path: Path) -> str:
    """Repo-relative when possible; absolute otherwise, so this stays usable on
    paths outside the checkout (a scratch file, a deployed copy under BAR.sdd)."""
    try:
        return path.relative_to(REPO).as_posix()
    except ValueError:
        return path.as_posix()


def strip_as_comments(text: str) -> str:
    return AS_LINE_COMMENT.sub("", AS_BLOCK_COMMENT.sub("", text))


def buildoptions(path: Path) -> list[str]:
    """The unit names a def can build, brace-matched.

    A regex of the form buildoptions\\s*=\\s*\\{(.*?)\\} stops at the first
    closing brace, which in these files lands inside a nested table -- it
    silently returns a truncated list. That is how `armck` was read as having no
    converter when it carries `armmakr`. Match the braces properly.
    """
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    i = text.lower().find("buildoptions")
    if i < 0:
        return []
    seg = text[i:]
    start = seg.find("{")
    if start < 0:
        return []
    depth, out = 0, []
    for ch in seg[start:]:
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                break
        out.append(ch)
    return re.findall(r'"([^"]+)"', "".join(out))


# The constructors this AI actually orders things from. The ground line only --
# these are what AiMakeTask hands build tasks to.
LAND_CONS = (
    "armck", "armcv", "armack", "armacv",
    "corck", "corcv", "corack", "coracv",
    "legck", "legcv", "legack", "legacv",
)


def builders_of(game_sdd: Path) -> dict[str, set[str]]:
    """unit -> the set of defs that list it in buildoptions."""
    out: dict[str, set[str]] = {}
    for p in (game_sdd / "units").rglob("*.lua"):
        for u in buildoptions(p):
            out.setdefault(u, set()).add(p.stem)
    return out


def producers(game_sdd: Path, cfg_root: Path) -> set[str]:
    """Everything this AI can order production from.

    Constructors AND factories AND the commander. A first version used only the
    constructors and drowned in false alarms -- a Flea is built by a lab, not by a
    con -- and a version before that unioned every def in the game, which passed
    `armfmkr` because commanders and ship constructors build it. The useful
    question is "can anything WE field make this", so the producer set is the
    ground constructors, the commanders, and whatever factories the variant's
    factory.json actually configures.
    """
    out = set(LAND_CONS) | {"armcom", "corcom", "legcom"}
    for name in ("factory.json", "factory_leg.json"):
        for cfg in cfg_root.rglob(name):
            try:
                data = json.loads(strip_jsonc(cfg.read_text(encoding="utf-8",
                                                            errors="replace")))
            except Exception:
                continue
            # Factory names live under the "factory" object, not at top level.
            fac = data.get("factory") if isinstance(data, dict) else None
            if isinstance(fac, dict):
                out.update(k for k in fac if UNITISH.match(k))
    return out


def con_buildable(game_sdd: Path, cfg_root: Path) -> set[str]:
    """Everything reachable from what we start with, transitively.

    Reachability has to be a CLOSURE, not one hop. Our ground constructors cannot
    build an advanced aircraft plant -- only air constructors can -- but our air
    plant builds an air constructor, so the plant IS reachable, just two steps
    out. A one-hop check reports that as broken and is wrong.

    Fixed point: start from the constructors, commanders and configured
    factories, then repeatedly absorb anything reachable that can itself build.
    """
    opts: dict[str, list[str]] = {}
    for p in (game_sdd / "units").rglob("*.lua"):
        o = buildoptions(p)
        if o:
            opts[p.stem] = o

    frontier = producers(game_sdd, cfg_root)
    reachable: set[str] = set()
    seen_producers: set[str] = set()
    while frontier:
        nxt: set[str] = set()
        for prod in frontier:
            if prod in seen_producers:
                continue
            seen_producers.add(prod)
            for u in opts.get(prod, ()):
                reachable.add(u)
                if u in opts and u not in seen_producers:
                    nxt.add(u)
        frontier = nxt
    return reachable


def scan_scripts(root: Path, units: set[str]) -> list[tuple[str, int, str]]:
    """Unit-ish string literals in .as files that are not unit defs."""
    found: list[tuple[str, int, str]] = []
    for path in sorted(root.rglob("*.as")):
        try:
            raw = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        code = strip_as_comments(raw)
        seen: set[str] = set()
        for name in AS_STRING.findall(code):
            if name in seen or name in NOT_UNITS:
                continue
            if not UNITISH.match(name):
                continue
            seen.add(name)
            if not is_unit(name, units):
                rel = rel_to_repo(path)
                # Report the line from the original text so it matches the file.
                line = next(
                    (i for i, ln in enumerate(raw.splitlines(), 1) if f'"{name}"' in ln),
                    0,
                )
                found.append((rel, line, name))
    return found


def scan_scripts_unbuildable(
    root: Path, units: set[str], buildable: set[str]
) -> list[tuple[str, int, str]]:
    """Real units that no constructor this AI uses can build."""
    found: list[tuple[str, int, str]] = []
    for path in sorted(root.rglob("*.as")):
        try:
            raw = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        code = strip_as_comments(raw)
        seen: set[str] = set()
        for name in AS_STRING.findall(code):
            if name in seen or name in NOT_UNITS or not UNITISH.match(name):
                continue
            seen.add(name)
            if name in SPAWNED:
                continue
            if is_unit(name, units) and name not in buildable:
                rel = rel_to_repo(path)
                line = next(
                    (i for i, ln in enumerate(raw.splitlines(), 1) if f'"{name}"' in ln),
                    0,
                )
                found.append((rel, line, name))
    return found


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("variants", nargs="*", help="variant names (default: all in ai/)")
    ap.add_argument("--builders", action="store_true",
                    help="also report real units that no def lists in buildoptions")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    units = load_units()
    if not units:
        print("no BAR checkout resolved -- cannot validate unit names", file=sys.stderr)
        return 2

    variants = args.variants or sorted(
        p.name for p in AI_DIR.iterdir() if p.is_dir()
    )

    buildable: set[str] = set()
    if args.builders:
        buildable = con_buildable(bar_env.load().game_sdd, AI_DIR)

    missing: list[tuple[str, int, str]] = []
    unbuildable: list[tuple[str, int, str]] = []
    for v in variants:
        sroot = AI_DIR / v / "game-side" / "script"
        if not sroot.is_dir():
            continue
        missing += scan_scripts(sroot, units)
        if args.builders:
            unbuildable += scan_scripts_unbuildable(sroot, units, buildable)

    if args.json:
        print(json.dumps({
            "missing": [{"file": f, "line": l, "unit": u} for f, l, u in missing],
            "unbuildable": [{"file": f, "line": l, "unit": u} for f, l, u in unbuildable],
        }, indent=2))
        return 1 if missing else 0

    if missing:
        print(f"MISSING -- no such unit def ({len(missing)}):")
        for f, l, u in missing:
            print(f"  {f}:{l}: '{u}'")
    if unbuildable:
        who = builders_of(bar_env.load().game_sdd)
        print(f"\nUNREACHABLE -- real unit, but nothing we field builds it "
              f"({len(unbuildable)}):")
        for f, l, u in unbuildable:
            b = sorted(who.get(u, ()))
            hint = (", ".join(b[:5]) + ("..." if len(b) > 5 else "")) or "nothing"
            print(f"  {f}:{l}: '{u}'")
            print(f"      built by: {hint}")
    if not missing and not unbuildable:
        print(f"ok -- every unit name in script/ resolves ({len(units)} defs known)")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
