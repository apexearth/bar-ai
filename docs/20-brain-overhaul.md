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
driven-line sweep, PendAdd ledger, GiveOrder-lag discipline) is KEPT as the
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
- **Values from state, not gates**: the Role objective (OPENING→GROW→T2LAB→
  MOHO→FUSION→AIRSCALE), the BP controller, Persona, and stance all express
  as VALUE multipliers (Persona's proven pattern). "No army for the role" =
  army Wants valued 0, not thirteen early returns.
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

## 5. KNOWLEDGE THAT MUST NOT BE LOST (measured, 2026-08-22 unless noted)

- **GiveOrder lag**: orders apply when the net message lands; ~45 sim-s at
  max headless speed. Count SENT, never trust reads (CLAUDE.md; the
  recruit-slip channel was this).
- **Recruit-slip**: engine response re-enqueues land on driven lines inside
  the lag window; the driven-line abort in SweepDeadRecruits is the fix.
- **Requests**: DEFENCE is Governed+Positional (never capped/joined);
  JOIN_MIN_COST bounds JOINING only — unmanned orphans must be adoptable at
  any cost or cheap towers block their ground forever (measured 24 created/
  3 built).
- **BP controller lessons**: don't count the commander (its 23 m/s lathe >
  opening income; froze con growth); BP must never outrank the ENERGY ladder
  pre-T2 (7 nanos, no tech); pre-T2 cons are income producers — bound them
  by DEMAND (queued tasks per con) + deficit, never by income curve alone
  (23 cons) and never by a flat cap (his explicit veto).
- **Role economics**: mohos before fusion (payback ~1m vs ~3m); T2 bar 600
  measured right, 450 measured worse (thin grid E-stalls mohos), 1200 cost
  9 minutes; fusion-2 is the boundary for air cons + T1 rebuild + T2-lab
  eat; reclaim bursts need storage headroom; gifting off at handicap ≥ +50;
  the anchor = back-most by TV_DIST (enemyPos reads ZeroVector pre-contact —
  substitute map center), latched at frame ~0, seeded into election slot 0
  unconditionally (qualifying let a faster teammate steal the designation).
- **Eco air plant**: ChooseFactory's switch clock is 550-900s — anything
  time-sensitive needs a ladder-side (now: Want-side) path.
- **Chain builds**: measured net-negative as implemented (ring-picked sites
  + holds beat think-gap savings; 46.1k control vs 32-40k). Binding
  CmdBuildQueuedAt + time-bounded hold kept for a placement-aware retry.
- **Squad coordination + commander no-chase + grid findings** (Part B of the
  approved plan, untouched by this overhaul): SnapToBaseGrid gridCell=8 no
  parity, unsnapped anchor, first-fit 1600-elmo search, BAND_BACK[NANO]=216,
  isFixed jitter — see the plan file and CHANGES.
- **Noise floor**: seed-47 tech read 6.8/7.0/8.4/never/14.0 on
  near-identical builds. Judge on ≥6-game tournaments (6 workers, 15m cap),
  never single runs.
- **Deploy discipline**: deploy exits nonzero on refusal but a pipe eats the
  code; check `deploy-exit` explicitly and grep a content marker in the
  live tree. Kill only spring-headless — windowed spring is apexearth's.

## 6. Sequence

1. apexearth reviews THIS document (the design review he asked for).
2. Kill: remove §1 wholesale; wire the ladder to holds→Decide→idle; stub
   facqueue to execute-only.
3. Validate the silence (§4.2) and the grep census (§4.1).
4. Rebuild Wants in dependency order: energy → mex/moho → plants(+factory
   choice) → cons/production → nanos/BP → fusion ladder → defence → the
   role's full arc — one Want per cycle, tournament-audited.
5. Then the grid work (Part B) on the clean base.
