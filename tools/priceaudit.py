"""What each kind of builder job cost us against what the market expected.

    python tools/priceaudit.py <match dir | dir of apex-t*.log> [--ally 0]

Per job kind (mex, energy, convert, nano, sense, protect, ...), over our side's mobile constructors:
  jobs      distinct jobs the builders took (`apex: exec`; a re-election onto the same job is not one)
  done      buildings of that kind finished within 96 elmos of a job's site after it was taken
  done%     done / jobs -- a job that never became a building is labour with nothing to show
  orderS    median seconds from the first job at a site to the building finishing there
  conS/m    constructor-seconds held on the kind (job to next job, walk included) per metal finished:
            the real labour price of a metal of this kind
  vMean     the value the market gave the jobs it executed (decide v=, geometric mean)
A balanced market spends labour where it returns most: a kind with a high conS/m and a high vMean is
over-priced; one with low conS/m and low vMean is under-priced.
"""
import argparse
import glob
import math
import os
import re
from collections import Counter, defaultdict

EXEC = re.compile(r"\[f=0*(\d+)\].*apex: exec t=(\d+) (\S+) #(\d+) ([a-z]+):(\S+) pick=\d+ at=(-?\d+),(-?\d+)(?: task=(-?\d+),(-?\d+))?")
DEC = re.compile(r"\[f=0*(\d+)\].*apex: decide t=(\d+) (\S+) #(\d+) -> [a-z]+/([a-z]+):\S+ v=([0-9.]+)")
BUILD = re.compile(r"\[BARAI_BUILD\] team=(\d+) ally=(\d+) frame=(\d+) min=[0-9.]+ unit=(\S+) cost=(\d+) x=(-?\d+) z=(-?\d+)")


def sources(path):
    own = [p for p in sorted(glob.glob(os.path.join(path, "apex-t*.log"))) if re.search(r"apex-t\d+\.log$", p)]
    if not own:
        own = sorted(glob.glob(os.path.join(path, "AI", "Skirmish", "*", "*", "apex-t*.log")))
        own = [p for p in own if re.search(r"apex-t\d+\.log$", p)]
    info = os.path.join(path, "infolog.txt")
    if not os.path.exists(info):
        info = os.path.join(os.path.dirname(path.rstrip("/\\")), "infolog.txt")
    return (own or [info]), info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--ally", default="0")
    a = ap.parse_args()
    logs, info = sources(a.path)
    teams = set()
    builds = defaultdict(list)   # (team, def) -> [(frame, x, z, cost)]
    for ln in open(info, encoding="utf-8", errors="ignore"):
        m = BUILD.search(ln)
        if m and m.group(2) == a.ally:
            t = m.group(1)
            teams.add(t)
            builds[(t, m.group(4))].append((int(m.group(3)), float(m.group(6)), float(m.group(7)), int(m.group(5))))
    jobs = defaultdict(list)     # (team, uid) -> [(frame, kind, def, x, z)]
    vals = defaultdict(list)
    for p in logs:
        for ln in open(p, encoding="utf-8", errors="ignore"):
            if "apex: exec" in ln:
                m = EXEC.search(ln)
                if not m:
                    continue
                f, t, dn, uid, kind, d, x, z, tx, tz = m.groups()
                if (teams and t not in teams) or "com" in dn:
                    continue
                x, z = (float(tx), float(tz)) if tx else (float(x), float(z))
                jobs[(t, uid)].append((int(f), kind, d, x, z))
            elif "apex: decide" in ln:
                m = DEC.search(ln)
                if m and (not teams or m.group(2) in teams) and "com" not in m.group(3):
                    vals[m.group(5)].append(float(m.group(6)))
    execN = Counter()
    heldS = defaultdict(float)
    first = {}                   # (team, def, cellx, cellz) -> first job frame, kind
    for (t, uid), js in jobs.items():
        js.sort()
        for k, (f, kind, d, x, z) in enumerate(js):
            if k + 1 < len(js):
                heldS[kind] += (js[k + 1][0] - f) / 30.0
            if k > 0:
                pf, pk, pd, px, pz = js[k - 1]
                if (pk == kind) and (pd == d) and (abs(px - x) <= 96) and (abs(pz - z) <= 96):
                    continue   # re-elected onto the same job: not a new one
            execN[kind] += 1
            key = (t, d, int(x // 96), int(z // 96))
            if key not in first or f < first[key][0]:
                first[key] = (f, kind)
    done = Counter()
    doneM = defaultdict(float)
    orderS = defaultdict(list)
    for (t, d), bs in builds.items():
        for (bf, bx, bz, cost) in bs:
            best = None
            for dx in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    key = (t, d, int(bx // 96) + dx, int(bz // 96) + dz)
                    if key in first and first[key][0] <= bf and (best is None or first[key][0] < best[0]):
                        best = first[key]
            if best is None:
                continue
            done[best[1]] += 1
            doneM[best[1]] += cost
            orderS[best[1]].append((bf - best[0]) / 30.0)
    print("%-10s %6s %5s %6s %7s %8s %8s" % ("kind", "jobs", "done", "done%", "orderS", "conS/m", "vMean"))
    for kind in sorted(execN, key=lambda k: -heldS[k]):
        os_ = sorted(orderS[kind])
        med = os_[len(os_) // 2] if os_ else float("nan")
        v = [x for x in vals.get(kind, []) if x > 0]
        vg = math.exp(sum(math.log(x) for x in v) / len(v)) if v else 0.0
        cps = heldS[kind] / doneM[kind] if doneM[kind] > 0 else float("inf")
        print("%-10s %6d %5d %5.0f%% %7.0f %8.2f %8.2f" % (kind, execN[kind], done[kind],
              100.0 * done[kind] / max(1, execN[kind]), med, cps, vg))


if __name__ == "__main__":
    main()
