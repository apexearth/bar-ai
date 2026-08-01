# What this AI does that stock BARb does not

Two variants, both built on BARb (CircuitAI). Everything here is a deliberate
difference from `BARb/stable`; anything not listed behaves as stock.

| variant | intent | best measured result |
|---|---|---|
| **apex** | stock BARb plus a team T2 rush | T2 at 5.7 min vs stock 13.9; ~45% wins |
| **apexdef** | hold ground, out-eco, finish with T3 | 4-3 over 10 clean games |

Status column below: **measured** = validated in a clean run; **unmeasured** =
implemented and smoke-tested only; **suspect** = measured under conditions later
found invalid.

---

## C++ / SkirmishAI.dll

New bindings in `vendor/engine/AI/Skirmish/BARb/src/circuit/`. The DLL is rebuilt
from source and stripped; see `docs/06-building-the-dll.md`.

| binding | purpose | status |
|---|---|---|
| `ai.SendResources(m, e, team)` | give metal to an ally — makes slinging possible at all | measured |
| `ai.GetTeamMetalIncome(team)` | ally income, for ranking the tech lead | measured |
| `ai.GetBestWreckPos(pos, r, min)` | richest wreck nearby, so reclaim is *valued* | measured |
| `ai.GetBuilderThreatAt(pos)` | per-position danger from the engine's `CThreatMap` | drives the constructor build-site veto; **unmeasured** |
| `CCircuitUnit::CmdMoveTo(pos)` | raw move order, outside the task system | **not called** |
| `ai.GetEnemyCostAt(pos, r)` | enemy count in radius | **not called — unsafe** |
| `aiEconomyMgr.FindOpenMexSpot(unit, pos)` | nearest open metal spot, using the guards `UpdateMetalTasks` applies | measured |
| `aiEconomyMgr.GetMexSpotPos(spotId)` | validated spot position, `-RgtVector` when invalid | measured |
| `aiEconomyMgr.EnqueueMexAt(unit, spotId)` | the only MEX enqueue carrying a real `spotId` | measured |

**measured**: 46 `con-reroute spot` events in one 40-minute 4v4, each moving a
constructor off a vetoed site onto a spot the threat map read at 0.

### Mex-spot indexing was an out-of-bounds write

`CBMexTask`'s constructor calls `SetOpenMexSpot(spotId, false)`, which indexed
`mexSpots[spotId]` with no bounds check, and `TaskB::Common` leaves that field at
`-1` (it aliases `pointId` in a union). Script could not safely enqueue a MEX
task at all. `mexSpots` is also sized in a deferred `Init()`, so before that runs
every id is out of range.

Guarded at the leaves — `CEconomyManager`'s mex/geo spot accessors and
`CMetalManager::IsOpenSpot`/`SetOpenSpot`/`GetCluster` — rather than at the call
sites, so the hazard closes for every caller. `SetOpenSpot` separately indexed
`clusterInfos[clusterId]` with a `clusterId` that is `-1` until clusterization
assigns it; that write is now guarded too.

Upstream bug found in the same pass: `CBMexTask::Reevaluate` set `spotId = 0` to
"prevent spot opening on Cancel", but `Cancel` guards on `spotId >= 0`, so `0`
passed and re-opened spot 0. Now `-1`.

### `FindFacing` orients on the enemy, not the map centre

`IBuilderTask::FindFacing` picked facing purely geometrically, facing the centre
of the map. `BuildPos` rotates `build_chain.json`'s `front` offset by that
facing, so every front-offset placement — flak, defences, nanos — pointed at the
map centre regardless of where the threat was. It now uses
`CEnemyManager::GetEnemyPos()`.

`enemyPos` initialises to the terrain centre, so before an enemy is located the
new code reproduces the old behaviour exactly. **unmeasured** — it compiles and
runs clean for 40 game-minutes on a hot path, but no placement outcome has been
measured against stock.

`ai.GetTeamMetalFill` also exists but returns nothing useful; see the engine bug
note in `CLAUDE.md`.

**Do not call** the last two. `GetEnemyCostAt` crashed the AI, and commander
retreat via `CmdMoveTo` correlated with the engine aborting 14-17 games per
20-game run. Both are registered but unreferenced.

## AngelScript (`script/hard_aggressive/`)

### Team tech coordination — the core of both variants
- **One designated tech lead**, chosen by **commitment**: whoever is building an
  advanced plant, and when two are, whichever plant is nearest done. Nanoframes
  count and the fractional build progress is the tie-break. Stock has no team
  coordination at all — each instance decides alone.
  **The election runs in the AI, over an in-process blackboard** — not in synced
  Lua, and not on income. Synced Lua cannot ship to a hosted multiplayer game;
  every AI the host adds shares one process, so the instances read each other via
  `PublishTeamValue`/`ReadTeamValue`. **measured**: with the released archive and
  no gadget present, all four instances elected the same lead within four frames
  and it never flapped across 20 minutes.
  It once ran per-instance on the assumption that identical synced inputs give
  identical answers; they do, but the *read instants* differ (SlowUpdate is
  offset by `skirmishAIId`), and 1 archived match in 533 elected two leads. The
  property that fixed it is kept — **one writer**: the lowest team id in the ally
  roster elects and publishes, everyone else only reads that slot.
- **The lead is replaced if it loses its plant**, and the title stops moving
  entirely past `RUSH_GIVEUP`, so the lead stays tech lead after sharing ends.
- **The commitment rule deadlocks against the follower gate unless the gate is
  conditioned on a lead existing.** The gate forbids any non-lead from starting a
  T2 factory before `FOLLOWER_TECH_FRAME`; if the lead *is* whoever started one,
  nobody may start, so nobody leads, so nobody may start. **measured**: first
  election at 10.5 min in two runs — the exact frame the gate opens — against a
  5.7 min baseline; gating on `LeadIsDesignated()` moved it to 6.9 min.
- **Slinging**: followers send 450-metal lumps to the lead, keeping 220, from
  5 min until they receive their own advanced constructor.
- **The whole strategy is abandoned at 15 min** (`Military::RUSH_GIVEUP`).
  Pooling is a bet -- the team runs poor and the lead runs armyless -- so if T2
  has not landed by then it has lost, and continuing compounds it. Slinging, the
  rusher's factory pre-emption, the T1-lab reclaim and both suppressed attack
  quotas all stop, and play reverts to stock. **measured**: all release paths fire
  at 15.0m and restore quota.attack to the stock 15.
- **The lead techs on zero bank**: stock requires `0.5 x plant cost` banked,
  which is never reachable. It places the plant and pours income in.
- **Followers get the same no-bank switch** once past 13 min — and **only one
  advanced plant each**.
- **Advanced plant matches the opening factory**: T1 bot lab → T2 bot lab,
  vehicle → vehicle. Stock forced a vehicle plant a bot lab cannot build.
- **The lead reclaims its own T1 lab** into the plant it replaces.
- **Advanced constructors are shared**, one per teammate. Big teams pre-empt the
  factory line to do it; small teams do not (measured: pre-empting cost 3-13).
- **The tech lead never opens air**, and on teams under 6 **nobody** does.

### Combat posture
- **Acting on enemy bearing did NOT work, and the machinery is gone.** The
  gadget used to publish the opposing start-position centroid as
  `ai_enemyx_/ai_enemyz_<teamId>` and `Military::BearingOffFromEnemy()` turned it
  into degrees off the line of attack. Skipping defence sites >90° off the line,
  and skipping them again while ahead on `mobileThreat/armyCost`, lost to an
  otherwise identical control over 12 paired 8v8 games: real K/D log-ratio
  −0.156 (t=−1.12) in the control's favour, metal a coin flip. Both the param and
  the helper have since been deleted — nothing in the script computes bearing
  today. `CEnemyManager::GetEnemyPos()` still exists in C++, unbound, if the idea
  is ever retried. **suspect — do not rebuild without a fresh A/B**
- **Mass before attacking**: attack quota grows 36 at 14 min → +3.5/min → cap 48.
  Stock attacks with whatever is to hand. Start/cap were raised from 30/36 on a
  request for a more cautious army; 140 and 80 both stalled the army entirely
  once the quota became enforceable (below), so the useful range is narrow and
  is being walked up rather than jumped. **unmeasured — not isolated from the
  AA change it shipped alongside.**
- **The attack quota did nothing until the promote shortcut was closed.**
  `CDefendTask::Update` promotes on
  `(attackPower >= maxPower) || !GetTasks(check).empty()`, and `DefaultMakeTask`
  builds the task with `check == ATTACK`. So the instant one attack task existed,
  every DEFEND task handed its units over on the next tick holding one unit or
  twenty — no value of `quota.attack` could close that. `Military::AiMakeTask`
  now enqueues `TaskF::Defend(MELEE, ATTACK, quota.attack)` for the units stock
  would route into the default branch; `MELEE` is a declared FightType nothing in
  CircuitAI ever enqueues, so `GetTasks(MELEE)` is permanently empty and only the
  mass test remains. Riot units with a live guard task, and support, keep stock
  routing. **unmeasured — and it makes `TURTLE_ATTACK`/`MASS_CAP` load-bearing
  for the first time, so those constants need a fresh read before they are
  trusted.**
- **Refuse bad trades** now compares metal to metal. It read
  `aiEnemyMgr.mobileThreat` against `armyCost`, which are different units; across
  eight 4v4 infologs that ratio logged **0.02–0.14** and never approached the 0.95
  threshold, so the clause had never fired. It now uses `EnemyArmyCost()`, the
  same `GetEnemyCost` sum `LosingGround()` already used. **unmeasured**
- **Reactive turtling**: hold when our army value drops 18% in 20 s, resume at
  85% of the pre-collapse peak, max 6 min, not before 5 min (apexdef).
  The hold itself fires and releases correctly — 7–22 HOLD/RESUME pairs per 40-min
  4v4 — it simply had no grip on dispatch until the item above.
- **Fodder is never grouped, and is bought while behind.** Cheap scout/raider
  units (`costM < 100`: Tick 21, Rascal 26, Wheelie/Goblin 25, Rover 31, Grunt 42,
  Pawn 54) skip the massing path entirely; cheap raiders also skip the
  `Defend(RAID, quota.raid[0])` staging and go straight to a RAID task. Every
  third "behind on the field" catch-up push now buys the cheapest body the
  factory can make instead of the assault mainstay — about 7% of the metal, since
  a Tick is 21 and a Hammer 130. Motivation, measured over the same eight
  infologs: apex's standing cheap-unit value ran **3–6× below stock BARb's from
  minute 14 on** (851 vs 3,727 at minute 18) while total army value was
  comparable. **unmeasured**

### Anti-air sized to the enemy's ground-vs-air mix
`Military::UpdateAirThreat()`, run every `AiUpdate`. Stock decides AA from raw
`GetEnemyCost(AIR)`, and nothing in the JSON layer can re-decide: build-chain
conditions are evaluated once, when the parent finishes.
- **`GetEnemyCost(AIR)` counts air constructors and scouts.** They carry
  `["builder", "air"]` / `["scout", "air"]` in `behaviour.json`, and
  `CFactoryManager`'s constructor adds the AIR *enemy* role to every def that
  `IsAbleToFly`. Two enemy air cons are 680 metal of "air" with no aircraft on
  the field. That is the input every AA path was reacting to.
- **`share = enemyAir / (enemyAir + enemyGround)`** drives one `scale` in
  `[0.1, 1]`, full strength at a quarter of their army flying. `scale` never
  exceeds 1, so this only ever builds *less* AA than stock.
- **Mobile AA**: `GetResponseInfo(AA).factor /= scale` and `.maxPercent = share`.
  `factor`, not `maxPercent`, is what binds while their air is small —
  `RoleProbability` builds AA while `enemyAir * ratio >= aaCost * factor`, so
  `aaCost` tops out at `ratio/factor * enemyAir` (0.268× on a 4-man team).
  `response.json` itself is untouched and still matches stock.
- **Static AA**: `armflak`/`armcir`, `corflak`/`corerad`, `legflak` get
  `maxThisUnit = count + spare` for `spare = enemyAir * scale / 1500`, capped at
  6 between them. `IsAvailable()` is checked on every path that can place one —
  build-chain hub, `DefaultMakeDefence`, base defence, factory — so one lever
  closes all four, and it gates task *creation* only, so anything already
  building finishes. The cheap tiers (`armrl`/`corrl`/`legrl` at 80 metal,
  `armferret`/`cormadsam`/`legrhapsis`) stay uncapped. `leglupara` is left out:
  it is Legion's superweapon entry as well, and `DiceBigGun` only re-rolls when a
  big gun finishes, so capping a def it had already picked denies Legion any
  superweapon for the rest of the game.
- Grep `apexaa:` for the measurement and the decision, once a minute per player.
- Removed `Military::AiIsAirValid()`: no C++ path looks that hook up (the engine
  reads `CEnemyManager::IsAirValid()` directly in `FactoryManager`/`FactoryData`),
  and `behaviour.json`'s `aa_threat` puts `maxAAThreat` above 100,000, so that
  gate is off in this profile regardless. **unmeasured**

### The factory overrides were land-blind, so water maps got no navy
Every override in `AiGetFactoryToBuild` named a hardcoded land def and runs
*ahead* of the engine's pick, so on a water map each replaced a naval choice with
something that had nowhere to go. The bot-lab branch was the worst: it returns
before every other pick in the function, so once it fired it held the side on
land for the rest of the game. Measured on Silent Sea:

    apex: opening corap -> corvp
    apex: no T1 bot lab -- building corlab   (x2)

and the side finished on `corlab`/`corvp`/`coralab`/`coravp` with no naval
anything, while stock BARb went amphibious.

None of this was the engine. `waterIsAVoid` is only set on harmful-water maps;
`CanBeBuiltAt` is sector-based so a shore-touching start qualifies; and
`T1_FAC`/`T2_FAC` already paired `armsy`->`armasy` and `corsy`->`corasy`.

`Factory::IsWaterMap()` is `!aiTerrainMgr.IsWaterAVoid() &&
aiTerrainMgr.GetLandPercent() < 40`. 40 is `factory.json`'s own
`select.min_land`, the same bar `CFactoryManager::GetRepresenter` uses to choose
a factory's water variant, so this agrees with the engine instead of inventing a
cutoff. Three sites now branch on it: the opening substitutes a shipyard rather
than a vehicle plant, the bot-lab branch is skipped, and `T3Gantry()` returns
`corgantuw`/`armshltxuw`.

**measured**, two 8-game arms, 3v3 Cortex on Silent Sea, same seeds and settings:

| | baseline | with fix |
|---|---|---|
| apex naval spend | **0 (0.0%)** | **63,640 (26.5% of top sinks)** |
| apex metal/game | 66,587 | 62,677 |

Zero naval metal in eight baseline games is the whole bug in one number. With the
fix it opens `corsy`, techs to `corasy`, and fields `corsub`/`corpt`/`corcrus`
with a `coracsub` constructor.

Metal per game is **not** improved: a single match showed 43,410 -> 51,646 and
that did not replicate over 8 games. Stock's own figure swung 62,339 -> 73,385
between the two arms, so the -5.9% here is inside run-to-run variation and no
economic claim should be made either way.

Land maps are unchanged — verified on Comet Catcher, same seed: still
`corap -> corvp`, bot lab x3, zero naval, `IsWaterMap()` false.

**Legion naval, corrected 2026-08-01.** An earlier note here claimed Legion had
no advanced shipyard, from a single failed filename search for `legasy`. That was
wrong. Legion's advanced shipyard is **Cortex's `corasy`** — listed in the
`buildoptions` of `legnavyconship`, `legcs` and `legch`, and named "Advanced
Shipyard" in `language/en/units.json` alongside `legadvshipyard`. Legion borrows
across factions elsewhere too: porcupine index 9 is `coratl` for all three sides.
`legsy` -> `corasy` is now paired in `T1_FAC`/`T2_FAC`, so a Legion shipyard
opening techs. `corasy` appears twice in `T2_FAC`, which is safe —
`AdvCounterpart` returns on the first `T1_FAC` match and `OwnAdvProgress` takes a
max.

`corgantuw` is genuinely Cortex-only (`coracsub`/`corhacs`/`corsacvsub` are its
only builders), so `T3Gantry()` leaves Legion on `leggant`.

**Legion crashes the AI at frame 0, and it is not new.** Reproduced on both a
water and a land map with this branch, and again with `ai/apex` checked out at
`d4ade1b` — the pre-session commit — so it predates every change here. The stack
is inside `SkirmishAI.dll`, not AngelScript, and no `.as` compile errors appear.
**Untriaged**; Legion is unusable until it is found.

Separately, `porcupine.water[1]` referenced index 17 while
`build_chain_leg.json`'s Legion array still ended at 16 — a real out-of-bounds
introduced by the AA fix above, now closed by appending `corfrt` there. It was
not the cause of the crash.

**Still open**: `coralab` remains 8.5% of apex spend on a water map. That is the
engine's own pick, not an override, and may be right where there are islands.
And `corcom` at 25.9% of all metal says the water *economy* is still weak — a
different problem from "we never build shipyards".

### AA at mex clusters — `porcupine.prevent` 1 -> 2
`DefaultMakeDefence` walks `num = isPorc ? defenders.size() : preventCount`, so
at `prevent: 1` an ordinary metal cluster could only ever reach `land[0]`, a
ground-only LLT. The AA tower sits at position 1, which made it **unreachable at
every non-porc cluster for the whole game**, however much air the enemy fielded.
The `CheapAA` rule in `builder.as` was firing but places at the constructor's own
position and caps at 4, so AA existed but never at the mexes being bombed.

Costs nothing while the enemy has no air: the walk `continue`s past any
`IsRoleAA()` def while `GetEnemyCost(AIR) < 1`, and the loop is bounded by
`i < num`, so the slot simply goes unused. `land[1]` is `armrl`/`corrl`/`legrl`
at 80 metal.

`water[1]` was a duplicate of `water[0]`, so `prevent: 2` would have bought a
*second torpedo launcher* rather than AA. Appended `armfrt`/`corfrt` (SeaDefence,
VTOL-only, 90 metal, buildable by commander/`armcs`/`armch`/`armbeaver`) at index
17 and pointed `water[1]` at it. Legion has no floating AA and borrows `corfrt`,
as its array already borrows `coratl`.

**measured**, 8 games 3v3 Cortex on Comet Catcher: T1 AA **37.0 per game vs
stock's 3.1**, with metal produced level (150,714 vs 150,651). Above the 12 that
`CheapAA` alone could produce, so the cluster path is doing the work.

### T3 defence gated on energy, not metal
`Pulsar()` gated only on `PULSAR_MIN_INCOME = 60` *metal* income, which T1 mexes
reach on their own — observed firing at `mInc=65..78`. These are energy monsters,
not metal ones: `cordoom` 37,000E, `legbastion` 58,000E, `armanni` 74,000E,
against 3,000-4,200 metal. So a Doomsday went up at 24.0 min while the fusion did
not arrive until 26.0.

Added `PULSAR_MIN_ENERGY = 1000` (apexearth: "we need at least 1000 energy per
second before we should start thinking about making those" — one fusion is
`armfus` 1000 / `corfus` 1100 / `legfus` 1200 E/s).

`porcupine.base`'s `[12, 1500]` entry is removed. That path has **no income test
of any kind** — `UpdateDefence` enqueues each entry at its frame — so it planted a
T3 gun at 25 min on a pre-fusion economy regardless of any gate on `Pulsar()`.
`Builder::Pulsar` is now the only route to those guns.

**measured**, 8 games against the arm above, same map/seeds/settings:

| | before | after |
|---|---|---|
| `cordoom` spend | 90,000 (18.8%) | **48,000 (10.7%)** |
| `corfus` spend | 13,500 (2.8%) | **31,500 (7.0%)** |
| fusion reaches top sinks | 3 of 8 games, median 30.0 min | **6 of 8 games, median 27.0 min** |

Remaining `cordoom` spend is post-1000 E/s and therefore intended. Army fell
17,586 -> 15,618 per game while stock held flat; that is inside the known
tournament noise floor and is **not** established as an effect.

### Economy
- **Reclaim over resurrect**: rez bots are handed a wreck reclaim before
  `DefaultMakeTask` can give them a resurrect. Resurrecting spends metal;
  reclaiming yields it.
- **Valued corpse reclaim**: idle builders go to the *richest* nearby wreck, not
  the closest. apexdef reaches further (2200) and accepts smaller bodies (55).
- **Reclaim when broke**: a builder standing on metal with an empty bank eats it
  rather than holding an unaffordable build task.
- **T3 gantry** is an explicit tech goal above 100 metal/s (apexdef).

### Constructor survivability
- **Threatened build sites are refused.** `AiMakeTask` reads the threat map at
  the build position of whatever `DefaultMakeTask` hands back, and drops the task
  above `CON_THREAT_VETO` (4.0) for economy and utility builds — mex, mexup,
  energy, geo, convert, store, pylon, radar, sonar, nano, factory. Defence,
  bunkers, big guns, repair and reclaim are deliberately exempt: those belong at
  the front.
  Stock's own check (`BuilderManager::MakeBuilderTask`) needs threat AND negative
  influence AND a powerless buildDef all at once, so contested ground the enemy
  has not yet painted with influence passes it. That is the ground a constructor
  walks into and dies on.
- **Refusal is a ladder, not just a veto**, per apexearth: "when a mex is too
  dangerous to build, they should try to find a safer mex to build instead. And
  if there are none, then they probably should be making some defenses."
  1. *Safer mex.* `Builder::SaferMex` asks `aiEconomyMgr.FindOpenMexSpot` for the
     nearest spot the engine has not claimed, and builds there via
     `EnqueueMexAt`. If no open spot survives the threat bar it falls back to
     trading for the nearest live MEX task the same unit reads as cold, within
     3000 elmos and with no assignee yet. Only from the refuse path — see below.
     Both outcomes are distinguishable in the log (`con-reroute spot` vs
     `con-reroute trade`); in one 40-minute 4v4 the split was 46 spot / 60 trade,
     so the fallback still carries real traffic.
  2. *Defence a distance back.* `Builder::ContestDefence` walks from the hot site
     toward our own start in 160-elmo steps until the threat map reads clear (up
     to 6 steps) and enqueues a tower there. apexearth: "build defenses a safe
     distance from the mex we desire to control." One per 30 s, and never within
     500 elmos of the last one; skipped while energy is stalling, because handing
     a task over directly bypasses `CanAssignTo`, which is where the engine's own
     energy test lives.
     **Only for ground worth holding** — mex, mexup, factory (gantry included),
     energy, geo, geoup. A radar, sonar, store, pylon, nano or convert can be
     rebuilt behind the line and does not justify a tower.
  3. Otherwise the previous behaviour: retreat if walking, wreck reclaim if idle.
- **The two paths differ, and it matters.** From `CIdleTask` the returned task is
  simply assigned, so an alternative mex can be handed over. From
  `IBuilderTask::Reevaluate` the swap happens *only when the returned task
  differs in build type*, so a mex-for-mex trade is silently discarded and the
  unit keeps walking; only the defence post and the retreat take effect there.
- **Tier split on the tower.** T2 constructors share no defence with T1:
  `armack`/`armacv` have neither `armllt` nor `armmex` in their buildoptions.
  Read from the unit defs: T1 gets `armllt`/`corllt`/`leglht`, T2 gets
  `armpb`/`corvipe`/`legapopupdef` (all three are porcupine index 8).
- Commanders are exempt — they have their own health-based retreat, and position
  threat was measured not to predict commander death.
- **Air constructors are covered now.** The site check uses
  `ai.GetUnitThreatAt(unit, pos)`, which picks the threat layer from the unit's
  own movement type; `GetBuilderThreatAt` is the BUILDER-role *surface* layer,
  and `ThreatMap::AddEnemyUnit` routes AA into the air layer, so a pure AA turret
  contributed nothing to it. For a ground constructor the two read the same
  array, so the 4.0 bar is unchanged.
- **Verify with** three greps, each rate limited to one line per 5 s and each
  carrying running totals. **unmeasured** beyond that the paths fire.
  - `grep "apex: con-veto" infolog.txt` — refusals and abandons, with
    `refused= abandoned= rerouted= defended=`.
  - `grep "apex: con-reroute" infolog.txt` — rung 1, tagged `spot` or `trade`,
    with the spot id, the alternative's threat and the distance.
  - `grep "apex: con-defend" infolog.txt` — rung 2, with the tower def and how
    far back it was placed.
- **The reroute's fallback keeps a list of the engine's own MEX tasks.**
  `AiTaskAdded` / `AiTaskRemoved` hold live MEX task handles; `IUnitTask` is
  refcounted and every removal funnels through `ITaskModule::DequeueTask`, which
  calls `AiTaskRemoved`, so the list cannot go stale. A traded task must carry
  the *same* `buildDef` as the refused one — that is the only proof available
  that the unit can build it, since `CCircuitDef` exposes no `CanBuild` binding
  and mex defs are per-constructor (`armck` builds `armmex`, `armack` only
  `armmoho`). The spot query has no such limit: `EnqueueMexAt` picks a def from
  the unit's own build options.

## Config (`config/hard_aggressive/`)

| change | why | status |
|---|---|---|
| `mex_up` 3 → 10 | T2 mexes are 4x metal; upgrade them all | measured |
| Metal storage `since` 300 → 1200 | at 5 min there is nothing to store | unmeasured |
| Fusion gated `m_inc > 28` | ~1000 e/s of economy, per human practice | suspect |
| Advanced fusion added to the fusion hub | it existed only as a hub *key*, so nothing ever built one | unmeasured |
| Nano gates on reachable income (14/22) | old gates of 22-46 produced **zero** nanos | measured |
| T1.5 towers at every advanced plant | plants had four nanos, a fusion, and no defence | unmeasured |
| Jammer towers rehung + `sensor: 900` | parent was porcupine index 12, never built, so `chance` never rolled | unmeasured |
| Commanders get `dg_cost` | stop D-gunning our own lab to kill one raider | unmeasured |
| Spam kept at high tiers (all factions) | cheap units for vision and distraction vs long-range T2 | unmeasured |
| `porcupine.land` index 13 removed, 12 moved ahead of 11 | inert towers were eating the cluster budget before the real guns | unmeasured |

### `porcupine.land` was spending its budget on towers that never fire

`DefaultMakeDefence` walks the list until cost passes a fraction of income, so
anything late in the list is unreachable on a normal budget. Two things were
wasting it.

Flak (index 10) appeared **seven times consecutively** in `rush` — ~5,740 metal
of flak per hot cluster at hosted-game income. Now 2×, matching what
`hard_aggressive` already carried.

Index 13 (`armguard`/`corpun`/`legcluster`) carries `"on": false` in behaviour,
and `SetOn(false)` is issued to the unit when it finishes
(`CircuitAI::UnitFinished`). The only thing that switches such a unit back on is
`CCircuitUnit::Attack`, and only when the def has `ATTR ONOFF` — which
`FactoryManager` sets only if the def declares `slow_target`. None of these do.
So they were built, paid for, and left switched off. Removed from the list.

Index 11 is the same defect for `armamb`/`cortoast` but **not** for Legion:
`legacluster` has no `on` flag and works. One list is shared by all three sides
(`ReadConfig` indexes each side's own `unit` array), so it is reordered rather
than cut — 12 (`armanni`/`cordoom`/`legbastion`, all functional) now precedes 11,
which reaches the working gun first without costing Legion its tower.

## One profile

`easy`, `medium`, `hard` and `rush` are gone — config and script both. They were
stock BARb trees carrying none of this AI's work (zero `apex:` markers between
them), and `AIOptions.lua` had already stopped offering them, so they were
unreachable in the lobby while still needing every change made four more times.
Deleting them also cleared 23 inherited dead-unit-name warnings from
`tools/check.py`.

`hard_aggressive` is the only profile. The shared fallback layer
(`config/*.json`, `script/{common,define,task,unit}.as`) is unchanged.
| Radar + mobile jammer paired | `coreter` beside `corvrad` (Cortex only so far) | unmeasured |
| Gantry `income_tier` 100/200 → 45/90 | unreachable, so a built gantry sat in its last tier | unmeasured |
| Converters moved to their own hub chain | they sat 6th-10th in the fusion/afus chain, so the first one started only after five nano turrets finished — and `~IBuilderTask` deletes `nextTask`, so a nano that failed placement took every converter behind it | unmeasured |
| Converters sized to the generator: fus 2, afus 5 (`legafus` 6) | one adv converter eats 600 e/s; armfus makes 1000, corfus 1100, legfus 1200, arm/corafus 3000, legafus 3300. `legfus` had none at all while armfus/corfus had two | unmeasured |
| `limit: 1` on `armuwadvms`, `armuwms`, `leguwmstore` | the last uncapped metal storages, and `limit` is the only cap there is | unmeasured |
| Advanced-fusion hub: 4 flak → 1, gated `air` (all three factions) | 3,280 metal / 52,000 energy of flak per `armafus`, unconditional and at `now` priority; `legafus` was 2 `legflak` + 2 `leglupara`, and `leglupara` is `anti_air` too | unmeasured |
| `porcupine.land`: flak listed 7× → 2× | `DefaultMakeDefence` walks the list until `totalCost` passes the income cap, so at hosted-game income a hot cluster spent 5,740 metal on flak and never reached indices 11/12 | unmeasured |

Upstream bugs found and worked around: `legbombard` has no builder, `armfmd` is
not a unit def, three `nanotct2` variants are buildable by nobody, several
porcupine entries ship `on: false` and are built inert.

## Energy waste, metal storage, late-game mexes — what was measured

Three late-game complaints from a hosted game, checked against the 8 paired
+40% 40-minute 4v4s in `ab_t*` / `ab_c*` / `run-t3*` (apex ally 0, stock BARb
ally 1) before anything was changed.

**Energy waste is real.** Whole-game `energyExcess/energyProduced` is worthless
here — it tracks who is losing, not which AI — so it was sliced per team per
2-minute sample and bucketed on that slice's own energy income. apex wastes more
than stock in **every** band:

| e/s band | apex waste | stock waste |
|---|---|---|
| 200-500 | 12.4% | 1.9% |
| 500-1000 | 3.3% | 0.8% |
| 1000-2000 | 8.0% | 1.1% |
| 2000-4000 | 3.8% | 2.7% |
| 4000-8000 | 5.3% | 3.4% |
| 8000+ | 2.5% | 1.0% |

BAR's `game_energy_conversion` gadget converts `eCur - eStor * 0.75` per tick,
capped by total converter capacity, so overflow at full storage *is* the measure
of missing converter capacity. Hence the two build-chain changes above.

**Metal storage runaway was not reproduced at benchmark scale** (`armmstor`
never reaches the telemetry's top-4 spend list in any of the 8 games), but the
mechanism is in the source. `CEconomyManager::UpdateStorageTasks` ships with its
`GetMetalStore() > 60 * GetAvgMetalIncome()` cap commented out, leaving
`IsMetalFull()` as the only gate — satisfied almost continuously on a bonused
economy. It also consults exactly one def, `storeMDefs.GetFirstDef()` (best
storage-per-metal, **no** availability filter, no fallback), which is
`armuwadvms` 10000/750 rather than `armmstor` 3000/330 wherever an advanced
constructor exists. `armuwadvms`, `armuwms` and `leguwmstore` carried no
`limit`; their Cortex twins did. Faction parity, again.

**Late-game mex obsession did NOT reproduce, and points the other way.** After
minute 20, apex builds 0.66 extractors/min against stock's 1.13, and sinks 3.9%
of metal produced into extractors against stock's 5.4% (n=32 team-games each).
So no config was changed for it. What is true in the source, at any scale:
`UpdateMetalTasks` enqueues MEX and MEXUP at `Priority::HIGH` and **returns**
before it ever reaches the converter branch, task weight is `1/(priority+1)²` so
a HIGH task beats a NORMAL one at 2.25x the distance, and the mex brake is
`(GetAvgMetalIncome() < 100) || !IsMetalFull()` — an OR, so high income alone
never stops it. `mex_max: [2.0, false]` leaves `mexMax` at `UINT_MAX`, so
concurrent MEX tasks are unbounded; dropping it below 1.0 also switches on the
`ms_pull` expansion rule, which is why it was left alone.

## T3 urgency gate — implemented, NOT shown to work

`T3Worthwhile()` used to refuse a gantry whenever `gTurtle` was set or our army
was smaller than the enemy's, so it only ever allowed T3 from a winning position.
Above `T3_INCOME_URGENT` (150 m/s) both vetoes are skipped. Motivated by a live
hosted game: a player on 398 m/s with enemy T3 in the base built nothing.

**8 paired +40% 40-minute 4v4s say the change is not measurable.** Win rate 2/4
treatment vs 1/4 control (2 draws). apex T3 median 40,265 vs 13,720, but the
ranges are 0-86,810 and 0-205,200 -- the single largest T3 game in the whole set
was a CONTROL run, because the old gate happily builds T3 when winning.

What actually predicts T3 spend is economy scale, not the gate: the four runs
above ~400 m/s peak built 86.8k/205.2k/64.0k/11.8k, the four below ~230 m/s built
0/16.6k/0/15.7k, with both arms on both sides. An earlier 1-vs-1 pair looked
decisive and was luck.

Kept because it only relaxes a veto in a case observed live and costs nothing
otherwise. The case it targets -- big economy AND losing -- is barely sampled by
random games, so testing it needs a scenario, not more matches. **unmeasured**

## Surprise air eco-assassination — implemented, NEVER RUN

`script/hard_aggressive/manager/air.as`, namespace `Air`. One player per ally
team builds a hidden T2 air force and throws all of it at the enemy economy.
**Not one game has been played with this. Every number in it is reasoned from
unit costs and from the C++ it drives.**

What it does:

| piece | mechanism | status |
|---|---|---|
| One air player per ally team | same one-writer blackboard as the tech election: everyone publishes `airinc`, `Factory::ElectorTeamId()` publishes `airlead` once, latched | unmeasured |
| Two-step plant chain | the T2 air plant is buildable by **air constructors only** (`armca`/`armaca` and pairs) — no ground con of any tier has it. So: T1 air plant → its 5-con opener → T2 air plant | unmeasured |
| 20 bombers + 20 fighters | forced from the T2 plant in `Factory::AiMakeTask`, alternating in proportion, 2 s apart | unmeasured |
| Held at home | `Military::AiMakeTask` returns null, which leaves the unit in the idle task with no orders | unmeasured |
| Abort on enemy AA | `GetEnemyCost(anti_air) > 2500` metal before committing; after committing it strikes early if half-massed, else stands down | unmeasured |
| Strike hits economy, not army | `ANTI_STAT` added to the bomber def at release: `CBombTask::FindTarget` then skips every mobile enemy. Per-instance — `CCircuitDef` is owned by each `CCircuitAI` | unmeasured |
| No retreat | `retreat: 0.0` on the six strike aircraft in `behaviour.json`/`behaviour_leg.json`; `IFighterTask::OnUnitDamaged` returns early while `healthPerc > GetRetreat()` | unmeasured |

What it does **not** do, and why:

- **They are not landed, only orderless.** `CmdFindPad` and `CmdWait` exist in
  `CCircuitUnit` but are not registered to AngelScript — only `CmdMoveTo` is. An
  idle aircraft hovers where it was built. Anything that scouts our base sees it,
  so "hidden" here means "off the map", not "invisible".
- **Bombers and fighters strike as two squads, not one.** `ISquadTask` merges
  only within one `fightType`, so bombers form a BOMB squad and fighters an AA
  squad and they travel separately. Combining them needs C++.
- **No edge-of-map routing and no anti-flak spreading.** The path comes from
  `CPathFinder` against the threat map; neither the route nor the formation is
  reachable from script.
- **`retreat: 0.0` is profile-wide, not scoped to the strategy.** There is no
  `SetRetreat` binding, so `armpnix`, `armhawk`, `corhurc`, `corvamp`,
  `legphoenix` and `legvenator` now fight to the death for every player on this
  profile, not just the air assassin.
- The income bar (60 m/s for the air player) is set above what the 4v4 benchmark
  reaches, so **the expected benchmark result is that this never fires**. The
  elector logs "no air assassin, best ally income X/60" once a minute past 15 min
  so that silence can be told apart from a script that failed to compile.

Also found while reading the C++: `Military::AiIsAirValid()` in `military.as` is
dead — no C++ path calls it. The real gate is `CEnemyManager::IsAirValid()`
against `quota.aa_threat`, which this profile sets to `[[8, 99999], [96, 500000]]`,
i.e. effectively disabled.

## Packaging — what makes it load in a hosted game

- **Ships under its own shortName, `BARbApex`**, rather than as version `apex` of
  `BARb`. The lobby's `ADDBOT` carries only `aiLib`, with no version field, so a
  hosted game's start script has `Version` empty; the engine then keeps every key
  matching the shortName and picks the highest by `VersionCompare`, and
  `"apex" < "stable"`. As a version, the variant loaded **stock BARb in every
  multiplayer game** and said nothing. Single-player was unaffected, because
  Chobby writes that start script itself and does pass the version — which is
  why it only appeared when hosting. **measured**: reproduced and fixed under
  `run_match.py --drop-ai-version`, which omits `Version` exactly as a host does.
- **Config and script are deployed engine-side as well**, into
  `AI/Skirmish/BARbApex/apex/`. Other players are on released BAR, which has no
  `LuaRules/Configs/...` for us; CircuitAI logs "Game-side config: missing!" and
  falls back to `LocatePath("config/")` over the AI data dirs. **measured**

## Dev instrumentation (not part of the AI)

`game-patches/gadgets/` — installed into `BAR.sdd`, inert in normal play.
- `dev_stats_export.lua` — value-weighted telemetry: real vs chaff kills, T2
  placement *and* completion, T2 mex count, reclaim, **commander losses**,
  **constructors held (T1/T2) and metal tied up in them**.
- `dev_team_income.lua` — **mostly dead, and deliberately still running.** The AI
  no longer reads its income table or its `ai_lead_` election; both moved
  in-process so they survive a hosted game. The only live reader left is the team
  front (`ai_frontx_`/`ai_frontz_`). Its `[BARAI_LEAD]` echo still fires and no
  longer reflects what the AI believes — read `apex: tech lead` from the AI's own
  log instead. Delete the dead half once the front is ported.
- `tools/trace_flow.py` — reconstructs the pooling sequence (elect → pool →
  rush → tech → share → follow) per ally team from an infolog and names the
  first step that broke. Needs the `[3.9m t2]` team-tagged log prefix.
- `tools/check.py` — pre-deploy gate: invalid JSON, non-existent unit names,
  multi-key `condition` objects, version/profile mismatches. Baseline-aware, so
  it reports our breakage and not the ~31 quirks inherited from stock.
- `ai_namer.lua` patch — prefixes AI names with their variant so replays are
  readable.

---

## Known not done

- **Factory placement in safe ground.** The `"support"` attribute is documented
  as "build in base radius, not on front" and is already set on every factory —
  but there is no `IsAttrSupport` in the source, so it is unclear anything reads
  it. Unsolved.
- **Commander retreat.** Three approaches tried, none worked. `commander.json`
  hide levers moved losses not at all and cost 10-20k metal; `GetEnemyCostAt`
  crashed and returned zeros; `GetBuilderThreatAt` works but **does not predict
  death** — across 10 games, readings within 30 s of a commander dying were
  *lower* than baseline (3% nonzero vs 8%). Commander survival is still the
  strongest outcome correlate measured here, so it is worth pursuing, but not
  through a sampled position-threat signal.
- **Choosing a metal spot from script.** Nothing in the binding surface can
  enumerate metal spots or clusters — `CMetalManager` and `CMetalData` are not
  registered at all — and `TaskB::Common` leaves `spotId` at -1, which
  `CBMexTask` indexes `mexSpots` with. So the constructor ladder can only reroute
  between MEX tasks the engine has already created, and cannot open a spot the
  engine has not picked. Wanted: `int aiEconomyMgr.FindOpenMexSpot(CCircuitUnit@,
  const AIFloat3& in)` returning a spot id, plus `AIFloat3 GetMexSpotPos(int)`,
  so `TaskB::Spot(MEX, ...)` becomes usable from script.
- **Reachability from script.** `CTerrainManager::CanReachAt(unit, pos, dist)`
  decides whether a builder can path to a position and is used all over
  `MakeBuilderTask`; it is not registered. The reroute is distance-bounded as a
  stand-in for it.
- **Sling guard when under attack.** Followers give away metal with no check on
  their own safety.
- **Nuke bomber massing, progressive scout quotas, all-in timing scaled to T3.**
- **Armada and Legion radar/jammer pairing.**

## Reading results

Check `exit_code` and `reason` in `result.json`, not just the winner. A run where
games end without a winner may be aborting rather than drawing — that mistake
invalidated several days of conclusions here. Clean games are `exit 0` with
`reason=gameover` or `reason=timelimit`.
