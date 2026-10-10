# A value net trained on our own decisions

His idea (2026-10-04): feed a network the game state at the moment a decision
is made, and train it on the outcomes that say whether we got better or worse.
The net then tells us what a decision is worth in that moment. His examples:
energy and metal fill, metal income against its maximum as inputs; income
growth, damage efficiency, mex count change, energy status and e-stall as
outputs.

Why decisions and not games: a net on the 42 ecoclimb tunables could not beat
"the knobs do nothing" on held-out rounds (`tools/surrogate.py`, held-out R^2
<= 0). The knob effect is below per-game noise (sd 0.14 vs NullAI). One game
holds ~850 builder decisions per AI, each with its own state and outcome.

His calls, 2026-10-04: **constructors first** (factory production later). The
net is a **modifier**, never the decider: the market still proposes concrete
options from the unit defs; the net says what to want more or less of (more
anti-nuke, fewer T1 labs, walk matters less now) by reweighting the draw. It
must **learn while games run** and show it live on the dashboard; all running
games feed one net (his "merge"). Enemy damage must not be blamed on a sound
decision: losses are split near/far from the chosen site and the state carries
the threat, so a predictable raid is in the baseline.

## The record

`manager/brain/market/nnlog.as`, riding `apex_decide_log` (on by default).
One `apex: nn` line per EXECUTED builder election (the `apex: exec` point in
`Decide`), so coverage is checked as nn/exec per team. An `apex: nn-schema v4`
line names the fields once per game (and `explore=1` on a discovery game);
parse by name, never by position. The 10-04 field list came from three
codebase sweeps (economy, enemy/risk, high-level decisions); the ones left out
were too costly per decision (`ReachSlack`, `CoverAt` alone) or need a
restructure (enemy economy estimate).

- state (`NnState`, 68): incomes, banks, pull, surplus AND the energy actually
  binned, economic power, slack, e-stall, feed, metal starved/wasting, hands
  vs feed, idle nanos, claimable spots, upgrade demand, backlog, tier; our and
  seen-enemy army (ghost-discounted and pessimistic), stance, trade, loss
  pressure, loss rates by killer class, OUR STRUCTURES DYING (`BleedM` -- the
  others count army), enemy air now/peak, incoming push, raid pressure, time
  since the last raid, intel freshness (is foeArmy=0 safe or blind), silos,
  team and map size; holdings off the commitment ledger (labs, nano BP --
  nanos are not IsBuilder, the census test is used -- converters, armed
  structures, anti-nukes, stockpilers); budget shares and targets. No map
  coordinates: they let a net memorise maps.
- options (`NnOpt`): the top 8 of `ranked` -- kind, def, MARKET value (net and
  discovery multipliers taken back out via `nm`), gain, costs, build time,
  walk, risk, seconds to the ETA target if built first (`EtaOfWant`, capped),
  the power it adds (`DPowerOf`), how many we own, tier, forward fraction,
  recent losses at the site, the persona multiplier, and **p**.
- `apex: nnfac` (production.as): every factory order with all candidates and
  their roulette odds.

- `apex: nnair` (`manager/air/nnair.as`, v2 2026-10-05): the AIR STRIKE --
  WAIT or GO -- for two groups on one head: `kind=0` the bombers held at home
  (not the atomic bomber), `kind=1` the gunships (flyers that hit ground, not
  a strike def). Every 15 s (staggered by team), plus when the old wing rules
  (massed / at its worth / deadline / home wave) fire (`legacy=1`) and when a
  gunship raid clears its cell (`why=arrive`). Every known economy cell of
  theirs (the 32 richest buildings, everything within `apex_air_cluster_r`)
  is priced: its metal plus its output (energy at the best converter's rate,
  metal, extraction, conversion) until a constructor walks out and rebuilds
  it, against a race over the cell -- group dps falls as the AA we know of
  (static/ground AA over the cell, fighters that reach it within our flight
  time) takes planes one by one -- plus the AA crossed on the way in (and out,
  for bombers); a scored run's survival floors the loss. Rule: GO when the
  best cell nets positive. Binding: bomber GO = `Release()` at the cell;
  gunship GO = every gunship raid goaled at the cell, home-pool gunships
  pulled onto one raid; gunship WAIT = their raids goaled on home ground.
  The best cell's net, per bomber type, also prices bomber production while
  the wing is short of the planes that cell takes (`NaTargetGain`).
  Fields: the `NN_STATE` values, then `air=` (`NNA_AIR`), `WAIT,w,p ; GO,w,p`,
  `chosen`. Scored by `NnAirScore` (NNA_* weights). `apex: nnair-stat` (60 s),
  `apex: nnair-go` (gunship goal moved). `tools/airaudit.py` reads the
  outcome side: planes built by minute, what our air killed, air losses.

- `apex: nnpost` (`manager/military/nnpost.as`, 2026-10-05): the ARMY'S
  POSTURE as a decision -- DEFEND (hold home, meet the push on our own ground),
  HOLD (hold at the lane), ATTACK (pools promote and march on their base),
  RAID (pools mass to the attack bar, then promote to a raid task). Every 30 s
  (staggered by team), and when the rule chain's verdict changes or a push
  starts closing on home. Default weights: 1 on the rule's verdict (turtle or
  stance hold = HOLD, a hit/contested/raided base = DEFEND, else ATTACK),
  0.01 on the rest. Outside discovery games with no net trust the rule's pick
  runs at p=1 and nothing changes; in a discovery game while the posture net has no trust p mixes
  `NN_HEAD_FLAT` (0.1) uniform in, and a pick that differs from the rule overrides
  `HoldReason`/`HoldHome`, the pool's promote type, and the lane anchor until
  the next decision (a deviation is not cut short by a rule flip; the rule
  chain flips every few seconds while a base is raided). Fields: the 75 `NN_STATE` values, then `post=` (our ground
  army metal, forward fraction, metal on attack/raid/defend, distance to their
  base; their biggest mobile group's metal, forward fraction, net influence and
  distance from home; incoming push; cover and threat at home; their base's
  structure metal and influence; separation; strength ratios; quota, held
  metal, turtle, hold reason), then `name,w,p` per option, `chosen`, `ov`.
  `NnPostScore` is the stub the trainer's NNP_* weights will fill.
  `apex: posture` (60 s): picks, rule verdicts and seconds under each
  posture actually in force, deviations, and the decision's cost in us.

- `apex: nncom` (`manager/brain/market/comdecide.as`, 2026-10-05): the
  COMMANDER'S answer to his situation -- WORK, FIGHT, TURRET, RETREAT. His
  ruling: "we can't die, that's paramount". Assessed once a second while a
  threat is in his horizon (5 s otherwise); recorded when the rule's pick
  changes, every 3 s under threat, every 30 s in peace. The threat is every
  enemy ground group that can reach him (distance past its range over its
  fastest member) before he reaches safety (the farm, or a nearer stand of our
  guns where he would win) or one light tower is built. The fight is read off
  catalog dps and health: they die one by one, their fire falls linearly, he
  takes half their dps times the kill time, his share by health against the
  guns and army beside him; his D-gun removes the kills its energy and reload
  allow at the odds a sideways-moving unit leaves the beam. FIGHT when that
  leaves him COM_RETREAT_HEALTH of his health, he is not already below it,
  and they arrive within a tower's build time (else WORK); TURRET when the
  towers he can finish before they arrive turn it; else RETREAT (assigned
  directly -- an idle commander is not re-elected; the engine's own retreat,
  armed when he is hurt, is left alone). T2 caution on far ground is RETREAT;
  losing health with no enemy seen is RETREAT. His mex/reclaim claims
  (`ComRaidF`) run the same fight against what can reach the spot before he
  is back under our guns. Default weights: 1 on the
  rule's pick, 0.01 on the rest; NO discovery game flattens it -- the draw
  runs only once `NnComScore` returns trust (a stub returning 0 until the
  trainer writes NNC_*). Fields: the 75 `NN_STATE` values, then `com=`
  (`NNC_COM`), then `name,w,p` per option and `chosen`. `apex: comstat` (60 s),
  `com-withdraw`, `com-turret`/`com-turret-end`, `com-retreat`, `com-drop`,
  `com-death`; the C++ D-gun logs every shot as `apex: dgun-fire`.

- `apex: nnhunt` (`manager/military/nnhunt.as`, 2026-10-08): his "kill their
  army, and eat it" -- NO or HUNT, every 30 s (staggered by team, none while a
  hunt runs) when we can see a ground army of theirs and have attack squads.
  The target is their biggest seen group by mobile armed ground metal. HUNT
  takes this AI's AttackTask focus (the team push's machinery; `TeamPush`
  yields it): squads gather short of the group, go once gathered power beats
  its influence (`apex: hunt go`), and the focus follows the group every 4 s
  until it is lost for 3 looks or 180 s pass (`apex: hunt start` / `hunt end
  why=gone|time`). Rule NO; an untrusted head mixes `NnHeadFlat` in discovery
  games, like every other head. None while a strike holds the focus. Label: every
  decision, either pick, is watched 180 s -- their metal we killed within
  1200 of the tracked group, ours lost there, and half of every death's metal
  credited (+) or debited (-) by who holds that ground (net influence at the
  death); `apex: nnhunt-done ... done=(kill+wreck-lost)/(kill+lost+grpM)` is
  the head's `done`. Prefix NNH. `apex: hunt-stat` (60 s).
- `scap` (`econet.as`) and `ecap` (`escnet.as`), continuous heads (below):
  count caps in the priors made learnable. `scap` multiplies the late ground
  scout cap (`ScoutFleetCap`, `:scoutcap` and `:esc-capped` in prodrank; 1x =
  the flat base, max(20, maxunits/50)) by v in 0.25-8 -- the top is his
  "almost unreasonably high": 8x is 160+ scouts an AI, the frame-budget risk
  that once dropped x4; prefix NNS. `ecap` multiplies the escorts-at-once cap
  (`EscortCap` = TUNE_ESCORT_CAP x the escort head's v) by v in 0.25-10,
  reading the escort head's fields; prefix NNY. Counts take the ceiling. The
  flat base itself stays a ceiling on rez bots and on `EscortShortfall`: it
  came from 564 rez bots taking his 4v4 to 0.65x sim speed (c4a489ac), a
  frame-budget contract, not a prior.
- `apex: nnstrike` (`manager/military/nnstrike.as`, 2026-10-08): TIMING
  WINDOWS, his priority #8 -- NO (the rule, today's play) or STRIKE, every 30 s
  (staggered by team) when we have attack squads, none while a hunt or a strike
  holds the focus. `apex: window` (every 12 s per AI, staggered) is the census
  the head reads, all from what a player sees: their seen armed ground metal,
  its metal-weighted distance from their start box over the base-to-base
  distance (`foeAwayF`) and the part within a quarter of it (`foeHomeM`); their
  biggest group's metal, distance from their base and from ours, forward
  fraction; our kills, our losses, our army's losses and their army seen dying
  (any killer) over the last 90 s (10 s bins fed by both death hooks);
  ln(our AIs' army / their seen army) and / their believed army (foemem), the
  believed ratio's 60 s trend and its gap below its 5-minute peak; the top tier
  of their seen army and seconds since it rose. STRIKE takes this AI's
  AttackTask focus exactly as a hunt does (`TeamPush` yields it and posts 0
  gathered power): the target is their richest economy cell (enemy group by
  economy metal, structure centroid if none known), squads gather short of it
  and go once gathered power beats its influence (`apex: strike go`); when a
  cell is gone the focus moves to the nearest other cell, until 180 s pass,
  no cell is known or our attack power is 0 (`apex: strike start` / `strike
  end why=time|gone|army kill= lost=`). Shared labels only (economy, losses,
  edges vs the enemy, endV, endFast). Prefix NNB. `apex: strike-stat` (60 s).
- `mass` / `odds` (`manager/military/nnmassodds.as`, 2026-10-08; continuous
  2026-10-09): two docs/24 section 7 priors made decisions, every 60 s per
  team (staggered), v in 0.25-6, rule 1x (today's numbers). MASS
  multiplies the bar a massing pool must reach before it leaves
  (`quota.attack` after `UpdateMassing`'s hold logic, before the own-army
  ceiling; also the turtle resume/lift writes); with the DLL also the
  biggest-enemy-group term of the C++ promotion bar (`UpdateDefenceTasks`).
  ODDS multiplies the enemy influence `CAttackTask::FindTarget` refuses
  against (the strong test and the remembered-strong-group test): 0.5 takes
  fights at half today's odds, 2 wants twice them. Both ride the team board
  (slots 1400+team odds, 1500+team mass); the DLL reads them every 5 s, logs
  `apex: mil-board` on a change and stamps 1600+team, and the odds head
  records nothing until that stamp is fresh (`noDll` in `apex:
  massodds-stat`, with `massOv`/`oddsOv`, the decisions played off 1x), so an
  old DLL never yields a row whose pick did nothing.
  No head-specific label: the shared targets (lnD, lost/kill, army edge,
  endFast) judge both. Prefixes NNM, NNO.
- `defamt` / `apex: nndefsite` (`protect_nn.as`, 2026-10-08): his
  "a NN governing defense count and placement". AMOUNT (prefix NND, a
  continuous head): every 60 s, v in 0.25-8 multiplies `DefenceTarget` (rule
  1x), held to the next decision; fields are leak metal (5 min, all / eco-nano-lab / inside the
  hull), enemy raid mass and army, army home/away, uncovered post share,
  cover/threat/hazard at home, wall fill and closure, assets. No `done` of its
  own: the team labels (lostMobile, edges, endV). SITE (prefix NNU): in
  `ExecuteWant`'s WK_PROTECT branch, for a ground gun, seven fixed slots --
  RULE (the want's site), the def's best WALL, MEXG and FRONT slot from its
  `DefSiteFill` cache, FLANK (the slot on the recent leak bearing), FORT (the
  slot nearest the nano mass), LEAK (the heaviest recent leak pushed to just
  past the rim) -- each with 13 fields (present, auction prevention, stake,
  leak near, bearing vs enemy, cover, threat, hazard, forward, rim distance,
  nano BP, guns near, distance to the rule site); an absent slot, one within
  200 of another, an interior site the executor refuses, or a tower grave is
  masked (w=0, p=0). A decision holds 90 s for re-elections of the same def
  and site. Label: `apex: nndefsite-done` 300 s later, done = (enemy ground
  metal killed within reach+200 - ours lost there to ground units) / (kill +
  lost + gun metal); decisions.py also gives lostNear at the site. Both heads
  rule-only at p=1 until trusted; a discovery game mixes NN_HEAD_FLAT.
  `apex: leak` (every building of ours an enemy ground unit kills: class,
  depth in the hull, zone in/rim/out, dir front/flank/rear, nearest gun) and
  `apex: leak-stat` (60 s) are the census; `tools/leaks.py` the same reading
  from gadget lines for any batch.
- `apex: nndeftype` (`protect_nntype.as`, 2026-10-09): his "we suck super
  hard at making T2 defenses" -- WHICH gun a ground-defence want builds,
  decided in `ExecuteWant`'s WK_PROTECT branch before the site head. Options
  are the guns the asking hand can build that its last ground proposal
  priced (the auction's gates -- obsolete, T1-after-T2 -- already applied),
  in six fixed slots: RULE (the want's gun), T1Q / T1K (T1 quickest to stand
  with the hand and nanos at its site / most kill), T2Q / T2K / T2R (T2+
  quickest / most kill / longest reach); absent and duplicate slots masked.
  A non-RULE pick builds that def at the site the auction priced it at; the
  site head then runs on it. Flak and torpedo guns are other halves and not
  here. 16 fields (rule gun, live enemy ground and T2+ metal, nearest T2 ETA
  to home, T2 mean distance and closing speed -- 10 s sampler --, our T1/T2
  gun metal, hand BP, ring BP, leaks) and 21 per slot (cost, energy-equal
  cost, tier, reach, kill, dps, aoe, hp, seconds to stand, auction value,
  threat, hazard, cover, forward, rim distance, enemy metal and T2 metal that
  reaches the site before it stands, nearest ETA, owned, distance from the
  rule site). Held 90 s per rule def + site. A want whose def/site is not in
  its asker's last proposal (the commander's first gun) is not a decision
  (`typeMiss`). Label: `apex: nndeftype-done`, the site watcher's trade at
  the gun's final site. Prefix NNN. Counters on `apex: leak-stat`: typeDec,
  typeOv, typeT2 (picks that were T2+), typeRuleT2, typeMiss, typeMemo, typeUs.
- `apex: nnopen` (`opennet.as`, 2026-10-09): the OPENING ORDER, his "learned,
  not ruled" (docs/24 section 4) -- LAB (plant first), MEX1 / MEX2 / MEX3
  (that many extractors, then the plant), MEX2E (two extractors, a generator,
  the plant). Once per AI, at the commander's first election with a plant on
  offer. Rule: LAB when the bank plus his own income (def make x (1 +
  ourBonus)) over the lab's build time (his BP) and its first constructor's
  (the lab's BP) pays for lab + constructor in metal AND energy (`carryM`,
  `carryE` >= 1), else MEX2. With 1000/1000 banks energy binds: Cortex flips
  at +0.49, Armada +0.30, Legion +0.43. The plan's step kind is moved to the
  front of the commander's `ranked` (every want of that kind, value order)
  below the panics and cover hoists, skipping the draw (`why=open`); a mex or
  energy step with nothing on offer is skipped, the plant step waits; the
  commander's exec of the step's kind advances it, any plant ordered (or a
  plant standing / in flight) ends it. Explorer games draw it uniformly while
  untrusted, half net / half uniform once trusted. 17 fields (commander make,
  banks, lab and constructor cost and build seconds, carry ratios, mex offers,
  walk to the best mex and to the plant, its gain, energy offers). Label: the
  shared targets, except that a decision before minute 1 has no income base in
  `labels()`, so dMInc/dEInc/dEco start from the commander's own income (the
  row's comM/comE) and `done` = ln(metal made in the next 5 min / comM x 300).
  Prefix NNOP (every single letter was taken). `apex: open-plan`,
  `apex: open-step why=exec|absent`, `apex: open-done why=ordered|plant`.
- `aplant` (`plannet.as`, 2026-10-07): while the plan is AIR, how many
  basic air plants -- a continuous head over the count itself, 1-8 (the rule
  1), every 30 s; the game owes ceil(v) plants. Short of the count,
  `AirPlantOwed` raises the plant at once (a duel still waits for the income
  bars) and waives the nanos-first copy rule for it (his call: more air
  plants are fine under AIR, the count the net's). Prefix NNL.
- `apex: nnplan` (`manager/brain/market/plannet.as`, 2026-10-07): the TEAM's
  way to win -- NORMAL, T3 (gantry gain, count and saving horizon x4; once a
  gantry stands, lower ground labs keep only the fodder share), MISSILE (silos,
  tactical and EMP launchers x4; the turret line becomes a nuke target with a
  volley sized by its guns), ARTY (LRPCs incl. mega and Starfall x4), MASS (no
  production change), AIR (air plant want and air eagerness x4; the T1 air-con
  floor stands aside and armed fliers weigh x4 in the plant's draw), RUSH (the
  army we hold x2, army row x4), GREED / GREED_DEEP (the army we hold x0.5 /
  x0.25 -- below their army, his 2026-10-07 -- economy row x4; only while the
  stance reads PASSIVE, so blind or attacked the full army returns), TURTLE
  (defence and anti-air rows x4). The last five (v4, 2026-10-07) are his
  strategic spontaneity -- drawn by the net, which sees the stance signals
  (stance, raid pressure, fresh enemy army), instead of a random personality
  roll it cannot see. Forced one 2v2 vs BARb each (Frozen Ford, min 12-16):
  GREED spent 28.4k at 16% ground army, NORMAL 17.1k at 30%, RUSH 55-64%
  ground; AIR still 1-3% air (one slow plant, copies refused). One plan per ally
  team on a board the allied AIs of one process share (`ai.SetTeamBoard`),
  held 8 min; whoever decides logs the row; a discovery explorer leads (see
  Discovery games). Under every plan but NORMAL, the GREEDs and TURTLE the
  TEAM PUSH runs: the owner posts the turret line our army dies to
  (it holds until broken), each AI posts the attack power it has gathered
  short of it, and when the team beats the strongest group there every squad
  goes (C++ `AttackTask` focus: the breach wins the target choice, refused
  only against the team's power); bombers may strike it (`apex: air-breach`).
  Allies also co-build: while we own no gantry, an ally's within walking reach
  stands for ours and the metal-first assist guards it (`TaskB::GuardAlly`,
  `apex: ally-gantry`). `apex_plan_force` forces one plan (A/B). Instruments:
  `tools/plancheck.py`, `apex: push` / `push go`.

## Continuous heads (2026-10-09)

His ruling: a quantity is never chopped into steps, and an integer count is a
real value the game takes the ceiling of. Thirteen heads are one mechanism,
`NnValDecide` (nnlog.as), each a value v on a range, the rule's value 1x
(aplant: the count itself, rule 1). Range tops are "almost unreasonably high"
so the net has room; EXPLORATION is local (his 10-10: tweak from where it is, never
leap): an explored value is the policy's v nudged, v + 0.2 x max(v, 0.25) x z, z ~ N(0,1),
clamped to the range (`NnNudge`, NN_NUDGE).

| head | file | v multiplies | range |
|---|---|---|---|
| con | econet | ConsNeedAny's target, and the army share the floor yields to: target / v (2026-10-09; it was a step, v > 1 never yielded) | 0.25-8 |
| mex | econet | every mex want's value before the draw (PUSH was 2); above 1x an open mex also jumps the forced guns (YIELD's effect); 1x = HOLD, the rule | 0-6 |
| cap | econet | the ground constructor pools' cap (base x v) | 0.5-12 |
| acap | econet | the air pool's cap, base x 4v (4 = the rule) | 1-20 |
| scap | econet | the late scout cap | 0.25-8 |
| esc | escnet | escorts per constructor, owed escort metal, the escorts-at-once cap and the escort buy's gain in the factory (MATCH = 1x; LIGHT was 0.5, HEAVY 2) | 0-8 |
| ecap | escnet | the escorts-at-once cap | 0.25-10 |
| cfear | escnet | the enemy-to-escort odds (EscortOdds: worse of armed metal by StrRatio and threat map vs escort surface threat) under which an escorted con still takes, keeps and works a site; also flags the con for the C++ guard and damage retreat; prefix NNCF; the esc head's own fields | 0.25-8 |
| mass / odds | nnmassodds | the pool's leave bar / the squad's refused enemy influence | 0.25-6 |
| defamt | protect_nn | DefenceTarget | 0.25-8 |
| mexg | protect_nn | MexGunsWanted's far term (guns a mex earns by its reach from them), and divides the coverall push's loss gate (TUNE_MEX_LOSS_COVER / v); every 30 s; prefix NNMG; own fields: mexes, unguarded (no gun in reach), guns covering a mex, mexes killed in 3 min, loss share, mean reach, enemy raid metal, army at home, minute | 0.25-8 |
| gunp | protect_nn | the forced defence pushes that bypass the draw: the guns basefront (gBfWanted), comself (ComSelfGun's need) and defrole (gDrQuota) want, as int(c x v + u) with u one uniform held all game (`apex: gunp-dither`), so v = 1 is c and below 1 a lone gun is bought in a share v of games; the cover jump's floor x v and its one gun by the same rounding; the defence role's quota (roles.as) x v. coverall stays mexg's, draw and defpanic stay rules. Every 30 s from 5 s + team stagger; prefix NNGP; own fields: minute, enemy army seen, its decaying peak, enemy army ever seen, raid metal, threat at home, danger gap, army at home, our guns, defence value, mexes, mexes killed in 3 min, eco metal lost | 0-4 |
| aplant | plannet | -- the plant count, owed ceil(v) | 1-8 |

**Play.** With odds t (trust x blend, honest trust only: NN_TRUST_KIND >= 2) the
net's best v, else the rule's 1x; then an explorer nudges it -- a held head (odds 0.2
per head per explorer game, ~2-3 of 13) by its game-long z, else with odds
NN_HEAD_FLAT by a fresh z. The placebo's stand-ins are the same nudges of the rule
(nntrain NUDGE_Z).
The best v is a sweep: 25 even points over the range clipped to the one the
net was trained on (`<P>_LO`/`<P>_HI` in nnweights.as), then 8 between the
best point's neighbours, 33 forward passes of the head's net with the state
layer done once -- ~37k multiply-adds (H = 32), ~4 ms by the builder net's
measured rate, as `nn.val` in the perf sections. It runs only on the t share
of a non-explorer decision. The five econet heads decide a second apart.
Never rounded: v plays as drawn; only the counts it sizes take a ceiling.

**Row.** `apex: nnval-schema v1 head=con state=.. own=.. lo= hi= rule=` once per
head, then per decision `apex: nnval head=con t=N f=F v=.. rule=1.0000 lo=..
hi=.. rnd=0|1 dens=.. ex=0|1 game=0|1 trust=.. vnet=..|- | state | own`.
`rnd=1` is a nudged value (held or per decision; `dens` still prints 1/(hi-lo) and
nothing reads it); `rnd=0` is the rule or the net (`vnet` = the net's pick when it
played). A new tag, so the old `apex: nncon`-style option rows never mix in;
`decisions.val_rows_of` reads it (`chosen` = v).

**Trainer.** `ValHead` (nntrain.py): the inputs are the state and own fields
(slog) and then v and the rule's value raw (the scaler standardises them), on
the same targets and labels. Trust is honest_trust on the same test as the
option heads, read for a value: on a game's first, unseen batch every
`rnd=1` row (one density per head, so weight 1) scores d = FULL(drawn v) -
FULL(1x) against outcome - FULL(1x), partial on FULL(1x); the lower end of the
game-clustered bootstrap, less the placebo (a rule row with one of 9 evenly
spaced values standing in). The range is saved with the net and exported.
The old discrete buffers of these heads were archived on the schema change.

`python tools/decisions.py <match|tournament> --out rows.jsonl` joins each
record to the gadget lines, for the deciding team, at +1/+3/+5 minutes: dMInc,
dEInc, mWaste, eWaste, dMex, lnD, kill, lost (enemy kills only) split into
lostNear (within 600 elmos of the chosen site: the decision's own exposure)
and lostFar (the enemy's doing), and by KILLER CLASS (lostAir / lostStatic /
lostMobile, from the killer's unit def), dEco (economic power incl. energy),
reclaim, `lostEco` (2026-10-09: metal of our extractors and mobile
constructors, not the commander, the enemy killed; its own TARGETS group
appended after endFast, since a key added to PER_H would land mid-list and
reset every net). Plus `done`/`buildS`, `survived`, and `lostPre` -- enemy kills in
the 5 minutes BEFORE the decision, a check that the state saw the pressure.

Against the enemy (2026-10-08): `edgeArmy`, `edgeEco`, `edgeLand`, `edgeMex`
at each horizon -- the change in ln(our side / theirs) of `tools/progress.py`'s
edges from the last whole minute before the decision to the last before f+h
(the same code, `progress.series_of`, per deciding ally team; ln clipped at
+-ln 10). His "did we do better" per decision, not one bit per game. Game
level: `endV` (result discounted from the decision, END_TAU 10 min) and
`endFast` = +-e^(-game minutes / 30), the result discounted from the game's
START, so a win at 25 min beats one at 55 and a loss held off to 55 costs
less; endV cannot see that for a decision equally far from either end.

A time-capped game (`winners=` empty, 2026-10-09) was STOPPED, not ended: a
horizon window that runs past its last minute is null, never cut at the cap.
Its result is where it stood (`capped_result`): 0.5 x tanh of the
mean of ln(our/their metal produced so far), the army edge and the extractor
edge at the end -- so a loss held to a draw counts -- giving endV, endFast and
won = 0.5 + 0.5 x that. comLostD there is labelled only where 9 minutes were
played after the decision, and never in a 1v1 (his death IS the loss, already
in endV; it was 0 on every row). The trainer clips mWaste/eWaste to [0, 1].
Targets are only appended: a trainer finding a
saved net and buffer with fewer outcomes grows masked columns and
zero-weighted outputs and logs it (`adopt_targets`), never a reset.
`won`/`endV`/`endFast`/`comLostD` are one value per game, so they are out of
the per-batch headline R2 (a single game's batch has no spread for them);
`game_sums` in metrics.jsonl carries their SSE/SST to pool over batches.

## Discovery games (`apex_nn_explore`, `apex_nn_plan_explore`)

His ruling 2026-10-09 (replacing 10-08's whole-strategy-only discovery):
about 75% of training games explore, many more single decisions are drawn
at random, and whole-team strategy exploration is much rarer, because it
changes behaviour too much. Two rolls, once per game per AI:

- **Decisions** (`apex_nn_explore`; the training launch passes the share):
  every head mixes `NN_HEAD_FLAT` (0.3) uniform into its odds
  (`NnHeadFlat()`), trusted or not -- builder heads, posture, escorts, raid,
  air, hunt, strike, tech, opening, the plan net's own 8-minute draw. The
  logged p includes the mix and `ex=1` marks the row. Exceptions keep their
  shape: the commander only ever trials SAFER (TURRET/RETREAT, one a minute,
  held 15 s; the trial share is in p and a held trial logs p=1), and the T2
  head draws one moment per tier instead of a coin every 30 s.
- **Balances held per game** (2026-10-09): a decision's single 30-s pick is
  buried under between-game variance (76% of the objective's), so each
  continuous head (below) is held, at even odds per explorer game and head,
  at ONE uniform draw over its range all game (`NnValHeldAt`); its rows carry
  `game=1 rnd=1`. The other half draw per decision (NN_HEAD_FLAT), so the
  trainer sees both. Situational heads (posture, hunt, strike, raid, air,
  tech, com, join, reinf, defsite, deftype, open) are never held.
  `apex: nn-balance t=N head=con held=0|1 v=.. lo=.. hi=..` once per head per
  explorer.
- **Strategy** (`apex_nn_plan_explore`, 0.1 of explorers): the explorer
  ALSO leads its team with one drawn plan, below.
- **The strategy** (`plannet.as`): the strategy explorer draws one plan for its team at
  its first plan decision (`why=first`) from the plan net's odds mixed with a
  flat share -- uniform while the plan net has no trust (its odds are only
  the NORMAL prior), half net / half uniform once it has. It holds the plan,
  renewing the team board's lease every 30 s, and re-draws only when our top
  tech tier rises and at least `NG_HOLD_S` has passed (`why=tier`; at most
  two re-draws). If it dies the lease lapses and allies decide as usual. A
  second explorer on the team follows the first (`BOARD_PLAN_LEAD`). The
  `nnplan` row carries the mixed p, so the trainer counts it a chance pick
  (weight 1/p, `rand_weight`). `apex_plan_explore` (Try strategies) runs the
  same path.
- **Kept**: one plant-type multiplier per game in every decision explorer
  (`PlantExpApply`; otherwise every opening is a bot lab).
- **What ran is what is logged** (2026-10-09): a drawn posture (`nnpost`) is
  held as drawn for its window even when it is the rule's, and none is drawn
  while all-in (p=1 on the rule; a standing draw re-decides `why=allin`); the
  escort head's v raises the per-constructor escort count (its ceiling), not
  only the metal owed; an air GO with nowhere to go logs WAIT at p=1.
- **Logs**: `apex: nn-explore t=N on | decide=1 strategy=0|1 headFlat=0.30
  planChance=0.10` at the roll (only explorers print it);
  `apex: nn-explore-plan t=N plan=X p=.. why=first|tier tier=..` at each
  strategy draw; chat "Team N is the DISCOVERY explorer this game: strategy X
  (...)" for a strategy explorer only.

The trainer archives (never deletes) the net when the record's layout or its
own outputs change: `runtime/nn-archive/<stamp>/`.

## Live training (Net tab)

`tools/nntrain.py`, started from the Net tab. Every 5 s it reads each RUNNING
game's own files (write dirs `matches/_engine*`, `runtime/engine-w*`: the
gadget log plus each AI's `apex-t*.log`, flushed every frame). A decision is
trainable once its 5 minutes have been played; at 150 matured decisions the
batch is predicted first (the accuracy point, always unseen data), then trained
on: STEPS_PER_GAME (50) minibatches of 512 rows, up to 128 of them new and the
rest replay -- half by recency (row age exponential, e-folding at 5% of the
buffer), half from everything with each script version weighted by how many
versions back it played (untagged rows 0.1). Finished games give their remainder; a game is keyed by its first
records, so nothing counts twice. Dropout 0.1; every 40,000 rows learned (per
net, not per batch) a partial reset (weights x0.8 + fresh x0.2) keeps it able
to learn. Two nets:
FULL (state + decision) and STATE (state only); full minus state is the
evidence that decisions carry learnable value. A live game is re-read at most
once a minute; logs without the v3 schema (his own build) are skipped after one
look. State in `runtime/nn/`.

**Buffers** (2026-10-09, `tools/nnstore.py`): `runtime/nn/shards/<net>_rows/`,
append-only -- a save writes only the rows since the last one plus a small
`index.json` (the old `buffer.npz` was rewritten whole every ~10 batches,
~300 GB/h, and filled C: on 10-09). XF float16 (XS is its first `ns` columns,
not stored), Y float16, M uint8, and a tag per row: the game's script version
(`apex: version ... script=`, `old` before 2026-10-08) and regime (map | team
sizes | minute cap). ~517 bytes a builder row instead of 1,567. A buffer keeps
the newest `REGIME_KEEP` rows per regime on load (`BARAI_NN_REGIME_KEEP`,
10M: nothing dropped today); `--compact` rewrites without the rest. A legacy
`*buffer.npz` is migrated once, streaming, its rows tagged from metrics.jsonl
(`--migrate`), and renamed `*.npz.migrated` -- deleting those is a disk call.
`python tools/nnstore.py runtime/nn/shards/builder_rows` shows the mix.

**Snapshots and evaluation**: every 6 h the exported weights are copied to
`runtime/nn/snapshots/<stamp>/`. `tools/nneval.py plan --a snapshot:<stamp>
--b blend0` prints the lanes, installs and tournaments of a paired held-out
evaluation (no exploration, bonus 0, fixed seeds, both seats); `nneval.py
report A B` judges it pair by pair on edge changes at minutes 10/15/20 and
time to loss, not wins.

## The net plays (`apex_nn_blend`)

Every ~800 learned decisions the trainer writes the FULL net as `nnweights.as`
into the deployed copies named in `runtime/nn/targets.json` (default the
`nnlog` lane, both engine- and game-side). The repo copy is the empty net; a
deploy keeps the deployed weights (S39: until 2026-10-07 it put the stub back,
and the stub did not compile). Every game loads the latest weights at start; they are fixed within a
game (host-side, no desync).

`NnScore` (in `Decide`, right after `OppTimeReprice`) scores the top 8 options
and folds the outputs through OBJECTIVE into one number in units of each
outcome's spread. Since 2026-10-05 (aebeab52, `comb=trust` in the schema line)
the vote is in LOG space with a per-kind TRUST: each option keeps the group's
mean log value, and its deviation from it is the market's at trust 0 and the
net's verdict (clamped +-3) at trust 1 -- his point that market prices are so
lopsided between kinds (nano 15, tech 1.5, assist 0.19) that the old capped
multiplier could never swing them. Trust per kind (per head) is EARNED, kind 2
since 2026-10-09 (`NN_TRUST_KIND = 2` in the exported weights; the repo stub
says 0; the game side is to read trust as 0 below 2 -- not in the scripts
yet): on a game's first, unseen
batch, every CHANCE row (logged odds below 0.95, or an explorer's override)
scores d = FULL(chosen) - FULL(rule) against the realized outcome -
FULL(rule), both in OBJECTIVE units, weighted 1/p (cap 20). The rule is the
head's rule option, or for the builder and factory the top-valued priced
option. Trust (kind 3, 2026-10-09 evening) is the lower end (2.5th
percentile) of a game-clustered bootstrap of the SLOPE of the realized gain on
the predicted one, FULL(rule) held fixed (both carry it, which alone made them
correlate) -- the share of the net's claimed gain that turns out real -- less
the net's own placebo slope when positive, in [0, 1]; nothing under 200 chance
rows or 5 games; the most recent 5,000 pairs. Kind 2 took their CORRELATION,
and outcome noise is 10-20x the decision's effect (sd(a) 2.3-4.4 against
sd(d) 0.1-0.6 on every net), so a perfect net read ~0.1: T2's slope was 1.10
[0.53, 1.71] while its correlation-trust sat at 0.07. The old trust -- FULL minus STATE against outcome minus STATE --
read +0.1..0.3 on rows where the pick WAS the rule: it measured the two nets
disagreeing. metrics.jsonl carries `placebo` (the new statistic on
rule-following rows, an option not taken standing in for the chosen one: it
should read ~0) and `placebo_old` (the old statistic on the same rows).
apex_nn_blend scales trust. The ETA ladder,
which ranked economy options by time to target alone, divides that time by
e^(trust x verdict). His rulings stay rules. The whole list is re-sorted
because `DrawWeights` takes the first of each category. OBJECTIVE
(nntrain.py) is a stated default until he picks one: +5 min economic power
1.0, metal and energy income 0.25 each, damage trade 0.5, losses near the
site -0.5, finished, survived, lifetime and lifetime kills 0.25 each; since
2026-10-08 also endFast 0.5, land edge +5/+10 0.25/0.5, army edge +5/+10 0.25
each, eco and mex edge +10 0.25 each; since 2026-10-09 lostEco +1/+3/+5
-0.25 each.
**Decision heads** (2026-10-09, `NnHeadScore`/`NnHeadMix`, posture's
`NnPostScore`): the log-space blend left the rule's 1 vs 0.01 (4.6 log units)
standing against a verdict clamped +-3, so no head below trust ~0.43 could
overturn its rule. Now p = (1-t) x rule policy (its weights normalised) +
t x net policy, the net policy a softmax of the option scores standardised
across the options (the score is an OBJECTIVE sum of predicted outcomes in
spread units, not a logit, so its ranking is used and trust alone sets how
much plays). Only when the trainer exports the honest decision-specific
trust, `NN_TRUST_KIND = 2` in nnweights.as; below 2 (the stub says 0) every
head plays its rule. The logged p is the mixture as drawn. A continuous head
mixes the same way over values: t plays the net's best v, 1-t the rule's 1x
(Continuous heads, above). The builder and factory nets still blend in log
space against market values.
The plan from here (his 2026-10-05): the market value becomes one input and
the net's score the value, kind by kind, as trust is earned. `apex: nn-score`
(60 s) proves it fires: scored count, how often it changed the top option,
perf as `dec.nn` (recording as `dec.nnrec`). NNW_GAMES counts training
batches, not games.

## Review 2026-10-04 (Fable, read-only) and what changed

Confirmed correct: train/serve feature parity, weight layout, no label
leakage, nnMult never compounds, the maturity rule. Fixed: live training was
dead (the trainer looked for schema v3); 22% of rows were FORCED wants
(escort/panic/join) inserted after the net looked, with placeholder values --
now flagged (`forced`, `Want.nnPriced`), excluded from the field's best and
value-masked, and the with-vs-without headline uses only rows chosen on value;
accuracy is scored only on a game's FIRST batch (later live batches overlap
99% of their label windows); games are keyed per team; a live row waits for
its survival label; survived counts enemy kills only (a moho finishing kills
its T1 mex); finishes match the decision's site (`[BARAI_BUILD]` now carries
x,z); target spread floored at 0.1; lostPre is a diagnostic, not an output;
retries on Windows file locks and a loop that survives errors; NnState once
per frame, each option's inputs computed once per election, int one-hot, full
weight-shape check. Open: the logged propensity p is exact only for drawn
rows (fallthrough picks read p=0); per-election cost still unmeasured at 8v8.

## What the first game showed (12 min, Comet Catcher, vs BARb hard)

123/123 executions recorded. **Only 3 of 123 came from the draw**; 103 were
fixed (roles, panics, pushes), 17 by the ETA ladder, and 41 fell past a refused
winner (pick > 0). The draw is where the net acts, so most decisions are still
outside its reach; opening them up is his call.

## Next

1. A tournament of logger games with the trainer running: does FULL beat STATE?
2. Blend A/B (0 vs 1) head to head, judged on minutes.py, not on the net's chart.
3. Randomized-net games for discovery (his idea): each game plays a perturbed
   net and records the perturbation.
4. Reload weights mid-game (needs a DLL file-read binding).
