#!/usr/bin/env python3
"""What our air did in a game: planes built by minute, what they killed, what died.

    python tools/airaudit.py <match|tournament> [...]   # one row per match, then totals
    python tools/airaudit.py <match> --minutes          # per-minute build/kill table

Planes are classed from the game tree's unit files (canfly + the description:
Bomber / Gunship / Fighter / Construction / Scout), never from a name list.
"Our side" is every team running an Apex spec (result.json, S16-safe).
Eco = a dead structure (mob=0) that is not armed: mex, energy, converter, lab,
nano; the cost is the metal killed.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

import bar_env
from unitdef import trees

KV = re.compile(r"(\w+)=(\S+)")
_CLASS: dict[str, str] = {}
_ARMED: dict[str, bool] = {}


def _load():
    if _CLASS:
        return
    env = bar_env.load() if hasattr(bar_env, "load") else bar_env.env()
    game, _ = trees(env)
    desc = game.lang()["descriptions"]
    for p in game.files():
        name = p.stem.lower()
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        _ARMED[name] = bool(re.search(r"\bweapondefs\s*=\s*\{\s*\w", text, re.I))
        if not re.search(r"\bcanfly\s*=\s*true", text, re.I):
            continue
        d = (desc.get(name) or "").lower()
        if "bomber" in d:
            c = "bomber"
        elif "gunship" in d or "fortress" in d:
            c = "gunship"
        elif "fighter" in d or "interceptor" in d:
            c = "fighter"
        elif "constructor" in d or "engineer" in d:
            c = "aircon"
        elif "transport" in d:
            c = "transport"
        else:
            c = "airother"
        _CLASS[name] = c


def cls(unit: str) -> str:
    _load()
    return _CLASS.get(unit.lower(), "")


def armed(unit: str) -> bool:
    _load()
    return _ARMED.get(unit.lower(), False)


def matches(paths):
    for a in paths:
        p = Path(a)
        if (p / "infolog.txt").exists():
            yield p
        elif (p / "matches").is_dir():
            for m in sorted((p / "matches").iterdir()):
                if (m / "infolog.txt").exists():
                    yield m


def ours(m: Path) -> set[int]:
    try:
        r = json.loads((m / "result.json").read_text())
    except Exception:  # noqa: BLE001
        return {0}
    return {t["team"] for t in r.get("teams", []) if "Apex" in t.get("spec", "")
            or "apex" in t.get("shortName", "").lower()}


def winner(m: Path, us: set[int]) -> str:
    try:
        r = json.loads((m / "result.json").read_text())
        w = set(r["result"]["winners"])
        return "W" if w & us else ("L" if w else "-")
    except Exception:  # noqa: BLE001
        return "?"


def audit(m: Path, per_minute=False, until=1e9):
    us = ours(m)
    built = defaultdict(int)
    built_min = defaultdict(lambda: defaultdict(int))
    lost = defaultdict(int)
    kills_eco = 0.0
    kills_army = 0.0
    kills_by = defaultdict(float)
    eco_kill_min = defaultdict(float)
    air_lines = defaultdict(int)
    end_min = 0.0
    with open(m / "infolog.txt", encoding="utf-8", errors="replace") as f:
        for line in f:
            fm = re.search(r"\[f=(\d+)\]", line)
            if fm and int(fm.group(1)) > until * 1800:
                break
            if "[BARAI_PROD]" in line:
                kv = dict(KV.findall(line))
                if int(kv.get("team", -1)) in us:
                    c = cls(kv["unit"])
                    if c:
                        built[c] += 1
                        built_min[int(float(kv["min"]))][c] += 1
            elif "[BARAI_DEATH]" in line:
                kv = dict(KV.findall(line))
                fr = int(kv.get("frame", 0))
                end_min = max(end_min, fr / 1800)
                vt = int(kv.get("team", -1))
                at = int(kv.get("atkteam", -1))
                if vt in us:
                    c = cls(kv["unit"])
                    if c:
                        lost[c] += 1
                elif at in us:
                    ac = cls(kv.get("atk", ""))
                    if ac in ("bomber", "gunship", "fighter"):
                        cost = float(kv.get("cost", 0))
                        if kv.get("mob") == "0" and not armed(kv["unit"]):
                            kills_eco += cost
                            eco_kill_min[int(fr / 1800)] += cost
                        else:
                            kills_army += cost
                        kills_by[ac] += cost
            elif "apex: air" in line:
                mm = re.search(r"apex: (air \w+(?: \w+)?)", line)
                if mm:
                    air_lines[mm.group(1)] += 1
    row = {"match": m.name[:60], "res": winner(m, us), "min": round(end_min, 1),
           "bomber": built["bomber"], "gunship": built["gunship"],
           "fighter": built["fighter"], "aircon": built["aircon"],
           "lostB": lost["bomber"], "lostG": lost["gunship"], "lostF": lost["fighter"],
           "ecoKill": int(kills_eco), "armyKill": int(kills_army),
           "byB": int(kills_by["bomber"]), "byG": int(kills_by["gunship"]),
           "lines": dict(air_lines)}
    if per_minute:
        print(f"{'min':>4} {'bomb':>5} {'gun':>5} {'fight':>5} {'acon':>5} {'ecoKill':>8}")
        for k in sorted(set(built_min) | set(eco_kill_min)):
            b = built_min[k]
            print(f"{k:>4} {b['bomber']:>5} {b['gunship']:>5} {b['fighter']:>5} "
                  f"{b['aircon']:>5} {int(eco_kill_min[k]):>8}")
    return row


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--minutes", action="store_true")
    ap.add_argument("--until", type=float, default=1e9, help="game minute to stop reading at")
    ap.add_argument("--lines", action="store_true", help="show apex: air line counts")
    a = ap.parse_args()
    rows = [audit(m, a.minutes, a.until) for m in matches(a.paths)]
    cols = ["res", "min", "bomber", "gunship", "fighter", "aircon", "lostB", "lostG",
            "lostF", "ecoKill", "armyKill", "byB", "byG"]
    print(f"{'match':<44} " + " ".join(f"{c:>7}" for c in cols))
    tot = defaultdict(float)
    for r in rows:
        print(f"{r['match'][-44:]:<44} " + " ".join(f"{str(r[c]):>7}" for c in cols))
        for c in cols[2:]:
            tot[c] += r[c]
        if a.lines:
            print("    ", r["lines"])
    if len(rows) > 1:
        print(f"{'TOTAL n=' + str(len(rows)):<44} {'':>7} {'':>7} "
              + " ".join(f"{int(tot[c]):>7}" for c in cols[2:]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
