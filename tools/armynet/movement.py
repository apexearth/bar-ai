#!/usr/bin/env python3
"""Where a unit can go, from the game's own movement definitions (his 11-19: "understand which units can move on land
vs water vs both").

    movement(name) -> (land, water, under, slope, wade)
      land   can stand on dry ground (ground units, hovers, aircraft)
      water  can cross the water's surface (ships, hovers, aircraft)
      under  can go under water (submarines; amphibious units walking the sea floor)
      slope  steepest slope it can climb / 90 (1 for ships and aircraft: not their limit)
      wade   how deep a ground unit can wade, log-scaled to 1 at amphibious (5000); 1 for ships, hovers, aircraft

Read from BAR.sdd: gamedata/movedefs.lua (the limits per movement class, its DEPTH / SLOPE / CRUSH constants
resolved) and units/**.lua (each unit's movementclass, canfly). The engine names the kind: a class with "boat" or
"ship" in its name moves as a ship, "hover" as a hovercraft, anything else on the ground.

    python tools/armynet/movement.py armpt corsub armamph cormh corak     # print a few
"""
import json
import math
import re
import sys
from functools import lru_cache
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
from paths import data_dir  # noqa: E402
CACHE = data_dir() / "movement.json"
AMPHIBIOUS = 5000.0


def _sdd():
    import bar_env
    return Path(bar_env.load().game_sdd)


def _consts(text, name):
    m = re.search(r"local %s = \{(.*?)\n\}" % name, text, re.S)
    return {k: float(v) for k, v in re.findall(r"(\w+)\s*=\s*(-?[\d.]+)", m.group(1))} if m else {}


def _value(expr, consts):
    expr = expr.strip().rstrip(",")
    total = 0.0
    for sign, term in re.findall(r"([+-]?)\s*([\w.]+)", expr):
        if "." in term and not term.replace(".", "").isdigit():
            table, key = term.split(".", 1)
            v = consts.get(table, {}).get(key)
            if v is None:
                return None
        else:
            try:
                v = float(term)
            except ValueError:
                return None
        total += -v if sign == "-" else v
    return total


def _build():
    sdd = _sdd()
    text = (sdd / "gamedata" / "movedefs.lua").read_text(errors="replace")
    consts = {t: _consts(text, t) for t in ("DEPTH", "SLOPE", "CRUSH")}
    classes = {}
    for name, body in re.findall(r"\n\t(\w+)\s*=\s*\{(.*?)\n\t\},", text, re.S):
        f = {}
        for key in ("maxslope", "maxwaterdepth", "minwaterdepth"):
            m = re.search(r"\b%s\s*=\s*([^\n]+)" % key, body)
            if m:
                f[key] = _value(m.group(1), consts)
        f["sub"] = bool(re.search(r"subMarine\s*=\s*true", body))
        classes[name.lower()] = f
    units = {}
    for p in (sdd / "units").rglob("*.lua"):
        t = p.read_text(errors="replace")
        mc = re.search(r'movementclass\s*=\s*"(\w+)"', t, re.I)
        fly = re.search(r"canfly\s*=\s*true", t, re.I)
        units[p.stem.lower()] = {"class": mc.group(1).lower() if mc else None, "fly": bool(fly)}
    data = {"classes": classes, "units": units}
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(data))
    return data


@lru_cache(maxsize=1)
def _data():
    if CACHE.exists():
        try:
            return json.loads(CACHE.read_text())
        except ValueError:
            pass
    return _build()


@lru_cache(maxsize=None)
def movement(name):
    d = _data()
    u = d["units"].get(name.lower())
    if u is None:
        return (1.0, 0.0, 0.0, 0.5, 0.0)  # unknown (a modded unit): a land unit of middling reach
    if u["fly"]:
        return (1.0, 1.0, 0.0, 1.0, 1.0)
    mc = u["class"]
    c = d["classes"].get(mc or "", {})
    if mc is None:
        return (0.0, 0.0, 0.0, 0.0, 0.0)  # buildings
    if "boat" in mc or "ship" in mc or (c.get("minwaterdepth") or 0) > 0:
        return (0.0, 1.0, float(c.get("sub", False)), 1.0, 1.0)
    slope = min((c.get("maxslope") or 90.0) / 90.0, 1.0)
    if "hover" in mc:
        return (1.0, 1.0, 0.0, slope, 1.0)
    depth = c.get("maxwaterdepth")
    depth = AMPHIBIOUS if depth is None else min(depth, AMPHIBIOUS)
    wade = math.log1p(max(depth, 0.0)) / math.log1p(AMPHIBIOUS)
    return (1.0, 0.0, float(depth >= AMPHIBIOUS), slope, wade)


if __name__ == "__main__":
    if "--rebuild" in sys.argv:
        _build()
    for n in sys.argv[1:]:
        if not n.startswith("--"):
            print("%-12s land %.0f water %.0f under %.0f slope %.2f wade %.2f" % ((n,) + movement(n)))
