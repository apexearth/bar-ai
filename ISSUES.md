# Open issues — what is wrong with this AI right now

Restarted 2026-08-24. The previous file (1,767 lines) was written almost
entirely before the Brain overhaul of 2026-08-22/23 and described leaf-era
mechanisms that no longer exist. Recover it with `git show HEAD:ISSUES.md` if
an old entry turns out to matter.

**Rule for this file:** every entry names the run it came from and the log line
that shows it. No entry survives on reasoning alone. Delete an entry once a
measurement confirms the fix — not when the fix lands.

Evidence below is from `matches/20260824-021933-...` (4-team, Altair, "before")
and `matches/20260824-024703-...` (1v1, Altair, "after the category change").
These are different setups, so treat magnitudes as indicative and the log lines
as the real evidence.

---

## OPEN: every T2 lab is bought by a want the arbiter priced 6-17x too low

The category draw in `market/decide.as` gives `produce` one ticket per
election. When that ticket wins, the drawn want is bought regardless of how
far below the best want it was priced.

```
f=13865  produce/tech:armalab  v=5.94  over buildpower/assist v=33.97   ( 5.7x)
f=16977  produce/tech:armalab  v=3.44  over energy/energy     v=44.03   (12.8x)
f=23273  produce/tech:armalab  v=5.16  over energy/energy     v=88.84   (17.2x)
```

All three landed before the first mex upgrade (f=30217). Same shape in the
before-run: `coralab v=6.09 over 17.75`, `coravp v=0.58 over 8.66`,
`armalab v=1.46 over 5.43` — three of the four tech decides were upsets.

The stakes are asymmetric and the ticket does not know it. Losing a wind draw
costs 43 metal and 15 builder-seconds; winning a lab draw commits 2,900 metal
and then `JoinBig` pulls the fleet onto it for minutes. Overall upset rate
(winner priced below the runner-up) is 91/295 decides.

The draw itself is deliberate — winner-takes-all previously starved every want
that never ranked first. What is missing is any relationship between ticket
size and how irreversible the purchase is.

## OPEN: the overhaul kill removed 23,511 lines; some of it has no replacement

`fcbabf2` ("Overhaul kill") deleted 23,511 lines across 77 files, 26 of them
entirely. Most was correctly superseded by the Brain market -- `statics.as`,
`nano.as`, `fusion.as`, `converter.as`, `assist.as` all have `want_*` successors.
Three areas do NOT:

**Nukes -- RESTORED 2026-08-24.** `manager/brain/nukes.as` (536 lines) is back
verbatim from `fcbabf2^`; it had only three external dependencies
(`Builder::gHomePos`, `Factory::T`, `Military::ForwardFraction`), all still
present. `Brain::UpdateNukes()` is wired into `AiUpdate` and
`Brain::NoteSiloFinished` into `AiUnitFinished`, matching the pre-kill call
sites. 17 `TUNE_NUKE_*`/`TUNE_ANTI_COVER` consts restored with pre-kill
defaults (`TUNE_BRAIN_NUKE` already existed -- a duplicate const is a
`Name conflict` that disables the whole variant, caught in smoke test).
Compile-clean over a 21-minute game. NOT EXERCISED: a 1v1 at this income never
reaches a silo, so the director ran dormant. Validation needs a long,
high-income game.

**Commander safety -- gone.** See the entry above.

**Air eco-assassination -- doctrine REPRICED 2026-08-24, production still
ORPHANED.** apexearth 2026-08-24 on what this is for: "we build up a sufficient
airforce to do a raid and try to kill enemy home base economy (ie blow up their
AFUS to cause a huge chain reaction)."

Surviving (905 lines in `manager/air/`): the doctrine and its gates in
`air/state.as` (`AIR_FROM` 11 min, `AIR_MIN_INCOME` 40, `AIR_AA_CEILING` 2500,
`ScaledBombers()` scaling the strike with income), the per-ally-team election in
`air/election.as`, and `update.as`/`wing.as`/`station.as`.

Deleted and not replaced: `manager/air/factory.as` -- `NextAirDef`,
`EnqueueBatch`, `MakeFactoryTask`, the code that actually queued the bombers --
and `manager/factory/airsupport.as`.

The break is total, and verified two ways:
- `grep` for `ScaledBombers|gAssassin|IsAssassin` outside `manager/air/`
  returns NOTHING. No consumer reads the assassin's demand.
- `grep -niE "air|bomber|fighter"` over `manager/brain/facqueue.as`, which now
  owns ALL factory production, returns one unrelated comment.

So the assassin can be elected and then nothing builds its airforce. Note also
that the election never fires on the standard benchmark: the log reads
`no air assassin, best ally income 22/40` -- `AIR_MIN_INCOME` is deliberately
above benchmark income, so this can only be judged in a hosted game.

**Landed 2026-08-24** (compile-clean, 22.7-minute game):
- `AIR_AA_CEILING` is no longer a veto. apexearth: "if there is AA we can still
  sometimes overwhelm them... 50 or 100 bombers coming in from different angles,
  some will likely get through." `Armed()` and the mid-buildup abort now consult
  `StrikeWorth()`; AA enters as a price, never a wall.
- `EcoDensity()` -- enemy cost sampled in one cluster radius around their
  centroid, the proxy for how packed their base is.
- `Throughput(n)` -- wing HEALTH soaks AA, so mass dilutes it: `soak/(soak+aa)`,
  never zero.
- `ScaledBombers()` grows with enemy AA and lost its flat `AIR_BOMBERS_MAX` cap.
- Heavy bomber tier `gBomberH` added to the election, which previously could not
  reach it at all: `corcrwh` Dragon (16,700 hp / 5,100 m), `legfort` Tyrannus
  (16,700 / 5,600), `armblade` Hornet (3,000 / 1,250).
  **`corcrw` is built by NOBODY** -- it is the legacy twin of the buildable
  `corcrwh`, identical stats, and requesting it would have been silently
  dropped. Caught by `tools/unitdef.py corcrw --builders`; check every new def
  that way.
- Atomic bomber tier `gBomberN`: `armliche` Liche (2,300 hp / 2,200 m),
  Armada only -- Cortex and Legion have no atomic bomber and get the heavy hull
  instead. apexearth: "light bombers are the best choice for Armada oftentimes.
  Nuke bombers can get thrown into the mix too - sometimes that's a huge pain
  for players to deal with a mix of threats." The mix needs no special term: the
  production draw is proportional, not winner-take-all, so every tier carrying
  positive gain gets bought in proportion to it.
- `Bombers()` now counts all four tiers. It counted only the original two, which
  would have left the wing permanently short of `ScaledBombers()` and never
  reading as massed.

**Armada has no true heavy** -- a real faction asymmetry, and the reason its mix
is light bombers plus Liches rather than Dragons.

**Production wired 2026-08-24.** `Air::StrikeGainFor(def, fillSec)` prices one
more bomber of a given type against the whole raid that type would need, and
`Market::ConOrderFor` enters it as an ordinary candidate in the proportional
draw. Not a gate: a raid that does not pay returns zero gain and the line builds
army as before.

**RESOLVED by measurement, not by modelling.** The HP-soak prior ranks cheap
bombers above heavies: Worked at 8k enemy AA, 40k eco density:

| | needed | throughput | strike cost | return on cost |
|---|---|---|---|---|
| Archaic Dragon (16,700 hp, 5,100 m) | ~20 | 0.70 | 102,000 | 0.27 |
| Hailstorm (1,520 hp, 310 m) | ~120 | 0.53 | 37,200 | **0.57** |

Light bombers win because BAR prices hp/metal in their favour (4.9 vs 3.27), and
`dmg = EcoDensity x Throughput` caps damage at what the cluster holds regardless
of who delivers it -- so cheap mass always looks better. apexearth's read is the
opposite: "20 of those and the enemy will definitely have a hard time."

That prior is CORRECT as a prior. apexearth: "I would certainly try a hailstorm
bombing run first... they're also faster moving. If you were able to gauge the
success of a bombing run then that tells you if hailstorms are viable. Sometimes
you don't know until you try."

So the fix is a feedback loop, not a better guess. `NoteStrikeLaunched()` records
the type, the count sent and the target cluster's value; `SettleStrike()` scores
the run `apex_air_settle_s` (90s) later from the drop in cluster value and how
many bombers came home, and EMAs both into `gObsSurv`/`gObsDmg` per def.
`Throughput()` and `StrikeGainFor()` prefer the measured numbers over the prior
the moment a type has been scored once -- so flak splash, interception and the
flight home are all counted without any of them being modelled.

The behaviour that falls out is the one described: fly a cheap Hailstorm probe
first, and if it dies for nothing, its measured survival collapses and Dragons
win the next draw. Log line: `apex: air run scored def=... sent=... home=...
surv=... dmg/bomber=...`.

Both estimates are crude -- the cluster also loses units to our ground army, and
reinforcements refill it -- which is why they smooth rather than replace.

**102 tunables in `tunables.as` now document files that do not exist:**

| dead file | orphaned tunables |
|---|---|
| mexguard.as | 21 |
| statics.as | 19 |
| nukes.as | 18 |
| assist.as | 9 |
| nano.as | 8 |
| obsolete.as | 8 |
| fusion.as | 7 |
| rules_commander.as | 6 |
| converter.as | 5 |
| crew.as | 1 |

This matters more than dead code usually would: `tunables.as` exists BECAUSE
apexearth asked for one file he could tweak without asking (its own header says
so). ~102 of its entries are knobs that now change nothing, with comments
confidently describing behaviour that was deleted. Either the readers come back
or the entries go.

Recovery is `git show d95e06e:<path>` -- the pre-kill tree is intact in history.

## LANDED 2026-08-24, benchmark CANNOT validate it: commander self-preservation restored

apexearth 2026-08-24, watching: "our commander was getting shot by enemies and
he did *nothing* to protect himself."

He is right that nothing runs. The cause is NOT that it was never written --
it was written, evolved over several commits, and deleted with the rest of the
leaf rules in `fcbabf2` ("Overhaul kill"). `ai/ord/.../builder/rules_commander.as`
at `d95e06e` carries three working behaviours, none of them ported to the Brain:

1. **Health retreat** -- below `COM_RETREAT_HEALTH`, and only while
   `ThreatFor(here) > CON_THREAT_VETO`, call `aiBuilderMgr.EnqueueRetreat()`.
   The local-threat condition exists because firing on health alone left him
   "cowering at the back at 50% health" (apexearth, watched); once safe it falls
   through to the DLL's own `MakeCommPeaceTask`/`MakeCommDangerTask`.
2. **Back-wall hide** -- on `BaseUnderAttack()`, relocate by taking a job at
   `RearPos` (a solar), or `EnqueueRetreat()` outright when energy is full.
3. **Abandon a hot site** -- if the held task's build position reads
   `ThreatFor > CON_THREAT_VETO`, retreat instead of standing there building.

**The safe primitive is `aiBuilderMgr.EnqueueRetreat()`, NOT `CmdMoveTo`.** The
original `UpdateCommanderSafety` used `CmdMoveTo` and "correlated with 14-17
engine aborts per 20-game run"; it was replaced for that reason, and the
commented-out call at `posture.as:628` is the corpse of that FIRST version, not
of the working one. Do not read that comment as "retreat crashes the engine".

Current state, verified by direct search of the whole `ai/Unstable` tree:

- `manager/military/posture.as:628` -- the only commander safety hook is a
  COMMENTED-OUT call: `// Builder::UpdateCommanderSafety();`, with the note
  "DISABLED: engine aborts (exit -1003) jumped sharply the moment this landed.
  Either CmdMoveTo issued outside a task context or GetEnemyCostAt's
  GetEnemyUnitsIn walk is unsafe here." Grepping the tree for that symbol
  returns ONLY this commented line -- no definition exists anywhere. There is
  nothing to re-enable.
- `misc/commander.as` -- `Commander::UpdateCaution()` runs every tick but is
  telemetry only: it sets `gCautious` and logs it. `gCautious` is written at
  lines 29/36/37 and read at line 52 (the log string). Nothing acts on it.
- `misc/commander.as:196+` -- the entire `Hide` namespace (threat/air-based
  hiding) is inside a `/* */` block comment and is not compiled.
- `tunables.as` documents a commander retreat health fraction, a force-march
  clock and a hiding ring, all attributed to `manager/builder/rules_commander.as`
  -- a file that does not exist in this variant. Orphaned documentation for
  logic deleted in the Brain overhaul and never ported.
- The one surviving commander rule (`market/decide.as`) only refuses to SITE a
  new build want more than 400 elmos forward of the base anchor. It never looks
  at his health and does nothing once he is under fire on an existing task.

**Restored** as `manager/brain/market/safety.as` (`Market::CommanderSafety`),
called from `Decide` BEFORE the finish-what's-started early return -- a
commander with progress on a frame would otherwise never reach it, which is
exactly the state he dies in. Carries the caution test (fielded HEAVY+SUPER at
half his cost, or post-T2 mobile massing at 2x), the forward-work refusal, the
influence flee (ring-sampled while cautious), and the low-HP retreat with the
critical-HP raw steer. Seven `TUNE_COMM_*` tunables restored with their original
defaults; `apex_comm_rules` is the master toggle and is modoption-tunable.

Two deliberate omissions from the original: pack-spreading (needs `AllyCommNear`
and `SolarDef`, both deleted -- matters for 8v8 chained commander explosions,
not for 1v1) and `Factory::gEnemyT2Seen` (sense deleted; the caution test uses
our own `Factory::gHaveT2` as the progression split instead).

**A/B, 6 seeds, master toggle on vs off, same build:**

| | comm deaths | mBuiltReal | mex | t2Mex | flee lines |
|---|---|---|---|---|---|
| safety ON | 0/6 | 14,350 | 12.5 | 0.0 | 1 |
| safety OFF | 0/6 | 15,235 | 14.5 | 0.5 | 0 |

**The commander does not die in either arm, so this benchmark cannot measure the
thing the feature exists to prevent.** What it can measure is the cost: about 6%
of metal and 2 mexes, inside a spread of 5,810-26,110. Judge this from a watched
hosted game, not from here. Do not "tune" it against these numbers.

## OPEN: ProposePlant dedups on FINISHED plants only -- two of the same plant get bought seconds apart

apexearth 2026-08-24, watching Altair_Crossing_V4.1: "we often make two t1 labs".
Confirmed in `matches/20260824-043712-...` (seed 4), which built
`armap:1420, armlab:500` -- TWO Aircraft Plants (710 each) plus a Bot Lab:

```
f=24369 con#393   produce/plant:armap v=284.49
f=24449 con#8485  produce/plant:armap v=292.34     <- 80 frames later, different con
```

Two constructors 2.7 seconds apart each elected to build an Aircraft Plant.
Neither divided its gain, because `ProposePlant`'s `reachKin` counts only
FINISHED plants -- `Catalog::Def(d).count` and `gOwnCount` -- and no armap had
finished yet. This is the async-order window the `async-sim-orders` skill
covers: the read lies during the walk phase.

`ProposeTech` already guards exactly this, two ways: `Requests::LiveOfDef(def)`
skips a def that is already requested, and `liveKin` counts live kin plants in
`Requests::gLive` and divides the demand among them. `ProposePlant` has neither.
The only live-aware check it has is the top-level
`Factory::gFactoryCount + Requests::LiveCountOf(FACTORY) >= supported` gate,
which bounds the TOTAL factory count, not copies of one def.

Second, separate cause of "two T1 labs": `reachKin` only counts a plant as a
duplicate when `kReach >= myReach && kAir == myAir`, so a ground Bot Lab and an
Aircraft Plant are never duplicates of each other and each prices as if it were
the first plant. That air/ground split is deliberate (the comment reads "we want
multiple T2 air labs, not T1 air labs"), but its side effect is that the first
air plant is never deduped against the ground lab it duplicates in the T1 role.
Seen in 2 of 6 recent runs as `armap:710, armlab:500`.

Same bug SHAPE as the tech channel-2 entry below: dedup logic that ignores work
already in flight, or that partitions on an attribute the duplicate does not
share.

## OPEN: the tech want's mobility channel buys a second same-tier plant on speed alone

`ProposeTech` channel 2 fires when a plant's constructor is >1.2x as mobile as
anything owned (`prodMob > ownMob * 1.2`). BAR's T2 vehicle constructor is 1.5x
the T2 bot constructor's speed (`coracv` 49.5 vs `corack` 33), and
`MobilityMult` = 60/(walk/speed + 12), so the ratio lands 1.23-1.36 across walk
distances of 500-1500 -- the gate clears essentially always. Once a T2 bot lab
stands, the T2 vehicle plant prices itself in, unlocking no new reach.

Unlike channel 1, **channel 2 has no kin division**. Channel 1 divides its gain
by `(1 + liveKin)` so demand splits among the pipes already serving it; channel 2
prices the mobility delta against the ENTIRE upgrade demand no matter how many
plants already work that stream.

Confirmed against `matches/20260824-021933-...`: `tech:coravp gain=2.66` at
f=32449 with `upD=15.76` matches `15.76 x pipe(2.0) x (1.30-1) x funded(0.50) x
latency(~0.5) = 2.4`. Channel 1 would have produced 31.5, an order of magnitude
more, so the mobility channel is the source.

It nonetheless priced LOW and was bought by the draw anyway (`v=0.58 over 8.66`,
a 15x upset), so the kin division is the smaller half of this. Fixing channel 2
makes the want weaker; the draw would keep buying it.

NOTE: at the current default this is not currently firing -- all four sweep runs
built exactly ONE T2 plant (`allBuilt` shows `armalab:2900`, one lab). Two plants
appeared in the 021933 baseline (`coralab:2900, coravp:2800`). Judge this on
`allBuilt`, never on the `produce/tech` decide count -- a decide can be a
re-election, and reading decides as buildings produced a wrong "2 labs" report
2026-08-24.

## OPEN: the displacement charge exempts exactly the builds that displace most

`ValueOf` in `market/price.as` charges an expensive build for the mex-upgrade
stream it postpones, but only inside `if (feedSec > buildSec)` — i.e. only when
metal income cannot keep the build fed. A def with a huge buildtime has a
`buildSec` so long that income always keeps up, so the gate never fires and the
charge is zero.

Two fusion decides 66 seconds apart, before-run:

```
f=15929  energy:corafus  m=9736  t=1348   (buildtime 329,200)
f=17601  energy:corfus   m=4973  t=6925   (buildtime  75,400)
```

The cheaper, faster building was charged 5x more builder-time. Pure walk+build
time for corfus should be roughly a quarter of corafus's at the same fleet, so
`displacedM` is ~6,600 on the fusion and ~0 on the AFUS — while `tech-diag`
reported `upD=39.5` m/s of unserved upgrade demand at that moment.

A build that occupies the fleet for ~900 seconds displaces more, not less. The
gate should key on occupation, not on which of two durations is larger.

## LANDED 2026-08-24: the energy floor now nets out the converter that realizes it

`EPriceFloor()` treated a conversion ratio as a free exchange rate. It is not
(apexearth: "we have to have a converter for that to even be true"). The floor
now amortizes the converter's metal, its own energy bill and its build time
against the metal it makes over `apex_conv_horizon` (600s, a CHOSEN number, not
derived), solved directly for P since the converter's cost is denominated in the
price being computed.

Two bugs fixed together: the floor was also taken from the best converter in the
whole catalog -- the T2 converter at 0.01724, above the T1 at 0.01429, from
frame zero -- with no check that anything we own could place one. Now restricted
via `CanBuildEver`.

Four runs after (`matches/20260824-0323*` .. `-032616`), all compile-clean:
T2 labs 1/1/1/1 (was 3 in the run before), zero AFUS decides in any run,
mex upgrades 25/6/13/1. Not attributed -- the AI is multithreaded and the
before-side is a single run.

`apex_conv_horizon` is 300s -- short on purpose (apexearth: "it pays off
eventually and that's fine; by the time this stuff matters less we're on to
fusions and afus"). Measured with `--modoption apex_efloor_diag=1`
(`matches/20260824-033449-...`):

| phase | floor | E-per-metal |
|---|---|---|
| early, build power scarce | 0.01209 - 0.01256 | **80:1 - 83:1** |
| late, build power plentiful | 0.01327 - 0.01333 | **75:1** |

Against the flat 0.01724 (58:1) the old code used from frame zero. The penalty
is largest exactly when build power is scarce, which is correct and is where it
decides wind-vs-moho.

It does not reach 80:1 late because the arithmetic honestly says a T1 converter
IS nearly free at high build power -- 2,600 buildtime against a 1,400-BP fleet
is under 2 seconds, so its net approaches the raw ratio. Getting late-game into
range needs a utilization term (nameplate `energyconv_capacity` is never fully
chewed), not a shorter horizon.

Minor: the winning def logs as `armfmkr`, the SEA converter, because its cost
and ratio are identical to the land `armmakr` and it sorts first. Harmless here;
it would misprice if a faction ever shipped a cheaper water-only converter,
since `CanBuildEver` does not ask whether the site is placeable.

**This does not touch the wind spam.** `EPrice()` returns `max(premium, floor)`
and the premium is ~0.093 against a floor of ~0.0148, so the floor never binds
for a wind turbine: mean `corwin` bid moved 33.9 -> 31.9. The floor binds only
where `EPriceAt` has decayed the premium away, i.e. on long builds -- which is
why the AFUS decides disappeared and the wind decides did not.

## TESTED 2026-08-24, DO NOT SIMPLY LOWER: energy's permanent scarcity premium

`EPrice()` multiplies energy pull by `apex_e_headroom` (1.75) before measuring
shortage, so `excess` reads 0.75 even when energy income exactly equals pull.
Energy is then priced as if permanently in shortage. The premium cannot be
cleared: building energy raises income, the fleet it feeds raises pull, and the
multiplier is applied to pull.

Measured against BAR's own exchange rate (`energyconv_efficiency = 0.01429`
M per E):

```
corwin   mean v=33.92  (gain 2.32 on windgenerator 25)  -> implied 0.093 M/E  =  6.5x floor
corfus   f=18457 gain=250.11 on 1100 E/s                -> implied 0.227 M/E  = 15.9x floor
```

Consequence in the before-run: 672 of 682 energy decides were `corwin`, a
43-metal wind turbine, against 1 mex upgrade all game. Priced at the converter
floor, wind bids v≈5.1 — below the moho's 9.05. The premium alone inverts the
order.

**A/B run 2026-08-24, 4 seeds each, same build, headroom varied by modoption
so nothing else differs. Lowering it is worse on every measure:**

| headroom | t2Mex | mex | mBuiltReal | wind decides | mexup | tech |
|---|---|---|---|---|---|---|
| 1.75 (default) | **1.0** | 19.0 | **18,365** | 234 | 9 | 2 |
| 1.0 | **0.0** | 17.5 | 16,690 | **320** | 6 | 4 |

T2 mexes appeared in 3 of 4 games at 1.75 and 0 of 4 at 1.0. Wind decides went
UP when energy was made cheaper -- the tell for a feedback loop: under-priced
energy means less of it gets built, we actually run dry, the
`eCur < 0.25*eStore` clause spikes `excess` to emergency levels, and wind gets
panic-bought anyway from a worse position. Same failure already recorded at the
`EPrice` call site ("we e-stalled and should have made a basic solar").

So the premium is real AND load-bearing. The mechanism description above stands;
the obvious fix does not. Anything that touches this must keep supply leading
demand -- the honest lever is probably the anticipation term
(`gEPullGrowth * apex_e_lookahead`) carrying the intent instead of a flat
multiplier, but that is untested and the flat multiplier currently wins.

Variance is high (wind decides ranged 139-814 within one setting), so n=4
medians are weak. Do not re-open this on a single run.

## LANDED 2026-08-24, needs a controlled measurement: wants compete by category

`market/kinds.as` now groups the 12 want kinds into 6 categories
(metal/energy/produce/buildpower/defence/reclaim). One lottery ticket per
category, weighted by that category's best want; argmax inside the winner.

Confirmed working in the after-run: mex upgrades went 1 -> 5 decides, and 4 of
the 5 won on price rather than on a draw (`armmoho v=12.58 over energy v=2.80`).
AFUS now lands after the first moho (f=35249 vs f=30217) instead of before it.

Not yet confirmed: the projected drop in energy's share of decides did not
appear (56% -> 60%, uncontrolled comparison). `geo` and `store` almost never
propose and `convert` fired 11 times in the before-run, so energy held about
two tickets, not four — the de-duplication was smaller than projected. Needs a
same-setup control before the entry is deleted.

## OPEN: none of the air assassination work can be measured on this benchmark

`AIR_MIN_INCOME` is 40 metal/s and deliberately "out of reach of the 4v4
benchmark" (its own comment). Benchmark logs read `no air assassin, best ally
income 22/40`, so the elector never fires, no wing is built, no run is scored,
and the feedback loop never gets its first sample. Everything landed 2026-08-24
is compile-clean over full games and DORMANT here.

It can only be judged in a hosted game. First thing to look for is the
`apex: air run scored` line -- until one appears, the loop is running on its
prior and the assassin will prefer the cheap fast bomber.

## LANDED 2026-08-24: AA was unbuyable, army gifting defaulted on, Juno bought as a turret

Three from one watched game (apexearth).

**Static AA could not be bought at all.** `ProtClassOf` files every static
defence into a protection class; its last test was `gSurfT > 0.5 * gAirT`, a
ground-shooting weapon. An anti-air tower fails that and fell through to
`return -1` -- no class, so `ProposeProtect` skipped it every time, and there was
no AA branch to reach anyway. No amount of being bombed could produce a tower.
The air-threat SENSE was fine (`AirThreatNow()` updates from `posture.as:622`);
what died with the leaf rules was its consumer -- `HeavyAAWant()` still sits in
`airthreat.as` with no caller.

Fixed: new `PROT_AA` class, and a protect branch priced off `AirThreatNow()`
(this tick's reading, not the 240s EMA, so a raid is answered as it develops).
Gain is the value at risk capped by the air they actually field, divided by the
towers already standing -- coverage scales with their air and stops on its own,
no count and no cap. `apex_aa_urgency` (4.0, CHOSEN, matching the shield
branch's multiplier) prices air above ordinary insurance.

Measured, 33-minute 4v4 where BARb fielded `corshad`/`corhurc`/`corvamp`: Apex
teams built `mDefAA` 80/480/1120 and 21 AA units. A 1v1 where neither side flew
built none -- correct silence, not a dead path. NO A/B: there is no toggle for
the branch, so the "zero before" claim rests on reading the code path.

**Army gifting now defaults OFF.** `apex_gift_army` already existed and simply
defaulted to 1. apexearth: "we should disable that by default. It only is
appropriate on certain maps." Confirmed silent over a 33-minute 4v4.

**Juno blocked.** A Juno is a one-shot area weapon against radar, jammers and
minefields; it carries a weapon and has no build options, so `ProtClassOf` filed
it as ground defence and the protect want bought it as a turret. 640 metal in one
measured 4v4. Blocked in `Catalog::BlockedDef` -- the single `gAvailable`
chokepoint every want already checks, so no proposer needed changing. Lift with
`apex_allow_juno=1`. Verified 0 metal into Juno after.

## 2026-08-24 — danger pricing, forward defence, sensors

### OPEN: a cheap want that needs a walk can never complete
`decide.as` re-elects every 2s and only holds a task with `Progress > 0.01` or a
site within 600 elmos. Combined with the category roulette, any LOW-value want
whose site needs a walk is abandoned mid-approach and re-bid forever.
Measured: 38 `sense/sense:armrad` decides and a created request
(`request new armrad inFlight=1`) in one 28-minute 4v4 — **zero radars built**.
Radar was not special; it is the cheapest distant want, so it shows the effect
first. Suspect the same mechanism starves other cheap-and-distant work.
Not yet fixed. A hysteresis on re-election (only switch if the new top is
meaningfully better than the held want) is the obvious candidate, but it is a
change to the core arbiter and needs its own measurement.

### FIXED-PENDING-CONFIRMATION: sensors never competed
All seven protection classes argmaxed for ONE `WK_PROTECT` slot, so ground
defence — whose gain is loss prevented outright — beat radar/jammer/targeting
every time. Measured across twelve 4v4 games: **zero sensors of any kind built**.
Split into `WK_SENSE`/`CAT_SENSE` so seeing and shooting draw separate tickets
(the same rule already applied to energy). Jammers now build; radar is still
blocked by the walk-abandonment issue above.

### FIXED-PENDING-CONFIRMATION: radar coverage was a boolean at one point
`want_protect.as` skipped the radar class if any radar stood within
`gRadarR[CANDIDATE] * 0.8` of the farm, and never varied the position from the
farm — so a 60-metal armrad permanently blocked the 3500-range armarad, and
coverage never followed the front. Now tested against each STANDING radar's own
range, sited at the nearest unwatched front post or mex, and priced by the
unseen share so it self-limits.

### MEASURED: our own base is uncovered by our own guns
`home[short=...]` in the `apex: risk` line read **1.00 in 42 of 64 samples** —
i.e. standing turret coverage stops none of the local threat at home. This is
the measured form of "our defenses don't seem good enough", and it is also why
the tech survival discount cannot yet discriminate: danger is high *always*, so
the discount is close to a constant factor rather than a signal.

### NEGATIVE RESULT: tech survival discount is unmeasurable on this benchmark
`TechSurvival` (gain discounted by `HazardAt * ShortfallAt` over the pipeline
latency plus affordability time) is wired and compile-clean, gated by
`apex_tech_survival`. A/B of 6+6 games showed **no detectable effect**: first-T2
4.8-10.0 min treated vs 4.3-8.7 control, fully overlapping. Expected — see the
uncovered-base finding above. Left on by default; re-measure once forward
defence produces variance in home coverage.

## 2026-08-24 (2) — the danger sense read zero at home

### FIXED: our own base was the safest place on the map, by construction
`ExposureAt(pos)` is `distance(pos, home) / apex_expose_r`, so it is **exactly 0
at home**. It multiplied two things:
- `ThreatM`'s cold-start baseline (`EnemyCostOf(RAIDER) * ExposureAt`) → the
  expected wave size at home was 0.
- `HazardAt`'s arrival term (`ExposureAt * foe/(foe+defended)`) → home hazard sat
  on `apex_risk_floor` all game (measured: 1.25/ks, the floor exactly).

Consequences, both measured and both reported by apexearth while watching:
- `ShortfallAt(home) = 0` ⇒ every turret's gain at home is `stake * hazard * 0`
  ⇒ **no base defence is ever worth buying** ("2 enemy units just destroyed our
  entire base. We made 0 defenses").
- `TechSurvival = 1/(1 + hazard*shortfall*T)` with shortfall 0 is **exactly 1.0**
  ⇒ the tech discount never fired at all ("we made a T2 lab REALLY EARLY and
  were working on that while our base was completely destroyed").

Fix: removed the `ExposureAt` factor from both. Wave SIZE is the same wherever
it goes; how OFTEN it arrives is `HazardAt`'s job, and position still enters
there through `CoverAt`. This is what `coverage.as`'s own header already said.

Measured, 6+6 games, 1v1 Altair Crossing, Apex vs BARb stable hard:

| | before | after |
|---|---|---|
| metal produced | 14,012 | **32,897** |
| mex | 12 | **18** |
| mDefence | 368 | **1,930** |
| army (real) | 140 | **545** |
| metal wasted | 2,779 | **1,604** |
| games lost | 6/6 | 4/6 (2 survived to the time limit) |

### OPEN: threat magnitude is still too low at home
Even after the fix, `home short=0.00` persists. `ThreatM`'s baseline is
`EnemyCostOf(RAIDER)` only — measured at 84-147 metal in a 1v1 — while one
`corhllt` contributes `600 * apex_def_trade(2) = 1200` of "wave stopped". So a
SINGLE tower saturates coverage at home and no second one is ever bought.
Two candidate levers, neither yet tested:
- the baseline should reflect what can actually concentrate on the base (their
  mobile mass), not just the raider role;
- `apex_def_trade = 2` claims a turret stops twice its own cost in attackers.

### OPEN: `covered=N` in the risk log was a boolean and lied
It counted "some turret's range reaches this mex", so one HLLT printed
`covered=3` while all three mexes died (apexearth: "the 3 mexes were not
covered, theres no way"). The line now also reports `meanShort=`, the share of
the local wave our guns do NOT stop, which is the number the gain math uses.

### OPEN: constructor over-investment in 1v1
1v1 baseline showed 10 constructors / 1,320 metal in cons against 140 metal of
army, with 2,779 metal wasted. Suspect the new `BacklogM` term in `BPGap`
(landed today) since `BPGap` also gates factory con-orders. NOT yet A/B'd --
`apex_bp_backlog_s=0` disables it.

## 2026-08-24 (3) — the arbiter was thrashing, not building

### FIXED: builders abandoned every walk, so distant work never happened
`decide.as` re-elected every 2s and only held a task with `Progress > 0.01` or a
site within 600 elmos. A builder electing anything further away walked, re-rolled
mid-walk, and abandoned. Measured in ONE 1v1 game:
**461 decisions to build a `corllt`, 21 requests created, ZERO defences standing
at the end** -- and defence was winning 46% of all constructor elections (579 of
1266). Constructor time, which is the economy, went almost entirely into walking
away from the previous decision.

Fix: a builder that is genuinely CLOSING on its site holds it. One that has
stopped closing (blocked, or the site moved) re-elects as before. Per-unit last
distance in `gApproachD`.

Measured, 6+6 games, 1v1 Altair:

| | thrashing | committed |
|---|---|---|
| metal produced | 19,970 | **27,444** |
| defence metal | 1,305 | **2,445** |
| army | 210 | **540** |
| metal wasted | 1,661 | **1,089** |
| `corllt` decides | 461 | **38** |
| defences standing | none | cortron/corhlt/cormaw/corhllt |

### FIXED: enemy standoff was ignored in coverage
`CoverAt` asked whether a turret reaches the TARGET. The attacker never stands on
the target -- it stands at its own weapon range and shoots in, so a turret that
barely reaches a mex denies nothing (apexearth: "an enemy can just stand right
next to that mex and still shoot it, while staying outside the range of the
turret"). Coverage is now measured on the ring the enemy can shoot from, valued
at the WEAKEST bearing, using `Military::FoeReach()` (max observed enemy group
weapon range, decayed). `apex_standoff_cover=0` restores the old test; measured
worse with it off (defence 90 vs 1305, army 0 vs 210).

### FIXED: the T2 lab was sited at the constructor's feet
`InteriorSite` fell back to `here` -- the asker's own position -- whenever no
nano farm existed. A con that had walked forward to claim a mex therefore put the
T2 lab on the front line (apexearth: "we just started T2 lab in a dangerous area
... off to the side is a smarter location than in the direct path"). Now falls
back to a rear FLANK of the anchor, which also removes the builder-in-its-own-way
inefficiency he noted.

### OPEN: unscouted still reads as safe outside the tech price
`Front::FoeKnown()` now forces shortfall to 1.0 inside `TechSurvival` only. The
same prior applied globally inside `HazardAt` repriced every want and cost 87% of
standing army (measured, 6 games) -- reverted. Scouting itself is untouched:
apexearth asked for scouts ("if we don't know the enemy strength then we
shouldn't be making a T2 lab... we need scouts") and nothing yet raises scout
production when intel is stale.

### OPEN: army production is starved by constructor orders
In 1v1, 80 of 137 factory orders were constructors (corck 42, corch 38) against
43 army units. Not caused by the new `BacklogM` term -- A/B'd with
`apex_bp_backlog_s=0`: metal 20,754 vs 19,970, army 140 vs 210, neutral.

## 2026-08-24 (4) — THE BENCHMARK CANNOT RESOLVE THESE CHANGES

Ran the SAME build twice, 6 games each, 1v1 Altair:

| | run A | run B |
|---|---|---|
| metal produced | 16,065 | 18,786 |
| defence metal | 180 | **682** |
| constructors | 12 | **6** |
| army | 145 | 210 |
| metal wasted | 1,357 | **3,070** |

Defence swings 3.8x and constructor count 2x on UNCHANGED CODE. That is the
same magnitude as most deltas reported earlier today, including the "net
regression" (27,444 -> 14,910) that caused `apex_def_net` to be defaulted off.
**Those economic medians were noise and should not have been reported as
results.** Judge these changes on log-level mechanism counts instead -- decides
vs things actually built, positions, shortfall readings -- which are direct
observations and were the findings that held up.

### LANDED, each verified by log evidence rather than by medians
- Commander FIGHTS (`safety.as`): he was never handed a fight task anywhere;
  `Role::COMM` appears in the whole military layer only in unblock code. Now,
  while `CommCaution` is false (i.e. before heavies are fielded), he goes at the
  nearest enemy group on our own half that he outweighs AND that is worth more
  than the round trip costs at `Wage()`. First cut chased a 1-metal scout six
  times; with the wage test it engages a 120-metal raid. `apex_comm_fight=0`
  restores the flee-only commander.
- Jammer gated on enemy INDIRECT FIRE (arty + half skirm >= 200). It was priced
  on total assets and won an early sense ticket ahead of sentries and mexes
  (apexearth: "we're making a jammer long before it would ever provide value").
- `apex_def_net` defaulted OFF pending a bounded site list -- see the noise
  caveat above; the regression that motivated this may not be real.

### OPEN AND NOW THE BLOCKER: we never scout
`Military::EnemyArmyCost()` logged as **0 for entire games** while the enemy
fielded 3000 metal of army. Everything that should respond to enemy strength --
`ArmyTarget`, `fundedMul` on the tech price, the commander's engage test, AA,
the danger model -- is reading a zero. apexearth, watching: "if we don't know
the enemy strength then we shouldn't be making a T2 lab... we need scouts."
Nothing in the variant raises scout production when intel is stale.

## 2026-08-24 (5) — defences were landing BEHIND the base

apexearth, watching: "we are more likely to build towers behind our base than in
front of our base. So the enemy just drives right up and kills all our energy
easily, nothings really protecting it."

Measured with a new `apex: defplace` line (tower position vs anchor, both as
ForwardFraction). Confirmed: `front=0` on 12 of 12 placements -- the front-post
branch never won a single auction -- and towers repeatedly landed behind the
anchor (-0.73 vs -0.47, -0.95 vs -0.57).

Two causes, both fixed:
- **Energy was never a candidate SITE.** Only structures over 1200 metal enter
  `gOwnBig`, so a solar field could never have a tower proposed at it however
  much `StakeAt` valued it. `gOwnGen` positions are now offered.
- **Every candidate sat ON something we own**, so a tower there meets the raider
  only after it has already arrived. Added `ShieldArcSpots`: the base's
  metal-weighted mass centre (`BaseCentroid`), an arc toward the enemy wrapping
  +/-110 degrees to cover both flanks, at one denied radius outside the measured
  base edge, spaced by what each turret actually denies. His spec verbatim.

After: `front=1` on 6 of 10 placements, and towers forward of the anchor in most
(e.g. -0.34 vs anchor -0.81).

Bound worth noting: the arc caps at 12 posts. That is a bound on WORK per
election, not on how much defence we may own -- the auction still buys as many
towers as the prices justify.

## 2026-08-24 (6) — THE ANSWER: we lose on combat, not economy

60 games, today's builds only, 1v1 Altair, Apex vs BARb stable hard. Paired
(both sides measured in the SAME game, which cancels map/seed noise).

| min | our metal | their metal | our army | their army | our def | their def |
|---|---|---|---|---|---|---|
| 10 | 4,755 | 4,990 | 140 | 450 | 0 | 90 |
| 20 | 16,457 | 15,898 | 720 | 2,618 | 555 | 1,845 |
| 25 | 19,843 | 22,252 | **215** | **4,040** | 555 | 3,288 |

At game end:

| | us | them | ratio |
|---|---|---|---|
| army standing | 215 | 4,040 | **0.05** |
| defence | 555 | 3,288 | 0.17 |
| metal LOST | **13,370** | 3,320 | **4.03** |
| metal KILLED | 1,620 | **12,038** | **0.13** |
| factories | 3,390 | 3,370 | 1.01 |
| constructors | 1,610 | 2,600 | 0.62 |

**Economy is at parity (0.89-1.04 all game). Trade ratio is 0.12 against their
3.63 -- roughly 30x worse.** `mT1` is 10,345, so we DO build army; it dies
immediately and kills almost nothing. Every symptom reported while watching
(no defences, no army, base overrun by two units) is downstream of this, not of
production. Factories are level; we run FEWER constructors than BARb.

Deaths are `by[stat/air/mob] = 76/0/1048` -- we die to mobile units in straight
fights, not to turrets.

### Lead, not yet confirmed as the cause
`apex: mass want=154 floor=61 army=1920 enemyArmy=5205 ratio=2.71` followed by
`apex: mass hold expired, committing at 108`. The no-commit suppressor
(`apex_mass_no_commit_ratio = 2`) SHOULD have fired at 2.71 -- so `localEdge`
(local superiority within 2200, `apex_local_edge = 1.3`) overrode it. Commits
fire 4-7 times per game against 4-12 suppressions. Whether the local-edge
override is what feeds the army in piecemeal is NOT yet established.

### METHOD NOTE -- a mistake that produced a wrong report today
An earlier version of this analysis globbed `tournaments/*1v1-*` and pulled in
732 games from PREVIOUS SESSIONS running different code, which produced a
confident and completely wrong conclusion (that we out-produce them 1.16x and
overspend 5.9x on factories). Always restrict the glob to the dated runs of the
build under test.

## 2026-08-24 (7) — where the metal actually goes, paired

apexearth's new destination telemetry (mEco/mBP/mArmy/mOther, commit 1b5f033),
12 games, 1v1 Altair, both sides measured in the same games.

At 10 minutes:

| bucket | us | them |
|---|---|---|
| BP | **18.5%** | 9.9% |
| defence | **0.8%** | 5.1% |
| eco | 14.3% | 11.1% |
| army | 65.3% | 73.9% |

At game end:

| bucket | us | share | them | share |
|---|---|---|---|---|
| eco | 2,416 | 16.3% | 2,969 | 14.1% |
| BP | 4,378 | **29.5%** | 3,750 | 17.8% |
| army | 6,605 | 44.5% | 9,852 | 46.8% |
| defence | 1,095 | **7.4%** | 4,068 | **19.3%** |
| mex count | 14 | | 17 | |

- **BP over-budgeted**, confirming his read: 1.7x their share, ~2x early.
- **Eco SHARE is already ahead of theirs** (16.3 vs 14.1) -- what is short inside
  it is mexes, 14 vs 17. "More eco" is not supported; "more mex within eco" is.
- **Defence is the largest gap and neither of us named it first**: they spend a
  fifth of their metal on defence, we spend a fourteenth.
- `mBP` is CUMULATIVE spend: 4,378 bought against 1,365 standing, so a large
  part of it is replacing constructors that died.

`apex_bp_headroom` 1.5 -> 1.0 moved mex 14 -> 17 and BP share 29.5% -> 27.2%
(12 games each). NOTE this reverses an earlier watched call recorded in the
tunable's own comment ("1.15 read 'lacked build power' in watch after watch").
The BP share barely moved for a 33% headroom cut, so BPGap's headroom term is
NOT the main driver of BP demand -- the rest is elsewhere (nano demand,
constructor production, and loss replacement).

## 2026-08-24 (8) — unprotected build power priced as the write-off it is

apexearth's value math: "a con outside of our home safe territory immediately
has 0 value and making the cheap pawn would add the pawns value + the
constructor value back."

- `EscortMetalAtRisk()` -- the metal of exposed, unescorted workers. Escort
  demand in `RoleTarget(RAIDER)` was a flat `count * 60`; it is now this, so an
  escort is worth the CONSTRUCTOR IT RESTORES.
- `BPProtectedFrac()` multiplies what a new constructor is worth, so buying
  more hands to walk out alone buys less than it costs. It lifts by itself once
  escorts exist, and both sides of the trade read the same metal.
- Escort ASSIGNMENT now excludes SKIRM and ARTY roles ("we make rocket bots and
  use those as protection (they're not good for that)").
- Unit value gained SPEED and LOS terms, plus an affordability term
  (`fillS / (fillS + costM/income)`) so cheap-now beats strong-later while we
  are poor -- "pawns are good early game when we cannot afford much stronger
  things". The affordability term is an economy ratio, not a clock: as income
  grows the same unit costs fewer seconds and the discount fades.

Measured, 12 games each, paired against BARb:

| bucket | before | after | BARb |
|---|---|---|---|
| BP | 29.5% | **22.9%** | 18.2% |
| army | 44.5% | **55.4%** | 51.1% |
| defence | 7.4% | 5.1% | 13.5% |
| constructors built | 1,290 | **940** | |

Grunts (`corak`, 42 metal -- the unit he named) now get ordered; they were
absent before. 2 of 12 games survived to the time limit.

### STILL OPEN
Defence share fell to 5.1% against their 13.5% -- the largest remaining
allocation gap, and it moved the wrong way. Constructors and rez bots still
take 65 of ~94 production decisions.

## 2026-08-24 (9) — mex capture: the probe bug and the value shape

apexearth: "our largest problem is still that we are not making enough mexes.
If we aren't capturing half the map worth of mexes in a 1v1 then we're losing."

Instrumented every refusal gate in `ProposeMex` (`apex: mexdiag`). Altair
Crossing has **30 spots**; we held **3-5**. The gates were NOT the reason --
`pastFront=0 deathWalk=0 ecoFar=0 ecoQuiet=0` throughout.

Two real causes:

1. **The probe gave up after one answer.** `FindOpenMexSpot` returns a single
   spot from one reference position; when that spot was already in our ledger
   the proposer returned NO WANT AT ALL -- 48 such refusals in one 60s window
   while ~25 spots stood open. Now it re-probes from home, both flanks, the
   rear and the map centre before giving up. Held 3-5 -> 8-10.
2. **Value shape was too flat.** `apex_mex_growth` 3 -> 8, so relative income
   boost dominates as he described: doubling x9, +10% x1.8, +1% x1.08 (was
   x4 / x1.3 / x1.03). "When a mex would double our income it is very
   important... if it boosts our income only 1% then its not too important."

Measured, 12 games paired: mex **13 -> 16, level with BARb's 16** (was 13 vs
20), and 4 of 12 games now survive to the time limit (was 2).

`held` also oscillates DOWNWARD during a game (5 -> 4 -> 5 -> 3), so we are
capturing spots and losing them, which is the defence problem below.

### THE OUTSTANDING GAP: static defence
apexearth's early-game priority order: energy income -> protect mexes (llt) ->
capture mexes -> army. Defence is his #2 and it is our worst number by far:
**3.5% of our metal against BARb's 18.5%**, and it has FALLEN this session
(7.4% -> 5.1% -> 3.3% -> 3.5%) as budget moved into army. BARb spends nearly a
fifth of its metal on static defence, and trades at 3.63 against our 0.12.

## 2026-08-24 (10) — WHY defences landed behind the base

apexearth: "we're still making defenses in the back of our base instead of in
front... they're made behind everything important we want to protect. Thus they
protect hardly anything."

Three causes, all introduced earlier the same day, all verified from logs:

1. **The shield arc switched itself off permanently.** It was called as
   `ShieldArcSpots(arc, reach - Military::FoeReach())` and opens with
   `if (denyR < 1.f) return false`. `FoeReach` is the longest enemy weapon range
   observed, so the first time BARb fielded anything out-ranging our towers the
   arc vanished for the rest of the game: `lineSpots` 22 -> 21 -> **0**, with
   `front` wins frozen at 7 while `asset` climbed to 1,496. Now sized by the
   turret's OWN reach; whether a post still helps against a standoff attacker is
   `CoverAt`'s question and it already asks it.

2. **`StakeAt` was side-blind -- the deep one.** A tower's gain is
   `stake x hazard x Dshortfall`, and `StakeAt` counted every asset inside the
   turret's weapon range REGARDLESS OF WHICH SIDE it sat on. A tower at the back
   of the base was therefore credited with the entire base standing in front of
   it, which the enemy reaches first. Added `FrontedStakeAt`: an asset counts
   only if the post stands between it and the enemy, measured on the true enemy
   bearing rather than the cardinal-snapped base axis.

3. **A forward post is priced on a thin strip.** On empty ground `StakeAt` is 0
   and only the narrow `ShieldedStakeAt` corridor applies, so asset sites won on
   raw stake: `bestAssetGain=112` against `bestFrontGain=17`. Unfixed.

Result: tower placement went from almost entirely behind the anchor to **51%
forward of it** (110 vs 107 over 12 games).

### STILL THE BIGGEST GAP: we barely build defence at all
Defence share **4.2% against BARb's 17.4%**. Placement is now roughly right;
QUANTITY is not. This is a separate problem from siting and is the largest
remaining allocation gap in the AI, matching apexearth's stated #2 priority
(protect mexes with llt) and the 0.12-vs-3.63 trade ratio.

## 2026-08-24 (11) — enemy reach as a power-weighted mean

apexearth: "we can perhaps average out all the enemy ranges we see. If they only
have a few things outranging those defenses then we can still make them...
per_unit(power * range) / totalPower"

`Military::FoeReach()` took the MAXIMUM observed enemy group weapon range, which
is an outlier statistic: one artillery piece spoke for their whole army. Now the
cost-weighted mean over enemy groups (group cost is the power proxy the enemy
model exposes). Measured in game: foeReach reads **294-413** instead of the
artillery maximum, and the shield arc stops collapsing (`lineSpots` holds at 5-6
rather than falling to 0).

Alongside it, `ShieldedStakeAt` was still testing "is this asset behind me"
against `Base::gFwd`, which is SNAPPED TO A CARDINAL -- so on a map where the
enemy sits diagonally it was wrong by up to 45 degrees and rejected the entire
base. Forward posts priced at exactly **0.00 gain** and could never win. Now on
the true enemy bearing, like `FrontedStakeAt`.

Measured, 12 games paired:

| | before | after |
|---|---|---|
| tower placement forward of anchor | 51% | **96%** (216 vs 10) |
| median bestFrontGain vs bestAssetGain | 0.0 vs 112 | **10.5 vs 19.5** |
| defence share | 4.2% | **6.4%** (theirs 14.6%) |
| games surviving to time limit | 2/12 | 3/12 |

Defence quantity is still short of theirs and remains the largest gap; their mex
count also pulled ahead (24 vs our 15) in this batch.

## 2026-08-24 (12) — the commander went on tour

apexearth: "we won that game because our commander rushed the other base for
some reason and gained enough experience to 1v1 the enemy commander. we left our
base completely undefended though which was pretty bad."

The commander-fight rule added earlier today gated targets on
`ForwardFraction(gp) < 0.5` -- "our half of the map". That is not a leash: he
walked to the midpoint, chained the next target from there, and ended up
duelling their commander in their base with ours empty. Winning that game is not
evidence the rule was right.

The bar is now our own property: `StakeAt(gp, apex_threat_r) > 0`, so something
of ours must be standing within the raider's reach. There is nothing of ours at
their base, so there is nothing to chase toward -- and no map fraction is
invented anywhere.

Measured, 12 games: engagements occur in 10 of 12 games against real raids (235,
455, 355 metal against his 2,700) rather than tours. Win/loss unchanged.

## 2026-08-24 (13) — emergencies, and a stake shape that finally works

Three shapes were tried for what a defence post's STAKE is:

1. **Side test** ("is the post between this asset and the enemy") -- right for a
   distant intercepting post, wrong for a tower inside the base, because half
   the base is in front of any home tower. Home priced to nothing and raiders
   walked in (apexearth: "we leave the home base completely undefended so the
   tiny enemy raiders totally kill it easily").
2. **Standoff-subtracted distance** (`reach - FoeReach`) -- demanded a post deny
   EVERY firing position: 450 reach against 300 standoff leaves 150 elmos, so
   almost nothing qualified. **Defence collapsed to 1.9% of our metal and we
   lost 12/12.** Standoff is CoverAt's question; charging it in the stake too is
   double counting.
3. **Plain distance within reach**, plus `ShieldedStakeAt` for what a forward
   post intercepts beyond its own range. Distance alone does the work the side
   test was reaching for -- a tower at the back of the base simply cannot reach
   a mex 800 elmos forward.

Plus two EMERGENCIES, both with measured two-part triggers, both skipping the
category lottery rather than taking a share of it:
- **AA panic**: zero AA standing AND metal actually being lost to aircraft now.
  UNTESTED -- BARb built no air in any of 24 games on this map, so it has never
  fired. Do not claim it works.
- **DEF panic**: zero ground defence standing AND structures dying at home.
  Fires in 5 of 12 games.

Measured, 12 games paired (shape 2 -> shape 3 + emergencies):

| | shape 2 | shape 3 |
|---|---|---|
| defence share | 1.9% | **9.1%** (theirs 17.4%) |
| mex | 12 | **19** (level with theirs) |
| army | 6,433 | 9,138 |
| metal produced | 11,596 | 19,206 |
| games surviving | 0/12 | **3/12** |
| home shortfall 0.00 | ~never | 104 of 216 samples |
