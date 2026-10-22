"""Draw how a game's base stands: team 0's buildings at their engine footprints, after transport moves and deaths,
with the turret zones the AI planned hatched over them.

    python tools/baseplot.py <match dir> <out.png> [--minute 20]
    python tools/baseplot.py --sheet <out.png> [--minute 20] [--cols 4] <match dir> <match dir> ...

Colours are by kind -- turret, energy, converter, storage, extractor, plant, other -- so every picture reads alike.
Footprints come from the AI's own lattice lines (apex: lattice <def> foot=AxB); a def without one falls back to the
unit file's footprint."""
import argparse
import glob
import re
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Patch, Rectangle  # noqa: E402

UNITS = Path.home() / "AppData/Local/Programs/Beyond-All-Reason/data/games/BAR.sdd/units"
BUILD = re.compile(r"BARAI_BUILD\] team=0 .*?frame=(\d+) .*?unit=([a-z0-9_]+) .*?x=(-?\d+) z=(-?\d+) uid=(\d+)")
DEATH = re.compile(r"BARAI_DEATH\] frame=(\d+) team=0 unit=[a-z0-9_]+ .*?uid=(\d+)")
MOVE = re.compile(r"\[f=0*(\d+)\].*apex: relocated [a-z0-9_]+ #(\d+) [-0-9,]+ -> (-?\d+),(-?\d+)")
LATTICE = re.compile(r"apex: lattice ([a-z0-9_]+) foot=(\d+)x(\d+)")
ZONE = re.compile(r"\[f=0*(\d+)\].*apex: zone t=0 #(\d+) (-?\d+),(-?\d+) \.\. (-?\d+),(-?\d+)")

KINDS = [("turret", "#3ca951"), ("energy", "#efb118"), ("converter", "#a463f2"), ("storage", "#9498a0"),
         ("extractor", "#4269d0"), ("plant", "#ff725c"), ("other", "#6cc5b0")]
COLOR = dict(KINDS)


def kind(u):
    if "nanotc" in u:
        return "turret"
    if re.search(r"(sol|fus|win|tide|geo)", u):
        return "energy"
    if re.search(r"(makr|mmkr|fmkr)", u):
        return "converter"
    if re.search(r"(estor|mstor|uwes|uwms)", u):
        return "storage"
    if re.search(r"(mex|moho)", u):
        return "extractor"
    if re.fullmatch(r"(arm|cor|leg)(a?ap|a?lab|a?vp|a?sy|hp|fhp|amsub|shltx|gant|a?plat)[a-z0-9]*", u):
        return "plant"
    return "other"


_unit_foot = {}


def unit_foot(u):
    if u not in _unit_foot:
        hits = glob.glob(str(UNITS / "**" / (u + ".lua")), recursive=True)
        txt = open(hits[0], encoding="utf-8", errors="replace").read() if hits else ""
        fx = re.search(r"footprintx\s*=\s*(\d+)", txt, re.I)
        fz = re.search(r"footprintz\s*=\s*(\d+)", txt, re.I)
        _unit_foot[u] = (int(fx.group(1)) if fx else 2, int(fz.group(1)) if fz else 2)
    return _unit_foot[u]


def read(match_dir, minute):
    cut = minute * 1800 if minute else 1 << 40
    built, foot, zones = {}, {}, []
    for line in open(Path(match_dir) / "infolog.txt", encoding="utf-8", errors="replace"):
        m = LATTICE.search(line)
        if m:
            foot[m.group(1)] = (int(m.group(2)), int(m.group(3)))
            continue
        m = BUILD.search(line)
        if m:
            if int(m.group(1)) <= cut:
                built[m.group(5)] = [m.group(2), float(m.group(3)), float(m.group(4))]
            continue
        m = DEATH.search(line)
        if m:
            if int(m.group(1)) <= cut:
                built.pop(m.group(2), None)
            continue
        m = MOVE.search(line)
        if m:
            if (int(m.group(1)) <= cut) and (m.group(2) in built):
                built[m.group(2)][1:] = [float(m.group(3)), float(m.group(4))]
            continue
        m = ZONE.search(line)
        if m and int(m.group(1)) <= cut:
            zones.append(tuple(float(m.group(i)) for i in range(3, 7)))
    return list(built.values()), foot, zones


def draw(ax, match_dir, minute, title=None):
    items, foot, zones = read(match_dir, minute)
    eco = [(x, z) for u, x, z in items if kind(u) != "extractor"] or [(x, z) for _, x, z in items]
    if not eco:
        ax.set_title((title or Path(match_dir).name) + " (nothing built)", fontsize=8)
        return
    xs = sorted(x for x, _ in eco)
    zs = sorted(z for _, z in eco)
    cx, cz = xs[len(xs) // 2], zs[len(zs) // 2]
    for x1, z1, x2, z2 in zones:
        ax.add_patch(Rectangle((min(x1, x2), min(z1, z2)), abs(x2 - x1), abs(z2 - z1), facecolor="none",
                               edgecolor="#3ca951", hatch="///", linewidth=0.8, alpha=0.7))
    counts = {}
    for u, x, z in items:
        fx, fz = foot.get(u) or unit_foot(u)
        k = kind(u)
        counts[k] = counts.get(k, 0) + 1
        ax.add_patch(Rectangle((x - fx * 8, z - fz * 8), fx * 16, fz * 16, facecolor=COLOR[k],
                               edgecolor="#222", linewidth=0.25))
    ax.set_xlim(cx - 1100, cx + 1100)
    ax.set_ylim(cz + 1100, cz - 1100)
    ax.set_aspect("equal")
    ax.tick_params(labelsize=6)
    head = title or Path(match_dir).name
    ax.set_title(head + (f"  m{minute}" if minute else "") + "\n"
                 + " ".join(f"{k}={counts[k]}" for k, _ in KINDS if k in counts), fontsize=7)


def legend(fig):
    fig.legend(handles=[Patch(facecolor=c, edgecolor="#222", label=k) for k, c in KINDS]
               + [Patch(facecolor="none", edgecolor="#3ca951", hatch="///", label="turret zone")],
               loc="lower center", ncol=8, fontsize=8, frameon=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--sheet", help="draw every match dir into one grid at this path")
    ap.add_argument("--minute", type=float, default=None)
    ap.add_argument("--cols", type=int, default=4)
    a = ap.parse_args()
    if a.sheet:
        dirs = a.paths
        cols = min(a.cols, len(dirs))
        rows = (len(dirs) + cols - 1) // cols
        fig, axes = plt.subplots(rows, cols, figsize=(4.2 * cols, 4.4 * rows), squeeze=False)
        for i, d in enumerate(dirs):
            draw(axes[i // cols][i % cols], d, a.minute)
        for j in range(len(dirs), rows * cols):
            axes[j // cols][j % cols].axis("off")
        legend(fig)
        fig.tight_layout(rect=(0, 0.03, 1, 1))
        fig.savefig(a.sheet, dpi=90)
        print("saved", a.sheet)
        return
    if len(a.paths) != 2:
        ap.error("give <match dir> <out.png>, or --sheet")
    fig, ax = plt.subplots(figsize=(9, 9.4))
    draw(ax, a.paths[0], a.minute)
    legend(fig)
    fig.tight_layout(rect=(0, 0.03, 1, 1))
    fig.savefig(a.paths[1], dpi=100)
    print("saved", a.paths[1])


if __name__ == "__main__":
    main()
