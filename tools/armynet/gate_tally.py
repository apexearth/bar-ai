#!/usr/bin/env python3
"""Gate tally from head-to-head ladder logs (selfplay.sh lines "seed <s> t0 <name> t1 <name> <match dir>"): a decided
game goes to result.json's winner; a game stopped at the time cap goes to the side with more standing metal at the cap
(its last BARAI_STATS line: mBuiltReal - mLostReal).

    python tools/armynet/gate_tally.py runtime/armynet/h2h-<tag>.log [...]
"""
import json
import re
import sys
from pathlib import Path

ST = re.compile(r"\[BARAI_STATS\] team=(\d+) .*?mLostReal=(\d+) .*?mBuiltReal=(\d+)")


def game(seed, n0, n1, d):
    """(winner name or None, how) for one ladder line's match."""
    d = Path(d)
    rj = d / "result.json"
    if not rj.exists():
        return None, "no result"
    res = json.loads(rj.read_text())
    wl = (res.get("result") or {}).get("winners") or []
    win = wl[0] if len(wl) == 1 else None
    names = {0: n0, 1: n1}
    last = {}
    log = d / "infolog.txt"
    if log.exists():
        for raw in open(log, errors="replace"):
            if "[BARAI_STATS]" in raw and (m := ST.search(raw)):
                last[int(m.group(1))] = int(m.group(3)) - int(m.group(2))
    w = None
    if isinstance(win, int) and win in names:
        w = names[win]
    elif isinstance(win, str) and win in names.values():
        w = win
    elif isinstance(res.get("winner_team"), int):
        w = names.get(res["winner_team"])
    if w is None:
        for k in ("winner_ally", "winning_ally", "winner"):
            v = res.get(k)
            if isinstance(v, int) and v in names:
                w = names[v]
                break
    if w is not None:
        return w, "decided"
    if len(last) == 2:
        return (n0 if last[0] > last[1] else n1), "cap %d vs %d" % (last.get(0, 0), last.get(1, 0))
    return None, "undecided"


def tally(logs, verbose=True):
    """Per name: [decided wins, wins at the cap]; plus the number of games read."""
    tot, n = {}, 0
    for log in logs:
        for ln in open(log):
            p = ln.split()
            if len(p) < 7 or p[0] != "seed":
                continue
            w, how = game(p[1], p[3], p[5], p[6])
            n += 1
            if verbose:
                print("seed %s %s vs %s -> %s (%s)" % (p[1], p[3], p[5], w, how))
            if w is None:
                continue
            tot.setdefault(w, [0, 0])
            tot[w][0 if how == "decided" else 1] += 1
    return tot, n


if __name__ == "__main__":
    t, n = tally(sys.argv[1:])
    print({k: "%d (%d decided + %d at cap)" % (v[0] + v[1], v[0], v[1]) for k, v in t.items()}, "of", n)
