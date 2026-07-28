"""Resolve the local Beyond All Reason installation layout.

Every other tool in this folder imports from here, so there is exactly one
place that knows where BAR lives on this machine. Override any path with an
environment variable of the same name (BAR_ROOT, BAR_DATA, BAR_ENGINE,
BAR_GAME_SDD) when you want to point at a second install or a test copy.
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from pathlib import Path

# The Electron launcher's install dir. The `data` subfolder inside it is the
# Spring "write dir" -- engines, maps, games, replays and config all live there.
DEFAULT_ROOT = Path(
    os.environ.get(
        "BAR_ROOT",
        r"C:\Users\apexe\AppData\Local\Programs\Beyond-All-Reason",
    )
)

# Repo root == parent of this tools/ directory.
REPO = Path(__file__).resolve().parent.parent


class BarEnvError(RuntimeError):
    pass


@dataclass(frozen=True)
class BarEnv:
    root: Path          # launcher install dir
    data: Path          # spring write dir (root/data)
    engine_dir: Path    # data/engine/<active version>
    engine_version: str
    game_sdd: Path      # data/games/BAR.sdd -- the unpacked game checkout

    # --- binaries -------------------------------------------------------
    @property
    def spring(self) -> Path:
        return self.engine_dir / "spring.exe"

    @property
    def headless(self) -> Path:
        return self.engine_dir / "spring-headless.exe"

    @property
    def dedicated(self) -> Path:
        return self.engine_dir / "spring-dedicated.exe"

    @property
    def pr_downloader(self) -> Path:
        return self.engine_dir / "pr-downloader.exe"

    # --- AI locations ---------------------------------------------------
    def skirmish_dir(self, short_name: str = "BARb", version: str = "stable") -> Path:
        """Engine-side AI folder: engine/<ver>/AI/Skirmish/<ShortName>/<version>/"""
        return self.engine_dir / "AI" / "Skirmish" / short_name / version

    def game_config_dir(self, short_name: str = "BARb", version: str = "stable") -> Path:
        """Game-side config folder inside the game archive.

        CircuitAI reads these through the engine VFS when the `game_config`
        AI option is enabled (it is on by default in BARb's AIOptions.lua).
        """
        return self.game_sdd / "luarules" / "configs" / short_name / version

    def installed_variants(self, short_name: str = "BARb") -> list[str]:
        base = self.engine_dir / "AI" / "Skirmish" / short_name
        if not base.is_dir():
            return []
        return sorted(p.name for p in base.iterdir() if p.is_dir())

    # --- misc -----------------------------------------------------------
    @property
    def infolog(self) -> Path:
        return self.data / "infolog.txt"

    @property
    def demos(self) -> Path:
        return self.data / "demos"

    def describe(self) -> str:
        lines = [
            f"root          {self.root}",
            f"data          {self.data}",
            f"engine        {self.engine_version}",
            f"engine dir    {self.engine_dir}",
            f"headless      {self.headless}  {'OK' if self.headless.exists() else 'MISSING'}",
            f"game (.sdd)   {self.game_sdd}  {'OK' if self.game_sdd.is_dir() else 'MISSING'}",
            f"BARb variants {', '.join(self.installed_variants()) or '(none)'}",
        ]
        return "\n".join(lines)


def _active_engine_version(data: Path) -> str:
    """Read the engine the launcher is currently configured to use.

    data/launcher_cfg.json names a setup id ("manual-win"); data/config.json
    lists setups, each with launch.engine. Fall back to the newest recoil_*
    directory if that lookup fails.
    """
    env_override = os.environ.get("BAR_ENGINE")
    if env_override:
        return env_override

    try:
        setup_id = json.loads((data / "launcher_cfg.json").read_text("utf-8"))["config"]
        cfg = json.loads((data / "config.json").read_text("utf-8"))
        for setup in cfg.get("setups", []):
            if setup.get("package", {}).get("id") == setup_id:
                engine = setup.get("launch", {}).get("engine")
                if engine and (data / "engine" / engine).is_dir():
                    return engine
    except (OSError, ValueError, KeyError):
        pass

    return newest_engine(data)


def newest_engine(data: Path) -> str:
    """Newest engine dir by version-ish sort, preferring recoil_* naming."""
    engines = [p.name for p in (data / "engine").iterdir() if p.is_dir()]
    if not engines:
        raise BarEnvError(f"no engines found under {data / 'engine'}")

    def key(name: str):
        recoil = name.startswith("recoil_")
        nums = tuple(int(n) for n in re.findall(r"\d+", name))
        return (recoil, nums)

    return max(engines, key=key)


def load(engine_version: str | None = None) -> BarEnv:
    root = DEFAULT_ROOT
    data = Path(os.environ.get("BAR_DATA", root / "data"))
    if not data.is_dir():
        raise BarEnvError(
            f"BAR data dir not found at {data}. Set BAR_ROOT or BAR_DATA."
        )

    version = engine_version or _active_engine_version(data)
    engine_dir = data / "engine" / version
    if not engine_dir.is_dir():
        available = ", ".join(sorted(p.name for p in (data / "engine").iterdir()))
        raise BarEnvError(f"engine '{version}' not found. Available: {available}")

    game_sdd = Path(os.environ.get("BAR_GAME_SDD", data / "games" / "BAR.sdd"))

    return BarEnv(
        root=root,
        data=data,
        engine_dir=engine_dir,
        engine_version=version,
        game_sdd=game_sdd,
    )


if __name__ == "__main__":
    print(load().describe())
