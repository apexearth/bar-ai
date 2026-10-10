"""Training game length grows as we catch BARb (his 10-09: master the opening in short
games, then run longer and longer ones as we improve).

    python tools/curriculum.py              # the stage, and where we stand at its judged minute
    python tools/curriculum.py --minutes    # the game length the loops use (just the number)
    python tools/curriculum.py --advance    # step up if this stage is passed

A stage of L minutes runs L+PAD-minute games (so decisions up to minute L-1 carry their
5-minute labels) and is judged on each game's MEAN edge from minute 3 to its end -- a game that falls behind and catches up counts (his 10-10). Passed when the median eco and
mex edge >= 1.0 -- over the stage's last 30 1v1 and last 15 2v2 games, and again over
the most recent half of each.
"""
import json
import os
import statistics
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import progress  # noqa: E402

STAGES = (8, 12, 16, 20, 30, 45, 60)
# games run this much past the stage so a decision at its judged minute still gets the
# 5-minute label (his 10-10: 12-minute games for the 8-minute stage)
PAD = 4
NEED = {"1v1": 30, "2v2": 15}
METRICS = ("eco", "mex")
PASS = 1.0
STATE = os.path.join(progress.REPO, "runtime", "nn", "curriculum.json")


def load():
    try:
        with open(STATE, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {"minutes": STAGES[0], "since": time.strftime("%Y%m%d-%H%M%S"), "history": []}


def save(st):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(st, fh, indent=1)
    os.replace(tmp, STATE)


WIN_FROM = 3   # the window starts here and runs to the game's last whole minute


def at(g, m, minute):
    s = g["series"][m]
    return s[minute] if minute < len(s) else None


def medians(games, last):
    """Per metric, the median over games of each game's mean edge across the window --
    a game that falls behind early and catches up counts (his 10-10)."""
    out = {}
    for m in METRICS:
        means = []
        for g in games:
            vals = [v for v in (at(g, m, k) for k in range(WIN_FROM, last + 1)) if v is not None]
            if vals:
                means.append(sum(vals) / len(vals))
        out[m] = statistics.median(means) if means else None
    return out


def curve(games, last):
    """Median edge at a few minutes of the window, for reading where we fall behind or catch up."""
    pts = list(range(WIN_FROM, last + 1, 2))
    out = {}
    for m in METRICS:
        row = []
        for k in pts:
            vals = [v for v in (at(g, m, k) for g in games) if v is not None]
            row.append("m%d=%s" % (k, "%.2f" % statistics.median(vals) if vals else "-"))
        out[m] = " ".join(row)
    return out


def judge(st):
    """{regime: {n, all: medians, recent: medians, ok}} for the current stage's games."""
    minute = st["minutes"] - 1
    last = st["minutes"] + PAD - 1
    # the rules-only control batches (-b0) are not how the AI plays
    # and only the training loops' batches -- an A/B arm named *1v1* is not how it plays either
    games = [g for g in progress.collect(since=st["since"][:13])
             if "nn-open" in g["tournament"] and not g["tournament"].endswith("-b0")]
    res = {}
    for reg, need in NEED.items():
        gs = [g for g in games if progress.regime_of(g) == reg and g.get("minutes", 0) >= minute][-need:]
        allm, rec = medians(gs, last), medians(gs[len(gs) // 2:], last)
        ok = len(gs) >= need and all(v is not None and v >= PASS for d in (allm, rec) for v in d.values())
        res[reg] = {"n": len(gs), "need": need, "all": allm, "recent": rec, "ok": ok, "curve": curve(gs, last)}
    return minute, res


def fmt(d):
    return " ".join("%s=%s" % (k, "-" if v is None else "%.2f" % v) for k, v in d.items())


def main(argv):
    st = load()
    if "--minutes" in argv:
        print(st["minutes"] + PAD)
        return 0
    minute, res = judge(st)
    print("stage %d min (games run %d; judged on each game's mean edge m%d-m%d) since %s" % (st["minutes"], st["minutes"] + PAD, WIN_FROM, st["minutes"] + PAD - 1, st["since"]))
    for reg, r in res.items():
        print("  %s n=%d/%d  last: %s  recent half: %s  %s" % (
            reg, r["n"], r["need"], fmt(r["all"]), fmt(r["recent"]), "PASS" if r["ok"] else "-"))
        for m, row in r["curve"].items():
            print("      %-4s %s" % (m, row))
    if "--advance" in argv and all(r["ok"] for r in res.values()):
        i = STAGES.index(st["minutes"]) if st["minutes"] in STAGES else 0
        if i + 1 < len(STAGES):
            st["history"].append({"minutes": st["minutes"], "since": st["since"],
                                  "passed": time.strftime("%Y%m%d-%H%M%S"), "result": res})
            st["minutes"], st["since"] = STAGES[i + 1], time.strftime("%Y%m%d-%H%M%S")
            save(st)
            print("ADVANCED to %d minutes" % st["minutes"])
    elif not os.path.exists(STATE):
        save(st)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
