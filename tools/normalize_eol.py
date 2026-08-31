#!/usr/bin/env python3
"""Make the working tree's line endings match .gitattributes.

    python tools/normalize_eol.py           # report only
    python tools/normalize_eol.py --fix     # rewrite the offenders
    python tools/normalize_eol.py --fix ai/Unstable tools

`.gitattributes` says `* text=auto eol=lf`, and git honours that in the INDEX --
so a CRLF file on disk and its LF blob compare equal, `git status` stays clean,
and nothing ever says the tree disagrees with itself. The cost lands somewhere
else entirely: a `str.replace` anchor copied out of one file does not match the
same text in another, silently, and the edit is simply not applied. That has
eaten edits here at least five times, three of them in one session.

Normalizing is therefore a NO-OP for git (the blobs are already LF) and a real
fix for every tool that reads bytes. `--fix` prints the resulting `git diff`
line count; anything but zero means .gitattributes and the index disagree, and
that is worth reading before committing.

Binary files, and anything .gitattributes marks `binary` or `-text`, are left
alone.

WINDOWS GOTCHA, and this one looks alarming: the rewrite changes every file's
size, so `git status` lists all of them as ` M ` even though `git diff` is
empty. It is a stale stat cache, not a content change, and neither
`git update-index --refresh` nor `--really-refresh` clears it. `git add` on a
file whose content already matches the index stages NOTHING and refreshes the
entry, so `--fix` does exactly that for the files it verified identical, and
prints what it staged (which must be nothing).
"""

from __future__ import annotations

import argparse
import fnmatch
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_ROOTS = ("ai", "tools")

# Files with no extension, or one git has no opinion about, are decided by the
# NUL-byte sniff below rather than by name.
NEVER = {".png", ".dll", ".7z", ".sd7", ".sdz", ".sdfz", ".pyc", ".ico", ".zip"}


def read_attributes() -> list[tuple[str, str | None]]:
    """[(glob, 'lf' | 'crlf' | None-for-binary)], last match winning."""
    rules: list[tuple[str, str | None]] = []
    ga = REPO / ".gitattributes"
    if not ga.exists():
        return [("*", "lf")]
    for line in ga.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        pattern, attrs = parts[0], parts[1:]
        eol: str | None = None
        for a in attrs:
            if a == "binary" or a == "-text":
                eol = None
                break
            if a.startswith("eol="):
                eol = a.split("=", 1)[1]
        rules.append((pattern, eol))
    return rules


def wanted_eol(rel: str, rules) -> str | None:
    """The last matching rule wins, exactly as git resolves attributes."""
    out: str | None = None
    for pattern, eol in rules:
        pat = pattern if "/" in pattern else "*/" + pattern
        if fnmatch.fnmatch("/" + rel, pat) or fnmatch.fnmatch(rel, pattern):
            out = eol
    return out


def classify(data: bytes) -> str:
    crlf = data.count(b"\r\n")
    lf = data.count(b"\n") - crlf
    if crlf and lf:
        return "mixed"
    if crlf:
        return "crlf"
    if lf:
        return "lf"
    return "none"


def convert(data: bytes, eol: str) -> bytes:
    body = data.replace(b"\r\n", b"\n")
    return body if eol == "lf" else body.replace(b"\n", b"\r\n")


def tracked(roots) -> list[Path]:
    """Only files git knows about -- matches/ and tournaments/ are gitignored
    output and must never be rewritten."""
    r = subprocess.run(["git", "-C", str(REPO), "ls-files", "-z", *roots],
                       capture_output=True, text=True)
    return [REPO / p for p in r.stdout.split("\0") if p]


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("roots", nargs="*", default=list(DEFAULT_ROOTS),
                    help=f"paths to scan (default: {' '.join(DEFAULT_ROOTS)})")
    ap.add_argument("--fix", action="store_true", help="rewrite the offenders")
    args = ap.parse_args()

    rules = read_attributes()
    offenders: list[tuple[Path, str, str]] = []
    counts: dict[tuple[str, str], int] = {}

    for path in tracked(args.roots):
        if path.suffix.lower() in NEVER or not path.is_file():
            continue
        rel = path.relative_to(REPO).as_posix()
        eol = wanted_eol(rel, rules)
        if eol is None:
            continue
        data = path.read_bytes()
        if b"\0" in data[:8000]:
            continue
        have = classify(data)
        if have in ("none", eol):
            continue
        offenders.append((path, have, eol))
        key = (path.suffix.lower() or "(none)", have)
        counts[key] = counts.get(key, 0) + 1

    if not offenders:
        print("line endings: every tracked file already matches .gitattributes")
        return 0

    for (suffix, have), n in sorted(counts.items()):
        print(f"  {n:4d}  {suffix:<6} {have.upper()}")
    print(f"{len(offenders)} file(s) disagree with .gitattributes "
          f"under {', '.join(args.roots)}")

    if not args.fix:
        print("\nreport only -- pass --fix to rewrite. git will show no diff: the\n"
              "index already holds LF, which is exactly why nothing reports this.")
        return 1

    before = dirty(args.roots)
    for path, _have, eol in offenders:
        path.write_bytes(convert(path.read_bytes(), eol))
    print(f"rewrote {len(offenders)} file(s)")

    # The only interesting number: did rewriting put anything NEW in the diff?
    # The tree normally has unrelated work in it, so an absolute count says
    # nothing.
    added = sorted(dirty(args.roots) - before)
    if not added:
        print("git diff unchanged -- the index was already LF, so this is "
              "invisible to review and safe to land on its own")
        refresh_stat([p for p, _h, _e in offenders])
    else:
        print(f"{len(added)} file(s) ENTERED the diff -- .gitattributes and the "
              f"index disagree, read these before committing:")
        for rel in added[:20]:
            print(f"  {rel}")
    return 0


def refresh_stat(paths) -> None:
    """Clear the stale ` M ` entries the rewrite leaves in `git status`.

    Only files whose worktree blob already equals the index blob are touched, so
    `git add` here can never stage a content change -- it only rewrites the size
    and mtime git cached before the rewrite."""
    index = {}
    out = subprocess.run(["git", "-C", str(REPO), "ls-files", "-s"],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        meta, _, rel = line.partition("\t")
        parts = meta.split()
        if len(parts) >= 2 and rel:
            index[rel] = parts[1]
    same = []
    for path in paths:
        rel = path.relative_to(REPO).as_posix()
        h = subprocess.run(["git", "-C", str(REPO), "hash-object", "--path", rel,
                            "--", rel], capture_output=True, text=True).stdout.strip()
        if h and index.get(rel) == h:
            same.append(rel)
    for i in range(0, len(same), 100):
        subprocess.run(["git", "-C", str(REPO), "add", "--", *same[i:i + 100]])
    staged = subprocess.run(["git", "-C", str(REPO), "diff", "--cached", "--numstat"],
                            capture_output=True, text=True).stdout.strip()
    print(f"stat cache refreshed on {len(same)} file(s); "
          f"staged content changes: {len(staged.splitlines()) if staged else 0}")


def dirty(roots) -> set[str]:
    out = subprocess.run(["git", "-C", str(REPO), "diff", "--name-only", *roots],
                         capture_output=True, text=True).stdout
    return {l for l in out.splitlines() if l}


if __name__ == "__main__":
    raise SystemExit(main())
