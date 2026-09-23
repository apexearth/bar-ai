"""What the repo is spending disk on, and what can go.

    python tools/reclaim.py                      # report only, deletes nothing
    python tools/reclaim.py --apply dupes
    python tools/reclaim.py --days 7 --apply lanes runtime

Categories, cheapest information loss first:

  dupes    stdout.txt beside a non-empty infolog.txt. The engine writes the
           same run twice; every reader in tools/ takes infolog first and
           falls back to stdout, so dropping it loses nothing at all.
  runtime  scratch engine write-dirs and tool logs older than --days.
  lanes    a lane idle longer than --days: its build tree, its C++ source, its
           write dir, ai/lane-<x>, AND the deployed engine slot -- which
           `lane.py drop` leaves behind, which is why 70 of them piled up.
  replays  *.sdfz older than --days. Only needed to watch a game back.
  records  whole match/tournament directories older than --days. This is the
           measurement history; it is the only category that loses a finding.

Nothing is deleted without --apply, and nothing at all while an engine is
running -- a match in flight is writing into these directories.
"""
import argparse
import os
import pathlib
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bar_env
import lane as lanemod

REPO = lanemod.REPO
GB = 1073741824.0

# Allocated size, not apparent: a compressed or sparse tree would otherwise read
# high. Do NOT check these numbers with `du` -- it cannot descend a build dir
# here and silently reports a seventh of the truth (4.87 GB read as 716M).
if sys.platform == "win32":
    import ctypes

    _gcfs = ctypes.windll.kernel32.GetCompressedFileSizeW
    _gcfs.restype = ctypes.c_uint32

    def on_disk(path: str, apparent: int) -> int:
        high = ctypes.c_uint32(0)
        low = _gcfs(ctypes.c_wchar_p("\\\\?\\" + os.path.abspath(path)),
                    ctypes.byref(high))
        if low == 0xFFFFFFFF and ctypes.get_last_error() != 0:
            return apparent
        return (high.value << 32) + low
else:
    def on_disk(path: str, apparent: int) -> int:
        try:
            return os.stat(path).st_blocks * 512
        except (OSError, AttributeError):
            return apparent


def file_size(path: str) -> int:
    try:
        return on_disk(path, os.stat(path).st_size)
    except OSError:
        return 0


def tree_size(p: pathlib.Path) -> int:
    total = 0
    for root, _dirs, files in os.walk(p, onerror=lambda e: None):
        for f in files:
            total += file_size(os.path.join(root, f))
    return total


def newest(p: pathlib.Path) -> float:
    best = 0.0
    for root, _dirs, files in os.walk(p, onerror=lambda e: None):
        for f in files:
            try:
                best = max(best, os.stat(os.path.join(root, f)).st_mtime)
            except OSError:
                pass
    return best


def engines_running() -> int:
    try:
        out = subprocess.run(["tasklist"], capture_output=True, text=True).stdout
    except OSError:
        return 0
    return sum(1 for line in out.splitlines() if "spring" in line.lower())


def find_dupes():
    """(path, bytes) for every stdout.txt whose infolog.txt sibling is intact."""
    out = []
    for base in (REPO / "matches", REPO / "tournaments"):
        for root, _dirs, files in os.walk(base, onerror=lambda e: None):
            if "stdout.txt" not in files or "infolog.txt" not in files:
                continue
            info = os.path.join(root, "infolog.txt")
            so = os.path.join(root, "stdout.txt")
            try:
                if os.stat(info).st_size < 1024:
                    continue
                out.append((pathlib.Path(so), file_size(so)))
            except OSError:
                pass
    return out


def find_runtime(cutoff):
    out = []
    base = REPO / "runtime"
    if not base.is_dir():
        return out
    for p in base.iterdir():
        try:
            t = newest(p) if p.is_dir() else p.stat().st_mtime
        except OSError:
            continue
        if t and t < cutoff:
            out.append((p, tree_size(p) if p.is_dir() else file_size(str(p))))
    return out


def lane_parts(name: str, env):
    """Every directory a lane owns, including the deployed slot lane.py forgets."""
    return [lanemod.build_out(name), lanemod.barb_src(name), lanemod.write_dir(name),
            REPO / "ai" / lanemod.variant(name),
            env.engine_dir / "AI" / "Skirmish" / lanemod.short(name)]


def find_lanes(cutoff, env):
    mine = lanemod.name()
    claims = lanemod._claims()
    holders = {}
    for sess, ln in claims.items():
        holders.setdefault(ln, []).append(sess[:8])

    names = set()
    for p in lanemod.ENGINE.glob("build-*"):
        if p.resolve() != lanemod.SHARED_BUILD.resolve() and p.is_dir():
            names.add(p.name[len("build-"):])
    skirmish = env.engine_dir / "AI" / "Skirmish"
    if skirmish.is_dir():
        for p in skirmish.iterdir():
            if p.is_dir() and p.name.startswith(lanemod.BASE_SHORT) and p.name != lanemod.BASE_SHORT:
                names.add(p.name[len(lanemod.BASE_SHORT):])
    for p in (REPO / "matches").glob("_engine-*"):
        if p.is_dir():
            names.add(p.name[len("_engine-"):])
    names.discard("")
    names.discard(mine)

    out = []
    for n in sorted(names):
        parts = [p for p in lane_parts(n, env) if p.exists()]
        if not parts:
            continue
        t = max((newest(p) for p in parts), default=0.0)
        if t and t >= cutoff:
            continue
        out.append((n, parts, sum(tree_size(p) for p in parts), t, holders.get(n, [])))
    return out


def find_suffix(cutoff, suffix):
    out = []
    for base in (REPO / "matches", REPO / "tournaments"):
        for root, _dirs, files in os.walk(base, onerror=lambda e: None):
            for f in files:
                if not f.endswith(suffix):
                    continue
                p = os.path.join(root, f)
                try:
                    st = os.stat(p)
                except OSError:
                    continue
                if st.st_mtime < cutoff:
                    out.append((pathlib.Path(p), file_size(p)))
    return out


def find_records(cutoff):
    out = []
    for base in (REPO / "matches", REPO / "tournaments"):
        if not base.is_dir():
            continue
        for p in base.iterdir():
            if not p.is_dir() or p.name.startswith("_"):
                continue
            t = newest(p)
            if t and t < cutoff:
                out.append((p, tree_size(p)))
    return out


def rm(p: pathlib.Path) -> None:
    if p.is_dir():
        shutil.rmtree(p, ignore_errors=True)
    else:
        try:
            p.unlink()
        except OSError:
            pass


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("categories", nargs="*",
                    choices=["dupes", "runtime", "lanes", "replays", "records"],
                    help="what to act on (default: report all)")
    ap.add_argument("--days", type=float, default=3.0,
                    help="an item is stale when nothing in it has changed for this "
                         "long (default 3)")
    ap.add_argument("--apply", action="store_true", help="actually delete")
    args = ap.parse_args()

    if args.apply:
        n = engines_running()
        if n:
            raise SystemExit(f"{n} spring process(es) are running -- a match in flight "
                             f"writes into these directories. Refusing.")

    env = bar_env.load()
    cutoff = time.time() - args.days * 86400
    want = args.categories or ["dupes", "runtime", "lanes", "replays", "records"]
    total = 0

    if "dupes" in want:
        items = find_dupes()
        size = sum(s for _, s in items)
        total += size
        print("dupes    %6.1f GB  %d stdout.txt beside an intact infolog.txt"
              % (size / GB, len(items)))
        if args.apply and args.categories:
            for p, _ in items:
                rm(p)
            print("         deleted")

    if "runtime" in want:
        items = find_runtime(cutoff)
        size = sum(s for _, s in items)
        total += size
        print("runtime  %6.1f GB  %d scratch dirs/logs idle >%.3g days"
              % (size / GB, len(items), args.days))
        if args.apply and args.categories:
            for p, _ in items:
                rm(p)
            print("         deleted")

    if "lanes" in want:
        items = find_lanes(cutoff, env)
        size = sum(s for _, _, s, _, _ in items)
        total += size
        print("lanes    %6.1f GB  %d lanes idle >%.3g days (this session's '%s' is never listed)"
              % (size / GB, len(items), args.days, lanemod.name() or "(shared)"))
        for n, parts, s, t, held in sorted(items, key=lambda x: -x[2]):
            age = (time.time() - t) / 86400 if t else 999
            print("    %-16s %5.2f GB  idle %5.1f d  %d dirs%s"
                  % (n, s / GB, age, len(parts),
                     "  claimed by " + ",".join(held) if held else ""))
        if args.apply and args.categories:
            claims = lanemod._claims()
            gone = {n for n, _, _, _, _ in items}
            lanemod._write_claims({k: v for k, v in claims.items() if v not in gone})
            for _n, parts, _s, _t, _h in items:
                for p in parts:
                    rm(p)
            print("         deleted")

    if "replays" in want:
        items = find_suffix(cutoff, ".sdfz")
        size = sum(s for _, s in items)
        total += size
        print("replays  %6.1f GB  %d demos older than %.3g days"
              % (size / GB, len(items), args.days))
        if args.apply and args.categories:
            for p, _ in items:
                rm(p)
            print("         deleted")

    if "records" in want:
        items = find_records(cutoff)
        size = sum(s for _, s in items)
        total += size
        print("records  %6.1f GB  %d match/tournament dirs older than %.3g days"
              % (size / GB, len(items), args.days))
        if args.apply and args.categories:
            for p, _ in items:
                rm(p)
            print("         deleted")

    print("-" * 60)
    print("         %6.1f GB total%s" % (total / GB, "" if args.apply else " (nothing deleted)"))
    if "records" in want and ("dupes" in want or "replays" in want):
        print("         (categories overlap: dupes and replays sit INSIDE records)")
    try:
        free = shutil.disk_usage(REPO).free
        print("         %6.1f GB free on the drive now" % (free / GB))
    except OSError:
        pass
    if not args.apply:
        print("\nAdd --apply and name the categories to delete, e.g.")
        print("  python tools/reclaim.py --apply dupes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
