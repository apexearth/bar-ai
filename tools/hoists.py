"""Tally builder elections by the rule that decided them (the decide line's why=).

    python tools/hoists.py <log dir | apex-tN.log ...> [--prev] [--by-team] [--why defjoin]

Per why: how many elections it decided, the jobs it gave (cat/kind), what it
beat (the 'over cat/kind v=' runner-up), and how often the job's own value was
BELOW the runner-up's -- a hoist overriding a higher-priced want. 'draw' and
'ladder' are the priced auction itself; everything else jumped the queue.
Reads `apex: decide` lines only (the `apex: nn` record repeats why=).
"""

from __future__ import annotations

import argparse
import re
import statistics
from collections import Counter, defaultdict
from pathlib import Path

DECIDE = re.compile(r"apex: decide t=(?P<team>\d+) (?P<con>\S+) #\d+ -> (?P<job>\S+?) v=(?P<v>-?[\d.]+)")
WHY = re.compile(r" why=(?P<why>\S+)")
OVER = re.compile(r" over (?P<over>\S+) v=(?P<ov>-?[\d.]+)")
AUCTION = {"draw", "ladder"}


def kind_of(job: str) -> str:
    return job.split(":", 1)[0]


def files_of(args_paths: list[str], prev: bool) -> list[Path]:
    out: list[Path] = []
    for a in args_paths:
        p = Path(a)
        if p.is_dir():
            for f in sorted(p.glob("apex-t*.log")):
                if prev or not f.name.endswith(".prev.log"):
                    out.append(f)
        elif p.exists():
            out.append(p)
    return out


class Tally:
    def __init__(self) -> None:
        self.n = 0
        self.jobs: Counter = Counter()
        self.over: Counter = Counter()
        self.ov: list[float] = []
        self.v: list[float] = []
        self.below = 0
        self.none = 0


SHADOW = re.compile(r"apex: shadow-defjoin t=\d+ fired=(\d+) priced=(\d+) noPrice=\d+ agree=(\d+) "
                    r"disagree=\d+ hoistV=[\d.]+ joinV=([\d.]+) shadowV=([\d.]+) byKind=(\S+)")
EX = re.compile(r" ex\d=(\S+ \S+)")


class Shadow:
    def __init__(self) -> None:
        self.fired = self.priced = self.agree = 0
        self.joinV = self.shadowV = 0.0
        self.kinds: Counter = Counter()
        self.ex: list[str] = []

    def add(self, line: str) -> None:
        m = SHADOW.search(line)
        if not m:
            return
        fired, priced, agree = int(m.group(1)), int(m.group(2)), int(m.group(3))
        self.fired += fired
        self.priced += priced
        self.agree += agree
        self.joinV += float(m.group(4)) * priced
        self.shadowV += float(m.group(5)) * priced
        if m.group(6) != "-":
            for kv in m.group(6).split(","):
                k, n = kv.rsplit(":", 1)
                self.kinds[k] += int(n)
        if len(self.ex) < 5:
            self.ex.extend(EX.findall(line)[:5 - len(self.ex)])

    def report(self) -> None:
        if self.fired == 0:
            return
        p = max(self.priced, 1)
        print(f"\nshadow-defjoin: fired {self.fired}, priced {self.priced}, the priced join still wins "
              f"{self.agree} ({100.0 * self.agree / p:.0f}%), mean join v {self.joinV / p:.2f} vs "
              f"shadow winner v {self.shadowV / p:.2f}")
        print(f"  lost to: {top(self.kinds, 6)}")
        for e in self.ex:
            print(f"  e.g. {e}")


def read(files: list[Path], only: str | None, by_team: bool, shadow: Shadow) -> dict:
    tallies: dict = defaultdict(Tally)
    for f in files:
        with f.open("r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if "apex: shadow-defjoin" in line:
                    shadow.add(line)
                    continue
                if "apex: decide" not in line:
                    continue
                m = DECIDE.search(line)
                if not m:
                    continue
                w = WHY.search(line)
                if not w:
                    continue
                why = w.group("why")
                if only and why != only:
                    continue
                key = (m.group("team"), why) if by_team else why
                t = tallies[key]
                t.n += 1
                t.jobs[kind_of(m.group("job"))] += 1
                v = float(m.group("v"))
                t.v.append(v)
                o = OVER.search(line)
                if o:
                    t.over[kind_of(o.group("over"))] += 1
                    ov = float(o.group("ov"))
                    t.ov.append(ov)
                    if v < ov:
                        t.below += 1
                else:
                    t.none += 1
    return tallies


def top(c: Counter, k: int = 3) -> str:
    return ", ".join(f"{name} {n}" for name, n in c.most_common(k))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--prev", action="store_true", help="include apex-tN.prev.log (an earlier game)")
    ap.add_argument("--by-team", action="store_true")
    ap.add_argument("--why", default=None, help="one rule only")
    ap.add_argument("--top", type=int, default=3)
    a = ap.parse_args()
    files = files_of(a.paths, a.prev)
    if not files:
        raise SystemExit("no apex-t*.log found")
    shadow = Shadow()
    tallies = read(files, a.why, a.by_team, shadow)
    total = sum(t.n for t in tallies.values())
    hoisted = sum(t.n for k, t in tallies.items() if (k[1] if a.by_team else k) not in AUCTION)
    print(f"{len(files)} logs, {total} elections, {hoisted} decided outside the draw "
          f"({100.0 * hoisted / max(total, 1):.1f}%)")
    print(f"{'why':<16}{'n':>7}{'%':>6}{'below':>7}{'medV':>9}{'medOverV':>10}  jobs | beat")
    for key, t in sorted(tallies.items(), key=lambda kv: -kv[1].n):
        name = f"t{key[0]} {key[1]}" if a.by_team else key
        medv = statistics.median(t.v) if t.v else 0.0
        medo = statistics.median(t.ov) if t.ov else 0.0
        print(f"{name:<16}{t.n:>7}{100.0 * t.n / max(total, 1):>6.1f}{t.below:>7}{medv:>9.2f}{medo:>10.2f}"
              f"  {top(t.jobs, a.top)} | {top(t.over, a.top)}" + (f" | no-runner-up {t.none}" if t.none else ""))
    shadow.report()


if __name__ == "__main__":
    main()
