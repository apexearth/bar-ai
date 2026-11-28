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
import bisect
import collections
import glob
import json
import math
import random
import re
import statistics
import sys
from pathlib import Path

DEATH_LINE = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\w+) .*? atkteam=(-?\d+) atk=(\w+)")
KILLER = re.compile(r" mob=(\d) .*? atkx=(-?[\d.]+) atkz=(-?[\d.]+) .*? atkid=(\d+)")
LINE = re.compile(r"\[f=(-?\d+)\] Skirmish AI <ApexUnstable-([^>]+)>: (?:\[[\d.]+m t(\d+)\] )?apex: (.*)")
T_IN = re.compile(r"\bt=(\d+)\b")
ARMY_LINE = re.compile(r"\[BARAI_ARMY\] frame=(\d+) team=(\d+) n=\d+ part=\S+ (.*)")
DEATH_POS = re.compile(r" x=(-?\d+) z=(-?\d+) .*? built=1 mob=(\d)")
DEATH_COST = re.compile(r" unit=(\S+) cost=([\d.]+) .*? uid=(\d+)")


class Seat:
    def __init__(self, match: str, team: int, ai: str):
        self.match, self.team, self.ai = match, team, ai
        self.stats: list[dict] = []
        self.lines: dict[str, list[tuple[int, str]]] = collections.defaultdict(list)
        self.deaths: list[tuple[int, str, str]] = []   # (frame, unit, killer) from [BARAI_DEATH]
        self.done_deaths: list[tuple[int, str]] = []   # (frame, unit), finished units only (built=1)
        self.kills: list[tuple[int, str, str]] = []    # (frame, their unit, our killer)
        self.foe_deaths: set[tuple[int, str]] = set()  # (frame, unit) of ours an enemy killed (not our own reclaim)
        self.building_kills: list[tuple[int, int, float, float]] = []  # (frame, killer uid, killer x, z), our buildings
        self.army_snaps: dict[int, list[tuple[int, float, float, int]]] = collections.defaultdict(list)  # frame -> (uid, x, z, fired)
        self.foe_bld_dead: list[tuple[int, float, float]] = []  # (frame, x, z) of enemy buildings that died
        self.army_def: dict[int, str] = {}              # army snapshot uid -> unit name
        self.mob_deaths: list[tuple[int, float, float, float, int]] = []  # (frame, x, z, cost, uid), finished mobiles
        self.foes: list["Seat"] = []                    # the other side's seats in this game
        self.cost: dict[str, float] = {}                # unit name -> metal, from this game's death lines
        self.start: tuple[float, float] | None = None   # the commander's first army snapshot


KEEP = ("exec t=", "decide t=", "ring-trim ", "congift ", "air run scored", "air run end", "peeled ", "metal cur=",
        "facqueue takes ", "facqueue lines=", "placed t=", "latency ",
        "unit-destroyed ", "defmeasured-stat ", "nnair-go gunships", "unstick-nudge ", "frontline perim",
        "com-pos ", "armyest t=", "AA PANIC")


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
    ally_of = {int(r["team"]): int(r["ally"]) for r in res.get("stats") or [] if "ally" in r}
    cost_of: dict[str, float] = {}
    with open(match / "infolog.txt", errors="replace") as fh:
        for raw in fh:
            if raw.startswith("[") and "[BARAI_ARMY]" in raw:
                a = ARMY_LINE.search(raw)
                if a and int(a.group(2)) in seats:
                    snap = seats[int(a.group(2))].army_snaps[int(a.group(1))]
                    for it in a.group(3).replace(",", " ").split():
                        p = it.split(":")
                        if len(p) >= 6 and not p[1].endswith("com"):
                            snap.append((int(p[0]), float(p[2]), float(p[3]), int(p[5])))
                            seats[int(a.group(2))].army_def[int(p[0])] = p[1]
                        elif len(p) >= 6 and seats[int(a.group(2))].start is None:
                            seats[int(a.group(2))].start = (float(p[2]), float(p[3]))
                continue
            if raw.startswith("[") and "[BARAI_DEATH]" in raw:
                d = DEATH_LINE.search(raw)
                bp = DEATH_POS.search(raw)
                if d and bp and bp.group(3) == "0":
                    for t_, s_ in seats.items():
                        if ally_of.get(t_, t_) != ally_of.get(int(d.group(2)), int(d.group(2))):
                            s_.foe_bld_dead.append((int(d.group(1)), float(bp.group(1)), float(bp.group(2))))
                c = DEATH_COST.search(raw)
                if c:
                    cost_of[c.group(1)] = float(c.group(2))
                if d and bp and c and bp.group(3) == "1" and int(d.group(2)) in seats:
                    seats[int(d.group(2))].mob_deaths.append(
                        (int(d.group(1)), float(bp.group(1)), float(bp.group(2)), float(c.group(2)), int(c.group(3))))
                if d and int(d.group(2)) in seats:
                    seats[int(d.group(2))].deaths.append((int(d.group(1)), d.group(3), d.group(5)))
                    if " built=1 " in raw:
                        seats[int(d.group(2))].done_deaths.append((int(d.group(1)), d.group(3)))
                    at = int(d.group(4))
                    if at >= 0 and ally_of.get(at, at) != ally_of.get(int(d.group(2))):
                        seats[int(d.group(2))].foe_deaths.add((int(d.group(1)), d.group(3)))
                        k = KILLER.search(raw)
                        if k and k.group(1) == "0":
                            seats[int(d.group(2))].building_kills.append(
                                (int(d.group(1)), int(k.group(4)), float(k.group(2)), float(k.group(3))))
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
    for s_ in seats.values():
        s_.cost = cost_of
        s_.foes = [o for o in seats.values() if ally_of.get(o.team, o.team) != ally_of.get(s_.team, s_.team)]
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


TICKS = ("armflea", "armfav", "corfav", "legscout")


def mex_lost_to_ticks(s: Seat):
    """His 11-16, watching v0.5.14 vs WRDistilled on Carrot Mountains: we lose extractors to Ticks that one turret
    would stop; one turret can guard up to four extractors and pays for itself in about a minute. Extractors of this
    seat killed by a Tick or a scout car before minute 10."""
    return float(sum(1 for f, u, k in s.deaths if (k in TICKS) and ("mex" in u or "moho" in u) and f < 10 * 1800))


def raider_repeat_kills(s: Seat):
    """His 11-18, watching the army model's second watch game: "as soon as a unit would go out of sight, we would sort
    of stop chasing after it if we didn't have radar". A raider we let go comes back: our buildings killed by an
    enemy unit that had already killed one of them at least 10 s earlier and has moved since (a turret does not), per
    10 minutes played."""
    if not s.stats:
        return None
    mins = s.stats[-1]["frame"] / 1800.0
    if mins < 5:
        return None
    last = {}
    repeats = 0
    for f, killer, x, z in sorted(s.building_kills):
        if killer in last:
            lf, lx, lz = last[killer]
            if f - lf >= 300 and math.hypot(x - lx, z - lz) >= 150:
                repeats += 1
        last[killer] = (f, x, z)
    return repeats * 10.0 / mins


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


LAND_PLANT = re.compile(r"^(arm|cor|leg)(lab|vp|hp|fhp|amsub|alab|avp|gant|shltx)$")
LATENCY_DONE = re.compile(r"^latency (\w+) done=")


CONVERTER = re.compile(r"^(arm|cor|leg)\w*(makr|mmkr|econv)\w*$")


def no_converter_minutes(s: Seat):
    """11-25, a T1-only replay at 44 min: both of our seats had no energy converters on a large energy income. Minutes after the first converter finished, while the seat stood, with none standing."""
    return _none_standing_minutes(s, CONVERTER)


BASIC_MEX = re.compile(r"^(arm|cor|leg)mex$")


def mex_by_3_neg(s: Seat):
    """11-25: a slow opening, AA and radar before the third extractor, nearby spots left untaken. Extractors finished by
    minute 3, negated (more is better)."""
    if not s.stats:
        return None
    return -float(sum(1 for f, b in s.lines["latency "]
                      if f <= 5400 and (m := LATENCY_DONE.match(b)) and BASIC_MEX.match(m.group(1))))


def aa_panic_unarmed(s: Seat):
    """The same game: the AA panic put an AA tower up at 50 s - 2 min in 17 of 20 seats, on 1 metal of seen enemy air,
    the enemy's assist drones (1 metal each, unarmed). Panics on under 10 metal of seen air: no armed aircraft costs that
    little."""
    if not s.stats:
        return None
    return float(sum(1 for _f, b in s.lines["AA PANIC"] if (m := AA_PANIC_SEEN.match(b)) and float(m.group(1)) < 10.0))


AA_PANIC_SEEN = re.compile(r"^AA PANIC -- seen ([\d.]+) metal")


def army_on_dead_ground(s: Seat):
    """11-27 (results/armynet/2026-11-27-step2-army-instrument.md): the army walks to an enemy base and stands there
    after the buildings are gone; nothing sends it on. Share of army unit snapshots from minute 5 standing still (under
    100 elmos since the last snapshot), not having fired for 10 s, within 500 elmos of where an enemy building died at
    least 30 s before."""
    if not s.army_snaps or not s.foe_bld_dead:
        return None
    dead = sorted(s.foe_bld_dead)
    last: dict[int, tuple[float, float]] = {}
    n = idle = 0
    for f in sorted(s.army_snaps):
        sites = [(x, z) for df, x, z in dead if df <= f - 900]
        for uid, x, z, fired in s.army_snaps[f]:
            prev = last.get(uid)
            last[uid] = (x, z)
            if f < 9000 or prev is None:
                continue
            n += 1
            if fired or (x - prev[0]) ** 2 + (z - prev[1]) ** 2 > 100 ** 2:
                continue
            if any((x - sx) ** 2 + (z - sz) ** 2 <= 500 ** 2 for sx, sz in sites):
                idle += 1
    return idle / n if n else None


def army_lost_outgunned(s: Seat):
    """11-27 (results/armynet/2026-11-27-odds-in-contact.md): the army goes into fights it is outgunned in and does
    not preserve itself. Share of our army metal lost (finished army units in the army snapshots) where, at the last
    snapshot of both sides before the death, our army metal within 1,000 elmos of the death was under 2/3 of theirs.
    Needs the other side's army snapshots (our AI on both sides); otherwise no reading."""
    snaps_f = [o for o in s.foes if o.army_snaps]
    if not s.army_snaps or not snaps_f or not s.mob_deaths:
        return None
    ours_f = sorted(s.army_snaps)
    lost = out = 0.0
    for f, x, z, cost, uid in s.mob_deaths:
        if uid not in s.army_def:
            continue
        i = bisect.bisect_right(ours_f, f) - 1
        if i < 0:
            continue

        def near(seat, fr):
            return sum(seat.cost.get(seat.army_def.get(u, ""), 0.0) for u, ux, uz, _ in seat.army_snaps[fr]
                       if (ux - x) ** 2 + (uz - z) ** 2 <= 1000 ** 2)
        ours = near(s, ours_f[i])
        theirs = 0.0
        for o in snaps_f:
            of = sorted(o.army_snaps)
            j = bisect.bisect_right(of, f) - 1
            if j >= 0:
                theirs += near(o, of[j])
        lost += cost
        if ours < theirs / 1.5:
            out += cost
    return out / lost if lost else None


def army_in_pieces(s: Seat):
    """11-27 (results/armynet/2026-11-27-fights-in-pieces.md): the army enters fights in pieces; the other side gathers
    first. A fight starts at an army snapshot where one of our army units has fired (in the last 10 s) with none of
    ours firing within 1,500 elmos of it at the snapshot before. Of our army metal within 600 of it then plus what
    came within 600 by the snapshot 60 s later, the share that came later (arrived after the fight began)."""
    if not s.army_snaps:
        return None
    fr = sorted(s.army_snaps)
    known = sorted(v for v in s.cost.values() if v > 0)
    dflt = known[len(known) // 2] if known else 100.0
    there = later = 0.0
    for i0, f in enumerate(fr):
        i1 = bisect.bisect_right(fr, f + 1800) - 1
        if i0 == 0 or i1 <= i0:
            continue
        prev = [(ux, uz) for _u, ux, uz, fired in s.army_snaps[fr[i0 - 1]] if fired]
        starts = []
        for _u, x, z, fired in s.army_snaps[f]:
            if fired and not any((x - px) ** 2 + (z - pz) ** 2 <= 1500 ** 2 for px, pz in prev + starts):
                starts.append((x, z))
        for x, z in starts:
            def near(fi):
                return {u: s.cost.get(s.army_def.get(u, ""), dflt) for u, ux, uz, _ in s.army_snaps[fr[fi]]
                        if (ux - x) ** 2 + (uz - z) ** 2 <= 600 ** 2}
            a0, a1 = near(i0), near(i1)
            there += sum(a0.values())
            later += sum(v for u, v in a1.items() if u not in a0)
    return later / (there + later) if there + later else None


def army_off_the_line(s: Seat):
    """11-27 (issues/army-off-axis-corner.md): part of the army parks in a far corner, off the line between the bases.
    Share of the army's snapshot metal from minute 5 standing more than 0.3 of the start-to-start distance away from
    the line through the two starts (the enemy start: the mean of the other side's commanders' first snapshots)."""
    starts = [o.start for o in s.foes if o.start is not None]
    if s.start is None or not starts or not s.army_snaps:
        return None
    ex, ez = sum(p[0] for p in starts) / len(starts), sum(p[1] for p in starts) / len(starts)
    ax, az = ex - s.start[0], ez - s.start[1]
    L = math.hypot(ax, az)
    if L < 1:
        return None
    known = sorted(v for v in s.cost.values() if v > 0)
    dflt = known[len(known) // 2] if known else 100.0
    tot = off = 0.0
    for f, units in s.army_snaps.items():
        if f < 9000:
            continue
        for u, x, z, _ in units:
            m = s.cost.get(s.army_def.get(u, ""), dflt)
            across = abs((x - s.start[0]) * az - (z - s.start[1]) * ax) / L   # distance from the line
            tot += m
            off += m if across > 0.3 * L else 0.0
    return off / tot if tot else None


def no_land_lab_minutes(s: Seat):
    """11-25, T1-only games: little land army late in the game. His 8 of 10 seats lost the land lab at minute 11-12 and bought only air plants after it. Minutes after the first
    land plant finished, while the seat stood, with none standing."""
    return _none_standing_minutes(s, LAND_PLANT)


def _none_standing_minutes(s: Seat, pat):
    ev = [(f, 1) for f, b in s.lines["latency "] if (m := LATENCY_DONE.match(b)) and pat.match(m.group(1))]
    ev += [(f, -1) for f, u in s.done_deaths if pat.match(u)]
    if not ev or not s.stats:
        return None
    ev.sort()
    first = next((f for f, d in ev if d > 0), None)
    if first is None:
        return None
    end = s.stats[-1]["frame"]
    decided = [f for f, _b in s.lines["decide t="]]
    if decided:
        end = min(end, max(decided))   # a dead seat keeps reporting stats; it stood while its builders decided
    n, at, bare = 0, first, 0
    for f, d in ev:
        if f < first or f > end:
            continue
        if n <= 0:
            bare += f - at
        n = max(0, n + d)
        at = f
    if n <= 0:
        bare += end - at
    return bare / 1800.0


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
STRUCT_DIED = re.compile(r"unit-destroyed (\w+) .*?frame=(\d+) .*?cost=([\d.]+) fwd=(-?[\d.]+) .*?built=1 mob=0")


def covered_loss_rate(s: Seat):
    """His 11-15 hosted 4v4: "our base is just dying to spam ... completely predictable", while the defence pricer read
    the stream as one arrival and held its target under what stood (t4: 0 of 63 tower bids won). Metal of our finished
    structures the ENEMY destroyed on our side of the map (forward fraction < 0.5), per minute the pricer read its
    defence as enough. 11-18: the per-game total counted our own reclaims and cancelled frames, and grew with the time
    spent covered (v0.5.17 85 covered minutes vs v0.5.16's 48 over rc17+rc19), so a bot that met its target more often
    read worse: 3.6k vs 1.8k a game, while per covered minute it lost 743 vs 1,011. None under 2 covered minutes."""
    if not s.lines["defmeasured-stat "]:
        return None
    events = sorted([(f, 0, b) for f, b in s.lines["defmeasured-stat "]] + [(f, 1, b) for f, b in s.lines["unit-destroyed "]])
    covered, last, cov_f, lost = False, None, 0, 0.0
    for f, kind, body in events:
        if kind == 0:
            m = DM_STAT.search(body)
            if m:
                if covered and last is not None:
                    cov_f += f - last
                last = f
                covered = float(m.group(2)) >= float(m.group(1)) > 0.0
        elif covered:
            m = STRUCT_DIED.search(body)
            if m and float(m.group(4)) < 0.5:
                u, fr = m.group(1), int(m.group(2))
                if any((fr + d, u) in s.foe_deaths for d in range(-5, 6)):
                    lost += float(m.group(3))
    return None if cov_f < 2 * 1800 else lost / (cov_f / 1800.0)


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
    ("base lost /covered min", covered_loss_rate, "median", 500.0, 0.0),   # "our base is just dying to spam"; v0.5.16 alone 120-728 by batch
    ("oldest plant order min", oldest_order_minutes, "mean", 1.0, None),  # n/a vs a release that cannot log it
    ("no t2 by minute 20", no_t2_by_20, "mean", 0.10, None),         # the T2 checks skip such seats
    ("frozen minutes", frozen_minutes, "mean", 1.0, 0.0),            # "we don't rebuild"
    ("com minutes on their half", com_their_half_minutes, "mean", 0.5, None),  # "the com got caught out in danger"
    ("com lost on their half", com_lost_their_half, "mean", 0.05, 0.0),
    ("mex lost to ticks by 10 min", mex_lost_to_ticks, "mean", 0.5, 0.0),  # one turret guards up to four extractors
    ("raider repeat kills /10min", raider_repeat_kills, "mean", 0.5, 0.0),  # "stop chasing after it" out of sight
    ("their mex killed /10min (neg)", their_mex_killed, "mean", 2.0, None),  # choke their economy, not only their base
    ("their army / ours, 8-12 min", outarmied, "mean", 0.25, None),     # react to an opponent who builds a lot of army
    ("lost per killed", trade_lost_per_killed, "median", 0.15, None),  # make them trade worse than us
    ("reclaimed / killed (neg)", reclaim_share, "median", 0.05, None),  # resbots eat the reclaim
    ("bare-hands minutes", bare_hands_minutes, "mean", 1.0, 0.0),    # "we don't really try to rebuild it"
    ("mex done by 3 min (neg)", mex_by_3_neg, "median", 0.5, None),  # "before it even has more than two mexes"
    ("AA panics on unarmed air", aa_panic_unarmed, "mean", 0.25, 0.0),  # "anti-air and radar before ... two mexes"
    ("army idle on dead enemy ground", army_on_dead_ground, "mean", 0.02, 0.0),  # stands where their base was
    ("army lost outgunned", army_lost_outgunned, "mean", 0.05, None),  # share of army metal lost in fights it was outgunned in
    ("army joins fights late", army_in_pieces, "mean", 0.05, None),  # share of a fight's army that came after it began
    ("army off the line", army_off_the_line, "mean", 0.05, None),  # share of army metal-time far off the line between the bases
    ("minutes without a land lab", no_land_lab_minutes, "mean", 1.0, 0.0),  # "we don't really make much land Army"
    ("minutes without a converter", no_converter_minutes, "mean", 1.0, 0.0),  # "no energy converters ... massive energy"
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


# A check fails only when it is worse than the release past its margin in this share of resampled batches (games
# drawn with replacement). Measured 11-17: on identical play (v0.5.15 vs v0.5.14, rv2-rv6) the point estimate failed
# ~2 of ~25 checks in every 20-40 game batch, a different two each time.
SURE = 0.9
RESAMPLES = 400


def worse_share(by_match, how, margin, rng):
    """by_match: [(our values, their values)] per game. Share of resamples where ours > theirs + margin."""
    n = len(by_match)
    hit = tot = 0
    for _ in range(RESAMPLES):
        pick = [by_match[rng.randrange(n)] for _ in range(n)]
        o = agg([v for ov, _t in pick for v in ov], how)
        t = agg([v for _o, tv in pick for v in tv], how)
        if o is None or t is None:
            continue
        tot += 1
        hit += o > t + margin
    return hit / tot if tot else 0.0


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
    rng = random.Random(1)
    matches = sorted({s.match for s in seats})
    for name, fn, how, margin, aim in CHECKS:
        ov = {id(s): fn(s) for s in ours}
        tv = {id(s): fn(s) for s in theirs}
        o = agg(list(ov.values()), how)
        t = agg(list(tv.values()), how)
        if o is None or t is None:
            rows.append((name, o, t, aim, "n/a"))
            continue
        worse = o > t + margin
        sure = 0.0
        if worse:
            by_match = [([ov[id(s)] for s in ours if s.match == m], [tv[id(s)] for s in theirs if s.match == m])
                        for m in matches]
            sure = worse_share(by_match, how, margin, rng)
        bad = worse and sure >= SURE
        fails += bad
        miss = (aim is not None) and (o > aim + 1e-9)
        short += miss
        v = ("FAIL (worse than release, %.0f%% of resamples)" % (100 * sure) if bad
             else "worse, within noise (%.0f%% of resamples)" % (100 * sure) if worse
             else ("ok, short of aim" if miss else "ok"))
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
        ahead += any(a.us in str(w) for w in win) if win else (mine > theirs_b)
    # A point test, not resampled like the checks above: the burden of proof is on the new code.
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
