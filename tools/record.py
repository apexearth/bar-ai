"""The unit track record, read off a run or a record file.

    python tools/record.py <match-dir|infolog|apex-record.txt> [...]
    python tools/record.py --foe <match-dir|apex-record-foe.txt> [...]   # THEIR units, vs what of ours killed them

Per type: damage dealt over own health, by the tier of what killed it (t0 =
unknown killer), and the top killers. Pass a run BEFORE a file so the file's
killers get their tiers from the log lines. Fodder and fighters are listed but the
price never reads them (worth.as RecordMul).
"""
import collections
import os
import re
import sys

LINE = re.compile(r'apex: record (\S+) died dealt=(\S+) hp=(\S+) .*killed-by=(\S+) t(\d)')
FOE_LINE = re.compile(r'apex: record-foe (\S+) died dealt=(\S+) hp=(\S+) .*killed-by=(\S+)')
TIERS = {}  # killer name -> tier, learned from the log lines


def read_log(path, acc, killers, foe=False):
    for line in open(path, errors='replace'):
        m = (FOE_LINE if foe else LINE).search(line)
        if not m:
            continue
        d, dealt, hp, killer = m.group(1), float(m.group(2)), float(m.group(3)), m.group(4)
        tier = 0 if foe else int(m.group(5))
        if not foe:
            TIERS[killer] = tier
        a = acc[(d, tier)]
        a[0] += dealt
        a[1] += hp
        a[2] += 1
        killers[d][killer] += 1


def read_file(path, acc, killers):
    """name killer dealt health n; killer '-' unknown. Older lines carry a
    numeric tier instead of a killer, or no second field at all."""
    for line in open(path):
        parts = line.split()
        if len(parts) == 5:
            name, killer, dealt, hp, n = parts[0], parts[1], float(parts[2]), float(parts[3]), float(parts[4])
            tier = int(killer) if killer.isdigit() else TIERS.get(killer, 0)
            if killer.isdigit():
                killer = '-'
        elif len(parts) == 4:
            name, killer, tier, dealt, hp, n = parts[0], '-', 0, float(parts[1]), float(parts[2]), float(parts[3])
        else:
            continue
        a = acc[(name, tier)]
        a[0] += dealt
        a[1] += hp
        a[2] += n
        if killer != '-':
            killers[name][killer] += int(n)


def main(argv):
    foe = '--foe' in argv
    argv = [a for a in argv if a != '--foe']
    if not argv:
        print(__doc__)
        return 1
    acc = collections.defaultdict(lambda: [0.0, 0.0, 0.0])
    killers = collections.defaultdict(collections.Counter)
    for p in argv:
        if os.path.isdir(p):
            p = os.path.join(p, 'infolog.txt')
        if os.path.isdir(os.path.dirname(p)) and foe and p.endswith('infolog.txt'):
            read_log(p, acc, killers, foe=True)
        elif p.endswith('apex-record.txt') or p.endswith('apex-record-foe.txt'):
            read_file(p, acc, killers)
        else:
            read_log(p, acc, killers)
    types = sorted({d for d, _ in acc}, key=lambda d: -sum(acc[(d, t)][2] for t in range(4)))
    print(('THEIR units, dealt to us over own health, vs what of ours killed them' if foe else 'OUR units, dealt over own health, by killer tier')
          + ('  (a fog shooter reads low; "-" = killer already dead)' if foe else ''))
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
