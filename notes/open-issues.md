# Open issues — living list

Started 2026-08-03. Everything here is either unfixed, unverified, or a lead
worth keeping. Move an item to `CHANGES.md` once it is measured; delete it once
it is dead. If you fix something, say what measurement showed it.

Ordered by how much it is currently costing us.

---

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
