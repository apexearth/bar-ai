"""Step our training bonus toward BARb's as the win rate allows.

    python tools/barb_handicap.py            # print the handicap pair to use next ("65,50")
    python tools/barb_handicap.py --dry-run  # say what the record reads, change nothing

His rule (2026-10-08): whenever we win steadily over 50%, tailor our bonus back
until we're about even -- counting NORMAL games only. A game where one of our AIs
rolled discovery (`apex: nn-explore t=N on`) is there to try things and is
expected to lose more. Normal games at the current bonus are pooled across
batches; once MIN_DECIDED of them are decided and we won more than half, our
bonus drops by STEP, never below BARb's. It never rises.
State: runtime/nn_barb_handicap.txt holds our bonus.
"""
import glob
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE = os.path.join(REPO, "runtime", "nn_barb_handicap.txt")
BARB = 50
START = 65
STEP = 5
MIN_DECIDED = 30


def our_bonus():
    try:
        return int(open(STATE).read().strip())
    except (OSError, ValueError):
        return START


def explored(match_dir):
    try:
        with open(os.path.join(match_dir, "infolog.txt"), encoding="utf-8", errors="replace") as f:
            return any("apex: nn-explore t=" in ln for ln in f)
    except OSError:
        return True   # no log, cannot tell: never counted as normal


def record(ours):
    """Normal-game (wins, losses) and explore-game (wins, losses) at our bonus, every batch."""
    nw = nl = ew = el = 0
    for t in glob.glob(os.path.join(REPO, "tournaments", "*nn-barbtrain*")):
        for r in glob.glob(os.path.join(t, "matches", "*", "result.json")):
            try:
                j = json.load(open(r, encoding="utf-8"))
            except (OSError, ValueError):
                continue
            hc = j.get("handicap")
            if not (isinstance(hc, list) and hc and int(hc[0]) == ours):
                continue
            win = " ".join((j.get("result") or {}).get("winner_specs") or [])
            if "Apex" not in win and "BARb" not in win:
                continue
            ex = explored(os.path.dirname(r))
            if "Apex" in win:
                ew, nw = (ew + 1, nw) if ex else (ew, nw + 1)
            else:
                el, nl = (el + 1, nl) if ex else (el, nl + 1)
    return nw, nl, ew, el


def main(argv):
    ours = our_bonus()
    nw, nl, ew, el = record(ours)
    nxt = ours
    rate = nw / float(nw + nl) if nw + nl else 0.0
    if nw + nl >= MIN_DECIDED and rate > 0.5 and ours > BARB:
        nxt = max(BARB, ours - STEP)
    sys.stderr.write("barb_handicap: +%d -> +%d (normal %d-%d %.0f%%, need %d decided; discovery %d-%d)\n"
                     % (ours, nxt, nw, nl, 100 * rate, MIN_DECIDED, ew, el))
    if "--dry-run" not in argv:
        with open(STATE, "w") as f:
            f.write("%d\n" % nxt)
    print("%d,%d" % (nxt, BARB))


if __name__ == "__main__":
    main(sys.argv[1:])
