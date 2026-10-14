"""Cases for command_guard.py: python tools/hooks/test_command_guard.py"""
import json
import os
import subprocess
import sys

GUARD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "command_guard.py")
BLOCK = [
    "python - <<'PY'\nprint(1)\nPY",
    "cd x; python3 <<EOF\nprint(1)\nEOF",
    "python -c \"import os\nprint(os.getcwd())\"",
    "echo 'print(1)' | python -",
    "du -sh matches",
    "taskkill /F /IM spring-headless.exe",
    "Stop-Process -Name spring -Force",
    "pkill spring",
]
PASS = [
    "python tools/review.py matches/x",
    "python -c \"import json;print(1)\"",
    "python -u tools/run_match.py --a A --b B > log 2>&1",
    "grep -n du tools/x.py",
    "cat <<'EOF' >> docs/27.md\ntext\nEOF",
    "git commit -m \"$(cat <<'EOF'\nmsg\nEOF\n)\"",
    "ls dump; echo duplicate",
    "Stop-Process -Id 1234 -Force",
]


def blocked(cmd):
    r = subprocess.run([sys.executable, GUARD], input=json.dumps({"tool_input": {"command": cmd}}),
                       capture_output=True, text=True)
    return r.returncode == 2


bad = [c for c in BLOCK if not blocked(c)] + [c for c in PASS if blocked(c)]
for c in bad:
    print("WRONG:", repr(c))
print("ok" if not bad else "%d wrong" % len(bad))
sys.exit(1 if bad else 0)
