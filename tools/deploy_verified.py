#!/usr/bin/env python3
"""Deploy apex and HARD-FAIL unless the live install matches the repo.

Exists because on 2026-08-20 four consecutive measurement batches ran on a
stale build: deploy refuses while an engine is running, every pipe after it
(`| tail`, `| grep`, even printing `status`) masked the refusal into a green
chain, and the games measured old code. This script is the only approved way
to deploy before a measurement:

    python tools/deploy_verified.py && <run games>

Exit 0 only when `deploy_ai.py status` reports apex in sync afterwards.
"""
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def run(args):
    return subprocess.run([sys.executable, str(REPO / "tools" / args[0]), *args[1:]],
                          capture_output=True, text=True).stdout


def main() -> int:
    out = run(["deploy_ai.py", "deploy", "apex"])
    status = run(["deploy_ai.py", "status"])
    m = re.search(r"^  apex\s+(\S[^\n]*)\n\s+repo (\w+)\s+live (\w+)", status, re.M)
    if not m:
        print("deploy_verified: cannot read apex status", file=sys.stderr)
        print(status, file=sys.stderr)
        return 2
    state, repo, live = m.group(1).strip(), m.group(2), m.group(3)
    if repo != live or "in sync" not in state:
        print(f"deploy_verified: NOT IN SYNC (repo {repo} live {live}) -- "
              f"deploy output follows", file=sys.stderr)
        print(out, file=sys.stderr)
        return 1
    print(f"deploy_verified: in sync ({repo})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
