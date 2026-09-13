# 05 — The AngelScript layer

This is the highest leverage-to-effort layer in BARb. It is real decision logic —
task selection, defence placement, factory choice — running inside the AI, with
no compiler in the loop. Edit a `.as` file, redeploy, restart the match.

Everything here was read from the shipped `stable` scripts in
`reference/barb-stable/`. The binding surface is defined in CircuitAI's
`src/circuit/script/` (~405 `Register*` calls, `InitScript.cpp` alone has 274)
and is **actively growing** — recent upstream commits add
`aiFactoryMgr.SetImportance`, military-response bindings, Tracy bindings. If
something you want isn't exposed, check `barbarian` HEAD before assuming.

## File layout

Per profile, in `game-side/script/<profile>/` — the live variant's profile is
`standard`:

```
init.as                 AiInit    — declares which JSON files to load
main.as                 AiMain    — one-time setup;  AiUpdate — every 30 frames
policy.as targets.as tunables.as perf.as
manager/air.as          air factory, air lead election, wings
manager/baseplan.as     where buildings go — grid, walkways, reserved spots
manager/brain.as        the Want market: every build and production decision
manager/builder.as      construction task selection (holds -> Decide -> idle)
manager/catalog.as      per-def economics and the who-builds-what graph
manager/economy.as      economy tick
manager/factory.as      factory senses; the facqueue executes production
manager/frontline.as    influence map, territory, front/back line
manager/lattice.as      the base lattice
manager/military.as     combat task selection, defence
manager/persona.as manager/role.as
misc/commander.as       commander behaviour
```

Stock ships only `builder`/`economy`/`factory`/`military`; the rest are ours.

**Every `manager/<name>.as` above is a shim** — a table of contents that
`#include`s the real code from a sibling `manager/<name>/` directory. There are
106 `.as` files under `script/standard/` (2026-08-30). Edit the parts, not the
shim, except to add a part (which means adding a line to the shim).

**The include order in a shim is load-bearing, but narrowly.** `CScriptBuilder`
adds a section before walking that section's own includes, depth-first in listed
order, so the shim's list is the order the compiler sees declarations in.

What actually breaks is only a **global's INITIALIZER expression** reading a
symbol declared in a later file. AngelScript registers every type and global
across all sections before compiling any function, so functions, parameter types
and ordinary reads inside function bodies are order-independent — this tree
proves it and runs (`market/want_super.as` reads `Base::gAnchor` from a namespace
included four lines later).

An earlier checker that enforced the stricter "every global must be declared
before the line that reads it" rule produced 250 false positives here. `python
tools/as_scope.py` reproduces the real walk and reports the two failures that do
bite: a global initializer reading a later symbol, and a local read outside its
declaring block.

Both `AiMakeTask`s are **rule pipelines**: `builder/maketask.as` and
`factory/maketask.as` are short ordered lists of named rules that live in the
sibling `rules_*.as` files. A rule returns null to pass. Where a new rule goes
in that list is the design decision — see the 2026-08-01 composition finding in
`docs/25-silent-failures.md`.

Shared, one level up (`script/`): `common.as`, `define.as` (constants: `SECOND`
= 30, `MINUTE`, `SQUARE_SIZE` = 8, `NEAR_ZERO`), `unit.as` (role and attribute
masks), `task.as` (task constructors), `side.as` (`SideDef3`/`SideName3`, the
Armada/Cortex/Legion faction dispatch), `world.as` (`OnMap` and other position
guards).

`#include` is relative to the including file.

## Hooks

Every hook has a default; the shipped scripts mostly call straight through to the
C++ default and exist as extension points.

| Hook | File | Purpose |
|---|---|---|
| `SInitInfo AiInit()` | `init.as` | which JSON parts to load, armor/category tables |
| `void AiMain()` | `main.as` | one-time setup after defs are known |
| `void AiUpdate()` | `main.as` | **every 30 frames** — free periodic hook, empty in all stock profiles |
| `IUnitTask@ AiMakeTask(CCircuitUnit@)` | builder / factory / military | **the core decision**: what should this unit do next |
| `void AiTaskAdded(IUnitTask@)` / `AiTaskRemoved(IUnitTask@, bool done)` | all managers | task lifecycle |
| `void AiUnitAdded(CCircuitUnit@, Unit::UseAs)` / `AiUnitRemoved(...)` | all managers | unit lifecycle |
| `void AiMakeDefence(int cluster, const AIFloat3& in pos)` | military | static defence placement |
| `bool AiIsAirValid()` | military | gate air production |
| `void AiUpdateEconomy()` | economy | economy tick |
| `bool AiIsSwitchTime(int lastSwitchFrame)` | factory | may we switch factory now |
| `bool AiIsSwitchAllowed(CCircuitDef@ facDef)` | factory | may we switch *to this* factory |
| `CCircuitDef@ AiGetFactoryToBuild(const AIFloat3& in pos, bool isStart, bool isReset)` | factory | **which factory to build** |
| `void AiLoad(IStream&)` / `AiSave(OStream&)` | all managers | save/load state |

## Globals

| Object | What it is |
|---|---|
| `ai` | root: `GetDefCount()`, `GetCircuitDef(id\|name)`, `frame` |
| `aiEconomyMgr` | `metal.income`, `energy`, `GetEnergyMake(def)`, `reclConvertEff` |
| `aiMilitaryMgr` | `DefaultMakeTask(unit)`, `DefaultMakeDefence(cluster, pos)` |
| `aiBuilderMgr` | builder task defaults |
| `aiFactoryMgr` | factory selection, `SetImportance` / `GetImportance` |
| `aiEnemyMgr` | `mobileThreat`, `GetEnemyThreat(roleType)` |
| `aiTerrainMgr` | `SetAllyZoneRange(n)`, terrain queries |
| `aiSetupMgr` | `GetModOptions()` — read the game's modoptions |
| `aiRoleMasker` / `aiAttrMasker` / `aiSideMasker` | `GetTypeMask(name)`; `AiAddRole(name, base)` |

Types: `CCircuitDef@`, `CCircuitUnit@`, `IUnitTask@`, `AIFloat3`, `TypeMask`,
`Id`, plus AngelScript's `array<T>` and `dictionary` add-ons. `AiLog(string)`
writes to the infolog prefixed with the AI name.

`CCircuitUnit::GetFacing()` (2026-09-12) returns the engine's building facing
(0 south +z, 1 east +x, 2 north -z, 3 west -x; -1 dead). Spring's "front" is
NOT every plant's exit: measure it (`Brain::ExitSign`) before acting on it.

## Roles and attributes

`unit.as` builds the mask tables. Engine-side roles: `builder`, `scout`,
`raider`, `riot`, `assault`, `skirmish`, `artillery`, `anti_air`, `anti_sub`,
`anti_heavy`, `bomber`, `support`, `mine`, `transport`, `air`, `sub`, `static`,
`heavy`, `super`, `commander`.

**You can define your own roles from script** — BARb already does:

```angelscript
TypeMask ROLE0    = AiAddRole("cloaked_raider",  ASSAULT.type);
TypeMask REZZER   = AiAddRole("rezzer",          SUPPORT.type);
TypeMask BUILDER2 = AiAddRole("builderT2",       BUILDER.type);
```

Each takes a base role to inherit behaviour from. Once declared, the name is
usable in `behaviour.json`'s `role` lists. This is a genuine extension point: new
unit categories with distinct handling, no C++.

## Tasks

`task.as` provides constructors in three namespaces, all returning task
descriptors you hand back from `AiMakeTask`:

- `TaskB::` — builder tasks: `Common`, `Spot`, `Factory`, `Pylon`, `Repair`,
  `Reclaim`, `Resurrect`, `Terraform`, `Patrol`, `Guard`, `Combat`, `Wait`
- `TaskS::` — factory/static: `Recruit`, `Repair`, `Reclaim`, `Patrol`, `Wait`
- `TaskF::` — fight: `Common`, `Guard`, `Defend`

Each takes a `Task::Priority` and type-specific arguments.

## init.as — conditional config loading

Worth reading in full; it shows how config composition is driven from script and
how to reach modoptions:

```angelscript
SInitInfo AiInit() {
    AiLog("hard AngelScript Rules!");
    SInitInfo data;
    data.armor    = InitArmordef();
    data.category = InitCategories();
    @data.profile = @(array<string> = {"behaviour", "block_map", "build_chain",
                                       "commander", "economy", "factory", "response"});
    if (string(aiSetupMgr.GetModOptions()["experimentallegionfaction"]) == "1") {
        Side::LEGION = aiSideMasker.GetTypeMask("legion");
        data.profile.insertAt(data.profile.length(),
            {"behaviour_leg", "build_chain_leg", "commander_leg", "economy_leg", "factory_leg"});
    }
    ...
    return data;
}
```

`data.profile` is the list of JSON basenames to load. Adding your own config file
means adding its name here.

## main.as — the setup pattern

```angelscript
void AiMain() {
    for (Id defId = 1, count = ai.GetDefCount(); defId <= count; ++defId) {
        CCircuitDef@ cdef = ai.GetCircuitDef(defId);
        if (cdef.costM >= 200.f && !cdef.IsMobile() && aiEconomyMgr.GetEnergyMake(cdef) > 1.f)
            cdef.AddAttribute(Unit::Attr::BASE.type);   // build heavy energy at base
    }

    array<string> names = {Factory::armalab, Factory::coralab, ...};
    for (uint i = 0; i < names.length(); ++i) {
        CCircuitDef@ cdef = ai.GetCircuitDef(names[i]);
        if (cdef !is null)
            Factory::userData[cdef.id].attr |= Factory::Attr::T2;
    }
}
```

Iterate all unit defs, classify by cost/mobility/output, attach attributes. This
is where rule-based classification belongs — it runs once and the results feed
everything downstream.

The commented-out block in the stock file shows the tuning knobs reachable here:
`aiTerrainMgr.SetAllyZoneRange(600)`, `aiEconomyMgr.reclConvertEff`,
`cdef.SetThreatKernel(...)`, and per-def `threat` / `power` inspection.

## military.as — overriding a real decision

```angelscript
void AiMakeDefence(int cluster, const AIFloat3& in pos) {
    if ((ai.frame > 5 * MINUTE)
        || (aiEconomyMgr.metal.income > 10.f)
        || (aiEnemyMgr.mobileThreat > 0.f))
    {
        aiMilitaryMgr.DefaultMakeDefence(cluster, pos);
    }
}
```

Suppress early defence spending until one of three conditions holds. The same
shape works for `AiMakeTask`: inspect state, sometimes return your own task,
otherwise `return aiMilitaryMgr.DefaultMakeTask(unit);`.

## Where to start

1. **`AiUpdate()`** — empty in every stock profile, runs every 30 frames. Log
   state, then act on it. Zero risk of breaking existing behaviour.
2. **`AiMakeDefence`** — small, self-contained, visibly affects play.
3. **`AiGetFactoryToBuild`** — opening build order, high impact on outcomes.
4. **`AiMakeTask`** in military — the deepest hook; overriding task selection is
   effectively rewriting the AI's mind while keeping its body.

## Practical notes

- Compile errors surface in the infolog at AI init, prefixed with the AI name.
  Grep `matches/<run>/infolog.txt` for your AI's name after a headless run — it's
  faster than launching the client.
- `ai.frame` is in sim frames; `SECOND` = 30, `MINUTE` = 1800.
- `@` is AngelScript's handle syntax; `!is null` is the null test.
- Scripts are per-profile. Changing `standard/main.as` does not affect any
  other profile.
- There is no hot reload for AngelScript — it loads at AI init, so a new match
  is required. That's what the headless harness is for.

## Hard-won limits of the script layer

Found by running it, not by reading docs. All verified against
`vendor/circuitai/src/circuit/script/` (clone with
`python tools/bootstrap_sources.py circuitai`).

**`aiMilitaryMgr` exposes much more than the shipped scripts use**
(`MilitaryScript.cpp`):

```
IUnitTask@+ DefaultMakeTask(CCircuitUnit@)
IUnitTask@+ Enqueue(const SFightTask& in)
IUnitTask@+ EnqueueRetreat()
void        DefaultMakeDefence(int, const AIFloat3& in)
uint        GetGuardTaskNum() const
uint        ReleaseHoldPools()      // every DEFEND pool promoting to MELEE now promotes to ATTACK (ours, 2026-09-13)
const float armyCost
SQuotaMilitary quota { uint scout; float attack; SRaidQuota raid{min,avg}; }
SResponseInfo@ GetResponseInfo(Type)   // { float maxPercent; float factor; }
```

`quota.scout` and `quota.attack` are **writable at runtime**, which is what
makes dynamic behaviour possible without touching JSON. `quota.scout` maps to
`maxScouts`, `quota.attack` to `minAttackers`.

**Three things that do not work:**

1. **`Enqueue(TaskF::Common(Task::FightType::ATTACK))` crashes the AI.** It
   faulted inside `SkirmishAI.dll` ~3 sim frames after firing, in 4 of 12
   matches. `CMilitaryManager::Enqueue` builds `new CAttackTask(this,
   minAttackers, ...)`, and the manager already creates attack tasks itself
   against that same threshold — so enqueueing one by hand is both redundant and
   unsafe. **Change `quota.attack` instead** and let the manager form the task.
2. **`SResponseInfo` is not a visible data type inside `main.as`.** The
   managers are `#include`d into main's module, but each manager registers its
   types against its own module namespace, so the type resolves in
   `military.as` and not in `main.as`. The global *property* `aiMilitaryMgr`
   does resolve there — only the type name fails. Tune anti-air in
   `response.json` unless you move the code into `military.as`.
3. **There is no per-UNIT enemy enumeration** — but there is a per-GROUP one,
   added by this repo's DLL. `aiEnemyMgr` exposes `GetEnemyGroupCount`,
   `GetEnemyGroupPos`, `GetEnemyGroupCost`, `GetEnemyGroupRange`,
   `GetEnemyCost`, `GetEnemyCostFresh`, `GetEnemyPos` and `mobileThreat`, which
   is what the nuke director's target ranking and the territory model are built
   on. There is still no unit list and no commander handle, so
   "scout, find the enemy commander, snipe it" is not writable in AngelScript.

   Two things to know about the group data: it is **LOS-slaved** (only units
   currently in LOS are kept), and `GetEnemyPos()` returns ZeroVector while no
   enemy group is known — never use it as a bearing pre-contact.

   The escape hatch for anything else: `ai.CallRules(string)`, `ai.CallUI(string)`
   and `ai.GetGameRulesParam(...)` are exposed, so a game-side LuaRules gadget
   could compute a target and hand it back through a rules param. That only works
   in a game archive you control.

**Debugging loop.** A script that fails to compile logs
`Script: Fix compilation errors!` and the AI then dies on its INIT event, which
looks like an instant loss (~200 frames). The real error is a few lines above:

```
main.as (95, 2) : ERR : Identifier 'SResponseInfo' is not a data type
```

So after any script change, run one short headless match and grep the infolog
for `Fix compilation errors` before trusting a tournament result.
