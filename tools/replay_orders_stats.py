import collections
import statistics
import sys

CMD = {0: "stop", 1: "insert", 2: "remove", 5: "wait", 10: "move", 15: "patrol", 16: "fight", 20: "attack",
       21: "area_attack", 25: "guard", 40: "repair", 45: "firestate", 50: "movestate", 70: "wantedspeed",
       75: "load", 81: "unload", 85: "onoff", 90: "reclaim", 95: "cloak", 110: "restore", 115: "repeat",
       125: "resurrect", 130: "capture", 140: "autorepair", 145: "idlemode"}

defs, teams, cmds, pos = {}, {}, [], []
for ln in open(sys.argv[1], encoding="utf-8", errors="replace"):
    p = ln.split()
    if not p:
        continue
    if p[0] == "D":
        defs[int(p[1])] = (p[2], p[3], float(p[4]))
    elif p[0] == "T":
        teams[int(p[1])] = (int(p[2]), p[3] == "true")
    elif p[0] == "C":
        cmds.append((int(p[1]), int(p[2]), int(p[3]), int(p[4]), int(p[5]), p[6] if len(p) > 9 else "",
                     p[-1] if len(p) > 9 else ""))
    elif p[0] == "P":
        pos.append((int(p[1]), int(p[2]), int(p[3]), int(p[4])))

FOCUS = {"army", "radar", "jammer", "air"}
human = {t for t, (a, ai) in teams.items() if not ai and a >= 0}
ai = {t for t, (a, ai) in teams.items() if ai}
print("teams", len(teams), "human", sorted(human), "ai", sorted(ai))


def side(t):
    return "human" if t in human else "ai" if t in ai else "other"


def name(c):
    return CMD.get(c, "build" if c < 0 else str(c))


by = collections.Counter((side(t), defs.get(d, ("?", "?"))[1]) for f, t, u, d, c, o, ps in cmds)
print("\norders by side and unit class")
for k, n in sorted(by.items(), key=lambda kv: -kv[1]):
    print("  %-6s %-8s %7d" % (k[0], k[1], n))

for s in ("human", "ai"):
    sel = [x for x in cmds if side(x[1]) == s and defs.get(x[3], ("", ""))[1] in FOCUS]
    print("\n== %s, focus classes (army/air/radar/jammer): %d orders" % (s, len(sel)))
    print("  types", collections.Counter(name(x[4]) for x in sel).most_common(12))
    print("  modifiers", collections.Counter(x[5] for x in sel).most_common(6))
    grp = collections.Counter((x[0], x[1], x[4]) for x in sel)
    sizes = list(grp.values())
    if sizes:
        print("  issue events %d, units per event median %s, mean %.1f, share of orders in events of 5+ %.2f" % (
            len(sizes), statistics.median(sizes), statistics.mean(sizes),
            sum(n for n in sizes if n >= 5) / sum(sizes)))
    # positional orders only (move/fight/attack/patrol): gap between successive orders to a unit
    last, gaps = {}, []
    for f, t, u, d, c, o, ps in sel:
        if c in (10, 15, 16, 20, 21):
            if u in last and f - last[u] > 0:
                gaps.append((f - last[u]) / 30)
            last[u] = f
    if gaps:
        q = statistics.quantiles(gaps, n=4)
        print("  seconds between move/fight/attack/patrol orders to one unit: q1 %.1f median %.1f q3 %.1f (n=%d)" % (
            q[0], q[1], q[2], len(gaps)))
    # how many focus units alive per sample vs how many got a positional order in the next 30 s
    alive = collections.defaultdict(set)
    for f, t, u, d in pos:
        if side(t) == s and defs.get(d, ("", ""))[1] in FOCUS:
            alive[f].add(u)
    ordered = collections.defaultdict(set)
    for f, t, u, d, c, o, ps in sel:
        if c in (10, 15, 16, 20, 21):
            ordered[f // 900].add(u)
    rows = []
    for f in sorted(alive):
        if f % 900 == 0 and f > 0:
            a = alive[f]
            rows.append((f // 1800, len(a), len(a & ordered[f // 900])))
    print("  per 30 s window: (minute, focus units alive, of them given a positional order in the window)")
    print("  ", rows[::2])
