"""Print an economy curve, one row per game minute, from any infolog.

Reads three sources and prints whichever it finds:
  [BARAI_WASTE]  cumulative metal/energy made per team (dev_team_income.lua,
                 loads in every game) -> income per minute by difference
  [BARAI_STATS]  standing counts (dev_stats_export.lua, needs dev_stats=1)
  [BARAI_CENSUS] standing counts in a REPLAY (dev_replay_census.lua)

    python tools/canon.py <match dir | infolog path> [--team 0] [--every 2]

The canon scenario (apexearth 2026-09-08): 1v1 vs NullAI on Comet Catcher
Remake 1.8, --handicap 50, --speed 5, --modoption apex_eco_only=1. His own
reference curve is in memory `canon-eco-game`.
"""
import argparse
import re
import sys
from pathlib import Path

KEYS = [("mex", ("armmex", "cormex", "legmex")), ("moho", ("armmoho", "cormoho", "legmoho")),
        ("sol", ("armsolar", "corsolar", "legsolar")), ("adv", ("armadvsol", "coradvsol", "legadvsol")),
        ("wind", ("armwin", "corwin", "legwin")), ("fus", ("armfus", "corfus", "legfus")),
        ("afus", ("armafus", "corafus", "legafus")), ("makr", ("armmakr", "cormakr", "legmakr")),
        ("mmkr", ("armmmkr", "cormmkr", "legmmkr")), ("nano", ("armnanotc", "cornanotc", "legnanotc")),
        ("con1", ("armck", "corck", "legck", "armcv", "corcv", "legcv")),
        ("con2", ("armack", "corack", "legack", "armacv", "coracv", "legacv")),
        ("air", ("armca", "corca", "legca", "armaca", "coraca", "legaca")),
        ("afus3", ("armafust3", "corafust3")),
        ("mmkr3", ("armmmkrt3", "cormmkrt3"))]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run")
    ap.add_argument("--team", type=int, default=0)
    ap.add_argument("--every", type=int, default=2)
    a = ap.parse_args()
    p = Path(a.run)
    log = p if p.is_file() else (p / "infolog.txt")
    if not log.exists():
        cands = sorted(Path("matches").glob(f"*{a.run}*"))
        if cands:
            log = cands[-1] / "infolog.txt"
    if not log.exists():
        print("no infolog at", log)
        return 1
    text = log.read_text("utf-8", errors="replace")
    made = {}
    for m in re.finditer(r"\[BARAI_WASTE\] frame=(\d+) team=(\d+) mWaste=(\d+) mMade=(\d+) eWaste=(\d+) eMade=(\d+)", text):
        if int(m.group(2)) == a.team:
            made[int(m.group(1)) // 1800] = (int(m.group(4)), int(m.group(6)), int(m.group(3)))
    counts = {}
    for ln in text.split(chr(10)):
        if "[BARAI_STATS]" not in ln and "[BARAI_CENSUS]" not in ln:
            continue
        fm = re.search(r"frame=([0-9]+)", ln)
        tm = re.search(r"team=([0-9]+)", ln)
        um = re.search(r"unit(?:s|Count)=([^ ]*)", ln)
        if not (fm and tm and um) or int(tm.group(1)) != a.team:
            continue
        uc = dict((k, int(v)) for k, v in (q.split(":") for q in um.group(1).split(",") if ":" in q))
        counts[int(fm.group(1)) // 1800] = uc
    if not made and not counts:
        print("no BARAI_WASTE / STATS / CENSUS lines for team", a.team)
        return 1
    head = f"{'min':>3} {'m/s':>6} {'e/s':>7} {'waste':>6} | " + " ".join(f"{k:>4}" for k, _ in KEYS)
    print(head)
    prev = (0, 0)
    for minute in sorted(set(made) | set(counts)):
        row = f"{minute:>3}"
        if minute in made:
            mm, em, w = made[minute]
            pm, pe = prev
            row += f" {(mm - pm) / 60:>6.0f} {(em - pe) / 60:>7.0f} {w:>6}"
            prev = (mm, em)
        else:
            row += f" {'':>6} {'':>7} {'':>6}"
        row += " | "
        uc = counts.get(minute)
        row += " ".join(f"{sum(uc.get(n, 0) for n in names):>4}" if uc else f"{'':>4}" for _, names in KEYS)
        if minute % a.every == 0 or minute == max(set(made) | set(counts)):
            print(row)
    return 0


if __name__ == "__main__":
    sys.exit(main())
