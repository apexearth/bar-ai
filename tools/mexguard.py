#!/usr/bin/env python3
"""How many of each side's standing extractors have a gun beside them,
split by how far forward the extractor stands.

    python tools/mexguard.py <match-dir> [...] [--at 12,16,20] [--r 450]

From [BARAI_POS] structure snapshots (every 2 min) and the start positions in
script.txt. "Forward" is f = d_own / (d_own + d_foe): the extractor's distance
to its own side's nearest start over the sum with the enemy's nearest start
(0 = at home, 0.5 = the middle, 1 = their base). A guard is any defence
structure (story.py's category "def") within --r elmos.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from story import category  # noqa: E402

POS_RE = re.compile(r"\[BARAI_POS\] team=(\d+) ally=(\d+) frame=(\d+) n=\d+ part=\d+/\d+ (\S+)")
TEAM_RE = re.compile(r"\[TEAM(\d+)\]\s*\{([^}]*)\}")
ECO_RE = re.compile(r"eco-status team=(\d+) growing=1")
BANDS = ((0.0, 0.35, "home"), (0.35, 0.5, "mid-own"), (0.5, 1.01, "mid-foe+"))


def main() -> int:
    args = sys.argv[1:]
    at = [12, 16, 20]
    r = 450.0
    if "--at" in args:
        i = args.index("--at")
        at = [int(x) for x in args[i + 1].split(",")]
        del args[i:i + 2]
    if "--r" in args:
        i = args.index("--r")
        r = float(args[i + 1])
        del args[i:i + 2]
    acc = {}   # (minute, side, band) -> [mexes, guarded]
    for a in args:
        d = Path(a)
        script = (d / "script.txt").read_text(encoding="utf8", errors="ignore")
        text = (d / "infolog.txt").read_text(encoding="utf8", errors="ignore")
        start, ally = {}, {}
        for m in TEAM_RE.finditer(script):
            body = m.group(2)
            x = re.search(r"StartPosX=(\d+)", body)
            z = re.search(r"StartPosZ=(\d+)", body)
            al = re.search(r"AllyTeam=(\d+)", body)
            if x and z and al:
                start[int(m.group(1))] = (float(x.group(1)), float(z.group(1)))
                ally[int(m.group(1))] = int(al.group(1))
        eco = ECO_RE.search(text)
        us = ally.get(int(eco.group(1)), 0) if eco else 0
        snaps = {}   # (frame, team) -> list of (name, x, z)
        for m in POS_RE.finditer(text):
            key = (int(m.group(3)), int(m.group(1)))
            lst = snaps.setdefault(key, [])
            for item in m.group(4).split(","):
                p = item.split(":")
                if len(p) >= 3:
                    lst.append((p[0], float(p[1]), float(p[2])))
        for minute in at:
            f = minute * 1800
            for t in ally:
                units = snaps.get((f, t)) or snaps.get((f + 1, t)) or []
                if not units:
                    continue
                own = [start[k] for k in ally if ally[k] == ally[t]]
                foe = [start[k] for k in ally if ally[k] != ally[t]]
                side = "us" if ally[t] == us else "them"
                # Guards may be the ally's too: everything of that alliance.
                guns = []
                for tt in ally:
                    if ally[tt] != ally[t]:
                        continue
                    for n, x, z in snaps.get((f, tt)) or snaps.get((f + 1, tt)) or []:
                        if category(n) == "def":
                            guns.append((x, z))
                for n, x, z in units:
                    if category(n) != "mex":
                        continue
                    do = min(((x - a) ** 2 + (z - b) ** 2) ** 0.5 for a, b in own)
                    df = min(((x - a) ** 2 + (z - b) ** 2) ** 0.5 for a, b in foe)
                    fw = do / max(1.0, do + df)
                    band = next(b for lo, hi, b in BANDS if lo <= fw < hi)
                    g = any((x - gx) ** 2 + (z - gz) ** 2 <= r * r for gx, gz in guns)
                    c = acc.setdefault((minute, side, band), [0, 0])
                    c[0] += 1
                    c[1] += 1 if g else 0
    n = len(args)
    print(f"extractors standing and guarded (a gun within {r:.0f}), summed over {n} match(es), per seat = /8 per match")
    print("  min  side   " + "   ".join(f"{b:>16}" for _, _, b in BANDS))
    for minute in at:
        for side in ("us", "them"):
            cells = []
            for _, _, b in BANDS:
                m_, g_ = acc.get((minute, side, b), [0, 0])
                cells.append(f"{m_ / (8 * n):4.1f} mex {100 * g_ / max(1, m_):3.0f}% g")
            print(f"  {minute:3}  {side:<5}  " + "   ".join(f"{c:>16}" for c in cells))
    return 0


if __name__ == "__main__":
    sys.exit(main())
