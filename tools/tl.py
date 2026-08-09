#!/usr/bin/env python3
"""Timeline of apex vs the other AI across a tournament, binned by game minute.

Which side is which is read from script.txt per match (tournaments swap sides),
so this never averages us against ourselves the way fight1v1 once did.

    python tools/tl.py tournaments/<run>            [subject-shortname]
"""
from __future__ import annotations
import re, sys
from pathlib import Path
from collections import defaultdict

FIELDS = ["metalProduced", "armyReal", "mex", "t2Mex", "mCon", "mDefence",
          "mLostReal", "mKillReal", "mT2", "mFactories"]


def subject_ally(script: Path, subject: str) -> dict[int, int]:
    """team id -> 1 if that team is the subject AI, else 0."""
    txt = script.read_text("utf-8", errors="replace")
    out = {}
    for blk in re.finditer(r"\[AI(\d+)\]\s*\{(.*?)\}", txt, re.S):
        body = blk.group(2)
        team = int(re.search(r"Team\s*=\s*(\d+)", body).group(1))
        name = re.search(r"ShortName\s*=\s*(\S+?)\s*;", body).group(1)
        out[team] = 1 if name.lower() == subject.lower() else 0
    return out


def main() -> int:
    run = Path(sys.argv[1])
    subject = sys.argv[2] if len(sys.argv) > 2 else "Apex"
    matches = sorted((run / "matches").glob("t*")) if (run / "matches").is_dir() else [run]

    # bin -> side -> field -> [values]
    acc: dict = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    tech = {0: [], 1: []}
    for m in matches:
        log, scr = m / "infolog.txt", m / "script.txt"
        if not log.exists() or not scr.exists():
            continue
        who = subject_ally(scr, subject)
        seen = {0: {}, 1: {}}
        # frame -> side -> row. A dead team stops reporting, so a bin that
        # counted whatever samples exist would compare live stock against
        # nothing; only frames where BOTH sides reported are used.
        byframe: dict = defaultdict(dict)
        for hit in re.finditer(r"\[BARAI_STATS\] (.*)", log.read_text("utf-8", errors="replace")):
            d = dict(t.split("=", 1) for t in hit.group(1).split() if "=" in t)
            team = int(d["team"])
            if team not in who:
                continue
            side = who[team]
            byframe[int(d["frame"])][side] = d
            ts = float(d.get("techStart", -1))
            if ts >= 0:
                seen[side].setdefault("tech", ts)
        for frame, pair in byframe.items():
            if 0 not in pair or 1 not in pair:
                continue
            b = (frame // 30 // 60 // 4) * 4
            for side in (0, 1):
                for f in FIELDS:
                    try:
                        acc[b][side][f].append(float(pair[side][f]))
                    except (KeyError, ValueError):
                        pass
        for s in (0, 1):
            if "tech" in seen[s]:
                tech[s].append(seen[s]["tech"] / 30 / 60)

    def med(v):
        v = sorted(v)
        return v[len(v) // 2] if v else float("nan")

    print(f"matches {len(matches)}   subject={subject} (side 1) vs other (side 0)")
    print(f"tech start (min, median): subject {med(tech[1]):.1f}  other {med(tech[0]):.1f}"
          f"   n={len(tech[1])}/{len(tech[0])}")
    hdr = "min  " + "".join(f"{f:>22}" for f in FIELDS)
    print(hdr)
    for b in sorted(acc):
        row = f"{b:3d}  "
        for f in FIELDS:
            a = acc[b][1][f]
            o = acc[b][0][f]
            if not a or not o:
                row += f"{'-':>22}"
            else:
                row += f"{sum(a)/len(a):>10.0f}/{sum(o)/len(o):<11.0f}"
        print(row)
    return 0


if __name__ == "__main__":
    sys.exit(main())
