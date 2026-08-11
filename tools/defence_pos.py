#!/usr/bin/env python3
"""WHERE the static defence actually stands, per AI.

"90% of our defences on the front line" is a claim about position, and until now
every check of it counted towers instead. This reads [BARAI_POS] -- the
per-building positions gadget -- and projects every defence building onto the
axis from its owner's own base to the enemy's, so 0.0 is "in our base" and 0.5
is the midpoint between the two sides.

Telemetry is read from each match's stdout.txt, never the shared infolog: the
engine write dir is shared across concurrent matches and their [BARAI_*] rows
interleave there.

A unit counts as static defence when its def lives in a *DefenceOffence or
*SeaDefence directory of the game tree -- the game's own classification, rather
than a name list that goes stale.

Usage:
    python tools/defence_pos.py tournaments/<run> [--control tournaments/<run>]
"""
from __future__ import annotations

import argparse
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402

POS_RE = re.compile(r"\[BARAI_POS\] team=(\d+) ally=(\d+) frame=(\d+) n=(\d+) (.*)")
AI_BLOCK_RE = re.compile(r"\[AI(\d+)\]\s*\{(.*?)\}", re.S)
FWD_MARK = 0.25   # "past the quarter mark" -- out of the base, toward them


def defence_defs() -> set[str]:
    env = bar_env.load()
    root = env.game_sdd / "units"
    out = set()
    for p in root.rglob("*.lua"):
        seg = p.parent.as_posix()
        if "DefenceOffence" in seg or "SeaDefence" in seg:
            out.add(p.stem.lower())
    return out


def ai_teams(script: str) -> dict[int, str]:
    """team id -> shortName:version, from the start script's [AI] blocks."""
    out = {}
    for _, body in AI_BLOCK_RE.findall(script):
        team = re.search(r"Team\s*=\s*(\d+)\s*;", body)
        short = re.search(r"ShortName\s*=\s*([^;]+);", body)
        ver = re.search(r"Version\s*=\s*([^;]*);", body)
        if not (team and short):
            continue
        label = short.group(1).strip()
        if ver and ver.group(1).strip():
            label += ":" + ver.group(1).strip()
        out[int(team.group(1))] = label
    return out


def last_positions(text: str):
    """the final sampled frame: ally -> team -> [(name, x, z)]"""
    frames = defaultdict(lambda: defaultdict(list))
    latest = -1
    for line in text.splitlines():
        m = POS_RE.search(line)
        if not m:
            continue
        team, ally, frame, _n, blob = m.groups()
        frame, team, ally = int(frame), int(team), int(ally)
        latest = max(latest, frame)
        rows = []
        for item in blob.split(","):
            bits = item.split(":")
            if len(bits) < 3:
                continue
            try:
                rows.append((bits[0].lower(), float(bits[1]), float(bits[2])))
            except ValueError:
                continue
        frames[frame][(ally, team)] = rows
    if latest < 0:
        return latest, {}
    return latest, frames[latest]


def centroid(pts):
    if not pts:
        return None
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def analyse_match(mdir: Path, defs: set[str]):
    out = mdir / "stdout.txt"
    scr = mdir / "script.txt"
    if not out.exists() or not scr.exists():
        return []
    frame, snap = last_positions(out.read_text("utf-8", errors="replace"))
    if not snap:
        return []
    labels = ai_teams(scr.read_text("utf-8", errors="replace"))

    # Base anchors: everything that is NOT defence. A base's own towers must not
    # define where its base is, or a wall of towers drags the origin onto itself.
    base = {}
    for (ally, team), rows in snap.items():
        base[(ally, team)] = centroid([(x, z) for n, x, z in rows if n not in defs])

    rows_out = []
    for (ally, team), rows in snap.items():
        home = base.get((ally, team))
        theirs = [base[k] for k in base if k[0] != ally and base[k]]
        if home is None or not theirs:
            continue
        ex = sum(p[0] for p in theirs) / len(theirs)
        ez = sum(p[1] for p in theirs) / len(theirs)
        ax, az = ex - home[0], ez - home[1]
        span = ax * ax + az * az
        if span <= 0:
            continue
        fracs = []
        for n, x, z in rows:
            if n not in defs:
                continue
            fracs.append(((x - home[0]) * ax + (z - home[1]) * az) / span)
        rows_out.append({
            "match": mdir.name, "frame": frame, "team": team, "ally": ally,
            "ai": labels.get(team, "?"), "n": len(fracs),
            "fracs": fracs,
        })
    return rows_out


def report(rows, title):
    by_ai = defaultdict(list)
    for r in rows:
        by_ai[r["ai"]].append(r)
    print(f"\n=== {title} ===")
    print(f"{'AI':<28}{'games':>6}{'def/player':>11}{'median':>9}"
          f"{f'>{FWD_MARK:.2f}':>8}{'>0.40':>8}")
    for ai, rs in sorted(by_ai.items()):
        allf = [f for r in rs for f in r["fracs"]]
        if not allf:
            print(f"{ai:<28}{len(rs):>6}{0:>11}{'-':>9}{'-':>8}{'-':>8}")
            continue
        fwd = sum(1 for f in allf if f > FWD_MARK) / len(allf)
        far = sum(1 for f in allf if f > 0.40) / len(allf)
        print(f"{ai:<28}{len(rs):>6}{len(allf) / len(rs):>11.1f}"
              f"{statistics.median(allf):>9.2f}{fwd:>7.0%}{far:>8.0%}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("--control")
    ap.add_argument("--per-match", action="store_true")
    a = ap.parse_args()

    defs = defence_defs()
    for label, run in (("run", a.run), ("control", a.control)):
        if not run:
            continue
        root = Path(run)
        mdirs = sorted((root / "matches").glob("t*")) or [root]
        rows = [r for m in mdirs for r in analyse_match(m, defs)]
        if not rows:
            print(f"{label}: no [BARAI_POS] telemetry under {root}")
            continue
        report(rows, f"{label}: {root.name}")
        if a.per_match:
            for r in sorted(rows, key=lambda r: (r["match"], r["team"])):
                if not r["fracs"]:
                    continue
                fwd = sum(1 for f in r["fracs"] if f > FWD_MARK) / len(r["fracs"])
                print(f"  {r['match'][:34]:<34} t{r['team']} {r['ai']:<22}"
                      f" n={r['n']:<4} med={statistics.median(r['fracs']):.2f}"
                      f" fwd={fwd:.0%}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
