"""Minimal ctypes binding for the engine's unitsync.dll.

Start scripts identify content by its *display* name -- "Comet Catcher Remake
1.8", "Beyond All Reason $VERSION" -- not by filename. Guessing those from
`maps/comet_catcher_remake_1.8.sd7` works often enough to be dangerous, so ask
the engine's own archive scanner instead.

    python tools/unitsync.py maps comet
    python tools/unitsync.py games
    python tools/unitsync.py ais

Note: unitsync builds its archive cache on first use, so the very first call
after an engine upgrade can take a while.
"""

from __future__ import annotations

import ctypes
import os
import sys
from pathlib import Path

import bar_env


class UnitSync:
    def __init__(self, env: bar_env.BarEnv | None = None):
        self.env = env or bar_env.load()
        dll = self.env.engine_dir / "unitsync.dll"
        if not dll.exists():
            raise FileNotFoundError(dll)

        # unitsync links against the engine's sibling DLLs (libcurl, zlib, ...),
        # so the engine dir has to be searchable before the load.
        os.add_dll_directory(str(self.env.engine_dir))
        # Tells unitsync which data dir to scan; without it, it guesses.
        os.environ.setdefault("SPRING_DATADIR", str(self.env.data))

        self.lib = ctypes.CDLL(str(dll))
        self._declare()
        if not self.lib.Init(False, 0):
            raise RuntimeError(f"unitsync Init failed: {self.error()}")

    def _declare(self) -> None:
        L = self.lib
        cs = ctypes.c_char_p
        ci = ctypes.c_int

        L.Init.argtypes, L.Init.restype = [ctypes.c_bool, ci], ci
        L.UnInit.argtypes, L.UnInit.restype = [], None
        L.GetNextError.argtypes, L.GetNextError.restype = [], cs

        L.GetMapCount.argtypes, L.GetMapCount.restype = [], ci
        L.GetMapName.argtypes, L.GetMapName.restype = [ci], cs
        L.GetMapFileName.argtypes, L.GetMapFileName.restype = [ci], cs

        L.GetPrimaryModCount.argtypes, L.GetPrimaryModCount.restype = [], ci
        L.GetPrimaryModArchive.argtypes, L.GetPrimaryModArchive.restype = [ci], cs
        L.GetPrimaryModInfoCount.argtypes, L.GetPrimaryModInfoCount.restype = [ci], ci

        L.GetSkirmishAICount.argtypes, L.GetSkirmishAICount.restype = [], ci
        L.GetSkirmishAIInfoCount.argtypes, L.GetSkirmishAIInfoCount.restype = [ci], ci

        L.GetMapInfoCount.argtypes, L.GetMapInfoCount.restype = [ci], ci

        L.GetInfoKey.argtypes, L.GetInfoKey.restype = [ci], cs
        L.GetInfoType.argtypes, L.GetInfoType.restype = [ci], cs
        L.GetInfoValueString.argtypes, L.GetInfoValueString.restype = [ci], cs
        L.GetInfoValueInteger.argtypes, L.GetInfoValueInteger.restype = [ci], ci
        L.GetInfoValueFloat.argtypes, L.GetInfoValueFloat.restype = [ci], ctypes.c_float

    # --- helpers --------------------------------------------------------
    @staticmethod
    def _s(raw) -> str:
        return raw.decode("utf-8", "replace") if raw else ""

    def error(self) -> str:
        msgs = []
        while True:
            e = self.lib.GetNextError()
            if not e:
                return " | ".join(msgs)
            msgs.append(self._s(e))

    def _info_block(self, count: int) -> dict[str, str]:
        """GetInfoKey/GetInfoValueString index into the *last* queried block."""
        out = {}
        for i in range(count):
            out[self._s(self.lib.GetInfoKey(i))] = self._s(self.lib.GetInfoValueString(i))
        return out

    # --- queries --------------------------------------------------------
    def maps(self) -> list[tuple[str, str]]:
        """[(display name, archive filename)] -- the display name goes in the script."""
        return [
            (self._s(self.lib.GetMapName(i)), self._s(self.lib.GetMapFileName(i)))
            for i in range(self.lib.GetMapCount())
        ]

    def map_starts(self, index: int) -> list[tuple[float, float]]:
        """The map's own start positions, in elmos, in mapinfo order.

        They arrive as alternating xPos/zPos FLOAT entries of the map's info
        block (one pair per position), which is why map_size's integer-only
        walk never showed them.
        """
        count = self.lib.GetMapInfoCount(index)
        out, cur = [], {}
        for i in range(count):
            key = self._s(self.lib.GetInfoKey(i))
            if key not in ("xPos", "zPos"):
                continue
            if self._s(self.lib.GetInfoType(i)) != "float":
                continue
            cur[key] = float(self.lib.GetInfoValueFloat(i))
            if "xPos" in cur and "zPos" in cur:
                out.append((cur["xPos"], cur["zPos"]))
                cur = {}
        return out

    def map_index(self, display_name: str) -> int:
        for i, (name, _fn) in enumerate(self.maps()):
            if name == display_name:
                return i
        return -1

    def map_size(self, index: int) -> tuple[int, int]:
        """(width, height) in the 512-elmo units BAR quotes, e.g. (16, 12).

        `width`/`height` come back as INTEGER info entries, so GetInfoValueString
        returns "" for them -- the reason a plain info block shows them blank.
        Returns (0, 0) when the map does not publish them.
        """
        count = self.lib.GetMapInfoCount(index)
        dims = {}
        for i in range(count):
            key = self._s(self.lib.GetInfoKey(i))
            if key in ("width", "height") and self._s(self.lib.GetInfoType(i)) == "integer":
                dims[key] = self.lib.GetInfoValueInteger(i)
        return (dims.get("width", 0) // 512, dims.get("height", 0) // 512)

    def games(self) -> list[dict[str, str]]:
        out = []
        for i in range(self.lib.GetPrimaryModCount()):
            archive = self._s(self.lib.GetPrimaryModArchive(i))
            info = self._info_block(self.lib.GetPrimaryModInfoCount(i))
            info["archive"] = archive
            out.append(info)
        return out

    def ais(self) -> list[dict[str, str]]:
        return [
            self._info_block(self.lib.GetSkirmishAIInfoCount(i))
            for i in range(self.lib.GetSkirmishAICount())
        ]

    def close(self) -> None:
        try:
            self.lib.UnInit()
        except Exception:
            pass

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


def resolve_map(query: str, us: UnitSync) -> str:
    """Accept a display name, a filename, or a substring; return the display name."""
    entries = us.maps()
    q = query.lower().strip()
    for name, fname in entries:
        if name.lower() == q or fname.lower() == q:
            return name
    matches = [n for n, f in entries if q in n.lower() or q in f.lower()]
    if len(matches) == 1:
        return matches[0]
    if not matches:
        raise SystemExit(f"no map matching {query!r} (scanned {len(entries)})")
    raise SystemExit(
        f"{query!r} is ambiguous, matches {len(matches)}:\n  "
        + "\n  ".join(sorted(matches)[:15])
    )


def main() -> int:
    what = sys.argv[1] if len(sys.argv) > 1 else "games"
    needle = sys.argv[2].lower() if len(sys.argv) > 2 else ""

    with UnitSync() as us:
        if what == "maps":
            all_maps = us.maps()
            rows = [
                (n, f, us.map_size(i))
                for i, (n, f) in enumerate(all_maps)
                if needle in n.lower() or needle in f.lower()
            ]
            print(f"{len(rows)} map(s)")
            # Comet Catcher is 16x12 = 192 and is a 4v4, so ~48 area per player
            # per side. Player count has to match map size: 8v8 on a 4v4 map
            # starves everyone and invalidates the economy.
            for name, fname, (w, h) in sorted(rows):
                if w and h:
                    fits = max(1, min(8, (w * h) // 48))
                    print(f"  {name}\n      {fname}   {w}x{h}  area={w*h}  suits ~{fits}v{fits}")
                else:
                    print(f"  {name}\n      {fname}   (size unavailable)")
        elif what == "games":
            for g in us.games():
                print(f"  {g.get('name', '?')}   [archive: {g.get('archive', '?')}]")
        elif what == "ais":
            for a in us.ais():
                print(f"  {a.get('shortName','?'):<12} {a.get('version','?'):<10} {a.get('name','')}")
        else:
            print(__doc__)
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
