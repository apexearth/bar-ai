#!/usr/bin/env python3
"""Ship the trained nets with the code, identically (his 2026-10-06: "when we
deploy it as shared, I have the weights and everything is set up identically").

The trained weights live only in the deployed copy of nnweights.as (the repo's
is an empty placeholder) and deploy_ai.py never copies that file, so a variant
deployed from the repo plays on rules alone until weights are put there.

    python tools/nn_release.py snapshot                 # lane weights -> nn-snapshots/<stamp>-<commit>/
    python tools/nn_release.py verify --to Apex:Unstable  # deployed code there == the lane's?
    python tools/nn_release.py ship --to Apex:Unstable [--snapshot DIR] [--follow]

ship refuses unless the target's deployed code is identical to the lane's
(every script/config file but nnweights.as) and its NN_STATE matches the
weights' layout -- a mismatch makes every net switch itself off in game.
--follow also adds the target to runtime/nn/targets.json so the trainer keeps
its weights current from then on.
"""
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
LANE = ("Apexnnlog", "lane-nnlog")
REL = Path("script/standard/manager/brain/market/nnweights.as")
NNLOG = Path("script/standard/manager/brain/market/nnlog.as")
SNAPS = REPO / "nn-snapshots"


def roots(short, ver):
    env = bar_env.load()
    return [r for r in (env.skirmish_dir(short, ver), env.game_config_dir(short, ver)) if r.is_dir()]


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def nn_state_of_script(root):
    """NN_STATE as the deployed nnlog.as declares it (the joined literals)."""
    s = (root / NNLOG).read_text(encoding="utf-8", errors="replace")
    m = re.search(r"const string NN_STATE = (.*?);", s, re.S)
    return "".join(re.findall(r'"([^"]*)"', m.group(1))) if m else None


def nn_state_of_weights(path):
    m = re.search(r'const string NNW_STATE = "([^"]*)";', Path(path).read_text(encoding="utf-8", errors="replace"))
    return m.group(1) if m else None


def trusts(path):
    s = Path(path).read_text(encoding="utf-8", errors="replace")
    out = {k: float(v) for k, v in re.findall(r"const float (NN[A-Z])_TRUST = ([0-9.]+)f?;", s)}
    m = re.search(r"const array<float> NNW_TRUST = \{([^}]*)\}", s)
    if m:
        vals = [float(x.strip().rstrip("f")) for x in m.group(1).split(",") if x.strip()]
        out["NNW(builder kinds) max"] = max(vals) if vals else 0.0
    return out


def tree_hashes(root):
    """Every deployed script/config file but the weights and the variant's own
    name card (AIInfo.lua), path -> sha."""
    out = {}
    for p in sorted(root.rglob("*")):
        if p.is_file() and p.suffix in (".as", ".json", ".lua", ".txt", ".ini") \
                and p.name not in ("nnweights.as", "AIInfo.lua", "stamp.as") \
                and "apex-t" not in p.name and p.name != "apex-record.txt":
            out[str(p.relative_to(root)).replace("\\", "/")] = sha(p)
    return out


def snapshot():
    src = roots(*LANE)[0] / REL
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=REPO, capture_output=True, text=True).stdout.strip()
    stamp = time.strftime("%Y%m%d-%H%M")
    dst = SNAPS / ("%s-%s" % (stamp, commit))
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst / "nnweights.as")
    try:
        freeze = json.loads((REPO / "runtime" / "nn" / "freeze.json").read_text())
    except (OSError, ValueError):
        freeze = None
    manifest = {"taken": stamp, "commit": commit, "freeze": freeze, "sha256": sha(dst / "nnweights.as"),
                "nn_state": nn_state_of_weights(dst / "nnweights.as"), "trust": trusts(dst / "nnweights.as")}
    (dst / "manifest.json").write_text(json.dumps(manifest, indent=1))
    print("snapshot %s  (%d KB, commit %s)" % (dst.relative_to(REPO), (dst / "nnweights.as").stat().st_size // 1024, commit))
    print("  trust:", {k: round(v, 3) for k, v in manifest["trust"].items()})
    return dst


def verify(target):
    lane, tgt = roots(*LANE), roots(*target)
    if len(tgt) < 2:
        print("FAIL: %s:%s is not deployed (deploy the code there first)" % target)
        return False
    ok = True
    for a, b in zip(lane, tgt):
        ha, hb = tree_hashes(a), tree_hashes(b)
        diff = sorted(k for k in set(ha) | set(hb) if ha.get(k) != hb.get(k))
        if diff:
            ok = False
            print("DIFF %s vs %s: %d file(s), e.g. %s" % (a.name, b.name, len(diff), ", ".join(diff[:6])))
    print("code identical to the lane" if ok else "code differs from the lane: deploy the same commit to the target first")
    return ok


def ship(target, snap=None, follow=False):
    if not verify(target):
        return 1
    src = Path(snap) / "nnweights.as" if snap else roots(*LANE)[0] / REL
    want = nn_state_of_weights(src)
    for r in roots(*target):
        have = nn_state_of_script(r)
        if have != want:
            print("FAIL: %s NN_STATE differs from the weights' layout -- the nets would switch off there" % r)
            return 1
    digest = sha(src)
    for r in roots(*target):
        (r / REL).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, r / REL)
        if sha(r / REL) != digest:
            print("FAIL: copy to %s did not verify" % r)
            return 1
        print("weights -> %s" % (r / REL))
    if follow:
        p = REPO / "runtime" / "nn" / "targets.json"
        names = json.loads(p.read_text()) if p.is_file() else ["%s:%s" % LANE]
        name = "%s:%s" % target
        if name not in names:
            names.append(name)
            p.write_text(json.dumps(names))
        print("the trainer now keeps %s current (targets.json: %s)" % (name, names))
    print("shipped: same code, same weights (sha %s)" % digest[:12])
    return 0


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    to = argv[argv.index("--to") + 1].split(":", 1) if "--to" in argv else None
    if argv[0] == "snapshot":
        snapshot()
        return 0
    if argv[0] == "verify" and to:
        return 0 if verify(tuple(to)) else 1
    if argv[0] == "ship" and to:
        snap = argv[argv.index("--snapshot") + 1] if "--snapshot" in argv else None
        return ship(tuple(to), snap, "--follow" in argv)
    print(__doc__)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
