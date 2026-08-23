"""Audit the eco/tech role in a single match.

Usage: python tools/audit_role.py <match-dir>

Checks the role against apexearth's spec (2026-08-22):
  - the role is held from the opening, by ONE player, wire-to-wire
  - every teammate's paid-for T2 constructor is delivered EARLY (all < 10m)
  - the holder builds ZERO army and ZERO static defence (sensors exempt)
  - the holder out-ecos every teammate (that is the point of the role)

Telemetry sources (all from the match dir's infolog.txt):
  BARAI_STATS   per-team periodic key=value samples (dev_stats_export.lua)
  BARAI_BUILD   per-unit builds >= SPAM_COST
  "apex: TECH ROLE team=N"    the facqueue's army-mix-off announcement
  "apex: tech lead = / CHANGED"  the election
  "apex: gave adv con to team N" the constructor gift
  "apex: sent X to lead N"       the sling payment (every 40th is logged)

armyReal/armyCheap are STANDING army value and include the commander;
mDefence is cumulative metal into static defence (gadget-classified, exact).
Army-unit detection from build lists is name-based and therefore heuristic:
the audit prints the names it counted so a human can veto a misclass.
"""
import re
import sys
from pathlib import Path

COMM_COST = 2700.0        # armcom/corcom/legcom metal cost
GIFT_DEADLINE_MIN = 10.0  # "Gifts should be coming out earlier than 10m - all of them"
ARMY_SLACK = 350.0        # standing-army slack above the commander (a stray scout)

# Name fragments that are NOT army. Constructors, scouts and rezzers are the
# role's floors; economy is its job; sensors are exempt by his call.
ECO_UTIL = ("mex", "moho", "solar", "adv", "win", "tide", "fus", "geo", "makr", "mmkr",
            "stor", "nano", "rad", "jam", "sonar", "eye", "targ", "silo",
            "gate", "amd", "scab", "lab", "vp", "ap", "hp", "sy", "plat",
            "gant", "shltx", "juno")
CONS = ("ck", "cv", "ca", "ack", "acv", "aca", "cs", "acsub", "com", "rectr",
        "necro", "farm", "consul", "mlv", "muskrat", "beaver")
SCOUTS = ("flea", "fav", "peep", "fink", "spy")
DEFENCE = ("llt", "rl", "ferret", "beamer", "hllt", "hlt", "fhlt", "frt",
           "pb", "vipe", "claw", "maw", "dtr", "toast", "amb", "anni",
           "doom", "bastion", "mg", "cluster", "hive", "guard", "pun",
           "agm", "flak", "mercury", "screamer", "drag", "fort", "dl",
           "tl", "popup")


def classify(name: str) -> str:
    n = name.lower()
    # order matters: check the specific lists before the broad eco list
    stripped = n[3:] if n[:3] in ("arm", "cor", "leg") else n
    for frag in SCOUTS:
        if frag in stripped:
            return "scout"
    for frag in CONS:
        if stripped == frag or stripped.startswith(frag) or stripped.endswith(frag):
            return "con"
    for frag in DEFENCE:
        if stripped == frag or stripped.startswith(frag):
            return "defence"
    for frag in ECO_UTIL:
        if frag in stripped:
            return "eco"
    return "army"


def parse_kv(line: str) -> dict:
    return dict(m.group(1, 2) for m in re.finditer(r"(\w+)=([^ ]+)", line))


def gmin(frame: int) -> float:
    return frame / 30.0 / 60.0


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    d = Path(sys.argv[1])
    log = d / "infolog.txt"
    if not log.exists():
        print(f"no infolog.txt in {d}")
        return 2
    text = log.read_text(errors="replace")
    # The handicap changes the ruleset (apexearth 2026-08-22): at >= +50 the
    # lead gifts no cons; at >= +100 two fusions by 10 minutes is required.
    handicap = 0
    script = d / "script.txt"
    if script.exists():
        hs = re.findall(r"Handicap=(\d+)", script.read_text(errors="replace"))
        handicap = max((int(h) for h in hs), default=0)

    flags = []
    oks = []

    def ok(name, msg):
        oks.append((name, msg))

    def flag(name, msg):
        flags.append((name, msg))

    # -- role timeline ------------------------------------------------------
    role_lines = re.findall(
        r"\[([0-9.]+)m t(\d+)\] apex: TECH ROLE team=(\d+)", text)
    holders = []           # (minute, team) in order, deduped by team-run
    for minute, _tag, team in role_lines:
        team = int(team)
        if not holders or holders[-1][1] != team:
            holders.append((float(minute), team))
    # Dedupe: every instance logs the same transition once, so eight identical
    # pairs are ONE change. A single early correction (fallback -> anchor)
    # inside the first 2.5 minutes is the anchor latching, not a handover.
    lead_changes = []
    for m in re.finditer(r"\[([0-9.]+)m t\d+\] apex: tech lead CHANGED "
                         r"team (\d+) -> (\d+)", text):
        minute, a, b = float(m.group(1)), m.group(2), m.group(3)
        if (a, b) not in [(x, y) for _, x, y in lead_changes]:
            lead_changes.append((minute, a, b))
    lead_changes = [(a, b) for minute, a, b in lead_changes if minute > 2.5]

    if not role_lines:
        flag("role-active", "NO 'TECH ROLE' lines at all -- the role never "
                            "engaged (team game? apex_role_tech_* zeroed?)")
        holder = None
    else:
        holder = holders[-1][1]
        first_min = holders[0][0]
        if first_min <= 2.5:
            ok("role-starts-early", f"army mix off by {first_min:.1f}m (team {holders[0][1]})")
        else:
            flag("role-starts-early", f"first army-mix-off at {first_min:.1f}m -- "
                                      "the opening window built army")
        if len(holders) == 1 and not lead_changes:
            ok("role-sticky", f"one holder wire-to-wire (team {holder})")
        else:
            path = " -> ".join(f"t{t}@{m:.1f}m" for m, t in holders)
            flag("role-sticky", f"{len(holders) - 1} handover(s): {path}"
                 + (f"; lead CHANGED {lead_changes}" if lead_changes else ""))

    # -- stats samples ------------------------------------------------------
    samples = {}   # team -> list of dict
    ally = {}      # team -> ally
    for line in text.splitlines():
        if "[BARAI_STATS]" not in line:
            continue
        kv = parse_kv(line)
        t = int(kv.get("team", -1))
        samples.setdefault(t, []).append(kv)
        ally[t] = int(kv.get("ally", -1))

    if holder is None or holder not in samples:
        print_report(oks, flags)
        return 1
    side = ally[holder]
    mates = [t for t, a in ally.items() if a == side and t != holder]
    hl = samples[holder][-1]

    # -- the transaction: gifts out, payments in ---------------------------
    gifts = [(float(m.group(1)), int(m.group(2))) for m in re.finditer(
        r"\[([0-9.]+)m t\d+\] apex: gave adv con to team (\d+)", text)]
    n_mates = len(mates)
    if handicap >= 50:
        # His rule: at +50 and above, no sharing -- teammates afford their own.
        if not gifts:
            ok("gifts-delivered", f"none, correctly (handicap +{handicap})")
        else:
            flag("gifts-delivered", f"{len(gifts)} con(s) gifted at handicap "
                 f"+{handicap} -- gifting should be OFF at >= +50")
    elif not gifts:
        flag("gifts-delivered", f"ZERO constructors gifted (owe {n_mates})")
    else:
        late = [g for g in gifts if g[0] > GIFT_DEADLINE_MIN]
        missing = sorted(set(mates) - {t for _, t in gifts})
        if len(gifts) >= n_mates and not late:
            ok("gifts-delivered", f"{len(gifts)}/{n_mates} gifted, last at "
                                  f"{max(g[0] for g in gifts):.1f}m")
        else:
            flag("gifts-delivered",
                 f"{len(gifts)}/{n_mates} gifted; "
                 f"{len(late)} after {GIFT_DEADLINE_MIN:.0f}m "
                 f"(times {[f'{m:.1f}' for m, _ in gifts]}); "
                 f"never gifted: {missing}")

    # His rule: at +100, two fusions by 10 minutes.
    FUSIONS = ("armfus", "corfus", "legfus", "armafus", "corafus", "legafus",
               "armckfus", "armuwfus", "coruwfus", "legdfus")
    fus_times = [float(m.group(1)) for m in re.finditer(
        r"\[BARAI_BUILD\] team=%d .*min=([0-9.]+) unit=(%s) " % (
            holder, "|".join(FUSIONS)), text)]
    if handicap >= 100:
        early = [t for t in fus_times if t <= 10.0]
        if len(early) >= 2:
            ok("two-fusions-10m", f"{len(early)} fusions by 10m "
               f"(times {[f'{t:.1f}' for t in sorted(fus_times)[:4]]})")
        else:
            flag("two-fusions-10m", f"{len(early)} fusion(s) by 10m at "
                 f"+{handicap} (all: {[f'{t:.1f}' for t in sorted(fus_times)]}) "
                 "-- rule: 2 by 10:00")
    pays = re.findall(r"\[[0-9.]+m t(\d+)\] apex: sent (\d+) to lead (\d+)", text)
    if pays:
        wrong = {int(l) for _, _, l in pays} - {holder}
        payers = {int(t) for t, _, _ in pays}
        if wrong:
            flag("payments-target", f"payments went to team(s) {sorted(wrong)} "
                                    f"but the role holder is team {holder}")
        else:
            ok("payments-target", f"{len(payers)}/{n_mates} teammates paid the holder "
                                  "(every 40th send is logged; totals are partial)")
    else:
        flag("payments-target", "no sling payments logged at all")

    # -- purity: zero defence, zero army -----------------------------------
    mdef = float(hl.get("mDefence", 0))
    if mdef <= 0:
        ok("zero-defence", "0 metal of static defence (exact, gadget-classified)")
    else:
        flag("zero-defence", f"{mdef:.0f} metal of static defence built by the holder")

    peak_army = max(float(s.get("armyReal", 0)) + float(s.get("armyCheap", 0))
                    for s in samples[holder])
    above = peak_army - COMM_COST
    if above <= ARMY_SLACK:
        ok("zero-army-standing", f"peak standing army {above:.0f} above the commander")
    else:
        flag("zero-army-standing", f"peak standing army {above:.0f} metal above "
                                   "the commander")

    army_names = {}
    cheap = hl.get("cheapBuilt", "")
    for part in cheap.split(","):
        if ":" not in part:
            continue
        name, cost = part.rsplit(":", 1)
        if classify(name) == "army":
            army_names[name] = army_names.get(name, 0) + float(cost)
    for m in re.finditer(r"\[BARAI_BUILD\] team=%d .*unit=(\w+) cost=(\d+)" % holder, text):
        if classify(m.group(1)) == "army":
            army_names[m.group(1)] = army_names.get(m.group(1), 0) + float(m.group(2))
    if not army_names:
        ok("zero-army-built", "no army-classified units in the holder's build lists")
    else:
        total = sum(army_names.values())
        flag("zero-army-built", f"{total:.0f} metal of army-classified builds: "
             + ", ".join(f"{k}:{v:.0f}" for k, v in sorted(army_names.items()))
             + "  (name-heuristic -- verify)")

    # -- economy: the holder must out-eco its teammates --------------------
    def last(t, key, default=0.0):
        return float(samples[t][-1].get(key, default)) if t in samples else default

    prod = {t: last(t, "metalProduced") for t in [holder] + mates}
    rank = sorted(prod, key=prod.get, reverse=True)
    mate_mean = (sum(prod[t] for t in mates) / len(mates)) if mates else 0.0
    ratio = prod[holder] / mate_mean if mate_mean > 0 else 0.0
    if rank[0] == holder:
        ok("eco-rank", f"holder #1 in metal produced ({prod[holder]:.0f}, "
                       f"{ratio:.2f}x teammate mean)")
    else:
        flag("eco-rank", f"holder #{rank.index(holder) + 1} of {len(rank)} in metal "
             f"produced: {prod[holder]:.0f} vs best teammate t{rank[0]} "
             f"{prod[rank[0]]:.0f} ({ratio:.2f}x teammate mean)")

    t2mex = {t: last(t, "t2Mex") for t in [holder] + mates}
    best_t2 = max(t2mex, key=t2mex.get)
    if best_t2 == holder:
        ok("moho-rank", f"holder leads mohos ({t2mex[holder]:.0f})")
    else:
        flag("moho-rank", f"holder has {t2mex[holder]:.0f} mohos vs "
             f"t{best_t2}'s {t2mex[best_t2]:.0f}")

    techs = {t: last(t, "techStart", -1) for t in [holder] + mates}
    real = {t: v for t, v in techs.items() if v > 0}
    if real:
        first_tech = min(real, key=real.get)
        if first_tech == holder:
            ok("tech-first", f"holder teched first ({gmin(real[holder]):.1f}m)")
        elif holder in real:
            flag("tech-first", f"holder teched at {gmin(real[holder]):.1f}m; "
                 f"t{first_tech} beat it ({gmin(real[first_tech]):.1f}m)")
        else:
            flag("tech-first", "holder NEVER started T2")
    fus = re.search(r"(armfus|corfus|legfus|armafus|corafus|legafus|"
                    r"armckfus|legdfus)",
                    samples[holder][-1].get("allBuilt", ""))
    if fus:
        ok("fusion", f"holder built {fus.group(1)}")
    else:
        flag("fusion", "holder never built a fusion "
                       "(benchmark income may make this unreachable)")

    # -- health -------------------------------------------------------------
    if float(hl.get("commLost", -1)) < 0:
        ok("commander", "holder's commander alive at last sample")
    else:
        flag("commander", f"holder's commander DIED at "
             f"{gmin(float(hl['commLost'])):.1f}m")
    mex_excess = float(hl.get("metalExcess", 0))
    mp = float(hl.get("metalProduced", 1)) or 1
    if mex_excess / mp <= 0.05:
        ok("metal-waste", f"{mex_excess:.0f} of {mp:.0f} overflowed "
                          f"({100 * mex_excess / mp:.0f}%)")
    else:
        flag("metal-waste", f"{mex_excess:.0f} of {mp:.0f} overflowed "
                            f"({100 * mex_excess / mp:.0f}%)")

    # His rule: no metal waste in the first ~15 minutes (waste == not enough
    # build power). metalExcess is cumulative and sampled every 2 game-min:
    # read the sample nearest 16m.
    def nearest(mins):
        return min(samples[holder],
                   key=lambda s: abs(float(s.get("frame", 0)) / 1800.0 - mins))
    s16 = nearest(16)
    ew = float(s16.get("metalExcess", 0))
    ep = float(s16.get("metalProduced", 1)) or 1
    if ew / ep <= 0.02:
        ok("early-waste", f"{ew:.0f} of {ep:.0f} overflowed by "
           f"{float(s16.get('frame', 0)) / 1800.0:.0f}m ({100 * ew / ep:.1f}%)")
    else:
        flag("early-waste", f"{ew:.0f} of {ep:.0f} overflowed by "
             f"{float(s16.get('frame', 0)) / 1800.0:.0f}m ({100 * ew / ep:.1f}%) "
             "-- rule: no waste in 0-15m; means not enough build power")

    # Build power: nanos standing by the early marks (from cheapBuilt/allBuilt
    # counts is unreliable; use the def-count in cheapBuilt names).
    def nano_count(sample):
        blob = sample.get("cheapBuilt", "") + "," + sample.get("allBuilt", "")
        n = 0.0
        for part in blob.split(","):
            if "nanotc" in part and ":" in part:
                n += float(part.rsplit(":", 1)[1]) / 210.0  # 210 = nano cost
        return n
    n8 = nano_count(nearest(8))
    if n8 >= 2:
        ok("build-power-8m", f"~{n8:.0f} nano turrets by 8m")
    else:
        flag("build-power-8m", f"~{n8:.0f} nano turrets by 8m (rule: >=2 -- "
                               "the controller should be buying build power)")

    print_report(oks, flags, holder=holder, mates=mates)
    return 0 if not flags else 1


def print_report(oks, flags, holder=None, mates=None):
    if holder is not None:
        print(f"== ECO/TECH ROLE AUDIT ==  holder: team {holder}"
              f"   teammates: {sorted(mates)}\n")
    for name, msg in oks:
        print(f"  ok    {name:<22} {msg}")
    for name, msg in flags:
        print(f"  FLAG  {name:<22} {msg}")
    print(f"\n{len(flags)} flag(s).")


if __name__ == "__main__":
    sys.exit(main())
