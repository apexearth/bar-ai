"""Chance our side is eliminated within the next 10 minutes, by army ratio ours/theirs, from finished matches.
A side is eliminated when its teams stop reporting BARAI_STATS before the game's last stats frame and the
result names the other side. Usage: defeatfit.py <our teams csv> <match dir> ..."""
import json
import re
import sys
from collections import defaultdict

ST = re.compile(r"BARAI_STATS\] team=(\d+) .*?frame=(\d+) .*?armyReal=(\d+)")
ours = set(int(x) for x in sys.argv[1].split(","))
rows = []
for d in sys.argv[2:]:
    st = defaultdict(dict)
    for line in open(d + "/infolog.txt", encoding="utf-8", errors="replace"):
        m = ST.search(line)
        if m:
            st[int(m.group(2))][int(m.group(1))] = int(m.group(3))
    try:
        res = json.load(open(d + "/result.json"))["result"]
        lost_at = None
        if res.get("reason") == "gameover" and res.get("winners") and str(res["winners"][0]) != "0":
            lost_at = max(st) if st else None
    except Exception:
        continue
    for f in sorted(st):
        if f < 4 * 1800:
            continue
        a = sum(v for t, v in st[f].items() if t in ours)
        e = sum(v for t, v in st[f].items() if t not in ours)
        if e <= 0:
            continue
        dead10 = (lost_at is not None) and (lost_at - f <= 10 * 1800)
        rows.append((a / e, 1 if dead10 else 0))
edges = [0, 0.1, 0.2, 0.35, 0.5, 0.75, 1.0, 1.5, 99]
print("ratio bucket      n   P(eliminated within 10 min)")
for lo, hi in zip(edges, edges[1:]):
    b = [r for r in rows if lo <= r[0] < hi]
    if b:
        print("%5.2f-%-5.2f  %5d   %5.3f" % (lo, hi, len(b), sum(r[1] for r in b) / len(b)))
