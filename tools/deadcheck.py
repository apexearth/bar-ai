"""Rules that never fired: the shape every silent bug this repo has had.

Each of these looked healthy. Each did nothing, for weeks, with no error:

    nanopull  ... static=1806 hasOutput=4   pulled=4     the release was a no-op
    raidsticky  hadPrev=40   noPrev=461     applied=29   82 lines after
                                                         SetTarget(nullptr)
    raidgate  passes=139     cand=1476      noBest=135   97% of picks chose
                                                         nothing

The pattern is always the same: an ACTION counter near zero beside a
DENOMINATOR that is large. Nothing in a compile, a smoke test, a win rate or a
composition table can see it -- the code runs, it just never does anything.

So this reads a match log and reports every `apex:` census line where an action
term is zero (or tiny) against a healthy denominator.

    python tools/deadcheck.py <run>
    python tools/deadcheck.py <run> --ratio 0.02   # stricter "tiny"

NONE OF THESE IS AN ERROR. `guardsum picks=337 flips=0` is a rule correctly
declining to act -- the defence anchor really is stable. The output is a list
of questions: is this rule choosing not to fire, or unable to?
"""

import argparse
import collections
import pathlib
import re
import sys

LINE = re.compile(r"apex: (?P<tag>[a-z_-]+) (?P<body>.*)")
FIELD = re.compile(r"\b(?P<k>[A-Za-z_][A-Za-z0-9_]*)=(?P<v>-?\d+(?:\.\d+)?)\b")

# Terms that mean "the rule DID something". Zero here is the interesting case.
ACTION = ("applied", "fired", "pulled", "refused", "flips", "promoted",
          "released", "switched", "taken", "chosen", "sent", "acted", "hit",
          "held")
# Terms that mean "the rule had the CHANCE to do something".
DENOM = ("passes", "seen", "cand", "picks", "candidates", "checked", "tried",
         "asks", "samples", "n", "total", "pools", "turrets")


def find_log(arg):
    p = pathlib.Path(arg)
    if p.is_dir():
        c = p / "infolog.txt"
        if c.exists():
            return c
        raise SystemExit("no infolog.txt in %s" % p)
    if p.exists():
        return p
    here = pathlib.Path(__file__).resolve().parent.parent
    c = here / "matches" / arg / "infolog.txt"
    if c.exists():
        return c
    raise SystemExit("cannot find a log for %r" % arg)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run")
    ap.add_argument("--ratio", type=float, default=0.05,
                    help="action/denominator below this counts as 'barely fired'")
    ap.add_argument("--min-denom", type=int, default=20,
                    help="ignore censuses that never got a real chance")
    args = ap.parse_args()

    # keep the LAST census of each tag: these counters are cumulative
    last = {}
    with open(find_log(args.run), "r", errors="replace") as fh:
        for line in fh:
            if "apex: " not in line:
                continue
            m = LINE.search(line)
            if m is None:
                continue
            fields = {f.group("k"): float(f.group("v"))
                      for f in FIELD.finditer(m.group("body"))}
            if not fields:
                continue
            acts = [k for k in fields if k.lower() in ACTION]
            dens = [k for k in fields if k.lower() in DENOM]
            if acts and dens:
                last[m.group("tag")] = fields

    if not last:
        print("No `apex:` census lines with both an action and a denominator.")
        print("Add one: a rule that can decline to act should count how often")
        print("it was ASKED and how often it ACTED.")
        return 0

    dead, thin, ok = [], [], []
    for tag, f in sorted(last.items()):
        den = max(f[k] for k in f if k.lower() in DENOM)
        act = max(f[k] for k in f if k.lower() in ACTION)
        if den < args.min_denom:
            continue
        row = (tag, act, den, f)
        if act == 0:
            dead.append(row)
        elif act / den < args.ratio:
            thin.append(row)
        else:
            ok.append(row)

    def show(rows, head):
        if not rows:
            return
        print(head)
        for tag, act, den, f in rows:
            body = " ".join("%s=%g" % (k, v) for k, v in f.items())
            print("  %-14s %s" % (tag, body))
            print("  %-14s   acted %g of %g asked (%.1f%%)"
                  % ("", act, den, 100.0 * act / den if den else 0.0))
        print("")

    show(dead, "NEVER FIRED -- was this rule unable to act, or choosing not to?")
    show(thin, "BARELY FIRED (under %.0f%%) -- is the gate above it eating everything?"
         % (100 * args.ratio))
    if ok:
        print("acting normally: " + ", ".join(t for t, _, _, _ in ok))
    print("")
    print("None is an error. Each is the question: can this rule act at all?")
    return 0


if __name__ == "__main__":
    sys.exit(main())
