"""The asset ledger, step 1 (todo/learn-from-each-decision.md): every building our seats placed, joined to the
decision that bought it and followed through its life, from logs every game already writes.

    python tools/ledger.py <tournament-or-match-dir> [...]      # summary by building type
    python tools/ledger.py --jsonl out.jsonl <dirs...>           # also one record per asset

Per asset: the founding decision (frame, builder, reason, rank picked, value, gain, metal, time, net multiplier,
the state and the chosen option), when it finished or that it died a frame (and whether the enemy, we, or nobody
ended it), when and how it ended, the metal of enemy units it killed (killing blow), a factory's army metal, and from
[BARAI_LIFE] the metal of damage it dealt and took, how far a frame got, its build power by source and its output.
Jobs that never put a building down are records too: the builder killed on the job, or dropped (with how long it was
open), or cut off by the game's end (censored).
"""
import argparse
import glob
import json
import math
import os
import re
from collections import defaultdict

FRAME = re.compile(r"\[f=(-?\d+)\]")
DECIDE = re.compile(r"apex: decide t=(\d+) (\S+) #(\d+) -> [a-z]+/[a-z]+:(\S+) v=([-\d.]+) \(gain=([-\d.]+) m=([-\d.]+) "
                    r"t=([-\d.]+)\)(?: nn=([-\d.]+))? why=(\S+)")
EXEC = re.compile(r"apex: exec t=(\d+) (\S+) #(\d+) ([a-z]+):(\S+) pick=(\d+) at=(-?\d+),(-?\d+)(?: task=(-?\d+),(-?\d+))?")
BUILD = re.compile(r"\[BARAI_BUILD\] team=(\d+) .*?frame=(\d+) .*?unit=(\S+) cost=([\d.]+) x=(\d+) z=(\d+) uid=(\d+)")
DEATH = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\S+) cost=([\d.]+) x=(-?\d+) z=(-?\d+) .*?built=(\d) "
                   r"mob=(\d) atkteam=(-?\d+) atk=(\S+) .*?uid=(\d+) atkid=(-?\d+)")
NN = re.compile(r"apex: nn t=(\d+) f=(-?\d+) u=(\d+) c=\S+ pick=(\d+) why=\S+ dm=\S+ \|([^|]*)\|([^|]*)\| chosen=(-?\d+)")
SCHEMA = re.compile(r"apex: nn-schema \S+ state=(\S+) opt=(\S+)")
LIFE = re.compile(r"\[BARAI_LIFE\] frame=(\d+) team=(\d+) uid=(\d+) unit=(\S+) dealtM=([-\d.]+) takenM=([-\d.]+) "
                  r"started=(-?\d+) finished=(-?\d+) prog=([-\d.]+) com=([-\d.]+) con=([-\d.]+) nano=([-\d.]+) "
                  r"fac=([-\d.]+) gaveMobileM=([-\d.]+) gaveStaticM=([-\d.]+) madeM=([-\d.]+) madeE=([-\d.]+) end=(\S+)")
PROD = re.compile(r"\[BARAI_PROD\] team=(\d+) .*?frame=(\d+) .*?unit=(\S+) cost=([\d.]+) fac=(\S+) uid=\d+ facid=(\d+)")
BUILDER = re.compile(r"^(arm|cor|leg)(ck|cv|ca|cs|ch|ack|acv|aca|acs|ach|nanotc\w*|rectr|necro|fast|mlv|com\w*)$")
CON = re.compile(r"^(arm|cor|leg)(ck|cv|ca|cs|ch|ack|acv|aca|acs|ach)$")
MATCH_R = 320.0
BUILD_KINDS = {"mex", "mexup", "energy", "protect", "nano", "plant", "convert", "sense", "airdef", "tech", "geo",
               "super", "store"}


def our_teams(mdir):
    """every player team an Apex AI plays: result.json lists sides, not players"""
    try:
        txt = open(os.path.join(mdir, "script.txt"), encoding="utf-8", errors="replace").read()
    except OSError:
        return set()
    ours = set()
    for block in re.findall(r"\[ai\d+\]\s*\{(.*?)\}", txt, re.S | re.I):
        sn = re.search(r"ShortName=([^;]+);", block)
        tm = re.search(r"\bTeam=(\d+);", block)
        if sn and tm and sn.group(1).startswith("Apex"):
            ours.add(int(tm.group(1)))
    return ours


def ally_teams(mdir):
    """team -> allyteam from the start script"""
    try:
        txt = open(os.path.join(mdir, "script.txt"), encoding="utf-8", errors="replace").read()
    except OSError:
        return {}
    out = {}
    for tid, block in re.findall(r"\[team(\d+)\]\s*\{(.*?)\}", txt, re.S | re.I):
        m = re.search(r"\bAllyTeam=(\d+);", block)
        if m:
            out[int(tid)] = int(m.group(1))
    return out


_TREE = None
_CAT = {}


def catalog_cost(name):
    """a unit's metal from the game's own unit files (never from a game's logs: a commander's cost was only known
    in games where a commander died, which leaked the outcome)"""
    global _TREE
    if name in _CAT:
        return _CAT[name]
    c = 0.0
    try:
        if _TREE is None:
            import bar_env
            import unitdef
            _TREE = unitdef.trees(bar_env.load())[0]
        info = _TREE.info(name)
        if info and info.get("metalcost"):
            c = float(info["metalcost"])
    except Exception:  # noqa: BLE001
        c = 0.0
    _CAT[name] = c
    return c


GRACE = 5 * 30          # a builder killed within 5 s of its job's end still died on it
TRUNC = 60 * 30         # a job still open in the last minute of a game is cut off, not dropped
NEAR_KILL_R, NEAR_KILL_F = 600.0, 300


def read_game(mdir):
    ours = our_teams(mdir)
    log = os.path.join(mdir, "infolog.txt")
    if not ours or not os.path.exists(log):
        return []
    ally = ally_teams(mdir)
    def friend(mine, t):
        t = int(t)
        return t == mine or (t >= 0 and ally.get(t) is not None and ally.get(t) == ally.get(mine))

    def foe(mine, t):
        t = int(t)
        return t >= 0 and not friend(mine, t)

    last_decide = {}
    last_nn = {}
    last_exec = {}
    names = {}

    def attach(rec, nm):
        # the nn line follows its exec line; its chosen option is the one executed
        if not names:
            return
        state = [float(v) for v in nm.group(5).split(",") if v.strip()]
        opts = [o.strip().split(",") for o in nm.group(6).split(";") if o.strip()]
        ch = int(nm.group(7))
        if len(state) == len(names["state"]):
            rec["state"] = state
        if 0 <= ch < len(opts) and len(opts[ch]) == len(names["opt"]):
            rec["opt"] = dict(zip(names["opt"], opts[ch]))
        rec["nOpts"] = len(opts)
    execs = defaultdict(list)       # (team, def) -> [exec record]
    builds, deaths, prods = [], [], []
    lives = {}
    end = 0
    for ln in open(log, encoding="utf-8", errors="replace"):
        fm = FRAME.search(ln)
        f = int(fm.group(1)) if fm else 0
        if "apex: nn-schema" in ln and not names:
            m = SCHEMA.search(ln)
            if m:
                names = {"state": m.group(1).split(","), "opt": m.group(2).split(",")}
            continue
        if "apex: nn t=" in ln:
            m = NN.search(ln)
            if m and int(m.group(1)) in ours:
                key = (int(m.group(1)), m.group(3))
                last_nn[key] = (int(m.group(2)), m)
                e = last_exec.get(key)
                if e is not None and "state" not in e and abs(e["frame"] - int(m.group(2))) <= 2:
                    attach(e, m)
            continue
        if "apex: decide t=" in ln:
            m = DECIDE.search(ln)
            if m and int(m.group(1)) in ours:
                last_decide[(int(m.group(1)), m.group(3))] = m
            continue
        if "apex: exec t=" in ln:
            m = EXEC.search(ln)
            if m and int(m.group(1)) in ours:
                team, uid, kind, d, pick = int(m.group(1)), m.group(3), m.group(4), m.group(5), int(m.group(6))
                x, z = (int(m.group(9)), int(m.group(10))) if m.group(9) else (int(m.group(7)), int(m.group(8)))
                dm = last_decide.get((team, uid))
                rec = {"frame": f, "builder": m.group(2), "builderId": uid, "kind": kind, "pick": pick, "x": x, "z": z,
                       "used": False, "def": d, "team": team}
                last_exec[(team, uid)] = rec
                if dm and dm.group(4) == d:
                    rec.update({"v": float(dm.group(5)), "gain": float(dm.group(6)), "m": float(dm.group(7)),
                                "t": float(dm.group(8)), "nn": float(dm.group(9) or 1), "why": dm.group(10)})
                execs[(team, d)].append(rec)
            continue
        m = BUILD.search(ln)
        if m:
            builds.append(m.groups())
            end = max(end, int(m.group(2)))
            continue
        m = DEATH.search(ln)
        if m:
            deaths.append(m.groups())
            end = max(end, int(m.group(1)))
            continue
        m = PROD.search(ln)
        if m:
            prods.append(m.groups())
            end = max(end, int(m.group(2)))
            continue
        if "[BARAI_LIFE]" in ln:
            m = LIFE.search(ln)
            if m and int(m.group(2)) in ours:
                old = lives.get(m.group(3))
                if not (old and old[17] == "died"):     # a dead unit's real record outranks anything printed after it
                    lives[m.group(3)] = m.groups()
            end = max(end, int(m.group(1)) if m else end)

    def founder(team, d, x, z, before):
        best, bd = None, MATCH_R
        for e in execs.get((team, d), []):
            if e["used"] or e["frame"] > before:
                continue
            dd = math.hypot(e["x"] - x, e["z"] - z)
            if dd < bd:
                best, bd = e, dd
        if best is not None:
            best["used"] = True
        return best

    game = os.path.basename(mdir)
    # `mob` in BARAI_DEATH is mobileArmed, not mobility: building types are the ones decisions place
    placed_defs = {d for (team, d), lst in execs.items() if any(e["kind"] in BUILD_KINDS for e in lst)}
    assets = {}
    for team, f, d, c, x, z, uid in builds:
        team, f, c, x, z = int(team), int(f), float(c), int(x), int(z)
        if team not in ours or CON.search(d):
            continue
        assets[uid] = {"game": game, "team": team, "def": d, "cost": c, "x": x, "z": z, "finished": f, "ended": None,
                       "how": "standing", "killedM": 0.0, "armyM": 0.0}
    # our units the enemy killed, for a frame that died with no attacker named near them (a shell whose owner was
    # already gone, a frame left when its builder died)
    enemy_kills = [(int(f), int(x), int(z), ally.get(int(team))) for f, team, d, c, x, z, built, mob, at, atk, uid, atkid
                   in deaths if int(team) in ours and foe(int(team), at)]
    lost_frames = []
    for f, team, d, c, x, z, built, mob, at, atk, uid, atkid in deaths:
        team, f = int(team), int(f)
        if team in ours and built == "0" and d in placed_defs and uid not in assets:
            if friend(team, at):
                how = "own"
            elif foe(team, at):
                how = "enemy"
            elif any(ka == ally.get(team) and abs(kf - f) <= NEAR_KILL_F
                     and math.hypot(kx - int(x), kz - int(z)) <= NEAR_KILL_R for kf, kx, kz, ka in enemy_kills):
                how = "enemy"
            else:
                how = "decayed"
            lost_frames.append({"game": game, "team": team, "def": d, "cost": float(c), "frame": f, "uid": uid,
                                "x": int(x), "z": int(z), "by": atk, "own": friend(team, at), "frameHow": how,
                                "frameLost": True})
    # founders in the order things happened: an asset finished late must not take an earlier frame's decision
    order = [(a["finished"], "a", uid) for uid, a in assets.items()] + \
            [(lf["frame"], "f", i) for i, lf in enumerate(lost_frames)]
    order.sort(key=lambda t: t[0])
    for fr, k, key in order:
        r = assets[key] if k == "a" else lost_frames[key]
        r["decision"] = founder(r["team"], r["def"], r["x"], r["z"], fr)
        if r["decision"] is not None:
            r["decision"]["endFrame"] = fr
    for f, team, d, c, x, z, built, mob, at, atk, uid, atkid in deaths:
        f, team, c = int(f), int(team), float(c)
        if atkid in assets and foe(assets[atkid]["team"], team):
            assets[atkid]["killedM"] += c
        if uid in assets and team in ours:
            a = assets[uid]
            a["ended"] = f
            a["how"] = "reclaimed/self" if friend(team, at) else ("killed by " + atk)
    for team, f, unit, c, fac, facid in prods:
        if facid in assets and not BUILDER.search(unit):
            assets[facid]["armyM"] += float(c)
    died_at = {}
    for f, team, d, c, x, z, built, mob, at, atk, uid, atkid in deaths:
        if int(team) in ours:
            died_at[uid] = (int(f), atk)

    # one job = a run of one builder's execs on the same def at the same site (re-elections re-issue it). It is open
    # from its first exec to the builder's next job, or to the frame or building it raised. A builder killed inside
    # that window (plus GRACE) died on the job; one killed later did not.
    out = []
    by_builder = defaultdict(list)
    for lst in execs.values():
        for e in lst:
            by_builder[e["builderId"]].append(e)
    sites = defaultdict(list)
    for a in assets.values():
        sites[(a["team"], a["def"])].append((a["x"], a["z"], a["finished"], a["ended"]))
    for lf in lost_frames:
        sites[(lf["team"], lf["def"])].append((lf["x"], lf["z"], lf["frame"], lf["frame"]))
    for bid, lst in by_builder.items():
        lst.sort(key=lambda e: e["frame"])
        runs = []
        for e in lst:
            if runs and runs[-1][-1]["def"] == e["def"] and \
                    math.hypot(runs[-1][-1]["x"] - e["x"], runs[-1][-1]["z"] - e["z"]) < MATCH_R:
                runs[-1].append(e)
            else:
                runs.append([e])
        bd = died_at.get(bid)
        for i, run in enumerate(runs):
            start = run[0]["frame"]
            nxt = runs[i + 1][0]["frame"] if i + 1 < len(runs) else end
            used = next((r for r in run if r["used"]), None)
            stop = min(nxt, used["endFrame"]) if (used is not None and "endFrame" in used) else nxt
            head = used if used is not None else run[0]
            head["jobEnd"] = stop
            head["builderCost"] = catalog_cost(head.get("builder", ""))
            if bd and start <= bd[0] <= stop + GRACE:
                head["diedOnJob"] = True
                head["killer"] = bd[1]
                head["diedAfterS"] = round((bd[0] - head["frame"]) / 30.0, 1)
            if used is not None or run[0]["kind"] not in BUILD_KINDS:
                continue
            e = run[0]
            # a join on a site that went up later, or a re-issue while one already stood, is not a job of its own
            if any(math.hypot(sx - e["x"], sz - e["z"]) < MATCH_R and
                   (fr >= start or (fr < start and (ended is None or ended > start)))
                   for sx, sz, fr, ended in sites.get((e["team"], e["def"]), [])):
                continue
            out.append({"game": game, "team": e["team"], "def": e["def"], "cost": e.get("m", 0.0), "x": e["x"],
                        "z": e["z"], "frame": start, "neverPlaced": True, "decision": head,
                        "reissued": len(run) - 1, "droppedAfterS": round((stop - start) / 30.0, 1),
                        "censored": (stop >= end - TRUNC) and not head.get("diedOnJob"),
                        "builderDied": bool(head.get("diedOnJob")), "builderKiller": head.get("killer")})

    def fate(r):
        d = r.get("decision")
        r["builderDied"] = bool(d and d.get("diedOnJob"))
        if r["builderDied"]:
            r["builderKiller"] = d.get("killer")

    def attach_life(r, uid):
        lv = lives.get(uid)
        if not lv:
            return
        r["dealtM"], r["takenM"] = float(lv[4]), float(lv[5])
        r["started"], r["prog"] = int(lv[6]), float(lv[8])
        r["bp"] = {"com": float(lv[9]), "con": float(lv[10]), "nano": float(lv[11]), "fac": float(lv[12])}
        r["madeM"], r["madeE"] = float(lv[15]), float(lv[16])

    for uid, a in assets.items():
        fate(a)
        a["lifeMin"] = round(((a["ended"] if a["ended"] is not None else end) - a["finished"]) / 1800.0, 2)
        attach_life(a, uid)
        out.append(a)
    for lf in lost_frames:
        fate(lf)
        attach_life(lf, lf["uid"])
        if "prog" in lf:
            lf["spentM"] = round(lf["cost"] * lf["prog"], 1)
        out.append(lf)
    # what each builder's lathe went into (BARAI_LIFE gaveMobileM / gaveStaticM), one record per builder
    for uid, lv in lives.items():
        if BUILDER.search(lv[3]) and (float(lv[13]) > 0 or float(lv[14]) > 0):
            out.append({"game": game, "team": int(lv[1]), "def": lv[3], "builder": True, "uid": uid,
                        "gaveMobileM": float(lv[13]), "gaveStaticM": float(lv[14]),
                        "dealtM": float(lv[4]), "takenM": float(lv[5]), "end": lv[17]})
    if names:
        for r in out:
            r["_names"] = names
    return out


def summarize(rows):
    by = defaultdict(lambda: {"n": 0, "cost": 0.0, "killed": 0.0, "army": 0.0, "zero": 0, "died": 0, "life": 0.0,
                              "framesLost": 0, "framesM": 0.0, "dec": 0, "v": [], "why": defaultdict(int),
                              "never": 0, "neverDied": 0, "conDied": 0})
    for r in rows:
        if r.get("builder"):
            continue
        s = by[r["def"]]
        s["conDied"] += bool(r.get("builderDied"))
        if r.get("neverPlaced"):
            s["never"] += 1
            s["neverDied"] += bool(r.get("builderDied"))
            continue
        if r.get("frameLost"):
            s["framesLost"] += 1
            s["framesM"] += r["cost"]
            continue
        s["n"] += 1
        s["cost"] += r["cost"]
        s["killed"] += r["killedM"]
        s["army"] += r["armyM"]
        s["zero"] += r["killedM"] == 0
        s["died"] += r["ended"] is not None and not r["how"].startswith("reclaimed")
        s["life"] += r["lifeMin"]
        d = r.get("decision")
        if d:
            s["dec"] += 1
            if "v" in d:
                s["v"].append(d["v"])
            s["why"][d.get("why", "?")] += 1
    print("%-12s %6s %9s %7s %7s %6s %6s %6s %7s %7s %6s %s" % (
        "building", "built", "metal", "kill/m", "army/m", "kill0", "lost", "life", "frames", "never", "conDie",
        "top reasons"))
    for d, s in sorted(by.items(), key=lambda kv: -(kv[1]["cost"] + kv[1]["framesM"]))[:40]:
        if s["n"] + s["framesLost"] < 10:
            continue
        n = max(1, s["n"])
        why = ", ".join("%s %d" % kv for kv in sorted(s["why"].items(), key=lambda kv: -kv[1])[:3])
        print("%-12s %6d %9.0f %7.2f %7.2f %5.0f%% %5.0f%% %6.1f %7d %7d %6d %s" % (
            d, s["n"], s["cost"], s["killed"] / max(1, s["cost"]), s["army"] / max(1, s["cost"]),
            100 * s["zero"] / n, 100 * s["died"] / n, s["life"] / n, s["framesLost"], s["never"], s["conDied"], why))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--jsonl")
    a = ap.parse_args()
    games = []
    for d in a.dirs:
        games += [d] if os.path.exists(os.path.join(d, "infolog.txt")) else sorted(glob.glob(os.path.join(d, "matches", "*")))
    rows = []
    n = 0
    for g in games:
        r = read_game(g)
        if r:
            n += 1
            rows += r
    print("%d games, %d assets" % (n, len(rows)))
    summarize(rows)
    if a.jsonl:
        names = next((r.pop("_names") for r in rows if "_names" in r), None)
        with open(a.jsonl, "w", encoding="utf-8") as fh:
            fh.write(json.dumps({"schema": names}) + "\n")
            for r in rows:
                r.pop("_names", None)
                fh.write(json.dumps(r) + "\n")
        print("wrote", a.jsonl)


if __name__ == "__main__":
    main()
