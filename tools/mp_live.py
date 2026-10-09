#!/usr/bin/env python3
"""Watch his hosted multiplayer games while he plays.

    python tools/mp_live.py

Every 15 s, reading only what the games already write:
  - data/infolog*.txt: a "Sync error for" line (the engine's only desync
    signal; the game plays on looking normal) -> ALERT, exit 2
  - our bots' logs (data/AI/Skirmish/Apex*/*/apex-tN.log): an AngelScript
    error or exception -> ALERT, exit 3
  - the same logs: each strategy pick, team push, air plant count and lobby
    option a bot read -> runtime/mp_live/<date>.txt, for the review after
Exits only on an alert, so whoever started it is woken by exactly that.
"""
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
NOTE = re.compile(r"apex: (?:nnplan t=\d+ .*?chosen=\S+|plan t=\d+ follows \S+|push go .*|nnval head=aplant t=\d+ f=\d+ v=\S+"
                  r"|tunable-opt .*|persona t=\d+ rolled.*)")
ERR = re.compile(r": ERR  :|[Ee]xception|Script error")


def main():
    env = bar_env.load()
    out = REPO / "runtime" / "mp_live"
    out.mkdir(parents=True, exist_ok=True)
    rec = out / (time.strftime("%Y%m%d") + ".txt")
    seen = {}

    def new_lines(p):
        try:
            size = p.stat().st_size
        except OSError:
            return []
        at = seen.get(p, 0)
        if size < at:   # rotated: a new game
            at = 0
        if size == at:
            seen[p] = at
            return []
        with open(p, "rb") as fh:
            fh.seek(at)
            data = fh.read(size - at)
        seen[p] = size
        return data.decode("utf-8", "replace").splitlines()

    # what is already written belongs to earlier games; a log that appears later is read whole
    for p in list(env.data.glob("infolog*.txt")) + list((env.data / "AI" / "Skirmish").glob("Apex*/*/apex-t*.log")):
        seen[p] = p.stat().st_size
    print("watching %s and the bots' logs; notes -> %s" % (env.data, rec), flush=True)
    while True:
        for p in env.data.glob("infolog*.txt"):
            for ln in new_lines(p):
                if "Sync error for" in ln:
                    print("ALERT desync: %s  (%s)" % (ln.strip()[:200], p.name), flush=True)
                    return 2
                # the AngelScript compiler reports to the engine log, not the bot's
                if ": ERR  :" in ln or ("Skirmish AI" in ln and "xception" in ln):
                    print("ALERT AI error: %s  (%s)" % (ln.strip()[:220], p.name), flush=True)
                    return 3
        for p in sorted((env.data / "AI" / "Skirmish").glob("Apex*/*/apex-t*.log")):
            if p.name.endswith(".prev.log"):
                continue
            lines = new_lines(p)
            notes = []
            for ln in lines:
                if ERR.search(ln):
                    print("ALERT AI error in %s/%s: %s" % (p.parent.name, p.name, ln.strip()[:220]), flush=True)
                    return 3
                m = NOTE.search(ln)
                if m:
                    notes.append("%s %s %s" % (time.strftime("%H:%M:%S"), p.name, m.group(0)[:200]))
            if notes:
                with open(rec, "a", encoding="utf-8") as fh:
                    fh.write("\n".join(notes) + "\n")
        time.sleep(15)


if __name__ == "__main__":
    raise SystemExit(main())
