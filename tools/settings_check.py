#!/usr/bin/env python3
"""Does a deployed AI play the repo's settings? (his 10-19: one config, committed, traceable.)

    python tools/settings_check.py Apexwatch:lane-watch [Apexc9:lane-c9 ...]
    python tools/settings_check.py --release v0.3.3

tunables.as is the one config: every value the AI plays, script and C++ (InitScript.cpp hands each TUNE_
constant to CCircuitAI::SetScriptDefaults). A lane or release must hold it unchanged, with the repo's played
policy (policydata.as), and an option its AIOptions.lua declares must default to the file's value, since a
declared option outranks the file. Exit 1 on any difference, listing each one.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "ai" / "Unstable"
STD = Path("script") / "standard"
POLICY = Path("manager") / "brain" / "market" / "policydata.as"
CONST = re.compile(r"^const float (TUNE_[A-Z0-9_]+) = ([-0-9.e]+)f;", re.M)
OPT = re.compile(r"key\s*=\s*'(apex_[a-z0-9_]+)'.*?def\s*=\s*([^,\n]+)", re.S)


def text(p: Path) -> str:
    return p.read_text(encoding="utf-8").replace("\r\n", "\n")


def values(p: Path) -> dict:
    return {m.group(1): float(m.group(2)) for m in CONST.finditer(text(p))}


def check_tree(label: str, script_dirs: list, options: Path, want: dict, want_policy: str) -> list:
    bad = []
    for d in script_dirs:
        t = d / "tunables.as"
        if not t.exists():
            bad.append(f"{label}: {t} missing")
            continue
        got = values(t)
        for k in sorted(set(want) | set(got)):
            if want.get(k) != got.get(k):
                bad.append(f"{label}: {k} repo={want.get(k)} deployed={got.get(k)}  ({d})")
        pol = d / POLICY
        if pol.exists() and text(pol) != want_policy:
            bad.append(f"{label}: policydata.as differs from the repo's  ({pol})")
    if options.exists():
        for m in OPT.finditer(text(options)):
            key, raw = m.group(1), m.group(2).strip().strip("'\"")
            name = "TUNE_" + key[5:].upper()
            if name not in want:
                continue
            try:
                v = float(raw)
            except ValueError:
                continue
            if v != want[name]:
                bad.append(f"{label}: AIOptions {key} def={raw} but tunables.as {name}={want[name]:g}"
                           " (a declared option outranks the file)")
    return bad


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    want = values(SRC / "game-side" / STD / "tunables.as")
    want_policy = text(SRC / "game-side" / STD / POLICY)
    env = bar_env.load()
    bad = []
    if args[0] == "--release":
        rel = REPO / "ai" / args[1]
        bad = check_tree(args[1], [rel / "game-side" / STD], rel / "engine-side" / "AIOptions.lua", want, want_policy)
    else:
        for spec in args:
            short, ver = spec.split(":")[:2]
            eng = env.skirmish_dir(short, ver)
            game = env.game_config_dir(short, ver)
            bad += check_tree(spec, [eng / STD, game / STD], eng / "AIOptions.lua", want, want_policy)
    for b in bad:
        print("DIFFERS", b)
    print(f"settings: {len(want)} values, {len(bad)} difference(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
