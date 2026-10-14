#!/usr/bin/env python3
"""The siege timeline of a match: what fortifications we knew, each siege decision, the squad, the outcome.

    python tools/siege.py <match|tournament> [...] [--census]

Reads the apex lines of manager/military/nnsiege.as and the C++ fort census / siege squad
(unit/enemy/FortCensus.cpp, task/fighter/SiegeTask.cpp):
  apex: fort-census   clusters of their known guns, the three richest (once a minute per AI)
  apex: nnsiege       the NO/SIEGE decision on the best-priced cluster
  apex: siege start / look / end, apex: siege-squad (C++), apex: nnsiege-done
--census also prints every fort-census line.
"""
import glob
import os
import re
import sys

import decisions

FRAME = re.compile(r"\[f=(\d+)\]")
SCHEMA = re.compile(r"apex: nnsiege-schema v\d+ state=\S+ siege=(\S+) opt=")
ROW = re.compile(r"apex: nnsiege t=(\d+) f=\d+ why=\S+ rule=(\S+) ex=(\d) trust=(\S+) \| \S+ \| (\S+) \| (.*?) \| chosen=(-?\d+)")
CENSUS = re.compile(r"apex: fort-census t=(\d+) forts=(\d+) guns=(\d+)")
SHOW = ("worthM", "forceM", "ratio", "gunN", "gunHD", "reach", "shieldN", "jamN", "fortM", "ecoM", "routeM",
        "haveM", "homeD", "fwd")
EVENTS = ("apex: siege start", "apex: siege end", "apex: siege look", "apex: siege-squad", "apex: nnsiege-done",
          "apex: siege-stat")


def files_of(match):
    out = [os.path.join(match, "infolog.txt")]
    out += sorted(glob.glob(os.path.join(match, "apex-t*.log")))
    return [f for f in out if os.path.isfile(f)]


def stamp(frame):
    s = frame // 30
    return "%2d:%02d" % (s // 60, s % 60)


def read(match, census):
    keys = None
    seen = set()
    rows = []
    last_stat = {}
    nforts = {}
    for path in files_of(match):
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if "apex: " not in line or ("siege" not in line and "fort-census" not in line):
                    continue
                i = line.find("apex: ")
                body = line[i:].rstrip()
                if body in seen:
                    continue   # infolog repeats what the per-AI logs already hold
                seen.add(body)
                fm = FRAME.search(line)
                f = int(fm.group(1)) if fm else -1
                m = SCHEMA.search(body)
                if m:
                    keys = m.group(1).split(",")
                    continue
                m = ROW.search(body)
                if m:
                    t, rule, ex, trust, own, opts, chosen = m.groups()
                    vals = dict(zip(keys or [], own.split(",")))
                    pick = ["NO", "SIEGE"][int(chosen)] if chosen in ("0", "1") else chosen
                    rows.append((f, "t%s decide rule=%s pick=%s ex=%s trust=%s  %s" % (
                        t, rule, pick, ex, trust,
                        " ".join("%s=%s" % (k, vals[k]) for k in SHOW if k in vals))))
                    continue
                m = CENSUS.search(body)
                if m:
                    nforts[m.group(1)] = (int(m.group(2)), int(m.group(3)))
                    if census:
                        rows.append((f, body[len("apex: "):]))
                    continue
                if body.startswith("apex: siege-stat"):
                    last_stat[body.split()[2]] = body
                    continue
                if body.startswith(EVENTS):
                    rows.append((f, body[len("apex: "):]))
    return rows, last_stat, nforts


def main(argv):
    census = "--census" in argv
    targets = [a for a in argv if not a.startswith("--")]
    if not targets:
        print(__doc__)
        return 2
    for match in decisions.match_dirs(targets):
        rows, stat, nforts = read(match, census)
        print("== %s" % os.path.basename(match.rstrip("/\\")))
        if not rows and not stat:
            print("  no siege lines (an AI without nnsiege.as, or no fortification ever seen)")
            continue
        for t, (nf, ng) in sorted(nforts.items()):
            print("  last census %s: forts=%d guns=%d" % (t, nf, ng))
        for f, text in sorted(rows, key=lambda r: r[0]):
            print("  %s %s" % (stamp(f) if f >= 0 else "  ?  ", text))
        for t in sorted(stat):
            print("  " + stat[t][len("apex: "):])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
