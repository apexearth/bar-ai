"""Compare lag across maps: one row per match directory.

frame   whole sim frame in ms (wall per frame from frametime), median and worst minute after min 5
ai%     our AIs' share of that frame at the worst minute; aiPF = ms per AI per frame there
units   peak unit count
path    work:pathOne total CPU seconds, queries, mean us -- our AI's path queries on the worker pool
stuck   unstick-nudge + stuck-com + stuckwatch lines; unreach = BuilderTask reach refusals
apm     move+fight+patrol orders per AI per minute, mean over the last 5 minutes

Usage: maplag.py <dir-of-matches>   (each subdir needs infolog.txt and <subdir>.ft.txt beside it)
"""
import re
import statistics
import sys
from pathlib import Path

MIN_RE = re.compile(r"^\s*(\d+)\s+([0-9.]+)\s+(\d+)\s+(\d+)\s+([0-9.]+)%")
WORK_RE = re.compile(r"^\s*work:pathOne\s+(\d+)\s+(\d+)\s+(\d+)")
PER_AI = re.compile(r"per AI per frame\s+([0-9.]+) ms")
WORST = re.compile(r"worst game-minute \(min (\d+), (\d+) AI")
ORD = re.compile(r"\[f=(\d+)\].*apex: orders t=\d+ move=(\d+) fight=(\d+) patrol=(\d+)")


def row(d: Path):
    ft = d.parent / (d.name + ".ft.txt")
    txt = ft.read_text(encoding="utf-8", errors="replace") if ft.exists() else ""
    mins = []
    path = (0, 0, 0)
    for line in txt.splitlines():
        m = MIN_RE.match(line)
        if m:
            mins.append((int(m.group(1)), float(m.group(2)), int(m.group(3)), int(m.group(4)), float(m.group(5))))
            continue
        m = WORK_RE.match(line)
        if m:
            path = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
    late = [x for x in mins if x[0] > 5]
    frames = [x[1] for x in late] or [0.0]
    worst = max(late, key=lambda x: x[1]) if late else (0, 0, 0, 0, 0)
    pa = PER_AI.search(txt)
    log = d / "infolog.txt"
    stuck = unreach = 0
    apm = {}
    last = 0
    if log.exists():
        with open(log, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if ("apex: unstick-nudge" in line) or ("apex: stuck-com" in line) or ("apex: stuckwatch" in line):
                    stuck += 1
                elif "apex: unreach " in line:
                    unreach += 1
                else:
                    m = ORD.search(line)
                    if m:
                        mi = int(m.group(1)) // 1800
                        apm.setdefault(mi, []).append(int(m.group(2)) + int(m.group(3)) + int(m.group(4)))
                        last = max(last, mi)
    a = [v for k, vs in apm.items() if k >= last - 4 for v in vs]
    return {
        "map": d.name, "mins": len(mins),
        "frameMed": statistics.median(frames), "frameWorst": max(frames), "worstMin": worst[0],
        "aiPct": worst[4], "aiPF": float(pa.group(1)) if pa else 0.0,
        "units": max((x[2] for x in mins), default=0),
        "pathS": path[0] / 1000.0, "pathN": path[1], "pathUs": path[2],
        "stuck": stuck, "unreach": unreach, "apm": (sum(a) / len(a)) if a else 0.0,
    }


def main():
    root = Path(sys.argv[1])
    rows = [row(d) for d in sorted(root.iterdir()) if d.is_dir()]
    print("%-28s %4s %8s %8s %5s %6s %6s %6s %8s %8s %6s %6s %6s %6s" % (
        "map", "min", "frameMed", "frameMax", "atMin", "ai%", "aiPF", "units", "pathS", "pathN", "pathUs",
        "stuck", "unrch", "apm"))
    for r in rows:
        print("%-28s %4d %8.1f %8.1f %5d %5.1f%% %6.3f %6d %8.1f %8d %6d %6d %6d %6.0f" % (
            r["map"][:28], r["mins"], r["frameMed"], r["frameWorst"], r["worstMin"], r["aiPct"], r["aiPF"],
            r["units"], r["pathS"], r["pathN"], r["pathUs"], r["stuck"], r["unreach"], r["apm"]))


if __name__ == "__main__":
    main()
