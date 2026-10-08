#!/usr/bin/env python3
"""Extract every replay in data/demos, newest first, a few at a time.

    python tools/replay_batch.py [--workers 2] [--limit N]

Each goes to runtime/replays/<demo stem>/ (tools/replay_extract.py); one done
already is skipped, so a stopped batch resumes; an empty result (a run that
died under memory pressure) is retried up to three times. Pauses
while a windowed game of his is running.
"""
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402
import mp_archive  # noqa: E402
import replay_extract  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "runtime" / "replays"


def one(demo):
    out = OUT / demo.stem
    tries = 0
    if (out / "replay_meta.json").is_file():
        old = json.loads((out / "replay_meta.json").read_text())
        tries = old.get("tries", 1)
        # an empty run under memory pressure dies in seconds: try again, a few times
        if old.get("events", 0) > 0 or tries >= 3:
            return None
    while mp_archive.his_game_running():
        time.sleep(60)
    t0 = time.time()
    try:
        meta = replay_extract.extract(str(demo), out, timeout=5400)
    except Exception as e:  # noqa: BLE001
        print("FAILED %s: %r" % (demo.name, e), flush=True)
        return None
    meta["tries"] = tries + 1
    (out / "replay_meta.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")
    print("%s: %s %s events=%d winners=%s ais=%d players=%d %.0fs" % (
        demo.stem[:40], meta.get("map"), meta.get("game"), meta.get("events", 0), meta.get("winners"),
        len(meta.get("ais") or []), len(meta.get("players") or []), time.time() - t0), flush=True)
    return meta


def main(argv):
    workers = int(argv[argv.index("--workers") + 1]) if "--workers" in argv else 2
    limit = int(argv[argv.index("--limit") + 1]) if "--limit" in argv else 0
    env = bar_env.load()
    demos = sorted(env.demos.glob("*.sdfz"), key=lambda p: -p.stat().st_mtime)
    if limit:
        demos = demos[:limit]
    print("%d replays, %d workers" % (len(demos), workers), flush=True)
    with ThreadPoolExecutor(max_workers=workers) as ex:
        list(ex.map(one, demos))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
