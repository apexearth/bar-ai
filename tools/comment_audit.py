#!/usr/bin/env python3
"""Catch archaeology as it is written, not two months later.

CLAUDE.md has always said findings, measurements and session transcripts go in
the commit message or ISSUES.md, never the source. 13,368 comment lines
accumulated anyway, because a rule fires when someone remembers it and a check
fires every time. This is the check.

It reads the DIFF, not the tree: only lines this change adds are judged, so the
existing backlog never drowns the signal.

    python tools/comment_audit.py                # working tree vs HEAD
    python tools/comment_audit.py --since main   # a branch's worth
    python tools/comment_audit.py --all          # the standing backlog, ranked

Two things are reported. A RUN REPORT is a comment that records what a game did
-- a date, a seed, a win/loss, a metal total. It is already in git history and
it rots in place, because the code moves and the number does not. An ESSAY is a
new comment block over --max-block lines; the rule it states is worth one line,
and the derivation behind it belongs in docs/.

Neither is an error. Both are questions: does this belong in the commit message?

One caveat: a diff cannot tell a NEW comment from a REWRAPPED one, so a pass
that re-flows existing prose reports the prose it preserved. Judge those on the
commit, not on this.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Validated against the 2026-09-05 cull: "measured as X" DEFINES a quantity and
# must not fire; "Measured 2026-08-22 over three paired runs" REPORTS one. The
# tell is a date or an explicit run descriptor, never the word on its own.
RUN_REPORT = re.compile(
    r"""(?xi)
      \b20\d\d-\d\d-\d\d\b
    | \bseeds?\s+\d
    | \bhead[- ]to[- ]head\b
    | \bwin\s+rate\b
    | \b\d+W[- ]\d+L\b
    | \b(?:measured|watched|paired|probe|bench)\b
      [^.]{0,60}\b(?:\d+v\d+|\d+[- ]min(?:ute)?|\d+\s*games?)\b
    | \b(?:in|over)\s+(?:one|two|three|four|five|six|ten|\d+)\s+
      (?:paired\s+)?(?:\d+v\d+|\d+[- ]minute|games?|runs?)\b
    """)
# A date attached to HIS words is provenance for a directive, not a run report.
# Case matters here only in that it must not: the same attribution is written
# "HIS RULING", "His ruling" and "his prior" in different files, and a guard
# that misses one flags the directive it was meant to protect.
QUOTE = re.compile(
    r"(?i)\bapexearth\b|\bhis (?:ruling|cadence|prior|ask|words|complaint|call)\b"
    r"|\bhe (?:asked|ruled|said|wants)\b")

COMMENT = re.compile(r"^\s*(?://|#)")
SRC = (".as", ".py", ".cpp", ".h", ".lua")

# PROSE FILES get the same question, because the same habit fills them.
# apexearth 2026-09-05, on a docs/27 entry: "It's so black and white... This is
# a good example of comments/content being added to our docs, blowing up our
# context, and causing baggage we carry down the road."
PROSE = ("docs/", "ISSUES.md", "USER-FEEDBACK.md", "TODO.md", "CLAUDE.md",
         "BAR-GUIDE.md", "README.md")

# A rule stated without its exception is baggage: the next session obeys it
# where it does not apply, or deletes it and loses the finding with it. The
# condition is usually one clause -- "when the worker is safe" -- and stating it
# costs less than the confusion of leaving it out.
ABSOLUTE = re.compile(
    "(?x) (?<![A-Za-z]) (?: NEVER | ALWAYS ) (?![A-Za-z])"
    " | (?i: (?<![A-Za-z]) must [ ]+ never (?![A-Za-z]) )")

# Lines one prose file may gain before the diff is asked to justify them.
# Context is the budget: every line here is re-read by every session after.
PROSE_BUDGET = 25


def added_lines(since):
    """[(path, lineno, text)] for lines this diff ADDS."""
    cmd = ["git", "diff", "-U0"]
    cmd += [since] if since else []
    out = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True,
                         errors="replace").stdout
    path, ln = None, 0
    for line in out.splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
        elif line.startswith("@@"):
            m = re.search(r"\+(\d+)", line)
            ln = int(m.group(1)) if m else 0
        elif line.startswith("+") and not line.startswith("+++"):
            if path and path.endswith(SRC):
                yield path, ln, line[1:]
            ln += 1


def prose_added(since):
    """{path: [(lineno, text)]} for PROSE lines this diff adds."""
    cmd = ["git", "diff", "-U0"] + ([since] if since else [])
    out = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True,
                         errors="replace").stdout
    got, path, ln = {}, None, 0
    for line in out.splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
        elif line.startswith("@@"):
            m = re.search(r"\+(\d+)", line)
            ln = int(m.group(1)) if m else 0
        elif line.startswith("+") and not line.startswith("+++"):
            if path and path.startswith(PROSE) and line[1:].strip():
                got.setdefault(path, []).append((ln, line[1:]))
            ln += 1
    return got


def all_lines():
    out = subprocess.run(["git", "ls-files"], cwd=REPO, capture_output=True,
                         text=True).stdout
    for f in out.splitlines():
        if not f.endswith(SRC) or f.startswith(("reference/", "vendor/")):
            continue
        try:
            text = (REPO / f).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            yield f, i, line


SENT = re.compile(r"(?<=[.!?]) (?=[A-Z0-9\"'(])")


def close(run, reports, essays, max_block):
    """Judge one finished comment block."""
    if not run:
        return
    if len(run) > max_block:
        essays.append((run[0][0], run[0][1], len(run)))
    body = " ".join(re.sub(r"^\s*(?://|#)\s?", "", t) for _, _, t in run)
    body = re.sub(r"\s+", " ", body)
    # A date on his words is provenance for a directive. Wrapping puts his name
    # and the date on different lines, so this has to be judged per BLOCK -- per
    # line it flags every quote he ever gave a date to.
    if QUOTE.search(body):
        return
    for s in SENT.split(body):
        if RUN_REPORT.search(s):
            reports.append((run[0][0], run[0][1], s.strip()))


def audit(lines, max_block):
    reports, essays = [], []
    run = []          # (path, lineno, text) of the block being accumulated
    for path, ln, text in lines:
        if COMMENT.match(text):
            if run and run[-1][0] == path and ln == run[-1][1] + 1:
                run.append((path, ln, text))
            else:
                close(run, reports, essays, max_block)
                run = [(path, ln, text)]
        else:
            close(run, reports, essays, max_block)
            run = []
    close(run, reports, essays, max_block)
    return reports, essays


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", metavar="REF",
                    help="audit REF..working-tree instead of HEAD..working-tree")
    ap.add_argument("--all", action="store_true",
                    help="audit the whole tree -- the standing backlog")
    ap.add_argument("--max-block", type=int, default=10,
                    help="warn on a new comment block longer than this (default 10)")
    ap.add_argument("--strict", action="store_true",
                    help="exit 1 if anything is reported")
    a = ap.parse_args()

    lines = all_lines() if a.all else added_lines(a.since)
    reports, essays = audit(lines, a.max_block)
    scope = "the tree" if a.all else ("%s..working tree" % (a.since or "HEAD"))

    if reports:
        print("RUN REPORTS in %s -- put these in the commit message:" % scope)
        for f, ln, body in reports[:40]:
            print("  %s:%d" % (f, ln))
            print("      %s" % (body[:150] + ("..." if len(body) > 150 else "")))
        if len(reports) > 40:
            print("  ... and %d more" % (len(reports) - 40))
        print()
    if essays:
        print("COMMENT BLOCKS over %d lines in %s -- state the rule, move the"
              " derivation to docs/:" % (a.max_block, scope))
        for f, ln, n in sorted(essays, key=lambda e: -e[2])[:40]:
            print("  %s:%d  (%d lines)" % (f, ln, n))
        if len(essays) > 40:
            print("  ... and %d more" % (len(essays) - 40))
        print()
    prose = {} if a.all else prose_added(a.since)
    fat = {f: v for f, v in prose.items() if len(v) > PROSE_BUDGET}
    absolutes = [(f, ln, t) for f, v in prose.items() for ln, t in v
                 if ABSOLUTE.search(t)]
    if fat:
        print("PROSE ADDED in %s -- docs are context every future session pays"
              " for; keep the rule, drop the transcript:" % scope)
        for f, v in sorted(fat.items(), key=lambda e: -len(e[1])):
            print("  %-42s +%d lines" % (f, len(v)))
        print()
    if absolutes:
        print("ABSOLUTES in added prose -- state the condition, not the ban"
              " (apexearth: \"It's so black and white\"):")
        for f, ln, t in absolutes[:20]:
            print("  %s:%d" % (f, ln))
            print("      %s" % (t.strip()[:110]))
        print()

    if not reports and not essays and not fat and not absolutes:
        print("clean: no run reports, no blocks over %d lines, no prose bloat"
              " in %s" % (a.max_block, scope))
        return 0

    print("%d run report(s), %d oversized block(s), %d fat prose file(s),"
          " %d absolute(s)." % (len(reports), len(essays), len(fat),
                                len(absolutes)))
    print("None is an error. Each is the question: does this belong here, or in")
    print("the commit that made it true?")
    return 1 if a.strict else 0


if __name__ == "__main__":
    sys.exit(main())
