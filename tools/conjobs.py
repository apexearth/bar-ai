"""Where our constructors' time goes: each builder's job holds from its decision to its next one.

    python tools/conjobs.py <match dir | tournament dir | dir of apex-t*.log> [--step 5] [--by size]

Reads `apex: decide t=N <unit> #id -> <kind>/<sub>:<def>` lines (commander, factories and production
excluded). A tournament is summed over its games and split by result (W/L); --by size also splits by
team size. Shares are of constructor-seconds, so a job a con walks 6 minutes to counts 6 minutes.
His 10-14 watch game on Greenest Fields: 20-55% on radar towers and up to 58% on defence, 2% energy.
"""
import argparse
import collections
import glob

import os
import re

PAT = re.compile(r"\[f=(\d+)\].*?apex: decide t=(\d+) (\S+) #(\d+) -> ([a-z]+)/[a-z]*:?(\S*)")


def logs_of(path):
    """(team-filtered log files) for one game: per-team apex logs if present, else its infolog."""
    own = sorted(glob.glob(os.path.join(path, "apex-t*.log")))
    own = [p for p in own if re.search(r"apex-t\d+\.log$", p)]
    if own:
        return own
    p = os.path.join(path, "infolog.txt")
    return [p] if os.path.exists(p) else []


def spans(path, step):
    """{bucket: Counter(kind -> con-frames)}, {bucket: Counter((kind, def) -> con-frames)}"""
    sp = collections.defaultdict(collections.Counter)
    what = collections.defaultdict(collections.Counter)
    for lf in logs_of(path):
        last = {}
        for line in open(lf, encoding="utf-8", errors="replace"):
            m = PAT.search(line)
            if not m:
                continue
            f, team, unit, uid, kind, tgt = int(m.group(1)), m.group(2), m.group(3), m.group(4), m.group(5), m.group(6)
            if kind == "produce" or "com" in unit or unit.endswith(("lab", "plant", "gant", "yard", "hp")):
                continue
            key = team + "#" + uid
            if key in last:
                f0, k0, t0 = last[key]
                for x in range(f0, f, 300):
                    b = x // (1800 * step)
                    d = min(300, f - x)
                    sp[b][k0] += d
                    what[b][(k0, t0)] += d
            last[key] = (f, kind, tgt)
    return sp, what


def result_of(path):
    """'W', 'L', 'D' or '?' for our side, as the random search scores it."""
    try:
        import cem
        sc = cem.score(path)
        return sc[1] if sc else "?"
    except Exception:
        return "?"


def size_of(path):
    try:
        s = open(os.path.join(path, "script.txt"), encoding="utf-8", errors="replace").read()
        return max(1, len(re.findall(r"\[ai\d+\]", s, re.I)) // 2)
    except OSError:
        return 0


def show(title, sp, what, step, games=None):
    print("== %s%s" % (title, "" if games is None else " (%d games)" % games))
    for b in sorted(sp):
        c = sp[b]
        n = sum(c.values())
        if not n:
            continue
        top = " ".join("%s %d%%" % (k, round(100.0 * v / n)) for k, v in c.most_common(6))
        tops = ", ".join("%s:%s %d%%" % (k, t or "-", round(100.0 * v / n)) for (k, t), v in what[b].most_common(4))
        print("  %3d-%-3d min  %s" % (b * step, b * step + step, top))
        print("               top: %s" % tops)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path")
    ap.add_argument("--step", type=int, default=5)
    ap.add_argument("--by", choices=("size",), default=None)
    a = ap.parse_args()
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    mdir = os.path.join(a.path, "matches")
    if not os.path.isdir(mdir) and not logs_of(a.path):
        mdir = a.path
    if not os.path.isdir(mdir) or logs_of(a.path):
        sp, what = spans(a.path, a.step)
        show(os.path.basename(os.path.normpath(a.path)), sp, what, a.step)
        return
    groups = collections.defaultdict(lambda: [collections.defaultdict(collections.Counter),
                                              collections.defaultdict(collections.Counter), 0])
    for m in sorted(glob.glob(os.path.join(mdir, "*"))):
        if not os.path.exists(os.path.join(m, "result.json")):
            continue
        sp, what = spans(m, a.step)
        r = result_of(m)
        key = (("%dv%d " % (size_of(m), size_of(m))) if a.by == "size" else "") + {"W": "wins", "L": "losses"}.get(r, "draws/other")
        g = groups[key]
        for b in sp:
            g[0][b].update(sp[b])
            g[1][b].update(what[b])
        g[2] += 1
    for key in sorted(groups):
        sp, what, n = groups[key]
        show(key, sp, what, a.step, n)


if __name__ == "__main__":
    main()
