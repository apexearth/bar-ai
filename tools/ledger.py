"""The results record (his 11-13: save the test results, the commit they ran and every detail; organised, not one file).

    python tools/ledger.py add --topic TOPIC --title "..." --purpose "..." [--verdict "..."] [--us SPEC] RUN [RUN ...]
    python tools/ledger.py index

Layout:
    results/README.md                   the index: one row per batch, grouped by topic, newest first (generated)
    results/<topic>/<date>-<slug>.md    one page per batch: purpose, code, settings, command, summary, every game
    results/patches/<head>-<sha>.patch  the uncommitted code a batch ran (tools/provenance.py)

RUN is a tournament dir, a match dir, or a glob of match dirs. Results are OUR side's (--us, a spec substring),
counted by seat: tournaments alternate seats, and the test turtle shares our spec name. Adding a batch with the
same topic, date and title again rewrites its page (a batch that finished after a partial entry).
Games run before 11-13 carry no code record: say what ran in --purpose.
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import re
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

import provenance

REPO = Path(__file__).resolve().parent.parent
RESULTS = REPO / "results"
INDEX = RESULTS / "README.md"
STATS = re.compile(r"\[BARAI_STATS\] team=(\d+) ally=(\d+) .*?frame=(\d+) .*? mInc=([-\d.]+)")
META = re.compile(r"^<!-- meta (\{.*\}) -->$", re.M)


def games(runs):
    for r in runs:
        p = Path(r)
        if (p / "matches").is_dir():
            yield from sorted(x for x in (p / "matches").iterdir() if (x / "result.json").is_file())
        elif (p / "result.json").is_file():
            yield p
        else:
            yield from sorted(Path(x) for x in glob.glob(r) if (Path(x) / "result.json").is_file())


def income(d: Path):
    last, at20 = {}, {}
    f = d / "infolog.txt"
    if not f.is_file():
        return None, None
    for ln in f.open(encoding="utf-8", errors="replace"):
        h = STATS.search(ln)
        if h:
            last[h.group(1)] = (int(h.group(2)), float(h.group(4)))
            if int(h.group(3)) <= 36060:
                at20[h.group(1)] = (int(h.group(2)), float(h.group(4)))

    def ratio(m):
        s = Counter()
        for a, v in m.values():
            s[a] += v
        return math.log(s[0] / s[1]) if s[0] > 0 and s[1] > 0 else None
    return ratio(at20), ratio(last)


def rel(d: Path) -> str:
    dd = d.resolve()
    return dd.relative_to(REPO).as_posix() if REPO in dd.parents else str(d)


def read_game(d: Path, us: str) -> dict:
    r = json.loads((d / "result.json").read_text(encoding="utf-8"))
    teams = [t for t in r.get("teams", []) if not t.get("extra")]
    mine = [i for i, t in enumerate(teams) if us in t["spec"]]
    ally = mine[0] if mine else 0
    w = r["result"].get("winners") or []
    i20, iend = income(d)
    if ally == 1:
        i20 = -i20 if i20 is not None else None
        iend = -iend if iend is not None else None
    if w:
        out = "W" if ally in w else "L"
    else:
        out = "w" if (iend or 0) > 0 else ("l" if iend is not None else "-")
    prov = r.get("provenance") or {}
    return dict(dir=rel(d), us=teams[ally]["spec"] if teams else "?",
                ver=(teams[ally].get("version") or teams[ally]["spec"]) if teams else "?",
                them=", ".join(sorted({t["spec"] for i, t in enumerate(teams) if i != ally})) or "?",
                map=r.get("map"), sides="/".join(dict.fromkeys(r.get("sides") or [])), seed=r.get("seed"),
                hc=r.get("handicap"), cap=r.get("minutes_cap"), mins=r["result"].get("game_minutes"), out=out,
                i20=i20, seat=ally, code={k: provenance.label(v) for k, v in prov.items()}, argv=r.get("argv"))


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")[:60]


def fmt_x(v):
    return f"x{math.exp(v):.2f}" if v is not None else "-"


def add(args):
    rows = [read_game(d, args.us) for d in games(args.runs)]
    if not rows:
        raise SystemExit("no games found")
    out = Counter(x["out"] for x in rows)
    i20 = [x["i20"] for x in rows if x["i20"] is not None]
    code = Counter((k, v) for x in rows for k, v in x["code"].items())
    date = args.date or datetime.now().strftime("%Y-%m-%d")
    summary = (f"{len(rows)} games: won {out['W']}, lost {out['L']}, timeouts ahead {out['w']}, behind {out['l']}"
               + (f"; income at 20 min {fmt_x(sum(i20) / len(i20))} ours/theirs" if i20 else ""))
    meta = dict(date=date, topic=args.topic, title=args.title, games=len(rows), W=out["W"], L=out["L"], w=out["w"],
                l=out["l"], inc20=round(math.exp(sum(i20) / len(i20)), 2) if i20 else None, verdict=args.verdict)
    page = [
        f"<!-- meta {json.dumps(meta)} -->",
        f"# {args.title}",
        "",
        f"- **Date:** {date}",
        f"- **Topic:** {args.topic}",
        f"- **Purpose:** {args.purpose}",
        f"- **Result:** {summary}",
    ]
    if args.verdict:
        page.append(f"- **Verdict:** {args.verdict}")
    page += [
        f"- **Ours:** {', '.join(sorted({x['us'] for x in rows}))}",
        f"- **Opponents:** {', '.join(sorted({x['them'] for x in rows}))}",
        "- **Code:** " + ("; ".join(f"{k} = `{v}` ({n} games)" for (k, v), n in sorted(code.items()))
                          or "not recorded (games before the code record, 11-13); see Purpose"),
        f"- **Maps:** {', '.join(sorted({str(x['map']) for x in rows}))}",
        f"- **Sides:** {', '.join(sorted({x['sides'] for x in rows}))}; **bonus:** "
        f"{', '.join(sorted({str(x['hc']) for x in rows}))}; **time cap:** "
        f"{', '.join(sorted({str(x['cap']) for x in rows}))} min",
        f"- **Runs:** {', '.join(sorted({str(Path(x['dir']).parent.parent) if Path(x['dir']).parent.name == 'matches' else x['dir'] for x in rows}))}",
    ]
    if rows[0].get("argv"):
        page.append(f"- **Command (first game):** `run_match.py {' '.join(rows[0]['argv'])}`")
    page += ["", "Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.",
             "", "| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    for i, x in enumerate(rows):
        page.append(f"| {i} | {x['map']} | {x['sides']} | {x['seed']} | {x['seat']} | {x['out']} | "
                    f"{x['mins'] if x['mins'] is not None else '-'} | {fmt_x(x['i20'])} | "
                    f"{', '.join(sorted(set(x['code'].values()))) or '-'} | `{x['dir']}` |")
    # THE BEHAVIOUR CONTRACT on every page (his 11-14: validate every game so regressions cannot slip in)
    try:
        import contextlib
        import io
        import contract
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = contract.main([x["dir"] for x in rows] + ["--md"])
        if rc in (0, 1):
            page += ["", "## Behaviour contract", "", "Ours against the release seats in these same games "
                     "(`tools/contract.py`). FAIL = worse than the release past the noise margin.", "",
                     buf.getvalue().rstrip()]
            print("contract: " + ("FAIL" if rc else "PASS") + " (table on the page)")
    except Exception as e:   # a contract that cannot run must say so, not vanish
        page += ["", "## Behaviour contract", "", f"not run: {e}"]
        print(f"contract: not run ({e})")
    # ANOMALIES: a seat unlike the release's normal play in the same regime (his 11-14 anomaly detector)
    try:
        import contextlib
        import io
        import anomaly
        buf2 = io.StringIO()
        with contextlib.redirect_stdout(buf2):
            # the detector matches a seat by its version name (lane-estall, v0.5.11), not the spec --us names
            anomaly.main(["check"] + [x["dir"] for x in rows] + ["--ai", rows[0]["ver"]])
        page += ["", "## Anomalies", "", "Seats far outside the release's normal play in the same regime "
                 "(`tools/anomaly.py`, robust z >= 5 against every finished release seat).", "", "```",
                 buf2.getvalue().rstrip(), "```"]
        print("anomaly: " + buf2.getvalue().splitlines()[0] if buf2.getvalue() else "anomaly: no output")
    except Exception as e:
        page += ["", "## Anomalies", "", f"not run: {e}"]
    text = "\n".join(page) + "\n"
    if args.dry:
        print(text)
        return
    p = RESULTS / slug(args.topic) / f"{date}-{slug(args.title)}.md"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")
    index()
    print(f"{p.relative_to(REPO).as_posix()}: {summary}")


def index(_args=None):
    by_topic = defaultdict(list)
    for p in sorted(RESULTS.glob("*/*.md")):
        m = META.search(p.read_text(encoding="utf-8"))
        if m:
            by_topic[m and json.loads(m.group(1))["topic"]].append((json.loads(m.group(1)), p))
    out = ["# Test results", "",
           "One page per test batch, written by `python tools/ledger.py add` (CLAUDE.md). Results are ours, counted by",
           "seat. W/L = decided games; w/l = time-capped games ahead/behind on income at the end. The code a batch ran",
           "is on its page; uncommitted code is in `patches/`. This index is generated (`tools/ledger.py index`).", ""]
    for topic in sorted(by_topic):
        out += [f"## {topic}", "", "| date | batch | games | W-L | timeouts w-l | income at 20 | verdict |",
                "|---|---|---|---|---|---|---|"]
        for m, p in sorted(by_topic[topic], key=lambda t: (t[0]["date"], t[1].name), reverse=True):
            out.append(f"| {m['date']} | [{m['title']}]({p.relative_to(RESULTS).as_posix()}) | {m['games']} | "
                       f"{m['W']}-{m['L']} | {m['w']}-{m['l']} | "
                       f"{'x%.2f' % m['inc20'] if m.get('inc20') else '-'} | {m.get('verdict') or ''} |")
        out.append("")
    INDEX.write_text("\n".join(out), encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("add")
    a.add_argument("--topic", required=True, help="folder under results/, e.g. release-gate, breach, gauntlet")
    a.add_argument("--title", required=True)
    a.add_argument("--purpose", required=True)
    a.add_argument("--verdict", default="")
    a.add_argument("--date", help="YYYY-MM-DD the batch ran (default today)")
    a.add_argument("--us", default="Apex", help="substring of the spec whose results these are (default Apex)")
    a.add_argument("--dry", action="store_true", help="print the page, write nothing")
    a.add_argument("runs", nargs="+")
    sub.add_parser("index")
    args = ap.parse_args()
    (add if args.cmd == "add" else index)(args)


if __name__ == "__main__":
    main()
