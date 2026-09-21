#!/usr/bin/env python3
"""Mobile combat units fielded per time bucket, by tier, ours against theirs.

apexearth 2026-09-20: "pretty late into the game we still make tier 1 units.
The game starts to lag really bad" -- the count is the lag, the metal is the
waste. Reads [BARAI_ARMY] snapshots (first frame a unit id is seen), so it
covers every unit that stood, including the ones that died between builds.

    python tools/tiercensus.py <match-dir | tournament-dir> [--bucket 4]
    python tools/tiercensus.py matches/_engine            # his live game

A tournament dir pools every match under it. Tier is read off the game tree
(techlevel, default 1); commanders, builders and unarmed units are not army.
"""
from __future__ import annotations

import argparse
import collections
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402
import unitdef  # noqa: E402

AI_BLOCK_RE = re.compile(r"\[AI\d+\]\s*\{(.*?)\}", re.S)
ARMY_RE = re.compile(r"\[BARAI_ARMY\] frame=(\d+) team=(\d+) n=\d+ part=\S+ (\S*)")

_tree = None
_info: dict[str, tuple[int, int] | None] = {}


def unit(name: str) -> tuple[int, int] | None:
    """(tier, metal) for a mobile combat def, else None."""
    global _tree
    if name in _info:
        return _info[name]
    if _tree is None:
        _tree = unitdef.trees(bar_env.load())[0]
    p = _tree.find(name)
    r = None
    if p is not None:
        txt = p.read_text(encoding="utf-8", errors="replace")

        def fld(k: str) -> str | None:
            m = re.search(r"\b" + k + r"\s*=\s*([^,\n}]+)", txt, re.I)
            return m.group(1).strip().strip('"') if m else None

        speed = float(fld("speed") or 0)
        tl = fld("techlevel")
        tier = int(tl) if tl and tl.isdigit() else 1
        builder = (fld("builder") or "").lower() == "true"
        armed = "weapondefs" in txt.lower()
        if speed > 0 and armed and not builder and not name.endswith("com"):
            r = (tier, int(float(fld("metalcost") or 0)))
    _info[name] = r
    return r


def apex_teams(match_dir: Path) -> set[int]:
    """Game team ids Apex played: the start script (either layout), else the
    per-team apex logs a dashboard game writes."""
    out: set[int] = set()
    for name in ("script.txt", "_script.txt"):
        p = match_dir / name
        if not p.exists():
            continue
        text = p.read_text("utf-8", errors="replace")
        heads = list(re.finditer(r"\[(ai\d+|team\d+|player\d+|modoptions|allyteam\d+|game)\]", text, re.I))
        for i, h in enumerate(heads):
            if not h.group(1).lower().startswith("ai"):
                continue
            block = text[h.end():heads[i + 1].start() if i + 1 < len(heads) else len(text)]
            m_name = re.search(r"shortname\s*=\s*(\w+)", block, re.I)
            m_team = re.search(r"\bteam\s*=\s*(\d+)", block, re.I)
            if m_name and m_team and m_name.group(1).lower().startswith("apex"):
                out.add(int(m_team.group(1)))
        if out:
            return out
    for p in match_dir.glob("AI/Skirmish/Apex*/*/apex-t*.log"):
        m = re.search(r"apex-t(\d+)\.log$", p.name)
        if m:
            out.add(int(m.group(1)))
    return out


def gadget_text(match_dir: Path) -> str:
    for name in ("barai-gadgets.log", "stdout.txt", "infolog.txt"):
        p = match_dir / name
        if p.exists():
            return p.read_text("utf-8", errors="replace")
    return ""


def census(match_dir: Path, bucket: int, metal, cnt, games) -> bool:
    text = gadget_text(match_dir)
    ours = apex_teams(match_dir)
    if not text or not ours:
        return False
    seen: set[tuple[int, str]] = set()
    for m in ARMY_RE.finditer(text):
        fr, team, body = int(m.group(1)), int(m.group(2)), m.group(3)
        for e in body.split(","):
            f = e.split(":")
            if len(f) < 2 or (team, f[0]) in seen:
                continue
            seen.add((team, f[0]))
            r = unit(f[1])
            if r is None:
                continue
            tier, mc = r
            key = ("ours" if team in ours else "theirs", int((fr / 1800) // bucket) * bucket)
            metal[key][tier] += mc
            cnt[key][tier] += 1
    games[0] += 1
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root")
    ap.add_argument("--bucket", type=int, default=4, help="minutes per row (default 4)")
    a = ap.parse_args()
    root = Path(a.root)
    metal = collections.defaultdict(lambda: collections.defaultdict(int))
    cnt = collections.defaultdict(lambda: collections.defaultdict(int))
    games = [0]
    if not census(root, a.bucket, metal, cnt, games):
        for d in sorted(p for p in root.iterdir() if p.is_dir()):
            census(d, a.bucket, metal, cnt, games)
    if games[0] == 0:
        print(f"no match with a gadget log and an Apex team under {root}")
        return 1
    B = a.bucket
    print(f"{games[0]} game(s); mobile combat units first seen per {B}-minute bucket, "
          f"metal (count); T1% is the T1 share of army metal")
    print("bucket  |  ours T1 (n)       T2+ (n)   T1%  | theirs T1 (n)     T2+ (n)   T1%")
    for b in sorted({k[1] for k in metal}):
        row = f"{b:>3}-{b + B:<3} |"
        for s in ("ours", "theirs"):
            d, n = metal[(s, b)], cnt[(s, b)]
            t1, t2 = d.get(1, 0), sum(v for k, v in d.items() if k >= 2)
            n1, n2 = n.get(1, 0), sum(v for k, v in n.items() if k >= 2)
            pct = 100 * t1 / (t1 + t2) if t1 + t2 else 0
            row += f" {t1 // games[0]:>7} ({n1 / games[0]:>4.0f}) {t2 // games[0]:>7} ({n2 / games[0]:>4.0f}) {pct:>3.0f}% |"
        print(row)
    print("per game where a tournament dir was given")
    return 0


if __name__ == "__main__":
    sys.exit(main())
