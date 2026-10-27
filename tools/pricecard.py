"""What each build was priced at, term by term, from `apex: pricecard` lines (decide.as PriceCard).

    python tools/pricecard.py <match-dir|infolog> [--team N] [--min-from M] [--min-to M] [--def NAME]

Per def that won or came second: how often, median value, gain, metal, every time charge, the net's multiplier and
`post` (value over gain/(m+t): a multiplier nothing names). The last column names the largest cost term and its share
of the whole bill -- a charge that dwarfs the build's own metal is the first thing to read.
"""
import argparse
import re
import statistics
from collections import defaultdict
from pathlib import Path

LINE = re.compile(r"\[f=0*(\d+)\].*?apex: pricecard t=(\d+) u=(\S+) why=(\S+) inc=(\d+) \| win (.*?) \| 2nd (.*)$")
PART = re.compile(r"(\S+?):(\S+) v=([0-9.]+) g=([-0-9.]+) m=(-?\d+) t=(-?\d+) \[walk(-?\d+) build(-?\d+) disp(-?\d+) "
                  r"lock(-?\d+) flow(-?\d+) risk(-?\d+) late(-?\d+) opp(-?\d+)\] nn=([0-9.]+) post=([0-9.]+)")
TERMS = ["m", "walk", "build", "disp", "lock", "flow", "risk", "late", "opp", "other"]


def parse(path, team, lo, hi):
    rows = defaultdict(lambda: defaultdict(list))
    for ln in open(path, encoding="utf-8", errors="replace"):
        m = LINE.search(ln.rstrip())
        if not m:
            continue
        if team is not None and int(m[2]) != team:
            continue
        mn = int(m[1]) / 1800.0
        if mn < lo or mn > hi:
            continue
        for role, txt in (("win", m[6]), ("2nd", m[7])):
            p = PART.search(txt)
            if not p:
                continue
            key = p[2] if p[2] != "-" else p[1]
            r = rows[key]
            r["role"].append(role)
            r["v"].append(float(p[3]))
            r["g"].append(float(p[4]))
            for name, idx in zip(TERMS, (5, 7, 8, 9, 10, 11, 12, 13, 14)):
                r[name].append(float(p[idx]))
            # what tCost holds that no named charge accounts for (a proposer's own term, a memo repricing)
            r["other"].append(float(p[6]) - sum(float(p[i]) for i in (7, 8, 9, 10, 11, 12, 13, 14)))
            r["nn"].append(float(p[15]))
            r["post"].append(float(p[16]))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("--team", type=int)
    ap.add_argument("--min-from", type=float, default=0)
    ap.add_argument("--min-to", type=float, default=1e9)
    ap.add_argument("--def", dest="only")
    a = ap.parse_args()
    p = Path(a.src)
    if p.is_dir():
        p = p / "infolog.txt"
    rows = parse(p, a.team, a.min_from, a.min_to)
    med = lambda xs: statistics.median(xs) if xs else 0.0
    print(f"{'def':14s} {'win':>4s} {'2nd':>4s} {'v':>8s} {'gain':>8s} " + " ".join(f"{t:>7s}" for t in TERMS)
          + f" {'nn':>6s} {'post':>6s}  largest")
    for d, r in sorted(rows.items(), key=lambda kv: -len(kv[1]["v"])):
        if a.only and d != a.only:
            continue
        meds = {t: med(r[t]) for t in TERMS}
        bill = sum(max(0.0, meds[t]) for t in TERMS) or 1.0
        big = max(TERMS, key=lambda t: meds[t])
        print(f"{d:14s} {r['role'].count('win'):4d} {r['role'].count('2nd'):4d} {med(r['v']):8.2f} {med(r['g']):8.2f} "
              + " ".join(f"{meds[t]:7.0f}" for t in TERMS)
              + f" {med(r['nn']):6.2f} {med(r['post']):6.2f}  {big} {100 * meds[big] / bill:.0f}%")


if __name__ == "__main__":
    main()
