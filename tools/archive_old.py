"""Move match and tournament directories older than --days to the archive drive (his standing answer when C: fills:
G:\\bar-ai-archive\\{matches,tournaments} mirror the repo folders). Training batches (*-nn-*) stay: tools/nntrain.py
reads finished games only from the repo's own folders. Engine write dirs (_engine*) and anything touched within
--days stay. Safe while engines run: a game in flight writes only to fresh directories.

    python tools/archive_old.py                 # report only
    python tools/archive_old.py --apply [--days 3] [--dest G:/bar-ai-archive]"""
import argparse
import os
import shutil
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


def newest_mtime(d: Path) -> float:
    # files only: a directory's own mtime moves when reclaim.py deletes a file in it
    t = 0.0
    for root, _dirs, files in os.walk(d):
        for f in files:
            try:
                t = max(t, os.stat(os.path.join(root, f)).st_mtime)
            except OSError:
                pass
    return t or d.stat().st_mtime


def size_of(d: Path) -> int:
    n = 0
    for root, _dirs, files in os.walk(d):
        for f in files:
            try:
                n += os.stat(os.path.join(root, f)).st_size
            except OSError:
                pass
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--days", type=float, default=3.0)
    ap.add_argument("--dest", default="G:/bar-ai-archive")
    ap.add_argument("--include-nn", action="store_true",
                    help="move -nn- training batches too (11-05: the trainers that read them, nntrain/randsearch, are stopped)")
    ap.add_argument("--only", choices=("matches", "tournaments"), help="one folder")
    ap.add_argument("--skip", action="append", default=[], help="a folder name to leave in place, repeatable")
    a = ap.parse_args()
    dest = Path(a.dest)
    if a.apply and not dest.exists():
        sys.exit(f"{dest} not found")
    moved, gb = archive(a.days, dest, a.apply, a.include_nn, a.only, a.skip)
    print(f"{'moved' if a.apply else 'would move'} {moved if a.apply else ''} {gb:.1f} GB "
          f"(older than {a.days:g} days, not -nn- batches) -> {dest}")
    print(f"C: free now {free_gb():.1f} GB")


def free_gb() -> float:
    return shutil.disk_usage(str(REPO)).free / 1073741824.0


def archive(days=3.0, dest=Path("G:/bar-ai-archive"), apply=True, include_nn=False, only=None, skip=()):
    """Move the old match/tournament folders; returns (folders moved, GB). A folder another process moved or is
    moving first is skipped."""
    cut = time.time() - days * 86400
    total = moved = 0
    for top in ((only,) if only else ("matches", "tournaments")):
        src = REPO / top
        if not src.is_dir():
            continue
        for d in sorted(src.iterdir()):
            if not d.is_dir() or d.name.startswith("_") or ("-nn-" in d.name and not include_nn) or d.name in skip:
                continue
            if newest_mtime(d) >= cut:
                continue
            n = size_of(d)
            total += n
            if not apply:
                continue
            target = dest / top / d.name
            if target.exists():
                target = dest / top / f"{d.name}-{int(time.time())}"
            try:
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(d), str(target))
                moved += 1
            except OSError as e:
                print(f"archive: skipped {d.name}: {e}", flush=True)
    return moved, total / 1073741824.0


# His 11-11: keep C: above this; run_match archives old folders when a launch finds less.
MIN_FREE_GB = 50.0


def ensure_disk(min_free_gb: float = MIN_FREE_GB) -> None:
    """Before a launch: below the floor, move 3-day-old folders to the archive drive; then 1-day-old if still short."""
    if free_gb() >= min_free_gb:
        return
    dest = Path("G:/bar-ai-archive")
    if not dest.exists():
        print(f"disk: C: {free_gb():.1f} GB free, under {min_free_gb:.0f}, and {dest} is not there", flush=True)
        return
    for days in (3.0, 1.0):
        before = free_gb()
        moved, gb = archive(days, dest)
        print(f"disk: C: {before:.1f} GB free, under {min_free_gb:.0f}: moved {moved} folders ({gb:.1f} GB) older "
              f"than {days:g} days to {dest}; now {free_gb():.1f} GB", flush=True)
        if free_gb() >= min_free_gb:
            return


if __name__ == "__main__":
    main()
