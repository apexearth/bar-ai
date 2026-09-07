"""What the army actually DID, scored against apexearth's own complaints.

He can watch a game and know in ten seconds that it is garbage. This session had
no equivalent -- every finding came from reading code backwards and guessing at
mechanism, and six real defects were found without one of them being shown to
win a game. apexearth, 2026-09-08:

    "you have no good way to understand the effects of what you're doing. fuck
    if you could just watch it like me you'd see how obviously terrible it is."

That is the actual problem, and this is the substitute for eyes. Each detector
below is one of his repeated complaints turned into a number, so a change can be
scored against the things he says are wrong instead of against my reasoning.

    python tools/behave.py <run>                 # one match or tournament dir
    python tools/behave.py <run> --control <run>  # against a baseline

REQUIRES the per-order trace, which is off by default because it is one line
per order:

    python tools/run_match.py ... --modoption apex_order_trace=1

Without it the order detectors say NO DATA rather than passing silently -- an
absent detector must never read as a clean bill of health.

## The detectors, and the complaint each one is

  standing        "they get redirected to stand around and do nothing"
                  Orders that send a unit somewhere to STAND (post, ring,
                  regroup, patrol) against orders that send it to FIGHT
                  (engage, attack, combat). Measured 2026-09-08 at 100:13.

  churn           "Every time I say 'defend our flanks better' it becomes this
                  overriding behavior that stupors a bunch of other behaviors.
                  It is terribly tempermental."
                  Consecutive orders to ONE unit from DIFFERENT subsystems that
                  move it a long way in a short time: one system countermanding
                  another. Reported per source PAIR, so the culprit is named.

  idle            "we stand around worthlessly going in circles never
                  accomplishing anything"
                  Units that received orders all game and never once got an
                  engage/attack order.

  arrival         "we never make it to enemy bases"
                  Whether an ATTACK task ever existed, and for how much of the
                  game. `fightcensus` reads attack=0/0/0 with thousands of
                  metal sitting in DEFEND.

  fragments       "The enemy tends to come at us with one big blob... Our army
                  tends to be very spread out so we die to them piece by piece."
                  Our largest squad against their largest group, from the
                  `squadsize` census.

  aa_no_air       "we have 17 AA and the enemy has no air"
                  Anti-air production decisions while the enemy air census
                  reads zero.

None of these is a win rate. They are behaviours he has named as wrong, so a
change that fixes one has done something real even if the game is still lost.
"""

import argparse
import collections
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent

# Orders that park a unit somewhere against orders that commit it to a fight.
# `travel`/`fightwalk`/`build`/`scout` are transport, not a posture, so they are
# counted apart rather than held against either side.
STAND = {"post", "ring", "regroup", "patrol", "rally", "standoff", "retreat"}
FIGHT = {"engage", "attack", "combat", "sniper"}

ORD = re.compile(
    r"apex: ord t=(?P<t>\d+) u=(?P<u>\d+) (?P<def>\S+) f=(?P<f>\d+) "
    r"src=(?P<src>\w+) kind=(?P<kind>\w+) to=(?P<x>-?[\d.]+),(?P<z>-?[\d.]+) "
    r"tgt=(?P<tgt>-?\d+) jump=(?P<jump>-?[\d.]+) gap=(?P<gap>-?\d+) "
    r"task=\S+ dup=(?P<dup>\d+) q=(?P<q>\d+)")
SQUAD = re.compile(r"squadsize own n=(\d+) avg=([\d.]+) max=(\d+) \| "
                   r"enemy n=(\d+) avg=([\d.]+) max=(\d+)")
CENSUS = re.compile(r"fightcensus .*?defend=(\d+)/(\d+)/(\d+).*?attack=(\d+)/(\d+)/(\d+)")
PRODUCE = re.compile(r"produce:(\w+)")
AIRRAW = re.compile(r"enemyAirRaw=(\d+)")

AA_DEFS = {"armjeth", "armaak", "armfig", "corcrash", "coraak", "corveng",
           "armaas", "armah", "corah"}


def logs(run: pathlib.Path):
    """Every infolog under a match or tournament directory."""
    if (run / "infolog.txt").is_file():
        return [run / "infolog.txt"]
    return sorted(run.glob("matches/*/infolog.txt")) or sorted(run.glob("*/infolog.txt"))


class Result:
    def __init__(self):
        self.stand = 0
        self.fight = 0
        self.other = collections.Counter()
        self.churn = collections.Counter()   # (srcA, srcB) -> count
        self.orders = 0
        self.per_unit = collections.defaultdict(lambda: {"n": 0, "fight": 0})
        self.squad_own = []
        self.squad_foe = []
        self.attack_samples = 0
        self.attack_live = 0
        self.defend_metal = []
        self.produce = collections.Counter()
        self.air_raw = 0
        self.games = 0
        self.have_trace = False


def scan(paths, team="0") -> Result:
    r = Result()
    # A countermand: another subsystem moved this unit a long way, soon after.
    # 300 elmos is four building widths -- not a path waypoint. 90 frames is
    # 3s, the window NoteOrder itself uses for "the previous order is plausibly
    # still running".
    JUMP, GAP = 300.0, 90
    for p in paths:
        r.games += 1
        last = {}
        try:
            text = p.read_text("utf-8", errors="replace")
        except OSError:
            continue
        for line in text.splitlines():
            if "apex: ord " in line:
                m = ORD.search(line)
                if not m or m.group("t") != team:
                    continue
                r.have_trace = True
                src = m.group("src")
                r.orders += 1
                u = m.group("u")
                r.per_unit[u]["n"] += 1
                if src in FIGHT:
                    r.fight += 1
                    r.per_unit[u]["fight"] += 1
                elif src in STAND:
                    r.stand += 1
                else:
                    r.other[src] += 1
                f, jump = int(m.group("f")), float(m.group("jump"))
                # q=1 is a SHIFT order: APPENDED to the queue, not a
                # replacement. CCircuitUnit::Attack queues a fight order to the
                # target position after every attack as a LOS workaround, and
                # MoveAction queues a lookahead waypoint every step. Counting
                # those as countermands inflated `ring` into the top offender in
                # every arm and was pure artefact -- the same warning is written
                # at the trace's own call site.
                if m.group("q") == "1":
                    continue
                prev = last.get(u)
                if (prev and prev[0] != src and jump >= JUMP
                        and 0 <= f - prev[1] <= GAP):
                    r.churn[(prev[0], src)] += 1
                last[u] = (src, f)
                continue
            if "squadsize" in line:
                m = SQUAD.search(line)
                if m:
                    r.squad_own.append(int(m.group(3)))
                    r.squad_foe.append(int(m.group(6)))
                continue
            if "fightcensus" in line:
                m = CENSUS.search(line)
                if m:
                    r.attack_samples += 1
                    if int(m.group(4)) > 0:
                        r.attack_live += 1
                    r.defend_metal.append(int(m.group(3)))
                continue
            if "produce:" in line:
                for d in PRODUCE.findall(line):
                    r.produce[d] += 1
                continue
            m = AIRRAW.search(line)
            if m:
                r.air_raw = max(r.air_raw, int(m.group(1)))
    return r


def pct(a, b):
    return (100.0 * a / b) if b else 0.0


def report(r: Result, ctrl: Result = None):
    def cmp(val, cval, fmt="%.0f", lower_better=True):
        s = fmt % val
        if ctrl is None or cval is None:
            return s
        d = val - cval
        if abs(d) < 1e-9:
            return f"{s}   (control {fmt % cval}, same)"
        good = (d < 0) == lower_better
        return f"{s}   (control {fmt % cval}, {'better' if good else 'WORSE'})"

    print("=" * 74)
    print("BEHAVIOUR  %d game(s)%s" % (r.games, "" if ctrl is None
                                       else "  vs control %d game(s)" % ctrl.games))
    print()

    print("1. standing  -- \"redirected to stand around and do nothing\"")
    if not r.have_trace:
        print("   NO DATA -- rerun with --modoption apex_order_trace=1")
    else:
        ratio = (r.stand / r.fight) if r.fight else float("inf")
        cratio = None
        if ctrl and ctrl.have_trace:
            cratio = (ctrl.stand / ctrl.fight) if ctrl.fight else float("inf")
        print("   park orders %d  vs  fight orders %d" % (r.stand, r.fight))
        print("   stand:fight = %s" % cmp(ratio, cratio, "%.1f"))
        if r.other:
            print("   (transport, not counted: %s)"
                  % ", ".join("%s=%d" % kv for kv in r.other.most_common(5)))
    print()

    print("2. churn  -- \"one behaviour stupors the others\"")
    if not r.have_trace:
        print("   NO DATA -- rerun with --modoption apex_order_trace=1")
    else:
        tot = sum(r.churn.values())
        ctot = sum(ctrl.churn.values()) if ctrl and ctrl.have_trace else None
        print("   countermands (>=300 elmo reversal within 3s, different source): %s"
              % cmp(tot, ctot))
        for (a, b), n in r.churn.most_common(6):
            print("     %-10s -> %-10s %d" % (a, b, n))
    print()

    print("3. idle  -- units that never got a single fight order")
    if not r.have_trace:
        print("   NO DATA")
    else:
        never = sum(1 for v in r.per_unit.values() if v["fight"] == 0)
        cnever = (sum(1 for v in ctrl.per_unit.values() if v["fight"] == 0)
                  if ctrl and ctrl.have_trace else None)
        print("   %s of %d units ordered all game" % (cmp(never, cnever), len(r.per_unit)))
    print()

    print("4. arrival  -- \"we never make it to enemy bases\"")
    if r.attack_samples:
        share = pct(r.attack_live, r.attack_samples)
        cshare = (pct(ctrl.attack_live, ctrl.attack_samples)
                  if ctrl and ctrl.attack_samples else None)
        print("   samples with an ATTACK task alive: %s%%"
              % cmp(share, cshare, "%.0f", lower_better=False))
        if r.defend_metal:
            peak = max(r.defend_metal)
            cpeak = max(ctrl.defend_metal) if ctrl and ctrl.defend_metal else None
            print("   peak metal parked in DEFEND: %s" % cmp(peak, cpeak))
    else:
        print("   NO DATA -- no fightcensus lines")
    print()

    print("5. fragments  -- \"they come as one blob, we arrive in pieces\"")
    if r.squad_own:
        ours, foes = max(r.squad_own), max(r.squad_foe)
        cours = max(ctrl.squad_own) if ctrl and ctrl.squad_own else None
        print("   our largest squad %s   |   their largest group %d"
              % (cmp(ours, cours, "%.0f", lower_better=False), foes))
    else:
        print("   NO DATA -- no squadsize lines")
    print()

    print("6. aa_no_air  -- \"17 AA and the enemy has no air\"")
    tot = sum(r.produce.values())
    aa = sum(n for d, n in r.produce.items() if d in AA_DEFS)
    if tot:
        caa = None
        if ctrl and sum(ctrl.produce.values()):
            caa = pct(sum(n for d, n in ctrl.produce.items() if d in AA_DEFS),
                      sum(ctrl.produce.values()))
        print("   enemy air ever seen: %d" % r.air_raw)
        print("   anti-air share of production: %s%%  (%d of %d)"
              % (cmp(pct(aa, tot), caa, "%.0f"), aa, tot))
        if r.air_raw == 0 and aa > 0:
            print("   ^^ bought anti-air against an enemy that never flew")
    else:
        print("   NO DATA -- no produce: lines")
    print()
    print("These are behaviours, not wins. A change that moves one has done")
    print("something real; whether it wins games is run_tournament's question.")
    print("=" * 74)


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run", help="match or tournament directory")
    ap.add_argument("--control", help="baseline to compare against")
    ap.add_argument("--team", default="0", help="our team id (default 0)")
    args = ap.parse_args()

    run = pathlib.Path(args.run)
    if not run.is_dir():
        run = REPO / args.run
    paths = logs(run)
    if not paths:
        print("no infolog under %s" % run, file=sys.stderr)
        return 2
    ctrl = None
    if args.control:
        cpath = pathlib.Path(args.control)
        if not cpath.is_dir():
            cpath = REPO / args.control
        cpaths = logs(cpath)
        if not cpaths:
            print("no infolog under %s" % cpath, file=sys.stderr)
            return 2
        ctrl = scan(cpaths, args.team)
    report(scan(paths, args.team), ctrl)
    return 0


if __name__ == "__main__":
    sys.exit(main())
