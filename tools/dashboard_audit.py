"""Does the dashboard still describe the AI it is pointed at?

    python tools/dashboard_audit.py            # report
    python tools/dashboard_audit.py --accept   # waive the current backlog
    python tools/dashboard_audit.py --stale    # tunables no run has ever swept

`--stale` answers a different question, and it is the cull list for
docs/21-simplification.md Phase 3. It cross-references every tunable declared in
`tunables.as` against every `apex_*` modoption that appears in a recorded run's
`script.txt`, and lists the ones that have never been overridden even once.

A tunable nobody has ever swept is a named constant carrying four registration
sites (tunables.as, dev_tunables.lua, dashboard_guide.py, the waiver here) and
an experiment's clothing. It is also, per docs/21 root cause 1, one more
multiplicative term in a product where no single term controls the outcome.
`reads=1` marks the ones that fold back into a constant at their single call
site with no argument about which caller wins.

`tools/dashboard_guide.py` is a hand-written map from TUNE_ symbol to a plain
sentence. Nothing keeps it in step with `tunables.as` on its own: a knob added
to the AI simply does not appear on the Balance tab, and a knob renamed away
leaves the guide pointing at nothing. Both are silent, which is the shape of
every other failure this repo checks for mechanically.

So this is a RATCHET, not a coverage score. `dashboard_coverage.json` records
the tunables that are deliberately not on the guided page -- the ones that are
diagnostics, or an implementation detail nobody tunes by hand. Anything NEW is
reported until it is either curated or waived, so the question "should this be
on the dashboard?" gets asked once per knob, at the moment the knob is added,
instead of never.

Three findings, all silent otherwise:

  new       a tunable exists that the guide has never seen. Curate it in
            dashboard_guide.py or waive it with --accept.
  missing   the guide names a TUNE_ symbol tunables.as no longer has. The
            dashboard drops it at runtime, so the knob is simply absent from the
            page that is supposed to explain it.
  dead      the guide offers a knob no GetTunable call reads. Editing it changes
            nothing, and a guided page must not recommend it.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
WAIVER = Path(__file__).resolve().parent / "dashboard_coverage.json"


def audit():
    import dashboard
    import dashboard_guide

    sections = dashboard.parse_tunables()
    guide = dashboard_guide.build(sections)

    live = {}
    for s in sections:
        for e in s["entries"]:
            if e["tunable"]:
                live[e["name"]] = e

    curated = set(guide["curated"])
    waived = set(load_waiver().get("uncurated", []))

    new = sorted(n for n in live if n not in curated and n not in waived)
    # A waiver for a knob that no longer exists is just stale bookkeeping; it is
    # reported so the file does not accumulate ghosts, but it is not a finding.
    stale = sorted(n for n in waived if n not in live)
    dead = sorted(n for n in curated if n in live and live[n]["unread"])
    return {
        "new": new,
        "missing": sorted(guide["missing"]),
        "dead": dead,
        "stale_waivers": stale,
        "curated": len(curated),
        "total": len(live),
        "waived": len(waived & set(live)),
    }


_MODOPT = re.compile(r"\b(apex_[a-z0-9_]+)\s*=")


def swept() -> dict[str, int]:
    """apex_* modoption -> how many recorded runs set it.

    Both layouts: `matches/<run>/script.txt` and
    `tournaments/<batch>/<game>/script.txt`. A modoption is only in a start
    script because someone deliberately overrode it, so presence here IS the
    record of a sweep."""
    hits: dict[str, int] = {}
    for pattern in ("matches/*/script.txt", "tournaments/*/*/script.txt"):
        for p in REPO.glob(pattern):
            try:
                text = p.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for name in set(_MODOPT.findall(text)):
                hits[name] = hits.get(name, 0) + 1
    return hits


def stale():
    """Declared tunables that no recorded run has ever overridden."""
    import dashboard

    runs = swept()
    out = []
    total = 0
    for s in dashboard.parse_tunables():
        rows = []
        for e in s["entries"]:
            if not e["tunable"]:
                continue
            total += 1
            if e["tunable"] in runs:
                continue
            sites = [x for x in (e["reads"] or "").split(",") if x.strip()]
            rows.append((e["tunable"], e["name"], len(sites)))
        if rows:
            out.append((s["title"], rows))
    return out, total, runs


def report_stale() -> int:
    sections, total, runs = stale()
    n = sum(len(r) for _, r in sections)
    print(f"\nnever swept: {n} of {total} tunables have never appeared as an "
          f"apex_* modoption in any recorded run")
    print(f"({len(runs)} distinct tunables HAVE been overridden at least once)\n")
    for title, rows in sections:
        print(f"  {title}")
        for tunable, sym, sites in sorted(rows):
            mark = "  <- one call site, fold it into a constant" if sites == 1 else ""
            print(f"    {tunable:<38} {sym:<32} reads={sites}{mark}")
        print()
    single = sum(1 for _, rows in sections for _, _, k in rows if k == 1)
    print(f"{single} of those are read at exactly one call site -- "
          f"docs/21-simplification.md Phase 3 takes these first.\n")
    return 0


def load_waiver() -> dict:
    try:
        return json.loads(WAIVER.read_text(encoding="utf-8"))
    except Exception:
        return {}


def accept() -> None:
    r = audit()
    doc = load_waiver()
    keep = set(doc.get("uncurated", [])) - set(r["stale_waivers"])
    doc["uncurated"] = sorted(keep | set(r["new"]))
    doc["_why"] = ("Tunables deliberately NOT on the dashboard's Balance tab. "
                   "Anything absent from both this list and dashboard_guide.py "
                   "is reported by tools/dashboard_audit.py, so a knob added to "
                   "the AI gets the question asked once rather than never.")
    WAIVER.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n",
                      encoding="utf-8", newline="\n")
    print(f"waived {len(r['new'])} new, dropped {len(r['stale_waivers'])} stale "
          f"-> {WAIVER.relative_to(REPO).as_posix()}")


def report(r, rep=None) -> int:
    """Print, or push into a check.py Report. Returns the error count."""
    def err(m):
        (rep.error if rep else lambda x: print("  ERROR   " + x))(m)

    def warn(m):
        (rep.warn if rep else lambda x: print("  warn    " + x))(m)

    n = 0
    for name in r["missing"]:
        err(f"dashboard_guide.py names {name}, which tunables.as no longer has "
            f"-- the dashboard drops it silently")
        n += 1
    for name in r["dead"]:
        err(f"dashboard_guide.py offers {name}, which no GetTunable call reads "
            f"-- editing it on the Balance tab changes nothing")
        n += 1
    if r["new"]:
        warn(f"{len(r['new'])} tunable(s) the dashboard has never seen: "
             f"{', '.join(r['new'][:8])}"
             f"{' …' if len(r['new']) > 8 else ''} -- add them to "
             f"tools/dashboard_guide.py, or run "
             f"`python tools/dashboard_audit.py --accept` to waive them")
    if r["stale_waivers"]:
        warn(f"{len(r['stale_waivers'])} waived tunable(s) no longer exist: "
             f"{', '.join(r['stale_waivers'][:6])} -- --accept clears them")
    return n


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--accept", action="store_true",
                    help="record every currently-uncurated tunable as deliberate")
    ap.add_argument("--stale", action="store_true",
                    help="list tunables no recorded run has ever overridden")
    a = ap.parse_args()
    if a.stale:
        return report_stale()
    if a.accept:
        accept()
        return 0
    r = audit()
    print(f"\ndashboard coverage: {r['curated']} curated, {r['waived']} waived, "
          f"of {r['total']} tunables")
    n = report(r)
    if not n and not r["new"] and not r["stale_waivers"]:
        print("  ok      every tunable is either on the dashboard or waived")
    print()
    return 1 if n else 0


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    raise SystemExit(main())
