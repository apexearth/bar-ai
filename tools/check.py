"""Preflight a BARb variant without running a match.

    python tools/check.py                 # every variant in ai/
    python tools/check.py apex            # one variant
    python tools/check.py --baseline      # also check reference/barb-stable

Every check here exists because the failure it catches is SILENT: the match
still runs, reports a plausible result, and says nothing. See the "Failure modes
that are SILENT" section of CLAUDE.md -- each of those cost hours before it was
understood, and each is mechanically detectable in under a second.

  json          a config jsoncpp cannot parse is dropped and the AI runs on
                defaults. Nothing is logged.
  units         asking for a unit that is not a unit def is a no-op. `armfmd`
                (Armada's anti-nuke is armamd) has been in build_chain forever.
  condition     SBuildInfo::condition is ONE enum. The parser takes
                getMemberNames().front() and jsoncpp sorts keys, so
                {"m_inc>": 10, "chance": 0.5} silently becomes chance-only.
  version       AIInfo.lua's version value must equal the variant folder name or
                the engine loads the wrong config, or nothing.
  profiles      a profile with files on disk but no entry in AIOptions.lua is
                unreachable from the lobby.
  parity        work done for Armada/Cortex gets forgotten for Legion. A missing
                _leg twin means the change does not exist on Legion.

Exit status is 1 if anything at ERROR level failed, so this is usable as a
pre-deploy gate.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import bar_env
from bar_env import REPO, BarEnvError

AI_DIR = REPO / "ai"

# Anything shaped like a BAR unit def name. Faction prefixes only, so role and
# category words ("defence", "front", "static") are never mistaken for units.
UNITISH = re.compile(r"^(arm|cor|leg)[a-z0-9_]{2,}$")

# Match the pattern but are not unit defs and are not meant to be: these are the
# faction names, used as keys in build_chain/commander/economy.
NOT_UNITS = {"armada", "cortex", "legion"}


def strip_jsonc(text: str) -> str:
    """Reduce jsoncpp-flavoured JSON to strict JSON.

    jsoncpp accepts // and /* */ comments and (in the mode BARb uses) trailing
    commas. Stripping has to respect string literals or a URL or a Windows path
    inside a value eats the rest of the line.
    """
    out: list[str] = []
    i, n, in_str = 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        out.append(c)
        i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def line_of(text: str, needle: str) -> int:
    """1-based line number of the first occurrence of `needle`, or 0."""
    idx = text.find(needle)
    return text.count("\n", 0, idx) + 1 if idx >= 0 else 0


class Report:
    """Three levels: things we broke, things worth a look, and things upstream
    shipped broken that we merely inherited."""

    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.notes: list[str] = []

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def note(self, msg: str) -> None:
        self.notes.append(msg)

    def dump(self, title: str, show_notes: bool = False) -> None:
        print(f"\n{title}")
        for m in self.errors:
            print(f"  ERROR   {m}")
        for m in self.warnings:
            print(f"  warn    {m}")
        if show_notes:
            for m in self.notes:
                print(f"  (stock) {m}")
        if not self.errors and not self.warnings:
            print("  ok" + (f"  ({len(self.notes)} inherited from stock BARb, "
                            f"--all to list)" if self.notes and not show_notes else ""))
        elif self.notes and not show_notes:
            print(f"  ({len(self.notes)} more inherited from stock BARb, --all to list)")


def walk_strings(node, path: str = ""):
    """Yield (json-path, string) for every key and string value in the tree."""
    if isinstance(node, dict):
        for k, v in node.items():
            yield f"{path}.{k}" if path else k, k
            yield from walk_strings(v, f"{path}.{k}" if path else k)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from walk_strings(v, f"{path}[{i}]")
    elif isinstance(node, str):
        yield path, node


def check_conditions(node, rel: str, rep: Report, path: str = "") -> None:
    """A `condition` object with more than one key silently keeps only one.

    SBuildInfo::Condition is a single enum; BuildChain.cpp reads
    getMemberNames().front() and jsoncpp sorts keys alphabetically. So
    {"m_inc>": 10, "chance": 0.5} is chance-only, and the income gate you wrote
    has no effect at all.
    """
    if isinstance(node, dict):
        for k, v in node.items():
            here = f"{path}.{k}" if path else k
            if k == "condition" and isinstance(v, dict) and len(v) > 1:
                keys = sorted(v)
                rep.error(
                    f"{rel}: {here} has {len(v)} keys {keys} -- conditions cannot be "
                    f"combined; only {keys[0]!r} takes effect"
                )
            check_conditions(v, rel, rep, here)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            check_conditions(v, rel, rep, f"{path}[{i}]")


def is_unit(name: str, units: set[str]) -> bool:
    """Scavenger units are generated at runtime from a base def, so armdrag_scav
    has no file of its own but is perfectly real if armdrag exists."""
    return (name in units
            or name in NOT_UNITS
            or (name.endswith("_scav") and name[:-5] in units))


def check_hubs(node, rel: str, rep: Report, path: str = "") -> None:
    """A `hub` list must hold either all objects or all lists, never both.

    Both spellings are legal and both appear upstream: `"hub": [ {..}, {..} ]`
    and `"hub": [[ {..}, {..} ]]`, the latter grouping alternatives. Mixing them
    is still valid JSON, so the syntax check passes -- but BuildChain calls
    Json::Value::find on each element, that throws on an array, and the AI logs
    "requires objectValue or nullValue" and loads NO build chain at all.
    Symptom is commanders standing idle from frame 0.
    """
    if isinstance(node, dict):
        for k, v in node.items():
            here = f"{path}.{k}" if path else k
            if k == "hub" and isinstance(v, list) and v:
                kinds = {type(e).__name__ for e in v}
                if len(kinds) > 1:
                    rep.error(
                        f"{rel}: {here} mixes {sorted(kinds)} -- BuildChain calls "
                        f"Json::Value::find on each element and throws on a list. "
                        f"The whole build chain fails to load.")
            check_hubs(v, rel, rep, here)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            check_hubs(v, rel, rep, f"{path}[{i}]")


def check_configs(cfg_root: Path, units: set[str], rep: Report,
                  baseline: Path | None = None) -> None:
    """Findings in a file byte-identical to the baseline belong to upstream.

    Stock BARb ships a dozen dead unit names (armuwmex, legplat, legamsub...).
    Reporting them every run trains you to ignore the output, which defeats the
    tool. They are demoted to notes; anything in a file this repo has actually
    touched stays an error.
    """
    if not cfg_root.is_dir():
        rep.error(f"no config/ directory at {cfg_root}")
        return
    for p in sorted(cfg_root.rglob("*.json")):
        rel = p.relative_to(cfg_root).as_posix()
        raw = p.read_text("utf-8", errors="replace")
        ours = baseline is None or not matches_any_baseline(p, rel, baseline)
        say = rep.error if ours else rep.note

        try:
            data = json.loads(strip_jsonc(raw))
        except json.JSONDecodeError as e:
            say(f"{rel}:{e.lineno}: invalid JSON -- {e.msg}. "
                f"jsoncpp drops the whole file and the AI runs on defaults.")
            continue

        check_conditions(data, rel, rep if ours else _NoteOnly(rep))
        check_hubs(data, rel, rep if ours else _NoteOnly(rep))

        if units:
            seen: set[str] = set()
            for _, s in walk_strings(data):
                if s not in seen and UNITISH.match(s) and not is_unit(s, units):
                    seen.add(s)
            for name in sorted(seen):
                say(f"{rel}:{line_of(raw, name)}: '{name}' is not a unit def "
                    f"-- requests for it are silently dropped")


def _norm(p: Path) -> bytes:
    """Content ignoring line endings: the baseline tree is CRLF, ours is LF."""
    return p.read_bytes().replace(b"\r\n", b"\n")


def matches_any_baseline(p: Path, rel: str, baseline: Path) -> bool:
    """True if this file is stock, at its own path or at any other profile's.

    A new profile is normally started by copying an existing one, so rush/ is
    full of files that are byte-identical to stock hard_aggressive/ but have no
    counterpart at rush/. Without the second lookup every inherited quirk gets
    attributed to us the moment we add a profile.
    """
    here = baseline / rel
    if here.exists():
        return _norm(p) == _norm(here)
    mine = _norm(p)
    name = Path(rel).name
    return any(_norm(c) == mine for c in baseline.glob(f"*/{name}"))


class _NoteOnly:
    """Adapter so check_conditions() can downgrade into an upstream note."""

    def __init__(self, rep: "Report") -> None:
        self._rep = rep

    def error(self, msg: str) -> None:
        self._rep.note(msg)


def check_parity(cfg_root: Path, rep: Report) -> None:
    """Legion is a third faction, not a variant of the other two.

    Cortex/Armada tuning lives in x.json; Legion's lives in x_leg.json. A change
    made only to x.json simply does not exist when the AI plays Legion.
    """
    for prof_dir in sorted(d for d in cfg_root.iterdir() if d.is_dir()):
        names = {p.stem for p in prof_dir.glob("*.json")}
        for base in sorted(n for n in names if not n.endswith("_leg")):
            twin = f"{base}_leg"
            # Only these four have a Legion twin upstream; the rest are shared.
            if base in ("behaviour", "build_chain", "commander", "economy", "factory") \
                    and twin not in names:
                rep.warn(f"{prof_dir.name}/: {base}.json has no {twin}.json "
                         f"-- Legion falls back to the shared default")


def check_engine_side(variant_dir: Path, variant: str, rep: Report) -> list[str]:
    """Returns the profiles declared in AIOptions.lua (uncommented ones only)."""
    info = variant_dir / "engine-side" / "AIInfo.lua"
    if not info.exists():
        rep.error(f"engine-side/AIInfo.lua missing -- the variant cannot load")
        return []
    text = info.read_text("utf-8", errors="replace")
    m = re.search(r"key\s*=\s*'version'\s*,\s*\n\s*value\s*=\s*'([^']*)'", text)
    if not m:
        rep.warn("engine-side/AIInfo.lua: could not parse the version value")
    elif m.group(1) != variant:
        rep.error(f"engine-side/AIInfo.lua declares version '{m.group(1)}' but the "
                  f"folder is '{variant}' -- the engine keys the config folder off "
                  f"this value")

    opts = variant_dir / "engine-side" / "AIOptions.lua"
    if not opts.exists():
        rep.warn("engine-side/AIOptions.lua missing -- profiles are not selectable")
        return []
    otext = opts.read_text("utf-8", errors="replace")
    # Only lines that are not Lua-commented declare a real, selectable profile.
    body = otext[otext.find("key     = 'profile'"):] if "key     = 'profile'" in otext else ""
    return [
        mm.group(1)
        for line in body.splitlines()
        if not line.lstrip().startswith("--")
        for mm in [re.search(r"key\s*=\s*'([a-z_]+)'", line)]
        if mm and mm.group(1) != "profile"
    ]


BASELINE = REPO / "reference" / "barb-stable" / "game-side"


def check_variant(variant: str, units: set[str]) -> Report:
    rep = Report()
    vdir = AI_DIR / variant
    cfg_root = vdir / "game-side" / "config"
    script_root = vdir / "game-side" / "script"

    declared = check_engine_side(vdir, variant, rep)
    base = BASELINE / "config" if (BASELINE / "config").is_dir() else None
    check_configs(cfg_root, units, rep, base)
    if cfg_root.is_dir():
        check_parity(cfg_root, rep)

    on_disk = sorted(d.name for d in cfg_root.iterdir() if d.is_dir()) if cfg_root.is_dir() else []
    if declared:
        hidden = [p for p in on_disk if p not in declared]
        if hidden:
            # Still reachable from a start script (run_match.py passes `profile`
            # straight through as an AI option); only the lobby list is gated.
            rep.warn(f"profiles with config on disk but no AIOptions.lua entry: "
                     f"{', '.join(hidden)} -- testable via the harness, "
                     f"not selectable in the lobby")
    for p in declared:
        if p not in on_disk:
            rep.warn(f"profile '{p}' is offered in AIOptions.lua but has no "
                     f"config/{p}/ -- it silently falls back to config/*.json")
        if script_root.is_dir() and not (script_root / p / "init.as").exists():
            rep.warn(f"profile '{p}' has no script/{p}/init.as")

    return rep


def load_units() -> set[str]:
    """Every unit def name BAR ships, from the filenames under units/.

    Empty set (checks skipped, with a warning) if the game checkout is missing,
    so this tool still works on a machine without BAR installed.
    """
    try:
        game = bar_env.load().game_sdd
    except BarEnvError:
        return set()
    udir = game / "units"
    if not udir.is_dir():
        return set()
    return {p.stem for p in udir.rglob("*.lua")}


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("variants", nargs="*", help="variant names (default: all in ai/)")
    ap.add_argument("--all", action="store_true",
                    help="also list findings inherited unchanged from stock BARb")
    args = ap.parse_args()

    units = load_units()
    if not units:
        print("note: BAR.sdd not found -- skipping unit-name checks\n")

    names = args.variants or sorted(
        p.name for p in AI_DIR.iterdir() if (p / "game-side").is_dir()
    )
    failed = 0
    for v in names:
        if not (AI_DIR / v / "game-side").is_dir():
            print(f"\n{v}\n  ERROR   no such variant in {AI_DIR}")
            failed += 1
            continue
        rep = check_variant(v, units)
        rep.dump(v, show_notes=args.all)
        failed += bool(rep.errors)

    print()
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
