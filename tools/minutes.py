"""One team game, minute by minute, per side: income, waste, what was built,
mexes standing, metal lost and killed, damage dealt and taken.

    python tools/minutes.py <match-dir> [--step 1]

perminute.py splits sides at team < 2 and so misreads any game bigger than a
2v2; this reads each team's alliance from its own [BARAI_PROD]/[BARAI_BUILD]
lines. Sources, all in the match infolog: [BARAI_WASTE] (cumulative metal and
energy made/wasted, once a minute), [BARAI_BUILD]/[BARAI_PROD] (finished
structures and units, with cost), [BARAI_DEATH] (cost, owner, killer; built=0
is a frame destroyed unfinished), [BARAI_DMG] (cumulative hit points dealt to
mobile/static and received, every 10 s). "us" is the alliance without BARb.

Columns per side:
  inc     metal made per second over the minute;  eInc  energy made per second
  mW% eW% share of the metal / energy made that minute that was thrown away
  built   metal of structures and units finished that minute
  mex     extractors standing
  lost    metal of our finished units/buildings destroyed that minute
  kill    metal of theirs we destroyed that minute
  k/l     kill / lost that minute;  K/L  the same, cumulative
  dmgOut  hit points dealt (thousands);  dmgIn  hit points taken
  D%      damage efficiency, dealt / received x100, that minute; cD% cumulative
          (his trade measure, not k/l -- memory how-to-test-and-report)
"""
import collections
import re
import sys

FPM = 1800
RE_WASTE = re.compile(r"\[BARAI_WASTE\] frame=(\d+) team=(\d+) mWaste=(\d+) mMade=(\d+) eWaste=(\d+) eMade=(\d+)")
RE_BUILT = re.compile(r"\[BARAI_(?:PROD|BUILD)\] team=(\d+) ally=(\d+) frame=(\d+) min=[\d.]+ unit=(\w+) cost=(\d+)")
RE_DEATH = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\w+) cost=(\d+) .*? built=(\d) .*? atkteam=(-?\d+)")
RE_DMG = re.compile(r"\[BARAI_DMG\] frame=(\d+) team=(\d+) dm=(\d+) ds=(\d+) rm=(\d+) rs=(\d+)")
RE_NAME = re.compile(r"\[BARAI_NAME\] team=(\d+) name=(.*)")
MEX = re.compile(r"(mex|moho|mme)\d*$")


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    path = argv[0]
    step = int(argv[argv.index("--step") + 1]) if "--step" in argv else 1
    with open(path.rstrip("/\\") + "/infolog.txt", encoding="utf-8", errors="replace") as fh:
        txt = fh.read()

    ally = {}
    for m in RE_BUILT.finditer(txt):
        ally[int(m.group(1))] = int(m.group(2))
    # The start script names each AI seat's short name; BARb's alliance is them.
    barb_teams = set()
    try:
        with open(path.rstrip("/\\") + "/script.txt", encoding="utf-8", errors="replace") as fh:
            script = fh.read()
        for block in re.findall(r"\[ai\d+\]\s*\{(.*?)\}", script, re.S | re.I):
            tm = re.search(r"team=(\d+);", block, re.I)
            if tm and re.search(r"shortname=BARb;", block, re.I):
                barb_teams.add(int(tm.group(1)))
    except OSError:
        pass
    barb_allies = {ally[t] for t in barb_teams if t in ally}
    side = lambda t: "them" if ally.get(t, -1) in barb_allies else "us"

    last_min = 0
    made = collections.defaultdict(dict)   # (side, minute) -> summed cumulative per team
    wmade = {}
    for m in RE_WASTE.finditer(txt):
        f, t = int(m.group(1)), int(m.group(2))
        wmade[(t, f // FPM)] = tuple(int(m.group(i)) for i in (3, 4, 5, 6))
        last_min = max(last_min, f // FPM)
    built = collections.Counter()
    mexd = collections.Counter()
    for m in RE_BUILT.finditer(txt):
        t, f, unit, cost = int(m.group(1)), int(m.group(3)), m.group(4), int(m.group(5))
        built[(side(t), f // FPM)] += cost
        if MEX.search(unit):
            mexd[(side(t), f // FPM)] += 1
        last_min = max(last_min, f // FPM)
    lost = collections.Counter()
    kill = collections.Counter()
    for m in RE_DEATH.finditer(txt):
        f, t, unit, cost, fin, atk = (int(m.group(1)), int(m.group(2)), m.group(3),
                                      int(m.group(4)), m.group(5) == "1", int(m.group(6)))
        mn = f // FPM
        # Our own reclaim of our own building is not a loss to the enemy.
        if fin and atk >= 0 and side(atk) == side(t):
            if MEX.search(unit):
                mexd[(side(t), mn)] -= 1
            continue
        if fin:
            lost[(side(t), mn)] += cost
            if MEX.search(unit):
                mexd[(side(t), mn)] -= 1
            if atk >= 0 and side(atk) != side(t):
                kill[(side(atk), mn)] += cost
    dmg = {}
    for m in RE_DMG.finditer(txt):
        f, t = int(m.group(1)), int(m.group(2))
        dmg[(t, f // FPM)] = (int(m.group(3)) + int(m.group(4)), int(m.group(5)) + int(m.group(6)))

    teams = sorted(ally)

    def cum_waste(s, mn):
        tot = [0, 0, 0, 0]
        for t in teams:
            if side(t) != s:
                continue
            best = None
            for k in range(mn, -1, -1):
                if (t, k) in wmade:
                    best = wmade[(t, k)]
                    break
            if best:
                tot = [a + b for a, b in zip(tot, best)]
        return tot

    def cum_dmg(s, mn):
        out = [0, 0]
        for t in teams:
            if side(t) != s:
                continue
            for k in range(mn, -1, -1):
                if (t, k) in dmg:
                    out = [out[0] + dmg[(t, k)][0], out[1] + dmg[(t, k)][1]]
                    break
        return out

    hdr = (" min | side |  inc  eInc  mW%  eW% | built  mex |  lost  kill   k/l   K/L | dmgOut dmgIn   D%  cD%")
    print(f"{path}  (us = the alliance without BARb)")
    print(hdr)
    print("-" * len(hdr))
    mexn = collections.Counter()
    cl = collections.Counter()
    ck = collections.Counter()
    prev_w = {"us": [0, 0, 0, 0], "them": [0, 0, 0, 0]}
    prev_d = {"us": [0, 0], "them": [0, 0]}
    for mn in range(0, last_min + 1):
        for s in ("us", "them"):
            mexn[s] += mexd[(s, mn)]
            cl[s] += lost[(s, mn)]
            ck[s] += kill[(s, mn)]
        if (mn + 1) % step and mn != last_min:
            continue
        for s in ("us", "them"):
            w = cum_waste(s, mn)
            dw = [a - b for a, b in zip(w, prev_w[s])]
            prev_w[s] = w
            d = cum_dmg(s, mn)
            dd = [a - b for a, b in zip(d, prev_d[s])]
            prev_d[s] = d
            span = 60.0 * step
            inc = dw[1] / span
            einc = dw[3] / span
            mw = (100.0 * dw[0] / dw[1]) if dw[1] > 0 else 0.0
            ew = (100.0 * dw[2] / dw[3]) if dw[3] > 0 else 0.0
            b = sum(built[(s, k)] for k in range(mn - step + 1, mn + 1))
            lo = sum(lost[(s, k)] for k in range(mn - step + 1, mn + 1))
            ki = sum(kill[(s, k)] for k in range(mn - step + 1, mn + 1))
            kl = f"{ki / lo:5.2f}" if lo > 0 else "    -"
            KL = f"{ck[s] / cl[s]:5.2f}" if cl[s] > 0 else "    -"
            print(f"{mn + 1:4d} | {s:4s} | {inc:4.0f} {einc:5.0f} {mw:4.0f} {ew:4.0f} | {b:5d} {mexn[s]:4d} |"
                  f" {lo:5d} {ki:5d} {kl} {KL} | {dd[0] / 1000:6.0f} {dd[1] / 1000:5.0f}"
                  f" {(100.0 * dd[0] / dd[1]) if dd[1] > 0 else 0:4.0f}"
                  f" {(100.0 * d[0] / d[1]) if d[1] > 0 else 0:4.0f}")
        print("-" * len(hdr))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
