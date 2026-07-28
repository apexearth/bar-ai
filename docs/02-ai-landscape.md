# 02 — The AI landscape in BAR

Four ways to put an AI into BAR. Two are live and worth using, one is a
different tool than it looks like, one is dead.

## 1. Native skirmish AI (C interface) — the real path

The engine loads an **AI Interface** library, which loads your **Skirmish AI**
library. Recoil ships exactly one interface: `C`.

```
engine/<ver>/AI/Interfaces/C/0.1/AIInterface.dll
engine/<ver>/AI/Skirmish/<ShortName>/<Version>/
    AIInfo.lua  AIOptions.lua  SkirmishAI.dll  [config/ script/]
```

On Windows the file is `SkirmishAI.dll` — the `lib` prefix is Linux-only.

`AIInfo.lua` is how the engine discovers the AI. The directory name must equal
`shortName`, and the subdirectory name must equal `version`:

```lua
{ key='shortName',          value='BARb'   },
{ key='version',            value='stable' },
{ key='name',               value='BARbarIAn' },
{ key='interfaceShortName', value='C'      },
{ key='interfaceVersion',   value='0.1'    },
```

`AILibraryManager` scans `AI/Skirmish/*/*/AIInfo.lua` across **all** data dirs,
so adding a folder is all it takes to get a new entry in the lobby.

Your DLL must export `handleEvent(skirmishAIId, topicId, void* data)`; `init` and
`release` are optional. Headers live in
[`rts/ExternalAI/Interface/`](https://github.com/beyond-all-reason/RecoilEngine/tree/master/rts/ExternalAI/Interface):
`SSkirmishAILibrary.h` (exports), `SSkirmishAICallback.h` (a flat struct of ~596
function pointers, engine→AI), `AISCommands.h` (AI→engine), `AISEvents.h` (28
`EVENT_*` topics, one struct each — there is no single `SSkirmishAIEvent` type;
you switch on `topicId` and cast).

Most AIs don't use the C API directly. `AI/Wrappers/Cpp` is an OO C++ wrapper
**generated at build time** by awk scripts from those headers, producing
`OOAICallback`, `Unit`, `UnitDef`, `Economy`, `Game`, `Map`, `Pathing` and ~40
more in namespace `springai`. Because it's generated, you can't read it in the
repo — you have to configure a build and look in
`<build>/AI/Wrappers/Cpp/src-generated/`.

`AI/Wrappers/LegacyCpp` (`springLegacyAI::IGlobalAI`) is the old Spring
interface. Nothing in BAR uses it. Historical.

Minimal templates in the engine tree: `AI/Skirmish/NullAI` (pure C, ~9-line
CMakeLists) and `AI/Skirmish/CppTestAI` (C++ wrapper). Note official builds pass
`-DAI_EXCLUDE_REGEX="^CppTestAI$"`, so CppTestAI is less exercised.

## 2. BARb / CircuitAI — what actually ships

**BARb is CircuitAI.** `rlcevg/CircuitAI` branch `barbarian`, pulled into
RecoilEngine as a submodule:

```
[submodule "AI/Skirmish/BARb"]      url = .../rlcevg/CircuitAI.git   branch = barbarian
[submodule "AI/Skirmish/CircuitAI"] url = .../rlcevg/CircuitAI.git   branch = zk
```

There is no `beyond-all-reason` fork. The same repo's `zk` branch is the Zero-K
build. It's a very live project — the `barbarian` branch had commits the day this
was written, many of them adding AngelScript bindings.

It is still BAR's default AI: Chobby's `aiSimpleName.lua` lists `BARb stable`
first with the tooltip *"The recommended excellent performance, adjustable
difficulty"*.

Its behaviour is driven by JSON + AngelScript loaded from the **game archive**,
which is why layers 1 and 2 need no compiler. See
[03 — BARb architecture](03-barb-architecture.md).

Two claims you'll find online are wrong: BARb is **not** built on the Shard
framework (DeepWiki says so; it isn't), and it does not have 8 difficulty levels
(Chobby ships 5 profiles).

## 3. LuaAI — your own architecture, no compiler

Add an entry to `luaai.lua` at the game archive root:

```lua
return {
  { name = 'SimpleAI',    desc = 'EasyAI' },
  { name = 'RaptorsAI',   desc = 'Raptor Defence' },
}
```

`LuaAIImplHandler` registers each as a skirmish AI. There is no AI-specific
interface — you write an ordinary **synced LuaRules gadget** that gates itself on
`Spring.GetTeamLuaAI(teamID)`. From `luarules/gadgets/ai_simpleai.lua`:

```lua
local luaAI = Spring.GetTeamLuaAI(teamID)
if luaAI and luaAI ~= "" and string.sub(luaAI, 1, 8) == 'SimpleAI' then
    enabled = true
end
...
function gadget:GetInfo() return { name = "SimpleAI", enabled = enabled } end
```

Selected per-team in the start script with `LuaAI=SimpleAI;` inside `[TEAM0]`,
not via an `[AI0]` section.

Trade-offs: no build step, hot-reloadable with `/luarules reload`, full
`Spring.*` API — but it runs on the sim thread (a hard performance ceiling
compared to BARb's threading) and it lives in the game archive, so multiplayer
requires everyone to have it.

**ScavengersAI and RaptorsAI are not AIs** in this sense — they're PvE spawner
gadgets that occupy a lobby slot. Don't use them as a template; use
`ai_simpleai.lua`.

**STAI and Shard** (Lua, by pandaro) are gone from BAR master. The local
`BAR.sdd/luaai.lua` still lists them only because the checkout is stale.

## 4. Dead ends

- **Java interface** — removed in Recoil. `AI/Interfaces/` contains only `C`;
  `AI/Wrappers/` has no Java wrapper. It survives in upstream `spring/spring`.
- **Python interface** — explicitly disabled in `AI/Interfaces/CMakeLists.txt`
  ("not yet compatible with pureint changes") and absent from the tree.
- **Legacy Spring AIs** (AAI, KAIK, E323AI, GAI, Shard) — none build on Recoil.

## The Lua ↔ native bridge

`Spring.SendSkirmishAIMessage` (Lua → AI) and the `RecvSkirmishAIMessage` callin
(AI → Lua), with `EVENT_LUA_MESSAGE` on the native side. This is the sanctioned
channel between a native AI and game Lua, and the natural foundation for any
external-process AI. Also `VFS.GetAvailableAIs()`, which gained an `isLuaAI`
field in the 2026.06 line.

## Choosing

| Goal | Path |
|---|---|
| Tune how BARb plays | JSON config |
| Change what BARb decides | AngelScript |
| New mechanism inside BARb | C++ |
| Your own AI architecture, quickly | LuaAI gadget |
| Learned policy / external process | C++ shim + `SendSkirmishAIMessage` — nothing off-the-shelf exists |
