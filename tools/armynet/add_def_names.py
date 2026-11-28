#!/usr/bin/env python3
"""Add def_names to training .npz files built before replay_dataset.py saved them (the army model looks up each unit's
full stats by name, tools/armynet/unitstats.py). Reads only the D lines of the recording beside each .npz
(orders.txt.gz or orders.txt in the same folder); no rebuild.

    python tools/armynet/add_def_names.py <roots ...> [--dry]
    python tools/armynet/add_def_names.py <roots ...> --borrow [--dry]
        (files whose recording is gone: each def's name from named files with the identical defs row -- same id and
        same stats is the same unit in the same game version)

A root is a folder searched recursively for *.npz. Files that already carry def_names, or have no recording beside
them, are skipped and counted.
"""
import gzip
import os
import sys
from pathlib import Path

import numpy as np


def names_from(rec):
    """{def id: name} from the recording's D lines (written at game start, before the first unit sample)."""
    op = gzip.open if rec.suffix == ".gz" else open
    out = {}
    with op(rec, "rt", encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            if ln.startswith("D "):
                p = ln.split(" ")
                if len(p) > 2:
                    out[int(p[1])] = p[2]
            elif out and ln.startswith("U "):
                break
    return out


def row_key(r):
    """A defs row as a key: its id and every stat the recording gave it (rounded), so a borrowed name is only ever
    taken from the same unit in the same game version."""
    return (int(r[0]),) + tuple(round(float(v), 3) for v in r[1:])


def borrow(roots, dry):
    """Files with no recording beside them take each def's name from named files whose defs row is identical (same id
    and same stats: within one game version a def id is the same unit). A row with no match, or with two different
    names, stays unnamed ("")."""
    table = {}
    named, todo = [], []
    for root in roots:
        for p in sorted(root.rglob("*.npz")):
            try:
                with np.load(p) as z:
                    if "def_names" in z.files:
                        named.append(p)
                        for r, n in zip(z["defs"], z["def_names"]):
                            if str(n):
                                table.setdefault(row_key(r), set()).add(str(n))
                    else:
                        todo.append(p)
            except Exception as e:  # noqa: BLE001
                print("skip %s: %s" % (p, e), flush=True)
    print("borrow: %d named files give %d distinct rows; %d files to name" % (len(named), len(table), len(todo)),
          flush=True)
    done = full = 0
    for p in todo:
        try:
            with np.load(p) as z:
                data = {k: z[k] for k in z.files}
            names = []
            for r in data["defs"]:
                s = table.get(row_key(r), set())
                names.append(next(iter(s)) if len(s) == 1 else "")
            got = sum(1 for n in names if n)
            if got == len(names):
                full += 1
            if dry:
                print("would name %d of %d defs in %s" % (got, len(names), p.name))
            else:
                data["def_names"] = np.array(names)
                tmp = p.with_name(p.stem + ".tmp.npz")
                np.savez_compressed(tmp, **data)
                os.replace(tmp, p)
            done += 1
            if done % 50 == 0:
                print("%d done (%d fully named)" % (done, full), flush=True)
        except Exception as e:  # noqa: BLE001
            print("skip %s: %s" % (p, e), flush=True)
    print("borrowed names for %d files, %d of them fully named" % (done, full))


def main(a):
    dry = "--dry" in a
    if "--borrow" in a:
        borrow([Path(x) for x in a if not x.startswith("--")], dry)
        return 0
    roots = [Path(x) for x in a if not x.startswith("--")]
    done = had = norec = bad = 0
    for root in roots:
        for p in sorted(root.rglob("*.npz")):
            try:
                with np.load(p) as z:
                    if "def_names" in z.files:
                        had += 1
                        continue
                    rec = next((p.parent / n for n in ("orders.txt.gz", "orders.txt") if (p.parent / n).exists()), None)
                    if rec is None:
                        norec += 1
                        continue
                    data = {k: z[k] for k in z.files}
                names = names_from(rec)
                ids = [int(r[0]) for r in data["defs"]]
                data["def_names"] = np.array([names.get(i, "") for i in ids])
                missing = sum(1 for i in ids if i not in names)
                if dry:
                    print("would add %d names (%d missing) to %s" % (len(ids), missing, p.name))
                    done += 1
                    continue
                tmp = p.with_name(p.stem + ".tmp.npz")
                np.savez_compressed(tmp, **data)
                os.replace(tmp, p)
                done += 1
                if done % 50 == 0:
                    print("%d done" % done, flush=True)
            except Exception as e:  # noqa: BLE001 -- one bad file must not stop the batch
                bad += 1
                print("skip %s: %s" % (p, e), flush=True)
    print("added %d, already had %d, no recording %d, failed %d" % (done, had, norec, bad))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
