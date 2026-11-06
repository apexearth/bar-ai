#!/usr/bin/env python3
"""Air over a game's life, both sides, in 10-minute buckets: what each side built, the air share of what each side
built, the planes alive, and our strikes (size, escort, survival, how many reached what they needed).

    python tools/airstory.py <match|tournament> [...] [--bucket 10]

Answers his 11-05 list: do we keep making air late, are the waves big enough for their AA, do bombers fly with no
fighters, do we have fighters when their big air comes. Our side and theirs read from script.txt (airaudit.ours).
"""
from __future__ import annotations

import argparse
import re
from collections import defaultdict
from pathlib import Path

import airaudit

KV = re.compile(r"(\w+)=(\S+)")
FR = re.compile(r"\[f=(\d+)\]")
MIN = re.compile(r"\[(\d+(?:\.\d+)?)m t(\d+)\]")


def matches(paths):
    for p in map(Path, paths):
        if (p / "infolog.txt").exists():
            yield p
        else:
            yield from sorted(x.parent for x in p.glob("matches/*/result.json"))


def story(m: Path, B: int, acc: dict):
    us = airaudit.ours(m)
    side = lambda t: "us" if t in us else "them"  # noqa: E731
    alive = defaultdict(int)          # (side, class) -> alive now
    last_bucket = -1

    def snap(b):
        for s in ("us", "them"):
            acc[(b, s, "aliveF")].append(alive[(s, "fighter")])
            acc[(b, s, "aliveStrike")].append(alive[(s, "bomber")] + alive[(s, "gunship")])
    with open(m / "infolog.txt", encoding="utf-8", errors="replace") as f:
        for line in f:
            fm = FR.search(line)
            if not fm:
                continue
            fr = int(fm.group(1))
            b = int(fr / 1800 // B)
            while last_bucket < b - 1:
                last_bucket += 1
                snap(last_bucket)
            if "[BARAI_PROD]" in line:
                kv = dict(KV.findall(line))
                s = side(int(kv.get("team", -1)))
                c = airaudit.cls(kv["unit"])
                cost = float(kv.get("cost", 0))
                acc[(b, s, "allM")].append(cost)
                if c in ("bomber", "gunship", "fighter"):
                    acc[(b, s, "airM")].append(cost)
                    acc[(b, s, c)].append(1)
                    alive[(s, c)] += 1
            elif "[BARAI_DEATH]" in line:
                kv = dict(KV.findall(line))
                c = airaudit.cls(kv.get("unit", ""))
                if c in ("bomber", "gunship", "fighter"):
                    s = side(int(kv.get("team", -1)))
                    alive[(s, c)] = max(0, alive[(s, c)] - 1)
            elif "apex: air strike --" in line:
                kv = dict(KV.findall(line))
                acc[(b, "us", "strikes")].append(1)
                acc[(b, "us", "strikeBombers")].append(float(kv.get("bombers", 0)))
                acc[(b, "us", "strikeNoEscort")].append(1 if float(kv.get("fighters", 0)) == 0 else 0)
                acc[(b, "us", "strikeEnemyAA")].append(float(kv.get("enemyAA", 0)))
            elif "apex: air run scored" in line:
                kv = dict(KV.findall(line))
                acc[(b, "us", "runSent")].append(float(kv.get("sent", 0)))
                acc[(b, "us", "runSurv")].append(float(kv.get("surv", 0)))
            elif "apex: bomb spread" in line:
                kv = dict(KV.findall(line))
                need, got = float(kv.get("need", 0)), float(kv.get("got", 0))
                if need > 0:
                    acc[(b, "us", "spreadShort")].append(1 if got < need else 0)
                    acc[(b, "us", "spreadNeed")].append(need)
                    acc[(b, "us", "spreadGot")].append(got)
    snap(last_bucket + 1)
    acc["games"].append(m.name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--bucket", type=int, default=10)
    a = ap.parse_args()
    acc = defaultdict(list)
    for m in matches(a.paths):
        story(m, a.bucket, acc)
    n = len(acc["games"])
    print("%d games, %d-minute buckets; per game per bucket (sums over our seats / their seats)" % (n, a.bucket))
    hdr = ("min", "games", "airM us", "share us", "airM them", "share them", "bomb us", "gun us", "ftr us",
           "bomb th", "gun th", "ftr th", "F alive us", "strike alive th", "strikes", "bombers/strike",
           "no escort", "their AA", "surv", "short of need")
    print("\t".join(hdr))
    buckets = sorted({k[0] for k in acc if isinstance(k, tuple)})
    for b in buckets:
        g = len(acc[(b, "us", "aliveF")]) or 1

        def s(side, key):
            return sum(acc[(b, side, key)]) / g

        def mean(key):
            v = acc[(b, "us", key)]
            return sum(v) / len(v) if v else float("nan")
        share = lambda side: s(side, "airM") / s(side, "allM") if s(side, "allM") else float("nan")  # noqa: E731
        row = ["%d-%d" % (b * a.bucket, (b + 1) * a.bucket), g, round(s("us", "airM")), "%.0f%%" % (100 * share("us")),
               round(s("them", "airM")), "%.0f%%" % (100 * share("them")),
               "%.1f" % s("us", "bomber"), "%.1f" % s("us", "gunship"), "%.1f" % s("us", "fighter"),
               "%.1f" % s("them", "bomber"), "%.1f" % s("them", "gunship"), "%.1f" % s("them", "fighter"),
               "%.1f" % mean("aliveF") if False else "%.1f" % (sum(acc[(b, "us", "aliveF")]) / g),
               "%.1f" % (sum(acc[(b, "them", "aliveStrike")]) / g),
               "%.1f" % s("us", "strikes"), "%.1f" % mean("strikeBombers"), "%.0f%%" % (100 * mean("strikeNoEscort")),
               "%.1f" % mean("strikeEnemyAA"), "%.2f" % mean("runSurv"), "%.0f%%" % (100 * mean("spreadShort"))]
        print("\t".join(str(x) for x in row))


if __name__ == "__main__":
    main()
