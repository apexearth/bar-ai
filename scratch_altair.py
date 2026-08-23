import re, sys, json
from pathlib import Path
from collections import defaultdict

LINE = re.compile(
    r"\[(?P<min>[\d.]+)m t(?P<team>\d+)\] apex: unit-destroyed (?P<name>\S+)"
    r" id=(?P<id>\d+) frame=(?P<frame>\d+) at=(?P<x>-?\d+),(?P<z>-?\d+)"
    r" curTask=t(?P<tt>-?\d+)b(?P<bt>-?\d+)f(?P<ft>-?\d+)"
    r" cost=(?P<cost>\d+) fwd=(?P<fwd>-?[\d.]+)(?: built=(?P<built>\d))?"
    r"(?: mob=(?P<mob>\d))?"
    r"(?: hist=\[(?P<hist>[^\]]*)\])?"
    r"(?: fhist=\[(?P<fhist>[^\]]*)\])?")

FIGHT = ["rally", "guard", "defend", "scout", "raid", "attack", "bomb",
         "melee", "arty", "aa", "ah", "support", "super"]

def analyze(path, apex_team):
    text = Path(path).read_text(errors="replace")
    frames = [int(f) for f in re.findall(r" frame=(\d+)", text)]
    cutoff = (max(frames) - 90*30) if frames else 0
    events = []
    seen = set()
    for line in text.splitlines():
        m = LINE.search(line)
        if not m: continue
        if int(m["team"]) != apex_team: continue
        key = (m["team"], m["id"])
        if key in seen: continue
        seen.add(key)
        frm = int(m["frame"])
        if frm >= cutoff: continue
        if m["mob"] != "1": continue  # mobile combat only
        if m["built"] != "1": continue
        events.append(m)
    # bucket into 60s windows for trickle vs group-wipe detection
    per_min = defaultdict(lambda: [0,0.0])
    solo_fresh = 0
    solo_total = 0
    for m in events:
        minute = int(m["frame"])//1800
        per_min[minute][0]+=1
        per_min[minute][1]+=float(m["cost"])
        fhist = m["fhist"] or ""
        # time since last transition (fresh order) at death
        parts = [p for p in fhist.split(";") if p]
        if parts:
            last = parts[-1]
            if "@" in last:
                tag, fr = last.split("@")
                fr = int(fr)
                dt = (int(m["frame"]) - fr) / 30.0
                if dt <= 20:
                    solo_fresh += 1
        solo_total += 1
    return events, per_min, solo_fresh, solo_total

if __name__ == "__main__":
    path, apex_team = sys.argv[1], int(sys.argv[2])
    events, per_min, solo_fresh, solo_total = analyze(path, apex_team)
    print(f"{path}: total mobile-built deaths (excl last 90s) = {solo_total}")
    total_cost = sum(float(m["cost"]) for m in events)
    print(f"  total metal lost = {total_cost:.0f}")
    print(f"  deaths within 20s of a fresh fight-task election = {solo_fresh} ({solo_fresh/max(1,solo_total):.0%})")
    # cluster sizes: group deaths within 10s and 800 units distance as one "event"
    evs = sorted(events, key=lambda m: int(m["frame"]))
    clusters = []
    cur = []
    for m in evs:
        if not cur:
            cur = [m]
            continue
        if int(m["frame"]) - int(cur[-1]["frame"]) <= 300:  # 10s
            cur.append(m)
        else:
            clusters.append(cur)
            cur = [m]
    if cur: clusters.append(cur)
    sizes = [len(c) for c in clusters]
    ones_twos = sum(1 for s in sizes if s<=2)
    big = sum(1 for s in sizes if s>=4)
    print(f"  clusters(<=10s gap): n={len(clusters)} sizes={sizes}")
    print(f"  ones/twos clusters={ones_twos}  big(>=4) clusters={big}")
