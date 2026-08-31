# 13 — Other people's BAR AIs: Felnious/Skirmish

> Narrow survey of two AIs. The wider community picture is
> [14 — The wider BAR AI landscape](14-bar-ai-landscape.md); read that first if
> you want "who is building what".

Read 2026-08-08 against commit `d765a46` of
<https://github.com/Felnious/Skirmish> (a full clone was taken; every quote
below is from a file in that tree, cited by path and line where it matters).
This is one of the more widely used alternatives to the shipped AI.

Everything here describes **their** code. Where I could not verify something I
say so; absence of a thing in their tree is reported as "I did not find it",
not as "it does not exist".

## 1. What kind of AI it is

**It is the same AI we are working on.** Not a Lua AI, not a native AI of its
own, not a fork of CircuitAI's C++. It is BARb/CircuitAI driven from layers 1
and 2 — JSON config and AngelScript — exactly the two layers `CLAUDE.md`
describes, laid out in exactly the same directory shape:

```
<shortName>/<version>/AIInfo.lua  AIOptions.lua  SkirmishAI.dll  config/  script/
```

The repo is nine of those folders side by side, i.e. it is a distribution of
*engine-side* AI directories that the user unzips into
`data/engine/$VERSION/AI/Skirmish` (the README's install instruction, verbatim).

Evidence there is no C++ layer: I byte-scanned their bundled `SkirmishAI.dll`s
for the binding names their own scripts call (`SetFireState`,
`SetAllyZoneRange`, `GetSideName`, `GetGameRulesParam`, `GetTeamRulesParam`) and
compared against the two BARb DLLs installed on this machine
(`recoil_2026.06.12`, `recoil_2026.07.04`). Every one of those names is present
in stock. Their DLLs are 6.60–6.61 MB against stock's 6.96 MB — i.e. **older
stock builds**, not custom ones. Seven of their nine folders ship a
byte-identical DLL (md5 `b45ead06…`).

That bundling is a real fragility and we do the opposite: `deploy_ai.py` derives
the engine-side folder from the engine's own `BARb/stable` on every run, so our
variant survives a BAR engine update. Theirs ships a frozen DLL that the user
copies into whatever engine directory exists today.

### The nine folders, and the shortName question

| Folder | shortName / version | What it is |
|---|---|---|
| `Barb3/stable` | `Barb3` / `stable` | The current work. "Barb2.0 PreAlpha Public Test" (commit `77ee4cb`). ~14,000 lines of AngelScript. |
| `Main/stable` | `Main` / `stable` | Config-only variant, stock-shaped scripts. |
| `Night/mare` | `Night` / `mare` | Four *playstyle* profiles: `Nightmare`, `Nuclear`, `Aircraft`, `Sea`. Config-only. |
| `Sweet/mare` | `Sweet` / `mare` | `hard` + `dev` profiles. Config-only. |
| `BARb/stable` | **`BARb`** / `stable` | A drop-in **replacement for the stock AI's own folder**. |
| 4 × `*-Deprecated` | — | Marked deprecated in the tree. |

They independently arrived at the shortName rule from `CLAUDE.md`'s "three
axes": their live variants use distinct shortNames (`Barb3`, `Main`, `Night`,
`Sweet`), which is what survives the lobby's `ADDBOT`. But `BARb/stable`
overwrites the stock AI's directory in place — a different distribution strategy
with a different failure mode (it changes what everyone's "BARb stable" does,
and an engine update silently reverts it).

Their `Barb3/stable/AIOptions.lua` declares six profiles, all named for a
resource-bonus setting: `experimental_balanced` (default),
`experimental_ThirtyBonus`, `_FiftyBonus`, `_EightyBonus`, `_HundredBonus`,
`experimental_Suicidal`. The six `config/experimental_*/` trees are near
byte-identical to each other (e.g. `ArmadaBehaviour.json` is 44,570 bytes in
five of six), and all six `script/experimental_*/main.as` are byte-identical at
5,595 bytes. **Whatever distinguishes a bonus profile, I could not find it in
the diffable content** — the difference is at most a few bytes per file. This
matters to us because `CLAUDE.md` records that we deleted the stock four-profile
tree for exactly this reason: duplicated profiles that carry none of the work.

## 2. The decision model

Stock BARb is a task/manager model: managers ask `DefaultMakeTask` /
`DefaultGetFactoryToBuild` / `DefaultMakeDefence`, and the game-side script may
override. `Barb3` keeps that spine and inserts **one big dispatch layer** in
front of it.

**Role-based delegation.** `types/role_config.as` defines a `RoleConfig` holding
~20 function-pointer slots (`AiMakeTaskDelegate`, `AiMakeDefence`,
`SelectFactoryDelegate`, `EconomyUpdateDelegate`, `AiIsSwitchAllowedDelegate`,
per-manager `UnitAdded`/`TaskAdded` hooks…). Every manager in
`manager/*.as` is a ~100-line shim that looks up
`Global::profileController.RoleCfg` and either calls that role's handler or
falls through to the CircuitAI default. All the actual logic lives in
`roles/{front,front_tech,tech,air,sea,hover_sea}.as` — 1,456 lines for TECH
alone.

**Role comes from map geography, hand-authored.** This is the design's centre of
gravity and the thing that most differs from us. `types/ai_role.as`:

```
FRONT, AIR, TECH, SEA, FRONT_TECH, HOVER_SEA
```

`maps/*.as` are data-only files listing every start position on that map with
the role the author thinks that position should play. From
`maps/glacial_gap.as`:

```angelscript
StartSpot(AIFloat3(  490, 0,  1140), AiRole::TECH,  false),
StartSpot(AIFloat3( 1800, 0,  1400), AiRole::FRONT, false),
...
StartSpot(AIFloat3(  880, 0,  6850), AiRole::HOVER_SEA, false),
```

At the first factory call, `Setup::setupMap` (in `setup.as`) matches the map by
name prefix, finds the nearest listed start spot to the AI's actual position,
and adopts that spot's role. Eighteen maps are registered in `maps.as`
(Supreme Isthmus, Glacial Gap, Eight Horses, Tempest, Mediterraneum,
Ancient Bastion Remake, …). Off those maps it falls back to
`RoleHelpers::DefaultRoleForFactory` on whatever factory CircuitAI would have
picked.

Setup is deliberately **deferred**: nothing resolves until the engine asks for a
real build position (`Barb3/README.md`, "High-Level Flow", and the
`if (isStart && !Global::Map::MapResolved)` guard in `setup.as`).

**Per-map, per-role unit caps.** `MapConfig` carries `UnitLimits` and
`RoleUnitLimitOverlays`; Glacial Gap's `HOVER_SEA` role sets
`armvp/corvp/legvp = 0`, and the map itself sets `armthor = 0`.
`LimitsHelpers::ComputeAndStoreMergedUnitLimits` merges map + role and applies
them at start.

**Openers are weighted queues, not a single order.** `types/opener.as` maps each
factory to a list of `SQueue(weight, orders)` and rolls `AiDice`. `armlab` gets
0.9 `BUILDER, SCOUT, RAIDER, BUILDER, RAIDER×4` / 0.1 a riot-first variant.

**Strategies are a bitmask rolled at game start.** `types/strategy.as` defines
`T2_RUSH`, `T3_RUSH`, `NUKE_RUSH`; `script/experimental_balanced/main.as` rolls
each independently — 0.85 / 0.35 / 0.25 — into `RoleSettings::Tech::StrategyMask`.
So a TECH player is, per game, some subset of those three.

**A "strategic objective" system** (`types/strategic_objectives.as`,
`manager/objective_manager.as`, `helpers/objective_helpers.as`,
`helpers/objective_executor.as` — ~800 lines together) lets a map declare
"at this coordinate, build 3× light AA, then a radar, then a jammer", gated by
role, faction, constructor class, tier, income and distance from base, and
assigned to one of three builder groups (`PRIMARY`/`SECONDARY`/`TACTICAL`).

**But it is wired to one role on one map.** `ObjectiveExecutor::ExecuteNextChainStep`
is called from exactly one place, `roles/hover_sea.as:459`; the other five roles
only call `ObjectiveHelpers::LogAllObjectivesFromStart`. And
`grep -rl AddObjective maps/` returns only `maps/supreme_isthmus.as`. I did not
find objectives defined for any other map or executed by any other role in this
commit. Treat this as an unfinished mechanism, not a shipped one.

**Constructor identity model.** `manager/builder.as` (2,859 lines) keeps named
handles for a fixed cast: `primary`/`secondary` × T1/T2 × Bot/Veh/Air/Sea/Hover,
plus `freelanceT2*` and `tactical*` constructors, each with a `guards`
dictionary and a weighted guard-distribution routine (`helpers/guard_helpers.as`,
`BuilderMaxGuardsPerLeader`). Role handlers dispatch on *which* named
constructor is asking. That is a different shape from ours, where builder logic
keys off unit properties rather than identity.

## 3. The author's viewpoint

The README is the clearest statement of it:

> "Hello, I am the AI Developer (Balancer / Maintainer) for Beyond All Reason.
> This Ai has been worked on for the past 1600+ Hours it is not finished."

with a per-faction completion table — "Armada: 90% Coded, Cortex: 90%,
Legion: 60%" — and a checklist of *unit-coverage* items: "Air // Done",
"Walls // Done", "Jammers // Done", "Missing Sea/Navy Structures and Units //
Done", "Ismus Lighting Turret on Geo NSea".

That is the theory of the game the code encodes, and it is genuinely different
from ours:

- **The problem is coverage, not efficiency.** Progress is measured as "which
  of BAR's units and structures does the AI know how to use", faction by
  faction. Ours is measured in metal produced and composition. Both are
  defensible; they explain the shapes of the two codebases. `unit_helpers.as` is
  1,827 lines and is mostly hand-maintained lists of unit names per faction per
  tier per role.
- **A game is a team game with assigned jobs.** The whole role system exists
  because the author believes position 3 on Supreme Isthmus should play air and
  position 8 should play sea — and that this is knowable in advance, per map,
  by a human. There is no attempt to *infer* it from terrain; `helpers/terrain_helpers.as`
  is a 0-byte file.
- **Maps are specific, and specificity is worth hand-authoring.** Eighteen map
  files, coordinates typed in by hand, a `// TODO precise` on several.
- **Economy is expressed as income thresholds**, per role, in one place. See
  below — this is where they and we agree most.
- **Playstyle is a user choice.** `Night/mare` ships `Nuclear`, `Aircraft`,
  `Sea` and `Nightmare` as lobby-selectable profiles. The author's product is a
  menu of characters, not one AI that adapts.

Tone note for calibration: the README also says "Do not be toxic about the bot!
Only Helpful Comments will be welcomed!" This is a hobby project maintained
under public scrutiny, and the code shows it — large commented-out blocks,
`FIXME: Remove/replace, deprecated`, and stub files. Judge the ideas, not the
finish.

## 4. Head-to-head on the problems we are stuck on

### Economy: when to expand, when to upgrade mexes

They do not decide either. **Mex placement and mex upgrades are left entirely to
CircuitAI's `DefaultMakeTask`.** What they added is a *guard so their own rules
cannot displace it* — the same early-return appears in five role files:

`roles/front.as:298-304` (and `front_tech.as:167`, `tech.as:786`, `sea.as:359`,
plus hover_sea):

```angelscript
if (defaultTask !is null && defaultTask.GetType() == Task::Type::BUILDER) {
    Task::BuildType dbt = Task::BuildType(defaultTask.GetBuildType());
    if (dbt == Task::BuildType::MEX || dbt == Task::BuildType::MEXUP ||
        dbt == Task::BuildType::GEO || dbt == Task::BuildType::GEOUP) {
        return defaultTask;   // never override expansion
    }
}
```

This is worth reading next to the "The path fires" section of `CLAUDE.md`: our
recorded 4.3× collapse in metal production came from twelve rules that all ran
*ahead* of `DefaultMakeTask`, where mex upgrades live, so mex upgrades fell from
11 to 2. They have a one-line structural answer to precisely that failure mode.
Whether it is *why* they hold economy I have not measured — I ran no matches.

Everything else economic is an **income threshold**, and only an income
threshold — `global.as` is a 696-line namespace of them, scoped per role. A
sample (`Global::RoleSettings::Tech`):

```
MinimumMetalIncomeForT2Lab      18      MinimumEnergyIncomeForT2Lab      600
MinimumMetalIncomeForFUS        20      MinimumEnergyIncomeForFUS        700
MinimumMetalIncomeForAFUS       70      MinimumEnergyIncomeForAFUS      2000
MetalIncomePerGantry           250      EnergyIncomePerGantry           6000
MetalIncomePerT2Lab            100      EnergyIncomePerT2Lab            1000
MinimumMetalIncomeForNukeRush   50      MinimumEnergyIncomeForNukeRush  2000
MetalIncomePerAntiNuke          80
```

Note `MetalIncomePerGantry = 250`. `CLAUDE.md` carried a matching "above ~250
m/s the affordability argument inverts" note until 2026-08-31, when it was
deleted as a threshold masquerading as a fact — two projects arriving at the
same number independently is interesting, but it is still a number the model
should produce rather than be told (`docs/23-the-plan.md`). What survives as
worth stealing is the SHAPE, not the constants: `allowed = min(floor(mi/X),
floor(ei/Y))` (`EconomyHelpers::AllowedGantryCountFromIncome` and four
siblings) scales with economic power instead of counting units — and even that
is a per-instant cap, which our own objective replaces with an ETA comparison.

The same file shows the cost of the approach: FRONT wants 40 metal/s for a T2
lab, FRONT_TECH wants 17, TECH wants 18 with 1000 stored. Six roles × ~40
constants each, hand-tuned, with no stated measurement behind any of them.

### Base layout

**They have none.** I grepped the whole `Barb3/stable/script/src` tree for
`FindBuildSite`, `facing`, `spacing`, build-site search, or anything that
computes a placement: the only hits are `GetBuildPos()` *reads* in
`map_helpers.as` and `global.as`. Placement is 100% CircuitAI C++ plus
`block_map.json`. Their `BARb/stable/config/hard_aggressive/block_map.json`
differs from our `reference/barb-stable` copy by ~107 changed comma-separated
tokens (a crude measure — these files carry `//` comments and the two trees are
different upstream vintages, so some of that is drift, not intent).

The one exception is the objective system's **hardcoded coordinates**
(`o1.pos = AIFloat3(340, 0, 12700)`, `radius = SQUARE_SIZE * 8`), which is
placement-by-authoring for a handful of spots on one map.

So on the 2.7×-footprint problem they offer no mechanism, only the observation
that a human typing coordinates is an acceptable answer for the few positions
that really matter.

### Build power vs income

Two lines, `helpers/economy_helpers.as:250` and `:264`:

```angelscript
int CalculateT1BuilderCap(float metalIncome, int minCap, int maxCap)  // cap = 3 + 3*floor(mi/15)
int CalculateT2BuilderCap(float metalIncome, int minCap, int maxCap)  // cap = 3 + 3*floor(mi/40)
```

clamped by `Global::RoleSettings::*::MaxT1Builders / MaxT2Builders` (5 and 5 for
TECH and FRONT_TECH). So: three builders floor, one more per 5 metal/s of
income, hard-capped at 5. Constructors are then assigned *roles* (primary /
secondary / freelance / tactical) and assist policy is another income threshold
(`ShouldSecondaryT2AssistPrimary`: assist while `mi < 160`).

### Target selection

**They do not do it.** The only military levers in the tree are
`aiMilitaryMgr.quota.attack`, `quota.raid.min`, `quota.raid.avg` and
`quota.scout`, set per role at init (`roles/air.as:110`, `front.as:42`,
`tech.as:77`, `sea.as:58`, …) and once more for AIR after ten minutes
(`air.as:85-93`, all three raised to 100). `manager/military.as` is 101 lines of
pure delegation; `AiMakeTask` for military falls through to
`aiMilitaryMgr.DefaultMakeTask` in every role. There is no reference anywhere to
enemy static defence, to enemy economy, or to scoring a target.

Two consequences for us. First, the undefended-economy priority and
static-defence penalty we just added has no counterpart here — we are ahead, and
there is nothing to copy. Second, note that setting `quota.attack` is exactly
the lever `CLAUDE.md` records as caps-units-*sent*-not-*built*; their per-role
"aggression" is therefore weaker than it reads.

### Defence placement — coverage or proximity?

Proximity, i.e. stock. `Military::AiMakeDefence` (`manager/military.as:61`)
delegates to the role or calls `aiMilitaryMgr.DefaultMakeDefence(cluster, pos)`
behind a gate of `frame > 10 min || metal.income > 10 || mobileThreat > 0`. Only
TECH registers a handler (`tech.as:743`) and its body also ends at
`DefaultMakeDefence`.

`helpers/defense_helpers.as` looks like the coverage model — `ShouldBuildT1LightAA`,
`ShouldBuildT2FlakAA`, `ShouldBuildLRPC`, twelve predicates in all. **Every one
is `// TODO` and `return false`.** It is a declared intention, not an
implementation.

The nearest thing to coverage is again the objective system: an objective's
`radius`/`line` plus per-type queued/built counters
(`ObjectiveManager::IncrementDefenseQueued/Built`) would express "this approach
needs N towers" — for the one map where objectives exist.

## 5. Things worth taking

Ordered by (my estimate of) value per unit of risk. None of this is measured —
I ran no matches, per the standing instruction while a watched game was live.

1. **The expansion early-return.** Six lines per role handler: if
   `DefaultMakeTask` came back with `MEX`/`MEXUP`/`GEO`/`GEOUP`, return it
   untouched. This is a *stop*, not a *spend* — `CLAUDE.md`'s own category for
   changes that cost no build power and are near-free to re-apply. It directly
   targets the mechanism behind our 11→2 mex-upgrade collapse.
2. **10-second sliding-minimum income instead of instantaneous income.**
   `manager/economy.as` keeps a monotonic-deque min over a 10-second window
   (`Economy::GetMinMetalIncomeLast10s` / `GetMinEnergyIncomeLast10s`), and every
   role's task logic reads *that*, not `aiEconomyMgr.metal.income`. Income in BAR
   spikes and stalls; a threshold sampled on a spike fires wrongly. `CLAUDE.md`
   already records that a `build_chain` condition "samples one moment" and that
   this produced zero nanos — this is the same bug class, and this is a clean
   fix that costs nothing at the point of use.
3. **Reclaiming your own obsolete buildings.** `RoleTech::Recycle`
   (`roles/tech.as:1332-1399`): reclaim the primary T1 bot lab once a T2 lab is
   queued, if stored metal < 600, if ≥ 3 T1 constructors exist, and if metal
   income ≤ 45; reclaim the primary T2 bot lab to fund a queued AFUS or nuke, but
   only if free metal *storage* ≥ the lab's cost so the reclaim isn't wasted;
   and never reclaim either once an Advanced Fusion is up. "Never reclaims old
   buildings" is a standing item in `USER-FEEDBACK.md`, and this is a
   ready-made, carefully-gated version of it.
4. **`allowed = min(floor(mi/X), floor(ei/Y))` as the standard shape for
   "how many of these can we afford".** We gate on income already; they have a
   uniform idiom for it that handles the energy axis at the same time.
5. **Per-map start-spot → role tables, as a *fallback-safe* mechanism.** The
   expensive part is the data (18 maps, hand-typed). The cheap part is the shape:
   match map by name prefix, nearest listed spot wins, otherwise derive the role
   from whatever factory CircuitAI already chose, and never hard-fail. If we ever
   want "that's a 4v4 map" or "this position is the sea player" to be knowable,
   this is a working pattern to copy rather than invent.

## 6. Things we already do better

Worth being explicit about, because it bounds how much attention this deserves.

- **Target selection.** They have none; we have undefended-economy priority and
  an enemy-static-defence penalty. Nothing to learn here.
- **Defence coverage.** Their model is a file of twelve stubs returning `false`.
- **Deployment robustness.** We derive the engine-side folder from the installed
  engine on every deploy; they bundle a frozen, older `SkirmishAI.dll` per
  folder and one of their folders overwrites stock `BARb/stable`.
- **Measurement.** I found no harness, no telemetry, no control runs, and no
  recorded results anywhere in the repo — 25 commits with messages like
  "Behaviour Update", "New Fixes", "Update 4/22/25". Every one of their ~250
  tuning constants is an unmeasured judgement call. Our `review.py` /
  `composition.py` / control-run discipline is the single biggest difference
  between the two projects, and it is in our favour.
- **Profile discipline.** Six near-identical `experimental_*` config trees is the
  exact duplication we deleted, for the exact reason `CLAUDE.md` gives.
- **Not writing findings into code.** Their tree carries claims in comments
  (`// Unit names are placeholders where uncertain`, `// TODO precise`) that have
  no dated evidence behind them — the failure mode
  `docs`/`CLAUDE.md` warn about repeatedly.

## 7. What I did not check

- I ran **no matches**. Nothing here is a statement about how well any of it
  plays, only about what the code does.
- I read `Barb3/stable` closely and the other eight folders only structurally.
  `Night/mare`'s four playstyle profiles are config-only and I did not diff them.
- The six `experimental_*` bonus profiles: I compared file sizes and found them
  near-identical but did not byte-diff every pair, so a small deliberate
  difference could exist that I missed.
- Their `BARb/stable` JSON vs stock: the token counts in §4 are a crude proxy
  measured against `reference/barb-stable`, which is a **different upstream
  vintage**. Do not quote those numbers as "how much they changed".
- The install Google Doc linked from the README (external, not fetched).
