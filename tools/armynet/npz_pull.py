"""Pull every .npz an npz_share.py-style server lists (GET /list, GET /<root>/<game>/<name>) into <out>/<game>/<name>;
a file already there at the listed size is skipped.

    python tools/armynet/npz_pull.py <base url> <out dir>
"""
import sys
import urllib.parse
import urllib.request
from pathlib import Path

base, out = sys.argv[1].rstrip("/"), Path(sys.argv[2])
rows = [ln.split("\t") for ln in urllib.request.urlopen(base + "/list", timeout=60).read().decode().splitlines() if ln]
done = 0
for root, game, name, size, _ in rows:
    dst = out / game / name
    if dst.exists() and dst.stat().st_size == int(size):
        continue
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_suffix(".part")
    url = "%s/%s/%s/%s" % (base, *(urllib.parse.quote(x) for x in (root, game, name)))
    with urllib.request.urlopen(url, timeout=300) as r, open(tmp, "wb") as f:
        while True:
            b = r.read(1 << 20)
            if not b:
                break
            f.write(b)
    tmp.replace(dst)
    done += 1
print("pulled %d of %d into %s" % (done, len(rows), out))
