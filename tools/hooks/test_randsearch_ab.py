"""The A/B readout pairs arm B with arm A by game index: python tools/hooks/test_randsearch_ab.py"""
import contextlib
import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import randsearch  # noqa: E402

A = {"id": 10, "arm": "A", "ab": "apex_x=1", "pair": [10, 11], "of": 3, "status": "done",
     "games": [[-1.0, "L", "v", 0], [0.5, "W", "v", 1], [-0.5, "L", "v", 2]]}
B = {"id": 11, "arm": "B", "ab": "apex_x=1", "pair": [10, 11], "of": 3, "status": "done",
     "games": [[0.5, "W", "v", 2], [-0.5, "L", "v", 0], [1.0, "W", "v", 1], [0.9, "W", "v", 7]]}
st = {"nets": {"10": A, "11": B}}
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    randsearch.ab_report(st)
out = buf.getvalue()
# pairs by index 0,1,2 (B's game 7 has no twin): diffs +0.5, +0.5, +1.0 -> mean +0.67
ok = "3 pairs" in out and "B - A score +0.67" in out and "A 1.0 of 3 wins, B 3.0 of 4" in out
print(out.strip())
print("ok" if ok else "WRONG")
sys.exit(0 if ok else 1)
