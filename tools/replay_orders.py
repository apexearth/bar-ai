#!/usr/bin/env python3
"""Record a replay for learning army control: every order, what each team could see, deaths, damage.

    python tools/replay_orders.py one <demo.sdfz> <out_dir> [max_game_minutes]
    python tools/replay_orders.py batch [--workers 2] [--limit N] [--out G:/bar-ai-archive/replay-orders]

The widget (tools/replay_orders_widget.lua) writes orders.txt, gzipped to orders.txt.gz:
    V 2 mapX mapZ
    D defid name class metal hp speed range ground_dps aa_dps sight radar jam
    A allyteam...            (the order of the sight bits in U)
    T team allyteam isAI
    S i x z                  (metal spots)
    H step h h h ...         (ground height every `step` elmos, rows of x)
    C frame team uid defid cmdid mods x z p1,p2,p3[,p4]   mods: s shift c ctrl a alt m meta r right-click
    U frame uid defid team x z vx vz health_frac build sight cmdid tx tz
         every second for mobile units, every 10 s for buildings; sight: 2 bits per allyteam in A order
         (1 in sight, 2 on radar); cmdid/tx/tz: the unit's current order and where it points
    K frame uid defid team x z attacker attackerdef attackerteam    (death)
    F frame uid defid team x z   (finished)   G frame uid newteam oldteam   (given)
    X frame attacker victim damage   (summed over the second before frame)
    W frame winners

Batch: the demos in data/demos with a human player, newest first; one done is skipped. Pauses while
his game runs; launches on free memory (run_match.wait_for_memory).
"""
import gzip
import itertools
import os
import shutil
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402

TOOLS = Path(__file__).resolve().parent
DEFAULT_OUT = Path("G:/bar-ai-archive/replay-orders")
_launch = threading.Lock()
_launch_port = threading.Lock()
_ports = itertools.count(os.getpid() % 50 * 4)


def demo_engine(demo):
    """The engine version in the demo's header (a replay plays only on its own engine)."""
    with gzip.open(demo, "rb") as f:
        head = f.read(16 + 8 + 256)
    return head[24:24 + 256].split(b"\x00", 1)[0].decode("ascii", "replace").split()[0]


def headless_for(env, demo):
    exe = env.data / "engine" / ("recoil_" + demo_engine(demo)) / "spring-headless.exe"
    return exe if exe.exists() else None


def free_commit_gb():
    """Windows commit left (RAM + paging file): 11-18 the trainer's workers failed with error 1455 at 2.7 GB left
    while free RAM read 27.7 GB, his ComfyUI holding 14 GB."""
    import ctypes

    class MS(ctypes.Structure):
        _fields_ = [("len", ctypes.c_ulong), ("load", ctypes.c_ulong), ("totPhys", ctypes.c_ulonglong),
                    ("availPhys", ctypes.c_ulonglong), ("totPage", ctypes.c_ulonglong),
                    ("availPage", ctypes.c_ulonglong), ("totVirt", ctypes.c_ulonglong),
                    ("availVirt", ctypes.c_ulonglong), ("availExt", ctypes.c_ulonglong)]
    m = MS()
    m.len = ctypes.sizeof(MS)
    ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
    return m.availPage / 2 ** 30


def _his_game():
    import mp_archive
    return mp_archive.his_game_running()


def run(demo, out, max_min=1e6, timeout=5400, yield_to_him=True, extra_data=None):
    env = bar_env.load()
    datadir = str(env.data) + (";" + str(extra_data) if extra_data and Path(extra_data).exists() else "")
    out = Path(out).resolve()   # the engine runs in wd: a relative write dir would resolve inside itself, without the widget
    import archive_old
    archive_old.ensure_disk()
    exe = headless_for(env, demo)
    if exe is None:
        print("no engine %s for %s" % (demo_engine(demo), demo), flush=True)
        return 0, None
    wd = out / "wd"
    (wd / "LuaUI" / "Widgets").mkdir(parents=True, exist_ok=True)
    cfg = wd / "LuaUI" / "Config"
    cfg.mkdir(parents=True, exist_ok=True)
    shutil.copy2(TOOLS / "replay_orders_widget.lua", wd / "LuaUI" / "Widgets" / "replay_orders_widget.lua")
    shutil.copy2(TOOLS / "headless.cfg", wd / "run.cfg")
    with _launch_port:
        port = 8600 + next(_ports) % 200
    with open(wd / "run.cfg", "a") as c:
        c.write("\nHostPortDefault = %d\n" % port)
    (cfg / "orders_maxframe.txt").write_text(str(int(max_min * 60 * 30)))
    cmd = [str(exe), "--write-dir", str(wd), "--config", str(wd / "run.cfg"), str(Path(demo).resolve())]
    t0 = time.time()
    stopped = False
    with open(wd / "stdout.txt", "w") as so:
        # below normal: an uncapped replay takes ~10 of 16 cores and starved training's data workers (11-19: 6.1 ->
        # 7.4 steps/s, GPU 19% -> 87% once lowered); it still uses whatever is idle
        proc = subprocess.Popen(cmd, cwd=str(wd), stdout=so, stderr=subprocess.STDOUT,
                                env={**os.environ, "SPRING_DATADIR": datadir},
                                creationflags=getattr(subprocess, "BELOW_NORMAL_PRIORITY_CLASS", 0))
        checked = t0
        while proc.poll() is None:
            time.sleep(3)
            if time.time() - t0 > timeout:
                print("timeout", demo, flush=True)
                proc.kill()
            elif yield_to_him and time.time() - checked > 30 and (checked := time.time()) and _his_game():
                print("his game started: stopped", demo, flush=True)
                proc.kill()
                stopped = True
        proc.wait()
    src = cfg / "orders.txt"
    size = None
    so_path = wd / "stdout.txt"
    text = so_path.read_text(encoding="utf-8", errors="replace") if so_path.exists() else ""
    # an engine killed from outside (11-21: two, killed by hand while he played) leaves half a game that read as
    # done; only a clean shutdown keeps its orders
    clean = "SpringApp::Kill" in text
    if not clean:
        print("not a clean end: not kept", demo, flush=True)
    if not stopped and clean and src.exists() and src.stat().st_size > 0:
        with open(src, "rb") as fi, gzip.open(out / "orders.txt.gz", "wb", compresslevel=6) as fo:
            shutil.copyfileobj(fi, fo)
        size = (out / "orders.txt.gz").stat().st_size
        src.unlink()
    (out / "desync.txt").write_text("\n".join(ln for ln in text.splitlines() if "DESYNC" in ln), encoding="utf-8")
    widget_lines = [ln for ln in text.splitlines() if "replay_orders_widget" in ln or "order capture" in ln]
    (out / "stdout.log").write_text("\n".join(widget_lines) + "\n----\n" + text[-200000:], encoding="utf-8")
    shutil.rmtree(wd, ignore_errors=True)
    return round(time.time() - t0), size


def has_human(demo):
    import replay_extract as rx
    m = rx.meta_of(rx.demo_script(demo))
    ai_teams = {a["team"] for a in m["ais"]}
    return any(p["spec"] in ("0", None) and p["team"] not in ai_teams for p in m["players"])


def batch(workers=2, limit=None, root=DEFAULT_OUT):
    env = bar_env.load()
    demos = sorted((env.data / "demos").glob("*.sdfz"), key=lambda p: -p.stat().st_mtime)
    todo = [d for d in demos if not (root / d.stem / "orders.txt.gz").exists() and has_human(d)]
    if limit:
        todo = todo[:limit]
    batch_list(todo, workers, root)


def batch_list(todo, workers, root, extra_data=None):
    import mp_archive
    import run_match
    print("%d demos to record, %d workers, into %s" % (len(todo), workers, root), flush=True)

    def one(demo):
        for attempt in range(20):
            with _launch:
                # every gate again after any wait (11-21: two launched mid-game after waiting out memory and commit)
                while True:
                    while mp_archive.his_game_running():
                        print("his game is running: waiting", flush=True)
                        time.sleep(120)
                    run_match.wait_for_memory(5.0, 12.0)
                    while free_commit_gb() < 20.0:
                        print("waiting for commit: %.1f GB left" % free_commit_gb(), flush=True)
                        time.sleep(60)
                    time.sleep(20)
                    if not mp_archive.his_game_running():
                        break
            wall, size = run(demo, root / demo.stem, extra_data=extra_data)
            print("%s wall %ss gz %s" % (demo.stem, wall, size), flush=True)
            if size or not mp_archive.his_game_running():
                return

    with ThreadPoolExecutor(workers) as ex:
        list(ex.map(one, todo))


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["one"] and len(a) >= 3:
        print("wall_s %s gz bytes %s" % run(a[1], a[2], float(a[3]) if len(a) > 3 else 1e6))
    elif a[:1] == ["batch"]:
        batch(int(a[a.index("--workers") + 1]) if "--workers" in a else 2,
              int(a[a.index("--limit") + 1]) if "--limit" in a else None,
              Path(a[a.index("--out") + 1]) if "--out" in a else DEFAULT_OUT)
    else:
        print(__doc__)
        raise SystemExit(1)
