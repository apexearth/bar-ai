"""The game as a story in time buckets, and where it turned.

apexearth 2026-09-19: "You can pretty much not ever just look at the final
numbers in the game. That's never telling you what the story is. You need to
look at things in buckets... capture the game and say 'this is the moment where
things started to turn'."

    python tools/story.py <match-dir> [--bucket 60] [--from 0] [--to 999]

One line per bucket for each side (allies pooled), stamped with the bucket's
END minute (standing values are read there; lost/built/spent are the bucket's
own): income, mexes held and
changed (by region: home / mid / enemy ground), standing army metal, how far
forward that army sits (0 = own start, 1 = enemy start), metal lost and to
what, what was finished, and the apex retreat counters. Then the TURN: the
last bucket the mex, army and income leads changed hands, the worst single-
bucket trade for each side, and the narrative around the earliest of them.

Reads the dev gadget's [BARAI_*] lines (ARMY every 10 s, DEATH every death,
STATS/POS every 2 min, BUILD per finished building) plus the apex: lines the
AI writes, so it reads BARb's side as well as ours.
"""
import argparse
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import battles  # noqa: E402  (parse, load_cost_table, team_labels)

FPS = 30
STATS_RE = re.compile(r"\[BARAI_STATS\] team=(\d+) ally=(\d+) \S+ frame=(\d+).*? mDefence=(\d+) mEco=(\d+) mArmy=(\d+) mBP=(\d+).*? mInc=([\d.]+)")
POS_RE = re.compile(r"\[BARAI_POS\] team=(\d+) ally=(\d+) frame=(\d+) n=\d+ part=\d+/\d+ (\S+)")
BUILD_RE = re.compile(r"\[BARAI_BUILD\] team=(\d+) ally=(\d+) frame=(\d+) min=[\d.]+ unit=(\S+) cost=(\d+)")
APEX_RE = re.compile(r"\[f=(\d+)\].*?apex: (withdraw|con-retreat|withdraw-hold|STALL interrupt|keep-job)\b.*?\bt=(\d+)")
APEX_RE2 = re.compile(r"\[f=(\d+)\].*?\[[\d.]+m t(\d+)\] apex: (withdraw|con-retreat|withdraw-hold)\b")

BUILDERS = set("""armck armcv armca armcom armack armacv armaca armbeaver armch armrectr armfark
armdecom armmlv armcsa armcs armcsp corck corcv corca corcom corack coracv coraca cornecro
corfast cormuskrat corch cormlv corcsa corcs corcsp corvac legck legcv legca legcom legack
legacv legaca legrezbot legch legotter""".split())


def category(name):
    n = name.lower()
    if "mex" in n or "moho" in n or n.endswith("uwmme") or "uwmex" in n:
        return "mex"
    if any(k in n for k in ("makr", "mmkr", "fmkr", "uwmmm")):
        return "conv"
    if any(k in n for k in ("solar", "advsol", "win", "fus", "geo", "tide", "wint")):
        return "energy"
    if "nanotc" in n or "nanotcplat" in n:
        return "nano"
    if any(k in n for k in ("lab", "vp", "ap", "hp", "shltx", "gant", "sy", "plat", "fhp", "amsub", "asy")) and "nanotcplat" not in n:
        return "plant"
    if any(k in n for k in ("llt", "beamer", "hlt", "guard", "pb", "anni", "claw", "rl", "ferret",
                             "cir", "flak", "mercury", "screamer", "doom", "vipe", "toast", "pun",
                             "maw", "hllt", "erad", "madsam", "exp", "tl", "dl", "drag", "fort")):
        return "def"
    return "other"


def region(x, z, own, foe):
    """0..1 along own start -> enemy start; home / mid / enemy by thirds."""
    do = math.hypot(x - own[0], z - own[1])
    de = math.hypot(x - foe[0], z - foe[1])
    if do + de < 1:
        return 0.5
    return do / (do + de)


def rname(f):
    return "home" if f < 0.4 else ("mid" if f <= 0.6 else "enemy")


def load(match_dir):
    text = (match_dir / "infolog.txt").read_text("utf-8", errors="replace")
    deaths, starts, costs, snaps = battles.parse(text)
    ally = {}
    inc = defaultdict(dict)       # frame -> team -> mInc
    spent = defaultdict(dict)     # frame -> team -> (def, eco, army, bp) cumulative
    for t, a, f, md_, me, ma, mb, mi in STATS_RE.findall(text):
        ally[int(t)] = int(a)
        inc[int(f)][int(t)] = float(mi)
        spent[int(f)][int(t)] = (int(md_), int(me), int(ma), int(mb))
    pos = defaultdict(lambda: defaultdict(list))   # frame -> team -> [(name,x,z)]
    for t, a, f, data in POS_RE.findall(text):
        ally[int(t)] = int(a)
        for tok in data.split(","):
            p = tok.split(":")
            if len(p) >= 3:
                pos[int(f)][int(t)].append((p[0], int(p[1]), int(p[2])))
    builds = []
    for t, a, f, unit, cost in BUILD_RE.findall(text):
        builds.append((int(f), int(t), unit, int(cost)))
    notes = []
    for f, t, what in APEX_RE2.findall(text):
        notes.append((int(f), int(t), what))
    return deaths, starts, costs, snaps, ally, inc, spent, pos, builds, notes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("match")
    ap.add_argument("--bucket", type=int, default=60, help="seconds per bucket")
    ap.add_argument("--from", dest="mfrom", type=float, default=0)
    ap.add_argument("--to", dest="mto", type=float, default=999)
    args = ap.parse_args()
    md = Path(args.match)
    deaths, starts, costs, snaps, ally, inc, spent, pos, builds, notes = load(md)
    sides = sorted(set(ally.values()))
    if len(sides) != 2:
        print("need exactly two allyteams, saw", sides)
        return 1
    A, B = sides
    teams_of = {s: sorted(t for t in ally if ally[t] == s) for s in sides}
    # the ally index is the spec index (S16), whatever the team layout
    specs = []
    try:
        import json
        specs = [t.get("spec", "?") for t in json.loads((md / "result.json").read_text()).get("teams", [])]
    except (OSError, ValueError):
        pass
    name_of = {s: (specs[s] if s < len(specs) else "ally%d" % s) for s in sides}
    cent = {}
    for s in sides:
        pts = [starts[t] for t in teams_of[s] if t in starts]
        cent[s] = (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)) if pts else (0, 0)
    foe = {A: B, B: A}
    bf = args.bucket * FPS
    last_frame = max([d.frame for d in deaths] + list(snaps) + list(inc) + [0])
    nb = last_frame // bf + 1

    def bucket_of(frame):
        return frame // bf

    # per bucket, per side
    lost = defaultdict(lambda: defaultdict(float))      # [b][s] metal lost (built units)
    killer = defaultdict(lambda: defaultdict(Counter))  # [b][s] killer def -> metal
    where = defaultdict(lambda: defaultdict(Counter))   # [b][s] region -> metal lost
    what = defaultdict(lambda: defaultdict(Counter))    # [b][s] def -> metal lost
    mexlost = defaultdict(lambda: defaultdict(Counter))  # [b][s] region -> count
    for d in deaths:
        s = ally.get(d.team)
        if s is None or d.built == 0:
            continue
        b = bucket_of(d.frame)
        c = costs.get(d.unit, d.cost)
        r = rname(region(d.x, d.z, cent[s], cent[foe[s]]))
        lost[b][s] += c
        what[b][s][d.unit] += c
        where[b][s][r] += c
        if d.atk != "?" and d.atkteam >= 0 and ally.get(d.atkteam) != s:
            killer[b][s][d.atk] += c
        if category(d.unit) == "mex":
            mexlost[b][s][r] += 1
    built = defaultdict(lambda: defaultdict(Counter))   # [b][s] category -> metal
    builtn = defaultdict(lambda: defaultdict(Counter))
    for f, t, unit, cost in builds:
        s = ally.get(t)
        if s is None:
            continue
        b = bucket_of(f)
        built[b][s][category(unit)] += cost
        builtn[b][s][category(unit)] += 1
    note = defaultdict(lambda: defaultdict(Counter))
    for f, t, w in notes:
        s = ally.get(t)
        if s is not None:
            note[bucket_of(f)][s][w] += 1
    # army standing + front, from the nearest snapshot at the bucket's end
    snap_frames = sorted(snaps)

    def army_at(frame, s):
        cand = [f for f in snap_frames if f <= frame]
        if not cand:
            return 0.0, None
        f = cand[-1]
        m = 0.0
        fw = 0.0
        for t in teams_of[s]:
            for (_, name, x, z, hp) in snaps[f].get(t, []):
                if name in BUILDERS:
                    continue
                c = costs.get(name, 0) * hp / 100.0
                m += c
                fw += c * region(x, z, cent[s], cent[foe[s]])
        return m, (fw / m if m > 0 else None)

    def mex_at(frame, s):
        cand = [f for f in sorted(pos) if f <= frame]
        if not cand:
            return None, Counter()
        f = cand[-1]
        byr = Counter()
        for t in teams_of[s]:
            for (name, x, z) in pos[f].get(t, []):
                if category(name) == "mex":
                    byr[rname(region(x, z, cent[s], cent[foe[s]]))] += 1
        return sum(byr.values()), byr

    def inc_at(frame, s):
        cand = [f for f in sorted(inc) if f <= frame]
        if not cand:
            return None
        return sum(inc[cand[-1]].get(t, 0.0) for t in teams_of[s])

    def spent_at(frame, s):
        cand = [f for f in sorted(spent) if f <= frame]
        if not cand:
            return None
        tot = [0, 0, 0, 0]
        for t in teams_of[s]:
            v = spent[cand[-1]].get(t)
            if v:
                for i in range(4):
                    tot[i] += v[i]
        return tot

    def spent_in(b, s):
        """metal into def/eco/army/bp during bucket b (cumulative deltas)."""
        a0 = spent_at(b * bf - 1, s)
        a1 = spent_at((b + 1) * bf - 1, s)
        if a0 is None or a1 is None:
            return None
        return [a1[i] - a0[i] for i in range(4)]

    print("match %s   %s = %s   %s = %s   bucket %ds   (front: 0 = own start, 1 = enemy start)"
          % (md.name[:60], "A", name_of[A], "B", name_of[B], args.bucket))
    print("%5s | %-4s | %5s %5s %-13s | %6s %5s | %-21s | %7s %-34s | %-30s | %s" % (
        "by", "side", "inc", "mex", "(home/mid/en)", "army", "front", "spent arm/eco/def/bp", "lost", "to (region)", "built", "notes"))
    series = []   # (b, incA, incB, mexA, mexB, armyA, armyB, lostA, lostB, killedA, killedB)
    prev_mex = {A: None, B: None}
    for b in range(nb):
        fend = (b + 1) * bf - 1
        minute = (b + 1) * args.bucket / 60.0   # the bucket's END: army/mex/inc are read there
        row = {}
        for s in (A, B):
            m, fw = army_at(fend, s)
            mx, byr = mex_at(fend, s)
            row[s] = (inc_at(fend, s), mx, byr, m, fw)
        series.append((b, row[A][0], row[B][0], row[A][1], row[B][1], row[A][3], row[B][3],
                       lost[b][A], lost[b][B]))
        if not (args.mfrom <= minute < args.mto):
            continue
        for s in (A, B):
            i, mx, byr, m, fw = row[s]
            dmx = ""
            if mx is not None and prev_mex[s] is not None and mx != prev_mex[s]:
                dmx = "%+d" % (mx - prev_mex[s])
            prev_mex[s] = mx if mx is not None else prev_mex[s]
            tops = ", ".join("%s %dm" % (k, v) for k, v in killer[b][s].most_common(2))
            regs = " ".join("%s:%d" % (k, v) for k, v in where[b][s].most_common(2))
            ml = " ".join("mex-%s x%d" % (k, v) for k, v in mexlost[b][s].items())
            bl = " ".join("%s:%d/%dm" % (k, builtn[b][s][k], v) for k, v in built[b][s].most_common(4))
            nt = " ".join("%s:%d" % (k, v) for k, v in note[b][s].items())
            sp = spent_in(b, s)
            spt = "-" if sp is None else "%d/%d/%d/%d" % (sp[2], sp[1], sp[0], sp[3])
            print("%5.1f | %-4s | %5s %5s %-13s | %6.0f %5s | %-21s | %7.0f %-34s | %-30s | %s %s" % (
                minute, "A" if s == A else "B",
                "-" if i is None else "%.0f" % i,
                ("-" if mx is None else str(mx)) + dmx,
                "" if not byr else "%d/%d/%d" % (byr.get("home", 0), byr.get("mid", 0), byr.get("enemy", 0)),
                m, "-" if fw is None else "%.2f" % fw, spt,
                lost[b][s], (tops + (" @" + regs if regs else ""))[:34], bl[:30], nt, ml))
        print("-" * 150)

    # ---- the turn -------------------------------------------------------
    def last_flip(key):
        prev = 0
        at = None
        for (b, iA, iB, mA, mB, aA, aB, lA, lB) in series:
            va, vb = key((iA, iB, mA, mB, aA, aB))
            if va is None or vb is None:
                continue
            sgn = (va > vb) - (va < vb)
            if sgn != 0 and prev != 0 and sgn != prev:
                at = b
            if sgn != 0:
                prev = sgn
        return at, prev

    print()
    print("THE TURN  (buckets where a lead last changed hands; who holds it now)")
    flips = {}
    for label, key in (("mexes", lambda v: (v[2], v[3])), ("army", lambda v: (v[4], v[5])),
                       ("income", lambda v: (v[0], v[1]))):
        at, now = last_flip(key)
        holder = name_of[A] if now > 0 else (name_of[B] if now < 0 else "even")
        print("  %-7s lead: %s, now %s" % (label, "never changed" if at is None else "last flipped by %.1f min" % ((at + 1) * args.bucket / 60.0), holder))
        flips[label] = at
    worst = {}
    for s in (A, B):
        o = foe[s]
        trade = [(b, lost[b][o] - lost[b][s]) for b in range(nb)]
        bw, tw = min(trade, key=lambda x: x[1])
        worst[s] = bw
        print("  worst bucket for %s: the one ending %.1f min, net trade %+.0f metal (lost %.0f, killed %.0f)" % (
            name_of[s], (bw + 1) * args.bucket / 60.0, tw, lost[bw][s], lost[bw][o]))
    cands = [v for v in flips.values() if v is not None] + list(worst.values())
    if not cands:
        return 0
    turn = min(cands)
    print()
    print("AROUND THE BUCKET ENDING %.1f MIN" % ((turn + 1) * args.bucket / 60.0))
    for b in range(max(0, turn - 2), min(nb, turn + 3)):
        minute = (b + 1) * args.bucket / 60.0
        for s in (A, B):
            o = foe[s]
            i, mx, byr, m, fw = None, None, None, None, None
            fend = (b + 1) * bf - 1
            m, fw = army_at(fend, s)
            mx, byr = mex_at(fend, s)
            m0, fw0 = army_at(b * bf - 1, s)
            move = ""
            if fw is not None and fw0 is not None and abs(fw - fw0) >= 0.05:
                move = "army moved %s (%.2f -> %.2f)" % ("BACK" if fw < fw0 else "FORWARD", fw0, fw)
            deadw = ", ".join("%s %dm" % (k, v) for k, v in what[b][s].most_common(3))
            tops = ", ".join("%s %dm" % (k, v) for k, v in killer[b][s].most_common(3))
            regs = ", ".join("%s %dm" % (k, v) for k, v in where[b][s].most_common(3))
            ml = ", ".join("%d mex on %s ground" % (v, k) for k, v in mexlost[b][s].items())
            bl = ", ".join("%d %s (%dm)" % (builtn[b][s][k], k, v) for k, v in built[b][s].most_common(3))
            sp = spent_in(b, s)
            if sp is not None:
                bl = ("spent army %d, eco %d, def %d, buildpower %d; " % (sp[2], sp[1], sp[0], sp[3])) + bl
            nt = ", ".join("%s x%d" % (k, v) for k, v in note[b][s].items())
            print("  by %4.1f %-26s army %6.0fm front %s  mex %s  %s" % (
                minute, name_of[s][:26], m, "-" if fw is None else "%.2f" % fw,
                "-" if mx is None else mx, move))
            if lost[b][s] > 0:
                print("        lost %.0fm: %s | to %s | on %s%s" % (lost[b][s], deadw, tops or "?", regs, ("; " + ml) if ml else ""))
            if bl:
                print("        finished: %s" % bl)
            if nt:
                print("        apex: %s" % nt)
    return 0


if __name__ == "__main__":
    sys.exit(main())
