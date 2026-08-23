# The Brain overhaul — kill all leaf build logic, rebuild through Wants

apexearth, 2026-08-22, after days of leaf-gate whack-a-mole (pawns → vaders →
bulls → amphibs → 10 cons, 3-of-6 tournament games wedging regardless of the
last fix): "all the building, all the factory production, everything needs to
be coming from the brain. There can be no old leaf logic left on... Kill the
entirety of our logic so we know definitively that we have no random leaf
logic sitting somewhere in the corner of our code. Then rebuild."

**Scope boundary (his):** every BUILDING decision and every FACTORY PRODUCTION
decision goes through the Brain's Want arbiter. Unit-level micro — fight
details, dodging, kiting, an individual unit's reclaim-what's-next — stays as
per-unit "thoughts."

Checkpoint: tag `pre-overhaul` (1fbc962). Everything below is recoverable
from that tag.

---

## 1. REMOVE — the spender census

Nothing on this list survives as an executor. Some return as Want proposers
(§3); none may Enqueue/Take/return a build task on its own.

### Builder ladder (manager/builder/maketask.as — the ordered rule list)
Every rule between the safety holds and the end that creates or adopts work:
CommanderTask's build branches, CommanderMexGuard (all three passes),
PassingMex, AdvancedPlantAtRear, GantryAtRear, MexUpLane, WantedAirPlant
(incl. today's eco air-plant branch), BigBuildAssist, MexOffer, OpeningEnergy,
FrontDefenceOffer, ChainBuildRule, the EcoNano pre-assist slot,
Assist::AssistFactory/Work/Fallback (parking IS a spend of con time), the
OptionalWork ladder (rules_optional.as: EcoNano, converters, fusion, pulsar,
radar/jammer...), Brain::Decide's current *partial* role, and the terminal
fall-through to `aiBuilderMgr.DefaultMakeTask` — the ENGINE's native economy
is leaf logic too: a con the Brain has no task for must IDLE VISIBLY, not
inherit CircuitAI's own spender.

### Crews (manager/builder/crewdedicated.as, crew.as)
EnergyCrewTask / MetalCrewTask ladders — become Want biases, not ladders.

### Dedicated spend rules (manager/builder/*.as)
HomeEnergy/EcoFusion/EnergyConverter/EcoNano executors, statics.as's 21
placement rules, mexguard.as tower/geo/fusion-pick branches, digin/fortify,
front defence, obsolete.as's ObsoleteSweep + today's EcoRoleEatT1Labs/
EatT2Lab/ConsPayForLab (reclaim of OWN BUILDINGS is a build choice → Brain;
a rez-bot eating a wreck in front of it is unit-thought → stays).

### Factory production (manager/brain/facqueue.as + factory/*)
The entire quota machinery: floors (cons, scouts, rez, T1/T2 cores, fighters,
bombers, spam stream, air cons), TierShare, CounterShares/mix, DefQuotaMod,
EcoLeadLine, rules_recruit.as, armypush. Factory CHOICE too: choose.as's
AiGetFactoryToBuild branch forest, switch.as timers. The facqueue's
MECHANISM (line adoption, Wait-hold, recruit abort incl. today's
driven-line sweep, PendAdd sent-ledger) is KEPT as the
production EXECUTOR — it just takes orders from the arbiter instead of
computing its own.

### Role leaf gates (today's work)
Role:: policy methods and the objective enum survive as INPUTS to Want
values; the ~15 remaining scattered IsEcoLead reads and every `apex_role_*`
leaf gate are deleted with their host rules.

### Engine-side leaf logic to sever
- `aiBuilderMgr.DefaultMakeTask` for build choices (keep for pure movement/
  repair fallbacks only if provably non-spending; else stub).
- CircuitAI response.json recruit re-enqueues (the slip channel) — the
  driven-line abort already kills them; verify no un-driven line remains.
- build_chain.json hubs (engine-side auto-defence/jammers) — off for apex.

## 2. KEEP — senses, execution plumbing, unit thoughts

- **Senses**: frontline/influence, enemy census, stance, telemetry gadgets,
  Perf, the election + blackboard (TV_*), EcoAnchor latch, OwnHandicap.
- **Execution plumbing** (below the arbiter, spends nothing on its own):
  Requests::Take dedup/orphan-adopt/join (the chokepoint), facqueue's line
  mechanics, placement/siting helpers (Base bands, NanoSiteAt, FindBuildSite
  wrappers, sitesafety vetoes), TaskB/enqueue bindings, storage-headroom
  math.
- **Unit thoughts**: dodge-fire, D-gun (point-blank), squad fight/kite/
  standoff, retreat/holds (safety, not spending), scout roam, rez-bot
  opportunism.
- **Military task layer**: army USE (attack/defend/coordination) is not in
  scope — only army PRODUCTION moves to the Brain.
- **Tools**: audit_role.py, audit.py, dashboard, harness discipline.

## 3. REBUILD — the shape

One arbiter, two markets, one budget:

- **Builder market**: every former rule returns as a `Want{kind, value,
  def, pos, cost}` PROPOSER (pure, no side effects — brain.as already
  defines this contract and Score/BudgetMult already exist). `Brain::Decide`
  becomes the ONLY function that turns a con's time into a task. Ladder =
  safety holds → Decide → idle.
- **Production market**: factory Wants (a con, a tier-core unit, a scout...)
  scored by the same budget + objective; the facqueue executes the top
  orders. Factory/plant CHOICE is itself a Want (a plant is a building).
- **Values from LIVE DYNAMICS, not gates or static bars**: each Want prices
  itself from current state — payback time computed from the def's real
  cost/yield against measured income, opportunity cost against the
  runner-up, demand from queued work, build power as a closed loop. The
  role, Persona, and stance express as value multipliers (Persona's proven
  pattern). "No army for the role" = army Wants valued 0, not thirteen
  early returns. Sequencing (energy vs mex vs tech vs reactor) EMERGES from
  the prices; nothing encodes an order.
- **One log line per decision**: `apex: decide <unit> -> <want> v=... over
  <runner-up> v=...` — the debuggability the leaf system never had.

## 4. VALIDATION OF THE KILL (before any rebuild)

1. **Grep census**: no `Enqueue(TaskB::`/`Requests::Take`/`DefaultMakeTask`
   call site outside the arbiter's executor files. CI-able as a check.py
   rule so leaf logic cannot regrow silently.
2. **The silence test**: a build with Wants disabled must produce a game
   where apex builds NOTHING after the pre-placed opening — commander and
   cons idle in place. Any structure appearing = a hidden spender; hunt it.
3. Then rebuild Want-by-Want, one per benchmark cycle, audit_role green
   gates at each step.

## 5. WHAT CARRIES FORWARD — and what deliberately does not

apexearth: weeks of leaf-fighting produced "very confusing side-effects.
Given the lack of control during our work I do not trust our assertions...
approach this with an open mind. Only bake in gameplay mechanics and logic
which is useful. Focus on dynamics, static #s are often not good."

So this section is split. Behavioral conclusions measured inside the old
chaos are DISCARDED as truths — the rebuild re-derives behavior from live
dynamics, and if the old numbers were right they will re-emerge.

### 5a. Verifiable facts (engine source / unit defs / our own tooling)

- Reclaimed metal goes to the bank and overflows past storage — any planned
  reclaim needs headroom (game mechanic).
- Only advanced constructors build T2+ structures; build options are
  per-unit-def; asking an incapable builder is a silent no-op (unit defs).
- `aiEnemyMgr.GetEnemyPos()` returns ZeroVector while no enemy group is
  known (EnemyManager.cpp) — never use it as a bearing pre-contact.
- ChooseFactory is consulted on a 550-900s engine switch clock — nothing
  time-sensitive may depend on it.
- The engine applies AI orders when the net message is consumed, not when
  sent — reads lag sends, scaled by sim speed (AICallback.cpp). Treat every
  read-back as stale; keep sent-ledgers in the executor plumbing.
- Grid findings for Part B (all from engine/our source, unchanged by this
  overhaul): Pos2BuildPos parity law, SnapToBaseGrid's 8-cell no-parity
  snap, unsnapped anchor, first-fit 1600-elmo search, isFixed jitter.
- Harness discipline (about our tools, not the game): identical seeds do
  not reproduce runs — judge on ≥6-game tournaments (6 workers, 15m cap);
  deploy exit codes get eaten by pipes — verify `deploy-exit` and a content
  marker in the live tree; kill only spring-headless, windowed spring is
  apexearth's.

### 5b. Design principles for the rebuild (his, standing)

- **Dynamics over static numbers.** A Want's value is computed from live
  state: payback time from the def's actual cost and yield against current
  income; build power as a closed loop on measured income; demand from
  queued work. Orderings (moho vs fusion, when to tech, when air cons)
  EMERGE from the value function — they are never hardcoded sequences.
  Static numbers are allowed only as physics read from defs, or as a
  last-resort tunable with a written derivation.
- **No caps, no clocks, no exclusivity** (long-standing): scale with the
  economy; a role changes how much, never whether.
- **Open mind on old conclusions.** Yesterday's bars, orderings and
  verdicts (T2 energy bars, mohos-first, chain-build harm, controller
  calibrations, gift economics) are HYPOTHESES the new value functions can
  confirm or refute — none are requirements.

### 5c. Suspected engine interactions to RE-VERIFY when relevant
(observed once, in the old chaos — check before relying on them)

- Response-table recruit re-enqueues appearing on driven factory lines.
- Cheap unmanned requests blocking their own ground in the Requests dedup.
- Team-value (TV_*) blackboard timing at game start.

## 6. Sequence

1. apexearth reviews THIS document (the design review he asked for).
2. Kill: remove §1 wholesale; wire the ladder to holds→Decide→idle; stub
   facqueue to execute-only.
3. Validate the silence (§4.2) and the grep census (§4.1).
4. Rebuild Wants in dependency order: energy → mex/moho → plants(+factory
   choice) → cons/production → nanos/BP → fusion ladder → defence → the
   role's full arc — one Want per cycle, tournament-audited.
5. Then the grid work (Part B) on the clean base.
