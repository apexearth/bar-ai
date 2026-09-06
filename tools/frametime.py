"""Sim speed per frame vs unit count, from any infolog.

Every engine log line carries [t=wall][f=frame], so wall-per-frame needs no
instrumentation; unit counts come from the apex logs already in the file
(facqueue's held=N per player, BARAI_STATS ownUnits where the dev gadgets ran),
and the perf lines separate the AI-script share from the engine's.

    python tools/frametime.py <infolog-or-match-dir> [more...]

Output, one row per game-minute: ms/frame, total units (sum of the latest
per-player reading in the bucket), and apex script ms in that bucket.
"""
import re
import sys
from pathlib import Path

LINE = re.compile(r"\[t=(\d+):(\d+):(\d+\.\d+)\]\[f=(\d+)\]")
HELD = re.compile(r"Skirmish AI <([^>]+)>.*?\[[\d.]+m t(\d+)\].*held=(\d+)")
OWN = re.compile(r"team=(\d+).*?ownUnits=(\d+)")
PERF = re.compile(r"perf Ai(?:MakeTask|Update) calls=\d+ totalMs=([\d.]+)")
# apex: perf AiFrame calls=N totalMs=X avgUs=Y maxMs=Z -- the WHOLE AI
# (scheduler, threat/infl maps, task reevaluation, script) per player.
AIFR = re.compile(r"perf AiFrame calls=\d+ totalMs=([\d.]+) avgUs=[\d.]+ maxMs=([\d.]+)")
# apex: perf sec <name> calls=N totalMs=X maxMs=Y -- script self-profiled sections.
SEC = re.compile(r"perf sec (\S+) calls=(\d+) totalMs=([\d.]+) maxMs=([\d.]+)")
# apex: perf jobs (ms/calls/maxMs) <name>=ms/calls/maxMs ... -- the C++ scheduler
# jobs, which are ~87% of aiMs at hour scale. Named "job:<name>" so they land in
# the same tables as the script sections; the two halves are directly comparable.
JOBS = re.compile(r"perf jobs \(ms/calls/maxMs\)(.*)$")
JOB = re.compile(r"(\S+)=([\d.]+)/(\d+)/([\d.]+)")
# apex: perf sweep <helper>=elements/calls -- how much WORK the O(n) helpers did.
SWEEP = re.compile(r"perf sweep (.*)$")
SWEEPONE = re.compile(r"(\w+)=(\d+)/(\d+)")

BUCKET = 1800  # frames per game-minute


def wall_seconds(h, m, s):
    return int(h) * 3600 + int(m) * 60 + float(s)




def secb_all(secb):
    """Every bucket index any section reported in."""
    out = set()
    for bk in secb.values():
        out.update(bk)
    return out

def analyze(path):
    first = {}   # bucket -> earliest (wall, frame)
    last = {}    # bucket -> latest (wall, frame)
    units = {}   # bucket -> {player -> count}
    script = {}  # bucket -> ms
    ai = {}      # bucket -> ms, whole-AI (AiFrame lines, all players summed)
    spike = {}   # bucket -> worst single AiFrame ms across players
    secs = {}    # name -> [ms, calls, maxMs], whole run
    perframe = {}  # frame -> AiFrame lines on it, = AIs in the game
    secb = {}    # name -> bucket -> ms, for the growth table
    sweeps = {}  # helper -> bucket -> [elements visited, calls]
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = LINE.search(line)
            if not m:
                continue
            frame = int(m.group(4))
            if frame <= 0:
                continue
            wall = wall_seconds(m.group(1), m.group(2), m.group(3))
            b = frame // BUCKET
            if b not in first or frame < first[b][1]:
                first[b] = (wall, frame)
            if b not in last or frame > last[b][1]:
                last[b] = (wall, frame)
            hm = HELD.search(line)
            if hm:
                units.setdefault(b, {})[f"t{hm.group(2)}"] = int(hm.group(3))
            om = OWN.search(line)
            if om:
                units.setdefault(b, {})[f"s{om.group(1)}"] = int(om.group(2))
            am = AIFR.search(line)
            if am:
                ai[b] = ai.get(b, 0.0) + float(am.group(1))
                spike[b] = max(spike.get(b, 0.0), float(am.group(2)))
                # Each AI flushes its own AiFrame line, and in self-play they
                # all log under the same <name>, so the only way to count them
                # is how many land on one frame.
                perframe[frame] = perframe.get(frame, 0) + 1
                continue
            sm_ = SEC.search(line)
            if sm_:
                e = secs.setdefault(sm_.group(1), [0.0, 0, 0.0])
                e[0] += float(sm_.group(3))
                e[1] += int(sm_.group(2))
                e[2] = max(e[2], float(sm_.group(4)))
                # Per-minute too: a section's GROWTH matters more than its total
                # for a long game. These lines are per-window, not cumulative.
                secb.setdefault(sm_.group(1), {})
                secb[sm_.group(1)][b] = (secb[sm_.group(1)].get(b, 0.0)
                                         + float(sm_.group(3)))
                continue
            jm = JOBS.search(line)
            if jm:
                for name, ms, calls, mx in JOB.findall(jm.group(1)):
                    key = "job:" + name
                    e = secs.setdefault(key, [0.0, 0, 0.0])
                    e[0] += float(ms)
                    e[1] += int(calls)
                    e[2] = max(e[2], float(mx))
                    secb.setdefault(key, {})
                    secb[key][b] = secb[key].get(b, 0.0) + float(ms)
                continue
            wm = SWEEP.search(line)
            if wm:
                for name, elems, calls in SWEEPONE.findall(wm.group(1)):
                    e = sweeps.setdefault(name, {})
                    e[b] = [e.get(b, [0, 0])[0] + int(elems),
                            e.get(b, [0, 0])[1] + int(calls)]
                continue
            pm = PERF.search(line)
            if pm:
                script[b] = script.get(b, 0.0) + float(pm.group(1))

    print(f"\n{path}")
    print(f"{'min':>4} {'ms/frame':>9} {'units':>6} {'aiMs':>8} {'ai%':>6} "
          f"{'scriptMs':>9} {'script%':>8} {'spikeMs':>8}")
    carry = {}
    for b in sorted(last):
        w0, f0 = first[b]
        w1, f1 = last[b]
        if f1 <= f0:
            continue
        mspf = (w1 - w0) * 1000.0 / (f1 - f0)
        carry.update(units.get(b, {}))
        total = sum(carry.values()) if carry else 0
        sm = script.get(b, 0.0)
        am_ = ai.get(b, 0.0)
        wall_ms = (w1 - w0) * 1000.0
        share = (100.0 * sm / wall_ms) if wall_ms > 0 else 0.0
        aishare = (100.0 * am_ / wall_ms) if wall_ms > 0 else 0.0
        print(f"{b:>4} {mspf:>9.2f} {total:>6} {am_:>8.0f} {aishare:>5.1f}% "
              f"{sm:>9.0f} {share:>7.1f}% {spike.get(b, 0.0):>8.1f}")
    # THE 16-AI BUDGET (apexearth 2026-09-05: sixteen of these in an hour-long
    # game, never below 1x). 1x is 30 sim frames/s, so the WHOLE frame -- engine
    # sim, pathing and every AI -- must fit in 33.3 ms. aiMs is summed over the
    # AIs present, so divide by how many actually logged before scaling up.
    nai = max(perframe.values()) if perframe else 0
    if nai and last:
        peak = max(last, key=lambda b: ai.get(b, 0.0))
        per_ai = ai.get(peak, 0.0) / nai / float(BUCKET)   # ms per AI per frame
        proj = per_ai * 16.0
        share = 33.33 * 0.20          # the AI's working share of one frame
        print()
        print(f"  16-AI budget, worst game-minute (min {peak}, {nai} AI here):")
        print(f"    per AI per frame   {per_ai:>8.3f} ms")
        print(f"    x16                {proj:>8.2f} ms of the 33.33 ms frame"
              f"  ({100.0 * proj / 33.33:.0f}%)")
        over = per_ai / (share / 16.0)
        print(f"    verdict            {'PASS' if proj <= share else 'FAIL'}"
              f" -- {'within' if over <= 1.0 else f'{over:.1f}x over'}"
              f" the 20% share (<= {share / 16.0:.3f} ms per AI per frame)")

    if sweeps:
        # Elements walked, not time. A helper whose visited count climbs faster
        # than the unit count is the quadratic one, whatever its clock says.
        bs = sorted({b for h in sweeps.values() for b in h})
        show = [b for b in bs if b % 10 == 0] + bs[-1:]
        print(f"\n  O(n) helper census, elements visited / calls per minute:")
        print("  " + f"{'min':>4}" + "".join(f"{n:>22}" for n in sorted(sweeps)))
        for b in sorted(set(show)):
            row = "".join(
                f"{sweeps[n].get(b, [0, 0])[0]:>14,}/{sweeps[n].get(b, [0, 0])[1]:<7,}"
                for n in sorted(sweeps))
            print(f"  {b:>4}{row}")

    if secs:
        print(f"\n  sections, whole run (all players summed; job: = C++ scheduler):")
        print(f"  {'section':<16} {'totalMs':>9} {'calls':>8} {'avgUs':>7} {'maxMs':>7}")
        for name, (ms, calls, mx) in sorted(secs.items(), key=lambda kv: -kv[1][0]):
            avg = (ms * 1000.0 / calls) if calls else 0.0
            print(f"  {name:<16} {ms:>9.0f} {calls:>8} {avg:>7.0f} {mx:>7.1f}")

    # WHAT BREAKS AN HOUR-LONG GAME IS THE SLOPE, NOT THE TOTAL. Units grew ~29x
    # over this window in the reference run, so a section growing faster than the
    # unit count is super-linear -- at 16 AIs and hour-long unit counts those
    # dominate everything, however small they look today.
    if secb and units:
        peakb = max(units, key=lambda b: sum(units[b].values()))
        carry2, ucount = {}, {}
        for b in sorted(units):
            carry2.update(units[b])
            ucount[b] = sum(carry2.values())
        early_bs = [b for b in sorted(secb_all(secb)) if 1 <= b <= 5]
        late_bs = [b for b in sorted(secb_all(secb)) if b >= max(6, peakb - 5)]
        if early_bs and late_bs:
            ue = max(1, sum(ucount.get(b, 0) for b in early_bs) / len(early_bs))
            ul = sum(ucount.get(b, 0) for b in late_bs) / len(late_bs)
            print()
            print(f"  growth, min {early_bs[0]}-{early_bs[-1]} vs "
                  f"{late_bs[0]}-{late_bs[-1]} (units {ue:.0f} -> {ul:.0f}, "
                  f"{ul / ue:.0f}x) -- above that is super-linear:")
            print(f"  {'section':<22}{'totalMs':>9}{'early':>8}{'late':>9}{'growth':>8}")
            rows = []
            for name, bk in secb.items():
                tot = sum(bk.values())
                if tot < 300:
                    continue
                e = sum(bk.get(b, 0.0) for b in early_bs) / len(early_bs)
                l = sum(bk.get(b, 0.0) for b in late_bs) / len(late_bs)
                g = (l / e) if e > 0.05 else float("inf")
                rows.append((g, name, tot, e, l))
            for g, name, tot, e, l in sorted(rows, reverse=True,
                                             key=lambda r: r[0])[:14]:
                gs = "inf" if g == float("inf") else f"{g:.0f}x"
                flag = " <<" if g > (ul / ue) else ""
                print(f"  {name:<22}{tot:>9.0f}{e:>8.1f}{l:>9.1f}{gs:>8}{flag}")



def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    for arg in sys.argv[1:]:
        p = Path(arg)
        if p.is_dir():
            p = p / "infolog.txt"
        if not p.exists():
            print(f"missing: {p}")
            continue
        analyze(p)


if __name__ == "__main__":
    main()
