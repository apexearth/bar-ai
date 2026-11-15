"""Anomaly detector: a seat that suddenly acts unlike our AI normally does (his 11-14: "some sort of anomaly detector
where you try to identify anomalous behavior ... when all of a sudden our AI acts dramatically different from the way
it normally acts").

    python tools/anomaly.py build                      # baseline from every finished game in matches/ (release seats)
    python tools/anomaly.py check matches/pkg3-*       # flag seats far outside the baseline, worst first
    python tools/anomaly.py check matches/x --ai lane-estall --z 5

The baseline is the release's own seats (`--base-ai`, default the newest ai/vX in this repo) across every finished game:
per feature and minute, the median and the MAD. A seat's feature is anomalous when it sits more than --z robust
deviations from that median (z = (x - median) / (1.4826 MAD)). Features are what the metal went to and what the seat
holds -- shares of spend, constructors, advanced extractors, factories, army, tech timing -- read from result.json, so a
check costs no log parsing. The contract checks behaviours he has named; this catches the ones nobody has named yet.
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import re
import statistics
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BASE = REPO / "runtime" / "anomaly"
MINUTES = (6, 10, 15, 20, 25, 30)


def latest_release() -> str:
    """The newest COMMITTED release (an untracked ai/vX is a candidate, not normal behaviour)."""
    import subprocess
    tracked = subprocess.run(["git", "ls-files", "ai/"], cwd=REPO, capture_output=True, text=True).stdout
    vs = sorted({ln.split("/")[1] for ln in tracked.splitlines() if ln.startswith("ai/v") and ln.count("/") > 1},
                key=lambda s: [int(x) for x in s[1:].split(".") if x.isdigit()])
    return vs[-1] if vs else "v0.5.11"


def features(rows: list[dict]) -> dict[str, float]:
    """One seat's features at each minute bucket, from its periodic stats rows (sorted by frame)."""
    out = {}
    tech = next((r["techFrame"] / 1800.0 for r in rows if r.get("techFrame", -1) > 0), None)
    if tech is not None:
        out["t2 minute"] = tech
    for m in MINUTES:
        r = min(rows, key=lambda r: abs(r["frame"] - m * 1800))
        if abs(r["frame"] - m * 1800) > 1800:
            continue
        # A seat beaten (no hands, no army left) is a lost game, which the head-to-head counts; its rows from then
        # on are not behaviour.
        peak_army = max(x.get("armyReal", 0) for x in rows if x["frame"] <= r["frame"])
        if (r.get("conT1", 0) + r.get("conT2", 0) <= 2) and peak_army > 0 and r.get("armyReal", 0) <= 0.05 * peak_army:
            break
        b = r.get("mBuiltReal", 0)
        if b <= 0:
            continue
        p = "%02dm " % m
        out[p + "built"] = math.log1p(b)
        for k, name in (("mEco", "eco share"), ("mArmy", "army share"), ("mDefence", "defence share"),
                        ("mBP", "build-power share"), ("mFactories", "factory share"), ("mCon", "constructor share"),
                        ("mT2", "T2 share")):
            out[p + name] = r.get(k, 0) / b
        out[p + "constructors"] = math.log1p(r.get("conT1", 0) + r.get("conT2", 0))
        out[p + "T2 constructors"] = math.log1p(r.get("conT2", 0))
        out[p + "advanced extractors"] = math.log1p(r.get("t2Mex", 0))
        out[p + "extractors"] = math.log1p(r.get("mex", 0))
        out[p + "units"] = math.log1p(_units(r))
    return out


def _units(r: dict) -> int:
    return sum(int(v) for _k, v in (x.split(":") for x in (r.get("unitCount") or "").split(",") if ":" in x))


LOGGED = ("built", "constructors", "T2 constructors", "advanced extractors", "extractors", "units")


def shown(name: str, v: float) -> str:
    if any(name.endswith(k) for k in LOGGED):
        return "%.0f" % math.expm1(v)
    if name.endswith("share"):
        return "%.0f%%" % (100 * v)
    return "%.1f" % v


def regime(res: dict, side: str) -> str:
    """What makes 'normal' differ: the bonus, a resource multiplier, the faction. A 2x-income Legion game is not
    compared with a +50 Armada one."""
    argv = [str(x) for x in (res.get("argv") or [])]
    mult = "1"
    special = ""
    for i, x in enumerate(argv):
        nxt = argv[i + 1] if i + 1 < len(argv) else ""
        if x == "--modoption" and nxt.startswith("multiplier_resourceincome="):
            mult = nxt.split("=", 1)[1]
        # a scenario or a forced test behaviour is its own normal (test turtle, eco-only, share overrides...)
        if x in ("--scenario", "--ai-options-file") or (x in ("--ai-option", "--b-option")
                                                       and nxt.split("=", 1)[0] in ("apex_test_turtle", "apex_eco_only",
                                                                                     "apex_share_army", "apex_share_defence")):
            special = "-test"
    per = len(res.get("sides") or []) // 2 or "?"
    # The map is part of normal: a metal map's hundreds of extractors and early T2 are not a fault. A map the
    # release has too few seats on has no normal yet, and its seats are skipped, not compared with other maps.
    mp = re.sub(r"\s+v?[\d.]+$", "", str(res.get("map") or "?").strip())
    return "hc%s-x%s-%s-%sv%s%s@%s" % (res.get("handicap", "?"), mult, side[:1].upper() if side else "?", per, per,
                                       special, mp)


def seats(match: Path):
    res = json.loads((match / "result.json").read_text())
    side_ai = {t["team"]: (t.get("version") or t["spec"]) for t in res.get("teams", [])}
    rows = {}
    for r in res.get("stats") or []:
        if r.get("reason") == "periodic":
            rows.setdefault(int(r["team"]), []).append(r)
    for t, rs in rows.items():
        rs.sort(key=lambda r: r["frame"])
        yield t, side_ai.get(int(rs[0]["ally"]), "?"), rs, res


def build(a):
    vals: dict[str, list[float]] = {}
    n = 0
    for rj in glob.glob(str(REPO / "matches" / "*" / "result.json")):
        p = Path(rj).parent
        try:
            for t, ai, rs, res in seats(p):
                if a.base_ai not in ai:
                    continue
                if "BaRandom" in json.dumps(res.get("argv") or []) or "--randomizer" in (res.get("argv") or []):
                    continue   # randomizer games are not normal play (memory: randomizer-games)
                for k, v in features(rs).items():
                    rg = regime(res, (res.get("sides") or ["?"] * 32)[t] if t < len(res.get("sides") or []) else "?")
                    vals.setdefault(rg + "|" + k, []).append(v)
                n += 1
        except Exception:
            continue
    base = {}
    for k, xs in vals.items():
        if len(xs) < 20:
            continue
        med = statistics.median(xs)
        mad = statistics.median(abs(x - med) for x in xs)
        base[k] = {"median": med, "mad": mad, "n": len(xs)}
    BASE.mkdir(parents=True, exist_ok=True)
    f = BASE / ("baseline-%s.json" % a.base_ai)
    f.write_text(json.dumps({"ai": a.base_ai, "seats": n, "features": base}, indent=1))
    print("baseline %s: %d seats, %d features -> %s" % (a.base_ai, n, len(base), f.relative_to(REPO)))
    return 0


_BASE_CACHE: dict = {}


def seat_anomalies(res: dict, team: int, rows: list[dict], base_ai: str = None, zmin: float = 5.0) -> int:
    """How many of one seat's features sit outside the release's normal (the contract's per-seat check)."""
    base_ai = base_ai or latest_release()
    if base_ai not in _BASE_CACHE:
        f = BASE / ("baseline-%s.json" % base_ai)
        _BASE_CACHE[base_ai] = json.loads(f.read_text())["features"] if f.exists() else None
    base = _BASE_CACHE[base_ai]
    if base is None:
        return -1
    sides = res.get("sides") or []
    rg = regime(res, sides[team] if team < len(sides) else "?")
    if not any(k.startswith(rg + "|") for k in base):
        return -1
    n = 0
    for k, v in features(rows).items():
        b = base.get(rg + "|" + k)
        if not b:
            continue
        floor = 0.05 if k.endswith("share") else 0.5
        if abs(v - b["median"]) / max(1.4826 * b["mad"], floor) >= zmin:
            n += 1
    return n


def check(a, out=print):
    f = BASE / ("baseline-%s.json" % a.base_ai)
    if not f.exists():
        out("anomaly: no baseline for %s (run `python tools/anomaly.py build`)" % a.base_ai)
        return 2
    base = json.loads(f.read_text())["features"]
    paths = []
    for p in a.matches:
        paths += [Path(x) for x in glob.glob(p)] or [Path(p)]
    flagged = []
    seen = 0
    unknown: dict = {}
    for p in sorted(set(paths)):
        if not (p / "result.json").exists():
            continue
        for t, ai, rs, res in seats(p):
            if a.ai not in ai:
                continue
            rg = regime(res, (res.get("sides") or ["?"] * 32)[t] if t < len(res.get("sides") or []) else "?")
            if not any(k.startswith(rg + "|") for k in base):
                unknown[rg] = unknown.get(rg, 0) + 1
                continue
            seen += 1
            for k, v in features(rs).items():
                b = base.get(rg + "|" + k)
                if not b:
                    continue
                s = 1.4826 * b["mad"]
                # a spread of ~nothing must not make noise an anomaly: shares +-5 points, counts ~65% (log1p 0.5)
                floor = 0.05 if k.endswith("share") else 0.5
                z = (v - b["median"]) / max(s, floor)
                if abs(z) >= a.z:
                    flagged.append((abs(z), p.name, t, ai, k, v, b["median"], z))
    flagged.sort(reverse=True)
    by_seat: dict = {}
    for zz, m, t, ai, k, v, med, z in flagged:
        by_seat.setdefault((m, t, ai), []).append((k, v, med, z))
    out("anomalies: %d seat(s) of %d outside %.0f robust deviations of %s's normal" % (len(by_seat), seen, a.z, a.base_ai)
        + ("; %d seat(s) skipped, no normal yet for %s" % (sum(unknown.values()), ", ".join(sorted(unknown)))
           if unknown else ""))
    for (m, t, ai), fs in sorted(by_seat.items(), key=lambda kv: -max(abs(x[3]) for x in kv[1]))[:a.top]:
        top = sorted(fs, key=lambda x: -abs(x[3]))[:4]
        out("  %s t%d %s: %s" % (m, t, ai, "; ".join("%s %s (normal %s, z %+.0f)" % (k, shown(k, v), shown(k, med), z)
                                                     for k, v, med, z in top)))
    return 1 if by_seat else 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("cmd", choices=("build", "check"))
    ap.add_argument("matches", nargs="*")
    ap.add_argument("--base-ai", default=latest_release())
    ap.add_argument("--ai", default="lane-", help="which seats to check (substring of the version; default our lanes)")
    ap.add_argument("--z", type=float, default=5.0)
    ap.add_argument("--top", type=int, default=12)
    a = ap.parse_args(argv)
    return build(a) if a.cmd == "build" else check(a)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
