#!/usr/bin/env python3
"""Public replays of strong players, for learning army control (todo/learn-army-from-replays.md).

    python tools/public_replays.py pick [--preset duel|team] [--pages 20] [--min-os 30] [--min-minutes 6] [--max-minutes 60]
    python tools/public_replays.py fetch [--limit N]          demos, then missing maps and game versions
    python tools/public_replays.py record [--workers 3] [--limit N]
    python tools/public_replays.py status

pick pages BAR's replay service (api.bar-rts.com/replays, newest first) and judges each game's detail: no AIs,
ended normally, no unit tweaks, start metal 1000, length in range, every player's rating (OS) at or above the floor.
One line per game judged in ROOT/manifest.jsonl (kept or why not); re-running adds new games only.

Everything downloaded lives under ROOT (G:/bar-ai-archive/public-replays): demos/ and a separate engine data
folder data/ for maps and game versions his install lacks, read beside his install's data by the replay run.
His install is never written to (fetching a game version there moves the byar:test tag his lobby uses).
"""
import glob
import gzip
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402

API = "https://api.bar-rts.com/replays"
DEMO_URL = "https://storage.uk.cloud.ovh.net/v1/AUTH_10286efc0d334efd917d476d7183232e/BAR/demos/"
ROOT = Path("G:/bar-ai-archive/public-replays")
MANIFEST = ROOT / "manifest.jsonl"
UA = {"User-Agent": "bar-ai replay research"}
PRD_ENV = {"PRD_RAPID_USE_STREAMER": "false", "PRD_RAPID_REPO_MASTER": "https://repos-cdn.beyondallreason.dev/repos.gz",
           "PRD_HTTP_SEARCH_URL": "https://files-cdn.beyondallreason.dev/find"}


def get(url, tries=4):
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=90) as r:
                return json.loads(r.read())
        except Exception as e:  # the service is slow at times
            if i == tries - 1:
                raise
            time.sleep(5 * (i + 1))


LONG_MIN, LONG_OS = 25.0, 20.0


def os_of(p):
    try:
        return float(str(p.get("skill", "")).strip("[]"))
    except ValueError:
        return None


def data_dirs():
    env = bar_env.load()
    return [env.data, ROOT / "data"]


def installed_versions():
    names = set()
    for d in data_dirs():
        packages = {Path(p).stem for p in glob.glob(str(d / "packages" / "*.sdp"))}
        for path in glob.glob(str(d / "rapid" / "*" / "*" / "versions.gz")):
            with gzip.open(path, "rt", errors="replace") as f:
                for line in f:
                    parts = line.rstrip("\n").split(",")
                    if len(parts) >= 4 and parts[1] in packages:
                        names.add(parts[3])
    return names


def installed_maps():
    out = set()
    for d in data_dirs():
        out |= {Path(p).stem.lower() for p in glob.glob(str(d / "maps" / "*.sd[7z]"))}
    return out


def installed_engines():
    return {Path(p).name.replace("recoil_", "") for p in glob.glob(str(bar_env.load().data / "engine" / "recoil_*"))}


def judge(d, min_os, min_minutes, max_minutes):
    if d.get("hasBots"):
        return "bots"
    if not d.get("gameEndedNormally"):
        return "not ended normally"
    s = d.get("gameSettings") or {}
    if s.get("tweakunits") or s.get("tweakdefs"):
        return "tweaked units"
    if str(s.get("startmetal", "1000")) != "1000":
        return "start metal %s" % s.get("startmetal")
    minutes = (d.get("durationMs") or 0) / 60000
    if not min_minutes <= minutes <= max_minutes:
        return "%.1f minutes" % minutes
    players = [p for a in d.get("AllyTeams") or [] for p in a.get("Players") or []]
    if not players:
        return "no players"
    # long games keep down to OS 20 (11-21: the army model has barely seen the late game; training weights each
    # player's orders by skill, 0.25 at OS 20 and 1.0 at 35, so weaker players teach less, not nothing)
    floor = min(min_os, LONG_OS) if minutes > LONG_MIN else min_os
    low = [p for p in players if os_of(p) is None or os_of(p) < floor]
    if low and minutes > LONG_MIN and len(players) > 2:
        # a long team game is judged by its median player (11-21: one weak player of 16 turned away 1,477 long
        # games; each order is weighted by how its moment went, so a weak player's bad orders teach little)
        rated = sorted(os_of(p) or 0 for p in players)
        low = [] if rated[len(rated) // 2] >= floor else low
    if low:
        return "OS below %s: %d of %d" % (floor, len(low), len(players))
    if d.get("engineVersion") not in installed_engines():
        return "engine %s not installed" % d.get("engineVersion")
    return None


def line_of(d, why):
    teams = []
    for a in d.get("AllyTeams") or []:
        teams.append({"ally": a.get("allyTeamId"), "won": a.get("winningTeam"),
                      "players": [{"name": p.get("name"), "team": p.get("teamId"), "os": os_of(p),
                                   "faction": p.get("faction")} for p in a.get("Players") or []]})
    m = d.get("Map") or {}
    return {"id": d["id"], "start": d.get("startTime"), "minutes": round((d.get("durationMs") or 0) / 60000, 1),
            "preset": d.get("preset"), "file": d.get("fileName"), "game": d.get("gameVersion"),
            "engine": d.get("engineVersion"), "map_script": m.get("scriptName"), "map_file": m.get("fileName"),
            "ranked": (d.get("gameSettings") or {}).get("ranked_game"), "teams": teams, "keep": why is None,
            "why": why}


def load():
    if not MANIFEST.exists():
        return []
    return [json.loads(l) for l in open(MANIFEST, encoding="utf-8") if l.strip()]


def save(rows):
    tmp = MANIFEST.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    os.replace(tmp, MANIFEST)


def pick(preset, pages, min_os, min_minutes, max_minutes):
    ROOT.mkdir(parents=True, exist_ok=True)
    rows = load()
    seen = {r["id"] for r in rows}
    kept = 0
    for page in range(1, pages + 1):
        q = {"page": page, "limit": 50, "preset": preset, "hasBots": "false"}
        data = get(API + "?" + urllib.parse.urlencode(q)).get("data") or []
        if not data:
            break
        new = 0
        for row in data:
            if row["id"] in seen:
                continue
            minutes = (row.get("durationMs") or 0) / 60000
            if not min_minutes <= minutes <= max_minutes:
                continue
            d = get(API + "/" + row["id"])
            ln = line_of(d, judge(d, min_os, min_minutes, max_minutes))
            rows.append(ln)
            seen.add(row["id"])
            kept += ln["keep"]
            new += 1
            time.sleep(0.3)
        save(rows)
        print("page %d: %d judged, %d kept so far" % (page, new, kept), flush=True)
    print("manifest %d games, %d kept" % (len(rows), sum(r["keep"] for r in rows)))


def prd(args):
    exe = sorted(glob.glob(str(bar_env.load().data / "engine" / "recoil_*" / "pr-downloader.exe")))[-1]
    (ROOT / "data").mkdir(parents=True, exist_ok=True)
    return subprocess.run([exe, "--filesystem-writepath", str(ROOT / "data")] + args,
                          env={**os.environ, **PRD_ENV}, check=False).returncode


def fetch(limit=None):
    rows = load()
    kept = [r for r in rows if r["keep"]]
    (ROOT / "demos").mkdir(parents=True, exist_ok=True)
    n = 0
    for r in kept:
        path = ROOT / "demos" / r["file"]
        if path.exists() and path.stat().st_size > 0:
            continue
        if limit and n >= limit:
            break
        url = DEMO_URL + urllib.parse.quote(r["file"])
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=180) as src:
            data = src.read()
        path.with_suffix(".part").write_bytes(data)
        os.replace(path.with_suffix(".part"), path)
        n += 1
        time.sleep(0.3)
    print("%d demos fetched" % n, flush=True)
    have = installed_maps()
    for script, fname in sorted({(r["map_script"], r["map_file"]) for r in kept}):
        if (fname or "").lower() not in have:
            prd(["--download-map", script])
    have = installed_versions()
    for v in sorted({r["game"] for r in kept} - have):
        if "$VERSION" not in v:
            prd(["--download-game", v])
    missing = sorted({r["game"] for r in kept} - installed_versions())
    print("game versions still missing:", missing or "none")


def record(workers=3, limit=None):
    import replay_orders
    rows = [r for r in load() if r["keep"] and (ROOT / "demos" / r["file"]).exists()]
    have = installed_versions()
    # longest first (11-21: the army model matches our own army to minute 20 and falls apart after; only 4% of the
    # players' orders came after minute 30)
    todo = sorted((r for r in rows if r["game"] in have
                   and not (ROOT / "recordings" / Path(r["file"]).stem / "orders.txt.gz").exists()),
                  key=lambda r: -(r.get("minutes") or 0))
    if limit:
        todo = todo[:limit]
    replay_orders.batch_list([ROOT / "demos" / r["file"] for r in todo], workers, ROOT / "recordings",
                             extra_data=ROOT / "data")


def status():
    rows = load()
    kept = [r for r in rows if r["keep"]]
    print("judged %d, kept %d" % (len(rows), len(kept)))
    why = {}
    for r in rows:
        if not r["keep"]:
            k = r["why"].split(":")[0]
            why[k] = why.get(k, 0) + 1
    print("turned away:", sorted(why.items(), key=lambda kv: -kv[1])[:8])
    print("kept by preset:", {p: sum(r["preset"] == p for r in kept) for p in {r["preset"] for r in kept}})
    print("demos on disk:", sum((ROOT / "demos" / r["file"]).exists() for r in kept))
    print("recorded:", sum((ROOT / "recordings" / Path(r["file"]).stem / "orders.txt.gz").exists() for r in kept))


def main(a):
    def opt(name, default):
        return a[a.index(name) + 1] if name in a else default
    if a[:1] == ["pick"]:
        pick(opt("--preset", "duel"), int(opt("--pages", "20")), float(opt("--min-os", "30")),
             float(opt("--min-minutes", "6")), float(opt("--max-minutes", "60")))
    elif a[:1] == ["fetch"]:
        fetch(int(opt("--limit", "0")) or None)
    elif a[:1] == ["record"]:
        record(int(opt("--workers", "3")), int(opt("--limit", "0")) or None)
    elif a[:1] == ["follow"]:
        idle = 0
        while idle < 3:
            before = sum(1 for r in load() if r["keep"])
            fetch()
            record(int(opt("--workers", "3")), 60)
            done = sum((ROOT / "recordings" / Path(r["file"]).stem / "orders.txt.gz").exists() for r in load() if r["keep"])
            idle = idle + 1 if done >= sum(1 for r in load() if r["keep"]) and before == sum(1 for r in load() if r["keep"]) else 0
            if idle:
                time.sleep(600)
    elif a[:1] == ["status"]:
        status()
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
