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
        for section in ("HEALTH", "ECONOMY", "MILITARY", "EFFICIENCY"):
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
    # first fusion ask + first standing, per team
    asks = [(minute_of(l), l) for l in
            re.findall(r".*eco fusion \w+ standing=.*", text)]
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


CHECKS = [check_health, check_economy, check_military, check_efficiency]


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
    rep.show()


if __name__ == "__main__":
    main()
