#!/usr/bin/env python3
"""Keep the modified CircuitAI C++ under version control.

`vendor/` is gitignored -- it holds upstream clones -- and both `vendor/engine`
and its `BARb` submodule are their own git repositories, so the parent repo can
only ever store them as pointers. Every C++ change we make therefore lives in a
gitignored working tree and one built DLL, and a re-clone or `git clean` destroys
it. That very nearly happened: a whole session of C++ work existed nowhere else.

So the files we actually modify are mirrored into `cpp/`, which IS tracked. That
directory is the source of truth for our C++ delta -- not the patch file, which
is a diff and cannot be compiled, reviewed line-by-line in a normal diff view, or
merged.

    python tools/sync_cpp.py pull     vendor -> cpp/   (after editing in vendor)
    python tools/sync_cpp.py apply    cpp/   -> vendor (after a fresh clone)
    python tools/sync_cpp.py status   what differs

`pull` is the one to run after any C++ edit, before committing.
"""
from __future__ import annotations

import filecmp
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
# A LANE edits its own copy of the BARb tree, so the mirror has to follow it --
# otherwise lane C++ work lives in exactly one directory, is invisible to git,
# and is destroyed by the next `apply`. That is not hypothetical: it happened
# on 2026-09-07 (tools/lane.py).
import os.path as _osp
sys.path.insert(0, _osp.dirname(_osp.abspath(__file__)))
import lane as _lane
BARB = _lane.barb_src()
MIRROR = REPO / "cpp"


# Upstream is a BRANCH, not this checkout's HEAD. The BARb clone sits on a local
# branch carrying our commits, so a bare `git diff` -- working tree vs HEAD --
# sees only what is uncommitted and calls every committed change of ours
# upstream's. That made `pull` skip any file whose change had been committed, and
# made `status` label 43 real files "no longer differs from upstream; rm by hand".
UPSTREAM_REFS = ("apex/barbarian", "origin/barbarian", "origin/master")


def _upstream_base() -> str | None:
    for ref in UPSTREAM_REFS:
        got = subprocess.run(["git", "merge-base", "HEAD", ref], cwd=BARB,
                             capture_output=True, text=True)
        if got.returncode == 0 and got.stdout.strip():
            return got.stdout.strip()
    return None


def modified_files() -> list[str]:
    """Files we have changed against upstream, per the submodule's own git."""
    if not (BARB / ".git").exists():
        raise SystemExit(f"no BARb checkout at {BARB}")
    base = _upstream_base()
    if base is None:
        raise SystemExit(
            f"no upstream ref in {BARB} (tried {', '.join(UPSTREAM_REFS)}).\n"
            "Refusing to guess: without a base every tracked file looks stale,\n"
            "and `status` would tell you to delete work that is not upstream's.")
    out = subprocess.run(["git", "diff", "--name-only", base, "HEAD"], cwd=BARB,
                         capture_output=True, text=True, check=True).stdout
    files = {line.strip() for line in out.splitlines() if line.strip()}
    # Uncommitted edits too -- an agent that has just written a file has not
    # committed it, and it is still ours.
    # A lane's .git points at the SHARED gitdir: --work-tree reads this tree.
    # --name-only compares blob hashes, so every CRLF checkout of an LF blob
    # counts; numstat with CR ignored names only real edits.
    out = subprocess.run(["git", f"--work-tree={BARB}", "diff", "--numstat",
                          "--ignore-cr-at-eol"],
                         cwd=BARB, capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        parts = line.split("	")
        if len(parts) == 3 and (parts[0] != "0" or parts[1] != "0"):
            files.add(parts[2].strip())
    return sorted(files)


def tracked_files() -> list[str]:
    if not MIRROR.exists():
        return []
    return sorted(str(p.relative_to(MIRROR)).replace("\\", "/")
                  for p in MIRROR.rglob("*") if p.is_file())


def do_pull() -> None:
    names = modified_files()
    if not names:
        print("nothing modified in vendor -- is the patch applied?")
        return
    copied = 0
    for rel in names:
        src, dst = BARB / rel, MIRROR / rel
        if not src.exists():
            print(f"  gone   {rel}")
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        if not dst.exists() or not filecmp.cmp(src, dst, shallow=False):
            shutil.copy2(src, dst)
            copied += 1
            print(f"  update {rel}")
    # Anything we previously mirrored but no longer modify is stale.
    for rel in tracked_files():
        if rel not in names:
            print(f"  STALE  {rel}  (no longer differs from upstream; rm by hand)")
    print(f"{len(names)} modified, {copied} written to cpp/")


def do_apply() -> None:
    names = tracked_files()
    if not names:
        raise SystemExit("cpp/ is empty -- nothing to apply")
    for rel in names:
        src, dst = MIRROR / rel, BARB / rel
        if not dst.parent.exists():
            print(f"  SKIP   {rel}  (no such path in vendor)")
            continue
        if not dst.exists() or not filecmp.cmp(src, dst, shallow=False):
            shutil.copy2(src, dst)
            print(f"  write  {rel}")
    print(f"{len(names)} files applied to vendor")


def do_status() -> None:
    names = set(modified_files())
    mirror = set(tracked_files())
    for rel in sorted(names | mirror):
        src, dst = BARB / rel, MIRROR / rel
        if rel not in mirror:
            print(f"  NOT MIRRORED  {rel}")
        elif rel not in names:
            print(f"  STALE         {rel}")
        elif not filecmp.cmp(src, dst, shallow=False):
            print(f"  DIFFERS       {rel}")
    print(f"{len(names)} modified in vendor, {len(mirror)} mirrored in cpp/")


def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "pull":
        _lane.require("sync_cpp pull")
        do_pull()
    elif cmd == "apply":
        _lane.require("sync_cpp apply")
        do_apply()
    elif cmd == "status":
        do_status()
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
