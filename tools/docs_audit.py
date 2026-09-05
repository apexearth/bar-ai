"""Do the docs still describe code that exists?

The recurring failure here is not a doc that is badly written -- it is a doc
that was TRUE and quietly stopped being true, while still reading as
authoritative. apexearth, 2026-08-31: "it's very organic through a normal
conversation that a specific case or situation is run into, and then the AI
will modify some documents based on that one conversation... I'm too busy, and
there's too much for me to look through here."

So this checks the one thing about a doc that is mechanically decidable: when a
doc names a FILE or a SYMBOL, does that file or symbol exist in the tree? It
makes no judgement about whether the prose is right -- it only catches the
claims that are checkably dead. That is enough to have caught every stale
reference found by hand on 2026-08-31: RushReady, techlead.as, mexhold.as,
builder/share.as, T1Commit, ShareAdvCon, AlwaysEco, docs/12, docs/18.

    python tools/docs_audit.py            # report
    python tools/docs_audit.py --quiet    # exit 1 on findings, no detail

Deliberately NOT checked: whether a described behaviour matches the code. That
needs judgement, and judgement is what keeps going wrong.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VARIANT = ROOT / "ai" / "Unstable" / "game-side" / "script" / "standard"

# Where prose lives.
PROSE = [ROOT / "CLAUDE.md", ROOT / "USER-FEEDBACK.md", ROOT / "ISSUES.md"]
PROSE += sorted((ROOT / "docs").glob("*.md"))
PROSE += sorted((ROOT / ".claude" / "skills").glob("*/SKILL.md"))
PROSE += sorted((ROOT / ".claude" / "agents").glob("*.md"))

# `backticked.as` or `backticked/path.as` -- a claim that a script file exists.
FILE_REF = re.compile(r"`([A-Za-z0-9_./-]+\.(?:as|lua|py|json))`")
# `SomeFunc()` or `Namespace::SomeFunc` -- a claim that a symbol exists.
SYM_REF = re.compile(r"`(?:([A-Z][A-Za-z0-9_]*)::)?([A-Za-z_][A-Za-z0-9_]*)\(\)`")
# `apex_foo` / TUNE_FOO -- tunables have their own auditor, but a doc naming a
# dead one is the same class of rot.
TUNE_REF = re.compile(r"`(apex_[a-z0-9_]+)`")

# Docs that deliberately describe OTHER repositories -- their file references
# are supposed to be absent from our tree, so scanning them is pure noise. An
# auditor with a 40% false-positive rate gets ignored, which is worse than no
# auditor (the as_scope undeclared-symbol pass was reverted the same day for
# exactly this).
SURVEYS = {"docs/13-other-ais.md", "docs/14-bar-ai-landscape.md",
           "docs/02-ai-landscape.md", "docs/09-resources.md"}

# Files owned by the game, the lobby or the ENGINE INSTALL, not by us. A path
# under the Beyond-All-Reason install is supposed to be absent from this repo --
# CLAUDE.md's "Local layout" table names several, and flagging them made the two
# most-read files in the repo look rotten when they are correct.
EXTERNAL_FILES = {"aiSimpleName.lua", "aiCustomData.lua", "parse_demo_file.py",
                  "config/x.json", "gadgets.lua", "units.json",
                  "launcher_cfg.json", "config.json", "interface_skirmish.lua",
                  "springsettings.cfg"}

# A doc that says a thing is GONE is not rotten -- it is the cure. Suppress a
# reference whose own line reports the absence, or every correct obituary reads
# as a stale claim. Verified 2026-08-31: 4 of the 5 findings in CLAUDE.md and
# ISSUES.md were this class or the external-file class above, and an auditor
# whose loudest hits are false gets ignored -- the as_scope lesson, same day.
OBITUARY = re.compile(
    "(?<![A-Za-z])(gone|deleted|removed|retired|no longer|does not exist"
    "|zero definitions|used to|stale|dead|was killed|killed with|split into"
    "|renamed|is now the|comment-only|no callers)(?![A-Za-z])", re.I)


def _obituary(text, pos):
    """True if the PARAGRAPH containing offset `pos` reports the thing's absence.

    The paragraph, not the line or the sentence. A doc that kills four files at
    once names them in a list and then says "none of those exist" several lines
    below, which a one-line lookahead cannot see -- four such correct obituaries
    were the checker's entire remaining output on 2026-08-31.

    The trade-off, stated because it is real: a genuinely dead reference sharing
    a paragraph with some OTHER thing's obituary is now suppressed. That is the
    right way to be wrong here. This checker exists to be run often and believed,
    and a false positive nobody can silence is what turned the last two
    heuristics into noise people learned to skip.
    """
    start = text.rfind(chr(10) + chr(10), 0, pos)
    start = 0 if start < 0 else start + 2
    end = text.find(chr(10) + chr(10), pos)
    return bool(OBITUARY.search(text[start:end if end >= 0 else len(text)]))

# Names that are engine/C++/stdlib, not ours -- absence proves nothing.
EXTERNAL = {
    "GetTeamUnits", "GetGameFrame", "GetTeamInfo", "GetTeamList", "GetModOptions",
    "GetUnitDefID", "SendMessage", "Echo", "GameFrame", "UnitFinished",
    "UnitDestroyed", "UnitCreated", "main", "printf", "assert", "sqrt", "pow",
    "min", "max", "abs", "floor", "ceil", "rand", "sort", "insert", "remove",
}


# The AI is not only AngelScript. A tunable can be read from the C++ DLL
# (circuit->GetTunable), and the dashboard skill documents JS functions that
# live in the served page. Scanning only the .as tree reported all of those as
# dead -- seven false positives across two skills on 2026-08-31, every one of
# them a correct doc. Absence is only evidence when the search covered the
# places the thing could be.
def script_text():
    out = []
    trees = [(VARIANT, "*.as"),
             (ROOT / "cpp" / "src", "*.cpp"), (ROOT / "cpp" / "src", "*.h"),
             (ROOT / "tools", "*.html")]
    for base, pat in trees:
        if not base.is_dir():
            continue
        for p in base.rglob(pat):
            try:
                out.append(p.read_text(encoding="utf-8", errors="replace"))
            except OSError:
                pass
    return "\n".join(out)


def main():
    quiet = "--quiet" in sys.argv
    if not VARIANT.is_dir():
        print(f"variant tree not found: {VARIANT}")
        return 1

    code = script_text()
    # Every symbol the AngelScript actually declares.
    declared = set(re.findall(r"\b(?:void|bool|int|uint|float|double|string)\s+"
                              r"([A-Za-z_][A-Za-z0-9_]*)\s*\(", code))
    declared |= set(re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\(", code))
    # `function foo()` and `const foo = ` both declare a name in the served page.
    declared |= set(re.findall(r"\bfunction\s+([A-Za-z_$][A-Za-z0-9_$]*)", code))
    declared |= set(re.findall(r"\b(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=",
                               code))
    tunables = set(re.findall(r'GetTunable\("([a-z_0-9]+)"', code))

    # Every file that exists, by basename and by tail path.
    have = set()
    # `vendor/` and `matches/` stay IN: vendor/bar is how a reference to a BAR
    # game file is confirmed, and matches/ is where result.json lives.
    # Excluding them turned 20 correct references into findings.
    for p in ROOT.rglob("*"):
        if not p.is_file():
            continue
        have.add(p.name)
        have.add("/".join(p.parts[-2:]))
        have.add("/".join(p.parts[-3:]))

    findings = []
    for doc in PROSE:
        if not doc.is_file():
            continue
        try:
            text = doc.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        rel = doc.relative_to(ROOT).as_posix()
        if rel in SURVEYS:
            continue
        seen = set()
        for m in FILE_REF.finditer(text):
            ref = m.group(1)
            if ref in seen:
                continue
            seen.add(ref)
            tail = ref.split("/")
            if (ref in have or tail[-1] in have
                    or "/".join(tail[-2:]) in have
                    or ref in EXTERNAL_FILES or tail[-1] in EXTERNAL_FILES):
                continue
            if _obituary(text, m.start()):
                continue
            findings.append((rel, "file", ref))
        for m in SYM_REF.finditer(text):
            ns, name = m.group(1), m.group(2)
            key = f"{ns}::{name}" if ns else name
            if key in seen or name in EXTERNAL:
                continue
            seen.add(key)
            if name not in declared:
                if _obituary(text, m.start()):
                    continue
                findings.append((rel, "symbol", key))
        for m in TUNE_REF.finditer(text):
            t = m.group(1)
            if t in seen:
                continue
            seen.add(t)
            if t not in tunables:
                if _obituary(text, m.start()):
                    continue
                findings.append((rel, "tunable", t))

    by_doc = {}
    for rel, kind, ref in findings:
        by_doc.setdefault(rel, []).append((kind, ref))

    if not quiet:
        for rel in sorted(by_doc, key=lambda r: -len(by_doc[r])):
            items = by_doc[rel]
            print(f"\n{rel}  ({len(items)} dead reference(s))")
            for kind, ref in items[:12]:
                print(f"    {kind:<8} {ref}")
            if len(items) > 12:
                print(f"    ... and {len(items) - 12} more")
        print(f"\n{len(findings)} dead reference(s) across {len(by_doc)} file(s)"
              f" of {len(PROSE)} scanned")
        print("A dead reference is a claim about code that is no longer there.")
        print("It does NOT mean the prose around it is wrong -- but it is the")
        print("cheapest signal that the section was written for a tree that")
        print("has since changed, and should be re-read before being trusted.")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
