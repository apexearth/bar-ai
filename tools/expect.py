"""What a big enough battery MUST show, or it is a red flag.

    python tools/expect.py <set-or-tournament-dir> [...]     # pools every game
    python tools/expect.py --min-minutes 25 <dirs...>

apexearth 2026-09-13: "I don't want to have to be the one who mentions that
stuff is broken. I want you to find it automatically. If we have been running
enough games and long enough games, then we should expect to see these things
in the logs. And if we don't, it should be a red flag."

Each EXPECTATION names the games that count as evidence (mature enough for
the thing to have happened), what to measure over them, and the bar. With too
few mature games it says NEED MORE, never OK. Every line is one of his own
complaints turned into an assertion; add the next one here the day he raises
it. Exit code 1 on any RED so a runner can act on it.

Reads the Apex side only (team 0 in ab.py sets; every Apex team in a
tournament game) -- BARb logs nothing.
"""
import re
import sys
import glob
import json
import math
import argparse
from collections import Counter, defaultdict
from pathlib import Path

MIN_MINUTES = 25.0

# ----------------------------------------------------------------- one game


def load_game(d):
    d = Path(d)
    il = d / "infolog.txt"
    if not il.is_file():
        return None
    text = il.read_text(errors="replace")
    g = {"dir": str(d), "name": d.name, "text": text}
    try:
        r = json.loads((d / "result.json").read_text())["result"]
        g["minutes"] = float(r.get("game_minutes", 0))
        win = r.get("winner_specs") or []
        g["outcome"] = "WIN" if any(w.startswith("Apex") for w in win) else ("LOSS" if win else "tl")
    except Exception:
        g["minutes"] = 0.0
        g["outcome"] = "?"
    ally = {}
    for m in re.finditer(r"\[BARAI_STATS\] team=(\d+) ally=(\d+)", text):
        ally[m.group(1)] = m.group(2)
    apex = set()
    scr = d / "script.txt"
    if scr.is_file():
        st = scr.read_text(errors="replace")
        for m in re.finditer(r"\[AI\d+\]\s*\{[^}]*?ShortName=(\w+);[^}]*?Team=(\d+);", st, re.S):
            if m.group(1).startswith("Apex"):
                apex.add(m.group(2))
    if not apex:
        apex = {"0"}
    g["apex"] = apex
    stats = {}
    for m in re.finditer(r"\[BARAI_STATS\] team=(\d+) [^\n]*", text):
        stats[m.group(1)] = dict(re.findall(r"(\w+)=(-?[\d.]+)", m.group(0)))
    g["stats"] = {k: v for k, v in stats.items() if k in apex}
    g["income"] = sum(float(v.get("mInc", 0)) for v in g["stats"].values())
    g["built"] = sum(float(v.get("mBuiltReal", 0)) for v in g["stats"].values())
    g["theirs"] = sum(float(v.get("mBuiltReal", 0)) for k, v in stats.items() if k not in apex)
    g["errors"] = len(re.findall(r" ERR  : ", text))
    g["apex_lines"] = len(re.findall(r"apex: ", text))
    # structures finished, Apex side: def -> [(minute, x?)]
    builds = Counter()
    build_min = defaultdict(list)
    for m in re.finditer(r"\[BARAI_BUILD\] team=(\d+) ally=\d+ frame=\d+ min=([\d.]+) unit=(\w+) cost=(\d+)", text):
        if m.group(1) in apex:
            builds[m.group(3)] += 1
            build_min[m.group(3)].append(float(m.group(2)))
    g["builds"] = builds
    g["build_min"] = build_min
    return g


def mature(g, min_minutes):
    return g["minutes"] >= min_minutes


def last_line(text, pat):
    m = None
    for m in re.finditer(pat, text):
        pass
    return m


def elect_counts(text):
    m = last_line(text, r"apex: elect ([^\n]*)")
    return dict((k, int(v)) for k, v in re.findall(r"([a-z.]+)=(\d+)", m.group(1))) if m else {}


# -------------------------------------------------------------- expectations
# Each returns (status, detail). status: "OK", "RED", "NEED MORE", "INFO".


def exp_health(games):
    bad = [g["name"] for g in games if g["errors"] > 0 or g["apex_lines"] < 100]
    if bad:
        return "RED", f"{len(bad)} game(s) with script errors or a silent AI: {', '.join(bad[:4])}"
    return "OK", f"{len(games)} games, no script errors, AI alive in all"


def exp_bombers(games):
    """A wing that never masses: 0 bombers against a target of 102 (his 8v8)."""
    ev = [g for g in games if g["builds"].get("armaap", 0) + g["builds"].get("coraap", 0)
          + g["builds"].get("legaap", 0) > 0 and g["minutes"] >= 25]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} mature games with an advanced air plant (need 3)"
    peaks = []
    strikes = 0
    for g in ev:
        best = 0
        for m in re.finditer(r"apex: air (\d+)/(\d+) bombers", g["text"]):
            best = max(best, int(m.group(1)))
        peaks.append(best)
        strikes += len(re.findall(r"apex: air strike -- ", g["text"]))
    if max(peaks) < 5:
        return "RED", f"advanced air plant in {len(ev)} games, peak bombers held {peaks} -- the wing never masses"
    if strikes == 0:
        return "RED", f"bombers massed (peaks {peaks}) but no strike ever flew"
    return "OK", f"peak bombers {peaks}, {strikes} strike releases"


def exp_gantry_used(games):
    """Idle gantries beside a full bank (his Oasis)."""
    ev = [g for g in games if g["builds"].get("armshltx", 0) + g["builds"].get("corgant", 0)
          + g["builds"].get("leggant", 0) > 0 and g["minutes"] >= 25]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} mature games with a gantry (need 3)"
    rows = []
    reds = 0
    for g in ev:
        first = min(g["build_min"].get("armshltx", []) + g["build_min"].get("corgant", []) + g["build_min"].get("leggant", []))
        stood = g["minutes"] - first
        idle = len(re.findall(r"facqueue idle (?:armshltx|corgant|leggant)", g["text"]))
        t3 = sum(float(v.get("mT3", 0)) for v in g["stats"].values())
        rows.append(f"{g['name']}: stood {stood:.0f}m idle-lines {idle} T3 {t3/1000:.0f}k")
        if stood >= 6 and t3 < 1000:
            reds += 1
    if reds:
        return "RED", f"{reds}/{len(ev)} games had a gantry for 6+ min and no T3 metal; " + "; ".join(rows[:4])
    return "OK", "; ".join(rows[:4])


def exp_plants_supported(games):
    """Six gantries under fewer nanos than their one (his 8v8 lesson in efficiency)."""
    ev = [g for g in games if g["minutes"] >= 25 and g["income"] >= 400]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} mature rich games (need 3)"
    ratios = []
    for g in ev:
        plants = sum(n for d, n in g["builds"].items() if re.match(r"(arm|cor|leg)(lab|vp|ap|hp|alab|avp|aap|ahp|shltx|gant|sy|asy|amsub)$", d))
        nanos = sum(n for d, n in g["builds"].items() if d.endswith("nanotc") or d.endswith("nanotcplat"))
        ratios.append((g["name"], plants, nanos, nanos / max(plants, 1)))
    low = [r for r in ratios if r[3] < 3.0]
    if len(low) >= max(2, len(ratios) // 2):
        return "RED", "fewer than 3 nanos per plant in " + ", ".join(f"{n} ({p} plants, {q} nanos)" for n, p, q, _ in low[:4])
    return "OK", ", ".join(f"{n}: {q}/{p} nanos per plant" for n, p, q, _ in ratios[:4])


def exp_silo_before_gun(games):
    """One Basilica per team early on; he would rather a silo."""
    ev = [g for g in games if g["minutes"] >= 25 and g["income"] >= 600]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} mature rich games (need 3)"
    silos = sum(g["builds"].get("armsilo", 0) + g["builds"].get("corsilo", 0) + g["builds"].get("legsilo", 0) for g in ev)
    guns = sum(g["builds"].get("armbrtha", 0) + g["builds"].get("corint", 0) + g["builds"].get("leglrpc", 0)
               + g["builds"].get("armvulc", 0) + g["builds"].get("corbuzz", 0) for g in ev)
    if guns > 0 and silos == 0:
        return "RED", f"{guns} big guns, 0 silos over {len(ev)} rich games"
    return "OK", f"{silos} silos, {guns} big guns over {len(ev)} rich games"


def exp_antinuke_depth(games):
    """Late game ~3 anti-nukes, not 1."""
    ev = [g for g in games if g["minutes"] >= 25 and g["income"] >= 800]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} mature games at 800+ income (need 3)"
    ans = [g["builds"].get("armamd", 0) + g["builds"].get("corfmd", 0) + g["builds"].get("legabm", 0) for g in ev]
    if max(ans) < 2:
        return "RED", f"anti-nukes per rich game {ans}: never a second umbrella"
    return "OK", f"anti-nukes per rich game {ans}"


def exp_escorts(games):
    """Cons losing their escorts and dying; workers outside the base go alone."""
    ev = [g for g in games if g["minutes"] >= 15]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} games of 15+ min (need 3)"
    nopair = []
    for g in ev:
        paired = 0
        short = 0
        for m in re.finditer(r"apex: escort-diag t=\d+ workers=(\d+) short=(\d+) paired=(\d+)", g["text"]):
            paired = max(paired, int(m.group(3)))
            short = max(short, int(m.group(2)))
        if paired == 0 and short > 0:
            nopair.append(g["name"])
    if len(nopair) >= max(2, len(ev) // 2):
        return "RED", f"exposed workers but no escort ever paired in {len(nopair)}/{len(ev)} games"
    return "OK", f"escorts paired in {len(ev) - len(nopair)}/{len(ev)} games"


def exp_army_leaves(games):
    """Held army at home while the enemy does nothing (the hold pool)."""
    ev = [g for g in games if g["minutes"] >= 25]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} mature games (need 3)"
    stuck = []
    for g in ev:
        e = elect_counts(g["text"])
        hold = e.get("mass.hold", 0)
        atk = e.get("mass.attack", 0) + e.get("stock", 0)
        if hold > 2 * max(atk, 1) and hold >= 100:
            stuck.append(f"{g['name']} hold={hold} attack={atk}")
    if stuck:
        return "RED", "; ".join(stuck[:4])
    return "OK", f"no game held more than twice what it sent"


def exp_lead_closes(games):
    """A 1.5x lead at the time limit is not a win."""
    ev = [g for g in games if g["minutes"] >= 25]
    if len(ev) < 4:
        return "NEED MORE", f"{len(ev)} mature games (need 4)"
    stalled = [g for g in ev if g["outcome"] == "tl" and g["theirs"] > 0 and g["built"] >= 1.5 * g["theirs"]]
    if len(stalled) >= max(2, len(ev) // 3):
        return "RED", f"{len(stalled)}/{len(ev)} games timed out with 1.5x+ their metal: " + ", ".join(f"{g['name']} {g['built']/1000:.0f}k/{g['theirs']/1000:.0f}k" for g in stalled[:3])
    return "OK", f"{len(stalled)}/{len(ev)} mature games stalled with a 1.5x lead"


def exp_spam_forward(games):
    """Cheap raiders go forward and die there, not at home."""
    ev = [g for g in games if g["minutes"] >= 20]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} games of 20+ min (need 3)"
    tot = far = 0
    for g in ev:
        for m in re.finditer(r"apex: unit-destroyed (?:armpw|armfav|armflash|corak|corgator|corfav|legkark|leggob) [^\n]*fwd=([\d.]+)", g["text"]):
            tot += 1
            if float(m.group(1)) > 1.0:
                far += 1
    if tot >= 50 and far / tot < 0.15:
        return "RED", f"only {far}/{tot} cheap-unit deaths were beyond the front -- the fodder is not going forward"
    return "OK", f"{far}/{tot} cheap-unit deaths beyond the front"


def exp_towers_where_hit(games):
    """Defence blobs at the centre while the raided flank has nothing."""
    ev = [g for g in games if g["minutes"] >= 25]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} mature games (need 3)"
    rows = []
    reds = 0
    for g in ev:
        towers = [(int(m.group(1)), int(m.group(2))) for m in re.finditer(
            r"apex: exec t=\d+ \S+ #\d+ protect:(?:arm|cor|leg)(?:llt|beamer|hlt|claw|guard|amb|pb|drag|hllt|exp|toast|pun|vipe|doom|anni|mwl|bhmth) pick=\d+ at=(\d+),(\d+)", g["text"])]
        deaths = [(int(m.group(1)), int(m.group(2))) for m in re.finditer(
            r"\[BARAI_DEATH\] frame=\d+ team=(?:%s) unit=\w+ cost=\d+ x=(\d+) z=(\d+) [^\n]*mob=0" % "|".join(g["apex"]), g["text"])]
        if len(deaths) < 20 or len(towers) < 5:
            continue
        covered = sum(1 for (x, z) in deaths if any(math.hypot(x - tx, z - tz) < 700 for (tx, tz) in towers))
        share = covered / len(deaths)
        rows.append(f"{g['name']} {share:.0%} of {len(deaths)} structure deaths within 700 of a tower site")
        if share < 0.25:
            reds += 1
    if not rows:
        return "NEED MORE", "no mature game with 20+ structure deaths and 5+ tower sites"
    if reds >= max(2, len(rows) // 2):
        return "RED", "; ".join(rows[:4])
    return "OK", "; ".join(rows[:4])


def exp_outer_mex_guns(games):
    """None of our mexes outside our base have any turrets guarding them."""
    ev = [g for g in games if g["minutes"] >= 25]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} mature games (need 3)"
    rows = []
    reds = 0
    for g in ev:
        home = re.search(r"apex: exec t=\d+ armcom #\d+ \S+ pick=\d+ at=(\d+),(\d+)", g["text"])
        if not home:
            continue
        hx, hz = int(home.group(1)), int(home.group(2))
        mex = {(int(m.group(1)), int(m.group(2))) for m in re.finditer(r"apex: exec t=\d+ \S+ #\d+ mex:\S+ pick=\d+ at=(\d+),(\d+)", g["text"])}
        outer = [p for p in mex if math.hypot(p[0] - hx, p[1] - hz) > 1500]
        towers = [(int(m.group(1)), int(m.group(2))) for m in re.finditer(
            r"apex: exec t=\d+ \S+ #\d+ protect:(?:arm|cor|leg)\w+ pick=\d+ at=(\d+),(\d+)", g["text"])]
        if len(outer) < 10:
            continue
        guarded = sum(1 for (x, z) in outer if any(math.hypot(x - tx, z - tz) < 350 for (tx, tz) in towers))
        rows.append(f"{g['name']} {guarded}/{len(outer)} outer mexes with a gun site")
        if guarded / len(outer) < 0.25:
            reds += 1
    if not rows:
        return "NEED MORE", "no mature game with 10+ outer mex claims"
    if reds >= max(2, len(rows) // 2):
        return "RED", "; ".join(rows[:4])
    return "OK", "; ".join(rows[:4])


def exp_rezbots(games):
    """Wow we have a lot (BARb caps at 60)."""
    ev = [g for g in games if g["minutes"] >= 25]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} mature games (need 3)"
    peaks = []
    for g in ev:
        best = 0
        for m in re.finditer(r"apex: rezwant t=\d+ [^\n]*have=(\d+)", g["text"]):
            best = max(best, int(m.group(1)))
        peaks.append(best)
    if sorted(peaks)[len(peaks) // 2] > 90:
        return "RED", f"peak rez bots per game {peaks} (BARb's limit is 60)"
    return "OK", f"peak rez bots per game {peaks}"


def exp_personas_up_only(games):
    """Never below neutral."""
    low = []
    for g in games:
        for m in re.finditer(r"apex: persona t=(\d+) rolled [^\n]*", g["text"]):
            vals = [float(v) for v in re.findall(r"=(\d+\.\d+)", m.group(0))[1:]]
            if any(v < 0.999 for v in vals):
                low.append(f"{g['name']} t{m.group(1)}")
    if low:
        return "RED", f"persona rolled below 1.0 in {len(low)} team(s): {', '.join(low[:4])}"
    if not any("apex: persona" in g["text"] for g in games):
        return "NEED MORE", "no persona line in any game"
    return "OK", "every roll at or above neutral"


def exp_eco_seat(games):
    """The eight-player eco seat: no army, no defence, no gantry while it grows."""
    rows = []
    reds = 0
    for g in games:
        grow = Counter(re.findall(r"apex: eco-status team=(\d+) growing=1", g["text"]))
        for t, n in grow.most_common(1):
            if n < 3:
                continue
            stat = re.findall(r"apex: eco-status team=%s growing=(\d) P=(\d+)/(\d+)" % t, g["text"])
            if not stat:
                continue
            grew = [i for i, (gr, _, _) in enumerate(stat) if gr == "1"]
            act = next((i for i, (gr, _, _) in enumerate(stat) if gr == "0"), None)
            # builds by the seat before it activated (eco-status is every 2 minutes)
            first_off = None
            if act is not None:
                mm = list(re.finditer(r"apex: eco-status team=%s growing=0" % t, g["text"]))
                if mm:
                    fm = re.search(r"\[f=(\d+)\]", g["text"][max(0, mm[0].start() - 200):mm[0].start()])
                    first_off = int(fm.group(1)) if fm else None
            gant = arm = defm = 0
            for b in re.finditer(r"\[BARAI_BUILD\] team=%s ally=\d+ frame=(\d+) min=[\d.]+ unit=(\w+) cost=(\d+)" % t, g["text"]):
                fr = int(b.group(1))
                if first_off is not None and fr >= first_off:
                    continue
                u = b.group(2)
                if u in ("armshltx", "corgant", "leggant"):
                    gant += 1
                if re.match(r"(arm|cor|leg)(llt|beamer|hlt|claw|guard|amb|pb|drag|hllt|exp|toast|pun|vipe|doom|anni|mwl|bhmth)$", u):
                    defm += int(b.group(3))
            last = stat[-1]
            rows.append(f"{g['name']} t{t}: P {last[1]}/{last[2]} growing={last[0]} gantries-while-growing={gant} defence-metal-while-growing={defm}")
            if gant > 0 or defm > 3000:
                reds += 1
    if not rows:
        return "NEED MORE", "no game with a rear specialist"
    if reds:
        return "RED", "; ".join(rows[:4])
    return "OK", "; ".join(rows[:4])


def exp_seat_hands(games):
    """The eco seat's hands are turrets, not constructors (apexearth: ~4 T2 ground,
    ~10 T1 air, 5-6 T2 air, "a ton of nano turrets"); its energy is converted."""
    rows = []
    reds = 0
    con = re.compile(r"(arm|cor|leg)(ck|ack|ca|aca|cv|acv|ch|cs|acs|csa|acsub|otter|beaver|muskrat|fark|consul|decom|mlv)$")
    nano = re.compile(r"(arm|cor|leg)nanotc")
    for g in games:
        if g["minutes"] < 20:
            continue
        # the seat is the team that spent longest growing (the role is
        # re-elected early and a second team can print ON once)
        grow = Counter(re.findall(r"apex: eco-status team=(\d+) growing=1", g["text"]))
        for t, n in grow.most_common(1):
            if n < 3:
                continue
            nanos = 0
            for b in re.finditer(r"\[BARAI_BUILD\] team=%s ally=\d+ frame=\d+ min=[\d.]+ unit=(\w+) " % t, g["text"]):
                if nano.match(b.group(1)):
                    nanos += 1
            # constructors are mobile and reach no gadget line: the lab's own
            # produce decisions are the census (orders, a few never finish)
            cons = 0
            for a in re.finditer(r"apex: decide t=%s \S+ #\d+ -> produce:(\w+)" % t, g["text"]):
                if con.match(a.group(1)):
                    cons += 1
            ew = re.findall(r"\[BARAI_WASTE\] frame=\d+ team=%s mWaste=\d+ mMade=\d+ eWaste=(\d+) eMade=(\d+)" % t, g["text"])
            epct = int(100 * int(ew[-1][0]) / max(int(ew[-1][1]), 1)) if ew else -1
            rows.append(f"{g['name']} t{t}: cons={cons} nanos={nanos} energy-wasted={epct}%")
            if cons > 30 or nanos < cons or epct > 50:
                reds += 1
    if not rows:
        return "NEED MORE", "no 20-min game with a rear specialist"
    if reds:
        return "RED", "; ".join(rows[:4])
    return "OK", "; ".join(rows[:4])


def exp_no_flipflop(games):
    """We keep making the same obsolete buildings we've reclaimed."""
    ev = [g for g in games if g["minutes"] >= 20]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} games of 20+ min (need 3)"
    rows = []
    reds = 0
    for g in ev:
        loops = Counter()
        for t in g["apex"]:
            eats = {}
            for m in re.finditer(r"\[f=(\d+)\][^\n]*apex: exec t=%s \S+ #\d+ reclaim:(\w+) " % t, g["text"]):
                eats.setdefault(m.group(2), []).append(int(m.group(1)))
            for m in re.finditer(r"\[BARAI_BUILD\] team=%s ally=\d+ frame=(\d+) min=[\d.]+ unit=(\w+) " % t, g["text"]):
                u, fr = m.group(2), int(m.group(1))
                if u in eats and any(fr > e for e in eats[u]):
                    loops[u] += 1
        tot = sum(loops.values())
        rows.append(f"{g['name']}: {tot} rebuilt-after-reclaim ({', '.join(f'{u} x{n}' for u, n in loops.most_common(3))})")
        if tot >= 5:
            reds += 1
    if reds >= 1:
        return "RED", "; ".join(rows[:4])
    return "OK", "; ".join(rows[:4])




def _minute_of(text, pat):
    """Game minute of the first line matching pat (its [M.Mm tN] stamp), or None."""
    for m in re.finditer(r"\[(\d+\.\d)m t\d+\] " + pat, text):
        return float(m.group(1))
    return None


def exp_home_mex_upgrades(games):
    """Home mexes are upgraded before a reactor is started, not after it."""
    ev = [g for g in games if g["minutes"] >= 25]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} mature games (need 3)"
    late = []
    for g in ev:
        t0 = _minute_of(g["text"], r"apex: request new (?:arm|cor|leg)(?:fus|afus|ckfus|uwfus)\b")
        if t0 is None:
            continue
        last = None
        for m in re.finditer(r"\[(\d+\.\d)m t\d+\] apex: mexup t=\d+ at=[\d,]+ surv=[\d.]+ raw=[\d.]+ v=[\d.]+ homeD=(\d+)", g["text"]):
            if int(m.group(2)) <= 700 and float(m.group(1)) > t0 + 3.0:
                last = float(m.group(1))
        if last is not None:
            late.append((g["name"], t0, last))
    if late and len(late) >= max(1, len(ev) // 3):
        return "RED", f"{len(late)}/{len(ev)} games still upgrading HOME mexes 3+ min after the reactor started: " + ", ".join(f"{n} reactor@{t0:.0f}m home mexup@{l:.0f}m" for n, t0, l in late[:3])
    return "OK", f"{len(late)}/{len(ev)} games with home mexes pending after the reactor"


def exp_home_not_discounted(games):
    """A mex inside the base is not priced as half-lost while nothing is hitting it."""
    ev = [g for g in games if g["minutes"] >= 15]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} games of 15+ min (need 3)"
    survs = []
    for g in ev:
        for m in re.finditer(r"apex: mexup t=\d+ at=[\d,]+ surv=([\d.]+) raw=[\d.]+ v=[\d.]+ homeD=(\d+)[^\n]*haz=([\d.]+)", g["text"]):
            if int(m.group(2)) <= 600 and float(m.group(3)) < 0.0005:
                survs.append(float(m.group(1)))
    if len(survs) < 10:
        return "NEED MORE", f"{len(survs)} home mexup readings with hazard 0 (need 10)"
    survs.sort()
    med = survs[len(survs) // 2]
    if med < 0.75:
        return "RED", f"median survival of a home mex with hazard 0 is {med:.2f} ({len(survs)} readings) -- the economy at home is discounted by a risk that is not there"
    return "OK", f"median home-mex survival {med:.2f} over {len(survs)} readings"


def exp_converters_on_overflow(games):
    """Energy overflowing for minutes is answered with converters, always."""
    ev = [g for g in games if g["minutes"] >= 15]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} games of 15+ min (need 3)"
    bad = []
    for g in ev:
        conv_min = set()
        for m in re.finditer(r"\[(\d+)\.\dm t\d+\] apex: exec t=\d+ \S+ #\d+ convert:", g["text"]):
            conv_min.add(int(m.group(1)))
        unanswered = 0
        for m in re.finditer(r"\[(\d+)\.\dm t\d+\] apex: energy cur=\d+/\d+ inc=(\d+) pull=\d+ use=\d+ excess=(-?\d+) [^\n]*eFull=1", g["text"]):
            mn, inc, exc = int(m.group(1)), float(m.group(2)), float(m.group(3))
            if inc > 100 and exc > 0.25 * inc and not any((mn + d) in conv_min for d in (-1, 0, 1)):
                unanswered += 1
        if unanswered >= 8:
            bad.append((g["name"], unanswered))
    if bad and len(bad) >= max(1, len(ev) // 3):
        return "RED", f"{len(bad)}/{len(ev)} games threw away 25%+ of energy for 8+ minutes with no converter ordered: " + ", ".join(f"{n} ({u} min)" for n, u in bad[:3])
    return "OK", f"{len(bad)}/{len(ev)} games with unanswered overflow"


def exp_builders_finish_walks(games):
    """A builder sent to a site is not aborted every 30 s on the walk."""
    ev = [g for g in games if g["minutes"] >= 15]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} games of 15+ min (need 3)"
    rates = []
    for g in ev:
        far = 0
        for m in re.finditer(r"apex: stuck -- \S+ #\d+ held \w+ progress=0\.00 toSite=(\d+) buildDist=(\d+)", g["text"]):
            if int(m.group(1)) > 4 * int(m.group(2)):
                far += 1
        rates.append((g["name"], far / max(g["minutes"], 1.0) * 30.0))
    bad = [(n, r) for n, r in rates if r > 30]
    if bad and len(bad) >= max(1, len(ev) // 3):
        return "RED", f"{len(bad)}/{len(ev)} games abort far walks {max(r for _, r in bad):.0f}+ times per 30 min -- builders walking away from what they were sent to"
    return "OK", "far-walk aborts per 30 min: " + ", ".join(f"{r:.0f}" for _, r in rates)


def exp_commander_moves(games):
    """The commander is never penned and never stands more than four minutes."""
    ev = [g for g in games if g["minutes"] >= 15]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} games of 15+ min (need 3)"
    penned = [g["name"] for g in ev if re.search(r"apex: unblock (?:arm|cor|leg)com\w* #\d+ walled in", g["text"])]
    frozen = []
    for g in ev:
        worst = 0.0
        for m in re.finditer(r"apex: com-still ([\d.]+)s", g["text"]):
            worst = max(worst, float(m.group(1)))
        if worst >= 240.0:
            frozen.append((g["name"], worst))
    if penned or frozen:
        parts = []
        if penned:
            parts.append(f"penned commander in {len(penned)} game(s): " + ", ".join(penned[:3]))
        if frozen:
            parts.append(f"commander still {max(w for _, w in frozen):.0f}s in {len(frozen)} game(s)")
        return "RED", "; ".join(parts)
    return "OK", f"no penned commander, longest stand-still under 240 s in {len(ev)} games"


def exp_t1_yields(games):
    """Once the enemy is T2, the T1 labs stop being the main producers."""
    ev = [g for g in games if g["minutes"] >= 25]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} mature games (need 3)"
    t1 = re.compile(r"\[(\d+\.\d)m t\d+\] apex: decide t=\d+ (?:arm|cor|leg)(?:lab|vp|hp) #\d+ -> produce:")
    t2 = re.compile(r"\[(\d+\.\d)m t\d+\] apex: decide t=\d+ (?:arm|cor|leg)(?:alab|avp|aap|ap) #\d+ -> produce:")
    bad = []
    for g in ev:
        t0 = None
        for m in re.finditer(r"\[(\d+\.\d)m t\d+\] apex: foetier [^\n]*above1=([\d.]+)", g["text"]):
            if float(m.group(2)) >= 0.8:
                t0 = float(m.group(1))
                break
        if t0 is None:
            continue
        n1 = sum(1 for m in t1.finditer(g["text"]) if float(m.group(1)) > t0 + 3.0)
        n2 = sum(1 for m in t2.finditer(g["text"]) if float(m.group(1)) > t0 + 3.0)
        if n2 > 0 and n1 > n2:
            bad.append((g["name"], n1, n2))
    if bad and len(bad) >= max(1, len(ev) // 3):
        return "RED", f"{len(bad)}/{len(ev)} games kept the T1 labs busier than the T2 ones after the enemy went T2: " + ", ".join(f"{n} T1={a} T2={b}" for n, a, b in bad[:3])
    return "OK", f"{len(bad)}/{len(ev)} games with T1 labs out-producing T2 after the enemy went T2"




def exp_first_t2_con_mohos(games):
    """The first advanced constructor's first job is an advanced extractor."""
    ev = [g for g in games if g["minutes"] >= 15]
    if len(ev) < 3:
        return "NEED MORE", f"{len(ev)} games of 15+ min (need 3)"
    pat = re.compile(r"\[f=(\d+)\][^\n]*apex: exec t=(\d+) (?:arm|cor|leg)(?:ack|acv|aca) #\d+ (\w+):(\w+) ")
    wrong = []
    seen = 0
    for g in ev:
        first = {}
        for m in pat.finditer(g["text"]):
            t = m.group(2)
            if t in g["apex"] and t not in first:
                first[t] = (int(m.group(1)) / 1800.0, m.group(3), m.group(4))
        for t, (mn, kind, d) in first.items():
            seen += 1
            if not d.endswith("moho"):
                wrong.append(f"{g['name']} t{t} {mn:.1f}m {kind}:{d}")
    if seen < 3:
        return "NEED MORE", f"{seen} first T2-con orders seen (need 3)"
    if wrong and len(wrong) >= max(1, seen // 3):
        return "RED", f"{len(wrong)}/{seen} first advanced constructors did something other than an advanced extractor first: " + ", ".join(wrong[:4])
    return "OK", f"{seen - len(wrong)}/{seen} first advanced constructors opened with a moho"

EXPECTATIONS = [
    ("first T2 con builds a moho first", exp_first_t2_con_mohos),
    ("home mexes upgrade before the reactor", exp_home_mex_upgrades),
    ("home ground is not discounted", exp_home_not_discounted),
    ("converters answer overflow", exp_converters_on_overflow),
    ("builders finish their walks", exp_builders_finish_walks),
    ("commander never penned or frozen", exp_commander_moves),
    ("T1 labs yield once the enemy is T2", exp_t1_yields),
    ("no rebuild of what we reclaimed", exp_no_flipflop),
    ("eco seat keeps to economy", exp_eco_seat),
    ("eco seat hands are turrets", exp_seat_hands),
    ("health", exp_health),
    ("personas up-only", exp_personas_up_only),
    ("escorts pair", exp_escorts),
    ("fodder goes forward", exp_spam_forward),
    ("army leaves home", exp_army_leaves),
    ("gantries produce", exp_gantry_used),
    ("plants supported by nanos", exp_plants_supported),
    ("bomber wing masses and strikes", exp_bombers),
    ("silo before the big gun", exp_silo_before_gun),
    ("anti-nuke depth late", exp_antinuke_depth),
    ("towers stand where we are hit", exp_towers_where_hit),
    ("outer mexes have guns", exp_outer_mex_guns),
    ("rez bots bounded", exp_rezbots),
    ("a 1.5x lead closes", exp_lead_closes),
]


def collect(dirs):
    games = []
    for d in dirs:
        p = Path(d)
        cands = sorted(glob.glob(str(p / "matches" / "*"))) + sorted(glob.glob(str(p / "*-s[0-9]*")))
        if (p / "infolog.txt").is_file():
            cands.append(str(p))
        for c in cands:
            if Path(c).is_dir():
                g = load_game(c)
                if g:
                    games.append(g)
    return games


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--min-minutes", type=float, default=MIN_MINUTES)
    a = ap.parse_args()
    games = collect(a.dirs)
    if not games:
        sys.exit("no games found")
    long = [g for g in games if mature(g, a.min_minutes)]
    print(f"expect: {len(games)} games pooled, {len(long)} of {a.min_minutes:.0f}+ min  "
          f"(outcomes {dict(Counter(g['outcome'] for g in games))})")
    red = 0
    for name, fn in EXPECTATIONS:
        status, detail = fn(games)
        red += status == "RED"
        print(f"  {status:9s} {name:<32} {detail}")
    print(f"{red} red flag(s)" if red else "no red flags")
    return 1 if red else 0


if __name__ == "__main__":
    raise SystemExit(main())
