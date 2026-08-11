# What this AI does that stock BARb does not

One AI, built on BARb (CircuitAI). Everything here is a deliberate difference
from `BARb/stable`; anything not listed behaves as stock.

| variant | shortName | intent | best measured result |
|---|---|---|---|
| **apex** | `Apex` | team T2 rush in team games; stock behaviour with no allies | **1v1 vs `BARb:stable:hard`: 56-57 over 113 decided games (49.6%)**, 2026-08-10 |

`apexdef` ("hold ground, out-eco, finish with T3", 4-3 over 10 clean games) was
merged into apex and no longer exists as a separate variant.

`ai/ctl` (`ApexCtl`) and `ai/stk` (`ApexStk`) are measurement fixtures, not AIs
being developed: a frozen control for self-play A/B, and stock config + stock
script on the apex DLL to isolate what the DLL itself changes.

The 8v8 numbers that used to sit here (16-0 vs medium, 8-0 vs hard) were taken
on the `hard_aggressive` config base, which is no longer what apex ships. They
are not withdrawn, they are simply no longer about this build.

## 2026-08-11: the front line is aimed correctly and almost never built

Layer 2 (`manager/brain.as`, `manager/military/territory.as`,
`manager/builder/{events,mexwork,mexguard}.as`) plus a new measurement tool,
`tools/defence_pos.py`.

Every previous claim about defence placement counted TOWERS. This projects each
static defence onto the axis from its owner's base to the enemy's, from the
`[BARAI_POS]` gadget, so 0.0 is "in our base" and 0.5 is midfield -- which is
what "90% on the front line" actually asserts. Six games, 4v4 Comet Catcher,
+50, both Armada, 20 minutes:

| | apex | stock |
|---|---|---|
| defences per player | 9.4 | 36.0 |
| median position | 0.01 | 0.13 |
| past the quarter mark | 2% | 36% |

Instrumenting the request side separated aim from outcome, which the end-state
telemetry cannot do:

- the front line itself is computed correctly -- mean crossing 0.35-0.48 of the
  way to the enemy, 13 lanes, edge to edge;
- the Brain aims correctly -- 139 of 140 orders past 0.25 for one player,
  typically 0.38-0.70;
- **7 of 235 orders became towers.** Every failure was still on the books 90
  seconds later with NO builder on it. Only ~1 in 3 had a builder even 10
  seconds in.

Ruled out by direct A/B: the def (Pit Bull 680m/14,000e -> Beamer changed
nothing) and invalid ground (adding the `FindBuildSiteNear` snap every other
placement already does changed nothing).

Two real bugs found on the way, both fixed here:

- **`gDefTasks` leaked.** Defence tasks were registered in `AiTaskAdded` and
  removed only inside `AiTaskRemoved`'s `MEX` branch, comparing against tasks
  that can never be in that array. `DefenceTaskNear` therefore answered "already
  ordered" for every point the Brain had EVER asked for, retiring the whole front
  curve after one pass along it.
- **Empty ground counted as enemy ground.** `GetNetInflAt` is ally minus enemy,
  so land neither side has walked into reads exactly 0, and the crossing test was
  `<= 0`. Measured min lane fraction 0.08 -- the first sample -- on every 30
  second tick of two games: every unwalked flank put the front one step from our
  own base.

Also: a request is only "spoken for" if a builder is on it, and outstanding
orders now count against the front budget. The budget counted STANDING towers,
which cannot bind on a line where nothing finishes -- one player ordered 140 in
fourteen minutes once the leak stopped capping it by accident, and that
constructor time is the economy: metal produced fell 29,148 -> 19,445 per player
against an unchanged opponent. With the order-bound in, six clean games:

| | before (6 games) | after (6 games) |
|---|---|---|
| metal produced | 29,148 | **32,548** |
| mex upgrades | 2 | **3** |
| constructors (T1, peak) | 21 | **27** |
| static defence share | 16.2% | 15.5% |
| defence past 0.25 | 2% | 0% |

So the position is still not fixed. What is fixed is that it is now MEASURED,
and the failure is located: the orders are right and nobody goes.

**REVERTED, do not retry as-is:** having the Brain hand back an existing
unworked defence task from `AiMakeTask` instead of enqueueing a new one. It
looks correct -- our script hook is the only thing that elects a builder onto a
task -- but it corrupted the heap: 5 of 6 games exited `0xC0000374` at 5-20
minutes, against 0x0 for every game before and after. Whatever re-election needs,
it is not returning a registered task by handle from this path.

Unrelated, found while reading a crash log: `dev_team_income.lua` had been
failing to load since the front-publication removal (a stray `end`, then a call
to the deleted `publishFront`). Every run between those two commits had no team
income gadget at all.

## 2026-08-10: the Brain — rules propose Wants, one ranking decides

Layer 2 (`manager/brain.as`, `manager/brain/mix.as`) + layer 3 (one new binding).
Design and current state: **`docs/18-brain.md`**.

apexearth: *"what if we created a stack/list of all the things we wanted to do
and then properly prioritized them after in some process which has a better macro
view?"* and *"I want it to generally be a macro-view brain/logic center."*

The ladder in `builder/maketask.as` makes POSITION the only priority — the first
rule that returns a task wins, so importance is expressed by where a rule sits.
Measured: `CommanderMexGuard`, one line above `DefaultMakeTask`, took 162
constructor-picks against 4 mex upgrades in a single game.

A rule now states a **Want** — kind, value in metal/second gained, cost in metal
— with no side effects. `Brain::Decide` ranks the list and only then acts. Four
arms, each measured over 6 games vs medium on the same map and settings:

| arm | T2 mex share | metal | army |
|---|---|---|---|
| before | 13.5% | 4.61M | 1.28M |
| Wants + the moho | 17.3% | 4.72M | 1.51M |
| optional class ranked | 20.6% | 4.97M | 1.53M |

Two flaws the measurement found, both now structural:

- **value/cost alone hands the game to whatever is cheapest.** A Pinpointer at
  0.5 metal/s and ~800 metal outscored a silo at 4.0 and 8,100, and won every
  pick. Value decays per copy already standing (`value / (1 + have)`) — which is
  also the true shape, since the second Pinpointer is worth much less than the
  first. This is what bounds open-ended things instead of a hard cap.
- **Ranking must not displace the economy that pays for it.** With the optional
  class free to execute whenever it ranked first, picks rose 13 → 20 per batch
  and T2 mex share fell 17.6% → 15.1%. If an upgrade is in reach the constructor
  takes it; ranking decides order among optional things only.

Then two follow-ons, both from apexearth watching:

- **Both banks full means income is not the problem** (*"if we are full on energy
  AND metal, then we can probably decrease all of our eco priority"*): eco kinds
  score × 0.25 while sated, and a nano turret — banked metal back into units at
  ~7 metal/s of build power for ~300 — outranks every income Want in that state.
- **Nothing optional before T2 exists.** Watching a 4v4 at +25: *"something's
  going wrong this game where our guys are not going to t2."* The lead logged
  "building advanced plant coravp" fifty times with `haveT2` still 0 while
  constructors went to converters, nanos and reactors. Pre-T2 the only Wants
  proposed are the upgrade and an energy stall. This is the 2026-08-01
  displacement finding arriving through the Brain instead of through the ladder.

**The binding is new.** `CBuilderManager::EnqueueMexUp`
(`cpp/src/circuit/script/BuilderScript.cpp`) — apexearth: *"it seems weird that
we cannot control telling one of our advanced construction bots to upgrade a mex.
I as a player can do that, so the AI must have that same capability."* It always
could; a MEXUP task carries a metal-spot INDEX as well as a position, so the
generic `Enqueue` could not express it and no rule of ours could ask.

### The same inversion for production: `brain/mix.as`

apexearth: *"imagine we know that we want a certain mix of plain composition…
we set up our queues and over time our composition shifts towards the target."*

The motivation, 60 games across five team sizes vs BARb medium: we out-produce
1.10–1.76× and field 0.57–0.90× their army in every bracket. Production was the
weak axis. A target share of army metal per role is now stated (raider .30,
assault .30, skirm .15, riot .10, arty .08, AA .07) and each pick is "the role
furthest below target", one unit at a time so the composition converges.

- **Build power cannot be a share.** At 0.15 alongside the combat roles it never
  won: combat shares start at zero and are emptied by losses, so the largest gap
  is always a combat role. Measured in a 1v1 vs hard — our advanced constructors
  stayed at 1 from minute 14 to the end while hard reached 15 by minute 16, with
  the old constructor rules switched off for the claimed line. It is now a floor
  checked before the ratio, one con per 30 metal/s of income.
- **A claimed line belongs to the mix.** apexearth: *"make sure the old system
  doesn't interact with that factory and add its own things."* Two systems taking
  turns on one production line is worse than either alone. An owned line the mix
  cannot answer falls through to the engine's `DefaultMakeTask`, never to our
  floors.

The mix has **no head-to-head measurement of its own on record** — it landed
alongside the role-leak fixes. Tunables: `apex_mix`, `apex_mix_con_income`.

## 2026-08-09: Behemoths charge the front instead of walking round the map

Layer 3 (`AttackTask`, `SquadTask`) + layer 2 (`military/superguard.as`).
**Landed and smoke-tested only** — see the caveat at the end.

apexearth: "these are extremely powerful units which should be braver than usual
and attack enemy bases. They should spread out and not be too close which would
allow multiple of them to be d-gunned together in a single shot. Currently they
seem to be using our 'attack around the edge of the map' strategy — normally
this is good but behemoths are terribly slow so its less good for them, and also
less good for juggernauts. Straight front assault usually is preferred — can
still do a small allotment to that side attack sometimes."

The unit is `corjugg` (Behemoth, 20,000 metal); `corkorg` is the Juggernaut. A
scan of the shipped `behaviour.json` for `role: heavy` + `attribute: melee`
returns exactly three: `corjugg`, `corkorg` and `armbanth` (Titan) — Armada's
only one. **`armraz` is NOT one of them**, correcting a comment in
`AttackTask.cpp` that had asserted it since the engage-margin bypass landed;
`armraz` is `skirmish, heavy` with no `melee` attribute. That pair of tags
already keyed `CAttackTask::FindTarget`'s bypass, so it is now the single
definition of a CHARGER, shared by three call sites: `ISquadTask::IsChargeDef`.

**Watch runs must be Cortex.** apexearth, on the first watch run: "you're
starting us as arm and them as cortex soooo impossible for you to validate your
changes." `run_match.py` alternates factions by default; Behemoth and Juggernaut
are Cortex, and Armada's only charger is the Titan. Use `--sides Cortex,Cortex`.

Three changes, all keyed off it:

1. **The route.** `CAttackTask::Update` gave every squad the same threat-aware
   path query — `ATTACK_THREAT_MOD` 2 on the cost, `ATTACK_CEILING_MOD` 3 on the
   ceiling. That is the machinery that produces map-edge detours, and it is
   deliberate for ordinary squads. A charger now queries with `threatMod 0` (see
   `CPathFinder::GetThreatFun` — the cost becomes pure distance) and a ceiling of
   1e9, so the route is the short one through the front. `CHARGE_DIRECT_PCT` 80
   leaves one squad in five on the old route, which is the "small allotment to
   that side attack"; the roll is per task and taken once, so a squad does not
   change its mind mid-walk. `apex: attack path` now logs `charge=`.
2. **The spacing.** The commander's disintegrator carries `noexplode = true` and
   range 262 (read from `CORCOM.lua`), so the projectile does not stop at what it
   hits — everything on that line dies to one shot. `CHARGE_SPACING` 360 is now a
   FLOOR on a charger's separation, both travelling (`ActivePath`, where gaps are
   now per neighbour-pair so a charger's neighbours widen without blowing the
   whole squad apart) and in formation (`Attack`, applied AFTER the `maxDelta`
   cap — that cap shrinks with unit count, so the more Behemoths arrived the
   tighter they packed, exactly backwards).
3. **The hold is lifted for them.** `WantsSuperGuard` parks role-SUPER units on
   our own defence line; that was the answer to "we make T3 and then fail to
   defend with it", and it stays for `armepoch`, `corblackhy` and friends. A
   charger is exempt: its value is delivered by arriving somewhere of theirs, so
   the defence line is the one place it can never pay for itself.

**What is actually verified:** compiles, links, and a 12-minute 4v4 runs with
zero AngelScript errors and no crash, against a matched control DLL built from
HEAD. The behaviour itself is NOT measured, and this benchmark cannot measure it
— the same reason recorded under "the juggernaut charge is UNVALIDATED" below:
at 4-9 metal/s per team no 20,000-metal unit is ever built. It needs a hosted
game or a heavily bonused one.

**One trap this cost an hour on.** The first build of these changes crashed at
frame 0 with an access violation and no AngelScript error. The code was fine:
`tools/sync_cpp.py apply` rewrites all 42 mirrored files, and a build interrupted
by a closed pipe (`docker ... | grep | head`) left a truncated `ThreatMap.cpp.obj`
that still linked. Never pipe a build through `head`; deleting the object and
rebuilding clean fixed it.

## 2026-08-09: units walled in by our own buildings get a way out

Layer 3 (C++ bindings) + layer 2 (`military/unblock.as`). **Not yet measured, not
yet run** — landed as code only.

apexearth: "we need to detect units that are blocked and reclaim cheapest
buildings we can to unblock their movement. This often happens in late game
where units are completely locked into an area and cannot move outside. Usually
theres just 1 or 2 buildings in the way."

Why nothing caught it: CircuitAI's only reachability test is
`CTerrainManager::CanMoveToPos`, over the areas `CTerrainData` computes from
**slope and depth**. Structures are not in that model at all, so a pocket sealed
by four solars is open ground to every routing decision in the AI — the unit is
handed a destination it cannot reach and keeps trying. Nothing enumerates
friendly units either, so "who has not moved" could not be asked.

Three new bindings, all thin:

- `ai.GetPathLength(unit, to)` → `CAICallback::GetPathLength` →
  `pathManager->RequestPath`. The engine's path manager reads the synced
  blocking map, buildings included; it is the only oracle here that can see a
  pen. Returns -1 when there is no path. `pathType` is cached per def because
  `UnitDef::GetMoveData()` allocates a wrapper the caller must delete.
- `ai.GetOwnStructsNear(pos, radius)` → our finished structures, any def. The
  existing `GetOwnUnitsOfDef` needs a def, and a per-faction name list is the
  parity trap that has eaten this repo repeatedly.
- `CCircuitDef::IsMex()` / `IsBuilder()`, so the script can refuse to eat a mex
  or a factory without naming them.

Detection is three gates, each cheap enough to pay for the next: motionless for
45 s (a position read); ≥ 4 structures of ours within 700 elmos (one array walk);
and every one of 8 rays out to 700 elmos failing a path query (the expensive
part — one unit at a time, at most every 3 s). Standing still alone is not
enough: a defend squad on the line is motionless for minutes and is exactly
where it should be. Failing *every* exit is what separates the two.

A path that reaches the ring is at least the straight line long, and a search
stopped by a wall comes back **short**, not long — so both bounds are failures
and the short one is what a pen actually produces. The ray that got furthest is
the thinnest part of the wall; the cheapest structure of ours in that lane
(within a 96-elmo corridor, never a mex, never a builder, never above 800 metal)
is what gets reclaimed, at most one per 10 s, then the unit is re-checked 15 s
later.

The ≥ 4 structures gate is what keeps this off terrain-locked units: an island
or a bay fails all 8 rays too, and reclaiming cannot fix either. `apex_unblock=0`
turns the whole thing off.

**What it costs, since that is the question this repo keeps getting wrong:** it
spends constructor time, on a reclaim that returns metal. The rate limit is the
control — one order per 10 s per player, and only for a unit that has failed
every test above.

## 2026-08-09: the AI desynced multiplayer by asking the engine for a path

Layer 2 (AngelScript), `manager/military/unblock.as`. New tool,
`tools/run_netmatch.py`. New widget, `game-patches/widgets/dbg_desync_alarm.lua`.

apexearth desynced twice in hosted games. Both times only HIS client was named
(`Sync error for apexearth in frame 9139`), permanently from ~5 minutes, with no
error logged anywhere and every player's map and mod checksum identical -- so
`BAR.sdd`, the dev gadgets and `game-patches` were all irrelevant, and the games
were played on the rapid packages like everyone else's.

The asymmetry: he was the only one running the AI. Every `[AI]` block carries
`Host=<player>`, so AI code executes on ONE machine and the other clients only
replay its netted orders. Anything the AI does that touches engine state
*directly* therefore happens on one machine.

**`ai.GetPathLength` is such a thing.** `unblock.as` used it to tell a penned
unit from a parked one -- eight rays, every 3 seconds. It reaches
`CAICallback::InitPath` -> `QTPFS::PathManager::RequestPath(..., synced=false,
immediateResult=true)` -> `QueueSearch`, which runs a real A* inline and creates
entities in the SAME global `entt` registry (`QTPFS/Registry.h`) as the synced
paths. QTPFS's own `ExecuteQueuedSearches` warns "Remember: Do NOT impact this
group while the background tasks are running!" about exactly that registry
group. It is not the synced RNG: `grep gsRNG rts/Sim/Path/` is empty.

Reproduced with `tools/run_netmatch.py`, which runs a host process and a peer
process against each other on one machine -- a single-process match cannot
desync, which is why the benchmark never saw this in months of running.

| configuration | sync errors |
|---|---|
| stock BARb vs stock BARb | none |
| `ApexOrd:ord` (older DLL + older scripts) | none |
| current DLL + `ord`'s scripts | none |
| apex, unblock ON | 44 @ f13018, 14 @ f19019, 37 @ f14167 stressed |
| apex, `apex_unblock=0` (seeds 11 and 12) | none |
| apex, rewritten rule | none, twice |

The current-DLL-with-old-scripts run is what proved it was the game-side layer:
today's whole C++ delta is exonerated. Binding usage then named the file --
`GetPathLength`, `GetOwnStructsNear` and `IsMex` are the only bindings apex's
scripts use that `ord`'s do not, all three from `unblock.as`, and only the first
mutates anything.

Two things did NOT hold up and are recorded so they are not re-argued:

- **No dose-response.** Six times the probe rate and a ninth of the stillness
  threshold gave 37 errors at f14167 -- no earlier, no heavier. The on/off
  switch is repeatable; the probe *count* driving it is not shown.
- **The first `apex_unblock=0` test was void**, because the name was missing
  from `NAMES` in `dev_tunables.lua` and the modoption was silently dropped --
  the trap that file's own comment warns about. And "the rule never fired" was
  wrong: the log line is on the reclaim ORDER, while the path probes run
  silently. Absence of that line proves nothing about the engine calls.

**The rewrite** (apexearth's design): order the unit to walk out of the ring and
see whether it does. A parked defender obeys; a walled-in one cannot. Issuing a
move is a netted command and reading a position is a read, so nothing executes
on the host alone. Direction comes from bucketing our own structures into
eighths, which is the same "thinnest part of the wall" reasoning the rays gave,
by arithmetic. It is also a better test: eight rays can miss the gap the engine
would route through, and a successful query does not prove the unit will
traverse it.

**Its accuracy is NOT established.** Of the three firings measured, all three
were commanders and all three were wrong: the commander stands in the middle of
the base by design and is re-tasked every few seconds, so the probe order is
overridden before it steps and "did not move" reads as "cannot move". Guards
added -- never test a unit on a BUILDER task, never test the commander, and
require two failed orders. After those, twelve minutes produced zero firings,
which is zero false positives and zero true ones. A run that catches a real pen
is still owed; a 12-minute 4v4 rarely walls anything in.

## 2026-08-09: the AI crashed the engine because C++ deleted tasks the script held

Layer 3 (C++), `module/EconomyManager.cpp` and `task/builder/BuilderTask.cpp`.

Two watched 8v8s died mid-game with `Access violation (0xc0000005)` at
`Exception Address: 0x0`, and the engine's own note — *"This stacktrace indicates
a problem with a skirmish AI"* — with every frame inside our `SkirmishAI.dll`.
Symbolized against the unstripped build (see `docs/06-building-the-dll.md`):

    circuit::IRefCounter::Release()          RefCounter.cpp:29   <- delete this
    asCContext::ExecuteNext()                as_context.cpp:3234
    circuit::CScriptManager::Exec()          ScriptManager.cpp:230
    circuit::ITaskModuleScript::MakeTask()   TaskModuleScript.cpp:40
    circuit::CBuilderManager::AssignTask()   BuilderManager.cpp:786
    circuit::CIdleTask::Update()             IdleTask.cpp:71

`RefCounter.cpp:29` is `delete this`, and the null PC is that call dispatching
through a freed vtable: a use-after-free that surfaces when AngelScript drops a
handle, not when the object dies.

`IUnitTask` derives `IRefCounter` and is registered `asOBJ_REF` with
`asBEHAVE_ADDREF`/`asBEHAVE_RELEASE` (`InitScript.cpp:599-601`), so a script
handle owns a counted reference. Three sites freed such an object with a bare
`delete`, bypassing that count:

- `CEconomyManager::UpdateFactoryTasks`, the discard branch. `PickNextFactory`
  enqueues the factory task INACTIVE, so it never enters `updateTasks` and the
  module never frees it — but `CBuilderManager::Enqueue` fires `TaskAdded`
  either way, which is where `joinbuild.as` registers the handle
  (`JoinEligibleType` includes FACTORY; `JOIN_MIN_COST` is 200 against a
  factory's thousands).
- `~CEconomyManager`, the same `delete factoryTask`.
- `~IBuilderTask`, `delete nextTask` — `nextTask` chains also come from
  `Enqueue`, so build_chain children and defence rows are script-visible too.

The discard branch now calls `builderMgr->AbortTask()` then `ClearRelease()`.
`AbortTask` runs the normal teardown, so `TaskRemoved` lets the script drop its
handle and `CBFactoryTask::Cancel` undoes the `AddFactory` its ctor did — which
**removes the apex workaround that was there**: the manual
`factoryMgr->DelFactory(facDef)` existed only because a bare delete skips
`Cancel`. The other two sites `ClearRelease()`, so the object outlives its owner
until the last handle goes.

Verified by replay: the crashing configuration — Flats and Forests v2.2, 8v8,
`--handicap 100`, seed 5703, which died at frame 32265 (17.9 min) — ran the full
45 minutes, zero AngelScript errors, with `con-join` firing 585 times. Note the
same build carried other in-flight C++, so only the not-crashing is attributable
here.

This is a latent upstream bug that only bites an AI whose script holds task
handles. Ours has to, for `joinbuild` and `mexguard` to work at all.

## 2026-08-09: the front line gets per-player sectors, and defenders stop garrisoning minute 5

Layers 2 and 3, `manager/frontline.as` and `module/MilitaryManager.{cpp,h}`.

apexearth: "I routinely see our units patrolling behind our own allies bases.
meanwhile, the enemy is attacking one of our frontline bases and our huge army
isn't there to protect it."

Read from source, not yet measured. Three defects compounding, all of them the
same shape — a team-wide answer used where a per-player one was needed, and an
answer computed once and never revised:

1. **The front collapsed onto one ally.** `Front::Scan` builds territory from
   `GetAllyInflAt`, which is ally-WIDE, so every AI on the team computes the same
   perimeter. It then kept only the arc within `FRONT_BAND` (3000) of the team's
   single closest approach to a single pooled enemy centroid. That arc belongs to
   whichever ally happens to sit furthest forward, so every other player's
   frontage was demoted to back line and every AI's `FrontNear(ourHome)` anchored
   on the same few cells — behind that ally's base.
2. **A flank base had no front at all.** FRONT vs BACK was
   `(cell - teamCentroid) · (enemyCentroid - teamCentroid)`. The team centroid is
   identical for every AI, so a player on a flank had its whole border projecting
   backwards along the team bearing and classified BACK.
3. **A DEFEND task's stand position was frozen at construction.** `Enqueue` sets
   it from `GetDefenceStand()` — the tower cluster nearest our lane at that
   instant — and the repositioning code in `UpdateDefenceTasks` had been
   commented out, so a garrison formed in minute 5 still held minute 5's ground
   at minute 40, and `CDefendTask::Start` walked every newly built unit there.
   Separately, a squad that found no target called `FillFrontPos`, which offered
   the pathfinder our own tower positions and never the front or the fighting.

Fixes:

- Each AI publishes its home on the blackboard (`apexHomeX`/`Z`) the same way the
  enemy bearing is already pooled, and a front cell belongs to the ally nearest
  it — a Voronoi split of the line over the team. Enemy-facing is measured from
  our OWN home for our own cells, and the `FRONT_BAND` trim is applied per sector
  rather than once for the team. `FrontNear` and `FrontChoke` take our sector
  first, falling back to the team line only for a player that owns no front cell.
  With no ally home published (a 1v1) the whole line is ours, which is the
  pre-change behaviour.
- `CMilitaryManager::GetGuardAnchor` — where we are actually bleeding
  (`GetAttackHotspot`, gated on the position not being enemy-dominated), else the
  front. `FillFrontPos` returns it as a STRICT single candidate rather than one
  of a set, because a multi-candidate path query always picks our own tower
  cluster over the front. `UpdateDefenceTasks` re-anchors every DEFEND task that
  has no target of its own to the same position each pass.

**Known side effect, deliberate but untested:** `CDefendTask::Update`'s
`FRONT_HOLD_RANGE` rule refuses to promote a DEFEND task to ATTACK while it sits
within 1800 of the front and holds under 2x `maxPower`. Defend tasks were rarely
on the front before, so that rule rarely fired; now they are anchored on it, so
it fires as designed and the mass needed before walking out roughly doubles. That
is the direction of "we attack too much and hold too little", but it is a second
behaviour change riding along and should be watched for a stalled offence.

Costs no constructor time — this is the "stop something wrong" class, not a new
rule that enqueues work.

## 2026-08-09: a raid that runs out of targets presses on instead of walking home

Layer 3 (C++), `task/fighter/RaidTask.{cpp,h}`.

apexearth: "after we do an attack raid on enemy mexes we often just turn around
and walk home to do nothing... in reality we could usually go further to take out
many more mexes."

Read from source, not measured: `CRaidTask::FindTarget` can only see enemies
already in `CCircuitAI::GetEnemyInfos`, i.e. things we have had radar or LOS on.
The mex field one screen beyond the one we just cleared has never been seen and
so does not exist to the raid. With no target, `Update` falls through to
`FallbackRaid`, whose destination is one of exactly two things:

- `CMilitaryManager::GetScoutPosition`, which only returns clusters that are
  unqueued, unfinished by us AND below `THREAT_MIN` — the quiet ground, which
  after a successful raid is behind the party; or
- a uniformly random map position (`rand() % width`), set in the constructor and
  again in `OnUnitIdle`.

Both are, on average, backwards. That is the walk home.

Added `CRaidTask::FindOnwardSpot`: the nearest metal spot that is at least
`PRESS_STEP` (400) closer to the enemy CENTROID than the party currently stands,
reachable by the leader's area, within `PRESS_MAX_LEG` (4000) and carrying less
threat than the party's own power. `FallbackRaid` uses it in place of the
scout/random destination — but only on the branch where the party is NOT already
outmatched where it stands; the existing "threat here exceeds us, go elsewhere"
escape is untouched, so this cannot push a losing party further in.

Measured against the enemy centroid rather than our own base deliberately: that
keeps arriving at their economy whichever flank the party came in on, with no
per-map special case. The per-spot threat test is what stops it walking a raid
into the enemy army — an undefended spot is worth approaching blind, a defended
one is not.

Spends no constructor time, so by the 2026-08-01 composition rule this is in the
cheap-to-try category rather than the displacing one.

Logged, rate-limited to 20s: `apex: raid presses on to (x,z), N further in`.

**Not yet measured.** Built and patched; deploy was blocked by a running BAR.

## 2026-08-09: T3 heavies hold the defence line instead of walking out alone

Layer 2 (AngelScript), `manager/military/superguard.as` (new),
`manager/military/hooks.as`, `manager/military.as`.

apexearth: "we make T3 units but then fail to really defend ourselves using that
T3... they're often the toughest things in the game so they should be standing
in front of our T3 defense helping to defend the base."

`CMilitaryManager::DefaultMakeTask` has exactly one branch for the SUPER role,
and for a **mobile** super it is `Enqueue(TaskF::Common(ATTACK))` -- a brand new
`CAttackTask` holding that one unit, the frame it finishes. So a 29,000-metal
Korgoth crosses the map by itself, and the next one gets its own task and
crosses by itself too. Nothing routed them home and nothing grouped them.
`Military::WantsMassing` excluded `SUPER` explicitly, so they fell through to
exactly that branch.

They now go into a DEFEND task that never promotes. Four mechanisms make that
hold, all read out of CircuitAI:

- `UpdateDefenceTasks` rewrites `maxPower` every 5 s to
  `max(minAttackers, PreMaxGroupThreat)` -- but only for a DEFEND task whose
  `promote` is ATTACK. Ours is RALLY, so it is skipped and the holding power
  survives.
- `CDefendTask::Update` promotes on
  `(attackPower >= maxPower) || !GetTasks(check).empty()`. Nothing in CircuitAI
  ever enqueues a MELEE task, so the second clause is dead; `SUPER_HOLD_POWER`
  puts the first out of reach.
- With no target inside our own influence, `CDefendTask` falls back to
  `CMilitaryManager::FillFrontPos`, which returns the **defence points of the
  metal cluster nearest our lane toward the enemy**. That is where the squad
  parks: on our own defence line, facing them.
- `CDefendTask::CanAssignTo` requires an equal `promote`, so this squad merges
  only with itself and never with the ATTACK-promoting massing pool.

`promote` is RALLY rather than a type that can never fire, so if the holding
power is ever reached the failure mode is "they attack together"
(`CRallyTask` carries `maxPower` 1 and converts the group into one ATTACK task)
rather than "they stand still forever".

Which units: role SUPER, or cost >= `SUPER_COST` 7000. The role alone is not
enough for faction parity -- Armada and Cortex tag `armbanth`/`armthor`/
`corkorg`/`corjugg` "super", and Legion tags **none** of its gantry units that
way (`legeheatraymech`, 23,500 metal, is only "heavy"). The cost key has to
clear the T2 heavies: `corsumo` 2,200, `armvang` 3,300, `legpede` 5,500 are all
T2, against `legeheatraymech` 23,500 and `legeshotgunmech` 7,000.

The hold is released for a declared team push and for the killing blow, read
when the unit is **tasked**. A super already holding stays holding: nothing in
the ~405 bindings can move a unit out of a task it has been assigned to, so
either the release is read at assignment time or it lives in C++. That is the
known cost of doing this in layer 2, and it is the first thing to revisit.

Tunables: `apex_super_guard` (default 1; 0 restores stock routing, one solo
attack task per super) and `apex_super_cost` (default 7000).

**Mechanism verified, effect NOT measured.** Zero AngelScript errors, variant
loaded, and the branch was exercised end to end -- 29 holds, no crash, no errors
-- but only by forcing `apex_super_cost=100` so ordinary units took it. It could
not be measured on its own terms because **this benchmark never builds a super
at all**: see the finding below.

### Finding: we build gantries and produce nothing from them

Measured 2026-08-09, Comet Catcher, 2v2 Cortex mirror, +300% handicap, 32
minutes -- an economy far past the point where T3 is affordable
(`metalProduced` 438,979 on the winning side).

Our side built **four gantries, 33,600 metal, and zero units out of them**:
`corgant:33600` appears in `allBuilt` and `corshiva`/`corkorg`/`corjugg` never
do. Stock BARb on the other side fielded `corkorg:87000` by minute 24 and
`mT3=259000` by the end, against our `mT3=30800` -- which is the gantries
themselves and nothing else. The same shape appeared in the Armada game:
`armshltx:31600`, five gantries, no `armbanth` or `armthor`.

The log also calls the gantry a T1 lab (`apex: T1 lab on field: corgant`) and
reports `conbranch fac=corgant ... roleDef=NULL`, so whatever picks what a
factory builds is not recognising it. Not yet diagnosed; it is a separate
change from this one.

## 2026-08-09: keep building silos while both banks are over 80%

Layer 2: `script/hard_aggressive/manager/builder/statics.as`.

apexearth: "when we are full on metal and energy (>80%) we should keep making
more nuke launchers."

The unlimited cap already existed but keyed on `isMetalFull` alone, and it was
the only thing that got lifted -- `NukeSilo`'s income bars (`eInc >= 2500`,
`mInc >= 150`) and its 50%-of-storage bank test still applied underneath it, so
a full bank on a modest income still built exactly one. Those bars are a proxy
for "can we afford one without starving the rest"; both banks sitting over 80%
answers that directly, so in that state the proxy is skipped rather than allowed
to veto. `NukeCap` now keys on the same both-banks state.

Energy is read at the same 0.8 as metal rather than through
`aiEconomyMgr.isEnergyFull`, which is 0.88. A silo is 8,100 metal and 90,000
energy, so energy is the half that decides whether the next one is really free,
and metal-full alone is not enough to say it is.

Also fixed while here: outstanding was `asked - standing`, which reads a
DESTROYED silo as one still in flight and blocks every rebuild for the rest of
the game. It is now `asked - peak-standing`, so a loss lowers standing and the
cap lets the replacement through.

One at a time is unchanged -- the cap is on how many may STAND, not how many are
in flight, so silos are still serialised and assisted.

Verified: deployed, 0 AngelScript errors, variant loads. **The behaviour is not
measured** -- the standard benchmark never reaches `eInc 2500`, let alone both
banks at 80%, so confirming it needs a long bonused or hosted game. Note it sits
after `SurplusGantry` in the pipeline, which fires on the same full bank, so
gantries are still bought first while `WantMoreGantries` holds.

## 2026-08-09: nuke the army massed on our own border

Layer 3: `cpp/src/circuit/task/static/SuperTask.cpp`.

apexearth: "if there is a huge mass of enemy army right on our border we should
prioritize nuking that army."

That target was previously unreachable, twice over. `isTargetValid` rejected any
group with `GetAllyInflAt(pos) > INFL_EPS` -- ally influence is nonzero within
range of our own armed units and defences, so "on our border" is exactly the
region that test excluded. Anything that survived it then had to clear a second
veto: no ATTACK/AH/AA squad leader within `1.25 * AOE` of the group, and with
`corsilo` at AOE 1920 that is a 2400-elmo exclusion around our own army -- which
is by definition sitting on the line the enemy is massing against. A silo could
shoot an enemy base or an army crossing neutral ground, and nothing else.

Both vetoes are now replaced, for that one case, by a value trade. A group
counts as a border mass when its MOBILE cost (`cost - roleCosts[STATIC]`) is at
least `ARMY_MASS_MIN` 4000 metal and our influence reaches its position. For such
a group the ally-influence and squad-proximity tests are skipped, and instead
`FriendlyCostIn` sums the metal of every friendly unit within one AOE of the
impact point; the strike is allowed only if the enemy mobile mass exceeds that by
`BLAST_TRADE` 3x. The influence map cannot price this itself -- it carries
range-weighted danger, not cost.

Priority is a scoring term, not an override: `GroupScore` adds
`ARMY_MASS_WEIGHT * mobileCost` (2.0) for a border mass, which makes a massed
army on our ground outrank a base of equal metal, while a base still beats a
loose group of the same size anywhere else.

The same relaxation applies to every unit CSuperTask drives, so long guns
(Bertha, Buzzsaw, Ragnarok) get it as well; their smaller AOE shrinks the
friendly-cost radius with them.

Verified: compiles and links clean, 0 AngelScript errors, variant loads.
`apex: super fire` now logs `mobile=` and `border=` so the border case can be
counted rather than inferred. **The behaviour itself is not yet measured** -- a
silo needs `eInc >= 2500` and `mInc >= 150`, which the standard benchmark never
reaches, so confirmation needs a long bonused game or a hosted one.

## 2026-08-09: help the identical building already started, instead of starting a second

Layer 2: `script/hard_aggressive/manager/builder/joinbuild.as` (new),
`builder/maketask.as`, `builder/events.as`, `builder.as`.

apexearth: "we tend to have multiple construction bots all decide to make
identical buildings at the same time... if they're about to make a building of a
certain type but one is already being made we'll instead choose to help the one
which is already being made" -- and, on the same behaviour: "this has to include
buildings where placement is pending (constructor still walking over to start
it)."

Nothing in the engine prevents it. `IBuilderTask::CanAssignTo` refuses a second
builder on ONE task once that task has enough build power
(`cost.metal < buildPower.metal * GetGoalBuildTime(income)`), but it has no
opinion about a second TASK for the same def -- and the queue legitimately holds
several, since `MakeEconomyTasks` and the build chains enqueue independently.
`MakeBuilderTask` then hands two idle constructors two different tasks for the
same building and each walks off to its own site.

`JoinDuplicateBuild` runs on the offer `DefaultMakeTask` just made, immediately
after `ExpansionAlwaysWins` and ahead of all optional spending. If the offer is a
fresh task (no assignees) for a def that another live task is already working, it
returns that other task instead. The pending-placement case is covered by
construction: `IBuilderTask::AssignTo` runs the moment the builder is given the
job and the entire walk happens before a nanoframe exists, so `GetUnits()` is
non-empty for the whole window -- a check on standing structures or on
`buildDef.count` would see nothing there.

This is a redirect, not a spend: the duplicate task stays queued and is built
later by whoever is idle then, so the rule serializes work rather than creating
any. That is why it sits ahead of `OptionalWork` despite the 2026-08-01 finding.

How many builders one task may hold is derived from economy, not fixed --
apexearth: "if something is 3000 metal to create and we make ~100 metal per
second then probably we'd be happy to put 5 or more builders on it to get it
built fast". `cost/income` is the seconds of whole income the building costs; a
rich player is build-power-limited and extra lathes are free speed, a poor player
is metal-limited and they just share the same trickle. `builders =
JOIN_AFFORD_SECONDS / (cost/income)`, `JOIN_AFFORD_SECONDS = 150`, clamped
[2, 8]: 3000 at 100/s is 30 income-seconds and gives 5; at the benchmark's 10/s
the same building gets the floor of 2.

Scope is deliberately narrow. Not MEX/MEXUP/GEO/GEOUP -- two of those are two
different spots, and stacking constructors on one is what `SaferMex` already
refuses. Not DEFENCE -- two towers in two places are both wanted. Not below 200
metal, where solar (155) and wind (43) are meant to be built several at once and
serializing costs more walk time than it saves.

Measured only as wired-up so far: 25-minute 4v4 on Comet Catcher, zero
AngelScript errors, variant loaded, `con-join` fired 3 times (`armck ->
armadvsol`, cap 7 at that income). Not yet judged on composition against a
control, which per the 2026-08-01 finding is the test that matters.

## 2026-08-09: mobile AA is all-or-nothing, and it never travels with the army

Layers 1 and 2: `config/hard_aggressive/factory.json`, `factory_leg.json`,
`behaviour_leg.json`, `script/hard_aggressive/manager/military/hooks.as`.

apexearth: "at some point recently i said we made too many AA units, in recent
games im feeling like we don't make enough... our armies often need at least 1
or 2 AA units attached to them but theres a lot of times I don't see that.
previously I'm seeing squads of 8 aa units very early in the game."

Both halves of that are the same mechanism. Read from
`FactoryManager.cpp:1706` (`GetFacTierProbs`) and `:1658`:

```
allyAACost = militaryMgr->GetRoleCost(AA) * allyTeam->GetAliveSize();
isAir      = enemyTotalAirCost > allyAACost;
tiers      = isAir ? airTiers : isWaterMap ? waterTiers : landTiers;
...
if (probs[i] > 0.f) { prob = RoleProbability(bd) * (probs[i] + reWeight); }
```

Three consequences, none of them visible from the config:

- **A unit with weight 0.00 in the selected terrain block is not a candidate at
  all.** `probs[i] > 0.f` gates entry to the candidate list, before the response
  system is consulted. Conversely `prob = isResp ? prob : probs[i]` means the
  raw weight is the floor when the response gate is shut -- so the terrain
  block, not `response.json`, is what decides whether any AA exists.
- **`isAir` is a bang-bang switch, and the ally-size multiplier makes it
  hair-trigger.** In an 8v8 our own AA metal is multiplied by 8 before the
  comparison, so one or two AA units per player flip the whole team back to the
  land block. Then, in the land block as shipped, **every T1 ground factory
  carried 0.00 AA at tier0 and tier1** -- `armjeth`, `armsam`, `corcrash`,
  `cormist` -- and 0.01-0.05 above that. Production stops dead until the enemy's
  air outgrows ours again, at which point the air block (0.2-0.3) turns it back
  on hard. That is the squad of eight and the drought, alternating.
- **Legion could not build mobile AA at all.** `legaabot` and `legadvaabot` were
  0.00 in *every* tier of *every* terrain block of `leglab`, `legalab` and
  `legamphlab` -- air block included, so the response path could not rescue it
  either.

Two unit defs were mis-roled in `behaviour_leg.json`. Both carry
`onlytargetcategory VTOL` and cannot fire on a ground target:
`legrail` (Lance, 240m) was roled `skirmish`, so it counted as ground power and
was sent to fight ground; `legvflak` (Charon, 470m) had **no entry at all**, so
it took the default role and never counted toward the AA response budget --
while sitting at weight 0.05 in `legavp`.

Changes:

- A floor in the **land and water** blocks of every ground, hover and amphib
  factory: 0.06 for a T1 plant, 0.05 for a T2 one, applied as
  `max(existing, floor)` so nothing was lowered. 102 weights raised across the
  two files. At a land-block total of ~1.3-1.9 that is a 3-5% share -- one or
  two escorts on an army of forty, which is what was asked for, not a squad.
  The air blocks are untouched: "enemy has a ton of air" already answers itself
  there.
- Legion's zeros filled in on the same rule, plus 0.15 in its air blocks to
  match what Armada and Cortex already had.
- `legrail` and `legvflak` roled `anti_air`.
- **Ground AA now masses with the army** (`Military::WantsMassing`). Stock routes
  the AA role to `FightType::AA`, and `CAntiAirTask`'s constructor seeds its
  destination with `rand() % terrainWidth/Height` -- a random point on the map.
  It also merges only same-def units (`CanAssignTo` compares against the
  leader's `circuitDef`), so it accumulates one single-type blob instead of
  spreading escorts along the front. Aircraft keep the stock routing: `Air::`
  owns them, and a fighter parked in a ground squad intercepts nothing.

**Not measured.** A 4v4 benchmark cannot reproduce the condition: it stays in
tier0 on 4-9 metal/s per team, and with the enemy flying it sat in the *air*
block for most of the game, where the land-block floor never binds. Changed vs
control on the same seed read 24 vs 28 mobile AA built -- and the opponent's own
AA moved 14 vs 1 between the two runs, which is the run-to-run divergence
CLAUDE.md records for `FixedRNGSeed`, not an effect. What the run does confirm:
zero AngelScript errors, variant loaded, AA still built and still ramping on the
player facing air (1-2 by minute 16, 10 by minute 24 on the pressured player).
The claim to test in a hosted 8v8 is that the drought between ramps is gone.

## 2026-08-09: long guns stand at 90% of their range instead of 40%

Layer 3 (C++), `task/fighter/FighterTask.{h,cpp}` and `task/fighter/SquadTask.cpp`.

apexearth: "I see units like the sniper standing far too close to enemy armies.
Let's make sure units like that stand at around 90%+ of their max range."

The standoff position is computed in exactly two places, and both discount by
`RANGE_MOD`:

| path | standoff | Sharpshooter |
|---|---|---|
| `IFighterTask::Attack` (solo), `FighterTask.cpp:206` | `min(minRange, losRadius) * RANGE_MOD` | **364** |
| `ISquadTask::Attack` (per range-tier row), `SquadTask.cpp:424` | `minRange * RANGE_MOD` | 720 |
| `ISquadTask::Attack` row 0 when the target is unseen, `:429` | `min(minRange, losRadius) * RANGE_MOD` | 364 |

`armsnipe` carries weapon range **900** against `sightdistance` **455**, so the
solo path stood it at 364 -- **40% of its own reach**, inside almost everything
that shoots back. The `losRadius` term, not `RANGE_MOD`, is the dominant cause:
it is the binding minimum for every gun that outranges its own eyes.

Two changes:

- The solo path now clamps to `losRadius` only when the target is **not** in
  radar or LOS, which is what `ISquadTask::Attack` already did for its scouting
  first row. A unit that can already see what it is shooting keeps its full
  standoff. Gated on `apex_los_standoff` (default 1; 0 restores the old
  unconditional clamp).
- `RANGE_MOD` 0.8 -> 0.9, reachable at runtime as `apex_range_mod`, which was
  already a registered name in `dev_tunables.lua` whose reader was removed by
  the 2026-08-10 fighter-task revert.

Sharpshooter standoff becomes 810 on both paths, 90% of 900, as asked.

The `* 0.9f` constants in `AttackTask.cpp:251`, `DefendTask.cpp:229`,
`RaidTask.cpp:260` and `ScoutTask.cpp:167` look like this and are **not**: they
are vertical reachability filters (`ePos.y - elevation > weaponRange`), never
positions. `AntiHeavyTask.cpp:294` -- the sniper's own task -- uses `GetMaxRange()`
for the same height test and computes no standoff of its own; it inherits the
solo path above.

Base range stays `GetMinRange()`, deliberately: a multi-weapon unit still closes
to its shortest gun. Switching that to `GetMaxRange()` is a separate axis and
would confound this measurement.

**NOT MEASURED YET.** This is the same territory as the 2026-08-10 revert
("the standoff/orbit carries a real part of it. That is the pair to re-land
first, with a measurement"), which is why both halves are tunable-gated: the
full control arm is `--modoption apex_range_mod=0.8 --modoption apex_los_standoff=0`,
so the A/B needs no rebuild and no redeploy.

Config-layer alternative, rejected: `behaviour.<unit>.range` is a real JSON key
(`FactoryManager.cpp:491-503` -> `CCircuitDef::SetRange`) and does feed this
formula, but only the scalar form raises `minRange`, it overwrites `maxRange`
for every consumer that reads it (threat, height filters, path reachability),
and it cannot reach the `losRadius` clamp that is the actual cause.

## 2026-08-09: The ally-mex upgrade also CLOGGED the mex_up slots — fixed in C++

Layer 3 (C++), one line in `CEconomyManager::UpdateMetalTasks`'s upgrade
predicate, plus the tracked copy in `cpp/` and
`game-patches/circuitai/0003-cumulative.patch`.

The veto below stopped the constructor walking, but not the real damage.
`CBMexUpTask`'s constructor calls `SetUpgradingMexSpot(spotId, true)` and the
task counts against `mex_up` (4 in our `economy.json`, same as stock `hard`). An
ally-spot task therefore **holds one of the four upgrade slots and marks that
spot as already-being-upgraded**. Before the veto it self-cleared, badly: a
constructor took it, `Execute` failed, `AbortTask` freed the slot — and the walk
was the visible symptom. With the veto, nothing executed it, so nothing aborted
it, and the slots filled permanently.

Measured, `expand-diag` pool depth for build type 14 (MEXUP):

| | samples pinned at the cap of 4 |
|---|---|
| before the veto (12:26 game) | 95 / 166 |
| with the veto only (12:54 game) | **237 / 291** |
| after this C++ fix | **49 / 148**, spread across 1-4 |

So the clog pre-dated the veto and the veto made it worse. Both are fixed by
correcting the predicate at source: `GetFriendlyUnit(unitId)` ->
`GetTeamUnit(unitId)`, which is the own-team lookup the original author had
already written and commented out on that exact line. Ally spots now never
become upgrade tasks, so there is nothing to walk to, nothing to clog, and the
script veto below is left as a guard that no longer fires (60 firings in the
live game, **1** after the fix).

Verified: 30-min 8v8, Flats and Forests v2.2, `--sides random`, seed 5701 —
0 AngelScript errors, 0 crashes, MEXUP flowing rather than stuck.

**The user's actual goal is NOT yet met.** apex holds a median of 17 mexes and
4 T2 mexes, so most home-base mexes are still un-upgraded. This change removed
the defect that was blocking upgrades; it did not raise the priority of making
them. apexearth: "Mex upgrades within our base are paramount importance for T2
cons." The named next step is a rule that puts an advanced constructor on a
home-base mex upgrade ahead of the optional cluster, and/or raising `mex_up`
now that the slots are no longer wasted — one at a time, with `composition.py`
against a matched control.

Do not compare the t2Mex totals of the 12:54 game against the verification run:
stock's own median fell from 12.5 to 3.0 between them, i.e. the two games are
not the same economy and neither is a control for the other.

## 2026-08-09: A crash in AiTaskRemoved — a dangling task handle, not the mex work

Not fixed. Recorded so the next session does not re-diagnose it.

A live 8v8 died at frame 54108 with `Access violation (0xc0000005)` at
**Exception Address 0x0** — a jump to a null function pointer — and
`This stacktrace indicates a problem with a skirmish AI`.

Resolved with the recipe in `docs/06`, against the DLL that actually crashed
(ImageBase `0x1e33b0000` + the infolog offsets):

```
(0) 0x0                        <- jumped to null
(1) circuit::IRefCounter::Release()          script/RefCounter.cpp:29
(2) asCContext::ExecuteNext()                as_context.cpp:3234
(4) circuit::CScriptManager::Exec(...)       ScriptManager.cpp:231
(5) ITaskModuleScript::TaskRemoved(IUnitTask*, bool)  <- AiTaskRemoved
(6) circuit::ITaskModule::DequeueTask(IUnitTask*, bool)
(7) std::_Rb_tree<int, CBRepairTask*>::find(...)
(8) circuit::CCircuitAI::UnitFinished(...)   CircuitAI.cpp:1111
```

So: a unit finished, a **repair** task was dequeued, `AiTaskRemoved` ran, and
releasing a handle called through freed memory. `manager/builder/events.as`
holds `array<IUnitTask@> gArmyRepairs` and `gMexTasks` — ref-counted task
handles kept across frames — and `AiTaskRemoved` is where `removeAt` releases
one. A task destroyed by a path that does not run `DequeueTask` leaves a stale
handle whose `Release()` runs on freed memory. `fortify.as:140` already asserts
that DequeueTask/AiTaskRemoved is a reliable contract; this stack is the
counter-example.

**It is not the mex work**: that code stores unit ids and positions, never task
handles, and appears nowhere on this stack. The clog fix above may make it
rarer by cutting task churn, but the use-after-free is untouched.

## 2026-08-09: Constructors walked into an ally's base to upgrade a mex that was not ours

Layer 2 (AngelScript), new `manager/builder/mexowner.as`, one line each in
`builder.as`, `builder/maketask.as`, plus `Economy::AiUnitAdded`/`AiUnitRemoved`
in `manager/economy.as` and the missing economy half of the `Unit::UseAs` enum
in `script/unit.as`.

apexearth, watching an 8v8 live: "'Supernova' (teal) is just running back and
forth in his allies base at <6m timeframe... it was bad", then "corcom cannot
mexup".

**`CEconomyManager::UpdateEconomyTasks` picks the mex spot to upgrade using
ALLY-wide unit lookups.** The predicate reads the extraction rate of everything
`GetFriendlyUnitIdsIn()` returns and resolves each id through
`GetFriendlyUnit()`, with the own-team `GetTeamUnit()` call commented out
beside it. So an ally's extractor satisfies "there is a mex here yielding less
than what I can build", and a MEXUP task is enqueued at `Priority::HIGH` on
ground we do not own.

**The task can never complete.** `CBMexUpTask::Execute` cannot place the
building — the ally's extractor occupies the spot — and its fallback (reclaim
the old mex, build on the second pass) resolves the occupant through
`GetTeamUnit()`, which returns null for another team's unit. `oldMex` stays
null, `AbortTask` fires, `SetUpgradingMexSpot(spotId, false)` releases the
spot, and the next `AiMakeTask` picks the same spot again. The constructor
walks to the ally's base, turns round, walks back, indefinitely.

**Why it bites in the opening, and why it looked Cortex-specific.** Before an
advanced constructor exists, `metalDefs.GetBuildDefs(conDef)` offers a
constructor only its own side's T1 mex, so the spot must hold something
yielding *less* than a T1 mex. Read from the pinned tree: **`armmex` and
`cormex` extract 0.001, `legmex` extracts 0.0008** ("Extracts Slightly Reduced
Metal"). So an Armada or Cortex player with a Legion ally starts doing this the
moment `GetAvgMetalIncome()` passes the rule's threshold of 10 — and a Legion
player never does, because nothing yields less than `legmex`. In the live
8v8 the vetoes appear for teams 0, 2, 3 and 5 (Armada and Cortex) and for the
Legion player not once. Once advanced constructors exist **every** faction
reaches it, because a moho outyields every ally's T1 mex.

It compounded on the commander: the held task is a MEXUP, and
`VetoCommanderHold` then refuses every replacement build type offered, so the
commander was pinned to a job it could not do. `corcom` builds `cormex` but not
`cormoho` — only `corcomlvl5`+ and the advanced constructors can.

The fix is a veto, `VetoAllyMexUp`, screening `DefaultMakeTask`'s offer ahead of
`ExpansionAlwaysWins` — an upgrade on an ally's spot reads as expansion and
would otherwise be taken outright. It refuses any MEXUP whose build position is
not within 96 elmos of a mex of ours.

**Which mexes are ours needs no def list.** `CEconomyManager`'s own
`mexFinishedHandler` fires `UnitAdded(UseAs::MEX)` for every extractor we
finish and `mexDestroyedHandler` the reverse, so the tracked set covers Armada,
Cortex and Legion, the moho tier, the exploding variants and the underwater
`armuwmme`/`coruwmme` pair by construction. That hook lands in the **Economy**
namespace, not Builder's — `Builder::AiUnitAdded` only ever receives `BUILDER`
and `REZZER` — and `script/unit.as` was missing the economy half of the
`UseAs` enum entirely (it stopped at `ASSIST`, where `Module.h` continues
`ENERGY, GEO, MEX, CONVERT, STORE, AIRPAD`). Both added.

Deliberately **not** made to work rather than refused: reclaiming an ally's
extractor to build our own on top is not something the engine-side task can
express, and in a team game the ally is the one who should be upgrading it.

**Deployed and confirmed firing; not yet measured.** 12-minute 8v8 on Supreme
Isthmus v1.8, `--sides random`, seed 5601: zero AngelScript errors, variant
loaded, the rule fires for `corcom`, `corca`, `corck`, `corcv` and `armck`, and
the old signature (`con-veto ... -> mexup`, 16 occurrences in the live game's
log) is **gone — zero**. What it displaced is unmeasured; judge it on
`composition.py` against a matched control.

## 2026-08-09: A mobile radar travels with the army

Layer 2 (AngelScript), new `manager/factory/eyes.as`, one line in
`factory/maketask.as` and one in `manager/factory.as`.

apexearth: "Some units have long range but poor LOS - when we have units like
this we should have them bring a radar unit with them (jammer too if possible)
so that they can see what they should fire at... one example is the Hound unit."

Read from the pinned game tree: **armfido (Hound) has 650 weapon range against
400 sight.** It is not the worst — `corvroc` is 1310 against 221, `armmerl` 1300
against 247, `cortrem` 1470 against 351, `cormart` 800 against 299.

**The escort mechanism was already there and already correct.** Every mobile
radar and jammer carries `"role": ["support"]` in `behaviour.json`;
`CMilitaryManager::DefaultMakeTask` routes a support unit to `CSupportTask`,
which paths to the nearest ATTACK/DEFEND squad leader and calls `AssignTask` to
join that squad. `Military::WantsMassing` already returns false for SUPPORT, so
apex does not divert them. What was missing is the unit: in `factory.json` the
radars sit at 0.00-0.05 in the ratio tables against 0.40 for the guns they would
be spotting for.

New `EyesForTheGuns` rule, placed with the other production floors, above
`RushBuildPower`. It recruits the mobile radar directly, the same way
`LateRadarPlane` recruits the radar plane:

- **The blind-gun set is derived, not listed.** `GetMaxRange()` and `losRadius`
  are both bound, so the rule walks every def once and marks anything mobile,
  non-flying, non-AA, non-commander, non-builder with range in [650, 3000] and
  `range > los * 1.6`. That covers all three factions and every terrain block by
  construction. The 3000 cap is because anti-ship missiles carry range 72000.
- **One radar per 5 blind guns standing, capped at 2**; a jammer per 10, capped
  at 1, and only once the radar cap is met. 30 s spacing.
- **Named per factory, not asked for by role.** The radar, the jammer and the
  assist bot all carry role `support`, so `GetRoleDef(SUPPORT)` cannot tell them
  apart — the same reason `RezBotDef` names its defs. Dispatch is on the
  factory's own def (`armalab`/`coralab`/`legalab`/`armavp`/`coravp`/`legavp`),
  which is what keeps the request from being a silent no-op.
- **Naval is deliberately out of scope.** A T2 ship already carries 1000-2950
  radar of its own.

Layer 1 alongside it: **`legavrad` and `legavjam` had no `behaviour_leg.json`
entry at all** — the only two of the six mobile radar/jammer units without one.
No entry means no `support` role, so Legion's vehicle-plant radar would not have
gone to `CSupportTask` and would not have followed anything. Added, matched to
the `legaradk`/`legajamk` bot-lab pair that do have entries.

Cheap by the standards of what it displaces: the radars are 92-125 metal and the
jammers 75-105, against 285 for a Hound and 320-920 for the artillery. It spends
factory time, not constructor time, so the 2026-08-01 composition finding does
not bite here — but it does displace a unit from the same lab, and the gate
(five T2 blind guns already fielded) is what keeps it out of the opening and the
tech rush.

**Deployed and confirmed firing; not yet measured.** One 30-minute 4v4 on Comet
Catcher, seed 1: zero AngelScript errors, `Load script: …Apex\apex\…` confirmed,
and the rule fired twice — `blindDefs=22` (the derived set), first at
`blindGuns=5 standing=0`, again at `blindGuns=10 standing=1`. So both the gate
and the one-per-five escalation behave as written. It did **not** fire in a
20-minute cut of the same game, which is the benchmark's starved economy, not a
bug: five T2 blind guns is simply not reached that early here.

What is still unknown is what it displaced. Judge it on `composition.py`
against a matched control.

## 2026-08-09: A defensive posture buys artillery and fodder, not Bulls

Layer 2 (AngelScript), `manager/factory/armypush.as`, `factory/rules_rush.as`,
`factory/maketask.as`.

apexearth: "When we are losing and playing defensively we should stop building
units like the 'Bull'. In a defensive posture we need to buy long range units
which can hit enemies from the safety of within our base. Also we need to create
spam units, cheap T1 units and use them as fodder against the enemy."

`Military::gTurtle` is already the AI's own statement that it is losing the trade
and has stopped attacking, and while it holds the army is parked in DEFEND tasks
inside our own influence. Nothing changed what we *bought* in that state:
`LosingArmyPush` asked `GetRoleDef(ASSAULT)` from the advanced plant, which is
`armbull` — 950 metal of short-ranged brawler bought to stand still.

New `DefensiveComposition` rule, above `LosingArmyPush` in the factory pipeline.
While turtling and not the eco lead, it alternates:

- **artillery** (`Unit::Role::ARTY`) — the long-range half. Per faction and tier
  that is `armart` 135 / `corstorm` 110 at T1, `armmart` 320 / `cormart` 400 /
  `corhrk` 600 / `armmerl` 920 / `corvroc` 880 at T2.
- **fodder** (the existing `Fodder()`, scout-or-raider under 100 metal) — the
  cheap bodies that soak the charge while the artillery fires.

with fallback both ways, so a bot lab with no artillery unit still contributes
fodder and a plant whose cheapest unit is not cheap still contributes artillery.
`LosingArmyPush`'s advanced branch takes the same ARTY-over-ASSAULT substitution
while turtling, because it is unspaced and would otherwise fill the gaps between
`DefensiveComposition`'s picks with exactly the Bulls this removes.

This is a **substitution, not an addition**: the factory was going to spend the
slot regardless, so unlike the builder-side rules the 2026-08-01 finding is about,
it costs no constructor time and displaces no expansion. What it displaces is the
assault mainstay.

**Not yet measured.** Deployed and smoke-tested only; judge it on
`composition.py` (assault share down, artillery share up, mex upgrades unchanged)
against a matched control.

## 2026-08-09: Jammers are placed deliberately instead of by chain accident

Layer 2 (AngelScript), `manager/builder/statics.as` + `rules_optional.as`.

apexearth: "We need to ensure our base is covered by jammers."

Nothing placed them on purpose. The only jammer entries in the game are
`build_chain.json` hubs hanging off `armrad`/`corrad`/`armfrad`/`corfrad`, and a
hub fires only when its exact parent unit finishes — so base jamming was a side
effect of whether a radar tower happened to get built, at `"low"` priority,
behind a Pulsar and a Big Bertha in the same list.

New `BaseJammer` rule asks for `armjamt` 240 / `corjamt` 115 / `legjam` 140
directly. Capped at 3, one outstanding at a time, 45-second period. The first
covers the base itself; later ones anchor on `Military::BorderPos` so they move
out to the approaches. Gated on **energy**, not metal — 5,200-8,500 to build and
40/s upkeep forever, against ~150 metal — and on `energy.income >= 150`.

Orders are recorded in `digin.as`'s existing `gJammerPos`/`gJammerAt` ledger, the
one built for the chain path after apexearth reported "I often see many jammers
all close together", so the two paths cannot cluster against each other.

Placed in the phase-gated (`gLastPhase >= 4`) ECO/HOME cluster with the other
one-off structures. Deliberate: before an advanced factory exists a constructor's
only job is expansion, per the 2026-08-01 finding. The cost of that choice is
that a base is not jammed until it has teched.

**Not yet measured.**

## 2026-08-09: Pinpointers are capped at three for the whole TEAM

Layer 2 (AngelScript) `manager/builder/statics.as` + `rules_optional.as` +
`manager/factory/phase.as`, and layer 1 (JSON) `build_chain.json`,
`behaviour.json`, `behaviour_leg.json`.

apexearth: "Ensure that we make pinpointer style units (for Armada, Cortex, and
Legion) - the entire team only needs 3 max."

We already built them, and the cap was on the wrong axis. Two sources, both
per-player:

- `build_chain.json`'s `base` list carried `[22, 1800]` — porcupine index 22 is
  `armtarg`/`cortarg`/`legtarg` — so **every AI on the side** scheduled one at
  30 minutes, on a clock, with no economy gate at all.
- `behaviour.json` set `"limit": 3` on `armtarg`/`cortarg` and `behaviour_leg.json`
  the same on `legtarg`. That is the engine's per-instance def limit, so an 8v8
  side was permitted **24**, for an effect that stops stacking at 3.

The `[22, 1800]` entry is removed and the limits are now `1` each, so
`Builder::Pinpointer` is the single source and the per-player ceiling is
engine-enforced underneath it. The team cap itself rides the same in-process
blackboard the tech-lead election uses: each instance publishes `TV_TARG`
("targ") from `UpdateTeamCoord` as its standing-plus-outstanding count, and sums
the ally roster before ordering.

Two things the cap needs that a plain sum does not give:

- **Its own contribution comes from `OwnPinpoints()`, not from its own
  blackboard slot.** Publishing happens once a second; a rule reading its own
  stale slot would order a second one inside that window.
- **One asker at a time, by rank in the ally roster** (`PinpointTurn`). Without
  it the cap is only as tight as the publish cadence — every instance passing the
  economy gates in the same second reads the same total and all of them order,
  which is how a cap of 3 becomes a 5.

An order that never becomes a building would otherwise hold a team slot for the
rest of the game, since the slot is released by the standing count; the ask
expires after `PINPOINT_ASK_TTL` (5 min).

Gated on the grid rather than a clock, because that is what this costs: 7,200-7,500
energy to build against 810 metal, and then `energyupkeep = 100` for the rest of
the game. Bar is 500 energy income and 30 metal income, T2 constructors only
(`armtarg` lists `armaca`/`armack`/`armacv` and their heavy variants, so asking a
T1 constructor is a silent no-op), placed with the nanos behind the base.

Sits in the phase-≥4 ECO/HOME cluster just after `Shield`. It is a SPEND rule of
the class CLAUDE.md records as having cut metal production 4.3x when twelve went
in at once — but capped at three for the entire side it can displace at most
~2,400 metal of expansion across all players, against the up-to-24 the shipped
config allowed.

**NOT YET MEASURED, AND NOT YET COMPILE-CHECKED.** A live game and two headless
matches were running when this was written, so `deploy_ai.py` correctly refused
and no infolog has confirmed the AngelScript compiles or that the rule fires.
An AngelScript compile error disables the whole variant silently; grep the
infolog before trusting any run on this.

## 2026-08-09: mex defence scales with how close the mex is to the enemy

Layer 2 (AngelScript), `manager/builder/mexguard.as` + `digin.as`.

apexearth: "The closer our metal extractors are to the enemy, the more defenses
we should be building on them. All of our mexes need to have at least 1 turret
in range to defend it. Make sure we always do this."

Both halves were broken, in different ways:

- **The wanted count was global, not positional.** `MexGuardWanted()` returned
  `LandIsPrecious() ? 1 : 2` — the same bar for a mex under the enemy's nose and
  one behind the factory. It now reads `FrontT(at)` (the existing home→enemy-axis
  projection, 0 at our base, 1 at the enemy centroid): **4 turrets past 0.40,
  3 past 0.20, and 1-2 at the rear**. `LandIsPrecious` now only decides whether a
  REAR mex gets a second turret; it can no longer take the last one away, and it
  does not apply forward at all.

  Those two thresholds were first set at 0.35/0.60 by eye and that was wrong.
  Measured over a 20-minute 4v4 (76 placements): **our own mexes span frontT
  -0.01 to 0.44 and stop there** -- a mex past midfield is the enemy's -- so
  0.35/0.60 put 69 of 76 in the rear tier and fired the forward tier zero times.
  The thresholds have to be set against the range we actually hold, not against
  the 0..1 the axis defines.
- **"Defended" was measured at the wrong radius.** The cover count used
  `MEX_COVER_RADIUS` = 700, but `armllt`/`corllt`/`leglht` have **430 range**, so
  a mex could be counted as defended by a tower that cannot shoot anything
  attacking it. The bare test now uses `MEX_IN_RANGE` = 420. 700 is still the
  right radius for the *ranking* question ("how thick is defence here"), so both
  now exist and answer their own question.

Three gates were stopping the "at least 1" floor from ever being a floor:

1. `if (aiEconomyMgr.isEnergyStalling) return null;` at the top declined to place
   even a first turret. Stalling now only blocks **thickening**; a bare mex is
   still guarded.
2. Ranking was `(cover + 1) * distanceToEnemy`, so a mex at cover 2 near the
   enemy outscored a bare mex further back — the rear half of the map never
   reached its floor. Bare-ness is now a hard first key that latches: once a bare
   mex is in hand, no covered one can displace it.
3. `MEX_GUARD_REACH` = 1200 meant a mex no constructor ever passed within 1200 of
   stayed bare forever. Bare mexes get `MEX_BARE_REACH` = 2400 — **for ordinary
   constructors only**; the commander keeps 1200, since walking it across the map
   is how games are lost. The walk-into-fire threat veto still applies to every
   candidate beyond `MEX_GUARD_HERE`, so this buys reach and not recklessness.

`DefenceAround()` was generalised to `DefenceWithin(pos, radius)` (fences plus
outstanding orders, same TTL bookkeeping) so the two radii share one
implementation; `DefenceAround` is now a one-line call at `DIG_AREA`.

Verified running, not verified good: 20-minute 4v4, `Comet Catcher`, seed 1 —
**0 AngelScript errors**, variant loaded, and the rule fired **76 times, 50 of
them on a mex with nothing in range** and 26 thickening.

**Effect not measured.** This is a rule that SPENDS constructor time, which is
the 2026-08-01 failure mode — the forward tiers (3 and 4 turrets) are the part
most likely to displace mex upgrades. Needs `composition.py` against a matched
control before it is trusted.

## 2026-08-10: where the 1v1 ended up

40 games per faction, Altair Crossing 1v1 mirror, side-swapped, 60-minute cap,
`Apex:apex:hard_aggressive` against `BARb:stable:hard`:

| faction | decided | apex wins | win% | 95% CI |
|---|---|---|---|---|
| Cortex | 37 | 17 | 46% | 31-62% |
| Armada | 39 | 23 | **59%** | 43-73% |
| Legion | 37 | 16 | 43% | 28-59% |
| **pooled** | **113** | **56** | **49.6%** | 40-59% |

Against a starting point of 1 win in 66 decided games. Every faction's interval
includes 50% and none reaches the 75% target; this is parity with stock, not
superiority over it.

## 2026-08-10: the 1v1 win rate is 1/66, and the 20-minute cap was hiding it

Every 1v1 tournament in this repo before today capped at 20 minutes, and most
games were still running at the cap -- so the headline metric was the army-trade
proxy and the win rate was simply unmeasurable. apexearth confirmed the cap need
not stand. **At 45 minutes essentially every game reaches game over**, and the
answer it gives is not ambiguous:

| faction | decided | apex wins | win% | 95% CI (for stock) |
|---|---|---|---|---|
| Cortex | 24/24 | 0 | **0.0%** | 86-100% stock |
| Armada | 22/24 | 1 | **4.5%** | 78-99% stock |
| Legion | 20/24 | 0 | **0.0%** | 84-100% stock |

Altair Crossing, 1v1 mirror, side-swapped, `Apex:apex:hard_aggressive` against
`BARb:stable:hard`, 24 games each. Median game length 24-34 min, i.e. the old
cap cut the games off at roughly the point where they were being decided.

Cortex army trade over those 24 games: **0.206** (we kill 110,605 metal and lose
271,725; they kill 316,610 and lose 159,985). Metal produced ratio 0.862.

**Where it goes wrong, from the paired timeline** (`tools/tl.py`, which pairs
samples by frame so a dead team's silence cannot flatter the survivor):

| game min | metalProduced | armyReal | mFactories | mKillReal | mLostReal |
|---|---|---|---|---|---|
| 8 | 4,936 / 4,635 | 2,938 / 3,290 | 531 / 520 | 83 / 86 | 269 / 316 |
| 12 | 9,265 / 8,322 | 3,390 / 4,077 | **1,052 / 519** | 498 / 752 | 1,092 / 1,116 |
| 16 | 15,189 / 14,038 | 3,678 / 4,816 | **2,147 / 695** | 1,607 / 2,554 | 3,160 / 2,394 |
| 20 | 23,640 / 21,151 | 4,041 / 4,906 | 2,921 / 2,146 | 3,530 / 4,975 | 5,947 / 4,550 |
| 32 | 54,753 / 54,440 | 2,964 / **7,756** | 5,066 / 3,370 | 9,332 / **18,933** | 23,020 / 11,802 |

(apex / stock. mex is 17/15 in our favour at minute 20 and 20/32 against us at
32.)

We are AHEAD on economy and mexes to minute 20. What we do with it is buy
factories: 2,147 metal of them at minute 16 against stock's 695, while stock
buys Thugs. Composition over the same 24 games, as a share of all metal built:

| | apex | stock |
|---|---|---|
| factories | **14.1%** | 7.1% |
| static defence | 16.2% | 22.0% |
| army (real) | 20.5% | 23.6% |
| `corthud` (the T1 mainstay) | **3.6%** | 10.9% |
| `coralab` (advanced bot lab) | **15.9%** | 4.5% |
| `corfus` | 0% | 11.7% |
| `corpun` (T2 area artillery) | 0% | 14.2% |

So stock's 1v1 plan is Thugs, mohos, a fusion and Agitators; ours is advanced
labs, T1 constructors and advanced solars. We tech at a median of 13.8 min
against their 17.5 and have nothing on the field when we get there.

## 2026-08-10: `hard_aggressive` is a STALE stock profile, and apex was forked from it

The 0-24 above was decomposed by layer, 24 games per arm, same map, same
opponent (`BARb:stable:hard`), side-swapped:

| arm | what it is | decided | wins | win% |
|---|---|---|---|---|
| `Apex:apex:hard_aggressive` | apex config + apex script + apex DLL | 24 | 0 | **0%** |
| `ApexStk:stk:hard_aggressive` | **stock** config + **stock** script + apex DLL | 24 | 2 | **8%** |
| `ApexStk:stk:hard` | stock config + stock script + apex DLL, `hard` profile | 17 | 6 | **35%** |
| `BARb:stable:hard_aggressive` | stock everything, `hard_aggressive` profile | 23 | 6 | **26%** |

Read down the list. Strip every line of apex's own game-side work and the AI
still loses 22-24; that is not apex's doing. Change nothing except the PROFILE
and it goes from 26% to ~50% — stock BARb playing `hard_aggressive` loses 6-17
to stock BARb playing `hard`, same binary, same everything, config only.

`hard_aggressive` is not "hard, but aggressive". It is an **unmaintained older
copy** of the hard tree. `economy.json` is the clearest tell: `hard` carries a
per-def efficiency term (`"corfus": [4, 6, 50, 600, 2.06]  // efficiency=2.057844`)
with geothermals, underwater fusion and `armckfus`; `hard_aggressive` carries a
two-element stub (`"corfus": [30, 40]`) with none of them. The energy `factor`
ladder is `[[6,1],[20,300],[30,420],[60,3600]]` in `hard` and `[[1,300],[30,7200]]`
in `hard_aggressive`. Stock's own `AIOptions.lua` has `def = 'hard'` and does not
list `hard_aggressive` in its items at all.

So the "one profile on purpose" decision — keep `hard_aggressive`, delete the
rest — picked the wrong survivor, and every measurement in this repo has been
taken on a config tree the upstream author stopped maintaining.

The C++ delta, by contrast, is roughly neutral here: apex's DLL running stock
`hard` game-side scored 6-11, a CI that includes 50%.

## 2026-08-10: the fighter-task C++ delta costs 12 points, and is reverted

Two arms, 40 games each, run CONCURRENTLY in one session against
`BARb:stable:hard` (Altair Crossing 1v1 Cortex, 60-minute cap):

| arm | decided | apex wins | win% |
|---|---|---|---|
| apex fighter tasks | 38 | 14 | 37% |
| reverted to upstream `0ef3626` | 39 | **19** | **49%** |

Reverted: `src/circuit/task/fighter/` in full, plus `MoveAction.cpp` and
`TravelAction.h`. That is line-formation travel, the orbiting standoff, the
engage and continue margins, trade-scaled caution, the raid-economy target
scoring and the sticky-target rules.

The tunable A/B pointed at the same place before the rebuild, on the same
40-game footing:

| arm | decided | apex wins |
|---|---|---|
| control | 38 | 10 |
| `apex_engage_margin=0.5` | 38 | 10 |
| `apex_orbit_rate=0 apex_range_mod=1.0` | 38 | **14** |

So the caution margins are NOT the cost — turning them almost off changes
nothing — and the standoff/orbit carries a real part of it. That is the pair to
re-land first, with a measurement.

Nothing is lost: every reverted behaviour is in the branch history and can come
back one at a time. What did not happen the first time is the measurement.

**8v8 is not re-measured. Every number in this section is 1v1.**

## 2026-08-10: apex stands aside when it has no allies, and moves onto the `hard` base

Two changes, measured separately, 24 games each against `BARb:stable:hard`,
Altair Crossing 1v1 Cortex mirror, side-swapped:

| build | decided | apex wins | win% |
|---|---|---|---|
| before | 24 | 0 | 0% |
| `ApexActive()` gate only (still on `hard_aggressive` configs) | 23 | 6 | **26%** |
| + config base moved to stock `hard` | 20 | 8 | **40%** (CI includes 50) |

**`ApexActive()`** (`script/world.as`) is false when `ai.GetTeamIds()` holds one
entry, i.e. no allies. Every apex game-side hook returns the stock answer when it
is false: both `AiMakeTask` pipelines, `Military::AiMakeTask`, `AiMakeDefence`,
`AiIsSwitchTime`, `AiIsSwitchAllowed`, `AiGetFactoryToBuild` and the whole of
`AiUpdate`. Verified in an infolog: `apex:` log lines go from 144 to 3 in a 1v1.

The 26% is the confirmation that the gate is COMPLETE, not just that it helped:
stock BARb running `hard_aggressive` measured 6-17 in its own 24-game arm, and
apex-with-the-gate measured 6-17. Identical, which is what "we are now playing
stock" should look like.

**The config base.** `config/hard_aggressive/` is now a copy of stock's `hard`
tree rather than of its `hard_aggressive` tree. The directory keeps its name
because the profile option names both the config dir and the script dir.

Two things this costs, recorded so they are not discovered later:

- apex's own config deltas (raider shares in `factory.json`, the build-chain
  edits, `economy.json` tuning) are GONE and need re-deriving on the new base.
  They were measured on a tree that loses to `hard` by construction.
- **8v8 is not re-measured.** The 16-0/8-0 results at the top of this file were
  taken on the `hard_aggressive` configs. Team play still runs every apex rule;
  only its config base moved. Re-measure before trusting the old numbers.

## 2026-08-10 (NEGATIVE): switching the T2 rush off in small teams changes nothing

The structural hypothesis was that the rush is a team strategy misapplied in a
1v1 — pool behind one player while others hold ground, with nobody to pool from
and nobody holding ground. Implemented as `!IsSmallTeam()` on both of the rush's
bypasses in `AiIsSwitchTime` (the 10-second probe, which also disables
EconomyManager's metal gate) and `AiIsSwitchAllowed` (the no-bank T2 grant), so a
small team falls through to stock's "have an army before you tech" gate.

**0-23, against a 0-24 baseline.** No effect in either direction. The factory
overspend it was aimed at is real (2,147 metal of factories at minute 16 against
stock's 695) but is evidently not what decides these games.

## 2026-08-09: the AngelScript was split up (pure refactor, no behaviour change)

`builder.as` was 4,651 lines and `factory.as` 2,859. That is a CORRECTNESS
problem, not a tidiness one: neither fits comfortably in an agent's context, so
edits were made by grepping for a landmark, reading twenty lines around it and
doing an anchored `str.replace` — and an anchor that does not match fails
silently, which has eaten edits here at least five times.

Nothing about how the AI plays was meant to change, and the diff was constructed
so that it could not:

| | before | after |
|---|---|---|
| largest script file | 4,651 | 512 |
| files over 800 lines | 3 | 0 |
| `Builder::AiMakeTask` | 989 lines | 118-line pipeline + 15 named rules |
| `Factory::AiMakeTask` | 502 lines | 60-line pipeline + 12 named rules |
| faction `if (side == …)` chains | 19 | 1 (`SideDef3` in `script/side.as`) |

**How "no behaviour change" was established.** Three independent checks, because
this benchmark's noise floor cannot carry the claim on its own:

1. *Reconstruction.* Every split is a line slice, and a script re-concatenates
   the parts and diffs the non-blank lines against the pre-split file. For the
   two `AiMakeTask`s the same check reports every line that is not present
   verbatim in the new files — the entire list is the pipeline glue, plus two
   `if (x !is null) return x;` that gained braces because they now also set an
   out-parameter, plus one three-line call that became the pipeline's own.
2. *Compile and load, on every faction.* 8-minute 1v1s on Armada, Cortex and
   Legion after each step: zero `.as (line, col) : ERR`, and `Load script:
   LuaRules\Configs\Apex\apex\...` present. This gate earned its keep — one
   qualified `Builder::SideDef3` survived a rename, the match still ran to
   completion and reported a normal result, and the grep is the only thing that
   caught it.
3. *A paired tournament.* The pre-refactor build was deployed as the `ctl`
   variant and both played `BARb:stable:hard` in the SAME tournament,
   interleaved, 24 games each, Altair Crossing 1v1 Armada mirror, 20 minutes.

| arm | trade ratio | metal produced ratio |
|---|---|---|
| pre-refactor (`ApexCtl:ctl`) | 0.621 | 0.957 |
| refactored (`Apex:apex`) | 0.564 | 0.982 |

and in the 24 games the two builds played each OTHER, the refactored build read
**1.689** against the old one's 0.592 — i.e. the two comparisons disagree about
the sign, which is what noise looks like and what a real change does not.

For scale, the same two builds measured in an EARLIER session, one after the
other rather than interleaved, read 0.301 (pre) and 0.243 (post). The same build
moved 0.301 -> 0.621 between sessions; the two builds differ by 0.057 within
one. Run the arms interleaved or the session is the biggest term in the result.

**Log-line counts are not a check.** Re-running the UNCHANGED baseline on the
same seed moved one log category from 75 lines to 0, because the DLL is
multithreaded and the games diverge. Anything read from a single run is noise.

The one thing deleted rather than moved: `config/*.json`, the seven top-level
files. `CSetupManager::ReadConfig` reads `config/<profile>/<name>.json` and only
falls back to `config/<name>.json` when that is empty or missing, so with all
seven present under `hard_aggressive/` the top-level copies were never read —
confirmed in an infolog, which lists seven `Load config:` lines and all seven are
the profile's. They were 2,360 lines byte-identical to `barb-stable`, and their
real cost was as a trap: editing one has no effect and says nothing.

## 2026-08-09: found while refactoring, NOT fixed

Everything here was found by reading, during a refactor that was required not to
change behaviour. None of it is fixed. An unmeasured behaviour change is
indistinguishable from a regression here, so these are recorded and left.

**AngelScript / config**

- `build_chain.json:/porcupine/land` is a SINGLE array read once per side, and
  `UpdateJson` replaces arrays rather than merging them. `build_chain_leg.json`
  sets its own `land`, and the `_leg` files load after the base ones — so with
  `experimentallegionfaction=1`, **Armada and Cortex silently use Legion's
  defence order too** (`armllt` first instead of `armbeamer`). The comment in
  `build_chain_leg.json` describes a per-side mechanism that does not exist.
  Does not bite the benchmark, which only sets the modoption for a Legion side;
  does bite hosted games, where it is normally on.
- `build_chain.json` `/factory/armshltx/hub[1]` and `/factory/corgant/hub[1]`
  are literally `[]`, under a comment claiming they are "the only place armanni
  gets built other than base index 12" — and index 12 is in neither
  `porcupine.base` nor `porcupine.land`. Legion's equivalent carries the real
  entry. A faction-parity gap; `Builder::Pulsar` is what actually fields them.
- The advanced-radar hubs (`armarad`/`corarad`/`legarad`) are unreachable.
  `AvailList::GetBestDef` scores `pi*r^2/costM`, the basic radar wins on every
  faction (230,907 vs 96,211 for Armada), and `checkSensor` ends the scan on the
  first available def even when it enqueues nothing.
- `porcupine.wall`, `porcupine.choke` and `porcupine.default` are parsed into
  `wallDefs`/`chokeDefs`/`defaultPorc` and never read: the choke block in
  `DefaultMakeDefence` is commented out and `GetDefaultPorc()` has no call site.
  (`choke.armada` is also `["coreyes"]`, a Cortex unit.)
- `armamb` and `cortoast` carry `"on": false`, so `CircuitAI::UnitFinished`
  switches them off the instant they finish — and `military/basedefence.as`
  deliberately picks them as the preferred T2 rung for Armada and Cortex.
  Legion's `legcluster` is `"on": true`.
- A comment in `build_chain.json` justifies skipping porcupine indices 11 and 13
  on the grounds that six defs carry `"on": false`. Only two of them do;
  `armguard`, `corpun` and `legcluster` are explicitly on and `legacluster` has
  no key. Index 13's exclusion rests on a false premise.
- `build_chain_leg.json` claims a short array makes the AI "die at frame 0" out
  of bounds. `ReadConfig` bounds-checks and skips. The padding is still needed
  for correct indexing; the crash claim is false.
- `economy.json` carries three `legion` keys (`geo`, `mex`, `default`) that
  point at Armada units and can never apply — overridden by `economy_leg.json`
  when Legion is on, and irrelevant when it is off.
- `block_map.json` names four units that do not exist (`armuwmex`, `coruwmex`,
  `legamsub`, `legplat`). Inherited from stock; `tools/check.py` reports them.

**C++ (`vendor/engine/.../BARb`, branch `barbarian-apex`)**

- `task/fighter/AttackTask.cpp:795,797` — the finish-off bonus is discarded. The
  block does `prio *= FINISH_PRIORITY;` and then `prio = ARTY_PRIORITY;` /
  `prio = LONG_RANGE_PRIORITY;` by plain assignment, so a nearly-dead artillery
  piece scores 4.0 instead of 12.0. Every other modifier in the block uses `*=`.
  This is exactly the "we walked away from a nearly-dead thing" case the
  `FINISH_PRIORITY` comment cites.
- `task/fighter/SquadTask.cpp:642` — `static int sLastPowerDiagFrame` is a
  FUNCTION-LOCAL static, so it is shared by every squad task of every AI
  instance in the process (all 8-10 bots the host adds live in one DLL). It both
  starves every AI but one of the diagnostic and is an unsynchronised
  read-modify-write. Labelled "TEMPORARY" and still shipping.
- `CircuitAI.cpp` — the team blackboard is a file-scope
  `static std::map<std::pair<int,std::string>, float> teamValues` mutated from
  every AI instance with no lock, and process-global rather than per-game.
- `task/fighter/SquadTask.cpp:681` — `range0` hardcodes `ATTACK_RANGE_MOD` while
  the row four lines above reads the `apex_range_mod` tunable, so an A/B of that
  modoption silently does not move the scouting row.
- `task/builder/BuilderTask.h:167` — `nextMetalEmptyReclaim` is declared with a
  large comment describing behaviour, and is never read or written.
- `ISquadTask::LinePos` and `ISquadTask::GetCohesionScale` are dead, and
  `AttackTask.cpp:653` re-implements the latter inline against the same
  constants.
- `SquadTask.cpp:531` derives the orbit direction from the object's address and
  a comment claims that makes it stable; it is heap-layout dependent, so the
  same seed gives different orbits run to run.

## 2026-08-09: we never attacked, and the group size was the reason

apexearth, watching an 8v8: "we just don't really attack ever... so the enemy
only ever takes territory from us slowly over time and we never get any of it
back", and "Our armies tend to chase around enemy armies instead of trying to
attack enemy metal extractor positions... the goal there shouldn't be to engage
enemy army, but to attack their economy."

Three separate mechanisms, each of which alone blocks the others.

**1. The group we demanded was sized against their whole army.** `MassWant()`
scales `quota.attack` -- the MINIMUM attack power before the engine will form an
attack at all -- with the ratio of their army to ours. Measured live in an 8v8:
ratio 1.28-1.35, so it returned 41-43 and never touched `MASS_CAP`, meaning a
deadline keyed on the cap would never have fired. Behind on economy means behind
on army means a larger demand means nobody leaves, which loses more ground.

**The quota is a POWER SUM, not a unit count** (`CFighterTask`: `attackPower +=
cdef->GetPower()`). Measured in-game: Pawn 2.5, Grunt 2.5, Rocketeer 4.8, Thug
6.4, Warrior 11.5. So `MASS_FLOOR` 30 is about **twelve Grunts**, and the 41-43
actually demanded was about **seventeen**. apexearth asked for "~10 grunts", so
the FLOOR was right all along -- the army-ratio scaling on top of it was not.
`MassWant` now returns the floor; `apex_mass_vs_army=1` restores the old scaling.

**2. Target selection scored purely by distance**, so the enemy army in the
middle is always nearer than the mex behind it. Re-landed from the reverted
fighter delta, and ONLY this part of it: undefended static economy gets
`FREE_ECO_PRIORITY` 5x (x2 again when soft -- a converter is 380 metal behind 445
hitpoints against an advanced solar's 350 behind 1130), and their defensive line
gets `ENEMY_WALL_PENALTY` 0.2x unless it is shooting us at home. The metric is a
DISTANCE, so preference divides it.

**3. Attack paths priced contested ground at 1.0**, i.e. not at all, so the short
route ran through their army. Now `apex_attack_threat_mod`, following
`RaidTask`'s `RAID_ROAM_THREAT_MOD = 8` -- the same trick that made raid parties
work round the outside with no waypoints.

**On the recorded warning.** This file already said "lowering minAttackers
globally is known to be catastrophic -- 15 -> 6 scored 0-10". apexearth's read:
"It probably was kinda 'catastrophic' because you were engaging the enemy army -
right???" That is the likely explanation -- when it was measured, targeting was
pure distance, so a small group walked at whatever was nearest, which is their
army. Six units meeting an army is a feed. The three changes above are meant to
be taken together for exactly that reason, and the bundle is being measured
interleaved against an unmodified control.

Also fixed here: `ExpansionAlwaysWins` ran AFTER `OptionalWork` and `Fortify`, so
a constructor could be claimed for AA, a deterrence tower, an energy converter, a
gantry, a nuke silo, a Pulsar or a shield before the engine was even asked what
to build -- and mex upgrades exist only in that engine offer. apexearth: "I see
purple making those two things at the same time instead of properly focusing on
increasing their metal income." This is the 2026-08-01 failure mode exactly.
Measured at 8v8 the mex ratio did not move (54% of stock either way), so the
ordering was not the binding constraint, but the offer now comes first regardless.

## 2026-08-09: solar was chosen over wind on essentially every map

`HomeEnergy` ranks energy candidates by RAW OUTPUT, which is deliberate -- the
ladder has to be able to tier up, and ranking by energy-per-metal would pin it on
wind turbines forever, since a 40-metal turbine beats a 4,300-metal fusion on
that ratio at every income there will ever be.

But raw output decides the WIND/SOLAR pair backwards. `armsolar` makes a flat 20;
a turbine makes the map's wind. Almost no map has wind above 20, so solar won
essentially everywhere -- at 155 metal against the turbine's 40. The comment
above the block claimed "GetEnergyMake() still decides wind against solar, where
the ratio question is real and map-dependent". It did not.

Per metal on a 12-wind map: wind 12/40 = **0.300**, solar 20/155 = **0.129**.
Break-even is around 5.2 wind. apexearth: "this map has tons of wind, we should
never make any solars on a map like this one... generally if average wind is
greater than ~7.5 then wind is better. and this map has 12 wind MINIMUM."

The pair is now decided on cost-effectiveness and the winner handed to the
raw-output ladder, so tiering up still works. Verified live: a smoke game that
previously built solars now builds 29 turbines and zero solars.
`apex_wind_per_metal=0` restores the old behaviour for A/B.

## 2026-08-09: the T2 rush is a TEAM strategy running in 1v1

apexearth: "on a 1v1 map we shouldn't dive straight into t2 either, we should
build a big army and strong economy."

Measured first, and the naive fix FAILS: raising `RUSH_MIN_METAL` 14 -> 22
scored 0.323 against 0.380, and made the economy worse too (metal ratio 0.939
against ~0.97). The constructors do not spend the extra window on mexes.

The structural reason is that the whole rush path is a TEAM design: pool the
team's metal behind one elected lead so ONE player reaches T2 fast, with
`FOLLOWER_TECH_INCOME` (25 metal/s) holding the others back to hold ground
meanwhile. In a 1v1 there are no followers to pool from and nobody holding
ground while the single player techs, so the machinery is misapplied rather than
mistuned -- which is why moving its threshold only made things worse. Gating the
rush path on TEAM SIZE rather than income is the untested candidate.

## 2026-08-09: every 24-game arm, and what actually survived

Altair Crossing 1v1, Armada mirror, side-swapped tournaments, 24 games per arm,
all on one build so the arms are comparable. Trade ratio = our army K/D in metal
over theirs.

| arm | trade ratio | enemy static metal killed |
|---|---|---|
| scouts may look at enemy-held clusters (`apex_scout_threat=1000`) | **0.415** | 8,257 |
| tree-reclaim walk capped at 900 (default) | 0.380 | 10,135 |
| tree-reclaim walk uncapped (previous behaviour) | 0.341 | 11,003 |
| air pays 8x for threat (`apex_air_threat_mod=8`) | 0.323 | 9,733 |
| T2 rush at 22 metal/s instead of 14 | 0.323 | -- |
| no sunk-cost discount under static guns | 0.238 | 8,963 |

**The tree cap is the one change that beat its own direct control** (0.380 vs
0.341, same build, same seeds). It is also the only one that purely REMOVES
work, which is the near-free category from the 2026-08-01 composition finding.

**A prediction that failed, recorded because it failed.** The scouting change
was justified by a chain: `GetScoutPosition` only counts a metal cluster
scoutable if some spot reads `threat < THREAT_MIN`, so enemy-held clusters are
excluded; enemy groups are built from `hostileDatas + peaceDatas`, i.e. only
enemies we have SEEN; target selection iterates those groups. So a defended
enemy mex cluster is not a low-priority target, it is not a candidate, and
`FREE_ECO_PRIORITY` can never fire on it. apexearth: "why didn't we attack the
enemy eco in that mex cluster area?"

That predicts enemy static kills should RISE when scouts may look. They FELL,
8,257 against 10,135. The arm scored best on trade, but not through the
mechanism claimed, so the mechanism is unsupported and the 0.415 is a number
without an explanation -- and at n=24 it is about 1.6 sd from the tree cap,
which is not separation. Re-run before believing it.

**Delaying T2 does not fix teching-before-mexes.** apexearth: "we really failed
to take mexes before making the T2". Raising the rush threshold 14 -> 22 metal/s
made both the trade (0.323) AND the economy (metal ratio 0.939 vs ~0.97) worse.
The constructors do not spend the extra window on mexes. The observation is real;
this is not its fix.

**Scoreboard by source.** Changes derived from watching the AI play located real
mechanisms every time. Changes I derived by reading code and reasoning about
mechanism went 0 for 10 against measurement -- including my own implementations
of behaviours apexearth had correctly identified (the tower sunk-cost fix scored
worst of every arm tried). Locating a problem and fixing it are separate skills,
and only the first one transferred.

## 2026-08-09 (SETTLED): trade caution is HARMFUL at proper sample size

24 games per arm, side-swapped tournament, Altair Crossing 1v1 Armada mirror:

| arm | games | trade ratio |
|---|---|---|
| baseline | 24 | **0.400** |
| `TRADE_MARGIN_MAX` 1.0 -> 1.6 | 24 | **0.288** |

So the +47% claimed earlier is not merely inside the noise, it has the wrong
sign. Nothing shipped: the compiled default remains 1.0 and 1.6 only ever
existed as a modoption. Note the baseline itself read 0.400 here against
0.227-0.307 across four 8-game samples -- the small batches understated the
baseline as well as overstating the arm, which is what a 30% noise floor does in
both directions.

The general lesson, third time today: an 8-game arm cannot resolve anything this
metric measures. Use `run_tournament` with >=24 games per arm.

## 2026-08-09: constructors walk the whole map for trees

`CEconomyManager::UpdateReclaimTasks` takes its `!isNear` branch from
`GetFeatures()` -- EVERY feature on the map -- then picks the nearest qualifying
one with **no distance limit at all**. An earlier session added a bank check
("do not reclaim for energy if we are >20% energy", `RECLAIM_ENERGY_MAX`), so
the behaviour is gated on the energy bank but never on the walk: whenever the
bank dips, a constructor may be dispatched to the far side of the board for a
tree. apexearth, watching a 1v1: "I saw 5 cons going far from the base and
reclaiming trees (energy)... waste of time... we shouldn't be doing that", and
"those cons should focus on eco more".

`RECLAIM_ENERGY_DIST` (900, ~one screen, tunable via
`apex_reclaim_energy_dist`) caps how far a constructor will travel for an
ENERGY-dominant feature. Scoped to energy features deliberately: a field of
metal wrecks after a repelled push is worth crossing ground for and is this
variant's whole funding plan; a tree is not.

Unlike most changes this one only TAKES WORK AWAY, which is the near-free kind
per the 2026-08-01 composition finding -- constructor time is the economy.
Unmeasured as yet.

## 2026-08-09 (CORRECTION): the army-trade metric has a 30% noise floor at n=8

The +47% "adaptive caution" result recorded below is WITHDRAWN. It came from
batches corrupted by a harness bug, and the effect is inside the noise anyway.

**Two instrument bugs, both silent, both producing confident numbers.**

1. Every match shared one engine write dir, and `run_match` copies `infolog.txt`
   out of it at the end -- so two matches running at once land each other's logs
   in each other's output folders. Watched games launched alongside measurement
   batches corrupted them. `run_tournament` already got this right and says so:
   "Never share a write dir across processes." Caught because a CONTROL logged a
   rule only the treatment enabled.
2. `fight1v1.py` assumed ally 0 was always the subject. True for `run_match`
   batches, FALSE for tournaments, which swap sides between pairings -- so every
   tournament arm read a ratio near 1.0 because it was averaging us against
   ourselves.

**The noise floor.** Four unmodified baseline measurements, 8 games each, all
Altair Crossing 1v1:

| run | trade ratio |
|---|---|
| base, seeds 1-8 | 0.252 |
| baserep, seeds 11-18 | 0.307 |
| c-base, clean sequential | 0.227 |
| t-base, tournament | 0.297 |

mean 0.271, sd 0.038, range 0.227-0.307 -- a spread of **30% of the mean on an
unchanged AI**. An 8-game arm must clear roughly **0.346** before it is
distinguishable from baseline at 2 sd. Nearly every "improvement" claimed today
sat below that: trade caution measured 0.310 in one clean run and 0.148 in
another. Both are noise.

**What clears the bar.** The commander flee (`apex_comm_flee_influence=0.3`, on
top of trade caution) measured **0.594** in a clean sequential run -- the only
arm above 0.346. That is one 8-game sample and is not yet a result; it is the
one worth spending a large tournament on. apexearth: "we keep losing to our
commander going banzai into enemy armies... almost every time."

**Method, for next time.** Use `run_tournament` (per-worker write dirs, swapped
sides, ledger, reproducible `config.json`, now `--modoption` for A/B arms), never
hand-rolled loops. Never run a watched game beside a measuring batch unless the
batch sets its own write dir. And size the batch against the 0.038 sd, not
against how large the difference looks.

## 2026-08-09: adaptive caution improves the army trade 47%; a blanket bar makes it worse

Measured in real 1v1 games, not the arena -- the arena found us at parity in an
isolated equal-army fight, so it cannot see the thing that costs us games, which
is WHICH fights we take. `tools/fight1v1.py` scores army K/D in metal across a
batch; `tools/fight1v1_ab.sh` runs one arm over eight seeds.

Altair Crossing, 1v1, 20 minutes, Apex vs BARb stable. Two independent batches
(seeds 1-8 and 11-18), pooled to 16 games per arm:

| arm | our K/D | their K/D | trade ratio |
|---|---|---|---|
| baseline | 0.347 | 1.271 | **0.273** |
| `TRADE_MARGIN_MAX` 1.0 -> 1.6 | 0.394 | 0.983 | **0.401** |

+47% relative, and it reproduced in both batches independently (0.252 -> 0.430,
then 0.307 -> 0.383). Metal production stayed at parity throughout (ratio
1.04-1.08), so this is the fight changing, not the economy.

**The direction matters more than the number.** A blanket higher bar made things
WORSE: `ENGAGE_MARGIN` 1.35 -> 2.0 dropped the ratio to 0.191 over 8 games. What
helps is caution that TRACKS the situation -- `TRADE_MARGIN_MAX` is the ceiling
on the 1/recentTradeRatio term, so raising it restores the "get more careful when
we are losing trades" half that was removed on 2026-08-08. That removal was
justified against a real problem (the term pinned at its ceiling all game, a bar
of 2.16, a spiral) but it deleted the feedback entirely by capping at 1.0. 1.6
restores it; the earlier failure was the ceiling being reached constantly, which
is a different complaint from the feedback existing at all.

**No win-rate improvement: every arm is 0-8, and so is the baseline.** The trade
moved a long way and the games did not, which is the honest state of it.

**The mechanism, seen live.** apexearth, watching a 1v1: "saw us make 1 welder
and engage an army of ~15 thugs with it" -- armzeus is 350 metal against roughly
1,800 of Thugs. `minAttackers` (the `attack` quota, default 8) is a flat POWER
threshold, so one high-power T2 unit clears it alone, and `minPower` is only ever
re-tested in `CAttackTask::RemoveAssignee`, when a unit LEAVES. Nothing stops an
attack advancing with one unit. `CDefendTask` already scales its requirement by
the largest known enemy group (`MilitaryManager.cpp` SetMaxPower); attack never
did. Added as `apex_attack_minpower_threat`, default 0 = unchanged.

**Rezbots were starved by the terrain block, not by the ratio.** apexearth: "we
need rezbots". The rezzer sat at 0.05 on `land` for all three factions while the
`air` block already used 0.09-0.12 -- so on every map actually tested they were
the rarest thing in the lab. Raised to 0.12 on land for `armrectr`, `cornecro`
and `legrezbot` together (faction parity for one change, not three experiments).
The 0.12 is anchored on the air block, not measured; factory ratios are
zero-sum, so it displaces something and needs its own A/B.

## 2026-08-09 (CORRECTED): the 25% close-range deficit was contamination

**The finding recorded earlier the same day is withdrawn. Read this instead.**

The arena sits at the map centre of a live 1v1, and each AI's real army walks
into it. `dev_arena.lua` now flags any round in which something outside the two
spawned sets landed a killing blow, and `arena.py` drops those rounds. **43-70%
of all rounds were contaminated.** They were not measuring the fight.

What exposed it: setting `dev_arena_nocontrol=3` removes BOTH sides' spawned
units from AI control, so neither AI is steering and the edge must be zero. It
read **-0.72**. An instrument that reports a three-quarter-unit tactical gap in a
fight neither AI is directing is measuring something else.

On clean rounds only, 2v2 Pawn, both orientations, 40-minute runs:

| arm | clean rounds | edge |
|---|---|---|
| baseline, both AIs steering | 96 | -0.20 |
| **neither AI steering** | 85 | **-0.12** |

Indistinguishable, and both near zero. **In an isolated equal-army fight we are
at parity with stock**, and AI orders move the result by about 0.08 units/round,
which is nothing. The earlier -0.46 was the surrounding match, and the tidy
range-dependence in the withdrawn table (even with a 475-range unit, -25% with a
180-range one) went with it -- a longer-ranged unit is simply harder for a
passing stranger to finish off.

Three combat constants were made runtime-tunable (`apex_orbit_rate`,
`apex_squad_spacing`, `apex_range_mod`; see CircuitAI `65ea323`) and A/B'd
before the contamination was known. Every arm was WORSE than leaving them alone
-- orbit off -0.95, lateral spacing off -0.77, standoff at 0.70/0.50/1.10 of
weapon range -0.89/-0.56/-0.64, against a -0.33 baseline. Those numbers are
contaminated too, but they are consistent and they point the same way, so the
current values are not obviously wrong and our own orbit and line-spacing
changes are not the problem. Nothing here justifies changing them.

**What survives, and it was measured outside the arena.** Six 20-minute 1v1
games on Altair Crossing: our metal production at parity (ratio 0.80-1.36,
median 1.09) against army K/D of **0.47 to stock's 1.42**, and we won 0 of 6.
We do lose the fighting in real games, with an equal economy to pay for it.

Putting the two together relocates the problem: it is not unit-level micro,
because that is at parity when the fight is symmetric and isolated. It is
**which fights we take** -- being caught at bad odds, piecemeal, or split. That
is engagement selection, and the arena as built cannot see it, because it hands
both sides the same army at the same moment by construction. Measuring it needs
either the real 1v1 games (army K/D, ~30s per game) or an arena that spawns
DELIBERATELY unequal forces and asks whether each AI correctly refuses the bad
ones.

## 2026-08-09 (WITHDRAWN, see above): we lose close-range fights by 25%

The first controlled measurement of fighting logic in this repo. `dev_arena.lua`
hands both AIs the SAME units, the same count, at mirrored positions, and
repeats the fight many times inside one match, so army size, economy, build
order and map position are all held constant and the only thing left varying is
what each AI does with the units. `tools/arena.py` scores it.

**Slot bias is real and must be cancelled.** Two self-play controls (apex vs
apex, stable vs stable) both gave ally 1 a ~1.0 unit advantage per round
(-0.93 and -1.08), and it did NOT cancel when the spawn positions were swapped,
so it is tied to the team slot, not terrain. Every result below is the mean of
both orientations (`tools/arena_ab.sh`); a single orientation is worthless. The
first probe, run one way only, said apex was +0.48 AHEAD -- the reverse
orientation showed the opposite, and the truth was -2.23.

Apex vs BARb stable, Armada both sides, edge = mean survivors we keep minus
survivors they keep, per round:

| units | unit (range) | map | rounds | W-L | edge | edge / force |
|---|---|---|---|---|---|---|
| 2 | armpw (180) | Altair Crossing | 126 | 41-67 | **-0.46** | -23% |
| 2 | armpw (180) | Avalanche | 109 | 28-56 | **-0.48** | -24% |
| 8 | armpw (180) | Altair Crossing | 81 | 18-32 | -2.23 | -28% |
| 16 | armpw (180) | Altair Crossing | 60 | 7-15 | -3.87 | -24% |
| 2 | **armrock (475)** | Altair Crossing | 83 | 30-29 | **+0.08** | +4% |

Two things fall out. The deficit is a near-constant **fraction** of the force at
every group size, including 2v2 -- so it is not a formation or coordination
failure that only appears in big groups, it is per-unit. And it is **absent for
a long-ranged unit**: dead even over 83 rounds, in both orientations
independently (+0.14 and -0.03).

This also relocates the 1v1 problem. Over six 20-minute 1v1 games on Altair
Crossing our metal production was at parity (ratio 0.80-1.36, median 1.09) while
army K/D was 0.47 against stock's 1.42. At 1v1 the economy is not the
bottleneck; the fight is.

**Not yet established: which change caused it.** Our four C++ commits add ~400
lines to `SquadTask` plus `MoveAction`/`TravelAction`/`CircuitUnit`, and none of
them was ever measured against a combat control -- the arena did not exist. The
standoff ring places a unit at `weaponRange * ATTACK_RANGE_MOD` (0.95), which is
a FRACTIONAL margin: 9 elmos of slack for a Pawn against 24 for a Rocketeer.
That asymmetry has the right shape to explain the table, but it is stock code
and stock wins, so on its own it is not the cause -- our orbit precession moves
the unit continuously along exactly that edge. Both are hypotheses. The bisect
is one arena run per commit and has not been done.

## 2026-08-08: the bank is empty, not full — the fraction-of-storage gates are dead

Measured on `matches/20260808-230041-…` (Supreme Isthmus 8v8, 40.7 min, apex =
ally 0). 583 `factory-diag` samples, 233 `fusion-gate diag` samples, 336
`BARAI_STATS` samples, read per player and per 5-minute bucket.

**Storage is built, by the C++ economy manager, not by any script rule.** No
script enqueues `Task::BuildType::STORE`; the only script-side requests are the
`store` entries in `build_chain.json` (`armuwadves`/`coruwadves`, +30,000 E) off
the T2 lab. Everything else comes from `CEconomyManager::UpdateStorageTasks`
under `IsMetalFull()`. Per player in that game: energy storage 36,000 on every
one of our eight; metal storage 10,000 on three of eight and **zero on the other
five**. Stock's split was comparable (13,000 / 10,000 / 3,000 / 0). Across four
maps the same pattern holds — metal storage is present on roughly half of both
sides' players. "We never build storage" is false.

**Metal fill by 5-minute bucket, our eight players pooled** (median of
`mCur/mStor`, and the share of samples with `isMetalFull=1`):

| min | median stor | median bank | median fill | isMetalFull |
|---|---|---|---|---|
| 0-5 | 1,300 | 1,139 | **0.91** | 56% |
| 5-10 | 1,350 | 856 | 0.63 | 37% |
| 10-15 | 1,450 | 18 | **0.01** | 15% |
| 15-30 | 2,700-3,800 | 11-32 | **0.01** | 0-8% |
| 35-40 | 3,700-3,925 | 127-133 | 0.01-0.03 | 5-17% |

Late-game (25 min+) per player, average income vs average bank: 92.5/s and 104
metal, 123.8/s and 68, 88.1/s and 124, 105.4/s and 412 — a bank worth **0.6 to
4 seconds of income**. We are metal-starved from minute 10 to the end, not full.
`metalExcess` for the whole game is 37-399 metal per player.

**The `isMetalFull` samples are dying bases.** Joining each `factory-diag` to the
nearest `BARAI_STATS`: `ownBuilders` > 5 → 12.4% full, mean fill 0.21;
`ownBuilders` 1-5 → 28.6%; `ownBuilders` = 0 → 75%, mean fill 0.79. Team 2 sat
10,400/11,850 for its last minutes with `armyReal=0` and `conT1=0`; team 3's
`mStor` fell 4,300 → 1,100 → 500 as its storage buildings died, and read
`isMetalFull=1` at 430/500. Storage shrinks when the base does, so a corpse
reads full.

**Energy is the opposite of the complaint.** Our `energyExcess` rate is 0 from
minute 14 to the end; stock wastes 4-8% of production over the same window
(2.15M on one player). Both sides spill 13-25% at minutes 8-10 only.

**So the fraction-of-storage gates almost never pass.** Share of samples clearing
each bar, our players, after minute 10:

| bar | rule | 10-25 min | 25 min+ |
|---|---|---|---|
| `>= 0.80` | `isMetalFull` (economy.as:30) | 4.8% | 5.2% |
| `>= 0.55` | `FUSION_MIN_BANK` (builder.as:1553) | 6.6% | 8.7% |
| `>= 0.50` | `NANO_MIN_BANK` (builder.as:1410), `SLING_FLOOD_FRAC` (military.as:103) | 8.3% | 8.7% |
| `>= 0.25` | `ECO_AID_KEEP` (military.as:227) | 11.4% | 18.7% |
| `< 0.20` | `isMetalEmpty` (economy.as:29) | 87.3% | 77.8% |

The only player that cleared them often (team 2, 25-35%) was the one that died.
`fusion-gate diag` passed its bank bar 14 times in 233 samples.

Corollary, because it inverts the obvious fix: **raising storage makes these
rules fire LESS.** The bar is a fraction of storage, so more storage raises the
absolute metal required while the bank stays at a few seconds of income. Any
storage increase has to be paired with a change of gate, not made on its own.

## 2026-08-08: the gantry cap WAS the T3 constraint

Single-variable change from the arm below -- `GANTRY_PER_INCOME` 150 -> 100 and
`GANTRY_MAX` 4 -> 6 -- measured the same way, 6 games, 8v8, Handicap 50.

| metric | gantry cap 100/6 | cap 150/4 | delta |
|---|---|---|---|
| **T3 plants built** | **16 gantries / 6 games** | 5 / 6 games | **3.2x** |
| T3 spend | 11,715 | 6,804 | +72% |
| corcat spend | 132,300 | 53,900 | +145% |
| metal built | 131,581 | 122,279 | +7.6% |
| **army share** | **14.6%** | 11.2% | **+30%** |
| **energy wasted** | **142,723** | 299,662 | **-52%** |
| T2 spend | 76,193 | 68,434 | +11.3% |
| mex upgrades | 5 | 4 | +25% |
| player-games wiped | 18/48 | 17/48 | ~same |

Total build normalised to the opponent is unchanged (61.3% vs 61.5%) -- this did
not make us build MORE, it changed WHAT we build, out of banked metal and wasted
energy and into T3 and army. Halving energy waste is the same story: T3 plants
and their units are where that energy goes.

"Building T3 gantry" decisions actually FELL, 50 -> 36, because the requests now
land: `WantMoreGantries` counts nanoframes, so a gantry that completes stops the
re-request. Fewer decisions, three times the plants.

### Cumulative, session start to now

| metric | ctl (session start) | apex (now) |
|---|---|---|
| metal built | 110,738 | **131,581** (+18.8%) |
| T3 spend | 3,483 | **11,715** (+236%) |
| army share | 12.5% | **14.6%** |
| energy wasted | 338,317 | **142,723** (-58%) |
| cons T2 held | 7 | **10** |
| player-games wiped | 24/48 | **18/48** (-25%) |

Still a long way behind stock, which fields 45% army on 214,826 metal built.

## 2026-08-08: measured -- the six changes are a net win

Paired tournaments, 6 games each arm, 8v8 Ascendancy, Handicap 50, same seeds and
settings. Control is `ctl` regenerated to session-start HEAD (the old frozen
`ctl` was several commits stale and would have measured the wrong thing).

| metric | apex (new) | ctl (control) | delta |
|---|---|---|---|
| metal produced | 150,240 | 138,252 | +8.7% |
| **metal built** | **122,279** | **110,738** | **+10.4%** |
| T2 spend | 68,434 | 62,309 | +9.8% |
| **T3 spend** | **6,804** | **3,483** | **+95%** |
| cons T1 (peak) | 22 | 22 | 0% |
| cons T2 (peak) | 9 | 7 | +29% |
| energy wasted | 299,662 | 338,317 | -11.4% |
| army share | 11.2% | 12.5% | -10.4% |
| **player-games wiped out** | **17/48** | **24/48** | **-29%** |

Normalised to each arm's own BARb opponent, because stock itself varied ~9%
between arms: metal built went from **51.4% -> 61.5%** of the opponent, and T3
spend from **9.8% -> 16.2%**.

Win rate says nothing, as expected -- 5 of 6 and 4 of 6 games hit the time limit,
and both decided-game CIs include 50%.

**The feared constructor sink did not happen.** 1,763 reclaims across 6 games
looked like a constructor time sink, but peak T1 constructors is identical (22 vs
22), peak T2 constructors is UP (9 vs 7), and metal built is up 10%. Clearing
obsolete buildings pays for its own constructor time.

The one regression is army share, 11.2% against 12.5%, and it is small. The gap
to stock remains the real story: stock fields 43.7%.

## 2026-08-08: the constraint is build power, not space

apexearth, watching an 8v8 on Ascendancy live: "we losing because we werent
making t3 enough even tho our economy was matched", and earlier "we're failing
to use all of the resources we make... i see them building [gantries] now at 36m
but i'd say that was too slow."

`composition.py` on that game says he was right on both halves, and identifies
which one is causal:

| per player | apex | stock BARb |
|---|---|---|
| metal produced | 240,298 | 258,209 |
| **metal built** | **177,462** | **243,352** |
| T3 spend | 10,215 | **51,334** |
| army share | 16.1% | **44.8%** |
| cons T1 (peak) | 35 | **61** |
| cons T2 (peak) | 6 | **15** |

The economy WAS matched -- we produced 93% of stock's metal. We then **built only
73% of what we produced**, against stock's 94%. Roughly 63,000 metal per player
was made and never turned into anything, and the shortfall lands hardest on the
most build-power-hungry thing on the board: stock spent **5x** more on T3.

Peak constructors held is where it comes from: 35 vs 61 at T1 and **6 vs 15 at
T2**. This is not a placement problem and not an affordability problem -- income
was 312-516 metal/second, far above the ~250 where CLAUDE.md notes the
affordability argument inverts, and 16 gantry requests went out. There was
nothing to build the requests with.

Note this contradicts the natural reading of the base-layout work below. Sprawl
is real and worth fixing, but on this evidence it is not what stopped the T3.

### "No room to tech up" did not happen in these games

Six-game 8v8 tournament, Handicap 50, 1,907 `techroom` samples:
**`techroom=-1` occurred ZERO times.** There was always a site for an advanced
lab within 1800 elmos of the base anchor, at every minute of every game, and the
distances cluster at 200-700 elmos -- i.e. close in, not out at the edge of the
probe. `blocked=1` appeared in 7 samples out of 1,907.

So on this evidence sprawl is **not** what stopped the gantries, and the base
layout work should not be credited with fixing T3. Walkability, self-walling and
density are still real problems worth solving; "no room to tech up" was not the
mechanism here.

**Caveat on this measurement**: the probe lives in `baseplan.as`, which only the
treatment variant has, so there is no before/after comparison -- only "after is
fine". A pre-change baseline would need the probe added to the control too. Worth
doing before this is treated as settled.

### Where the T3 actually went: 2 gantries against stock's 7

Same watched game, unit by unit from `allBuilt`:

| | apex | stock BARb |
|---|---|---|
| total built | 1,419,697 | 1,946,820 |
| **T3 share** | **3.9%** (54,800) | **26.7%** (520,600) |
| T3 plants | armshltx 15,800 = **2** | armshltx + corgant = **7** |
| T3 units | banth 1, thor 1, vang 1 | Sumo, Juggernaut, Catapult, Korgoth |
| armfark built | **0** | 5,460 |

apex's first T3 metal appears **after minute 26** and totals 42,050. Stock poured
429,000 into T3 units.

Two gantries is not an accident, it is the configured answer:
`GANTRY_PER_INCOME = 150` with `GANTRY_MAX = 4`, so a player at 400 metal/second
wants `400/150 = 2`. The comment above that constant records fixing a worse bug
(`gHaveT3` latched the AI to exactly ONE gantry per game), but the replacement
still caps throughput far below what stock reaches by having no T3 logic at all.

The other half is completion, not intent: **16 "building T3 gantry" decisions
were logged and 2 gantries exist.** `AiGetFactoryToBuild` returns the gantry and
the request dies downstream. Which of the two -- the cap or the completion rate --
dominates is not yet established, and is the next thing to measure rather than
guess.

apex also built ~66 `armack` (27,090 metal) to stock's ~10, while holding fewer
T2 constructors at peak (6 vs 15). We are buying advanced constructors and losing
them.

### armfark/corfast promoted to builder once an advanced con is held

`behaviour.json` parks armfark (Butler, 210m, 140 build power) and corfast
(Twitcher, 210m) as role **support**, not builder, with a documented reason:
`CFactoryManager::GetFacRoleDef` filters the recruit draw on `GetMainRole`, so at
builder weight they take a share of the draw away from armack and delay the
team's single shared advanced constructor -- which gates T2 mex upgrades.

That reason is entirely about the RACE for the first one, and it expires. Once
`gHaveAdvCon` is true there is nothing left to delay, and 210 metal for 140 build
power is the cheapest build power in the game. `Builder::PromoteAssistBots` now
calls `SetMainRole(RT::BUILDER)` at that moment, once.

Legion needs no equivalent: `legaceb` (Proteus, 310m) is already role builder in
`behaviour_leg.json`. Checked rather than assumed -- `legfast` does not exist in
either tree, and the faction-parity trap is the recurring one here.

### T1 towers are no longer offered past their tier

apexearth at 25 minutes on 130 metal/second: "i still see some of our cons
retreating from front line to build a light laser turret, the t1 super crappy
turret... at this point we shouldn't be making those anymore."

`ContestTower` chose the tower from the **constructor's** cost and nothing else --
`costM >= ADV_CON_COST` got corvipe/armpb/legapopupdef, everything else got
corllt/armllt/leglht. A T1 constructor was therefore offered a light laser at
minute 25 exactly as at minute 3. It now returns null past T1 tier, so the
constructor falls through instead of walking home. This STOPS work rather than
redirecting it, which is why it is safe to add on its own.

### Why obsolete reclaim "fired twice in thirty minutes"

Not the gates -- the queue position. `ObsoleteReclaim` sits at line 2762, near
the END of `AiMakeTask`, so a constructor is offered mexes, defence, converters,
nanos, fusions and wreck reclaim first and only ever reaches the tidy-up if every
one of those declines.

`ObsoleteUrgent` now runs it **ahead of the economy offers** -- the cheapest
constructor time in the file -- gated on being past T1 tier AND 6+ T1 structures
standing. Deliberately NOT moved above mex expansion: that is the documented way
this repo previously cut its own metal production 4.3x.

`ReclaimOwnDef` also now chooses WHICH copy to eat by geometry rather than
whichever the engine listed first -- one standing in a walkway scores above one
stranded outside the footprint, which scores above a tidy one in a row.

## 2026-08-08: one base layout, replacing position-plus-shake

apexearth: "every placement is (position, shakeRadius) and the engine slides the
site anywhere in that radius. There's no footprint, no rows, no lanes. That's why
tuning the radius trades sprawl against self-walling and never fixes either."

That was exactly right, and there was more of it than expected. Three separate
lattices existed -- `BandSpot` (nano rows plus eco flanks), `ConvSpot` (the
converter block) and `RearPos` -- each re-deriving its own axis from `gHomePos`
and the enemy centroid, none aware of the others, and **none asking whether
anything could stand where it pointed**. Everything else went out with the
default shake of 256 elmos.

New `manager/baseplan.as`, namespace `Base`: one anchor (the first factory,
latched), one axis (toward the front via `Front::FrontNear`, which falls back to
the start-box lane so it is stable from frame 0), and walkways defined in **world
offsets** rather than column indices, at a 720-elmo pitch, so bands on different
pitches leave their gaps in the same places and the gaps line up into an actual
corridor. Cells are validated through `ai.FindBuildSiteNear` before being handed
out, then enqueued with **shake 0**.

### The rules this first governed were all switched off on the benchmark

Measured: `placed=0` across an 8-minute and a 25-minute 4v4. Every rule put on
the grid first -- nanos, fusions, the converter block, the generic converter --
is eco-lead-only, and `ECO_ON_SMALL_TEAMS = false` with `BIG_TEAM = 6`, so at
4-per-side the eco lead never activates. Comet Catcher is a 4v4 map, so on the
standard benchmark the whole subsystem is inert. This is the CLAUDE.md
benchmark-economics trap in a new place: not income this time, but team size.

### So the grid is applied in C++, to every placement

`IBuilderTask::Execute` did `pos = (shake > 0) ? get_near_pos(position, shake)
: position`. It now snaps to a grid published from script
(`ai.SetBaseGrid(anchor, fwd, cell, lanePitch, laneHalf, range)`, the same
mechanism `SetFrontPos` uses), falling back to the old jitter when there is no
grid -- so stock BARb and the `ctl` control are unaffected and remain a valid
baseline.

Excluded by build type, for two different reasons. MEX/MEXUP/GEO/GEOUP/DEFENCE/
BUNKER/BIG_GUN/PYLON/TERRAFORM have to stand on a particular piece of ground and
would be ruined by being moved. **FACTORY is excluded for the opposite reason**:
packing labs into the lattice is what leaves no room to tech up, and keeping that
room free is what the lattice is for.

Cell 72, lane pitch 720, lane half-width 72, range 2200. Every band pitch and
band depth in `baseplan.as` is a whole multiple of the cell -- load-bearing,
because the C++ snap applies to the script's own placements too, and a band on
some other pitch would have its own cells moved off it.

### Measurement for the criterion apexearth named

"Can we still place a T2 lab at minute 30" was previously invisible -- it only
showed up as a build that quietly never happened. `Base::Update` now probes it
directly each minute via `FindBuildSiteNear` on the side's advanced lab and logs
how far out it had to go:

    apex: base area=<elmos^2> width= depth= placed= noroom= blocked= techroom=

`techroom=-1` means no site within 1800 elmos of the anchor. Base bounding-box
area and blocked-placement count are on the same line.

**Not yet measured for effect.** Compiles, loads, latches a sane frame
(`cols nano=26 eco=18 heavy=10`), zero AngelScript errors over two runs. What it
does to composition is unknown, and by the rule that firing is not evidence, that
is the number that decides it.

## 2026-08-07: naval response was switched off entirely

apexearth: "we suffer lots from enemy subs, we don't make enough torp launchers
or destroyers at t1... the destroyer is one of the best units to build along
with the submarine... if you spam a whole ton of subs, you can win an entire
water battle unless the enemy has T3 hovers."

`response.json` explains it. `anti_sub` was zeroed on every field:

    "anti_sub": { "vs": ["sub"], "ratio": [0.0], "importance": [0.0],
                  "max_percent": 0.00, "eps_step": 0.00 }

against stock BARb's `ratio 0.8, importance 5.0, max_percent 0.30`. And the
`"sub"` entry stock ships was **absent from our config altogether**. So the AI
had no response to enemy subs and no reason to build subs of its own. This dates
to the original apex import (`9d04b5a`), not a recent regression -- it has been
off the whole time.

The roles exist and are wired: `armroy` (Corsair, T1 destroyer, 880 metal) is
`anti_sub`, `armsubk` is `anti_sub`+`sub`, with Legion equivalents in
`behaviour_leg.json`. `response.json` is shared across all three factions, so
one fix covers faction parity.

Now `anti_sub` ratio 0.9 / importance 500 / max_percent 0.45, and `sub` restored
at ratio 0.6 / importance 300 / max_percent 0.6 -- above stock's 5.0 importance
because both units stay relevant well past T1.

Both are demand-driven (`vs` gates on enemy roles present), so neither can fire
on a land map. Unmeasured beyond "no config errors, no script errors".

### The overlay vanished because BAR erases map marks after 60 seconds

`luaui/Widgets/map_auto_mapmark_eraser.lua` ships with `eraseTime = 60` and
deletes every mark 60 seconds after it appears. So the previous commit's
"draw chokepoints once" was exactly backwards -- the layer disappeared a minute
in, which is precisely what was reported. Chokepoints are redrawn every pass
again. That widget also means marks CANNOT accumulate, so the 21,000-stale-lines
worry in that commit was wrong; the erase bookkeeping is now belt and braces.

The front lines were missing for a different reason: `Draw` only draws FRONT
cells, and FRONT requires `gFoeKnown`. Each AI's influence map holds only what
that AI knows, so if the single drawing AI is a rear player that never sees
anyone, the overlay is empty all game. The enemy bearing is now pooled across
the team over the blackboard (`apexFoeX/Z/W`), weighted by sighting count, so a
forward teammate's contact gives everyone behind them a real front.

## 2026-08-07: front vs back, and the front starts UNKNOWN

apexearth on the undirected perimeter: "the perceived frontline is behind us,
not even facing the enemy, its also too small so we have obvious gaps... the
front line is really where our territory ends and the enemy's territory is about
to begin... you might say in the beginning of a game the frontline is completely
unset / unknown."

Two errors, both fixed:

- **Too small, with gaps.** Territory was thresholded at 15% of peak ally
  influence, which selects the dense CORE. Its edge therefore sat behind our own
  army. Territory is now 3% (~15 against a ~520 peak) -- everything we
  meaningfully hold. Perimeter went from ~30 patchy cells to ~100 wrapping the
  whole territory.
- **Behind us.** A ring has no direction; half of any ring faces our own rear.
  The ring is now split against the bearing from our territory centroid to the
  enemy centroid: FRONT faces them, BACK is the fog behind us. Measured on Jade
  8v8: ~53 front / ~47 back of ~100.

Enemy position is REMEMBERED, not sampled (`gFoeSeen`, +1 per sighting, 0.995
decay per scan). Enemy influence only holds units currently known, so a raid
that passes through vanishes seconds later -- but the fact their territory lies
that way does not stop being true. Without the memory the bearing flickered.

**The front is UNKNOWN until an enemy has been seen**, and says so rather than
guessing: 240 of 673 samples in one game had foeKnown=0 (early game, and rear
players who never see anyone). `Front::IsFrontKnown()` exposes it; `FrontNear`
returns false rather than inventing a direction.

Overlay draws map LINES, not points. Points are pings -- each one fires an alert
and a minimap flash, unreadable at this density.

### Deploys keep failing silently while a game runs

Three deploys this session did nothing because a watch game held the files;
`cp` said "Device or resource busy" and the game-side script kept old code. Two
headless runs then reported on stale files. The deploy step now aborts if a
spring/Beyond-All-Reason process exists, and the deployed FILE is grepped for
the change rather than trusting deploy's exit.

Also walked into two documented traps again: a `str.replace` without an assert
silently did nothing, and `out` is a reserved AngelScript keyword (32 compile
errors, which disable the whole variant while the match still reports normally).

## 2026-08-07: the front is our own perimeter, not a seam

Three definitions of "front line", each killed by measurement, in order:

1. **Cells where both sides are present.** Found nothing. One Jade 8v8 scan had
   339 ally cells and 56 enemy cells and **zero** holding both -- where one side
   is strong the other reads ~0, so the fields are effectively disjoint and an
   overlap test only fires where both are so faint it means nothing.
2. **Cells on the boundary between the two fields.** Found 2-3 cells. Enemy
   influence counts only KNOWN enemy units, so it is far too sparse to draw a
   line with.
3. **The outer edge of our own influence region.** 102-112 cells spanning
   x3072-12492, z1843-7987 -- a real perimeter across the map. Needs no vision,
   exists from minute one, and is what a player means by their front: the edge
   of what we hold. Perimeter cells adjacent to known enemy influence are marked
   HOT; the rest is quiet flank that still has to be held.

**The two fields are not on the same scale.** Ally influence counts everything
we own and peaks around 520; enemy influence counts only what we have seen and
peaks under 33 in the same scan. An absolute presence floor of 5 erased the
enemy field completely -- every AI read cFoe=0 for an entire game -- so the
front vanished instead of moving. The floor is now 1.0 and the per-side
fraction does the work.

**Deploys fail silently while a game is running.** Two deploys during a watch
game did nothing; `cp` of the DLL reported "Device or resource busy" and the
game-side script kept the old code. Two headless runs then "tested" stale files
and produced results I nearly believed. Always confirm the deployed file
contains the change, not just that deploy exited.

Also: a `str.replace` without an `assert` silently did nothing, again, which is
what put a call to the non-existent `ai.GetTeamPos()` into a file that then
appeared to deploy fine.

## 2026-08-07: the front line is not at the chokepoints

Step 2 of the front-line work: classify each chokepoint ours/contested/theirs
against the influence map. It produced a result that invalidates the plan it was
part of.

Influence is now bound to script (`GetAllyInflAt`, `GetEnemyInflAt`,
`GetNetInflAt`), bounds-guarded -- `CInfluenceMap::PosToXZ` does NO bounds check
and indexes `enemyInfl[z * width + x]` straight from the raw position, the same
unchecked pattern that made `GetBuilderThreatAt` kill the engine at frame 3.

**Classify on ally and enemy separately, never on the difference.** Net influence
reads 77 beside our base and exactly 0 on ground nobody has been near, so a
difference-based test calls both "balanced" -- and most of the map is the second
kind. A seam requires BOTH sides present.

**Terrain chokepoints are not where the fighting is.** Jade Empress 8v8, 63
usable chokepoints:

| | |
|---|---|
| chokepoints ours | 23-36 |
| chokepoints contested | **0** |
| chokepoints theirs | **0** |
| influence-grid cells with BOTH sides present | **55-77** |

The contest is real and none of it lands on a chokepoint. BWEM chokepoints on
these maps are base entrances and interior pockets; the fighting happens in open
ground. Comet Catcher is the same story -- its 8 chokepoints sit at 6584,392 and
1048,4632, i.e. the two start corners.

So holding chokepoints would mean turtling at our own base entrance, which is
the opposite of a forward line. The front line is now read off the influence
field directly (`Front::SeamNear`), with chokepoints kept as a SECONDARY filter:
`Front::SeamChoke` returns a seam cell that also sits in a corridor, which is
the best metal-per-tower on the map when it exists, and returns false when the
front is in open ground -- the common case.

**Each AI has its own influence map.** Same game, same moment, on Jade: forward
teams read 72-82 enemy cells and a 55-77 cell seam; rear teams read cFoe=0 and
no seam at all. A rear player computing this alone concludes there is no front
line. Anything consuming the seam must share it across the team via
PublishTeamValue/ReadTeamValue rather than trust the local read. This cost an
hour of chasing a "seam=0" that was really a sampling artifact -- an `awk`
stride that happened to lock onto one rear team.

Also bound: `DrawPoint`/`DrawLine`/`DrawErase`, which place ordinary in-game map
markers via the already-present `springai::Drawer`. `Front::DRAW` is currently
**on**, drawing every chokepoint with its ownership and every seam cell as
FRONT. Allies and spectators see these -- turn it off before multiplayer.

No behaviour change yet: nothing consumes the seam.

## 2026-08-07: BWEM chokepoints exist, and were unreachable

CircuitAI vendors a full BWEM (Brood War Easy Map) implementation in
`circuit/map/GridAnalyzer.cpp`: every game it decomposes the map into areas
joined by chokepoints, with geometry, width and area adjacency. **Nothing could
read it.**

`CDefenceData::Init` pushes every chokepoint into `defPoints`:

    for (bwem::CChokePoint* ch : terrainMgr->GetTAChokePoints())
        defPoints.push_back({ch->GetCenter(), .0f});

but every consumer selects through `GetDefIndices(clusterIndex)` ->
`clusterInfos[k].idxPoints`, which is populated ONLY by the metal-cluster loop.
No cluster ever references a chokepoint index. The one path that could have
reached them -- a `knnSearch` over the whole `defPoints` tree -- is commented out
in `CDefenceData::GetDefPoint` behind `FIXME: Re-work cluster-only points into
search-tree`. `MilitaryManager.cpp:753` holds a second, also commented-out,
chokepoint block. Upstream built the analysis and left it unwired.

**Consequence: every defence position this AI has ever placed was anchored to a
metal cluster.** That is why defence reads as "towers around bases and mexes"
and never as a front line, and it is the likeliest reason ~9 attempts at
geometric wall/front-line placement all failed -- they were interpolating lines
with `BorderPos`/`FrontPos` while the real corridor topology sat unused.

Exposed read-only to script (no behaviour change): `GetChokePointCount`,
`GetChokePointPos`, `GetChokePointWidth`, `GetChokePointEnds`,
`GetChokePointArea`. Width is recomputed as `|end1 - end2|` because
`CChokePoint::size` is private and only `IsSmall()` (< 300) is public.

Verified returning real data, not the `Game_getTeamResource*` failure mode:

| map | chokepoints | usable (200-2000 wide) |
|---|---|---|
| Comet Catcher Remake (16x12) | 8 | 5 |
| Jade Empress 1.41 (32x32) | 100 | -- |

Jade's widths run 22 to 2806; most of the 100 are sub-200-elmo slivers between
interior areas, so the raw count is not the usable count. Area ids form a real
graph (1/2, 1/3, 5/6, 11/12, ...), which is what a "which corridor do enemy
reinforcements flow through" query would run over.

Not yet used by any behaviour. Next: classify each chokepoint ours/contested/
theirs against the influence map, then anchor defence to contested ones, then a
hold task that does not promote itself into an attack.

## 2026-08-07: constructors no longer pre-empt themselves into reclaim

`AiMakeTask`'s tail handed EVERY idle non-commander builder a wreck reclaim
before returning. Per the code's own `REZ_WRECK_PERIOD` comment, ordinary
constructors already get a RECLAIM offer from `DefaultMakeTask` (isResurrect is
false for them), so this path never ADDED reclaim -- it jumped the queue ahead of
the mex expansion that lives in `DefaultMakeTask`. Now rez-bot only; they still
need the pre-empt because for them the engine's offer is a 300s RESURRECT.

Motivating measurement, one 8v8 on Jade Empress 1.41 (32 min, no control):

| | Apex | BARb hard |
|---|---|---|
| mexes | 233 | **394** |
| T2 mexes | 25 | **44** |
| metal produced | 293k | **485k** |
| metal reclaimed | **13.8k** | 8.9k |
| killed / lost | 60k / 122k | 106k / 86k |
| PEAK constructor metal | 17,770 | **59,275** |

We were already out-reclaiming BARb 1.5x while falling 161 mexes behind. Mex
counts are level to minute 8 (83 vs 87) and diverge from 14 on (133/151, 186/248,
217/319, 233/394) -- we do not lose the expansion race early, we stop expanding.
A 0.49 trade ratio on 60% of the enemy's economy is about what the economy alone
predicts, so this is a candidate root cause for the long-standing K/D deficit
rather than a separate problem.

One game, no control. Unverified as an improvement -- the change is a REMOVAL,
which per the "path fires" section is the cheap kind to try and revert.

## 2026-08-07: RESULTS BELOW WERE VOID -- read this first

**Every tournament result in the section below was measured against a BARb with
no AI script, and is meaningless.** Kept, struck through, because the failure
mode is worth more than the numbers were.

Cause: `deploy_ai.py`'s stale-cleanup deletes `BARb/<variant>` to remove old
version-style deploys. `variant` is also the VERSION, so deploying a variant
named `stable` resolved that to `BARb/stable` -- the baseline -- in BOTH halves:
the engine-side folder AND `BAR.sdd/luarules/configs/BARb/stable`. The
engine-side half was noticed and restored from `files.md5.gz`. The GAME-SIDE
half was not, and that is where stock BARb's `hard`/`medium`/`easy` profile
scripts live. Engine-side ships only the `dev` profile.

So from that point on, `BARb:stable:hard` and `:medium` loaded, logged
`Game-side script: 'LuaRules\Configs\BARb\stable\script\hard\init.as' is
missing!`, and then did nothing. Commanders stood still all game.

**This reads exactly like a triumph.** 16-0 on every faction, 8-0 at 8v8 on the
configuration that had gone 0-8 hours earlier, games "won" in 19 minutes instead
of 40. Every one of those numbers is an artifact. The 19-minute games were not
fast wins, they were walkovers against a corpse.

What survived:
- The **0-8** 8v8 result from BEFORE the deletion is real.
- Both self-play A/Bs (`Apex` vs `ApexCtl`) are unaffected, since both sides are
  ours -- and both said the new strategic work does NOT help: 11-13 and 9-11.
- With BARb restored and verified (0 missing-script errors, 363 AI log lines vs
  12, army 18,470 vs 17,790 over a full 20 min), we are roughly EVEN with BARb
  hard, not dominant.

Detection: an AI that loads but never acts logs almost nothing. BARb produced 12
lines across a whole game against apex's 851. `tools/feature_audit.py` reports
per-game coverage and would have caught this instantly had it been pointed at
the OPPONENT rather than only at us. Check the opponent is alive before believing
a win rate -- a walkover and a triumph are the same number.

## 2026-08-07: the aggression session (RESULTS VOID, SEE ABOVE)

Measured after the night's batch, all on engine `recoil_2026.07.04`:

| test | result |
|---|---|
| 4v4 vs `BARb:stable:medium`, Cortex | **16-0** |
| 4v4 vs `BARb:stable:medium`, Armada | **16-0** |
| 4v4 vs `BARb:stable:medium`, Legion | **16-0** |
| 8v8 vs `BARb:stable:hard`, Supreme Isthmus +40% | **8-0** |

The 8v8 number is the one that matters: **the identical configuration went 0-8
earlier the same day**, and games now end around 19 minutes instead of running
to the 60-minute cap. Legion, historically the weak faction at ~40%, is level
with the others.

Two causes, both found by reading a real multiplayer game's infolog rather than
the benchmark:

- `ENGAGE_MARGIN` was 1.80, i.e. we demanded 80% more power than whatever
  defended a target. In one live game: 492 engage decisions, **3,973 candidate
  groups refused as too strong**, and `edge=0.00` on every sample -- meaning the
  target finally accepted had no defenders at all. The AI was refusing every
  real fight and attacking empty ground. Now 1.35.
- `quota.attack` was restored to stock BARb's value after the rush window --
  **15**. From mid-game on, only fifteen units per player could ever attack, and
  slots filled first-come so a T3 unit finished later never got one. Now
  `LATE_ATTACK_QUOTA = 200`, so the odds test decides who fights instead of an
  arbitrary cap.

**Do not read these as "the AI is solved".** Every one of these games is against
another AI. The whole reason this batch exists is apexearth's observation that
BARb is not the right measure, because humans punish timidity in ways BARb never
does. A 16-0 against medium mostly says the build is not broken.

### Self-play A/B, and what it does NOT show

`ai/ctl` is a frozen copy of the build above, deployed as shortName `ApexCtl`,
so later changes can be A/B'd by self-play instead of against a win rate already
saturated at 100%. First use, 12 games Cortex 4v4, new build (juggernaut charge
+ `AIR_FROM` 11 min) against it: **9-3, 75%** -- but the 95% CI is 47-91%, which
includes 50%. That is suggestive and **not** a demonstrated improvement. Twelve
games cannot resolve an effect this size; it needs ~40 to separate from noise.

### The juggernaut charge is UNVALIDATED, and the benchmark cannot validate it

Built, compiles, and has a log line (`apex: juggernaut charge`) specifically so
it can be observed. Across 8 games of 8v8 vs hard it fired **zero** times -- for
a reason that is not a bug: **no juggernaut-class unit was ever built**. Two
gantries total, and a 19.1 min median game length. A corjugg is 20,000 metal;
the games end long before one exists, *because the AI now wins quickly*.

So this feature is unreachable in the current benchmark, and no amount of
running it will say anything. Validating it needs a scenario with a much longer
game or a pre-seeded T3 force. **Do not tune it from benchmark results** -- there
are none, and there will not be any.

### Feature coverage, measured

`tools/feature_audit.py` reports which strategies actually fired. Every feature
that can fire under some condition has now been seen firing in at least one:
eco lead (8/8 at 8v8 only -- it is off under 6 per side by design), air strike
(8/8 at 8v8, 14/16 Legion, 7/16 Cortex -- it needs game length to mass), T3
gantry (11/16 Legion), rich-wreck reclaim (8/8 at 8v8), tech-lead handover (3/8,
72 fires -- a behaviour that did not exist before the latch fix).

Two remain unvalidatable here and are annotated in the tool: `cheap AA` (BARb
medium builds no air at all -- confirmed, every air unit in those 16 games was
ours) and `commander retreat` (nothing ever threatened our commander; **zero**
commanders lost across the 8 games vs hard).

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

### `SQUAD_SPEED_RATIO` 2.5 -> 3.5 — `AttackTask.cpp` — tuned on one Cortex pair, verified to fail for Legion

2026-08-05. `CAttackTask::CanAssignTo` gates squad merging on
`speedSlower * SQUAD_SPEED_RATIO >= speedFaster`; below that, the slower unit
is refused and fights alone. The constant was 2.5, chosen to just admit one
specific Cortex pair (Banisher 54 / Mammoth 22.5 = 2.4) -- faction-specific by
construction, since it was never checked against the other two factions.

Checked directly: Legion's comparably-common T2 pair, `legstr` (84 speed) and
`leginc` (24 speed, weighted up to 0.38 of `legalab`'s build share at some
income tiers -- not a rare unit), has a natural ratio of 3.5 and failed the
old 2.5 gate outright. `leginc` could never merge into a squad with its own
faction's fast T2 escort and fought alone every game, in exactly the T2-tier
window (~minute 14+) where a separate data-driven finding this session showed
Legion's combat trade starts eroding.

**Fix**: raised to 3.5, the minimum that admits the Legion pair, chosen after
checking it doesn't also swallow the genuine outliers this constant is meant
to exclude (Cortex's T3 superheavies at ~16.5 speed need 3.3+ and sit right at
the new boundary; scouts like `legscout` at 160 speed need ~6.7 and stay
excluded regardless).

Rebuilt (`ninja -C build-amd64-windows BARb`), smoke-tested clean on all three
factions (0 compile errors, correct script loaded, no crash). **Not yet
confirmed by tournament** -- this needs a large (64-96 game) solo batch per
faction before trusting a win-rate effect, per this session's own
hard-learned lesson about this benchmark's noise floor (see
`notes/open-issues.md` #45-52). Patch captured in
`game-patches/circuitai/0003-cumulative.patch`.

### Commander killer logging — `CCircuitAI::UnitDestroyed` — REVERTED, crashed

2026-08-04. This session had no way to see WHAT kills a commander -- the
AngelScript-side `AiUnitRemoved` hook (added the same session, see
`ba92167`) can log THAT and WHEN, but the attacker (`CEnemyInfo*`) is only
available in C++ and is not exposed to script. Added four lines in
`CircuitAI::UnitDestroyed`: if the destroyed unit `IsRoleComm()`, log the
attacker's unit name and 2D distance (or "UNKNOWN (no attacker)" if none --
env damage, self-destruct, capture).

**REVERTED.** A 4-game and an 8-game smoke test both came back clean
(`exit_code=0`, `crashed=false` on every game), which is why this was
believed safe and committed. A follow-up 16-game batch, collected purely for
more diagnostic data with no further code change, hit a real crash: access
violation (0xc0000005) inside `SkirmishAI.dll`, at the exact frame of a
`[BARAI_COMMLOST]` event -- 1 game in 16 (6.25%). Stack trace frames 0-2 are
inside our own DLL. Most likely cause: `attacker->GetCircuitDef()->GetDef()`
returning null in some circumstance this session did not characterise (a
simultaneous-death edge case, or a `CEnemyInfo` whose def was never fully
resolved), then `->GetName()` on that null pointer. Not root-caused with
confidence, and every further test costs a rebuild + multi-game batch to
even have a chance of reproducing the specific edge case, so the change was
fully reverted rather than patched blind. Source reverted in
`vendor/engine/` (gitignored, not visible as a diff here), DLL rebuilt from
the reverted source and redeployed, confirmed crash-free again over 4 games.

**Two lessons for a future attempt at this exact idea:**
1. **A handful of clean smoke-test games is not proof of safety for an event
   that only fires on death of a specific unit type.** A commander death is
   comparatively rare per game (this session's own data: roughly 2-4 per
   game), so a 4-8 game sample may simply not hit whatever specific
   circumstance triggers the crash. This is the same lesson `docs/`/CLAUDE.md
   already states for the AngelScript layer ("An AngelScript compile error
   disables the whole variant, and the match still runs") applied to C++:
   absence of an observed failure in a small sample is not absence of a bug.
2. **Null-check every pointer in the chain before dereferencing**, even ones
   that look like they should always be valid from the call site's contract
   (`attacker != nullptr` was checked; `attacker->GetCircuitDef()` and
   `->GetDef()` were not).

The killer-type data collected before the crash was found is preserved below
since it remains real data from real games (just from a build later proven
unstable in a way unrelated to the LOG call's own correctness under normal
conditions) -- read it as suggestive, not as settled.

**CORRECTED below -- the first read named `corthud` as artillery from the
name alone, the exact mistake `docs/`/CLAUDE.md warns about. Verified with
`tools/unitdef.py` before writing this version.**

**Read across two batches (4-game smoke + 8-game confirm, n=29 kills, 12
games total) — grep `apex: commander killed by`:**

| killer | count | mean distance | what it is |
|---|---|---|---|
| `corthud` "Thug" | 8 | 307 | Light Plasma Bot -- direct fire, medium range |
| `corban` "Banisher" | 7 | 575 | Heavy Missile Tank -- real ranged skirmisher |
| `corraid` "Brute" | 4 | 236 | Medium Assault Tank -- direct fire, close range |
| `corsumo` "Mammoth" | 3 | 498 | Heavily Armored Assault Bot |
| `corape` "Wasp" | 2 | -- | Gunship (air) |
| `corstorm`/`cormist`/`corllt`/`corlevlr`/`corcan` | 1 each | -- | mixed |

No single cause. Regular direct-combat units (`corthud`, `corraid`, `corcan`)
account for 13 of 29 kills (45%), a mixed group of ranged/heavier units
another chunk, and 2 kills came from the air -- not something the commander's
ground-based retreat logic can out-walk regardless of health threshold. The
one real pattern: `corban`'s mean kill distance (575) is roughly double
`corthud`'s (307) and `corraid`'s (236), consistent with it landing the
finishing hit from beyond where the commander perceived itself as clear of
the fight, which fits the burst-death pattern already found in
`notes/open-issues.md` issue 0.1 (a commander healing steadily at 84% health
dying within 2.4 seconds of the next sample). But this is one plausible
contributor among several causes, not a single dominant one -- do not act on
"cap corban's range" or similar as if it were the whole answer.

**This C++ source change lives in `vendor/engine/` only, which is
gitignored** (`.gitignore:2`). It is not visible as a diff in this repo's
history -- only the resulting `ai/apex/engine-side/SkirmishAI.dll` binary is
committed. A future session reading git log for this DLL's C++ provenance
will not find it there; this note is the record. The local
`vendor/engine/` clone is itself persistent on this machine (per
`docs/06-building-the-dll.md`, "the tree is already cloned, patched and
configured"), so the actual source edit does survive across sessions here,
just not in git.

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

### BUILD_PHASE gate on the optional economy/AA cluster — measured, confirmed

2026-08-04. `docs/12-build-phases.md` (apexearth's design) diagnosed the
recurring failure behind a long run of negative isolated-spend experiments
this session (heavy AA in three forms, eco-for-everyone, advanced-con
priority, cornecro cap — all measured worse or neutral, see
`notes/open-issues.md` "SESSION SYNTHESIS"): every one of them claims
constructor time, which is the actual scarce resource, and something else
— usually army — pays for it. `Factory::ComputePhase()` (a diagnostic added
the same session, driven from state — mex count, `gHaveT2`, fusion count,
gantry presence, `RushReady()` — never a clock, so it falls back down on
its own if a signal drops) made it possible to test the design's own fix
directly: defer a CLUSTER of optional investment rules together, rather
than one at a time.

`AiMakeTask` (`builder.as`) now gates `CheapAA`, `HeavyAA`, `Pulsar`,
`EcoConverters`, `EnergyConverter`, `EcoNano` and `EcoFusion` — the exact
block a standing comment in this file already named as the historical
danger ("Twelve rules pre-empting here... cut metal production 4.3x") —
behind a `Factory::gLastPhase` threshold. The reflexive `RepairNear`
(con-heal) rule stays ungated, per the design's own phase-gated-investment
vs never-gated-reflexive split.

Three thresholds tried, each against the established 7.9% baseline
(95% CI 3.9%-15.4%, n=89):

| threshold | meaning | decided win rate | games run to the full time limit |
|---|---|---|---|
| `phase >= 2` | `mex >= 4` | 0% (0/13) — reverted | typical |
| `phase >= 3` | `RushReady()`, economy can afford to tech | 22.7% (5/22), P=0.0260 | ~70% |
| `phase >= 4` | `gHaveT2`, an advanced factory actually finished | **60.0% (6/10), P=0.00004** | **~87%** |

**`phase >= 4` is what shipped.** `mex >= 4` was too early to matter;
"the economy could afford to tech" (phase 3) still isn't the same test as
"it actually has" (phase 4) — CheapAA/HeavyAA/Pulsar/the eco block were
still competing with the mex-upgrade and factory-building work that gets a
player TO T2 in the first place, right up until phase 3's bar. Gating
until the advanced factory is actually standing removed that competition
at exactly the point that mattered. Most games under this gate now run the
full 25-minute time limit as genuinely competitive draws rather than being
decided either way — a second, independent signal alongside the win rate
itself.

This validates the design's core claim directly: resolving competition
across a CLUSTER of rules together, not tuning or gating any one of them
alone (five prior isolated-spend experiments this session all failed for
exactly that reason), is what moves the outcome — and getting the
THRESHOLD right, per the design doc's own "hardest part" section, mattered
as much as the mechanism itself. **Still not statistically proven
"reliable"** at n=10 (the 95% CI's lower bound, 31.3%, is real progress but
not yet a guarantee) — worth a larger confirmation batch before treating
60% as settled.

**Not yet fully explored**: whether an even higher or lower threshold does
better, whether more rules (`ConDugIn`/`Fortify`) belong in the gated
cluster, and whether the same pattern holds on other maps/handicaps. The
design doc's own "hardest part" section (calibrated transition conditions,
not the phase concept) remains the open work.

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

### Killing blow — dominance that actually ends the game
Measured baseline: across 30 games on 8 maps, **20 (67%) hit the time limit
undecided**, and on Quicksilver we finished 16 games holding 4.5x stock's metal,
35x its T3 and 8.5x its army with ELEVEN unresolved. apexearth: "we are often
winning but we're very slow to kill enemies ... we need some sort of switch which
says ok now go for the killing blow."

Past 15 minutes, once OUR TEAM's army is worth 1.8x the enemy's, the attack
minimum drops to 10, any turtle hold is released, and both massing and turtling
are stopped from re-engaging. Hysteresis at 1.5x so one lost fight does not flip
it mid-push. The eco lead is exempt -- it holds no army by design.

`quota.attack` is a MINIMUM before the engine forms an attack, and UpdateMassing
walks it to MASS_CAP and pins it there whenever the enemy out-values us. Once far
ahead that gate is pure delay: we sit on an army several times their size waiting
for a bigger one.

**measured**: undecided games **67% -> 17%**, records of 4-2, 5-0 and 3-2 across
three 6-game 4v4 sets; one watched game on Supreme Isthmus won at 28.9 min where
both baseline games there ran out the 50-minute clock undecided.

Two bugs on the way, both worth remembering:
- The first version compared `aiMilitaryMgr.armyCost` (ONE player) against
  `EnemyArmyCost()` (the WHOLE enemy side) -- "is one of us worth more than all
  eight of them", which read 3.6 AGAINST us in a game we were dominating. Team
  army is now pooled over the blackboard. Same shape as `LosingGround()` being
  permanently true for a player with no army.
- At 2.5x it first became true at 36.8 minutes of a 50-minute game. A switch that
  only flips once the win is overwhelming does not address winning slowly.

### Air eco-assassination — it never once fired before this
The strategy was written, armed, committed, and built **0 bombers and launched 0
strikes** across every measured game. apexearth: "I only saw something akin to it
once in dozens of games." Four separate breaks, each invisible in the numbers:

- **Its factory request sat LAST in `AiGetFactoryToBuild`**, below the bot lab,
  gantry, tech rush and navy branches, all of which return first. 133 of 134
  status samples read `plants=0,0 cons=0 want=corap` -- it asked every time and
  was never reached. Moved above them.
- **Nothing built the air constructor.** `MakeFactoryTask` answered only for the
  ADVANCED plant, but `FactoryToBuild` will not ask for that plant until an air
  constructor exists -- and the only plant we owned was never told to build one.
- **The income bar was self-defeating.** Elected at 63 and 81 metal/s, by which
  point enemy anti-air was over the ceiling, so it never armed. The premise is
  surprise; waiting for a bigger income waits for the enemy to build the counter.
  60 -> 40.
- **Both defs were advanced-tier**, so the force could not start until a plant
  that rarely finished. The basic tier is a third of the price -- armthund 145
  and armfig 73 against armpnix 230 -- and `Bombers()`/`Fighters()` now count
  both tiers.

**measured**: chain completes 6/6 and the strike **releases in 6/6 games**, at
enemy anti-air of 0-2,351, with one stand-down. Aircraft are genuinely held:
`HoldsUnit` makes `Military::AiMakeTask` return null for them, leaving them idle
where built until Release, which then grants ANTI_STAT (target economy, skip
army) and SetRetreat(0).

**Still open**: strikes release on the DEADLINE path at exactly the half-mass
floor -- 6 bombers and 4 fighters -- because the deadline passes before
production reaches it, so the floor becomes the ceiling. `Priority::NOW`, a
second plant, assist while massing and batch-6 orders did NOT move it (still 6/4
in 6/6 games), because the advanced plant rarely completes and the second-plant
branch was gated on it.

### Resurrection — stock was rebuilding its army and we were scrapping ours
apexearth spotted it and named the confound himself: winners hold rez bots
BECAUSE they won. The timeline settles direction, and it was not survivorship.

**measured**: over 6 games stock spent 21,460 metal a game resurrecting to our
10,396; in one watched 8v8 it was **32,890 to our 436**, one stock player's
single largest sink of any kind was `cornecro` at 17,940, and `armrectr` appears
**zero times** in our entire log. Meanwhile we out-RECLAIM them 2:1 -- we win the
metal accounting and they win the units back.

Rez bots come only from a bot lab (`armrectr`/`cornecro`/`legrezbot`, 130 metal);
the vehicle plant and advanced plant cannot build them, and our side ran about
four vehicle plants per bot lab. Bot labs now come at 8 minutes rather than
waiting for T2 or 13 minutes, and a floor of 4 rez bots is built ahead of
anything else that lab would make. Requested BY NAME: these route through
`UseAs::REZZER` but their config roles disagree across factions ("support" for
Armada and Legion, "rezzer" for Cortex), so `GetRoleDef` is not reliable.

**measured**: rez spend **10,396 -> 18,053**, against stock's 12,104 -- reversed.

### Reading a game: `tools/report.py`
One command, fixed order: script errors, did-it-fire counts, a 2-minute timeline
per side with divergence points, then the outcome. It exists because three
verdicts in one session came from the wrong slice -- a team effect called at 6 of
8 games that reversed at 8; a cause read off the FINAL snapshot of a collapsing
side when the timeline showed the sides level on mexes until minute 12; and a
feature reported "never fired" from a regex that did not match the log line, in
the tool built to prevent exactly that. When a feature reads 0/N, grep the source
for the log string before believing it.

### Eco lead — one player builds economy and nothing else
apexearth: "one player who focuses mostly on building up a strong eco so that
they can reach the late game as soon as possible. They don't make army unless
endangered or our allies are dying." It **is** one of the tech leads: the primary
slot holder, so there is no second election and it is already the sling target.
Teams of 6+ only — on a 4v4 one player fielding no army is a quarter of the army
missing, which is the same arithmetic that already restricts the constructor
monopoly and the air opening.

While the role is active that player builds constructors from its factory up to
10 and then **nothing at all** — the idle line is the point, so income goes to
mexes, energy and the T2/T3 economy — keeps `quota.attack` at 400 for the whole
game rather than to `RUSH_GIVEUP`, and skips the Pulsar and the dig-in fortify.
Cheap AA and the energy converter are kept: an economy with no army is what air
goes looking for.

Released when it is losing its **own** extractors (under 70% of its own peak),
or when any ally is under 50% of theirs. Each player publishes its share of peak
extractors as `mexhold`.

**status: the role does what it says; whether the ROLE caused it is unproven.**
20 games, 8v8 Quicksilver at +40%, 30-min cap. The eco player against its own
seven teammates, mean per game: metal produced **60,800 vs 35,548 (+71%)**, mex
upgrades **5 vs 3**, T2 spend **29,530 vs 12,616 (+134%)**, energy produced
**+66%**, standing army **5,768 vs 6,127 (-6%)**. That is the intended shape --
far more economy, no more army. Role active a median of ~15 of 30 minutes.

**The confound is not small and is not resolved.** The eco lead IS the primary
tech lead, elected on `RushReady()` -- i.e. a player that already had the economy
to afford teching -- and it is the sling target every teammate donates to. A
selection effect plus seven donors would produce a similar table with no role at
all. Separating them needs the same variant with the role off, which has not been
run.

Two more things the same 20 games say:
- **T3 never happens** (eco lead 0, teammates 60), so "reach the late game
  sooner", the stated point of the role, is unevidenced at this scale.
- **The eco player holds FEWER T1 constructors than its teammates (8 vs 11)**,
  though `ECO_CON_CAP` is 10 and the idle-line log shows it sitting at 4-6. Build
  power is what compounds, so the one thing the role does buy is the thing it is
  short of. The cap is not what is binding.

**The 6+ team gate was re-tested and holds.** Six 4v4 games each way, three maps,
same seeds, only `ECO_ON_SMALL_TEAMS` differing: off went **2-1** on 904,267
metal and 166,643 army; on went **0-4** on 516,702 metal and 80,671 army, with
games ending *sooner* (41 min against 48). Everything below -- 28 constructors,
the turret band, the converter block, air constructors -- does not buy back the
quarter of a four-player team that stops fighting.

**One map is not a benchmark.** Every eco-lead number in this section came from
Quicksilver, where apex beats stock 4-1 on 4.5x the metal and 35x the T3. Across
eight maps, 30 games, the same build goes **4-6 with 20 games (67%) undecided**,
metal 1,374,971 vs 951,248 and **T3 136,557 vs 141,280 -- stock matches us**. On
five of the seven other maps stock out-T3s us heavily (Throne 497,825 to 2,850).
The "stock fields no T3" note elsewhere in this file is a benchmark artefact and
this is what it looks like when the bonused economy runs long.

**Build power, not willpower, was the whole problem.** Three arms of 8 games,
8v8 Quicksilver at +40%, 60-minute cap, identical settings. A = the role as first
written (ground constructor cap 10). B = cap 28, faster refill. C = B plus air
constructors, the nano rectangle, fusions in the band, and aid.

Eco player against its own teammates, mean per game:

| | A | B | C |
|---|---|---|---|
| metal produced | +24% | +59% | **+114%** |
| energy produced | -2% | +56% | **+82%** |
| T2 mex upgrades | +34% | +91% | +91% |
| advanced constructors | -45% | +75% | **+129%** |
| metal built | -41% | -18% | **-22%** |
| T3 spend | -94% | -84% | **-67%** |

Whole apex side, per game:

| | A | B | C |
|---|---|---|---|
| team metal produced | 1,367,701 | 1,301,770 | **1,773,612** |
| team metal built | 1,235,176 | 1,154,838 | **1,413,394** |
| team T3, MEDIAN | 66,300 | 82,950 | **221,325** |

Median, not mean, for T3: per-game values run 0 to over 1,000,000, so the mean
tracks whichever arm caught the runaway game and reverses sign between samples.
An interim read of B at n=6 was reported as "team T3 -69%" and did not survive
the last two games -- at n=8 the mean says -26% and the median says +25%. At
n=8 per arm the team-level differences between A and B are noise; C is the first
arm that moves the median several-fold.

Not controlled: the arms ran sequentially, not paired on seed, and win rate
separates none of them (A 7/8 decided, B and C 4/5).

Four bugs found by smoke-testing C before measuring it, every one of which would
have been invisible in the numbers:
- `IsAirFactory(CCircuitDef@)` refused `unit.circuitDef`, which is a CONST
  handle. An AngelScript compile error disables the whole variant and the match
  still runs and reports a normal result.
- **`aiBuilderMgr.GetWorkerCount()` counts nano turrets as workers.** The eco
  lead logged `cons=25` against a mobile-constructor cap of 16 while standing on
  eleven turrets, so the rectangle was eating the engineer budget.
- Turret orders reached `asked=40` against `standing=11`: the cap tests FINISHED
  units and Enqueue does not dedup. Bounded to 4 outstanding, with a resync so a
  destroyed turret cannot wedge the rule shut forever.
- **The air plant was unreachable.** The "no T1 bot lab" branch returns above it;
  the eco lead asked for `armlab` three times in one 40-minute game and never
  reached the air plant. Moved above it -- a bot lab builds the spam units this
  player does not build.

A single 8v8 on **Comet Catcher** went the other way: the eco player was overrun
(extractor share 0.43), stood down at 12.6 min, and the pre-existing catch-up
push then converted it into **29,450 metal of `armbull`** -- over half its
production -- because a player that deliberately built no army is maximally
`LosingGround()`. Standing the role down hands that player straight to the rule
this AI already records as its worst spender.

Three findings from getting it to run, each of which silently disabled it:
- **"Being dismantled" cannot be read off metal or energy income.** apexearth:
  reclaim gives a temporary income boost that later falls, and wind energy rises
  and falls on its own. A peak set by a reclaim burst reads the return to normal
  as death. Standing extractor count against that player's own peak moves in one
  direction for one reason.
- **`Military::gTurtle` is unusable as a gate for an armyless role**, exactly as
  `LosingGround()` is. The hold fires when our own army *shrinks*; a player that
  builds none can neither avoid it nor recover from it. Measured: HOLD at 8.7 min
  on army 1897 → 1266, RESUME only at 15.0 min on army 110 — the six-minute
  maximum hold expiring rather than recovering. It removed the role from the game.
- **"Any ally below 70% of peak mexes" is true essentially all the time** with
  seven allies. First 8v8: elected at 7.6 min, activated zero times. Self and ally
  now use different bars (70% / 50%).
- **The primary tech-lead slot flaps second to second**, because the election
  keeps an incumbent only while `RushReady()` holds and that reads energy income,
  which swings with the wind. Measured: slot moved 5 → lost → 5 → 3 → 5 inside
  two minutes, so the role never ran longer than six seconds. The eco role now
  keeps the title for 45s after losing the slot; **the underlying flapping is not
  fixed and affects the tech rush too.**

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
- **A fourth approach — "commander to the back wall" on enemy TEAM CENTROID
  proximity (`BaseUnderAttack`, `COMM_BASE_DANGER`) — measured actively harmful
  and is now disabled (`COMM_BACK_WALL_ON = false`).** On Comet Catcher 4v4 the
  centroid of four spread-out enemies sits under the 2200-elmo bar from ~1
  minute in for the entire game, regardless of whether anyone is attacking, so
  the branch fired roughly every 30s all game and spent the commander's build
  time — normally the fastest builder available early — on repeat back-wall
  solars instead of the opening build. 8-game control vs
  `BARb:stable:hard_aggressive`, same map/handicap/faction: paired K/D
  log-ratio t-stat went from -13..-17 (apex shut out 0-5/0-7 decided) to -0.87
  (not distinguishable from even, 1-1 head to head, one outright apex win). The
  health-based retreat (`COM_RETREAT_HEALTH`) is untouched by this flag and
  still the thing pulling a commander out of real danger.
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

---

## How the AI judges a fight — four defects found 2026-08-02

All four sit behind one symptom apexearth has reported repeatedly: *"we won a
fight, took that army to the enemy base and lost it all... we keep fighting with
2/3rd or 1/2 their size army... never gaining enough to really fight because we
throw our army away."* They are separate mechanisms and are being fixed one at a
time, with a watched game between each.

### 1. Squad strength is blind to damage — FIXED, unmeasured

`FighterTask.cpp:52` accumulates `attackPower += cdef->GetPower()`. `cdef` is the
`CCircuitDef` — the unit **type** — and `GetPower()` returns a constant field on
it. The value therefore changes only when a unit is added or removed from the
task; `RemoveAssignee` subtracts the same constant on death.

Nothing anywhere reduces it for damage. A squad at 10% health across the board
rates itself exactly as high as a fresh one, so after winning a bloody fight it
still passes the engagement test and pushes on into the enemy base.

The enemy side of that same comparison is **not** paper: `ThreatMap.cpp:290`
weights an enemy by `GetHealth() + shield * SHIELD_MOD`. So the AI rated the
enemy on current health and itself on paper strength — the asymmetry always
favoured attacking.

Fix: `CAttackTask::GetHealthScale()` returns power-weighted mean health across
the squad, and `FindTarget` multiplies `maxPower` by it. Clamped to [0,1] because
`GetHealthPercent()` subtracts `GetCaptureProgress() * 16` and can go negative.
Deliberately local to `CAttackTask` — see defect 3.

### 2. The engagement test has NO margin — not yet fixed

`AttackTask.cpp` `FindTarget`:

```cpp
if ((maxPower <= group.influence * scale) && ...) continue;  // skip target
```

The squad engages the moment its power exceeds enemy influence **by any amount**.
A 1% edge commits the whole army. Any enemy reserve not yet seen flips the
outcome after the commitment is already made, and a slow-turning vehicle squad
pays for the reversal on the way out.

apexearth, watching: *"we consider fighting. But then we discovered that they
actually have more units just behind the ones we see in the fog. And so then we
turn around... it takes a moment to turn around, and so that's enough time for us
to lose one or two."*

### 3. `attackMod` cannot separate raiding from frontal combat

One config value is read by SCOUT, RAID, ATTACK, BOMB, ARTY and AA. Raising
`thr_mod.attack` from [1.0,1.0] to [1.4,1.8] to buy caution **tripled losses**
and was reverted: it made raids cautious too, and a raid unwilling to trade is
just passivity.

This is why defects 1 and 2 are being fixed in `CAttackTask` rather than in
config — that reaches frontal engagements only, leaving raids free to make the
economic trades that are worth losing units for.

### 4. Fog memory is NOT the problem — measured from source

Checked because it was a natural suspect. `EnemyManager.cpp:129` sets
`maxFrame = now - 20 minutes`; an enemy unseen for less than that stays in the
list at its last known position, and line 551 adds `enemy.influence`
**unconditionally**. Threat memory persists for a full twenty minutes.

Only `cost` forgets: line 548 gates `eg.cost += enemy.cost` on
`!IsMobile() || IsInRadarOrLOS()`, so a fogged mobile enemy drops out of `cost`
while still counting in `influence`. The engagement test above uses
`influence`, so it is the remembering one.

Conclusion: units that surprise a committed squad were never seen at all — new
production, or reserves on unscouted ground. Better scouting or longer memory
would not have helped; margin (defect 2) is the answer.

---

## Defence towers were always the cheapest one — FIXED, unmeasured

`PorcToBuild` already picked the heaviest tower it could afford, capped at
`metal.income * 30`. Early income of ~6/s makes that a 180-metal budget, and the
mid-tier tower costs **195** — it missed by 15 metal in every early placement, so
the AI fell back to the basic laser tower indefinitely.

That tower cannot fight the units it is meant to stop. Measured from the unit
defs in the pinned tree:

| unit | metal | range |
|---|---|---|
| `corllt` | 90 | **435** |
| `corstorm` (rocket bot) | 110 | **475** |
| `corhllt` "Twin Guard" | 195 | **480** |
| `corhlt` "Warden" | 480 | 620 |

A rocket bot outranges the basic tower by 40 elmos and kills it without being
fired at. Armada is the same shape (`armllt` 85/430, `armbeamer` 190/480,
`armhlt` 440/620). `corrl` is not an alternative — `onlytargetcategory VTOL`,
it is anti-air only.

Fix: a `PORC_MIN_BUDGET` floor of 200 metal, so the mid tower is always
reachable. apexearth: *"HLTs are even better if we can afford it, but usually you
wanna get those mediums up first, then an HLT once you can afford"* — that
ordering falls out of the existing income term, which only clears 480 at 16
metal/s, by which time the mediums are already placed.

---

## Rez bots died to all-or-nothing resurrects — FIXED, unmeasured

A resurrect pays out only on completion; a bot driven off one has nothing to show
for the time spent. A reclaim credits metal continuously and can be abandoned
part-done. `RezSpotHot()` now forces reclaim when the bot stands on hot ground,
which is what makes "snatch and go" possible.

apexearth: *"we lose too many rezbots due to dangerous rezzing... dangerous
rezzing should turn into reclaiming, which allows for more 'snatch and go' type
behavior."*

---

## Metal converters may be eating the expansion gap — NOT ACTED ON

Measured in one clean 20-minute 4v4: apex held constructor counts **level with or
above** stock through minute 14, yet finished on 11.0 mexes to stock's 15.8.
Same builders, spent differently.

91 converters were built in that game. Build times from the pinned tree:

| unit | metal | buildtime |
|---|---|---|
| `cormakr` (converter) | 1 | **2680** |
| `cormex` | 50 | 1870 |

A converter costs 43% **more constructor time** than a mex while costing
essentially no metal — so it is invisible in a metal-spend audit and expensive in
the resource that actually binds. This is a candidate for the remaining
expansion gap, not a confirmed cause; nothing has been changed.

---

## Gating CDefendTask promotion — TRIED, REVERTED 2026-08-03

**Do not retry this without a different mechanism.** It made every measured axis
worse and it made squads *smaller*, which is the opposite of its purpose.

`CDefendTask::Update` promotes on:

```cpp
if ((attackPower >= maxPower) || !militaryMgr->GetTasks(check).empty()) {
```

The second clause is unconditional once one ATTACK task exists — which is always,
after the opening. Engagement logging showed the consequence: over a 40-minute
8v8, the median attack decision was made by **2 units**, p75 of 4, against a max
of 30. So a floor was added: while an attack is already running, a defend task
had to reach `maxPower * 0.5` before promoting.

Measured on **identical settings** (Comet Catcher, 4v4, +25% handicap), one
variable changed:

| | before | after |
|---|---|---|
| apex eliminated | 23.3 min | **20.0 min** |
| K/D | 0.55 | **0.32** |
| metal produced | 169,601 | **109,901** |
| mexes | 71 | **51** |
| squad size, median | 4 | **3** |
| decisions by <=2 units | 27% | **50%** |

The run was verified valid first: variant loaded 8x, zero AngelScript errors,
zero crashes. Apex simply died sooner.

**Why the model was wrong** (inference, not measured): the promote path
`Enqueue`s a new task, and `GetMergeTask()` on the following update folds it into
an existing squad. So the observed trickle of 1-2 unit promotions was largely the
*reinforcement pipeline*, not units walking off to fight alone — they promote,
then merge into the squad already in the field. Gating promotion blocked
reinforcement, so squads in contact shrank as they took losses with nothing
arriving, and fewer attack tasks existed at all (78 engagement decisions -> 36).

Consequence for future work: **squad size measured at the engagement decision is
not a measure of how many units are in the fight.** A small `units=` count may be
a wave about to merge. Any future attempt at massing has to measure the merged
squad, or work on the merge/assignment path rather than on the promote gate.

---

## Squad join radius 1000 -> 3000 — squad size FIXED, win effect UNPROVEN

`CAttackTask::CanAssignTo` rejected any unit further than 1000 elmos from the
squad leader. That gate governs **merging as well as joining**, because
`CheckMergeTask` calls `candidate->CanAssignTo(leader)` — so it, not the
`MAX_TRAVEL_SEC * speed` budget in the same function (~2700 elmos for a T1 bot),
was the binding limit. `CDefendTask::CanAssignTo` has no distance limit at all,
so units pooled near home, promoted as a group there, and then could never
combine with the squad already fighting 3000-5000 elmos away. The army was
structurally split into "the squad in contact" and "everything built since".

`CAntiAirTask` and `CBombTask` were already raised from the same 1000 to 4000
here; ground attack had been left behind. `CRaidTask` is deliberately still 1000
— raids are meant to be small and independent.

Measured on identical settings (Pinch Point 8v8, left/right, 0.35 boxes):

| | radius 1000 | radius 3000 |
|---|---|---|
| median squad at engagement | 2 | **5** |
| decisions by <=2 units | 52% | **30%** |
| decisions by >=8 units | 15% | **23%** |
| sample | n=1037 | n=806 |

The squad statistic has ~1000 samples inside a single game, so it does not depend
on between-game variance the way win/loss does.

**The same pair got worse on outcome** — apex K/D 1.71 -> 0.62, army peak
117,425 -> 66,011 — and that is NOT attributable. Apex's own metal was flat
(417,548 vs 414,945) while *stable's* doubled (258,443 -> 604,907), which no
change of ours can cause. Between-game variance on this benchmark was measured
the same day at ~50% on metal with the build held constant (89,814 vs 132,833,
and 0 vs 55 attack tasks).

The open question is real though: massing means fewer, larger attacks, therefore
less continuous harassment, therefore an enemy free to expand. Testing that needs
repeated games, and the answer may be that attacks should mass while raids stay
frequent — which is what the single shared `attackMod` prevents expressing.

---

## Naval players built no energy at all — 2026-08-03

`CEconomyManager::ReadConfig` line 431 picks the energy block once for the whole
team: `type = IsWaterMap() ? "water" : "land"`. Being naval is a property of the
START POSITION, not the map, so on a mostly-land map a water starter read the
`land` block, which carried no naval entries.

Absence is not neutral. A def with no entry gets `SEnergyCond::limit = 0`, and
`UpdateEnergyTasks` treats that as a hard stop:

```cpp
if (engy.cdef->GetCount() < engy.data.cond.limit) { ... }
else if (!isEnergyStalling) { bestDef = nullptr; break; }   // aborts the scan
```

Solar and wind sit above the tidal and `continue` out on `CanBeBuiltAtSafe`
(they cannot be placed in the sea), so the walk reached the tidal, evaluated
`0 < 0`, and **broke out of the whole loop**. A naval player therefore enqueued
no energy at all unless it was already stalling.

Same shape as the land-bot-lab bug found the same day: a map-level test standing
in for a per-player condition.

Fixed by adding the naval defs to the `land` block as well. Land players are
unaffected — `CanBeBuiltAtSafe` rejects a tidal at a land position before the
limit is read, and `min_income` drops tidals from the def list entirely on a
tideless map.

### The naval build helpers were handing ships land buildings

`EnergyConverter`, `EcoConverters` and `EcoFusion` in `builder.as` passed
`cormakr`/`corfus` to every builder including ship constructors, which cannot
build them. `EcoFusion` was worse than a silent no-op: the task enqueued
successfully, so a naval eco lead held an unbuildable task every 45 seconds.
Naval builders (`IsFloater() || IsSubmarine()`) now get the naval defs.

### Naval unit facts, verified 2026-08-03 in the pinned tree

| unit | cost | built by |
|---|---|---|
| `armtide`/`cortide`/`legtide` | 90 / 85 / 85 m | T1 con ships, commanders |
| `armfmkr`/`corfmkr`/`legfeconv` | 1 m, 70 e/s | T1 con ships, commanders |
| `armuwmmm`/`coruwmmm` | 380 / 370 m, 600 e/s | `armacsub`/`coracsub` |
| `armuwfus`/`coruwfus` | 5200 / 5400 m, 1200 e/s | `armacsub`/`coracsub` only |

**Legion has no naval fusion and no naval advanced converter in the pinned
tree** — `leganavalfusion`/`leganavaleconv` are upstream-only. Legion's naval
path runs through Cortex: `legcs` builds `corasy`, which yields `coracsub`,
which carries `coruwfus`/`coruwmmm`. Legion does have its own `legtide` and
`legfeconv`. `legcs` is game-tree-only, absent upstream.

## Range: no tower we build can answer enemy artillery

Verified 2026-08-03 from the pinned tree.

| ours | metal | range | | enemy | metal | range |
|---|---|---|---|---|---|---|
| `corhllt` | 195 | 480 | | `cormart` | 400 | **800** |
| `corhlt` | 480 | 620 | | `corban` | 1000 | 800 |
| `corvipe` | 730 | 730 | | `corvroc` | 880 | **1310** |
| `corpun` | 1300 | 1245 | | `cortrem` | 1850 | **1470** |

A 400-metal Pillager outranges our 480-metal heavy tower by 180 elmos and kills
it without being fired at. Repositioning cannot fix a range deficit.

`corpun` (range 1245) is the only static counter we own, and it carries
`"on": false` in `behaviour.json:790` — `CircuitAI.cpp` calls
`SetOn(cdef->IsOn())` when a unit finishes, so it is built switched off.
`armguard` and `cortoast` are the same.

Our own long-range units are correctly handled but barely produced: `cormart`
0.13/0.09, `corvroc` 0.06/0.05, and **`cortrem`, the only thing we own that
outranges enemy siege, 0.01/0.04**. The artillery role routes them to
`CArtilleryTask`, which positions at FULL `GetMaxRange()` — it does not apply the
0.8 `RANGE_MOD` ordinary squads use — and only fires from a position under
`THREAT_MIN`. `corban` is classed `skirmish`, not `artillery`, so it walks to
80% of its 800 range with the main squad.

Ruled out, do not chase: the per-unit `"threat": {all 0.0}` and `"power": 1.0`
on those entries are uniform across every unit including `correap`/`corthud` and
byte-identical to stock.

---

## The army loses; the towers do not carry us — measured 2026-08-03

`dev_stats_export.lua` now splits kills by KILLER type (`mKillStatic`,
`mKillMobile`) and reports mobile losses (`mLostMobile`) and standing jammer
towers (`jamT`). A combined K/D cannot tell "our defences are working" apart
from "our army is winning", and reads healthy while the army loses.

apexearth, watching: "we make them suffer a lot with our defenses, but our
units are still losing the battles."

8 games, Comet Catcher 4v4, +25%, 40 minutes:

| | apex | stable |
|---|---|---|
| combined K/D | 0.56 | 1.15 |
| **ARMY K/D** | **0.66** | **1.40** |
| kills by mobile | 1,141,429 | 1,682,405 |
| kills by static | 182,390 | 174,681 |
| mobile lost | 1,725,762 | 1,197,952 |
| jammer towers | 24 | 48 |

He was right about the army and wrong about the towers: static kills are within
5% of each other, so defences carry NEITHER side. The army is the whole gap.

## ENGAGE_MARGIN works at 25 minutes and not at 40

Matched 8-game pairs, same map and settings, only the constant changed:

| | 1.35 | 1.80 |
|---|---|---|
| apex K/D @25min | 0.82 | **0.97** |
| stable K/D @25min | 0.82 | **0.64** |
| metal ratio @25min | 0.94 | **1.26** |
| apex K/D @40min | — | **0.56** |

So requiring an 80% advantage genuinely improves fighting through mid-game and
then stops holding. The late game is a separate failure, not a weaker version of
the same one. At 10 minutes the two sides are IDENTICAL (0.76 vs 0.76 over 10
games), so nothing is wrong with the opening either.

## Reclaim cannot see the bodies

apexearth: "even once they die all on our doorstep, we're not rushin to reclaim
any of it... theres 1000+ metal in front of us and we don't even care".

Reclaim previously required an empty bank or an idle builder, so a constructor
holding any task walked past a corpse field. A rule was added that interrupts a
build for a rich field, gated on TOTAL nearby value rather than the biggest
single body — a dozen dead T1s is several hundred metal and none of them is
individually large. This needed a new binding, `ai.GetWreckValueAt(pos, radius)`,
since `GetBestWreckPos` only answers "is there one fat corpse here".

**It does not fire, and the cause is upstream of the rule.** Probed over a
16-minute game, 97 samples: `GetWreckValueAt` read 0 at both 1400 and 4000
radius, AND the established `GetBestWreckPos` returned no position at 4000 with
a 55-metal floor. Two independent bindings agree there is nothing reclaimable
within 4000 elmos of our constructors. Either features are not visible to that
callback without LOS, or constructors are never near the wrecks. **Do not tune
the threshold — find out which of those it is first.**

## Three fixes from one live session — 2026-08-06

### Commander wrecks are excluded from reclaim/resurrect targeting — unmeasured

apexearth: "any way we can enhance our reclaim logic to be careful not to fully
reclaim our own dead commander?" `GetBestWreckPos`/`GetWreckValueAt` (see
"Reclaim cannot see the bodies" above) now both skip any wreck whose
`GetResurrectDef()` resolves to a commander-role unit, via a new
`CCircuitAI::IsCommanderWreck(Feature*)`. Deliberately broadened from "our own"
to "any" commander corpse: the `Feature` API exposes no team-ownership
accessor, and BAR lets any allied rez bot resurrect any corpse under its own
control anyway. `GetWreckValueAt` is excluded too, not just `GetBestWreckPos` —
otherwise a commander corpse could still skew the "how rich is this field"
total that gates whether a constructor gets sent there at all.

### The metal-full-fallback was spamming Pharos instead of the T1.5 tower

The fallback added earlier this session (constructors spend idle metal on
defense once every other rule in `AiMakeTask` has had its chance) reused
`ContestTower()`, written for a different, reactive case: an under-fire con
grabbing whatever it can build fastest. `ContestTower`'s T1-vs-T1.5 split keys
on the CALLING CONSTRUCTOR's own cost, so a cheap T1 con (the common case)
always got the cheap turret — confirmed in an infolog, dozens of
`metal-full-fallback legcv -> leglht` lines. apexearth, watching live:
"Legion makes too many Pharos (llt light laser turret), not enough of the T1.5
defenses." New `MetalFullTower()` always prefers the T1.5 popup tower
(`legapopupdef`/`corvipe`/`armpb`) once it is unlocked, since reaching this
fallback at all means the team can afford it; only falls back to the T1 turret
before that tech exists. Smoke-tested all three factions: fallback now builds
`corvipe`/`legapopupdef`/`armpb` instead of `corllt`/`leglht`/`armllt`.

### No living commander now overrides `PreferReclaim()`

apexearth: "if we have no comm anymore then we should prefer to rez."
`PreferReclaim()` gates rez-bot behaviour and previously defaulted to
reclaim-first before T2 and whenever `Military::LosingGround()`. It now checks
`gComm is null` first, ahead of both: `gComm` is set null exactly once, at the
real death event in `AiUnitRemoved` (see the `COMMANDER LOST` log there), and
re-set the moment any commander-role unit is added — resurrected or freshly
built — so this only holds during the actual gap. Unmeasured: no commander died
in the three 8-minute faction smoke tests, so this path compiled and deployed
clean but has not fired live yet.

### Open: army production stalling with a live commander and idle metal

Recurring live report, this session's newest instance: "purple stopped making
army. he has a commander, home base still intact... he just stopped being
productive. our team died full on metal." Pulled that player's own timeline
from `result.json` (not the end-state total — see "Standing counters are not
end-state" in `CLAUDE.md`): `armyReal` frozen at exactly 2700 for 10 straight
minutes (20-30 min mark) while `metalProduced` climbed steadily and
`metalExcess` grew from 345 to 2079, and `mCon` (constructor value) fell to 0
by the same point. Ruled out the eco-lead role as the cause — this was a 4v4,
`IsSmallTeam()` is true, and `ECO_ON_SMALL_TEAMS` is false, so `IsEcoLead()`
cannot fire; no "eco lead" log line appears anywhere in that match's infolog.
**Not yet root-caused.** Added a rate-limited entry log to `AiMakeTask` in
`factory.as` (`apex: factory-diag`, once per 30s) recording income/current/
storage/`isMetalFull`/whether the factory already holds a task — the next time
this is caught live, that log will show whether the function keeps being
called and returning nothing (a decision problem, something below always
declines) or stops being called at all (the factory's task got stuck and the
engine stops re-asking) — the same two-hypothesis split the RECLAIM-abandon fix
resolved earlier this session for constructors, not yet applied to factories.

## Three more, same session, from watching two windowed games back to back

### The commander was thrashing between mex, factory-assist and reclaim

apexearth, watching live: "he'll start a job to build a mex, and then he'll
turn around to try to assist a factory, but then he'll move away, and he'll
follow some reclaim... we have a lot of different bits of logic that are all
kind of competing for control of the same unit... we need some sort of
control pass to compare what he's currently doing with what he's proposed to
do." One instance of exactly this already had a fix: the commander could be
pulled onto another unit's HIGH-priority Reclaim task from clear across the
map (`CBuilderManager::MakeCommPeaceTask`, native, ignores distance against a
HIGH-priority job), and that was vetoed while an open mex spot remained. That
veto only ever compared the incoming task against "is a mex spot still
open" -- it never looked at what the commander already held, so a
factory-assist pick (also handed out by the same native picker) sailed
through unguarded. Generalized: `unit.task` at this point in `AiMakeTask` is
still the OLD task (`IBuilderTask::Reevaluate` only swaps it once this
function returns something of a different build type), so comparing it
against the freshly computed `DefaultMakeTask` proposal is exactly the
"current vs proposed" check requested. Now refuses any proposed swap to a
different recognized build type while the commander holds real, in-progress,
non-dangerous work of its own. Confirmed firing in all three 8-minute faction
smoke tests (4-16 times each) with zero AngelScript compile errors.

### Air factories went permanently dead after the assassin stood down

apexearth, watching live: "blue made 2 t1 air labs, a t2 air lab.. he's not
making any army at 27m in... this is a brutal mistake." Root cause: the
air-assassin election is latched forever ("the role is paid for in
factories, so it never moves" -- `RunElection()`), and `Update()`'s
"STANDING DOWN" branch (enemy AA rose past the ceiling before the strike
ever committed) sets `gAbort = true`, which is never reset anywhere in the
file. `Armed()` checks `gAbort`, so it goes permanently false, and
`factory.as` has a deliberate blanket rule -- added for a different, earlier
bug -- that no air factory may ever reach `DefaultMakeTask`. The two combine
into a one-way trip: an elected lead whose strike aborts before committing
gets every air factory it owns locked out of production for the rest of the
match, with only a late-game 8-fighter floor (`LATE_FIGHTERS`) as a partial
safety net, and no path back since nobody else can ever be elected either.
Confirmed in that match's infolog: exactly one "STANDING DOWN" line, after
which the player's armap/armaap factories kept showing up in the new
factory-diag log with no further Air:: activity for the rest of the game.
Fixed with `Air::RoleAbandoned()` (true only for the standing-down case, not
the post-strike `gStrike` case, which is intentionally quiet) and an
exemption in `factory.as`'s blanket block so an abandoned lead's plants fall
back to ordinary production instead of building nothing.

### Open: a follower stuck at T1 all game despite heavy army spend

apexearth, same session: "purple at 29m in still pumping out TONS of
army... but never went t2... we were almost winning but these issues turned
it into a loss." Pulled from the same match: `mT1=47,500`, `mT2=0`,
`techStart=-1` the whole 30-minute game. This is NOT a fresh bug the way the
two above are -- `FOLLOWER_TECH_ENERGY`'s own comment already names this
exact failure mode as possible and says what to check before touching the
threshold: "Deliberately above what the AI currently reaches [on the
benchmark]... If followers stop teching at all, that is the factor being too
low, not this number being wrong -- check eInc in the T2GATE log before
lowering it." The problem: that log (`T2GATE reached`) only ever fires on
the PASSING path. A player that never once clears the bar leaves no record
of how far short it stayed -- confirmed in this match's own infolog, only 2
`T2GATE reached` lines total, for the two players who DID tech, and nothing
at all for the two who didn't. Added the missing half: `T2GATE blocked
FollowerEconomyReady`, logging the actual eInc/mInc against both thresholds
whenever a non-lead is refused for exactly this reason. **Do not lower
FOLLOWER_TECH_ENERGY from this report alone** -- get an actual blocked-side
reading first.

**Partly resolved same session, from source reasoning, not yet from a
blocked-side eInc reading**: see "The tech-lead election was a one-way
trip" below -- a follower stuck the whole game with `techStart=-1` may
simply have had no lead left to follow, not (only) an unreached energy bar.

## The tech-lead election was a one-way trip past 15 minutes

apexearth, watching a different match live, same session: "If green did
have T2 they must have lost it, and nobody else went and made T2." Found in
`RunElection()`'s incumbent-retention check:

```
if ((ai.frame > Military::RUSH_GIVEUP)
    || (ai.ReadTeamValue(held, TV_ADV, -1.f) > 0.f)
    || (ai.ReadTeamValue(held, TV_READY, 0.f) > 0.f))
```

`Military::RUSH_GIVEUP` is 15 minutes. The `||` meant that past that frame
the incumbent was kept UNCONDITIONALLY, regardless of `TV_ADV` -- which is
`ai.GetDefBuildProgress`, confirmed live (returns -1 the instant we own none
of the def) rather than a one-way ratchet. So a lead who loses their
advanced plant after 15 minutes stays "the lead" for the rest of the game,
the slot never reopens, and `MayPursueT2()`'s only remaining door for
everyone else is `FollowerEconomyReady()` alone -- see the still-open item
above for how high that bar sits. Likely the same root cause behind that
report, not a separate coincidence: a team-wide "stuck at T1" after the
30-minute mark is what "nobody left to designate" and "nobody clears the
follower bar" look like from the outside, together. Removed the frame
clause; retention is now governed purely by whether the incumbent still has
a plant or can still afford one, at any point in the game.

## The metal-full fallback was buying Pit Bulls — 2026-08-07

The idle-constructor fallback added the previous day built a defence tower.
Watched 8v8, Supreme Isthmus, +40%: **191 fires, every one an `armpb`** at
680 metal *and* 14,000 energy — ~130,000 metal and 2.7M energy team-wide.
apexearth, watching: "some of our guys in the back line are just building
tons of t2 small defenses... we have half the economy of our enemy."

It now builds energy (solar 155 / advanced solar 350), skipped entirely while
`EnergyWasting()`. In smoke tests it fires ~1x per 8 minutes instead of
continuously, because that gate holds it shut most of the time.

**A theory this refuted, recorded so it is not retried:** the first fix
claimed energy would unlock followers' T2 via `FOLLOWER_TECH_ENERGY`. The log
says otherwise — `T2GATE blocked` fired **zero** times, and five of eight
players cleared the follower gate and still ended with 5 T2 constructors
against stock's 20. The energy bar is not what holds tech back here.

### Open: the mex-upgrade flat-line is where the 8v8 economy actually goes

Same game, per-4-minute timeline (`analyze_stats.py` on the single match):
apex is level or ahead through minute 12 (113,727 metal vs 113,891, and
*ahead* on T2 at minute 8), then diverges. By minute 40: metal 1,015,506 vs
2,512,456, T2 spend 412,765 vs 1,410,430, T3 4,725 vs 132,509.

The mechanism is visible in one column: **apex mex upgrades go 32, 33, 33 over
the last twelve minutes while stock goes 44, 49, 56.** Apex stops upgrading
mexes around minute 30 and never restarts; stock never stops. Static-defence
*share* is comparable (11.5% vs 10.4%), so this is not simply "we built more
towers" — apex's whole economy is 4x smaller and the towers are part of what
its constructors did instead of expanding. Not yet root-caused: the fallback
fires only after everything above it declines, so something upstream is
declining mex upgrades too. Start there, not at the fallback.

## Commander idling at a haven patrolled back and forth forever

apexearth, watching live: "when a commander has retreated he often ends up
just patrolling back and forth for a very long time." `CRetreatTask::
OnUnitIdle` (C++), once a retreating unit is within range of its haven,
issues `CmdPatrolTo(pos)` to any repair-capable unit -- which includes the
commander. A patrol order to a single point is a there-and-back shuttle
between wherever the unit was when the order was given and `pos`, by engine
design, looping forever until something else takes the unit. Every other
branch in this file already carves the commander out of behaviour meant for
ordinary units (`GetRallyPos`, `GetRearHaven`, the cloak re-decide in the
same function) -- this one hadn't been. Excluded the commander from the
shuffle-to-a-nearby-build-site branch entirely; it now stays put at the
haven and AiMakeTask's own isComm section (build/hide/back-wall) picks it up
from there on the next cycle, same as any other commander idle event.
