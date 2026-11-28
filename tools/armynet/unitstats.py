"""Unit stats for the army model from defs.json (game-patches/gadgets/dev_defsdump.lua: the game's own UnitDefs and
WeaponDefs, after BAR's post-processing). His 11-22: "The model needs to know the unit's hp, range, damage, fire
rate, movement speed, it needs to understand all the factors".

    stats = UnitStats.load()            # runtime/armynet/defs.json by default
    vec = stats.vector("armpw")         # STAT_F floats, zeros for an unknown name

Weapons are summed per target class (ground: anything that is not anti-air only; air: anything that can hit VTOL),
so a unit reads as its whole armament against each. Damage is the weapon's damage against the default armor for
ground and against the "vtol" armor for air; shields and interceptors are not weapons here.
"""
import json
import math
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
from paths import data_dir  # noqa: E402
DEFAULT = data_dir() / "defs.json"

# body (13) + per target class ground/air (11 each)
STAT_NAMES = ("log_hp", "log_metal", "speed", "turn", "accel", "sight", "radar", "jammer", "cloak", "stealth",
              "log_shield", "fly", "size") + tuple(
    "%s_%s" % (t, n) for t in ("g", "a") for n in (
        "armed", "range", "log_dps", "log_volley", "reload", "aoe", "proj_speed", "high", "paralyzer", "stockpile",
        "n_weapons"))
STAT_F = len(STAT_NAMES)

_AIR_ONLY = {"VTOL"}


def _hits(only):
    """(ground, air) a weapon can target, from its onlyTargetCategory list (empty = anything)."""
    o = {str(s).upper() for s in only or ()}
    if not o:
        return True, True
    air = "VTOL" in o
    ground = bool(o - _AIR_ONLY)
    return ground, air


class UnitStats:
    def __init__(self, data):
        self.armor = {k.lower(): int(v) for k, v in (data.get("armor") or {}).items()}
        self.units = data.get("units") or {}
        self._cache = {}
        i_def = self.armor.get("default", 0)
        i_vtol = self.armor.get("vtol", i_def)
        self._idx = (i_def, i_vtol)

    @classmethod
    def load(cls, path=None):
        p = Path(path) if path else DEFAULT
        if not p.exists():
            return cls({})
        return cls(json.loads(p.read_text(encoding="utf-8", errors="replace")))

    def __bool__(self):
        return bool(self.units)

    def vector(self, name):
        name = str(name)
        if name in self._cache:
            return self._cache[name]
        u = self.units.get(name)
        v = [0.0] * STAT_F
        if u:
            def f(k):
                try:
                    return float(u.get(k) or 0.0)
                except (TypeError, ValueError):
                    return 1.0 if u.get(k) is True else 0.0
            v[0] = math.log1p(max(f("health"), 0.0)) / 10
            v[1] = math.log1p(max(f("metal"), 0.0)) / 10
            v[2] = f("speed") / 100
            v[3] = f("turn") / 1000
            v[4] = f("accel") / 1
            v[5] = f("sight") / 1000
            v[6] = f("radar") / 1000
            v[7] = f("jammer") / 1000
            v[8] = 1.0 if u.get("cloak") else 0.0
            v[9] = 1.0 if u.get("stealth") else 0.0
            v[10] = math.log1p(max(f("shield"), 0.0)) / 10
            v[11] = 1.0 if u.get("fly") else 0.0
            v[12] = (f("fx") * f("fz")) ** 0.5 / 10
            for t, (base, idx) in enumerate(((13, self._idx[0]), (24, self._idx[1]))):
                rng = dps = volley = reload = aoe = spd = high = para = stock = n = 0.0
                for w in u.get("weapons") or ():
                    if w.get("interceptor") or str(w.get("type", "")).lower() == "shield":
                        continue
                    g, a = _hits(w.get("only"))
                    if not (g if t == 0 else a):
                        continue
                    dm = w.get("damages") or []
                    d = float(dm[idx]) if idx < len(dm) else (float(dm[0]) if dm else 0.0)
                    if d <= 1.0:
                        continue
                    per = d * max(float(w.get("salvo") or 1), 1.0) * max(float(w.get("projectiles") or 1), 1.0)
                    rl = max(float(w.get("reload") or 1.0), 0.03)
                    n += 1
                    dps += per / rl
                    volley = max(volley, per)
                    rng = max(rng, float(w.get("range") or 0.0))
                    reload = max(reload, rl)
                    aoe = max(aoe, float(w.get("aoe") or 0.0))
                    spd = max(spd, float(w.get("speed") or 0.0))
                    # the engine's highTrajectory: 1 always lobs, 2 lets the player pick (most weapons), 0 never
                    high = max(high, 1.0 if float(w.get("high") or 0) == 1.0 else 0.0)
                    para = max(para, 1.0 if w.get("paralyzer") else 0.0)
                    stock = max(stock, 1.0 if w.get("stockpile") else 0.0)
                v[base:base + 11] = [1.0 if n else 0.0, rng / 1000, math.log1p(dps) / 10, math.log1p(volley) / 10,
                                     min(reload, 30.0) / 10, aoe / 100, spd / 1000, high, para, stock, n / 4]
        self._cache[name] = v
        return v

    def d_line(self, name):
        """The recorder's D-line stats for a unit (tools/replay_orders_widget.lua weaponStats and its format's rounding):
        metal, hp, speed, range, ground dps, aa dps, sight, radar, jammer. The AI-side bridge (ArmyNetBridge.cpp)
        writes only id, name and class; serve.py fills these so live inputs match the recordings."""
        u = self.units.get(str(name))
        if not u:
            return [0.0] * 9
        rng = ground = aa = 0.0
        for w in u.get("weapons") or ():
            dm = w.get("damages") or []
            d = float(dm[0]) if dm else 0.0
            per = d * float(w.get("salvo") or 1) * float(w.get("projectiles") or 1) / max(float(w.get("reload") or 1), 0.03)
            only = {str(s).lower() for s in (w.get("only") or ())}
            if "vtol" in only and not ({"notair", "surface", "ground"} & only):
                aa += per
            else:
                ground += per
                rng = max(rng, float(w.get("range") or 0.0))

        def g(k):
            try:
                return float(u.get(k) or 0.0)
            except (TypeError, ValueError):
                return 0.0
        return [round(g("metal")), round(g("health")), round(g("speed"), 1), round(rng), round(ground, 1), round(aa, 1),
                round(g("sight")), round(g("radar")), round(g("jammer"))]

    def table(self, names_by_def):
        """{def id: name} -> numpy (max id + 1, STAT_F), zeros where unknown."""
        import numpy as np
        nd = (max(names_by_def) + 1) if names_by_def else 1
        out = np.zeros((nd, STAT_F), np.float32)
        for d, n in names_by_def.items():
            if d >= 0:
                out[d] = self.vector(n)
        return out
