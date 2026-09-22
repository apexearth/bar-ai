"""The labs' effective rate: units and buildtime each side's factories turned
out per 2-minute window, both sides, from the stats gadget's snapshots.

    python tools/labrate.py <tournament-or-match> [--until 8]

Produced = mobile units alive in [BARAI_ARMY] at the window's end plus mobile
deaths ([BARAI_DEATH]) before it, both without commanders; constructors are
not in [BARAI_ARMY], so the count is combat plus scouts and the buildtime is a
floor. Buildtime per factory-second, against the lab's own build power, is
the multiple of nameplate the line ran at -- the number that said BARb's labs
ran at 2-3x in minutes 0-4 while ours ran at 1x (2026-09-22).
"""
import glob, os, re, subprocess, sys, collections, functools

@functools.lru_cache(maxsize=None)
def buildtime(unit):
    out = subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), 'unitdef.py'), unit],
                         capture_output=True, text=True).stdout
    m = re.search(r'buildtime\s+(\d+)', out)
    return int(m.group(1)) if m else 0

def sides(script):
    ai0 = re.search(r'\[AI0\](.*?)\[AI1\]', script, re.S).group(1)
    return 'them' if 'BARb' in ai0 else 'us'   # side of teams 0,1

def one(M, until):
    txt = open(os.path.join(M, 'infolog.txt'), encoding='utf-8', errors='replace').read()
    s01 = sides(open(os.path.join(M, 'script.txt')).read())
    side_of = lambda t: s01 if t < 2 else ('us' if s01 == 'them' else 'them')
    rows = {}
    for fr in range(3600, until * 1800 + 1, 3600):
        alive = collections.defaultdict(list)
        for m in re.finditer(r'\[BARAI_ARMY\] frame=%d team=(\d) n=\d+ part=\d+/\d+ (\S*)' % fr, txt):
            for e in m.group(2).split(','):
                p = e.split(':')
                if len(p) >= 2 and p[1] != 'armcom':
                    alive[side_of(int(m.group(1)))].append(p[1])
        dead = collections.defaultdict(list)
        for m in re.finditer(r'\[BARAI_DEATH\] frame=(\d+) team=(\d) unit=(\S+) cost=\d+ .*? mob=1 ', txt):
            if int(m.group(1)) <= fr and m.group(3) != 'armcom':
                dead[side_of(int(m.group(2)))].append(m.group(3))
        facs = collections.Counter()
        for m in re.finditer(r'\[BARAI_DUTY\] team=(\d) frame=%d facSamp=(\d+) facBusy=(\d+)' % fr, txt):
            facs[side_of(int(m.group(1)))] += int(m.group(2))
        for side in ('us', 'them'):
            units = alive[side] + dead[side]
            bt = sum(buildtime(u) for u in units)
            rows[(fr, side)] = (len(units), bt, facs[side])
    return rows

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    until = 8
    if '--until' in sys.argv:
        until = int(sys.argv[sys.argv.index('--until') + 1])
    for T in args:
        Ms = [T] if os.path.exists(os.path.join(T, 'infolog.txt')) else sorted(glob.glob(os.path.join(T, 'matches', 't*')))
        acc = collections.defaultdict(lambda: [0, 0, 0, 0])
        for M in Ms:
            if not os.path.exists(os.path.join(M, 'result.json')) and len(Ms) > 1:
                continue
            for k, (n, bt, fs) in one(M, until).items():
                a = acc[k]; a[0] += n; a[1] += bt; a[2] += fs; a[3] += 1
        print('==', T)
        print('by    side   units/side  buildtime/side   fac-samples  buildtime per fac-sample')
        for k in sorted(acc):
            n, bt, fs, g = acc[k]
            print(f'{k[0]//1800:3}m  {k[1]:5} {n/g:10.1f} {bt/g:14.0f} {fs/g:12.0f} {bt/max(fs,1):16.1f}')

if __name__ == '__main__':
    main()
