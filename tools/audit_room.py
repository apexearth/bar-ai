"""Audit checks for a base that boxes itself in (his 10-29 online games: big bonus, 1.5x income, the base so full of
basic converters and turrets that the gantry never found ground). Both read only the AI's own lines, so they run on
his hosted games' apex-t*.log as well as on our tests.

obsolete-converters-kept: `apex: reclobs t= ... conv=<own>/<dwarfed>/<past the swap test>/<priced>` once a minute;
  a seat holding 10 or more dwarfed (obsolete) converters in 4+ minutes when one of its important buildings found no
  site (his 10-30: they are swapped at the pace of their replacements, an issue only while they cost room) is flagged,
  with the stage they
  stop at: never past the swap test, past it but never priced (out of reach), or priced and still standing.
room-for-<def>: `apex: lathe-site t= <def> interior=.. bp=<i> to=.. bp=<b>` for every lathe site search of an
  important building (advanced or experimental plant, big reactor or converter); both bp at -1 is a search that
  found no site at all (what triggers the plot, plot.as). A seat with 10 or more of those for one def, half or more
  of its searches, is flagged, with what held the best spots (nofit) and what the plot did (plot / plot-clear /
  plot-built / plot-none).
"""
import re
from collections import Counter, defaultdict

RECLOBS = re.compile(r"\[([\d.]+)m t\d+\] apex: reclobs t=(\d+) .*? conv=(\d+)/(\d+)/(\d+)/(\d+)")
NANO_OBS = re.compile(r"apex: nano-assist reclaim x\d+ pen=\d+ obsolete=(\d+)/")
LATHE = re.compile(r"apex: lathe-site t=(\d+) (\w+) interior=\S+ bp=(-?\d+) to=\S+ bp=(-?\d+)[^\n]*")
LATHE_F = re.compile(r"\[f=(\d+)\][^\n]*apex: lathe-site t=(\d+) (\w+) interior=\S+ bp=(-?\d+) to=\S+ bp=(-?\d+)")
NOFIT = re.compile(r"nofit\(([^)]*)\)")
ORDER = re.compile(r"apex: exec t=(\d+) \S+ #\d+ \w+:(\w+) ")
PLOT = re.compile(r"apex: (plot|plot-clear|plot-built|plot-none|plot-drop) t=(\d+) (\w+)")
IMPORTANT = re.compile(r"(gant|alab|aap|avp|asy|amsub|afus|fus|mmkr|adveconv|shltx)")
DWARF_MIN, DWARF_MINUTES = 10, 8
ROOM_SHORT_MINUTES = 4   # minutes of 10+ obsolete converters while an important building had no site
NOSITE_MIN = 10


def check_obsolete_kept(text, rep):
    by = defaultdict(dict)   # team -> minute -> (own, dwarfed, denser, priced)
    for m in RECLOBS.finditer(text):
        by[int(m.group(2))][float(m.group(1))] = tuple(int(m.group(i)) for i in range(3, 7))
    if not by:
        return
    obs_reclaimed = sum(int(x) for x in NANO_OBS.findall(text))
    # his 10-30: obsolete converters are swapped at the pace of their replacements, so they are an issue only while
    # they cost room -- minutes in which an important building's site search found no site at all in this seat
    nosite = defaultdict(set)
    for m in LATHE_F.finditer(text):
        if IMPORTANT.search(m.group(3)) and int(m.group(4)) < 0 and int(m.group(5)) < 0:
            nosite[int(m.group(2))].add(int(int(m.group(1)) / 1800))
    for team in sorted(by):
        rows = sorted(by[team].items())
        held = [(mn, r) for mn, r in rows if r[1] >= DWARF_MIN]
        short = [(mn, r) for mn, r in held if any(int(mn) + k in nosite[team] for k in (-1, 0, 1))]
        span = (held[-1][0] - held[0][0]) if len(held) > 1 else 0.0
        peak = max((r[1] for _, r in rows), default=0)
        ok = len(short) < ROOM_SHORT_MINUTES
        detail = "peak %d obsolete converters standing, %d or more for %.0f min, %d of those minutes with an important " \
                 "building finding no site" % (peak, DWARF_MIN, span, len(short))
        if not ok:
            past = sum(1 for _, r in held if r[2] > 0)
            priced = sum(1 for _, r in held if r[3] > 0)
            stage = ("never past the swap test" if past == 0 else
                     "past the swap test but never priced (out of reach?)" if priced == 0 else
                     "priced and still standing (no hand took them)")
            detail += " -- %s; minutes past the swap %d/%d, priced %d/%d" % (stage, past, len(held), priced, len(held))
        rep.add("STRUCTURES", ok, "t%d-obsolete-converters-kept" % team, detail)
    rep.add("STRUCTURES", True, "obsolete-converters-nano-reclaimed",
            "%d obsolete converters handed to idle turrets (apex: nano-assist obsolete=)" % obs_reclaimed)


def check_room(text, rep):
    nosite = defaultdict(list)   # (team, def) -> lines with no site at all
    asked = Counter()
    for m in LATHE.finditer(text):
        team, d = int(m.group(1)), m.group(2)
        if not IMPORTANT.search(d):
            continue
        asked[(team, d)] += 1
        if int(m.group(3)) < 0 and int(m.group(4)) < 0:
            nosite[(team, d)].append(m.group(0))
    if not asked:
        return
    ordered = Counter((int(t), d) for t, d in ORDER.findall(text))
    plots = defaultdict(Counter)
    for kind, t, d in PLOT.findall(text):
        plots[(int(t), d)][kind] += 1
    for (team, d) in sorted(asked):
        lines = nosite.get((team, d), [])
        ok = not (len(lines) >= NOSITE_MIN and 2 * len(lines) >= asked[(team, d)])
        if ok and len(lines) < NOSITE_MIN:
            continue          # searched and found ground: nothing to say per def
        detail = "%d site searches, %d found no site, %d orders" % (asked[(team, d)], len(lines), ordered[(team, d)])
        pc = plots.get((team, d))
        if pc:
            detail += "; plot %s" % " ".join("%s=%d" % kv for kv in sorted(pc.items()))
        if not ok:
            fill = Counter()
            for line in lines:
                for grp in NOFIT.findall(line):
                    for tok in grp.split():
                        dd, _, n = tok.rpartition("x")
                        if n.isdigit():
                            fill[dd] += int(n)
            detail += " -- the best spots held: %s" % ", ".join("%s %d" % kv for kv in fill.most_common(5))
        rep.add("STRUCTURES", ok, "t%d-room-for-%s" % (team, d), detail)


ROOM_CHECKS = [check_obsolete_kept, check_room]
