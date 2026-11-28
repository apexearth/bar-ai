"""Per team, from a recorded replay (replay_orders.py orders.txt.gz): human or AI, metal killed and lost, the
trade, and whether its alliance won. For his online games: how our bots did against people.

    python tools/mp_teams.py <replay-orders dir> [...]
"""
import gzip
import sys
from collections import defaultdict
from pathlib import Path


def read(d):
    cost, team_ally, is_ai, winners = {}, {}, {}, set()
    lost, killed, last = defaultdict(float), defaultdict(float), 0
    with gzip.open(Path(d) / "orders.txt.gz", "rt", errors="replace") as f:
        for ln in f:
            t = ln[:2]
            if t == "D ":
                p = ln.split()
                cost[int(p[1])] = float(p[4])
            elif t == "T ":
                p = ln.split()
                team_ally[int(p[1])] = int(p[2])
                is_ai[int(p[1])] = p[3] == "true"
            elif t == "K ":
                p = ln.split()
                fr, defid, team, ateam = int(p[1]), int(p[3]), int(p[4]), int(p[9])
                last = max(last, fr)
                m = cost.get(defid, 0.0)
                if ateam >= 0 and team_ally.get(ateam) != team_ally.get(team):
                    lost[team] += m
                    killed[ateam] += m
            elif t == "W ":
                winners.update(int(x) for x in ln.split()[2:])
    return team_ally, is_ai, lost, killed, winners, last


def summary(dirs):
    """One line a game: AI teams' and humans' summed trade, and whether the alliance holding AI teams won."""
    for d in dirs:
        try:
            ta, ai, lost, killed, win, last = read(d)
        except (OSError, EOFError):
            continue
        if not ta or last < 1800 * 5:
            continue
        g = {True: [0.0, 0.0], False: [0.0, 0.0]}
        for t in ta:
            g[ai[t]][0] += killed[t]
            g[ai[t]][1] += lost[t]
        ai_allies = {ta[t] for t in ta if ai[t]}
        hum_allies = {ta[t] for t in ta if not ai[t] and (killed[t] or lost[t])}
        kind = "mixed" if ai_allies & hum_allies else "AI-vs-human"
        res = "AI side won" if win & ai_allies and not win & hum_allies - ai_allies else (
            "AI side lost" if win else "?")
        print("%s %3d min  %-11s AI trade %5.2f  humans %5.2f  %s" % (
            Path(d).name[:10], last // 1800, kind, g[True][0] / max(g[True][1], 1), g[False][0] / max(g[False][1], 1),
            res if kind != "mixed" else ""))


if __name__ == "__main__":
    if sys.argv[1] == "--summary":
        summary(sorted(sys.argv[2:]))
        sys.exit()
    for d in sys.argv[1:]:
        ta, ai, lost, killed, win, last = read(d)
        print("%s  (%d min, winners ally %s)" % (Path(d).name[:60], last // 1800, sorted(win) or "?"))
        for t in sorted(ta):
            print("  t%-2d ally %d %-5s killed %8.0f lost %8.0f trade %5.2f %s" % (
                t, ta[t], "AI" if ai[t] else "human", killed[t], lost[t], killed[t] / max(lost[t], 1.0),
                "WON" if ta[t] in win else ""))
