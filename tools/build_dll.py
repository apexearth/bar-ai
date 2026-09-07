"""Build the C++ AI, and REFUSE to look successful when it wasn't.

Two failures bit this repo repeatedly, both silent:

  1. A failed ninja leaves the PREVIOUS DLL in place. `deploy_ai.py` then says
     `SkirmishAI.dll (local build)` -- truthfully, the file is a local build --
     and ships hours-old code. The smoke test greens on it. Measured 2026-08-20
     (a const error, two "passing" smoke games on the prior binary) and twice
     again on 2026-09-06.
  2. Piping ninja through grep replaces its exit code with grep's, so a build
     that failed reports 0.

So this never pipes ninja, checks the exit code AND that the artifact's mtime
actually moved, and exits non-zero on either. If it prints OK, the DLL on disk
is the code in vendor/.

    python tools/build_dll.py            # build, verify
    python tools/build_dll.py --deploy   # ...and deploy only if it really built
"""

import argparse
import os
import pathlib
import subprocess
import sys
import time

IMAGE = ("ghcr.io/beyond-all-reason/recoil-build-amd64-windows@sha256:"
         "3ba630ac0c181a95dde522c3a4a81df2302914c7c4e6674e6bde0d4f6bf058ef")

REPO = pathlib.Path(__file__).resolve().parent.parent
ENGINE = REPO / "vendor" / "engine"
ARTIFACT = ENGINE / "build-amd64-windows" / "AI" / "Skirmish" / "BARb" / "data" / "SkirmishAI.dll"

# Below this the link produced a stub, not a real DLL with debug info.
MIN_BYTES = 50 * 1024 * 1024


def win(path):
    """Docker on Windows wants a native path for -v."""
    out = subprocess.run(["cygpath", "-w", "-a", str(path)],
                         capture_output=True, text=True)
    if out.returncode == 0:
        return out.stdout.strip()
    return str(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--deploy", action="store_true",
                    help="run deploy_ai.py deploy Unstable, only if the build verified")
    ap.add_argument("--variant", default="Unstable")
    ap.add_argument("--target", default="BARb")
    args = ap.parse_args()

    if not ENGINE.is_dir():
        print("no vendor/engine -- nothing to build", file=sys.stderr)
        return 2

    before = ARTIFACT.stat().st_mtime if ARTIFACT.exists() else 0.0
    started = time.time()

    cwd = win(ENGINE)
    cmd = ["docker", "run", "--rm",
           "-v", "%s:/build/src:ro" % cwd,
           "-v", "%s\\.cache\\ccache-amd64-windows:/build/cache" % cwd,
           "-v", "%s\\build-amd64-windows:/build/out" % cwd,
           "-e", "CCACHE_DIR=/build/cache", IMAGE,
           "bash", "-c", "ninja -C /build/out %s" % args.target]

    # NOT piped: ninja's own exit code has to survive.
    proc = subprocess.run(cmd, cwd=str(ENGINE))
    took = time.time() - started

    if proc.returncode != 0:
        print("")
        print("BUILD FAILED (ninja exit %d) after %.0fs." % (proc.returncode, took))
        print("The DLL on disk is the PREVIOUS build. Do not deploy it.")
        return 1

    if not ARTIFACT.exists():
        print("BUILD REPORTED OK but %s does not exist." % ARTIFACT)
        return 1

    st = ARTIFACT.stat()
    if st.st_mtime <= before:
        print("")
        print("BUILD REPORTED OK but the DLL's mtime did not move.")
        print("  %s" % ARTIFACT)
        print("Nothing was relinked; whatever is there is older than this build.")
        return 1

    if st.st_size < MIN_BYTES:
        print("BUILD REPORTED OK but the DLL is only %.1f MB -- a stub, not a link."
              % (st.st_size / 1e6))
        return 1

    print("")
    print("OK  %.1f MB  relinked %s  (%.0fs)"
          % (st.st_size / 1e6, time.strftime("%H:%M:%S", time.localtime(st.st_mtime)), took))

    if args.deploy:
        out = subprocess.run([sys.executable, str(REPO / "tools" / "deploy_ai.py"),
                              "deploy", args.variant],
                             capture_output=True, text=True, cwd=str(REPO))
        sys.stdout.write(out.stdout)
        if out.returncode != 0:
            sys.stderr.write(out.stderr)
            return out.returncode
        if "(local build)" not in out.stdout:
            print("DEPLOY DID NOT SHIP THE LOCAL BUILD -- it fell back to the repo copy.")
            return 1
        live = (pathlib.Path(os.path.expandvars(
            r"%LOCALAPPDATA%\Programs\Beyond-All-Reason\data\engine")) )
        print("deployed; verify the live mtime matches %s"
              % time.strftime("%H:%M:%S", time.localtime(st.st_mtime)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
