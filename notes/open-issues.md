# Open issues — living list

Started 2026-08-03. Everything here is either unfixed, unverified, or a lead
worth keeping. Move an item to `CHANGES.md` once it is measured; delete it once
it is dead. If you fix something, say what measurement showed it.

Ordered by how much it is currently costing us.

---

## 0. `a7f3399` reverted -- measured worse than the commit before it

Commit `a7f3399` (armfark/corfast back to builder, eco spend un-gated from
eco-lead, ContestDefence disabled, base tower chain trimmed, T1 fodder push
un-gated from `!gHaveT2`, `CON_FAR_FRAC` 0.72->0.95) went in without an
isolated measurement -- it was already staged when this session started.

8-game controls, Comet Catcher 4v4, +25% handicap, Cortex/Cortex, 25 min, vs
`BARb:stable:hard_aggressive` (both directions swapped):

| | before (`9a63122`) | after (`a7f3399`) |
|---|---|---|
| head to head (decided) | 0-5 | 0-7 |
| apex metal produced | 28,860 | 19,261 |
| apex wiped-out player-games | 17/32 | 21/32 |
| apex T2 spend | 9,445 | 3,674 |
| apex mex upgrades | 2 | 1 |

Both lose to `hard_aggressive` outright at this sample size -- see issue 1 below,
this is not new. But the bundle made it measurably worse on every axis, so it
was reverted whole (`d75d998`) rather than bisected further; no time was spent
finding which of the six changes was responsible, so any of them individually
may still be worth re-trying in isolation with its own measurement.

One candidate ruled out already: `CON_FAR_FRAC` reverted alone (0.95 -> 0.72,
rest of the bundle intact) did not fix the shutout against `BARb:stable:hard`
(still 0-7, same collapse starting minute 6), so the far-frac change specifically
is not the dominant cause of the loss -- it may still be worth keeping reverted
on its own merits, just not as an explanation for this result.

## 0.1 apex currently loses to STOCK BARb outright at this benchmark config

Not previously documented at this precision. 8-game controls at commit
`9a63122`, Comet Catcher 4v4, +25%, Cortex/Cortex, 25 min:

| opponent profile | decided h2h | apex win% (undecided=loss) |
|---|---|---|
| `BARb:stable:hard` | 0-6 (2 timelimit) | 0% |
| `BARb:stable:hard_aggressive` | 0-5 (3 timelimit) | 0% |

This contradicts the K/D 0.97-at-25min figure logged earlier in issue 1 below --
that number came from a different opponent/config combination that was not
re-verified here. `hard` and `hard_aggressive` are both real stock BARb
profiles (confirmed: `reference/barb-stable/game-side/config/{hard,hard_aggressive}`
both exist), not a config-fallback artifact.

**Next step, per the project's own doctrine**: stop reading telemetry blind and
get a `--watch` run in front of apexearth. Every diagnosis that has actually
landed on this AI came from him watching, not from aggregate stats.

**Resolved, partially** -- see `12f13f0` (commander back-wall hiding disabled).
A `--watch` run plus the infolog it produced found the mechanism: the
commander was spending its early build time on a false "under attack" signal
that reads true almost permanently on this map (see CHANGES.md, "Known not
done" -> commander retreat). After the fix: 8-game control vs
`hard_aggressive`, same config, went from 0-5 decided to 1-1, paired K/D
log-ratio t from -13..-17 to -0.87 (not significant). **Still not "reliable"**
-- the goal is not met, this is progress on issue 0.1's shutout, not a win.
Next candidate to chase: apex still produces ~40k metal to stable's ~64k
in the same 8-game run, so the economy gap (not just the commander's early
diversion) is still open.

**Tried and reverted (disabled, not deleted): heavy-AA escalation, `d3bb0e2`.**
apexearth watched a game and reported light AA (corrl, 80m, deterrence-only,
capped at 12) doing nothing against ~10 T2 gunships. Added a second tier
(cormadsam/armferret/legflak) gated on real enemy air investment and income.
Measured WORSE against the back-wall-fix baseline: head to head 1-1 -> 0-5,
apex metal 40,743 -> 27,382, static defence share 10.6% -> 11.5%, wiped-out
9/32 -> 13/32 -- a smaller version of the flak-tower mistake already on
record in this file. One trial-run game won outright on economy and K/D
(265,925 metal, K/D 1.13), so this is not obviously dead; a narrower version
(higher income floor, lower cap, or gated on SUSTAINED rather than one-shot
enemy air) may be worth a later isolated retry. `AA_HEAVY_ON = false`.

**Next candidate, found from the `nobackwall-confirm` infologs (not a watch --
apexearth went to bed, so this is stats-plus-mechanism per** [[mechanism-over-aggregates]]
**style, cross-checking a log line rather than trusting an aggregate alone):**
one player's `conbranch` instrumentation (a 30s heartbeat tied to that unit's
constructor decisions) stops dead at 13-19 minutes in most of the 8 games,
while the other three players' logs run to the full 25-minute cap. The
stopped player's own log shows why in `t000`: "commander retreating at 61%,
70%, 75%, 81% health" between 12.2 and 13.2 minutes, then nothing further from
that instance. In the two games where NO player's log stops early, both went
the full 25 minutes as competitive, undecided matches; in every game where one
(sometimes two) did stop early, apex lost decisively. This lines up with the
standing project finding [[commanders-decide-bar-games]]: commander survival
predicts the winner, and three prior attempts at commander retreat logic
(`commander.json` levers, `GetEnemyCostAt`, `GetBuilderThreatAt`) all failed to
fix it (see CHANGES.md "Known not done"). `COM_RETREAT_HEALTH` (0.85, health-
based) is the one thing in this file that reliably fires, and it still isn't
enough to keep a commander alive under sustained pressure once retreat itself
does not equal safety (no ally cover, no safe retreat lane, or simply
outranged while fleeing). Worth a dedicated session: instrument WHY a
retreating commander still dies (position at death vs. nearest ally, whether
allied fire support existed) rather than tuning the health bar again blind --
tuning that bar with a NUMBER has been tried and burned time before.

**Update, does NOT clearly replicate** -- added `comm threat=... hp=...`
logging (`56a4c66`) and re-ran 8 fresh games (`comm-death-investigate`) to test
the theory above with real HP data instead of inferring death from silence.
Result: in this batch's 3 decisive losses, ALL FOUR players' last log line
clusters tightly around the match's own end time (within ~1 minute of the
reported game length) and most read 77-100% HP at that last line -- not the
staggered "one player's log goes quiet 7-10 minutes before the others, at
declining health" pattern the `nobackwall-confirm` game showed. That pattern
looks more like a synchronized team-wide loss once already behind (consistent
with issue 0.1's economy gap) than an individual early commander death
triggering a cascade. **The log-silence method itself is the problem**: this
script has no `AiUnitDestroyed` hook (engine warns it is missing at every
match start; confirmed no working example anywhere in `reference/barb-stable/`
or `vendor/` either, so implementing one blind is a real crash risk given this
file's own history of unsafe-binding aborts -- see CHANGES.md). Absence of a
log line proves the unit stopped needing `AiMakeTask` calls, which is also
true of a commander settled into a long build with nothing to reevaluate.
**Do not treat this as a confirmed lead** -- it needs an actual death event to
investigate further, not more inference from a 30s heartbeat.

**Tried and reverted (discarded, never committed): eco-for-everyone, isolated
retry.** T2GATE data from `comm-death-investigate` showed followers crossing
`FOLLOWER_TECH_ENERGY` (600) only around minute 13 of 25 -- late, matching the
low cons-T2/mex-upgrade counts. Un-gated `EcoConverters`/`EcoNano`/`EcoFusion`
from `Factory::EcoLeadActive()` (every player builds some energy
infrastructure, eco lead at double cadence via `EcoPeriod()`) as an ISOLATED
retry of one piece of the `a7f3399` bundle, on top of the confirmed-good
back-wall fix. 4-game triage against the current baseline: energy wasted
24,829 vs baseline ~10,142 (2.4x), cons T2 1 vs ~3, mex upgrades 2 vs ~4, metal
produced 30,821 vs ~40,743 -- moved the WRONG way on every metric, not just
noisy. Matches a failure mode already on record in this file:
`FollowerEconomyReady`'s own comment cites an 8v8 where every follower teching
on a clock (not a mechanism this change resembles, but the same "spread
economy investment across more players" shape) cut army share to 19.3% against
stock's 31.7%. The bottleneck is real (followers ARE gated on energy pace) but
"more players build energy" is the wrong lever -- reverted without an 8-game
confirmation, since the 4-game signal was directionally consistent and
mechanistic, not just a coin-flip win/loss. Next angle, if pursued: raise the
energy the LEAD alone produces/converts (already fast at `EcoPeriod` full
speed) rather than recruiting followers into the same job.

## 1. The late game collapses, and it is a SEPARATE failure

Measured, 8-game pairs on Comet Catcher 4v4 +25%:

| | 10 min | 25 min | 40 min |
|---|---|---|---|
| apex K/D | 0.76 | 0.97 | **0.56** |
| stable K/D | 0.76 | 0.64 | 1.15 |

The opening is fine. `ENGAGE_MARGIN 1.80` genuinely fixes mid-game. Something
else breaks between 25 and 40 minutes and it is not a weaker version of the
same problem — the sign flips.

ARMY-only K/D at 40 min is **0.66 against stable's 1.40**, while kills by static
defence are within 5% of each other. The army is the whole gap.

**Not yet investigated**: what changes at ~25 min. Candidates: T3 arriving,
squads outgrowing the merge radius, enemy siege artillery, our own T2 mix.
Use `tools/kd_curve.py` on a 40-minute tournament and find the minute it turns.

## 2. Reclaim cannot see the bodies

apexearth: "theres 1000+ metal in front of us and we don't even care".

The rule exists (interrupt a build for a 400+ metal field within 1400 elmos,
`WRECK_RICH` in `builder.as`) and never fires. 97 probe samples over 16 min:
`ai.GetWreckValueAt` read 0 at BOTH 1400 and 4000 radius, and the established
`ai.GetBestWreckPos` also found nothing at 4000 with a 55-metal floor.

Two independent bindings agree. So either `callback->GetFeaturesIn` needs LOS,
or our constructors are never within 4000 elmos of a corpse.

**Next step**: run on a reclaim-heavy map (All That Glitters). Nonzero there =
the binding works and the Comet Catcher zeros mean constructors are simply far
from the fighting. Still zero = the callback is LOS-gated or broken.
**Do not tune the threshold before answering this.**

## 3. Factory tier weights are nearly inert

`FactoryManager.cpp`: `prob = RoleProbability(bd) * (probs[i] + reWeight)` with
`reWeight = 30` (stock). So a weight of 0.40 vs 0.22 is 30.40 vs 30.22 — a 0.6%
difference. **The doctrine reweight moved the numbers and not the behaviour.**

What DOES work: zero-to-nonzero, because `if (probs[i] > 0.f)` is a hard gate.
That is why enabling mobile AA mattered.

**The real lever is `response.json` role ratios.** Untouched. Note our `assault`
entry has `ratio: 5.0` against enemy `static` — likely why Tigers dominate,
since stock builds many towers.

## 4. Units we barely build that we probably should

- **`cortrem`** (Tremor, 1850m, range **1470**) — the ONLY thing we own that
  outranges enemy siege (`cortrem` 1470, `corvroc` 1310). Weight raised to
  0.04/0.08 but see issue 3: probably inert.
- **`corban`** (Banisher, 800 range) is role `skirmish`, so it joins normal
  squads and walks to 80% of its range with them. Probably belongs on the
  artillery path — but that pulls a 1000-metal unit out of assault squads, so
  it is a composition change and needs its own measurement.
- **`corsumo`** (Mammoth) is gated by `coralab`'s `income_tier: [40]` — below
  40 m/s it sits at 0.01 weight. Most of our players are below 40.

## 5. Verified-built but unverified-useful

- **Mobile AA** (`corcrash`, `corsent`, `armyork`, `armaak`, `armjeth`) was
  weight 0.00 = structurally unbuildable. Now enabled. Never confirmed that the
  `anti_air` response actually elects them.
- **`corpun`** (1245 range) enabled via `"on": true` and added as the last rung
  of the porc ladder, gated on 800 metal of enemy artillery. Its `sightdistance`
  is **455**, so it needs someone else's radar to shoot at range. Unverified.
- **Fighter massing** (`AA_MASS_RATIO` in `AntiAirTask`) — holds fighters until
  their cost matches enemy air. Never observed working.
- **Jammers on the line** — confirmed placed (`jamT` reaches 2+). Whether they
  actually stop sieges is unmeasured. We field 24 to stable's 48.

## 6. Reverted on noise, therefore UNTESTED not disproven

`Builder::NeedsAdvCon()` — advanced constructors scaling with income instead of
being capped at exactly one per player. Reverted after army share fell, but a
control run later showed army share swings 5+ points between identical runs.
`NeedsAdvCon()` and `gAdvConCount` are still in `builder.as`, unused. Either
re-test it properly or delete the dead code.

## 7. Faction parity gaps

- **Legion has no ~190-metal mid tower.** Its ladder is `leglht` (70) then
  `legmg` (420) — no equivalent of Beamer/Twin Guard, so the `PORC_MIN_BUDGET`
  floor buys it nothing.
- **Legion has no naval fusion or naval advanced converter** in the pinned tree
  (`leganavalfusion`/`leganavaleconv` are upstream-only). Its naval path runs
  through Cortex hulls: `legcs` -> `corasy` -> `coracsub` -> `coruwfus`.
- Armada/Legion doctrine weights were applied but are subject to issue 3.

## 8. Ideas not built

- **Rally-to-squad** (apexearth): let a unit be ASSIGNED to a distant squad and
  walk to it, instead of the hard 3000-elmo `CanAssignTo` cutoff. This is the
  generalisation of the join-radius fix that took median squad size 2 -> 5.
- **`attackMod` is one value read by SCOUT/RAID/ATTACK/BOMB/ARTY/AA.** Raising
  it for caution tripled losses because it made raids passive too. Splitting it
  would let attacks be cautious while raids stay willing to trade.
- **Counter-battery behaviour.** We have no answer to an artillery blob beyond
  target preference; artillery is the thing that beats a massed army without
  ever being engaged.

## 9. Method notes that keep mattering

- **This benchmark cannot resolve small changes.** Two identical-code control
  pairs moved further than any change did: army share 21.0% vs 15.7% (16 games
  each), T2 spend 36,812 vs 23,515 (32 games each). Head-to-head across seven
  tournaments: 9-6, 5-8, 6-7, 7-7, 13-16, 16-13, 11-19 — every CI includes 50%.
- **Composition metrics with ~1000 in-game samples ARE reliable** (squad size,
  engagement decisions, kill splits). Between-game aggregates are not.
- **Dead bindings are the recurring trap.** Confirmed dead: `GetBuilderThreatAt`
  (0 in 121 samples), `CThreatMap::GetThreatAt` at target positions (0 in 14/15),
  `Game_getTeamResource*` (-1 always), the published front outside BAR.sdd.
  Log a binding's raw value once before building logic on it.

---

## 10. Task displacement — investigated, guard added, NO measured gain

apexearth: "buildings getting started and then canceled... maybe you have some
logic that isn't checking if there's already a task and you are replacing tasks."

The mechanism is real: `AiMakeTask` is called by `IBuilderTask::Reevaluate` on
every task update while a builder is away from its build position, and the engine
swaps the unit's task whenever the returned task differs in BUILD TYPE. Every
optional rule (AA, Pulsar, converters, nanos, fusions, dig-ins) returned early
without checking whether the unit was already mid-build.

A guard now returns the held task when it survives the veto. Measured over 8
games at 25 min against the previous build:

| | no guard | guard |
|---|---|---|
| ARMY K/D | 1.06 | 1.04 |
| metal ratio | 1.16 | 1.09 |
| mex ratio | 1.08 | 1.03 |

**No gain; slightly down, within noise.** Kept because it stops a behaviour that
was directly observed, not because it measures better.

**Caveat that matters**: the "60 live MEX tasks, 60 unworked" measurement which
motivated this was taken WITH a rear-mex rule I had added, which fired every 2
seconds on a GLOBAL timer and enqueued a fresh mex task each time — displacing
whatever the constructor held. That rule probably manufactured the orphan pile.
It has been removed, along with its logging, so whether orphaned mex tasks still
occur is now UNKNOWN. Re-add the `live=/unworked=` counter before concluding
anything about task orphaning.

## 11. `FindOpenMexSpot` excludes ally zones — and that is CORRECT

Checked because it looked like the cause of "no open spot". `IsZoneAlly` is
`(allyCount > 0) && (ownCount == 0)` — a TEAMMATE's zone and not our own. It
prevents stealing a teammate's spots and does not exclude our own base. Not a
bug. Do not "fix" it.

The remaining candidate for `mex-none` is `IsAllyOpenMexSpot` — the spot is
already claimed by a live task. See issue 10.
