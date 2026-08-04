"""How fast each side claims metal spots, minute by minute.

Averages the per-2-minute mex count across every game in a run, so a single
unlucky game does not dominate. Also reports the per-minute CLAIM RATE, which is
what "they got theirs and we didn't" actually means -- a gap in the totals can
come from starting slower or from stalling later, and those want different fixes.

    python tools/mex_race.py <tournament-or-match-dir> [more dirs...]
"""
import collections
import pathlib
import re
import sys


def read(root: pathlib.Path):
    logs = ([root / "infolog.txt"] if (root / "infolog.txt").exists()
            else sorted(root.rglob("infolog.txt")))
    # frame -> side -> [per-game team totals]
    acc = collections.defaultdict(lambda: collections.defaultdict(list))
    games = 0
    for log in logs:
        txt = log.read_text("utf-8", errors="replace")
        per = collections.defaultdict(lambda: collections.defaultdict(float))
        seen = False
        for m in re.finditer(r"BARAI_STATS\] (.*)", txt):
            d = {}
            for tok in m.group(1).split():
                k, _, v = tok.partition("=")
                d[k] = v
            if "ally" not in d or "mex" not in d:
                continue
            seen = True
            side = "apex" if d["ally"] == "0" else "stable"
            per[int(float(d["frame"]))][side] += float(d["mex"])
        if not seen:
            continue
        games += 1
        for f, sides in per.items():
            for side, n in sides.items():
                acc[f][side].append(n)
    return acc, games


for arg in sys.argv[1:] or [None]:
    if arg is None:
        print(__doc__)
        break
    root = pathlib.Path(arg)
    acc, games = read(root)
    if not acc:
        print(f"{root.name}: no telemetry")
        continue
    print(f"\n{root.name}  ({games} game(s))   mean mexes held, and claims/min")
    print(f"{'min':>4}{'apex':>8}{'stable':>8}{'diff':>7}   {'apex/min':>9}{'stable/min':>11}")
    prev = {}
    for f in sorted(acc):
        a = acc[f]["apex"]
        s = acc[f]["stable"]
        # only minutes where MOST games still report, else a dead team drags it
        if len(a) < games * 0.6 or len(s) < games * 0.6:
            continue
        am, sm = sum(a) / len(a), sum(s) / len(s)
        mins = f / 1800
        dt = mins - prev.get("t", 0)
        ar = (am - prev.get("a", 0)) / dt if dt > 0 else 0
        sr = (sm - prev.get("s", 0)) / dt if dt > 0 else 0
        prev = {"t": mins, "a": am, "s": sm}
        flag = "  <-- we stall" if ar < sr * 0.7 and mins > 3 else ""
        print(f"{mins:>4.0f}{am:>8.1f}{sm:>8.1f}{am - sm:>7.1f}   {ar:>9.1f}{sr:>11.1f}{flag}")
