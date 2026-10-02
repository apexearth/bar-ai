"""Where each side's army stands, minute by minute: one blob or pieces.

His complaint (2026-10-01): "The enemy puts all of their army together in the
front line... we trickle in one squad at a time." Read from the gadget's
BARAI_ARMY samples, per side (ally team), at each sampled minute:

  metal   army metal on the field (mobile, non-builder, units the sample lists)
  blob    share of that metal in the side's largest cluster (units within
          LINK elmos of each other chain into one cluster) -- 1.0 is one army
  fwd     metal-weighted mean position on the axis between the two sides'
          start centroids: 0 = own start, 1 = the enemy's
  home    share of army metal within HOME elmos of its own start centroid

usage: python tools/armyfront.py <match-dir> [--step 2] [--to 24]
"""
import argparse
import math
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from battles import load_cost_table  # noqa: E402

LINK = 700.0
HOME = 2500.0
START_RE = re.compile(r"\[BARAI_START\] team=(\d+) x=(-?\d+) z=(-?\d+)")
ARMY_RE = re.compile(r"\[BARAI_ARMY\] frame=(\d+) team=(\d+) n=\d+ part=\d+/\d+ (\S*)")


def allies_of(md):
    """team -> ally team, from the start script."""
    txt = (md / "_script.txt") if (md / "_script.txt").exists() else (md / "script.txt")
    out = {}
    cur = None
    for ln in txt.read_text(errors="replace").splitlines():
        m = re.match(r"\s*\[team(\d+)\]", ln, re.I)
        if m:
            cur = int(m.group(1))
            continue
        m = re.match(r"\s*allyteam=(\d+)", ln, re.I)
        if m and cur is not None:
            out[cur] = int(m.group(1))
            cur = None
    return out


def clusters(pts):
    """Largest single-link cluster's metal, pts = [(x, z, m)]."""
    n = len(pts)
    if n == 0:
        return 0.0
    cell = {}
    for i, (x, z, _) in enumerate(pts):
        cell.setdefault((int(x // LINK), int(z // LINK)), []).append(i)
    seen = [False] * n
    best = 0.0
    for s in range(n):
        if seen[s]:
            continue
        seen[s] = True
        stack = [s]
        tot = 0.0
        while stack:
            i = stack.pop()
            x, z, m = pts[i]
            tot += m
            cx, cz = int(x // LINK), int(z // LINK)
            for dx in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for j in cell.get((cx + dx, cz + dz), ()):
                        if not seen[j]:
                            xj, zj, _ = pts[j]
                            if (xj - x) ** 2 + (zj - z) ** 2 <= LINK * LINK:
                                seen[j] = True
                                stack.append(j)
        best = max(best, tot)
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("match")
    ap.add_argument("--step", type=float, default=2.0)
    ap.add_argument("--to", type=float, default=99.0)
    a = ap.parse_args()
    md = Path(a.match)
    log = md / "barai-gadgets.log"
    if not log.exists():
        log = md / "infolog.txt"
    text = log.read_text(errors="replace")
    ally = allies_of(md)
    costs = load_cost_table()
    starts = {}
    for t, x, z in START_RE.findall(text):
        starts[int(t)] = (float(x), float(z))
    sides = sorted(set(ally.values()))
    if len(sides) != 2:
        print("needs exactly two ally teams; found", sides)
        return
    cen = {}
    for s in sides:
        ps = [starts[t] for t, al in ally.items() if al == s and t in starts]
        cen[s] = (sum(p[0] for p in ps) / len(ps), sum(p[1] for p in ps) / len(ps))
    # frame -> side -> [(x, z, metal)]
    samples = {}
    for f, t, data in ARMY_RE.findall(text):
        f, t = int(f), int(t)
        if t not in ally:
            continue
        side = ally[t]
        bucket = samples.setdefault(f, {}).setdefault(side, [])
        for tok in data.split(","):
            p = tok.split(":")
            if len(p) < 4:
                continue
            name = p[1]
            if name.endswith("com") or "nanotc" in name:
                continue
            try:
                x, z = float(p[2]), float(p[3])
            except ValueError:
                continue
            bucket.append((x, z, float(costs.get(name, 0) or 0)))
    frames = sorted(samples)
    step = int(a.step * 1800)
    want = list(range(step, int(a.to * 1800) + 1, step))
    print(f"{md.name}   blob = share of army metal in the largest cluster (link {int(LINK)});"
          f" fwd 0 = own start, 1 = theirs; home = within {int(HOME)} of own start")
    print(" min | side   |  metal  blob   fwd  home")
    for w in want:
        f = min(frames, key=lambda fr: abs(fr - w)) if frames else None
        if f is None or abs(f - w) > 900:
            continue
        for s in sides:
            pts = samples[f].get(s, [])
            tot = sum(p[2] for p in pts)
            if tot <= 0:
                continue
            o = cen[s]
            e = cen[[q for q in sides if q != s][0]]
            ax, az = e[0] - o[0], e[1] - o[1]
            L2 = ax * ax + az * az
            fwd = sum(((x - o[0]) * ax + (z - o[1]) * az) / L2 * m for x, z, m in pts) / tot
            home = sum(m for x, z, m in pts if math.hypot(x - o[0], z - o[1]) <= HOME) / tot
            blob = clusters(pts) / tot
            tag = "us  " if s == 0 else "them"
            print(f" {w / 1800:3.0f} | {tag} a{s} | {tot:6.0f}  {blob:4.2f}  {fwd:4.2f}  {home:4.2f}")
        print("-" * 44)


if __name__ == "__main__":
    main()
