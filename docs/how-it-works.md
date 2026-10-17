# How it works

What the AI is and how its parts decide. Current code only; where this page and the code
disagree, the code wins and this page is fixed. The `ai-*` skills carry each part's
operational detail; `doctrine.md` says what the AI should do, this page says how it does it.

## What it is

A fork of **BARb** (CircuitAI, branch `barbarian`): a C++ skirmish AI driven by JSON config and
AngelScript, running on the Recoil engine. Our variant is shortName **`Apex`**, version
**`Unstable`**, profile **`standard`**; the harness spec is `Apex:Unstable:standard`. It must have
its own shortName: a hosted lobby sends no version, so the engine loads the highest installed
version of a shortName (S1), which is also why a release is a new, higher version (`working.md`).

Three layers, edited in `ai/Unstable/`:

| Layer | Where | Build | Holds |
|---|---|---|---|
| JSON | `game-side/config/standard/*.json` | none | per-unit `role`/`threat`/`power` and the `quota`/`retreat`/`defence` roots in `behaviour.json`; `block_map.json`, `commander.json`, parts of `economy.json` |
| AngelScript | `game-side/script/standard/` | none | every building and production decision, posture, raids, air, nukes, the commander, the nets |
| C++ | `cpp/src/circuit/` (mirror of the lane's `vendor/` tree) | Docker, `build_dll.py` | squads and fight tasks, threat and influence maps, placement, the AngelScript bindings |

JSON and script load at AI init (no hot reload, S51). `factory.json` weight tables and
`response.json` (empty) decide nothing; `build_chain.json` hubs are emptied because the DLL
walked them past every script gate. Composition is decided in `manager/brain/market/`.

Script layout: `init.as` (which JSON loads), `main.as` (setup, `AiUpdate`), `tunables.as` (every
default, one line each; rationale in `tunables.md`), `targets.as` (the spend split),
`policy.as`, `perf.as`. Every `manager/<name>.as` is a shim `#include`-ing its
`manager/<name>/` parts; edit the parts. The modules: `brain/` (the market, production queue,
budget, nukes, factory yard), `builder/` (elections' plumbing, requests, reclaim, site safety),
`factory/`, `military/`, `air/`, `frontline/` (influence, territory, the front),
`baseplan/` + `lattice.as` + `grid.as` (where buildings go), `catalog.as` (per-def economics and
the who-builds-what graph), `role.as`, `misc/commander.as`.

## The one idea

Every decision answers **what is the fastest path to the state we are trying to reach?** The AI
names a target (so much army, or that much army with a fusion behind it) and takes the move that
makes it arrive soonest, under one standing obligation: army and defence stay at their share of
the economy we have built. Investing in the economy wins whenever its return pays for itself
before the target is due. A rung of the economic ladder is reached when the cheaper growth under
it is exhausted (spots taken, upgrades done, ground we cannot hold), not at an income. So a
threshold, build order, cap or exclusivity in this code is a bug in the model wearing a fix's
clothing (`value-paradigm`, `eta-objective`).

## Builders: the market

`Market::Decide` (`market/decide.as`) is the only thing that gives a mobile builder a job. One
call is one **election** for one constructor, and a builder with a job is re-elected on every task
update (S14), so an election that changes nothing must return the task it holds.

1. Holds: commander safety; keep the job while its build has progress, the builder is within
   reach of the site, or it is still closing on it.
2. About twenty proposer steps (`ProposeStep`): mex, energy, geo, plant, convert, store, mex
   upgrade, tech, nano, four reclaim kinds, assist/factory guard, protect (ground defence), teeth,
   sense (radar/jammer), air defence, superweapons, reclaim metal. Each returns its best
   **Want** `{kind, def, pos, gain, mCost, tCost, value}`. The steps are sliced across frames
   against a time budget (`ElecAfford`); expensive proposers are memoised per asker.
3. **Value = gain / cost**, cost being metal plus time (build time, the walk, and the expected
   loss on the road: `ChargeTrip`). Gains are priced in one currency (`ai-eco-pricing`); risk
   discounts come from the threat, hazard and cover fields (`ai-risk-model`).
4. `OppTimeReprice`: a hand's time is charged at its best alternative job, so a far hand does not
   claim what a near one should.
5. Forced wants (panics, cover jumps, escorts, the opening plan) hoist past the draw.
6. Wants compete as **categories** (metal, energy, produce, build power, defence, sense, air
   defence, reclaim): one ticket each, weighted by the category's best value sharpened by
   `apex_draw_sharp` (more for a big commitment) and scaled by the budget's target/actual
   correction for that category, drawn by roulette. Within the economic categories the **ETA
   ladder** (`eta.as`, `TUNE_ETA`) re-ranks by time to the target. The policy net tilts the list
   (below).
7. `ExecuteWant` walks down the ranked list; a want the executor refuses (ground taken, request
   standing, out of reach) falls to the runner-up. Nothing positive left: guard, patrol, idle.

`apex: decide` logs winner and runner-up; `trace.py --filter=decide` reads it.

**Crews** (`ai-builder-crew`): every build goes through the requests chokepoint
(`builder/requests/`), which dedups, joins and adopts orphans. How many hands work one site and
how many sites run at once are derived from income; surplus hands are peeled back to the auction.
A hand joins live work only if it shortens it after arriving (`WorthJoiningSite`); under
`TUNE_JOIN_ARRIVE` (off, `requests/joinarrive.as`) every join, assist, guard, commander rescue,
army gift and nano lift asks one helper that counts only the work left at arrival, times the job's
worth, less the trip's risk, and `check.py` holds those call sites to it.
Roles (`market/roles.as`) shift how much a seat leans to energy, defence or upgrades, never
whether it may.

**The kill census.** No leaf rule spends on its own. `check.py` fails any `Enqueue(TaskB::`,
`Requests::Take(` or native `DefaultMakeTask` call outside the files its `_SPEND_ALLOWED` table
names (the market's executors and a few non-spending unit thoughts). The DLL's native economy,
factory choice, defence placement and build chains are stubbed in C++.

## Factories

`facqueue.as` adopts every factory line, holds it on a Wait task and keeps its engine queue a
little deeper than the re-election gap (`TUNE_FAC_QUEUE`), inserting orders with `CMD_INSERT`
(S45, S46). What each slot makes is `Market::ConOrderFor` (`market/production.as`): constructor
floors (derived from income and the hands' backlog), then army priced against the army target
and the enemy's army, the unit track record (`worth.as`: damage dealt over own health, per type
and matchup), counter roles, scouts, rez bots, escorts and fodder. Which factory to build is a
Want of kind plant/tech. Nano turrets are owed to a plant before any copy of it; their price is
otherwise spare metal only, and under `TUNE_LAB_NANO` (off, `market/labnano.as`) a turret at a lab
is priced by the army metal per second it adds there, up to income / labs less its ring. Under
`TUNE_OPEN_RACE` (off) a con-floor order is first raced against the lab's best fighter on one
clock (`market/openrace.as`), and a lab short of energy prices its units by feed share instead of
idling; on short contact the con is worth the open spots it reaches before their cons
(`market/spotrace.as`), which also gives the team army and raiders their contest targets. Under
`TUNE_COUNTER_MIX` (off) each ground fighter's draw value is multiplied by its square-law fight
value per metal against the enemy army we have seen, and by a raid value against their economy
where it outruns what it cannot fight, renormalised over the army candidates (`market/countermix.as`).

**The budget** (`brain/budget.as`, `targets.as`): spend is counted from what finishes, in five
rows (army, defence, air defence, economy, build power), against target shares of what we hold.
The army target and the T2 switch live in `market/army.as`.

## Defence and placement

Ground defence is the protect want (`market/protect_*.as`; `ai-placement`, `ai-risk-model`). The
wall is drawn from the **team hull** (every ally's buildings), slots stand on the team's frontier,
and a slot is priced by how much it lowers the worst open bearing into the hull; teeth in front,
mains, nano and shield support behind. Extractors outside the base earn guns by how soon the enemy
reaches them. The defence target is a share of holdings and army; `defamt`, `mexg` and `gunp`
heads scale it. Placement itself is the lattice (`lattice.as`, `baseplan/`): one per-def grid from
the map corner, nano blocks, walkways the team shares; the DLL's `IBuilderTask::Execute` snaps to
it.

## Military

The C++ fight classes (`task/fighter/`: Attack, Defend, Raid, Squad, Bomb, ...) went back to stock
BARb on 2026-09-07, with additions since: the team push and focus (`AttackTask`, flank choice),
`CSiegeTask` with the fort census (`unit/enemy/FortCensus.cpp`), all-terrain squads kept apart,
the bomber formation. The script side (`manager/military/`) decides **use**, not micro:
`hooks.as` elects a fight task per unit (massing pool, raid pack, escort, cover, fodder,
charger); `massing.as` sets the pool's leave bar; `posture.as`/`stance.as` hold, defend or
attack; `raid.as` asks for raids on scored enemy spots; `withdraw.as` recalls; `nnhunt.as`,
`nnstrike.as`, `nnsiege.as`, `nnraid.as` are the decisions to hunt their army, strike a timing
window, siege a fort, raid. Under `TUNE_COM_FIGHT` (off) `comfight.as` fights every ground squad
in reach of an armed enemy out on paper each second and overrides its task through
`SetScriptMove`. The estimate is scaled by the team's running real/predicted metal (lost and killed
apart, team board; a prediction covers one engaged segment, retaken when the group or the enemy in
reach moves past its band, and outcomes count only while engaged); a group fights while calibrated loss minus kill is under the stake falling back
abandons (our metal and open spots in the threat's reach, times the share of their force the fight
destroys) plus the walk out and back, and a verdict moves only past the measured error band. Else
it falls back to the nearest friendly strength where the pooled estimate pays, onto one shared
point against their largest group; attack groups out of contact walk onto the enemy group they beat
by more than the band (defeat in detail); `nnraid.as` packs and split-off packs price their loss
with the same calibrated fight. A raid GO pulls every raider in the home pools and spare escorts
onto the one live pack, wherever it is; under `TUNE_GATHER` (off, `gather.as`) the pack in the
field and the raiders at home are priced as two groups, a GO launches the home group whole as a new
pack whose members never change, and their army counts at the target if it can arrive while the
pack walks and works. The same switch closes every squad's join window (`joinwin.as`, C++
`IFighterTask::JoinOpen`): a fighter task is OPEN while it forms and COMMITTED from its launch (the
pool's promotion, a detach, ATTACK/RAID/BOMB tasks on their first update, a script launch with its
claimed roster admitted for 10 s, a siege when the script calls it ready) until it is home again;
`ITaskModule::AssignTask`, `ISquadTask::Merge` and every election over live tasks refuse a committed
one, and a refused ground unit takes a fresh pool from `DefaultMakeTask` while a flier stays held. Off,
the state is still kept and only counted (`apex: joinwin-stat`). Who a squad member shoots: the task picks ONE target (raid: nearest
economy when committed, else builders then highest influence; attack/defend: group worth) and
`ISquadTask::Attack` gives each member a ring move plus set-target on it (refused beyond the
member's own range, so out-of-range members fire at whatever the engine auto-targets); under a
comfight engage every member fight-walks with no set-target, so the engine's CMD_FIGHT attacks
the closest enemy. Under `TUNE_FOCUS_FIRE` (off) a ground squad in contact sets targets by enemy
damage removed per second of our fire, in lethal doses, set-target only (no moves), through both paths (`SquadTask.cpp`
`FocusTick`). `ai-military`, `ai-army-composition`, `fight-analysis`.

**Air** (`manager/air/`): the wing masses bombers and gunships, `nnair.as` decides WAIT or GO on
priced enemy economy cells against the AA in the way, fighters are elected for cover and air
superiority (`ai-air`). **Nukes** (`brain/nukes.as`): multi-volley salvos, target ranking,
anti-nuke accounting (`ai-nukes`). **Commander** (`market/comdecide.as`): WORK, FIGHT, TURRET or
RETREAT from what can reach him before he reaches safety; the opening order is a decision
(`opennet.as`) (`ai-commander`).

## The nets

Every decision head goes through **one policy network** (`market/policy.as`). The live state (36
inputs from the `NnState` vector) feeds a shared tanh layer; each head adds its own decision
features through a small layer of its own and outputs either a continuous value over the head's
range (cons, caps, escorts, defence amount, mass, odds, tier mix, AA, army split/commit/stage/
stand/retreat...), the odds of a fixed choice (team plan, tech, opening, posture, hunt, strike,
siege, raid, air, commander, defence site and type...), or a tilt over a list (the builder auction
and factory production). Head names and weights are in `policydata.as`.

- With all weights zero every value sits at the log-middle of its range and every choice at the
  rule's odds: the "middle" network. The nets always decide; the rule is only the middle.
- Weights reach a game from the file the per-AI start-script option apex_pw_file names (read by the
  DLL, not a modoption), else `PN_BEST` in
  `policydata.as`. `apex_policy=0` turns the network off.
- Training is **search, not regression**: `tools/randsearch.py` plays networks drawn around the
  middle (or annealed around a centre), one game each on rotating maps, sizes and opponents, every
  game its own seed, and re-tests winners up a 1/4/12/24-game ladder; `tools/weightmine.py` merges
  what winners share. State in `runtime/nn/`. The older regression trainer (`nntrain.py`, the
  `apex: nn*` decision rows, `decisions.py` labels) stays off while the search runs.
- Every decision logs a row (`apex: nn`, `apex: nnval head=...`, per-head tags) through
  `market/nnlog.as`, so any game can be read back.

## The plan net and the team

One team plan per ally team on a board our in-process AIs share (`ai.SetTeamBoard`): NORMAL, T3,
MISSILE, ARTY, MASS, AIR, RUSH, GREED, GREED_DEEP, TURTLE, each scaling the relevant gains. Under
most plans the **team push** runs: the turret line our army dies to is posted, every AI gathers
short of it, and all squads go when the team's power beats it. Allies co-build one gantry, share
upgrade work and constructor gifts, and may merge seats on a crowded map (switched off).

**Team air** (`air/teamair.as`, `TUNE_TEAM_AIR`, off): the team leader prices AIR against NORMAL
every 30 s from what has been seen (a square-law ground fight with and without the hold's army
spend, plus one air sortie through their known AA, blended with the scored strikes) and that
verdict is the plan rule. Under AIR every seat holds its bombers, gunships and escorts at one rally
behind our lines, production prices them on the team target's shortfall, and every seat launches
on the same board op when the gathered wing finishes the target (`docs/tunables.md`).

## The script API in brief

- Hooks: `AiInit` (init.as: which JSON basenames load; Legion and extra-unit files are added
  here), `AiMain` (once, after defs are known), `AiUpdate` (every 30 frames), `AiMakeTask` per
  manager (builder, factory, military: the core "what does this unit do next"), unit and task
  lifecycle hooks, `AiMakeDefence`, `AiGetFactoryToBuild`, `AiLoad`/`AiSave`.
- Globals: `ai` (defs, frame, team, `GetTunable`, team board, many bindings this repo added),
  `aiEconomyMgr`, `aiMilitaryMgr` (quotas are writable at runtime), `aiBuilderMgr`,
  `aiFactoryMgr`, `aiEnemyMgr` (enemy GROUPS only, LOS-slaved; no unit list, S50),
  `aiTerrainMgr`, `aiSetupMgr` (`GetModOptions`), the role/attribute/side maskers
  (`AiAddRole(name, base)` adds a role usable in `behaviour.json`).
- Tasks are built with `TaskB::` (builder), `TaskS::` (factory/static) and `TaskF::` (fight) and
  returned from `AiMakeTask`; null passes.
- Shared script one level up: `define.as` (`SECOND` = 30 frames, `MINUTE`), `unit.as` (masks),
  `task.as`, `side.as` (faction dispatch), `world.as` (`OnMap` guards, S9).
- `#include` is relative to the including file; only a global's initializer depends on include
  order (`as_scope.py`). The binding surface lives in `cpp/src/circuit/script/`; a binding in the
  source but not the deployed DLL fails to compile the variant (S3).
- `behaviour.json`: `quota.attack` is a power sum (not units or metal) used as a departure bar,
  an attrition floor and the defend pool's promotion bar; `quota.thr_mod` is a divisor (lower
  engages more), rolled per task when given as a range; the length of a `retreat` list changes its
  meaning (band or rolled range). `defence.*` radii feed only the engine's own placement, which is
  stubbed.

## Telemetry

Each AI writes `apex-t<team>.log` (`apex:` lines), merged by frame into the match's infolog by
`run_match`; the dev gadgets in `game-patches/gadgets/` add `[BARAI_STATS|ARMY|DEATH|POS|BUILD]`
census lines, the result line and the modoption-to-rules-param bridge for tunables
(`dev_tunables.lua`, S8). The tools in `working.md` read these.

## The game, briefly

- Metal comes from extractors on a fixed, small set of spots and from reclaim; energy from
  solar, wind, geo and fusion; converters turn ~60 energy into 1 metal, so late income is energy.
- The ladder the arithmetic produces: T1 extractors and generators; T2 constructors upgrading
  every extractor (about 4x a T1 extractor's metal, worth most while income is small); fusion
  once converters run and cheaper growth is gone (advanced solar returns faster); advanced fusion;
  T3.
- T3 is cheap or dear by its cost against income (gantry 8,400; Juggernaut 29,000): twelve
  minutes of a team's income at 40 m/s, seconds at 400.
- Team play: one player usually techs and shares advanced constructors; then everyone upgrades
  their own extractors.
- Winning a fight and holding the field is a large metal swing through reclaim; static defence
  trades well against an AI that keeps attacking it.

## What BARb does that beat us (measured 2026-09)

Read over 90 games: BARb's army stands at the middle of the map by minute 4 while ours sits at
home; it takes and guards the middle extractors; its income per extractor pulls away from minute
14 (converters early, first fusion and gantry earlier); it keeps half its army in one body; it
spends ~20% on static defence from minute 14 and finishes with T3. Its stock fight code is a
handful of decision points against our dozens, which is why the C++ fight layer was reverted.
