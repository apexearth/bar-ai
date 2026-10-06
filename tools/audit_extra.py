"""Audit checks added 2026-10-06, imported by audit.py's CHECKS.

NETS: are the decision nets alive -- inputs that never move all game (a dead
binding reads one value forever), a builder net that never changes the pick,
heads whose trust is zero or whose choice never varies, NaN/inf in a record.
And the complaints from his watched games that day: extractors held against
open spots, constructors dying unescorted, masts piled together, LRPC shelling
answered by no shield.
"""
import math
import re
from collections import Counter, defaultdict

FPM = 1800
# Inputs that are constant within a game by nature, not a dead binding.
EXPECTED_CONST = {"mapArea", "allies", "foeTeam", "comm", "homeD", "foeBaseD"}
MEX = re.compile(r"(armmex|cormex|legmex|armamex|corexp|legmext15|armmoho|cormoho|legmoho)$")
CON = re.compile(r"^(arm|cor|leg)(ck|cv|ca|ch|ack|acv|aca|cs|acsub|ach)$")
RADAR = re.compile(r"^(armrad|corrad|legrad)$")
SHIELD = re.compile(r"^(armgate|corgate|leggatet|legdeflector|armfgate|corfgate)$")
LRPC = re.compile(r"^(armbrtha|corint|leglrpc|armvulc|corbuzz|legstarfall)$")


def our_teams(text):
    return sorted({int(t) for t in re.findall(r"apex: nn t=(\d+) ", text)})


def deaths(text):
    """(frame, team, unit, cost, x, z, atkteam, atk) for every death."""
    out = []
    for m in re.finditer(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\w+) cost=(\d+) x=(-?\d+) z=(-?\d+)"
                         r".*? atkteam=(-?\d+) atk=(\S*)", text):
        f, t, u, c, x, z, at, a = m.groups()
        out.append((int(f), int(t), u, int(c), int(x), int(z), int(at), a))
    return out


def builds(text):
    """(frame, team, unit, x, z, uid) for every finished build/production."""
    out = []
    for m in re.finditer(r"\[BARAI_(?:BUILD|PROD)\] team=(\d+) ally=\d+ frame=(\d+) min=[\d.]+ unit=(\w+) cost=\d+"
                         r"(?: x=(-?\d+) z=(-?\d+))?(?:.*? uid=(\d+))?", text):
        t, f, u, x, z, uid = m.groups()
        out.append((int(f), int(t), u, int(x or -1), int(z or -1), int(uid or -1)))
    return out


def check_nets(text, rep):
    us = our_teams(text)
    if not us:
        rep.add("NETS", True, "nets", "no decision records (net logging off or not our AI)")
        return
    t0 = us[0]
    sch = re.search(r"apex: nn-schema v\d+ state=(\S+)", text)
    rows = re.findall(r"apex: nn t=%d f=\d+ .*? \| (\S+) \|" % t0, text)
    if sch and len(rows) >= 100:
        keys = sch.group(1).split(",")
        lo, hi, bad = [math.inf] * len(keys), [-math.inf] * len(keys), 0
        for r in rows:
            v = r.rstrip(",").split(",")
            for i, s in enumerate(v[:len(keys)]):
                try:
                    x = float(s)
                except ValueError:
                    continue
                if math.isnan(x) or math.isinf(x):
                    bad += 1
                    continue
                lo[i] = min(lo[i], x)
                hi[i] = max(hi[i], x)
        const = [("%s=%g" % (k, lo[i])) for i, k in enumerate(keys)
                 if lo[i] == hi[i] and k not in EXPECTED_CONST]
        rep.add("NETS", not const, "net-dead-inputs",
                "%d of %d inputs never moved over %d records%s" % (
                    len(const), len(keys), len(rows), (": " + " ".join(const[:20])) if const else ""))
        rep.add("NETS", bad == 0, "net-nan", "%d NaN/inf value(s) in builder records" % bad)
    sc = re.findall(r"apex: nn-score t=%d net=(\d+) blend=([\d.]+) explore=\d scored=\d+ topChanged=(\d)" % t0, text)
    if sc:
        blend = float(sc[-1][1])
        net = int(sc[-1][0])
        changed = sum(1 for s in sc if s[2] == "1")
        if blend > 0 and net == 0:
            rep.add("NETS", False, "builder-net-loaded", "blend=%.2f but no net loaded (layout mismatch or empty weights)" % blend)
        else:
            rep.add("NETS", not (blend > 0 and len(sc) >= 50 and changed == 0), "builder-net-moves",
                    "net changed the top pick in %d of %d scored elections (%.0f%%), blend %.2f, net %d games" % (
                        changed, len(sc), 100.0 * changed / len(sc), blend, net))
    for head in ("post", "com", "tech", "raid", "air"):
        hr = re.findall(r"apex: nn%s t=%d f=\d+ why=\S+ rule=(\S+)(?: ex=(\d))? trust=(\S+) .*? chosen=(-?\d+)" % (head, t0), text)
        if not hr:
            continue
        trust = [float(x[2]) for x in hr if re.match(r"^[\d.]+$", x[2])]
        live = [x for x in hr if x[1] != "1"]
        rules = Counter(x[0] for x in live)
        chosen = Counter(x[3] for x in live)
        tmax = max(trust) if trust else 0.0
        one = (len(live) >= 20) and (len(chosen) == 1)
        detail = "%d rows, trust %.2f, rule %s, chosen %s" % (
            len(hr), tmax, dict(rules.most_common(4)), dict(chosen.most_common(4)))
        if tmax <= 0.0:
            rep.add("NETS", False, "head-%s-trust" % head, "trust 0 all game -- the rule decides alone; " + detail)
        elif one:
            rep.add("NETS", False, "head-%s-one-answer" % head, "one answer every time; " + detail)
        else:
            rep.add("NETS", True, "head-%s" % head, detail)


def check_extraction(text, rep):
    us = our_teams(text)
    if not us:
        return
    t0 = us[0]
    sch = re.search(r"apex: nn-schema v\d+ state=(\S+)", text)
    if sch:
        keys = sch.group(1).split(",")
        if "mex" in keys and "openSpots" in keys:
            im, io = keys.index("mex"), keys.index("openSpots")
            held = {}
            for f, st in re.findall(r"apex: nn t=%d f=(\d+) .*? \| (\S+) \|" % t0, text):
                v = st.split(",")
                m = int(int(f) / FPM)
                if m in (6, 10, 15) and m not in held:
                    try:
                        held[m] = (float(v[im]), float(v[io]))
                    except (ValueError, IndexError):
                        pass
            if 10 in held:
                mx, op = held[10]
                share = mx / max(1.0, mx + op)
                rep.add("ECONOMY", share >= 0.25, "extractors-held",
                        "held at min 6/10/15 (mex/open): %s -- %.0f%% of known spots at min 10" % (
                            " ".join("%d:%d/%d" % (k, a, b) for k, (a, b) in sorted(held.items())), 100 * share))
    b = [x for x in builds(text) if x[1] == t0 and MEX.match(x[2]) and x[0] <= 15 * FPM]
    d = [x for x in deaths(text) if x[1] == t0 and MEX.match(x[2]) and x[0] <= 15 * FPM and x[6] >= 0 and x[6] != t0]
    if b or d:
        killers = Counter(x[7] for x in d)
        rep.add("ECONOMY", len(d) < 0.5 * max(1, len(b)), "extractors-raided",
                "by min 15: %d built, %d killed by the enemy (%s)" % (len(b), len(d), dict(killers.most_common(4))))
    hot = len(re.findall(r"apex: task-die t=%d \w*mex\w* .*?why=hot-road" % t0, text))
    if hot:
        rep.add("ECONOMY", hot < 10, "extractor-jobs-abandoned", "%d extractor job(s) dropped as hot-road" % hot)


def check_constructors(text, rep):
    us = our_teams(text)
    if not us:
        return
    t0 = us[0]
    d = [x for x in deaths(text) if x[1] == t0 and CON.match(x[2]) and x[6] != t0]
    early = [x for x in d if x[0] <= 15 * FPM]
    esc = re.findall(r"apex: escort-diag t=%d workers=(\d+) short=(\d+) paired=(\d+)" % t0, text)
    shortmax = max((int(s) for _w, s, _p in esc), default=0)
    pairmax = max((int(p) for _w, _s, p in esc), default=0)
    rep.add("MILITARY", len(early) < 3, "constructors-lost-early",
            "%d constructor(s) killed by min 15, %d all game (%s); escort-diag peak short %d, paired %d" % (
                len(early), len(d), dict(Counter(x[7] for x in early).most_common(4)), shortmax, pairmax))


def check_radar_crowd(text, rep):
    us = our_teams(text)
    if not us:
        return
    t0 = us[0]
    ferried = set(re.findall(r"apex: ferry built t=%d \w+ #(\d+)" % t0, text))
    dead = {x[4:6] for x in deaths(text) if x[1] == t0 and RADAR.match(x[2])}
    alive = [(x[3], x[4]) for x in builds(text) if x[1] == t0 and RADAR.match(x[2])
             and str(x[5]) not in ferried and (x[3], x[4]) not in dead]
    worst = 0
    for i, p in enumerate(alive):
        n = sum(1 for q in alive if math.hypot(p[0] - q[0], p[1] - q[1]) < 400)
        worst = max(worst, n)
    rep.add("STRUCTURES", worst < 3, "radar-crowd",
            "%d mast(s) standing, the densest 400-elmo patch holds %d" % (len(alive), worst))


def check_bombardment(text, rep):
    us = our_teams(text)
    if not us:
        return
    t0 = us[0]
    lost = sum(x[3] for x in deaths(text) if x[1] == t0 and LRPC.match(x[7]))
    if lost <= 0:
        return
    shields = sum(1 for x in builds(text) if x[1] == t0 and SHIELD.match(x[2]))
    ours = sum(1 for x in builds(text) if x[1] == t0 and LRPC.match(x[2]))
    plasma = [float(p) for p in re.findall(r"apex: shield-lrpc t=%d plasma=([\d.]+)" % t0, text)]
    rep.add("VS-ENEMY", not (lost > 3000 and shields == 0), "lrpc-answered",
            "%d metal lost to their long-range guns; we built %d shield(s), %d LRPC(s); AI's bombardment rate peak %.2f m/s" % (
                lost, shields, ours, max(plasma) if plasma else 0.0))


EXTRA_CHECKS = [check_nets, check_extraction, check_constructors, check_radar_crowd, check_bombardment]
