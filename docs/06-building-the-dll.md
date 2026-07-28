# 06 — Building the AI DLL from C++

The full-control path. Assembled from primary sources (the Dockerfile,
`toolchain.cmake`, `build.sh`, `configure.sh`, the CMake macros) — as far as I
could find, **no one has published an end-to-end walkthrough of building a custom
BAR AI DLL on Windows**. Expect to debug.

Nothing here has been executed on this machine; the C++ toolchain is not
installed. Steps marked **inferred** are read off source rather than run.

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

## Build with the official container (recommended)

Docker Desktop is installed here but the daemon is stopped, and WSL has no
distro. The BAR docs are explicit that native Windows Docker is *"very slow in
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
