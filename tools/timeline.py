"""How a game DEVELOPED, not how it ended.

The dev gadget samples every 2 minutes; result.json carries every sample. Reading
only the last row is actively misleading -- the losing side has by then lost its
mexes, its army and its economy, so every number says "they had more stuff" no
matter what caused it. apexearth: "we lose ground, lose mexes, of course the
other team has way more stuff ... capture these values over time to get a real
understanding of how the game developed."

    python tools/timeline.py <match-dir>              one game
    python tools/timeline.py <tournament-dir> --mean  averaged across games

Prints per-side totals at each sample, and marks the first sample where a metric
crosses -- which is the moment worth explaining.
"""
import json
import sys
from pathlib import Path

FRAME_MIN = 1800.0

# What to show, and whether more is better for us.
COLS = [
    ("mex", "mexes"),
    ("metalProduced", "metalProd"),
    ("armyReal", "army"),
    ("mT2", "T2spend"),
    ("mT3", "T3spend"),
    ("mKillReal", "killed"),
    ("mLostReal", "lost"),
]


def games(root: Path):
    if (root / "result.json").exists():
        return [root]
    return sorted(p.parent for p in root.glob("**/result.json"))


def series(d: Path):
    """[(minute, ours{}, theirs{})] for one game."""
    r = json.loads((d / "result.json").read_text())
    specs = {t["team"]: t["spec"] for t in r["teams"]}
    ally = 0.0 if str(specs.get(0, "")).startswith("BARbApex") else 1.0

    by_frame = {}
    for row in r.get("stats", []):
        f = int(row["frame"])
        by_frame.setdefault(f, []).append(row)

    out = []
    for f in sorted(by_frame):
        rows = by_frame[f]
        ours = [x for x in rows if x.get("ally") == ally]
        theirs = [x for x in rows if x.get("ally") != ally]
        if not ours or not theirs:
            continue
        agg = lambda rs, k: sum(float(x.get(k, 0) or 0) for x in rs)
        out.append((f / FRAME_MIN,
                    {k: agg(ours, k) for k, _ in COLS},
                    {k: agg(theirs, k) for k, _ in COLS}))
    return out


def show(rows, title):
    print(f"\n{title}")
    head = f"{'min':>5}"
    for _, label in COLS:
        head += f"{label:>21}"
    print(head)
    print(f"{'':>5}" + "".join(f"{'apex / stock':>21}" for _ in COLS))
    crossed = {}
    for mins, a, b in rows:
        line = f"{mins:>5.0f}"
        for k, _ in COLS:
            line += f"{a[k]:>9,.0f} /{b[k]:>10,.0f}"
            # First sample where they overtake us on a "more is better" metric.
            if k not in ("lost",) and k not in crossed and b[k] > a[k] * 1.15 and b[k] > 0:
                crossed[k] = mins
        print(line)
    if crossed:
        print("\n  first sample where stock pulls 15% ahead:")
        for k, _ in COLS:
            if k in crossed:
                print(f"    {k:<14} at {crossed[k]:.0f} min")


def main():
    root = Path(sys.argv[1])
    mean = "--mean" in sys.argv
    gs = games(root)
    if not gs:
        print(f"no games under {root}")
        return
    if not mean:
        for d in gs[:1] if len(gs) == 1 else gs:
            show(series(d), d.name[:70])
        return

    # Average across games, sample by sample, over the samples they all reached.
    allser = [series(d) for d in gs]
    allser = [s for s in allser if s]
    n = min(len(s) for s in allser)
    rows = []
    for i in range(n):
        mins = sum(s[i][0] for s in allser) / len(allser)
        a = {k: sum(s[i][1][k] for s in allser) / len(allser) for k, _ in COLS}
        b = {k: sum(s[i][2][k] for s in allser) / len(allser) for k, _ in COLS}
        rows.append((mins, a, b))
    show(rows, f"{root.name} -- mean of {len(allser)} games, to the shortest ({n} samples)")


if __name__ == "__main__":
    main()
