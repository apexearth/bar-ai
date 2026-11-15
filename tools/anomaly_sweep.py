"""Every finished game on disk through the anomaly detector: which kinds of anomaly, how often, in which AI, with the
worst examples of each -- the list to root-cause (his 11-14: "how many issues you have caught ... and then have you done
any work to try to fix the behavior").

    python tools/anomaly_sweep.py                 # all finished normal games, every Apex seat
    python tools/anomaly_sweep.py --ai lane-      # our test lanes only
"""
from __future__ import annotations

import argparse
import collections
import glob
import json
import sys
from pathlib import Path

import anomaly

REPO = Path(__file__).resolve().parent.parent


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--ai", default="")
    ap.add_argument("--z", type=float, default=5.0)
    ap.add_argument("--examples", type=int, default=3)
    a = ap.parse_args(argv)
    base_ai = anomaly.latest_release()
    base = json.loads((anomaly.BASE / ("baseline-%s.json" % base_ai)).read_text())["features"]
    kinds = collections.defaultdict(list)   # (feature kind, direction) -> [(z, match, team, ai, minute, value, normal)]
    seats = flagged = 0
    by_ai = collections.Counter()
    by_ai_flag = collections.Counter()
    for rj in sorted(glob.glob(str(REPO / "matches" / "*" / "result.json"))):
        p = Path(rj).parent
        try:
            for t, ai, rs, res in anomaly.seats(p):
                if a.ai not in ai or "Apex" not in json.dumps(res.get("teams", [])):
                    continue
                if "--randomizer" in (res.get("argv") or []):
                    continue
                sides = res.get("sides") or []
                rg = anomaly.regime(res, sides[t] if t < len(sides) else "?")
                seats += 1
                by_ai[ai] += 1
                hit = False
                for k, v in anomaly.features(rs).items():
                    b = base.get(rg + "|" + k)
                    if not b:
                        continue
                    floor = 0.05 if k.endswith("share") else 0.5
                    z = (v - b["median"]) / max(1.4826 * b["mad"], floor)
                    if abs(z) >= a.z:
                        kind = k[4:] if k[:2].isdigit() else k
                        minute = k[:3] if k[:2].isdigit() else ""
                        kinds[(kind, "high" if z > 0 else "low")].append((abs(z), p.name, t, ai, minute, v, b["median"], k))
                        hit = True
                if hit:
                    flagged += 1
                    by_ai_flag[ai] += 1
        except Exception:
            continue
    print("swept %d seats in %d AIs; %d anomalous (z >= %.0f vs %s's normal in the same regime)"
          % (seats, len(by_ai), flagged, a.z, base_ai))
    for ai, n in by_ai.most_common(8):
        print("  %-22s %4d seats, %3d anomalous (%.0f%%)" % (ai, n, by_ai_flag[ai], 100.0 * by_ai_flag[ai] / max(1, n)))
    print("\nkinds, by seats affected:")
    for (kind, d), hits in sorted(kinds.items(), key=lambda kv: -len({(h[1], h[2]) for h in kv[1]})):
        n = len({(h[1], h[2]) for h in hits})
        print("  %-22s %-4s %3d seat(s)" % (kind, d, n))
        for h in sorted(hits, reverse=True)[:a.examples]:
            print("      %s t%d %s %s: %s (normal %s, z %.0f)" % (h[1], h[2], h[3], h[4].strip(), anomaly.shown(h[7], h[5]),
                                                               anomaly.shown(h[7], h[6]), h[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
