# Open issues — what is wrong with this AI right now

## OPEN: combat conversion -- army trades at ~0.5 K/D in metal and cannot finish a 2x lead inside 30 minutes (2026-08-15)

THE strategic deficit, measured across 56 tournament games tonight: we
out-produce stock ~2x and lead 26/32 games at the 30-minute cap, but army
K/D in metal is 0.33-0.82 against stock's 0.92-1.42 (`tools/fight1v1.py`
per tournament; note the noise floor -- two IDENTICAL baseline runs
scored 0.82 and 0.59, so single-tournament K/D deltas under ~0.3 are not
signal). 28 of 32 random-map games timed out undecided.

**Vision fixed, trade unchanged.** The first mechanism found was
blindness: `apexfoe raw=0` for the first 14 minutes of the worst game
(K/D 0.10), enemy model ~500 vs a real 3000+ army at 30m, radar ~3 towers/
game -- `CMilitaryManager::DefaultMakeSensors` refuses to place radar
inside our own zone (`IsZoneAlly` early-return, MilitaryManager.cpp:1060)
and only fires at contested clusters. Landed `Builder::RadarNet`
(statics.as; ledger hooks in main.as `AiUnitFinished`/`AiUnitDestroyed`,
which were engine-looked-up but unimplemented): territory-centre-then-
border-ranks anchor ladder, standing-position ledger so dead radars
re-open their rank, coverage scales with ground held. CONFIRMED WORKING
(coverage grows, enemy model reads 1000-2300 late-game instead of ~300)
-- but the 12-game re-run's K/D was 0.33, no improvement. Vision was
necessary, not sufficient.

**MEASURED 2026-08-15: the isHome exemption covers the map, which is why
nothing else moves the needle.** `CAttackTask::FindTarget` waives the odds
check entirely wherever net influence >= INFL_SAFE (2.0). The `home-edge`
sampler (massing.as, 60s cadence) across the 12-game engage-neutral
tournament: median **85%** of the base->enemy axis reads as "home"
(p25 67%, p75 95%, n=294). Every odds-related fix so far (scale-units bug,
trade-scaled margins, thrMod 0.6-0.8 -> 1.0 neutral, radar-net vision)
sits BEHIND this bypass on the ground where most fights actually happen --
measured K/D across four tournaments: 0.82 / 0.59 / 0.33 / 0.48, all
noise-band, no fix moved it. **Scoping fix LANDED 2026-08-15, apexearth-approved** ("Sounds like the
right fix"): `isHome = inflMap->GetAllyDefendInflAt(group.pos) > INFL_EPS`
(AttackTask.cpp) -- the defence-influence field around actual defence
structures instead of anywhere our units have walked. First 12-game
measurement (`tournaments/20260814-233602-ishome-scope-check`): K/D 0.635
-- best of the last four same-map runs (0.59/0.33/0.48) but still inside
the two-identical-baselines noise band (0.59-0.82), so NOT yet claimable
as an improvement; 8/12 games decided (6-2), the most decisive run of the
night, zero crashes. Needs either a large batch or apexearth watching to
close. Also landed this pass: army-scaled squad floor
(`Military::MassFloor`, `apex_mass_per_army` 0.0017, binds at hosted-game
scale, benchmark unchanged) and quota.attack now tracks want both ways
(the up-only ratchet would have wedged after losing a scaled-up army).

**Where the deficit actually lives, still open:** which fights get taken.
The army bleeds continuously (army value FALLING minute-over-minute while
the enemy's rises, e.g. 1870->937 over minutes 18-21 of t012) rather than
dying in a few big pushes -- piecemeal engagement, not one bad battle.
Next investigation belongs to military-engagement: massing/attack-quota
behaviour with a material lead, and the still-unmeasured standoff/
fragility passes in the entries below. A watched game is the right next
instrument -- the benchmark's noise floor cannot rank engagement changes.

Related fixes landed the same night (both STOP-class, measured firing):
rez bots (no buildoptions at all) routed out of the build pipeline
(maketask.as -- was 1443 blocked tasks/game); `GuardBuildCapability` no
longer nulls REPAIR/RECLAIM/RESURRECT tasks, whose buildDef is the
TARGET's def, not a construction (was silently killing commander assists,
291/game). Blocked-task log: 497 -> 11 per game.

What is broken or missing, with the evidence for it. `CHANGES.md` says what was
done; `USER-FEEDBACK.md` is the standing brief; this file is the live list.

---

## MEASURED-CONFIRMED at tournament scale, 2026-08-15 -- entry kept one cycle for the record, then delete: T2 line builds only Hound -- facqueue core "floors" fill first-listed-first, and factory.json was never in the loop (2026-08-15)

**CONFIRMED FIXED, 24 tournament games (2x12, `tournaments/20260814-214257`
and `-215028`, Geyser Plains, Apex vs stock BARb: 12-0 in decided games).**
Every T2-reaching game (8 of 24 + both smoke matches) shows 2-4 combat
types drawing orders instead of one: e.g. armfido 570 alongside armwar
810/armrock 600/armham 520/armfast 513; Cortex games corsumo/cormort/
corpyro/corhrk mixes with top share 54-80% BY METAL (heavies cost more per
count -- count-balanced quotas, not the old 100%-of-orders monoculture).
T1 lines likewise mixed (armpw/armwar/armham all drawing). Residual
question, deliberately NOT tuned now: quotas balance by COUNT, so a heavy
role takes a larger metal share -- if a future watched game shows heavy
crowding out the rest, the lever is metal-weighting the core wants, a
policy question for apexearth per CLAUDE.md.

ROOT CAUSE FOUND for the whole Hound/Sniper/Welder complex (supersedes the
factory.json weight-tuning passes below -- those tables were largely
irrelevant). The Brain drives every factory line (`apex_fac_queue_brain`
default 1, `brain/facqueue.as`), which bypasses `CFactoryManager`'s
roulette entirely: **while a line is driven, `factory.json` tier tables and
`response.json` decide nothing** except through `GetRoleDef`'s per-role
draw. Composition is decided in `QuotaFor`.

Inside `QuotaFor`, the `T2ArmyShort` block inserted ASSAULT/HEAVY/AH/AHA as
FLOOR entries, and `FillQuota`'s floor loop takes the FIRST short floor
(`break`). ASSAULT is listed first, ASSAULT on `armalab` resolves only to
`armfido`, and the floor counts ALIVE units -- so while Hounds die at the
front, the assault floor is short forever and HEAVY/AHA (armfboy, armsnipe)
never receive one order. Verbatim from
`matches/20260815-040355-.../infolog.txt`:
`facqueue armalab #6890 +1 armfido ... quota: armfido=5/21 armfboy=0/21
armsnipe=0/21` -- repeatedly, all game. The T1 block has the same shape
(`armpw=8/16 armwar=2/16 armham=3/16`, always armpw). armzeus (skirmish)
and armmav (riot) live only in the gMix ratio section, which the early
return never reaches while the core is short -- hence literally zero of
each.

**Patch (facqueue.as):** the two core blocks now insert their roles as
ratio entries (`isFloor=false`), so `FillQuota` balances by have/want
across the core instead of first-listed-first. Confirm on the next match:
`quota:` log lines should show armfboy/armsnipe counts rising alongside
armfido, and `allBuilt=` should stop being ~90% armfido within armalab
combat. Delete the two factory.json-tuning entries below along with this
one once measured.

---

## MEASURED-CONFIRMED at tournament scale, 2026-08-15 -- entry kept one cycle for the record, then delete: commander pinned in CRetreatTask for 13 minutes -- retreat is an absorbing state (2026-08-15)

**CONFIRMED FIXED, same 24 tournament games + 2 instrumented smokes.** Zero
commander deaths in 24 games (control match: died on the pin). `retreatCut`
fired 3-19 times in every contested game and the commander returned to work
each time; the new once-a-minute `comm-now` line (prints from the sampler,
not AiMakeTask, so it cannot go silent when the commander wedges) shows
commanders holding BUILDER tasks with live orders while under influence
5-17 -- working through heat instead of standing, exactly the
safer-ground-gate intent -- and retreating only on real damage (hp 69 ->
retreat -> repaired -> back to work within 2 minutes, instrumented match
`20260815-044903`). Overall `commIdle` fell from 56%+wedge-cases to 39-62%
(mean ~52) vs stock BARb's own 27-65% in the same games; the remaining gap
is the `waiting` bucket -- see the separate OPEN entry below.

THE stuck-commander mechanism for "he just stands around doing nothing",
found in `matches/20260815-040355-...`: at 10.8m the any-influence flee
(`apex_comm_flee_influence`, post-T2) put the commander into a
`CRetreatTask`; from that frame to its death at 25.7m the commander was
~100% idle (gadget `commIdle` 89 -> 1615 of 2881 samples), `comm-why` and
`comm threat=` logging stopped cold (both print from the commander's
AiMakeTask path, which a unit HOLDING a task never re-enters), and the
flee log printed exactly once. `CRetreatTask::Update`
(`RetreatTask.cpp:165-190`) ends the retreat only at >98% health, or for a
commander at zero enemy influence at its OWN tile -- with enemies loitering
near home neither ever arrived, `Retreat()`'s dedup kept returning the held
task, and the noTask watchdog never fires because a held retreat samples as
"other", not noTask. Absorbing state; the commander stood at the haven
while the base was ground down.

**Patch, two halves (both needed -- the watchdog alone just re-enters the
loop through CommanderTask's flee):** (1) `events.as CommIdleAttribute` now
counts consecutive retreat-held samples and aborts the task after
`apex_comm_retreat_ticks` (default 30 ≈ 30s), forcing a full re-election;
(2) `rules_commander.as`'s influence-flee only fires when home ground is
actually safer (`GetEnemyInflAt(gHomePos) < hereInfl * 0.5`) -- when home
is just as hot, retreating defends nothing, so the commander keeps working
and the per-rule site-safety vetoes steer the work. Confirm on the next
match: `comm-why` keeps printing past a flee, `retreatCut=` > 0 when a
retreat gets pinned, and gadget `commIdle/commSamp` stays well under the
56% measured here. Delete once measured.

---

## OPEN: commander holds a build task, site in build range, NO engine order ever issued -- 60s lost per occurrence, source not yet traced (2026-08-15)

Found while confirming the retreat-pin fix. In
`matches/20260815-042833-.../infolog.txt` the (now position-annotated)
stuck log shows: `stuck on bt13 ... comm=1500,3787 site=2144,4000
def=armmex` twice in a row on the SAME site, and `stuck on bt4 ...
comm=2174,3927 site=2184,3848 def=armsolar` -- the commander 80 elmos from
the site, i.e. IN build range, holding the task for 60s with
`CmdQueueSize()==0` before `apex_comm_stuck` dropped it. The `waiting`
comm-why bucket (task held, no order) accumulated ~8.5 minutes in that
match's first 12 minutes, mostly in sub-60s chunks the watchdog never trips
on. Candidate mechanisms, not distinguished: (1) the engine silently
refusing CmdBuild at a spot that became blocked/claimed (the documented
silent-no-op class) with the task then never re-siting; (2) a path query
that never completes; (3) benchmark-speed order-application lag inflating
the bucket (CLAUDE.md: reads lag ~45 sim-seconds at the speed cap) --
meaning the sub-60s chunks may not exist at watched/live speed at all.
Next step: reproduce at `--speed 3` to separate (3) from (1)/(2) before
touching any code; the stuck log's site/def annotation added 2026-08-15
gives the repro everything it needs.

**Scale data, 2026-08-15 tournaments:** `waiting` is now the single largest
commander idle bucket everywhere -- ~34% of samples even in the healthiest
instrumented game (612/1801), 60-75% of the first 12 minutes in the worst
(first tournament's t010: repeated 60s stucks on corlab/cormex/corllt, the
commander parked at one position for minutes at a time). Three games in
the first 12-game tournament froze ALL commander logging at ~11 minutes
(comm-why samples 636-794 for 30-minute games) -- terminal state unknown
there because the diagnostics of the time only printed from AiMakeTask;
the `comm-now` line added the same day prints from the sampler and closes
that blind spot, and the second 12-game tournament showed zero freezes.
This entry is now the main remaining commander-idle work item.

---

## OPEN, MINOR: commander noTask watchdog can fire repeatedly at low near-threshold influence (2026-08-15)

The `CommIdleAttribute()` noTask watchdog (`events.as`/`rules_commander.as`,
`gCommNoTaskStreak`) was added to fix a severe case -- a commander under
CONTINUOUS heavy influence (1-99, measured) sitting with literally no task
55% of the time. Confirmed fixed via smoke test. But the same smoke test also
showed 8 force-assigns in under a minute at LOW influence (0.16, barely above
the 0.01 flee threshold) -- likely `CRetreatTask`'s own `Recovered()` clears
the task quickly at such a weak signal, then the commander immediately reads
influence-above-0.01 again from a lingering weak source (e.g. a wandering
scout) and gets re-forced. Not the same failure mode as the severe case
(commander IS getting real tasks, just some redundant churn at the margin).
Candidate fix: hysteresis -- once forced, require influence to clear a lower
"truly safe" threshold (not just re-cross 0.01) before the watchdog goes
quiet, same shape as the dedup fix's own reasoning. Not implemented; needs a
match where this specific low-influence pattern is common enough to judge
whether it is worth the added complexity.

## PATCHED, NOT YET MEASURED: front-line defence share below local/rear share in the opening income bracket -- `Targets::DEF_FRONT`/`DEF_LOCAL` (2026-08-14)

apexearth, live: "we aren't guarding the front of our base well with
turrets." `targets.as:131-132` had `DEF_LOCAL` (mex guards, dig-ins) equal to
or above `DEF_FRONT` (the Brain's front line) for the whole opening income
bracket (8-20 m/s), the section's own comment warning about exactly this.
Rebalanced so front leads local at every income column -- see `changes/
2026-08-14.md` for the match evidence (rear 21 standing vs 3 front orders in
one match). Needs a deploy + watched/measured pass before closing.

**Separate, unresolved sub-question found while diagnosing the above**: the
Brain's `FrontDefenceWant` (`manager/brain.as:719`) stopped issuing new front
orders after #3 at 3.5 minutes, in a match where the front curve (`fwd=`,
`ForwardFraction`) was visibly shrinking (losing ground) for the following 12
minutes -- exactly when more front cover should be wanted, not less. Two
plausible mechanisms, neither checked yet: `FrontLineSpots`
(`territory.as:857`) finding no `have==0` gap once a short curve reads
covered by 3 turrets' nominal range, or `Builder::DefenceTaskNear` blocking a
re-request at a stretch whose order was placed but never built (no builder
survived the walk, or none was ever elected). Needs a match with `apex: brain
orders front defence #N` logged past #10 (the throttle only prints #1-3 then
every 10th) compared against one that stalls the way this one did.

---

## PATCHED, NOT YET MEASURED: commander sits on a full metal bank after a base wipe, never rebuilds the lab -- one-sided escape valve in `OpeningNeedsEconomy()` (2026-08-14)

apexearth, live: "our guy lost his main base, now he's running around hiding
with a full metal bank... he needs to make T1 labs asap... Commander doesn't
seem to rebuild the core lab after losing everything." Not a regression of the
held-task stickiness fix (`rules_commander.as:237-240`/`maketask.as:190-199`)
-- those only ever return an EXISTING factory task, never swallow a fresh
request. The real gate is `OpeningNeedsEconomy()` (`manager/builder/
opening.as:45`, itself added earlier the same night): its raid-collapse escape
checked METAL income only. A wipe that kills generators but leaves mexes (and
a banked stockpile) standing collapses ENERGY income while metal stays fine,
so `short_` stays true on the energy term forever and the gate never releases
-- `rules_commander.as:218`'s factory-rebuild branch stays blocked
indefinitely. **Fix:** added a symmetric `gOpenPeakEnergyIncome` escape,
mirroring the existing metal one. See `changes/2026-08-14.md`. **Not deployed
or measured** -- no accessible infolog for the live game (stale since
2026-08-13). Confirm on the next watched game with a full base wipe: `apex:
commander rebuilding a factory -- we have none` should log once energy income
collapses, not stay silent while `apex: opening economy-first` repeats
forever. Delete this entry once measured.

---

## PATCHED, NOT YET MEASURED: builders walk long distances to join/assist a build that finishes before they arrive -- added an ETA-vs-remaining-build-time guard, but the ETA is a flat-speed approximation (2026-08-14)

apexearth, live: "our units are willing to walk long distances to build a
building which would be built by the time they get there." `Requests::JoinFor`
and `Requests::Redirect` (`manager/builder/requests.as`) ranked candidate
sites on build progress then distance only -- no check on whether the walk
itself outlasts the remaining build. Added `WorthJoining()`: estimates
remaining build time as `costM * (1-progress) / (DRAIN * busyWorkers)` and
skips the candidate if `dist / ASSUMED_CON_SPEED` exceeds it (counted in new
`gTooFar`, in the `apex: request ...` log line). **This is a real arithmetic
estimate, not exact**: `CCircuitDef`/`CCircuitUnit` expose no move-speed
binding to AngelScript (grepped `InitScript.cpp`, confirmed absent), so the
travel time uses one flat `ASSUMED_CON_SPEED = 40` elmos/s for every unit
regardless of its actual speed (real T1 con speeds: armck/corck bots 36,
armcv/corcv vehicles 54) -- a fast vehicle con could be wrongly turned away
from a join still worth making. Not deployed or run tonight (apexearth
watching a game). Confirm with `behaviour_check.py`/`composition.py` after
deploy: watch for `tooFar` counts in the request log, and check `JoinFor`
picks (site progress vs. distance) no longer include cases where the site
would clearly finish first. If the flat-speed approximation proves too coarse
in practice, the real fix is binding `CCircuitDef::GetSpeed()` to script
(`cpp/src/circuit/script/InitScript.cpp`) -- a C++ change, not done here.
Delete this entry once measured.

---

## PATCHED, NOT YET MEASURED: AA overbuilt with zero current enemy air -- `GetEnemyCost` never decays (2026-08-14)

apexearth, live: "We've made 5 AA units while the enemy has no air... cost 125
metal each... Worthless." `Military::UpdateAirThreat()`
(`manager/military/airthreat.as`) fed `gAirRaw`/`gAirAvg` from
`aiEnemyMgr.GetEnemyCost(RT::AIR)`, which never forgets a unit once seen (dead
or not, per `EnemyManager.h:80-86`) and is monotonic non-decreasing -- one
early enemy air scout/con permanently pinned the reading above `AA_IGNORE`
for the rest of the match, keeping `Brain::AirCoverWant()`'s presence gate
open and `Builder::AAWantedNow()`'s per-player floor drawing indefinitely
with no real air left to answer. Pre-existing (the 240s EMA was always going
to climb past `AA_IGNORE` and never fall back eventually too), but tonight's
`AirThreatNow()` presence-gate fix collapsed the lag to zero, making it fire
the same tick instead of minutes later -- which is why it only became visible
tonight. **Fix:** swapped the raw input to `GetEnemyCostFresh` (already
bound, already used elsewhere for the same reason in
`manager/military/territory.as:744`'s `GhostDiag()`), which only counts
sightings within `freshFrames` (60s default) and genuinely decays. See
`changes/2026-08-14.md`. **Not deployed or measured** -- no accessible
infolog for the live-hosted game that prompted the report (`data/infolog.txt`
stale since 2026-08-13). Confirm on the next watched game: `apexaa: airRaw=`
should fall back toward 0 within ~60s once the enemy's air is gone/unseen, and
`aaT1` should stop climbing once it does. Delete this entry once measured.

---

## PATCHED, NOT YET MEASURED: T2 lab placed in front of the enemy base -- overbroad `GetTaskCountOf(FACTORY)` gate (2026-08-14)

apexearth, watching a fresh 1v1: "We built a T2 lab right in front of the
enemy's base." `Builder::AdvancedPlantAtRear`
(`manager/builder/rules_optional.as:191`) already places the T2 lab
home-safely via `RearOfBase()` + a `ThreatFor` veto, and sits above
`DefaultMakeTask`, so it wins when it fires -- but it bailed on
`aiBuilderMgr.GetTaskCountOf(int(Task::BuildType::FACTORY)) > 0`, which counts
by BuildType only (`cpp/src/circuit/module/BuilderManager.h:279`), so an
ordinary unrelated second T1 lab under construction silently vetoed it,
falling through to stock `DefaultMakeTask` with no home bias at all -- exactly
what the rule's own comment already predicted. **Not the same mechanism as
tonight's `BorderPos`/`OnBorder` fix** for static defence -- factory placement
never touches `BorderPos`. Fixed: replaced the gate with
`ai.GetDefBuildProgress(adv) >= 0.f`, per-def, which closes the intended race
(two builders grabbing the same rear-plant request) without tripping on an
unrelated factory; `Requests::Allowed`'s per-def `InFlight` check two lines
below already covered that race correctly and made the old gate redundant.
See `changes/2026-08-14.md`. **No infolog exists for the live-watched game
itself** (hosted MP writes to `data/infolog.txt`, last touched before this
session) -- diagnosis is from code reading plus a tournament log showing the
rear rule places correctly whenever its gate lets it. Confirm on the next
watched game: `apex: T2 plant <def> at the rear` should log even with a second
T1 lab mid-build, and no T2 lab should land forward of the front. Delete this
entry once measured.

---

## PATCHED, NOT YET MEASURED: 1v1 T2 commit read only economy, never safety (2026-08-14)

Same report as above ("T2 lab right in front of the enemy's base"), the WHEN
half rather than the WHERE half. `Factory::RushReady()`
(`manager/factory/techlead.as`) already collapses solo to the stricter
follower bar (`FollowerEconomyReady()`: metal>=25, energy>=600) since
`IsDesignatedLead()` needs allies -- checked against the most recent watched
1v1 (`matches/20260815-001117-.../infolog.txt`), the economy gate was
genuinely met (mInc 27-31, eInc 687) at the 5.4 min commit, not thin. But
`RushReady()`/`AiIsSwitchAllowed`/`RushBuildPower` never check whether it is
SAFE to commit -- committing idles the factory's own army line and waives the
normal army-value switch check, fine when a teammate is holding the front,
not fine alone. Fixed: `RushReady()` now also requires
`!Military::LosingGround() && !Military::BaseContested()`
(`manager/military/territory.as:1041,1048`), the same signals
`defenceline.as` already uses for this exact question. Uniform across team
sizes, not a team-count branch (the 2026-08-10 `!IsSmallTeam()` attempt was
negative, but ran under the since-removed `ApexActive()` solo gate that made
apex's own rush logic dead code in every 1v1 at the time -- that measurement
cannot be trusted now that `ApexActive()` always returns true). See
`changes/2026-08-14.md`. **Not yet measured** -- no match run in this task's
scope. Confirm on the next watched 1v1: T2 should not commit while
`Military::LosingGround()`/`BaseContested()` are true, and a 1v1 that never
sees enemy pressure near home should be unaffected (both signals stay false).
Delete this entry once measured.

---

## PATCHED, NOT YET MEASURED: commander lost with a clean threat sample 930 frames before death -- flee-influence tunable turned on (2026-08-14)

apexearth watched a match live and reported "our commander was being too brave."
Confirmed against that same match,
`matches/20260814-233416-Apex-apex-hard_aggressive_vs_BARb-stable-hard/infolog.txt`:
`COMMANDER LOST frame=27675 hp=-2`, and the last `apex: comm threat=` sample
before it, 930 frames (~31s, one sample period) earlier at frame 26745, read
`threat=0.00 hp=100`. The commander died alongside a cluster of other units
sharing its build task (`armrectr` x3, `armwar` x2, `armck`, `armjeth`,
`armmex`) all at the same position, all destroyed in the same tick -- a
sudden local strike, not a slow attrition the periodic threat sample could
have caught. Not offensive risk-taking (the commander has no combat/attack
logic and is excluded from `Fortify`/squad combat) and not a rule sending it
somewhere dangerous (its last accepted task, `mexup`, was ~900 elmos from the
death site). This is trap #2 from `commander-opening`'s domain notes,
reproduced: local threat reads clean right up to death.

**Patch:** `manager/builder/rules_commander.as`'s `apex_comm_flee_influence`
tunable already existed for exactly this (enemy INFLUENCE at the commander's
own tile, which is not fooled by a killer at range the way the threat map
is) but shipped compiled-default 0 (off), "no measured threshold." Turned on
at 0.01 -- the same "any nonzero `GetEnemyInflAt` reading = attacked"
calibration `BaseUnderAttack()` (`converter.as`) already uses, not a new
invented number. **Not deployed or re-run** by this pass (out of scope for
the agent that made it). Confirm on the next watched/tournament run: does
`commLost` improve, and does `apex: commander leaving, enemy influence`
actually fire before a death instead of after. Delete this entry once
measured.

---

## OPEN, FOLLOW-UP (not started): support role needs splitting into radar/jammer/spec-ops (2026-08-14)

Distinct from the zero-unfreeze landed in the "FOURTH PASS" entry below --
that only stopped the hard-zero on individual defs (`corvoyr`/`corspec`/
`armmark`/`armjam`/`cormabm`/`legaradk`/`legajamk`, 0.00->0.03 at low tiers).
It did NOT address the underlying taxonomy problem apexearth called out:
mobile radar, jammer and spec-ops units are ALL lumped into one generic
`behaviour.json` role `"support"`, which carries `response.json`'s lowest
`importance` (2.00) and `max_percent` (0.20) of the whole table -- a jammer
and a spec-ops raider have nothing in common tactically and compete for the
same undersized response budget. A real fix needs its own role categories
(e.g. `radar`, `jammer`, `spec_ops`) each with their own `response.json`
entry, sized on what each actually does -- real design work, not a config
tweak, and needs its own session per the task that produced this entry.

---

## PATCHED, NOT YET MEASURED: `EnergyConverter` handed armmmkr to units that can't build it, stalling conversion and blocking fusion all game (2026-08-14)

Live match `matches/20260814-231356-Apex-apex-hard_aggressive_vs_BARb-stable-hard`:
zero fusions built the whole game despite income reaching 293 m/s and
`energyExcess=249375.2` at end. Root cause: `EnergyConverter`
(`manager/builder/converter.as`) picked `BigConvDef(unit)` off a team-wide
tech-availability check with no per-unit buildOptions guard, so T1 cons and
the commander were handed armmmkr constantly (1,100+ `BUG blocked ...
armmmkr` lines, one match). `GuardBuildCapability` correctly vetoed each one,
but the veto is a null return, not a fallback to the buildable T1 def, so
these workers built no converter at all. Conversion capacity never kept up
with income, `EnergyWasting()` stayed true the whole game, and `EcoFusion`
(`fusion.as:199`) refuses by design while wasting is true. Patched with the
same `advBuilder` guard `EcoConverters` already carries. Not yet re-run —
confirm `fusCount` and `energyExcess` in the next watched/tournament run,
then delete this entry.

---

## OPEN, LOW CONFIDENCE: defence's under-attack escalation is a boolean, not graduated by severity (2026-08-14)

apexearth wanted excess con power redirected into defence during a sustained
attack. That mechanism already exists and was firing correctly in the match
that prompted the request (`defenceline.as:422`, `pressureAllow = (gTurtle ||
BaseContested()) ? 2.f : 1.f` — doubles the front-line metal budget;
`BaseContested()`, `territory.as:1041`, reads live net influence at home, not
economy). See `changes/2026-08-14.md` for the full telemetry from
`matches/20260814-225550-...` — `mDefence` climbed through the loss window and
requests (`armllt`/`armbeamer`) kept firing at rising cap right to shutdown;
the base was lost to total overrun in the final ~60-90s, not to defence being
undervalued or under-requested.

Left open only because the escalation term itself is coarse: a flat 2x that
trips only once the enemy already holds net influence at home (late), rather
than scaling with how badly we're losing (`EnemyArmyCost()/armyCost`,
`GetAttackHotspot` weight, or recent-loss rate as a leading indicator). No
patch proposed — one match showed the pipeline working, not failing, so
tightening this without a match that shows genuine under-firing would be
tuning on impatience rather than evidence (see CLAUDE.md "Ask before inventing
policy" / "Economy over static numbers"). Re-open with real evidence of
under-request before touching `pressureAllow`.

## PARTIALLY FIXED, awaiting tournament confirmation: T1 factory queue has no combat floor -- the con quota can own 100% of the line (2026-08-14)

LIVE report, apexearth watching: "our base is being hit/attacked and we're
only making cons... losing this game for sure" /
"if all our factory time is spent on cons then we'll have a small army" /
"the game wasn't even at T2 phase yet... we don't even have enough work or
need for cons." Match:
`matches/20260814-225550-Apex-apex-hard_aggressive_vs_BARb-stable-hard/`,
shutdown frame 19724, `armed=10` vs `ownBuilders=19`, `facCount=1` the whole
game.

`brain/facqueue.as:265` `QuotaFor` inserts the constructor want
(`Builder::ConsWantedFor`, `*1.5+1` under `isMetalFull`) as a FLOOR first,
and the consuming loop (`:541-553`) `break`s on the first short floor --
combat defs live only in the ratio section below, reached only once every
floor is met. `T2ArmyShort`/`T2CoreWanted` (`:205-231`) already give combat
roles priority over the con floor, but ONLY once the line has T2
buildoptions AND an advanced con already built (`:218-222`) -- there is no
equivalent protection while T1-only, which is exactly this match's whole
11 minutes. Measured: frame 7200->10800, `mLostMobile` 110->1575 while
cumulative `cheapBuilt armck` 550->1430 against `conT1` (alive) only 5->7 --
constructors were dying and being replaced in a loop instead of the line
ever reaching a combat def. By shutdown `armck` cumulative 2200 vs all
mobile combat (`armfav+armflash+armflea`) 749 -- 3x the factory metal into
cons.

**Implemented and smoke-tested this pass.** Added `T1ArmyShort`/
`T1CoreWanted` (`facqueue.as`, next to `T2ArmyShort`), same income-scaled
floor-only shape, gated on the line having neither `Factory::Attr::T2` nor
`Factory::Attr::T3` (T1-only). Used `RT::RAIDER`/`RIOT`/`SKIRM`, not
`T2ArmyShort`'s `RT::ASSAULT`/`HEAVY`/`AH`/`AHA` -- those roles are already
confirmed resolving on a T1-only line via `QuotaFor`'s own unconditional ratio
section, so no new uncertainty there. Deployed, compiled clean (`grep ERR`
empty across three headless smoke runs), and confirmed FIRING with a temporary
debug log (`apex: DEBUG T1ArmyShort fired ... want=4` at frame 1365, then not
again once the floor was met) before removing the log and redeploying the
final version. On the clean run, a still-T1-only line (`facCount=1` the whole
8-minute match) showed cons (`armck`) capping at 330 metal and holding flat
while combat (`armflea`, RT::RAIDER) kept growing (21 -> 84 -> 105) for the
rest of the match -- the con floor no longer owns the whole queue once met.

**Not yet closed.** Only an 8-minute 1v1 smoke test was run, not a
tournament/composition.py comparison against the pre-fix baseline at matching
scale -- the original report's ~7:1 con:combat ratio over 11 minutes was not
directly reproduced or disproved. Re-check with `python tools/composition.py`
on a longer/matched run before deleting this entry. See
`changes/2026-08-14.md` for the full trace, tunables
(`apex_t1_core_per_income`, `apex_t1_core_min`), and match dirs.

---

## OPEN: general CanBuild guard -- landed, not deployed, not measured-confirmed (2026-08-14)

Follow-up to tonight's `IsAdvConDef` fix (T1 constructors handed advanced-only
converter/fusion defs, 45/45 = 100% silent task-death). Generalizes it: added
a native `CCircuitDef::CanBuild` binding (`cpp/src/circuit/script/InitScript.cpp:958-963`,
wraps the already-existing `CircuitDef.h:203` buildOptions lookup) and a single
pipeline-wide guard, `Builder::GuardBuildCapability` in
`ai/apex/game-side/script/hard_aggressive/manager/builder/maketask.as`, called
from `AiMakeTask` on every returned task. C++ rebuilt via docker
(`ninja BARb` succeeded), `sync_cpp.py apply`'d and
`game-patches/circuitai/0003-cumulative.patch` regenerated. **Not deployed, no
match run, no `behaviour_check`/`composition` pass this session** -- per
instructions for this task. Confirm before deleting this entry: deploy, run a
watched or tournament match, grep the infolog for `apex: BUG blocked` (should
be rare/zero if upstream rules are already correct -- the guard existing and
never firing is the expected good outcome) and confirm no AngelScript compile
error (`grep -oiE "[a-z_]+\.as \([0-9]+, [0-9]+\) : ERR .{0,80}" infolog.txt`).

---

## OPEN, FOURTH PASS: Hound baseline tier1/2 smoothed + support hard-zeros unfrozen -- LANDED, not yet measured (2026-08-14)

apexearth watched a fresh match with BOTH tonight's fixes deployed
(`matches/20260814-231356-...`) and reported no change: "why are we still
making pretty much only hounds?" `top=armfido:31065,...`, `armfboy` reached
only 1400 cumulative, `armsnipe` doesn't appear in `allBuilt=` at all despite
the tier0 0.00->0.03 bump.

**Root cause, traced through `FactoryManager.cpp:1694-1704`:** the roulette
wheel weight for a candidate is `RoleProbability(bd) * (probs[i] + reWeight)`,
falling back to plain `probs[i]` whenever `RoleProbability` returns 0 (which it
does once a role's share of `armyCost` exceeds `response.json`'s
`max_percent`, or the `vs` condition isn't met at all). So response.json's
`reWeight` is *additive on top of* the factory.json baseline `probs[i]`, never
independent of it, and `max_percent` only throttles the response term -- the
underlying baseline draw keeps going regardless of cap.

`factory.json`'s `armalab.land` baseline (income tiers 1<=x<30 / 30<=x<60 /
60<=x<80 / >=80, `GetFacTierProbs`, `FactoryManager.cpp:1744`): `armfido`
0.50/0.45/0.40/0.15/0.15 across tier0-4 vs `armfboy` 0.03/0.05/0.15/0.30/0.30
and `armsnipe` 0.03/0.05/0.20/0.20/0.20 (tonight's earlier fix only touched
tier0). At **tier1 -- the income band most of a 20-minute game's early-mid
build time sits in -- armfido's baseline is 9x armfboy/armsnipe's (0.45 vs
0.05)**, entirely independent of any response boost. Only at tier3/4 does the
table flip (armfido 0.15 vs armfboy 0.30) -- but by then a large fraction of
cumulative `allBuilt=` metal has already been spent at the tier1/2 ratio,
which is what cumulative totals over a whole game measure. This is why the
`assault.max_percent` cut (0.8->0.4) landed earlier tonight did essentially
nothing: it caps the response bonus, not the baseline that's actually doing
the work.

**Sniper's total absence** is consistent with variance on a genuinely tiny
weight (0.03-0.05 baseline against a pool where `armfido` alone is 9-13x
larger at the tiers most decisions land in) rather than a second zeroing bug
-- tier2/tier3 values (0.20) were never touched and are not zero, they're just
competing against a much bigger `armfido` slice most of the time.

**PATCH (LANDED this pass, `factory.json`/`factory_leg.json`):** smoothed
`armalab.land` tier1/tier2 from the pass-3 cliff toward the already-tuned
tier3 shape instead of inventing new numbers: `armfido` tier1 0.45->0.30,
tier2 0.40->0.20 (tier3 stays 0.15, unchanged); `armfboy` tier1 0.05->0.15,
tier2 0.15->0.25 (tier3 stays 0.30); `armsnipe` tier1 0.05->0.12 (tier2 was
already 0.20, matching tier3, left alone). `.water` was left untouched --
checked and it was already smooth (`armfido` 0.50/0.40/0.20/0.10, no cliff),
so nothing to fix there.

**Correction to the Sniper/Fatboy entry below: Legion DOES have a T2
assault+heavy twin.** `leginc` (`behaviour_leg.json`) carries
`"role": ["heavy", "assault"]` and lives in `legalab` itself (not `leggant`
as previously written -- `legkeres` is a separate T3 unit). `leginc` was
hard-zeroed at tier0/1/2 (0.00/0.00/0.00) then cliffed to 0.40 at tier3 --
the same shape as pre-fix Sniper/Fatboy, just more extreme (literal zero, not
just low). Unfroze it: tier0 0.00->0.03, tier1 0.00->0.10, tier2 0.00->0.20,
ramping toward the unchanged tier3 0.40.

`coralab`'s assault-role T2 bot is `cormort` (confirmed via
`tools/unitdef.py`/`behaviour.json`, role `["assault"]`); its Cortex heavy
sibling is `corsumo` (role `["heavy"]`). Applied the same direction of
correction: `cormort` tier1 0.40->0.30, tier2 0.20->0.15; `corsumo` tier1
0.10->0.15 (tier2 already 0.20, left alone).

**Support-role hard-zeros unfrozen** (same 0.00->0.03 bump used as precedent
for Sniper/Fatboy tier0, applied only where a cell was a literal 0.00 at
tier0/tier1 -- see the follow-up entry below for the full role-split, not
attempted this pass): `armalab.land.tier0` `armmark` 0.00->0.03;
`coralab.land.tier0/tier1` `corspec` 0.00/0.00->0.03/0.03;
`coralab.water.tier1/tier2` `corvoyr` 0.00/0.00->0.03/0.03; `coravp.land/air/
water.tier0` `cormabm` 0.00->0.03 (all three), plus `water.tier1` 0.00->0.03;
`armavp.land/air/water.tier0` `armjam` 0.00->0.03 (all three), plus
`air.tier1` 0.00->0.03; `legalab.land.tier0/tier1` `legaradk`/`legajamk`
0.00/0.00->0.03/0.03 each.

`python tools/check.py` run after all edits: no new errors introduced (the 3
`legamsub`/`leggantuw`/`legplat` errors reported are pre-existing, in
`behaviour_leg.json`, untouched by this pass).

**Not deployed, no match run**, per instruction -- next step is deploy, then
`allBuilt=`/`composition.py` on a watched or tournament game to confirm
`armfido`'s share falls, `armfboy`/`armsnipe`/`leginc` actually get built, and
that Cortex/Legion combat mix moved with Armada's rather than staying flat.

Full math in `changes/2026-08-14.md`.

---

## OPEN: Sniper/Fatboy tier0 baseline bump vs Hound -- landed, not yet measured-confirmed (2026-08-14)

Follow-up to the Sniper zero-fix and the `assault.max_percent` cap fix earlier
tonight. apexearth: Sniper and Fatboy should also be credited as strong static
counters, alongside Hound. `response.json` already weights both above Hound
(`anti_heavy_ass`/`heavy` static importance 10.00 vs `assault`'s 5.00) so no
response.json change was made. The actual bottleneck is `factory.json`'s
tier0/tier1 baseline: `armalab.land`/`.water` tier0 had `armfboy`/`armsnipe`
both at 0.00 against `armfido` at 0.50 -- since `RoleProbability` multiplies
the response boost onto this baseline rather than drawing independently, a
near-zero baseline stays near-zero regardless of response weighting. Bumped
tier0 `armfboy`/`armsnipe` 0.00 -> 0.03 in `factory.json`, and Legion's Sniper
twin `legsrail` 0.00 -> 0.03 in `factory_leg.json`'s `legalab.land.tier0`.
**Correction (2026-08-14, fourth pass): the "no T2 Fatboy twin" claim above
was wrong** -- `leginc` (`legalab`, role `["heavy","assault"]`) is Legion's T2
assault+heavy unit; `legkeres` is a separate T3 unit in `leggant` and is not
relevant here. `leginc` was hard-zeroed through tier2 and has since been
unfrozen -- see the entry above. Also noted:
`legsrail`'s behaviour_leg.json role is `anti_heavy`, not `anti_heavy_ass`
like Armada's `armsnipe` -- unconfirmed whether that's deliberate. Full
mechanism in `changes/2026-08-14.md`. **Not yet measured** -- confirm via
`allBuilt=` for `armsnipe`/`armfboy` in the next watched or tournament game
before deleting this entry.

---

## OPEN: AA gate decoupled from 240s smoothing -- landed, not yet measured-confirmed (2026-08-14)

apexearth, live: "we get bombed by the enemy and aren't making any AA...
we plateau and don't do anything greater." Root cause: `AirCoverWant`
(`manager/brain.as`) and `UpdateAirThreat`'s heavy-AA sizing
(`manager/military/airthreat.as`) both gated on `gAirAvg`, a 240s EMA
(`AIR_AVG_SECONDS`, `manager/military/defenceline.as:595`) floored at
`AA_IGNORE=500`. In `matches/20260814-222654-Apex-apex-hard_aggressive_vs_BARb-stable-hard`,
`airRaw` (this tick's true enemy air cost) climbed 150 -> 4924 over minutes
12-20 while the gated smoothed value only reached 948 by the match's last log
line -- `apex: cheap-aa` never fired once, `aaT1` stayed 0 all game,
`allBuilt=` shows one `corrl` (80 metal) and zero heavy AA. Fix: added
`gAirRaw`/`Military::AirThreatNow()` (unsmoothed, same floor) for the
PRESENCE gate; sizing (`AAWantedNow`, `heavyWant`) now uses
`max(raw, smoothed)` so a detected raid is answered the same tick instead of
up to 4 minutes later, while the smoothed value still bounds the RATIO so a
single overflight can't swing the count. Full mechanism in
`changes/2026-08-14.md`. **Not yet re-measured against a live game** --
confirm via the next watched game's `apexaa:`/`apex: cheap-aa` lines and
`aaT1` before deleting this entry.

**FOLLOW-UP, same day**: the next watched game confirmed `AirThreatNow`
itself is NOT the problem -- `apexaa:` logged `airRaw=0` the entire match, and
the mobile AA apexearth saw built-then-killed (`armjeth`, 125 metal, matching
his count) came from an UNRELATED flat weight in `factory.json`'s general
vehicle pool, not from this gate. See `changes/2026-08-14.md`
("AA built with zero enemy air, and AA killed doing ground attacks") for the
two separate mechanisms and fixes (factory.json weight cut 0.05-0.06 -> 0.02;
`WantsMassing` no longer pools ground AA into the ATTACK-promoting massing
pool). Neither fix is tournament-confirmed yet.

---

## OPEN: "skirmish"/"riot" T2 roles are single-def in both armalab and coralab, same shape as the assault cap just lowered (2026-08-14)

Not yet fixed or measured. `armzeus` is the sole `role: ["skirmish"]` def and
`armmav` the sole `role: ["riot"]` def in `armalab`'s 16-unit list
(`ai/apex/game-side/config/hard_aggressive/behaviour.json:962,975`); Cortex's
`corcan`/mirrors the same "skirmish" singleton in `coralab`. Both response
entries still carry `max_percent: 0.8` (`response.json:44-50,58-64`) --
identical structural risk to the `assault` fix below (any single def response
can claim up to 80% of standing army cost). Not touched this session because
the assault case was the one with direct telemetry proof (`armfido` at 62% of
combat metal); these two are argued from the same code shape, not measured.
Fix by the same reasoning if a future watched game shows `armzeus` or `armmav`
dominating comparably: lower `max_percent` to match apex's own already-set
0.4-0.5 ceiling for other single-def T2 roles (`anti_heavy`/`anti_heavy_ass`/
`heavy`), not stock's inherited 1.0/0.5.

---

## OPEN: rez bots never position toward the army/front while winning -- fix designed, not implemented (2026-08-14)

apexearth, live: "our rezbots don't support our army/fighting... Reclaim,
Resurrection, Repair... they aren't doing much of it at all." Confirmed:
`RezzerFrontSalvage` (`manager/builder/rules_rezzer.as:40-60`) is the ONLY rez
rule that reaches beyond the bot's own position, and it only fires when
`Military::LosingGround()` -- so rez bots follow a retreating front but never
an advancing one. Every other rez rule searches `WRECK_SEARCH` (2200 elmos)
from the bot's current position only. No escort/follow pattern exists
anywhere in the codebase to reuse. Telemetry (`matches/20260814-222654-...`):
rez bots built to 2080 metal, `mRezSpend` only 110 by minute 18, against
thousands of `mKillMobile`/`mLostMobile` -- corpses existed, bots weren't
there. Proposed fix (see `changes/2026-08-14.md` for full writeup): broaden
the gate so `RezzerFrontSalvage` also fires when winning/pushing and the
bot's local search is empty, reusing the existing `FrontLinePos()` (already
win/lose-agnostic) and `ThreatFor`/`CON_THREAT_VETO` safety check. Layer 2
only, no DLL rebuild needed. Delete this entry once implemented and a run
shows `mRezSpend` rising relative to `mKillMobile`/`mLostMobile` while
attacking, not just defending.

---

## OPEN: rez-bot repair fix lands only after a DLL rebuild+deploy -- not yet live-confirmed (2026-08-14)

apexearth, live: "we have a lot of rezbots standing around doing nothing while
units next to them need to be repaired." Root cause and fix in
`changes/2026-08-14.md`: `CBuilderManager` never registers a `damagedHandler`
for ordinary mobile combat units (only for builders/rez-bots' own damage and
for static structures), so no REPAIR task is ever created for a hurt unit in
the field. Added `CCircuitAI::GetOwnDamagedNear` (C++,
`cpp/src/circuit/CircuitAI.cpp`/`.h` + `InitScript.cpp` binding) and
`Builder::RezzerRepairNearby` (AngelScript, `manager/builder/rules_rezzer.as`,
wired into `manager/builder/maketask.as`). **This needs a `SkirmishAI.dll`
rebuild (`docs/06-building-the-dll.md`) and `deploy_ai.py deploy apex` before
it does anything** -- the AngelScript half is inert until the new
`ai.GetOwnDamagedNear` binding actually exists in the running engine. Delete
this entry once a rebuilt/deployed run shows rez bots picking up REPAIR tasks
on damaged field units.

**2026-08-14 follow-up:** apexearth reported (after this landed, watching a
fresh game) "our rezbots still don't repair fast enough." Found and fixed a
real bug in the same rule: `RezzerRepairNearby`'s throttle (`gNextRezRepair`)
was a single global frame counter shared by every rez bot on the team, so at
most one bot on the whole side could be handed a new repair target per
`REZ_WRECK_PERIOD` (1s) no matter how many were idle. Changed to a per-bot
gate (`gConNextRepair[ConSlot(unit)]`, `manager/builder/fortify.as` +
`rules_rezzer.as`) -- see `changes/2026-08-14.md` for the full writeup,
including why the engine's native area-repair `CMD_REPAIR` (4-param) order
apexearth suggested is not a clean fit here (no C++ binding exists for it, and
wiring it in bypasses CircuitAI's whole task-tracking model). The residual
one-task-one-target-to-completion model is real and NOT fixed by this --
would need new C++ to change. Not deployed/measured this pass.

---

## OPEN: commander and rez bot both idle beside a damaged HLT under fire -- not yet live-confirmed (2026-08-14)

apexearth, live, a DIFFERENT match than the mobile-unit rez-bot fix above: "Our
HLT turret is being shot and the commander and rezbot nearby didn't try to heal
it -- they just sat idle." Distinct mechanism from the mobile-unit case:
`CBuilderManager` DOES register a `damagedHandler` for static structures
(`buildingDamagedHandler`, `BuilderManager.cpp` `InitHandlers`) and it
unconditionally enqueues a HIGH-priority `TaskB::Repair` the instant one takes
damage -- the task exists. Two separate native reasons nobody ever gets it:

1. `CBuilderManager::MakeTask`/`MakeCommTask`'s own ranking loop
   (`BuilderManager.cpp` ~line 1074) skips any task at NOT-`NOW` priority
   (repair is `HIGH`) sitting on ANY negative influence at all --
   `inflMap->GetInfluenceAt(testPos) < -INFL_EPS`, a bare boolean, not a graded
   threat check -- so a structure actively being shot at is by definition never
   offered via `DefaultMakeTask` to anyone.
2. `CBRepairTask::CanAssignTo` (`task/builder/RepairTask.cpp:37-39`) hard-excludes
   `IsRoleComm()` from ANY repair task, structure or mobile, at the native
   ranking layer -- independent of (1), so the commander specifically could
   never take one even from a safe distance.

**Fix (Layer 2 only, no DLL rebuild):** `AssignTask` (`TaskModule.cpp:70-76`)
never re-checks `CanAssignTo` when the script hands back a task directly -- the
same property tonight's `RezzerRepairNearby` already relies on for the
mobile-unit gap. Added `Builder::RepairStructureNearby` (`manager/builder/
fortify.as`), which scans the existing `gStructRepair` registry (already
populated by `AiTaskAdded`, previously used only to abort doomed repairs in
`obsolete.as`) for an unclaimed target within `REPAIR_REACH` passing the same
`ThreatFor <= CON_THREAT_VETO` graded check every other reflex in this file
uses, and enqueues that exact target directly -- bypassing both native gates at
once. Wired into `rules_optional.as` (ahead of `RepairNear`, same reflexive/
ungated slot, non-commander builders) and `rules_commander.as` (right after
`HomeTower`, which only ever builds a MISSING tower and is silent once one
already exists and is merely damaged).

Reasoned from `vendor/circuitai` C++ and existing script patterns, not yet
run. Delete this entry once a match shows a con or the commander taking a
REPAIR task on a damaged structure while it is under fire (`apex: ` log line
would need adding if this needs to be traced explicitly -- none was added this
pass to keep the change minimal).

---

## FIXED (deploy + measure pending): advanced converter/fusion handed to constructors that cannot build them -- 100% failure, not combat losses (2026-08-14)

Root cause isolated from the diagnostic added earlier tonight. New match
`matches/20260814-222654-...`, apexearth live: "we sit at full metal and
aren't building any more energy 15m into the game... stopped making more
energy at around 1200 energy."

**`hadNanoframe` settles it: every single removal is `hadNanoframe=0`.** 24/24
`convert-task-removed armmmkr` and 21/21 `energy-task-removed armfus` events
in this match read `hadNanoframe=0` -- the task never got far enough to place
a nanoframe, let alone lose one to combat. `done=0` on all of them too. Not
combat losses. `manager/builder/events.as:144-149`,
`manager/builder/events.as:130-135`.

**Mechanism:** `tools/unitdef.py armmmkr --builders` / `armfus --builders` --
both are built by `armaca/armack/armacv/armcomlvl5-10/armhaca/armhack/armhacv/
armsack/armsacv` only. **Never `armck`, the ordinary T1 constructor.** But
`Builder::HomeEnergy` (`manager/builder/mexguard.as`) picked `BigConvDef(unit)`
(armmmkr) whenever `EnergyWasting()` was true, and `fus` (armfus/armafus) by
pure energy-per-metal ranking, for **whatever constructor reached the rule** --
no capability check on `unit` at all. `Builder::EcoConverters`
(`manager/builder/converter.as:185-195`) had a matching bug: its `advBuilder`
gate had a bypass, `gHaveAdvCon && SmallConvCount(unit) >= ADV_CONV_AFTER`,
that let a plain T1 con request the advanced converter "on the theory nothing
claims it if it can't build it" -- but `Requests::Take`/`Create` binds the
ASKING unit to the task it just created (`aiBuilderMgr.Enqueue(TaskB::Common(
..., unit, ...))`), so the incapable unit gets attached as a worker
immediately, and the engine drops the task again a few frames later. Same
shape as the already-documented `IsAdvConDef` comment at
`mexguard.as:59-68` ("only armcomlvl4+ can build the advanced towers -- asking
a level-1 commander for one is a silent no-op") -- this bug is that exact
class, just on the reactor and advanced-converter rungs of `HomeEnergy`, which
had never had the same guard applied.

Log evidence, `matches/20260814-222654-...`/infolog.txt: e.g. lines
1993-2021 show the same worker (`unit=20146`) handed a fresh armmmkr task at
five different grid cells in under 20 seconds (2384,3184 / 2192,2800 /
2144,3424 / 2128,2800 / 2000,3184 / 2256,2736), every single one removed
within 2-96 frames (0.07-3s), `hadNanoframe=0` each time. Confirmed with
`[BARAI_STATS]`: `conT2=0` (zero advanced constructors) through frame 14400
(8 minutes), yet armfus/armmmkr requests started at frame 25 (game start,
handed to the commander, itself likely below the armcomlvl5 threshold) and
continued through the whole 0-10 minute window before any unit capable of
building either def existed.

**This also explains "stopped making more energy at ~15m":** once
`EnergyWasting()`/`isEnergyFull` goes true, `HomeEnergy`'s `isConv` branch
takes over exclusively -- it does NOT fall through to the solar/advsol/wind
branch that would add more generators (by design: more generation is
pointless while spilling). With the converter target unbuildable, every
constructor reaching `HomeEnergy` funneled into a doomed armmmkr request and
nothing else, so BOTH more generation and the converter that would have used
the spare energy stopped at once -- not `HaveReactor()` blocking new
generators (that gate is working as intended), and not a real "want stopped
scaling with income" bug.

**PATCH:** `manager/builder/mexguard.as` -- `HomeEnergy`'s converter branch
now uses `IsAdvConDef(unit) ? BigConvDef(unit) : null` (falls through to
`SmallConvDef`, armmakr, which `armck` CAN build) instead of unconditional
`BigConvDef(unit)`; the fusion branch now gates `fus` on
`Factory::HaveAnyFactory() && IsAdvConDef(unit)`. `manager/builder/
converter.as` -- `EcoConverters`' `advBuilder` bypass clause removed; only a
genuine advanced constructor (cost-based proxy, same as `IsAdvConDef`,
excluding the commander for the same unknowable-level reason) may request
`BigConvDef`.

**COST:** none new -- this removes spend on a task class that was never
completing, and lets `SmallConvDef` (armmakr, buildable by the T1 cons that
were being wasted on the broken path) absorb spare energy instead once a
T1 con reaches the rule.
**CONFIDENCE:** high on the mechanism (verified builder lists via
`tools/unitdef.py`, 45/45 `hadNanoframe=0` across both defs in this match,
`conT2=0` through the whole window the earliest failed requests occurred in).
**Not yet deployed or measured** per instruction -- next step is deploy +
watch/`composition.py` to confirm armmmkr/armfus actually complete and
`energyExcess` stops pinning at the storage ceiling.

---

## PATCHED, NOT YET LIVE-CONFIRMED: builder mid-walk thrashing + no idle-reclaim floor (2026-08-14)

apexearth, watching Altair_Crossing_V4.1: "construction bots walking around,
then turning around and going the other way, walking towards a mex, stopping,
going somewhere else... sometimes they'll just stand still for a while... in
this map there are trees, we could at least reclaim trees." Two mechanisms,
both in `manager/builder/`:

- `HoldWorkInProgress` (`rules_hold.as`) is the general-path re-election guard
  but gated on `SiteBuildName(busy) != ""`, and `SiteBuildName`
  (`sitesafety.as:245`) deliberately excludes `Task::BuildType::RECLAIM` -- so
  a builder mid-reclaim was never held, fell through to a fresh
  `DefaultMakeTask` offer every tick, and got swapped off the walk by
  `IBuilderTask::Reevaluate` whenever the offer's build type differed. Fixed
  by holding RECLAIM the same way (already re-verified safe every tick by
  `AbandonUnsafeSite`).
- No rule proposed reclaiming neutral map features (trees) at all --
  `ScavengeWrecks`/`TidyObsolete` only cover rich wreck piles and our own
  obsolete buildings, both gated well above a tree's metal value by design.
  Added `IdleFeatureReclaim` (`reclaim.as`), wired into `maketask.as`'s
  genuinely-idle floor (below `TidyObsolete`, non-commander only), reusing
  `EnqueueWreckReclaim` with `minMetal=1` instead of new scoring logic.

Not yet run against a match or watched live -- `tools/check.py` passes, no
match launched per instruction (a watch game may have been active). Delete
this entry once a watched game shows steady mex walks and idle builders
eating nearby trees instead of standing still.

## FIXED (mechanism confirmed live) but SYMPTOM NOT YET RESOLVED: solo tower-dive via LOS-confirmation fallback (2026-08-14)

apexearth, watching, same session as the fragility fix below: "I'll have one
hound standing outside range shooting at a tower, then the next will walk
into range of that tower and shoot at it and die." Root cause in
`CCircuitUnit::Attack(pos, enemy, isGround, isStatic, timeout)`,
`cpp/src/circuit/unit/CircuitUnit.cpp:530-575`: when `enemy->IsInLOS()`
reads false (common for a unit correctly holding standoff at its own weapon
range, which routinely exceeds its sight range -- Hound 650 vs ~400), the
function queues `CmdFightTo(enemy->GetPos())`, walking the unit to the
target's OWN position rather than the standoff ring. Intended for mobile
radar-only ghosts; fires just as often against static towers, whose
position needs no LOS to confirm. Fixed by exempting `isStatic` targets
from the LOS requirement (`CircuitUnit.cpp:551-552`).

**This was built, deployed and watched (DLL timestamp confirmed built and
deployed before the match started), and the symptom was reported again in
that exact watch**: "I see rocket bots walk into turrets and die too...
they out range these things but walk into their death... hounds still make
this mistake." So this fix is real and live, but was not the only cause --
see the next entry for the second mechanism found and patched. Do not
re-diagnose THIS mechanism; the LOS-reissue path is confirmed fixed. Delete
this entry once a watch confirms the second fix (below) closes the symptom.

## PATCHED, NOT YET LIVE-CONFIRMED: standoff margin could land inside a near-parity tower's range (2026-08-14)

Second mechanism behind the same "Hound/rocket bot walks into tower range and
dies" report, found AFTER the LOS-confirmation fix above was already live and
still reproduced. In `ISquadTask::Attack`, `SquadTask.cpp:744-746` (before
this fix): when a row genuinely out-ranges its target (`!outranged` branch),
`standoff` was set to the row's OWN weapon range with no reference to the
target's range at all, then shrunk 10% by `STANDOFF_RANGE_MOD`. Any target
whose range sits within 90-100% of the row's own range then reads as
"outranged" while the shrunk stand-off lands inside its reach anyway --
confirmed with `tools/unitdef.py`: Hound (`armfido`, 650 range) vs `corhlt`
(Warden tower, 620 range): 650*0.9=585 < 620. Fixed by flooring the computed
range at the target's own range (`OUTRANGED_SAFETY_MARGIN`, 1.1x) whenever
this "we out-range them" branch applies and none of the intentional-dive
exemptions (`isArty`/`powerDominant`/`glassCannon`) do.
`cpp/src/circuit/task/fighter/SquadTask.cpp:744-763`. Rebuilt clean via
docker, `sync_cpp.py status` confirms `cpp/`/`vendor` match. **Not deployed,
no match run** -- a watch game was in progress. Delete this entry once a
watched game with Hounds/Rocketeers vs towers shows standoff holding outside
tower range and the "walk in and die" report stops recurring. If it recurs a
THIRD time, check whether Hound/Rocketeer squads route through
`ISquadTask::Attack` at all (task-type assignment in `behaviour.json`) before
patching this file again.

## THIRD PASS, SAME REPORT: re-audited standoff/order path end-to-end, found no bypass for `CAttackTask` -- one narrower, real gap fixed in the SOLO path (2026-08-14)

apexearth pushed back on the pass-2 fix above before it was even deployed:
"that's probably not the real cause because I see them walk much closer than
what you're talking about" -- the 35-elmo band pass 2 closed is far smaller
than what he describes. Also clarified intent: `STANDOFF_RANGE_MOD=0.90` is
deliberate (a buffer against range-flicker), not a bug to relax.

Re-read `ISquadTask::Attack` end to end and `CCircuitUnit::Attack`'s non-melee
branches (`SquadTask.cpp:576-943`, `CircuitUnit.cpp:530-582`) looking for an
ORDER PATH that bypasses the ring position entirely, not another formula
error:
- For a static target, non-ground, non-melee (Hound/Rocketeer vs. a tower):
  `prefer` is unconditionally true (the pass-1 fix), so `CCircuitUnit::Attack`
  issues ONLY `CmdMoveTo(pos)` with `pos` = the ring standoff point computed in
  `SquadTask.cpp`. No `unit->Attack(enemy->GetUnit())`, no `CmdFightTo(enemy->
  GetPos())` reaches the engine for this exact case -- confirmed by re-reading
  the branch, not assumed.
- No AngelScript path issues a raw attack-move at a tower's own position:
  grepped `manager/military/**/*.as` for `Attack(`/`FightTo`/`MoveTo` --
  the only hits are `unblock.as` (stuck-unit deconfliction, unrelated) and
  `posture.as`/`hooks.as` (no direct order issuance). No "siege a defended
  position" task type exists at script level; `killingblow.as` only sets
  posture, never issues unit orders.
- `CMilitaryManager::DefaultMakeTask` (`MilitaryManager.cpp:2049-2126`) routes
  every unit with role `assault` (armfido/Hound, armrock/Rocketeer both are)
  to `IFighterTask::FightType::ATTACK` -> `CAttackTask` -- the SAME squad path
  already audited. `CScoutTask` is reachable only via `IsRoleScout()`, which
  neither unit has.
- The travel-phase path BEFORE `ENGAGE` triggers (`CAttackTask::Update`,
  `AttackTask.cpp:452-546`) already stops at `pathRange = highestRange - eps`
  from the target and is threat-weighted (`ATTACK_THREAT_MOD`, `threatCeiling`
  from squad power) -- consistent with "stop outside range," not a dive.

**Found one real, additional gap, but in the wrong task for this report.**
`IFighterTask::Attack` (`FighterTask.cpp:225-277`, the SOLO/scout standoff
path used only by `CScoutTask`) computed `range = cdef->GetMaxRange() *
rangeMod` with **no reference to the target's range at all** -- not even the
90-100% band pass 2 fixed in the squad path, but ANY degree of outranging.
Fixed to mirror the squad path's outrange floor (`FighterTask.cpp:267-276`,
reuses `OUTRANGED_SAFETY_MARGIN` from `SquadTask.h`). This is real and worth
keeping, but Hound/Rocketeer are role `assault`, not `scout`, so they never
go through this function -- **this fix does not explain the reported
symptom** and should not be presented as pass 3's answer to it.

**No third mechanism found in `CAttackTask`'s own path with the confidence of
passes 1-2.** Two honest possibilities left, neither confirmed:
1. apexearth's comment may describe the pre-pass-1/2 symptom from memory/
   general impression rather than a fresh observation against a build with
   both fixes deployed -- pass 2 was explicitly not yet deployed when he made
   the remark. Needs a genuinely fresh watch with both fixes live before
   concluding there IS a third bug.
2. If it recurs after that watch: the travel-phase pathfinding query
   (`AttackTask.cpp:536-540`) is threat-weighted, not threat-blocked below its
   ceiling -- on a map with a narrow approach (Altair_Crossing was the map in
   play), the shortest-cost route to the correct, far standoff point could
   legitimately pass transiently closer to a tower than the final position,
   which would look identical to "walked into range" on screen even though
   the unit does not linger there. Add a one-shot LOG of `curPos` distance
   to target the first frame `ENGAGE` triggers to distinguish "stood at the
   wrong distance" from "passed through on the way to the right one."

Built via docker (`FighterTask.cpp.obj` recompiled, linked clean). **Not
deployed, no match run** per instruction. Delete this entry, and the pass-2
entry above, only once a watch with both live shows Hounds/Rocketeers holding
outside tower range with no dive.

## PATCHED, NOT YET LIVE-CONFIRMED: fragile-unit standoff/angle scaling (2026-08-14)

apexearth, watching, after the standoff/LOS-floor/ring-safety fix already
landed the same night: "Hounds still walk much too close to enemies. They
aren't tough - they really need to be more careful with themselves...
certain lower hp units have to be way more careful than high hp units."
Confirmed no separate kiting/skirmisher code path exists that the earlier fix
missed -- everything funnels through `ISquadTask::Attack`
(`SquadTask.cpp`)/`IFighterTask::Attack`, the same place already touched --
but the standoff margin (`STANDOFF_RANGE_MOD`) and the ring-safety threat
threshold were both FLAT constants, identical for a glass-cannon Hound and a
tanky Mammoth. `GetRetreat()` is per-unit-def but hand-set in JSON, not
derived from HP.

Added a `fragility` ratio per row (`avgSquadHealth / rowDef->GetHealth()`,
squad-relative baseline, clamped `[1, FRAGILE_CAP]`) applied to both the
standoff distance and the ring-safety threshold in `ISquadTask::Attack`.
Compiled clean via the docker toolchain, `sync_cpp.py status` confirms
`cpp/`/`vendor` match. **Not deployed, no match run** (explicit instruction --
a watch game may have been running). Needs: deploy once the console is free,
then a self-play test with Armada (Hound actually in the roster) confirming
(a) `fragility` actually deviates from 1 in real mixed squads rather than
squads usually being HP-uniform by weapon-range grouping, and (b) K/D/static-
kills move the same direction as the earlier standoff fix did. See
`changes/2026-08-14.md` for the full mechanism and formula.

## PATCHED, NOT YET LIVE-CONFIRMED: Sharpshooter (armsnipe, anti-heavy "sniper") had a zeroed factory ratio through tier1 (2026-08-14)

apexearth, watching a 1v1 (Apex/Armada vs BARb/Cortex): "I don't see us
making snipers, just sprinters hounds and fatboys... Enemy has us countered
... we don't have the appropriate unit types to counter their mammoths
(snipers)." Confirmed via `tools/unitdef.py`: Sprinter=`armfast`,
Hound=`armfido`, Fatboy=`armfboy`, Mammoth=`corsumo` (Cortex, role `heavy`),
and the unit he means by "sniper" is `armsnipe` ("Sharpshooter"/"Sniper
Bot", role `anti_heavy_ass`) -- all from Armada's `armalab` (T2 bot lab).
`response.json`'s `anti_heavy_ass` entry already targets `heavy` at
importance 20 (the highest in the table), so the response side was not the
gap. Mechanism: `factory.json:67-68`'s `armalab` land/water ratio tables had
`armsnipe` at 0.00 for BOTH tier0 and tier1 (income < 30), while Sprinter/
Hound/Fatboy -- the three units he actually saw -- are all nonzero there.
Same shape as the `armpw`-raider zero already documented in CLAUDE.md. Patched:
raised `armsnipe` tier1 to 0.05 (land and water, matching `armfboy`'s own
tier1 share) and Legion's parity unit `legsrail` (`factory_leg.json:39`) tier1
to 0.10 (matching `legbart`'s tier1 share); tier0 left at 0.00 on both. Not
yet live-confirmed -- needs a fresh watched 1v1 where income sits 1-30 and the
enemy fields heavy-role units, with `allBuilt=` showing nonzero `armsnipe`/
`legsrail` metal, and `tools/composition.py` checked to confirm the raise
didn't just cannibalize Sprinter/Hound/Fatboy's own share 1:1.

## PATCHED, NOT YET LIVE-CONFIRMED: idle con next to an unclaimed home mex walked off instead (2026-08-14)

apexearth, watching a 1v1: a con stood idle next to an unclaimed, undefended
mex, then walked away to something else instead of claiming it. Mechanism:
`FindOpenMexSpot` (`EconomyManager.cpp:1000`) -- the only mex search a script
can run -- deliberately excludes ally-zone spots, so `brain.as`'s `MexWant`
never proposes a home mex and cannot win it inside `Brain::Decide`'s ranking.
`DefaultMakeTask`'s own native mex-task creation still covers home spots, but
only on its own scan cadence, not synchronously with the builder's next
election, and in that gap an optional want (gantry, nano, ...) can fire first
since it does not depend on `FindOpenMexSpot`. Patched (`Builder::MexOffer`,
`manager/builder/rules_offer.as`, called from `maketask.as:120`) to take the
engine's own mex offer ahead of every optional want once it arrives, which
narrows the window but does not close it -- there is still no script-side
query for an ally-zone open mex spot, so the tick before the engine's scan
reaches the spot remains exposed. Closing that fully needs a new/adjusted C++
binding. Not yet re-watched live -- needs a fresh 1v1 to confirm the con no
longer walks off an adjacent unclaimed home mex.

UPDATE 2026-08-14 (later, live report from Altair_Crossing_V4.1): a
DIFFERENT symptom that looks related but is not closed by `MexOffer` --
apexearth built a tower right next to two mexes and neither got claimed for
several minutes (too long to be the brief idle-then-walk-off window above).
No infolog for that game was available to confirm from `con-veto`/`mex
guard` lines (only stale/harness infologs on disk), so this is a code-level
finding, not a live-confirmed one. Two candidate mechanisms, not
distinguished without the actual log:
1. `Builder::ThreatFor` (`manager/builder/sitesafety.as:173`) and
   `MexHeat` (`sitesafety.as:134`) never give any credit for our OWN static
   defence. `ThreatFor` vetoes on raw enemy proximity (`GetEnemyCostAt`,
   LOS-gated, 600-elmo radius) or the real threat map; `MexHeat` only
   relaxes the GEOMETRIC PastFront fallback, not a real reading. So a mex
   next to a tower we just built precisely to secure that ground reads
   exactly as hot as one with no defence at all, for as long as any enemy
   unit loiters in LOS nearby -- which is plausible for many minutes at a
   contested border tile, and is arguably the actual reason he put a tower
   there. No existing helper reads "is there completed friendly defence
   covering this point" to fold into the veto; adding one safely needs a
   real match's `con-veto` log to confirm this is what actually fired
   before writing it blind.
2. Compounding possibility, not exclusive: if these two mex spots are
   ally-zone (home) ground, `FindOpenMexSpot` excludes them from every
   script query (see above), so they can ONLY ever be claimed on
   `DefaultMakeTask`'s own native scan cadence -- if that scan simply never
   re-offered these two particular spots in the observed window, no script
   change closes it; only a C++ scan-cadence/binding fix would.
Left unpatched: no log evidence to prefer one mechanism over the other, and
guessing between an eco-facing threat-model change and a C++ binding change
risks the wrong fix. Next watched game should grep for
`apex: con-veto`/`apex: mex guard` near the two mex spots' timestamps to
settle it.

UPDATE 2026-08-14 (later still, after both fixes above were live): "we are
still walking past mexes without building with our cons" -- a THIRD, distinct
mechanism: a MOVING con (already assigned a task), not an idle one.
`Builder::HoldWorkInProgress` (`manager/builder/rules_hold.as:94`) returns the
currently held task unconditionally for any task with a nonempty
`SiteBuildName`, and it runs BEFORE `aiBuilderMgr.DefaultMakeTask` in
`MakeTaskInner` (`maketask.as:107` vs `:129`) -- so a builder walking to a
factory/nano/energy site never even reaches `DefaultMakeTask`/`MexOffer`
during its ~1/second re-election (`IBuilderTask::Reevaluate`,
`BuilderTask.cpp:534`, confirmed still firing on a walking builder -- the
"moving units don't reconsider" assumption was wrong; what's actually true is
narrower: the SCRIPT'S OWN hold, added to stop a flip-flop, blocks the offer
regardless). Patched: `Builder::PassingMex` (`rules_hold.as:22`), called from
`maketask.as:113` immediately ahead of `HoldWorkInProgress`, using the same
`FindOpenMexSpot`/`GetMexSpotPos`/`EnqueueMexAt` path as `MexOffer`, gated on
a geometric "on the way" test (extra detour distance <= 35% of distance still
to travel), not a value threshold. Inherits `FindOpenMexSpot`'s ally-zone
exclusion, so this only closes the FRONTIER half of the walking-past gap; a
moving con passing a HOME mex still depends on `MexOffer`'s narrower
mechanism. Not deployed, no match run (apexearth was watching live at the
time) -- needs a fresh watched game or a tournament composition check
(`python tools/composition.py`, mex upgrades vs a control) to confirm.

## PATCHED, NOT YET LIVE-CONFIRMED: first high-quality defence placed off in a map corner (2026-08-14)

apexearth, watching a 1v1: the AI's first significant static defence (the
big gun / T3 dome / line jammer -- everything `BorderPos` places, see
`manager/military/territory.as:92`) appeared off in a corner of the map
rather than at the base. Mechanism: `BorderPos` ranked owned metal clusters
purely by `(cover + 1) * distanceToEnemy`, with no term for distance from
home and no check that the site is actually on contested ground -- so a lone
early forward expansion mex, merely happening to sit closer to
`GetEnemyPos()` than the base does, beat the base outright while having zero
cover. Patched to gate eligibility on `OnBorder` (the same contested-line
test `RebuildFront`'s ray model already computes) once a front exists, and to
fall back explicitly to `Builder::gHomePos` for rank 0 when it does not. Not
yet re-watched live -- needs a fresh 1v1 to confirm the big gun/dome/jammer
now lands at or near the base instead of a remote expansion.

## PATCHED, NOT YET LIVE-CONFIRMED: commander chains nearby mexes forever, factory never requested (2026-08-14)

**Update, same evening: the fix above was never exercised in the watched
match that "confirmed" it was still broken.** apexearth re-watched after the
patch and reported the exact same symptom (four mexes, full metal bank, no
factory). Diagnosis of THAT match's own infolog: `world.as`'s `ApexActive()`
latches false whenever `ai.GetTeamIds().length() <= 1` -- true for every
solo/no-ally match, which a plain 1v1 always is. `Builder::MakeTaskInner`
checks that gate first (`maketask.as:45-46`) and returns bare
`aiBuilderMgr.DefaultMakeTask(unit)` when it's false -- 100% stock
`CBuilderManager` logic, skipping `CommanderTask` (and every other apex rule)
entirely. The infolog had zero `apex:` lines over 4628 frames, confirming
nothing custom ran at all; the commander behavior watched was stock BARb's,
not this AI's, both before and after the patch. Fixed the HARNESS default,
not the AI: `tools/run_match.py` now sets `apex_solo_stock=0` automatically
whenever `per_side==1` (a true no-ally match), so `--watch` runs actually
exercise this AI's logic unless the caller explicitly asks for the
solo-stock fallback. The `CommanderTask` reordering fix itself is still
unconfirmed either way -- it needs a fresh watch now that the harness will
actually route through it.

**Update, same evening: apexearth had the gate removed outright rather than
patched around.** The 2026-08-10 rationale for `ApexActive()` was judged stale
against everything fixed since (crash fixes, commander opening fixes, squad
cohesion/positioning fixes). `ApexActive()` now unconditionally returns
`true`, the `apex_solo_stock` tunable no longer exists anywhere, and the
`run_match.py` harness default above is gone -- apex runs its own logic in
every game, allies or not. The `CommanderTask` fix now needs a fresh watch
under this, not the harness workaround.

apexearth, watching a 1v1 (Comet Catcher): full metal bank, commander just
keeps walking to the next mex, no factory, no solars, well past opening
timing. `CommanderTask`'s economy-first branch (`rules_commander.as:211-273`)
is the AI's ONLY path to ever requesting the first factory, and it ran the mex
lookup BEFORE the factory-rebuild request, unconditionally, every
`AiMakeTask` re-election. `2aa2cf9`'s `OpeningMexReach()` (700 elmo) only
bounds a single jump; `FindOpenMexSpot` re-searches from the commander's
CURRENT (moving) position every tick, so the next-nearest spot is again inside
700 forever -- confirmed structurally AND against a different infolog from the
same evening (`matches/20260814-180430-.../infolog.txt:2149-2168`,
frames 306-537): `commander economy-first, no factory yet -- mex before
rebuild` repeating multiple times per frame, `commander rebuilding a factory`
appearing between them but never sticking.

Applied fix (`rules_commander.as`, same block): (1) if the commander is
already holding a FACTORY-type task, return it immediately, before any mex
lookup -- this is what actually breaks the chain, since without it a task
just assigned this tick is abandoned on the very next re-election once the
commander has moved and a fresh mex spot opens. (2) reordered so the factory
rebuild request is attempted BEFORE the mex fallback, so a first request goes
out as soon as economy is judged sufficient, and mex is only offered when the
factory request is genuinely unavailable (def missing, or one already in
flight and not yet visible on `unit.task`). No hard cap added, no flag beyond
"do we currently hold a factory task" (real, reentrant, re-derived every
call -- survives a post-wipe rebuild the same as the opening).

NOT YET LIVE-CONFIRMED: verified against a same-day infolog showing the same
mechanism (not the exact match apexearth watched, which produced zero
`apex:` lines -- likely a different run or truncated log). Still need: a
fresh `--watch` run showing `commander economy-first` firing at most once
before `commander rebuilding a factory` sticks, and `mex2`/`mex4`/`mex8` +
`techStart` from `[BARAI_STATS]` compared before/after to confirm the factory
now actually gets built instead of the mex chain continuing indefinitely.
Also worth re-checking `OpeningNeedsEconomy()`'s escape valve
(`opening.as:45-78`, releases once no energy task is in flight rather than
once income clears the target) if factory timing is still late after this
fix lands.

## ABANDONED: Linux/ASan harness for the buildTasks crash (2026-08-14) -- back to Windows addr2line

Built a native Linux + AddressSanitizer build (`vendor/engine/build-amd64-linux/`,
docker's `recoil-build-amd64-linux` image) specifically to catch the
still-unresolved `MakeBuilderTask`/`buildTasks` dangling-pointer crash (see the
"IRefCounter" entry below), since MinGW's cross-toolchain has no `-fsanitize=
address`. It never got there: two different scenario configs each hit a
DIFFERENT crash during AI **init**, before the game even starts --

- 8v8 +70 handicap: null `CEnemyManager*` in `CEnemyManager_GetEnemyPos`
  (`InitScript.cpp:383`), at literally frame 0. Tried gating the one unguarded
  `aiEnemyMgr.GetEnemyPos()` call site (`baseplan/axis.as`) behind
  `Builder::gHomeSet` to match every other caller -- no effect; `gHomeSet` is
  already true by frame 0 (set on the commander's own `AiUnitFinished`, and the
  commander is a starting unit), so nothing was actually gated.
- 2v2 follow-up: null `CCircuitDef*` in `CMetalManager::ClusterizeMetal`
  during `CAllyTeam::Init`.

Neither reproduces on the shipped Windows build. Read as init-order fragility
in the hand-assembled Linux build itself (a partial `cmake --install` was
worked around by manually copying `.so`s into place, not a clean full
build+install), not a real player-facing bug. apexearth's call: not worth
the effort relative to the cost (~40 min per docker run to find out). The
three sites already fixed this session were all found the other way -- a real
Windows crash symbolized via `addr2line` against the `ImageBase`-adjusted
offset -- so that pipeline is what continues to be used as further crashes
surface. `vendor/engine/build-amd64-linux/` and the `asan_*` logs/writedirs
are left in place in case it's worth revisiting later; nothing further
planned there.

## NEW: heap corruption at shutdown in CCircuitAI::DestroyGameAttribute (2026-08-14, found via Application Verifier)

Not the crash apexearth is watching for -- caught incidentally while hunting
the one below. Windows Application Verifier's Heaps check, enabled for
`spring-headless.exe` (no rebuild needed, just `appverif -enable Heaps -for
spring-headless.exe`, reversible via `-disable`), flagged a heap violation at
the exact moment a match ends and `CCircuitAI::Release()` tears down --
resolved via `addr2line` against the unstripped build:

    circuit::CCircuitAI::DestroyGameAttribute()          CircuitAI.cpp:2591
    (deallocating a std::unordered_set<CCircuitAI*> node, which chains into
    releasing a shared_ptr whose deleter frees a terrain::SAreaSector via an
    std::_Rb_tree node deallocation)

Only observed at game-end teardown so far, in one repro. Not yet determined
whether this is harmless (process exits right after anyway) or corrupts
something that matters for multi-restart scenarios (a hosted lobby playing
several games without restarting the process). Needs its own pass: read
`DestroyGameAttribute` and whatever owns the `SAreaSector`/area-sector map to
find the double-free/use-after-free, independent of the mid-game crash below.

## PARTIALLY FIXED: the recurring "IRefCounter::Release() -> delete this" crash (2026-08-14)

**Overnight tally, 2026-08-15 (running):** after counted `buildTasks`
membership, the AssignTask reference-transfer, the ring-clamp, and finally
a counted `unit->task` pointer (`CCircuitUnit::SetTask` AddRef/Release,
crash #7 at 63 game-minutes in `UnitMoveFailed` was the finder), the soak
rotation has run Glitters 97m + Glitters 47m + Comet 41m + Ascendancy 41m
+ Adamantium 57m + Glitters 37m crash-free, with the two crashes found en
route (ring-clamp at ~35m, unit->task at 63m) each fixed and the loop
continued. The class dies one uncounted pointer at a time.

**Morning tally (06:30):** ~20 long 8v8 soaks over the night across
Glitters/Comet/Ascendancy/Adamantium. FIVE crash mechanisms found and
fixed in sequence, each surfacing only after the previous fix let games
run deeper: (1) counted buildTasks membership (freed candidate in the
MakeCommDangerTask iteration, ~35m); (2) AssignTask reference-transfer
(stale unit->GetTask() re-read in IdleTask); (3) ring-angle threat
sampling clamped on-map (watched game, ~30m); (4) counted unit->task
pointer (UnitMoveFailed on a freed task, 63m); (5) aux target maps
(repairUnits et al) erased unconditionally on dequeue + repair tasks
resolving their target LIVE by id instead of a cached pointer that a
one-slot-map eviction left dangling (85m and 48m finders). After fix (5):
soak #29 Comet 47m crash-free; #30 running at report time. Every fix is
committed individually with its mechanism.

**8v8 win-rate is the morning's gameplay item:** overnight record roughly
4W/16L by gameover; every loss is a full 8-commander wipe in the 25-45m
window while the economy leads -- commander survival in the late-game
grind, not economy, decides these. The 1v1 benchmark (12-0) does not
transfer to 8v8.

**2026-08-15, SIXTH crash, and it exposed why the AddRef brackets are not
enough.** apexearth's watched 8v8 crashed at frame 47331; addr2line (docker
image toolchain, `x86_64-w64-mingw32-addr2line`, ImageBase+offset) resolved
it to `CIdleTask::Update` at the `task->Start(ass)` INSIDE the existing
AddRef bracket, with a null-vtable call (exception address 0x0). The
bracket cannot help when `ass->GetTask()` returns an ALREADY-dangling
pointer: `manager->AssignTask(ass)` one line earlier runs the whole script
pipeline (AiMakeTask, then CBuilderManager's TaskAssigned hook), either of
which can abort/complete tasks, and `CCircuitUnit::SetTask` is a bare
assignment -- AddRef on freed memory protects nothing. **Fix, landed and
rebuilt:** `ITaskModule::AssignTask(CCircuitUnit*)` now RETURNS the task it
assigned with one reference transferred to the caller (TaskModule.h/.cpp,
BuilderManager.h/.cpp override), and `CIdleTask::Update` uses that return
value -- never re-reading the unit's task pointer -- guarded by `IsDead()`
before Start and Released after. 12 tournament games + a 25-min smoke on
the new DLL: zero crashes. Same caveat as every previous entry here: only a
long watched game closes it.

**apexearth, watching several more windowed games (+70 handicap):** "we are
still crashing," repeated after each of the two fixes below. This is the same
bug documented (and never fully fixed) in `changes/2026-08-09.md`, and it has
now been confirmed at FIVE different call sites across the session
(`CIdleTask::Update`, `MakeBuilderTask`, `MakeCommDangerTask`,
`CBuilderManager::UnitIdle`, `ITaskModule::AssignTask`) — the varying surface
location is why it looked like several different bugs and evaded manual
auditing for two sessions, and why fixing one confirmed site (below) was not
the same as fixing the disease.

**Status: two confirmed sites fixed (`DequeueTask`, `AssignTask`); a genuine
fifth crash after the first fix proves the pattern has more instances than
were found by reading alone.** Do not treat "fixed" as final until a long
watched game actually goes without one — this entry has been wrong about that
twice already tonight.

Windows Application Verifier's Heaps check (`appverif -enable Heaps -for
spring-headless.exe`, no rebuild needed, reversible via `-disable`) didn't
catch it directly — it's not raw OS heap corruption — but running under it
still eventually produced a crash whose stack pointed straight at the actual
bug: `ITaskModule::DequeueTask` (`TaskModule.cpp:78-83`):

    void ITaskModule::DequeueTask(IUnitTask* task, bool done)
    {
        task->Dead();
        TaskRemoved(task, done);   // <-- fires AiTaskRemoved (our script)
        task->Stop(done);          // <-- crash: use-after-free
    }

`IUnitTask` derives `IRefCounter`, registered `asOBJ_REF` with intrusive
refcounting (`RefCounter.cpp`: `Release()` calls `delete this` at refcount 0).
`TaskRemoved` runs the AngelScript `AiTaskRemoved` callback with a bare native
pointer and no extra reference held. If that callback happens to drop the
*last* AngelScript-side reference to the task (e.g. the last array element
removed from `Requests::gLive`, or any other tracked handle going out of
scope), AngelScript's own `Release()` legitimately deletes the object right
there — and `task->Stop(done)` one line later is now dereferencing freed
memory, from whichever native call chain happened to trigger it that time
(hence four different-looking crash sites for the same root cause).

**Fix**: bracket the callback with the object's own `AddRef()`/`Release()` --
the same guarantee AngelScript already gives every other holder of a handle:

    task->AddRef();
    task->Dead();
    TaskRemoved(task, done);
    task->Stop(done);
    task->Release();

Rebuilt via docker, deployed, verified clean on a fresh test (no AS compile
errors, opening timing unregressed).

**It crashed again anyway, ~26 minutes into the very next watched game**
(`matches/20260814-174501-*`), same `IRefCounter::Release()` signature, a
DIFFERENT call chain: `CBuilderManager::AssignTask(unit)` (the single-arg,
"auto-assign" overload) -> `ITaskModule::AssignTask(CCircuitUnit*)`
(`TaskModule.cpp:70-76`) -> `MakeTask(unit)` (runs `AiMakeTask`, our whole
script pipeline) -> `task->AssignTo(unit)`. Identical shape to the first
fix -- a raw pointer used again after a call into script that can drop
references -- just a different function that never went through
`DequeueTask` at all. Same fix pattern applied to both `AssignTask`
overloads in `TaskModule.cpp` (the two-arg version's `task->Start(unit)`
also runs script by the same reasoning, guarded too even though it hasn't
crashed yet -- same shape, same fix, no reason to wait for a sixth crash to
apply it):

    IUnitTask* task = MakeTask(unit);
    if (task != nullptr) {
        task->AddRef();
        task->AssignTo(unit);
        task->Release();
    }

Rebuilt, redeployed, clean compile.

**Crashed a THIRD time**, a 40-minute background repro this time
(`matches/20260814-175707-*`, 29 minutes in), same signature, back at
`CIdleTask::Update` -- but not the same line as the first `IdleTask.cpp` fix.
This one is `task->Start(ass)` at the tail of the loop (`IdleTask.cpp:79`
before this fix): `ass->GetTask()` fetches the unit's current task via a bare
native pointer -- `CCircuitUnit::SetTask` does a plain `this->task = task;`
with no `AddRef`, confirming native ownership of a unit's current task was
never reference-counted from the engine's own side, it relies entirely on
`buildTasks`/`updateTasks` membership and explicit `DequeueTask`/`AbortTask`
calls -- and `Start()` on it can run script exactly like `AssignTo`/
`TaskRemoved` do. My earlier fix to this same function only null-checked the
result; it never guarded against USE-AFTER-FREE, only against the task
never having existed. Same bracket applied:

    IUnitTask* task = ass->GetTask();
    if (task != nullptr) {
        task->AddRef();
        task->Start(ass);
        task->Release();
    }

Rebuilt, redeployed, clean compile, clean 5-minute sanity test. A fourth
40-minute background repro is running. **Given the pattern (three real sites
found by three separate crashes, all the exact same shape, none found by
reading alone until a crash pointed at them) treat this whole class as
UNVERIFIED until a genuinely long watched game goes without one** -- do not
report this as fixed again without that.

**Structurally similar but NOT yet fixed**: `TaskAdded(task); return task;`
in `CBuilderManager::Enqueue` (both overloads), `CFactoryManager::Enqueue`,
`CMilitaryManager::Enqueue` (`BuilderManager.cpp:741,766,774`,
`FactoryManager.cpp:820,849`, `MilitaryManager.cpp:742,778`) has the same
"script call, then native code still uses the raw pointer" shape, but the
"use" here is just returning the pointer to an arbitrary caller further up
the stack -- an AddRef-then-Release bracket INSIDE `Enqueue` would not
actually protect the caller (releasing before `return` just moves the
deletion to the instant before the caller gets the pointer). Protecting this
shape properly needs the guard to outlive the function, which is a bigger
change than the two fixed so far. Not confirmed as a real crash site, but
the same audit that found the first two sites should check this one before
declaring the disease cured.

Also found and documented, not yet fixed: `IBuilderTask::Reevaluate`
(`BuilderTask.cpp:472-480`, unmodified upstream) self-aborts any task costing
over 1000 metal with no nanoframe yet if average income drops under 60% of a
saved baseline. Plausible explanation for the separate "fusion reactors take
many attempts to complete" finding (armfus is 4300 metal; BAR income swings
40%+ routinely) — not yet confirmed as THE mechanism, a real lead for next
time.

**2026-08-15 (midday): the disease is ONE refcount imbalance on a task-module
SINGLETON, and it corrupts the whole process.** Symbolized with the release
dbgsym archive (`recoil_2026.07.04_amd64-windows-dbgsym.tar.zst`,
`addr2line -j .text` with section-relative offsets): the watched-game
crashes that looked like drawing/ping problems are Lua-heap corruption —
`sweeplist` (lgc.cpp:412) in the GC, and `luaV_equalval` under
`CBuilder::SetRepairTarget` — Lua is the victim. Headless reproduces at
~11-14 game-min on Glitters 8v8 +50 handicap in most games (post-09:59
builds, the first where the counted `unit->task` bracket actually linked:
crash rate jumped ~15% → ~90%, i.e. the bracket did not add the bug, it
converts a pre-existing imbalance into visible frees). Diagnostics built in
sequence, each landing one step closer:
(a) poison + underflow trap in `IRefCounter` — corruption still surfaced in
Lua first;
(b) guard-page allocator (`IRefCounter::operator new/delete` on VirtualAlloc,
delete decommits but keeps the address reserved) — faulted at
`CIdleTask::Update` reading `this->updateSlice`: **a manager's own idleTask
singleton was deleted mid-Update**;
(c) `SetPermanent()` on nil/idle/player singletons with a trap on the
release-to-zero — fired at frame 21290 under
`UnitFinished → AbortTask(reclaim) → IUnitTask::Stop → idle AssignTo →
CCircuitUnit::SetTask releasing a singleton with NO other holder` — an
over-release against zero holders, but of WHICH singleton and whose manager
the stack cannot say;
(d) REFTRAP context log in `SetTask` showed the drained singleton is always
an IDLE task with zero holders left — the born ref was stolen earlier;
(e) the 1M-reference CUSHION on singletons finally trapped the thief at the
call itself: `CCircuitAI::UpdateActions → DeleteTeamUnit → ~CCircuitUnit →
task->Release()` — **a unit sat in `actionUnits` TWICE, was reaped twice,
and `delete`d twice.** The second dtor ran on freed memory: its stale `task`
field still read the idleTask pointer, so idle was released once per
double-reap (the drain), and the double `delete` itself is the malloc-heap
corruption that killed Lua GC sweeps, unit LuaScript calls, and both AI
DLLs at random.

**FIX (2026-08-15, deployed, verification loop running):** three layers in
the DLL — (1) `AddActionUnit` dedupes (root cause: duplicate listing);
(2) `DeleteTeamUnit` defers the actual `delete` to `Release()` via a
`deadUnits` set (zombie units keep valid memory, so ANY remaining stale
task-set membership — CSRepairTask iterating a dead nano was observed live —
becomes inert instead of use-after-free; the set also makes a double reap
harmless); (3) `CIdleTask::Update` drains dead units instead of handing
them to MakeTask. Also fixed en route: the script binding
`AssignTask(CCircuitUnit@, IUnitTask@)` leaked one task reference per call
(plain `@` param = VM passes +1 the callee must release; now `@+`).
Diagnostics kept in the build until the loop proves it clean: refcount
poison/underflow traps, guard-page allocator for refcounted objects,
singleton cushion trap.

**2026-08-15 (afternoon): SECOND writer found and fixed — `unit->Clear()`
left `dgunAct`/`travelAct` dangling.** After the double-free fix, Apex-vs-
stock headless went clean but the Apex mirror still crashed 10/10 (so the
residual was ours, load-scaled; victims were always small malloc blocks —
Lua GC objects, the GetTunable string map). Guard-paging IAction caught it:
`IUnitTask::RemoveAssignee`/`Stop` and `CNilTask::RemoveAssignee` called the
inherited `CActionList::Clear()`, which deletes the unit's actions but
cannot null `CCircuitUnit`'s `dgunAct`/`travelAct` caches. Every later read
through those was the null-vtable crash family; `StateWait()` through them
wrote a byte into freed small blocks — the heap corruption. Upstream-latent;
our Reevaluate-heavy reassignment flow widened the exposure window
enormously. Fix (`1684a98`): call sites use `ClearAct()` and `CCircuitUnit`
shadows `Clear()` so the unsafe base version is unreachable. 12-game mirror
verification running; the mirror crashed 10/10 before the fix, so a clean
sweep is the confirmation gate. Diagnostics (guard pages on tasks / units /
enemy infos / actions, refcount traps, cushion, PushUpdate dupe trap) stay
in until then — strip or cheapen after.

## NEW: late-game air-economy directives (2026-08-15, apexearth watching)

Two standing asks, not yet implemented:
1. **Advanced construction aircraft in the late game** — once the economy is
   large, eco building should shift to air constructors for mobility ("rely on
   more advanced construction aircraft to efficiently move around and build
   eco"). Air domain: factory selection + builder role weighting by era.
2. **Thick fighter screen** — his number: "in an 8v8 that means ~100 or more
   fighters ALIVE and flying over your base." Scale with economy/team size,
   not a flat cap; this is an air-lead/AA-baseline sizing question.

Same session, already landed: obsolete-ask TTL (rezbots deadlocked idle on a
never-expiring reclaim ledger — his twice-repeated report), bank-inclusive
reactor concurrency ("0 delay" between fusions when metal-full), and
build-side obsolescence (never build a def obsolete.as would reclaim).

## NEW: not enough anti-swarm shot density in defences (2026-08-15, Greenhaven loss)

apexearth: "we lacked land defenses to block enemy mass grunt assaults. If we
don't have enough shots (fast firing stuff to kill bulk low hp units) then we
get overwhelmed." The porcupine/defence chooser should weight FAST-FIRING
towers (LLT/beamer class) up when the enemy composition is cheap-swarm (low
average unit cost / high armyCheap), instead of the current threat-value
draw that favours big single-shot towers equally against everything. Not yet
implemented — needs the enemy-composition signal wired into PorcToBuild.

## NEW: anti-air coverage is lacking (2026-08-13, watching)

**apexearth, watching the windowed 8v8:** "We lack anti air coverage."

Not yet investigated. In `matches/20260813-222958-*`, `corflak` (Cortex AA)
appears only 9 times across the whole log for an 8-player team, and no
`armflak`/`armjuno`/`corjuno` at all — but this is a raw grep, not a proper
count of built-vs-requested-vs-lost, and doesn't separate "AA was never
requested" from "AA was requested and refused" from "AA died and was never
replaced". Needs a proper pass — likely air-warfare's factory ratio /
`CheapAA`/`HeavyAA` selection, or static-defence's `AAOrder`
(`builder/statics.as`) gate, or both.

## NEW: too much metal in defence, not enough responsive army (2026-08-13, watching)

**apexearth, watching a second windowed 8v8:** "We still make way too many
defenses. I counted over 100 sentry turrets... once enemies break through one
part of the frontline that army goes around our entire frontline to hit us in
the back and we spend so much on the frontline that we lack army to defend
where the enemy penetrated. So tone back defense more, add more military -
ensure our military is ***responsive*** to needs for aid."

This is an explicit rebalancing directive from apexearth, not a bug report —
he is stating the policy himself (tone back defence, grow army, make the army
respond to where the enemy actually is), which is different from this repo
inventing a threshold on its own. Two distinct claims, two different
mechanisms:

1. **Static defence is overbuilt in aggregate — FIX LANDED 2026-08-13, NOT YET
   MEASURED.** Confirmed: the front-line budget was a tower COUNT scaling
   linearly with income (~1.2 towers per team metal/s), so a Sentry and a
   Pulsar each spent one unit of it — permitting 100+ towers before the count
   ever bound at hosted-game income. Also confirmed connected to the "spread
   thin" report below: `CrowdAllows` was being asked with `def = null` on the
   path that places most towers, so its tier-upgrade exemption could never
   fire, and a crowded spot was refused outright rather than allowed as an
   upgrade — landing as a fresh cheap Sentry on new ground instead. Both fixed
   in one pass: the budget is now a team metal-share test
   (`teamFrontMetal/teamTotalSpend` vs `TargetShare(DEFENCE) * pressure *
   front-share`), and the crowd check now receives a real candidate def via a
   new `Military::LadderDef()`. `SPEND_DEFENCE` recalibrated to 10% of spend
   at every income step, apexearth's explicit number ("Let's try defence at
   10%"). See CHANGES.md. Smoke-tested clean; needs a tournament + a watched
   game before this half can be closed out.
2. **Army does not redeploy to a breakout — FIX LANDED 2026-08-13/14, NOT YET
   MEASURED.** Confirmed: every DEFEND pool was pulled toward the SAME single
   anchor point (`GetGuardAnchor`) each pass — either one cost-weighted
   centroid of all recent losses (`GetAttackHotspot`) or one sticky front
   point, never a per-sector position. Two simultaneous breaches averaged to a
   point between them that was neither. A previous responsiveness attempt
   (freeze new units near-base while contested) was tried, measured, and
   reverted (`hooks.as`) — its own comment names the missing capability: "a
   per-task position, which this layer does not have."
   **Falsifier checked before implementing, per this repo's own discipline**:
   a temporary AngelScript sampler over `gSquads` found 2+ live DEFEND pools
   in 135 of 301 samples (up to 7), thousands of elmos apart — per-task
   anchoring had something real to steer.
   Implemented (C++, layer 3): the hotspot is now a small fixed-size set of
   loss spots instead of one centroid; `GetGuardAnchor` gained a per-task
   overload scored by remaining unanswered threat at each spot divided by
   distance, subtracting already-assigned power as pools are assigned so
   later pools naturally pick the next-worst breach; `CheckMergeTask` no
   longer merges DEFEND pools anchored to different spots back into one blob.
   See CHANGES.md. Smoke-tested clean (no compile errors, no crash). **Not yet
   measured** — needs a watched game with a real two-front breach to confirm
   the army actually splits toward both sides.
   **Further evidence, same watching session, after the defence-share fix
   deployed:** "we're losing our main base and our own army is walking around
   the back to a neighbor's base instead of protecting ourselves. I do see
   that defenses are less strong." Consistent with the diagnosis above — with
   defence now correctly weaker (working as intended), the missing
   redeployment mechanism was more exposed, not less relevant. This is the
   report that motivated implementing the fix rather than leaving it designed.

## NEW: the defensive front line is spread thin instead of massed on a line (2026-08-13, watching)

**apexearth, watching the same game:** "Our defensive frontline is too thick,
towers spread out instead of on a good straighter line that allows many more
of them to fire at the same time."

Not yet investigated. Candidate mechanism: `Brain::TowerReach`/`FrontCurve`/
`FrontLineSpots` (frontline.as, defenceline.as) place towers along a computed
curve rather than a straight line, or space them by the per-tower crowd check
landed today (`CrowdAllows`, `defenceline.as`) rather than by a firing-arc
overlap rule. Also worth checking against today's tower-crowding cap
(`apex_fence_crowd`) — that change caps how many towers cluster in ONE spot,
which is a different axis from "are they arranged so they mass fire," and
could in principle be making this specific complaint worse rather than better
if towers are now being pushed to spread out to avoid the crowd penalty
instead of lining up.

## 0b. REACTORS ARE STARTED IN PARALLEL AND NEVER FINISH

**THREE FIXES LANDED 2026-08-13. THE THIRD IS VERIFIED (SAME SEED, BEFORE/
AFTER), THE FIRST TWO ARE SMOKE-TESTED ONLY, NEITHER MEASURED BY A WATCHED
GAME OR TOURNAMENT.** The original four mechanisms were fixed in
`joinbuild.as`/`fusion.as`. Two further gaps were found the same night,
watching, and fixed within hours of each report: (1) `JoinTaskFor` now checks
duplicate-ness against the SITE being built (`spot`), not the calling
builder's own position; (2) a join refused only for hitting the builder cap no
longer falls through to an identical spot (`SpotCollides`), and the collision
registry (`JoinRegister`) no longer exempts cheap buildings like solar from
being checked at all. See CHANGES.md for all three. The 701/40 numbers below
are the *pre-any-fix* baseline — still needs a fresh tournament, and ideally a
fourth watched game to confirm apexearth stops seeing the burst live (the
verification below is scripted-log, not a watched game).

**Reported four times, in order:** "we are super inefficient when we make
multiple eco buildings at the same time, like 2 fusions, 2 or 3 afus" (after a
lost 6v6, before any fix) → "At 26:55... we are making 5 advanced solars and 2
fusions at the same time. You just made a fix which was supposed to fix
exactly this kind of issue" (watching, after fix 1's predecessor landed, before
fix 1 itself) → "I still see multiple advanced solars being built (~20m in)...
a single team going off making ~4 of them all at the same time" (watching, same
build as the previous report — fix 1 not yet deployed) → "You just spent 33
minutes working and the advanced solars still aren't fixed... what?" (watching,
AFTER fix 1 was deployed — this report is what surfaced fixes 2 and the
registry gap; fix 1 alone was real but insufficient).

**Verification for fix 2+registry** (not yet done for fix 1 alone): same
map/seed/player-count (8v8 Comet Catcher, seed 7) run twice via
`tools/run_match.py`, before and after. A scripted scan of every energy-enqueue
log line for same-team/same-def/same-position events within 5 real seconds of
each other found **18 bursts before, 0 after**, across 343 energy-enqueue
lines in the post-fix run. Solar building still proceeds normally post-fix (59
enqueues, teams reaching 10-12 standing) — the fix stops literal duplicates
without blocking legitimate nearby placement.

Traced in `matches/20260813-222958-*`: team t3 alone enqueued **5 separate
armadvsol tasks in an 8-game-second window** (frames 40956-41196), landing at
`1680,2880` / `544,3504` / `1744,2880` / `1616,2880` / `1792,3024` — four of
the five within ~200 elmos of each other. The join system was not dead: the
same log window shows successful joins elsewhere (`con-join(direct)
armrectr -> armadvsol joined=1`). It just didn't see this case.

**Mechanism, now fixed**: `JoinTaskFor(want, unit)` measured distance from
`unit.GetPos(ai.frame)` — the CALLING BUILDER's current position — never from
the spot `HomeEnergy`/`EcoFusion` was about to place the building at. Five idle
constructors scattered around the base each asked "is there a joinable task
near ME" from five different locations, each got "no", and each then
independently computed a `spot` from the SAME placement logic (pack/band
against the same base layout) — which is exactly why the five spots ended up
clustered together even though the five builders that decided to place them
were not. `JoinTaskFor` now takes the caller's `spot` as a required parameter
and checks against that instead.

**apexearth, 2026-08-13, after losing a real multiplayer 6v6 to HUMANS:** "we are
super inefficient when we make multiple eco buildings at the same time, like 2
fusions, 2 or 3 afus... etc."

Measured over the 16 `Handicap=50` runs in `matches/20260813-*`, 64 apex
player-games: **701 reactor start requests, 40 reactors finished.** 267 requests
(38%) started a reactor while at least one was already an unfinished nanoframe.
**93 of 109 observed reactor nanoframes never completed in 50 minutes.** Median
start→finish 4.6 game-minutes, p90 7.6.

**The engine already does this right; both our AngelScript paths bypass it.**
`CEconomyManager::UpdateEnergyTasks` bounds concurrent energy tasks at
`buildPower/costM*4+1` — which is 1 for a fusion at any realistic income — and it
*does* count our script-enqueued tasks. We route around it.

- **`JoinBuilderCap` (`builder/joinbuild.as:54`) is INVERTED.** `150*income/cost`
  grants *fewer* assistants the more expensive the building. Reactors got cap=2 in
  333 of 485 sampled misses; an armafus with 2 armacks is **14.5 game-minutes**.
  A refused builder walks off and starts another reactor.
- `JoinTaskFor` refuses a queued-but-unassigned task (`joinbuild.as:153`, 179
  sampled misses), so the caller enqueues a duplicate. Correct in
  `JoinDuplicateBuild`; a copy-paste defect here.
- It matches on `def.id`, so **an armfus nanoframe never blocks an armafus start**.
  `HomeEnergy` asked for armfus 210x and armafus 209x in the same sample — the
  ladder oscillates between rungs and each rung is invisible to the other. That is
  literally "2 fusions, 2 or 3 afus".
- `EcoFusion` (`builder/fusion.as:272`) never calls `JoinTaskFor` at all — 37
  enqueues at the *identical* position within 10 s, the `AiMakeTask` re-election
  leak. Its own `gFusionsAsked - built` bound (`fusion.as:247`) goes NEGATIVE and
  stops binding whenever `HomeEnergy` has out-built it, the steady state at 531 vs
  170 requests.

**Serialising is free money, and this is not a cap argument.** With build power B
fixed and K reactors of buildtime T: in parallel every one lands at `KT/B` and
nothing pays until then; serialised the k-th lands at `kT/B` and the first pays K
times earlier for identical metal. Integrated energy over the same window is
`(K+1)/2` greater. K=3 doubles the energy for zero extra spend.

Derivation for the replacement cap: `metalCost/buildtime` is ~0.03-0.06 across BAR
structures, so one builder drains `workertime * 0.04` metal/s — about 7 for a T2
constructor — **independent of what is being built**. What a building can feed is
`income / drain`. Cost cancels; the current formula makes it the denominator.

Fix is a STOP (redirect a builder onto queued work, enqueue nothing). Order,
measured between each: un-invert the cap; let `JoinTaskFor` take unassigned tasks
and give `EcoFusion` the same join check; make "already under way" per
reactor-CLASS using the existing `IsFusion` (`builder/events.as:403`); clamp the
negative `outstanding`. `JOIN_BUILDERS_MAX = 8` is a hard cap of the kind
apexearth has rejected twice and binds at 200 m/s.

---

## 0a. OUR PICTURE OF THE ENEMY NEVER EXPIRES — and it is worst against humans

**FIX LANDED 2026-08-13, NOT YET MEASURED AND SHIPPED AS A NO-OP.** Both halves
landed: a fresh-cost C++ binding (`GetEnemyCostFresh`/`freshMobileThreat`)
blended into `EnemyArmyCost`/`EnemyFieldCost` via `apex_ghost_weight` (default
1.0 — bit-identical to before, by design), and the radar-tower sensor unblock
(`DefaultMakeSensors`). See CHANGES.md for both. Neither is measured yet:
`apex_ghost_weight` needs the `GhostDiag()` ghost-fraction telemetry from a
real run before it's worth turning down, and radar count needs a fresh 10x
6v6 batch against the 1/player-vs-2.4/player baseline below. Both smoke-tested
clean (no compile errors, no crash, DLL rebuilt).

**apexearth, 2026-08-13, after losing a real multiplayer 6v6 to HUMANS:** "just
20m in we're dying a lot and we already need spam to get vision on the humans, or
air scouts."

`CEnemyManager::Update` (`unit/enemy/EnemyManager.cpp:129`) retires a sighting
only after `FRAMES_PER_SEC * 60 * 20` — **twenty game-minutes** unseen.
`CAllyTeam::AddEnemyCost` increments on `EnemyEnterLOS` and decrements only on
`EnemyDestroyed`. And **no script anywhere reads recency**: a whole-tree grep for
`lastSeen`/`stale`/freshness returns only *level* reads of `GetEnemyCost`, never
a recency test.

So at minute 20 our model of the enemy is the **union of everything ever seen,
undecayed** — and every consumer acts on it: `brain/mix.as`, `military/posture.as`,
`builder/sitesafety.as`, `airthreat.as`, `military/defenceline.as`.

**Why this is a humans-specific defect.** Against stock BARb it is nearly
harmless: stock's army does not retreat, so what we saw is still there and mostly
dies where we saw it. Humans move, retreat, re-position and hide — so the model is
systematically wrong, it is wrong in the direction of *overestimating* what is in
front of us, and it is worst exactly when we are scouting least. Any "do we have
enough to attack" comparison against that number gets monotonically harder.

`EnemyManager`'s `lastSeen` is **not bound to AngelScript**. Adding the binding is
a C++ change and the prerequisite for any fix here.

Measured alongside it, same runs (10x 6v6 Aethermoor Creek, `--handicap 50`):
**radar towers ~1 per player per game for us against BARb's ~2.4** (`armrad` 5-11
per side of six, `armarad` 0-1). No script rule builds a radar tower at all — the
only two `Enqueue(BuildType::RADAR)` sites build a *jammer* and a *targeting
facility*. Towers come solely from CircuitAI's `DefaultMakeDefence` sensor block
(`MilitaryManager.cpp:885-916`), which our own `AiMakeDefence` gates out of most
of the map: every early return in `military/defenceline.as:408-503` skips
`DefaultMakeDefence`, and the sensor block sits inside it.

Scouts themselves are NOT the gap — armflea 58-177, armfav 38-54, armpeep 7-40,
armawac 5-13 per side. We look; we do not remember correctly, and we hold almost
no permanent coverage.

## 3. Stealth and sight are not used to set up attacks

**PARTIAL FIX LANDED 2026-08-13, NOT YET MEASURED AND SHIPPED AS A NO-OP.**
`CAttackTask::FindTarget`'s 5x free-eco raid bonus is now discounted unless
`CMapManager::IsInLOS` confirms the target ground, via `apex_eco_unseen`
(default 1.0 — bit-identical to before). This addresses only the "target
scoring trusts memory, not current vision" half — the corrected diagnosis is
that targets ARE re-scored continuously, but the safety check reads
`hostileDatas`, which retains anything out of current LOS/radar, so unseen
reads as confirmed-clear. See CHANGES.md. Everything below about
`apex_scout_threat` and escort-based scouting-ahead-of-a-push is still
untouched — deliberately out of scope for this pass; land and measure the
target-scoring fix first.

**apexearth:** "Maybe some better use of the stealth units to provide sight would
help AI be even more cheeky/evil to players."

Nothing today pairs a scout, radar or cloaked unit with an attack party to see
what it is walking into. `apex_scout_threat` exists (how hot a metal cluster may
be and still be scoutable) and has never been enabled or measured at 8v8. The
mobile radar escort (`factory/eyes.as`, 2026-08-09) follows the army for
targeting, not for reconnaissance ahead of a push.

Untouched: cloaked units as spotters, and using vision to pick a target that is
undefended *right now* rather than one that scored well when the task was made.

---

## 4. The late game produces no moments

See `docs/16-big-plays.md` for the full plan. Summary: nukes fire one at a time
the instant they are ready (`super fire armsilo stock`, 427 launches in one
hosted game), which one anti-nuke absorbs forever. Fifteen simultaneous launches
need fifteen silos, because a silo reloads in 30 s and an interceptor re-fires
every 2 s.

Stage 0 of that plan — actually building the silos — has not started.

---

## 5. Unblock's escape direction can pick a lane that stays blocked

From the 2026-08-09 hosted game: `armbeaver #9079` needed **six** clearing
orders, eating a nano turret each time and staying stuck. Detection is right
(9 firings, no false positives, one unit had 86 of our buildings ringed around
it); the direction heuristic picks the thinnest wall by structure count, which is
not the same as the way out.

Also, 86 of our own buildings around one unit is the base-sprawl complaint in
`USER-FEEDBACK.md` showing up as a number.

## NEXT: come to an ally's aid (2026-08-11)

apexearth: "its 4 different AI right so this is just ally defense forces coming
to aid (so long as the distance is not too great)", and on naming: "You don't
need to label this as 'pincer' or anything like that. It's simply coming to an
ally's aid so label it as something like that."

The converging-from-three-sides effect is what it LOOKS like when four players
each defend their own side. Nothing coordinates it, so it is not a manoeuvre and
must not be named as one -- call it ally aid.

The signal already exists and is ours: `CCircuitAI::GetAttackHotspot`
(cpp/src/circuit/CircuitAI.cpp), a cost-weighted centroid of where we have been
losing units, with a decay so it tracks the current fight rather than averaging
the game. It is PER-AI: `NoteLossAt` accumulates only our own losses, so a player
cannot see an ally being overrun.

Make it ally-wide with the mechanism already carrying the front-tower budget and
the AA count -- PublishTeamValue/ReadTeamValue, three keys (x, z, weight). Each
player then picks the heaviest fight within reach and sends its massing pool.
"Not too great a distance" is the existing reach bound.

Also fixes: `BaseUnderAttack()` fired twice in six games because it asks about
enemy influence at our own start position; a loss-weighted hotspot is a far
better "we are being attacked" trigger. And it gives the Brain's defence wants a
second position source -- the one porc+ had, deleted with it.

Before touching the army: add army-position telemetry to dev_stats_export.lua
(each side's army centroid and its distance from its own base). [BARAI_POS]
records BUILDINGS ONLY, so "our armies run away when the base is attacked" cannot
currently be measured at all, only watched.

## NEXT: idle constructors must assist the factory (2026-08-11)

apexearth: "we really lacked any sort of T2 army... imagine if we had 20 cons
helping the T2 lab make army... maybe the game would have gone better", and "all
that time we spend making cons is time not spent making army, AND as i told you
before we often have cons just sitting around with nothing to do".

Capping constructors is the wrong lever and was tried today. The measurement says
the build power EXISTS and does not convert: at minute 12 we hold 3,027 metal of
constructors against stock's 2,428, and at minute 20 we field 6,399 army against
their 12,649, on comparable income. More builders, less army.

So the work is: a constructor with nothing to do assists the factory, turning
build power directly into units. That is also the answer to "cons sitting around"
-- there is no such thing as an idle constructor while a lab is building.

Check first, per attribute-before-fixing: ExpandDiag already logs idle/onMex/
onOther per constructor every 30s. Count what the idle ones are actually doing
before writing a rule. `aiFactoryMgr.isAssistRequired` and the REPAIR task path
(assisting a building under construction IS a repair task in Spring) are the
existing mechanisms; CBuilderManager's own elector already raises repair tasks it
never gets to because our ladder answers first.

Do NOT re-cap constructors to fix this. The cap fix committed today is only about
a full metal bank disabling the limit outright, which is why a losing player ended
with 60 T1 cons.

## The base layout axis is the exact 180-degree reversal in half of all games

Measured 2026-08-12 over 442 `apex: base frame` latches in `matches/2026081*`:

```
axis kept front-facing 221 | axis REPLACED 223
fwd points AWAY from enemy (bands grow toward enemy) 221
fwd sideways 2 | fwd toward enemy (bands grow rear) 221
```

Every one of the 223 replacements was the exact 180-degree flip, not some other
orientation. `baseplan/axis.as:76-93` probes four right-angle orientations and
takes any that "more than doubles the front-derived score"; candidate `t == 1` is
`(-f.x, -f.z)`. Bands are then laid out as `gAnchor - gFwd * depth`, so when the
axis flips the whole stack grows TOWARD the enemy and the DEEPEST band -- the one
`baseplan/state.as:75-76` reserves for heavy energy, "where a fusion going up does
not take the rest of the base with it" -- is the most exposed ground we own.

Example: team 3, run `20260812-211651`, `anchor=809,706 fwd=-0.81,-0.58`, enemy
centroid ~(6436, 2751), dot = -0.96.

This is not a reactor bug. It moves every building the base plan places, which is
why it is recorded here rather than fixed alongside the AFUS placement work --
that change routes around it (`Base::AxisIsRearward`) for reactors only.

## The AI crashes in SkirmishAI.dll at roughly 1 percent of runs

4 of 371 runs on 2026-08-12 ended `Spring 2026.07.04 has crashed`. Stack is four
frames deep inside our own DLL:

```
(0) SkirmishAI.dll [0x59edf]
(1) SkirmishAI.dll [0x5aaf6]
(2) SkirmishAI.dll [0x11850]
(3) SkirmishAI.dll [0x23e2]
(4) spring.exe ...
```

Predates the 2026-08-12 obsolete.as and rules_optional.as changes -- run
`20260812-210421` crashed before either was deployed, so do NOT attribute it to
them without a repro. Observed once at frame 54707 (30.4 game-minutes), well into
a game, with nothing unusual in the preceding AI log lines.

The deployed `SkirmishAI.dll` is a 208 MB unstripped build, so those offsets are
resolvable with addr2line against the matching build if this gets worse. Nobody
has done that yet. Not reproduced on demand.
