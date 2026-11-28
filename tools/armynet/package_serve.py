#!/usr/bin/env python3
"""Build the army model as a folder anyone can drop into BAR (his 11-24: "easy for anybody who downloads it ... even if
it was on a CPU"): a standalone server (PyInstaller; numpy + ONNX Runtime, no Python or PyTorch needed), the model as
ONNX, the game tables, and the launch file the AI reads (ArmyNetLaunch).

    python tools/armynet/package_serve.py <onnx_dir from export_onnx.py> <out_dir> [--skip-build]

<out_dir>/armynet/ and <out_dir>/armynet-launch.txt go in BAR's data/AI/Skirmish/Apex/ beside the version folders.
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
FLAGS = ["--forces", "--learned", "--rally", "--arc", "--fbias", "-0.19"]


def main(a):
    onnx_dir, out = Path(a[0]), Path(a[1])
    work = REPO / "matches" / "_pyinstaller"
    dist = work / "dist" / "armynet"
    if "--skip-build" not in a or not dist.exists():
        subprocess.check_call([sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--onedir", "--noconsole",
                               "--name", "armynet", "--distpath", str(work / "dist"), "--workpath", str(work / "build"),
                               "--specpath", str(work), "--paths", str(HERE), "--paths", str(HERE.parent),
                               *[x for m in ("torch", "matplotlib", "pandas", "scipy", "tkinter", "IPython", "PIL",
                                             "onnx", "onnxscript", "sympy")
                                 for x in ("--exclude-module", m)],
                               "--collect-binaries", "onnxruntime", str(HERE / "serve.py")])
    pkg = out / "armynet"
    if pkg.exists():
        raise SystemExit("%s exists: pick a fresh out_dir" % pkg)
    shutil.copytree(dist, pkg)
    (pkg / "data").mkdir()
    for f in ("defs.json", "economy.json", "movement.json"):
        shutil.copy2(REPO / "runtime" / "armynet" / f, pkg / "data" / f)
    shutil.copytree(onnx_dir, pkg / "model")
    meta = json.loads((pkg / "model" / "meta.json").read_text())
    meta["source"] = Path(meta.get("source", "")).name
    (pkg / "model" / "meta.json").write_text(json.dumps(meta))
    # relative to this file's folder; ArmyNetLaunch resolves them there
    (out / "armynet-launch.txt").write_text("\n".join(["armynet/armynet.exe", "--model", "armynet/model", *FLAGS]) + "\n")
    size = sum(p.stat().st_size for p in pkg.rglob("*") if p.is_file())
    print("package %s: %.0f MB; launch file %s" % (pkg, size / 1e6, out / "armynet-launch.txt"))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
