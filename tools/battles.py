#!/usr/bin/env python3
"""Reconstruct individual battles from a match's combat log.

Aggregate K/D says the army trades badly; it cannot say WHICH fights were bad,
whether we were outnumbered when we engaged, or whether the losers were trying
to leave. This reads the [BARAI_DEATH] / [BARAI_ARMY] / [BARAI_START] lines
dev_combat_log.lua emits (run_match.py enables it by default) and rebuilds the
fights offline.

Per battle: time window, location and whose territory it was in; each side's
losses in metal and units; what did the killing (static vs mobile); the local
force balance at the moment the battle started (from the nearest army snapshot);
and the retreat evidence -- which way each dying unit was physically moving.

Also reports a squad-tightness timeline: for each side's units in the field,
how many distinct groups they form and how big the largest is. "Fighting groups
stay 1-2 units" is visible here directly.

Usage:
    python tools/battles.py <match-dir>            # full report
    python tools/battles.py <match-dir> --battles  # battle list only
    python tools/battles.py <match-dir> --tightness
    python tools/battles.py <match-dir> --radius 600 --gap 45
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

FPS = 30

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

COST_CACHE = REPO / "tools" / ".unit_costs.json"
COST_RE = re.compile(r"\bmetalcost\s*=\s*(\d+)", re.I)


def load_cost_table():
    """def name -> metal cost, from the pinned game tree (BAR.sdd). Cached,
    because commanders and anything the enemy built but never lost would
    otherwise read as 0 metal and corrupt every odds estimate."""
    if COST_CACHE.exists():
        try:
            return json.loads(COST_CACHE.read_text())
        except json.JSONDecodeError:
            pass
    import bar_env
    env = bar_env.load()
    table = {}
    units = env.game_sdd / "units"
    if units.is_dir():
        for p in units.rglob("*.lua"):
            m = COST_RE.search(p.read_text("utf-8", errors="replace"))
            if m:
                table[p.stem.lower()] = int(m.group(1))
    if table:
        COST_CACHE.write_text(json.dumps(table))
    return table

DEATH_RE = re.compile(
    r"\[BARAI_DEATH\] frame=(?P<frame>\d+) team=(?P<team>\d+) unit=(?P<unit>\S+)"
    r" cost=(?P<cost>\d+) x=(?P<x>-?\d+) z=(?P<z>-?\d+)"
    r" vx=(?P<vx>-?[\d.]+) vz=(?P<vz>-?[\d.]+) built=(?P<built>\d) mob=(?P<mob>\d)"
    r" atkteam=(?P<atkteam>-?\d+) atk=(?P<atk>\S+) atkx=(?P<atkx>-?\d+) atkz=(?P<atkz>-?\d+)")
ARMY_RE = re.compile(r"\[BARAI_ARMY\] frame=(\d+) team=(\d+) n=\d+ (\S+)")
START_RE = re.compile(r"\[BARAI_START\] team=(\d+) x=(-?\d+) z=(-?\d+)")
BUILD_RE = re.compile(r"\[BARAI_BUILD\] team=\d+ ally=\d+ frame=\d+ min=[\d.]+ unit=(\S+) cost=(\d+)")


def gm(frame):
    return frame / (FPS * 60.0)


class Death:
    __slots__ = ("frame", "team", "unit", "cost", "x", "z", "vx", "vz",
                 "built", "mob", "atkteam", "atk", "atkx", "atkz")

    def __init__(self, m):
        self.frame = int(m["frame"]); self.team = int(m["team"])
        self.unit = m["unit"]; self.cost = int(m["cost"])
        self.x = int(m["x"]); self.z = int(m["z"])
        self.vx = float(m["vx"]); self.vz = float(m["vz"])
        self.built = int(m["built"]); self.mob = int(m["mob"])
        self.atkteam = int(m["atkteam"]); self.atk = m["atk"]
        self.atkx = int(m["atkx"]); self.atkz = int(m["atkz"])


def parse(log_text):
    deaths = [Death(m) for m in DEATH_RE.finditer(log_text)]
    starts = {int(t): (int(x), int(z)) for t, x, z in START_RE.findall(log_text)}
    costs = load_cost_table()
    for unit, cost in BUILD_RE.findall(log_text):
        costs[unit] = int(cost)
    for d in deaths:
        costs.setdefault(d.unit, d.cost)
    # snapshots: frame -> team -> [(id, def, x, z, hp)]
    snaps = defaultdict(dict)
    for frame, team, data in ARMY_RE.findall(log_text):
        units = []
        for tok in data.split(","):
            p = tok.split(":")
            if len(p) == 5:
                units.append((int(p[0]), p[1], int(p[2]), int(p[3]), int(p[4])))
        snaps[int(frame)][int(team)] = units
    return deaths, starts, costs, dict(snaps)


def heading(d, home):
    """toward-home / toward-enemy / still, from the velocity at death."""
    sp = math.hypot(d.vx, d.vz)
    if sp < 0.4:
        return "still"
    hx, hz = home[0] - d.x, home[1] - d.z
    hn = math.hypot(hx, hz)
    if hn < 1:
        return "still"
    cos = (d.vx * hx + d.vz * hz) / (sp * hn)
    if cos > 0.35:
        return "home"
    if cos < -0.35:
        return "enemy"
    return "lateral"


def cluster_battles(deaths, radius, gap_frames):
    """Greedy space-time clustering of combat deaths into battles."""
    battles = []
    for d in sorted(deaths, key=lambda d: d.frame):
        placed = None
        for b in battles:
            if d.frame - b["last"] > gap_frames:
                continue
            cx = b["sx"] / b["n"]; cz = b["sz"] / b["n"]
            if math.hypot(d.x - cx, d.z - cz) <= radius:
                placed = b
                break
        if placed is None:
            placed = {"deaths": [], "sx": 0.0, "sz": 0.0, "n": 0, "last": d.frame}
            battles.append(placed)
        placed["deaths"].append(d)
        placed["sx"] += d.x; placed["sz"] += d.z
        placed["n"] += 1; placed["last"] = d.frame
    return battles


def nearest_snap(snaps, frame, before=True):
    keys = sorted(snaps)
    best = None
    for k in keys:
        if before and k <= frame:
            best = k
        elif not before and best is None and k >= frame:
            best = k
    return best


def local_forces(snaps, frame, cx, cz, costs, radius):
    """team -> (count, metal) of mobile armed units near (cx,cz) at the snapshot
    at-or-before `frame`."""
    k = nearest_snap(snaps, frame)
    if k is None:
        return {}, None
    out = {}
    for team, units in snaps[k].items():
        c, m = 0, 0
        for _uid, name, x, z, _hp in units:
            if math.hypot(x - cx, z - cz) <= radius:
                c += 1
                m += costs.get(name, 0)
        out[team] = (c, m)
    return out, k


def whose_ground(cx, cz, starts):
    if not starts:
        return "?"
    best = min(starts, key=lambda t: math.hypot(cx - starts[t][0], cz - starts[t][1]))
    dists = {t: math.hypot(cx - starts[t][0], cz - starts[t][1]) for t in starts}
    lo = sorted(dists.values())
    if len(lo) >= 2 and lo[1] - lo[0] < 0.2 * lo[1]:
        return "midfield"
    return "t%d territory" % best


def tightness(snaps, starts, costs):
    """Per snapshot, per team: field units, group count, largest group, mean
    nearest-neighbour distance. Field = >600 elmo from own start."""
    rows = []
    for frame in sorted(snaps):
        for team, units in sorted(snaps[frame].items()):
            home = starts.get(team, (0, 0))
            field = [(x, z) for _u, _n, x, z, _hp in units
                     if math.hypot(x - home[0], z - home[1]) > 600]
            if not field:
                continue
            # single-linkage grouping, 350 elmo
            groups = []
            for p in field:
                joined = None
                for g in groups:
                    if any(math.hypot(p[0] - q[0], p[1] - q[1]) <= 350 for q in g):
                        if joined is None:
                            g.append(p); joined = g
                        else:
                            joined.extend(g); g.clear()
                groups = [g for g in groups if g]
                if joined is None:
                    groups.append([p])
            nnd = []
            for i, p in enumerate(field):
                dmin = min((math.hypot(p[0] - q[0], p[1] - q[1])
                            for j, q in enumerate(field) if j != i), default=0)
                nnd.append(dmin)
            rows.append({
                "frame": frame, "team": team, "field": len(field),
                "groups": len(groups),
                "biggest": max(len(g) for g in groups),
                "singles": sum(1 for g in groups if len(g) == 1),
                "nnd": sum(nnd) / len(nnd) if nnd else 0,
            })
    return rows


def team_labels(match_dir):
    labels = {}
    rj = match_dir / "result.json"
    if rj.exists():
        try:
            data = json.loads(rj.read_text())
            for t in data.get("teams", []):
                labels[int(t["team"])] = t.get("spec", "?")
        except (json.JSONDecodeError, KeyError, ValueError):
            pass
    return labels


def fmt_forces(forces, labels):
    parts = []
    for team in sorted(forces):
        c, m = forces[team]
        parts.append("t%d %d units/%dm" % (team, c, m))
    return "  ".join(parts) if parts else "no snapshot"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("match")
    ap.add_argument("--radius", type=float, default=550, help="battle cluster radius, elmo")
    ap.add_argument("--gap", type=float, default=40, help="battle max gap between deaths, seconds")
    ap.add_argument("--odds-radius", type=float, default=900, help="local-force radius, elmo")
    ap.add_argument("--min-metal", type=float, default=150, help="ignore battles below this total metal")
    ap.add_argument("--battles", action="store_true", help="battle list only")
    ap.add_argument("--tightness", action="store_true", help="tightness timeline only")
    args = ap.parse_args()

    p = Path(args.match)
    log = p / "infolog.txt" if p.is_dir() else p
    if not log.exists():
        sys.exit("no infolog at %s" % log)
    text = log.read_text("utf-8", errors="replace")
    deaths, starts, costs, snaps = parse(text)
    if not deaths:
        sys.exit("no [BARAI_DEATH] lines -- was dev_combatlog=1 set and the gadget installed?")
    labels = team_labels(p if p.is_dir() else p.parent)

    last_frame = max(d.frame for d in deaths)
    wipe_cut = last_frame - 90 * FPS

    print("teams: " + "  ".join("t%d=%s" % (t, labels.get(t, "?")) for t in sorted(starts)))
    print("starts: " + "  ".join("t%d@(%d,%d)" % (t, x, z) for t, (x, z) in sorted(starts.items())))
    print()

    if not args.tightness:
        combat = [d for d in deaths if d.built == 1 and (d.mob == 1 or d.atkteam >= 0)]
        battles = cluster_battles(combat, args.radius, args.gap * FPS)
        shown = 0
        for b in battles:
            ds = b["deaths"]
            total = sum(d.cost for d in ds)
            if total < args.min_metal:
                continue
            f0, f1 = ds[0].frame, ds[-1].frame
            cx, cz = b["sx"] / b["n"], b["sz"] / b["n"]
            endgame = f0 >= wipe_cut
            shown += 1
            lost = defaultdict(lambda: [0, 0])   # team -> [units, metal]
            units_lost = defaultdict(lambda: defaultdict(int))
            headings = defaultdict(lambda: defaultdict(int))
            for d in ds:
                lost[d.team][0] += 1
                lost[d.team][1] += d.cost
                units_lost[d.team][d.unit] += 1
                if d.mob == 1:
                    headings[d.team][heading(d, starts.get(d.team, (0, 0)))] += 1
            killers = defaultdict(lambda: defaultdict(int))  # victim team -> atk def -> metal
            for d in ds:
                if d.atk != "?":
                    killers[d.team][d.atk] += d.cost
            forces, snapf = local_forces(snaps, f0, cx, cz, costs, args.odds_radius)
            tag = "  [ENDGAME WIPE]" if endgame else ""
            print("== battle %d  %.1fm-%.1fm  at (%d,%d)  %s%s" % (
                shown, gm(f0), gm(f1), cx, cz, whose_ground(cx, cz, starts), tag))
            if snapf is not None:
                print("   forces at start (snap %.1fm, r=%d): %s" % (
                    gm(snapf), args.odds_radius, fmt_forces(forces, labels)))
            for team in sorted(lost):
                u, m = lost[team]
                top = sorted(units_lost[team].items(), key=lambda kv: -kv[1] * costs.get(kv[0], 0))[:4]
                tops = " ".join("%dx%s" % (n, name) for name, n in top)
                kk = sorted(killers[team].items(), key=lambda kv: -kv[1])[:3]
                ks = " ".join("%s(%dm)" % (name, m2) for name, m2 in kk)
                hh = headings[team]
                hs = " ".join("%s:%d" % (k, v) for k, v in
                              sorted(hh.items(), key=lambda kv: -kv[1])) if hh else "-"
                print("   t%d lost %2d units %5dm  [%s]  killed-by: %s  moving: %s" % (
                    team, u, m, tops, ks, hs))
            print()

        # summary
        print("-- summary (excluding endgame wipe) --")
        agg = defaultdict(lambda: [0, 0])
        eng_bad = defaultdict(int)
        eng_tot = defaultdict(int)
        for b in battles:
            ds = b["deaths"]
            if sum(d.cost for d in ds) < args.min_metal or ds[0].frame >= wipe_cut:
                continue
            cx, cz = b["sx"] / b["n"], b["sz"] / b["n"]
            per = defaultdict(int)
            for d in ds:
                agg[d.team][0] += 1
                agg[d.team][1] += d.cost
                per[d.team] += d.cost
            forces, _ = local_forces(snaps, ds[0].frame, cx, cz, costs, args.odds_radius)
            if len(forces) >= 2:
                for team in per:
                    them = sum(m for t, (_c, m) in forces.items() if t != team)
                    us = forces.get(team, (0, 0))[1]
                    if them > 0:
                        eng_tot[team] += 1
                        if us < 0.8 * them and per[team] > 0.6 * sum(per.values()):
                            eng_bad[team] += 1
        for team in sorted(agg):
            u, m = agg[team]
            print("t%d (%s): lost %d units / %dm across battles; outgunned-at-start in %d/%d battles it lost" % (
                team, labels.get(team, "?"), u, m, eng_bad[team], eng_tot[team]))
        print()

    if not args.battles:
        print("-- squad tightness (field units >600 from own start; groups at 350 elmo) --")
        rows = tightness(snaps, starts, costs)
        # print every ~2 minutes
        seen = set()
        for r in rows:
            slot = (int(gm(r["frame"]) // 2), r["team"])
            if slot in seen:
                continue
            seen.add(slot)
            print("  %5.1fm t%d: %2d in field, %2d groups (biggest %2d, %2d singletons), mean-NN %4.0f" % (
                gm(r["frame"]), r["team"], r["field"], r["groups"],
                r["biggest"], r["singles"], r["nnd"]))


if __name__ == "__main__":
    main()
