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
    t = d.stat().st_mtime
    for root, _dirs, files in os.walk(d):
        for f in files:
            try:
                t = max(t, os.stat(os.path.join(root, f)).st_mtime)
            except OSError:
                pass
    return t


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
    a = ap.parse_args()
    cut = time.time() - a.days * 86400
    dest = Path(a.dest)
    if a.apply and not dest.exists():
        sys.exit(f"{dest} not found")
    total = moved = 0
    for top in ("matches", "tournaments"):
        src = REPO / top
        if not src.is_dir():
            continue
        for d in sorted(src.iterdir()):
            if not d.is_dir() or d.name.startswith("_") or "-nn-" in d.name:
                continue
            if newest_mtime(d) >= cut:
                continue
            n = size_of(d)
            total += n
            if not a.apply:
                continue
            target = dest / top / d.name
            if target.exists():
                target = dest / top / f"{d.name}-{int(time.time())}"
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(d), str(target))
            moved += 1
    gb = total / 1073741824.0
    print(f"{'moved' if a.apply else 'would move'} {moved if a.apply else ''} {gb:.1f} GB "
          f"(older than {a.days:g} days, not -nn- batches) -> {dest}")
    print(f"C: free now {shutil.disk_usage(str(REPO)).free / 1073741824.0:.1f} GB")


if __name__ == "__main__":
    main()
