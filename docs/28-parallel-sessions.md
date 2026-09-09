# 28 — Two sessions, one repo

Several Claude sessions work this repo at once. Four things are shared that are
not safe to share, and each has already produced a wrong answer.


## Claim a lane, then forget about it

```bash
python tools/lane.py init <name>     # once, at the start of a session
python tools/lane.py status          # what am I using?
```

That is the whole interface. After `init`, `build_dll.py`, `deploy_ai.py`,
`sync_cpp.py`, `smoke.py` and `run_match.py` all pick the lane up on their own.
There is no flag to pass and no variable to export — the harness does not keep
shell state between calls, so the claim is recorded in `.barai-lanes` at the
repo root, **keyed by `CLAUDE_CODE_SESSION_ID`**. A session sees only its own
claim. The first design was one bare name for the whole checkout, and a session
that had claimed nothing inherited another's lane and wrote into its tree
(`docs/25`, S25).

**The shared slot is apexearth's.** `Apex:Unstable` is what the dashboard
launches and what he plays while sessions work. So a Claude session with no
claim is refused by every tool that writes a slot (`build_dll`, `sync_cpp
pull|apply`, `deploy`, `run_match`) rather than landing there, and each of
those prints `lane: <name>` as its first line. `BARAI_LANE=<name>` on one
command overrides the claim; `BARAI_LANE=shared` names his slot on purpose,
which is how it gets deployed for him to watch. A shell with no session id is
his own and needs no claim.

Your AI is then `Apex<name>:lane-<name>`, which is what you pass to
`run_match.py --a`. `lane.py status` prints it.

## What a lane redirects

| | shared slot | lane `foo` |
|---|---|---|
| C++ source you edit | `vendor/engine/AI/Skirmish/BARb` | `…/BARb-foo` |
| build output | `vendor/engine/build-amd64-windows` | `vendor/engine/build-foo` |
| deployed AI | `Apex:Unstable` | `Apexfoo:lane-foo` |
| engine write dir | `matches/_engine` | `matches/_engine-foo` |

Not redirected, deliberately: the **10 GB engine** (read-only input), the
**1.6 GB ccache** (concurrency-safe, and sharing it is why a lane's first real
build takes ~50 s instead of ten minutes), and **`ai/Unstable/`** — the
AngelScript everyone is working on. A lane is a shipping slot, not a fork:
`ai/lane-foo/` is re-copied from `ai/Unstable/` on every deploy, so a lane can
never quietly diverge from the work. A lane costs ~0.7 GB.

## Why each one matters

- **C++ source.** Two sessions editing `BARb/src` build one DLL containing both
  sets of changes. Whoever measures first attributes the other's work to their
  own — the exact attribution failure `CLAUDE.md` opens with.
- **Build output.** One `build-amd64-windows` means the second session's build
  replaces the artifact between the first session's build and its deploy.
- **Deploy target.** Both sessions ship `Apex:Unstable`, so the live AI is
  whoever deployed last. Worse, `deploy_ai.py` refuses outright while *any*
  engine is running, which serialises two sessions that would never have
  collided. With a lane the folders differ, so the refusal does not apply and
  both can deploy and run at once.
- **Engine write dir.** Two engines sharing one write dir interleave into one
  `infolog.txt`.

## The incident this came from (2026-09-07)

A session edited `SquadTask.cpp` in `vendor/` and did not run
`sync_cpp.py pull`. The other session's tree was later applied over `vendor/`,
and the edit — which existed in exactly one directory — was gone. Its
instrument had already produced real numbers from the deployed binary, so the
findings were true and the source that produced them no longer existed.

**Mirror after every C++ edit, lane or no lane:**

```bash
python tools/sync_cpp.py pull
```

`sync_cpp.py` follows the lane, so this mirrors `BARb-<lane>` into `cpp/`.
`cpp/` is the only copy git keeps; `vendor/` is gitignored.

## Traps

- **No leading underscore in a lane name.** The variant is also a directory
  under `AI/Skirmish/<shortName>/`, and the engine's scan skips `_`-prefixed
  directories. `_lane-x` deployed cleanly, passed every check in this repo, and
  died at frame 146 with `[FetchSkirmishAILibrary] unknown skirmish AI`.
  `lane.py` strips non-alphanumerics from the name for this reason.
- **A lane's first `build_dll.py` says "already current".** The copied build
  tree is a copy of a finished build, so ninja has nothing to do. The build
  check now compares the artifact against the newest source file rather than
  asking whether the mtime moved — which is strictly stronger, since it also
  catches a build that reported success while leaving an artifact older than
  the code that was meant to produce it.
- **A lane still shares the game install's `BAR.sdd`.** Gadgets and patches
  (`deploy_ai.py gadgets|patches`) are global. Two sessions changing modoption
  gadgets still collide; that is not solved here.
- **`lane.py drop <name>`** deletes the lane's directories. Do it when the
  session is finished, or they accumulate at 0.7 GB each.
