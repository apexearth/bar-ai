#!/usr/bin/env python3
"""Two-minute headless match whose only question is: does the variant compile?

An AngelScript error disables the whole variant and the match still reports a
normal result -- so a broken deploy looks exactly like a working one, and a
whole tournament can be spent measuring stock BARb by accident. That happened
today: six games, every check green except `ran at all`, because a global was
read from a file the shim includes earlier than the one declaring it.

    python tools/smoke.py            # after every deploy, before any batch
    python tools/smoke.py --map "Comet Catcher Remake 1.8"

Exit code 1 on any compile error, so it chains: `python tools/smoke.py && ...`
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ai", default="Apex:Unstable:standard")
    ap.add_argument("--map", dest="map_name", default="Ancient Vault v1.4")
    ap.add_argument("--minutes", type=int, default=2)
    args = ap.parse_args()

    # A smoke test of the LAST deploy proves nothing about the edit just made.
    # deploy_ai refuses while a match holds the engine directory, so it is easy
    # to "smoke ok" a build that does not contain the fix -- that happened.
    # deploy_ai REFUSES while a match holds the engine directory, so a chained
    # `deploy && smoke && tournament` can silently keep the old build. Say which
    # of the two it is rather than just "DRIFTED".
    import time
    busy = subprocess.run(["powershell", "-NoProfile", "-Command",
                           "@(Get-Process spring-headless,spring -ErrorAction SilentlyContinue).Count"],
                          capture_output=True, text=True).stdout.strip()
    # A LANE deploys into its own folder, so an engine another lane is running
    # never has this DLL loaded and the refusal does not apply (tools/lane.py).
    import os.path as _osp
    sys.path.insert(0, _osp.dirname(_osp.abspath(__file__)))
    import lane as _lane
    if busy.isdigit() and int(busy) > 0 and not _lane.name():
        print(f"SMOKE FAIL: {busy} engine processes are running -- deploy cannot replace the DLL")
        return 1
    status = subprocess.run([sys.executable, str(REPO / "tools" / "deploy_ai.py"), "status"],
                            capture_output=True, text=True).stdout
    variant = args.ai.split(":")[1]
    for line in status.splitlines():
        if line.strip().startswith(variant) and "DRIFTED" in line:
            print(f"SMOKE FAIL: '{variant}' is DRIFTED -- deploy before smoking")
            return 1

    out = REPO / "matches" / "_smoke"
    shutil.rmtree(out, ignore_errors=True)
    cmd = [sys.executable, "-u", str(REPO / "tools" / "run_match.py"),
           "--a", args.ai, "--b", "BARb:stable:medium", "--map", args.map_name,
           "--per-side", "1", "--seed", "1", "--minutes", str(args.minutes),
           "--out", str(out), "--write-dir", str(REPO / "matches" / "_engine_smoke")]
    subprocess.run(cmd, capture_output=True, text=True)

    log = out / "infolog.txt"
    if not log.exists():
        print("SMOKE FAIL: the match produced no infolog")
        return 1
    text = log.read_text(errors="replace")
    # NOT anchored on a filename. AngelScript treats warnings as errors and
    # that failure prints as " (0, 0) : ERR : Warnings are treated as errors by
    # the application" with no file at all -- a filename-anchored pattern reads
    # a variant that never compiled as a clean run, which cost a full round of
    # false "validated" reports on 2026-08-20.
    errs = re.findall(r"[^\n]{0,40}\(?\d+, \d+\) : ERR[^\n]{0,90}"
                      r"|Fix compilation errors[^\n]{0,60}", text)
    loaded = "Load script:" in text
    if errs:
        print(f"SMOKE FAIL: {len(errs)} AngelScript errors")
        for e in sorted(set(errs))[:10]:
            print("  " + e.strip())
        return 1
    if not loaded:
        print("SMOKE FAIL: the variant never loaded its script")
        return 1
    print(f"smoke ok: variant compiled and loaded ({args.minutes} min, {args.map_name})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
