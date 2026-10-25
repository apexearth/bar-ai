"""Re-read each match's result from its infolog with the current parser and rewrite result.json's outcome fields.
Written for the 10-24 bogus "reason=replayend frame=0" line (barai_replay_export removing itself at load), which
made every match from that afternoon read as no winner.

    python tools/rescore_results.py <match dir or glob> [...] [--dry]"""
import glob
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_match  # noqa: E402


def main():
    args = sys.argv[1:]
    dry = "--dry" in args
    args = [a for a in args if a != "--dry"]
    changed = same = 0
    for a in args:
        for p in sorted(glob.glob(a)):
            d = Path(p)
            rj, log = d / "result.json", d / "infolog.txt"
            if not (rj.exists() and log.exists()):
                continue
            payload = json.loads(rj.read_text(encoding="utf-8"))
            r = run_match.MatchResult()
            run_match.parse_infolog(log.read_text(encoding="utf-8", errors="replace"), r)
            old = payload["result"]
            labels = {t["team"]: t["spec"] for t in payload.get("teams", []) if not t.get("extra")}
            new = {"winners": r.winners, "winner_specs": [labels[w] for w in r.winners if w in labels],
                   "reason": r.reason, "game_frames": r.game_frames, "game_minutes": r.game_minutes}
            if all(old.get(k) == v for k, v in new.items()):
                same += 1
                continue
            changed += 1
            print(f"{d.name}: {old.get('reason')} {old.get('game_minutes')}m {old.get('winner_specs')} -> "
                  f"{new['reason']} {new['game_minutes']}m {new['winner_specs']}")
            if not dry:
                old.update(new)
                rj.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"{changed} rewritten, {same} unchanged" + (" (dry run)" if dry else ""))


if __name__ == "__main__":
    main()
