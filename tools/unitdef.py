#!/usr/bin/env python3
"""Answer unit questions from the game files, across both game trees.

There are two, and confusing them is what this tool exists to prevent:

  game       data/games/BAR.sdd   -- what matches actually run against. Pinned,
                                     and the only tree the dev gadgets live in.
  reference  vendor/bar           -- upstream master. What BAR has *today*.

A unit present upstream and absent in the game tree is not a unit you can use;
a unit present in both may still differ in cost. Every answer below says which
tree it came from, and divergence is always reported.

    python tools/unitdef.py corasy              # both trees, side by side
    python tools/unitdef.py corasy --builders   # who can build it
    python tools/unitdef.py legsy --builds      # what it builds
    python tools/unitdef.py "advanced ship"     # search display names
    python tools/unitdef.py --trees             # where the trees are, and their dates

A filename search answers none of this: unit defs sit in arbitrary faction
subdirectories, display names live in language/en/units.json, and what can
actually be BUILT is neither -- it is the buildoptions of constructors.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

import bar_env

FIELDS = ("metalcost", "energycost", "buildtime", "maxdamage",
          "minwaterdepth", "onlytargetcategory")
FIELD_RE = {k: re.compile(rf"\b{k}\s*=\s*([^,\n\}}]+)", re.I) for k in FIELDS}
BUILDOPT_RE = re.compile(r"buildoptions\s*=\s*\{(.*?)\}", re.S | re.I)
OPT_RE = re.compile(r'"([a-z0-9_]+)"', re.I)


class Tree:
    def __init__(self, label: str, root: Path):
        self.label = label
        self.root = root
        self.ok = root.is_dir() and (root / "units").is_dir()
        self._files: list[Path] | None = None
        self._lang: dict | None = None

    def files(self) -> list[Path]:
        if self._files is None:
            self._files = list((self.root / "units").rglob("*.lua")) if self.ok else []
        return self._files

    def lang(self) -> dict:
        if self._lang is None:
            f = self.root / "language" / "en" / "units.json"
            try:
                d = json.loads(f.read_text(encoding="utf-8"))
                u = d.get("units", {})
                self._lang = {"names": u.get("names", {}),
                              "descriptions": u.get("descriptions", {})}
            except Exception:  # noqa: BLE001
                self._lang = {"names": {}, "descriptions": {}}
        return self._lang

    def find(self, name: str) -> Path | None:
        target = name.lower() + ".lua"
        for p in self.files():
            if p.name.lower() == target:
                return p
        return None

    def head(self) -> str:
        try:
            r = subprocess.run(["git", "log", "-1", "--format=%h %ad", "--date=short"],
                               cwd=self.root, capture_output=True, text=True, timeout=20)
            return r.stdout.strip() or "(no git info)"
        except Exception as exc:  # noqa: BLE001
            return f"(git unavailable: {exc})"

    def info(self, name: str) -> dict | None:
        p = self.find(name)
        if p is None:
            return None
        text = p.read_text(encoding="utf-8", errors="replace")
        out = {"path": p.relative_to(self.root),
               "name": self.lang()["names"].get(name),
               "description": self.lang()["descriptions"].get(name)}
        for k in FIELDS:
            m = FIELD_RE[k].search(text)
            if m:
                out[k] = m.group(1).strip().strip('"')
        m = BUILDOPT_RE.search(text)
        out["builds"] = OPT_RE.findall(m.group(1)) if m else []
        return out

    def builders_of(self, name: str) -> list[str]:
        needle = f'"{name}"'
        out = []
        for p in self.files():
            try:
                text = p.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            if needle not in text:
                continue
            m = BUILDOPT_RE.search(text)
            if m and needle in m.group(0):
                out.append(p.stem)
        return sorted(set(out))


def trees(env) -> tuple[Tree, Tree]:
    return (Tree("game", env.game_sdd),
            Tree("reference", bar_env.REPO / "vendor" / "bar"))


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("query", nargs="?")
    ap.add_argument("--builders", action="store_true", help="who can build it")
    ap.add_argument("--builds", action="store_true", help="what it builds")
    ap.add_argument("--trees", action="store_true", help="tree locations and dates")
    args = ap.parse_args()

    env = bar_env.load()
    game, ref = trees(env)

    if args.trees or not args.query:
        for t in (game, ref):
            print(f"{t.label:<10} {t.root}")
            print(f"{'':<10} {t.head() if t.ok else 'MISSING'}")
        print("\nMatches run against 'game'. 'reference' is upstream master.")
        if not args.query:
            return 0

    q = args.query
    gi, ri = game.info(q), ref.info(q)

    if gi is None and ri is None:
        hits = {k: v for t in (game, ref) for k, v in t.lang()["names"].items()
                if q.lower() in v.lower()}
        if hits:
            print(f"no unit def named '{q}'. Display-name matches:")
            for k, v in sorted(hits.items()):
                where = "both" if game.find(k) and ref.find(k) else (
                    "game only" if game.find(k) else "reference only")
                print(f"  {k:<22} {v:<28} [{where}]")
            return 0
        print(f"'{q}': not found in either tree.")
        return 1

    # Divergence is the headline, not a footnote.
    if gi is None:
        print(f"!! '{q}' exists UPSTREAM ONLY -- it is NOT in the game matches run "
              f"against.\n   Do not use it in AI code. game={game.head()}\n")
    elif ri is None:
        print(f"!! '{q}' is in the game tree but NOT upstream -- likely removed from "
              f"BAR since {game.head()}.\n")

    src = gi or ri
    origin = "game" if gi else "reference"
    print(f"{q}   [{origin}]")
    print(f"  file        {src['path']}")
    print(f"  name        {src.get('name') or '(not in units.json)'}")
    print(f"  description {src.get('description') or '-'}")
    for k in FIELDS:
        if k in src:
            line = f"  {k:<11} {src[k]}"
            if gi and ri and ri.get(k) not in (None, gi.get(k)):
                line += f"   (reference: {ri.get(k)})"
            print(line)

    if args.builds:
        print(f"  builds      {', '.join(src['builds']) or '(none)'}")
    if args.builders:
        b = (game if gi else ref).builders_of(q)
        print("  built by    " + (", ".join(b) or
              "(NOBODY -- such requests are dropped silently)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
