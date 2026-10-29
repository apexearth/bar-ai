"""Local web dashboard for the bar-ai harness.

    python tools/dashboard.py            # serves http://127.0.0.1:8420 and opens a browser
    python tools/dashboard.py --port N --no-browser
    python tools/dashboard.py --remote   # view it from his other computers over Tailscale

Stdlib only. Binds 127.0.0.1 only; --remote also answers Tailscale devices,
view-only (no launch, deploy or tool runs). The page is tools/dashboard_ui.html; this file
is the API: browse matches/tournaments, run the analysis tools, launch watch or
headless games as tracked jobs with mod-option overrides, and deploy.
"""
import argparse
import ipaddress
import json
import math
import os
import re
import subprocess
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs


REPO = Path(__file__).resolve().parent.parent
TOOLS = REPO / "tools"
MATCHES = REPO / "matches"
TOURNAMENTS = REPO / "tournaments"
VARIANT = "Unstable"          # ai/<VARIANT>/ -- also the AI version
PROFILE = "standard"          # config/<PROFILE>/, script/<PROFILE>/
SCRIPT_DIR = REPO / "ai" / VARIANT / "game-side" / "script" / PROFILE
UI_FILE = TOOLS / "dashboard_ui.html"
LOG_DIR = MATCHES / "_dashboard_logs"
PY = sys.executable

# Analysis tools the UI may run against a run dir. Each entry: script name and
# whether it accepts --control.
ANALYSIS_TOOLS = {
    "review": ("review.py", True),
    "audit": ("audit.py", False),
    "diagnose": ("diagnose.py", False),
    "composition": ("composition.py", False),
    "allies": ("allies.py", False),
    "tl": ("tl.py", False),
    "fight1v1": ("fight1v1.py", False),
    "trace_flow": ("trace_flow.py", False),
    "deaths": ("deaths.py", False),
    "record": ("record.py", False),
    "scaling": ("scaling.py", False),
    "wdeaths": ("wdeaths.py", False),
    "arena": ("arena.py", False),
    "wall": ("wall_check.py", False),
    "wallmap": ("wall_map.py", False),
    "keepout": ("keepout.py", False),
    "earlyfight": ("test_earlyfight.py", False),
    "raid": ("test_raid.py", False),
    "siege": ("siege.py", False),
    "flank": ("flankstat.py", False),
    "deflag": ("deflag.py", False),
}

DEPLOY_ACTIONS = {
    "status": ["deploy_ai.py", "status"],
    "check": ["check.py"],
    "deploy": ["deploy_ai.py", "deploy", VARIANT],
    "pull": ["deploy_ai.py", "pull", VARIANT],
    "gadgets": ["deploy_ai.py", "gadgets"],
}

CONST_RE = re.compile(
    r"^(const\s+(?:float|int|uint|double|bool)\s+(\w+)\s*=\s*)([^;]+)(;.*)$")

JOBS = {}
JOBS_LOCK = threading.Lock()
JOB_SEQ = [0]

_summary_cache = {}


# ---------------------------------------------------------------- helpers

def _his_env():
    # The dashboard is his UI for the shared slot: whatever shell started it,
    # its tools must not be refused for holding no lane claim (tools/lane.py).
    env = dict(os.environ)
    env.setdefault("BARAI_LANE", "shared")
    return env


def run_tool(args, timeout=600):
    """Run a repo python tool synchronously; return dict with output."""
    cmd = [PY, "-u"] + args
    try:
        p = subprocess.run(cmd, cwd=str(REPO), capture_output=True, text=True,
                           errors="replace", timeout=timeout, env=_his_env())
        out = p.stdout + (("\n[stderr]\n" + p.stderr) if p.stderr.strip() else "")
        return {"ok": p.returncode == 0, "code": p.returncode,
                "cmd": " ".join(args), "output": out}
    except subprocess.TimeoutExpired:
        return {"ok": False, "code": -1, "cmd": " ".join(args),
                "output": "timed out after %ss" % timeout}


def running_processes():
    """Which BAR-related processes are alive (deploy safety)."""
    names = ["spring.exe", "spring-headless.exe", "Beyond-All-Reason.exe"]
    found = []
    try:
        out = subprocess.run(["tasklist", "/FO", "CSV", "/NH"],
                             capture_output=True, text=True, errors="replace",
                             timeout=30).stdout.lower()
        for n in names:
            if n.lower() in out:
                found.append(n)
    except Exception:
        pass
    return found


def safe_run_dir(rel):
    """Resolve a run dir string; must live under matches/ or tournaments/."""
    p = (REPO / rel).resolve()
    for base in (MATCHES, TOURNAMENTS):
        b = str(base.resolve()) + os.sep
        if p.is_dir() and (str(p) + os.sep).startswith(b):
            return p
    raise ValueError("not a run dir: %s" % rel)


def load_result(d):
    try:
        with open(d / "result.json", encoding="utf-8", errors="replace") as f:
            return json.load(f)
    except Exception:
        return None


STATS_LINE_RE = re.compile(r"\[BARAI_STATS\]\s+(.*)")
_stats_cache = {}


def stats_rows(d):
    """Every [BARAI_STATS] row of a run, periodic and shutdown.

    Since the gadget log sink (2026-09-12) the periodic rows reach only the
    merged stdout.txt/infolog.txt, and result.json holds the shutdown rows alone.
    """
    r = load_result(d) or {}
    rows = [e for e in (r.get("stats") or []) if isinstance(e, dict)]
    if any(e.get("reason") == "periodic" for e in rows):
        return rows
    for name in ("stdout.txt", "infolog.txt"):
        f = d / name
        if not f.is_file():
            continue
        key = (str(f), f.stat().st_mtime)
        if key not in _stats_cache:
            out = []
            with f.open(encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if "[BARAI_STATS]" not in line:
                        continue
                    m = STATS_LINE_RE.search(line)
                    row = {}
                    for tok in m.group(1).split():
                        k, _, v = tok.partition("=")
                        if not k:
                            continue
                        try:
                            row[k] = float(v)
                        except ValueError:
                            row[k] = v
                    if "team" in row:
                        out.append(row)
            _stats_cache[key] = out
        if any(e.get("reason") == "periodic" for e in _stats_cache[key]):
            return _stats_cache[key]
    return rows


def match_summary(d):
    """Light summary of one match dir, cached on result.json mtime."""
    rj = d / "result.json"
    if not rj.is_file():
        return {"dir": str(d.relative_to(REPO)).replace(os.sep, "/"),
                "name": d.name, "running": True}
    mt = rj.stat().st_mtime
    key = str(d)
    hit = _summary_cache.get(key)
    if hit and hit[0] == mt:
        return hit[1]
    r = load_result(d) or {}
    res = r.get("result", {}) or {}
    s = {
        "dir": str(d.relative_to(REPO)).replace(os.sep, "/"),
        "name": d.name,
        "map": r.get("map"),
        "specs": [t.get("spec") for t in r.get("teams", [])],
        "winner_specs": res.get("winner_specs", []),
        "reason": res.get("reason"),
        "minutes": res.get("game_minutes"),
        "handicap": r.get("handicap"),
        "crashed": res.get("crashed", False),
        "valid": res.get("valid"),
        "mtime": mt,
        "replay": bool(r.get("replay")),
        "seed": r.get("seed"),
    }
    _summary_cache[key] = (mt, s)
    return s


def newest_dirs(root, limit, skip_underscore=False):
    """The `limit` most recently modified subdirs; scandir carries the mtime on Windows."""
    try:
        ents = [e for e in os.scandir(root) if e.is_dir()
                and not (skip_underscore and e.name.startswith("_"))]
    except OSError:
        return []
    ents.sort(key=lambda e: e.stat().st_mtime, reverse=True)
    return [Path(e.path) for e in ents[:limit]]


def list_matches(limit=250):
    return [match_summary(d) for d in newest_dirs(MATCHES, limit, True)]


_winners_cache = {}


def match_winners(m):
    """winner_specs of a finished match, None while it runs; cached on result.json mtime."""
    try:
        mt = os.stat(os.path.join(m, "result.json")).st_mtime
    except OSError:
        return None
    hit = _winners_cache.get(m)
    if hit and hit[0] == mt:
        return hit[1]
    r = load_result(Path(m))
    w = (r.get("result", {}) or {}).get("winner_specs", []) if r else None
    _winners_cache[m] = (mt, w)
    return w


def tournament_summary(d):
    cfg = {}
    try:
        with open(d / "config.json", encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception:
        pass
    wins, games, done = {}, 0, 0
    try:
        ms = [e.path for e in os.scandir(d / "matches") if e.is_dir()]
    except OSError:
        ms = []
    for m in ms:
        games += 1
        w = match_winners(m)
        if w is None:
            continue
        done += 1
        for x in w:
            wins[x] = wins.get(x, 0) + 1
        if not cfg.get("ais"):
            # the training searches (neuro, rand) write no config.json; their games say who and where
            s = match_summary(Path(m))
            cfg = {"ais": [x for x in s.get("specs", []) if x][:2], "maps": [s["map"]] if s.get("map") else []}
    return {
        "dir": str(d.relative_to(REPO)).replace(os.sep, "/"),
        "name": d.name,
        "ais": cfg.get("ais", []),
        "maps": cfg.get("maps", []),
        "per_side": cfg.get("per_side"),
        "planned": len(cfg.get("jobs", [])) or None,
        "games": games,
        "done": done,
        "wins": wins,
        "mtime": d.stat().st_mtime,
    }


def list_tournaments(limit=120):
    return [tournament_summary(d) for d in newest_dirs(TOURNAMENTS, limit)]


def infolog_health(d):
    """The silent-failure gates: compile errors, duplicate bindings, apex alive."""
    f = d / "infolog.txt"
    if not f.is_file():
        return None
    try:
        txt = f.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return None
    errs = re.findall(r"\(?\d+, \d+\) : ERR.*|Fix compilation errors.*", txt)
    dup = txt.count("asALREADY_REGISTERED")
    apex_lines = len(re.findall(r"\bapex:", txt))
    return {"compile_errors": errs[:12], "compile_error_count": len(errs),
            "already_registered": dup, "apex_log_lines": apex_lines}


# One builder election (decide.as). A factory's `-> produce:` decide is a floor
# override, not an election, and does not match.
DECIDE_RE = re.compile(
    r"\[f=(\d+)\].*apex: decide t=(\d+) \S+ #\d+ -> (\w+)/(\w+):(\S+) v=([-\d.]+)")

_unit_names = {}


def unit_display_names():
    """internal def name -> in-game name, from the game we actually test against."""
    if not _unit_names:
        try:
            import bar_env
            f = bar_env.load().game_sdd / "language" / "en" / "units.json"
            u = json.loads(f.read_text(encoding="utf-8")).get("units", {})
            _unit_names.update(u.get("names", {}))
        except Exception:
            _unit_names["_"] = ""
    return _unit_names


def brain_wants(d):
    """Builder elections per team, bucketed by game minute, from `apex: decide`.

    The per-tick want dump this chart once read was removed on 2026-08-22; what
    is logged now is every election's winner, so the chart shows what was
    picked, not what was wanted. Needs apex_decide_log (on by default).
    """
    f = d / "infolog.txt"
    if not f.is_file():
        return {"error": "no infolog"}
    teams = {}
    kinds = {}
    labels = {}
    with f.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "apex: decide t=" not in line:
                continue
            m = DECIDE_RE.search(line)
            if not m:
                continue
            mins = int(m.group(1)) / 1800.0
            cat, kind, defname = m.group(3), m.group(4), m.group(5)
            key = cat + "/" + kind + ":" + defname
            if key not in labels:
                labels[key] = {"kind": cat + "/" + kind,
                               "def": "" if defname == "-" else defname,
                               "name": unit_display_names().get(defname, "")}
            kinds[key] = kinds.get(key, 0) + 1
            t = teams.setdefault(m.group(2), {"buckets": {}, "picks": []})
            b = t["buckets"].setdefault(int(mins), {})
            n, vs = b.get(key, (0, 0.0))
            b[key] = (n + 1, vs + float(m.group(6)))
            t["picks"].append({"min": round(mins, 2), "kind": key})
    order = sorted(kinds, key=lambda k: -kinds[k])
    out = {}
    for tid, t in sorted(teams.items(), key=lambda kv: int(kv[0])):
        last = max(t["buckets"])
        idx = list(range(last + 1))
        series = {k: [] for k in order}
        chance = {k: [] for k in order}
        for i in idx:
            b = t["buckets"].get(i, {})
            tot = sum(n for n, _ in b.values())
            for k in order:
                n, vs = b.get(k, (0, 0.0))
                series[k].append(vs / n if n else 0.0)
                chance[k].append(100.0 * n / tot if tot else 0.0)
        counts = {}
        for p in t["picks"]:
            counts[p["kind"]] = counts.get(p["kind"], 0) + 1
        out[tid] = {"min": [i + 0.5 for i in idx], "series": series,
                    "chance": chance, "picks": t["picks"], "pickCounts": counts}
    return {"kinds": order, "labels": labels, "teams": out}


CREW_ROLES = ["conT1", "conT2", "other"]


def crew_roles(d):
    """Builder headcount per team over time, from the dev_stats periodic rows.

    The AI's own role census (`crew home=`) was removed on 2026-08-22. conT1 and
    conT2 are mobile constructors without the commander; `other` is every other
    unit with a build menu: nano turrets, factories, the commander.
    """
    teams = {}
    for e in stats_rows(d):
        if e.get("reason") != "periodic":
            continue
        t = teams.setdefault(str(int(e.get("team", -1))),
                             {"min": [], "tracked": [], **{r: [] for r in CREW_ROLES}})
        t1, t2 = int(e.get("conT1", 0) or 0), int(e.get("conT2", 0) or 0)
        allb = int(e.get("ownBuilders", 0) or 0)
        t["min"].append(round((e.get("frame", 0) or 0) / 1800.0, 1))
        t["conT1"].append(t1)
        t["conT2"].append(t2)
        t["other"].append(max(allb - t1 - t2, 0))
        t["tracked"].append(allb)
    return {"roles": CREW_ROLES, "teams": teams}


DUTY_RE = re.compile(
    r"\[BARAI_DUTY\] team=(\d+) frame=(\d+) .*?conSamp=(\d+) .*?"
    r"conOnFac=(\d+) facNano=(\S+)")


def factory_support(d):
    """Nano turrets whose lathe reaches each standing factory, per team,
    from the dev_stats gadget's 2-minute DUTY line (every team, BARb's too).

    `conOnFac` over `conSamp` is the share of mobile-constructor time spent
    lathing a factory's build; stock BARb runs 13-22%, ours under 1%.
    """
    f = d / "infolog.txt"
    if not f.is_file():
        return {"error": "no infolog"}
    teams = {}
    with f.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "[BARAI_DUTY]" not in line or "facNano=" not in line:
                continue
            m = DUTY_RE.search(line)
            if not m:
                continue
            facs = []
            if m.group(5) != "-":
                for item in m.group(5).split("|"):
                    parts = item.split(":")
                    if len(parts) == 3:
                        facs.append({"def": parts[0], "nanos": int(parts[1]),
                                     "busy": parts[2] == "1"})
            con = int(m.group(3))
            teams[m.group(1)] = {"min": int(m.group(2)) / 1800.0, "facs": facs,
                                 "conOnFacPct": (100.0 * int(m.group(4)) / con) if con else 0.0}
    return {"teams": teams}


FRONTTOWER_RE = re.compile(
    r"\[(\d+(?:\.\d+)?)m t(\d+)\] apex: fronttowers built=(\d+) lost=(\d+) "
    r"standing=(-?\d+) m=(\d+) backBuilt=(\d+) backLost=(\d+) "
    r"backStanding=(-?\d+) backM=(\d+) wonFront=(\d+) wonAsset=(\d+) "
    r"rim=(\d+) core=(\d+) rimDAvg=(-?\d+)")
FRONTTOWER_KEYS = ["built", "lost", "standing", "metal",
                   "backBuilt", "backLost", "backStanding", "backMetal",
                   "wonFront", "wonAsset", "rim", "core", "rimDAvg"]


def front_towers(d):
    """Defence towers COMPLETED on the front line, against wants WON there.

    `wonFront` counts auction wins, and a re-election counts again; `built`
    counts AiUnitFinished events placed by Military::OnBorder. built far
    under wonFront is constructor time paid for towers that never arrived.
    """
    f = d / "infolog.txt"
    if not f.is_file():
        return {"error": "no infolog"}
    teams = {}
    with f.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "apex: fronttowers " not in line:
                continue
            m = FRONTTOWER_RE.search(line)
            if not m:
                continue
            t = teams.setdefault(m.group(2),
                                 {"min": [], **{k: [] for k in FRONTTOWER_KEYS}})
            t["min"].append(float(m.group(1)))
            for i, k in enumerate(FRONTTOWER_KEYS):
                t[k].append(int(m.group(3 + i)))
    return {"keys": FRONTTOWER_KEYS, "teams": teams}


LIFT_RE = re.compile(
    r"\[f=(\d+)\].*apex: lift census t=(\d+) turrets=(\d+) idle60=(\d+) "
    r"fleet=(\d+) moved=(\d+) aborted=(\d+) lost=(\d+)")
LIFT_KEYS = ["turrets", "idle60", "fleet", "moved", "aborted", "lost"]


def lift(d):
    """Construction turrets flown by air transport to the line short of lathe (lift.as)."""
    f = d / "infolog.txt"
    if not f.is_file():
        return {"error": "no infolog"}
    teams = {}
    with f.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "apex: lift census " not in line:
                continue
            m = LIFT_RE.search(line)
            if not m:
                continue
            teams[m.group(2)] = {"min": round(int(m.group(1)) / 1800.0, 1),
                                 **{k: int(m.group(3 + i)) for i, k in enumerate(LIFT_KEYS)}}
    return {"keys": LIFT_KEYS, "teams": teams}


ECODEF_RE = re.compile(
    r"\[f=(\d+)\].*apex: ecodef-stat t=(\d+) on=(\d+) radar=(\d+) gOld=([\d.]+) gNew=([\d.]+) "
    r"djOffer=(\d+) djWin=(\d+) djNoGain=(\d+) djV=([\d.]+) fieldDraw=(\d+) fieldWin=(\d+) "
    r"covOffer=(\d+) covWin=(\d+) bfOffer=(\d+) bfWin=(\d+) covNoPrice=(\d+) danger=([\d.]+) "
    r"threat=(-?\d+) meet=(-?\d+)")
ECODEF_KEYS = ["on", "radar", "gOld", "gNew", "djOffer", "djWin", "djNoGain", "djV",
               "fieldDraw", "fieldWin", "covOffer", "covWin", "bfOffer", "bfWin", "covNoPrice",
               "danger", "threat", "meet", "sdjFired", "sdjPriced", "sdjAgree"]
SHADOW_DJ_RE = re.compile(r"apex: shadow-defjoin t=(\d+) .* all=(\d+)/(\d+)/(\d+)")


def ecodef(d):
    """The five defence-pricing switches (ecodef.as): what each offered the draw and won."""
    f = d / "infolog.txt"
    if not f.is_file():
        return {"error": "no infolog"}
    teams = {}
    shadow = {}
    with f.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "apex: shadow-defjoin " in line:
                s = SHADOW_DJ_RE.search(line)
                if s:
                    shadow[s.group(1)] = s.groups()[1:]
                continue
            if "apex: ecodef-stat " not in line:
                continue
            m = ECODEF_RE.search(line)
            if not m:
                continue
            g = m.groups()
            row = {"min": round(int(g[0]) / 1800.0, 1)}
            for i, k in enumerate(ECODEF_KEYS[:-3]):
                row[k] = g[2 + i]
            teams[g[1]] = row
    for t, row in teams.items():
        row["sdjFired"], row["sdjPriced"], row["sdjAgree"] = shadow.get(t, ("-", "-", "-"))
    return {"keys": ECODEF_KEYS, "teams": teams}


COMIDLE_RE = re.compile(
    r"apex: com-idle t=(\d+) min=(\d+) idleS=([\d.]+) walkS=(\d+) gaps=(\d+) "
    r"worstS=([\d.]+) open=-?\d+ ask=(\d+)/([\d.]+) gate=(\d+)/([\d.]+) "
    r"slice=(\d+)/([\d.]+) none=(\d+)/([\d.]+)")
COMIDLE_KEYS = ["idleS", "walkS", "gaps", "worstS", "askS", "gateS", "sliceS", "noneS"]


def com_idle(d):
    """The commander's idle seconds per minute for the first ten, by cause (maketask.as)."""
    f = d / "infolog.txt"
    if not f.is_file():
        return {"error": "no infolog"}
    teams = {}
    with f.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "apex: com-idle t=" not in line:
                continue
            m = COMIDLE_RE.search(line)
            if not m:
                continue
            g = m.groups()
            teams.setdefault(g[0], []).append({
                "min": int(g[1]), "idleS": float(g[2]), "walkS": int(g[3]),
                "gaps": int(g[4]), "worstS": float(g[5]), "askS": float(g[7]),
                "gateS": float(g[9]), "sliceS": float(g[11]), "noneS": float(g[13])})
    return {"keys": COMIDLE_KEYS, "teams": teams}


# Cumulative metal by destination, straight from dev_stats_export's exclusive
# buckets. Runs from before those fields existed simply read zero everywhere,
# which is what an absent counter should look like.
SPEND_BUCKETS = {
    "eco": "mEco",
    "sArmy": "mArmy",
    "def": "mDefence",
    "defAA": "mDefAA",
    "bp": "mBP",
    "fac": "mFactories",
    "other": "mOther",
}


def economy(d):
    """The full economic picture per team, sample by sample.

    The engine's own counters are cumulative, so rates here are differenced
    between neighbouring samples rather than sampled instantaneously -- a
    2-minute mean, which is what a production figure should be. The bank,
    the pull and the stall counters come from GetTeamResources and have no
    cumulative equivalent.
    """
    teams = {}
    for e in stats_rows(d):
        if not isinstance(e, dict) or e.get("reason") != "periodic":
            continue
        tid = str(int(e.get("team", -1)))
        t = teams.setdefault(tid, {"ally": int(e.get("ally", -1)), "min": [],
                                   **{k: [] for k in ECON_FIELDS}})
        t["min"].append(round((e.get("frame", 0) or 0) / 30 / 60, 2))
        for k, field in ECON_FIELDS.items():
            t[k].append(round(float(e.get(field, 0) or 0), 2))
    for t in teams.values():
        mins, n = t["min"], len(t["min"])
        # Rates over each window. The first sample's window starts at 0:00,
        # which is true -- the game began there.
        for key, src in (("mRate", "mProd"), ("eRate", "eProd"),
                         ("mWasteRate", "mWaste"), ("eWasteRate", "eWaste")):
            out = []
            for i in range(n):
                dt = (mins[i] - (mins[i - 1] if i else 0.0)) * 60.0
                dv = t[src][i] - (t[src][i - 1] if i else 0.0)
                out.append(round(dv / dt, 2) if dt > 0 else 0.0)
            t[key] = out
        # Stall counters are cumulative sample counts; the useful number is
        # the share of THIS window spent unable to pay.
        for key, src in (("mStallPct", "mStall"), ("eStallPct", "eStall")):
            out = []
            for i in range(n):
                ds = t["resSamp"][i] - (t["resSamp"][i - 1] if i else 0.0)
                dv = t[src][i] - (t[src][i - 1] if i else 0.0)
                out.append(round(100.0 * dv / ds, 1) if ds > 0 else 0.0)
            t[key] = out
        for key, src in (("mFill", "mFillSum"), ("eFill", "eFillSum")):
            out = []
            for i in range(n):
                ds = t["resSamp"][i] - (t["resSamp"][i - 1] if i else 0.0)
                dv = t[src][i] - (t[src][i - 1] if i else 0.0)
                out.append(round(100.0 * dv / ds, 1) if ds > 0 else 0.0)
            t[key] = out
        # Waste as a share of what was made is the number that says whether an
        # overflow is a rounding error or half the economy.
        t["mWastePct"] = [round(100.0 * w / p, 1) if p > 0 else 0.0
                          for w, p in zip(t["mWaste"], t["mProd"])]
        t["eWastePct"] = [round(100.0 * w / p, 1) if p > 0 else 0.0
                          for w, p in zip(t["eWaste"], t["eProd"])]
    return {"teams": teams, "fields": list(ECON_FIELDS)}


# Sample fields this panel reads, mapped to their names in the gadget's dump.
# mNow/eNow and the stall counters are newer than the rest; a run without them
# reads zero, which is what an absent counter should look like.
ECON_FIELDS = {
    "mProd": "metalProduced", "mUsed": "metalUsed", "mWaste": "metalExcess",
    "eProd": "energyProduced", "eUsed": "energyUsed", "eWaste": "energyExcess",
    "mNow": "mNow", "mStore": "mStore", "mInc": "mInc", "mPull": "mPull",
    "eNow": "eNow", "eStore": "eStore", "eInc": "eInc", "ePull": "ePull",
    "resSamp": "resSamp", "mStall": "mStall", "eStall": "eStall",
    "mFillSum": "mFillSum", "eFillSum": "eFillSum",
}


def unit_counts(d):
    """Units finished per def, per team, over time -- from `unitCount=`.

    Counts, not metal: a metal sum divides out to a count only if you already
    know the cost, and the two game trees disagree on costs.
    """
    teams = {}
    for e in stats_rows(d):
        if not isinstance(e, dict) or e.get("reason") != "periodic":
            continue
        # unitCount is newer than the metal fields, so a run from before it
        # still charts metal rather than charting nothing.
        raw = e.get("unitCount")
        raw = raw if isinstance(raw, str) else ""
        tid = str(int(e.get("team", -1)))
        t = teams.setdefault(tid, {"ally": int(e.get("ally", -1)),
                                   "min": [], "counts": {}, "metal": {}})
        t["min"].append(round((e.get("frame", 0) or 0) / 30 / 60, 1))
        n = len(t["min"])
        for tok in raw.split(","):
            name, _, v = tok.partition(":")
            if not name or not v.isdigit():
                continue
            row = t["counts"].setdefault(name, [])
            row.extend([row[-1] if row else 0] * (n - 1 - len(row)))
            row.append(int(v))
        for tok in (e.get("allBuilt") or "").split(",") + \
                   (e.get("cheapBuilt") or "").split(","):
            name, _, v = tok.partition(":")
            if not name or not v:
                continue
            try:
                mv = float(v)
            except ValueError:
                continue
            row = t["metal"].setdefault(name, [])
            row.extend([row[-1] if row else 0.0] * (n - 1 - len(row)))
            row.append(mv)
    # A def first seen at sample k has no history before it, and a def that
    # stops appearing kept whatever it had: pad both ends so every series is
    # the same length as the time axis.
    for t in teams.values():
        n = len(t["min"])
        for tbl in (t["counts"], t["metal"]):
            for row in tbl.values():
                row.extend([row[-1] if row else 0] * (n - len(row)))
    names = unit_display_names()
    labels = {n: names.get(n, "")
              for t in teams.values() for n in list(t["counts"]) + list(t["metal"])}
    return {"teams": teams, "labels": labels}


INTEL_RE = re.compile(
    r"\[(\d+(?:\.\d+)?)m t(\d+)\] apex: intel ours=([-\d.]+) army=([-\d.]+) "
    r"massing=([-\d.]+) mobile=([-\d.]+) peak=([-\d.]+) groups=(\d+) "
    r"fresh=([-\d.]+) raw=([-\d.]+) \|(.*)")
INTEL_SCALARS = ["ours", "army", "massing", "mobile", "peak", "groups",
                 "fresh", "raw"]


def enemy_intel(d):
    """The enemy as the AI believes it to be, over time (Military::IntelDiag).

    Per role the pair is fresh/raw: raw includes everything ever seen, fresh
    only what was seen inside the manager's window. The gap is the ghost share,
    and apex_ghost_weight decides how much of it the posture gates consume.
    """
    f = d / "infolog.txt"
    if not f.is_file():
        return {"error": "no infolog"}
    teams, roles = {}, {}
    with f.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "apex: intel " not in line:
                continue
            m = INTEL_RE.search(line)
            if not m:
                continue
            t = teams.setdefault(m.group(2), {"min": [], "byRoleFresh": {},
                                              "byRoleRaw": {},
                                              **{k: [] for k in INTEL_SCALARS}})
            t["min"].append(float(m.group(1)))
            for i, k in enumerate(INTEL_SCALARS):
                t[k].append(float(m.group(3 + i)))
            n = len(t["min"])
            for tok in m.group(11).split():
                role, _, pair = tok.partition("=")
                fr, _, rw = pair.partition("/")
                if not role or not rw:
                    continue
                roles[role] = roles.get(role, 0.0) + float(rw)
                for key, val in (("byRoleFresh", fr), ("byRoleRaw", rw)):
                    row = t[key].setdefault(role, [])
                    row.extend([0.0] * (n - 1 - len(row)))
                    row.append(float(val))
            for key in ("byRoleFresh", "byRoleRaw"):
                for row in t[key].values():
                    row.extend([0.0] * (n - len(row)))
    return {"teams": teams, "roles": sorted(roles, key=lambda k: -roles[k]),
            "scalars": INTEL_SCALARS}


BUDGET_RE = re.compile(
    r"\[(\d+(?:\.\d+)?)m t(\d+)\] apex: budget army=([-\d.]+)/([-\d.]+) "
    r"def=([-\d.]+)/([-\d.]+) aa=([-\d.]+)/([-\d.]+) eco=([-\d.]+)/([-\d.]+) "
    r"bp=([-\d.]+)/([-\d.]+) (?:mult=\S+ )?inc=([-\d.]+) total=([-\d.]+)")
BUDGET_CATS = ["army", "def", "aa", "eco", "bp"]
RISK_RE = re.compile(
    r"\[(\d+(?:\.\d+)?)m t(\d+)\] apex: risk mex=(\d+) covered=(\d+) "
    r"meanShort=([-\d.]+) lostM=([-\d.]+)"
    r"(?:.*?home\[hazard=([-\d.]+)/ks short=([-\d.]+)\])?")
# The ETA objective's own state (eta.as): where the economy stands against the
# target it is heading for, how much cheap growth the board still owes us, and
# whether the ladder and the market's price actually disagree.
ETA_RE = re.compile(
    r"\[(\d+(?:\.\d+)?)m t(\d+)\] apex: eta t=\d+ "
    r"P=([-\d.]+) tgt=([-\d.]+) cheap=([-\d.]+) base=([-\d.]+) "
    r"mkt=(\S+) eta=(\S+)")
# Ground defence stage by stage (protect_census.as DefFunnelLog), per minute.
DEFFUNNEL_RE = re.compile(
    r"\[(\d+(?:\.\d+)?)m t(\d+)\] apex: def-funnel t=\d+ elec=(\d+) asked=(\d+) "
    r"skipped=(\d+) proposed=(\d+) top=(\d+) draw=(\d+) hoist=(\d+) exec=(\d+) "
    r"ok=(\d+) .*?finished=(\d+) gone=(\d+) have=(\d+) target=(\d+)")
DEFFUNNEL_KEYS = ["elec", "asked", "skipped", "proposed", "top", "draw", "hoist",
                  "exec", "ok", "finished", "gone", "have", "target"]


def brain_metrics(d):
    """The arbiter's own state over time: what share of metal each category has
    against the share its target curve asks for, plus the risk field.

    Share against target IS the multiplier every want is priced by
    (Brain::BudgetMult), so a category pinned under its target for ten minutes
    is the AI saying it wanted to buy something it never got to buy.
    """
    f = d / "infolog.txt"
    if not f.is_file():
        return {"error": "no infolog"}
    teams = {}
    with f.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "apex: budget " in line:
                m = BUDGET_RE.search(line)
                if not m:
                    continue
                t = teams.setdefault(m.group(2), _brain_team())
                t["min"].append(float(m.group(1)))
                for i, c in enumerate(BUDGET_CATS):
                    t["have"][c].append(float(m.group(3 + i * 2)))
                    t["target"][c].append(float(m.group(4 + i * 2)))
                t["income"].append(float(m.group(13)))
                t["spent"].append(float(m.group(14)))
            elif "apex: eta " in line:
                m = ETA_RE.search(line)
                if not m:
                    continue
                t = teams.setdefault(m.group(2), _brain_team())
                e = t["eta"]
                e["min"].append(float(m.group(1)))
                e["power"].append(float(m.group(3)))
                e["target"].append(float(m.group(4)))
                e["cheap"].append(float(m.group(5)))
                e["base"].append(float(m.group(6)))
                mkt, pick = m.group(7), m.group(8).split("=")[0]
                e["mkt"].append(mkt)
                e["pick"].append(pick)
                e["agree"].append(1 if mkt == pick else 0)
            elif "apex: def-funnel " in line:
                m = DEFFUNNEL_RE.search(line)
                if not m:
                    continue
                t = teams.setdefault(m.group(2), _brain_team())
                df = t["deffunnel"]
                df["min"].append(float(m.group(1)))
                for i, k in enumerate(DEFFUNNEL_KEYS):
                    df[k].append(int(m.group(3 + i)))
            elif "apex: risk " in line:
                m = RISK_RE.search(line)
                if not m:
                    continue
                t = teams.setdefault(m.group(2), _brain_team())
                t["risk"]["min"].append(float(m.group(1)))
                t["risk"]["mex"].append(int(m.group(3)))
                t["risk"]["covered"].append(int(m.group(4)))
                t["risk"]["shortfall"].append(float(m.group(5)))
                t["risk"]["lostM"].append(float(m.group(6)))
                t["risk"]["homeHazard"].append(float(m.group(7) or 0))
                t["risk"]["homeShort"].append(float(m.group(8) or 0))
    return {"cats": BUDGET_CATS, "teams": teams}


def _brain_team():
    return {"min": [], "income": [], "spent": [],
            "have": {c: [] for c in BUDGET_CATS},
            "target": {c: [] for c in BUDGET_CATS},
            "risk": {k: [] for k in ("min", "mex", "covered", "shortfall",
                                     "lostM", "homeHazard", "homeShort")},
            "eta": {k: [] for k in ("min", "power", "target", "cheap", "base",
                                    "mkt", "pick", "agree")},
            "deffunnel": {k: [] for k in ["min"] + DEFFUNNEL_KEYS}}


def match_detail(d):
    r = load_result(d)
    if r is None:
        return {"dir": str(d.relative_to(REPO)).replace(os.sep, "/"),
                "running": True, "files": [p.name for p in d.iterdir()]}
    r.pop("stats", None)
    stats = stats_rows(d)
    # Per-ally periodic series. Each spec's players share allyteam == spec index
    # (result.json's teams[].team is the spec index, NOT a game team).
    series = {}
    finals = {}
    for e in stats:
        if not isinstance(e, dict):
            continue
        ally = int(e.get("ally", -1))
        fr = e.get("frame", 0) or 0
        if e.get("reason") == "periodic":
            bucket = series.setdefault(ally, {})
            b = bucket.setdefault(fr, {"metal": 0.0, "army": 0.0,
                                       "mex": 0.0, "t2mex": 0.0, "n": 0,
                                       **{k: 0.0 for k in SPEND_BUCKETS}})
            b["metal"] += e.get("metalProduced", 0) or 0
            b["army"] += e.get("armyReal", 0) or 0
            b["mex"] += max(e.get("mex", 0) or 0, 0)
            b["t2mex"] += max(e.get("t2Mex", 0) or 0, 0)
            for k, field in SPEND_BUCKETS.items():
                b[k] += e.get(field, 0) or 0
            b["n"] += 1
        # keep the last entry seen per game team as its final snapshot
        finals[e.get("team")] = e
    chart = {}
    for ally, pts in series.items():
        rows = sorted(pts.items())
        chart[ally] = {
            "min": [round(fr / 30 / 60, 1) for fr, _ in rows],
            "metal": [round(v["metal"], 1) for _, v in rows],
            "army": [round(v["army"], 1) for _, v in rows],
            "mex": [v["mex"] for _, v in rows],
            "t2mex": [v["t2mex"] for _, v in rows],
            **{k: [round(v[k]) for _, v in rows] for k in SPEND_BUCKETS},
        }
    keep = ["team", "ally", "frame", "metalProduced", "armyReal", "mex", "t2Mex",
            "mT1", "mT2", "mT3", "mDefence", "mFactories", "mLostReal",
            "mKillReal", "conT1", "conT2", "techStart", "commLost", "top"]
    finals_out = [{k: e.get(k) for k in keep if k in e}
                  for _, e in sorted(finals.items(), key=lambda kv: kv[0] or 0)
                  if isinstance(e, dict)]
    return {
        "dir": str(d.relative_to(REPO)).replace(os.sep, "/"),
        "result": r,
        "chart": chart,
        "finals": finals_out,
        "health": infolog_health(d),
    }


def tournament_detail(d):
    out = tournament_summary(d)
    ms = []
    mdir = d / "matches"
    if mdir.is_dir():
        for m in sorted(mdir.iterdir()):
            if m.is_dir():
                ms.append(match_summary(m))
    # newest first, games still playing on top: a 600-game batch read oldest-first hid how it is going now.
    # An unfinished game whose dir has been quiet for an hour died; it sorts by its own age.
    now = time.time()
    for s in ms:
        if not s.get("mtime"):
            try:
                age = os.stat(REPO / s["dir"]).st_mtime
            except OSError:
                age = 0
            s["stalled"] = (now - age) > 3600
            s["sortAt"] = age if s["stalled"] else 9e18
    ms.sort(key=lambda s: -(s.get("mtime") or s.get("sortAt") or 0))
    out["matches"] = ms
    done = [s for s in ms if s.get("mtime")]
    out["recent"] = []
    for n in (25, 50, 100):
        last = done[:n]
        if len(last) >= min(n, 10):
            w = sum(1 for s in last if any(str(x).startswith("Apex") for x in (s.get("winner_specs") or [])))
            out["recent"].append({"n": len(last), "w": w, "since": last[-1]["mtime"]})
    out["rand"] = rand_view(d)
    if out["rand"]:
        lastAt, varied = {}, {}
        for s in done:
            m = re.match(r"c(\d+)-g\d+$", s["name"])
            if not m:
                continue
            nid = int(m.group(1))
            if nid not in lastAt:
                lastAt[nid] = s["mtime"]
            # every game until 10-11 15:15 was seed 1; only the others say how a network plays in general
            if s.get("seed") not in (None, 1):
                v = varied.setdefault(nid, [0, 0, 0])
                ws = s.get("winner_specs") or []
                v[0 if any(str(x).startswith("Apex") for x in ws) else (1 if not ws else 2)] += 1
        for n in out["rand"]["nets"]:
            n["last"] = lastAt.get(n["id"])
            n["varied"] = varied.get(n["id"])

        def vrate(n):
            v = n["varied"]
            return (v[0] + 0.5 * v[1]) / sum(v) if v and sum(v) >= 4 else None
        out["rand"]["nets"].sort(key=lambda n: (vrate(n) is None, -(vrate(n) or 0)))
    return out


RAND_STATE = REPO / "runtime" / "nn" / "rand.json"


def rand_view(d):
    """tools/randsearch.py's standings, when d is its batch: the ladder and one row per network played."""
    try:
        st = json.loads(RAND_STATE.read_text(encoding="utf-8"))
    except Exception:
        return None
    if os.path.basename(os.path.normpath(st.get("dir", ""))) != d.name:
        return None
    nets = []
    for n in st.get("nets", {}).values():
        g = n.get("games", [])
        if not g:
            continue
        res = [x[1] for x in g]
        nets.append({"id": n["id"], "s": n["s"], "games": len(g), "w": res.count("W"), "d": res.count("D"),
                     "l": res.count("L"), "score": sum(x[0] for x in g) / len(g), "target": n.get("target"),
                     "status": n.get("status"), "playing": n.get("busy", 0), "base": n.get("base"), "label": n.get("label")})
    nets.sort(key=lambda n: (n["games"] < 4, -(n["w"] + 0.5 * n["d"]) / n["games"], -n["games"]))
    rungs = {t: sum(1 for n in st.get("nets", {}).values() if n.get("target", 0) >= t or n.get("status") == "viable")
             for t in (4, 12, 24)}
    anneal = None
    if st.get("anneal"):
        import randsearch
        a = st["anneal"]
        kids = [n for n in st["nets"].values() if "base" in n]
        anneal = {"centre": a["centre"], "t": randsearch.temperature(st), "children": len(kids),
                  "viable": sum(1 for n in kids if n.get("status") == "viable")}
    return {"tried": st.get("next", 0), "explore": 1000, "rungs": rungs, "anneal": anneal,
            "viable": sum(1 for n in nets if n["status"] == "viable"), "nets": nets}


def known_maps():
    maps = set()
    for s in list_matches(400):
        if s.get("map"):
            maps.add(s["map"])
    for t in list_tournaments(200):
        maps.update(t.get("maps", []))
    return sorted(maps)


def short_name():
    """The deployed variant's shortName, from its own AIInfo.lua -- the deploy
    paths and the harness spec are keyed on it, not on the version."""
    info = REPO / "ai" / VARIANT / "engine-side" / "AIInfo.lua"
    try:
        m = re.search(r"key\s*=\s*'shortName'\s*,\s*\n\s*value\s*=\s*'([^']*)'",
                      info.read_text("utf-8", errors="replace"))
        if m:
            return m.group(1)
    except Exception:
        pass
    return "Apex"


def default_spec():
    return "%s:%s:%s" % (short_name(), VARIANT, PROFILE)


def _ai_profiles(options_lua):
    """(default, [profiles]) from an AIOptions.lua 'profile' list; (None, []) when it has none."""
    try:
        text = options_lua.read_text("utf-8", errors="replace")
    except OSError:
        return None, []
    text = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("--"))
    m = re.search(r"key\s*=\s*'profile'.*?\bitems\s*=\s*\{", text, re.S)
    if not m:
        return None, []
    depth, end = 1, m.end()
    while depth and end < len(text):
        depth += {"{": 1, "}": -1}.get(text[end], 0)
        end += 1
    d = re.search(r"\bdef\s*=\s*'([^']*)'", m.group(0))
    items = re.findall(r"\bkey\s*=\s*'([^']*)'", text[m.end():end])
    default = d.group(1) if d else (items[0] if items else None)
    return default, ([default] if default else []) + [i for i in items if i != default]


def _version_key(v):
    return tuple(int(x) for x in re.findall(r"\d+", v))


def launch_ai_choices():
    """Every AI the launch form can run: the installed ones, grouped and labelled for the picker."""
    import bar_env
    try:
        env = bar_env.load()
        installed, base = env.installed_ais(), env.engine_dir / "AI" / "Skirmish"
    except Exception:
        installed, base = [], None
    me, mine = short_name(), default_spec()
    out = []
    releases = sorted((a for a in installed if a.split(":")[0] == me and re.match(r"v\d", a.split(":")[1])),
                      key=lambda a: _version_key(a.split(":")[1]), reverse=True)
    for ai in installed:
        name, ver = ai.split(":", 1)
        default, profiles = _ai_profiles(base / name / ver / "AIOptions.lua") if base else (None, [])
        if name == me and ver == VARIANT:
            group, label = "This AI", "%s (repo)" % ver
        elif ai in releases:
            group, label = "Releases", ver + (" (latest)" if ai == releases[0] else "")
        elif ver.startswith("lane"):
            group, label = "Lanes", "%s (%s)" % (ver, name)
        else:
            group, label = "Other AIs", "%s %s" % (name, ver)
        rank = releases.index(ai) if ai in releases else 0
        for prof in profiles or [None]:
            spec = ai + (":" + prof if prof else "")
            show = label if not prof or (prof == default and prof == "standard") else "%s · %s" % (label, prof)
            out.append({"spec": spec, "group": group, "label": show, "rank": rank})
    if not any(c["spec"] == mine for c in out):
        out.insert(0, {"spec": mine, "group": "This AI", "label": "%s (not deployed)" % VARIANT, "rank": 0})
    order = {"This AI": 0, "Releases": 1, "Lanes": 2, "Other AIs": 3}
    out.sort(key=lambda c: (order[c["group"]], c["rank"], c["label"].lower()))
    for c in out:
        del c["rank"]
    return out


def _dead_spans():
    """{path: [(line, line)]} for unreachable functions; {} if the walk fails.

    A read inside a function nothing calls is not a read. Sixteen knobs in
    `policy.as` sat on this page adjustable and wired to nothing because each
    WAS read once -- by an accessor whose last caller went out with the brain
    overhaul. The dashboard must not offer those.
    """
    try:
        import as_scope
        return as_scope.dead_line_spans(as_scope.default_root())
    except Exception:
        return {}   # never let a static-analysis failure break the page


def tunable_callsites(live_only=False):
    """apex_<name> -> ["path/file.as:line", ...], read from the script tree.
    tunables.as's own file annotations rot on every refactor; this does not.

    `live_only` drops sites inside unreachable functions -- see `_dead_spans`.
    """
    base = REPO / "ai" / "Unstable" / "game-side" / "script"
    dead = _dead_spans() if live_only else {}
    out = {}
    # THE C++ DLL READS TUNABLES TOO (`circuit->GetTunable`). Scanning only the
    # script tree marked apex_porc_obsolete_ratio/_secs unread when both are
    # live reads in DefenceData.cpp -- the same blind spot docs_audit had.
    files = sorted(base.rglob("*.as"))
    cpp = REPO / "cpp" / "src"
    if cpp.is_dir():
        files += sorted(cpp.rglob("*.cpp")) + sorted(cpp.rglob("*.h"))
    for f in files:
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        # tunables.as annotates paths relative to its own profile dir.
        anchor = (SCRIPT_DIR if SCRIPT_DIR in f.parents
                  else base if base in f.parents else REPO)
        rel = str(f.relative_to(anchor)).replace(os.sep, "/")
        spans = dead.get(str(f), ())
        for mo in re.finditer(r'GetTunable\(\s*"([a-z_0-9]+)"', text):
            line = text.count("\n", 0, mo.start()) + 1
            if any(a <= line <= b for a, b in spans):
                continue
            out.setdefault(mo.group(1), []).append("%s:%d" % (rel, line))
    return out


def tunable_names():
    names = set()
    base = REPO / "ai" / "Unstable" / "game-side" / "script"
    for f in base.rglob("*.as"):
        try:
            names.update(re.findall(r'GetTunable\("([a-z_0-9]+)"',
                                    f.read_text(encoding="utf-8", errors="replace")))
        except Exception:
            pass
    return sorted(names)


# ---------------------------------------------------------------- jobs

def start_job(desc, args):
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    with JOBS_LOCK:
        JOB_SEQ[0] += 1
        jid = "j%d-%d" % (int(time.time()), JOB_SEQ[0])
    log = LOG_DIR / (jid + ".log")
    f = open(log, "wb")
    cmd = [PY, "-u"] + args
    f.write((" ".join(cmd) + "\n\n").encode())
    f.flush()
    proc = subprocess.Popen(cmd, cwd=str(REPO), stdout=f,
                            stderr=subprocess.STDOUT, env=_his_env())
    with JOBS_LOCK:
        JOBS[jid] = {"proc": proc, "logfile": f, "log": log, "desc": desc,
                     "cmd": " ".join(args), "started": time.time()}
    return jid


def job_state(jid, j):
    rc = j["proc"].poll()
    tail, head = "", ""
    try:
        with open(j["log"], "rb") as f:
            head = f.read(8000).decode("utf-8", errors="replace")
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - 12000))
            tail = f.read().decode("utf-8", errors="replace")
    except Exception:
        pass
    # run_match/run_tournament print "out      <dir>" — link the job to its run
    out_dir = None
    text = head + "\n" + tail
    # a tournament's "output:" (its run dir) wins over any child match's "out"
    m = (re.findall(r"^output: (.+)$", text, re.M)
         or re.findall(r"^out\s+(.+)$", text, re.M))
    if m:
        try:
            p = Path(m[-1].strip()).resolve()
            out_dir = str(p.relative_to(REPO)).replace(os.sep, "/")
        except Exception:
            pass
    result_ready = bool(out_dir and (REPO / out_dir / "result.json").is_file())
    return {"id": jid, "desc": j["desc"], "cmd": j["cmd"],
            "started": j["started"], "alive": rc is None, "exit": rc,
            "out_dir": out_dir, "result_ready": result_ready, "tail": tail}


# Watch games back to back: when the repeating game's job ends, the next one
# starts with the same settings and the next seed. Killing it or Stop ends it.
REPEAT = {"on": False, "params": None, "jid": None, "n": 0, "started": 0.0}
REPEAT_LOCK = threading.Lock()
REPEAT_MIN_S = 60     # a game that ends sooner failed to start: don't loop on it


def repeat_next():
    with REPEAT_LOCK:
        p = dict(REPEAT["params"])
        base = p.get("seed")
        p["seed"] = (int(base) + REPEAT["n"]) if base not in (None, "") else int(time.time()) % 1000000
        REPEAT["n"] += 1
        n = REPEAT["n"]
    jid = start_job("watch (repeat #%d) %s vs %s on %s" % (n, p.get("a"), p.get("b"), p.get("map")),
                    build_launch_cmd(p))
    with REPEAT_LOCK:
        REPEAT["jid"], REPEAT["started"] = jid, time.time()
    return jid


def repeat_start(p):
    p = dict(p)
    p.pop("repeat", None)
    build_launch_cmd(p)   # refuse bad settings now, not on the second game
    with REPEAT_LOCK:
        REPEAT.update(on=True, params=p, n=0, jid=None)
    return repeat_next()


def repeat_stop():
    with REPEAT_LOCK:
        REPEAT["on"] = False
    return {"ok": True}


def repeat_status():
    with REPEAT_LOCK:
        return {"on": REPEAT["on"], "n": REPEAT["n"], "jid": REPEAT["jid"],
                "map": (REPEAT["params"] or {}).get("map")}


def repeat_loop():
    while True:
        time.sleep(3)
        with REPEAT_LOCK:
            on, jid, started = REPEAT["on"], REPEAT["jid"], REPEAT["started"]
        if not on or not jid:
            continue
        with JOBS_LOCK:
            j = JOBS.get(jid)
        if j is not None and j["proc"].poll() is None:
            continue
        if time.time() - started < REPEAT_MIN_S:
            repeat_stop()
            continue
        try:
            repeat_next()
        except Exception:
            repeat_stop()


def kill_job(jid):
    with JOBS_LOCK:
        j = JOBS.get(jid)
    if not j:
        return {"ok": False, "error": "unknown job"}
    with REPEAT_LOCK:
        if REPEAT["jid"] == jid:
            REPEAT["on"] = False
    pid = j["proc"].pid
    # /T takes the whole tree so no engine process is orphaned
    subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"],
                   capture_output=True)
    return {"ok": True}


SEARCH_TTL = 180
SEARCH = {"at": 0.0, "data": None, "error": None, "cache": {}, "thread": None}
SEARCH_LOCK = threading.Lock()


def _search_compute():
    import nnshift
    try:
        d, err = nnshift.collect(SEARCH["cache"]), None
    except Exception as e:
        d, err = None, "%s: %s" % (type(e).__name__, e)
    with SEARCH_LOCK:
        if d is not None:
            SEARCH["data"] = d
        SEARCH.update(at=time.time(), error=err, thread=None)


def search_view(refresh=False):
    """The policy search (tools/nnshift.py): each group's lean against the rule and every finished game with its
    setup. Reading the infologs is slow, so it is redone in the background at most every SEARCH_TTL seconds or
    when asked; only the first call waits. The per-network progress is read from rand.json on every call."""
    import nnshift
    with SEARCH_LOCK:
        if (refresh or time.time() - SEARCH["at"] > SEARCH_TTL) and SEARCH["thread"] is None:
            SEARCH["thread"] = threading.Thread(target=_search_compute, daemon=True)
            SEARCH["thread"].start()
        t = SEARCH["thread"]
    if SEARCH["data"] is None and t is not None:
        t.join(180)
    with SEARCH_LOCK:
        d, at, err, busy = SEARCH["data"], SEARCH["at"], SEARCH["error"], SEARCH["thread"] is not None
    if d is None:
        return {"error": err or "still reading the games", "busy": busy}
    if d.get("mode") == "training":
        return {**d, "computed_at": at, "busy": busy, "error": err, "ttl": SEARCH_TTL}
    live = nnshift.load_state(str(RAND_STATE))
    return {**d, "progress": {"current": nnshift.progress(live), "old": d["progress"]["old"]},
            "search_dir": os.path.basename(os.path.normpath(live.get("dir") or "")) or d["search_dir"],
            "computed_at": at, "busy": busy, "error": err, "ttl": SEARCH_TTL}


PG_DIR = REPO / "runtime" / "pg"


LEAN_DIR = REPO / "runtime" / "lean"


def lean_view():
    """Training by held leans (tools/leanloop.py): every slot's lean and its slope over the pairs since it last moved,
    the moves, each finished pair's two scores."""
    import leanloop
    st = json.loads((LEAN_DIR / "state.json").read_text(encoding="utf-8"))
    pairs = leanloop.read_pairs()
    sl = leanloop.slopes(st, pairs)
    try:
        log = (LEAN_DIR / "lean.log").read_text(encoding="utf-8").splitlines()[-6:]
    except OSError:
        log = []
    on = (LEAN_DIR / "lean_on").exists()
    return {"exists": True, "mode": "lean", "on": on, "paused": (LEAN_DIR / "lean_on.paused").exists() and not on,
            "started": st.get("started"), "dir": os.path.basename(os.path.normpath(st.get("dir") or "")),
            "steps": st.get("steps", 0), "running": len(st.get("running", {})), "log": log,
            "pairs": [{"n": p["n"], "at": p["at"], "score": p["score"], "setup": p.get("setup")} for p in pairs],
            "slots": [{"name": st["names"][i], "amount": st["amount"][i], "live": st["live"][i],
                       "lean": st["lean"][i], "slope": round(g, 3), "t": round(t, 2), "n": n}
                      for i, (g, t, n) in enumerate(sl)],
            "moves": st.get("moves", []), "tMove": leanloop.T_MOVE, "minPairs": leanloop.MIN_PAIRS,
            "kinds": leanloop.kind_names(), "updated": (LEAN_DIR / "state.json").stat().st_mtime}


def training_view():
    """The training run: held leans (tools/leanloop.py) when one exists, else learning from our own choices
    (tools/pgloop.py): running or paused, the version playing, games launched and waiting for the next step, every
    step's report (games, decisions, mean score, result, step size, each decision's signal t), and the loop's last
    log lines. Cheap: a few small files, read on every call."""
    if (LEAN_DIR / "state.json").exists():
        try:
            return lean_view()
        except (OSError, ValueError, KeyError):
            pass
    try:
        st = json.loads((PG_DIR / "state.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {"exists": False}
    hist = []
    try:
        for line in (PG_DIR / "history.jsonl").read_text(encoding="utf-8").splitlines():
            if line.strip():
                hist.append(json.loads(line))
    except (OSError, ValueError):
        pass
    try:
        log = (PG_DIR / "pg.log").read_text(encoding="utf-8").splitlines()[-8:]
    except OSError:
        log = []
    on = (PG_DIR / "pg_on").exists()
    return {"exists": True, "on": on, "paused": (PG_DIR / "pg_on.paused").exists() and not on,
            "version": st.get("version", 0), "launched": st.get("next_game", 0),
            "waiting": len(st.get("pending", [])), "started": st.get("started"),
            "dir": os.path.basename(os.path.normpath(st.get("dir") or "")), "history": hist, "log": log,
            "updated": (PG_DIR / "state.json").stat().st_mtime}


PROGRESS_LOCK = threading.Lock()
PROGRESS_VIEW = {}


def progress_since(since):
    """A batch-name prefix from the Progress tab's choice: "search" is the current search's batch,
    "<N>h" the last N hours, anything else is the prefix."""
    import progress
    if not since:
        return progress.NEW_NETS
    if since == "search":
        try:
            return os.path.basename(os.path.normpath(json.loads(RAND_STATE.read_text(encoding="utf-8"))["dir"]))[:15]
        except Exception:
            return progress.NEW_NETS
    if since.endswith("h") and since[:-1].isdigit():
        return time.strftime("%Y%m%d-%H%M", time.localtime(time.time() - int(since[:-1]) * 3600))
    return since


def progress_view(q):
    import progress
    with PROGRESS_LOCK:
        since = progress_since(q.get("since"))
        games = progress.collect(since, q.get("all") == "1", q.get("bonus") or None, q.get("map") or None)
        games = [g for g in games if not g["tournament"].endswith("-b0")]
        groups = int(q["groups"]) if (q.get("groups") or "").isdigit() else None
        key = (since, q.get("all"), q.get("bonus"), q.get("map"), q.get("by"), groups,
               len(games), (games[-1]["tournament"], games[-1]["match"]) if games else None)
        hit = PROGRESS_VIEW.get(key[:6])
        if hit is None or hit[0] != key:
            hit = (key, progress.summary(games, q.get("by") or "batch", last_groups=groups))
            PROGRESS_VIEW[key[:6]] = hit
        return hit[1] | {"since": since}


FACTION_CHOICES = {"random", "armada", "cortex", "legion"}


def faction_sides(p):
    """Compose a --sides value from the per-side faction pickers. 'random' is
    passed through: dropping it let run_match's Armada-vs-Cortex default play
    while the picker said Random."""
    a = str(p.get("side_a") or "random").strip().lower()
    b = str(p.get("side_b") or "random").strip().lower()
    if a not in FACTION_CHOICES or b not in FACTION_CHOICES:
        raise ValueError("bad faction: %s,%s" % (a, b))
    return ",".join(s if s == "random" else s.capitalize() for s in (a, b))


def build_launch_cmd(p):
    def clean(v):
        v = str(v).strip()
        if not v or any(c in v for c in "\r\n\0"):
            raise ValueError("bad value")
        return v
    mode = p.get("mode", "headless")
    args = ["tools/run_match.py",
            "--a", clean(p.get("a", "Apex:Unstable:standard")),
            "--b", clean(p.get("b", "BARb:stable:hard")),
            "--map", clean(p.get("map", ""))]
    if p.get("minutes"):
        args += ["--minutes", str(int(p["minutes"]))]
    if p.get("per_side") and int(p["per_side"]) > 1:
        args += ["--per-side", str(int(p["per_side"]))]
    if p.get("seed") not in (None, ""):
        args += ["--seed", str(int(p["seed"]))]
    sides = p.get("sides") or faction_sides(p)
    if sides:
        args += ["--sides", clean(sides)]
    if p.get("boxes"):
        args += ["--boxes", clean(p["boxes"])]
    if p.get("box_size") not in (None, "", 0, "0"):
        bs = float(p["box_size"])
        if not (0.02 <= bs <= 0.9):
            raise ValueError("box_size out of range: %s" % bs)
        args += ["--box-size", str(bs)]
    # "" leaves run_match.py's own default in place: 50 under --watch because a
    # hosted game is always bonused, 0 headless so benchmarks stay comparable.
    if p.get("handicap") not in (None, "", "auto"):
        hc = int(p["handicap"])
        if not (0 <= hc <= 500):
            raise ValueError("handicap out of range: %s" % hc)
        args += ["--handicap", str(hc)]
    if mode == "watch":
        args += ["--watch"]
        if p.get("speed"):
            args += ["--speed", str(int(float(p["speed"])))]
    for mo in p.get("modoptions", []) or []:
        mo = clean(mo)
        if not re.fullmatch(r"[a-z0-9_]+=[-\w.]+", mo):
            raise ValueError("bad modoption: %s" % mo)
        args += ["--modoption", mo]
    return args


def build_tournament_cmd(p):
    def clean(v):
        v = str(v).strip()
        if not v or any(c in v for c in "\r\n\0"):
            raise ValueError("bad value")
        return v
    args = ["tools/run_tournament.py",
            "--a", clean(p.get("a", "Apex:Unstable:standard")),
            "--b", clean(p.get("b", "BARb:stable:hard")),
            "--maps", clean(p.get("map", "")),
            "--games", str(int(p.get("games", 6)))]
    if p.get("minutes"):
        args += ["--minutes", str(int(p["minutes"]))]
    if p.get("per_side") and int(p["per_side"]) > 1:
        args += ["--per-side", str(int(p["per_side"]))]
    sides = p.get("sides") or faction_sides(p)
    if sides:
        args += ["--sides", clean(sides)]
    # A tournament has no --watch, so "auto" is the tool's own 0.
    if p.get("handicap") not in (None, "", "auto"):
        hc = int(p["handicap"])
        if not (0 <= hc <= 500):
            raise ValueError("handicap out of range: %s" % hc)
        args += ["--handicap", str(hc)]
    for mo in p.get("modoptions", []) or []:
        mo = clean(mo)
        if not re.fullmatch(r"[a-z0-9_]+=[-\w.]+", mo):
            raise ValueError("bad modoption: %s" % mo)
        args += ["--modoption", mo]
    return args


# ---------------------------------------------------------------- tunables

TUNABLES_AS = SCRIPT_DIR / "tunables.as"
DIVIDER_RE = re.compile(r"^// ?[-=]{20,}$")
ENTRY_HEAD_RE = re.compile(
    r"^// ((?:[\w/]+\.as)(?:, [\w/]+\.as)*)?\s*(\[[^\]]+\])?\s*(?:--\s*)?(.*)$")
# A doc block STARTS at one of these lines; the rest are its continuation.
# tunables.as keeps blocks for tunables that were later deleted, so only the
# LAST block above a const describes that const.
BLOCK_START_RE = re.compile(
    r"^// (?:[\w/]+\.as(?:, [\w/]+\.as)*[\s\[]|[A-Z][A-Z_0-9]{2,}:)")
# Old-style continuation lines are indented under their header.
CONT_RE = re.compile(r"^//\s{2,}\S")


def starts_block(line, prev):
    """Does this comment line open a new doc block, or continue the last one?
    The newer entries carry no file/name header, so a fresh sentence after a
    finished one is the only separator they have."""
    if BLOCK_START_RE.match(line):
        return True
    if CONT_RE.match(line):
        return False
    return prev.endswith(".") and bool(re.match(r"^// [A-Z]", line))
ARRAY_RE = re.compile(r"^(array<float>\s+([A-Z_0-9]+)\s*=\s*\{)([^}]*)(\}.*)$")


CPP_TUNE_RE = re.compile(
    r'GetTunable\(\s*"(apex_[a-z0-9_]+)"\s*,\s*([^);]+)\)')


def gadget_tunable_names():
    """Names dev_tunables.lua will actually republish. A name missing from that
    list is silently ignored, so the modoption reads as a no-op."""
    f = REPO / "game-patches" / "gadgets" / "dev_tunables.lua"
    try:
        return set(re.findall(r'^\s*"(apex_[a-z0-9_]+)"', f.read_text(encoding="utf-8"),
                              re.M))
    except Exception:
        return set()


def cpp_tunables():
    """Tunables read by the DLL, which have no TUNE_ const in tunables.as and so
    are invisible to the parser above. Values are compiled in -- they can only be
    changed by a modoption (or a rebuild), so these entries are read-only."""
    # The build tree is what actually compiled; cpp/ is its mirror.
    roots = [REPO / "vendor" / "engine" / "AI" / "Skirmish" / "BARb" / "src" / "circuit",
             REPO / "cpp" / "src" / "circuit"]
    root = next((r for r in roots if r.is_dir()), None)
    if root is None:
        return None
    registered = gadget_tunable_names()
    found = {}
    for f in sorted(root.rglob("*.cpp")):
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        for m in CPP_TUNE_RE.finditer(text):
            name, default = m.group(1), m.group(2).strip()
            if name in found:
                continue
            line = text.count(chr(10), 0, m.start()) + 1
            found[name] = {
                "name": name, "tunable": name, "value": default,
                "unit": "", "readonly": True,
                "reads": str(f.relative_to(REPO)).replace(os.sep, "/") + ":" + str(line),
                "desc": ("" if name in registered else
                         "NOT in dev_tunables.lua -- the modoption is silently ignored. "),
                "file": str(f.relative_to(REPO)).replace(os.sep, "/"),
                "line": line,
            }
    if not found:
        return None
    return {"title": "C++ / SkirmishAI.dll (modoption only)",
            "entries": [found[k] for k in sorted(found)]}


def parse_tunables():
    """tunables.as -> [{title, entries:[{name,tunable,value,unit,reads,desc,line}]}]"""
    lines = TUNABLES_AS.read_text(encoding="utf-8").split("\n")
    callsites = tunable_callsites()
    # `unread` asks whether editing this knob can change the game, so it is
    # judged on REACHABLE reads only; `reads` still shows every site.
    livesites = tunable_callsites(live_only=True)
    sections, cur = [], None
    pending = []   # list of comment BLOCKS; only the last one is this const's
    i = 0
    while i < len(lines):
        line = lines[i]
        if DIVIDER_RE.match(line) and i + 1 < len(lines) \
                and lines[i + 1].startswith("//") \
                and not DIVIDER_RE.match(lines[i + 1]):
            # header block: divider / title / optional intro lines / divider
            cur = {"title": lines[i + 1][2:].strip(), "entries": []}
            sections.append(cur)
            pending = []
            i += 2
            while i < len(lines) and lines[i].startswith("//") \
                    and not DIVIDER_RE.match(lines[i]):
                i += 1
            if i < len(lines) and DIVIDER_RE.match(lines[i]):
                i += 1
            continue
        m = CONST_RE.match(line)
        if m and cur is not None:
            unit, reads, desc = "", "", []
            for k, c in enumerate(pending[-1] if pending else []):
                h = ENTRY_HEAD_RE.match(c)
                if k == 0 and h:
                    reads = h.group(1) or ""
                    unit = (h.group(2) or "").strip("[]")
                    if h.group(3):
                        desc.append(h.group(3))
                else:
                    desc.append(re.sub(r"^//\s*", "", c))
            name = m.group(2)
            tunable = ("apex_" + name.replace("TUNE_", "").lower()
                       if name.startswith("TUNE_") else "")
            sites = callsites.get(tunable, [])
            annotated = sorted(x.strip() for x in reads.split(",") if x.strip())
            actual = sorted({x.rsplit(":", 1)[0] for x in sites})
            cur["entries"].append({
                "name": name,
                "tunable": tunable,
                "value": m.group(3).strip(),
                "unit": unit,
                "reads": ", ".join(sites) or reads,
                "reads_stale": bool(sites) and bool(annotated)
                               and annotated != actual,
                "unread": bool(tunable) and not livesites.get(tunable),
                "desc": " ".join(desc).strip(),
                "file": str(TUNABLES_AS.relative_to(REPO)).replace(os.sep, "/"),
                "line": i + 1,
            })
            pending = []
        elif line.strip().startswith("//") and not DIVIDER_RE.match(line):
            if not pending or starts_block(line.strip(), pending[-1][-1]):
                pending.append([])
            pending[-1].append(line.strip())
        elif line.strip() == "":
            pending = []
        i += 1
    return [s for s in sections if s["entries"]]


# ---------------------------------------------------------------- http

REMOTE = False
TAILNET = ipaddress.ip_network("100.64.0.0/10")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a):
        pass

    def send_json(self, obj, code=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def allowed(self, write):
        """This machine may do anything; with --remote a tailnet address may only look."""
        ip = self.client_address[0]
        local = ip in ("127.0.0.1", "::1")
        try:
            tailnet = ipaddress.ip_address(ip) in TAILNET
        except ValueError:
            tailnet = False
        if local or (REMOTE and tailnet and not write):
            return True
        self.send_json({"error": "view-only from another computer" if tailnet else "forbidden"}, 403)
        return False

    def do_GET(self):
        if not self.allowed(False):
            return
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        try:
            if u.path in ("/", "/index.html"):
                body = UI_FILE.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            elif u.path == "/api/overview":
                with JOBS_LOCK:
                    jobs = [{"id": k, "desc": j["desc"],
                             "alive": j["proc"].poll() is None}
                            for k, j in JOBS.items()]
                self.send_json({"processes": running_processes(), "jobs": jobs,
                                "repo": str(REPO)})
            elif u.path == "/api/search":
                self.send_json(search_view(q.get("refresh") == "1"))
            elif u.path == "/api/training":
                self.send_json(training_view())
            elif u.path == "/api/progress":
                self.send_json(progress_view(q))
            elif u.path == "/api/games":
                kind = q.get("kind", "matches")
                self.send_json(list_matches() if kind == "matches"
                               else list_tournaments())
            elif u.path == "/api/game":
                d = safe_run_dir(q["dir"])
                if (d / "matches").is_dir():
                    self.send_json(tournament_detail(d))
                else:
                    self.send_json(match_detail(d))
            elif u.path == "/api/brain":
                self.send_json(brain_wants(safe_run_dir(q["dir"])))
            elif u.path == "/api/economy":
                self.send_json(economy(safe_run_dir(q["dir"])))
            elif u.path == "/api/units":
                self.send_json(unit_counts(safe_run_dir(q["dir"])))
            elif u.path == "/api/intel":
                self.send_json(enemy_intel(safe_run_dir(q["dir"])))
            elif u.path == "/api/brainmetrics":
                self.send_json(brain_metrics(safe_run_dir(q["dir"])))
            elif u.path == "/api/crew":
                self.send_json(crew_roles(safe_run_dir(q["dir"])))
            elif u.path == "/api/fronttowers":
                self.send_json(front_towers(safe_run_dir(q["dir"])))
            elif u.path == "/api/lift":
                self.send_json(lift(safe_run_dir(q["dir"])))
            elif u.path == "/api/ecodef":
                self.send_json(ecodef(safe_run_dir(q["dir"])))
            elif u.path == "/api/comidle":
                self.send_json(com_idle(safe_run_dir(q["dir"])))
            elif u.path == "/api/facsupport":
                self.send_json(factory_support(safe_run_dir(q["dir"])))
            elif u.path == "/api/launchais":
                self.send_json({"ais": launch_ai_choices(), "default_a": default_spec()})
            elif u.path == "/api/launchmeta":
                self.send_json({"maps": known_maps(),
                                "tunables": tunable_names(),
                                "variant": VARIANT,
                                "gadget_tunables": sorted(gadget_tunable_names())})
            elif u.path == "/api/jobs":
                with JOBS_LOCK:
                    items = list(JOBS.items())
                self.send_json([job_state(k, j) for k, j in
                                sorted(items, key=lambda kv: -kv[1]["started"])])
            elif u.path == "/api/tunables":
                secs = parse_tunables()
                cpp = cpp_tunables()
                if cpp:
                    secs.append(cpp)
                self.send_json({"sections": secs,
                                "gadget_tunables": sorted(gadget_tunable_names())})
            else:
                self.send_json({"error": "not found"}, 404)
        except Exception as e:
            self.send_json({"error": str(e)}, 400)

    def do_POST(self):
        if not self.allowed(True):
            return
        u = urlparse(self.path)
        try:
            p = self.read_body()
            if u.path == "/api/tool":
                tool = ANALYSIS_TOOLS.get(p.get("tool"))
                if not tool:
                    raise ValueError("unknown tool")
                script, has_control = tool
                target = safe_run_dir(p["target"])
                args = ["tools/" + script, str(target)]
                if has_control and p.get("control"):
                    args += ["--control", str(safe_run_dir(p["control"]))]
                self.send_json(run_tool(args))
            elif u.path == "/api/action":
                act = DEPLOY_ACTIONS.get(p.get("action"))
                if not act:
                    raise ValueError("unknown action")
                if p["action"] in ("deploy", "gadgets"):
                    procs = running_processes()
                    if procs and not p.get("force"):
                        self.send_json({"ok": False, "blocked": True,
                                        "processes": procs,
                                        "output": "Blocked: %s running. Deploying now "
                                        "leaves the AI folder half-written (WinError 5)."
                                        % ", ".join(procs)})
                        return
                self.send_json(run_tool(["tools/" + act[0]] + act[1:]))
            elif u.path == "/api/launch":
                if p.get("kind") == "tournament":
                    args = build_tournament_cmd(p)
                    desc = "tournament %s vs %s on %s" % (
                        p.get("a"), p.get("b"), p.get("map"))
                elif p.get("repeat") and p.get("mode") == "watch":
                    self.send_json({"ok": True, "id": repeat_start(p), "repeat": True})
                    return
                else:
                    args = build_launch_cmd(p)
                    desc = "%s %s vs %s on %s" % (
                        p.get("mode", "headless"), p.get("a"), p.get("b"),
                        p.get("map"))
                self.send_json({"ok": True, "id": start_job(desc, args)})
            elif u.path == "/api/repeat":
                self.send_json(repeat_stop() if p.get("action") == "stop" else repeat_status())
            elif u.path == "/api/kill":
                self.send_json(kill_job(p.get("id")))
            else:
                self.send_json({"error": "not found"}, 404)
        except Exception as e:
            self.send_json({"error": str(e)}, 400)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, default=8420)
    ap.add_argument("--no-browser", action="store_true")
    ap.add_argument("--remote", action="store_true",
                    help="also answer Tailscale devices (100.64.0.0/10), view-only")
    a = ap.parse_args()
    global REMOTE
    REMOTE = a.remote
    srv = ThreadingHTTPServer(("0.0.0.0" if REMOTE else "127.0.0.1", a.port), Handler)
    threading.Thread(target=repeat_loop, daemon=True).start()
    url ="http://127.0.0.1:%d" % a.port
    print("bar-ai dashboard: %s   (Ctrl+C to stop)" % url)
    if REMOTE:
        print("  view-only from the tailnet: http://<this machine's tailscale name>:%d" % a.port)
    if not a.no_browser:
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
