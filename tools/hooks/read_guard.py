"""PreToolUse hook (Read): refuse a whole-file read of a big text file.

His 11-03: stop sessions from opening big files and blowing up the context by accident. A text file
over LIMIT bytes is read only with offset/limit (or allow_large when the whole of it is truly needed);
otherwise grep it first. Images, PDFs and notebooks pass. Exit 2 blocks the call and shows the reason.
"""
import json
import os
import sys

LIMIT = 40_000
BINARY = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".pdf", ".ipynb")


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    args = data.get("tool_input") or {}
    path = args.get("file_path") or ""
    if not path or path.lower().endswith(BINARY):
        return 0
    if args.get("limit") or args.get("offset") or args.get("allow_large"):
        return 0
    try:
        size = os.path.getsize(path)
    except OSError:
        return 0
    if size <= LIMIT:
        return 0
    sys.stderr.write(
        "Blocked by tools/hooks/read_guard.py: %s is %d KB. Grep it for what you need, or Read with "
        "offset/limit. Pass allow_large only if the whole file is truly needed.\n" % (path, size // 1024))
    return 2


if __name__ == "__main__":
    sys.exit(main())
