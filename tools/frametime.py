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

BUCKET = 1800  # frames per game-minute


def wall_seconds(h, m, s):
    return int(h) * 3600 + int(m) * 60 + float(s)


def analyze(path):
    first = {}   # bucket -> earliest (wall, frame)
    last = {}    # bucket -> latest (wall, frame)
    units = {}   # bucket -> {player -> count}
    script = {}  # bucket -> ms
    ai = {}      # bucket -> ms, whole-AI (AiFrame lines, all players summed)
    spike = {}   # bucket -> worst single AiFrame ms across players
    secs = {}    # name -> [ms, calls, maxMs], whole run
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
                continue
            sm_ = SEC.search(line)
            if sm_:
                e = secs.setdefault(sm_.group(1), [0.0, 0, 0.0])
                e[0] += float(sm_.group(3))
                e[1] += int(sm_.group(2))
                e[2] = max(e[2], float(sm_.group(4)))
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
    if secs:
        print(f"\n  script sections, whole run (all players summed):")
        print(f"  {'section':<16} {'totalMs':>9} {'calls':>8} {'avgUs':>7} {'maxMs':>7}")
        for name, (ms, calls, mx) in sorted(secs.items(), key=lambda kv: -kv[1][0]):
            avg = (ms * 1000.0 / calls) if calls else 0.0
            print(f"  {name:<16} {ms:>9.0f} {calls:>8} {avg:>7.0f} {mx:>7.1f}")


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
