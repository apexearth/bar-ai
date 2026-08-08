#!/usr/bin/env python3
"""Did anything STOP firing?

The recurring failure this exists to catch: a new rule is added, it is confirmed
firing, and it silently starves an existing one. It happened three times in one
session -- the mex guard fell 32 -> 9 when the home crew was added (2 home + 3 mex
consumed the whole ~5-constructor pool, leaving eco=0), then 18 -> 6 when
HomeEnergy was placed ahead of it in the ladder. Each time the new thing was
verified and the broken thing was not, and each time apexearth found it by
watching rather than the harness finding it by measuring.

Checking the change you just made is not enough. Constructors are a fixed pool and
task selection is an ordered ladder, so every new claim on either can only be paid
for out of something else.

    python tools/behaviour_check.py <match-dir>      # count, compare to baseline
    python tools/behaviour_check.py <match-dir> --save   # accept as the new baseline

Counts are per game-minute so runs of different lengths compare.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "tools" / "behaviour_baseline.json"

# Marker -> substring searched in the infolog. Add a line here whenever a rule
# gains a log message; a rule with no marker cannot be regression-checked.
MARKERS = {
    "mex_guard": "apex: mex guard",
    "home_energy": "apex: home energy",
    "eco_nano": "apex: eco nano",
    "eco_converter": "apex: eco converter block",
    "eco_fusion": "apex: eco fusion",
    "obsolete_reclaim": "apex: obsolete-reclaim",
    "surplus_gantry": "apex: surplus gantry",
    "nuke_silo": "apex: nuke silo",
    "pulsar": "apex: pulsar",
    "crew_front": "apex: crew front",
    "crew_mex_done": "mex job done",
    "assist": "apex: assist",
    "gantry": "building T3 gantry",
    "engage": "engage TAKE",
    "air_rearm": "air strike spent",
    "base_grid": "apex: base area",
}

# Below this many per game-minute a marker counts as "not really firing", so a
# drop to zero is reported even when the baseline was itself small.
NOISE = 0.02


def scan(match_dir: Path):
    log = match_dir / "infolog.txt"
    if not log.exists():
        sys.exit(f"no infolog in {match_dir}")
    text = log.read_text(errors="ignore")

    frames = [int(m) for m in re.findall(r"\[f=(\d+)\]", text)]
    minutes = max(frames) / 30.0 / 60.0 if frames else 0.0
    if minutes < 1.0:
        sys.exit(f"game too short to judge ({minutes:.1f} min)")

    errs = len(re.findall(r"\.as \(\d+, \d+\) : ERR", text))
    counts = {k: text.count(v) for k, v in MARKERS.items()}
    return minutes, errs, counts


def main() -> int:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    match_dir = Path(sys.argv[1])
    save = "--save" in sys.argv

    minutes, errs, counts = scan(match_dir)
    rates = {k: v / minutes for k, v in counts.items()}

    print(f"{match_dir.name}  ({minutes:.1f} game-min)")
    if errs:
        print(f"  !! {errs} AngelScript errors -- the variant is DISABLED, "
              f"counts below are meaningless")
        return 2

    if save:
        BASELINE.write_text(json.dumps(rates, indent=2, sort_keys=True) + "\n")
        print(f"  baseline saved ({len(rates)} markers)")
        return 0

    if not BASELINE.exists():
        print("  no baseline yet -- run with --save once a run looks right")
        for k in sorted(rates):
            print(f"    {k:18s} {counts[k]:5d}  ({rates[k]:.2f}/min)")
        return 0

    base = json.loads(BASELINE.read_text())
    regressed, gained = [], []
    for k in sorted(MARKERS):
        was, now = base.get(k, 0.0), rates[k]
        if was > NOISE and now < was * 0.5:
            regressed.append((k, was, now, counts[k]))
        elif now > max(was, NOISE) * 2:
            gained.append((k, was, now))

    for k, was, now, n in regressed:
        print(f"  DROPPED  {k:18s} {was:6.2f}/min -> {now:5.2f}/min  (n={n})")
    for k, was, now in gained:
        print(f"  up       {k:18s} {was:6.2f}/min -> {now:5.2f}/min")
    if not regressed:
        print("  no behaviour stopped firing")
    return 1 if regressed else 0


if __name__ == "__main__":
    sys.exit(main())
