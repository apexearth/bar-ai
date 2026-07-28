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

Per profile, in `game-side/script/<profile>/`:

```
init.as                 AiInit    — declares which JSON files to load
main.as                 AiMain    — one-time setup;  AiUpdate — every 30 frames
manager/builder.as      construction task selection
manager/economy.as      economy tick
manager/factory.as      factory choice and unit recruitment
manager/military.as     combat task selection, defence
misc/commander.as       commander behaviour
```

Shared, one level up (`script/`): `common.as`, `define.as` (constants: `SECOND`
= 30, `MINUTE`, `SQUARE_SIZE` = 8, `NEAR_ZERO`), `unit.as` (role and attribute
masks), `task.as` (task constructors).

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
- Scripts are per-profile. Changing `hard_aggressive/main.as` does not affect
  `hard`.
- There is no hot reload for AngelScript — it loads at AI init, so a new match
  is required. That's what the headless harness is for.
