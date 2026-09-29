"""T1 ground units ordered after the player's first T2 land plant stood.

    python tools/t1after.py <log|dir> [...]

His ruling (2026-09-27): no T1 army once T2 stands, fodder included. Reads the
decide lines whose asker is a T1 land plant and counts what they produced
after the first advanced land plant finished (`latency <plant> done`).
"""
import os
import re
import sys

T1_LAND = {"armlab", "armvp", "armhp", "corlab", "corvp", "corhp", "leglab", "legvp", "leghp"}
T2_LAND = {"armalab", "armavp", "coralab", "coravp", "legalab", "legavp"}
BUILDERS = re.compile(r"(ck|cv|ca|rectr|necro|rezbot|com|cs|ch|fark|twitch|nanotc)")

RE_FRAME = re.compile(r"\[f=(\d+)\]")
RE_DONE = re.compile(r"apex: latency (\w+) done=")
RE_DECIDE = re.compile(r"apex: decide t=\d+ (\w+) #\d+ -> produce:(\w+)")


def logs_in(path):
    if os.path.isfile(path):
        return [path]
    out = []
    for root, _dirs, files in os.walk(path):
        out += [os.path.join(root, f) for f in files if re.fullmatch(r"apex-t\d+\.log", f)]
    return sorted(out)


def scan(path):
    t2_at = None
    after = {}
    before = 0
    frame = 0
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            f = RE_FRAME.search(line)
            if f and int(f.group(1)) > 0:
                frame = int(f.group(1))
            d = RE_DONE.search(line)
            if d and d.group(1) in T2_LAND and t2_at is None:
                t2_at = frame
                continue
            p = RE_DECIDE.search(line)
            if not p or p.group(1) not in T1_LAND or BUILDERS.search(p.group(2)):
                continue
            if t2_at is None:
                before += 1
            else:
                after[p.group(2)] = after.get(p.group(2), 0) + 1
    return t2_at, before, after


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    for a in argv:
        for p in logs_in(a):
            t2_at, before, after = scan(p)
            when = f"{t2_at / 1800.0:.1f}m" if t2_at is not None else "never"
            top = " ".join(f"{k}={v}" for k, v in sorted(after.items(), key=lambda kv: -kv[1])[:5])
            print(f"{os.path.basename(p)}  T2 land @{when}  T1 army before={before}"
                  f" after={sum(after.values())}  {top}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
