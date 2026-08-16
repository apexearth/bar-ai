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
    # plant discipline: approvals vs refusals; multiple same-tier approvals
    appr = re.findall(r"plant approved (\S+) have=(\d+)/(\d+) t1=(\d+)"
                      r" t2=(\d+)", text)
    # air plants past the totals are the air STRATEGY's sanctioned exemption
    air = {"armap", "corap", "legap", "armaap", "coraap", "legaap"}
    over = [a for a in appr
            if (int(a[3]) > 2 or int(a[4]) > 2) and a[0] not in air]
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
            r" fwd=\S+(?: built=(\d))?", text):
        key = (m.group(1), m.group(2))
        if key in seen or int(m.group(3)) >= cutoff:
            continue
        seen.add(key)
        if m.group(8) == "0":
            metal["under-construction"] += float(m.group(7))
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
                f"{n:.0%} died holding no task (base overrun signature)")
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
    first_eat = {}
    for line in text.splitlines():
        m = re.search(r"\[([\d.]+)m t\d+\].*obsolete-reclaim (\S+) ", line)
        if m and m.group(2) not in first_eat:
            first_eat[m.group(2)] = float(m.group(1))
    both = set()
    for line in text.splitlines():
        m = re.search(r"\[([\d.]+)m t\d+\].*request (?:new|join\S*) (\S+)",
                      line)
        if m and float(m.group(1)) > first_eat.get(m.group(2), 1e9):
            both.add(m.group(2))
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
    text = load(sys.argv[1])
    rep = Report()
    for chk in CHECKS:
        chk(text, rep)
    rep.show()


if __name__ == "__main__":
    main()
