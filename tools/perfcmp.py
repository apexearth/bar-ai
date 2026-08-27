"""Compare `apex: perf sec` totals between two runs over the SAME game-minute
window. frametime.py sums a whole run, which cannot compare a 15-minute match
against a 26-minute one -- and every section here grows with base size."""
import re
import sys
from pathlib import Path

LINE = re.compile(
    r"\[f=(\d+)\].*apex: perf sec (\S+) calls=(\d+) totalMs=([\d.]+) maxMs=([\d.]+)")


def read(path, lo, hi):
    acc = {}
    for ln in Path(path).read_text(errors="ignore").splitlines():
        m = LINE.search(ln)
        if not m:
            continue
        mins = int(m.group(1)) / 1800.0
        if not (lo <= mins < hi):
            continue
        name = m.group(2)
        a = acc.setdefault(name, [0, 0.0, 0.0])
        a[0] += int(m.group(3))
        a[1] += float(m.group(4))
        a[2] = max(a[2], float(m.group(5)))
    return acc


def infolog(d):
    p = Path(d)
    return p if p.is_file() else p / "infolog.txt"


def main():
    a, b = sys.argv[1], sys.argv[2]
    lo = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    hi = float(sys.argv[4]) if len(sys.argv) > 4 else 15.0
    A, B = read(infolog(a), lo, hi), read(infolog(b), lo, hi)
    print(f"minutes [{lo}, {hi})   A={a}   B={b}")
    print(f"{'section':22} {'A calls':>8} {'A us/call':>10} "
          f"{'B calls':>8} {'B us/call':>10} {'delta':>8}")
    for k in sorted(set(A) | set(B),
                    key=lambda k: -(A.get(k, [0, 0, 0])[1])):
        ca, ta, _ = A.get(k, [0, 0.0, 0.0])
        cb, tb, _ = B.get(k, [0, 0.0, 0.0])
        ua = (ta * 1000.0 / ca) if ca else 0.0
        ub = (tb * 1000.0 / cb) if cb else 0.0
        d = f"{(ub / ua - 1) * 100:+.0f}%" if (ua and ub) else "-"
        if ta < 20 and tb < 20:
            continue
        print(f"{k:22} {ca:8d} {ua:10.0f} {cb:8d} {ub:10.0f} {d:>8}")


main()
