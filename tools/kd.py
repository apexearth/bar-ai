"""Fight quality across a tournament: K/D in metal, plus the economy it drives.

    python tools/kd.py <tournament-dir> [more dirs...]

Cumulative counters are read at EACH SIDE'S OWN last sample -- a dead team stops
reporting, so the global last frame contains only the survivor.
"""
import collections
import pathlib
import re
import sys

CUM = ("mKillReal", "mKillCheap", "mLostReal", "mLostCheap",
       "metalProduced", "mex", "mDefence", "mT2", "mT3",
       "mKillStatic", "mKillMobile", "mLostMobile", "jamT")


def read(log: pathlib.Path):
    rows = []
    for m in re.finditer(r"BARAI_STATS\] (.*)", log.read_text("utf-8", errors="replace")):
        d = {}
        for tok in m.group(1).split():
            k, _, v = tok.partition("=")
            try:
                d[k] = float(v)
            except ValueError:
                d[k] = v
        if "ally" in d:
            rows.append(d)
    return rows


def main() -> int:
    roots = [pathlib.Path(a) for a in sys.argv[1:]]
    if not roots:
        print(__doc__)
        return 2
    for root in roots:
        logs = ([root / "infolog.txt"] if (root / "infolog.txt").exists()
                else sorted(root.rglob("infolog.txt")))
        agg = collections.defaultdict(lambda: collections.defaultdict(float))
        games = 0
        for log in logs:
            rows = read(log)
            if not rows:
                continue
            games += 1
            by = collections.defaultdict(list)
            for r in rows:
                by[int(r["ally"])].append(r)
            for a, rs in by.items():
                own = max(r["frame"] for r in rs)
                fin = [r for r in rs if r["frame"] == own]
                side = "apex" if a == 0 else "stable"
                for k in CUM:
                    agg[side][k] += sum(r.get(k, 0) for r in fin)
        if not games:
            print(f"{root.name}: no telemetry")
            continue
        print(f"\n{root.name}  ({games} game(s))")
        print(f"  {'side':<8}{'K/D':>7}{'ARMY K/D':>10}{'byMobile':>10}{'byStatic':>10}"
              f"{'lostMob':>10}{'metal':>11}{'jam':>5}")
        for side in ("apex", "stable"):
            d = agg[side]
            kills = d["mKillReal"] + d["mKillCheap"]
            lost = d["mLostReal"] + d["mLostCheap"]
            kd = kills / lost if lost else 0
            # ARMY K/D: what our MOBILE units killed over what mobile units we
            # lost. The combined figure hides towers doing the work.
            akd = d["mKillMobile"] / d["mLostMobile"] if d["mLostMobile"] else 0
            print(f"  {side:<8}{kd:>7.2f}{akd:>10.2f}{d['mKillMobile']:>10.0f}"
                  f"{d['mKillStatic']:>10.0f}{d['mLostMobile']:>10.0f}"
                  f"{d['metalProduced']:>11.0f}{d['jamT']:>5.0f}")
        a, s = agg["apex"], agg["stable"]
        for label, key in (("metal", "metalProduced"), ("mex", "mex"), ("T2", "mT2")):
            if s[key]:
                print(f"    apex/stable {label}: {a[key]/s[key]:.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
