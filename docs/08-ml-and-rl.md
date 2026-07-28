# 08 — ML and RL: what exists, what doesn't

Short version: **there is no RL environment for Spring, Recoil or BAR.** Multiple
targeted searches turned up nothing — no gym wrapper, no gRPC bridge, no
published agent, no dataset, no bot ladder. The RTS RL ecosystem lives on
microRTS and SC2. If you want one for BAR, you would be building the first.

That's not a reason not to. It does mean budgeting for infrastructure rather than
starting from a baseline.

## What you actually have

- **Fast headless self-play.** Measured here: ~37× realtime, a full match in
  ~45 s, deterministic with `FixedRNGSeed`. That's a workable sample rate for
  evolutionary/bandit methods; it is thin for step-wise deep RL.
- **A rich hand-written baseline.** CircuitAI is a strong opponent and a strong
  starting policy. Hybrid approaches — learn a small part, keep the rest — are far
  more tractable here than learning from scratch.
- **Three parameterisable layers** (JSON, AngelScript, C++) that a search process
  can drive without touching the engine.
- **A large corpus of human games** via `api.bar-rts.com`.

## The realistic architectures, in order of cost

### 1. Black-box config search — start here

The JSON configs are a few hundred numbers. `tools/run_tournament.py` gives you a
fitness function (win rate vs. stock BARb). That's a straightforward CMA-ES /
population-based / Bayesian-optimisation setup, no engine work at all.

Caveats: the objective is extremely noisy (BARb-vs-BARb outcomes swing on start
position and RNG), and each evaluation costs a match. Use side swapping, multiple
maps, fixed seed sets, and treat 10 games as a weak signal. Budget thousands of
matches for a real signal — at 45 s each, that's ~12 hours per thousand.

### 2. Scripted policy in AngelScript

`AiUpdate()` runs every 30 frames and is empty in every stock profile. You can
implement a state machine, a decision tree, or a learned policy *evaluated* there
— as long as inference is cheap and expressible in AngelScript. Training happens
offline; the script only executes the result.

Fits: learned build-order selection, learned aggression timing, a small tabular
or linear policy over hand-built features from `aiEconomyMgr` / `aiEnemyMgr`.

Doesn't fit: anything needing a tensor runtime.

### 3. Lua-side data extraction

Widgets and gadgets run under headless. A synced gadget can dump per-frame state
to CSV/JSON — army value, income, unit counts, map control. BAR already ships
`luaui/Widgets/dbg_unit_csv_export.lua` as a template, and there's a documented
community pattern of doing exactly this for BAR headless analysis.

This is the cheapest way to get a supervised dataset or a reward signal, and it
composes with (1) and (2). Watch out for `gl.*` calls — they misbehave headless.

### 4. External-process agent — the real thing

The sanctioned bridge is `Spring.SendSkirmishAIMessage` (Lua → AI) and the
`RecvSkirmishAIMessage` callin (AI → Lua), with `EVENT_LUA_MESSAGE` on the native
side. A C++ skirmish AI acts as the observation/action shim and IPCs to a Python
trainer.

Known blockers:

- **No step synchronisation.** The engine does not wait for an agent to decide.
  RecoilEngine [discussion #274](https://github.com/beyond-all-reason/RecoilEngine/discussions/274)
  ("SubmitTurn command for AI", open since 2022) has a contributor measuring
  ~3× speedup and ~5 ms/frame with a lockstep-submit patch — maintainers pushed
  back on merging it. Without lockstep you're doing asynchronous control, which
  most RL algorithms don't assume.
- **Action space.** BAR has hundreds of unit types and a continuous map. Anything
  resembling raw unit control is a research project. Acting at CircuitAI's task
  abstraction — choosing among the tasks it already knows how to execute — is far
  more tractable and is what layer 2 gives you for free.
- **Throughput.** 37× realtime on one core-bound process. Parallel matches need
  separate write dirs and `--only-local`, and the sim is already CPU-bound.

### 5. Imitation from human replays

`api.bar-rts.com` is public, unauthenticated and undocumented (the source is
`beyond-all-reason/bar-db`). It rate-limits, so be polite.

```bash
curl "https://api.bar-rts.com/replays?page=1&limit=100&preset=duel&hasBots=false&endedNormally=true"
curl "https://api.bar-rts.com/replays/<id>"
```

Query params (from `src/model/rest-api/replays.ts`): `page`, `limit`, `preset`
(`ffa|team|duel`), `endedNormally`, `hasBots`, `reported`, `tsRange`, `players`,
`maps`, `date`, `durationRangeMins`, `computeTotalResults` (note: `totalResults`
is `-1` unless you set this).

`/replays/:id` returns the full modoptions dict, `AllyTeams[].Players[]`,
`AllyTeams[].AIs[]`, `winningTeam`, `durationMs`, engine and game versions. **The
metadata alone is a usable tabular dataset** without downloading a single binary.

There is no download endpoint. Take `fileName` from the JSON and fetch:

```
https://storage.uk.cloud.ovh.net/v1/AUTH_10286efc0d334efd917d476d7183232e/BAR/demos/{fileName}
```

Then parse with `sdfz-demo-parser` (TypeScript, official, maintained). Also
relevant: `beyond-all-reason/data-processing` (SQL pipelines over BAR data).

Caveat: human replays teach you what humans do, and the action space you can
actually drive is CircuitAI's task layer. The mapping is not direct.

## Suggested order

1. Instrument. Add a data-dump gadget; get per-match time series out of the
   harness. Everything downstream needs this.
2. Establish a baseline. Run enough `apex` vs `stable` matches to know the noise
   floor. Without that you cannot tell improvement from variance.
3. Search the config space. Cheapest real gains, and it validates the harness.
4. Move logic into `AiUpdate` / `AiMakeTask` once you know which decisions matter.
5. Only then consider an external agent — by that point you'll know what
   observation and action spaces are worth wiring up.

Steps 1–4 need no C++ at all.
