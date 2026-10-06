#!/usr/bin/env python3
"""The audit's running tally: one entry per issue CODE (an audit check's name),
counting the games that flagged it out of the games audited, split by kind
(watch = his windowed games, batch = headless). Each game's full audit stays in
its own match dir (audit.txt); this file only aggregates, so it never grows past
one entry per check.

    python tools/audit_record.py              # the table, worst first
    python tools/audit_record.py --kind watch # his games only
    python tools/audit_record.py --reset      # start the tally over (old file kept)

audit.py --record [--kind watch|batch] adds a game; run_match does it after
every match.
"""
import json
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILE = ROOT / "runtime" / "audit" / "issues.json"
LOCK = FILE.with_suffix(".lock")
KEEP_GAMES = 400   # match names remembered so a re-audit does not count twice


def _locked(fn):
    FILE.parent.mkdir(parents=True, exist_ok=True)
    for _ in range(200):
        try:
            fd = os.open(str(LOCK), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            break
        except FileExistsError:
            if time.time() - LOCK.stat().st_mtime > 60:
                LOCK.unlink(missing_ok=True)
            time.sleep(0.1)
    else:
        return None
    try:
        return fn()
    finally:
        os.close(fd)
        LOCK.unlink(missing_ok=True)


def _load():
    try:
        return json.loads(FILE.read_text())
    except (OSError, ValueError):
        return {"games": [], "issues": {}}


def record(match, rows, kind):
    """rows: (section, ok, code, detail) from audit.Report. Returns the codes flagged."""
    name = Path(match).name
    flagged = [code for _s, ok, code, _d in rows if not ok]

    def upd():
        db = _load()
        if name in db["games"]:
            return
        db["games"] = (db["games"] + [name])[-KEEP_GAMES:]
        now = time.strftime("%Y-%m-%d %H:%M")
        for sec, ok, code, detail in rows:
            e = db["issues"].setdefault(code, {"section": sec, "first": now})
            k = e.setdefault(kind, {"audited": 0, "flagged": 0})
            k["audited"] += 1
            if not ok:
                k["flagged"] += 1
                e["last"] = {"when": now, "kind": kind, "match": name, "detail": detail[:300]}
        tmp = FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(db, indent=1))
        os.replace(tmp, FILE)

    _locked(upd)
    return flagged


def table(kind=None):
    db = _load()
    rows = []
    for code, e in db["issues"].items():
        kinds = [kind] if kind else [k for k in ("watch", "batch") if k in e]
        aud = sum(e.get(k, {}).get("audited", 0) for k in kinds)
        fl = sum(e.get(k, {}).get("flagged", 0) for k in kinds)
        if aud and fl:
            rows.append((fl / aud, fl, aud, code, e))
    rows.sort(key=lambda r: (-r[0], -r[1]))
    print("issue tally (%s), %d games recorded -- flagged/audited, latest evidence" % (kind or "all", len(db["games"])))
    for share, fl, aud, code, e in rows:
        w = e.get("watch", {})
        last = e.get("last", {})
        print("  %3.0f%% %3d/%-3d %-30s watch %d/%d  | %s" % (
            100 * share, fl, aud, code, w.get("flagged", 0), w.get("audited", 0), last.get("detail", "")[:110]))


def main(argv):
    if "--reset" in argv:
        if FILE.exists():
            FILE.rename(FILE.with_name("issues-%s.json" % time.strftime("%Y%m%d-%H%M%S")))
        print("tally reset")
        return 0
    kind = argv[argv.index("--kind") + 1] if "--kind" in argv else None
    table(kind)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
