"""Builds that took unusually long, and why (his 11-14: "analyze and look for build inefficiencies in games. Find
situations where something takes unusually long to build and then root cause that issue").

    python tools/slowbuild.py matches/pkg2-*                 # the slowest builds of our seats, each with its causes
    python tools/slowbuild.py matches/pkg2-* --ai v0.5.11    # the same for the release seats
    python tools/slowbuild.py matches/x --def coralab --top 5

A build is slow when it finished more than --x times later than its own price said (the priced walk + build seconds
the decision used, `apex: calib-build`) and at least --min-s seconds late. For each, the window from the decision to
the finish is rebuilt from the log and the lateness is split into what the log shows:

  walk        decision -> frame placed (`placed`), past the priced walk
  unmanned    seconds inside the window with no builder ordered onto the job
  left        builders that were on it and were re-decided onto something else, by reason (draw, estall, role...)
  peeled      peel / ring-trim lines at the site
  released    the order dropped and re-issued (`order-release` at the site)
  m-stall / e-stall   share of the window with metal / energy empty and pull above income
  crew        mean builders on it while the frame stood
"""
from __future__ import annotations

import argparse
import bisect
import collections
import glob
import re
import sys
from pathlib import Path

FPS = 30.0
LINE = re.compile(r"\[f=(-?\d+)\] Skirmish AI <ApexUnstable-([^>]+)>: (?:\[[\d.]+m t(\d+)\] )?apex: (.*)")
T_IN = re.compile(r"\bt=(\d+)\b")
CALIB = re.compile(r"calib-build t=(\d+) def=(\w+) fwd=\S+ walk=(\d+) build=(\d+) actual=(\d+) inc=\d+(?: at=(-?\d+),(-?\d+))?")
PLACED = re.compile(r"placed t=(\d+) (\w+) at=(-?\d+),(-?\d+)")
EXEC = re.compile(r"exec t=(\d+) (\w+) #(\d+) (\w+):([\w-]+) pick=\d+ at=(-?\d+),(-?\d+)(?: task=(-?\d+),(-?\d+))?")
DECIDE = re.compile(r"decide t=(\d+) (\w+) #(\d+) -> ([\w/]+):([\w-]+).*?why=(\w+)")
TRIM = re.compile(r"ring-trim (\w+) at=(-?\d+),(-?\d+) done=([\d.]+) crew=(\d+)")
RELEASE = re.compile(r"order-release t=(\d+) (\w+) age=\d+ by=(\w+) at=(-?\d+),(-?\d+)")
METAL = re.compile(r"metal cur=(\d+)/(\d+) inc=([\d.]+) pull=([\d.]+)")
ENERGY = re.compile(r"energy cur=(\d+)/(\d+) inc=(-?\d+) pull=(-?\d+)")
SITE_R = 260.0


def near(ax, az, bx, bz, r=SITE_R):
    return (ax - bx) ** 2 + (az - bz) ** 2 <= r * r


def scan(path: Path, want_ai: str):
    by_team = collections.defaultdict(lambda: collections.defaultdict(list))
    team_ai = {}
    with open(path, errors="replace") as fh:
        for raw in fh:
            if "apex: " not in raw:
                continue
            m = LINE.search(raw)
            if not m:
                continue
            f, ai, tp, body = int(m.group(1)), m.group(2), m.group(3), m.group(4)
            if want_ai not in ai:
                continue
            head = body.split(" ", 1)[0]
            if head not in ("calib-build", "placed", "exec", "decide", "ring-trim", "order-release", "metal", "energy",
                            "latency"):
                continue
            t = tp
            if t is None:
                tm = T_IN.search(body)
                t = tm.group(1) if tm else None
            if t is None:
                continue
            team_ai[int(t)] = ai
            by_team[int(t)][head].append((f, body))
    return by_team, team_ai


def stall_share(rows, f0, f1, rx):
    fr = [f for f, _ in rows]
    i = bisect.bisect_left(fr, f0)
    n = dead = 0
    while i < len(rows) and rows[i][0] <= f1:
        m = rx.match(rows[i][1])
        if m:
            cur, cap, inc, pull = (float(m.group(k)) for k in range(1, 5))
            n += 1
            dead += (cap > 0 and cur < 0.05 * cap and pull > inc)
        i += 1
    return (dead / n) if n else 0.0


LAT_START = re.compile(r"latency (\w+) start=(\d+) workers=(\d+) arrived=(\d+) cap=(\d+) banked=(\d) m=\d+ at=(-?\d+),(-?\d+)")
LAT_DROP = re.compile(r"latency (\w+) dropped=(\d+) workers=\d+ at=(-?\d+),(-?\d+)")


def analyse(match: Path, lines, d_filter, x, min_s):
    """Each finished building: its priced walk+build (calib-build, logged at the finish), the order it came from
    (latency start: when its frame went down, and how long after the order), the finish (placed, same frame)."""
    out = []
    for team, L in lines.items():
        execs = [(f, EXEC.match(b)) for f, b in L["exec"]]
        execs = [(f, m) for f, m in execs if m]
        decides = [(f, DECIDE.match(b)) for f, b in L["decide"]]
        decides = [(f, m) for f, m in decides if m]
        placed = [(f, PLACED.match(b)) for f, b in L["placed"]]
        placed = [(f, m) for f, m in placed if m]
        starts = [(f, LAT_START.match(b)) for f, b in L["latency"]]
        starts = [(f, m) for f, m in starts if m]
        drops = [(f, LAT_DROP.match(b)) for f, b in L["latency"]]
        drops = [(f, m) for f, m in drops if m]
        for f1, body in L["calib-build"]:
            c = CALIB.match(body)
            if not c:
                continue
            d = c.group(2)
            if d_filter and d_filter not in d:
                continue
            walk, build = int(c.group(3)), int(c.group(4))
            pl = [(f, m) for f, m in placed if m.group(2) == d and abs(f - f1) <= 2]
            if c.group(6) is not None:
                sx, sz = int(c.group(6)), int(c.group(7))
            elif pl:
                sx, sz = int(pl[0][1].group(3)), int(pl[0][1].group(4))
            else:
                continue
            st = [(f, m) for f, m in starts if m.group(1) == d and f <= f1 and near(int(m.group(7)), int(m.group(8)), sx, sz)]
            if not st:
                continue
            fst, sm = st[-1]
            walk_s = int(sm.group(2))
            f0 = fst - int(walk_s * FPS)
            frame_s = (f1 - fst) / FPS
            actual = int((f1 - f0) / FPS)
            priced = walk + build
            slow_walk = walk_s >= x * max(walk, 1) and walk_s - walk >= min_s
            slow_frame = frame_s >= x * max(build, 1) and frame_s - build >= min_s
            if not (slow_walk or slow_frame):
                continue
            redo = sum(1 for f, m in drops if m.group(1) == d and f1 - 20 * 60 * FPS <= f <= fst
                       and near(int(m.group(3)), int(m.group(4)), sx, sz))
            fplace = fst
            # who was on it, when, and why they left
            on = {}
            spans = []
            left = collections.Counter()
            ev = sorted([(f, "e", m) for f, m in execs if f0 - 10 * FPS <= f <= f1] + [(f, "d", m) for f, m in decides if f0 <= f <= f1],
                        key=lambda e: e[0])
            for f, kind, m in ev:
                if kind == "e":
                    uid, jdef = m.group(3), m.group(5)
                    tx = int(m.group(8)) if m.group(8) else int(m.group(6))
                    tz = int(m.group(9)) if m.group(9) else int(m.group(7))
                    mine = (jdef == d) and near(tx, tz, sx, sz)
                    if mine and uid not in on:
                        on[uid] = f
                    elif not mine and uid in on:
                        spans.append((on.pop(uid), f))
                else:
                    uid, jdef, why = m.group(3), m.group(5), m.group(6)
                    if uid in on and jdef != d:
                        left[why] += 1
                        spans.append((on.pop(uid), f))
            for uid, fs in on.items():
                spans.append((fs, f1))
            # unmanned seconds: the window minus the union of crew spans
            cover = 0
            cur_s = cur_e = None
            for s, e in sorted(spans):
                if cur_e is None or s > cur_e:
                    if cur_e is not None:
                        cover += cur_e - cur_s
                    cur_s, cur_e = s, e
                else:
                    cur_e = max(cur_e, e)
            if cur_e is not None:
                cover += cur_e - cur_s
            unmanned = max(0, (f1 - f0) - cover) / FPS
            fs_from = fplace if fplace is not None else f0
            crew_s = sum(max(0, min(e, f1) - max(s, fs_from)) for s, e in spans) / FPS
            frame_s = max(1.0, (f1 - fs_from) / FPS)
            trims = sum(1 for f, b in L["ring-trim"] if f0 <= f <= f1
                        and (lambda m: m and m.group(1) == d and near(int(m.group(2)), int(m.group(3)), sx, sz))(TRIM.match(b)))
            rel = collections.Counter()
            for f, b in L["order-release"]:
                if f0 <= f <= f1:
                    m = RELEASE.match(b)
                    if m and m.group(2) == d and near(int(m.group(4)), int(m.group(5)), sx, sz):
                        rel[m.group(3)] += 1
            out.append(dict(
                match=match.name, team=team, d=d, start=f0 / FPS / 60.0, actual=actual, priced=priced, walk=walk,
                build=build, late=actual - priced, walk_s=walk_s, frame_s=frame_s, redo=redo,
                arrived=int(sm.group(4)), banked=int(sm.group(6)), cap=int(sm.group(5)), crew0=int(sm.group(3)),
                unmanned=unmanned, crew=crew_s / max(1.0, frame_s), left=left, trims=trims, released=rel,
                mstall=stall_share(L["metal"], fst, f1, METAL), estall=stall_share(L["energy"], fst, f1, ENERGY)))
    return out


def cause_of(b):
    """The largest share of the lateness the log can name."""
    parts = []
    if b["walk_s"] > b["walk"] + 20:
        parts.append(("frame went down %.0fs after the order, priced %ds" % (b["walk_s"], b["walk"]), b["walk_s"] - b["walk"]))
    if b["redo"]:
        parts.append(("%d earlier order(s) of it dropped" % b["redo"], 20.0 * b["redo"]))
    if b["frame_s"] > b["build"] + 20:
        parts.append(("frame stood %.0fs, priced %ds, crew %.1f" % (b["frame_s"], b["build"], b["crew"]), b["frame_s"] - b["build"]))
    if b["unmanned"] > 20:
        parts.append(("nobody ordered onto it for %.0fs" % b["unmanned"], b["unmanned"] * 0.5))
    nleft = sum(b["left"].values())
    if nleft:
        parts.append(("%d hand(s) left it (%s)" % (nleft, ", ".join("%s %d" % kv for kv in b["left"].most_common(3))), 15.0 * nleft))
    if b["trims"]:
        parts.append(("%d ring-trim(s) to one hand" % b["trims"], 10.0 * b["trims"]))
    if b["released"]:
        parts.append(("order dropped %d time(s) (%s)" % (sum(b["released"].values()), ", ".join("%s %d" % kv for kv in b["released"].most_common(3))),
                      20.0 * sum(b["released"].values())))
    if b["mstall"] > 0.2:
        parts.append(("metal empty %.0f%% of the time" % (100 * b["mstall"]), b["actual"] * b["mstall"]))
    if b["estall"] > 0.2:
        parts.append(("energy empty %.0f%% of the time" % (100 * b["estall"]), b["actual"] * b["estall"]))
    parts.sort(key=lambda p: -p[1])
    return "; ".join(p[0] for p in parts) or "nothing in the log names it (crew %.1f)" % b["crew"]


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("matches", nargs="+")
    ap.add_argument("--ai", default="lane-", help="substring of the AI version to analyse (default: our lanes)")
    ap.add_argument("--def", dest="d", default=None, help="only builds of this def (substring)")
    ap.add_argument("--x", type=float, default=2.0, help="slow = actual >= x times the priced walk+build")
    ap.add_argument("--min-s", type=float, default=60.0, help="... and at least this many seconds late")
    ap.add_argument("--top", type=int, default=15)
    a = ap.parse_args(argv)
    paths = []
    for p in a.matches:
        paths += [Path(x) for x in glob.glob(p)] or [Path(p)]
    builds = []
    total = collections.Counter()
    for p in sorted(set(paths)):
        il = p / "infolog.txt"
        if not il.exists():
            continue
        lines, _ = scan(il, a.ai)
        for t, L in lines.items():
            total["finished"] += len(L["calib-build"])
        builds += analyse(p, lines, a.d, a.x, a.min_s)
    if not builds:
        print("no slow builds (%d finished)" % total["finished"])
        return 0
    byd = collections.defaultdict(list)
    for b in builds:
        byd[b["d"]].append(b)
    print("%d slow builds of %d finished (actual >= %.1fx priced and >= %.0fs late)\n" % (len(builds), total["finished"], a.x, a.min_s))
    print("by def (count, seconds late in all):")
    for d, bs in sorted(byd.items(), key=lambda kv: -sum(b["late"] for b in kv[1]))[:12]:
        print("  %-14s %3d  %6.0fs" % (d, len(bs), sum(b["late"] for b in bs)))
    causes = collections.Counter()
    for b in builds:
        for k, n in b["left"].items():
            causes["left:" + k] += n
        causes["ring-trim"] += b["trims"]
        for k, n in b["released"].items():
            causes["released:" + k] += n
        causes["unmanned>20s"] += b["unmanned"] > 20
        causes["metal empty>20%"] += b["mstall"] > 0.2
        causes["energy empty>20%"] += b["estall"] > 0.2
    print("\ncauses over all slow builds:", ", ".join("%s %d" % kv for kv in causes.most_common(12) if kv[1]))
    print("\nthe slowest %d:" % a.top)
    for b in sorted(builds, key=lambda b: -b["late"])[:a.top]:
        print("  %s t%d %-11s at %4.1fm: %4ds for priced %3ds (walk %d + build %d; cap %d at start) -- %s"
              % (b["match"], b["team"], b["d"], b["start"], b["actual"], b["priced"], b["walk"], b["build"], b["cap"], cause_of(b)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
