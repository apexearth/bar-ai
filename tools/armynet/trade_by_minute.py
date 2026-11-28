"""Trade over time per side of a model_vs_rules / model_vs_model set, from each game's death lines.

Per bucket (default 4 min), mean per game still running: mobile metal lost, mobile metal killed, building metal
killed (finished buildings only), and their running totals. The side named "model" in the run log is the candidate;
the other side is the rules army or the played model. Deaths in the last 2 s of a game (the end-of-game wipe) are
left out.

    python tools/armynet/trade_by_minute.py runtime/armynet/mvr-mvm-h2.log [--bucket 4]
"""
import argparse
import json
import re
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEATH = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=\S+ cost=([\d.]+) .*? built=(\d) mob=(\d)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("logs", nargs="+")
    ap.add_argument("--bucket", type=float, default=4.0, help="minutes per bucket")
    a = ap.parse_args()
    games = []
    for log in a.logs:
        for ln in open(log, encoding="utf-8"):
            p = ln.split()
            if len(p) >= 7 and p[0] == "seed":
                games.append((int(p[3].lstrip("t")), REPO / p[6]))
    bf = a.bucket * 60 * 30
    sums = {s: defaultdict(lambda: [0.0, 0.0, 0.0]) for s in ("model", "other")}
    alive = defaultdict(int)
    for mt, m in games:
        end = json.loads((m / "result.json").read_text())["result"].get("game_frames", 0)
        for b in range(int((end - 61) // bf) + 1):
            alive[b] += 1
        for ln in open(m / "infolog.txt", encoding="utf-8", errors="replace"):
            d = DEATH.search(ln)
            if not d:
                continue
            f, team, cost, built, mob = int(d[1]), int(d[2]), float(d[3]), d[4] == "1", d[5] == "1"
            if f > end - 60:
                continue
            b = int(f // bf)
            victim = "model" if team == mt else "other"
            killer = "other" if victim == "model" else "model"
            if mob:
                sums[victim][b][0] += cost
                sums[killer][b][1] += cost
            elif built:
                sums[killer][b][2] += cost
    print("%d games; per game still running; mobile lost / mobile killed / buildings killed (running sums of the bucket means)" % len(games))
    print("  minutes | games | model side                               | other side")
    tot = {s: [0.0, 0.0, 0.0] for s in sums}
    for b in sorted(alive):
        n = alive[b]
        cells = []
        for s in ("model", "other"):
            v = [x / n for x in sums[s][b]]
            tot[s] = [t + x for t, x in zip(tot[s], v)]
            cells.append("%5.0f / %5.0f / %5.0f (%6.0f / %6.0f / %6.0f)" % tuple(v + tot[s]))
        print("  %3.0f-%-3.0f | %5d | %s | %s" % (b * a.bucket, (b + 1) * a.bucket, n, cells[0], cells[1]))


if __name__ == "__main__":
    main()
