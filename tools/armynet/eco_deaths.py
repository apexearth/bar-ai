#!/usr/bin/env python3
"""Who removed each economy building in a recording: an enemy, its own side (an upgrade, a reclaim, a self-destruct),
or nobody recorded.

    python tools/armynet/eco_deaths.py <orders.txt.gz>...
"""
import collections
import gzip
import re
import sys

ECO = re.compile(r"^(arm|cor|leg)\w*(mex|moho|sol|win|tide|fus|geo|makr|mmkr)", re.I)


def main(a):
    for path in a:
        names, ally = {}, {}
        counts = collections.Counter()
        for ln in gzip.open(path, "rt", errors="replace"):
            p = ln.split()
            if not p:
                continue
            if p[0] == "D":
                names[int(p[1])] = p[2]
            elif p[0] == "T":
                ally[int(p[1])] = int(p[2])
            elif p[0] == "K":
                d, t, at = int(p[3]), int(p[4]), int(p[9])
                n = names.get(d, "")
                if not ECO.search(n):
                    continue
                kind = "extractor" if re.search("mex|moho", n) else "other eco"
                who = "none" if at < 0 else ("own side" if ally.get(at, -1) == ally.get(t, -2) else "enemy")
                counts[(kind, who)] += 1
        print(path.split("/")[-2][:45], dict(counts))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
