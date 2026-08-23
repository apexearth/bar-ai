#!/usr/bin/env python3
"""Diff the Catalog dump against the pinned game tree's unit defs.

The Catalog (manager/catalog.as) logs one `apex: catalog <name> ...` line per
available def when the match runs with `--modoption apex_catalog_dump=1`. This
tool parses those lines out of an infolog and compares them against the raw
unit defs in the PINNED tree (BAR.sdd -- the one matches actually run against),
for a fixed set of well-known defs.

    python tools/check_catalog.py <infolog.txt | match-dir>

Checked per def: mCost, eCost, bt (buildtime), makeM/makeE (net: make minus
upkeep; wind is map-averaged so it is only bounded by [0, windgenerator]),
storeM/storeE, convCap/convRatio, extractsM, and for builders the builds-graph
edge count against len(buildoptions).

Exit 0 when every check passes, 1 on any mismatch or missing line.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bar_env  # noqa: E402
import unitdef  # noqa: E402

DEFS = ["armcom", "armmex", "armsolar", "armwin", "armlab", "armck",
        "cormex", "corlab", "corck", "armfus", "armmoho", "armnanotc",
        "armmakr", "armadvsol", "armllt"]

LINE_RE = re.compile(r"apex: catalog (\S+) (.*)")
KV_RE = re.compile(r"(\w+)=(-?[\d.]+)")

# Raw lua fields the catalog values derive from.
RAW_FIELDS = ("metalcost", "energycost", "buildtime", "energymake",
              "energyupkeep", "metalmake", "metalupkeep", "energystorage",
              "metalstorage", "extractsmetal", "windgenerator")
RAW_RE = {k: re.compile(rf"\b{k}\s*=\s*(-?[\d.]+)", re.I) for k in RAW_FIELDS}
CONV_RE = {k: re.compile(rf"\b{k}\s*=\s*(-?[\d.]+)", re.I)
           for k in ("energyconv_capacity", "energyconv_efficiency")}


def parse_dump(text: str) -> dict[str, dict[str, float]]:
    out: dict[str, dict[str, float]] = {}
    for m in LINE_RE.finditer(text):
        out[m.group(1)] = {k: float(v) for k, v in KV_RE.findall(m.group(2))}
    return out


def raw_def(tree: unitdef.Tree, name: str) -> dict | None:
    p = tree.find(name)
    if p is None:
        return None
    text = p.read_text(encoding="utf-8", errors="replace")
    out: dict = {k: 0.0 for k in RAW_FIELDS}
    for k, rx in RAW_RE.items():
        m = rx.search(text)
        if m:
            out[k] = float(m.group(1))
    for k, rx in CONV_RE.items():
        m = rx.search(text)
        out[k] = float(m.group(1)) if m else 0.0
    m = unitdef.BUILDOPT_RE.search(text)
    out["builds"] = unitdef.OPT_RE.findall(m.group(1)) if m else []
    return out


def close(a: float, b: float, tol: float = 0.015) -> bool:
    return abs(a - b) <= max(abs(b) * tol, 0.01)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    p = Path(sys.argv[1])
    if p.is_dir():
        p = p / "infolog.txt"
    if not p.is_file():
        print(f"no infolog at {p}")
        return 2
    dump = parse_dump(p.read_text(encoding="utf-8", errors="replace"))
    if not dump:
        print("FAIL: no 'apex: catalog' lines in the infolog "
              "(run with --modoption apex_catalog_dump=1)")
        return 1
    print(f"catalog dump: {len(dump)} defs")

    env = bar_env.load()
    tree = unitdef.Tree("game", env.game_sdd)
    if not tree.ok:
        print(f"pinned game tree not found at {tree.root}")
        return 2

    fails = 0

    def check(name: str, field: str, got: float, want: float, exact_note: str = ""):
        nonlocal fails
        if not close(got, want):
            fails += 1
            print(f"  MISMATCH {name}.{field}: catalog={got} def={want} {exact_note}")

    for name in DEFS:
        raw = raw_def(tree, name)
        if raw is None:
            print(f"  SKIP {name}: not in pinned tree")
            continue
        row = dump.get(name)
        if row is None:
            fails += 1
            print(f"  MISSING {name}: no catalog line")
            continue
        check(name, "mCost", row["mCost"], raw["metalcost"])
        check(name, "eCost", row["eCost"], raw["energycost"])
        check(name, "bt", row["bt"], raw["buildtime"])
        check(name, "storeM", row["storeM"], raw["metalstorage"])
        check(name, "storeE", row["storeE"], raw["energystorage"])
        check(name, "makeM", row["makeM"], raw["metalmake"] - raw["metalupkeep"])
        check(name, "extractsM", row["extractsM"], raw["extractsmetal"])
        check(name, "convCap", row["convCap"], raw["energyconv_capacity"])
        check(name, "convRatio", row["convRatio"], raw["energyconv_efficiency"])
        # makeE: net = energymake - energyupkeep, EXCEPT wind (map-averaged --
        # the catalog stores min(avgWind, windgenerator), so bound it) and
        # converters (their capacity rides in upkeepE by CircuitDef.cpp).
        wind = raw["windgenerator"]
        if wind > 0:
            if not (0.0 <= row["makeE"] <= wind + 0.01):
                fails += 1
                print(f"  MISMATCH {name}.makeE: catalog={row['makeE']} "
                      f"not in [0, windgenerator={wind}]")
            if row.get("wind", 0) != 1:
                fails += 1
                print(f"  MISMATCH {name}.wind: expected wind=1")
        elif raw["energyconv_capacity"] > 0:
            pass  # converter: makeE is its idle net; economics live in convCap*convRatio
        else:
            check(name, "makeE", row["makeE"],
                  raw["energymake"] - raw["energyupkeep"])
        # builds-graph edge count for builders
        nopts = len(raw["builds"])
        if nopts > 0:
            got = int(row.get("builds", -1))
            if got != nopts:
                fails += 1
                print(f"  MISMATCH {name}.builds: catalog={got} "
                      f"buildoptions={nopts}")
        print(f"  ok {name}" if fails == 0 else f"  .. {name} checked")

    print("PASS" if fails == 0 else f"FAIL: {fails} mismatches")
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
