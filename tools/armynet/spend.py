#!/usr/bin/env python3
"""What each side spent its metal on, by kind and window ([BARAI_BUILD] lines: units started).

    python tools/armynet/spend.py <match-dir> [--to 10] [--every 5]
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import story  # noqa: E402

BUILD = re.compile(r"\[BARAI_BUILD\] team=(\d+) ally=\d+ frame=\d+ min=([\d.]+) unit=(\S+) cost=(\d+)")


def kind(name):
    c = story.category(name)
    if c in ("mex", "energy", "conv"):
        return c
    if c in ("def", "plant", "nano"):
        return c
    if name in story.BUILDERS:
        return "builder"
    return "army/other"


def main(a):
    md = Path(a[0])
    to = float(a[a.index("--to") + 1]) if "--to" in a else 10
    every = float(a[a.index("--every") + 1]) if "--every" in a else 5
    text = (md / "infolog.txt").read_text(errors="replace")
    spent = defaultdict(lambda: defaultdict(float))
    seen = set()
    for m in BUILD.finditer(text):
        if m.group(0) in seen:
            continue
        seen.add(m.group(0))
        t, mi, name, cost = int(m.group(1)), float(m.group(2)), m.group(3), int(m.group(4))
        if mi < to:
            spent[(t, int(mi // every))][kind(name)] += cost
    kinds = sorted({k for v in spent.values() for k in v})
    print("%-12s %s" % ("team window", " ".join("%10s" % k for k in kinds)))
    for key in sorted(spent):
        t, w = key
        print("t%d %3g-%-5g %s" % (t, w * every, (w + 1) * every, " ".join("%10.0f" % spent[key][k] for k in kinds)))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
