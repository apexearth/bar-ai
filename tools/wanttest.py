"""What does the AI want under a given economy? Run the real pricing and print it.

    python tools/wanttest.py                 # play one game on your lane, then report
    python tools/wanttest.py --dir <write-dir>   # report an existing run

The game runs with apex_wanttest=1. The first constructor that can build a
fusion-class generator is kept, and once a second the AI's own ProposeEnergy
prices every generator that hand can build with the economy POSED at one row of
market/wanttest.as (metal and energy income; banks half full; histories at
steady state). What stands and what is in flight are the game's own.

Each row prints every generator priced -- value, gain, metal-equivalent cost,
time charge, build seconds -- and the pick. EXPECTATIONS below are apexearth's
calls on what a sane player would build; they live here, in the test, never
in the AI.
"""
import argparse
import glob
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (description, predicate(row_metal_income, picked_def) -> ok)
EXPECTATIONS = [
    ("no Epic Fusion below 800 m/s (apexearth 2026-09-23: 'I wouldn't want one "
     "unless I was at 1,000 metal a second')",
     lambda m, pick: not (m < 800 and pick.endswith("afust3"))),
]

ROW = re.compile(r"apex: wanttest row=(\d+) mInc=(\d+) eInc=(\d+) conv=(\d+) ecoP=(\d+)")
PICK = re.compile(r"apex: wanttest pick row=(\d+) mInc=(\d+) -> (\S+) v=([-\d.]+)")
EWANT = re.compile(
    r"apex: ewant t=\d+ \S+ #\d+ (\S+)( barred)? v=([-\d.]+) close=[-\d.]+ "
    r"gain=([-\d.]+) \(mkE=([-\d.]+) P=([-\d.]+) grow=([-\d.]+) arr=([-\d.]+) "
    r"surv=([-\d.]+) inf=([-\d.]+) real=([-\d.]+)\) m=([-\d.]+) .*? t=([-\d.]+) "
    r".*?build=([-\d.]+)s")


def play(args):
    wd = os.path.join(REPO, "matches", args.out)
    cmd = [sys.executable, "-u", os.path.join(REPO, "tools", "run_match.py"),
           "--a", args.ai, "--b", "BARb:stable:hard",
           "--map", args.map, "--per-side", "2", "--sides", "Armada,Armada",
           "--handicap", "100", "--minutes", str(args.minutes), "--seed", str(args.seed),
           "--modoption", "apex_wanttest=1",
           "--modoption", "experimentalextraunits=1",
           "--modoption", "scavunitsforplayers=1",
           "--write-dir", wd]
    for kv in args.mod:
        cmd += ["--modoption", kv]
    print("wanttest: playing", args.map, "on", args.ai, "...", flush=True)
    subprocess.run(cmd, cwd=REPO, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    return wd


def report(wd):
    info = os.path.join(wd, "infolog.txt")
    if os.path.exists(info):
        errs = len(re.findall(r"\.as \(\d+, \d+\) : ERR",
                              open(info, encoding="utf-8", errors="replace").read()))
        if errs:
            print(f"wanttest: {errs} AngelScript compile error(s) -- the AI did not run; no data")
            return 2
    logs = sorted(glob.glob(os.path.join(wd, "AI", "Skirmish", "**", "apex-t*.log"),
                            recursive=True))
    fails = 0
    ran = False
    for p in logs:
        rows = {}
        cur = None
        for line in open(p, encoding="utf-8", errors="replace"):
            m = ROW.search(line)
            if m:
                cur = int(m.group(1))
                rows[cur] = {"m": int(m.group(2)), "e": int(m.group(3)), "conv": int(m.group(4)),
                             "ecoP": int(m.group(5)), "gens": [], "pick": None}
                continue
            if cur is None:
                continue
            m = EWANT.search(line)
            if m:
                rows[cur]["gens"].append({
                    "def": m.group(1), "barred": bool(m.group(2)),
                    # the log's v= is rounded to 2 places of a ~0.01 number
                    "v": 1000.0 * float(m.group(4))
                         / max(float(m.group(12)) + float(m.group(13)), 1.0),
                    "gain": float(m.group(4)),
                    "mkE": float(m.group(5)), "grow": float(m.group(7)),
                    "arr": float(m.group(8)), "real": float(m.group(11)),
                    "mc": float(m.group(12)), "tc": float(m.group(13)),
                    "bs": float(m.group(14))})
                continue
            m = PICK.search(line)
            if m and int(m.group(1)) == cur:
                rows[cur]["pick"] = m.group(3)
                cur = None
        if not rows:
            continue
        ran = True
        print(f"\n== {os.path.basename(p)}")
        for i in sorted(rows):
            r = rows[i]
            print(f"\n  {r['m']} m/s, {r['e']} e/s, converters {r['conv']} e/s"
                  f"  (economic power {r['ecoP']} m/s)"
                  f"  ->  PICK {r['pick']}")
            print(f"    {'generator':<11} {'value':>7} {'gain':>8} {'cost m':>8} "
                  f"{'time m':>8} {'build s':>8} {'grow':>6} {'arrive':>6} {'real':>5}")
            seen = set()
            for g in sorted(r["gens"], key=lambda g: -g["v"]):
                if g["def"] in seen:
                    continue
                seen.add(g["def"])
                print(f"    {g['def']:<11} {g['v']:>7.2f} {g['gain']:>8.1f} {g['mc']:>8.0f} "
                      f"{g['tc']:>8.0f} {g['bs']:>8.0f} {g['grow']:>6.2f} {g['arr']:>6.2f} "
                      f"{g['real']:>5.2f}" + ("  barred" if g["barred"] else ""))
            for desc, ok in EXPECTATIONS:
                if r["pick"] and not ok(r["m"], r["pick"]):
                    fails += 1
                    print(f"    FAIL  {desc}")
    if not ran:
        print("wanttest: no rows -- no hand that builds a fusion-class generator "
              "elected before the game ended (raise --minutes)")
        return 2
    print(f"\nwanttest: {fails} expectation failure(s)")
    return 1 if fails else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dir", help="report an existing write-dir instead of playing")
    ap.add_argument("--ai", default=None, help="spec; default your lane's")
    ap.add_argument("--map", default="All That Glitters v2.2.3")
    ap.add_argument("--minutes", type=int, default=16)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--mod", action="append", default=[], metavar="K=V",
                    help="extra modoption for the arm, e.g. apex_energy_growth_arrive=1")
    ap.add_argument("--out", default="_wanttest", help="write-dir name under matches/")
    args = ap.parse_args()
    if args.dir:
        return report(args.dir)
    if args.ai is None:
        sys.path.insert(0, os.path.join(REPO, "tools"))
        import lane
        args.ai = f"{lane.short()}:{lane.variant()}:standard"
    return report(play(args))


if __name__ == "__main__":
    sys.exit(main())
