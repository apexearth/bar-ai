#!/usr/bin/env python3
"""Split one big AngelScript manager file into a directory of smaller parts.

The parts are pure line slices of the original, each re-wrapped in the same
namespace, and the original file becomes a shim that #includes them in order.
CScriptBuilder adds a section BEFORE processing that section's includes and
walks includes depth-first in order, so the concatenated declaration order the
compiler sees is unchanged -- which is what AngelScript's "globals must be
declared before use" rule cares about.

    python tools/split_as.py <file.as> <namespace> <name>:<startline> ...

Start lines are 1-based and refer to the ORIGINAL file. The first part starts
at the line after the `namespace X {` opener; the last ends at the line before
the closing brace.
"""
import sys, os, re


def main(argv):
    path, ns = argv[1], argv[2]
    cuts = []
    for spec in argv[3:]:
        name, line = spec.rsplit(':', 1)
        cuts.append((name, int(line)))

    with open(path, encoding='utf-8', newline='') as fh:
        raw = fh.read()
    # Keep whatever the working tree already uses; .gitattributes normalises to
    # LF on commit, but rewriting a CRLF checkout as LF makes every file look
    # wholly modified until then.
    eol = '\r\n' if '\r\n' in raw else '\n'
    text = raw.replace('\r\n', '\n')
    lines = text.split('\n')          # 0-based; lines[i] is source line i+1

    open_re = re.compile(r'^namespace %s \{$' % re.escape(ns))
    close_re = re.compile(r'^\}\s*//\s*namespace %s$' % re.escape(ns))
    opens = [i for i, l in enumerate(lines) if open_re.match(l)]
    closes = [i for i, l in enumerate(lines) if close_re.match(l)]
    assert len(opens) == 1 and len(closes) == 1, (opens, closes)
    body_start, body_end = opens[0] + 1, closes[0]      # [start, end) 0-based

    assert cuts[0][1] - 1 == body_start, (cuts[0][1], body_start + 1)
    for (_, a), (_, b) in zip(cuts, cuts[1:]):
        assert a < b, (a, b)

    outdir = os.path.splitext(path)[0]
    os.makedirs(outdir, exist_ok=True)
    base = os.path.basename(outdir)

    bounds = [c[1] - 1 for c in cuts] + [body_end]
    for (name, _), lo, hi in zip(cuts, bounds, bounds[1:]):
        chunk = lines[lo:hi]
        while chunk and chunk[-1].strip() == '':
            chunk.pop()
        body = '\n'.join(chunk)
        out = 'namespace %s {\n\n%s\n\n}  // namespace %s\n' % (ns, body, ns)
        with open(os.path.join(outdir, name + '.as'), 'w',
                  encoding='utf-8', newline='') as fh:
            fh.write(out.replace('\n', eol))
        print('%-28s %5d lines' % (base + '/' + name + '.as', hi - lo))

    head = '\n'.join(lines[:opens[0]]).rstrip('\n')
    shim = [head, ''] if head else []
    shim += ['#include "%s/%s.as"' % (base, name) for name, _ in cuts]
    with open(path, 'w', encoding='utf-8', newline='') as fh:
        fh.write(eol.join(shim) + eol)
    print('%-28s %5d lines (shim)' % (path, len(shim)))


if __name__ == '__main__':
    main(sys.argv)
