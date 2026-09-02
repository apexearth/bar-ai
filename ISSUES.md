# Open issues — what is wrong with this AI right now

Each entry is a thing that is still WRONG, with the evidence for it and, where
known, the mechanism in our own code. Add to it rather than re-deriving the same
complaint next session.

What does NOT belong here: anything whose fix has been measured and confirmed.
That goes in the commit message, next to the diff, and the entry gets DELETED —
not marked FIXED and left to accumulate. `CHANGES.md` is frozen; git history is
the record of what was done, `USER-FEEDBACK.md` the record of what was asked
for, and this file only the open list.

Pruned 2026-08-30 from 2,637 lines. Everything dated 2026-08-27 or earlier was
dropped: those entries are campaign notes from before the wall revamp, the brain
market rework and the perf campaign, and the code they describe has been
rewritten under them. `git log -p -- ISSUES.md` has all of it if a claim needs
its provenance.

## 2026-08-31 — vs an INACTIVE opponent we still barely expand, and army still outspends economy

The first controlled economy measurement this repo has had. `NullAI:0.1` does
nothing at all -- no army, no expansion, no pressure -- so every number below is
this AI arguing with itself. Comet Catcher Remake 1.8, 30-minute cap, 13 seeds,
medians at fixed game minutes (the games end early, at ~20-28 min, when we kill
the passive commander, so end-of-game totals are not comparable and fixed
minutes are).

    min   mInc  produced   mEco    mBP  mArmy   mex   eInc
      6   11.2      2700    615    220   2862   4.0    104
     10   13.5      5666    965    480   4098   5.0    133
     14   18.1      9672   1836   1010   5590   7.0    256
     18   36.4     14916   3196   1630   7318  14.0    469

- **4 mexes at minute 10, 7 at minute 14, on a map with ~20+ spots and nothing
  contesting them.** This is apexearth's 2026-08-31 complaint ("4 un-upgraded
  mexes, income 15 m/s") reproduced with no enemy on the board to blame.
- **Army outspends economy from minute 10.** `mArmy` includes the ~2700-metal
  commander, so real army is ~1400 at min 10 against 965 of economy, and ~4600
  against 3196 at min 18. Against an opponent that cannot attack.
- Economy is ~21% of all metal produced at every checkpoint.

MECHANISM, partly identified and NOT yet fixed: most of that army metal never
passes through the builder market at all. `Market::ConOrderFor`
(`brain/market/production.as`) is the factory's own path, and the Brain drives
it independently of the Want auction -- so anything that reweights the
constructor market, the ETA objective included, structurally cannot move the
army/economy split. Whatever holds army at this share against a dead opponent
lives on the production side.

Do NOT read this as "the market is broken and the factory is fine". It is a
statement about WHERE to look: an economy-vs-army fix has to reach the producing
code, per CLAUDE.md's standing rule about attributing a composition problem
before touching any config table.

## 2026-08-31 — ENERGY: 46-58% of everything we generate is thrown away

apexearth: "We have not nearly enough energy converters. Take a look at how much
energy we waste."

Measured, watch-nanopack (SI 8v8 +100%, 26 min): median **57.8%** of all energy
produced wasted, 80.7% on the worst team, against 0.6% metal waste. Red Comet
1v1 +100%: 45.9% and 55.8%. An `armmmkr` is 380 metal, chews 600 e/s at
0.01724 -- 10.3 metal/s, a **37-second payback** -- and 11-13 stood per player
against an overflow needing ~16 more.

TWO WRONG DIAGNOSES BEFORE THE RIGHT ONE, both recorded so they are not retried:

1. "The storage gate blocks it" -- no. The bank sat at 87-99% of storage all
   game, so `current >= 0.85 * storage` passed throughout.
2. "The parallel-site fix is the answer" -- the serialization is real
   (`par` reads MCostScale, a METAL stall, so the one building whose trigger is
   surplus ENERGY was serialized), but it was not what bound. `apex: conv batch`
   fired ZERO times after the fix.

THE ACTUAL CAUSE, from `apex: convwhy`: the want fires and proposes 196 times,
nothing obsolete, nothing short of candidates -- and `ema=782` e/s in a game
discarding ~31,000. `gESurplusEma` is `energy.income - energy.pull`, and **pull
is DEMAND**: a fleet of 250 nano turrets asks for energy it is not drawing. So
the surplus is understated by more than an order of magnitude, a 600 e/s machine
is priced against a 1,000 e/s surplus, one order exhausts it, and the fleet
stalls.

FIX IN, NOT YET PROVEN: `EnergyPinned()` (bank >= 98% of storage) means
production exceeds consumption whatever the EMA says, so the chew is the
converter's full capacity and metal is the only bound on how many to start.
Self-limiting -- the bank empties, and the pin breaks once enough stands.

WHY IT IS NOT YET PROVEN: waste fell 51.7% -> 14.7% between the army sweep's 0s
and 40s arms, but a bigger army means a smaller energy grid. That is confounded
with the army change and separates nothing. The clean test is converters
STANDING and `conv batch` firing at a fixed army setting.

## 2026-09-02 — FRONT DEFENCE: the line now forms in 1v1; what is still open

The 2026-08-31 entry ("the line is drawn along the TEAM's band, and the wall
generator places 96% of everything") is closed by the 2026-09-02 commit that
carries the mechanisms and the numbers; `python tools/test_frontline.py` is
the regression contract (a gun per mex by minute 8, a line of >= 4 towers
>= 800 wide between us and them by minute 14, a factory by minute 4, no mex
with more than two guns on it). Residue, each measured in the same batteries
(Comet Catcher 1v1 vs BARb hard, +50%, 20 min):

- **The line is T1 and stays T1.** After T2 the T1 hands stop buying defence
  (`xT1late=0.020` x `xTeamPow=0.035` on an LLT once a Pulsar is the team's
  best) and the T2 con prices its own gun through `xWallEff=0.141`, so
  defence held 870 of a 16,988 target at minute 18 (`apex: targets`) and
  towers were lost faster than replaced (8 standing at 18 min from 10 at 16).
  His fortification doctrine (T2 con builds T2 guns, nanos heal them) has no
  path while both discounts stand; the dominance rule already drops dominated
  towers, so the per-metal `apex_wall_efficient` discount is now a second
  penalty on the only candidate left.
- **The commander walks to the line and dies there.** `Decide` exempts wall
  work from the 400-elmo forward limit on his ruling that commanders are good
  early wall makers; with the line at fwd 0.3-0.45 he walked 2,000 elmos and
  died to pawns at fwd 0.43 (fl-b s5, the only loss with a line standing).
  Exposure is charged to non-defence wants only; his own 2,700 metal is not
  in the price of a forward tower.
- **The opening wedge on the (1460,2976) Comet Catcher start.** Twice (seed 2
  and seed 6) a solar was drawn before the lab, landed 400 elmos from the
  anchor, and the lab order then failed to place three times
  (`task-die armlab fails=3 framed=0`), first factory at 8-18 min, game lost.
  Not a defence bug -- `Requests::Take` searches 256 elmos around a probed
  site -- but the defence rules that keyed on an ORDERED plant made it worse
  and now wait for a frame (`PlantFramed`).
- **The e-stall hoist owned the opening.** Before the fix 36-80% of builder
  elections in the first eight minutes were `why=estall`, every one joining
  the same solar. Now one generator on the way ends the hoist, but the stall
  itself is the ENERGY entry above: the lab eats the metal, solars starve.
- **Nanos outbid guns early.** `buildpower/nano` wins at v=50-54 against
  defence at 20-40 through minutes 2-8 (three nanos by minute 8 = seven
  LLTs); `apex: budget` reads bp=0.67-0.95 against its 0.16 target. Not
  touched here.
- **Team games are unmeasured.** Every battery above is a 1v1; `FoeRef` uses
  the mirror of the team's homes, which is right for lr/tb boxes and wrong
  for a corner start. Run `test_frontline.py` on a 4v4 before believing it
  there.

## 2026-08-31 — NANO: the fortification site is priced and then thrown away

`want_nano.as` prices a fortification lathe (`fortNeed`, from
`Military::FenceLostNear` -- demand where our own guns are actually dying) and
sets `w.pos` to that ground. `execute.as` then re-derives the site from scratch:
neediest line, then metal sinks, then bare big frames, then "any factory", and
only uses `w.pos` if we own no factory at all. So a nano bought to hold the wall
is built beside a lab.

This is why apexearth's split -- "defense oriented emplacements of nano turrets
are better when they're spread out so they don't all get blown up at the same
time" -- has no code path today: every executed nano is an assist turret. The
packed lattice (`market/nanopack.as`, 2026-08-31) is correct for all of them
until the fortification site is honoured; the spread answer has nothing to site.

## 2026-08-31 — NAVY: the T2 con is BUILT and then never elects; naval mex never happens

apexearth: "What we lack: T2 navy lab & T2 navy con; upgrade navy mexes." Probed
on Nine_Metal_Islands_V1, 4v4, +100%, 22 min. The chain is
shipyard -> advanced shipyard -> advanced construction sub -> naval advanced mex
(`armuwmme`/`coruwmme`, **620 metal, the same price as a land moho**), and every
link exists in the pinned game.

WHAT IS NOT THE PROBLEM, stated because a first reading of the code said it was:
the T2 shipyard is NOT unreachable. Measured, `plant:armasy` executed once and
`produce:armacsub` three times in one game -- the plant lane reaches it when a
navy con elects. It is RARE (1 advanced shipyard against 20 T1 ones), and
`want_tech.as` did skip every floater outright, which is now fixed -- but "never
built" was wrong.

THE ACTUAL GAP, and it is one step further down: **an advanced construction sub
is produced and then never takes a job.** In a whole game `acsub` appears in
three `apex: decide` lines and all three are a SHIPYARD deciding to produce one;
not one is an acsub electing work. Consequently `uwmme` is elected **zero**
times, while the AI's own `apex: upcons` line lists acsub among the constructors
that can upgrade a mex -- so the catalog knows, and the market never asks.

Next step is to find where a submerged builder falls out of the builder market:
`gWorkers` registration, the `OnMap`/reach guards, or an execute path that has
no water case. Do not "fix" the pricing before that is known -- the unit is not
losing an auction, it is not entering one.

ALSO OPEN, apexearth's ruling on how much navy to want: *"There are two sections
of water on the map. We should try to control each of those. Too much presence
would mean we lack ground forces - so we need a reasonable mix."* Today
`NavalLead()` elects a SINGLE player by distance-to-water and gates on
`OwnedWaterPlants() == 0` -- the exclusivity shape he has rejected before ("a
role may change how OFTEN or how MUCH; it must not decide WHETHER"), and it
cannot express per-water-body control at all: there is one `NAVDIST`, one cached
`WetPlantSite`, one lead. Naval demand wants to be per water BODY, with the mix
against ground falling out of the price rather than a cap.

## 2026-08-31 — the eco scoreboard: method, and what it has bought so far

A/B testing was ABANDONED here on apexearth's call: *"I also thought an A/B test
was silly to do here. Benchmark against ourselves, iterate and improve."* The
earlier attempt is why -- two batches of the identical configuration differed by
+9.3% and +13.3% mean `metalProduced` (sd ~20%, minute-18 CI excluding zero), so
the benchmark reported a significant difference between a config and itself, and
resolving a 10% effect would have needed ~60 pairs. **A 10-game eco A/B on this
benchmark measures noise. Do not run one.**

RETRACTED from the first attempt, and do not cite it: "the ETA arm builds more
army, +12.5% at minute 6, p=0.039". The identical-config control threw a p=0.039
too, and there are 28 tests per comparison.

THE METHOD INSTEAD. One scoreboard, 10 seeds, Apex vs `NullAI:0.1` (which does
nothing at all), Comet Catcher Remake 1.8, `apex_eta=1`, medians at fixed game
minutes. Only runs that actually REACHED a mark count toward it -- carrying a
finished run's last sample forward reports an early win as a small economy.

    SB1  economy-only          SB2  + spend the metal
    min  income  mex  waste%   min  income   mex  waste%
     10    15.8  6.0    46.6    10    18.2   6.5    18.2
     20    53.6 27.0    18.6    20   131.1  54.5    19.1
     30   211.2 64.0    11.7    30   233.1  66.0    13.0

**2.4x the income at minute 20**, n=10 each, far outside the noise floor above.

WHAT EACH STEP WAS, so the next one is not re-derived:

- **SB1 -- economy is the only target.** Two independent army drivers had to go,
  and the second is the one that matters: `ArmyTarget()` falls back to a
  SYMMETRIC PRIOR when no enemy is visible, so against an opponent that does
  nothing we built army to match an imagined mirror of ourselves; and
  `sinkGap = OverflowM() x fillS` **defines metal we fail to spend as army
  demand**, which is why army ran at 1.58x its own target (7370 against 4666).
  Army metal at minute 18: 5544 -> 324. Expressing "this player is for economy"
  as a zero target is apexearth's own shape, quoted in `protect_target.as:15`.
- **SB2 -- spend the metal, do not bank it.** `OverflowM()` only reports once the
  bank is past 80% of storage, a LATE report of a fact available immediately:
  measured, the bank pegged at its cap around minute 5 and the AI first admitted
  it lacked hands at minute 6, having already binned 792 metal (apexearth:
  *"Relying on storage is lazy - make sure spend the metal. (need more build
  power)"*). Replaced by `SlackFrac()` -- smoothed `(income - pull)/income`, no
  storage term -- which floors `feedRoom`, the forecast that had switched
  constructor production off at ten builders while 46% of the metal was being
  thrown away. A prediction must not veto production when a measurement refutes
  it.

OPEN, both attributed and neither guessed:

1. **Late-game waste is untouched.** 19.1% at minute 20 and 13.0% at minute 30 --
   the same failure as the early game, at a larger scale. SB2 bought the opening
   only.
2. **The frame budget is now violated by the economy this created.** 1v1 watch,
   `apex_perf=1`: worst spike **102 ms**, `hk.maketask.builder` 10,197 ms total,
   and the top per-call offender is `want.mexup` at 4.0 ms average / **75.3 ms
   worst**. That walk is O(spots x constructors) and this build reaches 98 mexes
   and 232 builders where the old one reached 14 -- a throttle sized for an
   economy a fifth the size, which is CLAUDE.md's "a bulk pass that got BIGGER
   without its throttle being revisited", exactly.

## 2026-08-31 — `policy.as` is 17 knobs and ONE of them is connected

The docs were swept against `docs/23-the-plan.md` on 2026-08-31 and this is what
the sweep found in the code. `policy.as` opens by declaring itself the home of
eco THRESHOLDS -- "the numbers that decide when energy is short, when a
generator is obsolete, when a constructor is worth buying" -- which is the shape
the plan forbids. But the file turns out to be a smaller problem and a stranger
one than that header implies.

MEASURED (grep over the whole of `ai/Unstable/game-side/script/`, verified twice
-- by `Policy::<name>` and again by the raw `apex_*` tunable string, because
absence is the least reliable finding here):

- **17 accessors. Exactly ONE call site in the entire tree**:
  `Policy::AntinukeIncome()` at `market/want_super.as:421`.
- The other 16 are read by nothing. `EnergyHeadroom`, `EPerMetal`, `T2Energy`,
  `T2Metal`, `T2EnergyFrom`, `T2EnergyReactor`, `FusionMinEnergy`,
  `ReclaimSolarE`, `ReclaimGenE`, `ReclaimPad`, the four `ConLog*` curve
  coefficients, `GreedCons`, `ShieldIncome`.
- All 16 are still registered in `game-patches/gadgets/dev_tunables.lua`, so
  they are live modoptions a dev game can set, that do nothing. They are NOT on
  the dashboard's guided page -- they sit in `dashboard_audit.py`'s waived list,
  which is why nothing has flagged them (see the audit gap below).
- Their comments name the code that used to read them: `techlead.as`,
  `manager/factory/phase.as`, `manager/builder/share.as`,
  `manager/builder/fusion.as`. **None of those files exist.** The brain overhaul
  deleted them and rebuilt their jobs as priced Wants in `brain/market/`, which
  read continuous inputs (`EcoPowerM`, `BestConvRatio`, `GenObsoleteOnArrival`'s
  ratio test) rather than any threshold. So the ETA-shaped replacements already
  exist and run; `policy.as` is the orphaned old interface sitting beside them.

So this is mostly a CULL, not a redesign, and it is cheap: 16 accessors, their
`TUNE_` constants, their `dev_tunables.lua` entries, and the stale comments that
cite deleted files. Do not confuse the cull with the one real issue below it.

### The one live one: an income floor stacked on top of an affordability test

`want_super.as` already refuses what it cannot afford -- `if (bill >=
classBudget) continue;` at :407, before the antinuke branch. The floor at :421
is an EXTRA gate, and its own comment says why it was added: the anti-nuke is
the cheapest class on the list, so it clears a budget-relative affordability
test long before a gantry or a silo does, and "took every super-push".

That diagnosis is right and the patch is the wrong shape. `afford =
(classBudget - bill)/classBudget` rewards being cheap by construction -- the
code says so itself, twenty lines later, where the gantry needed a special gain
term for exactly this reason. A hand-set 60 m/s bar on one class papers over a
pricing function that cannot rank a cheap insurance policy against an expensive
production line. The plan's answer is the comparison the floor replaces: which
of these makes the target arrive sooner. Fixing `afford` is the change;
deleting the floor is a consequence of it, not a change on its own.

### Why nothing flagged it, and the 26-knob cull list it was hiding

`unread` was `bool(tunable) and not sites` and `sites` counted any
`GetTunable("apex_x")` anywhere -- including the one inside the dead accessor
itself -- so every knob read only by an uncalled wrapper passed clean. A second
layer compounded it: `dashboard_audit.py` tested `unread` on CURATED entries
only, and all 16 policy.as knobs are waived.

FIXED 2026-08-31. `tools/as_scope.py reachable()` is a fixpoint reachability
walk seeded from the engine's own entry points (taken from
`reference/barb-stable`, not from us); `python tools/as_scope.py --dead` prints
it. A read inside an unreachable function is no longer counted, and waived
knobs are checked too. It also found **91 unreachable functions tree-wide** --
a cull list in its own right, and the same rot class as the accessors.

That turns up **26 tunables nothing can read**, not 16 -- live modoptions on
apexearth's dashboard wired to nothing:

    ENERGY_HEADROOM E_PER_METAL FUSION_MIN_ENERGY RECLAIM_GEN_E RECLAIM_PAD
    RECLAIM_SOLAR_E T2_METAL T2_ENERGY T2_ENERGY_FROM T2_ENERGY_REACTOR
    CON_LOG_T1_A CON_LOG_T1_B CON_LOG_T2_A CON_LOG_T2_B GREED_CONS SIEGE
    KILL_FLOOR RAID_MIN_EARLY SHIELD_INCOME SCOUT_BLIND_MULT E_STALL_BOOST
    LINE_PULL NUKE_RISK WAVE_MEET BUDGET ALLY_COVER

Verified per knob against `ai/Unstable`, `cpp/src`, `tools` and
`game-patches`, because two rounds of this produced false positives: **the C++
DLL reads tunables too** (`apex_porc_obsolete_ratio`/`_secs` are live reads in
`DefenceData.cpp` and were briefly on this list -- `dashboard.py` now scans
`cpp/src`), and `apex_siege` -- which IS gone -- looks read until you match
exactly, when the hits turn out to be the live `apex_siege_prior`.

NOT CULLED, because two are not mechanical and are apexearth's call:

- `TUNE_CON_LOG_T1_A/B`, `T2_A/B` are drawn as a curve by
  `dashboard_ui.html:1535-1537`. The UI rows go with them.
- `apex_t2_metal` has a SECOND life as a hardcoded `T2_BAR = 30.0` in
  `tools/audit.py:848`, which checks whether the AI went T2 above 30 m/s.
  Under `docs/23-the-plan.md` that bar should not exist to be checked against
  -- but deciding what the audit asks INSTEAD is a real question, not a
  deletion.

## 2026-08-31 — the T2 affordability FLOOR is gone; only a soft price remains

apexearth, watching a 1v1 loss: we started T2 at ~15 metal/s, and a fusion at
~10 metal/s (4,300 metal, roughly seven minutes of the entire economy). "I
thought these issues were fixed" — they were, by machinery that no longer exists.

VERIFIED, two ways, because absence is the least reliable finding here:

- `RushReady` has ZERO definitions in the tree. Five references survive and all
  five are comments (`factory/state.as:17`, `policy.as:31`, `tunables.as:158`,
  `:165`, `:314`), pointing at a `techlead.as` function the brain overhaul
  deleted.
- `T2Energy()`, `T2EnergyFrom()`, `T2EnergyReactor()` and `T2Metal()` are still
  defined in `policy.as` and are called from NOWHERE. So `apex_t2_energy`
  (1200), `apex_t2_energy_from` (12) and `apex_t2_energy_reactor` (400) are
  live knobs on the dashboard's Balance tab, adjustable, wired to nothing.

WHAT IS *NOT* TRUE, and the distinction changes the fix: it is not that nothing
expresses affordability. `want_tech.as` prices the advanced plant with real
arithmetic — `aiEconomyMgr.metal.income` and ValueOf's `feedSec` term, "half the
bank is spendable now, the rest waits on income". The hard FLOOR became a SOFT
PRICE, and the soft price does not bite. That is the same disease as
`docs/21-simplification.md`: one term among many cannot order an outcome.

The ruling has since landed, and it is neither of the two obvious patches.
`docs/23-the-plan.md` (2026-08-31): a floor is forbidden, and so is a decisive
affordability multiplier tuned by hand — **a plant we cannot feed loses because
starting it lengthens the ETA to every target we might name**, and at 15 m/s
with four un-upgraded mexes the cheap growth beneath T2 was not yet exhausted.
So the fix is the ETA comparison itself, not a term added to the existing
price. The three dead tunables above are what a *floor* would have consumed;
under the plan nothing will consume them, and they can be culled when the ETA
work lands rather than before.

ALSO OPEN, from the same watched game and unranked here: army sent out to die
instead of holding inside our own turret cover; the turret line drifting
backward rather than concentrating forward; fight orders issued too freely.

INSTRUMENT GAP, found while confirming the above: `tools/dashboard_audit.py`
cannot see this class. Its `unread` test asks only whether SOME `GetTunable`
call exists, and `policy.as` has one — so a knob read exclusively by an
accessor that nothing calls passes the audit clean. An attempt to add the
detection produced eleven false positives (`if (...)` parses as a function
definition, and a one-line `float T2Energy() { ... }` body does not) and was
reverted; doing it properly needs the real scope walk `tools/as_scope.py`
already implements, not another regex.

## 2026-08-30 — defence pricing: reach is paid as AREA, damage rate was paid as sqrt

apexearth: "you can get like 10x the DPS from HLT per mass compared to the
gauntlet style defense... dps per metal and range is usually what my brain
thinks about", then "So we value range a bit too generously :-P".

Three terms decide a turret's cover, and they were weighted almost exactly
backwards. Measured off the pinned tree (a scratch script, since deleted; dps counts
every weapon mount, range is the weapon's own):

| tower | cost | hp | dps | alpha | range | dps/metal | old threat/metal |
|---|---|---|---|---|---|---|---|
| armllt Sentry | 85 | 620 | 241 | 112 | 430 | 2.84 | 14.81 |
| armbeamer Beamer | 190 | 1430 | 400 | 40 | 480 | 2.11 | 10.01 |
| armhlt Sentinel | 440 | 2600 | 322 | 580 | 620 | 0.73 | 10.22 |
| armguard Gauntlet | 1250 | 3050 | 211 | 300 | 1220 | 0.17 | 2.67 |
| armanni Pulsar | 3500 | 6100 | 1091 | 10800 | 1400 | 0.31 | 7.51 |
| cordoom Bulwark | 3000 | 9400 | 1513 | 4500 | 950 | 0.50 | 10.30 |
| corbhmth Cerberus | 3100 | 8300 | 324 | 450 | 1650 | 0.10 | 2.44 |

- **REACH: paid as area, and still is.** `PfStakeIn` buckets our economy at
  the candidate turret's OWN range (protect_field.as:436, "The slot's pitch IS
  that reach"), so a 1220-reach gun is credited with 6.5x a 480-reach gun's
  stake. That would be right if a turret defended all of it at once; it shoots
  one thing at a time. **This is the open item.**
- **HIT POINTS: paid twice.** `sqrt(health)` inside CircuitAI's surfThreat
  (CircuitDef.cpp:623) and again as `hp/(hp+PfAlphaRef())` in `PfTowerKill`.
  The second is deliberate and earns its place (it is what makes a Bulwark
  reachable over twelve Beamers); the double count is the accident.
- **DAMAGE RATE: was paid as `sqrt(dps)`** — FIXED. A Beamer's real 12x
  damage-per-metal edge over a Gauntlet read as 3.7x. `PfTowerKill` now
  prices on surface DPS recovered from surfT (`apex_def_dps_linear`, default
  on; 0 restores the old pricing).

Net before the fix: Gauntlet beat Beamer 6.5x on reach and ~2x on doubled hp,
losing only 3.7x on compressed dps — **1.7x in the Gauntlet's favour**, which
is what the auction did. After it, Beamer wins ~2x early and they are level
late; the Gauntlet is held up entirely by the r² reach term.

Also fixed alongside (weakly): `apex_t1_def_late`'s gate was a STANDING
advanced defence constructor, so any player with an advanced lab but no such
con kept buying light towers at full price. Now `Factory::gHaveT2 ||
T2DefHandsStanding()`, default 0.15 -> 0.02. Matched 4v4 A/B (same map, seed,
handicap; control = discount off) moved T1 metal after T2 by only -43% / -14%
on two seeds with the tower COUNT unchanged (117->109, 132->133) — it shifted
which light tower gets picked, not whether. The multiplier is not the lever;
the pricing is.


## 2026-08-30 — we do not raid at all; stock BARb raids all game

apexearth: "I am convinced the barb stable AI uses raiders better than we do.
So I think we need to rethink our own usage of them." Measured, not inferred.

**Stock's pipeline, entire game.** `CMilitaryManager::DefaultMakeTask` maps
ROLE_RAIDER to `Defend(RAID, quota.raid.min)` (MilitaryManager.cpp:1679).
`CDefendTask::Update` promotes to a real `CRaidTask` at `quota.raid.min`
(10.0 power in hard_aggressive) **or the instant any RAID task already
exists** — so after the first pack it is a continuous stream, not one blob.
`CRaidTask::CanAssignTo` caps a pack at `quota.raid.avg` (65 power), same def
only, within 1000 elmos of the leader, so they field many small same-unit
packs concurrently. `CRaidTask::FindTarget` is economy-first: an enemy
BUILDER or COMM is taken with `maxThreat = FLT_MAX`, anything whose local
threat exceeds 0.75x the pack's power is skipped, and the allowed threat
DOUBLES inside their own base radius. No target -> `FallbackRaid` roams to an
unclaimed scout position.

**Ours diverts every raider out of that pipeline**, both in
`manager/military/hooks.as`:

1. `IsFodder` (hooks.as:8) — SCOUT/RAIDER ground units under
   `apex_fodder_cost` (100m). In `SpamPhase()` (posture.as:310, true once
   `Factory::gHaveT2`, `apex_spam_suicidal` default on) they become **solo
   `CScoutTask`s**, one per unscouted metal cluster. `CScoutTask` is not an
   `ISquadTask`, so they can never group, and they hunt unscouted ground, not
   the enemy's constructors.
2. `WantsMassing` (hooks.as:44) — `if (role == RT::RAIDER) return
   Factory::gHaveT2;` Every raider at or above 100m joins the single massing
   DEFEND pool the moment our advanced lab stands. They become line army.

Before T2 raiders do reach the stock pool, but `UpdateRaidCaution`
(posture.as:37) rewrites `quota.raid.min` from 10 to `apex_raid_pack (8) +
0.2 * metal income` — roughly double stock's first-pack bar at 40 m/s income.

**Evidence.** `NoteFightElection` stamps the elected fight type on each unit
(`f<N>@frame`; 1=GUARD 2=DEFEND 3=SCOUT 4=RAID 5=ATTACK 6=BOMB 9=AA
11=SUPPORT). Across the 11 most recent matches in `matches/`, **f4 = 0 and
f5 = 0 in every one**. f2 (the massing pool) runs 243–417 per game, f3
(fodder-as-scout) 121–253, f1 (escort guard) 36–183.

So the gap is not that we raid badly — after our own T2 we hold no RAID task
at all, and the same T2 flip is what turns the whole raider class into line
army. This also re-loses his 2026-08-20 "tit for tat" ruling, which is quoted
in UpdateRaidCaution's own comment.

Not yet fixed: the redesign is a policy question (does a raider stay a raider
once we are on T2, and does raid pack size scale with income rather than
flipping on a tier flag?) and needs his answer before anything is priced.


## 2026-08-30 — parallel expensive energy: FIXED, two residues open

He raised it four times, the last with a screenshot of a fusion at 55%, a
second reactor at 50%, an AFUS at 11% (ETA 64 min) and an abandoned frame at
`ETA ???`, then again live: "we're making 2 fusions and 1 afus all at the same
time... I feel like giving up." Cause: every duplicate gate keyed on DEF ID and
the energy ladder is six defs, so the per-def gate refused `armfus` and the
stall ladder immediately founded `armckfus` and `armafus` instead. Fixed in
e593ace: expensive energy (>=300m, makes energy, immobile) is one CLASS with
one site, enforced at the Requests chokepoint every entrance passes.
Validated over 32 4v4 Comet games (76cd434): zero episodes, peak concurrency 1
on 144 of 148 team-slots. `python tools/energy_parallel.py <run>` is the
instrument; the audit carries it as `parallel-big-energy`.

1. **`t1-eco-with-afus` is the price of the rule** — ~54 T1 generators and
   converters left standing with AFUS fielded, up from clean on the same seed
   before the gate. Serializing reactors sends more asks down to the sub-bar
   generators, and obsolete-reclaim is what should be clearing them. Not yet
   attributed to a reclaim rule; measure before touching one.
2. **The gate reads a ledger that drifts in team games.** `ledger-drift` fails
   32/32 in 4v4 (25 missed events; clean in every 1v1) and was already failing
   in the first 4v4 of the day, BEFORE any of this work — pre-existing, but now
   load-bearing, because `ComBigEnergyRising` is what decides whether a second
   reactor may be founded. Validation passed regardless, so the drift does not
   currently defeat the gate; that is luck, not design.
3. **No wealth exemption, deliberately.** Three were tried and each was the
   clause the overlaps returned through. His older "more than 1 of any building
   at one time if we are wealthy enough" still governs buildings at large; this
   class is now strictly serial. If he wants reactors to parallelize when rich,
   that is a policy change and needs a number he agrees with, not a re-derived
   guess.

## 2026-08-30 — the wall revamp: LANDED (75b2d97), residue open

His ask: towers blobbed at the start area; he wants a wall wrapping the base,
joining allied walls, advancing with expansion, rear towers reclaimed, tiers
rising — explicitly NOT the front-line or base-border models. Landed as
`apex_wall` (default on): perimeter slots on the building rim
(protect_wall.as), the open-slot target pull, the held-ahead stranded
retirement, and the frontier anchor (the furthest capped mex along the enemy
axis, midline-bounded). `tools/wall_check.py` and `tools/wall_map.py` are the
instruments; `lineFill` is the one that measures sealing.

1. **Walk churn eats the early sentry** (vs hard, 20260830-190332). The
   memo-starvation fix got the commander WINNING the sentry election at 2.6
   min; the re-election roulette then swapped his task for energy/mex six
   times mid-walk and the first tower stood at 12:00. Same class for every
   want: a walking builder re-rolls every update and any different-build-type
   winner replaces the task. The fix is election-to-standing stickiness during
   a committed short walk — a measured change on its own, NOT more pricing.
2. **The line advances faster than it fills** (smoke 20260830-184343). Every
   defence election lands exactly on the wall (wallD=0 throughout), but
   lineFill sat at 0.00 until minute 14: each newly capped mex steps the anchor
   forward, so the wall chases the frontier instead of sealing, holding, then
   stepping. Candidates, untried: quantize the advance harder (512), or anchor
   on a robust percentile of forward mex depth instead of the max.
3. **The early seal is late.** His doctrine: towers exist to stop leaks into
   the backline; "oftentimes its solved by 4 or 5 well placed turrets". The
   first defence election lands at a healthy 5.0 min, but the auction takes a
   420m HLT (TeamBestTowerPower scales the sentry down against it inside T1)
   and walk+build runs minutes, so nothing STANDS before ~8-10 min. Candidates,
   untried: sharpen apex_def_ttd_h so short threat windows favour the
   20-second sentry, or scope the power routing to tier gaps only.
4. **The commander never elects defence** — eco wants outbid the wall pull. He
   permitted commander wall work; it is not price-favoured. Ask him whether the
   commander should carry an explicit early-wall preference before nudging it.
5. **His 2v2 expectation — "a clear line of towers across the map" — is NOT
   met, and the blocker is the army, not the placement.** The machinery sites
   correctly (1v1 win, 26 towers, 69% enemy-side), but three 2v2s vs BARb
   medium lost on army/eco, the front collapses to the base corner, and the
   wall honestly concentrates THERE — which reads on screen as "towers in the
   middle of our base like always". See the 8v8 entry; re-show him a 2v2 after
   the team-fight work moves.
6. **Front::GateChokes returns ZERO candidates in every 1v1** (`lineSpots=0`
   all game), so the concentration-doctrine gates are inert and the wall
   carries everything. Pre-existing, now load-bearing.
7. **Untested, in order of risk:** tier progression on the wall at high economy
   (the T1-late ×0.15 discount should put T2 guns up late — verify in a long
   game); ally-join is smoke-tested only, never visually confirmed to meet.
8. Towers finish ~200 elmos inside the wall because it steps outward during the
   walk. Harmless at one quantum; the at-build rim/core split reads worse than
   election siting (election wallD≈0), so judge siting at the election.

## 2026-08-30 — all-angle defence: closure-ring candidates (LANDED, awaiting measurement)

His ask: "on some maps you might be completely surrounded. So our angle of
defense has to be really flexible." The closure ring already PAID for every
approach bearing a post newly closes, but no candidate ever stood on a cold
bearing — guard sites hug our metal and shift toward the enemy centroid,
FrontBuildSpots offers only hot bearings, and ShieldArcSpots/NetSpots had ZERO
callers. The credit existed and nothing could collect it. `apex_def_ring` now
offers one candidate per OPEN ring bearing, pulled inward so the def's own reach
covers the ring point; map-edge bearings are walls and are never offered. No arc
constant — a surround makes every on-map bearing a candidate, priced
individually.

OFF-path while `apex_wall=1`, which is the default, so this is measured only if
the wall is switched off. Read it via `apex: defsite ... ring=N bestRingGain=`
and `apex: fronttowers ... closure=`. Verify on a long high-economy game: at low
income DefenceTarget is a handful of light towers and ring sites correctly lose
to mex floors.

## 2026-08-30 — 8v8 vs 1v1 gap: the measured deltas from the first clean Supreme Isthmus soak

His report: "We perform worse on 8v8 games than we do 1v1 games." First
instrumented 8v8 since the AV fix (Supreme Isthmus v2.1, per-side 8, +50%,
16 min, timelimit, matches/soak8v8-s1). One game -- directional, not proof.
Side sums, us vs stock:

- FIGHTS: we built MORE army (70.5k vs 57.9k) and held more standing
  (26.9k vs 22.3k) yet traded 0.48 -- killed 12.4k, lost 25.7k; damage
  101k dealt vs 150k received. His complaint #1 at team scale; the
  DefendTask home-muster/towers fix (commit 28acfa1) targets this. Re-soak
  and compare this exact line.
- INCOME diverges late: final 289 vs 364 m/s on EQUAL mex counts (62 vs
  61, and we hold MORE mohos 11v8). Two of our eight sat at 2 mexes at 16m
  (t0, t2) with huge energy grids (t0 eInc 663 at mInc 19) -- expansion
  stopped, spend went to energy/BP (t0 budget line: bp=0.48 vs target
  0.17). Their stunted players have causes (t12 comm died); ours look like
  threat-priced-out mex wants (risk lines: threat 226-259, short=1.00).
  UPDATE same night: commit 5918909 aligned the PickSpot sweep on
  FoeAnchor (it still read the mobile centroid -- the documented collapse
  frontline.as:757 cures), but the re-soak (soak8v8-s1b, same settings)
  did NOT move the needle: pastFront intervals 356-1347, apex mex spread
  [2,3,4,4,7,8,11,14] vs stock 63 total. The interval counters aggregate
  many sweeps, so high counts may just be the enemy half of 90 spots
  legitimately refused -- they cannot distinguish "axis collapsed" from
  "half the map is theirs". ANSWERED same night by the sweep instrument
  (soak8v8-s2, seed 2): geometry is NOT the binder. Every player's sweep
  reads a healthy axis (span 6,680-9,345 elmos) and keeps 40-56 of 90
  candidates; pastFront refusals are the legitimate enemy half
  (~35/sweep). The worst player (t6, held=4) PRICED mex wants all game
  (claimed=0, noOpen~0), WON the auction 35x, EXECUTED 28 claims -- and
  lost zero cons and zero mexes. The claims CHURN: exec positions scatter
  map-wide (armcom #19794 sent to 6456,312; spot 4520,7208 claimed twice
  by different cons), and on a long walk the 3s re-election window lets a
  local want outbid the mex claim mid-walk -- the abandonment leaves no
  corpse, no task-die, no log. 1v1 walks are short, so claims complete
  before churn strikes; 8v8's taken-near/far-remainder geometry makes
  every claim a long walk. This is the commitment/stale-count bug class
  the velocity plan's commitment ledger targets -- the likely fix shape
  is claim stickiness priced by the walk already paid (sunk walk raises
  the incumbent's price), not a gate. Next instrument if needed:
  claim->finish conversion by claim distance. Keep 5918909 (the
  documented cure's missing half, strictly more stable).
- AIR is a team-scale write-off: all 8 players built an armap; the elected
  assassin (t4) logged "air lead NOT armed" from 11m to end while
  non-leads t5/t6 launched 5-6 bomber home waves scoring dmg/bomber=0 at
  0.20 survival. The non-lead frozen-bar fix (entry below) is now
  evidenced: waves launch undersized and die, and the lead never commits.
- DEFENCE: stock spent 20.1k on defence vs our 9.3k, and our defence was
  100% T1 towers (audit defence-tier flag) with advanced cons fielded.
  His concentration doctrine wants the opposite lean.

## 2026-08-29 (late night) — PERF: his target is <10% of tonight's AI cost; campaign open

His ruling, watching a laggy ~1500 m/s 1v1: "to be OK the perf needs to be
less than 10% of the impact we currently experience." Baseline measured on
that game (37 game-min, Archsimkats +150%, 655 builders at the end):
`apex: perf AiFrame` peaked at 10.6s per 60 game-sec (~18% of sim), with
30-146ms single-frame spikes every 8 frames continuously. Attribution:
hk.maketask.builder 7.0s/min of it (~66%) — 407 full want-stack elections
a minute at ~9.5ms plus exec.want at ~6ms; the C++ remainder (threat maps
etc.) is ~3s/min and second-order. Landed tonight, unmeasured: the
election memo (six proposers shared per asker-def for 1.5s, evicted on
execute), the rezzer-chain 2s gate, exec.orph/exec.pend/exec.k* and
dec.* attribution timers. STILL UNATTRIBUTED: the exec tail (~6ms/call —
exec.pend measured 0.02ms, so it is the per-kind Enqueue/dispatch), and
want.protect's fill residual (~3.3ms/call at scale, cap already 2/frame).
Compare `perf sec`/`perf AiFrame` on the next long high-income game
against the numbers above; the 10% bar is AiFrame ≤ ~1s/min at that scale.

Round 1+2 MEASURED (repro-4: Archsimkats +150% seed 2, WON, 1675 m/s,
395 builders, f=63000 window vs the baseline's same window): AiFrame
10,054 -> 4,652ms/min (-54%), worst frame 172 -> 69ms,
hk.maketask.builder 6,975 -> 2,265ms (-68%), full stacks 407 -> 148/min,
exec.knano 11.7 -> 3.4ms/call. dec.deferred fired 5 times all game (the
budget is a backstop).

Round 3 (C++, DLL rebuilt): `perf split` says ProcessJobs is ~97% of the
frame; inside it the ally FRIENDLY LIST was rebuilt 630x/min at 1,151
units (delete+new+engine call each, 1.83s of every game-minute) because
any task update demands it. Throttled to at most 2/sec -- verified 113
calls/283ms at 930 units.

Round 4 (his "do A and B" ruling): (A) IBuilderTask::Reevaluate now asks
the script market at most every 3s per walking builder (commanders and
rez bots exempt -- their safety lives inside the election; completion/
abort still elect immediately). Measured: hook calls 3,047 -> 1,023/min,
hk.maketask.builder 1.35s/min, AiFrame 2.4-2.7s/min maxMs 47-83 at 444
builders, 0 exceptions, won. (B, slice 1) DeathWalk's GetEnemyCostAt
engine sweep cached per cell/3s -- want.mexup per-call halved, mex
pipeline unharmed (94 mexes / 30 T2 on the validation win).

STILL OPEN toward his <10% bar (~1s/min): the board at 444 builders
reads want.protect 409 + fills ~500 (the memo-miss fills are now the
biggest script item), factory hook 262 with 61ms max spikes, and the
next long 650-builder game must confirm the at-scale total (projection
~2.5-3s/min there). B's remaining slices, in order: the protect fill/
election split (core per stamp, walk pricing per asker), then the full
market snapshot if still over. `perf AiFrame`/`perf split`/
`perf friendly` + the section board are the instruments; his watched
feel is the acceptance test.


Folded in from the 2026-08-29 spike entry: the two prescribed protect-stack
optimizations LANDED (RiskFill/RiskFillSiege frame memos, ClosurePrep memoized
on the field stamp, DefSiteFill capped at two fresh fills per frame). Worst
single call on a 12-min smoke: 12ms against a 126ms baseline — but that
baseline was a 43-min base, so it is NOT re-measured at scale yet. Do not add
more candidate generators to the protect stack before that measurement.

## 2026-08-29 (late night) — air release: non-lead home-wave still tracks the live want

The lead's release gates were all indexed to ScaledBombers(), which grows
with income AND their AA — measured 30/93 held forever, no strike all
game, then bar=-1 on the next watch because the market built the plants
and the assassin never "committed" at all. Fixed for the lead (frozen
commit snapshot + decaying deadline bar + standing-wing clock + the
stood-down wing still spends at deadline). NOT fixed: the non-lead
`apex_air_home_wave` release still compares against the LIVE
ScaledBombers() — same treadmill in team games; give it the same frozen
bar when a team game shows allied bombers hoarding.

## 2026-08-29 (late) — ZERO Titans at 500 m/s (his report; prodrank instrument landed)

"we have 2 players pulling around 500m/s income and neither one has made
any titans. We lose these games because we don't make those units. The
last adaptation didn't seem to change anything at all." At 500 m/s the
afford window is NOT the binder (x0.78 at 120s, x0.55 even at the old
60s), and armbanth's core worth ranks #3 in the game — by the visible
arithmetic (ppc/linePPC ~1 vs Vanguard's ~0.03) it should DOMINATE the
gantry draw. Something zeroes it upstream that no log shows, and hosted
games leave no infolog. `apex: prodrank` (production.as, defrank's
pattern) now prints every candidate per line per minute with draw weight
or drop reason (:aff0/:gap0/:eco/:amph). Read it on the next high-income
game; the term it names is the fix.

## 2026-08-29 (late) — behaviour.json power overrides leak into production worth (survey open)

The armthor x0.1 case is fixed by counter-mod (commit dac0946), but the
class remains: 22 defs carry hand-set "power" values written for THREAT
reading, and UnitCore inherits every one as production worth via PowerMod.
armvader sits at x100 (produces nothing today — a crawling bomb priced as
a god is a landmine, not a bug yet); armstil x0.05, corbw x0.1, several
aircraft at x0.5. Audit the 22 against the worth model's own means before
the next composition complaint lands on one of them.

## 2026-08-29 (arena) — amphibious units act cowardly (OPEN)

apexearth, watching arena rounds: "Not sure why but our amphibious tanks
act very very cowardly. Same with platypus, maybe it is an amphibious
behavior we have." Suspects, unattributed: (1) the standoff-row system
holding short-range brawlers at max range (apex_brawl_pass=0 default --
the arm built for exactly this measured neutral at the OLD noise floor,
re-test with the big-battle instrument); (2) amph-specific role/terrain
logic in CircuitAI (diver/submarine gates, water threat layer). Attribute
before touching either.
ATTRIBUTION 1: retreat threshold is NOT it (floor 0.08 + cost/3000 caps
Platypus at 17% hp, Triton at 50%); no amph gate exists in fight logic
(grep: amph only affects squad grouping affinity). Remaining suspect is
the standoff ring holding short-range rows at the squad's longest range
-- apex_brawl_pass is the existing arm, re-test with the big-battle
instrument; if positive, flip its default.

## 2026-08-29 — THE CONVERSION FAILURE: a 3.5x economy loses the 1v1 anyway

Measured on decision-length games (50m caps, 8 per map, winrate-comet /
winrate-glacier): decided results 2-10 vs stock overall. On Comet we led the mex
race 18v14 @15m, 45v29 @25m, 102v29 @35m — three and a half times their economy
— and went 2-6. Five of those six losses ended with OUR COMMANDER dying at
fwd 0.00-0.18 (AT HOME) between 18.7m and 32.7m: the economy never killed them,
the game ran long, and one breach decapitated us.

The eco lead converts into mexes, not into finishing power or commander safety.
Suspects, unattributed: the killing blow not firing or not finishing on a won
economy; home defence plus army-at-home losing to the late push despite wealth;
overflow (12% metal-wasted flag) meaning the lead is partly paper. Use
decision-length games and the death ledger — a 6-game arm cannot see this.

## 2026-08-29 — UpdateWithdraw throws "Index out of bounds" (FIX LANDED, awaiting a clean game)

2 occurrences in one battery game, 7 in the first 14 min of the 08-29
Small_Supreme watch (Function: void UpdateWithdraw(), Line: 500 — the
gCombatSent[i] region, withdraw.as). ROOT CAUSE READ FROM THE CODE, not
raced: pass 1 walks the registry descending and removeAt(i) on a dead
entry shifts every aliveSlot already cached (all recorded from ABOVE i)
down one — pass 2 then reads a neighbour's reissue stamp, WRITES the
wrong unit's stamp even in bounds, and the highest cached slot indexes
past the end. Fix: each removal decrements every cached slot. Delete this
entry when a long game shows zero UpdateWithdraw exceptions.

## 2026-08-29 — flanking: charger question RULED, two structural gaps remain

His ruling (same day): Behemoths through the middle (slow), Titans may take
the side — and the classes were never actually conflated in code (armthor
has no melee attr; it is a colossus by cost and already rolls the flank
via). The charge doctrine (never recalled, richest-in-reach set-target)
landed in 0ab7ded. Still open, structural: (1) the flank via needs an
approach over apex_flank_min_dist=1200 — tight-map targets sit closer, so
his Glacier games saw zero flanks (vs 13 on Isthmus); (2) DEFEND-pool
fights, most of a defensive game, have no flank concept at all. Both are
design work, not knobs.

The geo-abandonment check (his ask: con abandoned a damaged build while
allied combat idled nearby) needs the `apex: con-retreat` line to carry
POSITION and the def under construction — both in scope at the log site
(BuilderTask.cpp OnUnitDamaged). Add on the next DLL build cycle, then the
audit joins it against BARAI_ARMY snapshots (idle = position-stable combat
units within ~800). The flank detector (every attack entered the enemy's
front arc) reads BARAI_ARMY tracks alone — no new field needed.

## 2026-08-29 — long-range survival: two residues after the walk-in fix

The walk-in orders themselves are fixed (radar-aware `prefer` gate + long-gun
hold in `CCircuitUnit::Attack`; `apex_arty_mass` routes mobile arty into the
squads — see the commit). Left open:

1. **The ride to the squad is still a raw fight order.** `CSupportTask`
   (snipers via the `anti_heavy_ass`→SUPPORT binding, mobile radar/jammer)
   walks recruits to the nearest squad with `CmdFightTo` straight-line to the
   path end (`SupportTask.cpp` Start/ApplyPath). A 455-sight sniper crossing
   contested ground on a fight order can still stop-and-trade on its own
   acquisitions until it arrives. Squads reposition it on arrival, so the
   exposure is the trip only.
2. **`apex_arty_mass=0` arm keeps the old CArtilleryTask** — statics-only
   FindTarget, raw engine attack, CFightAction travel. If the A/B retires the
   OFF arm, nothing runs that code; until then it is the control, not a fix
   target.
3. **"Build up their numbers"** (his 2026-08-29 ask) — long-range composition
   share untouched; the army market prices ARTY off enemy static cost only
   (`market/army.as` counter). Judge after survival beds in: units that stop
   dying compound on their own before any pricing change.

## 2026-08-29 — builder retreat trigger is a hair trigger (his policy call pending)

Every builder retreats at 80-89% health (`behaviour.json` `retreat.builder
[0.80, 0.89]`, per-unit roll) and walks to the crow-flies-closest haven.
Measured the first game the `apex: con-retreat` line existed (s11 2v2, low
contact): 8 switches in 20 minutes, armck at hp=0.85-0.86 walking 924, 1475
and 3218 elmos — his sighting ("long walk for no big gain") exactly.
Stand-and-heal (ec2913b) removes the walk only when the con is already
inside a haven's assist reach. RULED 2026-08-29 ("Threat-gate it"), after
the eco cost was measured: 43 con-retreats in one Glacier Pass game, corck
at hp 0.81 walking 2400-2900 elmos, 42 mex elections -> 12 standing mexes
vs stock's 17. LANDED (apex_con_scratch_gate, BuilderTask.cpp): above the
stand floor a builder retreats only when the known attacker's gun reaches
its spot or the threat map covers it; below 0.5 hp always retreats. Awaiting
a measured `con-scratch` vs `con-retreat` count on his maps to close.

## 2026-08-28 (night) — THE OVERFLOW CAMPAIGN: residue only

Nine goals, all LANDED and MEASURED (commits 709e550, 1d1f1b8, 224a8c4,
6bb4561, d3fe925, 860e8f0) — super-site relocation, the strategic market's
serialization when rich, the overflow ladder, T1 air after T2, front towers and
mex guards, the 156x exec loop, the eco-player AFK, nano turret reclaim, eco
cluster split. Both reserved rulings were taken: T3 pacing became
`apex_unit_afford_s` (60s of income fades every unit bid toward zero at the full
bill, no tier table) and front towers got `apex_def_setback` (250). What is
left:

- **armmex unreach-safe churn, 156-228 per game**: mex claims elected at spots
  the walker cannot safely reach. The refusals are correct; the elections are
  waste. Election-side threat pricing is the lever if it grows.
- **armmakr (T1 converter) reclaim-rebuild loop, 11-16 per game**: the converter
  obsolete law eats makers the convert want then re-buys. Same shape the plant
  retire law had; needs its own waiver/window pass.
- **Radar at the front dies why=unreach-safe** (290 sense execs for 29 radars) —
  deliberately NOT exempted: walking a builder into fire for an unarmed radar is
  a real loss. If forward intel is worth more than that, it is a pricing
  question, not an exemption.
- **Tower SITING depth is a policy ruling, not a bug.** Completion is fixed (47
  towers finished, 4 defence-task deaths in a 57.9-min game); elections win front
  sites and towers still land rear/mid. Superseded in practice by the wall entry.
- The task-die `why=` distribution is this family's instrument; any new face
  shows up there first. A LOSING base abandons everything (719 nanoframes in s43
  vs 87-312 elsewhere) — never read that as a regression without a same-outcome
  control.

## 2026-08-28 (night) — THE ORDERS-THAT-DON'T-STICK FAMILY (next campaign, top priority)

One disease, four faces, all measured today:
1. **Mex guards never materialize** (his report: "we turned off the logic to
   make sure we build defensive turrets on our mexes... we lose them all").
   NOT the pricing: in his watched game (watch-vsmedium-s125) asset sites
   WON the defence election **677 times and 14 towers were built** (10
   standing, all in the base core; mexFloor 1,890 and the target lifted
   correctly). 98% completion failure.
2. **Front towers**: wonFront=63, built 2, standing 0 (same game; standing
   ISSUES item since 2026-08-27).
3. **The eco commander's 156x exec loop** (same converter, same occupied
   square, engine refusing every order — fixed at the Take door by the
   backoff, but the PLACEMENT that returns occupied ground is unfixed).
4. **The abandonment class**: 42 nanoframes abandoned in one game
   (cormex=22), 'finish before founding' flagging all day.
The common shape: an election is won, an order is issued, and between the
executor and a standing building the order dies -- placement on occupied
ground, task killed same-frame, builder peeled/re-elected, frame never
resumed. The dig is the task lifecycle from `apex: exec` to BARAI_BUILD:
pick ONE won defence election from s125 and trace its task id to its
death. Note: the TaskRemovedInner exception storm (fixed tonight) was
ABORTING the removal hook mid-flight all day, so ledger drift and Forget
misses may have been feeding this family -- re-measure completion rates
FIRST on the fixed build before digging deeper.

## 2026-08-28 (late) — the eco commander's 156-exec loop IS the AFK

His "eco player goes AFK" reproduced on the 15m SI 8v8 tell
(matches/si8-fix2-15m-s104): t7 (rear specialist) commander idle 49% vs
10-20% line teams, income 32 m/s at 13m (POORER than the line players).
Mechanism pinned: corcom #20590 elected AND EXECUTED the same
convert:cormakr at the same position (367,9665) **156 times**, one per
task update, gain=1.17 -- the order never becomes a task that sticks and
nothing logs an abort (so the abort-backoff never trips; suspect the exec
returns an existing covered/held task the unit never walks to, or a
same-frame silent rejection below the TaskRemoved hook). Next session:
trace ONE of those execs through Requests::Take's branch logging (which
Log(want,...) label fires 156x) and the C++ task lifecycle. Also open:
WHY the rear economist is the poorest player at 13m -- its pocket runs
out of T1 work and nothing routes it to T2/mohos/assist; the commIdle
number on the tell is the regression check. (Residue moved from the deleted
ArmyTarget entry, same player: the eco-role election never fires on
line-abreast starts -- 0 of 92 targets samples showed eco=1.)

## 2026-08-28 (evening) — T3 production pacing: the early gantry's products eat the mid-game

The gantry-by-100-team-m/s change works as asked (elections 27.8-28.6min ->
7.4-10.9min, gantries FINISHED on both apex teams, T3 fielded 50-55k vs
8.4k) and costs nothing through minute 10 (income tracks the control
exactly). The damage is 15-25min: the standing T3 line pulls Juggernauts
(20k) and Demons (12k) into the mid-game, the army flatlines at 20m while
BARb masses 43 Goliaths, and s21's side income collapsed 1045->212 while
the control compounded 1836->2537 (side metal 776k -> 393k; s23 640k ->
543k). BARb won the same game fielding 3 KORGOTHS — T3 is not the sin,
SEQUENCING is: they bought mass first and T3 from surplus; we bought T3
instead of mass. The lever is production-side (what a T3 unit bid may cost
against income mid-game — an affordability ramp like the supers carry),
NOT the gantry want. Decide with apexearth before wiring: it is his
composition philosophy. Evidence: matches/gantry-on-s21 vs
matches/allyshare-on-s21 (same seed, same day, one change).

## 2026-08-28 — nano turrets cannot be told to reclaim (mechanism gap)

His ask: "We have a lot of constructor units & turrets which could be doing
this [reclaiming old buildings]." Turrets is the blocked half. Verified in the
DLL source: `CmdReclaimUnit` exists in C++ (`common/ReclaimTask.cpp:83`) but
has no AngelScript binding, and the static-task route (`TaskS::Reclaim` →
`CSReclaimTask`, `task/static/ReclaimTask.cpp`) is area-only AND aborts
whenever `IsMetalFull()` — exactly the overflowing-bank state where space
reclaim matters most. So idle nano lathe cannot be pointed at an obsolete
neighbour from script today. Fix is C++: either bind `CmdReclaimUnit` on
`CCircuitUnit` or a unit-target static reclaim task without the metal-full
abort. Until then reclaim parallelism is constructors only (the claim
registry in `want_reclaim.as`, 2026-08-28).
His note 2026-08-28 (night): "nano turrets were able to reclaim prior to
us doing the big reimagining of the AI so maybe it really is there but we
just didn't see it" -- consistent with the mechanism above: the stock
static reclaim task exists but aborts on IsMetalFull(), and at his +100%
regime the bank is pinned full, so it aborts always. The C++ fix is the
same either way: drop/gate the metal-full abort (space reclaim matters
most exactly when full) or bind CmdReclaimUnit.

## 2026-08-28 — the +100% spend bottleneck (his Titan complaint, half-closed)

At his regime the AI banks a third of its metal (his game 31%, seeds 14-15:
27%/34%). The all-quiet gate half is FIXED (overflow floors the army gap;
milreq 1,665 -> 4,412 and demand now flows). The remaining half: the lines
only SENT 948 orders against 4,637 requested (seed 15) — the spend cap is
now the facqueue's 15s-per-line buffer (LineWindow = FQ_WAIT x
apex_fac_queue) and/or the line count at high income (9 lines; the overLine
income-supported count). Next lever: scale LineWindow with the overflow, or
let plant demand read the overflow the same way. Measure on metal-wasted at
+100%, 35 min. Related singles: our gantry hit 21.1m (seed 14) vs 30.2m in
his game after the super-lane copy law — directional, one seed each.
