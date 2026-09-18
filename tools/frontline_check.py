#!/usr/bin/env python3
"""Two things apexearth asks for every game, measured from position telemetry:

  1. EARLY MEX GUARDING -- "1 sentry turret guarding each of our mexes at
     least", and not "tons of turrets around mexes in the back of the map".
     Per snapshot: the share of standing extractors with a ground tower whose
     range covers them, and the worst stack (towers on one mex).

  2. THE FRONT LINE -- "a clear line of towers across the map", between our
     base and the enemy, and durable enough that the base behind it lives.
     Per snapshot: towers projected onto the home->nearest-enemy axis (0 = our
     start, 1 = theirs); a tower is FORWARD at fwd >= FRONT_LO. The line is
     the forward towers' lateral spread, their metal, and the sensors/nanos
     standing among them. Durability comes from [BARAI_DEATH]: how many
     forward towers died, and how much non-defence metal died BEHIND the
     line's median once it stood.

Everything is read from stdout.txt ([BARAI_POS] every 3600 frames,
[BARAI_START], [BARAI_DEATH]) -- never the shared infolog. Only Apex teams are
scored; the opponent's rows are printed for comparison with --all.

Usage:
    python tools/frontline_check.py <match-dir> [--all] [--json]
    python tools/frontline_check.py <match-dir> --assert     # exit 1 on a miss

The --assert thresholds are the regression contract (see THRESHOLDS); the
runner that applies them across a set of games is tools/test_frontline.py.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402
from defence_pos import ai_teams  # noqa: E402

# `part=a/b` since the census ships in short lines (31eca356); parts of one
# frame are concatenated.
POS_RE = re.compile(r"\[BARAI_POS\] team=(\d+) ally=(\d+) frame=(\d+) n=(\d+)(?: part=\d+/\d+)? (\S*)")
START_RE = re.compile(r"\[BARAI_START\] team=(\d+) x=(-?\d+) z=(-?\d+)")
DEATH_RE = re.compile(
    r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\S+) cost=(\d+) "
    r"x=(-?\d+) z=(-?\d+) .*?built=(\d) mob=(\d)")

FRONT_LO = 0.25       # forward fraction where "between us and them" begins
FRONT_HI = 0.80       # past this it is their base, not our line
LAT_MAX = 0.60        # lateral bound, as a fraction of the separation
SENSOR_R = 900.0      # a radar/jammer/nano within this of a forward tower fortifies it
STACK_R = 250.0       # towers this close to an extractor were built AT it, not around the base

# The regression contract. Snapshot minutes are the [BARAI_POS] cadence.
THRESHOLDS = {
    # Minute 8, not 6: at +50% the opening has made 5-10 builder decisions
    # by minute six, the lab and the first solars among them, so "a gun per
    # mex" cannot be judged yet; by eight it can (and stock BARb hard reads
    # 0.0-0.5 there).
    "guard_min": 8,          # by this minute...
    "guard_frac": 0.6,       # ...this share of standing mexes has its own gun
    "stack_max": 2,          # and no mex carries more than this many by then
    "plant_min": 4,          # the first factory stands by this minute (defence
                             # must not eat the opening -- measured: five towers
                             # before the lab, lab at 8.3 min, game lost)
    # Minute 16, not 14: the human meta he described caps the mid mexes and
    # THEN walls, and in these games the expansion runs to minute 12-16; the
    # line stood by 10-16 in every passing game and never by 14 in a third
    # of them.
    # ...then 18 once walks were priced at the builder's own output (commit
    # after 68c3b2e): the line forms two minutes later and the zigzags stop.
    "line_min": 18,          # by this minute...
    "line_towers": 4,        # ...at least this many towers stand forward
    "line_width": 800.0,     # spanning at least this many elmos laterally
    "line_metal": 300.0,     # and worth at least this much metal (four LLTs)
}


# --- game tree lookups ------------------------------------------------------

_DEF_CACHE = None


def unit_classes():
    """def -> ('mex' | 'gdef' | 'aa' | 'radar' | 'jam' | 'nano' | 'other', range, cost)

    Read from the pinned game tree, never from a name list: a ground tower is
    a *DefenceOffence unit with a weapon that is not to-air only; an
    extractor is anything with extractsmetal > 0.
    """
    global _DEF_CACHE
    if _DEF_CACHE is not None:
        return _DEF_CACHE
    env = bar_env.load()
    root = env.game_sdd / "units"
    out = {}
    for p in root.rglob("*.lua"):
        try:
            txt = p.read_text("utf-8", errors="replace")
        except OSError:
            continue
        name = p.stem.lower()
        seg = p.parent.as_posix()
        cost = 0.0
        m = re.search(r"\bmetalcost\s*=\s*([\d.]+)", txt)
        if m:
            cost = float(m.group(1))
        ranges = [float(r) for r in re.findall(r"\brange\s*=\s*([\d.]+)", txt)]
        rng = max(ranges) if ranges else 0.0
        kind = "other"
        em = re.search(r"\bextractsmetal\s*=\s*([\d.]+)", txt)
        if em and float(em.group(1)) > 0:
            kind = "mex"
        elif "DefenceOffence" in seg or "SeaDefence" in seg:
            # BAR marks anti-air by the weapon's target category, not a flag.
            cats = re.findall(r"onlytargetcategory\s*=\s*\"([^\"]*)\"", txt)
            nweap = len(re.findall(r"\bdef\s*=\s*\"", txt))
            if nweap == 0:
                kind = "other"          # a wall, a dragon's tooth
            elif cats and all(c.strip().upper() == "VTOL" for c in cats) and len(cats) >= nweap:
                kind = "aa"
            else:
                kind = "gdef"
        elif re.search(r"\bradardistancejam\s*=\s*[1-9]", txt):
            kind = "jam"
        elif re.search(r"\bradardistance\s*=\s*[1-9]", txt):
            kind = "radar"
        elif re.search(r"\bbuilddistance\s*=", txt) and "nanotc" in name:
            kind = "nano"
        elif "Factories" in seg or "Factory" in seg:
            kind = "plant"
        out[name] = (kind, rng, cost)
    _DEF_CACHE = out
    return out


# --- telemetry --------------------------------------------------------------

def parse_units(blob):
    units = []
    for tok in blob.split(","):
        parts = tok.split(":")
        if len(parts) >= 3:
            try:
                units.append((parts[0].lower(), float(parts[1]), float(parts[2])))
            except ValueError:
                pass
    return units


def read(match_dir: Path):
    text = (match_dir / "stdout.txt").read_text("utf-8", errors="replace")
    starts, ally_of = {}, {}
    snaps = defaultdict(dict)     # frame -> team -> units
    deaths = []
    for line in text.splitlines():
        m = START_RE.search(line)
        if m:
            starts[int(m.group(1))] = (float(m.group(2)), float(m.group(3)))
            continue
        m = POS_RE.search(line)
        if m:
            team, ally, frame = int(m.group(1)), int(m.group(2)), int(m.group(3))
            ally_of[team] = ally
            snaps[frame][team] = snaps[frame].get(team, []) + parse_units(m.group(5))
            continue
        m = DEATH_RE.search(line)
        if m:
            deaths.append({
                "frame": int(m.group(1)), "team": int(m.group(2)),
                "unit": m.group(3).lower(), "cost": float(m.group(4)),
                "x": float(m.group(5)), "z": float(m.group(6)),
                "built": m.group(7) == "1", "mob": m.group(8) == "1",
            })
    return starts, ally_of, snaps, deaths


def axis_for(team, starts, ally_of):
    """home, unit direction and separation to the NEAREST enemy start."""
    home = starts.get(team)
    if home is None:
        return None
    best = None
    for t, p in starts.items():
        if ally_of.get(t) == ally_of.get(team) or t == team:
            continue
        d = math.hypot(p[0] - home[0], p[1] - home[1])
        if best is None or d < best[0]:
            best = (d, p)
    if best is None or best[0] < 1:
        return None
    sep, foe = best
    return home, ((foe[0] - home[0]) / sep, (foe[1] - home[1]) / sep), sep


def project(home, dirv, sep, x, z):
    rx, rz = x - home[0], z - home[1]
    along = (rx * dirv[0] + rz * dirv[1]) / sep
    lat = (rx * dirv[1] - rz * dirv[0]) / sep
    return along, lat


# --- scoring ----------------------------------------------------------------

def score_snapshot(units, axis, classes):
    home, dirv, sep = axis
    mexes, towers, sensors = [], [], []
    for name, x, z in units:
        kind, rng, cost = classes.get(name, ("other", 0.0, 0.0))
        if kind == "mex":
            mexes.append((x, z))
        elif kind == "gdef":
            towers.append((name, x, z, rng, cost))
        elif kind in ("radar", "jam", "nano"):
            sensors.append((kind, x, z))
    # 1. guarding
    guarded, stacks = 0, []
    for mx, mz in mexes:
        n = sum(1 for _, tx, tz, rng, _ in towers
                if math.hypot(tx - mx, tz - mz) <= max(rng, 1.0))
        stacks.append(sum(1 for _, tx, tz, _, _ in towers
                          if math.hypot(tx - mx, tz - mz) <= STACK_R))
        if n > 0:
            guarded += 1
    # 2. the line
    fwd = []
    for name, x, z, rng, cost in towers:
        along, lat = project(home, dirv, sep, x, z)
        if FRONT_LO <= along <= FRONT_HI and abs(lat) <= LAT_MAX:
            fwd.append((name, x, z, along, lat, cost))
    width = 0.0
    if len(fwd) >= 2:
        lats = [f[4] * sep for f in fwd]
        width = max(lats) - min(lats)
    fort = {"radar": 0, "jam": 0, "nano": 0}
    for kind, sx, sz in sensors:
        if any(math.hypot(sx - f[1], sz - f[2]) <= SENSOR_R for f in fwd):
            fort[kind] += 1
    plants = sum(1 for name, _, _ in units
                 if classes.get(name, ("other", 0.0, 0.0))[0] == "plant")
    all_along = [project(home, dirv, sep, x, z)[0] for _, x, z, _, _ in towers]
    return {
        "mexes": len(mexes), "guarded": guarded,
        "guard_frac": (guarded / len(mexes)) if mexes else None,
        "stack_max": max(stacks) if stacks else 0,
        "stacked": sum(1 for s in stacks if s > THRESHOLDS["stack_max"]),
        "towers": len(towers), "tower_metal": sum(t[4] for t in towers),
        "fwd_towers": len(fwd), "fwd_metal": sum(f[5] for f in fwd),
        "fwd_width": width,
        "fwd_median": statistics.median([f[3] for f in fwd]) if fwd else None,
        "tower_fwd_median": statistics.median(all_along) if all_along else None,
        "radar": fort["radar"], "jam": fort["jam"], "nano": fort["nano"],
        "plants": plants,
    }


def durability(team, deaths, axis, classes, line_from_frame, line_pos):
    """what died: forward towers, and non-defence metal behind the line."""
    home, dirv, sep = axis
    fwd_dead, fwd_dead_m, behind_m, behind_n = 0, 0.0, 0.0, 0
    for d in deaths:
        if d["team"] != team or d["mob"] or not d["built"]:
            continue
        kind, _, _ = classes.get(d["unit"], ("other", 0, 0))
        along, lat = project(home, dirv, sep, d["x"], d["z"])
        if kind == "gdef" and FRONT_LO <= along <= FRONT_HI and abs(lat) <= LAT_MAX:
            fwd_dead += 1
            fwd_dead_m += d["cost"]
        elif kind != "gdef" and line_from_frame is not None \
                and d["frame"] >= line_from_frame and along < line_pos:
            behind_m += d["cost"]
            behind_n += 1
    return {"fwd_dead": fwd_dead, "fwd_dead_metal": fwd_dead_m,
            "behind_dead": behind_n, "behind_dead_metal": behind_m}


def analyse(match_dir: Path, everyone=False):
    classes = unit_classes()
    starts, ally_of, snaps, deaths = read(match_dir)
    labels = ai_teams((match_dir / "script.txt").read_text("utf-8", errors="replace")) \
        if (match_dir / "script.txt").exists() else {}
    teams = sorted(ally_of)
    if not everyone:
        teams = [t for t in teams if labels.get(t, "").startswith("Apex")]
    report = {}
    for team in teams:
        axis = axis_for(team, starts, ally_of)
        if axis is None:
            continue
        rows = []
        line_from, line_pos = None, None
        for frame in sorted(snaps):
            units = snaps[frame].get(team)
            if units is None:
                continue
            s = score_snapshot(units, axis, classes)
            s["frame"] = frame
            s["min"] = frame / 1800.0
            rows.append(s)
            if line_from is None and s["fwd_towers"] >= THRESHOLDS["line_towers"] \
                    and s["fwd_width"] >= THRESHOLDS["line_width"]:
                line_from, line_pos = frame, s["fwd_median"]
        dur = durability(team, deaths, axis, classes, line_from, line_pos)
        report[team] = {"ai": labels.get(team, "?"), "ally": ally_of[team],
                        "sep": axis[2], "rows": rows, "line_from_min":
                        (line_from / 1800.0) if line_from else None, **dur}
    return report


def outcome(match_dir: Path):
    """(won_by_apex, game_minutes) from result.json, or (None, None)."""
    p = match_dir / "result.json"
    if not p.exists():
        return None, None
    try:
        r = json.loads(p.read_text("utf-8"))
    except (OSError, ValueError):
        return None, None
    res = r.get("result", {})
    specs = res.get("winner_specs") or []
    won = any(s.startswith("Apex") for s in specs) if specs else None
    return won, res.get("game_minutes")


def verdict(rep, won=None):
    """(ok, reasons, skipped) against THRESHOLDS, per team.

    A game Apex WON before a snapshot minute is not a miss on that metric --
    the enemy was dead -- so it is listed in `skipped` instead. A game that
    ended early any other way keeps its miss: an early loss is the failure
    this exists to catch.
    """
    T = THRESHOLDS
    out = {}
    for team, r in rep.items():
        reasons, skipped = [], []
        p = [row for row in r["rows"] if row["min"] >= T["plant_min"] - 0.01]
        if p and p[0]["plants"] == 0:
            reasons.append(f"plant: no factory at {p[0]['min']:.0f}m")
        g = [row for row in r["rows"] if row["min"] >= T["guard_min"] - 0.01]
        if g:
            row = g[0]
            if row["guard_frac"] is not None and row["guard_frac"] < T["guard_frac"]:
                reasons.append(f"guard {row['guarded']}/{row['mexes']} at {row['min']:.0f}m")
            if row["stack_max"] > T["stack_max"]:
                reasons.append(f"stack {row['stack_max']} on one mex at {row['min']:.0f}m")
        elif won:
            skipped.append("guard")
        else:
            reasons.append("guard: no snapshot at guard_min")
        l = [row for row in r["rows"] if row["min"] >= T["line_min"] - 0.01]
        if l:
            row = l[0]
            if row["fwd_towers"] < T["line_towers"] or row["fwd_width"] < T["line_width"] \
                    or row["fwd_metal"] < T["line_metal"]:
                reasons.append(f"line {row['fwd_towers']} towers/{int(row['fwd_width'])} wide/"
                               f"{int(row['fwd_metal'])}m at {row['min']:.0f}m")
        elif won:
            skipped.append("line")
        else:
            reasons.append("line: no snapshot at line_min")
        out[team] = (not reasons, reasons, skipped)
    return out


def show(rep, match_dir):
    print(f"== {match_dir}")
    for team, r in rep.items():
        print(f"-- team {team} ({r['ai']}) ally={r['ally']} sep={int(r['sep'])}"
              f"  line from {r['line_from_min']:.0f}m" if r["line_from_min"] else
              f"-- team {team} ({r['ai']}) ally={r['ally']} sep={int(r['sep'])}  no line yet")
        print("   min  mex guard stk | twr   metal | fwd  metal width med | rad jam nano | plant")
        for row in r["rows"]:
            gf = "-" if row["guard_frac"] is None else f"{row['guard_frac']:.2f}"
            med = "-" if row["fwd_median"] is None else f"{row['fwd_median']:.2f}"
            print(f"  {row['min']:4.0f}  {row['mexes']:3d}  {gf:>4}  {row['stack_max']:2d} |"
                  f" {row['towers']:3d}  {int(row['tower_metal']):6d} |"
                  f" {row['fwd_towers']:3d} {int(row['fwd_metal']):6d} {int(row['fwd_width']):5d} {med:>4} |"
                  f" {row['radar']:3d} {row['jam']:3d} {row['nano']:4d} | {row['plants']:3d}")
        print(f"   died: forward towers {r['fwd_dead']} ({int(r['fwd_dead_metal'])}m);"
              f" behind the line {r['behind_dead']} buildings ({int(r['behind_dead_metal'])}m)")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("match", nargs="+")
    ap.add_argument("--all", action="store_true", help="score every team, not only Apex")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--assert", dest="assert_", action="store_true",
                    help="exit 1 if any Apex team misses THRESHOLDS")
    a = ap.parse_args()
    fail = 0
    for m in a.match:
        md = Path(m)
        if md.is_dir() and (md / "matches").is_dir():
            dirs = sorted(p for p in (md / "matches").iterdir() if (p / "stdout.txt").exists())
        else:
            dirs = [md]
        for d in dirs:
            rep = analyse(d, a.all)
            if a.json:
                print(json.dumps({"match": str(d), "teams": rep}, default=str))
                continue
            show(rep, d)
            if a.assert_:
                won, _ = outcome(d)
                for team, (ok, why, skipped) in verdict(rep, won).items():
                    tag = "PASS" if ok else "FAIL"
                    note = ("" if ok else ": " + "; ".join(why))
                    if skipped:
                        note += "  (won before: " + ", ".join(skipped) + ")"
                    print(f"   {tag} team {team}{note}")
                    if not ok:
                        fail += 1
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
