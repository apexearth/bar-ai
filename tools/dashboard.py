"""Local web dashboard for the bar-ai harness.

    python tools/dashboard.py            # serves http://127.0.0.1:8420 and opens a browser
    python tools/dashboard.py --port N --no-browser

Stdlib only. Binds 127.0.0.1 only. The page is tools/dashboard_ui.html; this file
is the API: browse matches/tournaments, run the analysis tools, launch watch or
headless games as tracked jobs, deploy, and edit tunables (top-level script
consts in place, config JSON as validated text so the // comments survive).
"""
import argparse
import json
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
SCRIPT_DIR = REPO / "ai" / "apex" / "game-side" / "script" / "hard_aggressive"
CONFIG_DIR = REPO / "ai" / "apex" / "game-side" / "config" / "hard_aggressive"
UI_FILE = TOOLS / "dashboard_ui.html"
LOG_DIR = MATCHES / "_dashboard_logs"
PY = sys.executable

# Analysis tools the UI may run against a run dir. Each entry: script name and
# whether it accepts --control.
ANALYSIS_TOOLS = {
    "review": ("review.py", True),
    "composition": ("composition.py", False),
    "tl": ("tl.py", False),
    "fight1v1": ("fight1v1.py", False),
    "trace_flow": ("trace_flow.py", False),
    "deaths": ("deaths.py", False),
    "scaling": ("scaling.py", False),
}

DEPLOY_ACTIONS = {
    "status": ["deploy_ai.py", "status"],
    "check": ["check.py"],
    "deploy": ["deploy_ai.py", "deploy", "apex"],
    "pull": ["deploy_ai.py", "pull", "apex"],
    "gadgets": ["deploy_ai.py", "gadgets"],
}

CONST_RE = re.compile(
    r"^(const\s+(?:float|int|uint|double|bool)\s+(\w+)\s*=\s*)([^;]+)(;.*)$")

JOBS = {}
JOBS_LOCK = threading.Lock()
JOB_SEQ = [0]

_summary_cache = {}


# ---------------------------------------------------------------- helpers

def run_tool(args, timeout=600):
    """Run a repo python tool synchronously; return dict with output."""
    cmd = [PY, "-u"] + args
    try:
        p = subprocess.run(cmd, cwd=str(REPO), capture_output=True, text=True,
                           errors="replace", timeout=timeout)
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
        "crashed": res.get("crashed", False),
        "valid": res.get("valid"),
        "mtime": mt,
        "replay": bool(r.get("replay")),
    }
    _summary_cache[key] = (mt, s)
    return s


def list_matches(limit=250):
    if not MATCHES.is_dir():
        return []
    dirs = sorted((d for d in MATCHES.iterdir()
                   if d.is_dir() and not d.name.startswith("_")),
                  key=lambda d: d.stat().st_mtime, reverse=True)[:limit]
    return [match_summary(d) for d in dirs]


def tournament_summary(d):
    cfg = {}
    try:
        with open(d / "config.json", encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception:
        pass
    mdir = d / "matches"
    wins, games, done = {}, 0, 0
    if mdir.is_dir():
        for m in sorted(mdir.iterdir()):
            if not m.is_dir():
                continue
            games += 1
            r = load_result(m)
            if not r:
                continue
            done += 1
            for w in (r.get("result", {}) or {}).get("winner_specs", []):
                wins[w] = wins.get(w, 0) + 1
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
    if not TOURNAMENTS.is_dir():
        return []
    dirs = sorted((d for d in TOURNAMENTS.iterdir() if d.is_dir()),
                  key=lambda d: d.stat().st_mtime, reverse=True)[:limit]
    return [tournament_summary(d) for d in dirs]


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


def match_detail(d):
    r = load_result(d)
    if r is None:
        return {"dir": str(d.relative_to(REPO)).replace(os.sep, "/"),
                "running": True, "files": [p.name for p in d.iterdir()]}
    stats = r.pop("stats", []) or []
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
                                       "mex": 0.0, "t2mex": 0.0, "n": 0})
            b["metal"] += e.get("metalProduced", 0) or 0
            b["army"] += e.get("armyReal", 0) or 0
            b["mex"] += max(e.get("mex", 0) or 0, 0)
            b["t2mex"] += max(e.get("t2Mex", 0) or 0, 0)
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
    out["matches"] = ms
    return out


def known_maps():
    maps = set()
    for s in list_matches(400):
        if s.get("map"):
            maps.add(s["map"])
    for t in list_tournaments(200):
        maps.update(t.get("maps", []))
    return sorted(maps)


def known_ai_specs():
    specs = {"Apex:apex:hard_aggressive", "BARb:stable:hard"}
    for s in list_matches(200):
        specs.update(x for x in s.get("specs", []) if x)
    return sorted(sp.replace("-", ":") if ":" not in sp else sp for sp in specs)


def tunable_names():
    names = set()
    base = REPO / "ai" / "apex" / "game-side" / "script"
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
                            stderr=subprocess.STDOUT)
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


def kill_job(jid):
    with JOBS_LOCK:
        j = JOBS.get(jid)
    if not j:
        return {"ok": False, "error": "unknown job"}
    pid = j["proc"].pid
    # /T takes the whole tree so no engine process is orphaned
    subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"],
                   capture_output=True)
    return {"ok": True}


def build_launch_cmd(p):
    def clean(v):
        v = str(v).strip()
        if not v or any(c in v for c in "\r\n\0"):
            raise ValueError("bad value")
        return v
    mode = p.get("mode", "headless")
    args = ["tools/run_match.py",
            "--a", clean(p.get("a", "Apex:apex:hard_aggressive")),
            "--b", clean(p.get("b", "BARb:stable:hard")),
            "--map", clean(p.get("map", ""))]
    if p.get("minutes"):
        args += ["--minutes", str(int(p["minutes"]))]
    if p.get("per_side") and int(p["per_side"]) > 1:
        args += ["--per-side", str(int(p["per_side"]))]
    if p.get("seed") not in (None, ""):
        args += ["--seed", str(int(p["seed"]))]
    if p.get("sides"):
        args += ["--sides", clean(p["sides"])]
    if p.get("boxes"):
        args += ["--boxes", clean(p["boxes"])]
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
            "--a", clean(p.get("a", "Apex:apex:hard_aggressive")),
            "--b", clean(p.get("b", "BARb:stable:hard")),
            "--maps", clean(p.get("map", "")),
            "--games", str(int(p.get("games", 6)))]
    if p.get("minutes"):
        args += ["--minutes", str(int(p["minutes"]))]
    if p.get("per_side") and int(p["per_side"]) > 1:
        args += ["--per-side", str(int(p["per_side"]))]
    return args


# ---------------------------------------------------------------- tunables

TUNABLES_AS = SCRIPT_DIR / "tunables.as"
TARGETS_AS = SCRIPT_DIR / "targets.as"
DIVIDER_RE = re.compile(r"^// ?[-=]{20,}$")
ENTRY_HEAD_RE = re.compile(
    r"^// ((?:[\w/]+\.as)(?:, [\w/]+\.as)*)?\s*(\[[^\]]+\])?\s*(?:--\s*)?(.*)$")
ARRAY_RE = re.compile(r"^(array<float>\s+([A-Z_0-9]+)\s*=\s*\{)([^}]*)(\}.*)$")


def parse_tunables():
    """tunables.as -> [{title, entries:[{name,tunable,value,unit,reads,desc,line}]}]"""
    lines = TUNABLES_AS.read_text(encoding="utf-8").split("\n")
    sections, cur = [], None
    pending = []
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
            for k, c in enumerate(pending):
                h = ENTRY_HEAD_RE.match(c)
                if k == 0 and h:
                    reads = h.group(1) or ""
                    unit = (h.group(2) or "").strip("[]")
                    if h.group(3):
                        desc.append(h.group(3))
                else:
                    desc.append(re.sub(r"^//\s*", "", c))
            name = m.group(2)
            cur["entries"].append({
                "name": name,
                "tunable": "apex_" + name.replace("TUNE_", "").lower()
                           if name.startswith("TUNE_") else "",
                "value": m.group(3).strip(),
                "unit": unit, "reads": reads,
                "desc": " ".join(desc).strip(),
                "file": str(TUNABLES_AS.relative_to(REPO)).replace(os.sep, "/"),
                "line": i + 1,
            })
            pending = []
        elif line.strip().startswith("//") and not DIVIDER_RE.match(line):
            pending.append(line.strip())
        elif line.strip() == "":
            pending = []
        i += 1
    return [s for s in sections if s["entries"]]


def parse_targets():
    """targets.as -> {income, groups:[{title, rows:[{name,values,line,comment,desc}]}]}"""
    lines = TARGETS_AS.read_text(encoding="utf-8").split("\n")
    income, groups, cur = [], [], None
    pending = []
    for i, line in enumerate(lines):
        m = ARRAY_RE.match(line)
        if m:
            vals = [v.strip().rstrip("f") for v in m.group(3).split(",")]
            tail = m.group(4)
            trailing = tail.split("//", 1)[1].strip() if "//" in tail else ""
            desc = " ".join(re.sub(r"^//\s*", "", c) for c in pending
                            if not re.match(r"^//[-=\s]*$", c)
                            and not re.match(r"^//\s+8\s+20", c)).strip()
            pending = []
            if m.group(2) == "INCOME":
                income = vals
                continue
            if cur is None:
                cur = {"title": "Curves", "rows": []}
                groups.append(cur)
            cur["rows"].append({"name": m.group(2), "values": vals,
                                "line": i + 1, "comment": trailing,
                                "desc": desc[:400]})
        elif CONST_RE.match(line) and cur is not None:
            c = CONST_RE.match(line)
            desc = " ".join(re.sub(r"^//\s*", "", x) for x in pending
                            if not re.match(r"^//[-=\s]*$", x)).strip()
            pending = []
            cur["rows"].append({"name": c.group(2), "scalar": True,
                                "value": c.group(3).strip(), "line": i + 1,
                                "comment": "", "desc": desc[:400]})
        elif re.match(r"^//\s*\d+[a-z]?\.\s", line):
            cur = {"title": re.sub(r"^//\s*", "", line).strip(), "rows": []}
            groups.append(cur)
            pending = []
        elif line.strip().startswith("//"):
            pending.append(line.strip())
        elif line.strip() == "":
            pending = []
    return {"income": income,
            "file": str(TARGETS_AS.relative_to(REPO)).replace(os.sep, "/"),
            "groups": [g for g in groups if g["rows"]]}


def set_target(lineno, name, old_values, new_values):
    """Edit floats of one array row in place, preserving alignment."""
    txt = TARGETS_AS.read_text(encoding="utf-8")
    lines = txt.split("\n")
    i = int(lineno) - 1
    m = ARRAY_RE.match(lines[i]) if 0 <= i < len(lines) else None
    if not m or m.group(2) != name:
        raise ValueError("line changed on disk; reload tunables")
    body = m.group(3)
    toks = list(re.finditer(r"-?[\d.]+f?", body))
    cur = [t.group().rstrip("f") for t in toks]
    if cur != [str(v).strip() for v in old_values] or len(new_values) != len(toks):
        raise ValueError("row changed on disk; reload tunables")
    out, last = [], 0
    for t, nv in zip(toks, new_values):
        v = float(nv)  # validates
        s = str(nv).strip()
        if "." not in s:
            s += ".0"
        out.append(body[last:t.start()] + s + "f")
        last = t.end()
    out.append(body[last:])
    lines[i] = m.group(1) + "".join(out) + m.group(4)
    TARGETS_AS.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    return {"ok": True}


def list_consts():
    out = []
    for f in sorted(SCRIPT_DIR.rglob("*.as")):
        rel = str(f.relative_to(REPO)).replace(os.sep, "/")
        try:
            lines = f.read_text(encoding="utf-8", errors="replace").split("\n")
        except Exception:
            continue
        for i, line in enumerate(lines):
            m = CONST_RE.match(line)
            if m:
                tail = m.group(4)
                cm = tail.split("//", 1)
                out.append({"file": rel, "line": i + 1, "name": m.group(2),
                            "value": m.group(3).strip(),
                            "comment": cm[1].strip() if len(cm) > 1 else ""})
    return out


def set_const(rel, lineno, name, old, new):
    p = (REPO / rel).resolve()
    if not str(p).startswith(str(SCRIPT_DIR.resolve()) + os.sep):
        raise ValueError("outside script dir")
    txt = p.read_text(encoding="utf-8")
    lines = txt.split("\n")
    i = int(lineno) - 1
    if i < 0 or i >= len(lines):
        raise ValueError("line out of range")
    m = CONST_RE.match(lines[i])
    if not m or m.group(2) != name or m.group(3).strip() != old.strip():
        raise ValueError("line changed on disk; reload tunables")
    new = str(new).strip()
    if not new or any(c in new for c in ";\r\n"):
        raise ValueError("bad value")
    lines[i] = m.group(1) + new + m.group(4)
    p.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    return {"ok": True}


def strip_jsonc(text):
    out, i, n, in_str = [], 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1]); i += 2; continue
            if c == '"':
                in_str = False
            i += 1
        elif c == '"':
            in_str = True; out.append(c); i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
        else:
            out.append(c); i += 1
    return "".join(out)


def config_path(name):
    if not re.fullmatch(r"[\w.-]+\.json", name):
        raise ValueError("bad name")
    p = CONFIG_DIR / name
    if not p.is_file():
        raise ValueError("no such config")
    return p


# ---------------------------------------------------------------- http

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

    def do_GET(self):
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
            elif u.path == "/api/games":
                kind = q.get("kind", "matches")
                self.send_json(list_matches() if kind == "matches"
                               else list_tournaments())
            elif u.path == "/api/game":
                d = safe_run_dir(q["dir"])
                if (d / "config.json").is_file() and (d / "matches").is_dir():
                    self.send_json(tournament_detail(d))
                else:
                    self.send_json(match_detail(d))
            elif u.path == "/api/launchmeta":
                self.send_json({"maps": known_maps(), "specs": known_ai_specs(),
                                "tunables": tunable_names()})
            elif u.path == "/api/jobs":
                with JOBS_LOCK:
                    items = list(JOBS.items())
                self.send_json([job_state(k, j) for k, j in
                                sorted(items, key=lambda kv: -kv[1]["started"])])
            elif u.path == "/api/job":
                with JOBS_LOCK:
                    j = JOBS.get(q.get("id"))
                self.send_json(job_state(q["id"], j) if j
                               else {"error": "unknown job"}, 200 if j else 404)
            elif u.path == "/api/tunables":
                self.send_json({"sections": parse_tunables(),
                                "targets": parse_targets()})
            elif u.path == "/api/config":
                p = config_path(q["name"])
                self.send_json({"name": q["name"],
                                "text": p.read_text(encoding="utf-8")})
            else:
                self.send_json({"error": "not found"}, 404)
        except Exception as e:
            self.send_json({"error": str(e)}, 400)

    def do_POST(self):
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
                else:
                    args = build_launch_cmd(p)
                    desc = "%s %s vs %s on %s" % (
                        p.get("mode", "headless"), p.get("a"), p.get("b"),
                        p.get("map"))
                self.send_json({"ok": True, "id": start_job(desc, args)})
            elif u.path == "/api/kill":
                self.send_json(kill_job(p.get("id")))
            elif u.path == "/api/const":
                self.send_json(set_const(p["file"], p["line"], p["name"],
                                         p["old"], p["new"]))
            elif u.path == "/api/target":
                self.send_json(set_target(p["line"], p["name"],
                                          p["old"], p["new"]))
            elif u.path == "/api/config":
                path = config_path(p["name"])
                text = p["text"]
                json.loads(strip_jsonc(text))  # validate before touching disk
                path.write_text(text, encoding="utf-8", newline="\n")
                self.send_json({"ok": True})
            else:
                self.send_json({"error": "not found"}, 404)
        except Exception as e:
            self.send_json({"error": str(e)}, 400)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, default=8420)
    ap.add_argument("--no-browser", action="store_true")
    a = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), Handler)
    url = "http://127.0.0.1:%d" % a.port
    print("bar-ai dashboard: %s   (Ctrl+C to stop)" % url)
    if not a.no_browser:
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
