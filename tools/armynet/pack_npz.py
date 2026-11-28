#!/usr/bin/env python3
"""Pack new training files (.npz) for the Mac, which pulls them with henry_fetch_file (10 MB a file at most).

    python tools/armynet/pack_npz.py --out henry-outbox/workhorse/npz-late-1 --sent henry-outbox/workhorse/npz-sent-1120.txt

New = an .npz whose name is not in --sent, or built after --sent's .stamp (a re-recorded game). Each root keeps its
own top folder in the tars: recordings/<game>/<name>.npz (public players) and replay-orders/<game>/<name>.npz (his
games against our AI), so the Mac can unpack them into its two roots. Tars hold whole files up to LIMIT bytes; a
file bigger than that gets a tar of its own, split into <tar>.partNN. FETCH.txt lists tar, bytes, games, root.
Appends what it packed to --sent.
"""
import io
import sys
import tarfile
from pathlib import Path

ROOTS = {"recordings": Path("G:/bar-ai-archive/public-replays/recordings"),
         "replay-orders": Path("G:/bar-ai-archive/replay-orders")}
LIMIT = 9_500_000


def main(a):
    def opt(name, default=None):
        return a[a.index(name) + 1] if name in a else default
    out, sent_p = Path(opt("--out")), Path(opt("--sent"))
    out.mkdir(parents=True, exist_ok=True)
    sent = set(sent_p.read_text(encoding="utf-8").split("\n")) if sent_p.exists() else set()
    stamp_p = sent_p.with_suffix(".stamp")
    stamp = float(stamp_p.read_text().strip()) if stamp_p.exists() else 0.0
    n_tar = len(list(out.glob("*.tar"))) + len(list(out.glob("*.tar.part00")))
    lines, packed = [], []
    for label, root in ROOTS.items():
        new = sorted(p for p in root.glob("*/*.npz") if p.name not in sent or p.stat().st_mtime > stamp)
        print("%s: %d new" % (label, len(new)))
        batch, size = [], 0

        def flush(files):
            nonlocal n_tar
            if not files:
                return
            name = "late-%03d-%s.tar" % (n_tar, label)
            n_tar += 1
            buf = io.BytesIO()
            with tarfile.open(fileobj=buf, mode="w") as t:
                for f in files:
                    t.add(f, arcname="%s/%s/%s" % (label, f.parent.name, f.name))
            data = buf.getvalue()
            if len(data) > LIMIT * 1.05:
                parts = [data[i:i + LIMIT] for i in range(0, len(data), LIMIT)]
                for k, part in enumerate(parts):
                    (out / ("%s.part%02d" % (name, k))).write_bytes(part)
                lines.append("%s.part00..part%02d\t%d\t%d\t%s" % (name, len(parts) - 1, len(data), len(files), label))
            else:
                (out / name).write_bytes(data)
                lines.append("%s\t%d\t%d\t%s" % (name, len(data), len(files), label))
            packed.extend(f.name for f in files)

        for f in new:
            s = f.stat().st_size
            if s > LIMIT:
                flush([f])
                continue
            if size + s > LIMIT:
                flush(batch)
                batch, size = [], 0
            batch.append(f)
            size += s
        flush(batch)
    with open(out / "FETCH.txt", "a", encoding="utf-8") as f:
        for ln in lines:
            f.write(ln + "\n")
    with open(sent_p, "a", encoding="utf-8") as f:
        for nm in packed:
            f.write(nm + "\n")
    print("tars %d, games %d -> %s" % (len(lines), len(packed), out / "FETCH.txt"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
