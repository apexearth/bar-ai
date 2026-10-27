"""Is the survival price right? Every finished structure of ours logs the risk the price assumed at its spot
(`apex: calib-born`, a rate per second); this joins it to how the building actually ended.

    python tools/calib.py <match-dir> [more...]

Per kind and forward band: buildings, the time they stood, deaths an enemy caused, the deaths the price expected
(sum of risk x seconds stood) and their ratio -- the factor the price is off by (1 = right, 3 = three times
safer than it really is). A building reclaimed or removed by us, or standing at the end, is censored: it counts the
seconds it stood and no death.
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

BORN = re.compile(r"\[f=0*(\d+)\].*?apex: calib-born t=(\d+) uid=(\d+) def=(\S+) fwd=(-?[\d.]+) risk=([\d.]+)")
DEATH = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=\S+ .*?atkteam=(-?\d+) .*?uid=(\d+)")
BUILD = re.compile(r"\[BARAI_BUILD\] team=(\d+) ally=(\d+) ")
FRAME = re.compile(r"\[f=0*(\d+)\]")
KINDS = [("mex", r"(mex|moho)"), ("tower", r"(llt|lht|hllt|hlt|beamer|guard|pun|ambush|amb|mg|dl|tl|fhlt|ptl|cir|vipe|toad|gate)"),
         ("aa", r"(rl|flak|aak|madsam|ferret|nansam|aap?ad|mercury|screamer)"), ("energy", r"(solar|wind|fus|tide|geo|afus|adv)"),
         ("convert", r"(makr|mmkr|maker)"), ("nano", r"nanotc"), ("lab", r"(lab|vp|ap$|aap|alab|avp|hp|shltx|gant|sy|plat|fhp)"),
         ("sensor", r"(rad|eyes|jam|sonar|targ)"), ("store", r"(stor)")]


def kind_of(d):
    body = d[3:] if d[:3] in ("arm", "cor", "leg") else d
    for k, pat in KINDS:
        if re.search(pat, body):
            return k
    return "other"


def band(f):
    return "rear" if f < 0.2 else ("mid" if f < 0.4 else "fwd")


acc = defaultdict(lambda: [0, 0.0, 0, 0.0])   # n, seconds, deaths, expected
for arg in sys.argv[1:]:
    for d in sorted(Path().glob(arg)) if any(ch in arg for ch in "*?") else [Path(arg)]:
        log = d / "infolog.txt" if d.is_dir() else d
        if not log.exists():
            continue
        ally, born, death, last = {}, {}, {}, 0
        for ln in open(log, encoding="utf-8", errors="replace"):
            m = FRAME.search(ln)
            if m:
                last = max(last, int(m[1]))
            m = BUILD.search(ln)
            if m:
                ally[int(m[1])] = int(m[2])
            m = BORN.search(ln)
            if m:
                born[m[3]] = (int(m[1]), int(m[2]), m[4], float(m[5]), float(m[6]))
                continue
            m = DEATH.search(ln)
            if m and m[4] not in death:
                death[m[4]] = (int(m[1]), int(m[2]), int(m[3]))
        for uid, (fb, team, dname, fwd, risk) in born.items():
            end, died = last, False
            if uid in death:
                fd, dteam, atk = death[uid]
                end = fd
                died = (atk >= 0) and (ally.get(atk, -1) != ally.get(team, -2))
            secs = max(0.0, (end - fb) / 30.0)
            a = acc[(kind_of(dname), band(fwd))]
            a[0] += 1
            a[1] += secs
            a[2] += 1 if died else 0
            a[3] += risk * secs
print(f"{'kind':8s} {'band':5s} {'n':>5s} {'stood h':>8s} {'deaths':>7s} {'expected':>9s} {'off by':>7s}  real rate/s  priced/s")
for (k, b), (n, s, dd, ex) in sorted(acc.items(), key=lambda kv: (kv[0][0], ["rear", "mid", "fwd"].index(kv[0][1]))):
    ratio = dd / ex if ex > 0 else float("inf")
    print(f"{k:8s} {b:5s} {n:5d} {s / 3600:8.1f} {dd:7d} {ex:9.1f} {ratio:7.2f}  {dd / s if s else 0:11.5f}  {ex / s if s else 0:8.5f}")
