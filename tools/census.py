"""Per-minute side-by-side of [BARAI_CENSUS] lines from a replayed demo.

    python tools/census.py <demo.sdfz>                # replay it headless (~1 min), then read
    python tools/census.py <write-dir or infolog> [--every 2]

Columns per team: metal/energy income, mobile builders (busy), T1/T2 extractors,
then the builder mix. Built for replays of other people's games, where only a
census can be had (the demo's own game archive carries none of our gadgets, so
the census comes from a LuaUI widget in the replay's write dir).
"""
import argparse
import re
import sys
from pathlib import Path

LINE = re.compile(r"\[BARAI_CENSUS\] frame=(\d+) team=(\d+) mInc=([\d.]+) eInc=([\d.]+) "
                  r"builders=(\d+) busy=(\d+) units=(\S*)")
MEX1 = ("armmex", "cormex", "legmex")
MEX2 = ("armmoho", "cormoho", "legmoho", "cormexp", "armamex")
CONS = {"armck": "kbot", "corck": "kbot", "armcv": "veh", "corcv": "veh", "armca": "air", "corca": "air",
        "armack": "kbot2", "corack": "kbot2", "armacv": "veh2", "coracv": "veh2", "armaca": "air2",
        "coraca": "air2", "armcs": "sea", "corcs": "sea", "armrectr": "rez", "cornecro": "rez",
        "armfark": "fark", "corfast": "fast", "armconsul": "consul", "armcom": "com", "corcom": "com"}
FACS = ("lab", "vp", "ap", "alab", "avp", "aap", "shltx", "gant", "sy")


def replay(demo: Path) -> Path:
    import os
    import re as _re
    import shutil
    import subprocess
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import bar_env
    env = bar_env.load()
    if not demo.exists():
        demo = env.data / "demos" / demo.name
    root = Path(__file__).resolve().parent.parent
    wdir = root / "matches" / ("_replay-" + _re.sub(r"[^A-Za-z0-9]+", "-", demo.stem)[:40])
    (wdir / "LuaUI" / "Widgets").mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path(__file__).with_name("replay_census_widget.lua"),
                 wdir / "LuaUI" / "Widgets" / "barai_census.lua")
    shutil.copy2(Path(__file__).with_name("headless.cfg"), wdir / "run.cfg")
    print(f"replaying {demo.name} into {wdir}", flush=True)
    subprocess.run([str(env.headless), "--write-dir", str(wdir), "--config", str(wdir / "run.cfg"), str(demo)],
                   env={**os.environ, "SPRING_DATADIR": str(env.data)},
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3600)
    return wdir


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--every", type=int, default=1)
    a = ap.parse_args()
    p = Path(a.path)
    if p.suffix == ".sdfz":
        p = replay(p)
    log = p / "infolog.txt" if p.is_dir() else p
    rows = {}
    for m in LINE.finditer(log.read_text("utf-8", errors="replace")):
        frame, team = int(m.group(1)), int(m.group(2))
        units = dict((kv.split(":")[0], int(kv.split(":")[1])) for kv in m.group(7).split(",") if ":" in kv)
        rows.setdefault(frame // 1800, {})[team] = (float(m.group(3)), float(m.group(4)),
                                                    int(m.group(5)), int(m.group(6)), units)
    teams = sorted({t for r in rows.values() for t in r})
    print("min | " + " | ".join(f"t{t}: m/s  e/s  cons(busy) mex/moho  facs  builder mix" for t in teams))
    for minute in sorted(rows):
        if minute % a.every:
            continue
        cells = []
        for t in teams:
            if t not in rows[minute]:
                cells.append("-")
                continue
            mi, ei, b, busy, u = rows[minute][t]
            mex1 = sum(u.get(k, 0) for k in MEX1)
            mex2 = sum(u.get(k, 0) for k in MEX2)
            facs = sum(n for k, n in u.items() if any(k.endswith(f) for f in FACS) and k[:3] in ("arm", "cor", "leg"))
            mix = {}
            for k, n in u.items():
                if k in CONS:
                    mix[CONS[k]] = mix.get(CONS[k], 0) + n
            cells.append(f"{mi:5.0f} {ei:6.0f}  {b:3d}({busy:2d})  {mex1:3d}/{mex2:<3d} {facs:2d}  "
                         + " ".join(f"{k}{v}" for k, v in sorted(mix.items())))
        print(f"{minute:3d} | " + " | ".join(cells))
    return 0


if __name__ == "__main__":
    sys.exit(main())
