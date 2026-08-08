"""The standard read of a match or tournament. One command, always the same order.

This exists because the reads that get skipped are the ones that matter. Three
times in one session a conclusion was drawn from the wrong slice: a team-level
effect called from 6 of 8 games that reversed at 8; a cause read off the FINAL
snapshot of a collapsing side ("they had more stuff") when the timeline showed
the sides level on mexes until minute 12; and a feature reported as working
because it appeared in a log, having never once completed. apexearth: "you always
get your verdicts wrong ... capture these values over time to get a real
understanding of how the game developed."

So the order here is deliberate, and nothing is optional:

  1. SCRIPT ERRORS   -- an AngelScript error disables the whole variant while the
                        match still runs and reports a normal result. Anything
                        measured after one is measuring stock BARb.
  2. DID IT FIRE     -- per-feature counts. A rule that never ran cannot be the
                        cause of anything, and "it fired" is not evidence it
                        helped.
  3. TIMELINE        -- per-side totals every 2 minutes, and the first sample
                        where each metric diverges. This is the causal picture;
                        the final row is not.
  4. OUTCOME         -- decided record and how many games never finished.

    python tools/report.py <match-or-tournament-dir>
"""
import json
import re
import sys
from pathlib import Path

FRAME_MIN = 1800.0

COLS = [
    ("mex", "mexes"),
    ("metalProduced", "metalProd"),
    ("armyReal", "army"),
    ("mT2", "T2spend"),
    ("mT3", "T3spend"),
    ("mKillReal", "killed"),
    ("mLostReal", "lost"),
    ("mReclaim", "reclaim"),
    ("mRezSpend", "rezSpend"),
]

# Markers worth counting, in the order a game would produce them.
FEATURES = [
    ("tech lead elected", r"apex: tech lead = team"),
    ("eco lead ON", r"apex: ECO LEAD"),
    ("eco lead held off", r"apex: eco lead held off"),
    ("eco nano", r"apex: eco nano"),
    ("eco fusion", r"apex: eco fusion [a-z]"),
    ("eco fusion BLOCKED", r"apex: eco fusion BLOCKED"),
    ("eco converter block", r"apex: eco converter block"),
    ("eco lead aid", r"apex: eco lead aiding"),
    ("gave fusion", r"apex: gave (arm|cor|leg)[a-z]*fus"),
    ("KILLING BLOW on", r"apex: KILLING BLOW ON"),
    ("air assassin armed", r"apex: air assassin armed"),
    ("air: basic plant", r"apex: air assassin building (arm|cor|leg)ap"),
    ("air: air con", r"apex: air assassin building (arm|cor|leg)ca"),
    ("air: adv plant", r"apex: air assassin building (arm|cor|leg)aap"),
    ("air NOT armed", r"apex: air lead NOT armed"),
    # Match the line the code ACTUALLY writes. This pattern was wrong once and
    # reported "never" across two tournaments in which the strike fired every
    # game -- a measurement bug in the tool built to prevent measurement bugs.
    # When a feature reads 0/N, grep the source for the log string before
    # believing it.
    ("air STRIKE released", r"apex: air strike --"),
    ("air stood down", r"apex: air assassin STANDING DOWN"),
    ("late-game air plant", r"apex: late game with no air"),
    ("bot lab for rez", r"apex: no T1 bot lab"),
]

ERR = re.compile(r"[a-z_]+\.as \(\d+, \d+\) : ERR .{0,80}", re.I)


def games(root: Path):
    if (root / "result.json").exists():
        return [root]
    return sorted(p.parent for p in root.glob("**/result.json"))


def apex_ally(r):
    specs = {t["team"]: t["spec"] for t in r["teams"]}
    return 0.0 if "Apex" in str(specs.get(0, "")) else 1.0


def series(d: Path):
    r = json.loads((d / "result.json").read_text())
    ally = apex_ally(r)
    by_frame = {}
    for row in r.get("stats", []):
        by_frame.setdefault(int(row["frame"]), []).append(row)
    out = []
    for f in sorted(by_frame):
        rows = by_frame[f]
        ours = [x for x in rows if x.get("ally") == ally]
        theirs = [x for x in rows if x.get("ally") != ally]
        if not ours or not theirs:
            continue
        agg = lambda rs, k: sum(float(x.get(k, 0) or 0) for x in rs)
        out.append((f / FRAME_MIN,
                    {k: agg(ours, k) for k, _ in COLS},
                    {k: agg(theirs, k) for k, _ in COLS}))
    return out


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    root = Path(sys.argv[1])
    gs = games(root)
    if not gs:
        print(f"no games under {root}")
        return 2

    print(f"=== {root.name} -- {len(gs)} game(s) ===")

    # 1. SCRIPT ERRORS. Loud, and first, because everything else is void if set.
    errs = {}
    for d in gs:
        log = d / "infolog.txt"
        if not log.exists():
            continue
        for m in ERR.findall(log.read_text(errors="ignore")):
            errs[m.strip()] = errs.get(m.strip(), 0) + 1
    print("\n[1] SCRIPT ERRORS")
    if errs:
        print("    *** THE VARIANT WAS DISABLED. Everything below measures stock BARb. ***")
        for e, n in sorted(errs.items(), key=lambda kv: -kv[1])[:10]:
            print(f"    {n:>4}x {e}")
    else:
        print("    none")

    # 2. DID IT FIRE.
    print("\n[2] DID IT FIRE  (games it appeared in / total, and total occurrences)")
    texts = []
    for d in gs:
        log = d / "infolog.txt"
        texts.append(log.read_text(errors="ignore") if log.exists() else "")
    for label, pat in FEATURES:
        rx = re.compile(pat)
        hits = [len(rx.findall(t)) for t in texts]
        ingames = sum(1 for h in hits if h)
        total = sum(hits)
        flag = "" if ingames else "   <-- never"
        print(f"    {label:<22} {ingames:>2}/{len(gs)}  {total:>6}{flag}")

    # 3. TIMELINE.
    allser = [s for s in (series(d) for d in gs) if s]
    print("\n[3] TIMELINE  (per side, mean across games, to the shortest game)")
    if allser:
        n = min(len(s) for s in allser)
        head = f"    {'min':>4}"
        for _, label in COLS:
            head += f"{label:>20}"
        print(head)
        print(f"    {'':>4}" + "".join(f"{'apex / stock':>20}" for _ in COLS))
        crossed = {}
        for i in range(n):
            mins = sum(s[i][0] for s in allser) / len(allser)
            line = f"    {mins:>4.0f}"
            for k, _ in COLS:
                a = sum(s[i][1][k] for s in allser) / len(allser)
                b = sum(s[i][2][k] for s in allser) / len(allser)
                line += f"{a:>8,.0f} /{b:>10,.0f}"
                if k != "lost" and k not in crossed and b > a * 1.15 and b > 0:
                    crossed[k] = mins
            print(line)
        print("\n    first sample where stock leads by 15%:")
        for k, label in COLS:
            if k == "lost":
                continue
            when = f"{crossed[k]:.0f} min" if k in crossed else "never"
            print(f"      {label:<12} {when}")

    # 4. OUTCOME.
    W = L = U = 0
    for d in gs:
        res = json.loads((d / "result.json").read_text())["result"]
        ws = res.get("winner_specs") or []
        if not ws:
            U += 1
        elif any("Apex" in s for s in ws):
            W += 1
        else:
            L += 1
    print(f"\n[4] OUTCOME  apex {W}-{L}, {U} undecided ({U/len(gs)*100:.0f}% never finished)")
    if U > len(gs) / 2:
        print("    more than half never finished -- dominance that does not convert")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
