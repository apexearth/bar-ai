"""How each side arrives at its big fights: together, or a trickle.

His complaint (2026-10-01): "when we do have some of them on the front line, it's
usually a smaller group... one squad versus five squads... we just trickle in one
by one and die." Team games: ally team 0 is "us", any other is "them".

Big fights are deaths of mobile units clustered in space (LINK elmos) and time
(GAP seconds) whose metal lost totals at least --min. For each, every BARAI_ARMY
sample from 30 s before its first death to its last: each side's army metal within
R elmos of the fight's centre, and the metal each side lost in that slice.

usage: python tools/fightarrival.py <match-dir> [--min 4000] [--from 6] [--to 20]
"""
import argparse
import math
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from battles import load_cost_table  # noqa: E402

LINK = 1200.0
GAP = 25 * 30
R = 1500.0
DEATH_RE = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\S+) cost=(\d+) x=(-?[\d.]+) z=(-?[\d.]+) .*? mob=(\d)")
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("match")
    ap.add_argument("--min", type=float, default=4000.0)
    ap.add_argument("--from", dest="lo", type=float, default=6.0)
    ap.add_argument("--to", type=float, default=20.0)
    a = ap.parse_args()
    md = Path(a.match)
    log = md / "barai-gadgets.log"
    if not log.exists():
        log = md / "infolog.txt"
    text = log.read_text(errors="replace")
    ally = allies_of(md)
    costs = load_cost_table()
    side = lambda t: 0 if ally.get(t, -1) == 0 else 1  # noqa: E731
    deaths = []
    for f, t, u, c, x, z, mob in DEATH_RE.findall(text):
        f = int(f)
        if mob != "1" or not (a.lo * 1800 <= f <= a.to * 1800) or u.endswith("com"):
            continue
        deaths.append((f, side(int(t)), float(c), float(x), float(z)))
    deaths.sort()
    fights = []
    for d in deaths:
        for fi in fights:
            if d[0] - fi["last"] <= GAP and math.hypot(d[3] - fi["cx"], d[4] - fi["cz"]) <= LINK:
                fi["d"].append(d)
                fi["last"] = d[0]
                w = sum(x[2] for x in fi["d"])
                fi["cx"] = sum(x[3] * x[2] for x in fi["d"]) / max(w, 1)
                fi["cz"] = sum(x[4] * x[2] for x in fi["d"]) / max(w, 1)
                break
        else:
            fights.append({"d": [d], "last": d[0], "cx": d[3], "cz": d[4]})
    samples = {}
    for f, t, data in ARMY_RE.findall(text):
        f = int(f)
        s = side(int(t))
        b = samples.setdefault(f, [[], []])[s]
        for tok in data.split(","):
            p = tok.split(":")
            if len(p) < 4 or p[1].endswith("com"):
                continue
            try:
                b.append((float(p[2]), float(p[3]), float(costs.get(p[1], 0) or 0)))
            except ValueError:
                pass
    frames = sorted(samples)
    for fi in fights:
        lost = [sum(x[2] for x in fi["d"] if x[1] == s) for s in (0, 1)]
        if sum(lost) < a.min:
            continue
        f0, f1 = fi["d"][0][0], fi["last"]
        print(f"== fight {f0 / 1800:.1f}-{f1 / 1800:.1f} min at {fi['cx']:.0f},{fi['cz']:.0f}"
              f"   us lost {lost[0]:.0f}  them lost {lost[1]:.0f}")
        print("     t(s) |  us near  them near | us lost  them lost")
        for f in frames:
            if f < f0 - 900 or f > f1 + 1:
                continue
            near = [sum(m for x, z, m in samples[f][s] if math.hypot(x - fi["cx"], z - fi["cz"]) <= R)
                    for s in (0, 1)]
            sl = [sum(x[2] for x in fi["d"] if x[1] == s and f - 300 < x[0] <= f) for s in (0, 1)]
            print(f"   {(f - f0) / 30:6.0f} | {near[0]:7.0f}  {near[1]:8.0f} | {sl[0]:7.0f}  {sl[1]:8.0f}")


if __name__ == "__main__":
    main()
