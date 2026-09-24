"""What is killing our units, in METAL, and what beats it.

    python tools/killers.py <match|tournament> [--team N]

apexearth, 2026-09-23: "look at in the specific game -- what is killing our
units? Identify that and then build the counter to it."

Reads `apex: record <ourdef> ... killed-by=<theirdef>` and charges each killer
the metal cost of what it killed, because 40 Pawns and one Ratte are not the
same loss. Counts alone rank a Pawn-killer top; metal ranks the thing actually
beating us.

The right-hand column is what the AI could build against it: for each killer,
the cheapest of our own defences whose range EXCEEDS the killer's, since
out-ranging a siege unit is the counter that does not trade.
"""
import argparse
import collections
import glob
import os
import re
import sys

REC = re.compile(r"apex: record (\S+) \S+ .*?killed-by=(\S+) t(\d+)")
COST = re.compile(r"metalcost\s*=\s*([\d.]+)")
# weapon range lives in the weapondefs block, not at unit level; take the
# longest weapon the def declares.
RANGE = re.compile(r"\brange\s*=\s*([\d.]+)", re.I)


def game_root():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import bar_env
    env = bar_env.load()
    for attr in ("game_sdd", "game_config_dir"):
        p = getattr(env, attr, None)
        if p and os.path.isdir(str(p)):
            return str(p)
    return None


def unit_table(root):
    """def name -> (metalcost, longest weapon range, flies)."""
    out = {}
    if not root:
        return out
    for dirpath, _dirs, files in os.walk(os.path.join(root, "units")):
        for f in files:
            if not f.endswith(".lua"):
                continue
            name = f[:-4].lower()
            try:
                txt = open(os.path.join(dirpath, f), encoding="utf-8",
                           errors="replace").read()
            except OSError:
                continue
            c = COST.search(txt)
            rs = [float(x) for x in RANGE.findall(txt)]
            low = txt.lower()
            # an aircraft "out-ranges" a tank on paper and cannot hold ground
            # against it, so it is not a counter; nor is anything that cannot
            # shoot a surface target.
            flies = ("canfly" in low and "canfly = false" not in low
                     and "canfly=false" not in low)
            out[name] = (float(c.group(1)) if c else 0.0,
                         max(rs) if rs else 0.0, flies)
    return out


def infologs(target):
    if os.path.isfile(target):
        return [target]
    p = os.path.join(target, "infolog.txt")
    if os.path.exists(p):
        return [p]
    return sorted(glob.glob(os.path.join(target, "matches", "*", "infolog.txt")))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("target")
    ap.add_argument("--team", type=int, default=None)
    a = ap.parse_args()

    tab = unit_table(game_root())
    lost = collections.Counter()      # killer -> metal of ours it killed
    n = collections.Counter()         # killer -> our units killed
    victims = collections.defaultdict(collections.Counter)

    for info in infologs(a.target):
        for ln in open(info, encoding="utf-8", errors="replace"):
            m = REC.search(ln)
            if not m:
                continue
            ours, killer, team = m.group(1), m.group(2), int(m.group(3))
            if killer in ("-", ""):
                continue
            if a.team is not None and team != a.team:
                continue
            cost = tab.get(ours.lower(), (0.0, 0.0, False))[0]
            lost[killer] += cost
            n[killer] += 1
            victims[killer][ours] += 1

    if not lost:
        print("no `apex: record ... killed-by=` lines (is the record on?)")
        return

    tot = sum(lost.values())
    print("our metal lost, by what killed it (%d killers, %d metal total)"
          % (len(lost), tot))
    print("  %-16s %9s %6s %-6s %-22s %s"
          % ("killer", "our metal", "share", "range",
             "its favourite victims", "our cheapest out-rangers"))
    for k, m_ in lost.most_common(14):
        kc, kr, _kf = tab.get(k.lower(), (0.0, 0.0, False))
        vs = ", ".join("%s x%d" % (d, c) for d, c in victims[k].most_common(2))
        # cheapest thing we own that out-ranges it
        counter = "-"
        if kr > 0:
            cands = sorted((c, d) for d, (c, r, f) in tab.items()
                           if (r > kr) and (c > 0) and (not f)
                           and d.startswith("arm") and ("scav" not in d))
            if cands:
                counter = ", ".join("%s %.0fm" % (d, c) for c, d in cands[:2])
        print("  %-16s %9.0f %5.0f%% r%-5.0f %-22s %s"
              % (k, m_, 100.0 * m_ / tot, kr, vs[:22], counter))
    print()
    print("  killer costs and ranges, for the exchange: "
          + ", ".join("%s %.0fm/r%.0f" % (k, tab.get(k.lower(), (0, 0, 0))[0],
                                          tab.get(k.lower(), (0, 0, 0))[1])
                      for k, _ in lost.most_common(6)))


main()
