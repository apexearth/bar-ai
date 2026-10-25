"""How much air each version of our AI built, by version, from games against a non-Apex opponent (only there is "our
side" unambiguous, S16). Per game and seat: metal built into bombers, gunships and fighters by --minute (the
BARAI_STATS allBuilt dump nearest that frame), and that as a share of all metal built into army (mArmy).

    python tools/air_by_version.py [--minute 30] [--roots matches G:/bar-ai-archive/matches ...]"""
import argparse
import json
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import airaudit  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
STAT = re.compile(r"\[BARAI_STATS\] team=(\d+) ally=(\d+) reason=periodic frame=(\d+) .*?mArmy=(\d+)")
BUILT = re.compile(r" allBuilt=(\S+)")
KINDS = ("bomber", "gunship", "fighter")
BY_DATE = "--by-date" in sys.argv
PAIRS = "--pairs" in sys.argv


def game(d: Path, minute: float):
    rj = d / "result.json"
    log = d / "infolog.txt"
    if not (rj.exists() and log.exists()):
        return []
    try:
        payload = json.loads(rj.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    teams = [t for t in payload.get("teams", []) if not t.get("extra")]
    ours = [t for t in teams if str(t.get("shortName", "")).startswith("Apex")]
    if PAIRS:
        # two of our versions in one game: each side under its own version, so the game's conditions cancel
        if len(ours) != 2 or len(teams) != 2 or ours[0].get("spec") == ours[1].get("spec"):
            return []
        out = []
        for t in ours:
            for row in side(log, t["team"], t.get("version", "?"), minute):
                out.append(row + (d.name,))
        return out
    if len(ours) != 1 or len(teams) != 2:
        return []
    return side(log, ours[0]["team"], ours[0].get("version", "?"), minute, payload)


def side(log: Path, ally: int, ver: str, minute: float, payload=None):
    if BY_DATE:
        import time as _t
        ver = _t.strftime("%Y-%m-%d", _t.localtime(log.stat().st_mtime))
    target = int(minute * 1800)
    best = {}
    for line in log.open(encoding="utf-8", errors="replace"):
        m = STAT.search(line)
        if not m or int(m[2]) != ally:
            continue
        f = int(m[3])
        if f > target + 1800:
            continue
        t = int(m[1])
        b = BUILT.search(line)
        if (t not in best) or (abs(f - target) < abs(best[t][0] - target)):
            best[t] = (f, int(m[4]), b[1] if b else "")
    rows = []
    for t, (f, army, built) in best.items():
        if f < target - 1800:
            continue
        air = defaultdict(float)
        for kv in built.split(","):
            if ":" not in kv:
                continue
            name, metal = kv.rsplit(":", 1)
            c = airaudit.cls(name)
            if c in KINDS:
                try:
                    air[c] += float(metal)
                except ValueError:
                    pass
        tot = sum(air.values())
        rows.append((ver, tot, tot / army if army > 0 else 0.0, air))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--minute", type=float, default=30.0)
    ap.add_argument("--by-date", action="store_true", help="group by the day each game was played, not by version")
    ap.add_argument("--roots", nargs="*", default=[str(REPO / "matches"), "G:/bar-ai-archive/matches"])
    ap.add_argument("--pairs", action="store_true", help="games between two of our versions, compared side by side")
    a = ap.parse_args()
    if PAIRS:
        return pairs(a)
    by = defaultdict(list)
    for root in a.roots:
        r = Path(root)
        if not r.is_dir():
            continue
        for d in r.iterdir():
            if d.is_dir() and not d.name.startswith("_"):
                for row in game(d, a.minute):
                    by[row[0]].append(row)
    print(f"air metal built by minute {a.minute:g}, per seat, vs a non-Apex opponent")
    print(f"{'version':16s} {'seats':>5s} {'median air':>10s} {'mean air':>9s} {'air/army':>8s} "
          f"{'no air':>6s}  bomber/gunship/fighter (mean)")

    def key(v):
        if BY_DATE:
            return (0, v)
        m = re.match(r"v(\d+)\.(\d+)\.(\d+)", v)
        return (0, int(m[1]), int(m[2]), int(m[3])) if m else (1, 0, 0, 0)

    for v in sorted(by, key=key):
        rows = by[v]
        if len(rows) < 4:
            continue
        tots = [r[1] for r in rows]
        shares = [r[2] for r in rows]
        none = sum(1 for x in tots if x <= 0)
        mk = [statistics.mean(r[3][k] for r in rows) for k in KINDS]
        print(f"{v:16s} {len(rows):5d} {statistics.median(tots):10.0f} {statistics.mean(tots):9.0f} "
              f"{statistics.median(shares):8.2f} {100.0 * none / len(rows):5.0f}%  "
              f"{mk[0]:.0f}/{mk[1]:.0f}/{mk[2]:.0f}")


def pairs(a):
    # per game: each version's mean air per seat; then per version pair, the games and how often each side built more
    games = defaultdict(lambda: defaultdict(list))
    for root in a.roots:
        r = Path(root)
        if not r.is_dir():
            continue
        for d in r.iterdir():
            if d.is_dir() and not d.name.startswith("_"):
                for ver, tot, share, _air, name in game(d, a.minute):
                    games[name][ver].append((tot, share))
    by = defaultdict(list)
    for name, sides in games.items():
        if len(sides) != 2:
            continue
        (va, ra), (vb, rb) = sorted(sides.items())
        ma = statistics.mean(x[0] for x in ra)
        mb = statistics.mean(x[0] for x in rb)
        sa = statistics.mean(x[1] for x in ra)
        sb = statistics.mean(x[1] for x in rb)
        by[(va, vb)].append((ma, mb, sa, sb))
    print(f"air metal per seat by minute {a.minute:g}, two of our versions in the same game")
    print(f"{'A':14s} {'B':14s} {'games':>5s} {'A air':>7s} {'B air':>7s} {'A share':>7s} {'B share':>7s} {'A more':>6s}")
    for (va, vb), rows in sorted(by.items(), key=lambda kv: -len(kv[1])):
        if len(rows) < 4:
            continue
        more = sum(1 for r in rows if r[0] > r[1])
        print(f"{va:14s} {vb:14s} {len(rows):5d} {statistics.median(r[0] for r in rows):7.0f} "
              f"{statistics.median(r[1] for r in rows):7.0f} {statistics.median(r[2] for r in rows):7.2f} "
              f"{statistics.median(r[3] for r in rows):7.2f} {more:4d}/{len(rows)}")


if __name__ == "__main__":
    main()
