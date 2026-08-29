"""Withdraw-death forensics: did pulled-back units die in place, walking
home, or walking the WRONG way -- and what was each unit doing before its
fatal retreat.

    python tools/wdeaths.py <tournament-dir | match-dir> [...]

The instrument for the 1v1 campaign's front (1): the W->R->death chain.
Reads apex: unit-destroyed lines (fhist W/R tags carry hp and forward
fraction at each transition) from every infolog under the given dirs.
"""
import glob
import os
import re
import statistics
import sys

DEATH_RE = re.compile(
    r"unit-destroyed (\S+) acts=\S* id=\d+ frame=(\d+) at=-?\d+,-?\d+ "
    r"curTask=\S+ cost=(\d+) fwd=(-?[\d.]+).*?fhist=\[([^\]]*)\]")
W_RE = re.compile(r"W@(\d+):h(\d+):w(-?[\d.]+)")
FIGHT = ["rally", "guard", "defend", "scout", "raid", "attack", "bomb",
         "melee", "arty", "aa", "ah", "support", "super"]


def logs_under(path):
    if os.path.isfile(os.path.join(path, "infolog.txt")):
        return [os.path.join(path, "infolog.txt")]
    return glob.glob(os.path.join(path, "matches", "*", "infolog.txt"))


def before_r(fh):
    prev = "start"
    for part in fh.split(";"):
        if part.startswith("R@"):
            return prev
        tag = part.split("@")[0]
        prev = tag
    return None


def main(paths):
    n = in_place = toward = wrong = 0
    frames, hps, cost = [], [], 0
    pre_r = {}
    for path in paths:
        for f in logs_under(path):
            txt = open(f, encoding="utf-8", errors="replace").read()
            for m in DEATH_RE.finditer(txt):
                fh = m.group(5)
                ws = W_RE.findall(fh)
                # action before the fatal retreat, W'd or not
                if ";R@" in fh or fh.startswith("R@"):
                    tag = before_r(fh)
                    if tag:
                        if tag.startswith("f") and tag[1:].isdigit():
                            i = int(tag[1:])
                            tag = FIGHT[i] if i < len(FIGHT) else tag
                        pre_r[tag] = pre_r.get(tag, 0) + 1
                if not ws:
                    continue
                wf, whp, ww = ws[-1]
                dframes = int(m.group(2)) - int(wf)
                if dframes < 0 or dframes > 3600:
                    continue
                n += 1
                cost += int(m.group(3))
                frames.append(dframes)
                hps.append(int(whp))
                delta = float(ww) - float(m.group(4))
                if delta > 0.05:
                    toward += 1
                elif delta < -0.05:
                    wrong += 1
                else:
                    in_place += 1
    print(f"deaths within 2min of a W order: {n}  ({cost} metal)")
    if n:
        print(f"  died in place:            {in_place} ({100*in_place//n}%)")
        print(f"  died moving toward home:  {toward} ({100*toward//n}%)")
        print(f"  died moving AWAY:         {wrong} ({100*wrong//n}%)")
        print(f"  median W->death: {statistics.median(frames)/30:.0f}s"
              f"   median hp at W: {statistics.median(hps)}")
    if pre_r:
        print("action before fatal retreat:")
        for tag, c in sorted(pre_r.items(), key=lambda kv: -kv[1]):
            print(f"  {tag:10} {c}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1:])
