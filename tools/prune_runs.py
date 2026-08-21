#!/usr/bin/env python3
"""Reclaim disk from run output, keeping everything that is evidence.

apexearth, 2026-08-20: "I do not want these sorts of files growing
perpetually in size." The rule this encodes, from that cleanup:

  - runtime/            deleted outright (documented disposable in CLAUDE.md)
  - matches/_engine-*   deleted (auto-suffixed scratch write dirs); the main
                        matches/_engine stays -- it holds the warm archive
                        cache that saves ~35s per run
  - matches/<run>       deleted when older than --days (default 5) AND not
                        referenced by name in ISSUES.md / CHANGES.md /
                        USER-FEEDBACK.md / changes/ / feedback/ / notes/
  - tournaments demos   *.sdfz inside tournament match dirs deleted when the
                        tournament is older than --days; ledgers, summaries,
                        configs and infologs are never touched

Refuses to run while any spring-headless process is alive.

    python tools/prune_runs.py            # report what would go
    python tools/prune_runs.py --apply    # actually delete
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
EVIDENCE = ["ISSUES.md", "CHANGES.md", "USER-FEEDBACK.md"]
EVIDENCE_GLOBS = ["changes/*.md", "feedback/*.md", "notes/*.md"]


def engines_running() -> bool:
    try:
        out = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq spring-headless.exe"],
            capture_output=True, text=True, timeout=20).stdout
        return "spring-headless" in out
    except OSError:
        return False


def referenced_prefixes() -> tuple[str, ...]:
    text = ""
    for f in EVIDENCE:
        p = REPO / f
        if p.exists():
            text += p.read_text(encoding="utf8", errors="replace")
    for g in EVIDENCE_GLOBS:
        for p in REPO.glob(g):
            text += p.read_text(encoding="utf8", errors="replace")
    refs = set(m.rstrip("-") for m in re.findall(r"matches/([A-Za-z0-9_.-]+)", text))
    refs |= set(m.rstrip("-") for m in re.findall(r"tournaments/([A-Za-z0-9_.-]+)", text))
    return tuple(r for r in refs if r)


def dir_date(name: str):
    m = re.match(r"(\d{8})-", name)
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1), "%Y%m%d")
    except ValueError:
        return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--days", type=int, default=5,
                    help="keep runs newer than this many days (default 5)")
    ap.add_argument("--apply", action="store_true", help="delete; default is dry-run")
    args = ap.parse_args()

    if engines_running():
        sys.exit("spring-headless is running -- finish or kill the run first")

    cutoff = datetime.now() - timedelta(days=args.days)
    keep = referenced_prefixes()
    total = 0

    def gone(path: Path, why: str):
        nonlocal total
        sz = sum(f.stat().st_size for f in path.rglob("*") if f.is_file()) \
            if path.is_dir() else path.stat().st_size
        total += sz
        print(f"{'DELETE' if args.apply else 'would delete'}  {sz/1e6:8.1f} MB  {path}  ({why})")
        if args.apply:
            if path.is_dir():
                shutil.rmtree(path, ignore_errors=True)
            else:
                path.unlink(missing_ok=True)

    rt = REPO / "runtime"
    if rt.exists():
        gone(rt, "documented disposable")

    md = REPO / "matches"
    if md.exists():
        for d in sorted(md.iterdir()):
            if not d.is_dir():
                continue
            if d.name == "_engine" or d.name == "_engine_watch":
                continue
            if d.name.startswith("_engine"):
                gone(d, "scratch write dir")
                continue
            when = dir_date(d.name)
            if when is not None and when < cutoff \
                    and not d.name.startswith(keep):
                gone(d, f"older than {args.days}d, unreferenced")

    for f in glob.glob(str(REPO / "tournaments/*/matches/*/*.sdfz")) \
            + glob.glob(str(REPO / "tournaments/*/matches/*/demos/*.sdfz")):
        p = Path(f)
        tname = p.relative_to(REPO / "tournaments").parts[0]
        when = dir_date(tname)
        if when is not None and when < cutoff:
            gone(p, "old tournament demo")

    print(f"\ntotal {'freed' if args.apply else 'reclaimable'}: {total/1e9:.1f} GB")
    if not args.apply:
        print("dry-run only; re-run with --apply to delete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
