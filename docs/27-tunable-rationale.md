# Tunable rationale

Why a default is what it is: the measurements, the A/Bs that failed, and the rulings
behind them. This is the long form that used to sit in `tunables.as`, which now
carries one line per knob -- CLAUDE.md puts findings in the commit message or
`ISSUES.md`, not in the source, but a negative result attached to a specific
default is worth more where you can grep for the symbol.

Keyed by `TUNE_` name. `grep -A20 'TUNE_YOURKNOB' docs/27-tunable-rationale.md`.

Generated from the tunables.as annotations as they stood 2026-09-05; edit here
from now on, and keep the one-liner in `tunables.as` in step.

## Economy — energy, fusion, converters, reclaim

### `TUNE_ETA` = 1.f (was 0 until 2026-09-08)

THE ECONOMY-ONLY ETA OBJECTIVE. 0 changes nothing; 1 lets the ETA re-rank wants
WITHIN the four economic categories. Swept against an inactive opponent -- see
the eta-objective skill -- and unresolved there. Resolved 2026-09-08 on Carrot
Mountains v2.0, 1v1 vs BARb hard, 12 games each, 31 min, --speed 10: with
apex_eta=1 our metal income at minute 30 went 188.0 -> 236.3 m/s (BARb 236.9
-> 232.1, i.e. flat), mexes held 68.6 -> 99.8, and no game was lost (0-3
before); minute 20: 83.0 -> 102.8. The shift is our arm's alone and clears the
~15% floor BARb's own numbers show between batteries. The log sample showed
`mkt` and `eta` agreeing almost always, so the effect is the MERGE of the three
economy tickets into one draw, not the ladder's pick. Cost: 47.8 constructors
at 30 (BARb 19.2) and a rich-income stall of 50% (32%).

### `TUNE_ECO_ONLY` = 0.f

THE ECONOMY-ONLY BENCHMARK. 1 removes every army product from the factories
and every defence, AA and superweapon want from the market, so a game against
an inactive opponent measures how fast the economy alone scales -- apexearth's
canon scenario (2026-09-08: "focus on these eco scenarios without any military
and see just how efficient we can make ourselves"). His own reference on Comet
Catcher Remake with a 50% bonus: 2,032 metal/s and 103k e/s at 16:15. Never on
in a real game.

### `TUNE_ETA_LOG` = 0.f

The `apex: eta` shadow line while `apex_eta` is 0. Off because the layer it
compares against is off: EtaLog runs a full LadderRun economy simulation per
ranked want to write one line, measured at 3,448 ms (5.0% of all script time) in
a 27-minute game, and with apex_eta=0 nothing consumes the comparison. Set it to
1 to read what the ETA layer WOULD pick without letting it steer; apex_eta=1
enables the line by itself.

### `TUNE_T2_METAL` = 30.f

Metal income required before committing to T2 (techlead.as RushReady, and the
rear plant-siting rule reads the same knob). apexearth 2026-08-21: "30 m/s is a
good number". The T2 decision is this pair: apex_t2_metal AND apex_t2_energy.


## Constructors, build power, nanos

### `TUNE_CON_LOG_T1_A` = 4.6f

T1 constructor curve slope: cons wanted = A x ln(income) + B. At A=4.6/B=-6.55
that is ~4 cons at 10 m/s, ~14 at 100. The dashboard edits this as anchor
points.

### `TUNE_SITE_BT_PER_WORKER` = 4700.f

Buildtime per worker -- the other arm of the site crew, taken as a MAX with the
cost arm so it only ever raises the cap. 4,700 is set from the reference
building rather than picked: a fusion is 70,000 buildtime and 4,300 metal, so
70,000/4,700 gives the same ~15 hands its price already gave it. What moves is
the buildtime-dense outlier -- the advanced converter goes from 2 hands to 8
for its 35,000 buildtime. Sweep it before trusting it.


## Expansion — mexes, upgrades, claims


## Build phases (manager/factory/phase.as ComputePhase)


## Factories, tech, quotas

### `TUNE_FAC_QUEUE` = 1.5f

How deep the facqueue keeps each driven line, as a multiple of the line's
re-election gap, measured in that line's own build seconds. Below 1 the plant
is idle by construction; the margin over 1 covers the order lag, which is a
window of its own at benchmark speed.

### `TUNE_KILL_QUOTA` = 300.f

Attack quota set while the killing blow is on -- concentrate the push, do not
disperse. Skipped for the eco lead, whose army is deliberately tiny.


## Military — stance, engagement, squads

### `TUNE_RAID_ASK` = 1.f

The raid is asked for, not waited for (apexearth 2026-09-05). 0 leaves only the
stock pool, which needs raiders to trickle in and merge before `quota.raid.min`;
13 reached it in one 16-minute game and no raid formed. At 1, `military/raid.as`
scores enemy-side metal spots as prize over the influence guarding them, sizes a
pack at that guard times `apex_local_edge`, and pulls units so they re-elect onto
it. `CRaidTask` still picks the actual target.

Taking a constructor's escort is fine when the worker is safe and costly when it
is not; pulling them regardless moved metal built 10,732 -> 7,963 while raids
doubled. Gated on the worker's own cover instead, six seeds: raids 4.0 -> 10.8
min/game (up in 6 of 6), losses -18%, metal built +4%, kills +3%. The behaviour
is reliable; the outcome gain is not established — a three-seed read of the same
change said kills +62% and did not survive six.

Do not call `Market::CacheSpots()` from this pass -- docs/25 S20.

### `TUNE_RECALL_HOME_FWD` = 0.5f

Only squads this far past our own territory (ForwardFraction) are recalled --
units already fighting near home need no order, they are already where they are
needed. Matches the threshold sentinel.as already uses to call the same thing a
CONCERN.

### `TUNE_FIGHT_ABORT` = 0.f

Abort a losing ATTACK/RAID task outright so the squad re-pools together.
Measured 1W-11L vs 4W-10L with it on (winrate6): the ledger reads "losing"
transiently in bloody fights and mid-commitment aborts throw engaged units
away. Experiment arm, default off.

### `TUNE_FODDER_COST` = 100.f

units at or under this cost are fodder: exempt from massing, always sent
forward (their job is vision and pulled fire). Cost AND role, so cheap
AA/bombers are not swept in.

### `TUNE_KILL_OFF_FRAC` = 0.35f

The blow disarms below KILL_EDGE times this. Wide enough to survive the push's
own measurement dip (retreating units read zero power); 0.6 flapped 15x in one
game.

### `TUNE_KILL_FROM` = 900.f

killing blow: earliest the normal (non-T1-commit) gate may arm. A clock, not an
economy reading, and the only one left in the blow -- it exists so a fog-driven
army estimate in the opening cannot commit the whole army. Tunable so the cost
of holding it can be measured against a faster finish.

### `TUNE_SEEN_HALFLIFE` = 300.f

half-life of gSeenPeak, the largest enemy massing threat ever seen at once. It
is the denominator of the killing blow and the massing floor, so how fast it
forgets decides how long a destroyed enemy army keeps holding us back from
committing. MEASURED 2026-08-22: 180s (the 3-minute figure the old comment
claimed) was WORSE -- two paired 50-minute runs against medium, 16 and 8 games,
both lost win rate and army trade against the effectively-frozen peak. Kept
near-frozen as the default; the frame-based decay below is the correctness fix,
not a behaviour change.

### `TUNE_BUDGET_LIVE` = 0.f

evaluate the SPEND_* target curves against live income (1) or against the
frame-0 column (0). GetTunable caches its default on first call, so passing a
live curve as the default froze every share at income 0 -- and SPEND_ARMY's
income-0 column is 0.0, which is why the ARMY budget row read zero in every
game ever played. Default 0 reproduces that measured behaviour.

Turning it on is an UNTUNED CHANGE, not just a fix: the numbers in `targets.as`
were authored against a system that never read them past column 0, so they have
never been exercised. Measured 2026-08-22 over three paired 50-minute runs
against medium (40 games per side): live curves went 23W-8L-9D against
20W-10L-10D — inside the noise floor, win times mixed, and metal rate 21% lower
(12.2k/min against 15.6k). No win-speed benefit was shown, so the default stays
on the behaviour that was measured. Re-tuning `SPEND_*` with the curves live is
the campaign this needs before flipping it.

### `TUNE_PUSH_TEAM_RATIO` = 1.6f

team army advantage that STARTS the all-in push. Deliberately above the
per-squad engage margin: this spends the whole army at once. Held while above
apex_push_keep.

### `TUNE_STATIC_DEFENSE_WEIGHT` = 0.5f

how much enemy STATIC defence counts in the massing decision, per metal. Half
weight: a turret cannot retreat or redeploy; full weight would let a porc base
pin the quota forever.

### `TUNE_T2_HOLD_BOOST` = 1.60f

engage bias while an advanced plant is under construction; above 1 is cautious.
Raises only the bar to START a fight -- fights already joined and defence are
untouched.

### `apex_standoff_s` = 1.0 (C++ only; no `TUNE_` const)

Seconds between re-issues of the standoff ring in `ISquadTask::Attack`
(`cpp/src/circuit/task/fighter/SquadTask.cpp`). There is no AngelScript const:
the DLL reads it through `CCircuitAI::GetTunable`, i.e. the modoption
republished by `dev_tunables.lua`, and falls back to the compiled 1.0 in every
game that does not set it. The Tunables tab discovers it from the source and
offers it as an override only.

**1.0 is exactly today's behaviour** -- it replaces a hardcoded
`FRAMES_PER_SEC * 1` and `int(30.f * 1.f)` is 30.

It exists to PRICE the ring against the engine's pathfinder, and for nothing
else. The ring point is `LeadPos` plus an orbit angle plus a fragility scale, so
it is a different destination every re-issue by construction, and
`CGroundMoveType::IsMovingTowards` compares goalPos by exact float equality --
so each re-issue is a forced `ReRequestPath`. 885k of an hour's orders land in
the `order-src` ring `far` bucket and their share of the engine's ~35 ms/frame
at minute 59 has never been measured. The engine binary is a pinned release, so
an A/B on this knob at a matched unit count is the only way in.

**Raising the default is apexearth's call, not a session's.**
`docs/24-how-units-fight.md`: "Almost always stay moving. Standing still leads
to death much quicker... Units may circle around the enemies they are shooting."
A larger value buys frames by standing units still between steps, which is the
one thing that file forbids.

Two mechanical notes for whoever runs the A/B. The orbit angle is
`ORBIT_RATE * (frame / FRAMES_PER_SEC)`, a function of absolute game time, so
raising this does not slow the orbit -- it makes it a coarser polygon at the
same average angular rate, and past roughly 2-3 s each step is a chord across
the ring rather than a strafe along it. And the re-issue is not gated on this
alone: `isRepeatAttack || unit->GetTarget() != GetTarget() || unit->GetTargetTile() != targetTile`,
so a target crossing an influence-map tile (`ConvertStoP * 4`, ~128-256 elmos)
still re-issues immediately at any cadence.


## Defence, towers, AA, insurance

### `TUNE_MEX_COVER_FLOOR` = 0.5f

MINIMUM PROTECTION PER MEX. Every site the defence auction considers is priced
against the wave that has actually arrived there, and a mex nothing has
attacked yet reads a wave of zero -- so it was skipped outright, and the
economy stayed naked until something came for it. This is the wave a standing
mex is assumed to have to meet whatever we have seen, measured in the faction's
own light towers so it scales across factions and tiers rather than being a
metal number. It is a FLOOR and nothing more: once a mex has this much cover
the shortfall is zero and the next turret there prices itself out, and a mex
under real threat is still sized by the threat. 0 restores the
observed-threat-only behaviour, which is how the A/B is run. Halved 2026-08-29
under his concentration ruling ("Move 8 spread out defenses from mexes into
less choke points which overwhelm the attack") -- the freed budget flows to the
gate depth floor under the same DefenceTarget.

### `TUNE_LEAK_SCREEN_M` = 800.f

Fielded army value at which the mobile screen, not per-mex towers, takes over
answering leaks. Below it every standing mex carries the FULL cover floor
whatever its bearing (the first mexes sit behind the centroid and read
forwardness zero). ~8 ticks' worth; an estimate, not a measurement.

### `TUNE_GATE_DEPTH` = 2.f

A choke-gate site's threat floor as a multiple of the arriving wave: the gate
keeps deepening until its cover OVERWHELMS the push, not merely matches it
("Have an unusual amount of tower at some spots. Try to deeply cover those
choke points").

### `TUNE_TEETH` = 1.f

The teeth line: one wall piece per election, a step enemy-ward of the wall's
FRONT ROW where the mains behind it stand (`WallTeethPoint`), or across a
defended gate's span when the map has one. Teeth split the attacker's fire in
front of the guns and are worthless with no gun behind them, which is what
the gate-only version (off 2026-08-29, "the implementation is terrible") got
wrong: it stood teeth at a doorway with nothing behind. On again 2026-09-15
with the layered line (docs/32); A/B it against 0 on Greenest 8v8.

### `TUNE_TEETH_GAIN` -- removed 2026-09-15

A tooth is now priced as the soak it is: the prevented loss a front-row
slot earns (team metal behind the gap x hazard x the wave share its health
absorbs for the guns behind it), through the same terms as every gun. The
fixed gain of 40 read v~55 against guns at 2-15 once the line stood, and
1517 of 1548 defence elections in one Greenest 8v8 were teeth (271 standing
at 20 min, 36 guns).

### `TUNE_DEF_SITE_WALK` = 1.f

HOW HARD A BUILDER PREFERS THE GROUND IT IS ALREADY STANDING ON. The defence
auction picks a site, then ValueOf charges the walk to it -- so the choice
never saw the cost of getting there, and a constructor that had just finished a
mex was sent across the base to a site worth marginally more (apexearth: "units
making mex and then not immediately making the light tower to cover it"). This
weights the walk inside the site ranking, in the same two terms the price uses:
the builder's idle seconds and the income the tower forgoes by starting late. 1
ranks sites exactly as they will be priced; 0 restores the old distance-blind
choice, which is how the A/B is run; above 1 makes defence more local still.

### `TUNE_COVER_PUSH` = 1.f

COVER WHAT YOU JUST BUILT. The category draw is proportional, not argmax, so a
tower worth twice the mex beside it still loses the roll about half the time --
which is what "we don't immediately make the light tower" looks like from the
outside (apexearth, twice). This lets ONE want skip the lottery: a
ground-defence want sited at a mex of ours that has no gun ordered or standing,
proposed by a builder already inside the tower's own reach of it. The same
queue-jump apex_super_push and the defence-panic path already use. Deliberately
narrow: it cannot fire away from a mex, cannot fire once the mex has its first
gun, and cannot fire for a builder that would have to walk -- one light tower
per extractor at most.

### `TUNE_DEFEND_LEASH` = 0.55f

A DEFEND-task unit farther forward than this (on losing ground) is recalled
first -- it is in the wrong place by the task's own meaning. 0.35 was tried
against the midfield-grind deaths and lost MORE (ceded the corridor's mexes).

### `TUNE_HOLD_COMMITTED` = 1.f

apex_hold_committed: units standing on ground the enemy's guns cover are never
given solo pull-out orders -- the split (half fights, half runs) loses the
fight twice. 0 restores per-unit withdrawal everywhere.


## Nukes (manager/brain/nukes.as) -- restored 2026-08-24 with the pre-kill


## Air eco-assassination (manager/air/state.as)

### `TUNE_AIR_CLUSTER_R` = 900.f

Radius around the enemy centroid sampled for how packed their base is. One
cluster, the reach of a single bombing run.

### `TUNE_AIR_AA_SOAK` = 0.05f

Wing HEALTH is what absorbs AA, so a 16,700 hp Dragon soaks 25x what a 670 hp
Thunder does. Sets both the throughput curve and how fast the required strike
grows with their AA; it is what makes "50 or 100 from different angles" the
answer to a wall instead of standing down. At 0.05, ~20 Dragons clear 8k of AA
at ~0.7 throughput while light bombers need ~67 to reach half through 2.5k --
and the payoff test then declines that as the suicide it is.

### `TUNE_AIR_AA_SPLIT` = 1.f

The strike sizes against the enemy AA census divided by their base count
(mirrored from our own team size): a raid overflies ONE base and static AA
cannot concentrate. 0 sizes against the whole map's AA, which read want=125
bombers and held a 50-bomber wing at home forever.

### `TUNE_AIR_SETTLE_S` = 90.f

How long after a strike launches before it is scored. Long enough for the wing
to reach, bomb and be shot at.


## Commander

### `TUNE_COMM_HEAVY_FRAC` = 0.5f

Fielded enemy HEAVY+SUPER mass at this fraction of the commander's value makes
him cautious. Scaled to his cost so it tracks the game, not a number.

### `TUNE_COMM_FLEE_INFLUENCE` = 0.01f

Enemy influence at his tile (or on the ring, while cautious) above which he
leaves. Uses the influence map, never ai.GetBuilderThreatAt, which reads clean
until he is dead.


## Air

### `TUNE_AIR_DOMINANCE_AA` = 0.15f

Enemy AA under this fraction of our own team army counts as DOMINATED: the
assassin's absolute AA ceiling waives and a standing abort un-latches, so a
beaten enemy's leftover flak cannot veto the one weapon that targets the win
condition. 0 keeps the ceiling only.

### `TUNE_AIR_MANDATORY_INCOME` = 200.f

Metal income at which the first air plant becomes mandatory for a player who is
NOT the air lead (the lead builds at apex_intel_air_income, 25). Raised 60 ->
200 on 2026-08-30: at 60 the whole team bought air while none of them could
survive on the ground, and air is the first thing a single enemy flak truck
deletes (apexearth, watching: "we don't need that air power at this point in
the game... We need survival at this point and we certainly don't have it. If
the enemy has 1 flak truck near our base then our air dies surprisingly fast.
Hold off on making air if we're not the air player until we have ~200m/s+").


## Nukes and superweapons

### `TUNE_BRAIN_NUKE` = 1.f

The sentinel: the brain checks its own concepts every 45s and logs a verdict
per check ("apex: thought <name> CONCERN ..."); observer-first, each
enforcement earned separately. logistics, target ranking); 0 leaves silos to
stock behaviour.


## Scouting, intel, ghosts

### `TUNE_ESCORT_SQUAD_VALUE` = 2000.f

squad metal value above which it is owed a sensor escort. apexearth 2026-08-20:
"any squad worth over 2000 metal".


## Base layout and placement

### `TUNE_FRONT_BAND_FRAC` = 0.35f

Width of the front band as a fraction of the territory radius (floored at one
influence-grid cell). The arc it keeps is acos(1 - frac) each side of the enemy
bearing: 1.0 was +/-90 degrees -- HALF the perimeter read as front, every game
(band=R in every frontline log line), which is a "front" through the middle of
the base. 0.35 is a +/-49 degree arc.


## Diagnostics and switches

### `TUNE_CATALOG_DUMP` = 0.f

Dump every available def's catalog row at init (one log line per def, parsed by
tools/check_catalog.py). Off by default: it is ~1000 lines of infolog that only
a verification run reads.

### `TUNE_DECIDE_LOG` = 1.f

The `apex: decide` and `apex: exec` lines. ON by default and it stays on for
every benchmark run: review.py, trace.py, rebuild_lag.py and audit.py all parse
them, and a run without them cannot be judged. It exists because the cost is not
free — AngelScript evaluates the argument eagerly, so each election builds a
~20-term concatenation with six formatFloat calls and each AiLog takes a mutex
and a formatted file write, ~2,600 times in a 27-minute game. Set it to 0 for a
live multiplayer game where nobody is going to read the log.

### `TUNE_PERF` = 0.f

One switch over the per-section profiler (`frametime.py`'s `apex: perf sec`
lines) and the lag governor's production cuts. Default 0 on apexearth's ruling,
"Default to 0, harness passes it explicitly" — so a live game stops paying two
`ClockUs` calls and a dictionary lookup per section for a log nobody opens. If
`frametime.py` reports nothing for a run, this is why.

### `TUNE_PLANT_PIPE` = 2.0f

PLANT_PIPE: the constructor pipeline's return in spot-streams. Early cons each
carry a full open-spot stream and compound; 0.5 measured lab 1 at 5.1m (too
late, apexearth 2026-08-23: "try building the first lab a bit sooner"); 2.0
targets the ~2m human timing. Labs 2+ are gated by PLANT_INCOME_PER, not this.

### `TUNE_TECH_SURVIVAL` = 1.f

Discount a tech want's deferred gain by the risk borne over its pipeline. 0
disables it, which is how the A/B control is run.

### `TUNE_ECO_SURVIVAL` = 1.f

The same survival discount on the ENERGY want, so a long-payback generator
(afus, fusion) is priced on the base it needs to still be standing. Cheap fast
generators are untouched by construction. 0 disables it.

### `TUNE_SIEGE_PRIOR` = 1.f

The siege prior: what share of our OWN total economy we assume the enemy has
converted into army and may be walking at us right now, seen or not. 1.0 = they
had our start and our minutes and spent it all on units. Used only by the
survival discount on long builds, never to size production.

### `TUNE_LINE_TANK` = 0.28f

ARMY COMPOSITION TARGET, shares of army metal (apexearth 2026-08-24:
30/25/25/20; re-ruled 2026-08-29 to 28/20/35/17 -- "build up these guys
[snipers/hounds/arty] in unit numbers so our army can grow very powerful",
"Rocket bots, artillery... they get free shots sometimes so we should leverage
that"). tank = health per metal, reach = weapon range, dps = damage per metal,
mid = nothing clearly dominant. Classes are read off unit data against the
game's own mobile combat units; see army.as.

### `TUNE_LINE_ADAPT` = 0.f

How hard the enemy's observed STATIC share of fielded metal bends the reach
target up (renormalized). MEASURED WORSE at 1.0 (winrate14: 0W-11L, trade 0.372
vs 0.53-0.65 refs) -- reach at ~48% left no screen and corridors deny it
standoff room. Experiment arm, default off; his adapting-composition ruling
stands as direction, this term's shape or scale is wrong.

### `TUNE_MEX_EXPOSE` = 1.5f

The per-mex defence floor grows with the spot's forward fraction: floor * (1 +
fwd * this). His ruling: "the closer our mex is to the enemy and furthest from
our army, the stronger the defenses should be."

### `TUNE_WORTH_COST` = 1.f

COST IS A CHOICE OF LANCHESTER LAW. The caller divides by cost once more, so
the total power of cost is 1 + this: at 1 that is cost^2, the LINEAR law where
bodies trade one for one and cheap chaff wins the draw; at 0 it is cost^1, the
SQUARE law where a massed army fires at once and quality wins superlinearly.
Tzar-and-Banisher armies are the square-law case; 0.5 is the middle. 1 is what
this AI has always priced under.

### `TUNE_WORTH_DIAG` = 0.f

1 = print the exponents and field means once; 2 = also dump the ranked field.
Costs no games to learn what an arm actually prefers.

### `TUNE_AIM_MISS` = 1.f

What a weapon's reach is worth when it CANNOT hit a moving target -- a slow
un-tracked rocket. 1 = the reach counts in full, as it always has; 0.5 would
say half of it only ever lands on buildings. The DLL's own IsAlwaysHit does the
detecting (see EffRange in market/worth.as); this is what it costs.

### `TUNE_LINE_MEDIAN` = 1.f

Judge each class axis against the field MEDIAN rather than its mean. 0 = as it
always was; see LineRef in market/army.as for why the mean cannot work.

### `TUNE_LINE_ABS` = 1.f

Read the tank and dps axes PER BODY rather than per metal (see LineAbs in
market/army.as). 0 = as it always was, which made a Thud tankier than a Tzar.

### `TUNE_LINE_RANGE_EXP` = 1.f

Exponent on the range axis of the class argmax. 1 = as it always was.

### `TUNE_LINE_ALLOC` = 0.f

1 = the factory draw runs among the LINE CLASS the team owes the most metal to,
instead of over every candidate weighted by apex_line_bite. A share cannot be
produced by a nudge: five pricing attempts left reach at 0.04-0.07 of a 0.35
target because the per-metal spread between classes is ~12x. 0 restores
weighting. MEASURED 2026-08-30 AND OFF: at 1, on a matched seed against the
same build, army metal collapsed 544,313 -> 60,324, kill/loss 0.81 -> 0.12,
economy 1.65 -> 0.41, and 18,667 metal overflowed unspent. Reach share DID rise
(0.06 -> 0.12) -- the allocation works, the STAND-DOWN deadlocks. Reach is owed
on every election because it is never filled, so the T1 labs yield permanently
waiting on a plant that "can serve" and never does. Yielding is only sound when
the debt is actually BEING PAID, not when something that could pay it merely
stands. Fix that before turning this on.

### `TUNE_COVER_WORTH` = 1.5f

How much ground-covered-per-metal is worth while the fleet is short of the
sites it must watch. Buys cheap fast bodies early and fades as they arrive; 0
disables the coverage term.

### `TUNE_STREAM_SURVIVAL` = 1.f

Discount a mex/upgrade's income stream by the share of it we expect to still be
collecting over the stake horizon. A tower within reach of the spot raises it
directly, so cover makes the next claim beside it worth more. 0 disables, which
is how the A/B control is run.

### `TUNE_LAVA` = 1.f

Master switch for the rising-lava tide (`manager/lava.as`). On a map running
BAR's `map_lava` gadget the AI samples its public `lavaLevel` param each second
and learns the schedule: the ramp speed is the climb it has measured, and the
level a climb ENDS at is a target the gadget reached and held, so the highest of
those is the ceiling. One output, `Eta(height)`, prices three consumers:

* `StreamRisk` (coverage.as) takes it as a floor, so every survival discount in
  the market sees it. A mex is bought against walk-plus-build and barely
  notices a tide five minutes out; a fusion is bought against its payback and
  is worthless on the same ground.
* `PfRebuild` (protect_field.as) discounts an asset's defence worth by the
  share of the stake horizon it survives, so the basin earns a light gun.
* `ProbedSite` (sites.as) refuses ground that floods before the build pays for
  itself, then retries without that filter so a flooded map still gets its
  generators. A hard "not under the surface right now" veto also sits in the
  C++ site predicate (`BuilderTask.cpp`), catching the whole farm — every
  generator, converter and nano the lattice is free to move — and exempting the
  sites the script chose deliberately, which are filtered above instead.

Kept OUT of `HazardAt`, and not multiplied by `ShortfallAt`: that field drives
defence gain, and a hazard turrets cannot answer would read there as a reason
to buy turrets.

Its limit is an escalating rhythm's NEXT step (Special Hotstepper climbs
120 → 250 → 400 → 880). Once two crests materially escalate it stops claiming a
ceiling and projects every height at the ramp speed; before that it will lose
buildings to the first escalation.

0 disables every price and placement while the sense keeps logging, which is
the only way to A/B this on the same map.

### `TUNE_SPACE_RENT` = 2.f

Rent a building pays for standing on DEFENDED ground: covering turrets' metal
spread over the area they cover, per cell of footprint. Makes dense beat
sprawling inside the perimeter and costs nothing outside it. 0 disables.

### `TUNE_PAYBACK_H` = 900.f

A gain is credited only for the share of this horizon it will actually be
collecting, so a build that delivers nothing for most of it is discounted
against the small compounding steps that deliver now. Scales itself with build
power: more lathes shorten buildSec and restore the big build's value. 0
disables, which is how the A/B control is run.

### `TUNE_LOCKUP` = 0.5f

the option cost of tying capital up in an unfinished frame, as a multiple of
(cost x duration / payback horizon). apexearth's "little bit extra of a penalty
on top of time". 0 disables.

### `TUNE_COMMIT_SHARP` = 12.f

How much sharper the category draw gets for a COMMITMENT -- added to
apex_draw_sharp in proportion to the candidate's cost as a share of what the
economy can produce over the payback horizon. Large values make an expensive
want effectively winner-takes-all while cheap wants keep their sampling.

### `TUNE_FARM_ROW_W` = 320.f

elmos one farm row runs before the next stacks behind it. Halved from 640 on
apexearth's watched report that the winds sat too far out on both sides: the
same slots in a narrower row form a block instead of a line, so the next slot
is adjacent to the last.

### `TUNE_FRONT_LINE` = 1.f

Offer the spaced front posts (Military::FrontBuildSpots) to the defence auction
alongside mexes and big structures. 0 disables, for the A/B.

### `TUNE_STANDOFF_COVER` = 1.f

Measure turret coverage on the ring the enemy can SHOOT FROM (their observed
weapon range), taking the weakest bearing, instead of asking only whether a
turret reaches the target itself. 0 restores the old test.

### `TUNE_COMM_FIGHT` = 1.f

Let the commander fight while he still outclasses the field. CommCaution is the
"heavies are out" sense, so this only ever fires before that. 0 = the old
flee-only commander.

### `TUNE_TECH_PIPE` = 2.0f

TECH_PIPE: discount on a tech plant's unlock demand. The pipeline DELAY is
priced by PipeLatencyMult -- a second 0.5 here double-counted it and, stacked
with the funded discount, priced the T2 lab ~100x under a nano (measured 8v8:
zero tech decides in 12 min, all eight players).

### `TUNE_E_BILL_SHARE` = 1.f

E_BILL_SHARE [toggle 0/1] -- WHILE E-STALLED, price a build's ENERGY bill by
the share of energy INCOME its own drain eats, instead of by how long the build
runs. Inert with energy in hand: outside a stall the bill competes with nothing
(apexearth: "it only matters when we're e-stalling"). costE/buildSec against
income: an advanced solar's 5,000 E is 63 E/s, most of a 100 E/s economy and a
sixth of a 400 E/s one, so the same building is unaffordable at the first and
cheap at the second (apexearth: "an advanced solar is hardly affordable at
100e/s income. And it costs a lot of energy to make. So income restrictions
must apply"). The scarcity premium is still zero while the economy is healthy,
so this only bites in a stall. 0 restores the build-length decay
(apex_e_response), which was blind to income and priced a 5,000 E bill at the
conversion floor.

### `TUNE_STALL_SOLAR_E` = 300.f

STALL_SOLAR_E [energy/second] -- while HARD e-stalled below this income, the
energy want is restricted to generators that cost NO energy to build, i.e. the
basic solar (apexearth: "if we are e-stalling and we have less than 300 energy
per second, MAKE A BASIC SOLAR"). His number, stated as a rule, not derived: an
advanced solar's 5,000 E bill and wind's 175 are both paid out of an economy
that has none. 0 disables the rule and leaves the ladder to the auction.

### `TUNE_E_HEADROOM` = 1.75f

E_HEADROOM: energy income target as a multiple of trending pull -- the standing
reserve that keeps the bank from ever being raced to zero. 1.25 still
under-supplied in watched games ("definite pattern now").

### `TUNE_ESCORT_SPEED` = 1.f

ESCORT_SPEED: an escort must CATCH a raider or be a riot unit (apexearth: "we
want fast or tough units on escort, rocket bots die in a 1v1 vs a pawn/grunt").
A multiple of the ground field's own mean speed, so 1.0 means "above average",
and no number here is about a particular unit. Lower it to let slower units
guard.

### `TUNE_MEX_GROWTH` = 8.f

A spot is worth what it RAISES us by, not what it yields (apexearth: "when a
mex would double our income it is very important... if it boosts our income
only 1% then its not too important"). At 8: doubling x9, +10% x1.8, +1% x1.08
-- 3 gave x4 / x1.3 / x1.03, too flat to express that ordering.

### `TUNE_INFERIOR_DISCOUNT` = 1.f

Discount a generator by how much better a one any constructor we own could
build instead, so a worker restricted to the inferior option prefers to spend
its build power on the better one. 0 restores flat per-def pricing.

### `TUNE_E_REALIZE` = 1.f

E_REALIZE [toggle 0/1]: the overflow-aware half of the energy market --
generation priced by the share of it anything would actually use (real demand
at E_HEADROOM plus standing converter capacity), the converter want reading the
true remaining waste, and the same eco-compounding premium on both halves of
the generator/converter pair. 0 restores pricing every E/s at the conversion
floor whether or not a converter exists to realize it, and is the control arm.

### `TUNE_E_WASTE_WORTH` = 0.25f

So an overflow makes a generator LOSE to the converter that realizes it, and
never makes it unbuildable (apexearth 2026-08-26; his standing ruling is that
the generator ladder never pauses on waste). Default chosen, not derived --
measure it.

### `TUNE_M_REALIZE` = 0.f  (measured, left off)

**OFF, and here is the A/B.** 18 games per arm, Comet/Callisto/Glacier, 25 min
vs BARb hard, `apex_m_realize` 0 against 1. The term is INERT where it was
measured: of 389 `apex: mrealize` samples in the ON arm, **377 returned
share=1.000** and 12 hit the floor. In a handicap-0 game metal demand sits above
income, so there is nothing to discount. The arms' composition differed
(metal 29,734 -> 25,266, mexes 242 -> 220, 3 of 12 games wiped out) and that is
**run-to-run variance on an unchanged decision**, which is the more useful
result: swings of that size are noise in an 18-game battery.

The premise is also unproven. The overflow it answers was measured in a `--watch`
game at +50% resources, and apexearth's objection stands: end-state totals are
downstream of losing (dead builders cannot spend, so metal piles up and spills).
The waste may be a symptom rather than a cause.

**The +50% A/B this asked for was run 2026-09-09 and it does NOT resolve.** The
canon economy board (Comet Catcher Remake 1.8, `apex_eco_only=1`, `--handicap
50`, `--speed 5`, 4 seeds per arm) is exactly the regime named: metal spilling
against an energy stall. ON 473 m/s at minute 16 and 988 at 20; OFF 412 and 913
-- means 8-15% apart with the ranges overlapping ([396-543] against [398-438]).
And the term is inert by its own instrument in that regime too: every sampled
`apex: mrealize` line returned `share=1.000`, because peak-held metal demand
(`pk`) holds the target above income even while the bank spills. Left OFF. The
overflow it was aimed at is answered instead by `LatheRealizedFrac`, which is
not a tunable.



M_REALIZE [toggle 0/1]: the metal twin of `E_REALIZE`. Extraction is priced by
the share of its metal we could actually spend — measured demand (peak-held
metal pull, grown over the build's own delivery time) at `E_HEADROOM`, plus the
room left in the bank over `E_LOOKAHEAD`. 0 restores full price for every
metal/s whether or not anything can spend it, and is the control arm.

WHY IT EXISTS. Energy has had to prove something would absorb it since
`E_REALIZE`; extraction never did. Measured 2026-09-06, Comet Catcher 1v1 vs
BARb hard, 15.3 min: **23.5% of all metal produced thrown away**, metal bank
pinned at 2100/2100, spend only 61% of income, while energy pull equalled energy
income and 17.6% of samples were energy-stalled. BARb was the mirror image —
2.25x our energy, 20.7% of it wasted, 3.5% metal wasted, spending 118% of metal
income. The market was buying the resource we were binning in preference to the
one throttling every build: mex won 46 elections and beat energy in 16 of the 28
that energy lost.

It does NOT replace `MEXUP_BOOST`: that preference still decides extraction
against energy whenever the metal can be spent at all. The horizon knobs are
deliberately shared with the energy side — a lookahead and a headroom are
properties of the question, not of the resource.

Serves apexearth's 2026-09-06 ruling: *"The constant goal we should always have
is to scale our economy. Grow grow grow."*

### `TUNE_M_WASTE_WORTH` = 0.25f

What a spot is still worth once its metal would only overflow. Never 0, for the
reason `E_WASTE_WORTH` is not 0: demand grows, and a spot claimed now is still
ours when it does — the band loses the wait, not the metal. Set to the energy
side's value rather than derived; measure it.

### `TUNE_THREAT_GRADIENT` = 1.f

Spatial threat prior: 0 at our start box, 1 at theirs. 0 disables it and threat
goes spatially flat, which is the control arm.

### `TUNE_SCREEN_WORTH` = 0.2f

SCREEN_WORTH: the scout/screen axis in production.as -- sight and dash per
metal, read INSTEAD OF combat worth when it is the larger of the two, so a unit
that is a hopeless soldier can still be a good screen. 0 disables it. 0.2 is
calibrated, not derived: it puts a Tick modestly ahead of a Pawn at a
half-covered patrol shortfall while the Pawn still wins on combat.

### `TUNE_MEDIC_FRAC` = 0.12f

MEDIC_FRAC: standing rez/repair fleet as a fraction of army value per minute
(apexearth: "3 times more rezbots" -- was 0.04). Named _FRAC: a legacy
TUNE_MEDIC_SHARE with other semantics survives at the bottom.

### `TUNE_WATER_FIRST` = 1.0f

WATER_FIRST: MODEL. What land-locked metal is worth ON TOP of its own stream
while the water is still uncontested -- the denial half of taking it first
("the earlier you get into the water the more likely you are to own it"). 1.0
prices denial equal to the gain; decays with the enemy's navy.

### `TUNE_AA_URGENCY` = 1.f

AA_URGENCY: multiplier on the insurance rate for anti-air. CHOSEN, matching the
shield branch's x4 -- air arrives faster than ground and a bombing run is over
before a reactive build finishes, so it is priced above ordinary insurance.
Divided by the towers already standing, so it self-limits. 4 was compensating
for a value that came out ~50x too small (an insurance rate on min(their air,
our base)); with AA priced like a ground turret the multiplier is 1 and the
knob still scales it.

### `TUNE_AA_COVER_FRAC` = 0.5f

AA metal we are aiming to have standing per metal of enemy air we have seen
(apexearth: "if the enemy rolls up with 100k metal worth of air... then I'd
hope we add at least 50k of AA"). This is what makes the AA want price itself
out: once cover reaches the target the next tower stops nothing. 0.5 reproduces
the old apex_def_trade=2 saturation point, now named.

### `TUNE_ECO_AA_MULT` = 1.5f

ECO_AA_MULT: the share of the air census the rear eco specialist answers,
relative to an even split. It holds the team's economy, builds no ground
defence and keeps no army at home, so it draws more of the air that gets
through than its headcount share (apexearth: "~50% more anti air than your
average player").

### `TUNE_GIFT_ARMY` = 0.f

GIFT_ARMY: master switch for back-to-front army gifting. DEFAULT OFF (apexearth
2026-08-24: "we are doing the share logic to send units to teammates. We should
disable that by default. It only is appropriate on certain maps"). Handing an
army away is only right where the map makes one player's front the whole team's
front; everywhere else it disarms us.

### `TUNE_T2_CON_BASE` = 1.f

T2_CON_BASE / T2_CON_PER_M: how many cons able to build the game's best
extractor we always want standing -- BASE plus one per PER_M of metal income
(apexearth 2026-08-23: "1 T2 con + 1 per 25 metal ... at 100 metal per second
we should have at least 5"). Under that count a factory line orders one
outright instead of pricing it against the army draw, which it loses whenever
the army gap is open -- which is nearly always.

NEGATIVE RESULT, 2026-09-14. Both floors also add the spilled metal as
more constructors (unspent / con BP), and on his 8v8 seat at 1,070 income
that term asked for 71 on top of 43 ("we have like 100 advanced bot cons,
way too many"). Gating that term on BPCapacity() < income -- the
OverflowBuysHands law -- and feeding the ETA's hands verdict from metal
income instead of economic power was measured together over 12 paired
Carrot 1v1s (Cortex, 30 min): metal built 335-554k -> 165-262k, damage
efficiency 81-132 -> 55-103, T2 constructors 41-70 -> 16. On a map with
seventy mexes the "excess" T2 constructors are the mohos. Reverted the
same day; his complaint stands for the mex-limited 8v8 base, where the
hands assist each other, and needs a term that reads what the hands are
DOING, not their count.

### `TUNE_CON_BASE` = 2.7f

constructors of ANY TIER the line orders before the draw, the plain "how many
hands" floor. The block above is narrower than its name suggests: it counts
only cons that reach BestExtract(), which scans every available def and so
means the MOHO, so no T1 con and no commander ever satisfied it. 2.7 + inc/44
is apexearth's own two points: 3 at 12 metal/s, 5 at 100. A floor, not a cap.

### `TUNE_RECLAIM_REZ_BIAS` = 3.f

How much more a reclaim is worth in the hands of a dedicated reclaimer (rezbot:
builds nothing, so it has no expansion to be pulled off) than in the hands of a
constructor that could be claiming open ground instead. A PREFERENCE, applied
both ways around 1: the con still reclaims when its list holds nothing better,
and the penalty lifts entirely once no metal spot is open. 1 disables.

### `TUNE_NANO_SITE_SHARE` = 1.f

How much of the metal nothing is spending one build site may claim as nano
demand. Replaced a bare 35 m/s clamp that two turrets saturated at any income,
which is why factories and gantries stood on 2-5 nanos while an enemy gantry
ran 38. Demand still nets off the crew and the turrets already there, so the
count self-limits.

### `TUNE_MEX_TRIES` = 10.f

Ranked metal spots offered to the engine per election before extraction gives
up for that tick. Was a bare 3: a builder whose three best spots were all
claimed proposed no mex want at all, which reads as "no ground left". A bound
on WORK (one engine probe each), never on how far we may expand.

### `TUNE_ROOM_WORTH` = 1.f

What the ROOM under an obsolete building is worth, as a multiple of (base fill
x metal per build cell x the building's own cells). SpaceRentM prices ground by
the turret cover over it and reads ~0 in a lightly defended base, so nothing
charged a wind farm for the space it occupied. 0 disables scarcity pricing.

### `TUNE_INSURE_RATE` = 0.0003f

INSURE_RATE: protection value per metal of covered assets, per second -- the
one modeled risk quantity for eyes and turrets. 0.00005 prices a radar at ~v5
on a 100k base.

### `TUNE_NUKE_RISK` = 0.0005f

NUKE_RISK: the anti-nuke's own rate; higher, because an uncovered nuke is total
loss. Timing emerges from assets x rate.


## Strategic structures -- manager/brain/market/want_super.as

### `TUNE_SUPER_WANT` = 1.f

SUPER_WANT: master switch for the strategic want (gantry, nuke silo, anti-nuke,
long-range gun). 0 disables it.

### `TUNE_SUPER_PUSH` = 1.f

SUPER_PUSH: 1 = an affordable strategic want skips the category lottery rather
than taking a proportional share of it. Off, these are priced normally and
drawn about once a game.

### `TUNE_SUPER_AFFORD_S` = 60.f

SUPER_AFFORD_S [seconds] -- the whole affordability test: the bill (metal plus
energy at the conversion floor) must be smaller than what the economy makes in
this many seconds. 60 puts the anti-nuke at ~36 metal/s, the long-range gun at
~90 and the gantry and silo at ~160 -- his "at 200 m/s we should eagerly build
one".

### `TUNE_SUPER_PER_INCOME` = 150.f

SUPER_PER_INCOME [metal/s] -- income per additional anti-nuke; the offensive
classes (silo, long-range gun) space at twice this. Never a cap: the count
rises with the economy, which is his "at least 1 usually, more if we want to be
safer".

### `TUNE_SUPER_SHARE` = 0.25f

SUPER_SHARE: the slice of total economic power the strategic market may claim
as a want's gain. Scaled by how much budget is left after the bill.

### `TUNE_SUPER_FLIGHT_PER` = 140.f

SUPER_FLIGHT_PER [metal/s of overflow] -- one strategic frame may stand
half-built per this much structural overflow, on top of the base one. The
single-frame focus law is for an economy that must choose; one throwing metal
away has already chosen.

### `TUNE_BLAST_AISLE` = 500.f

BLAST_AISLE [elmos] -- gap between a BIG generator's own clusters, so one death
explosion cannot chain the whole farm ("better if only half our economy blows
up"). Chosen, not derived from the defs' blast radii.

### `TUNE_CON_FEED_HEADROOM` = 1.5f

CON_FEED_HEADROOM -- how many hands the production draw may price toward, as a
multiple of income/apex_request_drain (the hands income keeps fed). A new con's
gain scales with the room left under that line; at 1.5 a 52 m/s economy stops
paying for its eleventh builder ("I have a hunch we make too many
constructors").

### `TUNE_UNIT_AFFORD_S` = 120.f

UNIT_AFFORD_S [seconds of income] -- a mobile unit's bid fades as its cost
approaches this much income, dying at the full bill (mass first, T3 from
surplus -- the supers' 60s affordability bar applied to units). His call
2026-08-29 ("we need more Titans or Thors so we can push"): 60 -> 120, so a
Thor bids from 75 m/s and a Titan from 112 instead of 150/225, while mass still
out-prices them at any income that can't spare the bill.

### `TUNE_SCOUT_OVER_S` = 45.f

SCOUT_OVER_S [seconds] -- one idle cheap air scout is sent across the enemy
position this often ("I don't see any scouts flying over their base"). 0
disables the overflight and stock mex-cluster scouting is all that remains.

### `TUNE_ECO_ROLE` = 1.f

RE-ARMED 2026-08-31 on his ask, with the mechanism replaced. It was switched
off ("the eco role ... does *not* work") while it worked by crushing the rear
player's army and defence TARGETS with multipliers -- a role deciding whether.
It now names a different target instead; see EcoRoleTargetM.

### `TUNE_GANTRY_AFFORD_S` = 100.f

GANTRY_AFFORD_S [seconds] -- the gantry's affordability horizon, over TEAM
income: one shared line the whole team's nanos man, so one team purse. At 100s
the ~9.3k bill clears right at ~100 team metal/s, his stated mark ("we can have
a gantry at like 100 m/s").

### `TUNE_GANTRY_HOST_INC` = 150.f

GANTRY_HOST_INC [metal/s] -- the proposing player's OWN income at which the
gantry gain is whole; below it the gain scales by (own/anchor)^2. The team
purse makes the case, the host's feed times it (apexearth, watching green start
one at 50 m/s: "that is too early"). Raised 100 -> 150 on his second call,
2026-08-30: "We should push back Gantry creation to 150m/s or later" -- watched
while the base had no T2 defence and the enemy arrived thick.

### `TUNE_OFFENSE_DEF_FLOOR` = 0.1f

OFFENSE_DEF_FLOOR: the share of its gain an offensive super (silo, LRPC) keeps
at ZERO standing defence; the rest scales in with the defence target's fill
("we consistently make Basilisk before T3 or even T2 defense"). 1 disables the
coupling.

### `TUNE_EXPOSED_LOSS_S` = 120.f

EXPOSED_LOSS_S: seconds over which a fully exposed, unguarded asset is expected
to be lost against a real opponent -- his "almost guaranteed". 300 priced
sentries below the NEXT mex claim, so every spot was claimed naked and died to
BARb inside the window; 120 flips to claim-then-guard.

### `TUNE_EXPOSE_R` = 1200.f

Until 2026-09-13 this circle around the nano farm WAS the escort trigger: a
worker more than half of it from the farm point was "exposed" and drew one
guard, whatever stood around it. Watched on Carrot Mountains 8v8: a base of
272 buildings had 225 of them past the circle, every Fark and Consul in the
back of it held a Pawn, 55% of fighter elections went to escort and 406
cheap units stood at home -- and those same Pawns filled the army target
that told five gantries `gap0`. Exposure is now `Market::WorkerExposure`:
the larger of the measured risk field's expected loss over the stake horizon
(`HazardAt x ShortfallAt x TUNE_STAKE_HORIZON_S`) and the territory map's
word on the ground (ours 0, empty half an escort, contested or theirs one).
His 2026-08-25 "home safe territory", read off the model instead of a
radius. The radius survives only as the reach inside which enemy metal near
a worker counts as escort demand.

### `TUNE_FRAME_RISK` = 0.0f

DEFAULT 0 -- the mechanism is wired but priced out. At 1.0 it suppressed
building outright rather than reordering it: total metal built fell 38.6k ->
17.6k and the head-to-head went 3-21 to 0-30 over 54 paired games. The charge
is a full standing expected-loss multiplied by buildSec/120, which for a
several-hundred-second structure exceeds its whole gain. Re-enable only with a
hazard field that is not saturated everywhere (see the front-geometry entry in
ISSUES.md).

### `TUNE_DEF_TRADE` = 3.f

DEF_TRADE: metal of enemy wave a standing turret is expected to stop, per metal
of its own cost. The exchange rate that puts coverage and threat in one
currency so a shortfall can be subtracted.

### `TUNE_DEF_TTD_H` = 120.f

A defence is discounted by H/(H+buildSec), so a slow turret keeps only the
share of the threat window it will actually cover. Defaults to the same 120 s
EXPOSED_LOSS_S uses -- a turret that takes as long to build as the asset it
guards takes to die is worth half of one that lands instantly. LOWER means
sharper pressure toward quick defences (a Guard at 2500 buildtime over an
Agitator at 17400); 0 restores the old behaviour, where build time reached the
price only through the builder's wage.

### `TUNE_PROTECT_FIELD_S` = 2.f

How often the protection field is rebuilt, in game seconds. It walks every team
unit once and every defence price reads it, so this is the knob between a stale
stake and a stalled sim -- want.protect was measured at 9.2 ms per call and
growing before the field existed.

### `TUNE_STALL_ANSWER_S` = 1.f

How often the energy-stall answer re-asks which worker should drop what it is
doing. Split from the 5-second housekeeping tick it used to share: a stall
costs income every second it holds, so the answer wants the fast cadence, while
the retreat table and the guard sweep do not. The scan stops at the first
worker whose top want is energy (commander first), so a faster tick costs less
per call rather than more.

### `TUNE_STALL_ANSWER_MAX_E` = 400.f

Energy income above which the stall answer stops asking at all. apexearth's
number: past this the economy is big enough that an energy stall is a transient
in the pull rather than something worth pulling a constructor off its task for.
0 disables the gate and asks at every income.

**2026-09-08: the bar now gates only the INTERRUPT (pulling a builder off a
task, army.as), not the per-election hoist (decide.as).** Measured on Isthmus
seed 13 at speed 10: energy income sat at 700 e/s from minute 12 to 24 with the
metal bank full and a fleet ask 1,950 e/s above income; `apex: nohoist ...
worth=0 hard=1 deficit=1950 eInc=773` every 15 s, and above the bar the
market's energy price won 6 elections in 12 minutes against 37 radars and 36
mexes. The deficit already says whether the stall is a transient (it is not
when the hands we own ask for three times what we make), so the hoist reads the
deficit alone. apexearth's 8v8 reading the same day: "teams are often lower on
energy than they should be. Would be fixed if we just had constructors
consistently creating energy buildings."

### `TUNE_UNPROT_DISCOUNT` = 0.20f

WHAT A BUILDING IS WORTH WHILE NOTHING GUARDS IT (apexearth: "give buildings a
~20% reduced value when they are unprotected. And the more powerful we create
defense around those buildings the more they become worth"). The share of a
structure's worth that is withheld over ground our cover does not beat the
local wave on, and that a turret covering it gives back.

### `TUNE_DEF_ALPHA_W` = 1.f

A TURRET ONLY SHOOTS WHILE IT IS ALIVE. Weights each turret's cover by
hp/(hp+alpha) against the punch of the biggest mobile unit the enemy fields,
derived through our own unit table. Near 1 for everything while they field
raiders; it is what separates a 1,670-hp Twin Guard from a 9,400-hp Bulwark
once they field something that erases the former in one pass. 0 disables it.

### `TUNE_ECO_RAID_TAU` = 180.f

ECO_RAID_TAU: seconds of memory in the structure-loss field. Matches the death
ledger's BLEED_TAU so both risk senses forget at the same speed.

### `TUNE_THREAT_R` = 900.f

THREAT_R: radius the enemy-mass prior is sampled over. DeathWalk's own corridor
sample, reused rather than re-invented.

### `TUNE_STAKE_HORIZON_S` = 300.f

STAKE_HORIZON_S: seconds of a mex's stream that count as the stake standing on
it. What makes a producing mex worth more to lose than its build cost.

### `TUNE_RISK_FLOOR` = 0 (was 0.15, 2026-09-11)

A flat hazard -- 0.15 of the full-loss rate, 1/800 s -- that every asset
carried whether or not anything had been seen, meant as cold-start insurance.
Once the siege prior was anchored on our own army (2026-09-09) this constant
became the whole of the early-game tower demand: on Greenest Fields at minutes
2-8 `apex: defprice` read `hz=0.00125 haz=0.00125 siege=0.0008-0.0011`, the
floor above the prior every time, nine light towers and four beamers before
minute 8 with `threat=1` (apexearth: "we still make too many early game
defenses and that slows us down"). The blind floor is now the siege prior
alone -- what a mirror of us could have committed to war -- so it is an
output that starts at zero and grows as anyone arms. The per-mex floor and
the measured loss rate stand. 0.15 is one modoption away.

### `TUNE_BUDGET_TAU` = 240 (2026-09-09)

How far back `Brain::ShareOf` averages realised spend. It was a lifetime total
against a steady-state target, which is not the same question: the commander is
2,700 metal booked as build power at frame 0, so the ledger read 1.00 build
power against a 0.17 target and `BudgetMult(BUILDPOWER)` sat on its 0.35 floor
until minute 8. Wired into the draw that cost 10% of metal produced over 3
seeds of his 8v8; with the fade and the commander excluded the same wiring is
inert. 240 s is four minutes -- long enough that one factory order does not
swing a row, short enough that the opening's build power does not follow us
into the mid-game. Not swept: the wiring it exists to serve was reverted, and
the ledger is a diagnostic until something reads `BudgetMult` again.
See ISSUES 2026-09-09.

### `TUNE_ROLE_SHARE` = 0.5, `TUNE_ROLE_TAU` = 120 (2026-09-08)

apexearth's design, his words: "assign roles to our constructors by a % based
on what it sees as a split of our needs... give an engineer a special role to
do only that job until our brain decides it is no longer needed... leave some
cons as open unroled cons." `market/roles.as`.

The split is not a new model of need: it is the category draw's own ticket
share, read off every election's full list and averaged over `TUNE_ROLE_TAU`
seconds. `TUNE_ROLE_SHARE` of the workers hold a role, quota per category =
share x roled hands, rounded. A hand takes the category furthest under quota
that its own list can answer, keeps it until the category is over quota or
offers it nothing, and its other wants stay behind the category's, so a
refused category falls through instead of idling (couplings law 3). The
commander is always open.

2026-09-13: the split is FLOORED BY THE TARGET GAP where a category has a
target of its own (`CatGapFrac`: defence = unmet share of `DefenceTarget`
net of in-flight; build power = `BPGap` over capacity; energy = unfed share of
pull). His ruling, watching Carrot Mountains 8v8: defence was 1% of every
Apex player's spend against a target 100x the holding, and the roles copied
that -- the ticket share IS what the draw picks, so a category the draw
starves got a starved quota too ("builder roles from target gaps sounds like
a smart idea to me. We certainly have more than enough builders"). The
`roles` line now prints `share+gap:held/quota`.

Both are his policy, not the model's: how many hands are committed is the
"leave some open" he asked for, and the averaging window is how long a role
outlives the job it was given for (a job is 30-300 s of walk and build; 120 s
is the exposure window every other rate here is scored over). 0 switches the
layer off for the A/B. Instrument: `apex: roles` every 30 s (share, held/quota
per category, taken/dropped) and `role=` on the decide line.

### `TUNE_HZ_APPROACH` = 0.f

Hazard floor from enemy formations **walking at** this ground:
`horizon / ETA`, clipped at 1, weighed by their mobile metal against
`our army + cover here` — the same mass ratio the presence term already uses.
`horizon` is `apex_exposed_loss_s`, which `gRkAnchor` is already the reciprocal
of, so `p = 1` means "here within the window, certain" and lands hazard on the
anchor. No new constant.

apexearth, 2026-09-07: *"when enemies are getting closer and closer to our base
and we're at T2 we really really need to try and making T2 or T3 defense…
it becomes a life/death situation."* Nothing in the risk field could hear that.
`HazardWith`'s loss term reads what has **already** been destroyed here, and
its presence term is scaled by `GradAt`, which measures distance to their
**base** and is zero at ours by construction. Measured, Frozen Ford minute
21–26 of `20260907-175233`, while the base was being dismantled — four mexes
down to one, economy 10,022 → 7,314, 1,148 / 2,251 / 2,337 metal of losses per
sample: `home[hazard=1.25/ks]` every line. 1.25/ks **is** `RISK_FLOOR/120`.
Defence gain over the same window: 0.03. Static defence ended that game at
**1.7% of spend against BARb's 15.9%**.

Evidence, never a prior: group data is LOS-slaved, so a wave we cannot see
reads zero here and leaves the field exactly as it was. That is what keeps it
out of the class of prior that repriced every want and cost 87% of standing
army — it cannot fire where nothing was seen. It is a floor, so it can only
raise. Mobile metal only (`GetEnemyGroupCost` counts the group's buildings,
and `velVec` is its fastest member, so a group centred on their base would
otherwise walk its whole economy at us at scout speed).

**MEASURED AND LEFT OFF. 8 games, Frozen Ford, 4 seeds x on/off, 2026-09-08.**
The term does exactly what it was built to do and it changes nothing, because
hazard was not the binding constraint.

It fires: in `HZ-on-13` home hazard reached 5.30/ks against a 1.25 floor, and
at the defence sites `hz` ran 0.0047-0.0053 where the floor is 0.00125 -- 4x,
on the measured approach, exactly as designed.

It does not matter: on the same lines `short=1.00->1.00`. One tower adds no
measurable cover against a wave of 2,000-2,900, so `stopped` is ~0 and
`gain = stakeK x hz x stopped` stays 0.01-0.06 however large `hz` gets.
Multiplying nothing by four is nothing. The single line in that game with real
gain (0.44) is the only one where the tower moved the shortfall at all
(`short=1.00->0.87`).

Across the sweep: defence 12.5% of spend off vs 13.7% on, T2+T3 50.3% vs 49.9%,
per-run defence share 7.9-17.1% in BOTH arms with no separation -- and the one
game where the term fired had the LOWEST defence share of its arm (9.8%).

**So the master blocker in USER-FEEDBACK is confirmed as the blocker, and it is
`stopped`, not hazard.** Defence against a real wave prices to zero because a
single turret's share of a large threat is negligible; every term upstream of
that is multiplying a zero. Fixing the risk field was the wrong blindness to
fix first. Kept at 0 as a working instrument -- the `appr=` field on
`apex: risk` and `apex: defprice` is what showed this -- not as a behaviour.

Note the baseline moved under this measurement: the GradAt/ForwardFraction fix
(same session, `coverage.as`) had already lifted defence from the 1.7% of the
`20260907-175233` loss to ~12.5%, so the field blindness this was aimed at was
substantially addressed by that change first.

### `TUNE_ALLY_SHARE` = 1.f

ALLY_SHARE: 1 = scale the SEEN census in ArmyTarget by our income share of the
team (the census is side-wide; the answer is split by the roster). 0 = every
player answers the whole enemy team (the pre-2026-08-28 form).

### `TUNE_REZ_HORIZON` = 120.f

Seconds over which the army's repair backlog (`GetOwnRepairM`) is read as a
rate. NEGATIVE RESULT, 2026-09-06: suspected of being the same stock-over-a-
hand-picked-horizon bug the wreck half was, and measured not to be. On the
60-minute 16-AI game `20260906-105022`, `repairPs` cross-checked against the
gadget's `damageReceived` derivative gives 0.09-0.25 metal per HP of damage
taken, no trend across the game -- i.e. the backlog sits in quasi-steady state
with a residence time near this horizon, so backlog/120 IS the arrival rate of
repair work. `repairPs` and the measured-rate `wreckPs` also grow at the same
speed over the game (10.1x vs 11.5x, minute 12 to 54), where the deleted
`gRezField` grew 90x against a 15x arrival rate. Cutting this half would take
the early fleet from 3.5 to ~2 bots at minute 12 and from 5.8 to ~1.8 at
minute 24, below the 4-5 apexearth asked for. Left alone.

### `TUNE_REZ_UTIL` = 0.35f (0.25 until 2026-09-13)

Share of a rez bot's work rate it actually delivers (the rest is walking
between wrecks). The fleet saturates when have x buildPower x this covers the
recoverable stream; an ESTIMATE, not a measurement -- raise it to field fewer
bots. It is the one term that scales the whole fleet 1:1 and the only one still
unmeasured; see ISSUES.md 2026-09-06 for what the fleet actually returns.

2026-09-13: 0.25 fielded 99-129 Rectors per player at 30 min in 1v1s (peak
`rezwant have=`) against BARb's `"limit": 60`. apexearth: "I like that we
have them, they're very good, but wow we have a lot... let's turn the rezbots
down a little and I'll watch it in future games." 0.35 is ~30% fewer at the
same stream. The honest value is still unmeasured: `rez-time` logs what the
bots spend their samples on and would give it.

### `TUNE_RETREAT_FLOOR` = 0.08f

RETREAT_FLOOR: the HP fraction where the cheapest unit starts to flee. 0.08 was
set against stock's 0.6 (93% of combat metal died retreating); his 2026-08-28
report is the other rail ("units retreat on a very low HP %" -- a sliver-HP
flee dies anyway). Raise only with a deaths.py died-retreating measurement
beside it.

### `TUNE_DRAW_DEFZONE` = 0.f

Draw the defense zone on the map: the inner ring is the C++ base-defence range
(the army fights at any odds inside it), the outer ring the incoming-push alarm
radius. Off by default because it ships; the harness opts in with
apex_draw_defzone=1.

### `TUNE_DRAW_LANE` = 0.f

Draw the army's staging anchor and, when apex_medic_setback is set, the medic
station behind it plus the step between them. Off by default because this
ships.

### `TUNE_DRAW_HEAL` = 0.f

Ping the heal post: the exact point CRetreatTask sends wounded units to (front
+ apex_retreat_behind toward home). A ping rather than a line because there is
only one of them.


## Everything else

### `TUNE_AID_RESPOND` = 1000.f

AID_RESPOND [metal lost at an ally's hotspot] -- above this the staging lane
moves to that fight (clamped to contested ground). 0 disables the response and
leaves the hotspot publish-only, as it was.

### `TUNE_WAVE_CONC` = 1.f

A defence site prices against the enemy's whole fielded army (capped by the
stake behind the site), not a per-site share of it: their mass all takes one
approach, and the rate term already says how often. This is what lets a
Pulsar-class gun out-bid a carpet of cheap towers once the enemy fields real
weight.

### `TUNE_WALL` = 1.f

Ground defence sites are slots along the WALL: the rim of our own buildings
plus a standoff, sampled at tower pitch so filled slots form a contiguous line
that grows with the base. Replaces the asset-cluster, front-line and
closure-ring candidates (gates and the ally-front post stay); 0 restores the
old set.

### `TUNE_WALL_REACH` = 2.5f

Cap on how far one bearing's buildings can drag the wall, as a multiple of the
worth-weighted RMS radius of everything we own. A lone far mex stays outside
the wall; a real expansion moves the RMS and the wall follows.

### `TUNE_WALL_REAR` = 0.08f

Share of the wall pull a slot DIRECTLY BEHIND the base keeps (enemy-facing
slots get the full pull, tapering by bearing). Low is the concentration
doctrine (apexearth 2026-08-30: "if we just focus on defending our frontline we
don't have to build so many defenses all around our backline") -- the sealed
LINE is what protects the rear, and a real rear threat still buys towers
through the evidence terms. 1 makes the pull uniform.

### `TUNE_WALL_LINE_W` = 2.f

The front LINE's pull relative to the ring: his completeness ruling (a wall the
enemy can walk around is useless) makes an extending section worth more than a
redundant deepening. 1 prices line and ring equally.

### `TUNE_WALL_EFFICIENT` = 1.f

1 = a WALL slot, whose gain is the def-independent unmet-target pull, ranks
candidate towers by cover per metal. Without it the only discriminator there is
absolute power, which buys a T1 hand's most expensive tower for a rear slot
with no threat.

### `TUNE_DEF_KILL_CAP` = 1.f

Cap a defence site's stake at the metal of attackers the candidate turret can
actually destroy over apex_exposed_loss_s. Without it reach pays as AREA with
no bound from rate of fire, which is most of why a long low-DPS gun outprices a
short one.

### `TUNE_DEF_DPS_LINEAR` = 1.f

Price a turret's cover on its SURFACE DPS (linear) instead of the engine's
sqrt(dps)-compressed threat. Reach is already paid as area by PfStakeIn and hit
points twice over, so rate of fire was the only under-weighted term; 0 restores
the old pricing for an A/B.

### `TUNE_T1_DEF_LATE` = 0.02f

A T1 tower's gain once our own advanced lab stands; 1 prices tiers equally.
Sized to agree with the AI's own outclassing measure: where an advanced defence
hand IS standing, TeamBestTowerPower already scales a Twin Guard by power
190/29000, and this is the same order for the players that have the lab but not
yet the hand.

### `TUNE_RADAR_OVERLAP` = 0.45f

A gap must sit outside this share of every standing radar's reach before a new
mast is blocked; lower = more overlapping radars, sturdier intel. Was a
hardcoded 0.8 (no redundancy; one death = a dark zone mid-fight).

### `TUNE_FRONT_REAR_ARC` = 0.f

NOTHING BEHIND US IS FRONT. 1 is the ESCAPE HATCH -- the full ring, for a
genuinely surrounded base. It shipped as the default, so the rear exclusion the
ring scan was written around had never once run: measured rays=24/24 with the
enemy on one bearing, which is the ring closing on itself that its own comment
warns of.

### `TUNE_PERSONA_SPREAD` = 0.35f

apexearth 2026-09-12: "adding personality to each unique AI randomly. Simple
high level modifiers affecting an AI's interest in making certain things --
Economy, Defense, Army, T3 Army, Air, Nuke Weapons, LRPC." Seven traits per
instance, each log-uniform in [1, 1+s] (0.35: 1x to 1.35x), rolled once and
logged as `apex: persona t=N rolled ...`. They multiply levers that already
exist -- the army and defence targets, the draw value of eco and defence
wants, the strategic wants (gantry/silo/big gun/air plant), the air commitment
-- never a gate. 0 makes every instance identical: the A/B arm.

Up only, never below 1 -- apexearth 2026-09-12, on seeing a roll of eco=0.76
army=0.75: *"we should probably not go below 1 on eco and gantry ... maybe we
should only ever increase some tendencies and not decrease them. i worry about
some really bad configs."* The worst roll is now the neutral AI; a lean is
extra interest in something, never starved interest in something else. The
budget rows are still shares of one pot, so army=1.35 still buys its army out
of the other rows -- the floor protects the pricing of eco wants and the
gantry, not the eco share. The adaptation leans were already all >= 1. In a
duel nuke and lrpc stay at 1 (was: clamped from above).
Replaced `TUNE_PERSONA` (the six discrete kinds -- berserker, turtle, greedy,
airboss, siloist, rearm -- whose budget lever nothing read since f4b8cdcc).
The default width is his to move; nothing measured it yet.

### `TUNE_ASSIST_RELEASE` = 1.f

Assisters beyond a site's ETA-derived worker count fall back into the auction
instead of being held to completion. 0 restores the glue.

### `TUNE_NANO_FED_S` = 15.f

NANO_FED_S [seconds] -- a join is refused when standing-nano lathe alone clears
the site's remaining bill within the joiner's walk plus this many seconds; the
freed constructor founds a new frame instead (a nano can assist a frame but
never place one). Sized to the walk-and-found time of the next ring spoke. 0
disables the gate.

### `TUNE_DRAW_SHARP` = 2.f

how sharply the category draw follows value. Odds go as (value/leader)^this: 1
is the old straight-proportional draw, 2 makes a six-fold value gap one
election in thirty-six, large approaches argmax. Never a threshold, so nothing
starves outright.

### `TUNE_MEMO_TTL` = 45.f

Frames a memoised proposer answer may be served for. VALIDITY is `MemoKey` — the
stamps of what the answer was computed from; this is only the ceiling on the half
no stamp reaches, `ValueOf`'s income, pull, bank, wage and build-power terms,
which move every frame. 45 is what the clock alone used to be, so the default
changes nothing. It is the throughput knob: measured 2026-09-05 the memo hit 593
/ missed 3,135 / deferred 1,760 (11%), because 45 frames is shorter than the 2 s
per-unit re-election gate, so an entry always expired before the next builder of
that def asked. Raising it buys recomputes with price staleness — a behaviour
call, so sweep it against `composition.py`.

### `TUNE_ELEC_FRAME_US` = 8000.f

Microseconds one sim frame may spend assembling builder elections. `decide.as`
cuts the 18-proposer stack against it between steps, opening a step only when
its own measured cost still fits, so it bounds the frame it is checked on — the
old door check could not (`hk.maketask.builder` maxMs 122.9 in one call). The
trade is latency: a builder waits `ceil(election / this)` slices, pumped from
every builder update. Above a whole election (~28.5 ms) nothing is sliced. Not
swept; read `apex: elec-slice` worstWaitS against that maxMs before moving it.

### `TUNE_MEDIC_SHARE` = 0.4f

share of the rez fleet that serves as battlefield medics: they stay with the
army's staging anchor, repair the wounded during fights and reclaim the
aftermath there. The rest work the corpse geometry as before. 0 disables
medics.

### `TUNE_MEDIC_SETBACK` = 0.f

how far BEHIND the lane a medic holds station. The lane is where the army is
fighting; a medic parked on it is in the fight. 0 keeps the old on-the-lane
behaviour.

### `TUNE_REZ_FLEE_S` = 20.f

how long one hit keeps a rez bot retreating. A rez bot cannot dig in, only
leave, but the hold was 90s: one stray shell parked it for a minute and a half.
Lower works sooner and eats more chip damage; the threat vetoes still refuse
hot work on the way back.

### `TUNE_REZ_SCAN_S` = 1.f

spacing on ONE bot's own wreck and resurrect scans. Was a single team-wide
clock, so with several bots idle most of them lost the race every period and
stood still. Lower is more responsive and costs one feature query per bot per
period.

### `TUNE_REZ_REACT_S` = 1.f

how much of the enemy's own walking counts as being in range already. A rez bot
backs away while the nearest enemy is still this many seconds short of its
firing envelope (its weapon reach plus speed x this), and refuses work inside
that envelope. Not picked: it is apexearth's own latency bar -- "delays of more
than a second are unacceptable" (2026-09-06) -- turned into distance, since the
ground the enemy covers while we notice and start moving is ground we have to be
clear of already. Read by both the DLL's guard (BuilderManager's UpdateRezGuard,
six times a second) and every rez election (`ReachSlack`, sitesafety.as), so the
reflex and the election cannot disagree. Higher = a wider no-go ring and fewer
corpses eaten; 0 = back away only once the shooting can already reach.

### `TUNE_RAIDER_MASSING` = 0.f

1 = raiders join the massing pool once our advanced lab stands and fight as
line army (the pre-2026-08-30 behaviour). 0 = they keep raiding all game, as
stock BARb does. Measured at 1: zero RAID and zero ATTACK task elections across
11 matches.

### `TUNE_SPAM_RAIDERS` = 1.f (0 until 2026-09-13)

1 = cheap RAIDER-role units are routed to solo scout tasks in spam phase,
spreading over unscouted clusters. 0 keeps them raiding; scout-role chaff
spreads either way. CScoutTask cannot group.

On since 2026-09-13, his ruling after the Carrot Mountains 8v8 where 55% of
one player's fighter elections went to escort and 406 cheap units stood in
the base: "All these escorts should instead be the fodder/spam guys
distracting our enemies... if raider-spam works correctly then yes I'm ok
with having it on." The condition is that it WORKS: judge on where the
spamscout units die (`deaths.py`, forward of the farm) and on the `elect`
census, not on the flag.

### `TUNE_SLOT_TRIES` = 12.f

Lattice slots offered to the engine before a placement gives up on growing a
cluster and seeds a new one. A bound on WORK per placement: each try is one
FindBuildSiteNear.

### `TUNE_AISLE_GROW` = 1.f

A GROW slot must keep the cluster aisle to a foreign def, not just avoid
touching it. Rule 3 parted clusters by an aisle on the SEED only, so growth
filled the street back in and sealed units into the pocket. Trades against
sprawl: a cluster that cannot grow toward its neighbour seeds another one
further out.

### `TUNE_CLUSTER_N` = 16.f

How many of one def stand together before the next starts a fresh cluster
elsewhere, so the whole economy is not in one spot. 16 is a 4x4 block; the
aisle between clusters is derived from the widest unit we field, not tuned
here.

### `TUNE_FARM_ROWS` = 28.f

Rows of lattice the farm scan walks rearward before giving up. A bound on WORK
per placement, not on the base.

### `TUNE_RECLAIM_BLOCKER` = 0.f

Reclaim one of our own economy buildings that is standing in a lattice slot C++
could not place on. DEFAULT OFF: measured 2026-08-25, 8 paired seeds, it cost
more constructor time than the ground was worth -- metal built median 17,978
with it off against 12,417 with it on, eco 5,436 against 3,869, and even the
tiling it exists to improve fell (47% touching to 39%). The pricing and the C++
blocked-slot signal stay for a cheaper retry: the want has to compete against a
mex, and clearing ground is not worth a mex.

### `TUNE_DEF_ECO_S` = 120.f

**SUPERSEDED 2026-09-09.** `DefenceTarget` is now `(gAssetsM + ArmyValue()) *
Brain::TargetShare(DEFENCE)` -- the defence row's share of standing power,
normalised against every other row (apexearth: "we should want our economy to
be N% of our overall power, we want to keep all of our aspects in balance with
each other"). Seconds of income has no relation to the size of the thing being
guarded and outruns it as income grows: on Greenest Fields the target reached
6,615 while the whole economy it protected stood at 5,478, and defence ran 30%
of everything we built against BARb's 7%. On the share basis the same game
asked for ~2,000. The constant is kept so a config naming it still parses.


HOW MUCH STATIC DEFENCE WE MAY OWN, as seconds of total economic power
(EcoPowerM, metal/s incl. realizable energy). The whole basis of DefenceTarget:
at 40 metal/s this is ~1,200 metal, a handful of light towers; at 400 it is
~12,000, enough to carry a Pulsar. Replaced (expected wave - our own army) /
trade, which collapsed the target to a mex floor exactly as the army grew. 30
was chosen to clear one heavy gun at hosted-game income and starved the low
end: at benchmark's ~25 m/s it budgeted 750 metal of defence for a whole game
while stock stood 11,700-17,800 in the same matches -- the naked rear the death
ledgers measured everywhere. 120 is the measured recalibration, still far under
the pre-target 175%-of-eco runaway.

### `TUNE_DEF_OFF` = 0.f

THE NO-TURRET TEST (docs/24-how-units-fight.md): 1 proposes no ground or AA
turret at all, so radar and units are the whole defence. Override it on a
launch (tools/test_earlyfight.py does); the default stays 0.

### `TUNE_ECO_TARGET_BASE` = 250.f

The economy the rear specialist names before it spends anything on war, in
metal/s of economic power AT NO BONUS -- EcoRoleTargetM multiplies by the
game's own handicap, so 250 here is 500 in a +100% game. Measured on Supreme
Isthmus 8v8 +100%, the median player passes 500 at minute 20 and 855 by minute
25, which is apexearth's "no army and no defense until like 20 minutes"
expressed as economy rather than a clock.

### `TUNE_ECO_TARGET_BASE_8` = 500.f (2026-09-13; halved 2026-09-14)

2026-09-14, watching the seat with the war ramp (army/defence/silo from half
the target): "we started to make more military but we didn't make any more
factories. I guess we should just let it go full military and normal
behavior at 1k metal instead of 2k metal." 500 x the +100% handicap is his
1k; the ramp then runs from 500 to 1,000 displayed. The seat at the old bar
(seed 4, 30 min): income 969, 4 silos, 139k army on a linear ramp.


The same bar for an eight-player team. His design: "1 player does an eco
role where they only activate their military once they've hit ~1000 metal
income... if bonus is +100% then its 2000 metal income. So this would be
only on an 8v8 map, 1 AI makes almost no defense and makes no military,
focusing on economy. It should be the player furthest away from the
enemies." The election (rear-most by margin, teams of 5+) is unchanged; the
bar is 1000 x handicap on an 8-player team and 250 x handicap below that.
What changed with it: while the role grows, the cover need, the spilled-metal
floor and the escort bid buy no army for that player -- measured on his
Carrot 8v8, the specialist (team 1) reached 386 of 500, then spent 76k on
army against 48k on economy through exactly those three and lost 228k, the
most on its team. Defence is ZERO while it grows too, his ruling an hour
into the first watch game ("they spend huge on defenses. Almost 10k on
defenses spent by minute 13, we would eco so much faster if we didn't do
that") -- superseding his 2026-09-02 correction, which was made on a 4v4
where no seat was safe. The raid valve (EcoDangerNear) still ends the
growth; anti-nuke and the AA emergency are not this target. Judge on `apex: eco-status` (P
against the target by minute, danger flips) and the specialist's own
metal lost.

### `TUNE_AIR_ECO_BASE` = 100.f

Economic power, at NO-BONUS scale, before the bomber raid is worth mounting at
all -- the game's handicap multiplies it, so 100 here is apexearth's "200 m/s"
in a +100% game. Below it bombers price at zero and the metal goes to the
ground army instead ("we don't want to make air too early, it makes us weak on
ground"). This replaced an 11-minute TIMER, which could not tell a rich game
from a poor one.

### `TUNE_LINE_TERRAIN` = 1.f

Weigh a production line by how much of the map its ARMY can move around in
(ai.DefMapCoverage, the engine's own per-movement-type partition). 1 = on, 0 =
off, which is the control arm. On a flat map every line reads the same and this
changes nothing; on a hill map the vehicle line is discounted against the bot
line, which is apexearth's rule for picking the ground line.

### `TUNE_LINE_QUALITY` = 1.f

Weigh a production line by the best army-per-metal its units offer here --
UnitPPC with the speed and sight terms production already buys single units
with -- against the best line of its class and tier. apexearth 2026-09-12: "if
we lose, it is because we are not making the most optimal army composition. I
still notice ... that we just make bots almost all the time. So in maps where
vehicles are obviously more powerful, we don't do quite as well." Before this
the production half of a plant's price carried no fact about its units at all:
on Comet Catcher Remake the bot and vehicle labs priced within 5% of each other
and bots won on coverage (95 vs 88). `apex: line-quality` logs what the model
thinks of each land line, once a minute. 0 is the control arm.

**Measured inert, 2026-09-12, and left OFF.** The census itself agrees with
him -- Comet Catcher Remake reads T1 corvp 1.00 / armvp 0.66 / corlab 0.56 /
armlab 0.51 and T2 armavp 0.65 / armalab 0.26 -- but the plant choice did not
move in any of 8 treated games (`tournaments/20260912-185255-linequal2`,
1v1 Comet Catcher Remake + Supreme Isthmus, 4 seeds, vs a control lane at
9986d2d8): every game still opened armlab and stepped to armalab. Two reasons,
both outside this term: the opening plant is bought at 0.7-1.3 min when the
production half is ~0.8 against a constructor half of ~4.3, so the line is
chosen for its constructor; and the T2 plant is priced in `want_tech.as` by
`PlantLineWorth` (mean power/cost), which this term does not touch. Outcomes
were noise either way (Comet control 2-1-1, treated 1-3; Isthmus 0-1-3 vs
1-1-2).

**Second form, same day, his terrain ruling.** *"If the map is mostly flat
with just some hills then we want vehicles but if it is full of hills all over
the place then we might want bots."* The factor is now units x ground --
median army-per-metal times `LineCoverage`, the pathfinder's own reach for the
line, which is his height average done by the thing that decides where a tank
can go (a smooth ramp stops nothing, a field of ridges stops everything) --
normalised to the best line of the class and tier and applied to the WHOLE
plant price and to the tech want's `lineW`. On Comet Catcher Remake that reads
T1 armvp 0.66x0.88 against armlab 0.51x0.95: vehicles; on Sulphur Springs
(coverage 54 vs 66) the T2 vehicle lab still wins on its units.

**Measured worse, 2026-09-12 late, and left OFF.** Third battery
(`tournaments/20260912-223726-lineunits2`, the factor on the value the plant
is actually priced by, 340a4a92): Comet control 4-0, treated 2-2; Isthmus
control 0-1 (+3 time-outs), treated 0-2 (+2). The opening plant still read
armlab 0.03 to armvp 0.02 with line 0.83 vs 1.00: the vehicle plant's own
higher cost and build time outweigh a 17% line factor in the ETA price, and
the proportional draw then opens a bot lab 7 games in 8. Where the factor did
move the choice it opened the HOVER plant on Isthmus (line 0.95) and lost at
24 min with 34k metal. Two of the treated Comet games opened a minute late and
were dead by 16 min -- near-equal plant candidates alternating in the draw is
the suspect (S14), unverified. What his rule needs is a factor that IS the
decision on a flat map, not a nudge under the plant's price; and the hover
plant must not qualify as "vehicles".

### `TUNE_COVER_LEAVES` = 1.f and `TUNE_COVER_BY_RAID` = 1.f

apexearth 2026-09-12, told that the C++ fight tasks are stock but the election
that feeds them is ours and that a 40-minute Isthmus 1v1 held 427 units in
`cover`, 231 in `escort` and 61 in `mass.hold` against 60 handed to stock and
20 in `mass.attack` -- a 307k army (target 323k, met) against 13-27k of theirs,
holding an uncontested line at -0.11 to the time limit: *"Ok try doing both of
those."* (1) the cover pool gets stock's exit -- `Defend(ATTACK, ATTACK,
quota.attack)` instead of the MELEE pair nothing ever converts; (2) the metal
posted to cover is bounded by our share of the raider metal they have fielded,
the AA counter's answer law, because the coverage need counts sites and a pool
never stands on the posts, so at scale it never closed. `apex: elect ... |
coverM=held/cap need=` is the instrument. 0/0 restores the hold. Battery on
the same eight time-out seeds pending.

### `TUNE_SCREEN_GAP` = 200.f

How far IN FRONT of the squad's longest row a short-range row holds, elmos.
apexearth 2026-09-01: "the tanks should just stand around in front of the
sheldons... they won't walk up to enemies to shoot at them. They are there as a
shield." The screen line is highestRange - this; clamped so it can only add
standoff, never pull a row closer than its own reach. 0 restores "stand at your
own range" for every armed row, which is the control arm.

**96 MEASURED WORSE, THREE WAYS, AND WAS REVERTED (2026-09-05.)** apexearth:
"Ensure that our tankier units in squads don't dive too deep into enemy lines...
Rely on rocketbots to shoot from long range." This number IS the dive depth, so
one formation rank (`SQUAD_FILE_SPACING`, 96) should have been the shallower,
safer screen. Four 24-game arms, Apex vs BARb hard, Comet Catcher / Callisto /
Glacier Pass, 25 min, identical DLL with the arm selected by modoption:

| arm | metal K/D | built | produced | T2 |
|---|---|---|---|---|
| **200 (kept)** | **0.414** | 24,932 | 25,858 | 3,840 |
| 96, every short row | 0.357 | 21,564 | 23,718 | 0 |
| 96, rows at/above squad-average hp | 0.393 | 22,064 | 25,050 | 3,135 |
| 96, rows out-tanking the carry | 0.321 | 27,174 | 26,120 | 4,690 |

The mechanism, from the `apex: screen` line added the same day: the rows that
actually screen are chaff, not tanks. corak (Grunt, 280 hp, our most-built unit
at 1,029 a tournament) and corfav (FAV, 90 hp) held the line, and at 96 they sit
outside their own 215/180 reach -- a DPS block told to stop shooting. Both
tankiness gates failed to exclude them (Grunt still screened 456 and 325 times),
so a working selector is an open problem, not a tuning one.

The last arm is the interesting one: best economy of all four (built 27,174, T2
4,690, both above the control) and the worst trade, because losses rose 207k ->
271k for flat kills. Standing the screen shallower buys build time and pays for
it in army.

What was kept from that session: three clamps in `ISquadTask::Attack` that
dragged a screen row forward to its own weapon range regardless of the line --
the coward "rear but still firing" cap, the static-we-outrange ceiling (which
fires against every unarmed target, so every mex and solar), and the
`staticCantReply` plain attack, which hands the unit to the engine to close on
its own. Those are in the 0.414 control arm.

### `TUNE_TEAM_LINE` = 1.f

The production half is divided by (1 + this * matesWithIt), so at 1.0 the
second team copy is worth half and the third a third. apexearth, watching a
4v4: "I'm still seeing us start with 4 bot labs on comet catcher. Enemy seems
to have done 2 bot labs, 1 vehicle, and 1 air." Not exclusivity -- a fourth bot
lab is still allowed, it just prices below the first vehicle plant. 0 restores
the old behaviour, where every player reasons alone.

### `TUNE_DEF_DOMINANCE` = 1.f

A defence slot holds ONE building, so a tower beaten on BOTH reach and killing
power by a gun we can afford right now is not a cheaper option, it is stranded
metal (apexearth: "why build something that so quickly becomes outdated?"). 1 =
on, 0 = off, which is the control arm.

### `TUNE_DEF_AFFORD_S` = 30.f

Seconds of total economic power a defence building may cost and still count as
affordable -- the guard that stops a Pulsar we cannot pay for making every
tower obsolete and leaving us with nothing. At 40 m/s this admits ~1,200 metal;
at 300 m/s it admits a Pulsar.

### `TUNE_CONV_AFFORD_S` = 30.f

Seconds of economic power the converter burst may commit at once. The bank is
the wrong bound -- we deliberately run it near empty, so metal.current/price
was 0 or 1 and the burst never fired while half the grid was wasted. A
converter pays back in 37 seconds, so 30 seconds of economic power is a bill
the economy carries comfortably.

### `TUNE_E_COMMITTED` = 1.f

Count the energy draw of work already ORDERED into the pull that prices energy.
Not a magnitude: the quantity added is arithmetic off the catalog (remaining E
cost over remaining build seconds), exactly as ConvCapInFlight already does for
converter capacity. 0 is the control arm, pricing on realized pull alone --
which is where the first energy decision lands 73 seconds and one full stall
after pull passed income.

### `TUNE_E_PARALLEL` = 0.f

Let a STALL open parallel energy sites, not only an overflowing bank. Energy
asks fold onto one standing request unless the bank spills, and during a stall
it never does -- so a 300/s deficit was answered 35/s at a time, serially.
Opens exactly while ordered generation still fails to cover the shortfall.
MEASURED AND DEFAULTED OFF. Three paired 20-minute Carrot Mountains seeds: with
it on, metal built 25,500 -> 19,555 and mexes 42 -> 33, for a stall reduction
of 444 -> 352. It buys the smaller stall by splitting build power across
several frames at once -- which is the same thing this AI penalises a second
lab for, and against apexearth's own rule to "focus as much build power as we
can on just the one building". The serialized fold is not the bug; it is that
focus rule working.

### `TUNE_PLANT_INFLIGHT` = 1.f

Discount a plant want by the plants of ANOTHER domain already under
construction. reachKin is per domain, so bot -> vehicle -> air rotated freely:
each new class priced as though nothing were in flight, and the same income
split across three frames finishes none of them.

### `TUNE_COVER_PUSH_S` = 10.f

The mex-cover QUEUE JUMP only fires once the tower costs less than this many
seconds of total economic power. The jump overrides the auction outright
(measured: an LLT priced 0.03 built ahead of a mex priced 88.17), so at opening
income it buys sentries before there is a base. 10s means a 90-metal light
tower waits until roughly 9 metal/s of economic power -- past the first mexes
and the first lab, which is the order apexearth asked for -- while a
1,250-metal Gauntlet has to wait for 125. Below the bar the tower still
competes on price like anything else.

### `TUNE_MEXUP_BOOST` = 1.f

What a mex UPGRADE'S extra metal stream is worth, over its honest arithmetic.
2.79 is the measured median ratio by which energy was beating mex upgrades head
to head when an upgrade ranked second (394 such losses in one 60-minute game),
so at this value the two are level at the median rather than extraction always
losing. 1 is the arithmetic with no thumb on it.  MEASURED AT 2.79 AND LEFT AT
1. Paired 60-minute Carrot Mountains games: the boost does exactly what it
claims -- mex upgrades go from 7% of advanced-con decisions to 33% and become
the most-chosen want -- and the OUTCOME is worse. Upgrades actually standing
fell 94 -> 69, mexes held 243 -> 182, metal built 863k -> 358k, income 1001 ->
377. It displaces the energy that pays for expansion, so there are fewer mexes
left to upgrade. One game per arm on a bench that does not reproduce, so treat
the direction and not the size -- but nothing here supports shipping it above 1
(apexearth's own rule: validate outcomes, not log lines).

### `TUNE_DUP_BP_SUBST` = 1.f

Price a DUPLICATE line's throughput against the cheaper way to buy the same
build power. An advanced lab is 300 workertime for 2900 metal and a
construction turret 200 for 210, so the turret is nine times the build power
per metal (apexearth: "the right choice is to add more nanos to the lab instead
of making another lab"). Applied only while a line is actually short of hands,
which is his "unless you ran out of room" clause. The one bad game that got
this defaulted off predates nano frames actually completing -- with nanos never
finishing, this discount removed the only build-power purchase that ever
completed. 0 is the control arm.

### `TUNE_REPLANT_DISCOUNT` = 0.15f

What a plant def we RECLAIMED ON PURPOSE prices at while the window below runs.
14 of 15 T2 bot labs in one 1v1 died to our own reclaim and were re-bought; a
retirement the market can immediately reverse decides nothing. 1 disables.

### `TUNE_REPLANT_WINDOW_S` = 600.f

How long the retirement memory above holds. Chosen, not derived -- long enough
to outlive the walk-and-rebuild cycle it exists to break (~90s), short enough
that a genuinely needed line returns inside a game phase.

### `TUNE_FOE_TIER_FADE` = 1.f

How fast a unit's -- and a plant's PRODUCTION -- value fades as the share of
identified enemy metal above its own tier rises. Priced as 1/(1 + this *
shareAbove): at 1 an enemy fielding nothing but a higher tier halves what a
lower-tier unit or line is worth. Never zero, because a fielded T1 still
shoots; 0 is the control arm. Chosen, not derived -- measure it.

### `TUNE_OWN_TIER_FADE` = 0.8f

The same fade against OUR OWN fielded tier: once a T2 lab or gantry stands,
lower-tier units lose 1/(1+this*tiersBelow) of their worth ("in late game,
aside from spam we should mostly only be putting our resources into T3 units
and advanced air"). 0 disables.

### `TUNE_ALLY_COVER` = 400.f

What a teammate holding this ground is worth as cover, in the same currency as
our own towers. 0 restores the own-towers-only reading, in which a rear player
behind four allies prices as the most dangerous ground on the map.

### `TUNE_DEF_PRIOR_SHARE` = 0.35f

Share of the SYMMETRIC enemy expectation that the defence target assumes could
arrive at our own base before anything has been seen. Without it the target is
zero until something actually arrives, which is a strategy of having no
defence.


### `TUNE_COMM_FWD_CAP` = 0.25f

Forward fraction (0 home, 1 enemy) beyond which the commander is run home
under caution, and since 2026-09-05 also the bound on where an election may
send him: a job whose site is past it is refused before the axis test, which
alone let a radar 1300 elmos sideways of the anchor through (fwd -267 by the
axis, 0.82 by the map) and lost him. Commander minutes forward per 6-game
set: 10-11 before, 0 after. Not tuned; 0.25 is the caution value.

### `LatheHeart` / `FarmSlot` origin (no tunable)

Where an expensive building is founded relative to the build power we already
own. Instrumented 2026-09-05 with `apex: sink-site` (logged in
`Requests::Register` for every def `NanoSinkWorthy` accepts): over 35 game
minutes vs BARb hard, seed 1, **13 of 15** such builds — both fusions, the
AFUS, the advanced converter, four T2 lab requests, the antinuke, the
annihilators — were founded with `ringbp=0`, on ground no standing turret
reached. The nearest turret was 42 to 725 elmos beyond its own reach. Only the
air plant (`ringbp=800`) and one lab (`ringbp=200`) were inside a ring, and
both are factories, which is where `ExecuteWant`'s `WK_NANO` branch sends
turrets in the first place.

Mechanism: `gFarmPos` is planned once, before any turret exists
(`EcoSiteFor`), and `FarmSlot`'s scan is a corridor one cluster wide and
`apex_farm_rows` (28) deep running *backward* from it. The turrets meanwhile
pack at the factories, which that corridor never crosses. Measured positions:
farm 1968,2976; turrets at 2368,2976 / 1616,2568 / 1424,2448; fusions at
1120,2792 and 1024,2792; AFUS at 640,3168.

Fix: for `BigEcoDef` only, `FarmSlot` scans from `LatheHeart()` — the standing
turret with the most build power reaching it — instead of `gFarmPos`. Only the
window moves; slots still come off `Base::gAnchor`'s lattice, so the phase C++
snaps to and every layout rule (kin, cluster cap, blast aisle, walkways, spot
clearance) is untouched.

**Negative result, measured:** gating this on `NanoSinkWorthy` instead of
`BigEcoDef` is a regression. That predicate's third clause is build time, and
the advanced solar (7,950) clears a construction turret's (5,300), so the
advsol pack — strictly serial, and the spine of the energy ladder — had its
window moved too. Seed 1, same map: advanced solars built 10 → 5, fusions and
AFUS 12 → 0, none ever priced, and the game was lost at 23.5 min against a
35-min baseline. Do not widen the predicate without re-measuring the ladder.

**Not yet measured:** the narrowed version has no clean A/B. Another session
was editing `baseplan/*`, `nanopack.as` and this same file and redeploying
between runs (silent failure S19), so every post-change run is unattributable.
The `apex: sink-site` line is the instrument to judge it with: it should show
`ringbp>0` on `armfus`/`armafus`.

**Still uncovered:** `WK_TECH`, `WK_PLANT` and `WK_SUPER` site from the
proposer's own `w.pos`, not through `FarmSlot`, so T2 labs, gantries, silos
and antinukes are unaffected by this. The lab was measured 42 elmos outside a
turret's reach.

## TUNE_SHIELD_COVER_FRAC = 0.5, TUNE_SHIELD_URGENCY = 1.0 (2026-09-06)

Both are the plasma twins of the AA pair, and they carry AA's values because
they are the same two terms in the same formula, not because 0.5 and 1.0 were
chosen for shields. Neither is a new policy: what they REPLACE was
`* rate * 4.f` -- an insurance rate on min(their arty, our base) with an
undocumented literal x4 bolted on, which is byte for byte the form AA was
rewritten away from for failing in exactly this way.

Measured before the change, one 38-minute game in which the enemy fielded a
4,600 metal `corint`: the shield want reached a nonzero gain 11 times, priced
at v ~0.9-1.3 against radar's 2.88-8.54, and lost all 11. The sense half picks
by argmax (`protect_want.as`), not by the category roulette, so it never even
drew. Shields built: zero. `armgate` has never been built in any recorded game.

COVER_FRAC is the term that makes the want self-limiting -- each dome raises
shield cover, which lowers both the arrival rate and the next dome's share --
so it answers his older complaint ("too many shields while theres still no
threat very close") with arithmetic instead of a cap. URGENCY is the honest
home for what the x4 was pretending to be.

NOT YET MEASURED. These land together with the LrpcStake latch, without which
the want was gated off almost all the time regardless of price, so no A/B of
the price alone is possible on the old build. First A/B still owed.

## TUNE_SHIELD_INCOME -- DELETED (2026-09-06)

`Policy::ShieldIncome()` was defined, published as a modoption, listed in
dashboard coverage, and **called by nothing**. The 50 metal/s bar it declared
had never once applied. Deleted rather than wired: the shield want now prices
against measured bombardment and remembered LRPC stake, which is a better
answer than an income gate to the same question.

## `apex_raid_sticky` (default 1.4) — MEASURED NULL, and why

How much a raid party flatters its CURRENT target's distance when re-picking
(`sqDist /= sticky^2`), so it stays committed unless something is genuinely
closer. Added originally as `RAID_TARGET_STICKY` after apexearth's "it can't
make up its mind and just runs in circles".

**It never once applied.** `RaidTask::FindTarget` calls `SetTarget(nullptr)` at
its top, and the test 82 lines later read `enemy == GetTarget()` — null by then,
and `enemy` is never null, so the branch was unreachable. Fixed 2026-09-06 to
capture `prevTarget` before the clear, the way `AttackTask` already did.

**Sweeping it after the fix changed nothing measurable.** 6 seeds per arm,
Frozen Ford 1v1 vs BARb:stable:hard, 25 min:

| sticky | raid long moves | return rate | metal built | share | K/D |
|---|---|---|---|---|---|
| 1.0 | 1312 | 63.3% | 17,743 | 0.531 | 0.39 |
| 2.0 | 1066 | 59.8% | 16,001 | 0.514 | 0.65 |
| 4.0 | 1135 | 64.1% | 14,322 | 0.465 | 0.22 |
| 8.0 | 1214 | 55.4% | 16,340 | 0.504 | 0.62 |

builtSD ~3,200 and shareSD 0.03–0.07, so every difference is inside one
standard deviation. At 8.0 the incumbent's SQUARED distance is divided by 64 —
if the term bound at all, raiders would be pinned to their first target.

**The S7 counter says why, and it is the real finding:**

    apex: raidsticky hadPrev=40 noPrev=461 applied=29

Over a whole 25-minute game `FindTarget` ran 501 times and **461 of them (92%)
had NO previous target at all**. The branch applied 29 times. There is nothing
to be sticky about, because a raid party does not HOLD a target between passes
— so no value of this tunable can matter.

Leave it at 1.4 or set it to 1.0; behaviourally it is the same. The question
worth answering is why a raid task has no target 92% of the time, since a
raider without a target falls through to `RoamPos` — the ±`apex_roam_r` scatter
around the front, or a uniform pick over the whole map when no front is
published, whose mean is the map centre.

## `apex_unit_cover` (default 1) — his escort-loop hypothesis, MEASURED NEGATIVE

apexearth 2026-09-07: *"I wonder if we need the turret because the ground is
unsafe, but then because a con comes over with an escort, the escort adds safety
and then defense no longer perceived as necessary?"*

`CoverWith` adds `Military::UnitCoverAt` to the same total as turrets, so the
loop is available in the code. This weight removes the mobile half. 6 seeds per
arm, Comet Catcher 1v1 vs BARb:stable:hard, 25 min:

| apex_unit_cover | defence wins | died pre-frame | lost | defHave | defPeak | built | share | K/D |
|---|---|---|---|---|---|---|---|---|
| 1 (his ruling) | 63 | 34 | **54%** | 414 | 517 | 22,975 | 0.437 | 0.15 |
| 0 | 58 | 31 | **53%** | 708 | 768 | 11,929 | 0.400 | 0.24 |

**The abort rate does not move: 54% -> 53%.** Removing every scrap of mobile
cover from the pricing changes nothing about how often a defence build dies
before it is framed. Whatever aborts these tasks, it is not an escort arriving
and closing the shortfall.

What the arm DOES show is that mobile cover really is suppressing defence
demand -- `defHave` 414 -> 708 and `defPeak` 517 -> 768 with it off, ~70% more
defence standing. So the mechanism he described exists; it is simply not the
abort cause. Economy fell hard in the same arm (22,975 -> 11,929 built) but
builtSD is 9,731-13,409 and defPeak per game ranges 0-2,080, so at n=6 that
half is not resolvable.

**Leave it at 1** -- his ruling that a unit protecting a building counts as
cover stands, and the arm that contradicts it bought no fewer aborts.

## `apex_inbase_path` (default 0) — the anomaly was real, the fix bought nothing

A builder skips pathfinding when it and its site are both inside
`baseDefRange` (`terrainDiagonal * 0.3`, measured 1,120 elmos). `apex: pathskip`
showed that **69% of the time it fired, the builder was NOT within build range**
— `inRange=29 farInBase=66`, worst 1,952 elmos against a 112 build range. Those
builders are handed no path and no move at all, which looked like a complete
explanation for the stuck-builder population (`progress=0.00`, `toSite`
500-1,175, and zero move failures because no move was ever ordered).

6 seeds per arm, Comet Catcher 1v1 vs BARb:stable:hard, 25 min:

| apex_inbase_path | farInBase/game | stuck/game | task deaths | defHave | mex held | built | share | K/D |
|---|---|---|---|---|---|---|---|---|
| 0 (shortcut) | 119.3 | 21.0 | 54.2 | 831 | 30.5 | 18,503 | 0.516 | 0.39 |
| 1 (always path) | **0.0** | **19.7** | 50.3 | 402 | 22.3 | 17,494 | 0.463 | 0.53 |

**The mechanism was eliminated outright and the stuck builders stayed.** 21.0 ->
19.7 is nothing next to 119 -> 0. So the pathless builders were not the parked
ones, and the theory was wrong. Mexes held fell 30.5 -> 22.3 and defHave 831 ->
402, with builtSD 10,257 and two collapsed games (3,320 and 6,860 built), so
running A* on every in-base hop looks actively worse rather than neutral.

Defaulted OFF. The `apex: pathskip` census stays: the anomaly is real and worth
knowing about, it is simply not what parks builders.

## `apex_def_eco_s` = 120, `apex_bp_headroom` = 1.0 — MEASURED, both raised, both worse (2026-09-08)

BARb outspends us badly in two categories, measured over 16 games of
`reverted-long`, per game:

| | us | BARb |
|---|---|---|
| static defence | 1,885 | **4,922** (2.6x) |
| build power | 2,831 | **3,718** (1.3x) |
| bank sitting >90% full | 12% of samples | 3% |

apexearth read the same numbers and called both: "the build power is a genuine
issue... it means they can build more army later and we fail to spend perhaps."
The bank figure supports the mechanism -- our metal pools because the lathes
cannot absorb it.

Both were raised to the measured gap (`apex_def_eco_s` 120 -> 300,
`apex_bp_headroom` 1.0 -> 1.4), separately and together, against BARb:stable:hard:

| arm | default | +BP | +defence | +both |
|---|---|---|---|---|
| 1v1 big maps | 0% | 14% | 12% | 0% |
| 2v2 | 30% | 12% | **0%** | -- |
| **1v1 small maps** | **64%** | -- | -- | **25%** |

Neither rescues an arm we lose; defence makes 2v2 strictly worse; and together
they cut the arm we WIN from 64% to 25% over 12 decided games, the largest
sample in the sweep.

**The gap is not a deficiency.** BARb spends that way because it is BARb's
strategy; the metal comes out of the army that is actually winning our games.
Do not re-open this by pointing at the composition table -- a category where we
spend less than the opponent is not evidence that we should spend more.

Left at the defaults. The team-game and big-map failures are real (0% at 4v4 and
8v8, before AND after the fight revert -- see docs/30) but this is not their
cause.

### `TUNE_OBSOLETE_RATIO`

**Team-wide refusal of the basic converter, measured 2026-09-08 and reverted
the same hour.** apexearth's ruling ("stop making T1 converters once they've
become obsolete") was built as: no hand makes the basic once ANY hand we own
can make the denser one. Supreme Isthmus 1v1 +100%, 33 min, 4 games
(`defhold-h100-t`, which also carried the defence hold): basic converters
finished 4 / 0 / 19 / 0 per game against 163 / 63 / 142 / 282 in the arm
before (`mexcap-h100-t`); advanced ones did NOT take their place (0 / 0 / 11 /
0 against 0 / 19 / 23 / 22); metal produced 296k against 704k; 2 of 4 games
wiped out against 0. The 700 basics a game were carrying the conversion, and
the T2 hands did not replace them. The per-hand law stands until the advanced
converter is bought where the basic used to be; his ruling needs that first.

2026-09-12, second ruling ("even at 1000 metal per second we're still making
basic converters... too fragile and take up far too much space"; 163 basics in
minutes 24-28 beside 11 fusions): `DenserHandsCover` -- a hand is refused the
basic once the hands that can make the denser one could build the whole
convertible surplus's worth of it inside the fill window. Comet Catcher 1v1,
34 min: 5 basics finished against ~300 in his game, conversion capacity 2,680 E
over a 478 E surplus, obsolete=176 of 255 asks. One T2 con beside three
fusions still fails the test, which is the 2026-09-08 case above.

### `NS_FLOORBID` (the gated factory floor -- measured and dropped)

The factory nano floor (`NS_FLOOR`, f06581c4) was gated 2026-09-12 to bid only
`min(FreeMetalFlow + OverflowM, one turret's drain)` and hoist only at the full
drain. Greenest Fields 2v2 +100%, 4 matched seeds, speed 6: nanos finished by
minute 16 fell 8/12/10/15 -> 8/7/5/4 for no change in metal waste (0.0-0.2%
both arms) and one treated elimination. The un-gated floor is what he asked
for ("high priority") and it wastes nothing; the gate is gone.

