#!/usr/bin/env python3
"""Queue the recordings made with the packed hit lines (11-18 19:14 .. the widget fix) to be recorded again: each
orders.txt.gz written in that span is renamed orders.packed.txt.gz (kept, not deleted), so public_replays.py follow
and replay_orders.py batch see the replay as not done. Datasets (.npz) built from them stay until the new
recording replaces them.

    python tools/armynet/requeue_packed.py [--dry]
"""
import datetime
import glob
import os
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
START = datetime.datetime(2026, 11, 18, 19, 14).timestamp()
FIXED = (REPO / "tools" / "replay_orders_widget.lua").stat().st_mtime + 300  # a replay launched before the fix finishes after it


def main(a):
    n = 0
    for root in ("G:/bar-ai-archive/public-replays/recordings", "G:/bar-ai-archive/replay-orders"):
        for p in glob.glob(root + "/*/orders.txt.gz"):
            t = os.path.getmtime(p)
            if START <= t < FIXED:
                n += 1
                if "--dry" not in a:
                    os.replace(p, p.replace("orders.txt.gz", "orders.packed.txt.gz"))
    print("%s %d recordings made between %s and the fix (%s)" % ("would requeue" if "--dry" in a else "requeued", n,
          datetime.datetime.fromtimestamp(START), datetime.datetime.fromtimestamp(FIXED)))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
