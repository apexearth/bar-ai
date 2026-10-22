"""How closely a game's base follows its turret zones: the share of turrets standing on a strip, and of eco
buildings (generators, converters, stores) standing in a strip's band -- inside the reach of the strip's turrets.

    python tools/zonecheck.py <match dir> [--minute 20] [--reach 400]"""
import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from baseplot import kind, read  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("match")
    ap.add_argument("--minute", type=float, default=20)
    ap.add_argument("--reach", type=float, default=400)
    a = ap.parse_args()
    items, foot, zones = read(a.match, a.minute)
    if not zones:
        print(f"{Path(a.match).name}: no zones")
        return

    def strip_dist(x, z):
        best = (1e9, 1e9)
        for x1, z1, x2, z2 in zones:
            lo_x, hi_x, lo_z, hi_z = min(x1, x2), max(x1, x2), min(z1, z2), max(z1, z2)
            dx = max(lo_x - x, 0, x - hi_x)
            dz = max(lo_z - z, 0, z - hi_z)
            d = (dx * dx + dz * dz) ** 0.5
            if d < best[0]:
                best = (d, 0)
        return best[0]

    t_on = t_all = e_in = e_all = 0
    for u, x, z in items:
        k = kind(u)
        d = strip_dist(x, z)
        if k == "turret":
            t_all += 1
            t_on += d <= 8
        elif k in ("energy", "converter", "storage"):
            e_all += 1
            e_in += d <= a.reach
    print(f"{Path(a.match).name} m{a.minute:g}: strips={len(zones)} turrets on strip {t_on}/{t_all}"
          f" ({100 * t_on // max(1, t_all)}%), eco in a band {e_in}/{e_all} ({100 * e_in // max(1, e_all)}%)")


if __name__ == "__main__":
    main()
