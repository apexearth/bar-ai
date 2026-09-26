# What apexearth wants and has not got yet

One line per open item, as a statement of the mechanic or the ruling. An item
is deleted when it is built and measured -- never marked done. If he says a
thing again, edit the line; a repeat means it is still open. Mechanisms and
numbers live in `ISSUES.md`; named plays in `TODO.md`; fight doctrine in
`docs/24`; defence in `docs/32`; the economy frame in `docs/23`. Rulings on
defaults are in `docs/27` keyed by tunable. Rewritten 2026-09-15 from 1,665
lines of quotes.

## Economy and builders

- HIS GOAL 2026-09-21 (night): beat BARb stable hard reliably, over half the
  time, in his 2v2 -- Glacier Pass, Armada both, +100% both, 0.2 lr boxes.
  He asked for unbiased agents to challenge the session's reading. Standing
  at 8-15 over 24 games from 1-19 (ISSUES "2v2 GLACIER PASS +100%"); the
  16-24 window (their converters and fusions, our army standing on the base
  rim while the forward spots go to them) is what is left. UNRESOLVED.
- We do a bad job expanding (his watch, 2026-09-21): both of our players
  held 5-7 mexes for 16 minutes on a 19-spot map while BARb's two took the
  strip between our corners by minute 8. Measured: the spot gap is forward
  spots only, and it forms while our hands upgrade home mohos in the 10-12
  window. The ladder's spot claim is no longer sampled away (64fcb121).
- The eco seat should run on nano turrets, not constructors: about 4 advanced
  land cons, ~10 T1 air cons, 5-6 advanced air cons, and turrets for the rest.
  Today the seat's ~120 T2 cons come from the T2-con floor `2 + income/25`
  (his 2026-08-23 "at 100 m/s at least 5", scaled); `expect.py` "eco seat
  hands are turrets" is RED. Whether that floor is right at 1k income on a
  turret-ringed seat is his call (ISSUES BUILD POWER).
- Air constructors are how a rich base scales; the seat should open an air
  plant and build T1/advanced air cons. Con floors count flyers once a plant
  offers them, but the seat opened an air plant in one game of three.
- A safe big build is started by the air con that flies there, not the
  ground con everyone trails (2026-09-20: the crew followed a T2 bot con 80 s
  to a base gantry). A front-line site is the ground crew's. Built 09-20
  (`apex: assist-own`); air cons took own orders on mohos in a 2v2, no
  gantry case seen yet.
- On big 8v8 maps (Carrot Mountains) he sees no eco player (2026-09-20).
  Under measurement.
- The 8v8 allies never scale: the eco seat does its role and supports the
  team, the other seven fall behind BARb's players all game and do nothing
  useful with unlimited money (2026-09-21, Isthmus 8v8). Measured: the seven
  reach a third of BARb's income by minute 16 in every 8v8 of the day; the
  first six minutes on a full bank (fixed 09-21, `HandsShort`), then the
  same army metal as BARb on a third of the economy (min 8-16: army 45% of
  spend to their 30%, eco 16% to their 28%) -- under scarcity the split
  between the lab and the eco hands is decided by build-power pull, not by
  any price. `tools/allies.py`. The split is his to rule on; open.
- The switch (2026-09-21): make enough army for a normal defence of
  ourselves, then stop making army and switch to a good T2 economy --
  upgraded mexes, fusions, advanced converters. His read of BARb: heavy T1
  army, then a sudden all-in on economy (measured: BARb's army spend flat
  from minute 8 to 14 while its economy spend triples). Built 09-21
  (`T2SwitchOn`, army.as): for non-seat players the army's share leaves the
  target until the T2 economy stands; cover, AA, towers and the seat's danger
  valve stay. Isthmus 8v8, 3 seeds: metal per player at 30 min 152k -> 208k.
  Open: (1) the labs still convert spare metal into army (the "waste is free
  army" law) -- the strict form that stopped that sent the freed metal into
  nano turrets and Farks (BP 31k -> 52k per player) and gained no economy;
  (2) the switch never read DONE in 30 minutes: the far mexes are never
  upgraded and no ally builds a fusion while the seat's energy overflow fills
  its bank. `apex: t2switch` says what is missing. 09-21 evening, his
  Isthmus 1v1: it could not read DONE at all -- the ledger dropped every
  upgraded spot (the moho's finish kills the mex under it) and the levelled
  commanders made the advanced converter read as T1-buildable (`mohos=0/N
  NOCONV` all game with 64 upgrades and 37 advanced converters standing).
  Fixed 09-21 (census.as, army.as; probe: `mohos=5/6 fus`). Its side-effect
  was his three reports that evening: with the army target at 0 only the
  counter roles have a share, so the T2 lab made 86 Hounds (artillery vs
  their statics) and nothing else, the T1 lab 21 Maces at 20-30 min, and
  the metal with no army to buy went into 772 nano turrets (107 around the
  fusion cluster, `idle=8960`). Still open: while the switch IS on the labs
  get only the counter roles (item 1), and his late-game rule -- past T2 the
  T1 lab makes only the cheap fodder (pawns, ticks), never a Mace: "you get
  a unit that takes the enemy fire but costs you a lot less" -- built 09-25
  as `OutgrownAtT3`, see "AT T3, ALL RESOURCES TO THE BIG UNITS" below.
- Air labs idle with unlimited money and many nano turrets; make longer
  queues so the line never runs out (2026-09-21, fourth report). Found and
  built 09-21 (`RedrawFor`, TODO "Never an idle factory"): seat lines empty
  46% -> 22% of snapshots. Unverified by him.
- At 1,000 m/s no basic converter should be started; at 32k E/s income with
  5k pulled, advanced converters should be going up in numbers. Open until a
  watched game shows it (ISSUES CONVERTERS, GANTRIES).
- Idle factories must not exist while the bank is full; an idle gantry never
  justifies another. Fixes 09-13 did not close it: 09-16 Isthmus 8v8, ~10
  advanced air labs idle while half our metal went unspent. Third report
  (TODO "Never an idle factory"; ISSUES GANTRIES).
- A pulsar alone at a few mid-map mexes with 79 nano turrets around it and
  nothing else: "if you're gonna commit so goddamn hard, at least build more
  defensive turrets around there" (2026-09-21). The turrets were the fusion
  cluster's sink term on a bank pinned full with no army to buy (see the
  switch above); the defence half -- a second base's guns where the
  economy commits -- is not built.
- No pile of basic towers in the base: 25 light towers inside 250 elmos of one
  base (09-19, Red Comet 2v2) was "embarrassingly stupid" and the money of a
  moho spent on T1 towers while a moho crawls. Fixed 09-19 in three parts (the
  T1 fill bounded at one gun; shortfall slots take the strongest affordable
  gun and only for ground still short; no basic tower once an advanced con
  exists; a gun no stronger than one that died there is not rebuilt there):
  towers per 2v2 game 25-65 -> 11-24. Unverified by him.
- Metal first, in his order: build the mexes, upgrade the mexes, then protect
  the mexes (2026-09-20, Frozen Ford 1v1 watched). Measured there: 5 mexes to
  their 10 at 9 min; the two mexes beside the commander upgraded at 23-25 min
  with the first T2 con out at 8.6; the upgrade was the top-valued want in 11
  elections 9-23 min and won none (5 to the defence role seat, 6 to the draw
  -- a geo at v=2.5 over a moho at 10.2). Both T2 cons walked to geos 1,900
  and 5,200 elmos out. Open: the election, not the price.
- No nano turret while the bank is empty and metal is fully spent
  (2026-09-20): 96 nanos in 6 min on a bank pinned at 0. Cause was 09-19's
  LowerLinesEat (a higher line's demand = the lower lines' paper lathe,
  unbounded). Bounded at parity 09-20; one 2v2: nanos per team 187 -> ~54.
- 380 m/s income and not one pulsar; defence spend read 0 in half the
  3-min buckets (2026-09-20). Same game: 604 nano orders to 16 defence orders
  after 20 min; where defence was worth more it lost to the energy role seat
  10 of 10. Re-measured 09-20 after the nano fix: unchanged (3.8% vs BARb
  17.7%). Three mechanisms fixed the same day (ISSUES DEFENCE SHARE): the
  defence role never assigned, the Pulsar rated under a Pit Bull, the LRPC
  reading zero in reach. Defence at 16-24 min ~3x on three seeds; still a
  third of BARb's share -- open.
- We make far less defence than BARb stable and no long-range plasma
  cannons; "we need to do better" (2026-09-20). Same entry.
- Constructors do not walk out alone onto ground where the last one died, and
  lost mexes are not passively conceded (09-19). The first half is built: a
  con's death marks its ground for the claims, the wrecks, the rez chain and
  a walking hand's own job. The second half -- the army retaking the mexes --
  is doctrine and open.
- The commander does not chase light scouts he cannot catch; he puts a turret
  where he stands (09-19). Built in the DLL (FindBCombatTarget) and the cover
  push; needs his DLL rebuild to reach his slot.
- The front players of an 8v8 scale their economy past one fusion (09-19).
  Found: the seat's energy overflow fills their bank so no generator is
  bought, their T1 converters eat it, their advanced-con floor read 1 with
  turrets standing (fixed), and their mex claims walk into the enemy. Open.
- A T2 lab is built by many hands, not one; we reach T2 behind our enemies.
  09-19 (Isthmus 1v1, T2 at 15.7 min at 120 income against their 6.5; his
  fifth report): the market bought it at 7.6 -- the hand walked off it, the
  orphan order deferred every re-ask, the def sat in abort backoff. Fixed
  09-19 (keep-job without the draw escape); 1v1 T2 median 4.2 min since.
  Still open: is T2 at 4 min and 27 income what he wants, and gantry timing.
- The gantry comes when the economy can carry it (~100-150 m/s), before a
  second T2 lab and before the enemy's T3 is on the field; 09-19 Isthmus: no
  gantry at 36 min against their 14, a second T2 bot lab at 30 (a plant-move
  copy priced 0.001 that went up as the last want left). The anti-nuke's
  extra copies (target 1 + income/150) won every super election over it.
- A T2 lab is not started while the front is being lost (seed 17) -- the
  tech price has no army-share term (ISSUES ECONOMY LADDER, stage 2).
- A dead mex is rebuilt quickly; six reports. Structural now (draw share and
  busy cons); a rebuild preemption is a rule and needs his say.
- The first factory is up by minute 2 in every game (ISSUES OPENING).
- Guarding a constructor must end when the job no longer needs the hands; 30
  cons following one hand to a nano turret is wrong. Assist pays its metal
  and a con-guard ends with the job (09-13/14) -- unverified by him.

## Base layout

- Allies block each other's walkways: we leave ground open to walk through
  and an ally builds in it; one lane system for the whole team
  (2026-09-21). TODO "Allies keep each other's walkways"; not built.
- Big builds go where the nano turrets are; that decides double-speed
  building. Built (densest ring, 09-14) -- unverified by him.
- Grid snapping, raised again 09-16 (third time): same-size buildings must
  line up exactly, never one square off; nano turrets go directly beside
  other nano turrets and form a block; different types MAY stand directly
  beside each other -- tight everywhere, with only room for units to move.
  Built 09-16: one per-def lattice from the map corner, the nano task routed
  through it (it had its own square search), the wide search's answer put
  back on the lattice, labs asked for on their own lattice, the block-map
  yards dropped to flush, the fresh-group foreign gap cut to one cell.
  Census (`tools/tiling.py`): same scenario 55% -> 100% aligned; eco-only 25
  min 94-96% of 700 structures, the rest nano turrets hugging a fixed site.
  Unverified by him.
- Shields only where they can be shelled: on the line, or once an enemy LRPC
  is seen; two on the eco seat far from any gun is waste (09-16). Jammers:
  one per location, a second adjacent one adds nothing (09-16). Mechanism
  found: a line want whose site the C++ veto refused fell to the base's
  700-ring 3,400 elmos away and the line stayed uncovered, so it was bought
  again; and five seats each bought the team line's one shield slot. Built
  09-16 (site.blocked gate, service-radius fallback, team-aware coverage) --
  unverified by him.
- Team games: we do well when wealthy and badly under scarcity; be more
  careful and thoughtful about spending (09-16). Measured: at +0 an 8v8 is
  lost 8/8 with a third of their metal -- income, not spend; ISSUES
  SCARCITY has the mechanisms. His ruling: grow ballistic only when it is
  intelligent; concentrate spending under scarcity; in 8v8 the mex count
  per player is small so income must come from the economy (energy,
  converters), and "understand our potential untapped mex economy". Built
  09-16: a TOTAL in-flight cap from income (help finish what is started),
  hot spots refused at choice time, `tools/mexeco.py` (extractors and
  income per side over time). One seed: 122k -> 257k metal vs their
  416k -> 343k, wiped -> no winner. Unverified by him.
- Team games under 10 minutes (09-17): we out-build their army early while
  holding fewer mexes -- too much army, too little economy -- and they always
  defend their mexes; put the guns right on our mexes outside the base, more
  the further from home. Built 09-17: a mex earns 1 + 3 x forward-fraction
  light towers, the floor and the cover jump read that count, and the jump
  puts the gun on the mex the hand stands at. Two seeds of Comet 8v8: metal
  418k -> 559k and 378k -> 422k, mexes held at 24 min 9 -> 31 and 6 -> 13,
  K/D 0.38 -> 0.59 and 0.29 -> 0.51 -- still losing the map, less badly.
  `tools/opening.py` is the under-10-minute table. The minute-2-4 hole (10
  mexes to their 19) is the energy-stall hoist buying solars -- his 09-08
  ruling, not touched. Unverified by him.
- Darts (09-17): "a bit excessive... we still need scouts but not so many";
  T2 only when the T2 can be afforded once built, but not late. Built 09-17:
  the cover and screen terms saturate on the patrol reading (the posted-guard
  share never fell: an escort holds no post), and a tech lab is never
  drawn by the lottery -- it wins when it is the best-priced thing. Comet
  8v8 seed 2: Darts made 882 -> 150, first T2 4.4 min -> 7.6, standing army
  at 10 min 16.5k -> 20.2k (theirs 20.4k), metal 378k -> 480k over the
  day's four steps. Unverified by him.
- The eco seat's guns stand inside its base with walk gaps, blocking the farm;
  two gantries starve for nanos with a full bank; LRPCs belong on hills;
  Behemoths when the enemy is winning (09-16). Recorded in ISSUES/TODO, not
  built.
- An eco base is rows with no gaps, no lanes behind the anchor, factories to
  one side, guns/radar/anti-nuke ringing it; two or three bodies so one blast
  does not take everything. Rows and no-lanes are built; "factories to one
  side" is not.
- Dragon's teeth become obsolete past ~100 m/s income and should be reclaim
  candidates; teeth are priced as a soak now, the reclaim half is not built.

## Defence

- Outer mexes get guns; pushing our mexes must cost the enemy. A raided
  bearing now carries the spots it starves (09-15) -- unverified beyond one
  Frozen Ford seed.
- Heavy towers are cheap relative to T3 army; the defence market leans that
  way (standing direction, 2026-08-29).
- Against tank armies the line holds with shields; the shield and support-row
  nano fire rarely (docs/32 open item).
- T2/T3 defence and jammers go up when the enemy closes on a T2 base: "a
  life/death situation". The `stopped` clip priced a single tower at zero on
  contested ground; unread under the team front (ISSUES THE LINE).
- Jammer logic "still needs improvement" (2026-09-09), no detail given -- ask
  what he sees before changing anything.
- Flak is spread around the base, not clustered at the nano block.
- When most of the army is far from home the base buys extra defence
  (2026-09-20). Army at home counts as cover both ways (his choice); built
  09-20, reads 0-31 metal of cover at the sites priced because a unit's
  answer reach is one building's 8-s life -- inert until the reach is his.

## Army

- The loss cause in team games is army share: we spend ~10% of metal on army
  against BARb's 23-32% and trade 0.4-0.6 (ISSUES ARMY SHARE). A won economy
  must end the game (ISSUES CLOSING).
- Multiple groups coordinate an attack; one big squad is not required
  (ruling 2026-09-06, not built -- ISSUES attack bar).
- Reach units (Sheldons, Arbiters, snipers) never arrive in numbers: reach
  holds 0.04-0.07 of army metal against a 0.35 target; five pricing changes
  and a draw allocation (`TUNE_LINE_ALLOC`, off) failed. A share cannot come
  from a nudge when the per-metal spread is ~12x.
- Escorts are for workers OUTSIDE the base; late game the base holds no
  escort per builder, and the cheap units die forward as spam. Air cons get a
  fighter escort. Built 09-13 (`FighterEscortWorthy`, exposure off the risk
  field, spam on) -- no game of his has shown it.
- Raids hit their ENERGY first, then metal, then build power; scouts find it.
  We run ~2 scouts (flat quota) and the raid director finds a target in 1-3%
  of asks (ISSUES RAIDS).
- A fragile long-range unit never blind-walks into fire on a plain move
  order (2026-08-16, Sharpshooter). The custom standoff was reverted to stock
  09-07; no read since.
- Fight orders are used too freely (2026-08-31); unattributed.
- When an enemy outranges us with high dps, the T2 lab answers with a longer-
  range unit; the production draw is a plain roulette (Sharpshooter ranked
  first, drawn 0 of 22) -- sharpening it is his call.
- Bots are made almost always; on vehicle maps we underperform. The line
  census agrees (T1 vehicles 1.3-1.8x, T2 2.5x on Comet) but the opening
  plant is bought for its constructor and want_tech prices by mean
  power/cost; `TUNE_LINE_QUALITY` measured inert (docs/27). Put the line's
  army worth where those two decisions are made.
- The whole army should not chase one Pawn; groups sent after raiders are
  sized to the raid (fight layer is stock since 09-07; docs/24 holds the
  doctrine).
- Titans are never walked home and never parked at home because shells are
  landing (2026-09-20, 8v8: 17 of 17 that turned at 30% died on the walk;
  13 stood at home on an uncapped under-attack hold). Both built 09-20;
  unverified in a game of his. OPEN, his to rule: solo beeline (08-19) or
  the thirteen going together as BARb's do -- "walk them through the ocean,
  come up the side and win".
- Are we more cautious than BARb? (2026-09-20) Yes on the one knob stock
  turns: `quota/thr_mod` neutral against stock hard's 0.6-0.8 / 0.3-0.5, set
  to offset a margin the 09-07 revert deleted; plus withdraw.as pulling units
  off enemy-influenced ground. The JSON A/B is not run (ISSUES ARMY).

## Air

- The seat, once it turns military, makes a lot of air and sends devastating
  bombing raids; late game is LRPC and nukes, not more factories. Bomber
  bidding, cost-weighed wings and the hold-off removal landed 09-13/14 --
  open until a game of his shows a raid (ISSUES BOMBERS).
- No AI starts with an air lab (rate term prices it out; 12 openings all
  bot/vehicle -- hold).
- Air scouting coverage has never been measured against the threat readings
  it feeds.
- A wave over the enemy base commits: no turning around over the cell
  (2026-09-20: 29 Phoenix circled, dropped nothing, lost 15). Built 09-20 in
  the DLL (`apex: bomb no-target`); unverified.
- While bombers are held for a strike the plant does not pause between them
  (2026-09-20). One order per election on an 8-28 ms order cost; re-entry
  after a second built 09-20, empty-line samples 28% -> 2% in a 2v2.

## Navy and water

- Legion in water made 90% constructors and rez subs; the navy stub is fixed,
  the frigate/sub water-only read is not (ISSUES LEGION CONFIG).
- From an Isthmus start no bot con can reach a shipyard; the naval lead's
  commander could at minute 5 and his 2026-08-28 ruling forbids commanders on
  water plants. Needs his answer.
- Composition follows where the enemy IS: an enemy living on water demands
  ships, seaplanes or advanced air from a land start. Not built.
- A naval player must contest water mexes, not defend himself and idle; the
  advanced construction sub never elects (ISSUES NAVY).

## Rez bots and the commander

- Rez bots: 4-5 by minute 12 (we hold ~3); productive between jobs; behind
  our units in combat; react within a second (reflex built, 1.4 deaths/game).
  Residues in ISSUES REZ.
- Rez boats are bought from land wrecks they cannot reach (ISSUES REZ).
- The commander stays home (docs/24; ruling 2026-09-02); his retreat must not
  end inside enemy influence (ISSUES army residues).
- Our commander's D-gun must not kill our own buildings behind the target.
- T1 attacking the base is the commander's to kill, cautious or hurt or not;
  his death is an accepted risk against losing the base (2026-09-20, docs/24).
  Built 09-20 in safety.as; unverified in a team game.

## Performance and the console

- No AI operation may pause the game (~1 s every 10 s was one 25 KB console
  line, fixed 09-12); the AI's log stays out of the in-game chat (done).
  Open until an hour-scale 8v8 shows no emergency collect.
- Hosting an 8v8 must not lag the host; budget 0.417 ms/AI/frame
  (`ai-performance`).

## Standing preferences and how he works

- Watching beats measuring: deploy and hand him a windowed run first, measure
  alongside. He does not need the noise floor re-explained.
- Fix mechanisms, not win rate; own regressions plainly; work through his
  whole list, not a few items.
- Validate outcomes (the structure, the metal, the mex), never log lines.
- He watches Greenest Fields 2v2/8v8 and Carrot/Isthmus 8v8; test games are
  1v1 on bigger maps. Multiplayer AIs carry a +50-100% bonus: watch runs at
  +50% both sides, batteries at +100% both sides. Same faction when he
  watches (Armada vs Cortex reads unequal to him).
- Match player count to map size (Comet Catcher is a 4v4 map).
- Deploys cannot run while BAR is open on his machine; local tests can.
- He reverts BEHAVIOURS freely, including ones he asked for, and keeps BUILD
  RULES (docs/30).
- Visualisation: what the AI believes, drawn as persistent lines on the map,
  never pings (the server drops >25 map-draws under 50 ms apart; the
  auto-eraser deletes marks after 60 s).
- Longer term: surprising strategies against humans, distinct personalities
  (rolled 09-12), cooperation between allied Apex AIs, water and mixed maps.
  Multiplayer is host-side only: no archive changes, no synced Lua.

## UNRESOLVED: WE DO NOT TAKE THE ECONOMY SERIOUSLY (2026-09-22)

Watching a 2v2 on Glitters: *"we're definitely not focusing on economy
enough... our kind of view is matching our opponent, but I'm watching this
stuff and I'm thinking to myself, no, we're just not even trying really. Like,
when you watch it, it looks like a player who doesn't care that much about
expanding their economy. They're not taking it seriously. And if you take it
seriously, you're going to do crazy phenomenal."*

He is describing something already in the numbers. Our standing extractors
over the game, his 2v2 regime, pooled by start box:

  minute        4     6     8    10    12    16
  left, us   7.01  7.18  7.58  7.87  7.32  7.44
  left, them 6.39  8.06  8.82  9.33  9.65  8.09
  right, us  5.48  4.81  4.54  4.61  4.04  3.38

We plateau at about seven and the right box goes BACKWARDS. BARb roughly
doubles. The opening gap is not the story -- the SLOPE is. We stop expanding
at minute 4 and never restart.

Consistent with it: over 20 games the market chose energy 1243 times against
metal/mex 263, and 56% of opening decisions never reach the priced draw at
all (hoists). docs/33's minute-4 programme measured the intercept; this is
the part nobody measured.

"Matching our opponent" is worth reading literally when looking for the
cause: several terms price against enemy strength rather than against our own
growth, and a target set by what they have cannot outgrow them.

### FUSIONS START SOON, ALONGSIDE THE MOHO WALK (2026-09-22)

*"I think we spend a long time walking all around the map to make as many T2
mexes as we can, while I applaud that effort. We also do need to get started
on making fusions. Pretty soon."*

The moho upgrades are RIGHT and stay. The fusion is not to be left until they
are done. Measured: our first T2 plant at minute 8.0 and our first fusion at
16.2, against BARb's 8.6 and 9.7.

This is the ruling `TUNE_T2_FUSION_PULL` was left off waiting for -- the pull
overrides a price (wind is not worse than fusion on energy-per-metal), and
whether to override it was his call. It is his answer: soon.

### AT T3, ALL RESOURCES TO THE BIG UNITS; REACTORS WITHOUT GAPS (2026-09-25)

Raised again (the "T1 lab makes only fodder past T2" rule above was unbuilt).
Once a gantry stands, the T1 lab makes only spam (Pawn, Tick, Grunt -- never
Thug or Mace) and the T2 labs only the tougher, bigger T2 units. Reactors:
several at once when we can afford them, and never a gap between one and the
next. Measured in his Cortex 2v2 on All That Glitters, minutes 20-38: equal
spend (1.33M each), theirs 664k in Juggernauts/Behemoths, ours spread over 20+
types with 367 Thugs; we never built a Juggernaut or a Behemoth (`:losing` read a
90-metal scratch as 0.9997); 11 afus to our 4; a 2.1-min reactor gap at 29.5
(three `hot-road` aborts tripped the 120 s backoff). Built 09-25, unverified:
`OutgrownAtT3`, the `RecordCount > 0` gate, `IncomeCoversReactors`,
`hot-road-leave`.

More anti-nukes: one per base, and the base had grown out from under it.
Measured the same game at minute 58: one each, never a second (no enemy silo
seen held the target at 1); 188k of our structure metal (19%) outside both
umbrellas -- 3 afus, 3 fusions, a gantry. Built 09-25, unverified: blind to
their silos, the count follows coverage (`UncoveredClusterM`, one more while
an uncovered cluster is worth more than an anti-nuke).

### THE COMMANDER: MID EARLY, HOME FROM T2, TURRETS NOT CHASES (2026-09-25)

His Red Comet 2v2: our commander walked 9,680 elmos in 8 minutes and ended
139 from where he started; the enemy held mid from minute 3. Rulings:
(1) the 09-02 "stays home" is a mid/late rule (T2+) -- early, the commander
leads to mid and stays well protected (unbuilt; open: with the army, or near it);
(2) commanders do not chase -- they are too slow; turrets counter raiders.
Built 09-25, unverified by him: a raid in our half no longer becomes "the enemy
centre" (`gFoeMid` falls back to `FoeAnchor`), and a group made entirely of
raiders/scouts is never his to walk at (artillery still is, per 09-20). Measured,
4 Red Comet 2v2 games each, first 8 min: engages 4 -> 0, walked 5,143 -> 4,336
per commander, reversals 23 -> 10. Still open: he took 2 turret jobs in 8 games,
so the turret answer to raiders is not there yet.

### TOO MUCH ARMY, BEHIND ON ECONOMY (2026-09-25)

His Koom Valley 8v8 (Armada, +100%): our army led theirs all game while they
put the difference into economy and pulled away -- minute 16: income 623 vs
1,343, eco 49k vs 101k, build power 46k vs 99k, army 155k vs 147k. Seven of
eight AIs spent 43-60% on army against 21-28% targets; the lab orders came from
the spare-metal floor (`src=rich`, 102 vs 0 from the target). One AI sat at
48 m/s with no T2 lab at minute 17 (army 49-65% of its spend from minute 6).
Ruling: spare metal goes to the economy while the enemy out-earns us; to army
only once we out-earn them (his 09-24 "no starved army when far richer" holds).
Built 09-25, unverified: `EcoBehind()` compares our team's structure metal with
the enemy's seen structure metal; `apex: ecoside` logs both every 30 s.

### NANO TURRETS WHILE OUT OF METAL (2026-09-26)

He sees more nano turrets ordered while the bank is empty, until there is no
room left -- not to be overturned, just not so much. Measured in his Omega 3v3:
with the bank under 5%, 35% of nano bids still went ahead, set by the factory
line's share of a raw one-tick "free metal" read (7.9 m/s median at a 23-metal
bank) while ~2 turrets of lathe stood idle. Built 09-26 in the lane, unverified by
him: the line/site/army terms are capped by the smoothed spare and netted of
idle lathe (the floor and fortification rulings untouched). Omega 3v3, 4 games
each: bids on an empty bank 35% -> 6%, nanos built 206 -> 143 per game (BARb
156-193).

### ALL-TERRAIN UNITS SQUAD APART (2026-09-26)

He sees Vanguards and other all-terrain units mostly walking the roads like
normal units. Cause: a squad's leader is its least mobile member and the squad
paths for the leader's move type, so a Vanguard beside a tank took the tank's
road. Ruling: all-terrain units never squad with units that cannot climb. Built
09-26 (C++ `ISquadTask::SameClimb`, used by attack, defend and rally admission
and so by merges; `apex: climb` logs each def's class once), unverified.

### TEN FUSIONS BEFORE THE FIRST ADVANCED FUSION (2026-09-26)

His Omega 3v3: 9-11 fusions per AI before any afus (ours first afus 33.6 min
or none by 36; BARb 24.7-27.9). The market prefers the afus (per metal 0.309 vs
0.233); the ETA pick overrides it for the fusion (per build time 0.0143 vs
0.0096) -- `eta-wins`. The afus blast is worse, but that does not explain ten.
Proposed, awaiting his go: the ETA override only while build power binds (metal
piling up); with the bank near empty the per-metal pick stands.

### BOMBERS, NOT ONLY GUNSHIPS (2026-09-26)

His Omega 3v3: we made hundreds of gunships and fighters and no bombers, where
bombers would have demolished their base and shortened the game. Gunships read
high on damage efficiency; bombers will not, and still fit their own role --
judge them separately. Also open: gunships rarely go for enemy economy or the
base itself. Found: bombers ARE priced apart (the wing prices structure damage),
but the one scored run -- 9 Phoenixes over an empty mirrored cell at 21 min,
42 metal per bomber -- replaced the model outright, so every later bomber read
42 against a 345 bar (`:wing0` on every air plant to minute 46, 1/143 bombers).
Built 09-26 in the lane, unverified: the first run blends with the model's
expectation at apex_air_obs_w instead of replacing it.

### THEY REACH T2 FIRST AND STAY AHEAD FOR A LONG TIME (2026-09-26)

Raised as his general read after several games: the enemy gets to T2 before us,
puts the rest into economy and stays ahead economically "for a long, long, long
time"; only if we survive very long does our economy pass theirs. Meanwhile we
keep making T1 units that trade horribly against their T2 -- roughly 10,000+
metal of T1 that sucks, where they built fewer, better units and banked the
difference into economy. Same root as the two entries above (army share far
over target, late T2 labs, few T2 constructors).

Raised again the same day, as a standing rule: at +100% (his regime) income is
so high that T2 comes quickly, so there is almost no window to use a T1 army --
only an all-in rush straight into their base could. Make far less T1 army and
get to T2 fast. Measured: our median first T2 lab 3-5 min after theirs in team
games, 14k-56k of T1 army bought in that gap. Built 09-26 in the lane: before
an AI owns a T2 lab, spare metal is not army (base coverage still is).

### UNRESOLVED: WE BUILD THINGS WE DO NOT WANT THE OUTPUT OF (2026-09-22)

*"If I was to sum it up -- we're like a crazy cancer virus that spreads all
around the map but we lack any good organization to do this craziness
efficiently."*

Four behaviours he called toxic, watching with extra units and scavenger
units for players turned on:

1. **A plant is built and then nothing is made from it.** He watched an
   Experimental Aircraft Plant go up and sit. A plant should only be built if
   we genuinely want one of the units it can produce; if we do not want the
   output, we do not want the plant.
2. **Fusion straight to Epic Fusion Reactor, skipping AFUS.** The Epic takes
   far too long. AFUS first -- and the algorithm has to choose that ITSELF,
   not be told. His suggested instrument: a script that shows, at income N,
   what eco we would build.
3. **Hovers, almost every game**, including maps with no water and well past
   T2. Hovers are T1; unless it is a deliberate water move they are not worth
   it.
4. **Still far too much build power**, and often placed outside the range of
   anything it could serve.

All four are the same shape: we buy capacity without wanting what the
capacity produces, and we buy it where it cannot be used. `nanoblob.py` found
14 turrets 2,937 elmo from any plant; this is that, generalised.

Also his read on the budget lever deployed 2026-09-22: "that balancing isn't
really working." Unresolved -- the A/B was still running when he said it.

5. **T1 construction turrets are never treated as obsolete.** Once T2
   construction turrets are available the ground is better spent on those.
   (2026-09-22. The "obsolete on arrival" machinery already exists for the
   GENERATOR ladder -- `DefObsoleteOnArrival`, gate check `def.obsolete` --
   and is not applied to nanos.)
