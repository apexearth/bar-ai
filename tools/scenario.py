#!/usr/bin/env python3
"""Short scripted fights between our AI and BARb, judged PASS/FAIL on a counter.

docs/army.md: a behaviour is written against a scenario that passes or fails in
about a minute, before any full game. A scenario is a JSON file in
tools/scenarios/: a map, units per side at fixed places, a length, and the
counters it must meet. game-patches/gadgets/dev_scenario.lua spawns the units
and removes every starting unit; the counters come from its lines and
dev_combat_log.lua's.

    python tools/scenario.py list
    python tools/scenario.py run llt_trickle --ai-option apex_stock_army=1
    python tools/scenario.py run all --parallel 2
    python tools/scenario.py judge <match-dir>
    python tools/scenario.py run all --install-gadget   # copy only dev_scenario.lua into BAR.sdd

Spec keys: about, passes, map, seconds, units, expect; optional enemy (an AI
spec or "none" for NullAI), commanders (remove|park|keep), los (global|normal),
window_s (trickle window, default 4), spawn_frame.
A unit group: side 0 (us) or 1 (them), def, n, at [ref, x, z], spacing,
order (ai|hold|guard|fight|move), to [ref, x, z] for fight/move. ref is c
(map centre), s0 or s1 (an ally's start); x points from ally 0 toward ally 1.
Groups whose order is not ai belong to a NullAI holder on that side.
expect is a list of alternatives; each maps a counter to [op, value] and
passes when all of its counters do.

Counters (0 = us, 1 = them): spawned0/1, dead0/1, alive_frac0/1, lost_m0/1,
alone (our mobile deaths with no armed friend within 400), still (our mobile
deaths that moved under 40 elmos in the last 3 s), contacted (our mobile units
that came within weapon reach of theirs), trickle (of those, arrivals later than
window_s after the first), nofire (our dead that never damaged an enemy),
first_kill_s, first_loss_s, killed:<def>, lost:<def>. `judge` re-reads a run
with the current file's expect. Runs land in matches/scenario-dev/.
"""
from __future__ import annotations

import argparse
import filecmp
import json
import math
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import bar_env  # noqa: E402
import lane as _lane  # noqa: E402
from bar_env import REPO  # noqa: E402

SPECS = HERE / "scenarios"
GADGET = REPO / "game-patches" / "gadgets" / "dev_scenario.lua"
OUT = REPO / "matches" / "scenario-dev"
ENEMY = "BARb:stable:hard"
HOLDER = "NullAI:0.1"
FPS = 30
ALONE_R = 400
STILL_D = 40

KV = re.compile(r"(\w+)=(\S+)")
ARMY_TAG = re.compile(r"army|squad|stock|raid|fight|retreat|engage|assess|joinwin")


def load_spec(name: str) -> dict:
    p = SPECS / f"{name}.json"
    if not p.is_file():
        raise SystemExit(f"no scenario {name!r} in {SPECS}")
    spec = json.loads(p.read_text(encoding="utf-8"))
    spec["name"] = name
    return spec


def names() -> list[str]:
    return sorted(p.stem for p in SPECS.glob("*.json"))


def encode_units(spec: dict) -> str:
    out = []
    for g in spec["units"]:
        ref, x, z = g["at"]
        f = [str(g["side"]), g["def"], str(g.get("n", 1)), ref, str(int(x)), str(int(z)),
             str(int(g.get("spacing", 48))), g.get("order", "ai")]
        if g.get("to"):
            tref, tx, tz = g["to"]
            f += [tref, str(int(tx)), str(int(tz))]
        out.append(":".join(f))
    return "|".join(out)


def gadget_check(install: bool) -> None:
    dst = bar_env.load().game_sdd / "luarules" / "gadgets" / GADGET.name
    if dst.exists() and filecmp.cmp(GADGET, dst, shallow=False):
        return
    if not install:
        raise SystemExit(f"{dst} is missing or stale (S8): pass --install-gadget, "
                         "or python tools/deploy_ai.py gadgets")
    shutil.copy2(GADGET, dst)
    print(f"installed {dst}")


def default_ai() -> str:
    return f"{_lane.short()}:{_lane.variant()}:standard"


def launch(spec: dict, args, slot: int) -> tuple[subprocess.Popen, Path]:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    out = OUT / f"{stamp}-{spec['name']}"
    out.mkdir(parents=True, exist_ok=True)
    wdir = OUT / f"_engine-{slot}"
    for rec in wdir.glob("AI/Skirmish/**/apex-record.txt"):
        rec.unlink()
    spawn = int(spec.get("spawn_frame", 90))
    end_frame = spawn + int(spec["seconds"] * FPS) + 2 * FPS
    enemy = args.enemy or spec.get("enemy", ENEMY)
    if enemy == "none":
        enemy = HOLDER
    coms = spec.get("commanders", "remove")
    cmd = [sys.executable, "-u", str(HERE / "run_match.py"),
           "--a", args.ai or default_ai(), "--b", enemy,
           "--map", spec["map"], "--minutes", str(math.ceil(end_frame / FPS / 60) + 1),
           "--speed", str(args.speed), "--sides", "Armada,Armada",
           "--out", str(out), "--write-dir", str(wdir), "--timeout", "420",
           "--modoption", f"dev_scenario={spec['name']}",
           "--modoption", f"dev_scenario_units={encode_units(spec)}",
           "--modoption", f"dev_scenario_spawn={spawn}",
           "--modoption", f"dev_scenario_len={spec['seconds']}",
           "--modoption", f"dev_scenario_coms={coms}",
           "--modoption", f"dev_scenario_los={spec.get('los', 'global')}",
           "--modoption", f"dev_maxgameminutes={end_frame / FPS / 60:.4f}",
           "--modoption", f"debugcommands={end_frame + 3 * FPS}:quitforce"]
    if coms != "keep":
        cmd += ["--modoption", "deathmode=neverend"]
    for side in (0, 1):
        if any(g["side"] == side and g.get("order", "ai") != "ai" for g in spec["units"]):
            cmd += ["--extra-ai", f"{HOLDER}@{side}"]
    if args.seed is not None:
        cmd += ["--seed", str(args.seed)]
    for kv in args.ai_option:
        cmd += ["--ai-option", kv]
    for kv in args.modoption:
        cmd += ["--modoption", kv]
    (out / "scenario.json").write_text(json.dumps(spec, indent=1), encoding="utf-8")
    log = open(out / "run.log", "w", encoding="utf-8")
    return subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT), out


def parse(text: str) -> dict:
    d = {"spawn": [], "deaths": [], "units": [], "end": {}, "head": None,
         "bdeath": {}, "fired": set(), "errors": [], "apex": {}}
    for line in text.splitlines():
        if "[BARAI_SCEN" in line:
            kv = dict(KV.findall(line))
            if "[BARAI_SCEN_DEATH]" in line:
                d["deaths"].append(kv)
            elif "[BARAI_SCEN_UNIT]" in line:
                d["units"].append(kv)
            elif "[BARAI_SCEN_END]" in line:
                d["end"][int(kv["side"])] = kv
            elif "[BARAI_SCEN_SPAWN]" in line:
                d["spawn"].append(kv)
            elif "[BARAI_SCEN]" in line:
                if "ERROR" in line:
                    d["errors"].append(line.strip())
                else:
                    d["head"] = kv
        elif "[BARAI_DEATH]" in line:
            kv = dict(KV.findall(line))
            d["bdeath"][kv.get("uid")] = kv
        elif "[BARAI_ARMY]" in line:
            for ent in line.split()[-1].split(","):
                p = ent.split(":")
                if len(p) == 6 and p[5] == "1":
                    d["fired"].add(p[0])
        elif "Fix compilation errors" in line or re.search(r"\bERR\b", line):
            d["errors"].append(line.strip()[:200])
        elif "apex: " in line:
            tag = line.split("apex: ", 1)[1].split(" ", 1)[0]
            if ARMY_TAG.search(tag):
                d["apex"][tag] = d["apex"].get(tag, 0) + 1
    return d


def counters(d: dict, spec: dict) -> dict:
    spawn = int(d["head"]["frame"]) if d["head"] else int(spec.get("spawn_frame", 90))
    window = float(spec.get("window_s", 4)) * FPS
    c = {}
    units = d["units"]
    for side in (0, 1):
        mine = [u for u in units if u["side"] == str(side)]
        c[f"spawned{side}"] = len(mine)
        dead = [x for x in d["deaths"] if x["side"] == str(side)]
        c[f"dead{side}"] = len(dead)
        c[f"alive_frac{side}"] = round(1 - len(dead) / len(mine), 2) if mine else 0.0
        lost = 0
        for x in dead:
            b = d["bdeath"].get(x["uid"])
            lost += int(b["cost"]) if b else int(x["cost"])
        c[f"lost_m{side}"] = lost
        key = "lost" if side == 0 else "killed"
        for x in dead:
            c[f"{key}:{x['def']}"] = c.get(f"{key}:{x['def']}", 0) + 1
    ours = [x for x in d["deaths"] if x["side"] == "0" and x["mob"] == "1"]
    c["alone"] = sum(1 for x in ours if int(x["near"]) < 0 or int(x["near"]) > ALONE_R)
    c["still"] = sum(1 for x in ours if 0 <= int(x["disp3"]) < STILL_D)
    c["nofire"] = sum(1 for x in ours if x.get("fired") != "1" and x["uid"] not in d["fired"])
    contacts = sorted(int(u["contact"]) for u in units
                      if u["side"] == "0" and u["mob"] == "1" and int(u["contact"]) >= 0)
    c["contacted"] = len(contacts)
    c["trickle"] = sum(1 for f in contacts if f > contacts[0] + window) if contacts else 0
    for side, key in ((1, "first_kill_s"), (0, "first_loss_s")):
        fr = [int(x["frame"]) for x in d["deaths"] if x["side"] == str(side)]
        c[key] = round((min(fr) - spawn) / FPS, 1) if fr else -1
    return c


OPS = {"==": lambda a, b: a == b, "<=": lambda a, b: a <= b, ">=": lambda a, b: a >= b,
       "<": lambda a, b: a < b, ">": lambda a, b: a > b}


def verdict(c: dict, spec: dict) -> tuple[bool, list[str]]:
    lines, ok_any = [], False
    for alt in spec.get("expect", []):
        ok = True
        parts = []
        for key, (op, val) in alt.items():
            have = c.get(key, 0)
            good = OPS[op](have, val)
            ok = ok and good
            parts.append(f"{key}={have} {op} {val} {'ok' if good else 'NO'}")
        ok_any = ok_any or ok
        lines.append(("PASS " if ok else "fail ") + ", ".join(parts))
    return ok_any, lines


def judge(mdir: Path, spec: dict | None = None) -> bool | None:
    if spec is None:
        sj = mdir / "scenario.json"
        if not sj.is_file():
            raise SystemExit(f"{mdir} has no scenario.json")
        spec = json.loads(sj.read_text(encoding="utf-8"))
        cur = SPECS / f"{spec['name']}.json"
        if cur.is_file():
            now = json.loads(cur.read_text(encoding="utf-8"))
            spec.update({k: now[k] for k in ("expect", "passes", "window_s") if k in now})
    log = mdir / "infolog.txt"
    text = log.read_text(encoding="utf-8", errors="replace") if log.is_file() else ""
    d = parse(text)
    print(f"== {spec['name']}: {spec.get('about', '')}")
    print(f"   {mdir}")
    if d["head"] is None or not d["end"]:
        print("   NO RESULT: no [BARAI_SCEN] or no end report (gadget not deployed, crash, or quit early);"
              " see run.log and infolog.txt")
        for e in d["errors"][:5]:
            print("   " + e)
        return None
    if d["errors"]:
        print(f"   WARNING {len(d['errors'])} error lines (S3), first: {d['errors'][0]}")
    c = counters(d, spec)
    print(f"   metal lost  us {c['lost_m0']}  them {c['lost_m1']}   "
          f"dead us {c['dead0']}/{c['spawned0']}  them {c['dead1']}/{c['spawned1']}")
    print(f"   our deaths  alone {c['alone']}  still {c['still']}  never fired {c['nofire']}")
    print(f"   contact     {c['contacted']} reached reach, {c['trickle']} trickled in "
          f"(> {spec.get('window_s', 4)} s after the first)")
    print(f"   first kill  {c['first_kill_s']} s   first loss {c['first_loss_s']} s")
    kd = {k: v for k, v in c.items() if ":" in k}
    if kd:
        print("   by def      " + "  ".join(f"{k}={v}" for k, v in sorted(kd.items())))
    if d["apex"]:
        top = sorted(d["apex"].items(), key=lambda kv: -kv[1])[:6]
        print("   apex lines  " + "  ".join(f"{k}={v}" for k, v in top))
    ok, lines = verdict(c, spec)
    for ln in lines:
        print("   " + ln)
    print(f"   {'PASS' if ok else 'FAIL'}  ({spec.get('passes', '')})")
    (mdir / "counters.json").write_text(json.dumps({"pass": ok, **c}, indent=1), encoding="utf-8")
    return ok


def run(args) -> int:
    todo = names() if args.name == "all" else args.name.split(",")
    specs = [load_spec(n) for n in todo]
    gadget_check(args.install_gadget)
    _lane.require("scenario")
    live, results, slots = [], [], list(range(args.parallel))
    pending = list(specs)
    while pending or live:
        while pending and slots:
            spec = pending.pop(0)
            slot = slots.pop(0)
            proc, out = launch(spec, args, slot)
            print(f"launched {spec['name']} -> {out}", flush=True)
            live.append((spec, slot, proc, out))
            time.sleep(2)
        for item in live[:]:
            spec, slot, proc, out = item
            if proc.poll() is not None:
                live.remove(item)
                slots.append(slot)
                results.append((spec, out))
        time.sleep(1)
    verdicts = []
    for spec, out in sorted(results, key=lambda r: todo.index(r[0]["name"])):
        verdicts.append((spec["name"], judge(out, spec)))
        print()
    for n, v in verdicts:
        print(f"{n:16s} {'PASS' if v else ('FAIL' if v is False else 'NO RESULT')}")
    return 0 if all(v for _, v in verdicts) else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    r = sub.add_parser("run")
    r.add_argument("name", help="scenario name, comma list, or all")
    r.add_argument("--ai", help="our AI spec (default: this lane's)")
    r.add_argument("--enemy", help="their AI spec, or none (default: the spec's, else BARb)")
    r.add_argument("--speed", type=int, default=20)
    r.add_argument("--seed", type=int)
    r.add_argument("--parallel", type=int, default=1)
    r.add_argument("--ai-option", action="append", default=[], metavar="K=V")
    r.add_argument("--modoption", action="append", default=[], metavar="K=V")
    r.add_argument("--install-gadget", action="store_true")
    j = sub.add_parser("judge")
    j.add_argument("dirs", nargs="+")
    args = ap.parse_args()
    if args.cmd == "list":
        for n in names():
            s = load_spec(n)
            print(f"{n:16s} {s.get('about', '')}\n{'':16s} passes: {s.get('passes', '')}")
        return 0
    if args.cmd == "judge":
        vs = [judge(Path(p).resolve()) for p in args.dirs]
        return 0 if all(vs) else 1
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
