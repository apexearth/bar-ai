"""How tightly each side packs its army: the splash test.

His directive (docs/24): "curves and lines, never a ball" -- splash makes a ball
pay. Per sampled minute, per side (ally 0 = us), over units within FIGHT elmos of
any enemy unit (so only armies near contact count): the mean number of own
units within SPLASH elmos of each unit, and the share of units with 4+ there.

usage: python tools/armypacking.py <match-dir> [--from 6] [--to 20]
"""
import argparse
import re
from pathlib import Path

SPLASH = 150.0
FIGHT = 1200.0
ARMY_RE = re.compile(r"\[BARAI_ARMY\] frame=(\d+) team=(\d+) n=\d+ part=\d+/\d+ (\S*)")


def allies_of(md):
    txt = (md / "_script.txt") if (md / "_script.txt").exists() else (md / "script.txt")
    out, cur = {}, None
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


def grid(pts, cell):
    g = {}
    for i, (x, z) in enumerate(pts):
        g.setdefault((int(x // cell), int(z // cell)), []).append(i)
    return g


def near(g, pts, x, z, r, cell):
    n = 0
    cx, cz = int(x // cell), int(z // cell)
    k = int(r // cell) + 1
    for dx in range(-k, k + 1):
        for dz in range(-k, k + 1):
            for j in g.get((cx + dx, cz + dz), ()):
                px, pz = pts[j]
                if (px - x) ** 2 + (pz - z) ** 2 <= r * r:
                    n += 1
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("match")
    ap.add_argument("--from", dest="lo", type=float, default=6.0)
    ap.add_argument("--to", type=float, default=20.0)
    a = ap.parse_args()
    md = Path(a.match)
    log = md / "barai-gadgets.log"
    if not log.exists():
        log = md / "infolog.txt"
    ally = allies_of(md)
    samples = {}
    for f, t, data in ARMY_RE.findall(log.read_text(errors="replace")):
        f = int(f)
        s = 0 if ally.get(int(t), -1) == 0 else 1
        b = samples.setdefault(f, ([], []))[s]
        for tok in data.split(","):
            p = tok.split(":")
            if len(p) < 4 or p[1].endswith("com"):
                continue
            try:
                b.append((float(p[2]), float(p[3])))
            except ValueError:
                pass
    print(" min | side | in contact | mean own within 150 | share with 4+")
    acc = {}
    for f in sorted(samples):
        m = int(f // 1800)
        if m < a.lo or m > a.to:
            continue
        for s in (0, 1):
            own, foe = samples[f][s], samples[f][1 - s]
            if not own or not foe:
                continue
            go, gf = grid(own, SPLASH), grid(foe, FIGHT)
            for x, z in own:
                if near(gf, foe, x, z, FIGHT, FIGHT) == 0:
                    continue
                k = near(go, own, x, z, SPLASH, SPLASH) - 1
                r = acc.setdefault((m, s), [0, 0, 0])
                r[0] += 1
                r[1] += k
                r[2] += 1 if k >= 4 else 0
    for (m, s), (n, k, b) in sorted(acc.items()):
        if m % 2:
            continue
        print(f" {m:3d} | {'us  ' if s == 0 else 'them'} | {n:10d} | {k / n:19.2f} | {b / n:12.2f}")


if __name__ == "__main__":
    main()
