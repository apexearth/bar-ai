#!/usr/bin/env python3
"""Re-read finished games for named decision heads only.

    python tools/nn_backfill.py --heads esc,con,mex,cap,acap,plan --since 2026-10-06

For a head that was starved of rows (2026-10-07: the clocked heads keyed their
used rows by team and first decision frames, which every game shares, so after
one game every later one read as already learned). Stop the live trainer first
-- both write runtime/nn. BARAI_NN_PARSE=N parses in N processes. Exports the
weights at the end unless BARAI_NN_NOEXPORT is set.
"""
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import decisions  # noqa: E402
import nntrain  # noqa: E402

REPO = Path(__file__).resolve().parent.parent


def main(argv):
    if "--heads" not in argv or "--since" not in argv:
        print(__doc__)
        return 1
    names = argv[argv.index("--heads") + 1].split(",")
    since = datetime.strptime(argv[argv.index("--since") + 1], "%Y-%m-%d").timestamp()
    tr = nntrain.Trainer()
    heads = {n: tr.heads[n] for n in names if n in tr.heads}
    missing = [n for n in names if n not in tr.heads]
    if missing:
        print("unknown heads:", missing)
        return 1
    tags = ["apex: nn%s t=" % n for n in names]
    games = []
    for t in (REPO / "tournaments").glob("*"):
        if not (t / "matches").is_dir():
            continue
        for d in (t / "matches").iterdir():
            res, log = d / "result.json", d / "infolog.txt"
            if not res.is_file() or not log.is_file() or res.stat().st_mtime < since:
                continue
            games.append((res.stat().st_mtime, str(d.relative_to(REPO)), d))
    games.sort()
    print("%d finished games since %s; heads %s" % (len(games), argv[argv.index("--since") + 1], names), flush=True)
    t0 = time.time()
    n = learned = 0
    rows = {k: 0 for k in heads}
    for key, d, g in nntrain.parsed_in_order(games):
        n += 1
        if g is None:
            continue
        for name, head in heads.items():
            h = g.get("heads", {}).get(name)
            if not h:
                continue
            rec = tr.learn_head(head, h["keys"], h["rows"], decisions.head_rows_of(str(d), g, name), key, g, True)
            if rec:
                learned += 1
                rows[name] += rec.get("rows", 0)
        if n % 50 == 0:
            print("%d/%d games, %d head batches, rows %s, %.0fs" % (n, len(games), learned, rows, time.time() - t0), flush=True)
    tr.save()
    if not nntrain.NO_EXPORT:
        tr.export()
    print("done: %d games, %d head batches, rows %s, trust %s" % (
        n, learned, rows, {k: h.trust() for k, h in heads.items()}), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
