# 06 — Building the AI DLL from C++

The full-control path, and the only layer that can reach threat evaluation,
attack-target selection or anything else the AngelScript bindings do not expose.

Assembled from primary sources (the Dockerfile, `toolchain.cmake`, `build.sh`,
`configure.sh`, the CMake macros) — as far as I could find, **no one has
published an end-to-end walkthrough of building a custom BAR AI DLL on
Windows**.

**Status, verified 2026-08-02: the build works on this machine and has been run
many times.** Everything under "Rebuilding here" below is executed, not
inferred. The one-time WSL/clone setup further down is history -- it is how the
tree got here, and you do not need it again.

Steps still marked **inferred** are read off source rather than run.

## What you're building

`beyond-all-reason/RecoilEngine` vendors CircuitAI twice as submodules:

```
[submodule "AI/Skirmish/BARb"]      url = https://github.com/rlcevg/CircuitAI.git   branch = barbarian
[submodule "AI/Skirmish/CircuitAI"] url = https://github.com/rlcevg/CircuitAI.git   branch = zk
```

**CircuitAI cannot build standalone.** Its `CMakeLists.txt` references
`${CMAKE_SOURCE_DIR}/rts/System/StringUtil.cpp`, the `Cpp_AIWRAPPER_TARGET` and
`CUtils` targets, and `Tracy::TracyClient`, then calls
`configure_native_skirmish_ai(...)` — a macro defined in
`AI/Interfaces/C/CMakeLists.txt`. You build in-tree, inside RecoilEngine.

That macro sets `myTarget` from the directory name and forces the output name:

```cmake
set(myTarget "${myName}")                                   # -> BARb
add_library(${myTarget} MODULE ${mySources} ...)
set_target_properties(${myTarget} PROPERTIES OUTPUT_NAME "SkirmishAI")
```

So the CMake target is **`BARb`** and the artifact lands at
`<build>/AI/Skirmish/BARb/data/SkirmishAI.dll`. *(Target name inferred from the
macro; verify with `ninja -t targets | grep -i barb`.)*

## Rebuilding here — the actual loop

The tree is already cloned, patched and configured; ccache is warm. A rebuild is
one ninja step. **Start Docker Desktop first** — the daemon is often stopped, and
the failure is `failed to connect to the docker API at npipe:...`.

```bash
cd vendor/engine
CWD=$(cygpath -w -a .)
IMG='ghcr.io/beyond-all-reason/recoil-build-amd64-windows@sha256:3ba630ac0c181a95dde522c3a4a81df2302914c7c4e6674e6bde0d4f6bf058ef'
docker run --rm \
  -v "${CWD}":/build/src:ro \
  -v "${CWD}\.cache\ccache-amd64-windows":/build/cache \
  -v "${CWD}\build-amd64-windows":/build/out \
  -e CCACHE_DIR=/build/cache "$IMG" bash -c "ninja -C /build/out BARb"
```

Artifact: `vendor/engine/build-amd64-windows/AI/Skirmish/BARb/data/SkirmishAI.dll`

Sizes tell you which one you have: the build output is **~205 MB** with full
DWARF; the copy committed at `ai/apex/engine-side/SkirmishAI.dll` is **~6.9 MB**,
stripped by hand. Keep the unstripped one out of git.

### Deploy picks up the local build automatically

`deploy_ai.py deploy` prefers the freshly built DLL whenever that path exists,
and prints which copy went out:

```
overlaid AIInfo.lua, AIOptions.lua, SkirmishAI.dll (local build)
overlaid AIInfo.lua, AIOptions.lua, SkirmishAI.dll (repo copy -- no local build in vendor/)
```

**Read that line.** A deploy silently reinstating the stripped repo copy looks
exactly like the C++ fix never working.

### The source is not the binary

The deployed DLL can lag the C++ in `vendor/`. Verified case: `quotaRaidMin` is
registered on `CMilitaryManager` in the current source, and referencing it from
AngelScript still failed with *"not a member of 'CMilitaryManager'"* because the
running DLL predated it. If a binding exists in source but the script cannot see
it, rebuild before assuming anything else.

### Keep the change reproducible

`vendor/` is gitignored, so a C++ edit lives only in a working tree and one
binary until it is captured as a patch. Regenerate the cumulative patch after
any change:

```bash
cd vendor/engine/AI/Skirmish/BARb
git diff > /path/to/bar-ai/game-patches/circuitai/0003-cumulative.patch
```

See `game-patches/circuitai/README.md` — apply only the cumulative patch; the
numbered ones are kept for their reasoning and conflict if replayed in sequence.

### Resolving a crash address

Offsets in an infolog stacktrace are relative to the module base, so add the PE
ImageBase before calling addr2line, and the reported PC is the RETURN address --
the faulting instruction is the one before it. Getting that backwards cost a
wrong diagnosis here.

```bash
x86_64-w64-mingw32-addr2line -f -C -i -e SkirmishAI.dll <ImageBase + offset>
```

## The toolchain you must match

The shipped DLL was probed directly. It reports `GCC: (GNU) 13`, contains a
mingw-w64 winpthreads path string, and imports **only** `kernel32.dll` and
`msvcrt.dll` — no `VCRUNTIME140`, no `libstdc++-6.dll`.

That is: **MinGW-w64 GCC 13, `-static-libstdc++ -static-libgcc`, legacy msvcrt
CRT.** Fully self-contained, no runtime DLLs to ship.

From `docker-build-v2/images/amd64-windows/toolchain.cmake`:

```cmake
SET(CMAKE_SYSTEM_NAME Windows)
SET(CMAKE_C_COMPILER   "x86_64-w64-mingw32-gcc-posix")
SET(CMAKE_CXX_COMPILER "x86_64-w64-mingw32-g++-posix")
SET(CMAKE_RC_COMPILER  "x86_64-w64-mingw32-windres")
SET(CMAKE_CXX_FLAGS_INIT "-static-libstdc++ -static-libgcc")
SET(CMAKE_DISABLE_PRECOMPILE_HEADERS ON)
```

The **`-posix`** threading variant is required (`std::thread`,
`std::condition_variable`). The image also clones
`beyond-all-reason/mingwlibs64` and points `MINGWLIBS` at it.

`AI/CMakeLists.txt` additionally applies, under MinGW,
`-Wl,--kill-at -Wl,--add-stdcall-alias`.

**Do not build the AI with MSVC** unless you build the whole engine with MSVC.
The AI↔engine boundary is a C struct of ~596 function pointers, and memory
crosses it; mixing UCRT and msvcrt CRTs is asking for trouble. CircuitAI does
have working MSVC support (there's a merged "fix: MSVC compilation" PR), but
that's for an all-MSVC stack. Nobody appears to have tested a mixed build.

## First-time setup (history — already done on this machine)

Kept because it explains how the tree was produced and what to redo if it is
ever lost. For an ordinary rebuild use "Rebuilding here" above.

The BAR docs are explicit that native Windows Docker is *"very slow in
comparison"* and that with WSL2 you should keep the checkout **inside the WSL
filesystem, not on `/mnt/c`**.

One-time setup:

```powershell
wsl --install -d Ubuntu     # reboot may be required
# start Docker Desktop, and enable WSL2 integration for the Ubuntu distro
```

Then, inside WSL (not `/mnt/c`):

```bash
git clone --recurse-submodules https://github.com/beyond-all-reason/RecoilEngine
cd RecoilEngine

# Match the engine you actually run, or the ABI may not line up (see below)
git checkout 2026.06.12
git submodule update --init --recursive

docker-build-v2/build.sh --configure windows        # pulls ghcr.io/beyond-all-reason/recoil-build-amd64-windows
docker-build-v2/build.sh --compile   windows -t BARb
```

Result: `build-amd64-windows/AI/Skirmish/BARb/data/SkirmishAI.dll`.

Things the scripts do that will bite you otherwise:

- `configure.sh` passes `-DAI_EXCLUDE_REGEX="^CppTestAI$"` — official builds skip
  CppTestAI. Drop it if you want to build that template.
- `compile.sh` **skips `cmake --install` when you pass custom build args**, so
  with `-t BARb` you copy the DLL out yourself.
- `build.sh` mounts the source read-only (`:ro`); edit on the host.
- It refuses to run with unsynced submodules. Escape hatch:
  `touch .i-understand-git-submodules.txt`.
- `AI_TYPES` already defaults to `NATIVE`; the MSVC wiki's instruction to change
  it is stale.

Deploy your build:

```bash
python tools/deploy_ai.py deploy mybuild     # sets up the folder + configs
# then overwrite the DLL it copied from stable:
cp SkirmishAI.dll "<data>/engine/recoil_2026.06.12/AI/Skirmish/BARb/mybuild/"
```

Keeping it under a **new version name** means stock BARb stays intact and you can
A/B them in one match with `tools/run_match.py`.

## ABI compatibility — build against your engine

`interfaceVersion` is `'0.1'` and has not moved in years. **It is not a
compatibility contract.** The boundary is the raw layout of
`struct SSkirmishAICallback`; if a newer engine inserts a pointer mid-struct, an
older DLL calls the wrong function with no diagnostic.

I could find **no documented AI-ABI stability policy** anywhere in RecoilEngine's
docs, wiki or changelogs. Practical rule: check out the engine tag you run,
build against it, rebuild when BAR updates. Your DLL imports nothing from the
engine binary, so there's no link-time error to warn you — failures will be
runtime weirdness.

## Dependencies

Vendored inside CircuitAI: AngelScript (`src/lib/angelscript/`, plus an optional
JIT under `platform/angelscript/jit/`, `-DCIRCUIT_AS_JIT=ON`), JsonCpp, Lemon.
From the engine: the generated C++ AI wrapper, `CUtils`, `Tracy::TracyClient`.
Optional: SDL2, only for `CIRCUIT_DEBUG` / `DEBUG_VIS`.
**Required on the host: `awk`** — the C++ wrapper is generated by awk scripts and
is silently skipped without it.

CircuitAI is C++20; the engine is C++23.

## Reading the wrapper API

`AI/Wrappers/Cpp` is generated at build time from the C headers by
`bin/wrappCallback.awk`, `wrappEvents.awk`, `combine_wrappCallback.awk`. You
cannot read it in the repo. After configuring, look in:

```
<build>/AI/Wrappers/Cpp/src-generated/*.h
```

Generated classes (namespace `springai`): `OOAICallback`, `Unit`, `UnitDef`,
`WeaponDef`, `Weapon`, `Economy`, `Game`, `Map`, `Mod`, `Team`, `Group`,
`Pathing`, `Resource`, `Feature`, `FeatureDef`, `MoveData`, `Cheats`, `Command`,
`Damage`, `DataDirs`, `Log`, `Lua`, `OptionValues`, `SkirmishAI`, `Version`,
`Engine`, and ~20 more. Hand-written: `AIFloat3`, `AIColor`, `AIEvent`,
`AIException`.

Ownership convention, straight from CppTestAI: **callback getters return raw
owning pointers you must `delete`.**

```cpp
int CCppTestAI::HandleEvent(int topic, const void* data) {
    switch (topic) {
        case EVENT_UNIT_CREATED: {
            const std::vector<springai::Unit*> units = callback->GetFriendlyUnits();
            const std::unique_ptr<springai::Game> game(callback->GetGame());
            game->SendTextMessage("hello", 0);
            for (springai::Unit* u : units) delete u;
            break;
        }
    }
    return 0;
}
```

## Alternative: build without Docker

`https://recoilengine.org/development/building-without-docker/` and
`AGENTS.md` in the engine repo:

```bash
mkdir -p build && cd build && cmake -G Ninja .. && cmake --build . --target BARb
```

On Windows this still needs a MinGW-w64 GCC 13 posix toolchain plus
`mingwlibs64`. The container exists because assembling that by hand is the
tedious part.

## Contributing back

C++ and AngelScript-binding changes go to `rlcevg/CircuitAI` branch `barbarian`
(very active — recent PRs for macOS arm64 and MSVC were merged). Game-side
configs go to `beyond-all-reason/Beyond-All-Reason`.

BAR's `AI_POLICY.md` requires disclosing AI-assisted code in the PR and having a
human verify it; undisclosed use gets the PR closed. It also recommends attaching
test artifacts — the tournament ledger from `tools/run_tournament.py` is exactly
that.

## Active forks worth reading

`tomjn/CircuitAI` (branches `bai2`, `barb3`, `f2`, `f3`, `m4` — the most
experimental variant fork found), `Anarchid/CircuitAI` (BAR/ZK dev),
`sprunk/CircuitAI` (Recoil maintainer), `erik-moedt/bargandhi` (a named custom
BAR AI fork; its provenance is unclear — worth a look for precedent).
