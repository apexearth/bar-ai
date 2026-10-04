"""Head-to-head readout of a tournament: per game, per side, how the economy,
army and constructors stood at fixed minutes, and who died when.

    python tools/h2h.py <tournament-dir> [--minutes 4 8 12 16 20]

Sides are labelled by AI spec (teams[] order is ally order), so a pairing
played both ways reads the same version in the same column.
"""
import argparse
import json
import sys
from pathlib import Path

CONS = ("armck", "corck", "armcv", "corcv", "legck", "legcv", "armca", "corca", "legca")


def at(stats, ally, m):
    rows = [r for r in stats if int(r.get("ally", -1)) == ally and r.get("reason") == "periodic"
            and abs(r.get("frame", 0) - m * 1800) < 300]
    return rows[0] if rows else None


def cell(r):
    if r is None:
        return "      dead/over      "
    uc = dict((kv.split(":")[0], int(kv.split(":")[1])) for kv in str(r.get("unitCount", "")).split(",") if ":" in kv)
    cons = sum(uc.get(k, 0) for k in CONS)
    eco = r.get("mInc", 0.0) + r.get("eInc", 0.0) / 60.0
    return f"eco{eco:5.0f} army{r.get('mArmy', 0) / 1000:5.1f}k mex{r.get('mexN', 0):3.0f} con{cons:3d}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tournament")
    ap.add_argument("--minutes", type=int, nargs="+", default=[4, 8, 12, 16, 20])
    a = ap.parse_args()
    games = sorted(Path(a.tournament).glob("matches/*/result.json"))
    tally = {}
    for p in games:
        r = json.loads(p.read_text("utf-8"))
        specs = [t["spec"] for t in r["teams"]]
        res = r["result"]
        win = [specs[w] for w in res.get("winners") or [] if w < len(specs)]
        for s in specs:
            tally.setdefault(s, [0, 0])
            tally[s][1] += 1
        for w in win:
            tally[w][0] += 1
        order = sorted(range(len(specs)), key=lambda i: specs[i])
        print(f"\n{p.parent.name[-40:]}  {res['game_minutes']:.1f} min  winner: {', '.join(win) or res['reason']}")
        stats = r.get("stats") or []
        for m in a.minutes:
            print(f"  {m:3d}m  " + "  |  ".join(f"{specs[i][5:11]} {cell(at(stats, i, m))}" for i in order))
    print("\nwins: " + ", ".join(f"{s} {w}/{n}" for s, (w, n) in sorted(tally.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
