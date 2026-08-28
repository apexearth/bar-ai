#!/usr/bin/env python3
"""Automated post-game audit: flag unwanted behavior from one match's logs.

Usage:
    python tools/audit.py <match-dir-or-infolog>

Reads the apex diagnostic lines a match already emits and prints findings in
three sections -- ECONOMY, MILITARY, EFFICIENCY -- each check as OK or FLAG
with the evidence inline. A FLAG is a lead, not a verdict: it names the log
line to read next. Checks and thresholds live in CHECKS at the bottom, one
function per behavior, so adding an audit is adding a function.
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

FRAMES_PER_MIN = 30 * 60


def load(path):
    p = Path(path)
    if p.is_dir():
        p = p / "infolog.txt"
    return p.read_text(errors="replace")


def minute_of(line):
    m = re.search(r"\[([\d.]+)m t\d+\]", line)
    return float(m.group(1)) if m else None


class Report:
    def __init__(self):
        self.rows = []

    def add(self, section, ok, name, detail):
        self.rows.append((section, ok, name, detail))

    def show(self):
        flags = 0
        for section in ("HEALTH", "PRIORITY", "STRUCTURES", "GEOMETRY",
                        "ECONOMY", "MILITARY", "EFFICIENCY", "VS-ENEMY",
                        "PERF"):
            rows = [r for r in self.rows if r[0] == section]
            if not rows:
                continue
            print(f"\n== {section} ==")
            for _, ok, name, detail in rows:
                tag = "  ok  " if ok else "  FLAG"
                if not ok:
                    flags += 1
                print(f"{tag}  {name:<28} {detail}")
        print(f"\n{flags} flag(s).")
        return flags


# ---------------------------------------------------------------- health --
def check_health(text, rep):
    errs = len(re.findall(r" : ERR ", text))
    rep.add("HEALTH", errs == 0, "angelscript-errors",
            f"{errs} compile errors" if errs else "clean")
    hangs = len(re.findall(r"Hang detection", text))
    rep.add("HEALTH", hangs == 0, "engine-hang", f"{hangs} watchdog firings"
            if hangs else "none")
    apex = len(re.findall(r"apex:", text))
    rep.add("HEALTH", apex > 100, "apex-alive",
            f"{apex} apex: lines" + ("" if apex > 100 else " -- near-stock?"))
    # duplicate death re-reports (the ghost bug); should be zero post-fix
    ids = re.findall(r"unit-destroyed \S+ id=(\d+)", text)
    dup = sum(1 for _, n in
              __import__("collections").Counter(ids).items() if n > 1)
    rep.add("HEALTH", dup == 0, "ghost-deaths",
            f"{dup} unit ids re-reported" if dup else "each death once")


# --------------------------------------------------------------- economy --
def check_economy(text, rep):
    # THE FIRST FACTORY, per player. The opening gate has wedged before
    # (Supreme Isthmus 8v8: four of eight players never fielded a lab while
    # cons roamed claiming mexes) -- this check catches the whole class,
    # whatever the mechanism: any apex team whose first lab is late or absent.
    teams = set(re.findall(r"m (t\d+)\] apex", text))
    first_lab = {}
    for m in re.finditer(r"\[([\d.]+)m (t\d+)\] apex: T1 lab on field", text):
        t = m.group(2)
        if t not in first_lab:
            first_lab[t] = float(m.group(1))
    missing = sorted(teams - set(first_lab))
    late = sorted(t for t, mn in first_lab.items() if mn > 4.0)
    ok = not missing and not late
    detail = "all players fielded a lab promptly"
    if missing:
        detail = f"NO FACTORY EVER: {', '.join(missing)}"
    elif late:
        detail = "first lab past 4min: " + ", ".join(
            f"{t}@{first_lab[t]:.1f}m" for t in late)
    rep.add("ECONOMY", ok, "first-factory", detail)
    # first fusion ask, per team. Two spellings: the market election
    # (`decide ... energy/energy:corfus`) is the live one; the old EcoFusion
    # `eco fusion <name> standing=` line is kept for pre-market infologs --
    # matching only the dead spelling read every 2026-08-28 game as "never"
    # while corfus/corafus elections were in the same log.
    asks = [(minute_of(l), l) for l in
            re.findall(r".*eco fusion \w+ standing=.*", text)]
    # decide lines have no [Nm tN] prefix; their minute comes off the
    # engine frame stamp.
    asks += [(int(fm.group(1)) / FRAMES_PER_MIN, l) for l in
             re.findall(r".*apex: decide .*-> energy/energy:"
                        r"(?:cor|arm|leg)\w*fus\w* .*", text)
             for fm in [re.search(r"\[f=(\d+)\]", l)] if fm]
    if asks:
        first = min(m for m, _ in asks if m is not None)
        rep.add("ECONOMY", first <= 18, "first-fusion-ask",
                f"{first:.1f} min" + ("" if first <= 18 else " (late)"))
    else:
        diag = re.findall(r"fusion-gate diag.*", text)
        rep.add("ECONOMY", False, "first-fusion-ask",
                "never" + (f"; last gate: {diag[-1][-90:]}" if diag else ""))
    # metal-full time: factory-diag prints isMetalFull per sample
    full = re.findall(r"factory-diag \S+ mInc=[\d.]+ mCur=\d+ mStor=\d+"
                      r" isMetalFull=(\d)", text)
    if full:
        share = sum(int(f) for f in full) / len(full)
        rep.add("ECONOMY", share < 0.25, "metal-full-time",
                f"{share:.0%} of samples at cap"
                + ("" if share < 0.25 else " -- wasted income"))
    # wasted resources: dev_team_income.lua accumulates the engine's
    # resPrevExcess (overflow thrown away after storage+sharing) and echoes
    # cumulative [BARAI_WASTE] lines. Last line per team is the game total.
    wl = {}
    for m in re.finditer(r"\[BARAI_WASTE\] frame=\d+ team=(\d+)"
                         r" mWaste=(\d+) mMade=(\d+) eWaste=(\d+) eMade=(\d+)",
                         text):
        wl[m.group(1)] = tuple(int(x) for x in m.groups()[1:])
    ours = {t[1:] for t in teams}   # "t3" -> "3"
    rows = [v for k, v in wl.items() if k in ours]
    if rows:
        mW = sum(r[0] for r in rows); mI = sum(r[1] for r in rows)
        eW = sum(r[2] for r in rows); eI = sum(r[3] for r in rows)
        ms = mW / mI if mI else 0.0
        es = eW / eI if eI else 0.0
        rep.add("ECONOMY", ms < 0.10, "metal-wasted",
                f"{mW:,} of {mI:,} overflowed ({ms:.0%})"
                + ("" if ms < 0.10 else " -- income buying nothing"))
        rep.add("ECONOMY", es < 0.30, "energy-wasted",
                f"{eW:,} of {eI:,} overflowed ({es:.0%})"
                + ("" if es < 0.30 else " -- feed converters or stop building E"))
    # plant discipline: approvals vs refusals; multiple same-tier approvals
    appr = re.findall(r"plant approved (\S+) have=(\d+)/(\d+) t1=(\d+)"
                      r" t2=(\d+)", text)
    # air plants past the totals are the air STRATEGY's sanctioned exemption.
    # Compare each approval against ITS OWN tier only: the t1/t2 counters are
    # printed post-approval and a T2 plant is not subject to the T1 total (a
    # coralab at t1=3 flagged here was a false positive).
    air = {"armap", "corap", "legap", "armaap", "coraap", "legaap"}
    t2names = {"armalab", "armavp", "coralab", "coravp", "legalab", "legavp"}
    over = []
    for a in appr:
        if a[0] in air:
            continue
        tier_count = int(a[4]) if a[0] in t2names else int(a[3])
        if tier_count > 2:
            over.append(a)
    rep.add("ECONOMY", len(over) == 0, "plant-gate",
            f"{len(appr)} approvals, {len(over)} past tier totals"
            + (f" e.g. {over[0]}" if over else ""))
    # obsolete junk pileup: last junk reading
    junk = re.findall(r"obsolete junk standing=(\d+)", text)
    if junk:
        last = int(junk[-1])
        rep.add("ECONOMY", last <= 12, "obsolete-junk",
                f"{last} T1 structures standing at last sample")


# -------------------------------------------------------------- military --
def check_military(text, rep):
    # death attribution: retreat share and no-task share of lost metal
    frames = [int(f) for f in re.findall(r" frame=(\d+)", text)]
    cutoff = (max(frames) - 90 * 30) if frames else 0
    metal = defaultdict(float)
    seen = set()
    for m in re.finditer(
            r"m t(\d+)\].*unit-destroyed \S+ id=(\d+) frame=(\d+)"
            r" at=\S+ curTask=t(-?\d+)b(-?\d+)f(-?\d+) cost=(\d+)"
            r" fwd=\S+(?: built=(\d))?(?: mob=(\d))?", text):
        key = (m.group(1), m.group(2))
        if key in seen or int(m.group(3)) >= cutoff:
            continue
        seen.add(key)
        if m.group(8) == "0":
            metal["under-construction"] += float(m.group(7))
            continue
        if m.group(9) == "0":
            metal["structure"] += float(m.group(7))
            continue
        tt = int(m.group(4))
        lab = {4: "retreat", 0: "nil", 7: "fight", 5: "build",
               2: "idle", 3: "wait"}.get(tt, str(tt))
        metal[lab] += float(m.group(7))
    total = sum(metal.values())
    if total > 0:
        r = metal.get("retreat", 0) / total
        n = metal.get("nil", 0) / total
        rep.add("MILITARY", r < 0.25, "retreat-bleed",
                f"{r:.0%} of lost metal died retreating")
        rep.add("MILITARY", n < 0.25, "taskless-deaths",
                f"{n:.0%} of lost metal was mobile units holding no task")
        s = metal.get("structure", 0) / total
        rep.add("MILITARY", s < 0.35, "base-attrition",
                f"{s:.0%} of lost metal was standing structures"
                + ("" if s < 0.35 else " -- the base is being eaten"))
    else:
        rep.add("MILITARY", True, "death-attribution", "no death data")
    # engage decisions: share of TAKEs at hopeless odds, and skip volume.
    # home=1 fights (defending our own ground) are odds-waived on purpose and
    # counted separately -- only AWAY fights at bad odds are the finding.
    away, home = [], []
    for m in re.finditer(r"engage TAKE .* edge=([\d.]+).*?(?: home=(\d))?$",
                         text, re.M):
        (home if m.group(2) == "1" else away).append(float(m.group(1)))
    if away:
        hopeless = sum(1 for e in away if 0 < e < 0.5) / len(away)
        rep.add("MILITARY", hopeless < 0.3, "hopeless-attacks",
                f"{hopeless:.0%} of away-TAKEs at edge<0.5 "
                f"({len(away)} away, {len(home)} home-defence)")
    skips = [int(s) for s in re.findall(r"skipped=(\d+)", text)]
    if skips:
        rep.add("MILITARY", max(skips) < 30, "target-skipping",
                f"max {max(skips)} groups skipped in one pass"
                + ("" if max(skips) < 30 else " -- squads refusing and"
                   " wandering"))
    # air target fixation: `apex: bomb-commit id= def= last=` logs FRESH
    # commits only (a task re-electing its own target does not log), so
    # many commits funneling into few ids is real fixation, the thing the
    # revisit discount exists to stop ("our air tends to repeatedly try
    # bombing the same thing").
    bombs = re.findall(r"apex: bomb-commit id=(\d+)", text)
    if len(bombs) >= 8:
        counts = defaultdict(int)
        for b in bombs:
            counts[b] += 1
        top = max(counts.values())
        ratio = len(bombs) / len(counts)
        rep.add("MILITARY", (ratio <= 4.0) and (top <= max(6, len(bombs) // 3)),
                "air-target-fixation",
                f"{len(bombs)} commits over {len(counts)} targets"
                f" (max one target {top}x)")
    # near-miss refusals: bestRef close to 1.0 means one merge or a small
    # margin change would have taken the target; low means hopeless anyway.
    refs = [float(r) for r in re.findall(r"bestRef=([\d.]+)", text)
            if float(r) > 0]
    if refs:
        near = sum(1 for r in refs if r >= 0.7) / len(refs)
        rep.add("MILITARY", True, "refusal-nearness",
                f"{near:.0%} of refusal passes had a best-refused >= 0.7 "
                f"({len(refs)} passes, median "
                f"{sorted(refs)[len(refs)//2]:.2f})")
    # massing: want vs actual army ratio at last samples
    mass = re.findall(r"mass want=(\d+) floor=(\d+) army=(\d+)"
                      r" enemyArmy=(\d+)", text)
    if mass:
        w, f, a, e = mass[-1]
        rep.add("MILITARY", True, "mass-state",
                f"want={w} floor={f} army={a} vs enemy={e} (last)")


# ------------------------------------------------------------ efficiency --
def check_efficiency(text, rep):
    # build-and-reclaim conflict: a def REQUESTED after its own kind was
    # already being reclaimed. Building early and eating late (successor
    # arrived) is the ladder working; only build-after-first-reclaim is a
    # conflict.
    # keyed per (team, def): reclaim eligibility is per PLAYER (successor
    # standing), so t0 eating what t1 still builds is not a conflict.
    first_eat = {}
    for line in text.splitlines():
        m = re.search(r"m (t\d+)\].*obsolete-reclaim (\S+) ", line)
        if m and (m.group(1), m.group(2)) not in first_eat:
            mm = re.search(r"\[([\d.]+)m", line)
            first_eat[(m.group(1), m.group(2))] = float(mm.group(1))
    both = set()
    for line in text.splitlines():
        m = re.search(r"\[([\d.]+)m (t\d+)\].*request (?:new|join\S*) (\S+)",
                      line)
        if m and float(m.group(1)) > first_eat.get(
                (m.group(2), m.group(3)), 1e9):
            both.add(f"{m.group(3)}({m.group(2)})")
    both = sorted(both)
    rep.add("EFFICIENCY", len(both) == 0, "build-eat-conflict",
            "none" if not both
            else f"requested AFTER reclaim began: {', '.join(both)}")
    # quota starvation: defs wanted but never held (from last quota line/line)
    starved = []
    for line in re.findall(r"facqueue \S+ #\d+ .*quota: (.*)", text)[-8:]:
        for d, have, want in re.findall(r"(\w+)=(\d+)/(\d+)", line):
            if int(want) >= 5 and int(have) == 0:
                starved.append(d)
    starved = sorted(set(starved))
    rep.add("EFFICIENCY", len(starved) == 0, "quota-starvation",
            "none" if not starved
            else f"want>=5 held 0 late: {', '.join(starved)}")
    # LATE-GAME FRONT INVESTMENT: fortresses ordered and idle-at-full-metal
    # factory samples -- apexearth's two standing complaints, as numbers.
    forts = re.findall(r"front fortress \S+ standing=(\d+) want=(\d+)", text)
    peak_inc = max([float(x) for x in
                    re.findall(r"fusion-gate diag .*?income=([\d.]+)", text)]
                   or [0])
    if peak_inc >= 100:
        rep.add("EFFICIENCY", len(forts) > 0, "front-fortress",
                f"{len(forts)} orders at peak income {peak_inc:.0f}"
                + ("" if forts else " -- NONE despite T3-scale economy"))
    idlefull = len(re.findall(
        r"factory-diag \S+ mInc=[\d.]+ mCur=\d+ mStor=\d+ isMetalFull=1"
        r" hasTask=\d+ calls=\d+ queue=0 unstarted=0", text))
    rep.add("EFFICIENCY", idlefull < 5, "idle-at-full-metal",
            f"{idlefull} factory samples idle at the metal cap")
    # blocked capability bugs: rules handing defs to units that cannot build
    bugs = len(re.findall(r"apex: BUG blocked", text))
    rep.add("EFFICIENCY", bugs == 0, "capability-blocks",
            f"{bugs} blocked-task events" if bugs else "none")
    # front defence aim: orders placed vs seen standing
    aimed = re.findall(r"brain orders front defence #(\d+)", text)
    if aimed:
        rep.add("EFFICIENCY", True, "front-defence-orders",
                f"{aimed[-1]} total orders")


def check_vs_enemy(text, rep):
    """Structural asymmetries vs the enemy, from the both-team telemetry.

    apexearth 2026-08-20: "This should be in some sort of audit check...
    looking for generic issues in any of our game matches... Enemy T2 lab had
    12 nanos supporting it. I don't think we had any." These checks compare
    the two sides on the same footing, which no single-side check can."""
    import math
    # Which team is apex: BARAI lines carry team ids; apex's own log lines
    # carry "t<local>" but the BARAI_* gadget lines are global. The apex team
    # is the one whose infolog carries "Skirmish AI <Apex" lines -- take its
    # id from the first "[<m>m t<N>]" apex line paired with BARAI_START order.
    m = re.search(r"Skirmish AI <Apex[^>]*>: \[[\d.]+m t(\d+)\]", text)
    my = int(m.group(1)) if m else 0
    foe = 1 - my

    # NANOS PER FACTORY, both sides, from the last BARAI_POS building snapshot
    # per team (name:x:z:xsize:zsize). Factories and nanos by def-name pattern.
    pos = {}
    for tm, n, data in re.findall(r"\[BARAI_POS\] team=(\d+) ally=\d+ frame=\d+ n=(\d+) (\S+)", text):
        pos[int(tm)] = data  # keep last
    FACS = ("alab", "avp", "aap", "lab", "vp", "ap", "hp", "sy", "gant", "shltx")
    def nano_density(team):
        if team not in pos:
            return None
        facs, nanos = [], []
        for tok in pos[team].split(","):
            parts = tok.split(":")
            if len(parts) < 3:
                continue
            name, x, z = parts[0], float(parts[1]), float(parts[2])
            if "nanotc" in name:
                nanos.append((x, z))
            elif any(name.endswith(f) for f in FACS) and not name.endswith("solar"):
                facs.append((x, z))
        if not facs:
            return None
        best = 0
        for fx, fz in facs:
            n = sum(1 for nx, nz in nanos if (nx-fx)**2 + (nz-fz)**2 <= 400**2)
            best = max(best, n)
        return best, len(nanos), len(facs)
    mine, theirs = nano_density(my), nano_density(foe)
    if mine and theirs:
        ok = mine[0] * 2 >= theirs[0]  # within 2x of their best-supported lab
        rep.add("VS-ENEMY", ok, "nanos-at-best-factory",
                f"ours {mine[0]} (of {mine[1]} total) vs theirs {theirs[0]} (of {theirs[1]})")

    # RAIDS EXIST: census f4 field entries ever nonzero
    census = len(re.findall(r"army-census", text))
    f4 = re.findall(r"army-census.*?f4=(\d+)h/(\d+)f", text)
    raided = any(int(x)+int(y) > 0 for x, y in f4)
    # The census omits zero buckets, so NO f4 field across a real game IS the
    # zero-raids case, not missing data.
    rep.add("VS-ENEMY", raided or census < 10, "raids-exist",
            "f4 tasks seen" if raided else "zero raid tasks all game")

    # CON ATTRITION, both sides, from BARAI_DEATH (mobile builders ~ c[kav]/ca)
    def con_deaths(team):
        return len(re.findall(r"\[BARAI_DEATH\] frame=\d+ team=%d unit=(?:arm|cor|leg)(?:ck|cv|ca|ack|acv|aca) " % team, text))
    cd_my, cd_foe = con_deaths(my), con_deaths(foe)
    rep.add("VS-ENEMY", cd_my <= cd_foe + 5, "constructor-attrition",
            f"ours {cd_my} vs theirs {cd_foe}")

    # ENERGY RACE at ~10 minutes -- apexearth, watching Prismatic 2026-08-20:
    # "By 10m in on prismatic we have less than half the energy the other
    # team has." Flag when our cumulative energyProduced is under 60% of
    # theirs at the sample nearest 10m.
    eras = {}
    for tm, fr, ep in re.findall(
            r"\[BARAI_STATS\] team=(\d+).*?frame=(\d+).*?energyProduced=([\d.]+)", text):
        t, f, e = int(tm), int(fr), float(ep)
        if abs(f - 18000) < 1800:
            eras[t] = e
    if my in eras and foe in eras and eras[foe] > 0:
        frac = eras[my] / eras[foe]
        rep.add("VS-ENEMY", frac >= 0.6, "energy-race-10m",
                f"ours {eras[my]:.0f} vs theirs {eras[foe]:.0f} ({frac:.0%})")

    # MEX RACE at last paired sample
    mex = re.findall(r"\[BARAI_STATS\] team=(\d+).*? mex=(\d+)", text)
    last = {}
    for tm, v in mex:
        last[int(tm)] = int(v)
    if my in last and foe in last:
        rep.add("VS-ENEMY", last[my] * 1.5 >= last[foe], "mex-race",
                f"ours {last[my]} vs theirs {last[foe]}")


# --------------------------------------------------------------- priority --
# apexearth, 2026-08-27: "Our audit script should check and fail if the
# priority for our advanced cons isn't upgrading mexes before the other things.
# Mex upgrade is the right choice."
#
# WHICH cons those are comes from the AI, not from a def name: `apex: upcons`
# lists every builder whose build options contain a better-than-basic
# extractor, read off the build graph at init. A naming guess would be wrong on
# one of the three factions and silently wrong on a unit BAR adds later.
UPCONS_RE = re.compile(r"apex: upcons ([a-z0-9,]+)")
DECIDE_RE = re.compile(
    r"apex: decide t=\d+ ([a-z0-9]+) #\d+ -> ([a-z]+)/([a-z]+)"
    r"(?:[^|]*? over ([a-z]+)/([a-z]+))?")


def check_priority(text, rep):
    cons = set()
    for m in UPCONS_RE.finditer(text):
        cons.update(m.group(1).split(","))
    if not cons:
        rep.add("PRIORITY", True, "upgrade-capable cons",
                "no `apex: upcons` line -- nothing that can upgrade a mex "
                "existed, or the variant predates the census")
        return

    picks = defaultdict(int)
    # docs/18-brain.md: the arbiter's ranking IS a log line, so the useful
    # assertion is "a moho was available and something beat it" rather than
    # inferring starvation from outcomes three layers downstream.
    beat = defaultdict(int)
    total = 0
    for m in DECIDE_RE.finditer(text):
        if m.group(1) not in cons:
            continue
        won = f"{m.group(2)}/{m.group(3)}"
        picks[won] += 1
        total += 1
        if m.group(4) and f"{m.group(4)}/{m.group(5)}" == "metal/mexup":
            beat[won] += 1
    if not total:
        rep.add("PRIORITY", True, "advanced con elections",
                f"cons {sorted(cons)} never elected -- none was ever built")
        return

    up = picks.get("metal/mexup", 0)
    ranked = sorted(picks.items(), key=lambda kv: -kv[1])
    top, topN = ranked[0]
    share = 100.0 * up / total
    detail = (f"{up}/{total} ({share:.0f}%) of advanced-con decisions were "
              f"metal/mexup; most-chosen was {top} ({topN}). "
              + " ".join(f"{k}={v}" for k, v in ranked[:5]))
    # His rule, stated as he stated it: the upgrade should be what these cons
    # do FIRST. Anything else winning more of their elections is the flag.
    # A DECISION SHARE IS NOT AN OUTCOME, and this check can be gamed by one:
    # measured 2026-08-27, raising apex_mexup_boost to 2.79 took this from 7%
    # to 33% and turned the flag green, while the upgrades actually STANDING
    # fell 94 -> 69 and metal built fell 863k -> 358k. Read it with t2Mex from
    # result.json, never on its own.
    rep.add("PRIORITY", top == "metal/mexup", "advanced cons upgrade mexes",
            detail + " -- decision share, NOT upgrades standing; check t2Mex")

    lost = sum(beat.values())
    if lost:
        who = sorted(beat.items(), key=lambda kv: -kv[1])[:4]
        rep.add("PRIORITY", False, "a moho was available and lost",
                f"{lost}x an advanced con ranked metal/mexup second and built "
                "something else: "
                + " ".join(f"{k}={v}" for k, v in who))
    else:
        rep.add("PRIORITY", True, "a moho was available and lost",
                "never -- mexup was not the runner-up in any advanced-con "
                "election")


# ------------------------------------------------------------- structures --
# The 2026-08-27 complaint list, each as an assertion over what actually got
# BUILT ([BARAI_BUILD] events carry def and cost) rather than over decides.
BUILD_RE = re.compile(
    r"\[BARAI_BUILD\] team=(\d+) ally=\d+ frame=(\d+) min=([\d.]+) "
    r"unit=(\S+) cost=(\d+)")
EXEC_RE = re.compile(
    r"apex: exec t=(\d+) (\S+) #\d+ ([a-z]+):(\S+) pick=(\d+)")
PLANT_DEFS = {
    "armlab", "armvp", "armap", "armhp", "armfhp", "armsy", "armplat",
    "armalab", "armavp", "armaap", "armasy", "armshltx", "armshltxuw",
    "corlab", "corvp", "corap", "corhp", "corfhp", "corsy", "corplat",
    "coralab", "coravp", "coraap", "corasy", "corgant", "corgantuw",
    "leglab", "legvp", "legap", "leghp", "legfhp", "legsy",
    "legalab", "legavp", "legaap", "leggant",
}
T1_DEF_TOWERS = {
    "armllt", "armbeamer", "armhlt", "armguard", "armrl", "armdl",
    "corllt", "corhllt", "corhlt", "corpun", "correfrac", "corrl",
    "legllt", "legmg", "leglht", "legdtf", "legdtl", "legrl",
}


def check_structures(text, rep):
    ours = set(re.findall(r"apex: decide t=(\d+) ", text))
    if not ours:
        return
    builds = [m for m in BUILD_RE.finditer(text) if m.group(1) in ours]
    if not builds:
        rep.add("STRUCTURES", True, "structure telemetry",
                "no [BARAI_BUILD] events -- gadget absent, checks skipped")
        return
    last_min = max(float(m.group(3)) for m in builds)

    # "Stop making storage." (apexearth 2026-08-27) -- zero is the target.
    stor = [m for m in builds
            if any(k in m.group(4)
                   for k in ("stor", "uwms", "uwes", "uwadvms", "uwadves"))]
    stor_m = sum(int(m.group(5)) for m in stor)
    rep.add("STRUCTURES", not stor, "no-storage",
            f"{len(stor)} storage(s) built, {stor_m} metal"
            + ("" if not stor else " -- ProposeStore should be dead"))

    # "We reclaim our T2 labs and then rebuild them." A successful reclaim
    # exec on a def followed by a NEW build of the same def is the loop
    # itself, whatever the def.
    recl_n = sum(1 for m in EXEC_RE.finditer(text)
                 if m.group(1) in ours and m.group(3) == "reclaim")
    # order-scan: walk the file once, tracking last reclaim exec per def
    loops = defaultdict(int)
    last_recl = {}
    for m in re.finditer(
            r"apex: exec t=(\d+) \S+ #\d+ reclaim:(\S+) pick=\d+"
            r"|\[BARAI_BUILD\] team=(\d+) ally=\d+ frame=\d+ min=[\d.]+ "
            r"unit=(\S+) cost=\d+", text):
        if m.group(1) is not None:
            if m.group(1) in ours:
                last_recl[m.group(2)] = True
        elif m.group(3) in ours:
            d = m.group(4)
            if last_recl.pop(d, False):
                loops[d] += 1
    if recl_n or loops:
        worst = sorted(loops.items(), key=lambda kv: -kv[1])[:4]
        rep.add("STRUCTURES", not loops, "reclaim-rebuild loop",
                (f"{sum(loops.values())} rebuild(s) after our own reclaim: "
                 + " ".join(f"{k}={v}" for k, v in worst)) if loops
                else f"{recl_n} reclaim exec(s), none followed by a "
                     "same-def rebuild")

    # "We still make multiple of the same type of T2 lab." Count per plant
    # def; two of one def can be a rebuilt loss, so the bar is three.
    per_def = defaultdict(int)
    per_def_m = defaultdict(int)
    for m in builds:
        per_def[m.group(4)] += 1
        per_def_m[m.group(4)] += int(m.group(5))
    dup_plants = {d: n for d, n in per_def.items()
                  if d in PLANT_DEFS and n >= 3 and per_def_m[d] >= 4000}
    plants_m = sum(v for d, v in per_def_m.items() if d in PLANT_DEFS)
    rep.add("STRUCTURES", not dup_plants, "plant-count",
            (f"{plants_m} metal into plants; "
             + (" ".join(f"{d}x{n}" for d, n in
                         sorted(dup_plants.items(), key=lambda kv: -kv[1]))
                if dup_plants else "no def built 3+ times")))

    # "Not enough nanos around factories." Standing at end vs plants standing.
    dead = defaultdict(int)
    for m in re.finditer(r"apex: unit-destroyed (\S+) ", text):
        dead[m.group(1)] += 1
    nanos_up = sum(n for d, n in per_def.items() if "nanotc" in d) \
        - sum(n for d, n in dead.items() if "nanotc" in d)
    plants_up = sum(n for d, n in per_def.items() if d in PLANT_DEFS) \
        - sum(n for d, n in dead.items() if d in PLANT_DEFS)
    if last_min >= 12 and plants_up > 0:
        rep.add("STRUCTURES", nanos_up * 2 >= plants_up, "nanos-standing",
                f"{nanos_up} nano(s) standing vs {plants_up} plant(s) at "
                f"{last_min:.0f}m (want >= 1 per 2 plants)")

    # "Some factories are very slow to receive nano turret support"
    # (apexearth 2026-08-27): minutes from each plant finishing to the next
    # nano finishing on the same team. Needs the widened gadget (nanos were
    # invisible to BARAI_BUILD before 2026-08-27).
    lat = []
    for t in ours:
        seq = [(float(m.group(3)), m.group(4)) for m in builds
               if m.group(1) == t]
        for i, (mn, d) in enumerate(seq):
            if d not in PLANT_DEFS:
                continue
            nxt = next((m2 for m2, d2 in seq[i:] if "nanotc" in d2), None)
            if nxt is not None:
                lat.append(nxt - mn)
    if lat:
        lat.sort()
        med = lat[len(lat) // 2]
        rep.add("STRUCTURES", med <= 4.0, "nano-latency",
                f"median {med:.1f}m from plant finished to next nano "
                f"finished ({len(lat)} plants measured)")

    # "Some players still have T1 energy and converters despite having AFUS"
    # (apexearth 2026-08-27): T1 generators standing late while an AFUS
    # stands. built - destroyed is standing; needs per-team destroyed, which
    # unit-destroyed lines do not carry, so this is team-pooled.
    t1eco = {"armwin", "armsolar", "armmakr", "corwin", "corsolar", "cormakr",
             "legwin", "legsolar", "legmakr"}
    afus = {"armafus", "corafus", "legafus", "armuwadves", "coruwadves"}
    if any(m.group(4) in afus for m in builds):
        t1_up = sum(1 for m in builds if m.group(4) in t1eco) \
            - sum(n for d, n in dead.items() if d in t1eco)
        rep.add("STRUCTURES", t1_up <= 10 * len(ours), "t1-eco-with-afus",
                f"~{t1_up} T1 generators/converters standing with AFUS "
                f"fielded ({len(ours)} team(s); reclaim should be clearing "
                "these)")

    # Radar churn: executions against radars actually finished.
    sense_exec = sum(1 for m in EXEC_RE.finditer(text)
                     if m.group(1) in ours and m.group(3) == "sense")
    radars = sum(n for d, n in per_def.items() if "rad" in d and "radl" not in d)
    if sense_exec >= 20:
        rep.add("STRUCTURES", sense_exec <= max(1, radars) * 8, "sense-churn",
                f"{sense_exec} sense executions for {radars} radar(s) built")

    # Gauntlet-class towers after an advanced con exists: T1 towers should
    # stop dominating defence metal once a T2 hand can answer the want.
    adv_cons = any(
        m.group(1) in ours and m.group(2) in (
            "armack", "armacv", "armaca", "corack", "coracv", "coraca",
            "legack", "legacv", "legaca")
        for m in EXEC_RE.finditer(text))
    if adv_cons:
        t1m = sum(int(m.group(5)) for m in builds
                  if m.group(4) in T1_DEF_TOWERS)
        # T2+ defence metal, by the known heavy set.
        heavy = {"armanni", "armamb", "armpb", "armgate", "armbrtha",
                 "cordoom", "cortoast", "corvipe", "corbhmth", "corint",
                 "legbastion", "leglupara", "legrampart"}
        t2m = sum(int(m.group(5)) for m in builds if m.group(4) in heavy)
        if t1m + t2m >= 2000:
            share = 100.0 * t1m / (t1m + t2m)
            rep.add("STRUCTURES", share <= 60.0, "defence-tier",
                    f"T1-tower share of defence metal {share:.0f}% "
                    f"({t1m} vs heavy {t2m}) with advanced cons fielded")


# ------------------------------------------------------------------ geometry --
FRONTLINE_RE = re.compile(
    r"apex: frontline perim=(\d+) front=(\d+) back=(\d+).*R=(\d+) band=(\d+)")


def check_geometry(text, rep):
    rows = FRONTLINE_RE.findall(text)
    if rows:
        fr_share = sorted(int(f) / max(1, int(f) + int(b))
                          for _, f, b, _, _ in rows)
        band_r = sorted(int(bd) / max(1, int(r)) for _, _, _, r, bd in rows)
        med_share = fr_share[len(fr_share) // 2]
        med_band = band_r[len(band_r) // 2]
        rep.add("GEOMETRY", med_band < 0.99 and med_share <= 0.55,
                "front-band",
                f"median front share {med_share:.2f} of perimeter, "
                f"band/R {med_band:.2f} -- band/R ~1.0 means the near-enemy "
                "trim is inert and the 'front' wraps the base")
    m = None
    for m in re.finditer(
            r"apex: fronttowers built=(\d+) lost=\d+ standing=(-?\d+) "
            r"m=\d+ .*wonFront=(\d+)", text):
        pass
    if m:
        built, standing, won = int(m.group(1)), int(m.group(2)), int(m.group(3))
        rep.add("GEOMETRY", not (won >= 10 and standing <= 0),
                "front-towers",
                f"front sites won {won}x, {built} built, {standing} standing")
    tiles = re.findall(r"apex: tiling flush=\d+ apart=\d+ cluster=\d+ "
                       r"of (\d+) \((\d+)% touching\)", text)
    if tiles:
        n, pct = tiles[-1]
        rep.add("GEOMETRY", int(pct) >= 60 or int(n) < 20, "grid-tightness",
                f"{pct}% of {n} eco structures touching a neighbor at game "
                "end (grid target: tight rows)")


# ---------------------------------------------------------------- performance --
PERF_RE = re.compile(
    r"apex: perf sec (\S+) calls=(\d+) totalMs=([\d.]+) maxMs=([\d.]+)")


def check_perf(text, rep):
    tot = defaultdict(float)
    mx = defaultdict(float)
    for m in PERF_RE.finditer(text):
        tot[m.group(1)] += float(m.group(3))
        if float(m.group(4)) > mx[m.group(1)]:
            mx[m.group(1)] = float(m.group(4))
    if not tot:
        return
    worst_tot = sorted(tot.items(), key=lambda kv: -kv[1])[:3]
    worst_max = sorted(mx.items(), key=lambda kv: -kv[1])[:3]
    spike = worst_max[0]
    heavy = worst_tot[0]
    # A 30ms single call is a visible hitch at watch speed; a section
    # burning >60s of one game is the slow-1v1 complaint.
    rep.add("PERF", spike[1] <= 30.0 and heavy[1] <= 60000.0, "ai-time",
            f"max single call {spike[1]:.0f}ms ({spike[0]}); busiest "
            + " ".join(f"{k}={v/1000:.0f}s" for k, v in worst_tot))


def check_commitments(text, rep):
    """The duplicate-plant and abandoned-frame laws. Own function so the
    income gates in check_priority can never silently skip them (they used to
    sit below two early returns -- a low-income game reported green by never
    running the checks that mattered)."""
    # apexearth 2026-08-27: a copy of an owned plant prices ZERO and forwards
    # its demand to the nano. A copy still PRICED is the sanctioned residue
    # (no-nano escape, or orphan-only kin being finished); a copy priced
    # UNDISCOUNTED (dupKin>0, subst=1.0) is the violation -- note the no-nano
    # escape logs subst=1.000 legitimately on maps/factions without a nano
    # def, which no current 1v1 map is.
    fwd = re.findall(r"apex: plantdup ([a-z0-9]+) kin=\d+ copy=1 dupGain=0",
                     text)
    dups = re.findall(
        r"apex: plantdup ([a-z0-9]+) kin=(\d+) dupKin=(\d+) unlocks=\d+ "
        r"liveOther=\d+ subst=([\d.]+) lineNeed=([\d.]+)", text)
    naked = [d for d in dups if int(d[2]) > 0 and float(d[3]) >= 1.0]
    detail = (f"{len(fwd)} copy want(s) zeroed -> nano; "
              f"{len(dups)} discounted dup price(s)")
    if naked:
        worst = sorted(naked, key=lambda d: -int(d[1]))[0]
        detail += (f"; {len(naked)} UNdiscounted copy price(s), worst "
                   f"kin={worst[1]} {worst[0]}")
    rep.add("PRIORITY", not naked, "duplicate line over nanos", detail)

    # apexearth 2026-08-27: "when we e-stall we think to do something else...
    # instead of choosing to finish the original lab afterwards we just start
    # making a new one." A frame abandoned once is an interrupted job; the SAME
    # def abandoned repeatedly means nothing is adopting it before founding.
    orph = defaultdict(int)
    for m in re.finditer(r"apex: frame-orphan ([a-z0-9]+) ", text):
        orph[m.group(1)] += 1
    repeat = {k: v for k, v in orph.items() if v > 1}
    if orph:
        top = sorted(orph.items(), key=lambda kv: -kv[1])[:5]
        rep.add("PRIORITY", not repeat, "finish before founding",
                f"{sum(orph.values())} nanoframes abandoned, "
                f"{len(repeat)} def(s) abandoned more than once: "
                + " ".join(f"{k}={v}" for k, v in top))
    else:
        rep.add("PRIORITY", True, "finish before founding",
                "no abandoned nanoframes")


def check_ledger(text, rep):
    """The commitment ledger holds truth: drift means a missed event, an
    INVARIANT line means the pricing let a stated law reach the door."""
    summaries = re.findall(
        r"apex: ledger t=\d+ rows=(\d+) ord=(\d+) frm=(\d+) fin=(\d+) "
        r"drift=(\d+) enginediff=(\d+) shadow=(\d+)", text)
    if not summaries:
        rep.add("HEALTH", True, "ledger", "no ledger telemetry (older AI build)")
        return
    rows, ord_, frm, fin, drift, ediff, shadow = (int(x) for x in summaries[-1])
    drifts = re.findall(r"apex: ledger drift .* why=(\S+)", text)
    bad = [w for w in drifts if w in ("unit-gone", "task-gone")]
    rep.add("HEALTH", not bad, "ledger-drift",
            f"{len(bad)} missed-event drift(s); last summary rows={rows} "
            f"ord={ord_} frm={frm} fin={fin} enginediff={ediff}")
    rep.add("HEALTH", True, "ledger-shadow",
            f"{shadow} shadow mismatch(es) recorded (data for the flip, "
            "not a failure)")
    inv = re.findall(r"apex: INVARIANT (\S+)", text)
    rep.add("HEALTH", not inv, "invariants",
            "none reached the door" if not inv
            else f"{len(inv)} refusal(s): " + " ".join(sorted(set(inv))))


CHECKS = [check_health, check_ledger, check_commitments, check_priority,
          check_economy,
          check_military, check_efficiency, check_vs_enemy, check_structures,
          check_geometry, check_perf]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    p = Path(sys.argv[1])
    # A tournament dir: audit every game and aggregate -- single games on
    # this benchmark are noise (documented 60%->10% win swings unchanged).
    infologs = sorted(p.glob("matches/*/infolog.txt")) if p.is_dir() else []
    if len(infologs) > 1:
        agg = defaultdict(list)
        for il in infologs:
            rep = Report()
            text = il.read_text(errors="replace")
            for chk in CHECKS:
                chk(text, rep)
            for _, ok, name, detail in rep.rows:
                m = re.search(r"(\d+(?:\.\d+)?)%", detail)
                agg[name].append((ok, float(m.group(1)) if m else None))
        print(f"aggregate over {len(infologs)} games:")
        for name, vals in agg.items():
            flags = sum(1 for ok, _ in vals if not ok)
            nums = sorted(v for _, v in vals if v is not None)
            med = f"  median {nums[len(nums)//2]:.0f}%" if nums else ""
            print(f"  {name:<28} flagged {flags}/{len(vals)}{med}")
        return
    text = load(sys.argv[1])
    rep = Report()
    for chk in CHECKS:
        chk(text, rep)
    # FAIL, not just report: he asked for a script that can find issues on its
    # own, which means a non-zero exit a runner can act on.
    return 1 if rep.show() else 0


if __name__ == "__main__":
    raise SystemExit(main() or 0)
