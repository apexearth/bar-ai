#!/usr/bin/env python3
"""The eco seat, read from one 8v8 run: income curve, hands, sites, waste.

    python tools/seat.py <run-dir> [<run-dir>...]

The seat is the team whose `apex: eco-status` says growing=1 for longest.
Lane runs keep per-team apex logs under <write-dir>/AI/Skirmish/<Apex..>/;
pass the run dir and the lane's log dir is found from infolog's first line.
"""
import re
import sys
from pathlib import Path

MIN = (8, 12, 16, 20, 24)


def team_lines(run: Path):
    """Return (team -> list of apex lines) for our side, plus the infolog path."""
    info = run / "infolog.txt"
    text = info.read_text(encoding="utf8", errors="ignore")
    by = {}
    m = re.search(r"apex: log file (\S+apex-t)\d+\.log", text)
    if m:
        base = Path(m.group(1).replace("\\", "/"))
        for t in range(16):
            p = Path(f"{base}{t}.log")
            if p.exists():
                by[t] = p.read_text(encoding="utf8", errors="ignore").splitlines()
    if not by:
        for line in text.splitlines():
            mm = re.search(r"apex: \S+ t=(\d+) ", line) or re.search(r"\[\d+\.\dm t(\d+)\]", line)
            if mm:
                by.setdefault(int(mm.group(1)), []).append(line)
    return by, text


def read(run: Path):
    by, text = team_lines(run)
    seat, best = None, 0
    for t, lines in by.items():
        n = sum(1 for l in lines if "eco-status" in l and "growing=1" in l)
        if n > best:
            seat, best = t, n
    if seat is None:
        print(f"{run.name}: no eco seat")
        return
    lines = by[seat]
    print(f"== {run.name}  seat=t{seat}")
    curve = {}
    for l in lines:
        m = re.search(r"f=(\d+)\].*eco-status.*P=(\d+)/(\d+).*inc=([\d.]+)", l)
        if m:
            curve[round(int(m.group(1)) / 1800)] = (int(m.group(2)), float(m.group(4)))
    print("  P/inc:   " + "  ".join(f"{mn}m {curve.get(mn, ('-', '-'))[0]}/{curve.get(mn, ('-','-'))[1]}" for mn in MIN
                                    if mn in curve))
    prod = {}
    for l in lines:
        m = re.search(r"decide t=\d+ .* -> produce:(\w+)", l)
        if m:
            prod[m.group(1)] = prod.get(m.group(1), 0) + 1
    print("  cons ordered: " + " ".join(f"{k}={v}" for k, v in sorted(prod.items(), key=lambda kv: -kv[1])))
    new = {}
    for l in lines:
        m = re.search(r"request new (\w+)", l)
        if m:
            new[m.group(1)] = new.get(m.group(1), 0) + 1
    top = sorted(new.items(), key=lambda kv: -kv[1])[:8]
    print("  sites new (rate-limited log): " + " ".join(f"{k}={v}" for k, v in top))
    lat = {}
    for l in lines:
        m = re.search(r"latency (\w+) done=(\d+) workers=(\d+)", l)
        if m:
            d = lat.setdefault(m.group(1), [0, 0, 0])
            d[0] += 1; d[1] += int(m.group(2)); d[2] += int(m.group(3))
    top = sorted(lat.items(), key=lambda kv: -kv[1][0])[:6]
    print("  grounds: " + " ".join(f"{k}=n{v[0]}/lat{v[1]/v[0]:.0f}s/crew{v[2]/v[0]:.1f}" for k, v in top))
    unreach = sum(1 for l in lines if "apex: unreach" in l)
    peel = [l for l in lines if "apex: peeled" in l]
    nf = re.search(r"nanoFed=(\d+)", peel[-1]).group(1) if peel and "nanoFed=" in peel[-1] else "-"
    elec = sum(1 for l in lines if "apex: decide t=" in l and "produce:" not in l)
    print(f"  elections={elec} unreach={unreach} nanoFedPeels={nf}")
    st = [l for l in text.splitlines() if f"[BARAI_STATS] team={seat} " in l]
    if st:
        s = st[-1]
        g = lambda k: re.search(rf"\b{k}=(-?\d+)", s).group(1) if re.search(rf"\b{k}=(-?\d+)", s) else "-"
        print(f"  built={g('mBuiltReal')} eco={g('mEco')} BP={g('mBP')} def={g('mDefence')} army={g('mArmy')}")
    w = [l for l in text.splitlines() if "[BARAI_WASTE]" in l and f"team={seat} " in l]
    if w:
        m = re.search(r"mWaste=(\d+) mMade=(\d+) eWaste=(\d+) eMade=(\d+)", w[-1])
        mw, mm, ew, em = map(int, m.groups())
        print(f"  waste: metal {mw}/{mm} ({100*mw/max(mm,1):.0f}%)  energy {100*ew/max(em,1):.0f}%")


if __name__ == "__main__":
    for a in sys.argv[1:]:
        read(Path(a))
