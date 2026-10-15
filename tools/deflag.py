"""Tower refill lag: for every defence of ours that died, how long until we next ordered a defence near
that spot -- and where the defences ordered in the meantime went instead.

    python tools/deflag.py <match dir | infolog | tournament dir> [--near 400] [--window 180]

His 10-14 watch: heavy attacks were answered with towers in other places, so the gaps where we
were hit stayed open. `near` is how close an order must be to count as a refill (elmos);
`window` is how many seconds after the death we look.
"""
import argparse
import glob
import math
import os
import re
import statistics

DEFS = ("llt", "hllt", "beamer", "hlt", "rl", "guard", "toaster", "pun", "lab", "ambush", "viper", "emp",
        "flak", "nett", "mercury", "screamer", "doom", "anni", "bulwark", "cerb", "vipe", "dl", "drag")
DEATH = re.compile(r"\[f=0*(\d+)\].*?apex: unit-destroyed (\w+) .*?at=(\d+),(\d+).*? mob=0")
ORDER = re.compile(r"\[f=0*(\d+)\].*?apex: exec t=(\d+) \w+ #\d+ protect:(\w+) .*?at=(\d+),(\d+)")
TEAM = re.compile(r"\[[0-9.]+m t(\d+)\]")


def is_def(name):
    n = name[3:] if name[:3] in ("arm", "cor", "leg") else name
    return any(n.startswith(d) for d in DEFS) and not n.startswith(("lab", "drag"))


def files(path):
    if os.path.isfile(path):
        return [path]
    p = os.path.join(path, "infolog.txt")
    if os.path.exists(p):
        return [p]
    return sorted(glob.glob(os.path.join(path, "matches", "*", "infolog.txt")))


def one(path, near, window):
    deaths, orders = [], []
    for line in open(path, encoding="utf-8", errors="replace"):
        m = DEATH.search(line)
        if m and is_def(m.group(2)):
            tm = TEAM.search(line)
            deaths.append((int(m.group(1)), tm.group(1) if tm else "?", m.group(2), int(m.group(3)), int(m.group(4))))
            continue
        m = ORDER.search(line)
        if m:
            orders.append((int(m.group(1)), m.group(2), m.group(3), int(m.group(4)), int(m.group(5))))
    rows = []
    for f, t, d, x, z in deaths:
        later = [o for o in orders if (o[1] == t) and (f < o[0] <= f + window * 30)]
        refill = [o for o in later if math.hypot(o[3] - x, o[4] - z) <= near]
        lag = (refill[0][0] - f) / 30.0 if refill else None
        rows.append((f, t, d, lag, len(later), len(refill)))
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path")
    ap.add_argument("--near", type=float, default=400.0)
    ap.add_argument("--window", type=float, default=180.0)
    a = ap.parse_args()
    allrows = []
    for p in files(a.path):
        allrows += one(p, a.near, a.window)
    if not allrows:
        print("no defence deaths found")
        return
    lags = [r[3] for r in allrows if r[3] is not None]
    others = sum(r[4] - r[5] for r in allrows)
    refills = sum(r[5] for r in allrows)
    print("defences lost: %d   refilled within %ds: %d (%.0f%%)   median lag %s s" % (
        len(allrows), a.window, len(lags), 100.0 * len(lags) / len(allrows),
        ("%.0f" % statistics.median(lags)) if lags else "-"))
    print("defence orders in the %ds after a loss: %d near the loss, %d elsewhere" % (a.window, refills, others))


if __name__ == "__main__":
    main()
