"""Append-only training buffers for tools/nntrain.py (docs/35-decision-net.md).

A net's buffer is a directory: index.json plus segments, each segment four flat
files of rows (xf float16, y float16, m uint8, tag int32 [version, regime,
batch]). A save appends only the rows added since the last one and rewrites
only index.json, so a save costs the new rows, not the whole buffer (the old
buffer.npz was rewritten whole every ~10 batches: ~300 GB/h at 230 batches/h).

The index is the truth: bytes past a segment's committed row count (a kill
between the data write and the index write) are ignored on load and cut on the
next append. A segment keeps the layout it was written in -- state field count
k, input width nf, target count ny -- and is mapped into the current layout on
load the way nntrain's adopt_keys / adopt_targets grow the arrays in memory:
zero columns inserted at k, zero (masked) target columns appended.

    python tools/nnstore.py <shard dir>      # what a buffer holds, by regime and version
"""
import json
import os
import sys
import time
import zipfile
from pathlib import Path

import numpy as np

FORMAT = 1
SEG_ROWS = 1_000_000   # a segment closes past this many rows: the unit a compaction rewrites
F16_MAX = 65000.0      # float16 tops out at 65504; anything larger is clipped, never inf
OLD_VER = "old"        # a game logged before the version banner (2026-10-08)
UNKNOWN = "unknown"    # a row whose regime could not be recovered (migrated, live write dir)
PARTS = (("xf", np.float16), ("y", np.float16), ("m", np.uint8), ("tag", np.int32))


def f16(a):
    a = np.asarray(a, dtype=np.float32)
    return np.clip(np.nan_to_num(a, nan=0.0, posinf=F16_MAX, neginf=-F16_MAX), -F16_MAX, F16_MAX).astype(np.float16)


class Store:
    def __init__(self, root):
        self.root = Path(root)
        self.idx = None

    @property
    def index_path(self):
        return self.root / "index.json"

    def exists(self):
        return self.index_path.is_file()

    def read_index(self):
        self.idx = json.loads(self.index_path.read_text(encoding="utf-8"))
        if self.idx.get("format") != FORMAT:
            raise ValueError("%s: buffer format %s, this code reads %d" % (self.root, self.idx.get("format"), FORMAT))
        return self.idx

    def _file(self, seg, part):
        return self.root / ("seg%05d.%s" % (seg["id"], part))

    def rows(self):
        return sum(s["rows"] for s in (self.idx or self.read_index())["segs"])

    def load(self, keep=None):
        """(XF, Y, M, T, meta) in the index's current layout. `keep(T)` may
        return a boolean row mask (the per-regime cap); dropped rows stay on
        disk until compact()."""
        idx = self.read_index()
        K, NF, NY = idx["k"], idx["nf"], idx["ny"]
        n = sum(s["rows"] for s in idx["segs"])
        XF = np.zeros((n, NF), np.float16)
        Y = np.zeros((n, NY), np.float16)
        M = np.zeros((n, NY), np.uint8)
        T = np.zeros((n, 3), np.int32)
        at = 0
        for s in idx["segs"]:
            r, k, nf, ny = s["rows"], s["k"], s["nf"], s["ny"]
            gap = K - k
            if r == 0:
                continue
            if gap < 0 or nf + gap != NF or ny > NY:
                raise ValueError("%s seg %d: layout k=%d nf=%d ny=%d does not map into k=%d nf=%d ny=%d"
                                 % (self.root, s["id"], k, nf, ny, K, NF, NY))
            xf = np.fromfile(self._file(s, "xf"), dtype=np.float16, count=r * nf).reshape(r, nf)
            XF[at:at + r, :k] = xf[:, :k]
            XF[at:at + r, k + gap:] = xf[:, k:]
            del xf
            Y[at:at + r, :ny] = np.fromfile(self._file(s, "y"), dtype=np.float16, count=r * ny).reshape(r, ny)
            M[at:at + r, :ny] = np.fromfile(self._file(s, "m"), dtype=np.uint8, count=r * ny).reshape(r, ny)
            T[at:at + r] = np.fromfile(self._file(s, "tag"), dtype=np.int32, count=r * 3).reshape(r, 3)
            at += r
        if keep is not None:
            mask = keep(T)
            if mask is not None and not mask.all():
                XF, Y, M, T = XF[mask], Y[mask], M[mask], T[mask]
        return XF, Y, M, T, idx

    def append(self, XF, Y, M, T, meta):
        """Add rows in the layout meta names (k, nf, ny, ...), then commit the
        index. meta's other keys (state_keys, targets, tables, batches) replace
        the index's."""
        idx = self.idx if self.idx is not None else (self.read_index() if self.exists() else
                                                     {"format": FORMAT, "segs": [], "next": 1})
        self._write_rows(idx, XF, Y, M, T, meta)
        idx.update(meta)
        idx["nf"], idx["ny"], idx["at"] = XF.shape[1], Y.shape[1], time.time()
        self._write_index(idx)

    def _write_rows(self, idx, XF, Y, M, T, meta):
        self.root.mkdir(parents=True, exist_ok=True)
        k, nf, ny = meta["k"], XF.shape[1], Y.shape[1]
        segs = idx["segs"]
        n = len(XF)
        if n:
            seg = segs[-1] if segs else None
            if seg is None or (seg["k"], seg["nf"], seg["ny"]) != (k, nf, ny) or seg["rows"] >= SEG_ROWS:
                seg = {"id": idx["next"], "k": k, "nf": nf, "ny": ny, "rows": 0}
                idx["next"] += 1
                segs.append(seg)
            arrays = {"xf": f16(XF), "y": f16(Y), "m": np.asarray(M).astype(np.uint8),
                      "tag": np.asarray(T, dtype=np.int32).reshape(n, 3)}
            for part, dt in PARTS:
                p = self._file(seg, part)
                width = arrays[part].shape[1]
                committed = seg["rows"] * width * np.dtype(dt).itemsize
                with open(p, "r+b" if p.exists() else "wb") as fh:
                    fh.truncate(committed)
                    fh.seek(committed)
                    fh.write(np.ascontiguousarray(arrays[part], dtype=dt).tobytes())
                    fh.flush()
                    os.fsync(fh.fileno())
            seg["rows"] += n

    def _write_index(self, idx):
        self.root.mkdir(parents=True, exist_ok=True)
        tmp = self.root / "index.json.tmp"
        tmp.write_text(json.dumps(idx), encoding="utf-8")
        for i in range(20):
            try:
                os.replace(tmp, self.index_path)
                break
            except PermissionError:
                if i == 19:
                    raise
                time.sleep(0.25)
        self.idx = idx
        self._sweep()

    def _sweep(self):
        """Segment files the index no longer names (an interrupted compaction)."""
        live = {"seg%05d" % s["id"] for s in self.idx["segs"]}
        for p in self.root.glob("seg*.*"):
            if p.stem not in live and p.suffix[1:] in dict(PARTS):
                try:
                    p.unlink()
                except OSError:
                    pass

    def compact(self, XF, Y, M, T, meta):
        """Rewrite the whole buffer as these rows (after a cap dropped some):
        new segments first, the index swap commits, then the old files go."""
        old = self.read_index() if self.exists() else {"next": 1}
        fresh = {"format": FORMAT, "segs": [], "next": old["next"]}
        for a in range(0, len(XF), SEG_ROWS):
            self._write_rows(fresh, XF[a:a + SEG_ROWS], Y[a:a + SEG_ROWS], M[a:a + SEG_ROWS], T[a:a + SEG_ROWS], meta)
        fresh.update(meta)
        fresh["nf"], fresh["ny"], fresh["at"] = XF.shape[1], Y.shape[1], time.time()
        self._write_index(fresh)

    def archive(self, dest):
        """Move the whole buffer away (a fresh net): never deleted."""
        if self.root.is_dir():
            dest.parent.mkdir(parents=True, exist_ok=True)
            os.replace(self.root, dest)
        self.idx = None


def _npy_member(zf, name):
    """(open member, shape, dtype) of an uncompressed-or-not .npy inside an npz,
    positioned at the data: read sequentially, never whole."""
    fh = zf.open(name + ".npy")
    ver = np.lib.format.read_magic(fh)
    if ver == (1, 0):
        shape, fortran, dtype = np.lib.format.read_array_header_1_0(fh)
    else:
        shape, fortran, dtype = np.lib.format.read_array_header_2_0(fh)
    if fortran and len(shape) > 1:
        raise ValueError("%s is Fortran-ordered; cannot stream it by rows" % name)
    return fh, shape, dtype


def _read_rows(fh, shape, dtype, r):
    width = int(np.prod(shape[1:])) if len(shape) > 1 else 1
    need = r * width * dtype.itemsize
    buf = bytearray()
    while len(buf) < need:
        chunk = fh.read(need - len(buf))
        if not chunk:
            raise EOFError("npz member ended early")
        buf += chunk
    return np.frombuffer(bytes(buf), dtype=dtype).reshape((r,) + tuple(shape[1:]))


def migrate(npz, store, tags=None, tables=None, chunk=200_000, log=print):
    """Stream a legacy <name>buffer.npz into `store` without holding it in
    memory: XF in float16, Y float16, M uint8; XS is dropped (it is XF's first
    ns columns -- checked chunk by chunk, mismatches counted). `tags` is an
    (n, 3) int32 array for the rows, or None (all OLD_VER / UNKNOWN). Returns
    the index meta written."""
    npz = Path(npz)
    with zipfile.ZipFile(npz) as zf:
        names = {n[:-4] for n in zf.namelist() if n.endswith(".npy")}
        small = {}
        for key in ("state_keys", "batches", "targets"):
            if key in names:
                with zf.open(key + ".npy") as fh:
                    small[key] = np.lib.format.read_array(fh, allow_pickle=True)
        fx, sx, dx = _npy_member(zf, "XF")
        fs, ss, ds = _npy_member(zf, "XS")
        fy, sy, dy = _npy_member(zf, "Y")
        fm, sm, dm = _npy_member(zf, "M")
        n, nf, ns, ny = sx[0], sx[1], ss[1], sy[1]
        if not (ss[0] == sy[0] == sm[0] == n):
            raise ValueError("%s: arrays disagree on rows (%s %s %s %s)" % (npz, sx, ss, sy, sm))
        state_keys = [str(s) for s in small.get("state_keys", [])]
        k = len(state_keys)
        meta = {"k": k, "ns": int(ns), "state_keys": state_keys, "batches": int(small.get("batches", 0)),
                "targets": [str(t) for t in small.get("targets", [])],
                "tables": tables or {"ver": [OLD_VER], "regime": [UNKNOWN]}, "migrated_from": str(npz)}
        if tags is None:
            tags = np.zeros((n, 3), np.int32)
            tags[:, 2] = -1
        if len(tags) != n:
            raise ValueError("tags: %d rows for %d" % (len(tags), n))
        store.idx = {"format": FORMAT, "segs": [], "next": 1}
        bad = 0
        t0 = time.time()
        for a in range(0, n, chunk):
            r = min(chunk, n - a)
            xf = _read_rows(fx, sx, dx, r)
            xs = _read_rows(fs, ss, ds, r)
            bad += int((xs != xf[:, :ns]).any(1).sum())
            del xs
            y = _read_rows(fy, sy, dy, r)
            m = _read_rows(fm, sm, dm, r)
            store.append(xf, y, m, tags[a:a + r], meta)
            if (a // chunk) % 10 == 0:
                log("  %s: %d / %d rows (%.0f s)" % (store.root.name, a + r, n, time.time() - t0))
        for fh in (fx, fs, fy, fm):
            fh.close()
        if n == 0:
            store.append(np.zeros((0, nf), np.float32), np.zeros((0, ny), np.float32),
                         np.zeros((0, ny), np.uint8), np.zeros((0, 3), np.int32), meta)
    if bad:
        log("  %s: %d rows whose XS was not XF's first %d columns (XS is rebuilt from XF)" % (store.root.name, bad, ns))
    return store.idx


def describe(root):
    st = Store(root)
    idx = st.read_index()
    tag = np.concatenate([np.fromfile(st._file(s, "tag"), dtype=np.int32, count=s["rows"] * 3).reshape(-1, 3)
                          for s in idx["segs"] if s["rows"]] or [np.zeros((0, 3), np.int32)])
    size = sum(st._file(s, p).stat().st_size for s in idx["segs"] for p, _ in PARTS if st._file(s, p).is_file())
    print("%s: %d rows in %d segments, %.2f GB, layout k=%d nf=%d ny=%d, batches %s"
          % (root, len(tag), len(idx["segs"]), size / 1e9, idx["k"], idx["nf"], idx["ny"], idx.get("batches")))
    for col, name in ((1, "regime"), (0, "ver")):
        table = idx.get("tables", {}).get(name, [])
        ids, cnt = np.unique(tag[:, col], return_counts=True)
        for i, c in sorted(zip(ids, cnt), key=lambda p: -p[1])[:15]:
            print("  %-6s %8d  %5.1f%%  %s" % (name, c, 100.0 * c / max(len(tag), 1),
                                               table[i] if 0 <= i < len(table) else i))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    for a in sys.argv[1:]:
        describe(a)
