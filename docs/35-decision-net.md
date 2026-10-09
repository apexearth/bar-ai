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
- `apex: nnscap` (`econet.as`, 2026-10-08) and `apex: nnecap` (`escnet.as`,
  2026-10-08): count caps in the priors made learnable, the `nncap` pattern.
  `nnscap` sizes the late ground scout cap (`ScoutFleetCap`, `:scoutcap` and
  `:esc-capped` in prodrank) at S1 (the rule: the flat base, max(20,
  maxunits/50)), S1.5 or S2 (x4 dropped: 160 scouts an AI is a frame-budget risk at 16 AIs); prefix NNS. `nnecap` multiplies the escorts-at-once
  cap (`EscortCap` = TUNE_ESCORT_CAP x the escort net's strength) by E1 (the
  rule), E2 or E4, reading the escort net's own fields; prefix NNY. Both on the
  30 s clock of their file. The flat base itself stays a ceiling on rez bots
  and on `EscortShortfall`: it came from 564 rez bots taking his 4v4 to 0.65x
  sim speed (c4a489ac), a frame-budget contract, not a prior.
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
- `apex: nnmass` / `apex: nnodds` (`manager/military/nnmassodds.as`,
  2026-10-08): two docs/24 section 7 priors made decisions, every 60 s per
  team (staggered), options X05 / X1 / X2, rule X1 (today's numbers). MASS
  multiplies the bar a massing pool must reach before it leaves
  (`quota.attack` after `UpdateMassing`'s hold logic, before the own-army
  ceiling; also the turtle resume/lift writes); with the DLL also the
  biggest-enemy-group term of the C++ promotion bar (`UpdateDefenceTasks`).
  ODDS multiplies the enemy influence `CAttackTask::FindTarget` refuses
  against (the strong test and the remembered-strong-group test): X05 takes
  fights at half today's odds, X2 wants twice them. Both ride the team board
  (slots 1400+team odds, 1500+team mass); the DLL reads them every 5 s, logs
  `apex: mil-board` on a change and stamps 1600+team, and the odds head
  records nothing until that stamp is fresh (`noDll` in `apex:
  massodds-stat`), so an old DLL never yields a row whose pick did nothing.
  No head-specific label: the shared targets (lnD, lost/kill, army edge,
  endFast) judge both. Prefixes NNM, NNO.
- `apex: nndefamt` / `apex: nndefsite` (`protect_nn.as`, 2026-10-08): his
  "a NN governing defense count and placement". AMOUNT (prefix NND): every
  60 s, D05 / D1 / D2 multiplies `DefenceTarget` (rule D1), held to the next
  decision; fields are leak metal (5 min, all / eco-nano-lab / inside the
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
- `apex: nnaplant` (`plannet.as`, 2026-10-07): while the plan is AIR, how many
  basic air plants -- P1 (the rule), P2, P4, every 30 s. Short of the count,
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

## The table

`python tools/decisions.py <match|tournament> --out rows.jsonl` joins each
record to the gadget lines, for the deciding team, at +1/+3/+5 minutes: dMInc,
dEInc, mWaste, eWaste, dMex, lnD, kill, lost (enemy kills only) split into
lostNear (within 600 elmos of the chosen site: the decision's own exposure)
and lostFar (the enemy's doing), and by KILLER CLASS (lostAir / lostStatic /
lostMobile, from the killer's unit def), dEco (economic power incl. energy),
reclaim. Plus `done`/`buildS`, `survived`, and `lostPre` -- enemy kills in
the 5 minutes BEFORE the decision, a check that the state saw the pressure.

Against the enemy (2026-10-08): `edgeArmy`, `edgeEco`, `edgeLand`, `edgeMex`
at each horizon -- the change in ln(our side / theirs) of `tools/progress.py`'s
edges from the last whole minute before the decision to the last before f+h
(the same code, `progress.series_of`, per deciding ally team; ln clipped at
+-ln 10). His "did we do better" per decision, not one bit per game. Game
level: `endV` (result discounted from the decision, END_TAU 10 min) and
`endFast` = +-e^(-game minutes / 30), the result discounted from the game's
START, so a win at 25 min beats one at 55 and a loss held off to 55 costs
less; endV cannot see that for a decision equally far from either end. Both
masked for a time-capped game. Targets are only appended: a trainer finding a
saved net and buffer with fewer outcomes grows masked columns and
zero-weighted outputs and logs it (`adopt_targets`), never a reset.
`won`/`endV`/`endFast`/`comLostD` are one value per game, so they are out of
the per-batch headline R2 (a single game's batch has no spread for them);
`game_sums` in metrics.jsonl carries their SSE/SST to pool over batches.

## Discovery games (`apex_nn_explore`, 0.1)

Each AI rolls `apex_nn_explore` once per game (training passes 0.1). Agreed
with him 2026-10-08: discovery is a WHOLE STRATEGY, not a coin per decision.

- **The strategy** (`plannet.as`): the explorer draws one plan for its team at
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
- **Every other head** plays its rule or net as in a normal game. Only a head
  whose net has no trust -- it plays its rule at p=1 and would never see an
  alternative -- mixes `NN_HEAD_FLAT` (0.1) uniform in (`NnHeadFlat`); its
  row says `ex=1` only then. A trusted head draws from its own odds in every
  game and supplies its own chance rows.
- **Kept**: one plant-type multiplier per game (`PlantExpApply`; otherwise
  every opening is a bot lab) and the T2 head's single drawn moment per tier
  while it has no trust. Both are whole-game, not per decision.
- **Logs**: `apex: nn-explore t=N on | headFlat=0.10` at the roll;
  `apex: nn-explore-plan t=N plan=X p=.. why=first|tier tier=..` at each draw;
  chat "Team N is the DISCOVERY explorer this game: strategy X (...)".

The trainer archives (never deletes) the net when the record's layout or its
own outputs change: `runtime/nn-archive/<stamp>/`.

## Live training (Net tab)

`tools/nntrain.py`, started from the Net tab. Every 5 s it reads each RUNNING
game's own files (write dirs `matches/_engine*`, `runtime/engine-w*`: the
gadget log plus each AI's `apex-t*.log`, flushed every frame). A decision is
trainable once its 5 minutes have been played; at 150 matured decisions the
batch is predicted first (the accuracy point, always unseen data), then trained
on, each minibatch mixed with as many old rows (replay, so it does not drift
toward the loudest game). Finished games give their remainder; a game is keyed
by its first records, so nothing counts twice. Dropout 0.1; every 40 batches a
partial reset (weights x0.8 + fresh x0.2) keeps it able to learn. Two nets:
FULL (state + decision) and STATE (state only); full minus state is the
evidence that decisions carry learnable value. A live game is re-read at most
once a minute; logs without the v3 schema (his own build) are skipped after one
look. State in `runtime/nn/`.

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
multiplier could never swing them. Trust per kind is EARNED: on unseen games,
the correlation of what the net says the decision adds (FULL minus STATE
prediction of the objective) with what it actually added; 0 under 200
decisions, over the most recent 2,000 pairs only (TRUST_RECENT: older pairs
scored weights since replaced -- the commander net read -0.22 on its oldest
quarter and +0.17 on its newest); exported as NNW_TRUST; apex_nn_blend scales it. The ETA ladder,
which ranked economy options by time to target alone, divides that time by
e^(trust x verdict). His rulings stay rules. The whole list is re-sorted
because `DrawWeights` takes the first of each category. OBJECTIVE
(nntrain.py) is a stated default until he picks one: +5 min economic power
1.0, metal and energy income 0.25 each, damage trade 0.5, losses near the
site -0.5, finished, survived, lifetime and lifetime kills 0.25 each; since
2026-10-08 also endFast 0.5, land edge +5/+10 0.25/0.5, army edge +5/+10 0.25
each, eco and mex edge +10 0.25 each.
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
