"""Clone the upstream sources into vendor/ so they are local and greppable.

    python tools/bootstrap_sources.py circuitai      # ~40 MB, the AI itself
    python tools/bootstrap_sources.py bar            # BAR game repo (shallow)
    python tools/bootstrap_sources.py engine         # RecoilEngine + submodules, large
    python tools/bootstrap_sources.py --list

CircuitAI is the one worth having early even if you never compile: the JSON
schema and the AngelScript binding surface are only documented by its source.
Nothing here is committed -- vendor/ is gitignored.
"""

from __future__ import annotations

import argparse
import subprocess
import sys

from bar_env import REPO

VENDOR = REPO / "vendor"

SOURCES = {
    "circuitai": {
        "url": "https://github.com/rlcevg/CircuitAI.git",
        "branch": "barbarian",
        "submodules": False,
        "why": "BARb's actual source. Read src/circuit/script/ for the AngelScript "
               "bindings, src/circuit/setup/ and module/ for the JSON schema, "
               "doc/Profile.md for profile authoring.",
    },
    "bar": {
        "url": "https://github.com/beyond-all-reason/Beyond-All-Reason.git",
        "branch": None,
        "submodules": False,
        "why": "Upstream game content. Useful for diffing against the local BAR.sdd "
               "checkout, which is stale, and for reading tools/headless_testing/.",
    },
    "engine": {
        "url": "https://github.com/beyond-all-reason/RecoilEngine.git",
        "branch": None,
        "submodules": True,
        "why": "Needed to build the DLL. Also the only place to read the AI "
               "interface headers (rts/ExternalAI/Interface) and the NullAI / "
               "CppTestAI templates. Large; submodules make it larger.",
    },
}


def clone(name: str, shallow: bool) -> int:
    spec = SOURCES[name]
    dest = VENDOR / name
    if dest.exists():
        print(f"{dest} already exists -- pulling instead")
        return subprocess.call(["git", "pull", "--ff-only"], cwd=dest)

    VENDOR.mkdir(parents=True, exist_ok=True)
    cmd = ["git", "clone"]
    if spec["branch"]:
        cmd += ["--branch", spec["branch"]]
    if shallow:
        # Shallow is fine for reading; drop --depth if you need history or to build
        # a specific engine tag.
        cmd += ["--depth", "1"]
    if spec["submodules"]:
        cmd += ["--recurse-submodules"]
        if shallow:
            cmd += ["--shallow-submodules"]
    cmd += [spec["url"], str(dest)]

    print(" ".join(cmd))
    rc = subprocess.call(cmd)
    if rc == 0:
        print(f"\n-> {dest}\n   {spec['why']}")
    return rc


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    # No `choices=` here: argparse validates the default against it, and an empty
    # default is what makes a bare invocation list the sources.
    ap.add_argument("what", nargs="*", metavar="{" + ",".join([*SOURCES, "all"]) + "}")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--full", action="store_true",
                    help="full history (needed to check out an engine tag for a build)")
    args = ap.parse_args()

    if args.list or not args.what:
        for name, spec in SOURCES.items():
            state = "cloned" if (VENDOR / name).exists() else "-"
            branch = f" (branch {spec['branch']})" if spec["branch"] else ""
            print(f"{name:<11} {state:<7} {spec['url']}{branch}")
            print(f"            {spec['why']}\n")
        return 0

    unknown = [w for w in args.what if w not in SOURCES and w != "all"]
    if unknown:
        raise SystemExit(f"unknown source(s): {', '.join(unknown)}")

    names = list(SOURCES) if "all" in args.what else args.what
    for name in names:
        print(f"\n=== {name} ===")
        if clone(name, shallow=not args.full) != 0:
            print(f"failed: {name}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
