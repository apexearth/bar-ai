"""The game as pictures: one map frame per chosen minute, on a contact sheet.

apexearth 2026-09-19: "You could visualize the game minute by minute perhaps
and then get a good understanding of the state?" This is that -- a PNG the
model can read, from the same gadget lines story.py reads.

    python tools/mapframe.py <match-dir> [--minutes 4,8,12,16,20,24] [-o out.png]
    python tools/mapframe.py <match-dir> --every 2 --to 30      # every 2 min

Per frame: the first spec (ally 0) is blue, the second red -- the header names them. Squares are buildings (larger for
plants), diamonds are mexes/mohos, rings are static defence, dots are mobile
army (area ~ metal), stars are commanders, x marks are deaths in the two
minutes before the frame (coloured by the side that lost them). The header
carries minute, income, standing army metal and mex count per side. Grid
lines every 2048 elmos.
"""
import argparse
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import battles  # noqa: E402
import story  # noqa: E402
from defence_pos import defence_defs  # noqa: E402

FPS = 30
COL = {0: (40, 90, 200), 1: (200, 40, 40)}
COL_LIGHT = {0: (140, 170, 235), 1: (235, 150, 150)}


def load(md):
    text = (md / "infolog.txt").read_text("utf-8", errors="replace")
    deaths, starts, costs, snaps = battles.parse(text)
    ally = {}
    inc = defaultdict(dict)
    for t, a, f, mi in re.findall(r"\[BARAI_STATS\] team=(\d+) ally=(\d+) \S+ frame=(\d+).*? mInc=([\d.]+)", text):
        ally[int(t)] = int(a)
        inc[int(f)][int(t)] = float(mi)
    pos = defaultdict(lambda: defaultdict(list))
    for t, a, f, data in story.POS_RE.findall(text):
        ally[int(t)] = int(a)
        for tok in data.split(","):
            p = tok.split(":")
            if len(p) >= 3:
                pos[int(f)][int(t)].append((p[0], int(p[1]), int(p[2])))
    return deaths, starts, costs, snaps, ally, inc, pos


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("match")
    ap.add_argument("--minutes", default="")
    ap.add_argument("--every", type=float, default=0)
    ap.add_argument("--to", type=float, default=30)
    ap.add_argument("--size", type=int, default=520, help="pixels per frame")
    ap.add_argument("-o", "--out", default="")
    args = ap.parse_args()
    md = Path(args.match)
    deaths, starts, costs, snaps, ally, inc, pos = load(md)
    # the ally index is the spec index (S16)
    specs = []
    try:
        import json
        specs = [t.get("spec", "?")[:22] for t in json.loads((md / "result.json").read_text()).get("teams", [])]
    except (OSError, ValueError):
        pass
    label = {s: (specs[s] if s < len(specs) else "ally%d" % s) for s in (0, 1)}
    if args.minutes:
        minutes = [float(m) for m in args.minutes.split(",")]
    elif args.every > 0:
        minutes = [m for m in [args.every * i for i in range(1, 200)] if m <= args.to]
    else:
        minutes = [4, 8, 12, 16, 20, 24]
    last = max(list(snaps) + [d.frame for d in deaths] + [0]) / (FPS * 60.0)
    minutes = [m for m in minutes if m <= last + 0.5] or [last]
    defs = set(defence_defs()) if callable(defence_defs) else set(defence_defs)
    # map extent from everything that has a coordinate
    mx = mz = 1.0
    for (x, z) in starts.values():
        mx, mz = max(mx, x), max(mz, z)
    for d in deaths:
        mx, mz = max(mx, d.x), max(mz, d.z)
    for f in list(snaps)[:50]:
        for units in snaps[f].values():
            for (_, n, x, z, hp) in units:
                mx, mz = max(mx, x), max(mz, z)
    mx = math.ceil(mx / 1024.0) * 1024
    mz = math.ceil(mz / 1024.0) * 1024
    S = args.size
    sx, sz = S / mx, S / mz
    cols = 3 if len(minutes) > 4 else max(1, len(minutes))
    rows = (len(minutes) + cols - 1) // cols
    head = 44
    img = Image.new("RGB", (cols * S, rows * (S + head)), (255, 255, 255))
    drw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("arial.ttf", 14)
        small = ImageFont.truetype("arial.ttf", 11)
    except OSError:
        font = small = ImageFont.load_default()
    snap_frames = sorted(snaps)
    pos_frames = sorted(pos)
    inc_frames = sorted(inc)
    teams_of = {s: [t for t in ally if ally[t] == s] for s in (0, 1)}

    for i, minute in enumerate(minutes):
        fr = int(minute * 60 * FPS)
        ox, oy = (i % cols) * S, (i // cols) * (S + head) + head
        drw.rectangle([ox, oy, ox + S - 1, oy + S - 1], fill=(242, 239, 230), outline=(120, 120, 120))
        for g in range(2048, int(max(mx, mz)), 2048):
            if g < mx:
                drw.line([ox + g * sx, oy, ox + g * sx, oy + S], fill=(220, 215, 205))
            if g < mz:
                drw.line([ox, oy + g * sz, ox + S, oy + g * sz], fill=(220, 215, 205))
        # deaths in the two minutes before the frame
        for d in deaths:
            if fr - 2 * 60 * FPS <= d.frame <= fr and d.built and ally.get(d.team) is not None:
                c = COL[ally[d.team]]
                px, py = ox + d.x * sx, oy + d.z * sz
                r = 2 + min(5, int(math.sqrt(costs.get(d.unit, d.cost)) / 6))
                drw.line([px - r, py - r, px + r, py + r], fill=c, width=1)
                drw.line([px - r, py + r, px + r, py - r], fill=c, width=1)
        # structures
        pf = [f for f in pos_frames if f <= fr]
        mexn = {0: 0, 1: 0}
        if pf:
            for t, items in pos[pf[-1]].items():
                s = ally.get(t)
                if s is None:
                    continue
                for (name, x, z) in items:
                    px, py = ox + x * sx, oy + z * sz
                    cat = story.category(name)
                    if cat == "mex":
                        mexn[s] += 1
                        r = 5
                        drw.polygon([(px, py - r), (px + r, py), (px, py + r), (px - r, py)], fill=COL[s], outline=(0, 0, 0))
                    elif name in defs or cat == "def":
                        drw.ellipse([px - 4, py - 4, px + 4, py + 4], outline=COL[s], width=2)
                    elif cat == "plant":
                        drw.rectangle([px - 6, py - 6, px + 6, py + 6], fill=COL[s], outline=(0, 0, 0))
                    else:
                        drw.rectangle([px - 2, py - 2, px + 2, py + 2], fill=COL_LIGHT[s])
        # army
        sf = [f for f in snap_frames if f <= fr]
        army = {0: 0.0, 1: 0.0}
        if sf:
            for t, units in snaps[sf[-1]].items():
                s = ally.get(t)
                if s is None:
                    continue
                for (_, name, x, z, hp) in units:
                    px, py = ox + x * sx, oy + z * sz
                    if name.endswith("com"):
                        drw.text((px - 5, py - 8), "*", fill=(0, 0, 0), font=font)
                        drw.ellipse([px - 4, py - 4, px + 4, py + 4], outline=COL[s], width=2)
                        continue
                    if name in story.BUILDERS:
                        drw.ellipse([px - 2, py - 2, px + 2, py + 2], outline=COL[s])
                        continue
                    c = costs.get(name, 0)
                    army[s] += c * hp / 100.0
                    r = 1.5 + min(6, math.sqrt(max(c, 1)) / 8)
                    drw.ellipse([px - r, py - r, px + r, py + r], fill=COL[s])
        # starts
        for t, (x, z) in starts.items():
            s = ally.get(t)
            if s is None:
                continue
            drw.rectangle([ox + x * sx - 3, oy + z * sz - 3, ox + x * sx + 3, oy + z * sz + 3], outline=COL[s], width=1)
        # header
        incf = [f for f in inc_frames if f <= fr]
        incs = {0: 0.0, 1: 0.0}
        if incf:
            for t, v in inc[incf[-1]].items():
                if ally.get(t) is not None:
                    incs[ally[t]] += v
        drw.rectangle([ox, oy - head, ox + S - 1, oy - 1], fill=(255, 255, 255))
        drw.text((ox + 6, oy - head + 4), "%.0f min" % minute, fill=(0, 0, 0), font=font)
        drw.text((ox + 70, oy - head + 4), "%s  inc %.0f  army %.0fk  mex %d" % (label[0], incs[0], army[0] / 1000, mexn[0]), fill=COL[0], font=small)
        drw.text((ox + 70, oy - head + 22), "%s  inc %.0f  army %.0fk  mex %d" % (label[1], incs[1], army[1] / 1000, mexn[1]), fill=COL[1], font=small)
    out = Path(args.out) if args.out else md / ("mapframe-%s.png" % "-".join("%g" % m for m in minutes[:6]))
    img.save(out)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
