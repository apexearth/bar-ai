"""The spend table: mean income, mexes, standing army, front, spend by category
and metal lost per 4-minute bucket, us vs them, over every game of a tournament.

    python tools/spendtable.py <tournament-dir> [<tournament-dir> ...]

Reads story.py per match; \"us\" is whichever side is not BARb. This is the read
that shows WHERE a batch is lost (the 16-24 bucket, the 8-12 bucket) before
any win count is trusted -- an 8-game 2v2 arm swings 0-8 to 4-4 on one tree."""
import subprocess,sys,glob,re,os
def f(x):
    try: return float(x)
    except: return 0.0
for T in sys.argv[1:]:
    acc={}
    for M in sorted(glob.glob(T+'/matches/t*/')):
        if not os.path.exists(M+'result.json'): continue
        out=subprocess.run([sys.executable,'tools/story.py',M,'--bucket','240'],capture_output=True,text=True).stdout
        h=re.search(r'A = (\S+)\s+B = (\S+)',out)
        if not h: continue
        amap={'A':'them' if 'BARb' in h.group(1) else 'us','B':'them' if 'BARb' in h.group(2) else 'us'}
        for line in out.splitlines():
            m=re.match(r'\s*([\d.]+) \| (\S+)\s+\|\s+(\d+)\s+(\S+)\s+\S+\s+\|\s+(\d+)\s+(\S+) \| (\S+)\s+\|\s+(\d+)',line)
            if not m: continue
            by,side,inc,mex,army,front,spent,lost=m.groups()
            side=amap[side]
            sp=[int(x) for x in spent.split('/')] if '/' in spent else [0,0,0,0]
            mexn=int(re.match(r'\d+',mex).group(0))
            acc.setdefault((float(by),side),[]).append([int(inc),mexn,int(army),f(front)]+sp+[int(lost)])
    print('==',T)
    print('by   side n   inc  mex  army front |  arm   eco   def    bp | lost')
    for by in (4.0,8.0,12.0,16.0,20.0,24.0):
        for side in ('us','them'):
            rows=acc.get((by,side),[])
            if not rows: continue
            n=len(rows); m=[sum(r[i] for r in rows)/n for i in range(9)]
            print(f'{by:4.0f} {side:4} {n:2} {m[0]:5.0f} {m[1]:4.1f} {m[2]:5.0f} {m[3]:5.2f} | {m[4]:5.0f} {m[5]:5.0f} {m[6]:5.0f} {m[7]:5.0f} | {m[8]:5.0f}')
