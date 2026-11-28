#!/usr/bin/env python3
"""A game over time, as pictures (his 11-19: "a render of the map over time and just watch it ... you know best of your
own capabilities"). I read still images, not video, so:

    python tools/armynet/timelapse.py <match-dir> [--every 1] [--gif-every 10]

  lane.png       time across, place along the line from our start (0) to theirs (1) up the side: every army unit at
                 every 10-s snapshot, deaths as x, lost buildings as squares; below it metal lost per minute by kind
                 and each side's army and income. A held line, a push, a retreat and a chase each have a shape here.
  film-N.png     the map every --every minutes, 12 frames a sheet: units with their last 60 s as a trail, buildings,
                 deaths in the minute before.
  timelapse.gif  the map every --gif-every seconds, 500 px, for him to play.

Side A (blue, ally 0) is the model's army in an armynet watch game.
"""
import math
import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import mapframe  # noqa: E402
import story  # noqa: E402
from defence_pos import defence_defs  # noqa: E402

FPS = 30
COL = {0: (37, 99, 235), 1: (220, 38, 38)}
LIGHT = {0: (147, 180, 245), 1: (240, 150, 150)}


class Game:
    def __init__(self, md):
        self.deaths, self.starts, self.costs, self.snaps, self.ally, self.inc, self.pos = mapframe.load(md)
        self.snap_frames = sorted(self.snaps)
        self.pos_frames = sorted(self.pos)
        self.defs = set(defence_defs()) if callable(defence_defs) else set(defence_defs)
        mx = mz = 1.0
        for x, z in self.starts.values():
            mx, mz = max(mx, x), max(mz, z)
        for d in self.deaths:
            mx, mz = max(mx, d.x), max(mz, d.z)
        for f in self.snap_frames[:80]:
            for units in self.snaps[f].values():
                for (_, _n, x, z, _h) in units:
                    mx, mz = max(mx, x), max(mz, z)
        self.mx, self.mz = math.ceil(mx / 1024.0) * 1024, math.ceil(mz / 1024.0) * 1024
        self.end = max(self.snap_frames + [d.frame for d in self.deaths] + [1])
        side = {}
        for t, s in self.ally.items():
            side.setdefault(s, t)
        self.home = {s: self.starts.get(side.get(s, s), (0, 0)) for s in (0, 1)}

    def along(self, x, z):
        (hx, hz), (ex, ez) = self.home[0], self.home[1]
        ax, az = ex - hx, ez - hz
        return ((x - hx) * ax + (z - hz) * az) / max(ax * ax + az * az, 1)

    def snap_at(self, fr):
        i = max(0, min(len(self.snap_frames) - 1, _bisect(self.snap_frames, fr)))
        return self.snap_frames[i] if self.snap_frames else None


def _bisect(xs, v):
    lo, hi = 0, len(xs)
    while lo < hi:
        m = (lo + hi) // 2
        if xs[m] <= v:
            lo = m + 1
        else:
            hi = m
    return lo - 1


def fonts(n=13):
    try:
        return ImageFont.truetype("arial.ttf", n), ImageFont.truetype("arial.ttf", max(9, n - 3))
    except OSError:
        f = ImageFont.load_default()
        return f, f


def draw_frame(g, fr, S, trail_s=60, death_s=60):
    img = Image.new("RGB", (S, S + 30), (255, 255, 255))
    d = ImageDraw.Draw(img)
    font, small = fonts(13 if S >= 400 else 11)
    sx, sz = S / g.mx, S / g.mz
    oy = 30
    d.rectangle([0, oy, S - 1, oy + S - 1], fill=(242, 239, 230), outline=(120, 120, 120))
    for s, (x, z) in g.home.items():
        d.rectangle([x * sx - 4, oy + z * sz - 4, x * sx + 4, oy + z * sz + 4], outline=COL[s], width=2)
    pf = [f for f in g.pos_frames if f <= fr]
    mex = {0: 0, 1: 0}
    if pf:
        for t, items in g.pos[pf[-1]].items():
            s = g.ally.get(t)
            if s is None:
                continue
            for (name, x, z) in items:
                px, py = x * sx, oy + z * sz
                cat = story.category(name)
                if cat == "mex":
                    mex[s] += 1
                    d.polygon([(px, py - 3), (px + 3, py), (px, py + 3), (px - 3, py)], fill=COL[s])
                elif name in g.defs or cat == "def":
                    d.ellipse([px - 3, py - 3, px + 3, py + 3], outline=COL[s], width=1)
                else:
                    d.rectangle([px - 1, py - 1, px + 1, py + 1], fill=LIGHT[s])
    for de in g.deaths:
        if fr - death_s * FPS <= de.frame <= fr and de.built and de.team in g.ally:
            c = COL[g.ally[de.team]]
            px, py = de.x * sx, oy + de.z * sz
            r = 2 + min(5, int(math.sqrt(g.costs.get(de.unit, de.cost)) / 7))
            if de.mob:
                d.line([px - r, py - r, px + r, py + r], fill=c, width=2)
                d.line([px - r, py + r, px + r, py - r], fill=c, width=2)
            else:
                d.rectangle([px - r, py - r, px + r, py + r], outline=(0, 0, 0), fill=c)
    # trails: each unit's positions over the last trail_s seconds
    hist = defaultdict(list)
    lo = _bisect(g.snap_frames, fr - trail_s * FPS)
    hi = _bisect(g.snap_frames, fr)
    for f in g.snap_frames[max(0, lo):hi + 1]:
        for t, units in g.snaps[f].items():
            for (uid, name, x, z, hp) in units:
                hist[(t, uid)].append((x, z, name, hp))
    army = {0: 0.0, 1: 0.0}
    cur = g.snap_frames[hi] if hi >= 0 else None
    for (t, uid), pts in hist.items():
        s = g.ally.get(t)
        if s is None:
            continue
        if len(pts) > 1:
            d.line([(x * sx, oy + z * sz) for x, z, _n, _h in pts], fill=LIGHT[s], width=1)
        alive = cur is not None and any(u[0] == uid for u in g.snaps[cur].get(t, []))
        if not alive:
            continue
        x, z, name, hp = pts[-1]
        px, py = x * sx, oy + z * sz
        if name.endswith("com"):
            d.ellipse([px - 4, py - 4, px + 4, py + 4], outline=(0, 0, 0), fill=COL[s], width=2)
            continue
        c = g.costs.get(name, 0)
        army[s] += c
        r = 1.5 + min(5, math.sqrt(max(c, 1)) / 9)
        d.ellipse([px - r, py - r, px + r, py + r], fill=COL[s])
    d.text((4, 2), "%.1f min" % (fr / 1800.0), fill=(0, 0, 0), font=font)
    d.text((S * 0.28, 2), "A army %.0fk mex %d" % (army[0] / 1000, mex[0]), fill=COL[0], font=small)
    d.text((S * 0.64, 2), "B army %.0fk mex %d" % (army[1] / 1000, mex[1]), fill=COL[1], font=small)
    return img


def film(g, md, every):
    frames = [int(m * 1800) for m in _range(every, g.end / 1800.0, every)]
    S, cols, per = 300, 4, 12
    out = []
    for k in range(0, len(frames), per):
        chunk = frames[k:k + per]
        rows = (len(chunk) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * S, rows * (S + 30)), (255, 255, 255))
        for i, fr in enumerate(chunk):
            sheet.paste(draw_frame(g, fr, S), ((i % cols) * S, (i // cols) * (S + 30)))
        p = md / ("film-%d.png" % (k // per + 1))
        sheet.save(p)
        out.append(p)
    return out


def gif(g, md, every_s):
    frames = [draw_frame(g, fr, 500, trail_s=40, death_s=20).convert("P", palette=Image.ADAPTIVE, colors=64)
              for fr in range(every_s * FPS, g.end + 1, every_s * FPS)]
    p = md / "timelapse.gif"
    if frames:
        frames[0].save(p, save_all=True, append_images=frames[1:], duration=150, loop=0, optimize=True)
    return p


def _range(a, b, step):
    v = a
    while v <= b + 1e-9:
        yield v
        v += step


def lane(g, md):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    kinds = ("army", "builders", "economy", "defence", "other")
    fig, axs = plt.subplots(3, 1, figsize=(15, 11), sharex=True, gridspec_kw={"height_ratios": [3, 1.3, 1]})
    ax = axs[0]
    for s in (0, 1):
        ts, fs, ss = [], [], []
        for f in g.snap_frames:
            for t, units in g.snaps[f].items():
                if g.ally.get(t) != s:
                    continue
                for (_u, name, x, z, _h) in units:
                    if name in story.BUILDERS:
                        continue
                    ts.append(f / 1800.0)
                    fs.append(g.along(x, z))
                    ss.append(max(1.5, min(40, g.costs.get(name, 0) / 40)))
        ax.scatter(ts, fs, s=ss, color=[c / 255 for c in COL[s]], alpha=0.25, linewidths=0,
                   label="%s army units" % ("A (model)" if s == 0 else "B"))
    for s in (0, 1):
        mob = [de for de in g.deaths if g.ally.get(de.team) == s and de.mob and de.atkteam >= 0 and de.atkteam != de.team]
        ax.scatter([de.frame / 1800.0 for de in mob], [g.along(de.x, de.z) for de in mob], marker="x", s=14,
                   color=[c / 255 for c in COL[s]], linewidths=0.8)
        bld = [de for de in g.deaths if g.ally.get(de.team) == s and not de.mob and de.atkteam >= 0 and de.atkteam != de.team]
        ax.scatter([de.frame / 1800.0 for de in bld], [g.along(de.x, de.z) for de in bld], marker="s", s=22,
                   color=[c / 255 for c in COL[s]], edgecolors="black", linewidths=0.4)
    ax.axhline(0, color=[c / 255 for c in COL[0]], lw=0.8, ls=":")
    ax.axhline(1, color=[c / 255 for c in COL[1]], lw=0.8, ls=":")
    ax.axhline(0.5, color="grey", lw=0.6, ls=":")
    ax.set_ylabel("place: 0 = A's start, 1 = B's start")
    ax.set_ylim(-0.25, 1.25)
    ax.legend(loc="upper left", fontsize=8)
    ax.set_title("Army units by place on the A-B line over time (dots); units lost (x), buildings lost (squares)")
    # metal lost per minute by kind
    ax = axs[1]
    nmin = int(g.end / 1800) + 1
    eco = mapframe.story.category
    import numpy as np
    bottom = {0: np.zeros(nmin), 1: np.zeros(nmin)}
    shades = {"army": 1.0, "builders": 0.75, "economy": 0.55, "defence": 0.4, "other": 0.25}
    for k in kinds:
        for s in (0, 1):
            v = np.zeros(nmin)
            for de in g.deaths:
                if g.ally.get(de.team) != s or de.atkteam < 0 or de.atkteam == de.team:
                    continue
                cat = eco(de.unit)
                kind = ("army" if de.unit not in story.BUILDERS else "builders") if de.mob else (
                    "economy" if cat in ("mex", "conv", "energy") else ("defence" if de.unit in g.defs or cat == "def"
                                                                      else "other"))
                if kind == k:
                    v[min(nmin - 1, int(de.frame / 1800))] += de.cost
            sign = -1 if s == 0 else 1
            col = tuple(c / 255 for c in COL[s]) + (shades[k],)
            ax.bar(np.arange(nmin) + 0.5, sign * v, bottom=sign * bottom[s], width=0.9, color=col,
                   label="%s %s" % ("A" if s == 0 else "B", k))
            bottom[s] += v
    ax.axhline(0, color="black", lw=0.6)
    ax.set_ylabel("metal lost / min\n(A below, B above)")
    ax.legend(loc="upper left", fontsize=7, ncol=5)
    # army and income
    ax = axs[2]
    for s in (0, 1):
        ts, av = [], []
        for f in g.snap_frames:
            tot = sum(g.costs.get(n, 0) for t, us in g.snaps[f].items() if g.ally.get(t) == s for (_u, n, _x, _z, _h) in us
                      if n not in story.BUILDERS)
            ts.append(f / 1800.0)
            av.append(tot / 1000)
        ax.plot(ts, av, color=[c / 255 for c in COL[s]], lw=1.5, label="%s army (k metal)" % ("A" if s == 0 else "B"))
        fi = sorted(g.inc)
        ax.plot([f / 1800.0 for f in fi], [sum(v for t, v in g.inc[f].items() if g.ally.get(t) == s) / 10 for f in fi],
                color=[c / 255 for c in COL[s]], lw=1, ls="--", label="%s income / 10" % ("A" if s == 0 else "B"))
    ax.set_xlabel("minute")
    ax.legend(loc="upper left", fontsize=8, ncol=4)
    fig.tight_layout()
    p = md / "lane.png"
    fig.savefig(p, dpi=85)
    plt.close(fig)
    return p


def main(a):
    md = Path(a[0])
    every = float(a[a.index("--every") + 1]) if "--every" in a else 1.0
    gif_every = int(a[a.index("--gif-every") + 1]) if "--gif-every" in a else 10
    g = Game(md)
    print(lane(g, md))
    for p in film(g, md, every):
        print(p)
    if "--no-gif" not in a:
        print(gif(g, md, gif_every))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
