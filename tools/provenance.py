"""What code a test ran (his 11-13: save the results, the commit they ran and every detail).

capture() reads the repo: HEAD, branch, and the uncommitted work as one patch (tracked changes plus the untracked
files under the AI, C++, gadget and scenario trees), saved once to results/patches/<sha>.patch so the exact code
stays recoverable after the tree moves on. deploy_ai.py writes it beside every deployed variant as provenance.json;
run_match.py copies each AI's into result.json. tools/ledger.py turns runs into results/ledger.md entries.
"""
from __future__ import annotations

import hashlib
import json
import subprocess
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PATCHES = REPO / "results" / "patches"
ROOTS = ("ai/Unstable", "cpp", "game-patches", "tools")
FILE = "provenance.json"


def _git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=REPO, capture_output=True, text=True, encoding="utf-8",
                          errors="replace").stdout


def capture() -> dict:
    head = _git("rev-parse", "HEAD").strip()
    branch = _git("rev-parse", "--abbrev-ref", "HEAD").strip()
    patch = _git("diff", "--binary", "HEAD", "--", *ROOTS)
    untracked = [p for p in _git("ls-files", "--others", "--exclude-standard", "--", *ROOTS).splitlines() if p]
    for p in sorted(untracked):
        f = REPO / p
        if f.is_file() and f.stat().st_size < 2_000_000:
            patch += subprocess.run(["git", "diff", "--no-index", "--binary", "/dev/null", p], cwd=REPO,
                                    capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
    sha = hashlib.sha256(patch.encode("utf-8", "replace")).hexdigest()[:12] if patch else ""
    if sha:
        PATCHES.mkdir(parents=True, exist_ok=True)
        out = PATCHES / f"{head[:10]}-{sha}.patch"
        if not out.exists():
            out.write_text(patch, encoding="utf-8")
    return {"head": head, "branch": branch, "dirty": bool(patch), "diff_sha": sha,
            "patch": f"results/patches/{head[:10]}-{sha}.patch" if sha else "",
            "captured": datetime.now().isoformat(timespec="seconds")}


def write(dirs, **extra) -> dict:
    p = dict(capture(), **extra)
    for d in dirs:
        d = Path(d)
        if d.is_dir():
            (d / FILE).write_text(json.dumps(p, indent=2), encoding="utf-8")
    return p


def read(d) -> dict | None:
    f = Path(d) / FILE
    if f.is_file():
        try:
            return json.loads(f.read_text(encoding="utf-8"))
        except ValueError:
            return None
    return None


def label(p: dict | None) -> str:
    if not p:
        return "?"
    if p.get("release"):
        return p["release"]
    return p["head"][:10] + ("+" + p["diff_sha"] if p.get("dirty") else "")


if __name__ == "__main__":
    print(json.dumps(capture(), indent=2))
