"""Opening means per tournament: ours vs theirs at the given minutes, from
tools/opening.py. Usage: opening_ab.py <tournament-dir> [4,8,12]"""
import subprocess, sys, glob, json, os, re
T = sys.argv[1]
mins = [int(x) for x in (sys.argv[2].split(',') if len(sys.argv) > 2 else ['4', '8', '12'])]
rows = []
for M in sorted(glob.glob(T + '/matches/t*/')):
    if not os.path.exists(M + 'result.json'):
        continue
    r = json.load(open(M + 'result.json'))
    s = open(M + 'script.txt').read()
    ai0 = re.search(r'\[AI0\](.*?)\[AI1\]', s, re.S).group(1)
    ours = 0 if 'Apex' in ai0 else 1
    out = subprocess.run([sys.executable, 'tools/opening.py', M], capture_output=True, text=True).stdout
    name = os.path.basename(M.rstrip('/\\'))[:4] + ' ' + r['map'][:12]
    for line in out.splitlines():
        if line.count('|') < 4 or not line.split('|')[0].strip().isdigit():
            continue
        parts = [p.split() for p in line.split('|')]
        mn = int(parts[0][0])
        a0 = parts[1] + parts[2]
        a1 = parts[3] + parts[4]
        us, them = (a0, a1) if ours == 0 else (a1, a0)
        if mn in mins:
            rows.append((name, mn, us, them))
print(f"{'game':18} min | ours: mex  m/s   e/s armed  built | theirs: mex m/s   e/s armed  built")
for name, mn, us, them in rows:
    print(f"{name:18} {mn:3} | {us[0]:>4} {us[1]:>4} {us[2]:>5} {us[4]:>4} {us[6]:>6} | {them[0]:>4} {them[1]:>4} {them[2]:>5} {them[4]:>4} {them[6]:>6}")
