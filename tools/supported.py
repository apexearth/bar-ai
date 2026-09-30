"""What became of each mex spot a builder asked the army to clear.

    python tools/supported.py <match> [--r 500]

Reads `apex: support call|done` and the BARAI_POS snapshots. For each call:
how it closed (claimed / cooled / lost / open at the end), and for claimed
spots whether our mex stood there, when a defence first stood within --r of
it, and when the mex was last seen.
"""
import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402
import unitdef  # noqa: E402

FPS = 30
CALL = re.compile(r"\[f=(\d+)\].*apex: support call t=(\d+) spot=(\d+) at=(\d+),(\d+) worth=(\d+)")
DONE = re.compile(r"\[f=(\d+)\].*apex: support done t=(\d+) spot=(\d+)(?: at=\S+)? why=(\w+)")
POS = re.compile(r"\[BARAI_POS\] team=(\d+) ally=(\d+) frame=(\d+) n=\d+ (?:part=\d+/\d+ )?(\S*)")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("match")
    ap.add_argument("--r", type=float, default=500.0, help="defence radius around the spot")
    args = ap.parse_args()
    text = (Path(args.match) / "infolog.txt").read_text("utf-8", errors="replace")
    game, _ = unitdef.trees(bar_env.load())
    kind = {}

    def is_def(name):
        if name not in kind:
            p = game.find(name)
            kind[name] = (p is not None) and ("Defen" in str(p)) and ("Buildings" in str(p))
        return kind[name]

    calls = {}
    for f, t, s, x, z, w in CALL.findall(text):
        calls[(int(t), int(s))] = {"f": int(f), "x": int(x), "z": int(z), "worth": int(w), "why": "open", "df": None}
    for f, t, s, why in DONE.findall(text):
        c = calls.get((int(t), int(s)))
        if c is not None and c["df"] is None:
            c["why"], c["df"] = why, int(f)
    # snapshots: frame -> ally -> [(name, x, z)]
    snaps = defaultdict(lambda: defaultdict(list))
    ally_of = {}
    for t, a, f, data in POS.findall(text):
        ally_of[int(t)] = int(a)
        for tok in data.split(","):
            p = tok.split(":")
            if len(p) >= 3:
                snaps[int(f)][int(a)].append((p[0], int(p[1]), int(p[2])))
    frames = sorted(snaps)
    r2 = args.r * args.r

    def near(items, x, z, rr, pred):
        return any(pred(n) and (ix - x) ** 2 + (iz - z) ** 2 <= rr for n, ix, iz in items)

    print("team spot   call   done  why       worth   mexSeen  defFirst  mexLast")
    tally = defaultdict(int)
    for (t, s), c in sorted(calls.items(), key=lambda kv: kv[1]["f"]):
        tally[c["why"]] += 1
        a = ally_of.get(t, -1)
        seen = first_def = last = None
        if c["why"] == "claimed":
            for fr in frames:
                if fr < c["df"]:
                    continue
                items = snaps[fr].get(a, [])
                if near(items, c["x"], c["z"], 64 * 64, lambda n: n.endswith(("mex", "moho")) or "mex" in n):
                    seen = seen if seen is not None else fr
                    last = fr
                if first_def is None and near(items, c["x"], c["z"], r2, is_def):
                    first_def = fr
            if seen is not None:
                tally["mex stood"] += 1
            if first_def is not None:
                tally["defended"] += 1
        m = lambda v: "-" if v is None else "%.1f" % (v / FPS / 60)
        print("%4d %4d %6s %6s  %-8s %6d %8s %9s %8s" % (
            t, s, m(c["f"]), m(c["df"]), c["why"], c["worth"], m(seen), m(first_def), m(last)))
    print("\n" + "  ".join("%s=%d" % kv for kv in sorted(tally.items())))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
