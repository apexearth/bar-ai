#!/usr/bin/env python3
"""How each seat built, humans against our AI, from a replay recording (tools/replay_orders.py one <demo> <dir>).

His 11-22, after online games our seats lost to the humans' T3: "humans will build far more efficient patterns of
buildings than the AI does ... you're creating small, inefficient gaps in the build grid", "how much open ground is in
their base by percentage", land value ("fully packed in, but ... advanced solar and basic energy converters, whereas
... advanced fusions and advanced energy converters"), and "it oftentimes just takes one human player to go crazy
powerful and it's enough to beat all of the AI" -- so every figure is per seat, best seat against best seat.

    python tools/base_audit.py <recording dir or orders.txt.gz> ... [--minutes 20,30]

Per seat:
  finished   metal of every unit it finished; the shares in air, anti-air, T3 (gantry-built, 1,500+ metal)
  first T3   the minute its first T3 unit finished
  at each minute, its standing buildings but extractors and geos, at their unit-file footprints:
  flush / gap  the nearest other building's edge gap: 0 squares, or 1-2 (the small wasted gaps)
  open         open ground in its main base: 1 - footprint / hull of its biggest cluster (buildings within 10 build
               squares of each other)
  E/sq         energy made per build square of its energy buildings (wind at half its rating)
  m/sq         metal converted per build square of its converters
"""
import collections
import glob
import gzip
import re
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402

GANTRY_BUILDS = set("armbanth armcroc armlun armmar armraz armthor armvang corcat cordemon corjugg corkarg corkorg "
                    "corparrow corsala corshiva corsok legamph leganavybattleship legeallterrainmech legeheatraymech "
                    "legehovertank legelrpcmech legerailtank legeshotgunmech legfloat legjav legkeres".split())
_file = {}


def unit_file(name):
    if name not in _file:
        units = bar_env.load().game_sdd / "units"
        hits = glob.glob(str(units / "**" / (name + ".lua")), recursive=True)
        _file[name] = open(hits[0], encoding="utf-8", errors="replace").read() if hits else ""
    return _file[name]


def num(txt, key):
    r = re.search(key + r"\s*=\s*(-?[\d.]+)(?:\s*/\s*([\d.]+))?", txt, re.I)
    return float(r.group(1)) / (float(r.group(2)) if r.group(2) else 1.0) if r else 0.0


def foot(name):
    txt = unit_file(name)
    return int(num(txt, "footprintx") or 2), int(num(txt, "footprintz") or 2)


def output(name):
    txt = unit_file(name)
    e = num(txt, "energymake") or max(-num(txt, "energyupkeep"), 0.0) or 0.5 * num(txt, "windgenerator")
    return e, num(txt, "energyconv_capacity") * num(txt, "energyconv_efficiency")


def hull_area(pts):
    pts = sorted(set(map(tuple, pts)))
    if len(pts) < 3:
        return 0.0

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
    h = lo[:-1] + hi[:-1]
    return 0.5 * abs(sum(h[i][0] * h[(i + 1) % len(h)][1] - h[(i + 1) % len(h)][0] * h[i][1] for i in range(len(h))))


def layout(blds):
    """blds: (x, z, half x, half z, name). Returns (flush share, small-gap share, open ground, E/sq, m/sq, top energy)."""
    a = np.array([b[:4] for b in blds], float)
    gaps = np.full(len(a), np.inf)
    for i in range(len(a)):
        g = np.maximum(np.maximum(np.abs(a[:, 0] - a[i, 0]) - a[:, 2] - a[i, 2],
                                  np.abs(a[:, 1] - a[i, 1]) - a[:, 3] - a[i, 3]), 0)
        g[i] = np.inf
        gaps[i] = g.min() / 16.0
    lab = -np.ones(len(a), int)
    c = 0
    for i in range(len(a)):
        if lab[i] >= 0:
            continue
        lab[i], st = c, [i]
        while st:
            k = st.pop()
            near = np.maximum(np.abs(a[:, 0] - a[k, 0]) - a[:, 2] - a[k, 2],
                              np.abs(a[:, 1] - a[k, 1]) - a[:, 3] - a[k, 3]) <= 160
            for j in np.where(near & (lab < 0))[0]:
                lab[j] = c
                st.append(j)
        c += 1
    fpa = 4 * a[:, 2] * a[:, 3]
    m = lab == np.bincount(lab, weights=fpa).argmax()
    area = hull_area([(x + sx * hx, z + sz * hz) for x, z, hx, hz in a[m] for sx in (-1, 1) for sz in (-1, 1)])
    e = e_sq = mc = m_sq = 0.0
    kinds = collections.Counter()
    for b in blds:
        sq = (b[2] / 8) * (b[3] / 8)
        eo, mo = output(b[4])
        if eo > 0:
            e, e_sq = e + eo, e_sq + sq
            kinds[b[4]] += sq
        if mo > 0:
            mc, m_sq = mc + mo, m_sq + sq
    top = ",".join(k for k, _ in kinds.most_common(2))
    return ((gaps < 0.5).mean(), ((gaps >= 0.5) & (gaps < 2.5)).mean(), 1 - fpa[m].sum() / area if area else 0.0,
            e / e_sq if e_sq else 0.0, mc / m_sq if m_sq else 0.0, top)


def audit(path, minutes):
    p = Path(path)
    if p.is_dir():
        p = p / "orders.txt.gz"
    defs, teams, done = {}, {}, set()
    fin = collections.defaultdict(collections.Counter)
    first_t3, last = {}, 0
    snap = {mm: {} for mm in minutes}
    with gzip.open(p, "rt", errors="replace") as f:
        for ln in f:
            if ln.startswith("U "):
                v = ln.split()
                fr, uid, d, team, build = int(v[1]), int(v[2]), int(v[3]), int(v[4]), float(v[10])
                last = fr
                if d not in defs or build < 1.0:
                    continue
                for mm in minutes:
                    if mm * 1800 - 300 < fr <= mm * 1800:
                        snap[mm][uid] = (team, d, float(v[5]), float(v[6]))
                if uid in done:
                    continue
                done.add(uid)
                name, cls, metal, gdps, adps = defs[d]
                k = "air" if cls == "air" else "aa" if adps > 0 and adps >= gdps else \
                    "t3" if name in GANTRY_BUILDS and metal >= 1500 else "other"
                fin[team][k] += metal
                if k == "t3":
                    first_t3.setdefault(team, fr / 1800)
            elif ln.startswith("D "):
                v = ln.split()
                defs[int(v[1])] = (v[2], v[3], float(v[4]), float(v[8]), float(v[9]))
            elif ln.startswith("T "):
                v = ln.split()
                teams[int(v[1])] = (int(v[2]), v[3] == "true")
    lay = {}
    for mm, units in snap.items():
        per = collections.defaultdict(list)
        for team, d, x, z in units.values():
            name, cls = defs[d][:2]
            if cls == "static" and not any(s in name for s in ("mex", "moho", "geo")) and not name.endswith("_meteor"):
                fx, fz = foot(name)
                per[team].append((x, z, fx * 8.0, fz * 8.0, name))
        for t, blds in per.items():
            if len(blds) >= 5:
                lay[t, mm] = layout(blds)
    print("== %s (%.0f min)" % (p.parent.name[:70], last / 1800))
    hdr = "  seat side  finished   air  AA   T3 firstT3"
    for mm in minutes:
        hdr += " | m%d flush gap1-2 open  E/sq  m/sq" % mm
    print(hdr)
    rows = sorted((t for t in teams if t in fin), key=lambda t: -sum(fin[t].values()))
    for t in rows:
        s = sum(fin[t].values()) or 1
        line = "  %4d %-5s %7dk %4.0f%% %3.0f%% %3.0f%% %7s" % (
            t, "AI" if teams[t][1] else "human", s // 1000, 100 * fin[t]["air"] / s, 100 * fin[t]["aa"] / s,
            100 * fin[t]["t3"] / s, "%.1f" % first_t3[t] if t in first_t3 else "-")
        for mm in minutes:
            if (t, mm) in lay:
                fl, sg, op, e, mc, top = lay[t, mm]
                line += " |    %3.0f%%   %3.0f%%  %3.0f%% %5.1f %5.2f" % (100 * fl, 100 * sg, 100 * op, e, mc)
            else:
                line += " |       -      -     -     -     -"
        print(line)
    for who in (False, True):
        side = [t for t in rows if teams[t][1] == who]
        if side:
            best = side[0]
            print("  best %s seat %d: %dk finished (side median %dk)" % (
                "AI" if who else "human", best, sum(fin[best].values()) // 1000,
                int(np.median([sum(fin[t].values()) for t in side])) // 1000))


if __name__ == "__main__":
    args = [x for x in sys.argv[1:] if not x.startswith("--")]
    mins = [int(x) for x in (sys.argv[sys.argv.index("--minutes") + 1].split(",") if "--minutes" in sys.argv else
                             ("20", "30"))]
    args = [x for x in args if not re.fullmatch(r"[\d,]+", x)]
    for a in args:
        audit(a, mins)
