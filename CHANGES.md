# What this AI does that stock BARb does not

## 2026-08-26: rez bots stood around, and had not resurrected anything in weeks

apexearth: "I see a lot of rezbots standing around doing nothing when they
should be resurrecting or reclaiming wrecks which are nearby."

`apex_medic_share` was NOT the cause -- the medic rule is the first of six in
the rez branch of `Builder::AiMakeTask` and returns null to pass, so a medic
falls through to salvage/reclaim like any other bot. Four separate mechanisms
were:

- **Nothing in the pipeline could resurrect at all.** `RezzerPreemptReclaim`
  held the only `TaskB::Resurrect` call site in the whole variant, and the
  kill-phase rewrite of `AiMakeTask` dropped its last caller -- verified by
  grep: no reference outside its own definition. With no fall-through to
  `DefaultMakeTask` either, a rez bot could only ever reclaim. Rewired as
  `RezzerRezOrEat`, and the resurrect is now centred on a corpse from
  `GetBestWreckPos` rather than the bot's own feet, so an area order can no
  longer sit over empty ground for its 60s timeout.
- **One team-wide clock served the whole fleet.** `gNextRezWreck` gated both
  `RezzerFrontSalvage` and `RezzerEatCorpse`, so of N idle bots at most one per
  period got an assignment and the rest lost the race. Now per bot via
  `ConSlot`, spaced by `apex_rez_scan_s`.
- **One hit parked a bot for 90 seconds.** `REZ_TROUBLE_WINDOW` is now
  `apex_rez_flee_s`, default 20s. The threat vetoes on every rule above still
  refuse hot work on the way back, so the shorter hold does not walk it back
  into the fire.
- **A veto refuses a job; it never moved the bot.** A rez bot standing on hot
  ground had every rule decline and then just stood there. `RezzerIdle` retreats
  in that case instead.

Also: a medic on station with nobody hurt returned null and stood in the
aftermath, because every rule below it is gated on being behind, exposed or
short of metal. It now eats what is within `apex_medic_r` of its station.

Not yet measured -- landed 2026-08-26, awaiting a watched game.

## 2026-08-26: a nanoframe outlives its request, so we built the same thing twice

apexearth: "Sometimes we decide that we want to build something like an anti
nuke but it happens that we were already in progress to do that but got
distracted for a moment. We then choose to make a new one, and sometimes a nano
turret will finish the first one, so then we have 2 of those buildings."

Everything that answered "is one of these already coming" read
`Requests::gLive`, a registry of TASKS. `IBuilderTask::OnUnitDestroyed` aborts
on `(target == nullptr) || units.empty()`, so losing the one builder mid-build
removes the task while the frame stays standing — and the census credits a
structure only at `AiUnitFinished`. Between the two the AI owns a half-built
anti-nuke that nothing in it knows about: `ProtCovered` reads the ground as
uncovered, `SuperCensus` reads have=0, a second is sited, and a nano turret in
range quietly finishes the first.

**Measured: 66-89 abandoned nanoframes per 30-minute 1v1** (armmex 44, armmakr
9, armadvsol 9, armsolar 8, armrad 6, armllt 5, armnanotc 3 in one game). Not a
rare race — the normal outcome of losing a constructor.

- **`Requests` keeps a ledger of orphaned frames** (`gPendId`/`gPendDef`/
  `gPendPos`): entered from `AiTaskRemoved` when a task leaves unfinished with
  its `target` up, left at `AiUnitFinished`/`AiUnitDestroyed`, with a sweep
  through `ai.GetTeamUnit` as the backstop for an event never seen. Ids, not
  handles, so a frame that dies between events cannot dangle. Bounded at 7-11
  entries across a game.
- **`Take` finishes the frame instead of starting a second.** A pending frame of
  the wanted def within the site radius (positional) or `REACH` (everything
  else) is adopted with a `TaskB::Guard` on it — a build order needs a free
  square and the frame is standing on the only one that matters; guarding a
  nanoframe pushes `CMD_REPAIR` in `CBuilderCAI::ExecuteGuard`. The hold is the
  frame's remaining cost at one pair of hands, so the guard does not outlive the
  job. Vetoed by the same `CON_THREAT_VETO` as `JoinFor`: a frame abandoned
  because the ground was hot is not walked back to. Mex/mexup exempt, for the
  reason they are exempt from the rest of the dedup.
- **`ProtCovered` and `SuperCensus` count what is coming**, both the live-task
  kind and the orphaned kind. `ProtCovered` previously consulted neither, which
  is why the anti-nuke case reached the auction at all.

New log lines: `apex: frame-orphan <def> at=x,z done= standing=`, and
`apex: request resume-frame` / `frame-standing` alongside the existing request
outcomes.

## 2026-08-26: energy nothing converts is worth nothing

apexearth: "When we are overflowing energy that energy provides no value in the
form of metal -- to make that value we need to have enough converters. If we're
already overflowing energy we should understand that adding more energy will not
add the metal value. We currently overflow too much and do not prioritize
converters enough."

Every E/s of new generation was priced at `EPriceFloor()`, which amortizes the
converter that realizes it -- an honest price for the generator+converter PAIR,
paid whether or not the converter exists. Nothing else in the market closed that
gap, so generation could run indefinitely ahead of the capacity to convert it.

Four parts, all behind `apex_e_realize` (default 1; 0 is the control arm):

- **`ERealizeShare` (`market/price.as`)** scales a generator's gain by the share
  of its output anything would use: real demand at `apex_e_headroom`, plus the
  converter fleet's capacity, plus the room left in the E bank. Above that line
  the gain decays to zero and the market buys the converter instead; it lifts
  by itself the moment capacity or demand rises. Applied to `ProposeEnergy` and
  `ProposeGeo`.
- **Demand is not raw pull.** Pull is throttled demand AND dips to nothing
  between jobs -- measured flipping the share 1.00/0.00 tick to tick. It is now
  a fast-attack, slow-decay peak of `pull - converter draw`, converters excluded
  because a converter is the sink for what nothing else wants, not a consumer to
  supply at headroom.
- **`ProposeConvert` was double-subtracting its own fleet.** BAR's
  `game_energy_conversion.lua` charges each maker's draw as unit energy use
  (`SetUnitResourcing "uue"`), which lands in `CTeam::resPull` -- so
  `energy.pull` already contains it and the surplus EMA is already net of
  standing converters. Subtracting `StandingConvCap()` again hid a saturated
  fleet's remaining waste entirely: capacity 100 chewing everything with 50 e/s
  still spilling read as -50 and proposed nothing. Now it subtracts only
  capacity ALREADY ORDERED, and reads the gadget's own `mmUse`/`mmCapacity`
  team rules params as ground truth (`ConvUseE`/`ConvCapE`) with the old
  estimate as fallback. The converter want also gets the same eco-compounding
  premium the generator has always had -- it was the only half of the pair
  paying flat.
- **The share never reaches zero** (`apex_e_waste_worth`, 0.25). apexearth's
  standing ruling is that the generator ladder never pauses on waste, and his
  call on this change was "we still should care about energy, so not zero - but
  we want converters to be above the energy want." Energy in the wasted band is
  worth the conversion floor the moment a converter follows -- and that
  converter's own cost is already netted out inside `EPriceFloor` -- so what is
  actually missing is the wait and the risk, which is a discount, not a zero.
  An overflow now makes a generator LOSE to the converter that realizes it and
  never makes it unbuildable. The 0.25 is chosen, not derived.

Measured on the benchmark, three arms, seeds 21-32 (n=11-12 each), and they are
all inside its noise: waste 16.7% / 15.9% / 13.0% by median for control /
zero-floor / 0.25-floor, metal produced 14.1k / 13.9k / 15.1k. What the floor
arm does show is the intended shape -- a 20-minute game at 7 standing
converters, 7.8% of energy wasted, and 51 energy elections against 11 converter
ones, i.e. generation never stopped.

Measured earlier, 18 pairs, Comet Catcher 16 min vs BARb stable, `apex_e_realize` 0 vs 1
on one build: energy wasted 17.9% -> 16.9% of production by median and
21.3% -> 17.2% by mean (the control's tail includes a 74% game; the treated
arm's worst is 28%), converters 1.89 -> 2.50 per game, with metal produced, eco
share and army share unchanged. So it removes the overflow blowups and costs
nothing here. This benchmark barely reaches the overflow regime -- the effect
belongs to the high-income hosted games the complaint came from, and has not
been watched there.

## 2026-08-26: no constructor stands still

apexearth: "A lot of our engineers tend to sit idle. Instead of doing nothing
we should always fall back to doing something useful even if it is just
assisting."

`Market::Decide` had two exits that returned null. The one with a floor under
it -- no want priced positive -- fired ZERO times in a measured 20-minute game.
The one that actually fires had no floor at all: **472 elections in that same
game ranked wants and had every one refused by the executor** (energy=507,
sense=276, protect=27 refusals), and each of those left a constructor holding
nothing. `apex: exec-refused` was reporting it and nothing acted on it.

**`market/floor.as`** is now reached from both exits. It lends the idle lathe
to work somebody else already commissioned: a worker raising a nano first
(build power compounds), then one raising a factory, then any other build, then
a line with something queued; failing all of those, reclaim a nearby feature,
then patrol the farm. A guard auto-assists whatever its target builds, so this
is real build power, not a parking spot. The commander is held inside the eco
leash -- a cross-map assist is the walk that kills him.

The leash is 15 seconds, against the priced assist want's 60: a held builder
task is never re-elected, so the floor must not lock a lathe out of the market
it just failed to win in. `GuardSweep` already releases a guard the moment its
boss stops working.

Measured: fires as designed (`apex: floor ... -> assist:`), always finding a
boss -- the reclaim and patrol tiers never ran. Composition at 16 minutes,
Red Comet seed 1, is a wash against a floor-disabled baseline (12.6k / 9.1k
built against 12.3k), which is what a fallback on a previously-dead path should
look like; it is a single pair of runs and says nothing stronger than "no
visible displacement".

### ...and it assists whatever matters most

apexearth: "If we're using all our resources and people are building 5
different things, but 1 of them is way more important than the rest, then I'm
hoping our constructors will assist the building which is the most important."

A live builder task carries its def and its progress but not its price, so
that question was unanswerable and idle hands went to whoever was nearest or
first in a list. **`Decide` now records the winning Want's value on the task it
commissions** (`NoteJob`), and `BestLiveJob` ranks what is in flight by it --
halved per hand already on site (the second lathe doubles a site's speed, the
tenth adds a tenth) and discounted for the walk. The market's own currency, not
a second opinion. Work the market never priced -- the engine's own tasks -- is
ranked against nothing and stays on the old class fallback.

Two rungs, because they answer different questions. **Can a lathe be fed here?**
decides whether to TAKE the task; **which job matters most?** decides where to
STAND. Conflating them made the first version dead on arrival: `SiteWorkerCap`
splits the income's hands EVENLY across live sites, so with thirteen of them
every site read "full" at a single lathe and the join rung never fired once in a
25-minute game (`apex: floor-diag ... full=11`). Now a saturated crew is
overridden while `FreeMetalFlow` has a lathe's drain going unspent -- and that
is self-limiting, since each hand that joins raises pull and closes the gap
behind it -- while the "where to stand" ranking ignores the feed test entirely,
because a hand parked on the top job is the one drawing the instant flow frees.

The priced assist Want takes the same target (`BestJobBoss`), and is now priced
by what that target is worth.

### The assist is repriced by the acceleration it buys

Pricing the DRAIN made every assist worth the same: helping a reactor and
helping a wind turbine bid alike, because both move one lathe's metal. What the
extra lathe actually buys is the building arriving sooner, so with B the flow
the site already draws, d the joiner's fed drain, R the metal still to go and
G the job's own recorded return:

	dT   = R*d / (B*(B+d))      how much sooner it lands
	Tocc = R / (B+d)            how long the joiner is posted there
	gain = G * dT / H           the one-off, annuitized

The return now scales with the JOB's return and falls away as the site fills --
one hand on a lonely reactor is worth the reactor, the tenth hand a tenth of
it. Unfed drain gives dT = 0, so the existing eFeed/FreeMetalFlow bounds kill
the want by arithmetic instead of by a second rule, and `tCost` charges the
real posting `(walk + Tocc) * Wage` rather than a flat guard stint.

**Dividing by the payback horizon is what makes it comparable.** Every other
want's gain is a rate that runs forever; an assist buys a one-off and stops.
Priced as a rate over its own stint it read as ENORMOUS exactly when the stint
was shortest -- a site seconds from done bid v=446 against a mex at 18
(measured), the arithmetic saying "infinite return for no time". Annuitized
over the horizon the rest of the market pays back against, a nearly-finished
site is worth nearly nothing to join and a lonely reactor is worth a lot.

The "only lesser cons may assist" gate went with it: a role may change how
much, never whether. A ceiling con's own upgrade work is now priced against the
acceleration and wins on its own merits, so the ban was deciding an auction the
auction can decide.

Measured, 6 runs against 4 of the flat pricing: metal built 22.3k median both
ways, eco 7.35k against 7.36k -- composition-neutral at this benchmark. What
changed is behaviour: assist wins fall from 70-107 elections a game to 5, and
the ones that remain are on the job that matters. The un-annuitized form was
tried first and is the one real signal here -- 16.8k built, its worst run, with
the v=446 pathology visible in the log.


Measured: idle hands converge on one job at a time and pile onto it --
`armalab`, then `armadvsol`, then `armfus`, three cons each -- and the join rung
takes unmanned work outright (`-> join:armnanotc v=13.94 hands=0`). Composition
over four runs is 22.3k median metal built against 25.3k for the unranked floor,
with a 20.0-43.6k range: inside the noise, and not a control.

## 2026-08-26: the golden metrics, and the class reference that hid them

apexearth: "We build a lot of the wrong units. We don't seem to value range
and damage enough... enemies often kick our ass with Tzar and Banisher armies.
We're making close range units that can't even touch them." Asked how to
express a force-build lever, he redirected to the formula itself: "Maybe range
* hp * damage? Perhaps we can try a variety of algorithms."

**The golden metrics were never bound.** `power` fuses them as
`sqrt(dps)*alpha^0.25*sqrt(hp)`, and script could only recover the product by
squaring it. `rawDps`/`rawDmg` are now members, and `GetAoe`/`GetRawDps`/
`GetRawDmg` are registered. Weapon AoE had existed in C++ since forever and
was simply never exposed. Verified: `combat == dps*sqrt(alpha)*hp / 128^2`
holds for 205 of 250 armed defs, and all 39 outliers are exactly their
`behaviour.json` "power" override squared (armvader x100, armthor x0.01,
corak x0.81).

**`market/worth.as`** replaces the ad-hoc multiplier chain with one score
weighted by exponent per metric, each normalised by the field's own reference.
At the shipped defaults it is a *pure rescale* of the old `gCombat/costM` --
max relative deviation 6.7e-16 across 250 defs, ranking identical -- so it
ships as a no-op and every setting is a clean A/B. The cost exponent is a
choice of Lanchester law, not a taste for expensive units: `gCombat` is
quadratic in quality, so cost^2 is the linear law (bodies trade one for one,
chaff wins) and cost^1 the square law (a massed army fires at once).

**THE FINDING: the class reference was a mean, and the mean was an outlier
statistic.** `LineClassOf` judged each axis against the field MEAN. A Korgoth
(149,000 hp) and a Behemoth (335,000 hp) drag mean hp to 7,741, so a Tzar at
7,800 reads as 1.008x the field and misses the 1.15 edge; mean range came out
1,645 elmos, which no ground unit clears. Measured in-game: **127 of 151
buildable units classified as MID**, leaving the 30/25/25/20 composition
target five tank units and five reach units in the entire field to select.
The target could not be expressed at all.

Fixed with the median (`LineRef`), plus reading the hp and dps axes per BODY
rather than per metal -- range was already absolute, so the argmax had been
comparing three axes in two different units, which is what made a Thud
(7.9 hp/m) a tankier unit than a Tzar (4.7). Both halves are needed: the
median alone still calls a Pawn a TANK and a Tzar a DPS unit. Class split
5/127/5/14 -> 51/52/23/25; Tzar -> TANK, Banisher -> REACH.

Measured, 10 games each vs BARb stable, per-game median army share of metal
built (pooled means overstate this -- they weight the longest games):

| arm | median army share | games above baseline median |
|---|---|---|
| baseline | 10.1% | 5/10 |
| median + per-body | **13.2%** | **8/10** |
| + cost exponent 0.5 | 13.5% | 6/10 |

Shipped: `apex_line_median` and `apex_line_abs` default ON. `apex_worth_cost`
stays at 1 (today's law) -- 0.5 raised the pooled figures and the IQR ceiling
(to 21.9%) and put a Behemoth in the top metal sinks, but did not move the
median, so it needs more games than the noise floor here allows.

**NEGATIVE RESULT: discounting inaccurate rockets does not pay.** apexearth,
reading the reach class: "those reach units were probably the terribly
inaccurate rocket launcher dudes... they're only good vs structures. i wish
you could detect that somehow." It is detectable, and now is: `isDumbFire` is
true when a unit's longest land weapon is an unguided (non-tracking) rocket.
It separates the case exactly -- armsptk/corstorm/corvroc true, corban (a
tracking missile) false, every cannon false. Note `isAlwaysHit` is NOT this
test: it gates air targeting, so its bar is "can hit an aircraft", which
condemns a Tzar and blesses a Luger.

But pricing it lost on every counter. As a range discount in the score, 10
games: army 17.1% -> 12.5% pooled, metal built 142k -> 85k -- the discount
also drags the field's range reference down, pushing the same units back into
MID and re-saturating the class the fix had just emptied. Narrowed to
classification only, still no better (median 13.2%, 6/10). `apex_aim_miss`
therefore ships at 1.0 (no effect); the detector stays for a future use that
does not move the reference.

**Also found: `targets.as`'s ROLE_* income-bracket tables are DEAD.**
`QuotaFor` and `NextForMix` no longer exist and nothing outside `targets.as`
reads them. `Market::ConOrderFor` is the only path to what gets built --
CLAUDE.md's "read the facqueue quota lines first" and the `ai-factory-brain`
skill are stale on this point.


## 2026-08-26: nanos serve the factories that are building units

apexearth: "We make nano turrets around buildings we're making, but we
rarely make them around factories that are building units. Factories need
more support and we should want to make nanos around them."

Three defects, each measured in an 18-minute Comet Catcher run with the
nano demand and siting logged:

- **A line was priced on the army shortfall, a build site on free flow.**
  `NeediestLine` split `LineSpend()` (army gap / fill time) across the
  lines, which reads 0.6-2.5 m/s whenever the army is near target, while
  a build frame was priced at the full free metal flow -- 26 m/s. A
  factory could never outbid a frame. Both now price the same way: what
  the economy can feed the site, less the lathe already standing on it.
- **A build site counted its crew as demand.** The frame loop asked "does
  it have fewer than three turrets", and the sink-siting loop used its
  crew's drain AS the pull -- so the more hands a site had, the more it
  bid. Crew and existing turrets are supply now, subtracted on both sides.
- **The siting loop had no bigness filter.** `ProposeNano` restricts sinks
  to `apex_nano_sink_m` / `apex_big_e`, but the executor's placement loop
  walked every live request, so a turret bought by a queued lab got parked
  at a 50-metal mex: 13 of 14 sink placements in one run were armmex or
  armmakr, at 1600 elmos from the factory that priced them.

Also: `LineWorking()` -- a line counts as working if `CountQueued > 0` OR
the facqueue ledger has orders pending for it, because CountQueued lags
sends by an order window and reads zero for work really on the line.

Before: 9 nanos, 6 sited at eco frames or mexes, labs with a queue running
on one turret. After: every placement at a working line (distance 0), the
ring reaching 3 while the queue stays fed.

## 2026-08-26: the strategic structures have a want of their own

apexearth: "The best defenses in the game I rarely see us make. I also
don't see us making Nuke silos or Anti Nuke... So far in a bunch of games
recently I haven't seen a Gantry... I prefer not to take a purely
mathematical approach to this topic. It is more of a 'if I can afford
this, I'll insert it as a want so we make one'."

Three separate mechanisms were behind it, all measured:

- **The gantry was structurally impossible.** `want_tech.as` Channel 3
  ends with `if (!unlocksTier) continue`, where unlocking means reaching a
  better extractor or a better converter. A gantry builds neither -- no
  constructor at all -- so it was dropped before it was ever priced. Its
  only other route, `ProposePlant`, prices per metal against a 600-metal
  lab and never wins.
- **The nuke silo and the long-range gun were priced as turrets.** Both
  are static, unarmed of build options and weapon-bearing, so
  `ProtClassOf` filed them PROT_DEF and the ground-defence auction --
  which divides gain by cost -- was the only bidder. It buys LLTs.
- **The anti-nuke shared the defence category's single ticket** with
  ground turrets and lost its argmax every election, the same failure
  CAT_SENSE and CAT_AIRDEF were split out for.

New: `WK_SUPER` / `CAT_SUPER` (`brain/market/want_super.as`) covering the
anti-nuke, nuke silo, long-range gun, the faction's best turret and the
T3 gantry. Its one question is affordability -- the bill in metal plus
energy at the conversion floor against what the economy makes in
`apex_super_afford_s` (60) seconds -- and the gain is the share of that
budget left over, so the same structure prices at nothing on the income
that can barely pay for it. That single number produces the ladder: the
anti-nuke clears at ~36 metal/s, the long-range gun at ~90, the gantry
and the silo at ~160. Counts rise with income (`apex_super_per_income`),
one strategic frame stands at a time, and an affordable want skips the
category lottery (`apex_super_push`) rather than drawing a ticket it
would win once a game.

Two classification traps found while measuring:

- Detecting a silo by its **stockpile** attribute named `armmercury` one
  (the long-range AA batteries stockpile too). Range does the job:
  2,400 elmos against a silo's 72,000, plus an air-threat guard.
- Detecting a gantry by "its products dwarf what our lines make" named
  the **T1 bot lab** one in a 4v4, because with no plant standing the
  ceiling it compares against is the sentinel 1. It now reads the
  `Factory::Attr::T3` marking `Main::AiMain` already sets.

Measured, bonused 4v4, seed 21, 28 minutes: the four apex players built
three Citadels and three Rattlesnakes, having previously built none of
either. Basilica and gantry wants priced and ranked but the game ended
before their turn -- they sit behind the cheaper classes in the
category's argmax. Unbonused benchmark 4v4 proposes nothing at all,
which is the design: 4-9 metal/s buys no strategic structure.


## 2026-08-24: the economy is legible over time

dev_stats_export samples GetTeamResources twice a second and dumps the
bank, storage, income, pull and spend for both resources, plus cumulative
stall counts. A stall is the engine's own arithmetic -- pull exceeded
what it granted -- not a threshold on storage. The dashboard differences
neighbouring samples into per-second production, per-second waste, bank
fill and the stalled share of each window.

First reading (12m Comet Catcher vs stock hard, seed 3, apex side):
44.5% of all metal produced was thrown away, with the bank pinned at
100% of storage from 6m to 12m while income climbed 14 -> 23 m/s.
Metal and energy stall counts move together on this side (identical to
the sample), which is what a build step paying both resources looks like
when energy is the binding one -- team 1 in the same game diverges
(122 vs 150), so the two counters are independent.

## 2026-08-24: the dashboard can see what the AI was thinking

Four telemetry gaps closed, all read through tools/dashboard.py:

- **Metal by destination.** dev_stats_export now assigns every finished
  unit to exactly one bucket -- mEco, mArmy, mDefence, mDefAA, mBP,
  mFactories, mOther -- so army production has a counter for the first
  time and cheap units are inside one. BAR states a solar's output as
  negative energyupkeep and a converter only via
  customparams.energyconv_capacity; testing energyMake alone filed every
  solar under "other" (caught on the first verification run, seed 3).
- **Unit counts.** `unitCount=name:n` per sample, for every finished def
  at any cost. Counts were previously derived by dividing a metal sum by
  a cost read from the other game tree.
- **Perceived enemy.** Military::IntelDiag logs `apex: intel` every 30s:
  our army, massing threat, seen peak, group count, and per role the
  fresh/raw pair whose gap IS the ghost share the posture gates discount.
- **Brain metrics over time.** The dashboard now parses the existing
  `apex: budget` and `apex: risk` lines into share-against-target curves
  per category, plus income, committed metal, and the risk field.

Verified on a 10-minute Comet Catcher run: zero compile errors, buckets
reconcile against unitCount (5 mex = 350 eco, radar = 60 other), all four
panels render with no console errors.

## 2026-08-24: cluster insurance, the first T2 con, and commitment discipline

Three from apexearth's watches, one session:

- **Building clusters are insured** ("a 50 metal enemy unit destroys 100s
  of our value"): factories, the fusion pack, and the farm each price a
  tower want at cluster value x apex_insure_rate when nothing covers them
  within 450; identical gain across tower defs means ValueOf picks the
  cheapest (the Sentry) by arithmetic. Sited at the cluster edge toward
  the enemy.
- **The first T2 con prices like the monopoly it is** ("we make a T2 lab
  but don't even make a T2 con"): the upgrade stream now divides among
  cons that can REACH it, not all busy hands -- a T1 fleet cannot moho.
  First armack v=7 -> 173; techStart 7.8-8.1m on check seeds; first
  decided KILL WIN vs stock hard (14.1m) same build.
- **Commitment discipline**: started frames are held, and the final
  approach (<600) counts as started; the roulette explores only at free
  elections. Before: 61 sentry requests, 850m of abandoned nanoframes,
  zero finished. After: first insurance defence standing (armbeamer,
  seed 9); completion still unreliable on seed 5 -- residual filed in
  ISSUES (suspects: frames killed by the raids they exist to stop, walk
  churn beyond 600, NORMAL priority).

## 2026-08-23: the line floor is a scarcity question

The opportunity floor (an order must beat 0.25x the executed-want EMA)
structurally idled expensive T2 lines: per-metal value comparison buries
units whose gain does not scale with cost, and its OverflowM escape (bank
at 80%% of storage) opened far too late (A/B: 1 produce decide in 5.5
minutes at floor 0.25 vs a real stream at 0). Now gated on
FreeMetalFlow() <= 0.5: in true scarcity the per-metal compare is right
(metal IS the constraint, the 22-armacks-vs-fusion lesson); with unspent
flow standing, an idle line is pure waste and the floor stands aside.
First default-floor verification: T2 at 11.7m. Division-only baseline
(6 games): mex ~26, prod ~30.7k, T2 ~12m median, with a no-tech tail
(seed 7: never teched, 10.5k waste -- unsunk late income IS the waste).

## 2026-08-23: the veto dies -- same-tier labs lose on price (apexearth's correction)

"The math should be correct. We shouldn't need vetos... perhaps what
we're missing is an affordability element." Three states tried same day,
each measured:

1. Reach-kinship VETO (0add861) -- worked but violated the paradigm.
2. Veto replaced by MATH on both sides: tech gain divides among same-tier
   pipes in flight (unserved-demand law), and a cost-side affordability
   multiplier (cost+committedDebt)/cost on the feed floor.
3. The cost-side multiplier REVERTED: a debt ledger is not a flow
   commitment. Three seeds wasted 3.5-8.7k with T2 past 20m WHILE METAL
   OVERFLOWED -- overflow is proof the income was never spoken for.

Final state: gain-side division only (tech demand/(1+liveKin); plant
dedup counts equal-reach same-class kin). Verified: one T2 ground lab on
both check seeds, mohos still lead fusion. Economy medians pending a
batch -- single-run variance on this benchmark is too high to read
(known: 60%->10% on an unchanged AI).

## 2026-08-23: one tier purchase at a time -- reach-kinship for labs

apexearth, watching: "we made a T2 bot lab and then a T2 vehicle lab...
we couldn't at all afford two, barely could afford one." Mechanism: tech
gain fires on prodCeil > OwnedCeil, and OwnedCeil counts STANDING
factories but not ones under construction -- a window minutes long
exactly when feed-bound -- while the per-def dedup (deliberately narrow
so a T1 rebuild cannot zero tech) is blind to same-tier-different-def.

- ProposeTech: a live plant whose products reach the same extraction tier
  vetoes any other lab claiming that unlock (kinship by REACH, in flight).
- ProposePlant: a "duplicate" is any standing plant of equal reach and the
  same air/ground class, not the same def -- parallel capacity of one tier
  splits the gain like copies always did.

Verified seed-5 Comet: exactly one armalab, no armavp, techStart 11.8m,
mex 34, prod 37.7k (profile held).

## 2026-08-23: nano farms ditched; fusions pack the deep rear; amphibs x0 on dry maps; mobile radar/jammer unblocked

All four from apexearth watching, each verified on seed-5 Comet (floor off):

- **Nano farm removed entirely** ("these nano farms are just not working
  out"). Nano demand is now working lines short of hands OR a fusion-tier /
  >=1000m frame without its ring of ~3 (his read of stock's caretaker
  logic); BPGap buys constructors, never turrets. Placement: hungriest
  line or big frame, bare fusion frames count, last resort beside a
  working factory -- never a freestanding farm. Nano decides 97 -> 11,
  4 pulled to live sinks, techStart improved to 11.3m.
- **BigEnergySite**: fusion-tier generators (apex_big_e 500 E/s) pack
  beside standing/building kin, else apex_fus_back (700) behind the base
  anchor -- "fusions belong in the back of the map".
- **Amphib x0 under apex_water_pct (15%) real water** -- Frozen Ford's
  pond flipped IsWaterAVoid; the bar is GetLandPercent (already bound,
  no C++ needed; verified percent-scale, 100.00 on Comet).
- **Mobile radar/jammer were structurally impossible**: the DLL sets
  isRadar/isJammer only in the IMMOBILE branch of its def loop (a past
  session documented it in CircuitDef.h:355 and nobody wired around it),
  so the support branch was unreachable -- pricing changes could never
  matter. Catalog now classifies from the sensor radii (radar >900,
  jam >100) with the DLL flags as static fallback. First armmark and
  armaser ever produced, one pair at ~1 squad, per apex_squad_m.

## 2026-08-23: the temporal-consistency law gets shared primitives; assists can no longer feed a starved site

apexearth's 10 m/s arithmetic (com + 3 cons on a 5-minute T2 lab while 2
safe mexes sat open) exposed two pricing bugs, fixed and A/B'd on seed 5:

- **ProposeAssist ignored the metal feed**: gain was the assister's full
  drain at mCost=1 (value in the hundreds) regardless of whether the
  economy had any unspent flow. Now capped by `FreeMetalFlow()` (unspent
  income + bank trickle) -- the metal twin of its existing eFeed. Result:
  assist pile-on gone, mexes 11 -> 36 on the same seed, production 2.3x.
- **Displacement charges feed-competitors only**: an intermediate version
  also charged open T1 claims (via an OpenSpotStream) and priced T2 out of
  a whole 25-minute game -- double-counting, since 50m claims proceed in
  parallel on the hands FreeMetalFlow frees. Final form: `UpDemand x
  feedSec` (620m mohos genuinely compete for feed; free claims do not).
  Seed 5 final: mex 36, prod 38.1k, techStart 15.4m, mT2 14,640 (vs
  baseline 11 / 16.3k / 12.1m / 4,040).

The law and its review checklist are now written into the value-paradigm
skill: hands conflicts are priced where hands are priced (FreeMetalFlow),
feed conflicts where feed is priced (displacement); charging one conflict
in both places produces the opposite failure. Also this session: user
worth-mod table (UnitWorthMod: armsnipe 1.6, armsptk 0.6), amphib 0.5x on
IsWaterAVoid maps (gAmphib), mobile radar/jammer repriced per apex_squad_m
(2000) at apex_intel_rate (0.1/min) -- support units still unverified in a
game (their T2 line was idle; see the line-floor ISSUES entry).

## 2026-08-23: builder wants draw proportionally; the eco defence gate classifies by def; death walks refused

Three linked changes, each audit- or log-verified same day:

- **Builder-side roulette** (market.as Decide): builder wants were argmax
  while only factory lines drew proportionally -- measured starvation: team 3
  bought nanos at v=20-275 for 8 straight minutes while its T2 lab bid 16.7
  once and never won (apexearth, watching: "a ton of nanos and no T2 lab").
  The same seeded value-weighted draw as the produce side now picks; ranked
  order remains the executor-refusal fallback. After: tech wins draws against
  nano bids 10x its value; team 3's kind mix diversified (18 nano / 2 tech /
  31 protect / 38 produce decides).
- **Eco defence gate fixed -- it never worked**: the ExecuteWant gate compared
  `w.spotId == PROT_DEF` (constant 4), but defence branches store the CLUSTER
  id in spotId -- only cluster #4's claws were ever caught, which is why three
  "airtight" runs still grew claws with zero prot-exec lines. Now classified
  by the def (any ground-shooting weapon; AA exempt, matching the audit's
  mDefAA split). Seed-11 after: mDefence=0, 190 intercepts on non-eco teams,
  full audit PASS (waste 0.9%, 210 m/s).
- **DeathWalk** (ProposeMex + ProposeMexUp): corridor samples (mid, dest,
  r=900) with known enemy cost above the walker's own metal cost refuse the
  want outright -- apexearth's standing "super risky places are out of the
  question", triggered by a fresh T2 con marching into the enemy army while 4
  home mexes sat unupgraded. Bar is the walker's value; no fixed threshold.
  The roulette made this urgent: risky wants that argmax never picked now get
  drawn, so they must not exist.

Also: nano placement follows metal sinks (live build sites with crews compete
for turrets when the bank is above apex_nano_sink_bank of storage; 5 sink
placements in the seed-11 run), committed separately as e17aef7.

## 2026-08-23: rear specialist PROVEN -- audit passes on both seeds

apexearth: "run it on your own until these features are working and an audit
proves it." tools/audit_role.py rewritten for the market era: seven checks
(elected wire-to-wire, no-army-until-T3, no ground defence with AA exempt,
tech-first, waste <5%, out-eco by RATE, mexups) with void-gates for compile
errors and missing telemetry. The gadget now splits static AA out of
mDefence (vtol-only weapons), and armyReal excludes builders (a decoy
commander read as 770 of army).

The iteration chain, each step measured on 8v8 Supreme Isthmus +100:
danger by GetEnemyCostAt not front geometry (packed-box FrontNear read
structurally true: 8.6k army, 510 defence, teched last) -> nano demand
from BPGap/UnservedLineSpend only, never raw overflow (full-metal stall
bought nanos forever while the T2 lab priced at nothing) -> TECH_PIPE
0.5->1.0 (double-counted the latency discount PipeLatencyMult already
prices) -> overflow escalates a justified tech want (40-metal winds beat
the 3.3k lab bill at argmax for 5 min of full storage; T2 10.9m -> ~3m)
-> line floor: factory orders must beat 25% of the rolling executed-want
value unless overflowing (22 armacks / 1 fusion inversion) -> successor-
first con reclaim (reclaiming the claim fleet pre-T2 starved the ladder)
-> reclaim etiquette (only lesser cons reclaim, air cons exempt, keep 3,
condemned walks to reclaimer) -> factory-assist priority + join-don't-
duplicate >=500m (a joiner doubles speed on the standing frame) -> gantry
want carries the FULL army gap only its products fill (250 m/s, no gantry:
porc+overflow were its only terms) -> quiet rear expands by AIR only,
ground labs retire when an air successor of equal reach stands, first
flying-builder unlock prices at full demand -> danger dwell ~30s (one
plane overflight flipped quiet off and bought dragon claws at 13m) ->
bank past half storage is unserved BP backlog (9.4k banked at 234 m/s
with 30 nanos read "satisfied") -> fighters exempt from the no-army gate,
priced off the unsuppressed air census (his call: "we *do* want fighters").
Shields need enemy within 1800 of the covered core (wealth alone bought
shield stacks). Decoy commanders excluded (armed producible builders).
Eco leash 2500 from home; mex claims past the front refused for everyone.

Final audits: seed 11 PASS (T2 2.7m, 276.7 m/s, waste 0.5%, mT3 7900,
air lab built, zero ground defence), seed 23 PASS (T2 3.0m, 228.4 m/s,
waste 0.3%, mT3 7900, air lab built, zero ground defence). Both with 4
mohos by 15m and the con fleet retiring on schedule (7->1 T1 cons as T2
fleet grows).

## 2026-08-23: rear specialist v3 -- quiet mode redirects, not just suppresses

apexearth's second watch (role confirmed ON in the log): still too many T1
cons, one T2 con walking to frontline mexes, army trickling, "loads of
defence buildings -- none of which we needed." v3, all in the market:
(1) GENERAL rule, his words "super risky places are out of the question":
any claim past the front is refused for every instance, and the refusal also
clears `gMexOpen` so the market stops hiring cons for ground nobody holds.
(2) The quiet rear (elected + no known front within `apex_eco_safe_r`)
claims nothing meaningfully closer to the enemy than its own base depth
(`apex_eco_reach_frac` 0.7, mirror-reference so it works pre-contact) --
this is what was hiring the T1 con flood and walking the T2 con forward.
(3) Quiet rear skips ALL ground defense (v2's home-distance check was
defeated by per-site exposed-mex wants). (4) No army below the cheapest
gantry-tier assault (`apex_eco_army_min_m` 1550-derived) until T3-grade
units exist; a known front inside the safe radius restores every normal
response including full stake. (5) Surplus-con reclaim: quiet rear with no
claimable safe ground and no BP deficit reclaims its cheapest
factory-remakable con (never the commander), self-balancing on BPGap.
T2-con/mexup scarcity (his "teams have T2 but no mexups") measured team-wide
and filed in ISSUES.md -- separate mechanism, not tuned blind here.

## 2026-08-23: rear specialist v2 -- median election, and the multiplier reaches everything

apexearth watched the 8v8: the presumed eco player still built army and "too
much rezbots", and needed no defense at all. The log showed WHY: nobody had
elected -- the two back corners were 11055 vs 11007 from the enemy reference
(0.4% apart) and the vs-#2 margin can never pass on a two-back-corner map.
Election is now farthest vs the TEAM MEDIAN (his game: 11055 vs ~8973 =
1.23x, clears the 1.15 margin). Three production branches had bypassed the
role multiplier entirely -- the overflow sink (an overflowing eco player
kept army lines running on the sink term), rez bots, and squad support --
all now scaled by it; `apex_eco_army_mul` dropped 0.1 -> 0.03 ("they don't
need to create any army at all"; 3% of a monster late economy is still a
gantry stream). And the safe rear skips ground defense outright when the
front is beyond `apex_eco_safe_r` (2500) of home. Smoke: compile clean,
median logged, no false election on a tight 4v4 box (1.077x < margin).

## 2026-08-23: the rear specialist -- the farthest teammate scales instead of fighting

apexearth's design: in a big team game one player starts obviously farther
from the enemy than everyone else; walking T1/T2 there is waste, compounding
eco there is exponential. Implemented in the market (`EcoRoleActive`,
market.as): homes off the team blackboard, enemy reference = ally centroid
mirrored through map center, rear-most self-elects only with a clear margin
(`apex_eco_rear_margin` 1.15) and 4+ allies. Effects: ArmyTarget x
`apex_eco_army_mul` (0.1, stake shrinks with it) and a cost-weighted quality
bias (x0.1..x5) in the army draw so its late military is gantry/heavy-air,
never spam. Protection untouched. Unit-gifting shelved per apexearth: at +100
"everyone is already faster than those gifted units could even walk"
(`GiveUnits` binding confirmed available if ever wanted). Smoke 4v4 Supreme
Isthmus: election computed on all 4 instances (`apex: rear-elect homes=4`),
rear-most at 1.077x the #2 distance correctly declined the margin.

## 2026-08-23: Grid alignment (Part B) -- the anchor now sits on the engine's build lattice

C++ (vendor d019a05): `SetBaseGrid` rounds the published anchor to 16 elmos;
`SnapToBaseGrid` takes `(def, facing)` and maps its output through the
engine's own center-parity law (`CTerrainManager::Pos2BuildPos`: center at
16k, +8 per axis whose half-footprint is odd, facing swaps xsize/zsize);
`IBuilderTask::Execute` hoists `FindFacing` above the snap and passes both.
Script: `GRID_CELL` 8 -> 16 (state.as), `BAND_BACK[NANO]` 216 -> 224
(grid.as) so the nano band is born on the same lattice as the other bands;
the false CorrectPosition-snaps comment in state.as corrected (it is a
map-bounds clamp).

Measured with the BARAI_POS audit: final built positions ALWAYS satisfy the
engine parity law (0 violations before and after -- the engine enforces it
at ExecuteBuildCmd), so the defect was intent drift, not final-position
parity. Before: anchor 2777,2922 (residue 9,10 mod 16) -- all 956 audited
eco statics in the reference run sat off the anchor's own lattice, i.e. the
engine floor-shifted 100% of grid placements 1-15 elmos relative to the
plan. After: anchor snaps to 2784,2928, published cell=16, intended
positions coincide with the engine lattice by construction (drift 0); smoke
run clean (no compile ERR, no asALREADY_REGISTERED, no crash, mBuiltReal
8140 / 21 mexes / T2 at 8.8 min vs NullAI in 15 min), storages in the farm
landing flush (dz exactly 64 for 8x8 pairs). B2 (tight-then-wide search)
and B3 (defence lattice) not taken up: no measurement demanded them yet --
intent drift from whole-cell occupancy is not observable offline without
extra logging.

## 2026-08-23: Catalog senses -- step 0 of the Brain rebuild (senses only, silence holds)

New def-property bindings on the script `CCircuitDef` (InitScript.cpp):
GetBuildTime/GetBuildSpeed/GetWorkerTime/GetExtractsM/GetUpkeepM/GetUpkeepE/
GetReloadTime/IsWind, plus six values precomputed at def load in
CircuitDef.cpp because the raw UnitDef holds them and CCircuitDef did not:
GetMakeM/GetMakeE (NET generation, make minus upkeep; wind averaged against
the map's (minWind+maxWind)/2 per the pre-strip CEconomyManager recipe, tidal
scaled by map tidal; the engine's own energyconv upkeepE inflation happens
AFTER makeE so converters read their true idle net), GetStoreM/GetStoreE,
and GetConvertCapacity/GetConvertRatio (energyconv_capacity /
energyconv_efficiency custom params, verified in the pinned tree on armmakr:
70 / 0.01429). Script side: `manager/catalog.as` (namespace Catalog) reads
the whole def table once at AiMain -- per-def economics arrays, availability
(maxThisUnit>0, deliberately NOT IsAvailable(frame): that folds in
behaviour.json "since" clocks, and ai.frame is -2 at AiMain), and the
who-builds-what graph both directions (builders x defs CanBuild; 580 defs,
2981 edges on Supreme Isthmus). Pure data + accessors (CheapestBuilderOf,
BuildSecondsAt, ConvertMakeM); nothing decides or enqueues. Dump behind
`apex_catalog_dump` (default 0), one line per available def;
`tools/check_catalog.py` diffs the dump against the pinned tree for 15
well-known defs -- PASS on all 15 (armlwall was tried and correctly absent:
it is Scavengers-only, engine-restricted to maxThisUnit 0). Silence
re-verified on the same smoke: apex allBuilt = armcom only, facCount 0, no
compile ERR, no asALREADY_REGISTERED; check.py spend census clean.

## 2026-08-23: THE C++ STRIP -- the DLL originates no economy/build decisions

The engine-side half of the overhaul kill (docs/20-brain-overhaul.md par.1,
"Engine-side leaf logic to sever"): the inherited CircuitAI DLL's own
spenders are cut at their decision entry points, so the silence no longer
depends on script stubs returning null. Neutered (early-return, bookkeeping
and bindings kept): `CBuilderManager::DefaultMakeTask` (a builder the Brain
has no task for idles visibly); `CEconomyManager`'s whole native economy --
`MakeEconomyTasks`, `UpdateMetalTasks`, `UpdateEnergyTasks` (was already
dead), `UpdateGeoTasks`, `UpdateReclaimTasks`, `UpdateFactoryTasks`,
`UpdateStorageTasks`, `CheckAssistRequired`, `CheckAirpadRequired`,
`CheckMobileAssistRequired`, `StartFactoryJob` (unschedules itself and never
starts the recurring native factory job), `ReclaimOldConvert`/
`ReclaimOldEnergy` (auto-melt of own eco buildings is a Brain decision);
`CFactoryManager::DefaultGetFactoryToBuild` (returns null),
`CreateFactoryTask`'s native recruit (response.json BUILDPOWER/FIREPOWER --
the last army leak's source; the factory now Waits), and the Watchdog's
factory-recovery enqueue; `CMilitaryManager::DefaultMakeDefence`,
`DefaultMakeSensors`, and `MakeBaseDefence` (the behaviour-config base-
defence drip that `UpdateDefence` fed to builders outside `AiMakeDefence` --
the previously unattributed defence trickle); `IBuilderTask::ExecuteChain`
(build_chain hubs). Kept as execution plumbing: `EnqueueMexAt`/`EnqueueGeoAt`
and every TaskB/TaskS binding (script executors), nano `CreateAssistTask`
(assist/repair of ordered work), repair-on-damage handlers, the facqueue
line mechanics, and all military task logic. All AngelScript bindings remain
registered; `DefaultMakeTask`/`DefaultGetFactoryToBuild`/`DefaultMakeDefence`/
`DefaultMakeSensors` are now registered no-ops.

Smoke (8-minute 8v8 vs BARb stable hard, Supreme Isthmus, +100, seed 3):
no crash, no asALREADY_REGISTERED, zero compile ERR, apex alive (1,548
`apex:` lines); every apex team `allBuilt=armcom:2700` only, facCount 0,
mex 0; every BARb team built normally (4.9-6.4k metal, labs, mexes, units)
-- the engine's own DLL untouched. NOTE: the DLL is host-side in multiplayer;
the desync-check applies before hosted play.

## 2026-08-22: THE OVERHAUL KILL -- all leaf build/production logic removed

Steps 3-4 of docs/20-brain-overhaul.md. Every AngelScript spending path is
gone: the builder ladder is now holds -> `Brain::Decide` -> idle with the
`DefaultMakeTask` fall-through severed (`Decide` returns null -- an empty
market awaiting the rebuild); the facqueue keeps only its line MECHANICS
(adoption, Wait-hold, recruit abort, driven-line sweep, sent-ledger) and lays
no orders; factory choice/switch are stubbed at the engine hooks (a MISSING
`AiGetFactoryToBuild` would fall back to the DLL's native chooser, so the
stubs must exist); `AiMakeDefence` is a NoteSite-only stub for the same
reason. 37 rule files deleted (~13,600 lines: statics, mexguard, fusion,
converter, nano, crews, obsolete/lab-eaters, digin/fortify, openers, quota/
mix/choose/switch, rush/eco-lead roles, nukes director, assist/parking);
build_chain hubs and response.json emptied; factory.json left structural
(the factory manager's identity/tier tables -- weights inert). Kept per par.2:
senses (frontline, stance, territory, budget ledger, BP measurement,
fusion/home/commander latches), Requests plumbing (`Take` now has ZERO
callers), placement helpers, rez-bot unit thoughts, and the whole military
USE layer. Census enforced: `tools/check.py` now fails on any
`Enqueue(TaskB::`/`Requests::Take(`/`DefaultMakeTask`/`DefaultMakeDefence`
call site outside the allowlisted executor files.

Silence verified twice (8-minute 8v8 vs BARb hard, Supreme Isthmus, +100):
zero compile errors by the unanchored ERR grep, apex alive (1,55x `apex:`
lines of pure sense/military logging), and every apex team ended with
`allBuilt = armcom:2700` only -- facCount 0, mex 0, commBuild 0, commIdle
957 samples, all income overflowed. The commander and cons idle visibly;
nothing is produced. Rebuild proceeds Want-by-Want per par.7 after the
architecture session.

## 2026-08-22: Role policy layer + the build-power controller

`manager/role.as` (new): the eco/tech role's ~25 scattered `IsEcoLead` leaf
gates collapse into one policy object -- `Role::ArmyMult(fac)` (mix, core
floors and spam stream all read it, so new army channels inherit the role by
construction), `DefenceAllowed()`, `ConCap()`, `T2EnergyBar()`, `FusionBar()`,
`GiftsCons()`, `NanoWant()`/`BPExcess()` -- resolved once per AiUpdate ahead
of the facqueue. Mechanical migration measured behavior-identical on the
seed-47 +100 audit before any behavior change.

THE BUILD-POWER CONTROLLER (apexearth's design: "enough build power to use
the metal and not overflow, but not so much that you far exceed income...
The code should find that balance. It is not the sort of thing you can
hard-code"): standing lathe measured in metal/s (per-class physics weights
off the DRAIN=7 convention; swap to GetBuildSpeed reads at the next DLL
rebuild), target = income x `apex_bp_headroom` (1.15). Deficit buys nanos
(pre-T2 unlock: the phase>=4 lock on EcoNano was WHY the role overflowed
early) and licenses con growth post-T2; excess arms the land-con trim.
Two calibration lessons, both measured on seed-47 +100 and now enforced in
code: (1) the COMMANDER is not counted -- its 23 m/s of lathe exceeds
income x headroom for the opening and froze all con growth (holder #7 eco);
(2) the nano lane must never outrank the ENERGY ladder pre-T2 -- ungated it
bought 7 nanos while eInc never reached the T2 bar (tech never started).
Cons are unbounded pre-T2 (his call: "bots are the most cost efficient" --
they are income producers there, not parked lathes).

Also: `apex_role_fus_frac` (0.6 x the fusion-prefer bar for the role),
`apex_role_t2_energy` 450 tried and measured worse (tech 8.4 vs 6.8/7.0 --
a lab on a thin grid E-stalls its mohos; 600 stands), and the T2-LAB EAT:
once the adv-con fleet is complete, gifts settled, both fusions stand AND
free storage covers the burst (his overflow rule), the ground adv plants are
reclaimed (~2,900 metal) with a latch so the tech logic cannot re-buy them
unless the con fleet halves. Audit: `early-waste` (<=2% cumulative at 16m)
and `build-power-8m` (>=2 nanos) added to tools/audit_role.py; both hold
green across every run since the controller landed.

CAVEAT recorded the hard way: seed-47 tech times read 6.8, 7.0, 8.4, never,
14.0 across five near-identical builds -- single-run cycles are inside the
noise floor, and the last three tuning decisions above were re-validated on
a 5-seed batch rather than one game. `two-fusions-10m` remains the open
rule: fusions land ~10.9-13.7 on good runs; the tech-earlier lever is
measured dead, the lab->adv-con->fusion compression is the live one.

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


## 2026-08-22: dashboard tunable overrides actually reach the game

The Tunables tab was only a browser of tunables.as defaults; apexearth set
apex_chain_builds=1 there and launched, and the value never reached the
game. Each tunable row now has a persisted override input; every launch AND
tournament from the dashboard appends each non-blank override as
--modoption (build_tournament_cmd previously dropped modoptions ENTIRELY --
no dashboard tournament has ever carried a tunable). Free-text Modoptions
wins on collisions; the Launch tab shows the active overrides before
launching; names dev_tunables.lua will not republish are flagged red.
UI-only change.

## 2026-08-22: shift-queue chain builds -- built, measured, defaulted OFF

apexearth: "queue up our next build item while we're already building."
Built as a DLL binding (`CmdBuildQueuedAt`, SHIFT-appended mobile build) +
a first-position ladder rule that chains 2 extra cheap ENERGY/CONVERT
builds behind a started one and holds the builder while the engine walks
the queue. First cut wedged builders on stuck orders (side economy HALVED,
seed-37) -- the hold is now time-bounded (15s window + 90s hard ceiling).
Fixed version paired-measured on seed 37: chains-off control out-ecoed all
three chains-on runs (46.1k vs 32.4-40.3k holder metal; tech 6.5m vs
7.6-15.5m) -- ring-picked sites and election holds cost more than the
think-gaps saved. apex_chain_builds default 0; binding and rule kept for a
placement-aware retry. The felt "delays between buildings" remain real;
the parked-assist ISSUES entry is the open suspect.

## 2026-08-22: the eco/tech role announces itself, techs through ground

DLL binding `ai.SendChat` (Game::SendTextMessage, same call as BARb's
welcome line): the role holder says "I am the eco/tech player this game
(team N)" in chat at the anchor latch -- apexearth watched three games
unable to tell which color held the role (he was watching dark green;
the holder was cyan, and behaving). And the role techs through a GROUND
advanced plant even when its remembered T1 lab is air: an air T2 cannot
build the T2 constructors the sling payments bought (watched: T2 via air
lab at 14m, gift chain starved).

## 2026-08-22: the eco/tech role -- one player plays tech like a human

apexearth's spec, built and audit-verified over ~10 validation runs on
Supreme Isthmus +100: in big team games ONE player (the back-most, latched
at frame ~0 via published home->enemy distances -- `EcoAnchorTeamId`,
`mexhold.as`) plays TECH: no army of any tier, no static defence, all metal
into economy, T2 lab rushed, both T1 labs eaten at the T2 plant, T1 rebuilt
only after the second fusion, T2 constructors gifted to every teammate (who
pay ~450 via the sling), heavy build power at surplus.

Mechanisms, each with a tunable: army mix + T1/T2 core floors + spam stream
all behind one predicate (`EcoRoleArmyOff`, facqueue -- three channels each
leaked a different unit before it existed: six Pawns from the core floor,
twenty Tumbleweeds/pass from the spam stream resolving armvader as the T2
lab's fodder); defence refused at Requests::Take AND AiMakeDefence (sensors
exempt); election seeds slot 0 with the anchor unconditionally (qualifying
on readiness let a faster teammate take the designation and block the
anchor's own T2 -- measured 14.2m vs 6.7m); T2ArmyReady waived and a
role-specific 600 e/s energy bar (`apex_role_t2_energy`; the 1200 lead bar
cost 9 minutes); gift keep-floor drops to 1 while teammates lack cons
(income-scaled floor delivered the first gift at minute 18); pre-T2 con
want bounded at one per 7 m/s steady income; NanoCap waived at real
surplus. Tunables: apex_role_tech_t1/t2/t3/air, apex_role_tech_def,
apex_role_gift_keep, apex_role_t1_refac, apex_role_con_per,
apex_role_t2_energy. `tools/audit_role.py <match>` audits the role against
the spec (holder, stickiness, gift timing, purity, eco rank, health).

Best audited run: role active 0.6m, sticky, teched first at 6.7m, advanced
fusion, all 7 paid + all 7 gifted, holder #1 in metal at 1.58x teammate
mean. Residual leaks (~1k metal/game): engine raid-response recruits
slipping the facqueue abort (ISSUES), and a small defence trickle pending
attribution. Benchmark income cannot validate the gift-before-10m bar; the
+100 handicap runs can and nearly do (first gift ~10.5m; bound by T2 lab
timing + con build rate).

## 2026-08-22: squads coordinate -- the engage decision counts allies

C++ (DLL), `CAttackTask::FindTarget`. The engage question was answered per
squad with only its own power: a mixed force the SQUAD_SPEED_RATIO split
keeps in 2+ tasks answered it 2+ times, so half a 2000-metal army parked at
the enemy base dived while the other half failed the same odds test and
walked off (apexearth: "1000 of that metal worth of army will attack and the
other half will go walk somewhere else"). lastRefused had already measured
the shape: median refusal at 0.82 of needed power -- fights one partner
would win.

Now each pass collects the other ATTACK/DEFEND squads once, and (1) the
group-level weakness gate tests `maxPower + groupAlly`, where an ally counts
if it is within `apex_support_radius` (default ASSIGN_RADIUS 3000, the same
distance the merge budget treats as joinable) of us, standing on the group,
or already attacking it; (2) the near-target army test uses the same ally
set (it previously counted only allies already within 800 of the target, so
squads massed BESIDE us counted for nothing); (3) a group an ally already
attacks gets `apex_ally_converge` (2x) preference in the distance metric, so
co-located squads elect the same fight and converge instead of scattering.
No forced merging -- the 1.5 speed split stands; squads move separately and
decide together. Master gate stays `apex_ally_aggregate`; the engage log
gained `ally=`. Built, deployed (local build), smoke-gated clean; mirror
synced, cumulative patch regenerated. Not yet measured against a control.

Second pass same day: a 30-min 4v4 watch game held ZERO `apex: engage`
lines -- the army spends these games in DEFEND-promote pools
(base-contested/conservative-stance hold them at MELEE), so the fights run
through `CDefendTask::FindTarget`, not CAttackTask. The same ally term went
into the defend odds test (`checkPower + allyPower <= eThreat` refuses):
there an ally counts ONLY when standing within `apex_support_radius` of the
ENEMY -- support that can actually reach that fight -- so a lone fresh unit
at home cannot borrow the strength of an army on the far side of the base
(the 1.2x home-odds fragment fix stays intact).

## 2026-08-22: T1 army keeps producing until the T2 army actually exists

`facqueue.as`: `t1MixRetired` -- the switch that zeroes a T1 line's army mix
once T2 stands -- fired on `CleanupMode()`, which is income >= 200 m/s. On a
bonused economy that lands exactly at the T2 transition: the T2 lab is still
making cons, the T1 line goes silent, and nobody makes army at the most
sensitive moment of the game (apexearth: "If we don't have any substantial
T2 army yet then let's keep making T1"). Income is no longer a reason:
t1MixRetired now fires only on `Perf::GameLagging()` (sim health, not
policy), and the handoff belongs entirely to `TierShare`, which phases T1
down as the FIELDED T2 core (income / apex_t2_core_per_income, min
apex_t2_core_min) fills, bottoming at `apex_quota_t1_after_t2` (0.25).
Deployed, compile-gated clean. Not yet measured.

## 2026-08-22: working commander no longer chases everything he can see

C++ (DLL). `IBuilderTask::AssignTo` and builder `CPatrolTask` armed the
commander's `CDGunAction` at `max(dgunRange, LOS radius)` -- LOS (~700) dwarfs
D-gun reach, so any enemy in sight drew a queue-replacing DGun order that
walked him after it and dropped what he was building (apexearth: "commanders
sometimes get distracted by enemy units, chase after them a moment, then
forget what they were originally doing"). Both sites now arm at plain
`GetDGunRange()`, the same shape RetreatTask already used (0.9x): the D-gun
answers only what is on top of him, his regular gun handles close raiders, and
minor threats are ignored -- his direction. Fighter tasks keep the wide
radius; a commander sent to FIGHT should still hunt. Built, deployed
(local build), smoke-gated clean; mirror synced and 0003-cumulative.patch
regenerated. Not yet measured against a control.

## 2026-08-22: mex sentries -- crew rung wired, orphaned cheap towers adoptable

Two wiring bugs behind "apex_mex_sentry is not always working" (apexearth:
satellite expansions -- a couple of mexes and solars -- left with zero defence
and lost to one or two raiders).

1. **The metal crew never asked for the underfoot sentry.** `MetalCrewTask`
   sits above the shared ladder's three `CommanderMexGuard` passes and its own
   mini-ladder went hold -> converter -> next mex, so every crew-built
   extractor was walked away from bare. The `lightOnly` pass was written for
   exactly this crew (its comment names it) and had zero callers. Wired in as
   a rung after the crew's hold, before the next-mex claim: light tower only,
   self-limiting (one per bare mex, covered mexes skipped).
2. **A cheap defence order, once abandoned, blocked its own ground forever.**
   `Requests::Take`'s cover branch only handed back an existing task when
   `want.costM >= JOIN_MIN_COST` (200), so an llt (85) or beamer (190) whose
   builder was pulled away could never be re-manned -- every re-ask was
   refused as "covered" (measured 20260822-190301: 24 defence requests
   created, 3 finished, live=14 orphans, covered=37). Now an UNMANNED cover
   task is handed to the asker at any cost ("adopt-orphan" in the request
   log); JOIN_MIN_COST still bounds joining a manned site.

Smoke-gated clean (no compile errors, adopt-orphan observed firing). NOT yet
measured against a control -- single 12-min seeds are inside the noise floor,
and the residual late-sentry trace points at the commander D-gun chase
(ISSUES entry of the same date) abandoning the frames this fix now recovers.

## 2026-08-22: dashboard launch panel picks factions per side

`tools/dashboard.py` / `dashboard_ui.html`: per-side faction pickers
(Random/Armada/Cortex/Legion, default Random) for both match and tournament
launches, riding the existing `--sides` flag. `run_match.py` now accepts
`random` as an individual `--sides` entry (per-player draw from the run seed,
so the same seed replays the same factions); a side that can draw Legion still
enables `experimentallegionfaction`. Both pickers at Random omits `--sides`
entirely, byte-identical to the previous default launch. `--per-side N`
applies the picked faction to all N players of that side. Verified by
exercising the script/command builders directly; no matches run.

## 2026-08-22: dodge fire -- units sidestep incoming shots

C++ (DLL). `IFighterTask::DodgeFire`, called from `OnUnitDamaged` before any
retreat question: a unit that takes a hit and stays in the fight moves one
short step perpendicular to the incoming fire (the engine's `UnitDamaged`
`dir`, or the attacker's actual position when known), so slow projectiles --
the rocket volleys apexearth watched kill stationary rocket bots -- land on
where it was. Side alternates by unit id (a squad splits, not shuffles);
distance = own speed x `apex_dodge_sec` (0.75s), so slow units barely move;
per-unit cooldown `apex_dodge_cd` (2s); gate `apex_dodge` (default on); the
move carries a 2s timeout and the forced task update re-engages. Fires on
damage taken, not on projectiles in flight -- the AI callback cannot see
projectiles. Dodges mark as `DODGE` pings. Smoke-gated clean; not yet
measured for cost (a jink trades a moment of stationary DPS for the misses).

## 2026-08-22: brain roulette is no longer optional

`apex_brain_roulette` removed at apexearth's direction ("that should just be
a standard feature"): the score-proportional draw in `brain.as` is now
unconditional, `TUNE_BRAIN_ROULETTE` and the gadget entry deleted. The
argmax path is gone.

## 2026-08-22: intent pings rewritten (dedupe + reasons), and the breach SPLIT

Both C++ (DLL), landed together; the pings shipped and smoke-gated first.

**Intent pings** (`apex_ping=1` only, off in MP). `IUnitTask::IntentPing`
draws one mark per CHANGE of intent -- same message near the last mark is
silent, the previous mark is erased -- replacing the per-re-path "DEF march
n=1" spam apexearth reported as "the pings often seem useless". Every mover
now explains itself: DEF chase carries the target name plus which clause
elected it (`atUs`/`post`) and the threat it was priced at (attribution for
the army-chases-one-unit issue, see ISSUES.md); the DEF U-turn carries why
the election emptied (`tgt hid`/`small fry`/`outgunned`/`no enemy`); ATK
names targets, flanks, press/re-front/home; RET says heal vs home; RAID says
target/press/outgunned/roam; script-side withdraw pings leash/recall/odds.

**SPLIT** (`apex_army_split`, default 1): in `UpdateDefenceTasks`, a loss
hot-spot on our own ground whose live enemy-group influence exceeds what the
defend pools already assigned can answer peels a slice out of the biggest
ATTACK squad -- fastest units first, sized demand x `apex_split_margin`
(1.3) -- into a fresh CDefendTask anchored on the breach, promote held
`apex_split_hold` (40s) so it cannot dissolve back into ATTACK before
arriving. Only fires when the squad is over `apex_split_min_dist` (1600)
away; cooldown `apex_split_cd` (30s). apexearth: "There'll be an army
killing our base and our army is off fighting some other army, winning that
fight, but our base is dead." Not yet measured beyond the smoke gate; judge
on watched games + composition, and grep `apex: SPLIT` for firings.

Two same-day refinements, both apexearth's rules verbatim:
- **Chase gate 0.15 -> 0.5, home ring exempt** ("armies generally ignore
  enemies that are less than half their strength unless we need to defend
  the home base"): `apex_chase_min_ratio` default raised in
  `CDefendTask::FindTarget`; enemies inside `GetBaseDefRange` of home and
  anything in contact (atUs) are still always electable.
- **Standing guns count against the split demand** ("if the base has enough
  defenses to handle what's attacking it then we don't need to send our
  army"): finished, non-AA armed statics within 800 of the breach subtract
  their power before the peel is sized -- a porc'd base absorbs a raid
  without pulling the army at all.

## 2026-08-21: ALTAIR chapter 4 -- campaign conclusions after 13 hypotheses

- 2v2 shares the signature exactly (0-12, trades 0.36): the weakness is the
  map's combat regime, not scale. Solving 1v1 solves the ladder.
- H13 arty retest (justified by new evidence: the wall named, hot-lane +
  aggregation infrastructure in place): NULL AGAIN -- the 0.06/0.08 weights
  field ONE Wolverine (170 metal); a counter-siege is a behavior, not a
  ratio. Weights reverted; do not re-propose as a ratio nudge.
CONCLUSIONS. Kept from the campaign: fence DEPTH, HOT-LANE fencing, ally
AGGREGATION (all mechanism-true generally). Confirmed load-bearing by
removal: the T2 safety veto, the coverage caution. The two REQUIRED BUILDS
the evidence names: (1) TERRAIN-AWARE STANDOFF -- overlays-off was the best
trade arm (0.45 vs 0.26-0.42), our flat-geometry standoff holds ground
where the target is unhittable on ramp/ridge maps; (2) COUNTER-SIEGE -- the
enemy creep wall advances monotonically and is never treated as a target
class (needs massed arty behind our line, or committed wall-breaking).
Neither is a knob. The watched-game request to apexearth stands.

## 2026-08-21: ALTAIR chapter 3 -- the geometry named, the micro implicated, the wall stands

SPATIAL RECONSTRUCTION (BARAI_POS, 3 losses, coordinates in the agent
report): stock porc-creeps ONE lane at 150-250 elmos/min behind an
LLT->Punisher/HLT/Maw wall (24 towers, fusions behind), reaching our base
by ~26m; our deaths scatter across ALL THREE crossings; our 3-9 towers
cluster in the NORTH CORNER (base-band axis artifact); 75% of our mobile
metal died at home. The one near-draw had forward, spread towers.
- H11 HOT-LANE FENCING (kept, brain.as): stretch selection ranks enemy
  presence above least-covered -- towers mass on the pressed lane.
  Geometry moved decisively (home-death share 75% -> 23%) -- W/L 0-11.
  Containment broken, fights lost forward instead.
- H12 combat overlays OFF (los_standoff, range_mod, fragility, withdraw):
  kill/loss 0.45, BEST of any Altair arm (from 0.26-0.42) -- our micro
  costs real trades on this terrain map -- but still under half, 2-8.
INVARIANT after 12 hypotheses: the trade deficit vs stock's creep-wall
composition survives every posture, budget, tech timing, geometry and
micro configuration. The remaining axis is COMPOSITION vs the wall
(their corgol+porc; our thud-mix has no answer that outranges it) and
TERRAIN-AWARE standoff (stand only where the target is hittable) -- both
are builds, not knobs. 2v2 baseline running (the team machinery may not
share the 1v1 weakness). NEXT per house rule: a watched game -- twelve
remote hypotheses is the point where his eyes beat the thirteenth.

## 2026-08-21: ALTAIR CAMPAIGN chapter 2 -- knob-space exhausted, the failure is structural

- H6 ally aggregation (C++, SquadTask squadOverwhelms + AttackTask
  nearMargin): co-located ATTACK/DEFEND squads count as their joint force
  (apex_ally_aggregate, default on). Trades climbed 0.26->0.38->0.42 across
  the stack. KEPT (mechanism-true everywhere, not just Altair).
- H7 tech-race posture (army share 1): REFUTED and revealing -- fusion metal
  ZERO; the fusion pipeline is income-gated, not budget-driven, so freed
  metal had nowhere to go.
- H8 scarcity thresholds (fusion bar 12): STILL blocked -- the cascade roots
  at the T2 ENERGY bar (400-800 e/s), unreachable at Altair's ~200-300;
  measured income 14-17 m/s at minute 15 with `asked=0` and energy WASTING.
- H9 energy gate off (+metal 10, fusion 10): the one strong arm -- 4 wins,
  kill/loss 0.61, fusions exist. REPLICATE: 1-12, 0.26, fusions 0 -- the win
  signal was noise; pooled H9-config 5-19/32.
- H10 tech-safety veto off: REFUTED HARD (2-12, 0.28) -- the LosingGround/
  BaseContested veto on the T2 commit is load-bearing; teching through
  pressure collapses. apex_t2_safety stays default 1.
Ten hypotheses: every mechanism metric improved (defence 0.38->0.62, trades
0.26->0.42, depth exists, fusions possible), W/L never left the noise band.
Conclusion: the Altair failure is STRUCTURAL/SPATIAL -- a geometry
reconstruction from BARAI_POS snapshots is running (do we split lanes while
stock masses one; does stock porc-creep the choke unanswered; are we
contained). The threat-blind middle-lane pathing remains the standing
unaddressed suspect.

## 2026-08-21: THE ALTAIR CAMPAIGN (goal: 60%+), and 248 dead modoption knobs found

Goal-driven hypothesis chain on the one map every fix bounced off (15%
pooled, n=48). Map-paired discriminants (Altair vs Comet, same arms):
conT1 6 vs 16.5, defence spend 0.35x stock, kill/loss 0.31 vs 0.79,
commander idle 40%, tech 19m -- a constructor/defence famine loop.
- H1 allowance gate 3x: REFUTED, 0-10, spend frozen 0.38 -- gate not binding.
- H2 budget share 3x: REFUTED, 0-12, spend frozen again -- because...
- H3 the model cannot buy DEPTH: found in source -- the fence want's value
  is `uncovered * ...`, zero at full coverage, so both knobs were
  structurally inert. Fix: coverage saturation converts the want to
  THICKENING at the least-covered stretch (picker already prefers
  chokepoints) valued by the UNSPENT defence share (apex_fence_depth 0.5)
  -- the budget knob finally governs depth. First arm: first 2 Altair wins
  of the campaign, +1000 defence metal, but orders still ~4/game -- capped
  by the con famine itself (6 cons cannot issue more builds).
- H5 (running): break the famine circle at the constructor floor
  (apex_t1_core_min=10 + share 6 + depth).

INFRASTRUCTURE: H5's first arm was INVALID -- apex_t1_core_min was not in
dev_tunables.lua's NAMES list, the third silent-dead-modoption incident.
Swept the whole class: 248 OF 462 GetTunable names were unpublished (every
A/B that used one tested nothing). The gadget now carries all 462, synced
mechanically from the actual GetTunable calls in script+cpp. Any past arm
whose modoption is on the missing list is suspect.

## 2026-08-21: watched-game batch -- trees, the abandoned mex, the frozen commander

Three live reports, one session:
- TREES AT FULL ENERGY, twice reported: first the area-sweep fix (a con sent
  for one metal rock vacuumed every tree in the 320-elmo circle; the circle
  tightens to the wreck's footprint while energy is full), then his
  categorical rule when trees persisted: constructors are OUT of the
  energy-reclaim business entirely (C++ UpdateReclaimTasks; the 20%-bank
  gate still let them graze on every dip). Rezbots keep the full feature
  set. apex_con_energy_reclaim=1 restores the old gate.
- THE ABANDONED FRESH MEX: the guard rule existed but PassingMex outranked
  it -- the commander claimed the next mex and walked away from a radar
  contact standing over the one he just built. A THREATENED bare mex now
  jumps the queue: CommanderMexGuard's urgent pass (enemy visible within
  the 500-elmo ring) sits above the next-mex claim; peaceful ground keeps
  the old order.
- THE FROZEN COMMANDER: the ladder's panic-solar was unreachable mid-build
  (a commander in build range holds its task; a stalled builder parks on
  WAIT). The watchdog sampler now places the solar directly and the held
  nanoframe returns via the normal re-offer. FIRST CUT TOO TWITCHY: 8
  fires/game on opening blips, arm 6-11 (day's worst) -- now it never
  interrupts a FACTORY build and requires an 8s persistent stall.

Also: the comm-panic arm extended the soft-arm run to three since the
eco/spam/mexup batch (6-8, 6-9, 6-11) -- if the calmed batch stays soft,
the eco batch is the isolation target. The SENTINEL entry above carries
the observer whose thoughts now watch all of this.

## 2026-08-21: THE SENTINEL -- the brain checks its own concepts, out loud (his design)

apexearth: "Our brain needs to be smart enough to know all these concepts
and prioritize them... report in the log our brain thoughts and assertions
... the guard that helps us tweak/tune the proper behavior in all our 'leaf
logic'." Built as manager/brain/sentinel.as: every 45s, seven named checks
each log a verdict with the numbers that produced it --
  energy (income vs the 12:1 lead) / metal (GROWTH over a 3m window) /
  army (spend share vs budget target; standing vs enemy seen-peak) /
  spam (standing fodder vs the stream want) / labs (T1 count vs the
  one-until-reactor policy) / fusion (age of an unbuilt ask) /
  recall (losses at home or enemy influence ON home, with the lane forward)
plus one "thoughts ok:" line so silence is never ambiguous. OBSERVER-FIRST
by design: each concern line names the leaf logic responsible; enforcement
is earned per-check (the 2026-08-01 twelve-silent-rules lesson). Tunable
apex_brain_thoughts. First live sessions already earned their keep by
flagging TWO false positives in the sentinel itself, both fixed same hour:
the energy check judged the opening by an established-economy ratio, and
recall trusted BaseContested, which reads negative on a 90-second-old base
(now: real losses at home, or enemy influence physically on it).
grep "apex: thought" is now the AI's own self-assessment.

Also this block: the eco/spam/mexup batch replicate read 6-9-9, agreeing
with 6-8-10 -- the batch is draw-leaning on the BENCHMARK (thin economies
feel the moho slowdown; the fusion speed it buys is what hosted games
need). Isolation levers per member are in place if a measurement is wanted.

## 2026-08-21: home odds 1.2x, escort standoff, spam stream, eco scaling, mexup cap

HOME ODDS (his number): the defend home-fight allowance 4x -> 1.2x
(apex_defend_home_odds), and the odds test now reads live group influence
(the old threat-map read was ~0, so NOTHING was ever refused -- the
trickle-into-the-grinder was ungated, not mistuned). Refusals fall back to
the defence posts where pools merge and re-elect at 1.2x. Measured:
11W-6L-7D, 64.7% decided -- best arm of the project; Comet 7-0-1 and
Avalanche 3-0-5 UNDEFEATED.

ESCORT STANDOFF: weaponless radar/jammer keyed squad row 0 ("stand at your
own range" = stand ON the target), which is why sensors died first. They now
hold behind the squad's longest row on the enemy-away axis
(apex_escort_standoff, 240 past highestRange). Measured on top: 10W-5L-9D,
66.7% decided -- second consecutive best-ever.

SPAM STREAM (his spec, "attack the fog of war"): the no-squad fog-scout
routing existed (IsFodder + SpamPhase per-unit SCOUT tasks); production did
not -- the raider share fades with income so the quota stopped buying ticks
late. A RATIO entry (not a floor: the rez-conveyor lesson) keeps one
standing spam unit per apex_spam_per_income (5 m/s), post-T2, ground lines.
Verified live: armfav quota 4/4 -> 11/11 met.

ALWAYS-ECO actually always: was "at most one eco build at a time"; now one
parallel build per apex_always_eco_per (30 m/s) income, minimum one.

MEXUP CAP (his diagnosis): while the fusion is asked and no reactor stands,
mex upgrades hold at most HALF the adv-con fleet; the refused con falls to
the fusion request. Measured: fusion asked->standing median 2.0 MINUTES
(was ~11 in the documented starvation); cap fired 14 times in 24 games.
The combined arm read 6W-8L-10D (draws up -- watch this; replicate running).

## 2026-08-21: the T2 gate is one pair -- apex_t2_metal (30) + apex_t2_energy; strict post kept; ring -20%

T2 KNOBS: apex_rush_min_metal (14, "Tunable for A/B testing") renamed to
apex_t2_metal at 30 (his number) as the metal half of the T2 permission;
apex_t2_income RETIRED -- it was a second private 30 m/s gate on the same
decision inside the rear plant-siting rule, which now reads Policy::T2Metal()
(two knobs on one decision drift the first time one is tuned).
apex_t2_energy_from's doc now states it is NOT a permission knob (it starts
the pre-T2 energy-floor lane). A/B of the 14->30 bar: 7W-9L-8D, T2 median
18.7m (no later than before -- the 800 e/s energy bar binds first at
benchmark income), no-T2 games 6/24 (normal). Benchmark-neutral; the bar
will bind in richer hosted games, which is the stated intent.

STRICT POST (same arm series): election is post-relative ONLY -- the first
post cut kept proximity-to-squad as self-defense and a won fight advanced
the squad into the next election ("victorious march to death", watched).
Units still auto-fire in weapon range; the task never re-targets off its own
advanced ground. Very-deep defend deaths (>3000): 20% -> 5% across the
campaign; Comet went 5-0-3 then 5-1-2 in the last two arms. Ring shrunk 20%
on his call: base_rad [800,1400] -> [640,1120], defzone pad 500 -> 400.
Altair is 0-5/0-6 in EVERY arm today -- its failure is not these mechanisms.

## 2026-08-21: defence is a post, not a pursuit -- kept (apexearth's design ruling)

apexearth, on the measured 71%-outside-the-ring defend deaths: "How are we
defending outside of our defense zone? That seems like totally inappropriate
logic. if the enemy has fled or left, why are we still attacking them as if
it is defense?" Mechanism found in source: CDefendTask::FindTarget rewrote
`position` (the pool's post) to every elected target, so each chase re-based
the pool on newly-taken ground and the next election reached further --
candidates were accepted relative to the CREPT squad (atUs), never the
assigned post. Defence creep, one fled enemy at a time.

Fix (apex_defend_post, default 1): the anchor never follows the target;
candidates must be within weapon reach of the ASSIGNED post (or on our
defended ground); a unit actively shooting the squad is still fought
wherever it stands; with nothing electable the existing fallback walks the
pool back to a front post.

Validation, fourth arm of the day's series (same benchmark): defend deaths
outside the ring 79% -> 71% -> 65% across the campaign, very-deep share
20% -> 9%, median depth 0.65 -> 0.56 -- monotone improvement on every
mechanism metric. W/L 7-10 (noise band; Altair 0-6 again -- Altair's
problem is not this mechanism). The ~65% still outside is substantially
the LANE force: defend pools posted at front points, legitimately beyond
the base ring. Getting that to zero is the defend/lane split design
question, recorded as open. The muster clamp and solo-deep gate remain as
defense-in-depth beneath this.

## 2026-08-21: the single-unit attack stream -- two-iteration fix, kept (watched-game verdict pending)

apexearth, watching Geyser Plains: "suddenly we just started doing single
unit attacks into the enemy... well outside our base defense range." His
game's transitions table agreed exactly: 73% of combat metal died on DEFEND
at fwd ~0.7, disengaging at 9-15% hp, dead ~1s later.

Iteration 1 (muster clamp, DefendTask Merge/Start): rookies and fresh units
no longer walk solo to an anchor/leader beyond 1.25x the base-defence ring
-- they muster at the lane instead. Validated INSUFFICIENT alone: pooled
defend->retreat share flat (33->35%), median depth 0.65->0.60, W/L 6-10.
Root cause deeper: the manager spawns 1-unit defend pools that chase deep
targets as their own leader.

Iteration 2 (solo-deep gate, DefendTask FindTarget): a pool of ONE may not
elect a target beyond 1.25x the ring -- it fights whatever is on top of it
or inside the ring; travelling deep needs company. Narrow by design (solo
TRAVEL only), unlike the shelved broad engage gate that traded losses for
timeout draws. apex_defend_muster=0 / apex_defend_solo_deep=1 restore old
behavior.

Validation across the three same-day arms: median defend->retreat depth
0.65 -> 0.60 -> 0.57, deep (fwd>0.85) share 20% -> 17% -> 17%, W/L
6-10 -> 9-7 (best recent arm) with NO draw inflation. Direction consistent,
power modest (n=24/arm) -- the acceptance test is whether apexearth still
SEES single-unit streams in a watched game. STILL OPEN, next in queue: the
middle-lane bias (threat-blind approach paths take the direct lane into the
best-defended ground; flanks never considered).

## 2026-08-21: geothermals exist now -- three stacked defects, all fixed and verified

apexearth: "we don't build geo... maybe you can check?" The value ranking was
innocent; three independent defects stacked so geo could NEVER be built:
1. C++: ParseGeoSpots runs ONCE at AI birth and GetFeatures() is LOS-limited
   -- vents outside the start area never became spots, on any map, forever
   (geo-diag: spot=-1 for a whole 30m game on Death Valley with the income
   gate floored). Fix: RescanGeoSpots -- a 120s-throttled per-instance
   feature rescan appends newly-seen vents (lateGeoSpots) without mutating
   the shared CEnergyData other AI threads read; all geo paths (script query,
   EnqueueGeoAt, stock's own geo task) read through GeoSpotPos.
2. Script: EnergyReclaimable's "no successor to wait for" fallthrough classed
   geo reclaimable (cliff fallthrough 0), so EnergyValuePerMetal priced it -1
   ALWAYS -- vent found, value=-1, advsol picked (measured on Geyser Plains).
   Fix: geothermals never obsolete, stated explicitly at the predicate top.
3. Gate: apex_geo_min_income 300 -> 250 e/s (his call, same session), and
   the tunable's doc said metal/s while the code reads ENERGY income.
Verified end-to-end on Geyser Plains BAR v1.2.1 (his suggested vent-rich
map): three "home energy armgeo geo spot=N" picks at 16.5-18.5m as energy
income crossed 250-336, geo standing in the final tally, late diag reading
spot=-1 only once every vent was claimed. The geo-diag line (60s throttle)
stays for future attribution. Geo economics: 300 e/s for 560 metal = 0.54
e/s per metal, 2.5x the advanced solar -- the ranking now sees it.

## 2026-08-21: escorts ungated, the T1 cap enforced at the nanoframe, advsols behind the base

Three watched-game reports, each attributed and fixed the same day:

ESCORTS (radar+jammer): the want was wired twice -- a maketask rule that has
NEVER fired (sits below the driven-line early-return; left as dead code, note
here) and the real quota floor, whose blanket Outmassed gate suppressed it in
301/616 diag samples. apexearth overrode the 2026-08-19 jammer caution
outright: "We need 1 jammer and 1 radar on all the expensive squads... It
allows us to shoot at enemies before they can see us." Gate removed for BOTH
defs. Measured: in every benchmark game where a squad cleared the 2000-metal
bar, exactly 1+1 were built -- the chain works. The live bottleneck is the
bar vs real squad sizes (fragmented squads ~1500 metal; peak qualifying
squads 0 in most 40m benchmark games). apex_escort_squad_value is the knob;
the once-a-minute "apex: escort-diag" line prints squads/outmassed/counts
for attribution in hosted games.

T1 CAP: the gate held but the C++ unattributed entrance built labs without
asking it. Def-pin added in choose.as (gT1Def, with a 20s nothing-backs-it
re-point after the plain pin wedged a smoke opening outright -- zero
factories for 12 minutes; do not re-propose a pin without the escape), plus
nanoframe enforcement in hooks.as (same pattern as the T1-commit reclaim):
a surplus land T1 plant appearing while adv-con/T2-mex/reactor are missing
is reclaimed before metal sinks in. Measured: 2nd ground T1 pre-fusion
2/24 games (metric note: count GROUND labs only -- the air intel plant is
exempt by design and polluted the first read as "21/24").

ADVSOLS: "behind the base" was a radius, not a direction -- a forward panel
within apex_advsol_home_r seeded the pack toward the enemy, and the FIRST
panel skipped the block entirely (count>0 gate). Both fixed: founders route
through the rear band, and a seed forward of the base anchor (Base::Coords
depth < 0) is refused. Benchmark-ambiguous (noise band); acceptance is
watched placement.

All arms in today's noise band (7W-7L to 8W-10L on the 24-game benchmark);
compile gates clean throughout.

## 2026-08-21: lab discipline -- the join bug and the double-T2 transition, fixed (kept)

apexearth, watching (Death Valley, 76 m/s): "3 t1 labs, and 2 t2 labs...
started making the second T2 like 15 minutes in... we wasted too much metal
on labs and still don't have our first fusion." Attributed to two defects
in his game's log:
1. JOIN BUG: the commander's "joining the standing factory request" branch
   passed its OWN preferred lab def to Requests::Take -- the standing request
   was armlab, the "join" created an armvp beside it (same frame in the log:
   join line + "request new armvp"). Fixed: Requests::LiveFactoryDef() looks
   up the def actually asked; joining now joins.
2. DOUBLE-T2: the "first fusion before a second T2 line" rule exists, but
   the plant-ask ledger's phantom fuse cleared armalab's ask during its
   walk-and-place gap, and armavp's query 36s later was approved as another
   "first" T2. Fixed with a def pin (choose.as gT2Def): the transition's
   chosen def rebuilds freely through every recovery path; a DIFFERENT T2
   def is an extra and meets the afus+pulsar+army discipline. A plain
   boolean latch was tried first and MEASURABLY WEDGED TECH (83 stuck-
   reopens, 9 no-T2 games, 5W-13L-6D) -- do not re-propose the boolean form.

Measured (24-game 3-map benchmark): v2 is 7W-7L-10D vs the 11W-8L-5D
control -- within noise, tech health equal (stuck 6 vs 8, T2 median 23.8 vs
20.7). The TARGET failures are rare at benchmark income (double-advanced
1/24 games in BOTH arms; the join bug fires in low-income openings), so the
benchmark can only show no harm -- the benefit case is his watched game
class. Confirm by watching: the opening should build ONE T1 lab, and no
second T2 def before a fusion stands.

STILL OPEN (next single change): the fusion itself -- asked on time at
13.7m, starved on execution for 10+ minutes with advCon=1 while mohos
monopolized the only T2 con (ISSUES.md, candidate: floor the adv-con want
at 2 while a fusion request is standing).

## 2026-08-21: air assassin dominance waiver -- landed, NOT yet exercised (watch for "BACK ON")

The drawn 40m games' finisher analysis (two adversarial agents, cross-
examined): the bombers are the ONLY weapon in the stack that targets the
enemy commander -- the win condition -- and t007 stood them down permanently
at the ABSOLUTE AIR_AA_CEILING (2500) against a beaten enemy we out-armied
12:1. Ground AttackTask has no commander case at all; a freed army shoots
the wall, not the win condition. Fix (wing.as AADominated + update.as
un-latch): the ceiling waives and a latched gAbort clears when the enemy
field army is under apex_air_dominance_army (0.2) of ours AND their AA under
apex_air_dominance_aa (0.15) of ours. A/B ran 8W-8L-8D (within noise of the
10-6-8 control) with ZERO aborts latched in 24 games -- the state is rare;
the change is dormant until it recurs. Verify in any future long draw:
grep "STANDING DOWN" then "BACK ON".

Sibling finding left OPEN (ISSUES.md): late-game squads average 3.2 units
and BOTH C++ engage gates (AttackTask groupWeak/nearMargin, SquadTask
squadOverwhelms) test the lone fragment against the whole porc cluster --
40k mobile metal died killing 3.8k of statics in one draw. Proposed fix
(unbuilt): a nearby-ALLY power sum, symmetric to the enemy-side localInfl
aggregation. Also unbuilt: a corsilo request sat inFlight for 10 minutes
with no builder (silo execution, t007).

## 2026-08-21: commander anti-stall -- tried, measured, DEFAULT OFF (apex_comm_hot_secs)

The t003 stall (commander "leaving" 10+ times over 7 minutes, zero
displacement, retreat destination = the hot base it stood in) got a direct
countermeasure: sustained influence at the commander's own tile with no
displacement forces the steered CmdMoveTo, hp-independent, post-T2
(events.as anti-stall block). A/B vs the flee-85 control (10W-6L-8D):
8W-9L-7D, 77 marches fired, commander-death losses 4/6 -> 7/9 -- the march
fires and the commander dies anyway (or the yanking off tasks hurts).
Default 0; the code and tunable stay for experiments. The stall's ROOT --
RetreatTask's destination being the already-hot base -- remains open in
ISSUES.md.

## 2026-08-21: commander DEAD-MAN arms at 0.85 (was 0.55) -- measured direction-positive, kept

Forensics over 8 com-death 1v1 losses: SLOW EXPOSURE dominates -- the
commander holds a build task at ~100% hp on influence-hot ground for 5-9
minutes, then one volley crosses the soft retreat (0.85) and the DEAD-MAN
(0.55) in 2-10s, faster than either produces movement. Fix: arm the
guaranteed CmdMoveTo at the same 0.85 where the soft retreat already logs.
A/B (modoption, 24-game 3-map benchmark vs the 11W-8L-5D control):
10W-6L-8D, DEAD-MAN fires 51 -> 215, losses ending in commander death
7/8 -> 4/6. Power is modest (n=24, W/L within noise) but the mechanism
metric and the loss count both moved the intended way at near-zero cost
(the trigger still requires influence at the commander's own tile).
STILL OPEN from the same forensics (ISSUES.md): a commander that logs
"leaving" 10+ times over 7 minutes with zero net displacement -- the soft
Retreat() path produces no movement while a RETREAT task is held.

## 2026-08-21: T1 arty reweight -- tried, measured, REVERTED (do not re-propose without new evidence)

Hypothesis (adversarial panel round 4): choke maps are lost for want of
artillery -- corwolv is weighted 0.00 below 25 m/s income in factory.json's
corvp block and legbar 0.00 at every tier, so duel-income games cannot answer
a Punisher wall. Tried corwolv tier0/1 at 0.06/0.08 and a legbar floor.
Measured, same 24-game 3-map benchmark: 7W-10L-7D against 11W-8L-5D without
it, with Altair -- the map it was aimed at -- going 2-5-1 -> 1-5-2. Wolverines
were built (composition confirmed the path fired) and the economy stayed
ahead of stock's; the results still went the wrong way. Reverted whole.
The cross-examination had already weakened the evidence: the zero-arty games
were the SHORT losses, i.e. low income explained by early defeat, not defeat
by missing arty. The Altair discriminator that survives is mT2=0 in 4/5
losses, and the economy tracer cleared expansion (mex parity in 4/5 losses;
ownBuilders collapse and structure deaths say the fights reach the base) --
Altair is a fight-quality problem with no room to absorb it, not a
composition or mex problem.

## 2026-08-21: DefendTask engage gate -- built, measured, DEFAULT OFF (do not re-propose as-is)

Mechanism (real, verified in source): a defend pool's only strength gate is
checkPower*4 <= ThreatMap::GetThreatAt(ePos), and that layer reads ~0 almost
everywhere -- a Punisher wall rates as empty ground; the approach path's
threat cost collapses to distance; one-shot units never trigger the squad
retreat vote (needs WOUNDED voters); Merge/Start send reinforcements solo
CmdMoveTo to the dying leader. The localInfl safety massing.as promises
exists only in CAttackTask.

Fix tried: port the group-influence refusal into CDefendTask::FindTarget
(apex_defend_engage_margin), scoped off atUs/base-ring. Measured on the
24-game 3-map 1v1 benchmark, both margins vs the no-gate arm (11W-8L-5D):
margin 1.0 -> 6W-7L-11D, margin 0.6 -> 8W-7L-9D. The gate converts losses
into timeout draws (draws 5 -> 9-11) without adding wins; finishing is
already the weak axis, so refusal-shaped safety is the wrong currency here.
Kept in the DLL behind the tunable, default 0. The UNTRIED half of the
diagnosis remains open in ISSUES.md: threat-aware approach PATHS and gating
the solo reinforcement trickle, which stop the bleed without forbidding the
fight.

## 2026-08-21: retreat config was rolling a per-game army timidity dice -- fixed, 1v1 benchmark 3W -> 11W

behaviour.json still carried the pre-migration 2-element retreat form
("fighter": [0.50, 1.0], comment "[<default>, <modifier>]"). The current DLL
parses index 0/1 as MIN/MAX (MilitaryManager.cpp:314-317) and rolls ONE
uniform threshold per game: our whole army's retreat point was drawn from
50-100% hp (builders 85-100%), so about half of all games were played by an
army that fled at three-quarters health, back turned, released only at 98%.
Stock's shipped hard profile has the same stale lines, so the roll was
symmetric -- what it explains is not the old losses but this benchmark's
NOISE (unchanged-AI swings): each side flips its own timidity coin per game.
Fix: the 3-element form upstream's hard_aggressive already uses
([0.50, 0.55, 1.0] / [0.80, 0.89, 1.0]).

Measured, 24-game 3-map 1v1 vs BARb:stable:hard, same maps/seeds as the
baseline (tournaments/20260821-012258-1v1-baseline-3maps vs
20260821-*-1v1-retreatfmt-fix): 3W-15L-6D -> 11W-8L-5D. Comet 2-6 -> 6-2,
Avalanche 0-3-5 -> 3-1-4, Altair 2-5-1 (choke map, still losing -- the
DefendTask porc story). Death profile moved the intended way: fight:defend
deaths went from ~0 to a leading bucket (units die fighting, not fleeing).

Found by the adversarial 1v1 panel (retreat-mechanics agent), cross-examined
against the battle-reconstruction agent whose "engagement, not retreat"
verdict also stands: both shared this root cause.

## Change log

Full detail moved to `changes/<date>.md`, one file per day, newest first. This index lists each day's entry titles; open the day file for the mechanism, evidence, and measurement.

Older reference/appendix material with no date of its own (binding tables, config tables, known-not-done lists): `changes/reference.md`.

### 2026-08-14

- 2026-08-14: opening-sequence income gate made economy-only, no time cap
- 2026-08-14: many DIFFERENT sites of the same building opened at once — VERIFIED

Full detail: `changes/2026-08-14.md`

### 2026-08-13

- 2026-08-13/14: the army answers one breach at a time, not all of them at once
- 2026-08-13/14: generator tier selection is one energy-per-metal ranking — VERIFIED
- 2026-08-13: duplicate energy buildings landed on the identical tile — VERIFIED
- 2026-08-13: defence budget is a share of metal, not a count of towers
- 2026-08-13: duplicate energy builds were checked against the wrong position
- 2026-08-13: radar towers were placed only where a wall also went up
- 2026-08-13: the enemy model never forgot, and raids never checked
- 2026-08-13: reactors started in parallel and never finished
- 2026-08-13: the front-hold gate skipped the merge, so the army could never mass
- 2026-08-13: rez bots had a hard cap of 8, and two of them
- 2026-08-13: a rezbot and a con turret fought each other over a windmill forever
- 2026-08-13: a T1 constructor was blocked by a job only a T2 one can do

Full detail: `changes/2026-08-13.md`

### 2026-08-12

- 2026-08-12: ally aid — the signal was already there, the response needs the DLL
- 2026-08-12: Fight is the wrong primitive -- move, and set-target the preference
- 2026-08-12: the standoff was silently reverted by a factory commit, and the ring leaked
- 2026-08-12 (night): five mechanisms, all found by agents from a watched game
- 2026-08-12 (evening): six things apexearth saw in one watched game
- 2026-08-12 (later still): the budget counted solar collectors as defence
- 2026-08-12 (later): the quota was building nothing but constructors, and the benchmark was hiding it
- 2026-08-12: factories run our own standing queue, not one CRecruitTask per unit

Full detail: `changes/2026-08-12.md`

### 2026-08-11

- 2026-08-11: three rules deleted, one real bug fixed, and a pattern banned
- 2026-08-11: the tower blobs were ONE rule, and its throttle was never wired
- 2026-08-11 (corrected): the safe ground exists, and it is EARLY
- 2026-08-11: there is no ground forward that a builder is allowed to work on
- 2026-08-11: WHY the front orders are never filled -- the site search refuses
- 2026-08-11: the front line is aimed correctly and almost never built

Full detail: `changes/2026-08-11.md`

### 2026-08-10

- 2026-08-10: the Brain — rules propose Wants, one ranking decides
- 2026-08-10: where the 1v1 ended up
- 2026-08-10: the 1v1 win rate is 1/66, and the 20-minute cap was hiding it
- 2026-08-10: `hard_aggressive` is a STALE stock profile, and apex was forked from it
- 2026-08-10: the fighter-task C++ delta costs 12 points, and is reverted
- 2026-08-10: apex stands aside when it has no allies, and moves onto the `hard` base
- 2026-08-10 (NEGATIVE): switching the T2 rush off in small teams changes nothing

Full detail: `changes/2026-08-10.md`

### 2026-08-09

- 2026-08-09: Behemoths charge the front instead of walking round the map
- 2026-08-09: units walled in by our own buildings get a way out
- 2026-08-09: the AI desynced multiplayer by asking the engine for a path
- 2026-08-09: the AI crashed the engine because C++ deleted tasks the script held
- 2026-08-09: the front line gets per-player sectors, and defenders stop garrisoning minute 5
- 2026-08-09: a raid that runs out of targets presses on instead of walking home
- 2026-08-09: T3 heavies hold the defence line instead of walking out alone
- 2026-08-09: keep building silos while both banks are over 80%
- 2026-08-09: nuke the army massed on our own border
- 2026-08-09: help the identical building already started, instead of starting a second
- 2026-08-09: mobile AA is all-or-nothing, and it never travels with the army
- 2026-08-09: long guns stand at 90% of their range instead of 40%
- 2026-08-09: The ally-mex upgrade also CLOGGED the mex_up slots — fixed in C++
- 2026-08-09: A crash in AiTaskRemoved — a dangling task handle, not the mex work
- 2026-08-09: Constructors walked into an ally's base to upgrade a mex that was not ours
- 2026-08-09: A mobile radar travels with the army
- 2026-08-09: A defensive posture buys artillery and fodder, not Bulls
- 2026-08-09: Jammers are placed deliberately instead of by chain accident
- 2026-08-09: Pinpointers are capped at three for the whole TEAM
- 2026-08-09: mex defence scales with how close the mex is to the enemy
- 2026-08-09: the AngelScript was split up (pure refactor, no behaviour change)
- 2026-08-09: found while refactoring, NOT fixed
- 2026-08-09: we never attacked, and the group size was the reason
- 2026-08-09: solar was chosen over wind on essentially every map
- 2026-08-09: the T2 rush is a TEAM strategy running in 1v1
- 2026-08-09: every 24-game arm, and what actually survived
- 2026-08-09 (SETTLED): trade caution is HARMFUL at proper sample size
- 2026-08-09: constructors walk the whole map for trees
- 2026-08-09 (CORRECTION): the army-trade metric has a 30% noise floor at n=8
- 2026-08-09: adaptive caution improves the army trade 47%; a blanket bar makes it worse
- 2026-08-09 (CORRECTED): the 25% close-range deficit was contamination
- 2026-08-09 (WITHDRAWN, see above): we lose close-range fights by 25%

Full detail: `changes/2026-08-09.md`

### 2026-08-08

- 2026-08-08: the bank is empty, not full — the fraction-of-storage gates are dead
- 2026-08-08: the gantry cap WAS the T3 constraint
- 2026-08-08: measured -- the six changes are a net win
- 2026-08-08: the constraint is build power, not space
- 2026-08-08: one base layout, replacing position-plus-shake

Full detail: `changes/2026-08-08.md`

### 2026-08-07

- 2026-08-07: naval response was switched off entirely
- 2026-08-07: front vs back, and the front starts UNKNOWN
- 2026-08-07: the front is our own perimeter, not a seam
- 2026-08-07: the front line is not at the chokepoints
- 2026-08-07: BWEM chokepoints exist, and were unreachable
- 2026-08-07: constructors no longer pre-empt themselves into reclaim
- 2026-08-07: RESULTS BELOW WERE VOID -- read this first
- 2026-08-07: the aggression session (RESULTS VOID, SEE ABOVE)
- The metal-full fallback was buying Pit Bulls — 2026-08-07
- Commander idling at a haven patrolled back and forth forever

Full detail: `changes/2026-08-07.md`

### 2026-08-02

- How the AI judges a fight — four defects found 2026-08-02
- Defence towers were always the cheapest one — FIXED, unmeasured
- Rez bots died to all-or-nothing resurrects — FIXED, unmeasured
- Metal converters may be eating the expansion gap — NOT ACTED ON

Full detail: `changes/2026-08-02.md`

### 2026-08-03

- Gating CDefendTask promotion — TRIED, REVERTED 2026-08-03
- Squad join radius 1000 -> 3000 — squad size FIXED, win effect UNPROVEN
- Naval players built no energy at all — 2026-08-03
- Range: no tower we build can answer enemy artillery
- The army loses; the towers do not carry us — measured 2026-08-03
- ENGAGE_MARGIN works at 25 minutes and not at 40
- Reclaim cannot see the bodies

Full detail: `changes/2026-08-03.md`

### 2026-08-06

- Three fixes from one live session — 2026-08-06
- Three more, same session, from watching two windowed games back to back
- The tech-lead election was a one-way trip past 15 minutes

Full detail: `changes/2026-08-06.md`


### 2026-08-21

Tunables audit (git-history-verified per item), all compile-gated clean:

- `factory/buildpower.as` REMOVED — factory build-power requests, apexearth's
  own 2026-08-19 idea, but measured hurting (K/D 0.86 -> 0.48 paired seed),
  default-off since, and its problem statement is now solved by the assist
  path's army-shortfall gate (`apex_assist_army_frac`). Four knobs went with
  it (`fac_demand`, `fac_ask_hold`, `fac_help_mult`, `fac_spare_frac`).
- Jammer gate merged: `apex_jammer_upkeep_margin` deleted;
  `JammersAfforded` no longer grants a free first jammer (`1 + int(...)` ->
  `int(...)`), so the count formula is also the gate. First jammer now needs
  income >= upkeep/share (10x upkeep at the 0.10 default) vs 4x before —
  slightly later on small grids, unchanged at scale.
- `apex_t2_energy_floor` (700) deleted — the pre-T2 energy forecast now
  builds to `apex_t2_energy` (800) itself, so the grid the forecast builds is
  the grid the rush bar demands.
- `apex_reclaim_advsol_e` + `apex_reclaim_wind_e` (both 2000) merged into
  `apex_reclaim_gen_e` — one number in apexearth's own statement
  (">2000 reclaim wind and advanced solar"); wind's map-wind scaling kept.
- Incoming-push DETECTION renamed `apex_push_*` -> `apex_incoming_*`
  (notice_r, cost, closing, danger_pad, danger_cost, answer_frac, stand) —
  the prefix had collided with the team-push family.

KEPT, verified against history (do not re-propose):

- `ArmyPressureMod` is NOT redundant with the budget's `LossArmyMult`/stance
  multipliers: the budget never reaches facqueue army production (targets.as
  2026-08-16 warning), so it is the only adaptive army-count response.
- The three outnumbered predicates (`Outmassed`, `ConservativeStance`,
  `mass_no_commit_ratio`) differ deliberately in ratio, fog policy and
  consumer; fog-flooring `Outmassed` would suppress constructor growth while
  blind, which is the wrong direction for the economy.

### 2026-08-21 (later)

- `apex_rez_per_income` 0.1 -> 0.2 — double the rez fleet, still income-scaled.
- BATTLEFIELD MEDICS (`rules_rezzer.as` RezzerMedic, apexearth request): a
  tunable share of rez bots (`apex_medic_share` 0.4) stays with the army's
  staging anchor — repairs wounded mobiles near it (`apex_medic_r` 1200),
  holds station by area-reclaiming the aftermath there. Flee rule still wins;
  threat at the anchor holds the medic home. Compile-gated clean.
- FORMATION TRAVEL (C++, AttackTask+DefendTask, apexearth: enemy "uses the
  synchronized move speed fight orders... we give spread out move orders"):
  ground squads now travel on CFightAction (CmdFightTo waypoints +
  CmdWantedSpeed at the squad's lowestSpeed) instead of per-unit CMoveAction.
  Previously only SIEGE-attr units (32 defs) fought-travelled. Flyers keep
  MOVE; RaidTask untouched (raiders bypass fights). Wounded pull-back is
  unchanged: RetreatTask swaps the travel act out, which IS dropping the
  fight order; the standoff/kite ring still owns distance in the engagement
  phase. Tunable `apex_fight_travel` (default 1, in dev_tunables.lua) for the
  A/B. NOT yet judged on a watched game.

### 2026-08-21 (watched-opening batch, Altair campaign)

Five watched-game reports, each traced to a mechanism, fixed, and measured on
Altair (16-game arms, apex_share_defence=4, vs BARb stable):

- BASE AXIS 180-FLIP REMOVED (`baseplan/axis.as`): a start near a map edge
  scored the true rear 0 (probe off-map) and the flip then won on any count,
  laying the whole eco band TOWARD the enemy (watched: solars at fwd 0.36-0.39,
  log `axis front=0 kept=44`). Perpendiculars remain the fallback; energy now
  lands home-side (fwd ~0).
- FIRST LAB PLANNED AT HOME (`rules_commander.as`): the factory request used to
  carry the commander's wander position; now `FindBuildSiteNear(home)`. With the
  home-anchored opening-mex bound in `brain.as` (per-jump bound could not stop a
  chain of hops), the lab commit moved from ~1.8-2.3m to 0.7-0.8m and the
  metal-full walk is gone.
- NEAR-PASS MEX SENTRY (`rules_commander.as` nearOnly + maketask slot above
  PassingMex): the mex a builder just finished gets its turret before the
  builder walks away. Sentry #1 now ~2.2-2.5m (was ~6m or never). On Geyser the
  pass correctly declines: the home LLT already covers the start mexes.
- PANIC/WIND MATH + TIDAL (`mexguard.as`): the panic-stall branch hardcoded
  solar and had put 5 panels down on a wind 12-27 map before the ranking ran;
  it now compares EnergyValuePerMetal and takes wind when bank+5s of income
  covers costE. Tidal (armtide/cortide/legtide) enters the T1 ranking on
  water/mixed maps, gated on a placeable site near home.
- RECALL HOME OR COMMIT (`military/withdraw.as`, apex_recall_home/_fwd): while
  BaseUnderAttack() and no killing blow armed, ATTACK/RAID squads past fwd 0.5
  are ordered to gHomePos (not the nearest tower) to mass over the contested
  ground; gKilling still exempts a committed push. Smoke: recall fired 11.4m,
  squads walked home.

Altair 1v1 ladder: baseline 2/16 (12.5%) -> opening fixes 3/16 (18.8%) ->
+recall 5/16 (31.2%, CI includes 50%). H15 wall-arty was a null (2-11): a few
Wolverines do not answer the porc-creep; entry stays until superseded.

Harness note: a 6-worker tournament froze all engines at the same second once
(cause unknown, not RAM); killed and relaunched clean. Watch for repeats.

### 2026-08-21 (evening, live-game batch)

Fixes traced from apexearth's watched/hosted games, each with the measured
mechanism (details in the commit messages 8be6c90..ba85b52):

- Second-T1-lab fork closed at Requests::Take; in-flight factories counted
  as pool + MANNED registry (the engine's held placeholder wedged the
  opening when counted -- facCount=0 at 10m until Workers()>0 separated it).
- Commander: stuck-breaker decays instead of resetting (191s phantom-task
  stands), cloak hysteresis (23 flips/2min at used==produced).
- Economy: converter urgency = spare/600 (27k produced vs 8.4k used, live);
  extra advanced plant bypasses milestones at 8s of income (his 150 m/s
  bar); gantry sited by us with a doubling radius; big-build assist gives
  frames a cost-scaled worker floor; JoinFor reach scales with the build's
  income impact.
- Brain: no want may exceed 1.5x all others in the roulette (gantry=80 vs
  silo=3.5 starved nukes/antinuke); crew ENERGY/METAL roles with fleet-ratio
  slots and demotion (roles-off A/B read them ~neutral); rez log curve +
  floor split; rez may buy the bot lab post-reactor.
- Escorts: native guard system uncapped [12,1,100000]; air scouts excluded
  from fodder/spam.
- Home-stand strength gate: NULL at both ratios, reverted (ISSUES.md).
- tools/units.py: per-team built-units dump, counts + metal share.

Arms (16-game Altair 1v1 unless noted): batch3 4-12, tonight (no
modoptions) 3-13, cycle9 4-12 -- stable 19-31% band vs 12.5% session start.
2v2 cycle9: 1-11, the campaign's first 2v2 win (prior 0-11, 0-12).
share_defence=4 is the shipped default. The standing bottleneck is
unchanged: trade 0.29-0.49, engagement selection (ISSUES.md).

## 2026-08-23 -- Prototype 1: the opening, un-scripted (the first market)

`manager/brain/market.as`: mex / energy / geo / plant Wants priced in one
currency (value = gain / (metal + builder-time at the wage)); Brain::Decide
runs the auction with executor fall-through; the facqueue takes its first
production orders (cons, one in flight, ledger reconciled by AiUnitFinished).
DLL: IsNeedGeo + GetMexSpotIncome bindings (spot yield is now real data, not
a model term). Measured vs NullAI on Comet Catcher (12m, seed 1): the
mex-solar-mex-solar-lab-cons opening EMERGED from prices with no opening
script; 6.9k metal produced vs 1.4k base; decision log carries the full
arithmetic. Known gap, deliberate: ~55% metal excess late -- storage,
converters, moho, and assist Wants do not exist yet (rebuild order steps
5+). Fixed along the way: TaskB::Spot for mex (Common's spotId=-1 freezes
CBMexTask), CanDefReach product-feasibility for plants (armsy on a land
map), value-based mex def choice (armamex nomination), FactoryCAI's x5
SHIFT multiplier (replace=true), pend reconcile via the finished event
(CountQueued lags ~45s at bench speed).

## 2026-08-23 -- The ladder campaign (solo session): easy BARb, from 0-4 to first win

Baseline after the day's watch-driven fixes: 0-4 vs BARb:stable:easy with
two 12-minute deaths. Three measured root causes, each fixed and re-run:
(1) con claim gain lacked its closed loop -- 37 cons chasing 13 spots, 3
army units, dead by 12m; claim gain now divides by claimers per open spot.
(2) argmax production turned a 10% con edge into 29 cons/0 army (the
vehicle DOA) -- production is now a value-weighted proportional draw, the
old Brain's roulette lesson reapplied; corroach-class crawling bombs
(selfd countdown 0) joined the kamikaze exclusion via a new def binding.
(3) reinforcing the doorstep one unit at a time lost 19k of army at 0.008
K/D -- the front perimeter now scales with OBSERVED enemy massing (standing
turret power meets the wave before it lands). Result: 1-1 with 4 draws --
the market's first win against any BARb -- tagged `market-first-win`; eco
now out-produces easy 2.5:1 (fight1v1 across the set). Open: army trades
still 0.43 vs 1.9 K/D and they out-grind our statics 38k:7k (easy's arty
outranges the LLT line); massing meet/hold dials nudged (1.3/240s) without
a clear signal at small samples. A 10-game baseline is recorded in
tournaments/ for the next session's comparisons.

## 2026-08-23 -- Solo session wrap: the market is healthy; the war is not

Final ladder state (45m, Comet): vs easy hovering at the noise floor
(3-5, then 0-3 with 5 draws across one-feature-apart builds -- 8-game
batches cannot separate them); vs medium 0-6. Shields landed in the
protection market (IsShieldDef binding; worth the arty mass they blank).
Range-answers-arty landed in defense picking. The measured verdict stands:
eco 2.5:1 at 30m, army K/D 0.22 -- every long game is lost in trades, in
the kept legacy military-use layer. Next session needs (1) the military
design conversation (squad formation, engage odds, group travel -- his
domain by declared boundary), and (2) tournament batches of 20+ for any
military tuning claim. Tags: pre-overhaul -> market-first-win ->
ladder-easy-parity. The market rebuild itself -- catalog, one currency,
six pricing laws, ~15 want families -- is DONE and measuring clean.

## 2026-08-23 -- The 20-game anchor (final build, vs easy, 45m, Comet)

4-12 with 4 draws: easy wins 75% of decided (CI 51-90 -- the first
statistically real ladder number; the 8-game batches were coin-flips).
Profile: eco 1.56:1 in our favor, static-grind war EVEN at 82k:74k (the
shields + range-vs-arty fixes measurably landed), mobile army K/D 0.315
carrying every loss. The next session's military work is judged against
exactly this anchor: tournaments/ 20-game set, tag market-v1-complete.

## 2026-08-23 -- Escort-fix re-anchor: 5-11, K/D 0.36; the band is robust

20 more games with the 45s-walk escort gate: 5-11 (+4 draws) vs 4-12,
K/D 0.315 -> 0.362 -- mild positive drift, CIs overlap. Across 40 anchored
games the army-trade signature is stable at K/D ~0.32-0.36; escorts were a
contributor, not the core. All solo-safe levers are now exhausted; per the
harness discipline (tournaments confirm identified mechanisms, they do not
go fishing), further military changes wait for the design session.

## 2026-08-23 -- Easy parity at 20-game scale: 8-9 (+3 draws)

The retreat fix's verdict: wins 4 -> 5 -> 8 across three 20-game anchors
(one named fix each: base anchor, escort proximity, value-scaled retreat).
K/D unmoved at 0.346 -- the fix pays in ground held, not kills: eco
leverage rose 1.43 -> 1.9:1 as fights stopped collapsing, and more games
close before their arty grind matures. Easy is now a coin flip at scale
(CI 31-74%). deaths.py remains the sharpest instrument in the toolbox:
"93% died retreating" found in one table what 60 games of win rates hid.

## 2026-08-23 -- Medium re-anchor 0-20; the wall is genuine

The commander exposure guard (found via the 15:00 COMMANDER LOST forensic:
he died building an LLT at a naked forward mex) did not crack medium:
0-19 -> 0-20. Config diff shows medium is not boosted -- it differs from
easy only in behavioral weights (attack 30->40, static value 0.8->1.2);
the wall is skill, and its name is the same K/D ~0.35 trade deficit. The
commander guard stays (right on its own evidence). Ladder file complete:
easy AT PARITY (8-9/20), medium 0-20, both at 20-game confidence. The
solo campaign ends here; the military design session is the key to the
next rung.

## 2026-08-23 -- RETRACTION: the 0-20 medium re-anchor measured a regression

The commander exposure guard's farm-radius test also banned the rear-flank
plant site; the commander (early game's only builder) never made a factory
(apexearth watched it live). The 0-20 "the wall is genuine" conclusion is
therefore contaminated and withdrawn. Guard reformulated on the base axis:
forward of the anchor (+150) is banned for the commander, behind is safe by
construction. Medium re-anchors on the fixed build.

## 2026-08-25 -- The escort floor: an unguarded constructor orders a Pawn now

apexearth: "make producing guards a high priority when we have a constructor
with no guard. Typically this is just a Pawn or Grunt." The escort machinery
already existed -- `EscortNeeded` pairs a produced cheap unit with an exposed
worker, and `RoleTarget(RAIDER)` carries `EscortMetalAtRisk()` -- but nothing
ever ORDERED one: `EscortShortfall()` was written and never called, so escorts
only happened when the proportional draw happened to produce a fast cheap unit
near an exposed con. Measured before the change: 0 pairings in a 12-minute
smoke run.

`Market::EscortOrderFor` is now a floor in `ConOrderFor`, ahead of the con
floor, the all-quiet gate and the draw, and the facqueue queues it behind a
busy head like the T2-con floor. It picks by combat-per-metal x speed over
the military hook's own eligibility (ground, not SKIRM/ARTY, under
`apex_escort_max_cost`) -- which lands on `armpw`, and cannot land on
something that would then refuse the duty. Demand is one order per
unescorted exposed worker; in-flight is the factory queue plus the
sent-ledger, not a time-decayed ledger (an escort queued behind a busy line
took 77 s to arrive, so a 60 s TTL expired and the floor double-ordered).

20-minute smoke: 5 floor orders, 8 pairings, shortfall returns to 0 within a
sweep of each order, no compile errors. NOT yet measured for displacement --
the paired single run at seed 1 differed 2x in metal built, which is the DLL's
own thread noise, so a tournament is still owed.

**Eligibility, same day.** apexearth: "we want fast or tough units on escort,
rocket bots die in a 1v1 vs a pawn/grunt so not good protection vs raiders."
The Rocketeer slipped the old SKIRM/ARTY filter because its role tag is
`assault` -- which in this AI's own counter chain means "answers statics"
(docs/18-brain.md), and BAR's own description of it is "Rocket Bot - good vs.
static defenses". `behaviour.json` even prices it at `vs raiders: 0.5`.
`Market::EscortWorthy` is now the single test, shared by the production floor
and the military election: ground, under `apex_escort_max_cost`, not SKIRM or
ARTY, and either FAST (speed at or above the ground field's own mean, 63 in
the pinned tree -- Pawn 87 passes, Rocketeer 50.7 fails) or a RIOT unit, the
role the game itself defines as the answer to raiders. A health bar cannot
express "tough" here: the tanky cheap bot at T1 IS the rocket bot (720 hp
against a Pawn's 370), and the field mean health is 9447.

NOTE: every riot unit in the pinned tree costs 220-3800 (Pounder 220,
Centurion 270, Gunslinger 650, Razorback 3800), all above the 120-metal
escort cap, so the riot clause cannot fire today -- escorts are fast units
until `apex_escort_max_cost` is raised. 20-min smoke after the change: 4 floor
orders, 3 pairings, all fast units (armpw from a bot lab, armflash from a
vehicle plant), zero rocket bots.
