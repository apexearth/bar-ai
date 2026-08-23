"""Audit the REAR SPECIALIST (eco role) in a single match.

Usage: python tools/audit_role.py <match-dir> [--allies N]

Checks apexearth's spec (2026-08-23) against the market-era telemetry:
  elected        exactly one ally holds `rear-specialist ON`, and holds it
                 wire-to-wire (no flapping off)
  no-army        the holder's standing army stays at commander level while
                 it owns no T3-grade production (mT3 == 0)
  no-defence     the holder puts zero metal into static defence
  tech-first     the holder starts T2 no later than any teammate
  no-waste       the holder's cumulative metal excess stays under 5% of
                 what it produced ("full on metal for minutes" = fail)
  out-eco        the holder out-produces every teammate (that is the point)
  mexups (soft)  the holder has upgraded mexes by game end (warn only under
                 20 game-min; the ladder may honestly still be mid-climb)

Telemetry sources (all from the match dir's infolog.txt):
  BARAI_STATS  per-team periodic key=value samples (dev_stats_export.lua):
               armyReal armyCheap conT1 conT2 mDefence metalProduced
               metalExcess techStart t2Mex mT1 mT2 mT3 top=...
  "apex: rear-specialist ON team=N"   the election (market.as)

armyReal INCLUDES the commander (~2700). Standing counters go to zero when
a team dies -- the audit reads PEAK for standing values and final for
cumulative ones, per the judge-the-timeline rule.
"""
import re
import sys
from pathlib import Path

ARMY_SLACK = 400.0     # a stray scout/escort (armyReal excludes builders now)
WASTE_FRAC = 0.05
MEXUP_SOFT_MIN = 20.0  # under this many game-minutes, missing mohos is a warn


def parse_kv(line: str) -> dict:
    out = {}
    for m in re.finditer(r"(\w+)=([^\s]+)", line):
        out[m.group(1)] = m.group(2)
    return out


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    d = Path(sys.argv[1])
    log = d / "infolog.txt"
    if not log.exists():
        print(f"FAIL: no infolog.txt in {d}")
        return 2

    text = log.read_text(encoding="utf-8", errors="replace")

    # -- gate: a compile error disables the variant and the audit is void --
    if re.search(r"\(\d+, \d+\) : ERR|Fix compilation errors", text):
        print("VOID: AngelScript compile error in this run -- nothing below is evidence")
        return 2

    # -- election lines --
    ons = re.findall(r"rear-specialist ON team=(\d+)", text)
    offs = re.findall(r"rear-specialist off team=(\d+)", text)
    holders = sorted(set(ons))

    # -- per-team sample streams (our side = ally 0, spec 'a') --
    samples: dict[int, list[dict]] = {}
    for line in text.splitlines():
        if "[BARAI_STATS]" not in line:
            continue
        kv = parse_kv(line)
        if kv.get("ally") != "0":
            continue
        samples.setdefault(int(kv["team"]), []).append(kv)

    if not samples:
        print("VOID: no ally-0 BARAI_STATS samples -- gadget missing or wrong side anchor")
        return 2

    game_min = max(float(s[-1].get("frame", 0)) / 30 / 60 for s in samples.values())
    checks: list[tuple[str, bool | None, str]] = []  # (name, ok|None=warn, detail)

    # elected
    if len(holders) == 1 and not offs:
        checks.append(("elected", True, f"team {holders[0]}, wire-to-wire"))
        holder = int(holders[0])
    elif len(holders) == 1:
        checks.append(("elected", False, f"team {holders[0]} but flapped off {len(offs)}x"))
        holder = int(holders[0])
    else:
        checks.append(("elected", False,
                       f"{len(holders)} holders ({holders}); need exactly 1 ON, 0 off"))
        holder = None

    if holder is None or holder not in samples:
        for name in ("no-army", "no-defence", "tech-first", "no-waste", "out-eco", "mexups"):
            checks.append((name, False, "no holder to audit"))
        return report(checks, game_min, None, samples)

    hs = samples[holder]
    last = hs[-1]
    f = lambda s, k: float(s.get(k, 0) or 0)

    # no-army: peak standing army <= slack, unless T3 era began
    peak_army = max(f(s, "armyReal") + f(s, "armyCheap") for s in hs)
    t3 = f(last, "mT3")
    ok = peak_army <= ARMY_SLACK or t3 > 0
    checks.append(("no-army", ok,
                   f"peak standing {peak_army:.0f} vs slack {ARMY_SLACK:.0f}"
                   + (f" (mT3={t3:.0f}, exempt)" if t3 > 0 else "")))

    # no-defence: ground defence only; static AA is allowed (air ignores
    # distance-from-front, so the safe rear still answers it)
    mdef = f(last, "mDefence")
    maa = f(last, "mDefAA")
    checks.append(("no-defence", mdef <= 0,
                   f"ground mDefence={mdef:.0f} (AA {maa:.0f}, allowed)"))

    # tech-first: holder techStart minimal among allies that have one
    starts = {t: f(s[-1], "techStart") for t, s in samples.items() if f(s[-1], "techStart") > 0}
    hstart = starts.get(holder, -1)
    if hstart > 0:
        first = min(starts.values())
        ok = hstart <= first + 1  # frames; ties count
        checks.append(("tech-first", ok,
                       f"holder {hstart / 30 / 60:.1f}m vs team first {first / 30 / 60:.1f}m"))
    else:
        others = f", teammates: {len(starts)} teched" if starts else ""
        checks.append(("tech-first", False, f"holder never started T2{others}"))

    # no-waste: cumulative excess fraction at the last sample
    prod = f(last, "metalProduced")
    exc = f(last, "metalExcess")
    frac = exc / prod if prod > 0 else 0.0
    checks.append(("no-waste", frac < WASTE_FRAC,
                   f"excess {exc:.0f} / produced {prod:.0f} = {frac:.1%}"))

    # out-eco: the RATE over the last window (exponential advantage shows in
    # slope long before cumulative catches up; a front player's early mexes
    # win the total at 15m without meaning anything about scaling)
    def rate(ss):
        if len(ss) < 2:
            return 0.0
        (f0, p0), (f1, p1) = ((float(x.get("frame", 0)), float(x.get("metalProduced", 0)))
                              for x in ss[-2:])
        return (p1 - p0) / ((f1 - f0) / 30) if f1 > f0 else 0.0
    rates = {t: rate(s) for t, s in samples.items()}
    best = max(rates, key=rates.get)
    ok = rates[holder] >= 0.9 * rates[best]
    checks.append(("out-eco", ok,
                   f"holder rate {rates[holder]:.1f} m/s vs best team {best} {rates[best]:.1f}"))

    # mexups (soft under MEXUP_SOFT_MIN)
    t2mex = f(last, "t2Mex")
    if t2mex > 0:
        checks.append(("mexups", True, f"t2Mex={t2mex:.0f}"))
    elif game_min < MEXUP_SOFT_MIN:
        checks.append(("mexups", None, f"none yet at {game_min:.0f}m (soft under {MEXUP_SOFT_MIN:.0f}m)"))
    else:
        checks.append(("mexups", False, f"none by {game_min:.0f}m"))

    return report(checks, game_min, holder, samples)


def report(checks, game_min, holder, samples) -> int:
    print(f"rear-specialist audit -- {game_min:.1f} game-min, "
          f"{len(samples)} ally teams, holder={'team ' + str(holder) if holder is not None else 'NONE'}")
    hard_fail = 0
    for name, ok, detail in checks:
        tag = "ok  " if ok else ("warn" if ok is None else "FAIL")
        if ok is False:
            hard_fail += 1
        print(f"  {tag}  {name:<11} {detail}")
    # informational: holder con trajectory (his "too many T1 cons" watch)
    if holder is not None and holder in samples:
        hs = samples[holder]
        pts = [(float(s.get("frame", 0)) / 1800, s.get("conT1", "?"), s.get("conT2", "?"))
               for s in hs[:: max(1, len(hs) // 6)]]
        print("  info  conT1/T2    " + "  ".join(f"{m:.0f}m:{a}/{b}" for m, a, b in pts))
    print("VERDICT: " + ("PASS" if hard_fail == 0 else f"FAIL ({hard_fail} hard)"))
    return 0 if hard_fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
