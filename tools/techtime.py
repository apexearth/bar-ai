"""When the tiers came, per side: T2 lab, first fusion, first afus, gantry,
with the metal income at the time -- his 2026-09-19 complaint ("we got to T2
when we had like 120 metal income... way too late") as numbers.

    python tools/techtime.py <tournament-dir|match-dir> [more...]

Reads the gadget's [BARAI_T2START]/[BARAI_BUILD]/[BARAI_STATS]/[BARAI_DUTY]
markers, so it works on any team's log, ours or BARb's. Aggregates per spec
(the ally field is the spec index -- S16).
"""
import os
import re
import statistics
import sys

T2_RE = re.compile(r"\[BARAI_T2START\] team=\d+ ally=(\d+) frame=(\d+)")
BUILD_RE = re.compile(r"\[BARAI_BUILD\] team=\d+ ally=(\d+) frame=(\d+) min=[\d.]+ unit=(\w+) cost=(\d+)")
STATS_RE = re.compile(r"\[BARAI_STATS\] team=\d+ ally=(\d+) \S+ frame=(\d+).*? mInc=([\d.]+)")
DUTY_RE = re.compile(r"\[BARAI_DUTY\] team=(\d+) frame=\d+.*?conSamp=(\d+) conIdle=(\d+)")
RESULT_RE = re.compile(r"\[BARAI_RESULT\].*?ally=(\d+).*?(won|lost)")

GANTRY = {"armshltx", "corgant", "leggant", "armshltxuw", "corgantuw"}
AFUS = {"armafus", "corafus", "legafus"}
FUS = {"armfus", "corfus", "legfus", "armckfus", "corckfus"}


def minute(frame):
    return frame / 1800.0


def harvest(log):
    """One match -> {ally: {...}}."""
    sides = {}
    stats = {}   # ally -> [(frame, mInc)]
    duty = {}    # team -> (samp, idle) last cumulative
    with open(log, encoding="utf-8", errors="replace") as f:
        for line in f:
            if "[BARAI_" not in line:
                continue
            m = T2_RE.search(line)
            if m:
                a = int(m.group(1))
                sides.setdefault(a, {}).setdefault("t2", minute(int(m.group(2))))
                continue
            m = BUILD_RE.search(line)
            if m:
                a, fr, unit = int(m.group(1)), int(m.group(2)), m.group(3)
                d = sides.setdefault(a, {})
                if unit in GANTRY:
                    d.setdefault("gantry", minute(fr))
                elif unit in AFUS:
                    d.setdefault("afus", minute(fr))
                elif unit in FUS:
                    d.setdefault("fus", minute(fr))
                continue
            m = STATS_RE.search(line)
            if m:
                stats.setdefault(int(m.group(1)), []).append((int(m.group(2)), float(m.group(3))))
                continue
            m = DUTY_RE.search(line)
            if m:
                duty[int(m.group(1))] = (int(m.group(2)), int(m.group(3)))
                continue
    for a, rows in stats.items():
        d = sides.setdefault(a, {})
        for want in (10, 20, 30):
            at = [inc for fr, inc in rows if abs(minute(fr) - want) < 1.1]
            if at:
                d["inc%d" % want] = at[0]
        # income when T2 started: the nearest sample before it
        if "t2" in d:
            before = [inc for fr, inc in rows if minute(fr) <= d["t2"] + 0.1]
            if before:
                d["incT2"] = before[-1]
        d["len"] = minute(rows[-1][0]) if rows else 0.0
    # con idle is per TEAM in the gadget; in a 1v1 team == ally
    for t, (samp, idle) in duty.items():
        if t in sides and samp > 0:
            sides[t]["idle"] = 100.0 * idle / samp
    # the spec per side: result.json's teams[] (team index == spec index in a
    # 1v1, and the ally field is the spec index in every layout -- S16)
    rj = os.path.join(os.path.dirname(log), "result.json")
    if os.path.isfile(rj):
        try:
            import json
            for t in json.load(open(rj, encoding="utf-8")).get("teams", []):
                sides.setdefault(int(t["team"]), {})["name"] = t.get("spec", "?")
        except (ValueError, KeyError, OSError):
            pass
    return sides


def fmt(v, w=6, f="%.1f"):
    return (f % v).rjust(w) if v is not None else "-".rjust(w)


def main(args):
    logs = []
    for root in args:
        if os.path.isfile(os.path.join(root, "infolog.txt")):
            logs.append((os.path.basename(root), os.path.join(root, "infolog.txt")))
            continue
        mdir = os.path.join(root, "matches")
        if os.path.isdir(mdir):
            for m in sorted(os.listdir(mdir)):
                p = os.path.join(mdir, m, "infolog.txt")
                if os.path.isfile(p):
                    logs.append((m, p))
    if not logs:
        print("no matches under", args)
        return 1
    per_spec = {}
    print("%-44s %-24s %6s %6s %6s %6s %6s %6s %6s %6s %5s" % (
        "match", "side", "T2", "@inc", "fus", "afus", "gantry", "inc10", "inc20", "inc30", "idle"))
    for name, log in logs:
        sides = harvest(log)
        for a in sorted(sides):
            d = sides[a]
            spec = d.get("name", "ally%d" % a)
            print("%-44s %-24s %s %s %s %s %s %s %s %s %s" % (
                name[:44], spec[:24], fmt(d.get("t2")), fmt(d.get("incT2"), f="%.0f"),
                fmt(d.get("fus")), fmt(d.get("afus")), fmt(d.get("gantry")),
                fmt(d.get("inc10"), f="%.0f"), fmt(d.get("inc20"), f="%.0f"),
                fmt(d.get("inc30"), f="%.0f"), fmt(d.get("idle"), w=5, f="%.0f")))
            per_spec.setdefault(spec, []).append(d)
    print()
    print("median per spec  (n = games; a tier never reached counts as the game's length)")
    for spec, rows in per_spec.items():
        def med(key, absent_len=False):
            vals = []
            for d in rows:
                if key in d:
                    vals.append(d[key])
                elif absent_len:
                    vals.append(d.get("len", 0.0))
            return statistics.median(vals) if vals else None
        print("  %-24s n=%d  T2=%s @inc=%s fus=%s afus=%s gantry=%s | inc10=%s inc20=%s inc30=%s | idle=%s%%  reached T2/gantry %d/%d" % (
            spec[:24], len(rows), fmt(med("t2", True), 5), fmt(med("incT2"), 4, "%.0f"),
            fmt(med("fus", True), 5), fmt(med("afus", True), 5), fmt(med("gantry", True), 5),
            fmt(med("inc10"), 4, "%.0f"), fmt(med("inc20"), 4, "%.0f"), fmt(med("inc30"), 4, "%.0f"),
            fmt(med("idle"), 3, "%.0f"),
            sum(1 for d in rows if "t2" in d), sum(1 for d in rows if "gantry" in d)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or ["tournaments"]))
