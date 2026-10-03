#!/usr/bin/env python3
"""Where each side's finished extractors died, and whether a gun stood beside them.

    python tools/mexdeaths.py <match-dir> [...] [--to 20] [--r 450]

Each finished extractor death ([BARAI_DEATH] built=1, not the T1 removed by its
own upgrade) is placed in a forward band (see mexguard.py) and checked against
the alliance's defence structures in the last [BARAI_POS] snapshot before it.
The killer's unit is tallied too: raiders, artillery, air.
"""
from __future__ import annotations

import collections
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from mexguard import BANDS, ECO_RE, POS_RE, TEAM_RE  # noqa: E402
from story import category  # noqa: E402

DEATH_RE = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\S+) cost=\d+ x=(\d+) z=(\d+) .*? built=1 .*?atkteam=(-?\d+) atk=(\S+)")


def main() -> int:
    args = sys.argv[1:]
    to, r = 20.0, 450.0
    for flag in ("--to", "--r"):
        if flag in args:
            i = args.index(flag)
            v = float(args[i + 1])
            del args[i:i + 2]
            to, r = (v, r) if flag == "--to" else (to, v)
    acc = collections.Counter()
    killers = {"us": collections.Counter(), "them": collections.Counter()}
    for a in args:
        d = Path(a)
        script = (d / "script.txt").read_text(encoding="utf8", errors="ignore")
        text = (d / "infolog.txt").read_text(encoding="utf8", errors="ignore")
        start, ally = {}, {}
        for m in TEAM_RE.finditer(script):
            b = m.group(2)
            x, z, al = (re.search(p, b) for p in (r"StartPosX=(\d+)", r"StartPosZ=(\d+)", r"AllyTeam=(\d+)"))
            if x and z and al:
                start[int(m.group(1))] = (float(x.group(1)), float(z.group(1)))
                ally[int(m.group(1))] = int(al.group(1))
        eco = ECO_RE.search(text)
        us = ally.get(int(eco.group(1)), 0) if eco else 0
        guns = {}   # (snapshot frame, allyteam) -> [(x, z)]
        for m in POS_RE.finditer(text):
            f = int(m.group(3)) // 1800 * 1800
            al = ally.get(int(m.group(1)))
            lst = guns.setdefault((f, al), [])
            for item in m.group(4).split(","):
                p = item.split(":")
                if len(p) >= 3 and category(p[0]) == "def":
                    lst.append((float(p[1]), float(p[2])))
        snaps = sorted({f for f, _ in guns})
        for m in DEATH_RE.finditer(text):
            f, t, u = int(m.group(1)), int(m.group(2)), m.group(3)
            if f > to * 1800 or category(u) != "mex" or t not in ally:
                continue
            atk = m.group(7)
            if int(m.group(6)) < 0 and not re.search(r"moho|uwmme", u):
                continue   # removed by its own upgrade, or self-destructed
            x, z = float(m.group(4)), float(m.group(5))
            own = [start[k] for k in ally if ally[k] == ally[t]]
            foe = [start[k] for k in ally if ally[k] != ally[t]]
            do = min(((x - a) ** 2 + (z - b) ** 2) ** 0.5 for a, b in own)
            df = min(((x - a) ** 2 + (z - b) ** 2) ** 0.5 for a, b in foe)
            band = next(b for lo, hi, b in BANDS if lo <= do / max(1.0, do + df) < hi)
            prev = [s for s in snaps if s <= f]
            g = False
            if prev:
                g = any((x - gx) ** 2 + (z - gz) ** 2 <= r * r for gx, gz in guns.get((prev[-1], ally[t]), []))
            side = "us" if ally[t] == us else "them"
            acc[(side, band, g)] += 1
            killers[side][atk] += 1
    n = len(args)
    print(f"finished extractors lost by minute {to:g}, per match (n={n}); guarded = a gun within {r:.0f} at the last snapshot")
    for side in ("us", "them"):
        cells = []
        for _, _, b in BANDS:
            gd, ug = acc[(side, b, True)] / n, acc[(side, b, False)] / n
            cells.append(f"{b}: {gd + ug:4.1f} ({ug:4.1f} unguarded)")
        print(f"  {side:<5} " + "   ".join(cells))
        print(f"        killers: " + ", ".join(f"{k} {v / n:.1f}" for k, v in killers[side].most_common(6)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
