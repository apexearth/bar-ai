# Open issues — what is wrong with this AI right now

What is broken or missing, with the evidence for it. `CHANGES.md` says what was
done; `USER-FEEDBACK.md` is the standing brief; this file is the live list.

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

---

## OPEN: advanced converter (armmmkr) requested dozens of times, never completes once -- energy spills at the storage cap for 12+ minutes (2026-08-14)

apexearth, live: "we have really stalled and it seems like we aren't making
any energy." Measured from `matches/20260814-214851-...` (Apex/Armada vs
BARb/Cortex, lost 26.6m): `[BARAI_STATS] team=0` `energyExcess` plateaus at
114,985-124,055 (storage cap) from minute 14 to 26 while `energyProduced`
climbs from 185k to 1.35M -- almost everything made past minute 16 is spilled.
`allBuilt=` never once includes `armmmkr` for the whole match despite `apex:
home energy armmmkr` (a genuine NEW creation, confirmed via the `created`
flag in `Requests::Take`) firing 18 times in the throttled log and a
cumulative `new=` counter reaching 99 by minute 16, with zero `covered`/
`full`/`claim` events for the def. One requesting unit proposed 3 different
armmmkr sites within 6 seconds. `Requests::InFlight(armmmkr)` samples at
exactly 1 the entire match (never 2+) even as the income-derived cap grows to
17. Compare an earlier same-night match (`20260814-163003`) where armmmkr DOES
complete (2,660 metal invested) and InFlight genuinely reaches 2-4
concurrently.

**Ruled out** (see `changes/2026-08-14.md` for the full trace): `MexOffer`
(only screens an already-MEX-typed offer), `HoldWorkInProgress`'s RECLAIM
extension (additive; CONVERT was already held via `SiteBuildName`),
`forcedFusion` (doesn't touch the `isConv` branch HomeEnergy takes here), and
a threat-veto misread (zero `con-veto abandon ... convert` lines in the log).

**Not yet isolated:** why each armmmkr request dies before completing one
unit -- killed builder, an engine-side site-validity rejection after the
script's speculative grid reservation, or something else. The
`AiTaskAdded`/`AiTaskRemoved` lifecycle log was scoped to reactor-tier ENERGY
(>=2000 metal) only, so CONVERT tasks were invisible to it; extended
(`manager/builder/events.as`, `apex: convert-task-added`/`convert-task-
removed`, fields `done`/`hadNanoframe`/`workers`/`unit`/`at`) as a pure
diagnostic, no behaviour change. **Needs one more watched/completed match with
this new logging** to read `hadNanoframe` on the removed events and settle
whether this is combat losses (expected, not a bug) or a genuine construction
mechanism failure (a real regression).

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
