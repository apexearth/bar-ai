# 09 — Resources

Verified reachable 2026-07-27 unless marked.

## The three repos that matter

| | |
|---|---|
| Game content | https://github.com/beyond-all-reason/Beyond-All-Reason |
| Engine | https://github.com/beyond-all-reason/RecoilEngine |
| The AI itself | https://github.com/rlcevg/CircuitAI — branch **`barbarian`** = BARb, `zk` = Zero-K |

## AI-specific

- **[CircuitAI `doc/Profile.md`](https://github.com/rlcevg/CircuitAI/blob/barbarian/doc/Profile.md)**
  — the only real prose doc for adding a BARb profile. Read this first.
- [CircuitAI `data/`](https://github.com/rlcevg/CircuitAI/tree/barbarian/data) —
  the shipped `AIInfo.lua`, `AIOptions.lua`, `config/`, `script/`
- [CircuitAI `src/circuit/script/`](https://github.com/rlcevg/CircuitAI/tree/barbarian/src/circuit/script) —
  the AngelScript binding surface. `InitScript.cpp` is the master file.
- [BAR game-side BARb configs](https://github.com/beyond-all-reason/Beyond-All-Reason/tree/master/luarules/configs/BARb/stable)
- [BAR `luaai.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/master/luaai.lua) ·
  [`ai_simpleai.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/master/luarules/gadgets/ai_simpleai.lua)
  — the LuaAI pattern
- [Engine AI interface headers](https://github.com/beyond-all-reason/RecoilEngine/tree/master/rts/ExternalAI/Interface) ·
  [engine AI glue](https://github.com/beyond-all-reason/RecoilEngine/tree/master/rts/ExternalAI) ·
  [`AI/Wrappers`](https://github.com/beyond-all-reason/RecoilEngine/tree/master/AI/Wrappers) ·
  [`AI/Skirmish`](https://github.com/beyond-all-reason/RecoilEngine/tree/master/AI/Skirmish) (NullAI, CppTestAI templates)
- [BAR microblog #134](https://www.beyondallreason.info/microblogs/134) — rlcevg
  announcing custom BARb profiles without editing the engine
- [Lamer — Lead BARbarian AI](https://www.beyondallreason.info/team/lamer)

## Engine docs

- https://recoilengine.org/docs/ — [Lua API](https://recoilengine.org/docs/lua-api/) ·
  [synced commands](https://recoilengine.org/docs/synced-commands/) ·
  [unsynced commands](https://recoilengine.org/docs/unsynced-commands/) ·
  [config vars](https://recoilengine.org/docs/configuration-variables/)
- [Headless and dedicated](https://recoilengine.org/docs/guides/getting-started/headless-and-dedicated/)
- [Technicalities of starting a match](https://recoilengine.org/articles/technicalities-of-starting-a-match/)
- **[`doc/StartScriptFormat.txt`](https://github.com/beyond-all-reason/RecoilEngine/blob/master/doc/StartScriptFormat.txt)**
  — authoritative start-script reference
- [`AGENTS.md`](https://github.com/beyond-all-reason/RecoilEngine/blob/master/AGENTS.md)
  — concise build/test cheat sheet
- [Changelogs](https://recoilengine.org/changelogs/) ·
  [Releases](https://github.com/beyond-all-reason/RecoilEngine/releases)

## Building

- [`docker-build-v2/README.md`](https://github.com/beyond-all-reason/RecoilEngine/blob/master/docker-build-v2/README.md)
  — the container build, including the Windows/WSL2 guidance
- [Building without Docker](https://recoilengine.org/development/building-without-docker/) ·
  [Building on MSVC (wiki)](https://github.com/beyond-all-reason/RecoilEngine/wiki/Building-on-MSVC)
- [mingwlibs64](https://github.com/beyond-all-reason/mingwlibs64) ·
  [vclibs64](https://github.com/beyond-all-reason/vclibs64)

## Tooling

- [`tools/headless_testing/`](https://github.com/beyond-all-reason/Beyond-All-Reason/tree/master/tools/headless_testing)
  — BAR's own headless harness, incl. `startscript_barb_smoke.txt` (BARb vs BARb)
- [`tools/StartScripts/`](https://github.com/beyond-all-reason/Beyond-All-Reason/tree/master/tools/StartScripts)
  — ready-made scenarios (3v3 barbs, barbs vs scavengers, FFA vs NullAI)
- [sdfz-demo-parser](https://github.com/beyond-all-reason/demo-parser) — replay
  parsing, TypeScript, maintained
- [bar_debug_launcher](https://github.com/beyond-all-reason/bar_debug_launcher) —
  GUI for engine/game/map/modoption selection; also ships `parse_demo_file.py`
- [recoil-lua-library](https://github.com/beyond-all-reason/recoil-lua-library) —
  LuaLS type definitions. Worth wiring into your editor for Lua work.
- [pr-downloader](https://github.com/beyond-all-reason/pr-downloader) ·
  [BAR-Devtools](https://github.com/beyond-all-reason/BAR-Devtools) ·
  [recoil-autohost](https://github.com/beyond-all-reason/recoil-autohost)

`pr-downloader` ships in every engine dir:

```powershell
& "$ENG\pr-downloader.exe" --filesystem-writepath "$BAR" --download-map "Supreme Isthmus v2.1"
& "$ENG\pr-downloader.exe" --filesystem-writepath "$BAR" --download-game "byar:test"
```

Rapid tags are only `byar:stable`, `byar:test`, and `byar:git:<sha>`.
Env: `PRD_HTTP_SEARCH_URL=https://files-cdn.beyondallreason.dev/find`,
`PRD_RAPID_REPO_MASTER=https://repos-cdn.beyondallreason.dev/repos.gz`.

## Data

- **`https://api.bar-rts.com`** — public, unauthenticated, undocumented,
  rate-limited (be polite). Source of truth is
  [bar-db](https://github.com/beyond-all-reason/bar-db) (`src/rest-api/routes/`).
  `GET /replays` takes `page`, `limit`, `preset` (`ffa|team|duel`),
  `endedNormally`, `hasBots`, `reported`, `tsRange`, `players`, `maps`, `date`,
  `durationRangeMins`, `computeTotalResults` (`totalResults` is `-1` unless you
  set this). `GET /replays/:id` returns the modoptions dict,
  `AllyTeams[].Players[]`, `AllyTeams[].AIs[]`, `winningTeam`, `durationMs` and
  the engine/game versions — usable as a tabular dataset without downloading a
  single replay blob. There is no download endpoint: take `fileName` from the
  JSON and fetch it from the storage URL below, then parse with
  [sdfz-demo-parser](https://github.com/beyond-all-reason/demo-parser).
- [data-processing](https://github.com/beyond-all-reason/data-processing) — SQL
  pipelines over BAR data
- Replay blobs: `https://storage.uk.cloud.ovh.net/v1/AUTH_10286efc0d334efd917d476d7183232e/BAR/demos/{fileName}`

## Community

- **[BAR Discord](https://discord.gg/beyond-all-reason)** — the primary dev hub.
  Self-assign the "Development" role to see the dev channels. There is no
  dedicated AI community; AI talk happens in the general dev channels.
- [Recoil Discord](https://discord.gg/GUpRg6Wz3e)
- [Infrastructure overview](https://beyond-all-reason.github.io/infrastructure/)
- Issues: [game](https://github.com/beyond-all-reason/Beyond-All-Reason/issues) ·
  [engine](https://github.com/beyond-all-reason/RecoilEngine/issues)

## Contributing

- [CONTRIBUTING.md](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/master/CONTRIBUTING.md)
- **[AI_POLICY.md](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/master/AI_POLICY.md)**
  — about LLM-assisted contributions, not game AI. Requires explicit disclosure
  in the PR and human verification; undisclosed use gets the PR closed. Relevant
  to anything produced in this repo with Claude.

## Treat with caution

- **[DeepWiki's BAR AI page](https://deepwiki.com/beyond-all-reason/Beyond-All-Reason/8-ai-system)**
  — useful for navigating the codebase, but **wrong about BARb**: it claims BARb
  is a "Shard AI variant". It is CircuitAI. Shard is a different, older Lua
  framework.
- **springrts.com wiki and forums** (`AI:Development`, `AI:Skirmish`, `Script.txt`)
  — pre-fork, ~2015, Java-oriented, and currently behind an anti-bot wall.
  Archaeology only.
- **Legacy Spring AIs** — AAI, KAIK, E323AI, GAI, Shard. None build on Recoil.
- **BYAR-Chobby / spring-launcher** — maintenance mode; `bar-lobby` is the
  successor but not yet default.
- The `Quit` unsynced command is deprecated; use `QuitForce`.
- `beyond-all-reason.github.io/spring/development/build-with-docker` — 404, still
  surfaced by search engines. The docs moved to recoilengine.org.
