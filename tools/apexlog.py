"""Merge the AI's own log files back into an infolog, by frame.

The AI writes its lines to `apex-t<team>.log` in its data dir instead of the
engine log, because the engine log is also the in-game chat (S31). Each line
carries the engine's own `[t=..][f=..] Skirmish AI <..>:` prefix, so once
merged the file reads exactly as before and no tool changes. The infolog names
the files it should absorb in `apex: log file <path>` lines; stale files from
an earlier game in the same write dir are never picked up by accident.

The AI's `[t=` is its own clock (time since the process started); the engine's
is time since its first log call, a few hundred ms later. Frames agree exactly;
wall stamps only within one source -- hitch.py and frametime.py know.

    python tools/apexlog.py <infolog-or-run-dir> [more targets...]
    python tools/apexlog.py <infolog> --out <merged-copy>     # leave the original

run_match.py calls `merge_into()` on its infolog and stdout copies itself.
"""
import heapq
import os
import re
import sys

STAMP = re.compile(r'^\[t=[^\]]*\]\[f=(-?\d+)\]')
LOGFILE = re.compile(r'apex: log file (\S.*?\.log)\s*$', re.M)
MERGED = 'apex-log merged'


def apex_files(text: str) -> list[str]:
    seen, out = set(), []
    for m in LOGFILE.finditer(text):
        p = m.group(1)
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def _stamped(path: str):
    frame = -1
    with open(path, encoding='utf-8', errors='replace') as fh:
        for line in fh:
            m = STAMP.match(line)
            if m:
                frame = int(m.group(1))
            yield frame, line


def merge_text(text: str, files: list[str]) -> str:
    """Return `text` with the lines of `files` interleaved by frame: an AI line
    lands after every engine line of its frame, before the next frame's."""
    streams = [_stamped(p) for p in files if os.path.isfile(p)]
    if not streams:
        return text
    ai = heapq.merge(*streams, key=lambda fl: fl[0])
    out = []
    pending = next(ai, None)
    frame = -1
    for line in text.splitlines(keepends=True):
        m = STAMP.match(line)
        if m:
            frame = int(m.group(1))
            while pending is not None and pending[0] < frame:
                out.append(pending[1])
                pending = next(ai, None)
        out.append(line)
    while pending is not None:
        out.append(pending[1])
        pending = next(ai, None)
    out.append(f'[{MERGED}] {len(files)} file(s)\n')
    return ''.join(out)


def merge_into(target: str, files: list[str] | None = None) -> int:
    """Rewrite `target` in place with its AI logs merged. Idempotent."""
    if not os.path.isfile(target):
        return 0
    text = open(target, encoding='utf-8', errors='replace').read()
    if MERGED in text[-200:]:
        return 0
    files = files if files is not None else apex_files(text)
    files = [f for f in files if os.path.isfile(f)]
    if not files:
        return 0
    merged = merge_text(text, files)
    with open(target, 'w', encoding='utf-8', newline='') as fh:
        fh.write(merged)
    return len(files)


def main():
    args = sys.argv[1:]
    out = None
    if '--out' in args:
        i = args.index('--out')
        out = args[i + 1]
        del args[i:i + 2]
    if not args:
        sys.exit(__doc__)
    if out is not None:
        # a copy, for a live game or an install's infolog that must stay as it is
        import shutil
        shutil.copyfile(args[0], out)
        text = open(args[0], encoding='utf-8', errors='replace').read()
        n = merge_into(out, apex_files(text))
        print(f'{out}: merged {n} file(s)' if n else f'{out}: nothing to merge')
        return
    for arg in args:
        targets = [arg] if os.path.isfile(arg) else [
            os.path.join(arg, n) for n in ('infolog.txt', 'stdout.txt')]
        for t in targets:
            n = merge_into(t)
            print(f'{t}: merged {n} file(s)' if n else f'{t}: nothing to merge')


if __name__ == '__main__':
    main()
