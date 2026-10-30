"""Audit checks for a base that boxes itself in (his 10-29 online games: big bonus, 1.5x income, "our AI is messy ...
it doesn't leave any room ... basic converters. What are we doing?"). Both read only the AI's own lines, so they run
on his hosted games' apex-t*.log as well as on our tests.

obsolete-converters-kept: `apex: reclobs t= ... conv=<own>/<dwarfed>/<past the swap test>/<priced>` once a minute.
  A seat that holds 10 or more dwarfed (obsolete) converters for 8 minutes or more is flagged, with the stage they
  stop at: never past the swap test, past it but never priced (out of reach), or priced and still standing.
gantry-room: `apex: lathe-site t= <gantry def> ... room=<n>` for every gantry site search. A seat whose searches
  found no room 10 or more times and that never ordered a gantry is flagged, with what filled the best spots
  (the nofit(...) lists).
"""
import re
from collections import Counter, defaultdict

RECLOBS = re.compile(r"\[([\d.]+)m t\d+\] apex: reclobs t=(\d+) .*? conv=(\d+)/(\d+)/(\d+)/(\d+)")
NANO_OBS = re.compile(r"apex: nano-assist reclaim x\d+ pen=\d+ obsolete=(\d+)/")
LATHE_GANT = re.compile(r"apex: lathe-site t=(\d+) (\w*gant\w*) .*? room=(\d+)[^\n]*")
NOFIT = re.compile(r"nofit\(([^)]*)\)")
GANT_ORDER = re.compile(r"apex: exec t=(\d+) \S+ #\d+ (?:plant|tech):\w*gant")
DWARF_MIN, DWARF_MINUTES = 10, 8
NOROOM_MIN = 10


def check_obsolete_kept(text, rep):
    by = defaultdict(dict)   # team -> minute -> (own, dwarfed, denser, priced)
    for m in RECLOBS.finditer(text):
        by[int(m.group(2))][float(m.group(1))] = tuple(int(m.group(i)) for i in range(3, 7))
    if not by:
        return
    obs_reclaimed = sum(int(x) for x in NANO_OBS.findall(text))
    for team in sorted(by):
        rows = sorted(by[team].items())
        held = [(mn, r) for mn, r in rows if r[1] >= DWARF_MIN]
        span = (held[-1][0] - held[0][0]) if len(held) > 1 else 0.0
        peak = max((r[1] for _, r in rows), default=0)
        ok = span < DWARF_MINUTES
        detail = "peak %d obsolete converters standing, %d or more for %.0f min" % (peak, DWARF_MIN, span)
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


def check_gantry_room(text, rep):
    searches = defaultdict(list)
    for m in LATHE_GANT.finditer(text):
        searches[int(m.group(1))].append((int(m.group(3)), m.group(0)))
    if not searches:
        return
    ordered = Counter(int(t) for t in GANT_ORDER.findall(text))
    for team in sorted(searches):
        rows = searches[team]
        noroom = [line for room, line in rows if room == 0]
        ok = not (len(noroom) >= NOROOM_MIN and ordered[team] == 0)
        detail = "%d gantry site searches, %d found no room, %d gantry orders" % (len(rows), len(noroom), ordered[team])
        if not ok:
            fill = Counter()
            for line in noroom:
                for grp in NOFIT.findall(line):
                    for tok in grp.split():
                        d, _, n = tok.partition("x")
                        if n.isdigit():
                            fill[d] += int(n)
            detail += " -- the best spots held: %s" % ", ".join("%s %d" % kv for kv in fill.most_common(5))
        rep.add("STRUCTURES", ok, "t%d-gantry-room" % team, detail)


ROOM_CHECKS = [check_obsolete_kept, check_gantry_room]
