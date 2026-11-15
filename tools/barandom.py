"""BaRandom (Beyond All Random) unit randomizer as a test mode (his 11-14: randomized stats find the flaws in our
algorithm that the normal game never shows).

The mod is four tweakdefs Lua files (https://github.com/bazilio91/beyond-all-random, by LoH, based on AMBO & MGGW's
Random Rarities). The repo carries no licence, so it is never copied into this repo: `fetch` downloads one pinned
commit into reference/barandom/<sha>/ (git-ignored), and `modoptions()` encodes the files the way its serialize.sh
does (URL-safe base64, no padding) for the slots its README names. Unminified is fine here: the 16,384-char limit is
the lobby's, and a start script has none.

    python tools/barandom.py fetch [--sha SHA]
    python tools/barandom.py show  [--sha SHA]       # slot sizes
    run_match.py ... --randomizer [SHA]               # every AI plays the randomized defs

Each game rolls its own units; the infolog carries `[BaRandom]` lines and the rolled names, and
tools/trial_report.py --kind randomizer already recognises them.
"""
from __future__ import annotations

import argparse
import base64
import pathlib
import sys
import urllib.request

REPO = "bazilio91/beyond-all-random"
PINNED = "4f3a820a5a9abd9b37d4a7d6ac75a1b0abc89f48"   # master on 2026-11-14
SLOTS = (("tweakdefs", "mod.lua"), ("tweakdefs1", "mod_part2.lua"),
         ("tweakdefs2", "faction_buff.lua"), ("tweakdefs3", "mod_tiers.lua"))
ROOT = pathlib.Path(__file__).resolve().parent.parent / "reference" / "barandom"


def cache_dir(sha: str) -> pathlib.Path:
    return ROOT / sha


def fetch(sha: str = PINNED) -> pathlib.Path:
    d = cache_dir(sha)
    d.mkdir(parents=True, exist_ok=True)
    for _, name in SLOTS:
        p = d / name
        if p.exists() and p.stat().st_size > 0:
            continue
        url = "https://raw.githubusercontent.com/%s/%s/%s" % (REPO, sha, name)
        with urllib.request.urlopen(url, timeout=30) as r:
            data = r.read()
        if not data.lstrip().startswith(b"--"):
            raise SystemExit("barandom: %s does not look like the mod's Lua (%d bytes)" % (url, len(data)))
        p.write_bytes(data)
    return d


def encode(text: bytes) -> str:
    return base64.urlsafe_b64encode(text).decode("ascii").rstrip("=")


def modoptions(sha: str = PINNED) -> dict[str, str]:
    d = cache_dir(sha)
    if not all((d / n).exists() for _, n in SLOTS):
        d = fetch(sha)
    return {slot: encode((d / name).read_bytes()) for slot, name in SLOTS}


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("cmd", choices=("fetch", "show"))
    ap.add_argument("--sha", default=PINNED)
    a = ap.parse_args(argv)
    if a.cmd == "fetch":
        print("fetched", fetch(a.sha))
        return 0
    for slot, val in modoptions(a.sha).items():
        print("%-10s %6d chars" % (slot, len(val)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
