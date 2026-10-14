"""Did the one army form, and what did the army heads play? Minute by minute, per team.

    python tools/armyheads.py <match dir | infolog.txt> [--team N]

From the C++ `apex: army-stat` line (once a game-minute per AI): ground attack squads alive, the main
army's share of their power, their power-weighted spread from it (elmos), and that minute's events --
walk (a squad walking to the army), shared (fighting its target), stage / go (the army waiting short
of a target / leaving), merge (squads fused), sw (target switches). Then the value each army head
(split, commit, stage, stand, retreat; mass and odds too) last played, from its `apex: nnval` row.
squads near 1 with share near 1 is the one army; many squads with a low share is the old play.
"""
import argparse, re, sys
from pathlib import Path

FRAME = re.compile(r"\[f=(\d+)\]")
STAT = re.compile(r"apex: army-stat t=(\d+) squads=(\d+) main=([\d.]+) all=([\d.]+) share=([\d.]+) spread=(\d+)"
                  r" walk=(\d+) shared=(\d+) stage=(\d+) go=(\d+) merge=(\d+) sw=(\d+)")
VAL = re.compile(r"apex: nnval head=(\w+) t=(\d+) f=(\d+) v=([\d.]+)")
HEADS = ("split", "commit", "stage", "stand", "retreat", "mass", "odds")


def resolve(arg):
    p = Path(arg)
    if p.is_file():
        return p
    if (p / "infolog.txt").is_file():
        return p / "infolog.txt"
    sys.exit("no infolog.txt at %s" % p)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run")
    ap.add_argument("--team", type=int)
    a = ap.parse_args(argv)
    stats = {}   # team -> minute -> row
    vals = {}    # team -> [(frame, head, v)]
    for line in resolve(a.run).open(encoding="utf-8", errors="replace"):
        if "apex: army-stat" in line:
            m, f = STAT.search(line), FRAME.search(line)
            if m and f:
                t = int(m.group(1))
                stats.setdefault(t, {})[int(f.group(1)) // 1800] = m.groups()[1:]
        elif "apex: nnval head=" in line:
            m = VAL.search(line)
            if m and m.group(1) in HEADS:
                vals.setdefault(int(m.group(2)), []).append((int(m.group(3)), m.group(1), float(m.group(4))))
    teams = sorted(set(stats) | set(vals))
    if a.team is not None:
        teams = [t for t in teams if t == a.team]
    if not teams:
        print("no army-stat or army-head lines: an older DLL/script, or no army")
        return 1
    for t in teams:
        print("team %d" % t)
        print("  min squads share spread  walk shared stage  go merge  sw | " + " ".join("%7s" % h for h in HEADS))
        rows = stats.get(t, {})
        vs = sorted(vals.get(t, []))
        last = max(list(rows) + [f // 1800 for f, _, _ in vs] or [0])
        cur = {}
        k = 0
        for mi in range(last + 1):
            while k < len(vs) and vs[k][0] // 1800 <= mi:
                cur[vs[k][1]] = vs[k][2]
                k += 1
            r = rows.get(mi)
            if r is None and not cur:
                continue
            left = ("%3d %6s %5s %6s %5s %6s %5s %3s %5s %3s" % (
                (mi, r[0], "%.2f" % float(r[3]), r[4], r[5], r[6], r[7], r[8], r[9], r[10])) if r
                else "%3d %6s %5s %6s %5s %6s %5s %3s %5s %3s" % ((mi,) + ("-",) * 9))
            print("  " + left + " | " + " ".join("%7s" % ("%.2f" % cur[h] if h in cur else "-") for h in HEADS))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
