"""Commander engagements per game: every `commander engaging` line with the
strength ratio (theirs / his), and whether he was dead within 90 s of it."""
import glob, json, os, re, sys

for T in sys.argv[1:]:
    print('==', T)
    for M in sorted(glob.glob(T + '/matches/t*/')):
        if not os.path.exists(M + 'infolog.txt'):
            continue
        txt = open(M + 'infolog.txt', encoding='utf-8', errors='replace').read()
        eng = []
        for m in re.finditer(r'\[f=(\d+)\].*?apex: commander engaging -- T(\d) x(\d+), (\d+) metal.*?at (\d+) of ours, str ([0-9.]+) vs his ([0-9.]+) hp=(\d+)', txt):
            f, tier, n, cost, stake, theirs, mine, hp = m.groups()
            eng.append((int(f), int(tier), int(n), int(cost), int(stake), float(theirs), float(mine), int(hp)))
        fell = re.search(r'\[f=(\d+)\].*?apex: commander fell', txt)
        fellF = int(fell.group(1)) if fell else -1
        name = os.path.basename(M.rstrip('/\\'))[:4] + ' ' + re.sub(r'.*-', '', os.path.basename(M.rstrip('/\\')))[:14]
        won = sum(1 for e in eng if not (fellF > 0 and e[0] <= fellF <= e[0] + 90 * 30))
        fatal = [e for e in eng if fellF > 0 and e[0] <= fellF <= e[0] + 90 * 30]
        s = f"{name:22} engagements={len(eng):2} survived={won:2}"
        if fatal:
            f, tier, n, cost, stake, theirs, mine, hp = fatal[-1]
            r = theirs / mine if mine > 0 else 99
            s += f" FATAL@{fellF/1800:.1f}m T{tier}x{n} {cost}m stake={stake} str-ratio={r:.1f} hp={hp}"
        elif fellF > 0:
            s += f" fell@{fellF/1800:.1f}m (no engagement within 90s)"
        print(s)
