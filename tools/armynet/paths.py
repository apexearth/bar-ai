"""Where the army model's game tables live (defs.json, economy.json, movement.json): ARMYNET_DATA when set, data/ beside
the packaged server (package_serve.py), else runtime/armynet/ in the repo."""
import os
import sys
from pathlib import Path


def data_dir():
    if os.environ.get("ARMYNET_DATA"):
        return Path(os.environ["ARMYNET_DATA"])
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent / "data"
    return Path(__file__).resolve().parents[2] / "runtime" / "armynet"
