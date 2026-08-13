# Open issues — what is wrong with this AI right now

What is broken or missing, with the evidence for it. `CHANGES.md` says what was
done; `USER-FEEDBACK.md` is the standing brief; this file is the live list.

---

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

**FIX LANDED 2026-08-13, NOT YET MEASURED — AND A REAL GAP FOUND THE SAME
NIGHT, WATCHING.** All four mechanisms below were fixed in
`joinbuild.as`/`fusion.as` (see CHANGES.md). Smoke-tested clean (no compile
errors, full 30-minute run). The 701/40 numbers below are the *pre-fix*
baseline — a fresh tournament against the same baseline conditions is still
needed.

**apexearth, watching a windowed 8v8 the same night, at 26:55:** "At 26:55 into
this game We are making 5 advanced solars and 2 fusions at the same time. You
just made a fix which was supposed to fix exactly this kind of issue." Traced
in `matches/20260813-222958-*`: team t3 alone enqueued **5 separate armadvsol
tasks in an 8-game-second window** (frames 40956-41196), landing at
`1680,2880` / `544,3504` / `1744,2880` / `1616,2880` / `1792,3024` — four of
the five within ~200 elmos of each other. The join system is not dead: the
same log window shows successful joins elsewhere (`con-join(direct)
armrectr -> armadvsol joined=1`). It just doesn't see this case.

**Mechanism**: `JoinTaskFor(want, unit)` (`joinbuild.as:128-134`) measures
distance from `unit.GetPos(ai.frame)` — the CALLING BUILDER's current
position — never from the spot `HomeEnergy`/`EcoFusion` is about to place the
building at. That is deliberate for one purpose (`joinbuild.as:33-36`: "a
constructor on the far side of the map building its own is better than one
walking across the map to help"), but `HomeEnergy` computes `spot` via
`ReactorSpot`/`BandSpot`/`CoveredSpot` *before* calling `JoinTaskFor`
(`mexguard.as:538-595`) and never passes it in. So five idle constructors
scattered around the base each ask "is there a joinable task near ME" from
five different locations, each gets "no", and each then independently
computes a `spot` from the SAME placement logic (pack/band against the same
base layout) — which is exactly why the five spots end up clustered together
even though the five builders that decided to place them were not.

**Not yet fixed.** The right question is closer to "is there a joinable task
near the SPOT I am about to build at", which needs `JoinTaskFor` (or a sibling
check) to take the candidate `spot` as a parameter and compare against
`cand.GetBuildPos()` directly, independent of where the calling unit currently
stands — walk-time-to-assist and duplicate-detection are two different
questions that the current single distance check conflates.

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
