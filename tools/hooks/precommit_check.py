"""Git pre-commit gate: `tools/check.py Unstable --fast` may not gain an ERROR.

The checker carried 32 standing errors on 10-14, so it was always red and nobody read it; a gate
only works from a clean baseline. Errors already in check_baseline.txt pass (line numbers are
ignored, since edits move them); a new one blocks the commit. Fix it, or -- only when the check is
wrong -- record it with `python tools/hooks/precommit_check.py --rebaseline` and say why in the
commit message.

Runs only when the commit stages AI code, config or the checker's own inputs.
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASELINE = os.path.join(REPO, "tools", "hooks", "check_baseline.txt")
WATCH = ("ai/Unstable/", "cpp/", "tools/check.py", "tools/dashboard", "tools/as_scope.py")


def errors():
    r = subprocess.run([sys.executable, os.path.join(REPO, "tools", "check.py"), "Unstable", "--fast"],
                       cwd=REPO, capture_output=True, text=True)
    out = set()
    for line in r.stdout.splitlines():
        line = line.strip()
        if line.startswith("ERROR"):
            out.add(re.sub(r":\d+:", ":", re.sub(r"\s+", " ", line)))
    return out


def staged():
    r = subprocess.run(["git", "diff", "--cached", "--name-only"], cwd=REPO, capture_output=True, text=True)
    return [p for p in r.stdout.splitlines() if p.strip()]


def main(argv):
    if "--rebaseline" in argv:
        e = sorted(errors())
        open(BASELINE, "w", encoding="utf-8").write("\n".join(e) + "\n")
        print("baseline: %d errors recorded in %s" % (len(e), os.path.relpath(BASELINE, REPO)))
        return 0
    if not any(p.startswith(WATCH) for p in staged()):
        return 0
    base = set()
    if os.path.exists(BASELINE):
        base = {l.strip() for l in open(BASELINE, encoding="utf-8") if l.strip()}
    new = sorted(errors() - base)
    if not new:
        return 0
    sys.stderr.write("pre-commit: tools/check.py found %d new error(s):\n" % len(new))
    for e in new:
        sys.stderr.write("  " + e + "\n")
    sys.stderr.write("Fix them, or if the check is wrong: python tools/hooks/precommit_check.py --rebaseline\n")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
