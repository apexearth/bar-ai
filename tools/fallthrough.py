"""Per-game mechanism census for the interior-gun fix: refusals, fallthrough
executions, what the fallthroughs bought, and the energy overbuild at 8 min."""
import glob, json, os, re, sys

def census(T):
    rows = []
    for M in sorted(glob.glob(T + '/matches/t*/')):
        if not os.path.exists(M + 'infolog.txt'):
            continue
        txt = open(M + 'infolog.txt', encoding='utf-8', errors='replace').read()
        s = open(M + 'script.txt').read()
        ai0 = re.search(r'\[AI0\](.*?)\[AI1\]', s, re.S).group(1)
        t = '0' if 'Apex' in ai0 else '1'
        ref = re.findall(r'interior-gun refused t=' + t + r' .*?-- (\d+) refused', txt)
        ref = int(ref[-1]) if ref else 0
        execs = re.findall(r'\[f=(\d+)\].*?apex: exec t=' + t + r' \S+ #\d+ (\S+) pick=(\d+)', txt)
        early = [e for e in execs if int(e[0]) < 10 * 1800]
        fall = [e for e in early if int(e[2]) > 0]
        fallE = sum(1 for e in fall if e[1].split(':')[0] in ('energy', 'convert', 'geo'))
        conv = sum(1 for e in early if e[1].startswith('convert:'))
        ener = sum(1 for e in early if e[1].split(':')[0] in ('energy', 'geo'))
        mexes = sum(1 for e in early if e[1].startswith('mex:'))
        # energy income vs use at 8.0m
        m8 = re.search(r'\[8\.0m t' + t + r'\] apex: energy cur=\S+ inc=(\d+) pull=(\d+) use=(\d+)', txt)
        eInc, eUse = (int(m8.group(1)), int(m8.group(3))) if m8 else (0, 0)
        gate = re.findall(r'site\.interior=(\d+)/(\d+)', txt)
        name = os.path.basename(M.rstrip('/\\'))[:4] + ' ' + re.sub(r'.*-', '', os.path.basename(M.rstrip('/\\')))[:12]
        rows.append((name, ref, len(early), len(fall), fallE, conv, ener, mexes, eInc, eUse))
    return rows

for T in sys.argv[1:]:
    print('==', T)
    print(f"{'game':18} interior fall/execs<10m fall->energy conv<10m energy<10m mex<10m  eInc/eUse@8m")
    tot = [0] * 9
    rows = census(T)
    for r in rows:
        print(f"{r[0]:18} {r[1]:8} {r[3]:4}/{r[2]:<9} {r[4]:11} {r[5]:8} {r[6]:10} {r[7]:7}  {r[8]:5}/{r[9]}")
        for i in range(9):
            tot[i] += r[i + 1]
    n = max(len(rows), 1)
    print(f"{'MEAN':18} {tot[0]/n:8.1f} {tot[2]/n:4.1f}/{tot[1]/n:<9.1f} {tot[3]/n:11.1f} {tot[4]/n:8.1f} {tot[5]/n:10.1f} {tot[6]/n:7.1f}  {tot[7]/n:5.0f}/{tot[8]/n:.0f}")
