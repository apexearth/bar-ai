"""Training game length grows as we catch BARb (his 10-09: master the opening in short
games, then run longer and longer ones as we improve).

    python tools/curriculum.py              # the stage, and where we stand at its judged minute
    python tools/curriculum.py --minutes    # the game length the loops use (just the number)
    python tools/curriculum.py --advance    # step up if this stage is passed

A stage of L minutes is judged at minute L-1; its games run L+PAD so decisions up to the
judged minute carry their 5-minute labels. It is passed when our normal games match BARb there -- median eco and
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


def medians(games, minute):
    out = {}
    for m in METRICS:
        vals = [g["series"][m][minute] for g in games
                if minute < len(g["series"][m]) and g["series"][m][minute] is not None]
        out[m] = statistics.median(vals) if vals else None
    return out


def judge(st):
    """{regime: {n, all: medians, recent: medians, ok}} for the current stage's games."""
    minute = st["minutes"] - 1
    # the rules-only control batches (-b0) are not how the AI plays
    # and only the training loops' batches -- an A/B arm named *1v1* is not how it plays either
    games = [g for g in progress.collect(since=st["since"][:13])
             if "nn-open" in g["tournament"] and not g["tournament"].endswith("-b0")]
    res = {}
    for reg, need in NEED.items():
        gs = [g for g in games if progress.regime_of(g) == reg and g.get("minutes", 0) >= minute][-need:]
        allm, rec = medians(gs, minute), medians(gs[len(gs) // 2:], minute)
        ok = len(gs) >= need and all(v is not None and v >= PASS for d in (allm, rec) for v in d.values())
        res[reg] = {"n": len(gs), "need": need, "all": allm, "recent": rec, "ok": ok}
    return minute, res


def fmt(d):
    return " ".join("%s=%s" % (k, "-" if v is None else "%.2f" % v) for k, v in d.items())


def main(argv):
    st = load()
    if "--minutes" in argv:
        print(st["minutes"] + PAD)
        return 0
    minute, res = judge(st)
    print("stage %d min (judged at m%d, games run %d) since %s" % (st["minutes"], minute, st["minutes"] + PAD, st["since"]))
    for reg, r in res.items():
        print("  %s n=%d/%d  last: %s  recent half: %s  %s" % (
            reg, r["n"], r["need"], fmt(r["all"]), fmt(r["recent"]), "PASS" if r["ok"] else "-"))
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
