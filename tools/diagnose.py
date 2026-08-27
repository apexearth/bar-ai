#!/usr/bin/env python3
"""Read an infolog and say what the AI did wrong, without being told what to look for.

Every check here exists because a specific pathology was watched in a game and
then had to be re-found by hand. A check reports EVIDENCE -- the log lines and
the arithmetic -- rather than a verdict, and stays silent when the behaviour is
fine, so that a clean run can come back clean.

    python tools/diagnose.py <match-dir|infolog|tournament-dir>
    python tools/diagnose.py <tournament-dir> --agg     # pooled over every game

The checks:

  front-geometry   is the front line where the enemy is, or drawn through them
  plant-glut       a factory bought while the ones we own are not saturated
  frag             many copies of one def in flight at once, each built slowly
  frame-waste      metal that died as an unfinished nanoframe, by def
  piecemeal        army lost in a trickle rather than in battles
  deep-deaths      army lost on ground far past our own territory
  never-fought     army that died without ever firing
"""

from __future__ import annotations

import argparse
import re
import statistics as st
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FRAME_S = 30.0

# ---------------------------------------------------------------- log parsing

RE_FRAME = re.compile(r"\[f=(\d+)\]")

RE_FRONTLINE = re.compile(
    r"apex: frontline perim=(?P<perim>\d+) front=(?P<front>\d+) back=(?P<back>\d+) "
    r"mine=(?P<mine>\d+) sectors=\d+ foeKnown=(?P<foe>\d+) .*?"
    r"R=(?P<R>-?[\d.]+) band=(?P<band>-?[\d.]+) "
    r"ourMid=(?P<ox>-?[\d.]+),(?P<oz>-?[\d.]+) "
    r"foeMid=(?P<fx>-?[\d.]+),(?P<fz>-?[\d.]+) "
    r"lane=(?P<lx>-?[\d.]+),(?P<lz>-?[\d.]+) "
    r"frontD=(?P<frontD>-?[\d.]+) backD=(?P<backD>-?[\d.]+)"
)

RE_REQUEST = re.compile(
    r"apex: request (?P<how>\w+) (?P<def>\w+) inFlight=(?P<inflight>\d+) cap=(?P<cap>\d+)"
    r" live=(?P<live>\d+)"
)

RE_DECIDE_PLANT = re.compile(r"apex: decide t=(?P<team>\d+) \S+ #\d+ -> produce/plant:(?P<def>\w+)")

RE_FACQUEUE = re.compile(r"apex: facqueue lines=(?P<lines>\d+) orders=(?P<orders>\d+)")

RE_BUDGET = re.compile(
    r"apex: budget army=(?P<army>[\d.]+)/(?P<armyT>[\d.]+) def=(?P<def>[\d.]+)/(?P<defT>[\d.]+)"
)

RE_DESTROYED = re.compile(
    r"apex: unit-destroyed (?P<def>\w+) acts=(?P<acts>\S*) id=\d+ frame=(?P<frame>\d+) "
    r"at=(?P<x>-?[\d.]+),(?P<z>-?[\d.]+) curTask=\S* cost=(?P<cost>[\d.]+) "
    r"fwd=(?P<fwd>-?[\d.]+) built=(?P<built>\d) mob=(?P<mob>\d) "
    r"hist=\[(?P<hist>[^\]]*)\] fhist=\[(?P<fhist>[^\]]*)\]"
)


class Game:
    """Everything the checks need from one infolog, parsed in a single pass."""

    def __init__(self, path):
        self.path = path
        self.frontline = []
        self.requests = []
        self.plant_decides = []
        self.facqueue = []
        self.budget = []
        self.deaths = []
        self.last_frame = 0
        self._parse()

    def _parse(self):
        with open(self.path, "r", errors="replace") as fh:
            for line in fh:
                if "apex: " not in line:
                    continue
                mf = RE_FRAME.search(line)
                frame = int(mf.group(1)) if mf else 0
                if frame > self.last_frame:
                    self.last_frame = frame

                m = RE_FRONTLINE.search(line)
                if m:
                    d = dict((k, float(v)) for k, v in m.groupdict().items())
                    d["frame"] = frame
                    self.frontline.append(d)
                    continue
                m = RE_REQUEST.search(line)
                if m:
                    self.requests.append(dict(
                        frame=frame, how=m.group("how"), name=m.group("def"),
                        inflight=int(m.group("inflight")), cap=int(m.group("cap")),
                        live=int(m.group("live"))))
                    continue
                m = RE_DECIDE_PLANT.search(line)
                if m:
                    self.plant_decides.append((frame, m.group("def")))
                    continue
                m = RE_FACQUEUE.search(line)
                if m:
                    self.facqueue.append((frame, int(m.group("lines")), int(m.group("orders"))))
                    continue
                m = RE_BUDGET.search(line)
                if m:
                    self.budget.append((frame, float(m.group("army")), float(m.group("armyT"))))
                    continue
                m = RE_DESTROYED.search(line)
                if m:
                    g = m.groupdict()
                    self.deaths.append(dict(
                        frame=int(g["frame"]), name=g["def"], cost=float(g["cost"]),
                        fwd=float(g["fwd"]), built=g["built"] == "1", mob=g["mob"] == "1",
                        acts=g["acts"], fhist=g["fhist"],
                        x=float(g["x"]), z=float(g["z"])))

    @property
    def minutes(self):
        return self.last_frame / (FRAME_S * 60.0)

    @property
    def is_apex(self):
        return bool(self.deaths or self.requests or self.frontline)


class Finding:
    def __init__(self, check, severity, headline, evidence):
        self.check = check
        self.severity = severity      # 1 worst .. 3 note
        self.headline = headline
        self.evidence = evidence

    def __str__(self):
        mark = {1: "!!", 2: " !", 3: "  "}[self.severity]
        out = ["%s [%s] %s" % (mark, self.check, self.headline)]
        out += ["      " + e for e in self.evidence]
        return "\n".join(out)


def _med(xs, default=0.0):
    xs = list(xs)
    return st.median(xs) if xs else default


def _sep(f):
    return ((f["fx"] - f["ox"]) ** 2 + (f["fz"] - f["oz"]) ** 2) ** 0.5


# ------------------------------------------------------------------- checks

def check_front(g):
    """A front edge should sit BETWEEN us and them. Past their centroid it is not
    a front -- it is our army standing on their ground, painting that ground as
    our territory, and every consumer of the front (the staging lane, the
    PastFront veto, defence siting) inherits the error."""
    rows = [f for f in g.frontline if f["foe"] > 0.5 and f["front"] > 0]
    if len(rows) < 5:
        return []
    reach, noop = [], 0
    for f in rows:
        d = _sep(f)
        if d < 200.0:
            continue                      # centroids coincide: the ratio says nothing
        reach.append(f["frontD"] / d)
        if f["band"] >= d:
            noop += 1
    if not reach:
        return []
    med, hi = _med(reach), max(reach)
    noop_share = noop / len(reach)
    out = []
    if med > 0.6:
        out.append(Finding(
            "front-geometry", 1,
            "front line sits %.0f%% of the way to the enemy centroid (max %.0f%%) "
            "-- it is drawn through their territory, not between us" % (med * 100, hi * 100),
            ["samples=%d  median frontD/|foeMid-ourMid|=%.2f  max=%.2f"
             % (len(reach), med, hi),
             "band >= centroid separation in %.0f%% of samples: the 'near them' "
             "trim in Front::Scan never trims" % (noop_share * 100),
             "median band=%.0f  median separation=%.0f"
             % (_med(f["band"] for f in rows), _med(_sep(f) for f in rows)),
             "consumers: Military::LanePos (where the army stages), "
             "Builder::PastFront (eco veto), defence siting"]))
    elif noop_share > 0.5:
        out.append(Finding(
            "front-geometry", 2,
            "the front-band trim is inert in %.0f%% of samples" % (noop_share * 100),
            ["apex_front_band_frac * TerritoryRadius >= |foeMid-ourMid|, so every "
             "enemy-facing perimeter cell is classed FRONT"]))
    jumps = [((b["fx"] - a["fx"]) ** 2 + (b["fz"] - a["fz"]) ** 2) ** 0.5
             for a, b in zip(rows, rows[1:])]
    if jumps and _med(jumps) > 400.0:
        out.append(Finding(
            "front-geometry", 2,
            "the enemy centroid moves %.0f elmos per rescan (median)" % _med(jumps),
            ["max jump %.0f; gFoeSeen is a decaying memory over the whole grid, so a "
             "raid inside our own base drags the bearing backwards" % max(jumps)]))
    return out


def check_plant_glut(g):
    """A new line is only worth its production half if the lines we own are
    saturated. facqueue prints each line's queue depth; a plant bought while the
    depth is shallow is capacity we had no way to use."""
    if not g.plant_decides:
        return []
    out = []
    events = []
    for frame, name in g.plant_decides:
        prior = [f for f in g.facqueue if f[0] <= frame]
        lines = prior[-1][1] if prior else 0
        orders = prior[-1][2] if prior else 0
        bud = [b for b in g.budget if b[0] <= frame]
        army = bud[-1][1] if bud else 0.0
        armyT = bud[-1][2] if bud else 0.0
        events.append((frame, name, lines, orders, army, armyT))

    glut = [e for e in events if e[2] >= 1 and e[3] <= e[2]]
    if glut:
        out.append(Finding(
            "plant-glut", 1 if len(glut) > 1 else 2,
            "%d of %d factory purchases were made while the lines we already "
            "owned had no queue backlog" % (len(glut), len(events)),
            ["%5.1fm  %-12s lines=%d queued-orders=%d armyShare=%.2f/%.2f"
             % (f / (FRAME_S * 60), n, l, o, a, at) for (f, n, l, o, a, at) in glut]))

    starved = [e for e in events if e[2] >= 1 and e[5] > 0 and e[4] < e[5] * 0.5]
    if starved:
        out.append(Finding(
            "plant-glut", 2,
            "%d factory purchase(s) made while the army was under half its own "
            "budget share -- a new line cannot close a gap the standing lines are "
            "already failing to close" % len(starved),
            ["%5.1fm  %-12s armyShare=%.2f target=%.2f lines=%d"
             % (f / (FRAME_S * 60), n, a, at, l) for (f, n, l, o, a, at) in starved]))

    for (f1, d1), (f2, d2) in zip(g.plant_decides, g.plant_decides[1:]):
        if 0 < f2 - f1 < 90 * FRAME_S:
            out.append(Finding(
                "plant-glut", 2,
                "two factories bought %.0fs apart" % ((f2 - f1) / FRAME_S),
                ["%.1fm %s then %.1fm %s"
                 % (f1 / (FRAME_S * 60), d1, f2 / (FRAME_S * 60), d2)]))
    return out


def check_frag(g):
    """Build power is finite. N copies of one def in flight at once each build at
    roughly 1/N speed, so all N land late instead of one landing on time -- and
    anything shot at while it is still a nanoframe is a total loss."""
    peak = defaultdict(int)
    hits = defaultdict(int)
    for r in g.requests:
        if r["inflight"] > peak[r["name"]]:
            peak[r["name"]] = r["inflight"]
        if r["inflight"] >= 3:
            hits[r["name"]] += 1
    bad = sorted(((d, peak[d], hits[d]) for d in hits), key=lambda t: -t[1])
    if not bad:
        return []
    sev = 1 if any(p >= 4 for _, p, _ in bad) else 2
    return [Finding(
        "frag", sev,
        "%d def(s) had 3+ copies under construction simultaneously" % len(bad),
        ["%-14s peak in-flight=%d  occasions at 3+=%d" % (d, p, n) for d, p, n in bad[:10]])]


def check_frame_waste(g):
    """Metal that died as a nanoframe bought nothing at all. A def that keeps
    dying unfinished is being started where it cannot be finished, or is too slow
    to build under fire -- the expensive-defence failure."""
    lost = defaultdict(float)
    n = defaultdict(int)
    for d in g.deaths:
        if not d["built"]:
            lost[d["name"]] += d["cost"]
            n[d["name"]] += 1
    if not lost:
        return []
    total = sum(lost.values())
    allbuilt = sum(d["cost"] for d in g.deaths) or 1.0
    rank = sorted(lost.items(), key=lambda kv: -kv[1])
    sev = 1 if total > 0.15 * allbuilt else 2
    return [Finding(
        "frame-waste", sev,
        "%.0f metal died as unfinished nanoframes (%.0f%% of everything we lost)"
        % (total, total / allbuilt * 100),
        ["%-14s %7.0fm over %3d frame(s)  (%.0fm each)" % (d, v, n[d], v / n[d])
         for d, v in rank[:10]])]


def check_piecemeal(g):
    """Army lost in ones and twos is army fed into a fight it never joined. Army
    lost in clumps is a battle, which may simply have been lost. The two want
    different fixes, so they are separated here rather than pooled into one
    kill/loss ratio."""
    army = sorted((d for d in g.deaths if d["mob"] and d["built"] and d["cost"] > 1),
                  key=lambda d: d["frame"])
    if len(army) < 10:
        return []
    window = 15 * FRAME_S
    clumps, cur = [], [army[0]]
    for d in army[1:]:
        if d["frame"] - cur[-1]["frame"] <= window:
            cur.append(d)
        else:
            clumps.append(cur)
            cur = [d]
    clumps.append(cur)
    total = sum(d["cost"] for d in army)
    trickle = sum(sum(x["cost"] for x in c) for c in clumps if len(c) <= 2)
    share = trickle / total if total else 0.0
    if share <= 0.35:
        return []
    return [Finding(
        "piecemeal", 1,
        "%.0f%% of army metal died in ones and twos, not in battles" % (share * 100),
        ["army lost %.0fm across %d engagement window(s), %d of them 1-2 units"
         % (total, len(clumps), sum(1 for c in clumps if len(c) <= 2)),
         "biggest single battle %.0fm over %d units"
         % (max(sum(x["cost"] for x in c) for c in clumps),
            max(len(c) for c in clumps)),
         "units arriving at the fight one at a time, or left alone to be picked off"])]


def check_deep_deaths(g):
    """fwd is the forward fraction: 0 at our base, 1 at theirs. Army metal lost
    past 0.5 died on their half, beside their static defence and inside their
    reinforcement range -- the most expensive ground there is to fight on."""
    army = [d for d in g.deaths if d["mob"] and d["built"] and d["cost"] > 1]
    if len(army) < 10:
        return []
    total = sum(d["cost"] for d in army)
    deep = sum(d["cost"] for d in army if d["fwd"] > 0.5)
    share = deep / total if total else 0.0
    if share < 0.4:
        return []
    return [Finding(
        "deep-deaths", 1 if share > 0.6 else 2,
        "%.0f%% of army metal died past the halfway line, on their ground" % (share * 100),
        ["%.0fm of %.0fm at fwd>0.5; median fwd at death %.2f"
         % (deep, total, _med(d["fwd"] for d in army)),
         "cross-check front-geometry: if the staging lane sits inside their "
         "territory, this is simply where the army was told to stand"])]


def check_never_fought(g):
    """A unit with an empty fight history died without ever engaging: caught out
    of position, bombed, or run down while moving."""
    army = [d for d in g.deaths if d["mob"] and d["built"] and d["cost"] > 1]
    if len(army) < 10:
        return []
    quiet = [d for d in army if not d["fhist"] and "atk" not in d["acts"]]
    total = sum(d["cost"] for d in army)
    qm = sum(d["cost"] for d in quiet)
    share = qm / total if total else 0.0
    if share < 0.3:
        return []
    return [Finding(
        "never-fought", 1 if share > 0.5 else 2,
        "%.0f%% of army metal died without ever attacking anything" % (share * 100),
        ["%d of %d units, %.0fm of %.0fm" % (len(quiet), len(army), qm, total),
         "no fight history and no attack action in the unit's own action log"])]


CHECKS = [check_front, check_plant_glut, check_frag, check_frame_waste,
          check_piecemeal, check_deep_deaths, check_never_fought]

ALL_NAMES = ["front-geometry", "plant-glut", "frag", "frame-waste",
             "piecemeal", "deep-deaths", "never-fought"]


# --------------------------------------------------------------------- driver

def infologs(target):
    if target.is_file():
        return [target]
    direct = target / "infolog.txt"
    if direct.exists():
        return [direct]
    return sorted(target.glob("matches/*/infolog.txt"))


def run_one(path, quiet=False):
    g = Game(path)
    findings = []
    for c in CHECKS:
        findings += c(g)
    findings.sort(key=lambda f: f.severity)
    if not quiet:
        print("\n=== %s  (%.1f game-min, %d deaths, %d requests)"
              % (path.parent.name, g.minutes, len(g.deaths), len(g.requests)))
        if not findings:
            print("    clean -- no check fired")
        for f in findings:
            print(f)
    return g, findings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("target", nargs="?", default=None)
    ap.add_argument("--agg", action="store_true",
                    help="pool over every game, report how often each check fires")
    ap.add_argument("--each", action="store_true",
                    help="per-game detail even for a whole tournament")
    args = ap.parse_args()

    if args.target:
        target = Path(args.target)
    else:
        runs = sorted(p for p in (REPO / "tournaments").iterdir() if p.is_dir())
        if not runs:
            sys.exit("no tournaments/ to read")
        target = runs[-1]

    logs = infologs(target)
    if not logs:
        sys.exit("no infolog under %s" % target)

    # A whole tournament printed game by game is unreadable, and the useful
    # question there is "how often does this fire", not "what happened in t017".
    if args.each or (not args.agg and len(logs) <= 3):
        for p in logs:
            run_one(p)
        return

    fired = defaultdict(int)
    first = {}
    n = 0
    for p in logs:
        g, findings = run_one(p, quiet=True)
        if not g.is_apex:
            continue
        n += 1
        for check in set(f.check for f in findings):
            fired[check] += 1
            if check not in first:
                first[check] = next(f for f in findings if f.check == check)
    print("\n=== %s: %d apex game(s)\n" % (target.name, n))
    for name in sorted(ALL_NAMES, key=lambda k: -fired.get(k, 0)):
        count = fired.get(name, 0)
        if count:
            print("%3d/%-3d  %-16s  e.g. %s" % (count, n, name, first[name].headline))
        else:
            print("%3d/%-3d  %-16s  (never fired)" % (0, n, name))


if __name__ == "__main__":
    main()
