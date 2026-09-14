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
        for m in re.finditer(r"apex: rear-specialist ON team=(\d+)", g["text"]):
            t = m.group(1)
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


EXPECTATIONS = [
    ("eco seat keeps to economy", exp_eco_seat),
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
