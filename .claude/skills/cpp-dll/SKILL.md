---
name: cpp-dll
description: Modify, build, deploy, and verify the custom CircuitAI C++ DLL (SkirmishAI.dll) for the apex BAR AI. Use when a change needs the C++ layer - squad movement, threat evaluation, task types, new AngelScript bindings - or when diagnosing whether the running DLL matches the source.
---

# The C++ layer — edit, build, deploy, verify

The only layer that reaches squad movement, threat evaluation, target
selection, and anything the AngelScript bindings don't expose. apexearth
2026-08-20: "it is a good thing if we can extend the logic in there to be
more capable... I understand the crash risk and am OK with it." Don't be shy
about this layer — but respect its failure modes, which are silent or fatal.

## Where things live

- **`vendor/engine/AI/Skirmish/BARb/src/circuit/`** — the BUILD tree. Edit
  here. It is a git repo on a local `barbarian-apex` branch, gitignored by
  the parent repo.
- **`cpp/src/circuit/`** — the version-controlled mirror (source of truth
  for git). After any vendor edit: `python tools/sync_cpp.py pull`.
  **This is not optional.** A vendor edit that is not mirrored exists in
  exactly one gitignored directory, and the next `sync_cpp.py apply` — from
  this session or another one — destroys it. That happened 2026-09-07: the
  instrument's numbers survived in the deployed binary and its source did not.
- **Another session may be editing the same tree.** If one might be, claim a
  lane first: `python tools/lane.py init <name>` gives you a private
  `BARb-<name>` source, a private build output and a private deploy slot, then
  every tool here follows it with no flags. `docs/28-parallel-sessions.md`.
  Without one, two sessions build a single DLL containing both their changes
  and each measures the other's work as its own.
- Key files: `task/fighter/SquadTask.cpp` (wall, regroup, standoff ring,
  kite), `task/fighter/AttackTask.cpp` (engage decision, DEPLOY_SLACK,
  assembly gate, flanking, attack-break), `module/MilitaryManager.cpp`,
  `script/InitScript.cpp` + `script/*Script.cpp` (AngelScript bindings).
- `docs/06-building-the-dll.md` is the full walkthrough; this skill is the
  working summary.

## The loop

1. Edit in `vendor/engine/AI/Skirmish/BARb/src/circuit/...`.
2. **Start Docker Desktop** (usually stopped; failure reads
   `failed to connect to the docker API at npipe:...`), wait for
   `docker info` to succeed.
3. Build (warm ccache, minutes):
   ```bash
   cd vendor/engine
   CWD=$(cygpath -w -a .)
   IMG='ghcr.io/beyond-all-reason/recoil-build-amd64-windows@sha256:3ba630ac0c181a95dde522c3a4a81df2302914c7c4e6674e6bde0d4f6bf058ef'
   docker run --rm -v "${CWD}":/build/src:ro \
     -v "${CWD}\.cache\ccache-amd64-windows":/build/cache \
     -v "${CWD}\build-amd64-windows":/build/out \
     -e CCACHE_DIR=/build/cache "$IMG" bash -c "ninja -C /build/out BARb"
   ```
   Artifact: `vendor/engine/build-amd64-windows/AI/Skirmish/BARb/data/SkirmishAI.dll` (~205MB with DWARF).
4. `python tools/deploy_ai.py deploy Unstable` — **read the output line**: it
   must say `SkirmishAI.dll (local build)`. `(repo copy)` means the stripped
   6.9MB fallback shipped and your C++ never ran.
5. Smoke: one short `run_match.py` game, then gate it:
   - `grep -c "apex:" infolog.txt` nonzero (AI alive)
   - `grep asALREADY_REGISTERED infolog.txt` empty (a DUPLICATE binding
     kills the AI at init; result.json says crashed with EMPTY stats and
     only this line tells you why)
   - exit code / `result.json` not crashed; watch for `0xc0000005`
     (a release build compiles asserts out — bounds-check by hand, see the
     GetBuilderThreatAt story in CLAUDE.md)
6. Capture: `python tools/sync_cpp.py pull`, then regenerate the cumulative
   patch:
   ```bash
   cd vendor/engine/AI/Skirmish/BARb
   git diff --ignore-cr-at-eol $(git merge-base apex/barbarian HEAD) \
       > <repo>/game-patches/circuitai/0003-cumulative.patch
   ```
   A bare `git diff` drops everything already committed on `barbarian-apex`.
   **In a lane, `BARb-<lane>/.git` points at the SHARED gitdir**, so every git
   command run inside it reads `BARb/`'s files, not the lane's -- a `git diff`
   there silently omits the lane's edits (2026-09-13). Diff the lane tree
   through a scratch index instead:
   ```bash
   cd vendor/engine/AI/Skirmish/BARb && BASE=$(git merge-base apex/barbarian HEAD)
   GIT_INDEX_FILE=/tmp/lane.idx git read-tree $BASE
   GIT_INDEX_FILE=/tmp/lane.idx git --work-tree=../BARb-<lane> add -A src
   GIT_INDEX_FILE=/tmp/lane.idx git diff --cached --ignore-cr-at-eol $BASE > <repo>/game-patches/circuitai/0003-cumulative.patch
   ```

## Crash triage

Stack offsets are module-relative: add the PE ImageBase, and the reported PC
is the RETURN address — the faulting instruction is the one before it.
```bash
x86_64-w64-mingw32-addr2line -f -C -i -e SkirmishAI.dll <ImageBase+offset>
```

## Traps specific to this layer

- **The source is not the binary.** A binding in source that the script
  can't see = stale DLL. Rebuild before diagnosing anything else.
- **`(local build)` is stale-blind.** The deploy line confirms WHICH file
  shipped, not that your build produced it: a FAILED ninja leaves the
  previous DLL in place, deploy happily ships it, and the smoke test greens
  on old code (happened live 2026-08-20: RaidTask const error, two "passing"
  smoke games on the prior binary). After every build: check ninja's output
  for FAILED/error AND compare the DLL mtime against the build attempt.
- Never deploy while any match/tournament/arm is running — engines launched
  after the deploy run the new DLL mid-experiment.
- New AngelScript bindings: registering a name that already exists returns
  asALREADY_REGISTERED and the ASSERT kills the AI at init (measured: a
  SetRetreat bound twice, 14 lines apart).
- `Date`-like nondeterminism doesn't exist here, but the DLL is
  multithreaded: identical seeds do NOT reproduce runs; measure with paired
  batches, never single games.
- Desync: the DLL is host-side in multiplayer. After any C++ change that
  alters engine calls, the desync-check skill applies before hosted play.
- Read tunables via `circuit->GetTunable("apex_...", default)` — they flow
  from modoptions through dev_tunables.lua, so behavior changes are A/B-able
  without rebuilds. Add new names to the gadget's list.
