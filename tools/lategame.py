"""What the late game built, per player, from apex-tN.log files.

    python tools/lategame.py [--summary] <log|dir> [...]

For each log: game length, each finished gantry (when, where) and the construction
turrets finished within reach of it (minus those that died there), the long-range
plasma cannons (T2 and rapid-fire T3), nukes and anti-nukes, and how often the
super want won an election. A directory is searched for apex-t*.log.
"""
import math
import os
import re
import sys

GANTRY = {"armshltx", "corgant", "leggant", "armshltxuw", "corgantuw", "leggantuw", "legapt3"}
LRPC = {"armbrtha", "corint", "leglrpc"}
RAPID = {"armvulc", "corbuzz", "legstarfall"}
NUKE = {"armsilo", "corsilo", "legsilo"}
ANTI = {"armamd", "corfmd", "legabm"}
NANO_REACH = {"armnanotc": 400, "cornanotc": 400, "legnanotc": 400,
              "armnanotct2": 500, "cornanotct2": 500, "legnanotct2": 500}
GANTRY_HALF = 120  # half an experimental gantry's footprint, roughly

RE_FRAME = re.compile(r"\[f=(\d+)\]")
RE_MIN = re.compile(r"\[(\d+(?:\.\d+)?)m t\d+\]")
# A finished build: `placed` misses turrets raised through other paths.
RE_PLACED = re.compile(r"apex: latency (\w+) done=\d+ .*?at=(\d+),(\d+)")
RE_DEAD = re.compile(r"apex: unit-destroyed (\w+) .*? at=(\d+),(\d+)")
RE_SUPER = re.compile(r"-> super/super:(\w+)")
# Turrets are flown to the line that needs them: built elsewhere, standing here.
RE_LIFT = re.compile(r"apex: lift go .*? takes (\w+) #\d+ from=(\d+),(\d+) to=(\d+),(\d+)")


def logs_in(path):
    if os.path.isfile(path):
        return [path]
    out = []
    for root, _dirs, files in os.walk(path):
        for f in files:
            if re.fullmatch(r"apex-t\d+\.log", f):
                out.append(os.path.join(root, f))
    return sorted(out)


def read(path):
    last_min = 0.0
    placed = []   # (def, x, z, minute)
    dead = []     # (def, x, z)
    supers = {}
    lifts = []    # (def, fromX, fromZ, toX, toZ)
    frames = []   # (def, x, z) destroyed unfinished
    minute = 0.0
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = RE_MIN.search(line)
            if m:
                minute = float(m.group(1))
                last_min = max(last_min, minute)
            else:
                f = RE_FRAME.search(line)
                if f and int(f.group(1)) > 0:
                    minute = int(f.group(1)) / 1800.0
            p = RE_PLACED.search(line)
            if p:
                placed.append((p.group(1), int(p.group(2)), int(p.group(3)), minute))
                continue
            d = RE_DEAD.search(line)
            if d:
                # A frame destroyed before it finished also ends its build task,
                # which logs `latency ... done`: that build never stood.
                if " built=0 " in line:
                    frames.append((d.group(1), int(d.group(2)), int(d.group(3))))
                else:
                    dead.append((d.group(1), int(d.group(2)), int(d.group(3))))
                continue
            s = RE_SUPER.search(line)
            if s:
                supers[s.group(1)] = supers.get(s.group(1), 0) + 1
                continue
            lf = RE_LIFT.search(line)
            if lf:
                lifts.append((lf.group(1), int(lf.group(2)), int(lf.group(3)),
                              int(lf.group(4)), int(lf.group(5))))
    for fd, fx, fz in frames:
        for i, (pd, px, pz, _m) in enumerate(placed):
            if pd == fd and near(px, pz, fx, fz, 64):
                placed.pop(i)
                break
    return max(last_min, minute), placed, dead, supers, lifts


def near(ax, az, bx, bz, r):
    return math.hypot(ax - bx, az - bz) <= r


def report(path):
    length, placed, dead, supers, lifts = read(path)
    out = [f"{path}  {length:.0f} min"]
    gantries = [p for p in placed if p[0] in GANTRY]
    for g, gx, gz, gm in gantries:
        def serves(n, x, z):
            return n in NANO_REACH and near(x, z, gx, gz, NANO_REACH[n] + GANTRY_HALF)
        built = sum(1 for n, x, z, _m in placed if serves(n, x, z))
        lost = sum(1 for n, x, z in dead if serves(n, x, z))
        lin = sum(1 for n, fx, fz, tx, tz in lifts if serves(n, tx, tz) and not serves(n, fx, fz))
        lout = sum(1 for n, fx, fz, tx, tz in lifts if serves(n, fx, fz) and not serves(n, tx, tz))
        # Not every turret build is logged, so this is a floor, not a census:
        # at least as many stood here as arrived, and at least as many as died.
        floor = max(built + lin - lout, lost)
        out.append(f"  gantry {g} @{gm:.0f}m at {gx},{gz}: nanos in reach built={built}"
                   f" liftedIn={lin} liftedOut={lout} lost={lost} atLeast={floor}")
    if not gantries:
        out.append("  gantry: none")
    for label, group in (("lrpc", LRPC), ("rapid-lrpc", RAPID), ("nuke", NUKE), ("anti", ANTI)):
        hits = [p for p in placed if p[0] in group]
        if hits:
            first = min(h[3] for h in hits)
            names = sorted({h[0] for h in hits})
            out.append(f"  {label}: {len(hits)} built ({','.join(names)}), first @{first:.0f}m")
        else:
            out.append(f"  {label}: none")
    if supers:
        out.append("  super wins: " + " ".join(f"{k}={v}" for k, v in sorted(supers.items(), key=lambda kv: -kv[1])))
    return "\n".join(out)


def summary(paths):
    """One line per game directory: the whole side at a glance."""
    games = {}
    for p in paths:
        games.setdefault(os.path.dirname(p), []).append(p)
    for g, logs in sorted(games.items()):
        length = 0.0
        gantries = nanos = 0
        counts = {"lrpc": 0, "rapid": 0, "nuke": 0, "anti": 0}
        for p in logs:
            ln, placed, dead, _s, lifts = read(p)
            length = max(length, ln)
            for gd, gx, gz, _m in placed:
                if gd not in GANTRY:
                    continue
                gantries += 1
                def serves(n, x, z):
                    return n in NANO_REACH and near(x, z, gx, gz, NANO_REACH[n] + GANTRY_HALF)
                arrived = sum(1 for n, x, z, _m2 in placed if serves(n, x, z)) \
                    + sum(1 for n, fx, fz, tx, tz in lifts if serves(n, tx, tz) and not serves(n, fx, fz))
                nanos += max(arrived, sum(1 for n, x, z in dead if serves(n, x, z)))
            for key, group in (("lrpc", LRPC), ("rapid", RAPID), ("nuke", NUKE), ("anti", ANTI)):
                counts[key] += sum(1 for d in placed if d[0] in group)
        per = (nanos / gantries) if gantries else 0.0
        print(f"{g}  players={len(logs)} {length:.0f}min gantries={gantries}"
              f" nanos/gantry>={per:.1f} lrpc={counts['lrpc']} rapid={counts['rapid']}"
              f" nuke={counts['nuke']} anti={counts['anti']}")


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    brief = "--summary" in argv
    paths = [p for a in argv if a != "--summary" for p in logs_in(a)]
    if brief:
        summary(paths)
        return 0
    for p in paths:
        print(report(p))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
