"""Builder decisions joined to what followed them: the training table for a value net.

    python tools/decisions.py <match|tournament> [more...] [--out rows.jsonl]

Inputs come from `apex: nn` lines (manager/brain/market/nnlog.as): the state at
the decision, up to 8 ranked options as priced, which one ran, and each
option's draw probability (p; the roulette is the exploration, so p is the
propensity an off-policy estimate needs). Outcomes come from the gadget lines
minutes.py reads, for the DECIDING team, at +1/+3/+5 minutes:

  dMInc / dEInc   ln(income over the minute ending at f+h / the minute ending at f)
  mWaste / eWaste share of the metal / energy made in (f, f+h] that was thrown away
  dMex            extractors standing at f+h minus at f
  lnD             ln((dealt+1)/(received+1)) hit points in (f, f+h] -- damage efficiency
  kill / lost     metal destroyed by / of this team in (f, f+h]; lost counts only
                  enemy kills, split into lostNear (within NEAR of the chosen site:
                  the decision's own exposure) and lostFar (the enemy's doing)
  survived        the chosen building still stood SURVIVE_S after it finished

A horizon past the end of the game is null. The summary checks the instrument:
nn lines against exec lines per team, so a decision path that writes no record
shows up as coverage below 100%.
"""
import bisect
import json
import math
import os
import re
import sys

FPM = 1800
HORIZONS = (1, 3, 5)
NN = re.compile(r"\]\[f=(\d+)\] .*?apex: nn t=(\d+) f=\d+ u=(\d+) c=(\S+) pick=(\d+) why=(\S*) dm=(\S+)"
                r" \| (\S+)(?: \| (.*?))? \| chosen=(-?\d+)")
SCHEMA = re.compile(r"apex: nn-schema v(\d+) state=(\S+) opt=(\S+)")
EXEC = re.compile(r"apex: exec t=(\d+) ")
WASTE = re.compile(r"\[BARAI_WASTE\] frame=(\d+) team=(\d+) mWaste=(\d+) mMade=(\d+) eWaste=(\d+) eMade=(\d+)")
BUILT = re.compile(r"\[BARAI_(?:PROD|BUILD)\] team=(\d+) ally=(\d+) frame=(\d+) min=[\d.]+ unit=(\w+) cost=(\d+)"
                   r"(?: x=(-?\d+) z=(-?\d+))?(?: uid=(\d+))?")
UIDS = re.compile(r" uid=(\d+) atkid=(-?\d+)")
LIFE_CAP_S = 1200   # a building's lifetime outcomes are counted for at most 20 minutes
DEATH = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\w+) cost=(\d+) x=(-?\d+) z=(-?\d+)"
                   r" .*? built=(\d) .*? atkteam=(-?\d+) atk=(\S+)")
STATS = re.compile(r"\[BARAI_STATS\] team=(\d+) .*?frame=(\d+) .*?mReclaim=(\d+)")
NEAR = 600      # elmos: losses this close to the chosen site are the decision's own exposure
SURVIVE_S = 300
DMG = re.compile(r"\[BARAI_DMG\] frame=(\d+) team=(\d+) dm=(\d+) ds=(\d+) rm=(\d+) rs=(\d+)")
MEX = re.compile(r"(mexp?|moho|mme)\d*$")
NOT_A_BUILD = {"reclaim", "assist"}   # their def names the target, not something we make
CANFLY = re.compile(r"\bcanfly\s*=\s*true", re.I)
SPEED = re.compile(r"\bspeed\s*=\s*([\d.]+)", re.I)
_KILLER = {}


def killer_class(name):
    """air / static / mobile for the unit that made a kill, from its unit def;
    '?' when the game logged no killer (bombs often carry atk=?)."""
    if name in _KILLER:
        return _KILLER[name]
    cls = "?"
    if name and name != "?":
        try:
            import bar_env
            import unitdef
            p = unitdef.trees(bar_env.load())[0].find(name)
            if p is not None:
                text = p.read_text(encoding="utf-8", errors="replace")
                m = SPEED.search(text)
                cls = "air" if CANFLY.search(text) else ("mobile" if m and float(m.group(1)) > 0 else "static")
        except Exception:
            cls = "?"
    _KILLER[name] = cls
    return cls


class Series:
    """A cumulative counter sampled at frames, read anywhere by linear interpolation."""

    def __init__(self):
        self.f, self.v = [0], [0.0]

    def add(self, f, v):
        if f > self.f[-1]:
            self.f.append(f)
            self.v.append(v)

    def at(self, f):
        if f > self.f[-1]:
            return None
        i = bisect.bisect_right(self.f, f)
        if i >= len(self.f):
            return self.v[-1]
        f0, f1 = self.f[i - 1], self.f[i]
        return self.v[i - 1] + (self.v[i] - self.v[i - 1]) * (f - f0) / (f1 - f0)


def num(s):
    try:
        return float(s)
    except ValueError:
        return s


def match_dirs(targets):
    for t in targets:
        if os.path.isfile(os.path.join(t, "infolog.txt")):
            yield t
            continue
        for root, _dirs, files in os.walk(t):
            if "infolog.txt" in files:
                yield root


class _Chain:
    """Several log files read as one stream: a running game keeps its gadget
    lines and each AI's lines in separate files until run_match merges them."""

    def __init__(self, files):
        self.files = files

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def __iter__(self):
        for f in self.files:
            try:
                with open(f, encoding="utf-8", errors="replace") as fh:
                    yield from fh
            except OSError:
                continue


def fingerprint(g):
    """The same game's identity whether read live or finished: its first records."""
    first = sorted((int(r[0]), int(r[1]), int(r[2])) for r in g["rows"])[:3]
    return "|".join("%d.%d.%d" % k for k in first)


def parse(path, files=None):
    sm, se, wm, we = {}, {}, {}, {}
    dealt, recv = {}, {}
    mexev, killev, lostev, builds, dead = {}, {}, {}, {}, {}
    died, killby = {}, {}   # by unit id: frame it died; (frame, metal) of what it killed
    rows, execs, nns, reclaim = [], {}, {}, {}
    explore = False
    state_keys, opt_keys = None, None
    lastw = lastd = 0
    with _Chain(files or [os.path.join(path, "infolog.txt")]) as fh:
        for ln in fh:
            if "apex: nn" in ln:
                m = SCHEMA.search(ln)
                if m:
                    state_keys, opt_keys = m.group(2).split(","), m.group(3).split(",")
                    explore = explore or "explore=1" in ln
                    continue
                m = NN.search(ln)
                if m:
                    rows.append(m.groups())
                    nns[int(m.group(2))] = nns.get(int(m.group(2)), 0) + 1
                continue
            m = EXEC.search(ln)
            if m:
                execs[int(m.group(1))] = execs.get(int(m.group(1)), 0) + 1
                continue
            if "[BARAI_" not in ln:
                continue
            m = STATS.search(ln)
            if m:
                reclaim.setdefault(int(m.group(1)), Series()).add(int(m.group(2)), float(m.group(3)))
                continue
            m = WASTE.search(ln)
            if m:
                f, t = int(m.group(1)), int(m.group(2))
                for d, k in ((sm, 4), (se, 6), (wm, 3), (we, 5)):
                    d.setdefault(t, Series()).add(f, float(m.group(k)))
                lastw = max(lastw, f)
                continue
            m = DMG.search(ln)
            if m:
                f, t = int(m.group(1)), int(m.group(2))
                dealt.setdefault(t, Series()).add(f, float(m.group(3)) + float(m.group(4)))
                recv.setdefault(t, Series()).add(f, float(m.group(5)) + float(m.group(6)))
                lastd = max(lastd, f)
                continue
            m = BUILT.search(ln)
            if m:
                bx = int(m.group(6)) if m.group(6) is not None else None
                bz = int(m.group(7)) if m.group(7) is not None else None
                uid = int(m.group(8)) if m.group(8) is not None else None
                builds.setdefault(int(m.group(1)), []).append((int(m.group(3)), m.group(4), bx, bz, uid))
                if MEX.search(m.group(4)):
                    mexev.setdefault(int(m.group(1)), []).append((int(m.group(3)), 1))
                continue
            m = DEATH.search(ln)
            if m:
                f, t, unit, cost = int(m.group(1)), int(m.group(2)), m.group(3), float(m.group(4))
                x, z, built, atk = int(m.group(5)), int(m.group(6)), m.group(7) == "1", int(m.group(8))
                if built:
                    # only what the enemy killed: a T1 mex dies when its moho
                    # finishes and a reclaimed building dies on purpose
                    if atk >= 0 and atk != t:
                        dead.setdefault(t, []).append((f, unit, x, z))
                    if atk >= 0 and atk != t:
                        lostev.setdefault(t, []).append((f, cost, x, z, killer_class(m.group(9))))
                    if MEX.search(unit):
                        mexev.setdefault(t, []).append((f, -1))
                if atk >= 0 and atk != t:
                    killev.setdefault(atk, []).append((f, cost))
                mu = UIDS.search(ln)
                if mu:
                    died[int(mu.group(1))] = f
                    if atk >= 0 and atk != t and int(mu.group(2)) >= 0:
                        killby.setdefault(int(mu.group(2)), []).append((f, cost))
    return dict(rows=rows, execs=execs, nns=nns, state_keys=state_keys, opt_keys=opt_keys, last=min(lastw, lastd) if lastd else lastw,
                sm=sm, se=se, wm=wm, we=we, dealt=dealt, recv=recv,
                mexev=mexev, killev=killev, lostev=lostev, builds=builds, dead=dead,
                reclaim=reclaim, explore=explore, died=died, killby=killby,
                final=files is None)   # a finished game's merged infolog, not live files


def window_sum(ev, f0, f1):
    return sum(c for f, c in ev if f0 < f <= f1)


def rate(s, f):
    a, b = s.at(f - FPM), s.at(f)
    if a is None or b is None or f < FPM:
        return None
    return (b - a) / 60.0


def near(x0, z0, x, z):
    return (x - x0) ** 2 + (z - z0) ** 2 <= NEAR * NEAR


def labels(g, t, f, site=None):
    y = {}
    sm, se = g["sm"].get(t), g["se"].get(t)
    for h in HORIZONS:
        f1 = f + h * FPM
        out = {}
        if sm is None or f1 > g["last"]:
            y[h] = None
            continue
        m0, m1, e0, e1 = rate(sm, f), rate(sm, f1), rate(se, f), rate(se, f1)
        out["dMInc"] = math.log(m1 / m0) if m0 and m1 else None
        out["dEInc"] = math.log(e1 / e0) if e0 and e1 else None
        for key, made, waste in (("mWaste", sm, g["wm"][t]), ("eWaste", se, g["we"][t])):
            pts = (made.at(f1), made.at(f), waste.at(f1), waste.at(f))
            if None in pts:
                out[key] = None
                continue
            dm = pts[0] - pts[1]
            out[key] = (pts[2] - pts[3]) / dm if dm > 0 else None
        mev = g["mexev"].get(t, [])
        out["dMex"] = sum(d for ff, d in mev if f < ff <= f1)
        d, r = g["dealt"].get(t), g["recv"].get(t)
        if d is not None and r is not None and d.at(f1) is not None and r.at(f1) is not None:
            out["lnD"] = math.log((d.at(f1) - d.at(f) + 1) / (r.at(f1) - r.at(f) + 1))
        else:
            out["lnD"] = None
        out["kill"] = window_sum(g["killev"].get(t, []), f, f1)
        lev = [e for e in g["lostev"].get(t, []) if f < e[0] <= f1]
        out["lost"] = sum(e[1] for e in lev)
        out["lostNear"] = (sum(e[1] for e in lev if near(site[0], site[1], e[2], e[3]))
                           if site else None)
        out["lostFar"] = None if site is None else out["lost"] - out["lostNear"]
        for cls in ("air", "static", "mobile"):
            out["lost" + cls.capitalize()] = sum(e[1] for e in lev if e[4] == cls)
        out["dEco"] = (math.log((m1 + e1 / 60.0) / (m0 + e0 / 60.0))
                       if None not in (m0, m1, e0, e1) and m0 + e0 > 0 and m1 + e1 > 0 else None)
        rc = g["reclaim"].get(t)
        rc0, rc1 = (rc.at(f), rc.at(f1)) if rc is not None else (None, None)
        out["reclaim"] = (rc1 - rc0) / h if None not in (rc0, rc1) else None
        y[h] = out
    # the pressure the state should already have seen: enemy kills of ours in
    # the 5 minutes BEFORE the decision
    y["lostPre"] = sum(e[1] for e in g["lostev"].get(t, []) if f - 5 * FPM < e[0] <= f)
    return y


def rows_of(path, g):
    if g["state_keys"] is None:
        return
    sk, ok = g["state_keys"], g["opt_keys"]
    claimed = set()
    for frame, t, u, con, pick, why, dm, state, opts, chosen in sorted(g["rows"], key=lambda r: int(r[0])):
        f, t = int(frame), int(t)
        sv = [num(x) for x in state.split(",")]
        ov = []
        for o in (opts or "").split(" ; "):
            if o:
                ov.append(dict(zip(ok, (num(x) for x in o.split(",")))))
        ci = int(chosen)
        o = ov[ci] if 0 <= ci < len(ov) else {}
        site = (o["x"], o["z"]) if isinstance(o.get("x"), float) and o["x"] > 0 else None
        y = labels(g, t, f, site)
        builds = bool(o) and o["kind"] not in NOT_A_BUILD
        y["done"], y["buildS"], built = finished(g, t, f, o["def"] if builds else "-", claimed, site)
        y["lifeS"], y["lifeKill"] = lifetime(g, built)
        y["survived"] = survived(g, t, f, o.get("def"), site, y["buildS"]) if y["done"] == 1 and site else None
        yield dict(match=os.path.basename(path.rstrip("/\\")), team=t, f=f, unit=int(u), con=con,
                   pick=int(pick), why=why, dm=dm, state=dict(zip(sk, sv)), opts=ov,
                   chosen=ci, y=y)


def survived(g, t, f, udef, site, build_s):
    """The chosen building, once finished, still standing SURVIVE_S later: 1/0,
    or None when the game ended first."""
    f0 = f + int(build_s * 30)
    f1 = f0 + SURVIVE_S * 30
    for df, unit, x, z in g["dead"].get(t, []):
        if f0 <= df <= f1 and unit == udef and (x - site[0]) ** 2 + (z - site[1]) ** 2 <= 200 * 200:
            return 0
    return None if f1 > g["last"] else 1


SITE_R = 200    # elmos: a finish this close to the decision's site is its building


def finished(g, t, f, udef, claimed, site=None):
    """The first finish of this def by this team after f not already given to an
    earlier decision -- at the decision's own site when the log carries build
    positions, so an abandoned decision cannot take a later one's finish:
    (1, seconds) -- or (0, None) when none came within the longest horizon,
    (None, None) when the game ended first or there is no def."""
    if udef == "-":
        return None, None, None
    f1 = f + HORIZONS[-1] * FPM
    for i, (bf, name, bx, bz, uid) in enumerate(g["builds"].get(t, [])):
        if bf > f1:
            break
        if bf <= f or name != udef or (t, i) in claimed:
            continue
        if site is not None and bx is not None and (bx - site[0]) ** 2 + (bz - site[1]) ** 2 > SITE_R ** 2:
            continue
        claimed.add((t, i))
        return 1, round((bf - f) / 30.0, 1), (bf, uid)
    return (None, None, None) if f1 > g["last"] else (0, None, None)


def lifetime(g, built):
    """The chosen building's own record from its finish: seconds it lived and
    metal it killed, over at most LIFE_CAP_S. None until the cap has been
    played out or it died (a building still standing has not finished its
    record) -- except at the end of a finished game -- and for logs without
    unit ids."""
    if built is None or built[1] is None:
        return None, None
    bf, uid = built
    end = bf + LIFE_CAP_S * 30
    df = g["died"].get(uid)
    if df is not None and df <= end:
        end = df
    elif end > g["last"]:
        if not g.get("final"):
            return None, None
        end = g["last"]   # standing when the game ended: it survived, kills so far
    kills = sum(c for kf, c in g["killby"].get(uid, []) if bf < kf <= end)
    return round((end - bf) / 30.0, 1), kills


def main(argv):
    out = None
    if "--out" in argv:
        i = argv.index("--out")
        out = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    if not argv:
        print(__doc__)
        return 2
    fh = open(out, "w", encoding="utf-8") if out else None
    total, labelled, games = 0, 0, 0
    for path in match_dirs(argv):
        g = parse(path)
        games += 1
        n = 0
        for row in rows_of(path, g):
            n += 1
            labelled += row["y"].get(HORIZONS[-1]) is not None
            if fh:
                fh.write(json.dumps(row, separators=(",", ":")) + "\n")
        total += n
        cov = " ".join(f"t{t}={g['nns'].get(t, 0)}/{e}" for t, e in sorted(g["execs"].items()))
        name = os.path.basename(path.rstrip("/\\"))
        print(f"{name}: {n} decisions, nn/exec {cov or '-'}"
              + ("" if g["state_keys"] else "  (no nn-schema line: logger not in this build)"))
    print(f"{games} games, {total} decisions, {labelled} with a +{HORIZONS[-1]}min label"
          + (f" -> {out}" if out else ""))
    if fh:
        fh.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
