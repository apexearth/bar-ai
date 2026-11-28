#!/usr/bin/env python3
"""Read-only share of the army model's training files for the Mac (his 11-21: "it is fine to share a folder from
this PC, just for this stuff").

    python tools/armynet/npz_share.py [--port 8765] [--root <label>=<folder> ...]   (--root replaces the two roots;
                                                                                      a game may be a sub/path)

Serves only .npz files under the two recording roots, nothing else:
    GET /list                          one line per file: root TAB game TAB name TAB bytes TAB mtime
    GET /<root>/<game>/<name>.npz      the file (root: recordings | replay-orders)
Answers only the home network (192.168.0.0/16) and Tailscale (100.64.0.0/10); every request is logged.
"""
import ipaddress
import os
import sys
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOTS = {"recordings": Path("G:/bar-ai-archive/public-replays/recordings"),
         "replay-orders": Path("G:/bar-ai-archive/replay-orders")}
ALLOW = [ipaddress.ip_network("192.168.0.0/16"), ipaddress.ip_network("100.64.0.0/10"),
         ipaddress.ip_network("127.0.0.0/8")]
LOG = Path("G:/bar-ai-archive/npz-share.log")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        with open(LOG, "a", encoding="utf-8") as f:
            f.write("%s %s %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), self.client_address[0], fmt % args))

    def do_GET(self):
        ip = ipaddress.ip_address(self.client_address[0])
        if not any(ip in n for n in ALLOW):
            return self.send_error(403)
        path = urllib.parse.unquote(urllib.parse.urlparse(self.path).path).strip("/")
        if path == "list":
            lines = []
            for label, root in ROOTS.items():
                for p in root.glob("**/*.npz"):
                    st = p.stat()
                    lines.append("%s\t%s\t%s\t%d\t%d" % (label, p.parent.relative_to(root).as_posix(), p.name,
                                                         st.st_size, st.st_mtime))
            body = ("\n".join(lines) + "\n").encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            return self.wfile.write(body)
        parts = path.split("/")
        if len(parts) < 3 or parts[0] not in ROOTS or not parts[-1].endswith(".npz") or ".." in path:
            return self.send_error(404)
        f = ROOTS[parts[0]].joinpath(*parts[1:]).resolve()
        if ROOTS[parts[0]].resolve() not in f.parents or not f.is_file():
            return self.send_error(404)
        size = f.stat().st_size
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(size))
        self.end_headers()
        with open(f, "rb") as fh:
            while chunk := fh.read(1 << 20):
                self.wfile.write(chunk)


def main(a):
    port = int(a[a.index("--port") + 1]) if "--port" in a else 8765
    roots = [a[i + 1].split("=", 1) for i, x in enumerate(a) if x == "--root"]
    if roots:  # serve only these instead: --root <label>=<folder>, repeatable
        ROOTS.clear()
        ROOTS.update({k: Path(v) for k, v in roots})
    srv = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print("serving .npz on port %d (pid %d)" % (port, os.getpid()), flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
