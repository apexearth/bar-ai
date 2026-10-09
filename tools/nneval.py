"""Held-out evaluation of the decision nets: two arms, the same seeds, compared game by game.

    python tools/nneval.py snapshots                       # what runtime/nn/snapshots/ holds
    python tools/nneval.py snapshot-current                # copy the weights deployed now into snapshots/
    python tools/nneval.py plan --a snapshot:<stamp> --b blend0 [--map M] [--games N] [--minutes M]
    python tools/nneval.py install <stamp> --ai Apexevala:lane-evala [--dry-run]
    python tools/nneval.py report <tournament A> <tournament B>

An ARM is `snapshot:<stamp>` (weights the trainer copied every ~6 h; `current`
= the weights deployed now, snapshotted first) or `blend0` (the rules alone:
apex_nn_blend=0). Each arm plays from its own lane, so its weights stay fixed
while the trainer keeps exporting into the training lane. `plan` prints the
commands and runs nothing: no exploration (apex_nn_explore=0, no plan
exploration), bonus 0, the tournament's fixed seeds (1000 + pair), both seats.

`report` pairs the games by (map, seed, our seat) and judges each pair on
the change in ln(our side / theirs) at minutes 10, 15 and 20 -- metal
produced so far, army, extractors, metal income (tools/progress.py's edges)
-- and on time to loss (a game not lost counts as lasting to its cap). A game
already over by a minute carries its result there: ln 10 for a win, -ln 10
for a loss. Win counts are printed and not judged on: one bit per game.
"""
import json
import math
import os
import re
import shutil
import statistics
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import progress  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
OUT = Path(os.environ.get("BARAI_NN_OUT", str(REPO / "runtime" / "nn")))
SNAP = OUT / "snapshots"
REL = Path("script/standard/manager/brain/market/nnweights.as")
MINUTES = (10, 15, 20)
CLIP = math.log(10.0)
FPM = 1800
MODS = ("apex_nn_explore=0", "apex_nn_explore_team=-1", "apex_plan_explore=0", "apex_lag_speed=0")


def snapshots():
    if not SNAP.is_dir():
        print("no snapshots in %s" % SNAP)
        return 0
    for d in sorted(SNAP.iterdir()):
        if not (d / "nnweights.as").is_file():
            continue
        try:
            m = json.loads((d / "meta.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            m = {}
        tr = m.get("trust") or {}
        print("%-22s batches %-6s rows %-9s trusted kinds %d  version %s"
              % (d.name, m.get("batches", "?"), m.get("rows", "?"), sum(1 for v in tr.values() if v > 0),
                 (m.get("newest_version") or ["?"])[-1]))
    return 0


def deployed_weights(ai):
    """The nnweights.as files of a deployed AI 'Short:version' (engine- and game-side)."""
    import bar_env
    short, ver = ai.split(":", 1)
    env = bar_env.load()
    return [root / REL for root in (env.skirmish_dir(short, ver), env.game_config_dir(short, ver))
            if (root / REL).parent.is_dir()]


def snapshot_current():
    names = json.loads((OUT / "targets.json").read_text()) if (OUT / "targets.json").is_file() else ["Apexnnlog:lane-nnlog"]
    src = next((p for p in deployed_weights(names[0]) if p.is_file()), None)
    if src is None:
        print("no deployed weights for %s" % names[0])
        return 1
    dest = SNAP / (time.strftime("%Y%m%d-%H%M%S") + "-current")
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dest / "nnweights.as")
    (dest / "meta.json").write_text(json.dumps({"at": time.time(), "from": str(src)}), encoding="utf-8")
    print("snapshot of %s -> %s" % (src, dest))
    return 0


def install(stamp, ai, dry):
    src = Path(stamp) if Path(stamp).is_file() else SNAP / stamp / "nnweights.as"
    if not src.is_file():
        print("no snapshot %s" % src)
        return 1
    dests = deployed_weights(ai)
    if not dests:
        print("%s is not deployed (deploy its lane first)" % ai)
        return 1
    for p in dests:
        print(("would copy" if dry else "copy") + " %s -> %s" % (src, p))
        if not dry:
            shutil.copyfile(src, p)
    return 0


def plan(argv):
    opt = lambda k, d=None: argv[argv.index(k) + 1] if k in argv else d
    arms = [("A", opt("--a", "current")), ("B", opt("--b", "blend0"))]
    mp, games, minutes = opt("--map", "Comet Catcher Remake 1.8"), opt("--games", "20"), opt("--minutes", "30")
    workers, sides = opt("--workers", "4"), opt("--sides", "random,random")
    stamp = time.strftime("%m%d")
    print("# Both arms deploy the SAME scripts (deploy both lanes from one commit); only the weights differ.")
    print("# The trainer will also learn from these games (they are ordinary finished tournaments).\n")
    names = []
    for tag, spec in arms:
        lane = "eval" + tag.lower()
        ai = "Apex%s:lane-%s" % (lane, lane)
        print("# arm %s: %s" % (tag, spec))
        print("python tools/lane.py init %s" % lane)
        print("BARAI_LANE=%s python tools/deploy_ai.py deploy Unstable" % lane)
        blend = "1"
        if spec == "current":
            print("python tools/nneval.py snapshot-current     # then use its stamp below")
            print("python tools/nneval.py install <stamp>-current --ai %s" % ai)
        elif spec.startswith("snapshot:"):
            print("python tools/nneval.py install %s --ai %s" % (spec.split(":", 1)[1], ai))
        elif spec == "blend0":
            blend = "0"
        else:
            print("# unknown arm %r: snapshot:<stamp> | current | blend0" % spec)
            return 2
        name = "nneval-%s-%s-%s" % (stamp, tag, re.sub(r"[^\w-]", "", spec.replace(":", "-")))
        names.append(name)
        print(('python tools/run_tournament.py --a %s:standard --b BARb:stable:hard --maps "%s" --games %s '
               '--minutes %s --workers %s --per-side 1 --sides %s --handicap 0 --modoption apex_nn_blend=%s %s --name %s')
              % (ai, mp, games, minutes, workers, sides, blend, " ".join("--modoption " + m for m in MODS), name))
        print()
    print("python tools/nneval.py report tournaments/<stamp>-%s tournaments/<stamp>-%s" % tuple(names))
    return 0


# -- report -------------------------------------------------------------------

def metal_made_edge(mdir, minutes):
    """ln(our metal produced so far / theirs) at each minute, from BARAI_WASTE."""
    try:
        txt = open(os.path.join(mdir, "infolog.txt"), encoding="utf-8", errors="replace").read()
        script = open(os.path.join(mdir, "script.txt"), encoding="utf-8", errors="replace").read()
    except OSError:
        return {}
    barb = set()
    for block in re.findall(r"\[ai\d+\]\s*\{(.*?)\}", script, re.S | re.I):
        tm = re.search(r"team=(\d+);", block, re.I)
        if tm and re.search(r"shortname=BARb;", block, re.I):
            barb.add(int(tm.group(1)))
    ally = {}
    for rx in (progress.RE_PROD, progress.RE_BUILD):
        for m in rx.finditer(txt):
            ally[int(m.group(1))] = int(m.group(2))
    them = {ally[t] for t in barb if t in ally}
    made = {}
    for m in progress.RE_WASTE.finditer(txt):
        made.setdefault(int(m.group(2)), []).append((int(m.group(1)), int(m.group(4))))
    out = {}
    for mn in minutes:
        f = mn * FPM
        side = [0.0, 0.0]
        for t, pts in made.items():
            if t not in ally:
                continue
            before = [v for fr, v in pts if fr <= f]
            if before:
                side[1 if ally[t] in them else 0] += before[-1]
        if side[0] > 0 and side[1] > 0:
            out[mn] = max(-CLIP, min(CLIP, math.log(side[0] / side[1])))
    return out


def game_of(mdir):
    g = progress.load(str(mdir))
    if not g or g.get("skip"):
        return None
    try:
        res = json.load(open(os.path.join(mdir, "result.json"), encoding="utf-8"))
    except (OSError, ValueError):
        return None
    name = os.path.basename(str(mdir).rstrip("/\\"))
    seat = "first" if re.match(r"t\d+-Apex", name) else "second"
    cap = res.get("minutes_cap") or g["minutes"]
    out = {"key": (g["map"], res.get("seed"), seat), "result": g["result"], "minutes": g["minutes"],
           "ttl": g["minutes"] if g["result"] == "L" else float(cap), "m": {}}
    made = metal_made_edge(str(mdir), MINUTES)
    for mn in MINUTES:
        row = {}
        over = mn > g["minutes"]
        for k, series in (("made", None), ("army", "army"), ("mex", "mex"), ("eco", "eco")):
            if over and g["result"] in ("W", "L"):
                row[k] = CLIP if g["result"] == "W" else -CLIP
                continue
            if k == "made":
                v = made.get(mn)
            else:
                s = g["series"][series]
                v = s[mn] if mn < len(s) else None
                v = None if v is None else max(-CLIP, min(CLIP, math.log(max(v, 1e-9))))
            row[k] = v
        out["m"][mn] = row
    return out


def ci(xs):
    """(mean, half-width of a 95% interval) of paired differences."""
    if len(xs) < 2:
        return (xs[0] if xs else None), None
    return statistics.mean(xs), 1.96 * statistics.stdev(xs) / math.sqrt(len(xs))


def report(a_dir, b_dir):
    arms = []
    for d in (a_dir, b_dir):
        games = {}
        for m in sorted(Path(d, "matches").glob("*")):
            if (m / "result.json").is_file():
                g = game_of(m)
                if g:
                    games[g["key"]] = g
        arms.append(games)
    keys = sorted(set(arms[0]) & set(arms[1]), key=str)
    print("A = %s\nB = %s" % (a_dir, b_dir))
    print("pairs %d (A games %d, B games %d; an unpaired game is left out)" % (len(keys), len(arms[0]), len(arms[1])))
    if not keys:
        return 1
    for tag, games in (("A", arms[0]), ("B", arms[1])):
        rs = [games[k]["result"] for k in keys]
        print("  %s  W %d  L %d  D %d   (not judged on)" % (tag, rs.count("W"), rs.count("L"), rs.count("D")))
    print("\nA minus B, paired; edges are ln(ours/theirs), + favours A")
    print("%-8s %-6s %5s %8s %8s %6s" % ("minute", "edge", "n", "mean", "+-95%", "A>B"))
    for mn in MINUTES:
        for k in ("made", "army", "mex", "eco"):
            diffs = [arms[0][q]["m"][mn][k] - arms[1][q]["m"][mn][k] for q in keys
                     if arms[0][q]["m"][mn][k] is not None and arms[1][q]["m"][mn][k] is not None]
            mu, hw = ci(diffs)
            print("%-8s %-6s %5d %8s %8s %6s" % (mn, k, len(diffs), "-" if mu is None else "%+.3f" % mu,
                                                  "-" if hw is None else "%.3f" % hw,
                                                  "%d/%d" % (sum(1 for x in diffs if x > 0), len(diffs))))
    ttl = [arms[0][q]["ttl"] - arms[1][q]["ttl"] for q in keys]
    mu, hw = ci(ttl)
    lost = [(arms[0][q]["result"] == "L", arms[1][q]["result"] == "L") for q in keys]
    print("\ntime to loss (min, a game not lost lasts to its cap): A-B %+.2f +- %s over %d pairs; "
          "A held longer in %d, B in %d; lost by A only %d, by B only %d"
          % (mu, "-" if hw is None else "%.2f" % hw, len(ttl), sum(1 for x in ttl if x > 0),
             sum(1 for x in ttl if x < 0), sum(1 for a, b in lost if a and not b), sum(1 for a, b in lost if b and not a)))
    return 0


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd = argv[0]
    if cmd == "snapshots":
        return snapshots()
    if cmd == "snapshot-current":
        return snapshot_current()
    if cmd == "plan":
        return plan(argv[1:])
    if cmd == "install" and len(argv) >= 2 and "--ai" in argv:
        return install(argv[1], argv[argv.index("--ai") + 1], "--dry-run" in argv)
    if cmd == "report" and len(argv) >= 3:
        return report(argv[1], argv[2])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
