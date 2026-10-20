"""How our losses depend on the army ratio, from finished matches. Between consecutive stats samples: our army
(sum armyReal of our teams) and theirs at the first, our structure/eco metal lost to the enemy in between
(BARAI_DEATH, mob=0, attacker not ours), our standing assets (mEco+mFactories+mDefence+mBP). Buckets by ratio
r = ours/theirs; prints the loss rate as a share of assets per minute.
Usage: lossfit.py <our teams csv> <match dir> ..."""
import re
import sys
from collections import defaultdict

ST = re.compile(r"BARAI_STATS\] team=(\d+) .*?frame=(\d+) .*?mFactories=(\d+) mDefence=(\d+) mEco=(\d+).*?mBP=(\d+).*?armyReal=(\d+)")
DE = re.compile(r"BARAI_DEATH\] frame=(\d+) team=(\d+) unit=\S+ cost=(\d+) .*? mob=(\d) atkteam=(-?\d+)")
ours = set(int(x) for x in sys.argv[1].split(","))
rows = []
for d in sys.argv[2:]:
    st = defaultdict(dict)
    deaths = []
    for line in open(d + "/infolog.txt", encoding="utf-8", errors="replace"):
        m = ST.search(line)
        if m:
            st[int(m.group(2))][int(m.group(1))] = (sum(int(m.group(i)) for i in (3, 4, 5, 6)), int(m.group(7)))
            continue
        m = DE.search(line)
        if m and int(m.group(2)) in ours and m.group(4) == "0" and int(m.group(5)) not in ours:
            deaths.append((int(m.group(1)), float(m.group(3))))
    frames = sorted(f for f in st if len(st[f]) >= 2)
    for f1, f2 in zip(frames, frames[1:]):
        if f1 < 4 * 1800:
            continue
        a = sum(v[1] for t, v in st[f1].items() if t in ours)
        e = sum(v[1] for t, v in st[f1].items() if t not in ours)
        s = sum(v[0] for t, v in st[f1].items() if t in ours)
        if e <= 0 or s <= 0:
            continue
        lost = sum(c for f, c in deaths if f1 <= f < f2)
        rows.append((a / e, lost / s / ((f2 - f1) / 1800.0), a, e, s, lost))
edges = [0, 0.1, 0.2, 0.35, 0.5, 0.75, 1.0, 1.5, 2.5, 99]
print("ratio bucket      n   loss/min as share of assets   mean army ours/theirs   mean assets")
for lo, hi in zip(edges, edges[1:]):
    b = [r for r in rows if lo <= r[0] < hi]
    if not b:
        continue
    print("%5.2f-%-5.2f  %5d   %8.4f                      %7.0f / %7.0f      %7.0f" % (lo, hi, len(b),
          sum(r[1] for r in b) / len(b), sum(r[2] for r in b) / len(b), sum(r[3] for r in b) / len(b),
          sum(r[4] for r in b) / len(b)))
