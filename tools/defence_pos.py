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
import collections
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
        fracs, pts, names = [], [], []
        for n, x, z in rows:
            if n not in defs:
                continue
            fracs.append(((x - home[0]) * ax + (z - home[1]) * az) / span)
            pts.append((x, z))
            names.append(n)
        rows_out.append({
            "match": mdir.name, "frame": frame, "team": team, "ally": ally,
            "ai": labels.get(team, "?"), "n": len(fracs),
            "fracs": fracs, "pts": pts, "names": names,
        })
    return rows_out


def blobs(points, radius=420.0, min_size=5):
    """Tight clusters of static defence, by single-link grouping.

    apexearth: "you could quickly just parse the log to see where all the turrets
    are getting built, and if theres any blobs like this. Seems like an audit
    script check candidate."

    He is right that this is the check, and it would have caught a heap of 13
    light laser turrets sitting below a base without anyone having to notice it
    on screen. A blob is not defined by count alone -- towers SHOULD cluster on a
    chokepoint -- so the report carries how far forward the cluster sits, which is
    what separates a held line from a pile in the back yard.
    """
    unused = list(range(len(points)))
    out = []
    while unused:
        seed = unused.pop()
        group = [seed]
        frontier = [seed]
        while frontier:
            cur = frontier.pop()
            for j in list(unused):
                a, b = points[cur], points[j]
                if (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 <= radius * radius:
                    unused.remove(j)
                    group.append(j)
                    frontier.append(j)
        if len(group) >= min_size:
            out.append(group)
    return out


# WHAT a blob is made of decides whether it is a problem. apexearth: "its just
# especially an issue when they're the light laser turrets and its BEHIND our
# base. in late game if theres like 10 pulsars all near each other, thats not a
# bad thing."
#
# So the flag is cheap-AND-rearward, not merely clustered. Cost is the honest
# discriminator and, read from the unit defs, it cannot go stale like a name list.
CHEAP_DEFENCE = 400.0   # metal each; llt 85, beamer 190, claw 170, rl 80
BEHIND = 0.10           # forward fraction at or below which this is our back yard


def def_costs(defs: set[str]) -> dict:
    env = bar_env.load()
    root = env.game_sdd / "units"
    out = {}
    for p in root.rglob("*.lua"):
        if p.stem.lower() not in defs:
            continue
        m = re.search(r"metalcost\s*=\s*(\d+)",
                      p.read_text("utf-8", errors="replace"), re.I)
        if m:
            out[p.stem.lower()] = float(m.group(1))
    return out


def report_blobs(rows, title, costs):
    print(f"\n=== blobs: {title} ===")
    print("Clusters of 5+ static defences within 420 elmos.")
    print(f"  WASTE = mostly cheap turrets (under {CHEAP_DEFENCE:.0f} metal each)"
          f" at or behind fwd {BEHIND:.2f}.")
    print("  A pile of heavy defence, or a pile out on the line, is not flagged.")
    print(f"{'':<6}{'AI':<16}{'match':<9}{'n':>4}{'fwd':>7}{'avg m':>7}  types")
    waste = 0
    for r in sorted(rows, key=lambda r: (r["ai"], r["match"])):
        pts = r.get("pts") or []
        for g in blobs(pts):
            fwd = statistics.median([r["fracs"][i] for i in g])
            names = collections.Counter(r["names"][i] for i in g)
            avg = sum(costs.get(r["names"][i], 0.0) for i in g) / len(g)
            bad = (avg < CHEAP_DEFENCE) and (fwd <= BEHIND)
            waste += 1 if bad else 0
            top = ", ".join(f"{n}x{c}" for n, c in names.most_common(3))
            print(f"{'WASTE ' if bad else '      '}{r['ai']:<16}"
                  f"{r['match'][5:13]:<9}{len(g):>4}{fwd:>7.2f}{avg:>7.0f}  {top}")
    print(f"  -- {waste} wasteful blob(s)")


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
    ap.add_argument("--blobs", action="store_true",
                    help="report tight clusters of static defence")
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
        if a.blobs:
            report_blobs(rows, root.name, def_costs(defs))
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
