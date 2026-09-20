"""The unit track record: the exchange matrix, and what died to what.

    python tools/record.py <apex-record.txt> [run ...]     # the matrix: our type vs theirs, metal for metal
    python tools/record.py --foe <apex-record.txt> [run]   # the same matrix from their side
    python tools/record.py --deaths <run> [...]            # the death lines: dealt/health, killed-by, tier

A cell is metal of theirs our type destroyed over metal of ours that type
destroyed; 1 = an even trade. Runs passed alongside the file teach the
reader each type's tier from the death lines. Fodder and fighters are listed
but the price never reads them (worth.as RecordMul).
"""
import collections
import os
import re
import sys

LINE = re.compile(r'apex: record (\S+) died dealt=(\S+) hp=(\S+) .*killed-by=(\S+) t(\d)')
TIERS = {}


def read_deaths(path, acc, killers):
    for line in open(path, errors='replace'):
        m = LINE.search(line)
        if not m:
            continue
        d, dealt, hp, killer, tier = m.group(1), float(m.group(2)), float(m.group(3)), m.group(4), int(m.group(5))
        TIERS[killer] = tier
        a = acc[(d, tier)]
        a[0] += dealt
        a[1] += hp
        a[2] += 1
        killers[d][killer] += 1


def read_matrix(path):
    cells = {}
    for line in open(path):
        f = line.split()
        if len(f) != 4 or f[1] == '-' or f[1][0].isdigit():
            continue
        try:
            cells[(f[0], f[1])] = (float(f[2]), float(f[3]))
        except ValueError:
            pass
    return cells


def print_matrix(cells, foe):
    rows = collections.defaultdict(dict)
    for (a, b), (dealt, taken) in cells.items():
        if foe:
            rows[b][a] = (taken, dealt)
        else:
            rows[a][b] = (dealt, taken)
    print(('THEIR type vs ours' if foe else 'OUR type vs theirs')
          + ': exchange = metal destroyed / metal lost (1 = even), by tier of the other side, then the top trades')
    print('%-12s %7s %8s | %s' % ('type', 'lostM', 'all', '  '.join('t%d' % t for t in range(4))))
    order = sorted(rows, key=lambda k: -sum(v[1] for v in rows[k].values()))
    for a in order:
        d = sum(v[0] for v in rows[a].values())
        t = sum(v[1] for v in rows[a].values())
        if t <= 0:
            continue
        cols = []
        for tier in range(4):
            dd = sum(v[0] for b, v in rows[a].items() if TIERS.get(b, 0) == tier)
            tt = sum(v[1] for b, v in rows[a].items() if TIERS.get(b, 0) == tier)
            cols.append('%5.2f' % (dd / tt) if tt > 0 else '    -')
        top = sorted(rows[a].items(), key=lambda kv: -kv[1][1])[:4]
        tops = ' '.join('%s:%.2f' % (b, v[0] / v[1]) for b, v in top if v[1] > 0)
        print('%-12s %7.0f %8.2f | %s  %s' % (a, t, d / t, '  '.join(cols), tops))


def main(argv):
    foe = '--foe' in argv
    deaths = '--deaths' in argv
    argv = [a for a in argv if not a.startswith('--')]
    if not argv:
        print(__doc__)
        return 1
    acc = collections.defaultdict(lambda: [0.0, 0.0, 0.0])
    killers = collections.defaultdict(collections.Counter)
    cells = {}
    for p in argv:
        if os.path.isdir(p):
            p = os.path.join(p, 'infolog.txt')
        if p.endswith('apex-record.txt'):
            cells.update(read_matrix(p))
        else:
            read_deaths(p, acc, killers)
    if cells and not deaths:
        print_matrix(cells, foe)
        return 0
    types = sorted({d for d, _ in acc}, key=lambda d: -sum(acc[(d, t)][2] for t in range(4)))
    print('OUR units: damage dealt over own health at death, by killer tier (t0 unknown), top killers')
    print('%-12s %6s %7s | %s' % ('type', 'deaths', 'all', '  '.join('t%d(n)' % t for t in range(4))))
    for d in types:
        tot = [sum(acc[(d, t)][i] for t in range(4)) for i in range(3)]
        if tot[1] <= 0:
            continue
        cols = []
        for t in range(4):
            a = acc[(d, t)]
            cols.append('%5.2f(%3d)' % (a[0] / a[1], a[2]) if a[1] > 0 else '     -    ')
        top = ' '.join('%s:%d' % kv for kv in killers[d].most_common(3)) if killers[d] else ''
        print('%-12s %6d %7.2f | %s  %s' % (d, tot[2], tot[0] / tot[1], '  '.join(cols), top))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
