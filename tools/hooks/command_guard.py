"""PreToolUse hook (Bash, PowerShell): refuse the commands his standing rules forbid.

Each rule here was written down first and broken anyway; a blocked command is the one that gets
followed (10-14 bug analysis, recommendation 5). Exit 2 blocks the call and shows the reason.
"""
import json
import re
import sys

RULES = [
    (re.compile(r"\bpython[0-9.]*(?:\.exe)?\b[^\n|;&]*<<", re.I),
     "Python in a heredoc. Write the script to a file (scratchpad, or tools/ for a keeper), then run it."),
    (re.compile(r"\bpython[0-9.]*(?:\.exe)?\s+(?:-\S+\s+)*-c\s+(['\"])(?:(?!\1).)*\n", re.I | re.S),
     "Multi-line `python -c`. Write the script to a file, then run it."),
    (re.compile(r"\|\s*python[0-9.]*(?:\.exe)?\s+(?:-\S+\s+)*-(?:\s|$)", re.I),
     "Python fed on stdin. Write the script to a file, then run it."),
    (re.compile(r"(?:^|[;&|(]\s*)du(?:\s|$)", re.M),
     "`du` undercounts here (it cannot descend a build dir). Use tools/reclaim.py."),
    (re.compile(r"taskkill[^\n]*?/im\s+\"?spring", re.I),
     "Killing spring by image name can end his live game. Stop engines by command line only."),
    (re.compile(r"(?:Stop-Process|kill|spps)\s+[^\n]*-Name\s+\"?spring", re.I),
     "Killing spring by name can end his live game. Stop engines by command line only."),
    (re.compile(r"\b(?:pkill|killall)\s+[^\n]*spring", re.I),
     "Killing spring by name can end his live game. Stop engines by command line only."),
]


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    cmd = (data.get("tool_input") or {}).get("command") or ""
    for rx, why in RULES:
        if rx.search(cmd):
            sys.stderr.write("Blocked by tools/hooks/command_guard.py: " + why + "\n")
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
