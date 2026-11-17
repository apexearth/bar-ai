"""The behaviour contract: every behaviour he has called wrong, measured per seat in every game, ours against the
release seats playing the same games. His 11-14: "find a way to validate our games so that we don't allow ourselves to
create this sort of problem in the first place ... I keep seeing regressions."

    python tools/contract.py matches/pkg1-v0-*            # table + verdict, exit 1 on any FAIL
    python tools/contract.py matches/pkg1-v0-* --us estall --them v0.5.11

A check FAILS when our seats are worse than theirs over the batch (median per seat for times, totals per seat for
counts), by more than its noise margin. Nothing here is an invented threshold: the release in the same games is the
bar. Add a check = add one function to CHECKS; each names his words in its docstring.
"""
from __future__ import annotations

import argparse
import collections
import glob
import json
import math
import re
import statistics
import sys
from pathlib import Path

DEATH_LINE = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\w+) .*? atkteam=(-?\d+) atk=(\w+)")
LINE = re.compile(r"\[f=(-?\d+)\] Skirmish AI <ApexUnstable-([^>]+)>: (?:\[[\d.]+m t(\d+)\] )?apex: (.*)")
T_IN = re.compile(r"\bt=(\d+)\b")


class Seat:
    def __init__(self, match: str, team: int, ai: str):
        self.match, self.team, self.ai = match, team, ai
        self.stats: list[dict] = []
        self.lines: dict[str, list[tuple[int, str]]] = collections.defaultdict(list)
        self.deaths: list[tuple[int, str, str]] = []   # (frame, unit, killer) from [BARAI_DEATH]
        self.kills: list[tuple[int, str, str]] = []    # (frame, their unit, our killer)


KEEP = ("exec t=", "decide t=", "ring-trim ", "congift ", "air run scored", "air run end", "peeled ", "metal cur=",
        "facqueue takes ", "facqueue lines=", "placed t=", "latency ",
        "unit-destroyed ", "defmeasured-stat ", "nnair-go gunships", "unstick-nudge ", "frontline perim", "raid-answer t=",
        "com-pos ", "armyest t=")


def load(match: Path) -> list[Seat]:
    _MATCH_DIRS[match.name] = str(match)
    res = json.loads((match / "result.json").read_text())
    side_ai = {t["team"]: t.get("version") or t["spec"] for t in res.get("teams", [])}
    seats: dict[int, Seat] = {}
    for r in res.get("stats") or []:
        if r.get("reason") != "periodic":
            continue
        t = int(r["team"])
        if t not in seats:
            seats[t] = Seat(match.name, t, side_ai.get(int(r["ally"]), "?"))
        seats[t].stats.append(r)
    for s in seats.values():
        s.stats.sort(key=lambda r: r["frame"])
    with open(match / "infolog.txt", errors="replace") as fh:
        for raw in fh:
            if raw.startswith("[") and "[BARAI_DEATH]" in raw:
                d = DEATH_LINE.search(raw)
                if d and int(d.group(2)) in seats:
                    seats[int(d.group(2))].deaths.append((int(d.group(1)), d.group(3), d.group(5)))
                if d and int(d.group(4)) in seats and int(d.group(4)) != int(d.group(2)):
                    seats[int(d.group(4))].kills.append((int(d.group(1)), d.group(3), d.group(5)))
                continue
            if "apex: " not in raw:
                continue
            m = LINE.search(raw)
            if not m:
                continue
            body = m.group(4)
            key = next((k for k in KEEP if body.startswith(k)), None)
            if key is None:
                continue
            team = m.group(3)
            if team is None:
                tm = T_IN.search(body)
                team = tm.group(1) if tm else None
            if team is None or int(team) not in seats:
                continue
            seats[int(team)].lines[key].append((int(m.group(1)), body))
    return list(seats.values())


# --- the checks: each returns a number for one seat (lower is better) or None when it does not apply -------------

MOHO_DONE = re.compile(r"latency \w*(moho|uwmme)\w* done=")


def _moho_minutes(s: Seat, k: int):
    """Minutes from T2 to the k-th advanced extractor finished, from the frame of its `latency <moho> done=` line (the
    stats rows come every 2 minutes, coarser than the differences being judged). None before T2; the game's end when
    the k-th never finished."""
    tech = next((r["techFrame"] for r in s.stats if r.get("techFrame", -1) > 0), None)
    if tech is None:
        return None
    done = sorted(f for f, b in s.lines["latency "] if MOHO_DONE.search(b) and f >= tech)
    at = done[k - 1] if len(done) >= k else s.stats[-1]["frame"]
    return (at - tech) / 1800.0


def t2_to_first_moho(s: Seat):
    """His 11-14: income 1x to 4x within ~3 minutes of T2, not ~10. Minutes from T2 to the first advanced extractor."""
    return _moho_minutes(s, 1)


def t2_to_four_moho(s: Seat):
    """The same, to the fourth advanced extractor."""
    return _moho_minutes(s, 4)


PLANTJOB = re.compile(r"exec t=\d+ \w+ #(\d+) (plant|tech|assist):(\w+).*? at=(-?\d+),(-?\d+)")
DECIDE = re.compile(r"decide t=\d+ \w+ #(\d+) -> [\w/]+:([\w-]+)")
PLACED = re.compile(r"placed t=\d+ (\w+) at=(-?\d+),(-?\d+)")
SAME_SITE = 400.0


def _is_plant(d: str) -> bool:
    return "lab" in d or "vp" in d or "ap" in d


def lab_job_leaves(s: Seat):
    """His 11-14: a con on a T2 lab "stops, walks away, and then goes right back ... a pure waste of time". Times a
    builder on a factory's construction was re-decided onto something else before the factory stood, per builder put
    on one. The plant finishing (`placed`) ends every job on it; an assist on a plant already standing is its
    production, not its construction, and is not counted."""
    events = sorted(s.lines["exec t="] + s.lines["decide t="] + s.lines["placed t="],
                    key=lambda e: (e[0], not e[1].startswith("placed")))
    on = {}
    done = []      # (def, x, z, frame) of every plant finished
    left = []      # (def, x, z, frame) of every builder re-decided off a plant job
    jobs = 0

    def near(x, z, a, b):
        return (x - a) ** 2 + (z - b) ** 2 <= SAME_SITE ** 2

    for f, body in events:
        p = PLACED.match(body)
        if p:
            if _is_plant(p.group(1)):
                x, z = float(p.group(2)), float(p.group(3))
                done.append((p.group(1), x, z, f))
                for uid in [u for u, (dd, a, b) in on.items() if dd == p.group(1) and near(x, z, a, b)]:
                    del on[uid]
            continue
        m = PLANTJOB.match(body)
        if m and _is_plant(m.group(3)):
            t = re.search(r"task=(-?\d+),(-?\d+)", body)
            x, z = (float(t.group(1)), float(t.group(2))) if t else (float(m.group(4)), float(m.group(5)))
            if any(dd == m.group(3) and near(x, z, a, b) for dd, a, b, _f in done):
                on.pop(m.group(1), None)
                continue
            if m.group(1) not in on:
                jobs += 1
            on[m.group(1)] = (m.group(3), x, z)
            continue
        d = DECIDE.match(body)
        if d and d.group(1) in on and on[d.group(1)][0] not in d.group(2):
            dd, a, b = on.pop(d.group(1))
            left.append((dd, a, b, f))
    # the plant finished within two seconds of the re-decide: the job was done, not left
    leaves = sum(1 for dd, a, b, f in left
                 if not any(pd == dd and near(a, b, x, z) and f <= pf <= f + 60 for pd, x, z, pf in done))
    return (leaves / jobs) if jobs else None


def near_done_stripped(s: Seat):
    """His 11-14: "something 95% done and then taking a long time to finally 100% complete". Crews cut to one hand on a
    frame already >= 90% done. Per 10k metal built (his 11-16: a raw count failed a seat for out-building the release);
    a seat that built under 10k has too few frames to read."""
    built = s.stats[-1].get("mBuiltReal", 0) if s.stats else 0
    if built < 10000:
        return None
    n = 0
    for _f, body in s.lines["ring-trim "]:
        m = re.search(r"done=([\d.]+)", body)
        if m and float(m.group(1)) >= 0.9:
            n += 1
    return n * 10000.0 / built


def t2_cons_given_early(s: Seat):
    """His 11-14: the first T2 con "walks to some other allies base and then was given away"; our extractors first.
    Advanced cons given away before this seat had four advanced extractors."""
    four = next((r["frame"] for r in s.stats if r.get("t2Mex", 0) >= 4), 10 ** 9)
    return sum(1 for f, _b in s.lines["congift "] if f < four)


ANS_SENT = re.compile(r"raid-answer t=\d+ sent .* m=(\d+) n=.* army=(\d+)")


def raid_answer_share(s: Seat):
    """His 11-16: "very aggressive enemy pushes can't hold us back from doing our own pushes and we need to make sure
    that we don't end up with our entire army just chasing small raiding groups". The largest raid answer of the game
    as a share of the army standing then (army= on the sent line; older logs lack it and read None)."""
    best = None
    for f, body in s.lines["raid-answer t="]:
        m = ANS_SENT.search(body)
        if not m:
            continue
        army = float(m.group(2))
        if army > 0:
            x = float(m.group(1)) / army
            best = x if best is None else max(best, x)
    return best


TICKS = ("armflea", "armfav", "corfav", "legscout")


def mex_lost_to_ticks(s: Seat):
    """His 11-16, watching v0.5.14 vs WRDistilled on Carrot Mountains: we lose extractors to Ticks that one turret
    would stop; one turret can guard up to four extractors and pays for itself in about a minute. Extractors of this
    seat killed by a Tick or a scout car before minute 10."""
    return float(sum(1 for f, u, k in s.deaths if (k in TICKS) and ("mex" in u or "moho" in u) and f < 10 * 1800))


def their_mex_killed(s: Seat):
    """His 11-16, watching v0.5.14 beat WRDistilled on Carrot Mountains: we won by out-scaling to T2 while they built
    a huge army; we hit their base and did too little raiding of their extractors to choke their economy. Their
    extractors this seat killed per 10 minutes played, negative (more is better)."""
    if not s.stats:
        return None
    mins = s.stats[-1]["frame"] / 1800.0
    if mins < 5:
        return None
    n = sum(1 for f, u, k in s.kills if "mex" in u or "moho" in u)
    return -10.0 * n / mins


def trade_lost_per_killed(s: Seat):
    """His 11-16 strategy against a heavy-army opponent: make them trade worse than us (a medium army and strong
    defences they bleed into). Metal we lost per metal we killed, at the end of the seat's game."""
    if not s.stats:
        return None
    r = s.stats[-1]
    killed = r.get("mKillReal", 0) or 0
    return (r.get("mLostReal", 0) or 0) / max(killed, 500.0)


def reclaim_share(s: Seat):
    """The same strategy: resurrection bots eat the reclaim of what they lose. Metal reclaimed (and resurrected) over
    the metal of theirs we killed, negative (more is better); None before 2,000 metal killed."""
    if not s.stats:
        return None
    r = s.stats[-1]
    killed = r.get("mKillReal", 0) or 0
    if killed < 2000:
        return None
    return -((r.get("mReclaim", 0) or 0) + (r.get("mRezSpend", 0) or 0)) / killed


ARMYEST = re.compile(r"armyest t=\d+ ours=(\d+) own=\d+ .*? theirs=(\d+)")


def outarmied(s: Seat):
    """His 11-16, watching WRDistilled 0.4 on Comet Catcher: we do not react properly to an opponent who builds a great
    deal of army (his +50 game: their army 12.3k against our 3.7k at minute 12 with the economies close). Their
    believed ground army over our side's, mean of the samples from minute 8 to 12."""
    r = []
    for f, b in s.lines["armyest t="]:
        if 8 * 1800 <= f <= 12 * 1800 and (m := ARMYEST.search(b)):
            ours, theirs = float(m.group(1)), float(m.group(2))
            r.append(theirs / max(ours, 100.0))
    return sum(r) / len(r) if r else None


COM_POS = re.compile(r"com-pos t=\d+ at=\S+ fwd=(-?[\d.]+)")
COM_DIED = re.compile(r"unit-destroyed (arm|cor|leg)com\S* .*? fwd=(-?[\d.]+)")


def com_their_half_minutes(s: Seat):
    """His 11-16 watch game vs WRDistilled: "we lost because the com got caught out in danger" (he walked extractor to
    extractor to 0.70 of the way to their start, priced at zero risk). Minutes the commander stood past the middle,
    from the 30-s com-pos samples."""
    return 0.5 * sum(1 for _, b in s.lines["com-pos "] if (m := COM_POS.search(b)) and float(m.group(1)) > 0.5)


def com_lost_their_half(s: Seat):
    """The same words: 1 when the seat's commander died past the middle of the map, else 0."""
    return float(any((m := COM_DIED.search(b)) and float(m.group(2)) > 0.5 for _, b in s.lines["unit-destroyed "]))


def frozen_minutes(s: Seat):
    """His 11-14: "when we lose too much of our base we don't rebuild". Minutes after minute 8 with nothing built while
    the seat still stood."""
    mins = 0.0
    prev = None
    for r in s.stats:
        if prev is not None and r["frame"] >= 8 * 1800 and r.get("mBuiltReal", 0) - prev <= 0:
            mins += 2.0
        prev = r.get("mBuiltReal", 0)
    return mins


def bare_hands_minutes(s: Seat):
    """His 11-14: "we'll lose our base and we don't really try to rebuild it even when there's nobody contesting it".
    Minutes after minute 8 with at most one constructor standing (anomaly sweep: 98 seats fell to 0-1 with commander
    and labs alive)."""
    return 2.0 * sum(1 for r in s.stats if r["frame"] >= 8 * 1800 and (r.get("conT1", 0) + r.get("conT2", 0)) <= 1)


def wing_wiped_runs(s: Seat):
    """His 11-14: ~100 fighters met every bombing run; runs must not be fed in to die. Bomber runs with no survivor that
    followed another run with none (`home=`, the run's own survivors; `surv=` is the running estimate), as a share of
    the seat's runs: a count rises with income alone (rc3: 922 bombers sent vs the release's 572, same wiped share)."""
    run = worst = n = 0
    for _f, body in s.lines["air run scored"]:
        m = re.search(r"home=(\d+)", body)
        if not m:
            continue
        n += 1
        run = run + 1 if int(m.group(1)) == 0 else 0
        worst += 1 if run >= 2 else 0
    return worst / n if n >= 2 else None


def gunships_sent_to_lose(s: Seat):
    """His 11-15, a hosted 4v4 at minute 78: "50 or more Tyrannus ... just sitting around doing nothing", "they're under
    attack ... not even using them defensively". The stale net turned the rule's WAIT into GO at a cell the wing's own
    price said loses (killF=0, net=-321), every 25 s for 14 minutes, so the wing hovered there instead of holding home.
    Share of the seat's gunship launches made at a negative own price."""
    nets = [int(m.group(1)) for _f, body in s.lines["nnair-go gunships"] if (m := re.search(r"net=(-?\d+)", body))]
    return sum(1 for v in nets if v < 0) / len(nets) if len(nets) >= 2 else None


def army_stuck_per_10(s: Seat):
    """His 11-15 v0.5.13 game: pushes stall because the move order points "right inside of a bunch of things ...
    dead robot bodies", "it continuously retries to move to a place it can't go". Army units the stuck watcher caught
    standing under an order (unstick-nudge without `builder`), per ten game minutes (t4-t7 there: 123-203 by ~40 min),
    per 1,000 metal of standing army (armyReal, mean over the game): per seat alone, a side that wins fields more army
    and reads worse (h07: v0.5.13 41 vs v0.5.07 16 per seat, 4.9 vs 7.2 per 1k army metal)."""
    n = sum(1 for _f, b in s.lines["unstick-nudge "] if " builder" not in b)
    end = max((r["frame"] for r in s.stats), default=0)
    army = [r.get("armyReal", 0) for r in s.stats]
    mean_k = (sum(army) / len(army) / 1000.0) if army else 0.0
    if end <= 1800 * 5 or mean_k < 0.5:
        return None
    return 10.0 * n / (end / 1800.0) / mean_k


FRONT_CELLS = re.compile(r"cAlly=(\d+) cFoe=(\d+)")


def ground_given_up(s: Seat):
    """His 11-15 v0.5.13 game: "consistently getting pushed back ... if you keep falling back and getting more and more
    tight into your base, you will definitely not win ... it's just a slow death" (doctrine: push the front back).
    Our share of the held cells (cAlly over cAlly+cFoe) from minute 10: the deepest fall below its own running peak
    (t4 there: 176 of 1001 cells at minute 26, 17 of 1383 by minute 48)."""
    peak = worst = 0.0
    seen = False
    for f, b in s.lines["frontline perim"]:
        m = FRONT_CELLS.search(b)
        if f < 18000 or not m or int(m.group(1)) + int(m.group(2)) == 0:
            continue
        seen = True
        share = int(m.group(1)) / (int(m.group(1)) + int(m.group(2)))
        peak = max(peak, share)
        worst = max(worst, peak - share)
    return worst if seen else None


SENSE_R = {"rad": 2100, "frad": 2100, "arad": 3500, "jamt": 500, "veil": 760, "shroud": 700, "jam": 390}
SENSE_PLACED = re.compile(r"placed t=\d+ ((arm|cor|leg)(rad|frad|arad|jamt|veil|shroud|jam)) at=(-?\d+),(-?\d+)")
SENSE_DIED = re.compile(r"unit-destroyed ((arm|cor|leg)(rad|frad|arad|jamt|veil|shroud|jam)) .*? at=(-?\d+),(-?\d+)")


def stacked_senses(s: Seat):
    """His 11-15 v0.5.13 game: "multiple radar or jammers completely adjacent to each other ... pretty much pointless";
    a jammer hides the buildings around it, one is enough (t4: five Cortex jammers in a row 32 apart, t6: three Veils
    40 apart). Radar or jammer placements within a quarter of their own range of a standing one of the same kind
    (radar with radar, jammer with jammer); a rebuild on a dead one's spot is not stacking."""
    ev = sorted([(f, 0, m) for f, b in s.lines["placed t="] if (m := SENSE_PLACED.search(b))]
                + [(f, 1, m) for f, b in s.lines["unit-destroyed "] if (m := SENSE_DIED.search(b))], key=lambda e: (e[0], e[1]))
    if not ev:
        return None
    standing = {"radar": [], "jam": []}
    stacked = 0
    for _f, died, m in ev:
        kind = "radar" if m.group(3) in ("rad", "frad", "arad") else "jam"
        x, z = float(m.group(4)), float(m.group(5))
        if died:
            near = min(range(len(standing[kind])), default=None,
                       key=lambda i: math.hypot(standing[kind][i][0] - x, standing[kind][i][1] - z))
            if near is not None and math.hypot(standing[kind][near][0] - x, standing[kind][near][1] - z) < 64:
                standing[kind].pop(near)
            continue
        r = SENSE_R[m.group(3)]
        if any(math.hypot(a - x, b - z) < 0.25 * r for a, b in standing[kind]):
            stacked += 1
        standing[kind].append((x, z))
    return float(stacked)


ADV_PLANT = re.compile(r"^(arm|cor|leg)(a(lab|vp|ap|sy)|gant|shltx|haap|halab|havp)")
_SLOW_CACHE: dict = {}


def adv_plant_frame_x(s: Seat):
    """His 11-14: "a 4.5 minute T2 lab turned into a 7 minute T2 lab". Seconds an advanced plant's frame stood, over
    the build seconds it was priced at (median over the seat's advanced plants; tools/slowbuild.py pairs them)."""
    import slowbuild
    key = (s.match, s.ai)
    if key not in _SLOW_CACHE:
        lines, _ = slowbuild.scan(Path(_MATCH_DIRS[s.match]) / "infolog.txt", s.ai)
        _SLOW_CACHE[key] = slowbuild.analyse(Path(_MATCH_DIRS[s.match]), lines, None, 0.0, -1e9)
    # the seat's FIRST advanced plant, the unlock he timed; a later plant is fed its share like any other site
    # a plant whose decision logged no price (calib-build walk=0 build=0, ~1 in 5 for both AIs) has no ratio: the 10 s
    # floor made its 200-s frame read 20x (na7/na8: three such seats failed the check alone)
    xs = sorted((b["start"], b["frame_s"] / max(b["build"], 10), b["build"] + b["walk"]) for b in _SLOW_CACHE[key]
                if b["team"] == s.team and ADV_PLANT.match(b["d"]))
    return xs[0][1] if xs and xs[0][2] > 0 else None


_MATCH_DIRS: dict = {}


def anomalous_seat(s: Seat):
    """His 11-14: an anomaly detector -- "when all of a sudden our AI acts dramatically different from the way it
    normally acts". 1 when any feature of the seat sits >= 5 robust deviations from the release's normal play in the
    same regime (tools/anomaly.py), else 0; None without a baseline."""
    import anomaly
    res = json.loads((Path(_MATCH_DIRS[s.match]) / "result.json").read_text())
    n = anomaly.seat_anomalies(res, s.team, s.stats)
    return None if n < 0 else (1.0 if n > 0 else 0.0)


def runs_turned_back(s: Seat):
    """His 11-14: the bombers "are met by the enemy fighters and then we turn around and we just run ... dying to
    enemy fighters". Bomber runs recalled with survivors before any reached the cell (`apex: air run end arrived=0
    left=N/..` with N > 0; a wave shot down on the way in is a wiped run, not a retreat). None for a build that does not
    log the line (11-14 on), so it never compares against a silent release."""
    ends = s.lines["air run end"]
    if not ends:
        return None
    return float(sum(1 for _f, b in ends if "arrived=0" in b and not re.search(r"left=0/", b)))


def no_t2_by_20(s: Seat):
    """The T2 checks skip a seat that never reaches T2, so a change that stops T2 would pass them. 1 when the seat
    stood past minute 20 with no T2, else 0."""
    if not s.stats or s.stats[-1]["frame"] < 20 * 1800:
        return None
    return 0.0 if any(0 < r.get("techFrame", -1) <= 20 * 1800 for r in s.stats) else 1.0


def lone_t2_minutes(s: Seat):
    """His 11-14: a seat with a T2 air plant "has only one T2 con. Just one." Minutes from two minutes after T2 with at
    most one advanced constructor standing WHILE an advanced plant stands to make more (pkg3-rc-A9501 t0: one from
    minute 14 to 30, no moho finished; rc5's three worst seats had lost every advanced plant first, a lost fight)."""
    tech = next((r["techFrame"] for r in s.stats if r.get("techFrame", -1) > 0), None)
    if tech is None:
        return None
    ev = sorted([(f, 1) for f, b in s.lines["latency "] if ADV_PLANT_DONE.search(b)]
                + [(f, -1) for f, b in s.lines["unit-destroyed "] if ADV_PLANT_DIED.search(b)])
    def standing(frame):
        return sum(d for f, d in ev if f <= frame)
    return 2.0 * sum(1 for r in s.stats if r["frame"] >= tech + 2 * 1800 and r.get("conT2", 0) <= 1
                     and standing(r["frame"]) > 0)


ADV_PLANT_DONE = re.compile(r"latency (arm|cor|leg)a(lab|vp|ap|sy) done=")
ADV_PLANT_DIED = re.compile(r"unit-destroyed (arm|cor|leg)a(lab|vp|ap|sy) ")


DM_STAT = re.compile(r"target=[\d.]+->([\d.]+) have=([\d.]+)")
STRUCT_DIED = re.compile(r"unit-destroyed \w+ .*?cost=([\d.]+) fwd=(-?[\d.]+) .*?mob=0")


def covered_losses_k(s: Seat):
    """His 11-15 hosted 4v4: "our base is just dying to spam ... completely predictable", while the defence pricer read
    the stream as one arrival and held its target under what stood (t4: 0 of 63 tower bids won). Thousands of metal of
    our structures lost on our side of the map (forward fraction < 0.5) while the pricer said we had enough."""
    events = sorted([(f, 0, b) for f, b in s.lines["defmeasured-stat "]] + [(f, 1, b) for f, b in s.lines["unit-destroyed "]])
    if not s.lines["defmeasured-stat "]:
        return None
    covered, lost = False, 0.0
    for _f, kind, body in events:
        if kind == 0:
            m = DM_STAT.search(body)
            if m:
                covered = float(m.group(2)) >= float(m.group(1)) > 0.0
        elif covered:
            m = STRUCT_DIED.search(body)
            if m and float(m.group(2)) < 0.5:
                lost += float(m.group(1))
    return lost / 1000.0


OLDEST = re.compile(r"facqueue lines=.* oldest=(\d+)s")


def oldest_order_minutes(s: Seat):
    """His 11-14 "only one T2 con. Just one.": a plant order still waiting to be built, longest in the game. Each new
    batch used to jump the queued ones, so on a busy lab a T2 con order waited for ever (rc3-rc2-A9504 t1, 12.8 min on)
    and the floor, counting it pending, ordered no other. None for a build that does not log the age (before 11-15)."""
    ages = [int(m.group(1)) for _f, b in s.lines["facqueue lines="] for m in [OLDEST.search(b)] if m]
    return max(ages) / 60.0 if ages else None


ADV_CON = re.compile(r"exec t=\d+ (arm|cor|leg)(ack|acv|aca|acsub) #\d+ super:")


def supers_before_upgrades(s: Seat):
    """His 11-14: the first T2 con "should be upgrading our metal extractors", 1x to 4x income. Strategic builds
    (silo, anti-nuke, long-range gun, gantry) ordered to advanced constructors before the 4th advanced extractor
    finished (rc2-cm2-C9502 t0: the first T2 con took an anti-nuke at v=2.4 over an upgrade at v=52.8)."""
    tech = next((r["techFrame"] for r in s.stats if r.get("techFrame", -1) > 0), None)
    if tech is None:
        return None
    done = sorted(f for f, b in s.lines["latency "] if MOHO_DONE.search(b) and f >= tech)
    four = done[3] if len(done) >= 4 else 10 ** 9
    return sum(1 for f, b in s.lines["exec t="] if f < four and ADV_CON.search(b))


def cons_peak(s: Seat):
    """His 11-14 randomizer game: 143-232 constructors a seat and no army. Most constructors standing at once, per the
    seat's best metal income, as a log so the margin is a ratio (his 11-15: a bigger economy with the same army share
    is not this failure; rc5+rc6 121 vs 106 cons on 17% more income)."""
    cons = max((int(r.get("conT1", 0) + r.get("conT2", 0)) for r in s.stats), default=0)
    inc = max((r.get("mInc", 0) for r in s.stats), default=0)
    return math.log(cons / inc) if cons > 0 and inc > 0 else None


def income_at_20(s: Seat):
    """His eco target (memory eco-target-750): metal income at minute 20. Negative log, so lower is better and the
    margin is a ratio (0.15 ~ 14% below the release's median seat). None for a seat gone before minute 20."""
    rows = [r for r in s.stats if r["frame"] <= 36060]
    if not rows or rows[-1]["frame"] < 35000 or rows[-1].get("mInc", 0) <= 0:
        return None
    return -math.log(rows[-1]["mInc"])


def army_share(s: Seat):
    """His 11-14: "have an army that is capable of fighting". Share of all metal built that went to army, at the end
    (lower is worse, so negated)."""
    if not s.stats or s.stats[-1].get("mBuiltReal", 0) <= 0:
        return None
    return -s.stats[-1].get("mArmy", 0) / s.stats[-1]["mBuiltReal"]


# (name, measure, aggregate, noise margin, his stated aim or None). A regression past the margin FAILS the batch; the
# aim is his words made a number, reported as "short of aim" and never gating (his words are intent, not thresholds).
CHECKS = [
    ("t2->1st moho (min)", t2_to_first_moho, "median", 0.5, None),
    ("t2->4th moho (min)", t2_to_four_moho, "median", 1.0, 3.0),     # "1x to 4x ... within three minutes"
    ("lab-job leaves/job", lab_job_leaves, "median", 0.10, 0.0),     # "no good reason it should walk away"
    ("adv plant frame x", adv_plant_frame_x, "median", 0.5, 1.5),    # "4.5 minute T2 lab turned into 7"
    ("near-done /10k built", near_done_stripped, "mean", 0.1, 0.0),  # "we should stop doing that"
    ("t2 cons given early", t2_cons_given_early, "mean", 0.25, 0.0), # "upgrade our metal extractors" first
    ("supers before 4 moho", supers_before_upgrades, "mean", 0.5, 0.0),  # the same, strategic builds first
    ("lone t2 con minutes", lone_t2_minutes, "mean", 1.0, 0.0),      # "only one T2 con. Just one."
    ("base lost while 'covered' k", covered_losses_k, "mean", 1.0, 0.0),   # "our base is just dying to spam"
    ("oldest plant order min", oldest_order_minutes, "mean", 1.0, None),  # n/a vs a release that cannot log it
    ("no t2 by minute 20", no_t2_by_20, "mean", 0.10, None),         # the T2 checks skip such seats
    ("frozen minutes", frozen_minutes, "mean", 1.0, 0.0),            # "we don't rebuild"
    ("raid answer army share", raid_answer_share, "mean", 0.1, None),  # "not our entire army chasing small raids"
    ("com minutes on their half", com_their_half_minutes, "mean", 0.5, None),  # "the com got caught out in danger"
    ("com lost on their half", com_lost_their_half, "mean", 0.05, 0.0),
    ("mex lost to ticks by 10 min", mex_lost_to_ticks, "mean", 0.5, 0.0),  # one turret guards up to four extractors
    ("their mex killed /10min (neg)", their_mex_killed, "mean", 2.0, None),  # choke their economy, not only their base
    ("their army / ours, 8-12 min", outarmied, "mean", 0.25, None),     # react to an opponent who builds a lot of army
    ("lost per killed", trade_lost_per_killed, "median", 0.15, None),  # make them trade worse than us
    ("reclaimed / killed (neg)", reclaim_share, "median", 0.05, None),  # resbots eat the reclaim
    ("bare-hands minutes", bare_hands_minutes, "mean", 1.0, 0.0),    # "we don't really try to rebuild it"
    ("wiped bomber runs", wing_wiped_runs, "mean", 0.15, 0.0),       # share; the release alone spans 0.40-0.57 on the same seeds
    ("runs turned back", runs_turned_back, "mean", 0.25, 0.0),       # "we turn around and we just run"
    ("gunships sent to lose", gunships_sent_to_lose, "mean", 0.10, 0.0),  # "just sitting around doing nothing"
    ("stacked radar/jammers", stacked_senses, "mean", 0.5, 0.0),     # "completely adjacent ... pretty much pointless"
    ("army stuck /10min/1k army", army_stuck_per_10, "median", 1.0, 0.0),  # "continuously retries to move to a place it can't go"
    ("ground given up share", ground_given_up, "mean", 0.05, 0.0),   # "falling back ... tight into your base ... slow death"
    ("anomalous seats", anomalous_seat, "mean", 0.10, 0.0),          # "acts dramatically different"
    ("log peak cons per income", cons_peak, "mean", 0.10, None),   # mean: a median falls between map clusters
    ("army share (neg)", army_share, "median", 0.03, None),
    ("-log income at 20", income_at_20, "median", 0.15, None),  # his eco target, minute 20
]


AI_ROOTS = ("ai/Unstable/", "cpp/", "game-patches/")
MIN_GAMES = 12   # the release-gate batch size (memory: release gate, both factions, rich + normal maps)
REPO = Path(__file__).resolve().parent.parent
RECORDS = REPO / "runtime" / "contract"


def ai_code_key(head: str, patch_text: str) -> str:
    """The AI code a game ran: HEAD plus only the AI roots of the working-tree diff (a tools edit is not new AI)."""
    import hashlib
    keep = [s for s in re.split(r"(?m)^(?=diff --git )", patch_text or "")
            if any(s.startswith("diff --git a/" + r) for r in AI_ROOTS)]
    sha = hashlib.sha256("".join(keep).encode("utf-8", "replace")).hexdigest()[:12] if keep else "clean"
    return "%s-%s" % (head[:10], sha)


def games_code_key(dirs, us: str):
    keys = set()
    for d in dirs:
        prov = (json.loads((Path(d) / "result.json").read_text()).get("provenance") or {})
        for spec, p in prov.items():
            if us in spec and p.get("head"):
                text = (REPO / p["patch"]).read_text(encoding="utf-8", errors="replace") if p.get("patch") else ""
                keys.add(ai_code_key(p["head"], text))
    return keys


def current_code_key() -> str:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import provenance
    p = provenance.capture()
    text = (REPO / p["patch"]).read_text(encoding="utf-8", errors="replace") if p.get("patch") else ""
    return ai_code_key(p["head"], text)


def passed(key: str) -> dict | None:
    f = RECORDS / ("%s.json" % key)
    return json.loads(f.read_text()) if f.exists() else None


SKIP_FILES = {"AIInfo.lua", "nnweights.as", "policydata.as"}   # what a release rewrites for itself


def tree_hash(variant_dir: Path) -> str:
    """The AI's own script and config, as a release copy holds it: every file under game-side, by path and content."""
    import hashlib
    h = hashlib.sha256()
    root = variant_dir / "game-side"
    for f in sorted(p for p in root.rglob("*") if p.is_file() and p.name not in SKIP_FILES):
        h.update(f.relative_to(root).as_posix().encode())
        h.update(f.read_bytes().replace(b"\r\n", b"\n"))
    return h.hexdigest()[:16]


def release_cleared(variant: str) -> dict | None:
    """A PASS record whose scripts are exactly this release's (deploy_ai.py refuses a release without one)."""
    want = tree_hash(REPO / "ai" / variant)
    for f in sorted(RECORDS.glob("*.json")):
        rec = json.loads(f.read_text())
        if rec.get("tree") == want:
            return rec
    return None


def agg(vals, how):
    vals = [v for v in vals if v is not None]
    if not vals:
        return None
    return statistics.median(vals) if how == "median" else sum(vals) / len(vals)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("matches", nargs="+")
    ap.add_argument("--us", default="lane-", help="substring of our AI's version name (default: any lane)")
    ap.add_argument("--them", default=None, help="substring of the bar's version (default: every seat that is not us)")
    ap.add_argument("--md", action="store_true", help="print a markdown table (for results pages)")
    ap.add_argument("--record", action="store_true",
                    help="on PASS with >= %d games of one AI code, record it; a release deploy requires that record" % MIN_GAMES)
    a = ap.parse_args(argv)
    paths = []
    for p in a.matches:
        paths += [Path(x) for x in glob.glob(p)] or [Path(p)]
    seats = []
    for p in sorted(set(paths)):
        if (p / "result.json").exists() and (p / "infolog.txt").exists():
            seats += load(p)
    ours = [s for s in seats if a.us in s.ai]
    theirs = [s for s in seats if a.us not in s.ai and (a.them is None or a.them in s.ai)]
    if not ours or not theirs:
        print("contract: need seats of both (ours %d, theirs %d)" % (len(ours), len(theirs)))
        return 2
    fails = short = 0
    rows = []
    for name, fn, how, margin, aim in CHECKS:
        o = agg([fn(s) for s in ours], how)
        t = agg([fn(s) for s in theirs], how)
        if o is None or t is None:
            rows.append((name, o, t, aim, "n/a"))
            continue
        bad = o > t + margin
        fails += bad
        miss = (aim is not None) and (o > aim + 1e-9)
        short += miss
        v = "FAIL (worse than release)" if bad else ("ok, short of aim" if miss else "ok")
        rows.append((name, o, t, aim, v))
    games = len({s.match for s in seats})
    # HEAD TO HEAD (memory: release-gate-head-to-head -- no release without beating the previous one): a game is ours
    # when our side won, or at the time cap built more metal than theirs. Under half fails.
    ahead = 0
    for m in sorted({s.match for s in seats}):
        res = json.loads((Path(_MATCH_DIRS[m]) / "result.json").read_text())
        rb = res.get("result") if isinstance(res.get("result"), dict) else {}
        win = [w for w in (rb.get("winner_specs") or res.get("winner_specs") or []) if w]
        mine = sum(s.stats[-1].get("mBuiltReal", 0) for s in ours if s.match == m and s.stats)
        theirs_b = sum(s.stats[-1].get("mBuiltReal", 0) for s in theirs if s.match == m and s.stats)
        if win:
            ahead += any(a.us in str(w) for w in win)
        else:
            ahead += mine > theirs_b
    h2h = ahead / max(1, games)
    h2h_bad = h2h < 0.5
    fails += h2h_bad
    rows.append(("games won or ahead", -h2h, -0.5, None, "FAIL (does not beat the release)" if h2h_bad else "ok"))
    fmt = lambda x, name: "-" if x is None else "%.2f" % (abs(x) if ("share" in name or "ahead" in name) else x)
    if a.md:
        print("| check | ours | release | his aim | verdict |\n|---|---|---|---|---|")
        for name, o, t, aim, v in rows:
            print("| %s | %s | %s | %s | %s |" % (name, fmt(o, name), fmt(t, name), fmt(aim, name), v))
        print("\nContract: **%s** over %d games (%d of our seats, %d release seats); %d check(s) short of his aim."
              % ("FAIL (%d)" % fails if fails else "PASS", games, len(ours), len(theirs), short))
    else:
        print("contract over %d games, %d of our seats vs %d release seats" % (games, len(ours), len(theirs)))
        for name, o, t, aim, v in rows:
            print("  %-22s ours %8s  release %8s  aim %5s  %s" % (name, fmt(o, name), fmt(t, name), fmt(aim, name), v))
        print("contract: %s; %d short of his aim" % ("FAIL (%d)" % fails if fails else "PASS", short))
    if a.record:
        keys = games_code_key(sorted({str(p) for p in paths if (p / "result.json").exists()}), a.us)
        import anomaly
        bar = anomaly.latest_release()
        them = sorted({s.ai for s in theirs})
        if fails:
            print("contract: not recorded -- FAIL")
        elif not bar or any(bar not in t for t in them):
            print("contract: not recorded -- the bar must be the newest committed release %s, these games played %s"
                  % (bar, them))
        elif games < MIN_GAMES:
            print("contract: not recorded -- %d games, a release needs %d" % (games, MIN_GAMES))
        elif len(keys) != 1:
            print("contract: not recorded -- the games ran %d different AI codes %s" % (len(keys), sorted(keys)))
        elif current_code_key() not in keys:
            print("contract: not recorded -- the AI code changed since these games (%s now, games ran %s)"
                  % (current_code_key(), sorted(keys)))
        else:
            key = keys.pop()
            RECORDS.mkdir(parents=True, exist_ok=True)
            (RECORDS / ("%s.json" % key)).write_text(json.dumps({
                "key": key, "tree": tree_hash(REPO / "ai" / "Unstable"), "games": games, "us": a.us, "them": them,
                "matches": sorted({s.match for s in seats}),
                "rows": [[n, o, t, aim, v] for n, o, t, aim, v in rows]}, indent=1))
            print("contract: recorded PASS for AI code %s" % key)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
