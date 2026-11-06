#!/usr/bin/env python3
"""When metal is the binding resource and energy is to spare, what do our builders start? (his 11-05: "if you have
enough energy and you're completely out of metal, your number one priority should probably be that metal")

    python tools/metalfirst.py <match|tournament> [...]

A seat-minute is METAL-BOUND when the seat spends at least what it makes in metal (mPull >= 0.95 mInc) while energy
income runs at least 20% over energy pull. Every `apex: decide` election won in such a minute is counted by its
category/kind; the same for the other minutes, for comparison.
"""
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import airaudit

STATS = re.compile(r"\[BARAI_STATS\] team=(\d+) ally=\d+ reason=periodic frame=(\d+) (.*)")
DEC = re.compile(r"\[f=(\d+)\].*apex: decide t=(\d+) \S+ #\d+ -> ([a-z]+)/([a-z]+):(\S+) v=")


def matches(paths):
    for p in map(Path, paths):
        if (p / "infolog.txt").exists():
            yield p
        else:
            yield from sorted(x.parent for x in p.glob("matches/*/result.json"))


EX = defaultdict(list)


def main():
    bound_wins, free_wins = Counter(), Counter()
    bound_min = free_min = 0
    for m in matches(sys.argv[1:]):
        us = airaudit.ours(m)
        state = {}
        decides = []
        for line in open(m / "infolog.txt", encoding="utf-8", errors="replace"):
            if "[BARAI_STATS]" in line:
                x = STATS.search(line)
                if not x:
                    continue
                t, f = int(x.group(1)), int(x.group(2))
                if t not in us:
                    continue
                kv = dict(re.findall(r"(\w+)=([-\d.]+)", x.group(3)))
                try:
                    mi, mp = float(kv["mInc"]), float(kv["mPull"])
                    ei, ep = float(kv["eInc"]), float(kv["ePull"])
                except KeyError:
                    continue
                state[(t, f // 1800)] = (mp >= 0.95 * mi) and (mi > 1) and (ei >= 1.2 * ep)
            elif "apex: decide t=" in line:
                x = DEC.search(line)
                if x:
                    decides.append((int(x.group(1)) // 1800, int(x.group(2)), x.group(3) + "/" + x.group(4)))
        for (t, mi), b in state.items():
            if b:
                bound_min += 1
            else:
                free_min += 1
        for mi, t, what in decides:
            b = state.get((t, mi))
            if b is None:
                continue
            (bound_wins if b else free_wins)[what] += 1
            if b and what in ("energy/energy", "metal/mex") and len(EX[what]) < 6:
                EX[what].append((m.name[:12], mi, t))
    for name, c, n in (("METAL-BOUND, energy spare", bound_wins, bound_min), ("other minutes", free_wins, free_min)):
        tot = sum(c.values()) or 1
        print("%s: %d seat-minutes, %d elections" % (name, n, sum(c.values())))
        for k, v in c.most_common(12):
            print("   %5.1f%%  %s" % (100.0 * v / tot, k))


def show_examples(paths):
    for what, rows in EX.items():
        for g, mi, t in rows[:3]:
            for m in matches(paths):
                if m.name.startswith(g):
                    for line in open(m / "infolog.txt", encoding="utf-8", errors="replace"):
                        x = DEC.search(line)
                        if x and int(x.group(2)) == t and int(x.group(1)) // 1800 == mi and (x.group(3) + "/" + x.group(4)) == what:
                            print("  ", m.name[:20], mi, line.split("apex: ", 1)[1].strip()[:230])
                            break
                    break


if __name__ == "__main__":
    main()
    show_examples(sys.argv[1:])
