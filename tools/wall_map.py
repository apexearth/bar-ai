#!/usr/bin/env python3
"""Draw the wall: an SVG map of towers vs buildings for every player.

apexearth 2026-08-30: "The svg was useful - it serves as good proof if we
actually have a wall or not." This is that proof, one command per match:
circles are static defence, squares are everything else, colour is the
allyteam. Read it next to `wall_check.py` (the numbers) -- a wall is a band
of circles along the outside of the squares, a blob is the failure.

Usage:
    python tools/wall_map.py <match-dir> [--minute M] [-o out.svg]

With --minute it draws the snapshot nearest that game minute (default: the
last one). Prints the SVG to stdout so the dashboard renders it inline;
-o also writes it to a file. A tournament dir resolves to its first match.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from defence_pos import defence_defs  # noqa: E402

POS_RE = re.compile(r"\[BARAI_POS\] team=(\d+) ally=(\d+) frame=(\d+) n=\d+(?: part=\d+/\d+)? (\S*)")
SIZE = 760
# (tower, building) fill per allyteam; further allies cycle.
PALETTE = [("#d02020", "#3060c0"), ("#e08800", "#909090"),
           ("#209040", "#70a070"), ("#8040c0", "#a090c0")]


def find_stdout(target: Path) -> Path:
    if (target / "stdout.txt").exists():
        return target / "stdout.txt"
    for sub in ("matches",):
        d = target / sub
        if d.is_dir():
            for m in sorted(d.iterdir()):
                if (m / "stdout.txt").exists():
                    return m / "stdout.txt"
    sys.exit(f"no stdout.txt under {target}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("match")
    ap.add_argument("--minute", type=float, default=None,
                    help="draw the snapshot nearest this game minute")
    ap.add_argument("-o", "--out", default=None)
    args = ap.parse_args()
    stdout = find_stdout(Path(args.match))
    ddefs = defence_defs()

    snaps: dict[int, list] = {}
    ally_of: dict[int, int] = {}
    for line in stdout.read_text(errors="replace").splitlines():
        m = POS_RE.search(line)
        if not m:
            continue
        t = int(m.group(1))
        ally_of[t] = int(m.group(2))
        fr = int(m.group(3))
        lst = snaps.setdefault(t, [])
        if lst and lst[-1][0] == fr:
            lst[-1] = (fr, lst[-1][1] + "," + m.group(4))
        else:
            lst.append((fr, m.group(4)))
    if not snaps:
        sys.exit("no [BARAI_POS] telemetry (dev gadgets installed?)")

    target_f = None if args.minute is None else int(args.minute * 60 * 30)
    els, mx, used_f = [], 1.0, 0
    counts: dict[int, int] = {}
    for t, rows in snaps.items():
        row = rows[-1] if target_f is None else min(
            rows, key=lambda r: abs(r[0] - target_f))
        used_f = max(used_f, row[0])
        for tok in row[1].split(','):
            p = tok.split(':')
            if len(p) < 3:
                continue
            n, x, z = p[0], float(p[1]), float(p[2])
            mx = max(mx, x, z)
            isdef = n in ddefs
            if isdef:
                counts[ally_of[t]] = counts.get(ally_of[t], 0) + 1
            els.append((isdef, x, z, ally_of[t]))
    mx *= 1.05

    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" '
           f'height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">'
           f'<rect width="{SIZE}" height="{SIZE}" fill="#f2efe6"/>']
    # Buildings under towers, so the wall reads on top.
    for pass_def in (False, True):
        for isdef, x, z, a in els:
            if isdef != pass_def:
                continue
            sx, sz = x / mx * SIZE, z / mx * SIZE
            tw, bd = PALETTE[a % len(PALETTE)]
            if isdef:
                svg.append(f'<circle cx="{sx:.0f}" cy="{sz:.0f}" r="6" '
                           f'fill="{tw}" stroke="#000" stroke-width="0.7"/>')
            else:
                svg.append(f'<rect x="{sx - 2:.0f}" y="{sz - 2:.0f}" '
                           f'width="4" height="4" fill="{bd}" opacity="0.55"/>')
    label = " · ".join(f"ally{a}: {n} towers"
                       for a, n in sorted(counts.items())) or "no towers"
    svg.append(f'<text x="10" y="20" font-family="monospace" font-size="13">'
               f'@{used_f / 1800:.1f}min — circles=towers, squares=buildings — '
               f'{label}</text></svg>')
    out = "".join(svg)
    if args.out:
        Path(args.out).write_text(out, encoding="utf-8")
    print(out)


if __name__ == "__main__":
    main()
