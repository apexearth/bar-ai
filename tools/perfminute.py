"""Per-section AI time inside one game-minute window, all players summed.

The `apex: perf sec` / `apex: perf jobs` lines are per-minute deltas; frametime.py sums the whole run.
This prints the sections of the minutes asked, largest first, so the late-game bill can be read
directly. Usage: perfminute.py <match> <fromMin> [toMin] [--top N]
"""
import re
import sys
from pathlib import Path

FPS = 30 * 60

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    top = 30
    if "--top" in sys.argv:
        top = int(sys.argv[sys.argv.index("--top") + 1])
        args = [a for a in args if a != str(top)]
    path = Path(args[0])
    log = path / "infolog.txt" if path.is_dir() else path
    lo = float(args[1])
    hi = float(args[2]) if len(args) > 2 else lo
    sec_re = re.compile(r"\[f=(\d+)\].*apex: perf sec (\S+) calls=(\d+) totalMs=([0-9.]+) maxMs=([0-9.]+)")
    job_re = re.compile(r"\[f=(\d+)\].*apex: perf jobs (.*)")
    item_re = re.compile(r"(\S+)=([0-9.]+)/(\d+)/([0-9.]+)")
    tot, calls, mx = {}, {}, {}
    with open(log, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = sec_re.search(line)
            if m:
                minute = int(m.group(1)) / FPS
                if lo - 1 < minute <= hi:
                    k = m.group(2)
                    tot[k] = tot.get(k, 0.0) + float(m.group(4))
                    calls[k] = calls.get(k, 0) + int(m.group(3))
                    mx[k] = max(mx.get(k, 0.0), float(m.group(5)))
                continue
            m = job_re.search(line)
            if m:
                minute = int(m.group(1)) / FPS
                if lo - 1 < minute <= hi:
                    for it in item_re.finditer(m.group(2)):
                        k = "job:" + it.group(1)
                        tot[k] = tot.get(k, 0.0) + float(it.group(2))
                        calls[k] = calls.get(k, 0) + int(it.group(3))
                        mx[k] = max(mx.get(k, 0.0), float(it.group(4)))
    print("minutes %g-%g, all players: %-28s %10s %9s %8s %7s" % (lo, hi, "section", "totalMs", "calls", "avgUs", "maxMs"))
    for k in sorted(tot, key=lambda x: -tot[x])[:top]:
        c = calls[k] or 1
        print("  %-40s %10.0f %9d %8.0f %7.1f" % (k, tot[k], calls[k], tot[k] * 1000.0 / c, mx[k]))

if __name__ == "__main__":
    main()
