#!/usr/bin/env python3
"""One army-model game, explained (his 11-19: "break down into some more detail, like how much building/army metal
is lost/killed, a 3d view (time as 3rd dimension) of the map so you can see where units are over time and understand
where we're failing. I won't always be around to understand why we fail so you should work on rigging up better
evaluations of our performance").

    python tools/armynet/game_report.py <matches/armynet-watch-...> [--every 4]

Writes beside the match report.md (the text, also printed), then tools/armynet/timelapse.py's pictures: lane.png
(time against place on the A-B line), film-N.png (the map every minute with 60-s trails), timelapse.gif (--no-gif
skips it). Side A (team 0) is the model's army, side B (team 1) our AI's.

report.md: result; per side and 4-minute bucket, metal lost and killed by kind (army, builders, commander, economy,
defence, other buildings); extractors, income and army by minute; the battles (tools/battles.py) -- how many side A
entered outnumbered (its metal within 900 under two thirds of B's) and what they cost, the share of each side's
units that died standing still; the army's distance from home over time; and the moments that decided it (the
costliest battle, the largest swing in extractors, side A's army size against where it stood).
"""
import json
import math
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
import battles  # noqa: E402
import story  # noqa: E402

ECO = re.compile(r"^(arm|cor|leg)\w*(mex|moho|sol|win|tide|fus|geo|makr|mmkr)", re.I)
KINDS = ("army", "builders", "commander", "economy", "defence", "other")


def engine_dir(match):
    stamp = match.name.replace("armynet-watch-", "")
    for d in (REPO / "matches" / ("watch-armynet-engine-" + stamp), REPO / "matches" / ("_engine-armynet-watch-" + stamp)):
        if d.exists():
            return d
    return None


def unit_kinds(eng):
    kind = {}
    p = eng / "armynet_static.txt" if eng else None
    if p and p.exists():
        for ln in open(p, errors="replace"):
            s = ln.split()
            if s and s[0] == "D":
                name, cls, rng = s[2], s[3], float(s[7])
                if cls == "static":
                    kind[name] = "economy" if ECO.search(name) else ("defence" if rng > 0 else "other")
                elif cls == "builder":
                    kind[name] = "builders"
                elif cls == "com":
                    kind[name] = "commander"
                else:
                    kind[name] = "army"
    return kind


def kind_of(kinds, d):
    if d.unit in kinds:
        return kinds[d.unit]
    if not d.mob:
        return "economy" if ECO.search(d.unit) else "other"
    return "army"


def centre(units, costs):
    w = [(x, z, costs.get(n, 0)) for _u, n, x, z, _h in units]
    tot = sum(c for _, _, c in w)
    if tot <= 0:
        return None
    return sum(x * c for x, _, c in w) / tot, sum(z * c for _, z, c in w) / tot, tot


def main(a):
    match = Path(a[0])
    every = int(a[a.index("--every") + 1]) if "--every" in a else 4
    eng = engine_dir(match)
    res = json.loads((match / "result.json").read_text())
    r, stats = res.get("result") or {}, res.get("stats") or []
    text = (match / "infolog.txt").read_text(errors="replace")
    gl = eng / "barai-gadgets.log" if eng else None
    if gl and gl.exists():
        text += gl.read_text(errors="replace")
    deaths, starts, costs, snaps = battles.parse(text)
    seen, uniq = set(), []
    for d in deaths:
        k = (d.frame, d.team, d.unit, d.x, d.z)
        if k not in seen:
            seen.add(k)
            uniq.append(d)
    deaths = uniq
    kinds = unit_kinds(eng)
    out = []
    w = out.append
    winners = r.get("winners") or []
    w("# %s\n" % match.name)
    w("Result: %s at %.1f min. Factions %s. Side A = the model's army (team 0), side B = our AI's (team 1).\n" % (
        "A won" if 0 in winners else ("draw" if not winners else "B won"), r.get("game_minutes") or 0, res.get("sides")))

    # metal lost and killed by kind, per bucket
    end = max([d.frame for d in deaths] + [1]) / 1800.0
    buckets = list(range(0, int(end) + every, every))
    w("## Metal lost by kind (killed by the other side), per %d minutes\n" % every)
    w("| min | side | " + " | ".join(KINDS) + " | total |")
    w("|---|---|" + "---|" * (len(KINDS) + 1))
    for b in buckets:
        for t, name in ((0, "A"), (1, "B")):
            row = defaultdict(float)
            for d in deaths:
                if d.team == t and b * 1800 <= d.frame < (b + every) * 1800 and d.atkteam not in (t, -1):
                    row[kind_of(kinds, d)] += d.cost
            if sum(row.values()):
                w("| %d-%d | %s lost | %s | %.0f |" % (b, b + every, name, " | ".join("%.0f" % row[k] for k in KINDS),
                                                     sum(row.values())))
    tot = {t: defaultdict(float) for t in (0, 1)}
    for d in deaths:
        if d.atkteam not in (d.team, -1):
            tot[d.team][kind_of(kinds, d)] += d.cost
    w("\nWhole game, lost: A %s; B %s\n" % (
        ", ".join("%s %.0f" % (k, tot[0][k]) for k in KINDS if tot[0][k]),
        ", ".join("%s %.0f" % (k, tot[1][k]) for k in KINDS if tot[1][k])))

    # economy and army by minute
    def at(team, minute, key):
        rows = [s for s in stats if int(s["team"]) == team and s["frame"] <= minute * 1800 + 1]
        return rows[-1].get(key) if rows else None

    # his 11-20: a game cut by the time limit is a soft win or loss by who was doing better at the end -- side A's
    # mean share of income, army and extractors then, and of the metal killed over the game; past 0.55 / under 0.45
    if not winners:
        shares = []
        for key in ("mInc", "armyReal", "mex"):
            a_, b_ = at(0, 1e9, key), at(1, 1e9, key)
            if a_ is not None and b_ is not None and a_ + b_ > 0:
                shares.append(a_ / (a_ + b_))
        la, lb = sum(tot[0].values()), sum(tot[1].values())
        if la + lb > 0:
            shares.append(lb / (la + lb))
        if shares:
            sc = sum(shares) / len(shares)
            verdict = "soft W" if sc > 0.55 else ("soft L" if sc < 0.45 else "even")
            out[1] = out[1].replace("Result: draw", "Result: %s (A's share %.2f)" % (verdict, sc), 1)
    w("## Extractors / income / army (metal) by minute\n")
    w("| min | A mex | B mex | A income | B income | A army | B army |")
    w("|---|---|---|---|---|---|---|")
    mex_by = {}
    for m in range(every, int(end) + 1, every):
        vals = [at(0, m, "mex"), at(1, m, "mex"), at(0, m, "mInc"), at(1, m, "mInc"), at(0, m, "armyReal"), at(1, m, "armyReal")]
        mex_by[m] = vals[:2]
        w("| %d | %s |" % (m, " | ".join("-" if v is None else "%.0f" % v for v in vals)))

    # battles
    combat = [d for d in deaths if d.atkteam >= 0 and d.atkteam != d.team]
    bl = battles.cluster_battles(combat, 900, 45 * 30)
    rows = []
    for b in bl:
        if len(b["deaths"]) < 3:
            continue
        cx, cz = b["sx"] / b["n"], b["sz"] / b["n"]
        t0 = min(d.frame for d in b["deaths"])
        forces, _ = battles.local_forces(snaps, t0, cx, cz, costs, 900)
        lost = {t: sum(d.cost for d in b["deaths"] if d.team == t) for t in (0, 1)}
        fa, fb = forces.get(0, (0, 0))[1], forces.get(1, (0, 0))[1]
        rows.append((t0 / 1800.0, cx, cz, fa, fb, lost[0], lost[1], battles.whose_ground(cx, cz, starts)))
    outn = [x for x in rows if x[3] > 0 and x[3] < 0.67 * x[4]]
    w("\n## Battles (3+ deaths within 900 elmos and 45 s)\n")
    w("%d battles; side A entered %d outnumbered (its metal within 900 under 2/3 of B's), losing %.0f and killing %.0f "
      "in them; overall A lost %.0f and killed %.0f in battles." % (
          len(rows), len(outn), sum(x[5] for x in outn), sum(x[6] for x in outn), sum(x[5] for x in rows),
          sum(x[6] for x in rows)))
    still = {t: (sum(1 for d in combat if d.team == t and d.mob and battles.heading(d, starts.get(t, (0, 0))) == "still"),
                 sum(1 for d in combat if d.team == t and d.mob)) for t in (0, 1)}
    w("Mobile units that died standing still: A %d of %d, B %d of %d.\n" % (still[0][0], still[0][1], still[1][0],
                                                                          still[1][1]))
    w("| min | where | A metal there | B metal there | A lost | B lost |")
    w("|---|---|---|---|---|---|")
    for x in sorted(rows, key=lambda x: -(x[5] + x[6]))[:8]:
        w("| %.1f | %s (%d,%d) | %.0f | %.0f | %.0f | %.0f |" % (x[0], x[7], x[1], x[2], x[3], x[4], x[5], x[6]))

    # army distance from home
    w("\n## Army centre: share of the way from home to their start, by minute\n")
    track = {0: [], 1: []}
    for k in sorted(snaps):
        for t in (0, 1):
            c = centre(snaps[k].get(t, []), costs)
            if c and t in starts and (1 - t) in starts:
                hx, hz = starts[t]
                ex, ez = starts[1 - t]
                ax_, az_ = ex - hx, ez - hz
                f = ((c[0] - hx) * ax_ + (c[1] - hz) * az_) / max(ax_ * ax_ + az_ * az_, 1)
                track[t].append((k / 1800.0, c[0], c[1], c[2], f))
    line = []
    for m in range(every, int(end) + 1, every):
        cells = []
        for t in (0, 1):
            pts = [p for p in track[t] if m - every < p[0] <= m]
            cells.append("%.2f" % np.median([p[4] for p in pts]) if pts else "-")
        line.append("%d min A %s B %s" % (m, cells[0], cells[1]))
    w("; ".join(line) + "\n")

    # the deciding moments
    w("## What decided it\n")
    if rows:
        big = max(rows, key=lambda x: x[5] + x[6])
        w("- Costliest battle at %.1f min in %s: A had %.0f there, B %.0f; A lost %.0f, B lost %.0f." % (
            big[0], big[7], big[3], big[4], big[5], big[6]))
    swings = [(m, (mex_by[m][1] or 0) - (mex_by[m][0] or 0)) for m in sorted(mex_by)]
    if len(swings) >= 2:
        d_ = [(swings[i][0], swings[i][1] - swings[i - 1][1]) for i in range(1, len(swings))]
        m, dv = max(d_, key=lambda x: x[1])
        w("- Largest swing in extractors toward B: %+d (B minus A) in the %d minutes to minute %d." % (dv, every, m))
    if track[0]:
        late = [p for p in track[0] if p[0] >= end / 2]
        if late:
            w("- Side A's army in the second half: median %.0f metal, median %.2f of the way to their start (B's: %s)." % (
                np.median([p[3] for p in late]), np.median([p[4] for p in late]),
                "%.2f" % np.median([p[4] for p in track[1] if p[0] >= end / 2]) if track[1] else "-"))
    w("- Lost to the other side over the game: A's economy %.0f vs B's %.0f; armies A %.0f vs B %.0f." % (
        tot[0]["economy"], tot[1]["economy"], tot[0]["army"], tot[1]["army"]))

    # who killed what: a nuke, gunships or artillery show up here even when no army stood there
    w("\n## Killers: the other side's metal each side's unit types destroyed (top 6)\n")
    for t, name in ((1, "B's"), (0, "A's")):
        by = defaultdict(float)
        for d in deaths:
            if d.atkteam == t and d.team != t:
                by[d.atk or "?"] += d.cost
        w("- %s: %s" % (name, ", ".join("%s %.0f" % kv for kv in sorted(by.items(), key=lambda kv: -kv[1])[:6])))

    # reach: how much of the map each side's army stood on, and how many of the other side's extractors it came near
    w("\n## Reach: map squares (1/16 of each side) where the army stood, and the other side's extractors it came "
      "within 800 of, per %d minutes\n" % every)
    mexes = defaultdict(dict)
    for tm, _al, f, data in story.POS_RE.findall(text):
        for tok in data.split(","):
            p = tok.split(":")
            if len(p) >= 3 and story.category(p[0]) == "mex":
                mexes[int(f)].setdefault(int(tm), set()).add((int(p[1]), int(p[2])))
    pf = sorted(mexes)
    mapx = max([x for f in snaps for us in snaps[f].values() for (_u, _n, x, _z, _h) in us] + [1])
    mapz = max([z for f in snaps for us in snaps[f].values() for (_u, _n, _x, z, _h) in us] + [1])
    parts = []
    for b in buckets:
        cell, near = {0: set(), 1: set()}, {0: set(), 1: set()}
        for k in sorted(snaps):
            if not (b * 1800 <= k < (b + every) * 1800):
                continue
            before = [f for f in pf if f <= k]
            for t in (0, 1):
                theirs = mexes[before[-1]].get(1 - t, set()) if before else set()
                for (_u, n, x, z, _h) in snaps[k].get(t, []):
                    cell[t].add((int(4 * x / (mapx + 1)), int(4 * z / (mapz + 1))))
                    for (mx_, mz_) in theirs:
                        if abs(mx_ - x) < 800 and abs(mz_ - z) < 800 and math.hypot(mx_ - x, mz_ - z) < 800:
                            near[t].add((mx_, mz_))
        if cell[0] or cell[1]:
            parts.append("%d-%d: A %d sq, %d of B's mex | B %d sq, %d of A's mex" % (
                b, b + every, len(cell[0]), len(near[0]), len(cell[1]), len(near[1])))
    w("; ".join(parts) + "\n")

    report = "\n".join(out) + "\n"
    (match / "report.md").write_text(report, encoding="utf-8")
    print(report)
    subprocess.run([sys.executable, str(TOOLS / "armynet" / "timelapse.py"), str(match),
                    *(["--no-gif"] if "--no-gif" in a else [])], check=False)



if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
