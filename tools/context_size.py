#!/usr/bin/env python3
"""What does this repo cost to read?

Agentic coding pays for the repo in tokens, and the bill is dominated by prose
that is not code. This reports the bill per area, splitting every source file
into code, comment and blank, so a documentation cull can be judged the way a
behaviour change is: baseline, change, measure.

    python tools/context_size.py                  # the table
    python tools/context_size.py --top 20         # worst files by comment lines
    python tools/context_size.py --area live-as   # one area, per-file
    python tools/context_size.py --save           # stamp a baseline
    python tools/context_size.py --since          # diff against the baseline

Token counts are bytes/4 -- close enough for prose and code, and the point is
the ratio between runs, not the absolute.
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BASELINE = REPO / "tools" / ".context_size.json"

# Ordered: first match wins, so the specific paths precede the general ones.
AREAS = [
    ("live-as", "AS   ai/Unstable game-side",
     lambda f: f.startswith("ai/Unstable/game-side") and f.endswith(".as")),
    ("live-json", "JSON ai/Unstable",
     lambda f: f.startswith("ai/Unstable") and f.endswith(".json")),
    ("frozen", "FROZEN ai/{ord,ctl,stk}",
     lambda f: f.split("/")[:2] in (["ai", "ord"], ["ai", "ctl"], ["ai", "stk"])),
    ("cpp", "CPP  cpp/src", lambda f: f.startswith("cpp/src")),
    ("tools", "PY   tools/", lambda f: f.startswith("tools/")),
    ("docs", "MD   docs/", lambda f: f.startswith("docs/")),
    ("skills", "MD   .claude/skills", lambda f: f.startswith(".claude/")),
    ("history", "MD   changes+notes",
     lambda f: f.startswith(("changes/", "notes/"))),
    ("reference", "REF  reference/", lambda f: f.startswith("reference/")),
    ("patches", "LUA  game-patches/", lambda f: f.startswith("game-patches/")),
    ("rootmd", "MD   root", lambda f: f.endswith(".md") and "/" not in f),
    ("other", "other", lambda f: True),
]

CODE_EXT = {"as", "cpp", "h", "hpp", "py", "lua", "json", "md", "txt", "cfg", "sh"}


def split_c(lines):
    """// and /* */ -- AngelScript, C++."""
    code = com = blank = 0
    inblk = False
    for raw in lines:
        s = raw.strip()
        if inblk:
            com += 1
            if "*/" in s:
                inblk = False
        elif not s:
            blank += 1
        elif s.startswith("//"):
            com += 1
        elif s.startswith("/*"):
            com += 1
            if "*/" not in s:
                inblk = True
        else:
            code += 1
    return code, com, blank


def split_py(lines):
    """# and the docstrings that stand alone on their own line."""
    code = com = blank = 0
    quote = None
    for raw in lines:
        s = raw.strip()
        if quote:
            com += 1
            if quote in s:
                quote = None
        elif not s:
            blank += 1
        elif s.startswith("#"):
            com += 1
        elif s[:3] in ('"""', "'''"):
            q = s[:3]
            com += 1
            if not (len(s) > 3 and s.endswith(q)):
                quote = q
        else:
            code += 1
    return code, com, blank


def split_lua(lines):
    code = com = blank = 0
    for raw in lines:
        s = raw.strip()
        if not s:
            blank += 1
        elif s.startswith("--"):
            com += 1
        else:
            code += 1
    return code, com, blank


def split_prose(lines):
    # Markdown and config have no comment layer to cull, only the whole file.
    return len(lines), 0, 0


SPLIT = {"as": split_c, "cpp": split_c, "h": split_c, "hpp": split_c,
         "py": split_py, "lua": split_lua}


def scan():
    out = subprocess.run(["git", "ls-files"], cwd=REPO,
                         capture_output=True, text=True, check=True).stdout
    rows = []
    for f in out.splitlines():
        ext = f.rsplit(".", 1)[-1].lower() if "." in f else ""
        if ext not in CODE_EXT:
            continue
        try:
            text = (REPO / f).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        lines = text.splitlines()
        code, com, blank = SPLIT.get(ext, split_prose)(lines)
        combytes = 0
        if ext in SPLIT:
            combytes = sum(len(L) + 1 for L in lines
                           if L.strip().startswith(("//", "#", "--")))
        rows.append({"f": f, "ext": ext, "bytes": len(text), "total": len(lines),
                     "code": code, "com": com, "blank": blank,
                     "combytes": combytes,
                     "area": next(k for k, _, m in AREAS if m(f))})
    return rows


def aggregate(rows):
    agg = {}
    for r in rows:
        a = agg.setdefault(r["area"], dict(files=0, total=0, code=0, com=0,
                                           bytes=0, combytes=0))
        a["files"] += 1
        for k in ("total", "code", "com", "bytes", "combytes"):
            a[k] += r[k]
    return agg


def table(agg, prev=None):
    hdr = "%-28s%6s%8s%8s%8s%6s%7s" % (
        "area", "files", "lines", "code", "comment", "com%", "~ktok")
    if prev:
        hdr += "%8s" % "d ktok"
    print(hdr)
    print("-" * len(hdr))
    tot = dict(files=0, total=0, code=0, com=0, bytes=0)
    for key, label, _ in AREAS:
        a = agg.get(key)
        if not a:
            continue
        pct = 100 * a["com"] / max(1, a["code"] + a["com"])
        line = "%-28s%6d%8d%8d%8d%5.0f%%%7.0f" % (
            label, a["files"], a["total"], a["code"], a["com"], pct,
            a["bytes"] / 4096)
        if prev:
            line += "%+8.0f" % ((a["bytes"] - prev.get(key, {}).get("bytes", 0))
                                / 4096)
        print(line)
        for k in tot:
            tot[k] += a[k]
    print("-" * len(hdr))
    pct = 100 * tot["com"] / max(1, tot["code"] + tot["com"])
    line = "%-28s%6d%8d%8d%8d%5.0f%%%7.0f" % (
        "TOTAL", tot["files"], tot["total"], tot["code"], tot["com"], pct,
        tot["bytes"] / 4096)
    if prev:
        was = sum(v.get("bytes", 0) for v in prev.values())
        line += "%+8.0f" % ((tot["bytes"] - was) / 4096)
    print(line)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, metavar="N",
                    help="worst N files by comment lines")
    ap.add_argument("--area", help="restrict --top to one area key")
    ap.add_argument("--save", action="store_true", help="write the baseline")
    ap.add_argument("--since", action="store_true", help="diff vs the baseline")
    args = ap.parse_args()

    rows = scan()
    agg = aggregate(rows)

    prev = None
    if args.since:
        if not BASELINE.exists():
            print("no baseline at %s -- run --save first"
                  % BASELINE.relative_to(REPO))
            return 1
        prev = json.loads(BASELINE.read_text())["areas"]

    table(agg, prev)

    live = agg.get("live-as")
    if live and live["bytes"]:
        print("\nlive AI comment share by BYTES: %.0fKB of %.0fKB "
              "(%.0f%%, ~%.0fk tok of prose)"
              % (live["combytes"] / 1024, live["bytes"] / 1024,
                 100 * live["combytes"] / live["bytes"],
                 live["combytes"] / 4096))

    if args.top:
        sel = [r for r in rows
               if (not args.area or r["area"] == args.area) and r["com"]]
        print("\n%6s%6s%6s  file" % ("com", "code", "com%"))
        for r in sorted(sel, key=lambda r: -r["com"])[:args.top]:
            pct = 100 * r["com"] / max(1, r["com"] + r["code"])
            print("%6d%6d%5.0f%%  %s" % (r["com"], r["code"], pct, r["f"]))

    if args.save:
        head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=REPO,
                              capture_output=True, text=True).stdout.strip()
        BASELINE.write_text(json.dumps({"areas": agg, "stamp": head}, indent=1))
        print("\nbaseline written to %s" % BASELINE.relative_to(REPO))
    return 0


if __name__ == "__main__":
    sys.exit(main())
