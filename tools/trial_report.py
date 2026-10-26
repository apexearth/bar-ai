#!/usr/bin/env python3
"""Seat-level trials in his multiplayer games: is the change working?

    python tools/trial_report.py              # archive any finished game, then report every trial
    python tools/trial_report.py --no-archive # report only
    python tools/trial_report.py --kind normal       # leave out randomizer (and unknown) games; also randomizer, unknown

A release can ship a change as a TRIAL (manager/trial.as): each AI seat flips a coin for the switch, logs
`apex: trial name=<n> arm=<0|1>` once and `apex: trial-stat ...` every minute (income, metal killed and lost,
the trial's own counters). This reads every game we have -- runtime/mpgames/* (tools/mp_archive.py) and the
install's current and .prev bot logs, de-duplicated -- and compares the arms: per seat, and paired inside each
game that had both arms (teammates share a result, so the per-seat economy and trade carry the weight, not wins).
Running it also archives the last finished game first, so nothing is lost to log rotation.
"""
import hashlib
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
ARCH = REPO / "runtime" / "mpgames"
ARM = re.compile(r"apex: trial name=(\w+) arm=(\d) t=(\d+)")
STAT = re.compile(r"apex: trial-stat name=(\w+) arm=(\d) t=(\d+) min=(\d+) (.*)")
VER = re.compile(r"apex: version t=\d+ (\S+)")
GAME_SPAN_S = 900
EXTRA = []   # --dirs: match folders to read instead of his games (harness checks)


def seat_of(path):
    """The seats' trials in one log: {(name, team): {"arm", "min", fields...}} from each last trial-stat line, and
    the AI version. A bot log holds one team; a match's merged infolog holds all of ours."""
    out, ver = {}, "?"
    with open(path, encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            m = STAT.search(ln)
            if m:
                rec = {"arm": int(m.group(2)), "min": int(m.group(4))}
                for kv in m.group(5).split():
                    k, _, v = kv.partition("=")
                    try:
                        rec[k] = float(v)
                    except ValueError:
                        pass
                key = (m.group(1), m.group(3))
                prev = out.get(key, {})
                rec["peak_mInc"] = max(prev.get("peak_mInc", 0.0), rec.get("mInc", 0.0))
                out[key] = rec
                continue
            m = ARM.search(ln)
            if m and (m.group(1), m.group(3)) not in out:
                out[(m.group(1), m.group(3))] = {"arm": int(m.group(2)), "min": 0}
                continue
            m = VER.search(ln)
            if m and ver == "?":
                ver = m.group(1)
    return out, ver


def head_hash(path):
    with open(path, "rb") as fh:
        return hashlib.md5(fh.read(65536)).hexdigest()


def games():
    """Lists of seat logs, one list per game, de-duplicated by the logs' first 64 KB."""
    found = []
    if ARCH.is_dir():
        for d in sorted(p for p in ARCH.iterdir() if p.is_dir()):
            logs = sorted(d.glob("apex-t*.log"))
            if logs:
                found.append(logs)
    for d in EXTRA:
        found.append([d / "infolog.txt"] if (d / "infolog.txt").is_file() else sorted(d.glob("apex-t*.log")))
    if EXTRA:
        return found
    try:
        env = bar_env.load()
        for prev in (False, True):
            logs = [p for p in (env.data / "AI" / "Skirmish").glob("Apex*/*/apex-t*.log")
                    if p.name.endswith(".prev.log") == prev]
            logs.sort(key=lambda p: p.stat().st_mtime)
            group = []
            for p in logs:
                if group and p.stat().st_mtime - group[-1].stat().st_mtime > GAME_SPAN_S:
                    found.append(group)
                    group = []
                group.append(p)
            if group:
                found.append(group)
    except Exception as e:  # the install may be absent on another machine
        print("(install logs not read: %s)" % e)
    seen, out = set(), []
    for g in found:
        key = frozenset(head_hash(p) for p in g)
        if key in seen:
            continue
        seen.add(key)
        out.append(g)
    return out


def kind_of(group):
    """randomizer / normal / unknown: the BaRandom tweakdefs announce themselves in the game's own infolog, which the
    archive keeps when it belongs to that game (his 10-25: randomizer games, unit stats changed, very wacky)."""
    log = group[0].parent / "infolog.game.txt" if group else None
    if log is None or not log.is_file():
        return "unknown"
    with open(log, encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            if "[BaRandom]" in ln or "--BaRandom" in ln:
                return "randomizer"
    return "normal"


def trade(r):
    m = max(1.0, r.get("min", 0))
    return (r.get("killedM", 0.0) - r.get("lostM", 0.0)) / m


def main(argv):
    if "--dirs" in argv:
        EXTRA.extend(Path(a) for a in argv[argv.index("--dirs") + 1:])
        argv = argv[:argv.index("--dirs")] + ["--no-archive"]
    if "--no-archive" not in argv:
        try:
            import mp_archive
            mp_archive.archive(bar_env.load(), st := mp_archive.load_state())
            mp_archive.STATE.parent.mkdir(parents=True, exist_ok=True)
            mp_archive.STATE.write_text(__import__("json").dumps(st))
        except Exception as e:
            print("(archive step skipped: %s)" % e)
    want = None
    if "--kind" in argv:
        want = set(argv[argv.index("--kind") + 1].split(","))
    seats = defaultdict(list)          # trial -> [(game index, version, arm, record)]
    kinds = defaultdict(int)
    for gi, g in enumerate(games()):
        k = kind_of(g)
        kinds[k] += 1
        if want is not None and k not in want:
            continue
        for p in g:
            trials, ver = seat_of(p)
            for (name, _team), rec in trials.items():
                if rec.get("min", 0) >= 5:
                    seats[name].append((gi, ver, rec["arm"], rec))
    print("games by kind: " + ", ".join("%s %d" % kv for kv in sorted(kinds.items()))
          + ("" if want is None else "  (reading only: %s)" % ",".join(sorted(want))))
    if not seats:
        print("no trial seats yet: play a game on a release that runs a trial (v0.3.8+), then run this again")
        return 0
    for name, rows in sorted(seats.items()):
        vers = sorted({v for _, v, _, _ in rows})
        print("== trial %s: %d seat-games over %d games, versions %s" % (
            name, len(rows), len({g for g, _, _, _ in rows}), ",".join(vers)))
        keys = ["min", "peak_mInc", "mInc", "killedM", "lostM"] + sorted(
            {k for _, _, _, r in rows for k in r} - {"arm", "min", "peak_mInc", "mInc", "eInc", "killedM", "lostM"})
        for arm in (1, 0):
            rs = [r for _, _, a, r in rows if a == arm]
            if not rs:
                print("  arm %d: no seats" % arm)
                continue
            parts = ["%s %.0f" % (k, statistics.mean(r.get(k, 0.0) for r in rs)) for k in keys]
            parts.append("trade/min %.0f" % statistics.mean(trade(r) for r in rs))
            print("  arm %d (%s): %d seats | %s" % (arm, "on" if arm else "off", len(rs), " | ".join(parts)))
        diffs = []
        for gi in sorted({g for g, _, _, _ in rows}):
            on = [r for g, _, a, r in rows if g == gi and a == 1]
            off = [r for g, _, a, r in rows if g == gi and a == 0]
            if on and off:
                diffs.append((statistics.mean(trade(r) for r in on) - statistics.mean(trade(r) for r in off),
                              statistics.mean(r.get("peak_mInc", 0) for r in on)
                              - statistics.mean(r.get("peak_mInc", 0) for r in off)))
        if diffs:
            better = sum(1 for d, _ in diffs if d > 0)
            print("  paired, %d games with both arms: on - off trade/min %+.0f (on better in %d of %d), peak income %+.0f"
                  % (len(diffs), statistics.mean(d for d, _ in diffs), better, len(diffs),
                     statistics.mean(i for _, i in diffs)))
            n = len(diffs)
            if n >= 8:
                from math import comb
                k = max(better, n - better)
                p = sum(comb(n, j) for j in range(k, n + 1)) / 2 ** n * 2
                print("  sign test: p = %.2f%s" % (min(1.0, p), " -- decided" if p < 0.05 else " -- keep playing"))
            else:
                print("  fewer than 8 paired games: keep playing")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
