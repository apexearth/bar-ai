#!/usr/bin/env python3
"""Leaks: our buildings killed by enemy units, by where they stood in our base.

    python tools/leaks.py <tournament|match> [...]   -> per game table + pooled summary

The base is each Apex seat's hull of standing non-mex, non-defence structures
(from [BARAI_BUILD] minus [BARAI_DEATH]) at the death: in = 150+ inside its
edge, rim = up to 250 outside, out = beyond. Direction is the death's bearing
from the base centre against the enemy's structure centroid (front < 60 deg,
rear > 120). "sens" = generators/converters/storage, nanos and labs. The
in-game counterpart is `apex: leak` / `apex: leak-stat` (protect_nn.as).
"""
import glob
import json
import math
import os
import re
import sys
from collections import defaultdict

import bar_env
import decisions

BUILD = re.compile(r"\[BARAI_BUILD\] team=(\d+) ally=(\d+) frame=(\d+) min=[\d.]+ unit=(\w+) cost=(\d+) x=(-?\d+) z=(-?\d+) uid=(\d+)")
DEATH = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\w+) cost=(\d+) x=(-?[\d.]+) z=(-?[\d.]+) .*? built=(\d) mob=(\d)"
                   r" atkteam=(-?\d+) atk=(\S+) atkx=(-?[\d.]+) atkz=(-?[\d.]+) .*? uid=(\d+)")
FPM = 1800
INSIDE = 150.0   # elmos inside the hull edge: interior
RIM = 250.0      # elmos outside the hull edge still counts as its rim

_CLS = {}
_ROOT = bar_env.load().game_sdd / "units"
_FILES = None


def ucls(name):
    """mex / eco / nano / lab / gun / wall / util / mobile, from the unit file's folder."""
    global _FILES
    if name in _CLS:
        return _CLS[name]
    if _FILES is None:
        _FILES = {p.stem.lower(): p for p in _ROOT.rglob("*.lua")}
    p = _FILES.get(name.lower())
    c = "mobile"
    if p is not None:
        rel = str(p.relative_to(_ROOT)).replace("\\", "/")
        txt = p.read_text(encoding="utf-8", errors="replace")
        if "Buildings" in rel or rel.startswith("Legion/") and any(
                k in rel for k in ("Defenses", "Economy", "Seaconomy", "Labs", "Utilities", "SeaDefenses", "SeaUtility")):
            if "extractsmetal" in txt and not re.search(r"extractsmetal\s*=\s*0[,\s]", txt):
                c = "mex"
            elif "Defen" in rel:
                c = "gun" if "weapondefs" in txt else "wall"
            elif "Econom" in rel or "Seaconomy" in rel:
                c = "eco"
            elif "Factor" in rel or "Labs" in rel:
                c = "lab"
            elif "nanotc" in name:
                c = "nano"
            else:
                c = "util"
        elif "Gantry" in rel or ("T3" in rel and "builder = true" in txt and "speed" not in txt):
            c = "lab"
    _CLS[name] = c
    return c


_KC = {}


def kcost(name):
    global _FILES
    if name in _KC:
        return _KC[name]
    if _FILES is None:
        ucls("armllt")
    p = _FILES.get(name.lower())
    v = 0.0
    if p is not None:
        m = re.search(r"\bmetalcost\s*=\s*([\d.]+)", p.read_text(encoding="utf-8", errors="replace"), re.I)
        v = float(m.group(1)) if m else 0.0
    _KC[name] = v
    return v


def hull(pts):
    pts = sorted(set(pts))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], p) <= 0:
            hi.pop()
        hi.append(p)
    return lo[:-1] + hi[:-1]


def seg_d(p, a, b):
    ax, az = b[0] - a[0], b[1] - a[1]
    L = ax * ax + az * az
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * az) / L))
    return math.hypot(p[0] - a[0] - t * ax, p[1] - a[1] - t * az)


def depth(p, h):
    """Signed distance to the hull edge: + inside, - outside."""
    if not h:
        return -1e9
    if len(h) < 3:
        return -min(math.hypot(p[0] - q[0], p[1] - q[1]) for q in h)
    d = min(seg_d(p, h[i], h[(i + 1) % len(h)]) for i in range(len(h)))
    inside = all((h[(i + 1) % len(h)][0] - h[i][0]) * (p[1] - h[i][1])
                 - (h[(i + 1) % len(h)][1] - h[i][1]) * (p[0] - h[i][0]) >= 0 for i in range(len(h)))
    return d if inside else -d


def game(mdir):
    res = json.load(open(os.path.join(mdir, "result.json"), encoding="utf-8"))
    script = open(os.path.join(mdir, "script.txt"), encoding="utf-8", errors="replace").read()
    apex = set()
    for block in re.findall(r"\[ai\d+\]\s*\{(.*?)\}", script, re.S | re.I):
        tm = re.search(r"team=(\d+);", block, re.I)
        if tm and re.search(r"shortname=Apex", block, re.I):
            apex.add(int(tm.group(1)))
    blds = []   # frame, team, ally, unit, cost, x, z, uid
    deaths = []
    ally = {}
    died_at = {}
    with open(os.path.join(mdir, "infolog.txt"), encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            if "[BARAI_" not in ln:
                continue
            if "[BARAI_BUILD]" in ln:
                m = BUILD.search(ln)
                if m:
                    t = int(m.group(1))
                    ally[t] = int(m.group(2))
                    blds.append((int(m.group(3)), t, int(m.group(2)), m.group(4), int(m.group(5)),
                                 float(m.group(6)), float(m.group(7)), m.group(8)))
            elif "[BARAI_DEATH]" in ln:
                m = DEATH.search(ln)
                if m:
                    f, uid = int(m.group(1)), m.group(13)
                    died_at[uid] = f
                    deaths.append(dict(f=f, t=int(m.group(2)), unit=m.group(3), cost=int(m.group(4)),
                                       x=float(m.group(5)), z=float(m.group(6)), built=m.group(7) == "1",
                                       mob=m.group(8) == "1", at=int(m.group(9)), atk=m.group(10),
                                       ax=float(m.group(11)), az=float(m.group(12)), uid=uid))
    our_ally = {ally[t] for t in apex if t in ally}
    r = res.get("result") or {}
    win = " ".join(r.get("winner_specs") or [])
    out = dict(match=os.path.basename(mdir), map=res.get("map", "?"), mins=round((r.get("game_frames") or 0) / FPM, 1),
               res="W" if "Apex" in win else ("L" if win else "D"), rows=[])

    def standing(f, pred):
        return [b for b in blds if b[0] <= f and pred(b) and not (b[7] in died_at and died_at[b[7]] < f)]

    cache = {}
    for d in deaths:
        if d["t"] not in apex or d["mob"] or not d["built"]:
            continue
        if d["at"] < 0 or ally.get(d["at"], -1) in our_ally:
            continue
        c = ucls(d["unit"])
        if c == "mobile":
            continue
        kc = decisions.killer_class(d["atk"])
        key = (d["t"], d["f"] // 150)
        if key not in cache:
            mine = standing(d["f"], lambda b: b[1] == d["t"])
            core = [(b[5], b[6]) for b in mine if ucls(b[3]) not in ("mex", "gun", "wall")]
            guns = [(b[5], b[6]) for b in standing(d["f"], lambda b: b[2] in our_ally) if ucls(b[3]) == "gun"]
            foe = [(b[5], b[6], b[4]) for b in standing(d["f"], lambda b: b[2] not in our_ally) if ucls(b[3]) != "mex"]
            ctr = None
            if core:
                ctr = (sum(p[0] for p in core) / len(core), sum(p[1] for p in core) / len(core))
            fc = None
            if foe:
                w = sum(p[2] for p in foe) or 1
                fc = (sum(p[0] * p[2] for p in foe) / w, sum(p[1] * p[2] for p in foe) / w)
            cache[key] = (hull(core), guns, ctr, fc)
        h, guns, ctr, fc = cache[key]
        p = (d["x"], d["z"])
        dep = depth(p, h)
        zone = "in" if dep >= INSIDE else ("rim" if dep >= -RIM else "out")
        gd = min((math.hypot(p[0] - g[0], p[1] - g[1]) for g in guns), default=9999.0)
        g6 = sum(1 for g in guns if math.hypot(p[0] - g[0], p[1] - g[1]) <= 600)
        dirn = "?"
        if ctr and fc:
            vx, vz = p[0] - ctr[0], p[1] - ctr[1]
            ex, ez = fc[0] - ctr[0], fc[1] - ctr[1]
            nv, ne = math.hypot(vx, vz), math.hypot(ex, ez)
            if nv > 1 and ne > 1:
                a = math.degrees(math.acos(max(-1, min(1, (vx * ex + vz * ez) / (nv * ne)))))
                dirn = "front" if a < 60 else ("flank" if a < 120 else "rear")
            else:
                dirn = "centre"
        out["rows"].append(dict(f=d["f"], t=d["t"], unit=d["unit"], cls=c, cost=d["cost"], kc=kc, zone=zone,
                                dep=dep, dir=dirn, gunD=gd, gun600=g6, atk=d["atk"], akm=kcost(d["atk"]),
                                end=out["res"] == "L" and d["f"] > (r.get("game_frames") or 0) - 5 * FPM))
    return out


def fmt_game(g):
    rows = g["rows"]
    mob = [r for r in rows if r["kc"] == "mobile"]
    z = defaultdict(float)
    for r in mob:
        z[r["zone"]] += r["cost"]
    air = sum(r["cost"] for r in rows if r["kc"] == "air")
    st = sum(r["cost"] for r in rows if r["kc"] == "static")
    sens = [r for r in mob if r["zone"] in ("in", "rim") and r["cls"] in ("eco", "nano", "lab")]
    dirs = defaultdict(float)
    for r in sens:
        dirs[r["dir"]] += r["cost"]
    gds = sorted(r["gunD"] for r in sens)
    med = gds[len(gds) // 2] if gds else -1
    nogun = sum(r["cost"] for r in sens if r["gun600"] == 0)
    sm = sum(r["cost"] for r in sens)
    return ("%-58s %-4s %5.1f %s | mob in %6d rim %6d out %6d | air %6d st %5d | sens %6d f/fl/r %5d/%5d/%5d"
            " | gunD med %5d nogun600 %3.0f%%" % (
                g["match"][:58], g["map"][:4], g["mins"], g["res"], z["in"], z["rim"], z["out"], air, st, sm,
                dirs["front"], dirs["flank"], dirs["rear"], med, 100.0 * nogun / sm if sm else 0))


def main(argv):
    dirs = []
    for a in argv:
        if os.path.isfile(os.path.join(a, "infolog.txt")):
            dirs.append(a)
        else:
            dirs += sorted(d for d in glob.glob(os.path.join(a, "matches", "*")) if os.path.isfile(os.path.join(d, "infolog.txt")))
    games = []
    for d in dirs:
        try:
            g = game(d)
        except (OSError, ValueError) as e:
            print("skip", d, e)
            continue
        games.append(g)
        print(fmt_game(g), flush=True)
    rows = [r for g in games for r in g["rows"]]
    print("\nPOOLED %d games, %d building deaths to enemies" % (len(games), len(rows)))
    tab = defaultdict(float)
    for r in rows:
        tab[(r["kc"], r["zone"], r["cls"])] += r["cost"]
    for kc in ("mobile", "air", "static", "?"):
        line = []
        for zone in ("in", "rim", "out"):
            parts = ["%s=%d" % (c, tab[(kc, zone, c)]) for c in ("eco", "nano", "lab", "mex", "gun", "util", "wall") if tab[(kc, zone, c)]]
            line.append("%s[%s]" % (zone, " ".join(parts)))
        print("  killer %-6s %s" % (kc, "  ".join(line)))
    sens = [r for r in rows if r["kc"] == "mobile" and r["zone"] in ("in", "rim") and r["cls"] in ("eco", "nano", "lab")]
    tot = sum(r["cost"] for r in sens) or 1
    dd = defaultdict(float)
    for r in sens:
        dd[r["dir"]] += r["cost"]
    print("  sensitive (eco/nano/lab, in+rim) to ground mobiles: %d metal; dir %s" % (
        tot, " ".join("%s=%.0f%%" % (k, 100 * v / tot) for k, v in sorted(dd.items()))))
    for lo, hi in ((0, 300), (300, 600), (600, 1000), (1000, 99999)):
        v = sum(r["cost"] for r in sens if lo <= r["gunD"] < hi)
        print("    nearest gun %5d-%5d: %5.1f%%" % (lo, hi, 100 * v / tot))
    for lo, hi in ((0, 10), (10, 20), (20, 30), (30, 99)):
        v = sum(r["cost"] for r in sens if lo * FPM <= r["f"] < hi * FPM)
        print("    minute %2d-%2d: %6d" % (lo, hi, v))
    for res in ("W", "L", "D"):
        gs = [g for g in games if g["res"] == res]
        if not gs:
            continue
        v = [sum(r["cost"] for r in g["rows"] if r["kc"] == "mobile" and r["zone"] in ("in", "rim")
                 and r["cls"] in ("eco", "nano", "lab") and not r["end"]) for g in gs]
        v.sort()
        print("  %s %3d games: sensitive leak (final 5 min of a loss excluded) median %6d mean %6d" % (
            res, len(gs), v[len(v) // 2], sum(v) / len(v)))
    pre = [r for r in sens if not r["end"]]
    pt = sum(r["cost"] for r in pre) or 1
    print("  excluding a loss's final 5 min: %d metal (%.0f%%)" % (pt, 100 * pt / tot))
    for lo, hi, nm in ((0, 400, "raider<400"), (400, 1200, "mid 400-1200"), (1200, 1e9, "heavy>1200")):
        v = sum(r["cost"] for r in pre if lo <= r["akm"] < hi)
        print("    killer %-13s %5.1f%%" % (nm, 100 * v / pt))
    dd = defaultdict(float)
    for r in pre:
        dd[(r["zone"], r["dir"])] += r["cost"]
    print("    zone x dir:", " ".join("%s/%s=%.0f%%" % (k[0], k[1], 100 * v / pt) for k, v in sorted(dd.items())))
    for lo, hi in ((0, 300), (300, 600), (600, 1000), (1000, 99999)):
        v = sum(r["cost"] for r in pre if lo <= r["gunD"] < hi)
        print("    nearest gun %5d-%5d: %5.1f%%" % (lo, hi, 100 * v / pt))
    v = sum(r["cost"] for r in pre if r["gun600"] <= 1)
    print("    <=1 gun within 600: %5.1f%%" % (100 * v / pt))
    au = defaultdict(float)
    for r in sens:
        au[r["atk"]] += r["cost"]
    print("  top killers:", ", ".join("%s=%d" % kv for kv in sorted(au.items(), key=lambda kv: -kv[1])[:12]))


if __name__ == "__main__":
    main(sys.argv[1:])
