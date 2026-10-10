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
  lostEco         metal of our extractors and mobile constructors (not the
                  commander) the enemy killed in (f, f+h]
  survived       the chosen building still stood SURVIVE_S after it finished
  edgeArmy / edgeEco / edgeLand / edgeMex
                  change in ln(our side / theirs) over the whole minutes from f to
                  f+h, progress.py's edges: did the game move our way
  endFast         the result discounted from the game's start (GAME_TAU)

A horizon past the last logged minute is null, except in a game that ENDED (a
winner), where it runs to the end; a time-capped game (winners= empty) was
stopped, not ended, so its late windows stay null. The summary checks the instrument:
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
HORIZONS = (1, 3, 5, 10)
DONE_H = 5          # minutes: "the chosen build finished" is judged inside this window
RESULT = re.compile(r"\[BARAI_RESULT\] reason=(\w+) frame=(\d+) winners=([\d,]*)")
NN = re.compile(r"\]\[f=(\d+)\] .*?apex: nn t=(\d+) f=\d+ u=(\d+) c=(\S+) pick=(\d+) why=(\S*) dm=(\S+)"
                r" \| (\S+)(?: \| (.*?))? \| chosen=(-?\d+)")
SCHEMA = re.compile(r"apex: nn-schema v(\d+) state=(\S+) opt=(\S+)")
POST_SCHEMA = re.compile(r"apex: nnpost-schema v\d+ state=\S+ post=(\S+) opt=")
NNPOST = re.compile(r"\]\[f=(\d+)\] .*?apex: nnpost t=(\d+) f=\d+ why=(\S+) rule=(\S+) ex=(\d) trust=\S+"
                    r" \| (\S+) \| (\S+) \| (.*?) \| chosen=(-?\d+)")
# the commander's and the T2 decisions, one shape: state | own fields | options | chosen
REINF_DONE = re.compile(r"apex: nnreinf-done t=(\d+) f=(\d+) done=(\d)")
HUNT_DONE = re.compile(r"apex: nnhunt-done t=(\d+) f=(\d+) opt=\d+ done=(-?[\d.]+) kill=(-?\d+) killAll=-?\d+"
                       r" lost=(-?\d+) wreck=(-?\d+)")
HEAD_SCHEMA = re.compile(r"apex: nn(com|tech|raid|air|plan|join|reinf|hunt|strike|open)-schema v\d+ state=\S+ (?:com|tech|raid|air|plan|join|reinf|hunt|strike|open)=(\S+) opt=")
HEAD_ROW = re.compile(r"\]\[f=(\d+)\] .*?apex: nn(com|tech|raid|air|plan|join|reinf|hunt|strike|open) t=(\d+) f=\d+ why=(\S+) rule=(\S+)(?: ex=(\d))?"
                      r"(?: game=\d)? trust=\S+ \| (\S+) \| (\S+) \| (.*?) \| chosen=(-?\d+)")
HEAD_TAG = re.compile(r"apex: nn(?:com|tech|raid|air|plan|join|reinf|hunt|strike|open)")
# the continuous heads (nnlog.as NnValDecide): the value played, the rule's, the range, how it was drawn
VAL_SCHEMA = re.compile(r"apex: nnval-schema v\d+ head=(\w+) state=\S+ own=(\S+)")
VAL_ROW = re.compile(r"\]\[f=(\d+)\] .*?apex: nnval head=(\w+) t=(\d+) f=\d+ v=(\S+) rule=(\S+) lo=(\S+) hi=(\S+)"
                     r" rnd=(\d) dens=(\S+) ex=(\d) game=(\d) trust=(\S+) vnet=\S+ \| (\S+) \| (\S+)")
# static defence (protect_nn.as, protect_nntype.as): site and gun class with their watch
DEF_SCHEMA = re.compile(r"apex: nn(defsite|deftype)-schema v\d+ state=\S+ (?:defsite|deftype)=(\S+) opt=")
DEF_ROW = re.compile(r"\]\[f=(\d+)\] .*?apex: nn(defsite|deftype) t=(\d+) f=\d+ why=(\S+) rule=(\S+)(?: ex=(\d))?"
                     r"(?: game=\d)? trust=\S+ \| (\S+) \| (\S+) \| (.*?) \| chosen=(-?\d+)")
DEFSITE_DONE = re.compile(r"apex: nndef(site|type)-done t=(\d+) f=(\d+) opt=\d+ done=(-?[\d.]+) kill=(-?\d+) lost=(-?\d+)"
                          r" pre=(-?\d+) base=(-?\d+) m=\d+ at=(-?\d+),(-?\d+)")
FAC_SCHEMA = re.compile(r"apex: nnfac-schema v(\d+) state=\S+ opt=(\S+)")
NNFAC = re.compile(r"\]\[f=(\d+)\] .*?apex: nnfac t=(\d+) f=\d+ u=(\d+) c=(\S+) \| (\S+) \| (.*?) \| chosen=(-?\d+)")
PROD = re.compile(r"\[BARAI_PROD\] team=(\d+) ally=\d+ frame=(\d+) min=[\d.]+ unit=(\w+) cost=\d+ fac=\S+"
                  r" uid=(\d+) facid=(\d+)")
EXEC = re.compile(r"apex: exec t=(\d+) ")
WASTE = re.compile(r"\[BARAI_WASTE\] frame=(\d+) team=(\d+) mWaste=(\d+) mMade=(\d+) eWaste=(\d+) eMade=(\d+)(?: eConv=(\d+))?")
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
# legmext15 (Legion's overcharged extractor) replaces a legmex on the same spot
MEX = re.compile(r"(mexp?|moho|mme)(t\d+)?\d*$")
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


BUILDER = re.compile(r"\bbuilder\s*=\s*true", re.I)
_ECO = {}


def eco_kind(name):
    """'mex' for an extractor, 'con' for a mobile constructor other than the
    commander (his death is comLost/comLostD), else None."""
    if name in _ECO:
        return _ECO[name]
    kind = None
    if MEX.search(name):
        kind = "mex"
    elif not name.startswith(COMS):
        try:
            import bar_env
            import unitdef
            p = unitdef.trees(bar_env.load())[0].find(name)
            if p is not None:
                text = p.read_text(encoding="utf-8", errors="replace")
                m = SPEED.search(text)
                if BUILDER.search(text) and m and float(m.group(1)) > 0:
                    kind = "con"
        except Exception:
            kind = None
    _ECO[name] = kind
    return kind


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


def script_text(path):
    """The start script: script.txt in a match dir, _script.txt in a running write dir."""
    for name in ("script.txt", "_script.txt"):
        try:
            with open(os.path.join(path, name), encoding="utf-8", errors="replace") as fh:
                return fh.read()
        except OSError:
            continue
    return ""


def script_regime(path):
    """'<map>|<team sizes>|<cap>' (e.g. 'Comet Catcher Remake 1.8|1v1|20m'): which
    kind of game a row came from, so a buffer can be capped per regime."""
    txt = script_text(path)
    mp = re.search(r"MapName=([^;\n]+);", txt)
    if not mp:
        return None
    per = {}
    for m in re.finditer(r"\[team\d+\]\s*\{(.*?)\}", txt, re.S | re.I):
        a = re.search(r"allyteam=(\d+);", m.group(1), re.I)
        if a:
            per[int(a.group(1))] = per.get(int(a.group(1)), 0) + 1
    cap = re.search(r"dev_maxgameminutes=(\d+);", txt, re.I)
    return "%s|%s|%s" % (mp.group(1).strip(), "v".join(str(n) for n in sorted(per.values(), reverse=True)) or "?",
                         "%sm" % cap.group(1) if cap and int(cap.group(1)) > 0 else "nocap")


VERSION = re.compile(r"apex: version t=(\d+) .*?script=(.+?)\s*$")   # plannet.as VersionBanner


def script_bonus(path):
    """Per engine team (our bonus, the highest enemy bonus), as multiplier - 1,
    read from the match's start script -- what the live state carries as
    ourBonus/foeBonus since 2026-10-08, filled in for games logged before."""
    txt = script_text(path)
    if not txt:
        return {}
    hc, ally = {}, {}
    for m in re.finditer(r"\[team(\d+)\]\s*\{(.*?)\}", txt, re.S | re.I):
        t = int(m.group(1))
        h = re.search(r"handicap=(-?[\d.]+);", m.group(2), re.I)
        a = re.search(r"allyteam=(\d+);", m.group(2), re.I)
        hc[t] = float(h.group(1)) / 100.0 if h else 0.0
        if a:
            ally[t] = int(a.group(1))
    out = {}
    for t in hc:
        foes = [hc[u] for u in hc if ally.get(u) != ally.get(t)]
        out[t] = (hc[t], max(foes) if foes else 0.0)
    return out


_CANON = []


def canon_state():
    """Today's state field list, from the NN_STATE string in the live script."""
    if not _CANON:
        p = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                         "ai", "Unstable", "game-side", "script", "standard", "manager", "brain", "market", "nnlog.as")
        try:
            txt = open(p, encoding="utf-8").read()
            m = re.search(r"const string NN_STATE\s*=\s*(.*?);", txt, re.S)
            _CANON.extend("".join(re.findall(r'"([^"]*)"', m.group(1))).split(","))
        except (OSError, AttributeError):
            pass
    return _CANON


_HEAD_CANON = {}


def canon_head_keys(name):
    """Today's own-field list of a decision head (the string its `nn<name>-schema`
    line logs), from the live script; None when the script does not say."""
    if not _HEAD_CANON:
        root = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                            "ai", "Unstable", "game-side", "script")
        txt = ""
        for dirpath, _, files in os.walk(root):
            for f in files:
                if f.endswith(".as"):
                    with open(os.path.join(dirpath, f), encoding="utf-8", errors="replace") as fh:
                        txt += fh.read() + "\n"
        consts = {m.group(1): "".join(re.findall(r'"([^"]*)"', m.group(2)))
                  for m in re.finditer(r"const string (NN\w+)\s*=\s*(.*?);", txt, re.S)}
        for m in re.finditer(r'"apex: nn(\w+)-schema v\d+ state=" \+ (?:Market::)?NN_STATE\s*\+\s*" \w+=" \+ (NN\w+)', txt):
            if m.group(2) in consts:
                _HEAD_CANON[m.group(1)] = consts[m.group(2)].split(",")
        for m in re.finditer(r'NnValDecide\(\s*"(\w+)",\s*(?:\w+::)?(NN\w+)', txt):
            if m.group(2) in consts:
                _HEAD_CANON[m.group(1)] = consts[m.group(2)].split(",")
        _HEAD_CANON.setdefault("", None)
    return _HEAD_CANON.get(name)


def widen_keys(keys):
    """A game logged before fields were appended reads in today's layout: the
    missing fields are absent from its rows (0 to the trainer) unless filled,
    as ourBonus/foeBonus are from the start script. Without this the trainer
    took the game's own shorter list and never read a filled field."""
    canon = canon_state()
    if keys and canon and len(keys) < len(canon) and canon[:len(keys)] == keys:
        return list(canon)
    return keys


def fill_bonus(g, t, state):
    b = g.get("bonus", {}).get(t)
    if b is not None and "ourBonus" not in state:
        state["ourBonus"], state["foeBonus"] = b
    return state


def parse(path, files=None):
    sm, se, wm, we = {}, {}, {}, {}
    dealt, recv = {}, {}
    mexev, killev, lostev, builds, dead = {}, {}, {}, {}, {}
    died, killby = {}, {}   # by unit id: frame it died; (frame, metal) of what it killed
    facrows, fac_keys, prods = [], None, {}
    allyof, winners = {}, None   # engine team -> ally team; winning ally teams (BARAI_RESULT)
    postrows, post_keys = [], None
    heads = {}   # "com" / "tech": {"keys": their own fields, "rows": [...]}
    vals = {}    # the continuous heads ("con", "mex", ...), the same shape
    rows, execs, nns, reclaim = [], {}, {}, {}
    explore = False
    explorers = set()   # engine teams that rolled discovery (apex: nn-explore t=N on)
    reinf_done = {}     # (team, decision frame) -> arrived while the fight raged (apex: nnreinf-done)
    hunt_done = {}      # (team, decision frame) -> the trade near the watched army (apex: nnhunt-done)
    defsite_done = {}   # (team, decision frame) -> the trade at the chosen gun site (apex: nndefsite-done)
    deftype_done = {}   # ...and at the chosen gun class's site (apex: nndeftype-done)
    state_keys, opt_keys = None, None
    versions = {}   # engine team -> the script version its AI logged (none before 2026-10-08)
    lastw = lastd = 0
    gadget = []
    with _Chain(files or [os.path.join(path, "infolog.txt")]) as fh:
        for ln in fh:
            if "apex: version t=" in ln:
                mv = VERSION.search(ln)
                if mv:
                    versions[int(mv.group(1))] = mv.group(2)
                continue
            if "apex: nnreinf-done t=" in ln:
                mr = REINF_DONE.search(ln)
                if mr:
                    reinf_done[(int(mr.group(1)), int(mr.group(2)))] = int(mr.group(3))
                continue
            if "apex: nndef" in ln:
                md = DEFSITE_DONE.search(ln)
                if md:
                    (defsite_done if md.group(1) == "site" else deftype_done)[(int(md.group(2)), int(md.group(3)))] = dict(
                        done=float(md.group(4)), siteKill=float(md.group(5)), siteLost=float(md.group(6)),
                        sitePre=float(md.group(7)), siteBase=float(md.group(8)),
                        site=(float(md.group(9)), float(md.group(10))))
                    continue
                md = DEF_SCHEMA.search(ln)
                if md:
                    heads.setdefault(md.group(1), {"keys": None, "rows": []})["keys"] = md.group(2).split(",")
                    continue
                md = DEF_ROW.search(ln)
                if md:
                    heads.setdefault(md.group(2), {"keys": None, "rows": []})["rows"].append(
                        (md.group(1),) + md.groups()[2:])
                continue
            if "apex: nnhunt-done t=" in ln:
                mh = HUNT_DONE.search(ln)
                if mh:
                    hunt_done[(int(mh.group(1)), int(mh.group(2)))] = dict(
                        done=float(mh.group(3)), huntKill=float(mh.group(4)), huntLost=float(mh.group(5)),
                        huntWreck=float(mh.group(6)))
                continue
            if "apex: nn-explore t=" in ln:
                mx = re.search(r"nn-explore t=(\d+) on", ln)
                if mx:
                    explorers.add(int(mx.group(1)))
            if "apex: nnval" in ln:
                m = VAL_SCHEMA.search(ln)
                if m:
                    vals.setdefault(m.group(1), {"keys": None, "rows": []})["keys"] = m.group(2).split(",")
                    continue
                m = VAL_ROW.search(ln)
                if m:
                    vals.setdefault(m.group(2), {"keys": None, "rows": []})["rows"].append(
                        (m.group(1),) + m.groups()[2:])
                continue
            if "apex: nn" in ln and HEAD_TAG.search(ln):
                m = HEAD_SCHEMA.search(ln)
                if m:
                    heads.setdefault(m.group(1), {"keys": None, "rows": []})["keys"] = m.group(2).split(",")
                    continue
                m = HEAD_ROW.search(ln)
                if m:
                    heads.setdefault(m.group(2), {"keys": None, "rows": []})["rows"].append(
                        (m.group(1),) + m.groups()[2:])
                continue
            if "apex: nnpost" in ln:
                m = POST_SCHEMA.search(ln)
                if m:
                    post_keys = m.group(1).split(",")
                    continue
                m = NNPOST.search(ln)
                if m:
                    postrows.append(m.groups())
                continue
            if "apex: nnfac" in ln:
                m = FAC_SCHEMA.search(ln)
                if m:
                    fac_keys = m.group(2).split(",")
                    continue
                m = NNFAC.search(ln)
                if m:
                    facrows.append(m.groups())
                continue
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
            gadget.append(ln)
            m = RESULT.search(ln)
            if m:
                winners = {int(w) for w in m.group(3).split(",") if w}
                continue
            m = STATS.search(ln)
            if m:
                reclaim.setdefault(int(m.group(1)), Series()).add(int(m.group(2)), float(m.group(3)))
                continue
            m = WASTE.search(ln)
            if m:
                f, t = int(m.group(1)), int(m.group(2))
                for d, k in ((sm, 4), (wm, 3), (we, 5)):
                    d.setdefault(t, Series()).add(f, float(m.group(k)))
                # net of what the converters burned: their metal is already in mMade, so the
                # gross energy credited a converter twice in dEco and dEInc (10-09)
                se.setdefault(t, Series()).add(f, float(m.group(6)) - float(m.group(7) or 0))
                lastw = max(lastw, f)
                continue
            m = DMG.search(ln)
            if m:
                f, t = int(m.group(1)), int(m.group(2))
                dealt.setdefault(t, Series()).add(f, float(m.group(3)) + float(m.group(4)))
                recv.setdefault(t, Series()).add(f, float(m.group(5)) + float(m.group(6)))
                lastd = max(lastd, f)
                continue
            m = PROD.search(ln)
            if m:
                prods.setdefault(int(m.group(1)), []).append(
                    (int(m.group(2)), m.group(3), int(m.group(4)), int(m.group(5))))
            m = BUILT.search(ln)
            if m:
                bx = int(m.group(6)) if m.group(6) is not None else None
                bz = int(m.group(7)) if m.group(7) is not None else None
                allyof[int(m.group(1))] = int(m.group(2))
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
                        lostev.setdefault(t, []).append((f, cost, x, z, killer_class(m.group(9)), unit))
                    if MEX.search(unit):
                        mexev.setdefault(t, []).append((f, -1))
                if atk >= 0 and atk != t:
                    killev.setdefault(atk, []).append((f, cost))
                mu = UIDS.search(ln)
                if mu:
                    died[int(mu.group(1))] = f
                    if atk >= 0 and atk != t and int(mu.group(2)) >= 0:
                        killby.setdefault(int(mu.group(2)), []).append((f, cost))
    deciders = {int(r[1]) for r in rows} | {int(r[1]) for r in facrows} | {int(r[1]) for r in postrows}
    for h in list(heads.values()) + list(vals.values()):
        deciders |= {int(r[1]) for r in h["rows"]}
    return dict(bonus=script_bonus(path), edges=side_edges(gadget, allyof, deciders, lastw),
                rows=rows, execs=execs, nns=nns, state_keys=widen_keys(state_keys), opt_keys=opt_keys, last=min(lastw, lastd) if lastd else lastw,
                sm=sm, se=se, wm=wm, we=we, dealt=dealt, recv=recv,
                mexev=mexev, killev=killev, lostev=lostev, builds=builds, dead=dead,
                reclaim=reclaim, explore=explore, explorers=explorers, reinf_done=reinf_done, hunt_done=hunt_done, died=died, killby=killby,
                facrows=facrows, fac_keys=fac_keys, prods=prods, allyof=allyof, winners=winners,
                postrows=postrows, post_keys=post_keys, heads=heads, vals=vals, defsite_done=defsite_done, deftype_done=deftype_done,
                versions=versions, regime=script_regime(path),
                solo=bool(allyof) and len(set(allyof.values())) == len(allyof),   # one team per side: a 1v1
                final=files is None)   # a finished game's merged infolog, not live files


def window_sum(ev, f0, f1):
    return sum(c for f, c in ev if f0 < f <= f1)


def ev_window(g, key, t, f0, f1):
    """(events with f0 < frame <= f1, the sum of their second field) from g[key][t].
    Asked per decision per horizon, so the team's events are sorted once per game
    and a window is two bisects and a difference of running totals."""
    cache = g.setdefault("_evw", {})
    if (key, t) not in cache:
        ev = sorted(g[key].get(t, []), key=lambda e: e[0])
        run = [0]
        for e in ev:
            run.append(run[-1] + e[1])
        cache[(key, t)] = ([e[0] for e in ev], ev, run)
    fr, ev, run = cache[(key, t)]
    i, j = bisect.bisect_right(fr, f0), bisect.bisect_right(fr, f1)
    return ev[i:j], run[j] - run[i]


def com_deaths(g, t):
    """Frames our commanders died on, sorted, once per game."""
    cache = g.setdefault("_comd", {})
    if t not in cache:
        cache[t] = sorted(df for df, unit, _x, _z in g["dead"].get(t, []) if unit.startswith(COMS))
    return cache[t]


EDGES = ("army", "eco", "land", "mex")   # progress.py's edges the labels follow
EDGE_CLIP = math.log(10.0)   # progress.ratio reads 9.99 when they have none


def side_edges(gadget, allyof, deciders, last):
    """Per deciding ally team: progress.py's per-minute edges of that side over
    every other, from the game's own gadget lines (ground truth, labels only)."""
    allies = {allyof[t] for t in deciders if t in allyof}
    if not allies or len(set(allyof.values())) < 2:
        return {}
    import progress
    txt = "".join(gadget)
    out = {}
    for a in allies:
        s = progress.series_of(txt, allyof, lambda t, a=a: 0 if allyof.get(t) == a else 1, last // FPM + 1)
        out[a] = {k: s[k] for k in EDGES}
    return out


def edge_delta(series, f0, f1):
    """ln(edge) at the last whole minute before f1 minus before f0, or None."""
    i0, i1 = f0 // FPM - 1, f1 // FPM - 1
    if i0 < 0 or i1 <= i0 or i1 >= len(series) or series[i0] is None or series[i1] is None:
        return None
    a, b = (max(-EDGE_CLIP, min(EDGE_CLIP, math.log(max(series[i], 1e-9)))) for i in (i0, i1))
    return b - a


def rate(s, f):
    a, b = s.at(f - FPM), s.at(f)
    if a is None or b is None or f < FPM:
        return None
    # energy net of the converters goes negative while they drain the bank faster than income
    return max(0.0, (b - a) / 60.0)


def near(x0, z0, x, z):
    return (x - x0) ** 2 + (z - z0) ** 2 <= NEAR * NEAR


def ended(g):
    """The game reached a result. A time-capped game logs `winners=` empty: it
    was stopped, not ended, so a window past its last minute is unknown."""
    return bool(g.get("winners"))


def labels(g, t, f, site=None):
    y = {}
    sm, se = g["sm"].get(t), g["se"].get(t)
    over = ended(g)
    for h in HORIZONS:
        f1 = f + h * FPM
        out = {}
        # A finished game's horizon runs to its end: blanking it left the long
        # labels to losses and draws (wins end early).
        if over and f1 > g["last"] and g["last"] - f >= FPM:
            f1 = g["last"]
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
        out["dMex"] = ev_window(g, "mexev", t, f, f1)[1]
        d, r = g["dealt"].get(t), g["recv"].get(t)
        if d is not None and r is not None and d.at(f1) is not None and r.at(f1) is not None:
            out["lnD"] = math.log((d.at(f1) - d.at(f) + 1) / (r.at(f1) - r.at(f) + 1))
        else:
            out["lnD"] = None
        out["kill"] = ev_window(g, "killev", t, f, f1)[1]
        lev, out["lost"] = ev_window(g, "lostev", t, f, f1)
        out["lostNear"] = (sum(e[1] for e in lev if near(site[0], site[1], e[2], e[3]))
                           if site else None)
        out["lostFar"] = None if site is None else out["lost"] - out["lostNear"]
        for cls in ("air", "static", "mobile"):
            out["lost" + cls.capitalize()] = sum(e[1] for e in lev if e[4] == cls)
        out["lostEco"] = sum(e[1] for e in lev if eco_kind(e[5]))
        out["dEco"] = (math.log((m1 + e1 / 60.0) / (m0 + e0 / 60.0))
                       if None not in (m0, m1, e0, e1) and m0 + e0 > 0 and m1 + e1 > 0 else None)
        rc = g["reclaim"].get(t)
        rc0, rc1 = (rc.at(f), rc.at(f1)) if rc is not None else (None, None)
        out["reclaim"] = (rc1 - rc0) / h if None not in (rc0, rc1) else None
        ed = g.get("edges", {}).get(g["allyof"].get(t))
        for k in EDGES:
            out["edge" + k.capitalize()] = edge_delta(ed[k], f, f1) if ed else None
        y[h] = out
    # the pressure the state should already have seen: enemy kills of ours in
    # the 5 minutes BEFORE the decision
    y["lostPre"] = ev_window(g, "lostev", t, f - 5 * FPM, f)[1]
    # the game's result for the deciding team: the longest horizon there is
    w = g.get("winners")
    y["won"] = (1 if g["allyof"].get(t) in w else 0) if w and t in g.get("allyof", {}) else None
    # our commander killed within COM_H minutes: in a 1v1 that is the game
    f1 = f + COM_H * FPM
    cd = com_deaths(g, t)
    lost = bisect.bisect_right(cd, f1) > bisect.bisect_right(cd, f)
    y["comLost"] = 1 if lost else (None if f1 > g["last"] else 0)
    # His ruling 2026-10-06: the game's end and the commander's death count,
    # discounted by how far ahead of this decision they came (e-folding
    # END_TAU / COM_H minutes), so a game-wide outcome stops being one label
    # for every row of the game.
    capped = None if over else capped_result(g, t)
    if capped is not None:
        # a time-capped game: its result is where it stood (capped_result)
        y["won"] = 0.5 + 0.5 * capped
        y["endV"] = capped * math.exp(-max(0, g["last"] - f) / (END_TAU * FPM))
        y["endFast"] = capped * math.exp(-g["last"] / (GAME_TAU * FPM))
    if over:
        mine = g["allyof"].get(t)
        # a game stopped by our time cap has no result: 0 read every such row as "even"
        sign = None if not w or mine is None else (1.0 if mine in w else -1.0)
        y["endV"] = None if sign is None else sign * math.exp(-max(0, g["last"] - f) / (END_TAU * FPM))
        # endV is discounted from the decision, so it cannot tell a win at 25
        # minutes from one at 55 for a decision 15 minutes before either; this is
        # the result discounted from the game's start: a win is worth less the
        # longer it took, a loss costs less the longer it was held off.
        y["endFast"] = None if sign is None else sign * math.exp(-g["last"] / (GAME_TAU * FPM))
        # ...only a death the game went on after: in 1v1 the commander's death IS
        # the loss, already in endV -- counted again it made a loss -3 to a win's
        # +1 (his 2026-10-06).
        dfs = [df for df in cd[bisect.bisect_right(cd, f):] if g["last"] - df > COM_END_F]
        y["comLostD"] = math.exp(-(min(dfs) - f) / (COM_H * FPM)) if dfs else 0.0
    else:
        if capped is None:
            y["endV"] = None
            y["endFast"] = None
        # a time-capped game: labelled only where the discount has run its course
        # inside the played minutes -- chosen by time, never by whether he died
        # (a running game stays unlabelled, as before)
        dfs = cd[bisect.bisect_right(cd, f):]
        if not g.get("final") or g["last"] - f < 3 * COM_H * FPM:
            y["comLostD"] = None
        else:
            y["comLostD"] = math.exp(-(dfs[0] - f) / (COM_H * FPM)) if dfs else 0.0
    if g.get("solo"):
        # 1v1: his death IS the loss (endV has it), so this was 0 on every row
        y["comLostD"] = None
    return y


CAP_RESULT = 0.5   # a time-capped game is worth at most half a decided one


def capped_result(g, t):
    """A time-capped finished game's result for t's side in (-CAP_RESULT,
    CAP_RESULT): tanh of the mean log edge at the end in metal produced, army
    and extractors, so a loss held to a draw counts. None for any other game."""
    if not g.get("final") or g.get("winners") is None or g.get("winners"):
        return None
    a = g["allyof"].get(t)
    cache = g.setdefault("_capped", {})
    if a in cache:
        return cache[a]
    terms = []
    made = [0.0, 0.0]
    for tm, s in g["sm"].items():
        if tm in g["allyof"]:
            made[0 if g["allyof"][tm] == a else 1] += s.v[-1]
    if made[0] > 0 and made[1] > 0:
        terms.append(max(-EDGE_CLIP, min(EDGE_CLIP, math.log(made[0] / made[1]))))
    ed = g.get("edges", {}).get(a) or {}
    for k in ("army", "mex"):
        vals = [v for v in ed.get(k, []) if v is not None]
        if vals:
            terms.append(max(-EDGE_CLIP, min(EDGE_CLIP, math.log(max(vals[-1], 1e-9)))))
    cache[a] = CAP_RESULT * math.tanh(sum(terms) / len(terms)) if a is not None and terms else None
    return cache[a]


END_TAU = 10   # minutes: the longest horizon
GAME_TAU = 30   # minutes: about a decided 2v2's length vs BARb, where the label spreads most
COM_END_F = 300   # frames: a commander death this close to the end ended the game


COM_H = 3
COMS = ("armcom", "corcom", "legcom")


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
                   pick=int(pick), why=why, dm=dm, state=fill_bonus(g, t, dict(zip(sk, sv))), opts=ov,
                   chosen=ci, y=y, explore=t in g.get("explorers", ()))


def fac_rows_of(path, g):
    """Factory orders (`apex: nnfac`), labelled like builder decisions: team
    outcomes at +1/+3/+5 min, and the produced unit -- the first unclaimed
    [BARAI_PROD] of that def from THAT factory -- with its own lifetime."""
    if g["state_keys"] is None or not g.get("fac_keys"):
        return
    sk, ok = g["state_keys"], g["fac_keys"]
    claimed = set()
    for frame, t, u, con, state, opts, chosen in sorted(g["facrows"], key=lambda r: int(r[0])):
        f, t, fid = int(frame), int(t), int(u)
        ov = []
        for o in (opts or "").split(" ; "):
            if o:
                ov.append(dict(zip(ok, (num(x) for x in o.split(",")))))
        ci = int(chosen)
        o = ov[ci] if 0 <= ci < len(ov) else {}
        y = labels(g, t, f, None)
        y["done"] = y["buildS"] = None
        built = None
        f1 = f + DONE_H * FPM
        if o:
            for i, (pf, name, uid, facid) in enumerate(g["prods"].get(t, [])):
                if pf > f1:
                    break
                if pf > f and name == o.get("def") and facid == fid and (t, i) not in claimed:
                    claimed.add((t, i))
                    y["done"], y["buildS"], built = 1, round((pf - f) / 30.0, 1), (pf, uid)
                    break
            else:
                y["done"] = None if f1 > g["last"] else 0
        y["lifeS"], y["lifeKill"] = lifetime(g, built)
        y["survived"] = None
        yield dict(match=os.path.basename(path.rstrip("/\\")), team=t, f=f, unit=fid, con=con,
                   pick=0, why="fac", dm="draw", state=fill_bonus(g, t, dict(zip(sk, (num(x) for x in state.split(","))))),
                   opts=ov, chosen=ci, y=y)


POST_OPTS = ("DEFEND", "HOLD", "ATTACK", "RAID")   # military/state.as POST_* order


def post_rows_of(path, g):
    """Army posture decisions (`apex: nnpost`), labelled with the deciding
    team's outcomes -- trade, losses, economy at +1..+10 min, and the result."""
    if g["state_keys"] is None or not g.get("post_keys"):
        return
    sk, pk = g["state_keys"], g["post_keys"]
    for frame, t, why, rule, ex, state, post, opts, chosen in sorted(g["postrows"], key=lambda r: int(r[0])):
        f, t = int(frame), int(t)
        ov = []
        for o in opts.split(" ; "):
            parts = o.split(",")
            if len(parts) == 3:
                ov.append({"name": parts[0], "w": num(parts[1]), "p": num(parts[2])})
        y = labels(g, t, f, None)
        yield dict(match=os.path.basename(path.rstrip("/\\")), team=t, f=f, unit=-1, con="army",
                   why=why, rule=rule, explore=ex == "1", pick=0, dm="draw",
                   state=fill_bonus(g, t, dict(zip(sk, (num(x) for x in state.split(","))))),
                   post=dict(zip(pk, (num(x) for x in post.split(",")))),
                   opts=ov, chosen=int(chosen), y=y)


def head_rows_of(path, g, tag):
    """The `apex: nn<tag>` decisions (com, tech) in post_rows_of's shape: the
    head's own fields under "post", labelled with the team's outcomes."""
    h = g.get("heads", {}).get(tag)
    if g["state_keys"] is None or not h or not h["keys"]:
        return
    sk, pk = g["state_keys"], h["keys"]
    for frame, t, why, rule, ex, state, own, opts, chosen in sorted(h["rows"], key=lambda r: int(r[0])):
        f, t = int(frame), int(t)
        ov = []
        for o in opts.split(" ; "):
            parts = o.split(",")
            if len(parts) == 3:
                ov.append({"name": parts[0], "w": num(parts[1]), "p": num(parts[2])})
        post = dict(zip(pk, (num(x) for x in own.split(","))))
        yield dict(match=os.path.basename(path.rstrip("/\\")), team=t, f=f, unit=-1, con=tag,
                   why=why, rule=rule, explore=ex == "1", pick=0, dm="draw",
                   state=fill_bonus(g, t, dict(zip(sk, (num(x) for x in state.split(","))))),
                   post=post, opts=ov, chosen=int(chosen), y=head_labels(g, t, f, tag, post))


def val_rows_of(path, g, tag):
    """A continuous head's `apex: nnval` decisions in head_rows_of's shape: `chosen`
    is the value played and `rule` the rule's, with the range, `rnd` (a uniform
    draw, at density `dens`), `game` (held all game) and the trust it played at."""
    h = g.get("vals", {}).get(tag)
    if g["state_keys"] is None or not h or not h["keys"]:
        return
    sk, pk = g["state_keys"], h["keys"]
    for frame, t, v, rule, lo, hi, rnd, dens, ex, game, trust, state, own in sorted(h["rows"], key=lambda r: int(r[0])):
        f, t = int(frame), int(t)
        post = dict(zip(pk, (num(x) for x in own.split(","))))
        yield dict(match=os.path.basename(path.rstrip("/\\")), team=t, f=f, unit=-1, con=tag,
                   why="clock", rule=num(rule), explore=ex == "1", game=game == "1", rnd=rnd == "1",
                   dens=num(dens), lo=num(lo), hi=num(hi), trust=num(trust), pick=0, dm="draw",
                   state=fill_bonus(g, t, dict(zip(sk, (num(x) for x in state.split(","))))),
                   post=post, opts=[], chosen=num(v), y=head_labels(g, t, f, tag, post))


def open_labels(g, t, f, y, own):
    """The opening is decided before minute 1, where labels() has no income to
    start from: the commander's own income (his make x the bonus, in the row)
    is the base for dMInc/dEInc/dEco, and 'done' is ln(metal made over the
    next 5 minutes / what he alone makes in them)."""
    sm, se = g["sm"].get(t), g["se"].get(t)
    m0, e0 = own.get("comM") or 0.0, own.get("comE") or 0.0
    for h in HORIZONS:
        out = y.get(h)
        if out is None or sm is None or se is None:
            continue
        f1 = min(f + h * FPM, g["last"])
        m1, e1 = rate(sm, f1), rate(se, f1)
        out["dMInc"] = math.log(m1 / m0) if m0 > 0 and m1 else None
        out["dEInc"] = math.log(e1 / e0) if e0 > 0 and e1 else None
        out["dEco"] = (math.log((m1 + e1 / 60.0) / (m0 + e0 / 60.0))
                       if None not in (m1, e1) and m0 + e0 > 0 and m1 + e1 > 0 else None)
    f5 = f + 5 * FPM
    made = (sm.at(f5) - sm.at(f)) if sm is not None and f5 <= g["last"] else None
    y["done"] = math.log(made / (m0 * 5 * 60.0)) if made and m0 > 0 else None
    return y


def head_labels(g, t, f, tag, own=None):
    """The team's outcomes; the join-the-fight head's 'done' is whether the squad
    arrived while the fight still raged (apex: nnreinf-done); the hunt head's is
    (kill + wreck - lost) / (kill + lost + army) near the army it weighed."""
    if tag in ("defsite", "deftype"):
        # the site and gun-class heads' own 'done' is the trade at the chosen site over 5 min
        # (kill - lost) / (kill + lost + gun metal); lostNear is measured there
        ds = dict(g.get(tag + "_done", {}).get((t, f), {}))
        y = labels(g, t, f, ds.pop("site", None))
        y["done"] = None
        y.update(ds)
        return y
    y = labels(g, t, f, None)
    if tag == "reinf":
        y["done"] = g.get("reinf_done", {}).get((t, f))
    elif tag == "hunt":
        y["done"] = None
        y.update(g.get("hunt_done", {}).get((t, f), {}))
    elif tag == "open":
        open_labels(g, t, f, y, own or {})
    return y


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
    f1 = f + DONE_H * FPM
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
