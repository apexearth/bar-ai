"""Are we getting better against BARb, win or lose? Minute-by-minute edges over time.

    python tools/progress.py                      # batches since the even bonus, normal games
    python tools/progress.py --games              # one line per game: where each one turned
    python tools/progress.py --all                # discovery games too
    python tools/progress.py --since 20261008 --bonus 0-50 --map Glacier
    python tools/progress.py --by day             # group by day instead of batch

For each finished game vs BARb (tournaments/*/matches/*), per minute, OUR side
divided by THEIRS (an "edge"; 1.00 = level, 1.20 = 20% ahead):
  eco    metal income that minute          energy  energy income that minute
  army   standing army metal (mobile, non-builder units produced minus lost)
  trade  metal killed / metal lost, cumulative
  dmg    damage dealt / damage taken, cumulative (his D%)
  mex    extractors standing
  land   map cells (256 elmos) nearer our standing buildings than theirs, within
         1500 of one -- territorial control (his 2026-10-08: we cede ground)
A game's edge at minute M exists only if the game lasted to M, so late columns
are read from the games that got there. Edges are medians over games. Each game
is read once and cached in runtime/progress/.

Why (his 2026-10-08): "we didn't win, but we did better that time" -- a win
count is one bit per game; the edges say where a game was won or lost and
whether a change moved the early game, the middle, or the end.
"""
import glob
import json
import math
import os
import re
import statistics
import sys
from collections import defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(REPO, "runtime", "progress")
FPM = 1800
MINUTES = (3, 5, 8, 10, 12, 15, 20, 25, 30)
VERSION = 2
CELL = 256.0
CLAIM_R = 1500.0

RE_WASTE = re.compile(r"\[BARAI_WASTE\] frame=(\d+) team=(\d+) mWaste=(\d+) mMade=(\d+) eWaste=(\d+) eMade=(\d+)")
RE_PROD = re.compile(r"\[BARAI_PROD\] team=(\d+) ally=(\d+) frame=(\d+) min=[\d.]+ unit=(\w+) cost=(\d+)")
RE_BUILD = re.compile(r"\[BARAI_BUILD\] team=(\d+) ally=(\d+) frame=(\d+)")
RE_BUILT_AT = re.compile(r"\[BARAI_BUILD\] team=(\d+) ally=\d+ frame=(\d+) min=[\d.]+ unit=(\w+) cost=\d+ x=(-?\d+) z=(-?\d+) uid=(\d+)")
RE_DIED_UID = re.compile(r"\[BARAI_DEATH\] frame=(\d+) .*? x=(-?[\d.]+) z=(-?[\d.]+) .*? uid=(\d+)")
MEX = re.compile(r"(mex|moho|mme)\d*$")
RE_DEATH = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\w+) cost=(\d+) .*? built=(\d) mob=(\d) atkteam=(-?\d+)")
RE_DMG = re.compile(r"\[BARAI_DMG\] frame=(\d+) team=(\d+) dm=(\d+) ds=(\d+) rm=(\d+) rs=(\d+)")
BUILDER = re.compile(r"(ck|cv|ca|ack|acv|aca|cs|ch|acsub|fark|consul|rectr|necro|nanotc|com|comlvl\d+)$")


def read_game(mdir):
    """Per-minute series for one match, or None if it is not a finished game vs BARb."""
    try:
        res = json.load(open(os.path.join(mdir, "result.json"), encoding="utf-8"))
        script = open(os.path.join(mdir, "script.txt"), encoding="utf-8", errors="replace").read()
        txt = open(os.path.join(mdir, "infolog.txt"), encoding="utf-8", errors="replace").read()
    except (OSError, ValueError):
        return None
    r = res.get("result") or {}
    if not r.get("valid", True) or r.get("reason") not in ("gameover", "timelimit"):
        return None
    barb_teams = set()
    for block in re.findall(r"\[ai\d+\]\s*\{(.*?)\}", script, re.S | re.I):
        tm = re.search(r"team=(\d+);", block, re.I)
        if tm and re.search(r"shortname=BARb;", block, re.I):
            barb_teams.add(int(tm.group(1)))
    if not barb_teams:
        return None
    ally = {}
    for m in RE_PROD.finditer(txt):
        ally[int(m.group(1))] = int(m.group(2))
    for m in RE_BUILD.finditer(txt):
        ally[int(m.group(1))] = int(m.group(2))
    barb_allies = {ally[t] for t in barb_teams if t in ally}
    if not barb_allies:
        return None

    def side(t):
        return 1 if ally.get(t, -1) in barb_allies else 0

    last = int(r.get("game_frames") or 0) // FPM
    n = last + 1
    made = defaultdict(dict)                  # team -> minute -> (mMade, eMade)
    for m in RE_WASTE.finditer(txt):
        made[int(m.group(2))][int(m.group(1)) // FPM] = (int(m.group(4)), int(m.group(6)))
    inc = [[[0.0] * n, [0.0] * n] for _ in range(2)]   # [m/e][side][minute]
    for t, by in made.items():
        if t not in ally:
            continue
        s = side(t)
        for mn in range(1, n):
            if mn in by and (mn - 1) in by:
                inc[0][s][mn] += (by[mn][0] - by[mn - 1][0]) / 60.0
                inc[1][s][mn] += (by[mn][1] - by[mn - 1][1]) / 60.0
    army_in = [[0.0] * n, [0.0] * n]
    for m in RE_PROD.finditer(txt):
        mn = min(int(m.group(3)) // FPM, n - 1)
        if not BUILDER.search(m.group(4)):
            army_in[side(int(m.group(1)))][mn] += int(m.group(5))
    army_out = [[0.0] * n, [0.0] * n]
    lost = [[0.0] * n, [0.0] * n]
    for m in RE_DEATH.finditer(txt):
        f, t, unit, cost, fin, mob, atk = (int(m.group(1)), int(m.group(2)), m.group(3), int(m.group(4)),
                                           m.group(5) == "1", m.group(6) == "1", int(m.group(7)))
        if not fin or t not in ally:
            continue
        mn = min(f // FPM, n - 1)
        if atk >= 0 and atk in ally and side(atk) == side(t):
            continue   # our own reclaim
        lost[side(t)][mn] += cost
        if mob and not BUILDER.search(unit):
            army_out[side(t)][mn] += cost
    dmg = defaultdict(dict)
    for m in RE_DMG.finditer(txt):
        dmg[int(m.group(2))][int(m.group(1)) // FPM] = (int(m.group(3)) + int(m.group(4)), int(m.group(5)) + int(m.group(6)))
    series = {k: [] for k in ("eco", "energy", "army", "trade", "dmg", "mex", "land")}
    land_mex(txt, side, n, series)
    standing = [0.0, 0.0]
    cl = [0.0, 0.0]
    for mn in range(n):
        for s in (0, 1):
            standing[s] = max(0.0, standing[s] + army_in[s][mn] - army_out[s][mn])
            cl[s] += lost[s][mn]
        dd = [[0, 0], [0, 0]]
        for t, by in dmg.items():
            if t not in ally:
                continue
            ks = [k for k in by if k <= mn]
            if ks:
                v = by[max(ks)]
                dd[side(t)][0] += v[0]
                dd[side(t)][1] += v[1]
        series["eco"].append(ratio(inc[0][0][mn], inc[0][1][mn]))
        series["energy"].append(ratio(inc[1][0][mn], inc[1][1][mn]))
        series["army"].append(ratio(standing[0], standing[1]))
        series["trade"].append(ratio(cl[1], cl[0], floor=500.0))
        series["dmg"].append(ratio(dd[0][0], dd[0][1], floor=20000.0))
    winners = " ".join(r.get("winner_specs") or [])
    hc = res.get("handicap")
    if isinstance(hc, list):
        hc = hc[0] if hc else None
    return {
        "v": VERSION, "match": os.path.basename(mdir.rstrip("/\\")),
        "tournament": os.path.basename(os.path.dirname(os.path.dirname(mdir.rstrip("/\\")))),
        "map": res.get("map", "?"), "bonus": hc, "minutes": round(r.get("game_minutes") or 0, 1),
        "result": "W" if "Apex" in winners else ("L" if "BARb" in winners else "D"),
        "explore": "apex: nn-explore t=" in txt,
        "series": series,
    }


def land_mex(txt, side, n, series):
    """Per minute: our/their standing extractors, and our/their claimed land."""
    import numpy as np
    born = []      # (frame, side, x, z, uid, is_mex)
    died = {}
    span_x = span_z = 0.0
    for m in RE_BUILT_AT.finditer(txt):
        x, z = float(m.group(4)), float(m.group(5))
        born.append((int(m.group(2)), side(int(m.group(1))), x, z, m.group(6), bool(MEX.search(m.group(3)))))
        span_x, span_z = max(span_x, x), max(span_z, z)
    for m in RE_DIED_UID.finditer(txt):
        died[m.group(4)] = int(m.group(1))
        span_x, span_z = max(span_x, float(m.group(2))), max(span_z, float(m.group(3)))
    gx = np.arange(CELL / 2, span_x + CELL, CELL)
    gz = np.arange(CELL / 2, span_z + CELL, CELL)
    cells = np.array([(x, z) for x in gx for z in gz]) if len(gx) and len(gz) else np.zeros((0, 2))
    for mn in range(n):
        f = (mn + 1) * FPM
        stand = [b for b in born if b[0] <= f and not (b[4] in died and died[b[4]] <= f)]
        mex = [sum(1 for b in stand if b[1] == s and b[5]) for s in (0, 1)]
        series["mex"].append(ratio(mex[0], mex[1]))
        d = []
        for s in (0, 1):
            pts = np.array([(b[2], b[3]) for b in stand if b[1] == s])
            if len(pts) == 0 or len(cells) == 0:
                d.append(np.full(len(cells), np.inf))
                continue
            dd = ((cells[:, None, :] - pts[None, :, :]) ** 2).sum(-1).min(1)
            d.append(np.sqrt(dd))
        if len(cells):
            ours = int(((d[0] < d[1]) & (d[0] <= CLAIM_R)).sum())
            theirs = int(((d[1] < d[0]) & (d[1] <= CLAIM_R)).sum())
            series["land"].append(ratio(ours, theirs, floor=4.0))
        else:
            series["land"].append(None)


def ratio(a, b, floor=0.0):
    """Our/their, None while both sides are too small to compare."""
    if a + b <= floor or (a <= 0 and b <= 0):
        return None
    return (a + 1e-6) / (b + 1e-6) if b > 0 else 9.99


def load(mdir):
    key = os.path.join(CACHE, os.path.basename(os.path.dirname(os.path.dirname(mdir.rstrip("/\\"))))
                       + "__" + os.path.basename(mdir.rstrip("/\\")) + ".json")
    if os.path.exists(key):
        try:
            g = json.load(open(key, encoding="utf-8"))
            if g.get("v") == VERSION:
                return g
        except (OSError, ValueError):
            pass
    g = read_game(mdir)
    os.makedirs(CACHE, exist_ok=True)
    json.dump(g if g is not None else {"v": VERSION, "skip": True}, open(key, "w", encoding="utf-8"))
    return g


def med(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def fmt(x):
    return "  -  " if x is None else "%5.2f" % min(x, 9.99)


def turn(series):
    """Where the economy edge went: best minute and the edge at the end."""
    eco = [(i, x) for i, x in enumerate(series["eco"]) if x is not None and i >= 2]
    if not eco:
        return "-"
    i_best, best = max(eco, key=lambda p: p[1])
    return "eco best %.2f@%d -> %.2f@%d" % (best, i_best, eco[-1][1], eco[-1][0])


def collect(since="20261008-1232", include_explore=False, bonus=None, map_part=None):
    games = []
    for t in sorted(glob.glob(os.path.join(REPO, "tournaments", "*"))):
        if os.path.basename(t)[:len(since)] < since:
            continue
        for mdir in sorted(glob.glob(os.path.join(t, "matches", "*"))):
            if not os.path.exists(os.path.join(mdir, "result.json")):
                continue
            g = load(mdir)
            if g and not g.get("skip"):
                games.append(g)
    if not include_explore:
        games = [g for g in games if not g["explore"]]
    if bonus:
        lo, hi = (int(x) for x in bonus.split("-"))
        games = [g for g in games if g["bonus"] is not None and lo <= int(g["bonus"]) <= hi]
    if map_part:
        games = [g for g in games if map_part.lower() in g["map"].lower()]
    return games


def summary(games, by="batch", recent=60):
    """The dashboard's view: per group and metric, medians at MINUTES; the latest games."""
    groups = defaultdict(list)
    for g in games:
        groups[g["tournament"][:8] if by == "day" else g["tournament"][:13]].append(g)
    out = {"minutes": list(MINUTES), "groups": [], "games": []}
    for name, gs in sorted(groups.items()) + [("ALL", games)]:
        row = {"name": name, "n": len(gs),
               "w": sum(1 for g in gs if g["result"] == "W"), "l": sum(1 for g in gs if g["result"] == "L")}
        for metric in ("eco", "energy", "army", "trade", "dmg", "mex", "land"):
            row[metric] = [med([g["series"][metric][m] for g in gs if m < len(g["series"][metric])]) for m in MINUTES]
        out["groups"].append(row)
    for g in games[-recent:][::-1]:
        s = g["series"]
        out["games"].append({k: g[k] for k in ("tournament", "match", "map", "bonus", "result", "minutes", "explore")}
                            | {"eco": [s["eco"][m] if m < len(s["eco"]) else None for m in MINUTES],
                               "army": [s["army"][m] if m < len(s["army"]) else None for m in MINUTES],
                               "land": [s["land"][m] if m < len(s["land"]) else None for m in MINUTES],
                               "turn": turn(s)})
    return out


def main(argv):
    opt = lambda k, d=None: argv[argv.index(k) + 1] if k in argv else d
    since = opt("--since", "20261008-1232")
    games = collect(since, "--all" in argv, opt("--bonus"), opt("--map"))
    kind = "all games" if "--all" in argv else "normal games (no discovery)"
    print("vs BARb, %s, since %s: %d games   edge = ours / theirs, 1.00 = level" % (kind, since, len(games)))
    if not games:
        return 0
    if "--games" in argv:
        print("  %-8s %-13s %5s %3s %5s | eco at %s | army at %s | %s" % (
            "batch", "map", "bonus", "res", "min", "/".join(str(m) for m in (5, 10, 15)), "/".join(str(m) for m in (5, 10, 15)), "turn"))
        for g in games:
            s = g["series"]
            at = lambda k, m: fmt(s[k][m]) if m < len(s[k]) else "  -  "
            print("  %-8s %-13s %5s %3s %5.1f | %s %s %s | %s %s %s | %s" % (
                g["tournament"][4:13], g["map"][:13], g["bonus"], g["result"], g["minutes"],
                at("eco", 5), at("eco", 10), at("eco", 15), at("army", 5), at("army", 10), at("army", 15), turn(s)))
        return 0
    by = opt("--by", "batch")
    groups = defaultdict(list)
    for g in games:
        groups[g["tournament"][:8] if by == "day" else g["tournament"][:13]].append(g)
    for metric in ("eco", "army", "land", "mex", "trade", "dmg", "energy"):
        print("\n%s edge (median over games that reached the minute)" % metric)
        print("  %-14s %4s %7s | %s" % ("group", "n", "W-L-D", " ".join("m%-4d" % m for m in MINUTES)))
        rows = sorted(groups.items()) + [("ALL", games)]
        for name, gs in rows:
            w = sum(1 for g in gs if g["result"] == "W")
            l = sum(1 for g in gs if g["result"] == "L")
            d = len(gs) - w - l
            cells = []
            for m in MINUTES:
                cells.append(fmt(med([g["series"][metric][m] for g in gs if m < len(g["series"][metric])])))
            print("  %-14s %4d %7s | %s" % (name, len(gs), "%d-%d-%d" % (w, l, d), " ".join(cells)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
