# What apexearth wants and has not got yet

One line per open item, as a statement of the mechanic or the ruling. An item
is deleted when it is built and measured -- never marked done. If he says a
thing again, edit the line; a repeat means it is still open. Mechanisms and
numbers live in `ISSUES.md`; named plays in `TODO.md`; fight doctrine in
`docs/24`; defence in `docs/32`; the economy frame in `docs/23`. Rulings on
defaults are in `docs/27` keyed by tunable. Rewritten 2026-09-15 from 1,665
lines of quotes.

## Economy and builders

- The eco seat should run on nano turrets, not constructors: about 4 advanced
  land cons, ~10 T1 air cons, 5-6 advanced air cons, and turrets for the rest.
  Today the seat's ~120 T2 cons come from the T2-con floor `2 + income/25`
  (his 2026-08-23 "at 100 m/s at least 5", scaled); `expect.py` "eco seat
  hands are turrets" is RED. Whether that floor is right at 1k income on a
  turret-ringed seat is his call (ISSUES BUILD POWER).
- Air constructors are how a rich base scales; the seat should open an air
  plant and build T1/advanced air cons. Con floors count flyers once a plant
  offers them, but the seat opened an air plant in one game of three.
- At 1,000 m/s no basic converter should be started; at 32k E/s income with
  5k pulled, advanced converters should be going up in numbers. Open until a
  watched game shows it (ISSUES CONVERTERS, GANTRIES).
- Idle factories must not exist while the bank is full; an idle gantry never
  justifies another. Fixes 09-13 did not close it: 09-16 Isthmus 8v8, ~10
  advanced air labs idle while half our metal went unspent. Third report
  (TODO "Never an idle factory"; ISSUES GANTRIES).
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

## Air

- The seat, once it turns military, makes a lot of air and sends devastating
  bombing raids; late game is LRPC and nukes, not more factories. Bomber
  bidding, cost-weighed wings and the hold-off removal landed 09-13/14 --
  open until a game of his shows a raid (ISSUES BOMBERS).
- No AI starts with an air lab (rate term prices it out; 12 openings all
  bot/vehicle -- hold).
- Air scouting coverage has never been measured against the threat readings
  it feeds.

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
