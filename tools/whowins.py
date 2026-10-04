"""What separates the winner from the loser of a 1v1, minute by minute.

    python tools/whowins.py <tournament-dir>... [--minutes 4 8 12 16]

For every decided game: the winner's and the loser's army built (mArmy), army
metal lost and killed, economy (metal income + energy/60), extractors and
constructors, averaged at each minute. Same code on both sides of a mirror, so
whatever differs at minute 8-12 is what decides the game.
"""
import argparse
import json
import sys
from pathlib import Path

CONS = ("armck", "corck", "armcv", "corcv", "armca", "corca")
KEYS = ("army", "lost", "killed", "eco", "mex", "cons", "eStall%")


def row(stats, ally, m):
    rs = [r for r in stats if int(r.get("ally", -1)) == ally and r.get("reason") == "periodic"
          and abs(r.get("frame", 0) - m * 1800) < 300]
    if not rs:
        return None
    r = rs[0]
    uc = dict((kv.split(":")[0], int(kv.split(":")[1])) for kv in str(r.get("unitCount", "")).split(",") if ":" in kv)
    return {"army": r.get("mArmy", 0.0), "lost": r.get("mLostReal", 0.0), "killed": r.get("mKillReal", 0.0),
            "eco": r.get("mInc", 0.0) + r.get("eInc", 0.0) / 60.0, "mex": r.get("mexN", 0.0),
            "cons": float(sum(uc.get(k, 0) for k in CONS)),
            "eStall%": 100.0 * r.get("eStall", 0.0) / max(1.0, r.get("resSamp", 1.0))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--minutes", type=int, nargs="+", default=[4, 8, 12, 16])
    a = ap.parse_args()
    acc = {m: {"W": [], "L": []} for m in a.minutes}
    n = 0
    for d in a.dirs:
        for p in Path(d).glob("matches/*/result.json"):
            r = json.loads(p.read_text("utf-8"))
            w = r["result"].get("winners") or []
            if len(w) != 1:
                continue
            n += 1
            win = w[0]
            for m in a.minutes:
                rw, rl = row(r.get("stats") or [], win, m), row(r.get("stats") or [], 1 - win, m)
                if rw and rl:
                    acc[m]["W"].append(rw)
                    acc[m]["L"].append(rl)
    print(f"{n} decided games")
    print("min  side   " + "  ".join(f"{k:>8s}" for k in KEYS))
    for m in a.minutes:
        for side in ("W", "L"):
            rs = acc[m][side]
            if not rs:
                continue
            print(f"{m:3d}  {'winner' if side == 'W' else 'loser '} "
                  + "  ".join(f"{sum(x[k] for x in rs) / len(rs):8.0f}" for k in KEYS) + f"   n={len(rs)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
