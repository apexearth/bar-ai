#!/usr/bin/env python3
"""Keep-out: did the enemy's ground units get into the backline through arcs no gun covered?

    python tools/keepout.py <tournament|match> [...] [--standoff N]

Two reads per game:
  live    -- the in-game census (`apex: keepout`, `keepout-sum`, `keepout-leak`,
             protect_keepout.as) when the AI that played had it;
  replay  -- the same geometry rebuilt from [BARAI_BUILD]/[BARAI_DEATH] at every
             leak, so games played before the census existed can be read too.

Replay geometry, as the AI builds it: the alliance's sensitive buildings
(generators, converters, storage, nanos, labs; every allied seat), cost-weighted
centre, outliers past 2.5x the RMS radius dropped (apex_wall_reach), convex hull,
pushed out by the standoff (half a light tower's reach, or the killer's own
reach when longer -- the AI uses the enemy's seen reach), sampled every half a
light tower's reach. A sample is covered when any allied gun standing at that
frame reaches it. A leak (sensitive building of ours, in or at the rim of our
base, killed by an enemy ground unit) entered at the ring sample nearest the
killer. The null is the share of the ring that was uncovered at that moment.
"""
import glob
import math
import os
import re
import sys
from collections import defaultdict

import decisions
import leaks

LIGHT_R = 430.0
REACH_CAP = 2.5
SECTOR = re.compile(r"Sector-Map Size: \d+ \(x(\d+), z(\d+)\)")
KO = re.compile(r"apex: keepout t=(\d+) scope=ally cov=(\d+) held=(\d+) gaps=(\d+)")
KOSUM = re.compile(r"apex: keepout-sum t=(\d+) passes=(\d+) cov=(\d+) held=(\d+) open=(\d+) .*?"
                   r"leakN=(\d+) leakGap=(\d+) leakUncov=(\d+) leakOwn=(\d+) .*?best=(\d+) late=(\d+) "
                   r"t1refused=(\d+) sited=(\d+) claims=(\d+)")
SENS = ("eco", "nano", "lab")

_RANGE = {}


def urange(name):
    if name in _RANGE:
        return _RANGE[name]
    leaks.ucls("armllt")
    p = leaks._FILES.get(name.lower())
    r = 0.0
    if p is not None:
        txt = p.read_text(encoding="utf-8", errors="replace")
        i = txt.lower().find("weapondefs")
        if i >= 0:
            for m in re.finditer(r"\brange\s*=\s*([\d.]+)", txt[i:]):
                r = max(r, float(m.group(1)))
    _RANGE[name] = r
    return r


def offset_ring(h, s, step):
    """Samples along the hull pushed out by s: edges shifted along their
    outward normals, arcs at the vertices."""
    n = len(h)
    segs = []
    if n == 1:
        segs.append(("a", h[0], 0.0, 2 * math.pi))
    else:
        nrm = []
        for i in range(n):
            a, b = h[i], h[(i + 1) % n]
            dx, dz = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(dx, dz) or 1.0
            nrm.append((dz / ln, -dx / ln))
        for i in range(n):
            p = nrm[i - 1]
            a0 = math.atan2(p[1], p[0])
            d = (math.atan2(nrm[i][1], nrm[i][0]) - a0) % (2 * math.pi)
            if n == 2 and d < 0.01:
                d = math.pi
            segs.append(("a", h[i], a0, d))
            a, b = h[i], h[(i + 1) % n]
            segs.append(("l", (a[0] + nrm[i][0] * s, a[1] + nrm[i][1] * s),
                         (b[0] + nrm[i][0] * s, b[1] + nrm[i][1] * s)))
    lens = [(sg[3] * s if sg[0] == "a" else math.hypot(sg[2][0] - sg[1][0], sg[2][1] - sg[1][1])) for sg in segs]
    total = sum(lens)
    if total < 1:
        return []
    ns = max(3, int(total / step + 0.5))
    st = total / ns
    out, acc, nxt = [], 0.0, 0.5 * st
    for sg, L in zip(segs, lens):
        while nxt <= acc + L and len(out) < ns:
            t = nxt - acc
            if sg[0] == "a":
                a = sg[2] + (t / s if s > 0 else 0)
                out.append((sg[1][0] + math.cos(a) * s, sg[1][1] + math.sin(a) * s))
            else:
                f = t / L if L > 0 else 0
                out.append((sg[1][0] + (sg[2][0] - sg[1][0]) * f, sg[1][1] + (sg[2][1] - sg[1][1]) * f))
            nxt += st
        acc += L
    return out


def runs(flags):
    """Lengths (in samples) of the circular runs of True, and each sample's run length."""
    n = len(flags)
    rl = [0] * n
    if not any(flags):
        return rl
    if all(flags):
        return [n] * n
    start = next(i for i in range(n) if not flags[i]) + 1
    k = 0
    while k < n:
        i = (start + k) % n
        if not flags[i]:
            k += 1
            continue
        j = k
        while j < n and flags[(start + j) % n]:
            j += 1
        for q in range(k, j):
            rl[(start + q) % n] = j - k
        k = j
    return rl


def replay(mdir, standoff0):
    script = open(os.path.join(mdir, "script.txt"), encoding="utf-8", errors="replace").read()
    apex = set()
    for block in re.findall(r"\[ai\d+\]\s*\{(.*?)\}", script, re.S | re.I):
        tm = re.search(r"team=(\d+);", block, re.I)
        if tm and re.search(r"shortname=Apex", block, re.I):
            apex.add(int(tm.group(1)))
    blds, deaths, ally, died, live = [], [], {}, {}, []
    mapw = maph = None
    with open(os.path.join(mdir, "infolog.txt"), encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            if mapw is None and "Sector-Map Size" in ln:
                m = SECTOR.search(ln)
                if m:
                    mapw, maph = int(m.group(1)) * 64, int(m.group(2)) * 64
            if "apex: keepout" in ln:
                live.append(ln.rstrip())
                continue
            if "[BARAI_BUILD]" in ln:
                m = leaks.BUILD.search(ln)
                if m:
                    t = int(m.group(1))
                    ally[t] = int(m.group(2))
                    blds.append((int(m.group(3)), t, int(m.group(2)), m.group(4), float(m.group(6)),
                                 float(m.group(7)), m.group(8), int(m.group(5))))
            elif "[BARAI_DEATH]" in ln:
                m = leaks.DEATH.search(ln)
                if m:
                    died[m.group(13)] = int(m.group(1))
                    deaths.append(dict(f=int(m.group(1)), t=int(m.group(2)), unit=m.group(3), cost=int(m.group(4)),
                                       x=float(m.group(5)), z=float(m.group(6)), built=m.group(7) == "1",
                                       mob=m.group(8) == "1", at=int(m.group(9)), atk=m.group(10),
                                       ax=float(m.group(11)), az=float(m.group(12))))
    if mapw is None:
        mapw = max((b[4] for b in blds), default=0) + 512
        maph = max((b[5] for b in blds), default=0) + 512
    our = {ally[t] for t in apex if t in ally}
    rows = []
    for d in deaths:
        if d["t"] not in apex or d["mob"] or not d["built"]:
            continue
        if d["at"] < 0 or ally.get(d["at"], -1) in our:
            continue
        if leaks.ucls(d["unit"]) not in SENS or decisions.killer_class(d["atk"]) != "mobile":
            continue
        f = d["f"]
        stand = [b for b in blds if b[0] <= f and not (b[6] in died and died[b[6]] < f) and b[2] in our]
        sens = [b for b in stand if leaks.ucls(b[3]) in SENS]
        guns = [(b[4], b[5], urange(b[3])) for b in stand if leaks.ucls(b[3]) == "gun"]
        if not sens:
            continue
        w = sum(max(1, b[7]) for b in sens)
        cx = sum(b[4] * max(1, b[7]) for b in sens) / w
        cz = sum(b[5] * max(1, b[7]) for b in sens) / w
        rms = math.sqrt(sum(max(1, b[7]) * ((b[4] - cx) ** 2 + (b[5] - cz) ** 2) for b in sens) / w)
        cap = rms * REACH_CAP
        pts = [(b[4], b[5]) for b in sens if cap <= 1 or math.hypot(b[4] - cx, b[5] - cz) <= cap]
        h = leaks.hull(pts)
        own = [(b[4], b[5]) for b in stand if b[1] == d["t"] and leaks.ucls(b[3]) in SENS]
        if leaks.depth((d["x"], d["z"]), leaks.hull(own)) < -leaks.RIM:
            continue   # an outlying building: not the backline
        s = max(standoff0, urange(d["atk"]))
        ring = offset_ring(h, s, 0.5 * LIGHT_R)
        ring = [p for p in ring if 0 <= p[0] <= mapw and 0 <= p[1] <= maph]
        if len(ring) < 3:
            continue
        ng = [sum(1 for g in guns if g[2] > 1 and math.hypot(p[0] - g[0], p[1] - g[1]) <= g[2]) for p in ring]
        unc = [k == 0 for k in ng]
        thin = [k <= 1 for k in ng]
        rl = runs(unc)
        ax, az = (d["ax"], d["az"]) if d["ax"] >= 0 else (d["x"], d["z"])
        ei = min(range(len(ring)), key=lambda i: (ring[i][0] - ax) ** 2 + (ring[i][1] - az) ** 2)
        vi = min(range(len(ring)), key=lambda i: (ring[i][0] - d["x"]) ** 2 + (ring[i][1] - d["z"]) ** 2)
        step = 0.5 * LIGHT_R
        rows.append(dict(f=f, m=d["cost"], unit=d["unit"], atk=d["atk"], n=len(ring),
                         uncFrac=sum(unc) / len(ring), thinFrac=sum(thin) / len(ring),
                         entUnc=unc[ei], entThin=thin[ei], entGap=rl[ei] * step, vicUnc=unc[vi],
                         gaps=sum(1 for i in range(len(ring)) if unc[i] and not unc[i - 1]) if not all(unc) else 1,
                         worst=max(rl) * step))
    return rows, live


def main(argv):
    standoff0 = 0.5 * LIGHT_R
    args = []
    i = 0
    while i < len(argv):
        if argv[i] == "--standoff":
            standoff0 = float(argv[i + 1])
            i += 2
            continue
        args.append(argv[i])
        i += 1
    dirs = []
    for a in args:
        if os.path.isfile(os.path.join(a, "infolog.txt")):
            dirs.append(a)
        else:
            dirs += sorted(d for d in glob.glob(os.path.join(a, "matches", "*"))
                           if os.path.isfile(os.path.join(d, "infolog.txt")))
    allrows = []
    livesum = defaultdict(list)
    for d in dirs:
        try:
            rows, live = replay(d, standoff0)
        except (OSError, ValueError) as e:
            print("skip", d, e)
            continue
        allrows += rows
        for ln in live:
            m = KOSUM.search(ln)
            if m:
                livesum[(d, m.group(1))] = [int(x) for x in m.groups()[1:]]
        if rows:
            m = sum(r["m"] for r in rows)
            mu = sum(r["m"] for r in rows if r["entUnc"])
            nu = sum(r["m"] * r["uncFrac"] for r in rows)
            print("%-62s leaks %3d %7d m | entered uncovered %3.0f%% (ring uncovered %3.0f%%) | worst gap med %5d"
                  % (os.path.basename(d)[:62], len(rows), m, 100 * mu / m, 100 * nu / m,
                     sorted(r["worst"] for r in rows)[len(rows) // 2]))
    if not allrows:
        print("no leaks found")
    else:
        m = sum(r["m"] for r in allrows)
        print("\nREPLAY %d games, %d leaks, %d metal (sensitive, in/rim, killed by enemy ground units)" % (
            len(dirs), len(allrows), m))
        for key, lab in (("entUnc", "no gun reached the entry"), ("entThin", "at most one gun reached the entry"),
                         ("vicUnc", "no gun reached the ring point nearest the victim")):
            v = sum(r["m"] for r in allrows if r[key])
            null = sum(r["m"] * r["uncFrac" if key != "entThin" else "thinFrac"] for r in allrows)
            print("  %-50s %5.1f%% of leak metal; that share of the ring at the time: %5.1f%%  (x%.2f)" % (
                lab, 100 * v / m, 100 * null / m, (v / null) if null else 0))
        for lo, hi in ((0, 1), (1, 650), (650, 1300), (1300, 2600), (2600, 1e9)):
            v = sum(r["m"] for r in allrows if lo <= r["entGap"] < hi)
            print("    entry in an uncovered arc %5d-%5s long: %5.1f%%" % (lo, "inf" if hi > 1e8 else int(hi), 100 * v / m))
        g = sorted(r["gaps"] for r in allrows)
        print("  uncovered arcs on the ring at a leak: median %d; ring samples median %d" % (
            g[len(g) // 2], sorted(r["n"] for r in allrows)[len(allrows) // 2]))
    if livesum:
        print("\nLIVE census (last keepout-sum per seat): passes cov held open leakN leakGap leakUncov leakOwn best late t1refused sited claims")
        for (d, t), v in sorted(livesum.items()):
            print("  %-50s t%s %s" % (os.path.basename(d)[:50], t, " ".join(str(x) for x in v)))


if __name__ == "__main__":
    main(sys.argv[1:])
