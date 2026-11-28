#!/usr/bin/env python3
"""What an economy building earns, in metal per second (his 11-19: "eco damage is one of the best forms of damage we
could possibly rate"). A kill costs its owner the income until it is rebuilt, not only its price: an extractor pays
for itself in ~25 s.

    income(name) -> metal per second
      extractors  extractsmetal x 2000 (a 2.0 metal spot, the common one; the recordings do not carry spot values)
      energy      energymake, or a negative energyupkeep (solar), wind at half its maximum, tidal x 18, at 60 energy
                  per metal (what converters pay: 70 energy for 1 metal at 0.0143)
      converters  energyconv_capacity x energyconv_efficiency

Read from BAR.sdd units/**.lua; cached in runtime/armynet/economy.json.

    python tools/armynet/economy.py armmex armmoho armsolar armwin armfus armmakr cortide
"""
import json
import re
import sys
from functools import lru_cache
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
from paths import data_dir  # noqa: E402
CACHE = data_dir() / "economy.json"
E_PER_M = 60.0
SPOT = 2000.0
WIND = 0.5
TIDE = 18.0


def _num(text, key):
    m = re.search(r"\b%s\s*=\s*(-?[\d.]+)" % key, text, re.I)
    return float(m.group(1)) if m else 0.0


def _build():
    import bar_env
    out = {}
    for p in (Path(bar_env.load().game_sdd) / "units").rglob("*.lua"):
        t = p.read_text(errors="replace")
        m = _num(t, "extractsmetal") * SPOT
        e = _num(t, "energymake") + max(-_num(t, "energyupkeep"), 0.0) + _num(t, "windgenerator") * WIND \
            + _num(t, "tidalgenerator") * TIDE
        conv = _num(t, "energyconv_capacity") * _num(t, "energyconv_efficiency")
        v = m + e / E_PER_M + conv
        if v > 0:
            out[p.stem.lower()] = round(v, 4)
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(out))
    return out


@lru_cache(maxsize=1)
def _data():
    if CACHE.exists():
        try:
            return json.loads(CACHE.read_text())
        except ValueError:
            pass
    return _build()


def income(name):
    return _data().get(name.lower(), 0.0)


if __name__ == "__main__":
    if "--rebuild" in sys.argv:
        _build()
    for n in sys.argv[1:]:
        if not n.startswith("--"):
            print("%-10s %.3f metal/s" % (n, income(n)))
