"""At N economic power, which eco rung does the model actually buy?

    python tools/ecoladder.py <tournament|match dir|substring> [...]
        [--by power|metal|energy] [--bucket N] [--kind energy,convert,mexup]
        [--reactors] [--team-spec apex]

apexearth 2026-09-22: "You could probably write a script to show that at N
incomes, what eco would we build."

This reads the LOGS, it does not re-run the model.  Every number here was
produced by the AI in a real game:

  ``apex: bpgap ... mInc=``     metal income, per team, every 30 s
  ``apex: energy ... inc=``     energy income, same cadence
  ``apex: eta t=N P=``          EcoPowerM -- total economic power in metal/s
  ``apex: decide ... -> energy/energy:<def>``   the rung that WON an election
  ``apex: ebig``/``apex: epick``  the reactor-class market-vs-ETA disagreement

Each decision is joined to the most recent economic reading for the same team,
bucketed, and counted.  The result is the income -> rung curve: read down the
table and the ladder the AI is climbing is the sequence of column winners.

``--reactors`` prints the second table: for every election where both the
market (value) and the ladder (arrival time) named a reactor, who won and by
how much.  That is where a rung gets skipped.

``--why`` prints the third: the mean gain, metal cost, time cost and value each
def carried at the moment it won, and the same three per e/s of output.  A def
whose GAIN PER E/S rises with its size is being paid for being big.
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

FRAME = re.compile(r"\[f=(-?\d+)\]")
BPGAP = re.compile(r"\[f=(-?\d+)\].*\[[\d.]+m t(\d+)\] apex: bpgap .*\bmInc=(-?[\d.]+)")
ENERGY = re.compile(r"\[f=(-?\d+)\].*\[[\d.]+m t(\d+)\] apex: energy .*\binc=(-?\d+)")
ETAP = re.compile(r"\[f=(-?\d+)\].*apex: eta t=(\d+) P=(-?[\d.]+)")
DECIDE = re.compile(r"\[f=(-?\d+)\].*apex: decide t=(\d+) \S+ #\d+ -> "
                    r"([a-z]+)/([a-z]+)(?::(\S+))? v=(-?[\d.]+)"
                    r"(?: \(gain=(-?[\d.]+) m=(-?[\d.]+) t=(-?[\d.]+)\))?")
EBIG = re.compile(r"\[f=(-?\d+)\].*apex: ebig t=(\d+) \S+ #\d+ mkt=(\S+) eta=(\S+) \|([^|]*)\|")
EPICK = re.compile(r"\[f=(-?\d+)\].*apex: epick t=(\d+) \S+ mkt=(\S+) v=(-?[\d.]+) "
                   r"eta=(\S+) s=(-?\d+) mktS=(-?\d+) lat=(-?\d+) (\S+)")

KINDS = {
    "energy": ("energy", "energy"),
    "convert": ("energy", "convert"),
    "geo": ("energy", "geo"),
    "mex": ("metal", "mex"),
    "mexup": ("metal", "mexup"),
    "plant": ("produce", "plant"),
    "tech": ("produce", "tech"),
}

AXIS = {"power": "EcoPowerM m/s", "metal": "metal income m/s", "energy": "energy income e/s"}


def find_logs(key: str) -> list[Path]:
    p = Path(key)
    if p.is_dir():
        if (p / "infolog.txt").exists():
            return [p / "infolog.txt"]
        return sorted(p.rglob("infolog.txt"))
    for base in ("tournaments", "matches"):
        hits = sorted(d for d in (REPO / base).glob(f"*{key}*") if d.is_dir())
        if hits:
            out: list[Path] = []
            for h in hits:
                out.extend(sorted(h.rglob("infolog.txt")))
            if out:
                return out
    return []


class Track:
    """Latest reading of each economic axis, per team, walked forward in frame order."""

    def __init__(self) -> None:
        self.cur: dict[tuple[int, str], float] = {}

    def set(self, team: int, axis: str, v: float) -> None:
        self.cur[(team, axis)] = v

    def get(self, team: int, axis: str) -> float | None:
        return self.cur.get((team, axis))


# Three fields, because BAR states a generator's output three ways: a reactor
# has energymake, a solar has a NEGATIVE energyupkeep, a wind has windgenerator
# (its nameplate; the map's wind decides the rest).
MAKE_E_RE = (re.compile(r"\benergymake\s*=\s*([\d.]+)", re.I),
             re.compile(r"\benergyupkeep\s*=\s*-([\d.]+)", re.I),
             re.compile(r"\bwindgenerator\s*=\s*([\d.]+)", re.I))


def make_e(names: list[str]) -> dict[str, float]:
    """e/s each def generates, straight from the live game tree (never guessed)."""
    out: dict[str, float] = {}
    try:
        sys.path.insert(0, str(REPO / "tools"))
        import bar_env  # noqa: PLC0415
        import unitdef  # noqa: PLC0415
        tree = unitdef.Tree("game", bar_env.load().game_sdd)
    except Exception:  # noqa: BLE001
        return out
    for n in names:
        p = tree.find(n)
        if p is None:
            continue
        text = p.read_text(encoding="utf-8", errors="replace")
        for rx in MAKE_E_RE:
            m = rx.search(text)
            if m:
                out[n] = float(m.group(1))
                break
    return out


def bucket_of(v: float, width: float) -> float:
    return (int(v / width)) * width


def fmt_bucket(lo: float, width: float) -> str:
    return f"{lo:>7.0f}-{lo + width:<6.0f}"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("runs", nargs="+")
    ap.add_argument("--by", choices=("power", "metal", "energy"), default="power",
                    help="which economic axis to bucket on (default: EcoPowerM)")
    ap.add_argument("--bucket", type=float, default=0.0,
                    help="bucket width on that axis (default: 10 power / 10 metal / 500 energy)")
    ap.add_argument("--kind", default="energy,convert,mexup",
                    help="comma list of " + ",".join(KINDS))
    ap.add_argument("--reactors", action="store_true",
                    help="also print the market-vs-ETA reactor table")
    ap.add_argument("--why", action="store_true",
                    help="also print what each def was priced at when it won")
    ap.add_argument("--min-n", type=int, default=3,
                    help="drop buckets with fewer decisions than this")
    ap.add_argument("--top", type=int, default=4, help="defs shown per bucket")
    args = ap.parse_args()

    width = args.bucket or {"power": 10.0, "metal": 10.0, "energy": 500.0}[args.by]
    kinds = [k.strip() for k in args.kind.split(",") if k.strip()]
    for k in kinds:
        if k not in KINDS:
            print("unknown kind:", k, "-- have", ",".join(KINDS))
            return 2

    logs: list[Path] = []
    for key in args.runs:
        found = find_logs(key)
        if not found:
            print("no infolog found for", key)
        logs.extend(found)
    if not logs:
        return 1

    # (kind, bucket) -> def -> count
    picks: dict[tuple[str, float], Counter] = defaultdict(Counter)
    # bucket -> [total v, n] per kind, so a bucket with no winner still shows it was offered
    seen: Counter = Counter()
    # reactor table: (mkt, eta) -> [n, sum(mktS - etaS), n eta-wins]
    react: dict[tuple[str, str], list[float]] = defaultdict(lambda: [0.0, 0.0, 0.0])
    react_bucket: dict[float, Counter] = defaultdict(Counter)
    ebig_offered: dict[float, Counter] = defaultdict(Counter)
    ebig_eta: dict[tuple[float, str], list[float]] = defaultdict(lambda: [0.0, 0.0])
    # (kind, def) -> [n, gain, mCost, tCost, v]
    priced: dict[tuple[str, str], list[float]] = defaultdict(lambda: [0.0] * 5)
    games = 0

    for log in logs:
        try:
            text = log.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        games += 1
        tr = Track()
        for line in text.splitlines():
            if "apex: " not in line:
                continue
            m = BPGAP.search(line)
            if m:
                tr.set(int(m.group(2)), "metal", float(m.group(3)))
                continue
            m = ENERGY.search(line)
            if m:
                tr.set(int(m.group(2)), "energy", float(m.group(3)))
                continue
            m = ETAP.search(line)
            if m:
                tr.set(int(m.group(2)), "power", float(m.group(3)))
                continue
            m = DECIDE.search(line)
            if m:
                team = int(m.group(2))
                kind, cat, dname = m.group(3), m.group(4), m.group(5)
                for k in kinds:
                    if KINDS[k] != (kind, cat):
                        continue
                    if args.why and m.group(7) is not None:
                        row = priced[(k, dname or "(none)")]
                        row[0] += 1
                        row[1] += float(m.group(7))
                        row[2] += float(m.group(8))
                        row[3] += float(m.group(9))
                        row[4] += float(m.group(6))
                    v = tr.get(team, args.by)
                    if v is None:
                        break
                    b = bucket_of(v, width)
                    picks[(k, b)][dname or "(none)"] += 1
                    seen[b] += 1
                    break
                continue
            if not args.reactors:
                continue
            m = EPICK.search(line)
            if m:
                team = int(m.group(2))
                mkt, eta = m.group(3), m.group(5)
                etaS, mktS = float(m.group(6)), float(m.group(7))
                won = m.group(9)
                r = react[(mkt, eta)]
                r[0] += 1
                r[1] += mktS - etaS
                if won == "eta-wins":
                    r[2] += 1
                v = tr.get(team, args.by)
                if v is not None:
                    react_bucket[bucket_of(v, width)][
                        (eta if won == "eta-wins" else mkt)] += 1
                continue
            m = EBIG.search(line)
            if m:
                team = int(m.group(2))
                v = tr.get(team, args.by)
                if v is None:
                    continue
                b = bucket_of(v, width)
                ebig_offered[b][m.group(3)] += 1
                for tok in m.group(5).split():
                    if "=" not in tok:
                        continue
                    name, secs = tok.rsplit("=", 1)
                    try:
                        s = float(secs)
                    except ValueError:
                        continue
                    row = ebig_eta[(b, name)]
                    row[0] += s
                    row[1] += 1

    print(f"# ecoladder: {games} logs, bucketed by {AXIS[args.by]} in steps of {width:g}")
    print("# each cell is the def that WON that election, counted; read down for the ladder")
    for k in kinds:
        buckets = sorted(b for (kk, b) in picks if kk == k)
        if not buckets:
            continue
        print()
        print(f"== {k} ==")
        print(f"{'bucket':>15}  {'n':>5}  winners (share)")
        for b in buckets:
            c = picks[(k, b)]
            n = sum(c.values())
            if n < args.min_n:
                continue
            top = "  ".join(f"{d}:{cnt * 100 // n}%" for d, cnt in c.most_common(args.top))
            print(f"{fmt_bucket(b, width)}  {n:>5}  {top}")

    if args.why and priced:
        mke = make_e(sorted({d for (_k, d) in priced}))
        print()
        print("== what each def was priced at IN THE ELECTION IT WON ==")
        print("# gain/e/s rising with size is the growth premium paying for bigness")
        print(f"{'kind':<8}{'def':<14}{'n':>5}{'mkE':>8}{'gain':>10}{'mCost':>10}"
              f"{'tCost':>10}{'v*1e3':>8}{'gain/e/s':>10}{'cost/e/s':>10}")
        for (k, d), row in sorted(priced.items(), key=lambda kv: (kv[0][0], -kv[1][1])):
            n = row[0]
            if n < 1:
                continue
            e = mke.get(d, 0.0)
            per_g = f"{row[1] / n / e:>10.3f}" if e > 0 else f"{'-':>10}"
            per_c = f"{(row[2] + row[3]) / n / e:>10.1f}" if e > 0 else f"{'-':>10}"
            print(f"{k:<8}{d:<14}{int(n):>5}{e:>8.0f}{row[1] / n:>10.0f}"
                  f"{row[2] / n:>10.0f}{row[3] / n:>10.0f}{row[4] / n:>8.1f}"
                  f"{per_g}{per_c}")

    if args.reactors:
        print()
        print("== reactor class: what the ladder OFFERED, and its ETA in seconds ==")
        print(f"{'bucket':>15}  def                 mean ETA s     n   mkt picks")
        for b in sorted(ebig_offered):
            names = sorted({n for (bb, n) in ebig_eta if bb == b})
            mktc = ebig_offered[b]
            first = True
            for name in names:
                tot, n = ebig_eta[(b, name)]
                if n < args.min_n:
                    continue
                pick = ""
                if first:
                    pick = "  ".join(f"{d}:{c}" for d, c in mktc.most_common(3))
                    first = False
                print(f"{fmt_bucket(b, width) if pick else '':>15}  {name:<18}"
                      f"{tot / n:>10.0f}  {int(n):>5}   {pick}")
        print()
        print("== epick: market pick vs ETA pick (a tie goes to the market) ==")
        print(f"{'market':<14}{'eta':<14}{'n':>6}{'mean mktS-etaS':>16}{'eta-wins':>10}")
        for (mkt, eta), (n, dsum, wins) in sorted(react.items(), key=lambda kv: -kv[1][0]):
            print(f"{mkt:<14}{eta:<14}{int(n):>6}{dsum / n:>16.0f}{int(wins):>10}")
        if react_bucket:
            print()
            print("== the reactor actually taken, by bucket ==")
            for b in sorted(react_bucket):
                c = react_bucket[b]
                n = sum(c.values())
                if n < args.min_n:
                    continue
                print(f"{fmt_bucket(b, width)}  {n:>5}  "
                      + "  ".join(f"{d}:{cnt}" for d, cnt in c.most_common(args.top)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
