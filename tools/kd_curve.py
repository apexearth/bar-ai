"""K/D over game time, averaged across every game in a tournament.

Finds WHEN fight quality turns, which a single end-of-game K/D cannot show.

    python tools/kd_curve.py <tournament-dir> [more dirs...]
"""
import collections
import pathlib
import re
import sys


def curve(root: pathlib.Path):
    logs = ([root / "infolog.txt"] if (root / "infolog.txt").exists()
            else sorted(root.rglob("infolog.txt")))
    # frame -> side -> metric
    agg = collections.defaultdict(lambda: collections.defaultdict(lambda: collections.defaultdict(float)))
    games = 0
    for log in logs:
        txt = log.read_text("utf-8", errors="replace")
        seen = False
        for m in re.finditer(r"BARAI_STATS\] (.*)", txt):
            d = {}
            for tok in m.group(1).split():
                k, _, v = tok.partition("=")
                try:
                    d[k] = float(v)
                except ValueError:
                    d[k] = v
            if "ally" not in d:
                continue
            seen = True
            side = "apex" if int(d["ally"]) == 0 else "stable"
            f = int(d["frame"])
            for k in ("mKillReal", "mKillCheap", "mLostReal", "mLostCheap",
                      "armyReal", "metalProduced", "mT2"):
                agg[f][side][k] += d.get(k, 0)
        games += 1 if seen else 0
    return agg, games


for root in [pathlib.Path(a) for a in sys.argv[1:]] or [None]:
    if root is None:
        print(__doc__)
        break
    agg, games = curve(root)
    if not agg:
        print(f"{root.name}: no telemetry")
        continue
    print(f"\n{root.name}  ({games} games)   K/D is CUMULATIVE to that minute")
    print(f"{'min':>4}{'apexK/D':>9}{'stblK/D':>9}   {'apexArmy':>9}{'stblArmy':>9}"
          f"   {'apexT2':>9}{'stblT2':>9}")
    prev = {}
    for f in sorted(agg):
        a, s = agg[f]["apex"], agg[f]["stable"]
        al = a["mLostReal"] + a["mLostCheap"]
        sl = s["mLostReal"] + s["mLostCheap"]
        if not al or not sl:
            continue
        ak = (a["mKillReal"] + a["mKillCheap"]) / al
        sk = (s["mKillReal"] + s["mKillCheap"]) / sl
        # marginal K/D for this 2-minute window, which shows the turn far more
        # sharply than the running total
        dk = (a["mKillReal"] + a["mKillCheap"]) - prev.get("ak", 0)
        dl = al - prev.get("al", 0)
        marg = dk / dl if dl else 0
        prev = {"ak": a["mKillReal"] + a["mKillCheap"], "al": al}
        print(f"{f/1800:>4.0f}{ak:>9.2f}{sk:>9.2f}   {a['armyReal']:>9.0f}{s['armyReal']:>9.0f}"
              f"   {a['mT2']:>9.0f}{s['mT2']:>9.0f}   window={marg:.2f}")
