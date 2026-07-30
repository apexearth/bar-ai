# CircuitAI (SkirmishAI.dll) patches

Changes to the vendored AI **C++**, which lives in `vendor/` and is therefore
gitignored. Without these patches the fixes exist only in a working tree and in
one binary in the live engine directory, and vanish the next time anyone
re-clones or redeploys. They are kept here so they are reproducible.

## Applying

The source is a submodule of the vendored engine. Apply **only the cumulative
patch** -- it carries the entire C++ delta, including everything 0001 and 0002
did:

    cd vendor/engine/AI/Skirmish/BARb
    git apply /path/to/bar-ai/game-patches/circuitai/0003-cumulative.patch

`0001-guardtasks-use-after-free.patch` and `0002-real-ally-team-id.patch` are
kept for the reasoning in their headers, not to be applied. They are subsumed:
0002 and the later in-process coordination work both edit `CircuitAI.{h,cpp}`,
so applying them in sequence conflicts. One cumulative patch regenerated from
the working tree is the thing that actually reproduces the shipped DLL.

## Rebuilding

`docs/06-building-the-dll.md` says the toolchain is not installed and nothing
here has been run. **That is out of date.** The build tree is already
configured, every object is compiled `-O3 -g`, and the Docker image is present,
so a rebuild is one ninja step:

    cd vendor/engine
    CWD=$(cygpath -w -a .)
    IMG='ghcr.io/beyond-all-reason/recoil-build-amd64-windows@sha256:3ba630ac0c181a95dde522c3a4a81df2302914c7c4e6674e6bde0d4f6bf058ef'
    docker run --rm \
      -v "${CWD}":/build/src:ro \
      -v "${CWD}\.cache\ccache-amd64-windows":/build/cache \
      -v "${CWD}\build-amd64-windows":/build/out \
      -e CCACHE_DIR=/build/cache "$IMG" bash -c "ninja -C /build/out BARb"

Artifact: `vendor/engine/build-amd64-windows/AI/Skirmish/BARb/data/SkirmishAI.dll`

## Symbols

That artifact is ~205 MB and carries full DWARF; the shipped one is 6.9 MB and
stripped by hand afterwards. Keep the unstripped copy OUT of git.

Resolving a crash address: the offsets in an infolog stacktrace are relative to
the module base, so add the PE ImageBase before calling addr2line, and remember
the reported PC is the RETURN address -- the faulting instruction is the one
before it. Getting that backwards cost a wrong diagnosis here.

    x86_64-w64-mingw32-addr2line -f -C -i -e SkirmishAI.dll <ImageBase + offset>

## Caveat

A `deploy_ai.py deploy` overwrites the engine-side DLL with the stripped copy
from `ai/<variant>/engine-side/`, dropping both the symbols and any fix in this
directory. Re-copy the built DLL after every deploy until that is automated.
