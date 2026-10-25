"""Score the enemy-army estimates each seat logs (apex: foemem) against the true standing army (BARAI_STATS armyReal
+ armyCheap of every team on the other alliance, less armyAir where the game logged it). Before armyAir, truth
includes aircraft and the ground-only estimates read low in an air game.

    python tools/armyest_score.py <match dir or glob> [...] [--from 5] [--to 60]

Per candidate: median of estimate/truth, and the spread (the 25th-75th percentile of log2 of the ratio), over every
seat-minute with a true enemy army over 500 metal."""
import glob
import math
import re
import statistics
import sys
from pathlib import Path

STAT = re.compile(r"\[BARAI_STATS\] team=(\d+) ally=(\d+) reason=periodic frame=(\d+) .*?armyReal=(\d+) armyCheap=(\d+)")
FM = re.compile(r"\[([0-9.]+)m t(\d+)\] apex: foemem t=\d+ .*?liveM=(\d+) memM=(\d+) lostM=(\d+) .*?armyCost=(\d+) "
                r"raw=(\d+) fresh=(\d+)")
AIR = re.compile(r" armyAir=(\d+)")   # games since 10-24 log it: truth is then ground only, like the estimates
NAMES = ["live", "live+mem", "believed", "armyCost", "raw", "fresh", "lost.25", "lost.5", "lost.75",
         "mirror", "geo(l.5,mir)", "max(l.5,mir/2)", "geo.25", "geo.75", "armyest"]
AE = re.compile(r"\[([0-9.]+)m t(\d+)\] apex: armyest t=\d+ ours=(\d+) .*? theirs=(\d+)")


def one(path, lo, hi, rows):
    truth = {}
    ally = {}
    aest = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        m = STAT.search(line)
        if m:
            t, a, f = int(m[1]), int(m[2]), int(m[3])
            ally[t] = a
            air = AIR.search(line)
            truth.setdefault(f, {})[t] = int(m[4]) + int(m[5]) - (int(air[1]) if air else 0)
            continue
        m = AE.search(line)
        if m:
            aest[(round(float(m[1])), int(m[2]))] = (int(m[3]), int(m[4]))
            continue
        m = FM.search(line)
        if m:
            minute, seat = float(m[1]), int(m[2])
            live, mem, lost = int(m[3]), int(m[4]), int(m[5])
            cand = [live, live + mem, live + mem + lost, int(m[6]), int(m[7]), int(m[8])]
            rows.append((path, minute, seat, cand))
    out = []
    frames = sorted(truth)
    for path_, minute, seat, cand in rows:
        if path_ != path or not (lo <= minute <= hi) or seat not in ally or not frames:
            continue
        f = min(frames, key=lambda x: abs(x - minute * 1800))
        if abs(f - minute * 1800) > 1800:
            continue
        foe = sum(v for t, v in truth[f].items() if ally.get(t) != ally[seat])
        ours = sum(v for t, v in truth[f].items() if ally.get(t) == ally[seat])
        live, mem, lost = cand[0], cand[1] - cand[0], cand[2] - cand[1]
        ext = list(cand)
        for w in (0.25, 0.5, 0.75):
            ext.append(live + mem + w * lost)
        ext.append(ours)
        half = live + mem + 0.5 * lost
        ext.append(math.sqrt(max(half, 1.0) * max(ours, 1.0)))
        ext.append(max(half, 0.5 * ours))
        for a in (0.25, 0.75):
            ext.append(math.exp(a * math.log(max(half, 1.0)) + (1 - a) * math.log(max(ours, 1.0))))
        ext.append(aest.get((round(minute), seat), (0, 0))[1])
        if foe > 500:
            out.append((ext, foe, ours))
    return out


def main():
    args = sys.argv[1:]
    lo, hi = 5.0, 60.0
    if "--from" in args:
        i = args.index("--from")
        lo = float(args[i + 1])
        del args[i:i + 2]
    if "--to" in args:
        i = args.index("--to")
        hi = float(args[i + 1])
        del args[i:i + 2]
    paths = []
    for a in args:
        for p in sorted(glob.glob(a)):
            q = Path(p)
            paths.append(q / "infolog.txt" if q.is_dir() else q)
    samples = []
    games = 0
    for p in paths:
        if not p.exists():
            continue
        rows = []
        got = one(str(p), lo, hi, rows)
        if got:
            games += 1
            samples += got
    print(f"{games} games, {len(samples)} seat-minutes (minutes {lo:g}-{hi:g}, true enemy army > 500)")
    clear = [(c, foe, ours) for c, foe, ours in samples if ours > 0 and (ours / foe > 1.5 or ours / foe < 1 / 1.5)]
    print(f"  ('side right' = of {len(clear)} seat-minutes where one side truly had 1.5x the other, the share where "
          f"the estimate put the same side ahead by any margin)")
    for k, name in enumerate(NAMES):
        # a seat that does not log a candidate (an older release) reads 0: not a sample of it
        r = [c[k] / foe for c, foe, _ in samples if foe > 0 and (c[k] > 0 or k < len(NAMES) - 1)]
        mine = [x for x in clear if x[0][k] > 0 or k < len(NAMES) - 1]
        right = sum(1 for c, foe, ours in mine if c[k] > 0 and ((ours / foe > 1) == (ours / c[k] > 1)))
        side = f"   side right {100.0 * right / len(mine):3.0f}% of {len(mine)}" if mine else ""
        lg = sorted(math.log2(x) for x in r if x > 0)
        zero = sum(1 for x in r if x <= 0)
        if not lg:
            print(f"  {name:10s} no data")
            continue
        q1 = lg[len(lg) // 4]
        q3 = lg[(3 * len(lg)) // 4]
        print(f"  {name:10s} median est/true {statistics.median(r):5.2f}   middle half x{2 ** q1:4.2f}..x{2 ** q3:4.2f}"
              f"   spread {q3 - q1:4.2f} doublings   zero {zero}{side}")


if __name__ == "__main__":
    main()
