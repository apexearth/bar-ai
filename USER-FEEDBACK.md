# What apexearth wants and has not got yet

One entry per open ask: the ask (his words where they are the record), then its state. Deleted
when built and measured; a repeat means it is still open, so edit the line. The standing
principles behind these are in `docs/doctrine.md`; evidence and mechanisms in `ISSUES.md`; named
plays in `TODO.md`; the full older text is in git (`git log -p USER-FEEDBACK.md`).

## Unresolved, his headline complaints

- **We do not take the economy seriously** (09-22): *"it looks like a player who doesn't care that much about expanding their economy... if you take it seriously, you're going to do crazy phenomenal."* Our extractors plateau near seven from minute 4 while BARb's roughly double; the market chose energy 1,243 times to metal 263 over 20 games, and several terms price against enemy strength rather than our own growth. Open.
- **Too much army, behind on economy** (09-25, again 09-30): our army led all game while they put the difference into economy and pulled away (minute 16 income 623 vs 1,343). Ruling: spare metal goes to the economy while the enemy out-earns us, to army only once we out-earn them. `EcoBehind()` built; the split did not move (cover demand and the navy budget were the buyers). Open.
- **They reach T2 first and stay ahead "for a long, long, long time"** (09-26), while we make ~10k+ of T1 that trades horribly against their T2. At +100% there is almost no window for a T1 army: make far less of it and get to T2 fast. Built: before a T2 lab, spare metal is not army. Open.
- **We build things we do not want the output of** (09-22): *"we're like a crazy cancer virus that spreads all around the map but we lack any good organization."* A plant is built only for units we want from it; AFUS before the Epic reactor, chosen by the algorithm itself; no hovers unless it is a water move; far too much build power, often out of reach of anything; T1 construction turrets obsolete once T2 ones exist. Open.
- **Beat BARb stable hard reliably in his 2v2** (Glacier Pass, Armada both, +100% both, 0.2 lr boxes). Open; the 16-24 minute window is where it is lost.
- **Fusions start soon, alongside the moho walk** (09-22): *"we also do need to get started on making fusions. Pretty soon."* (`TUNE_T2_FUSION_PULL` waits on this.) Open.

## Economy and builders

- Upgrade the extractors first, ours and allies' (09-30): one T2 con stays on the fusion with T1 help, the rest upgrade every extractor, one hand each, each priced on its own walk and danger; give a T2 con to an ally with none. Built, unmeasured (`UpgradeHandsWant`, `UpgradesFirst`, `UpdateConGift`).
- An advanced lab goes near our extractors, not in the map corner (09-30). Built, unmeasured (`UpgradeAnchor`).
- Expansion: an unsafe mex is not refused, the constructor calls for support and builds it; under the constructor cap advanced hands come first (09-29). Investigate every cause of the stall. Open.
- Metal first, in his order: build the mexes, upgrade them, then protect them (09-20). The upgrade lost its elections to the role seat and the draw. Open.
- The eco seat runs on nano turrets, not constructors (~4 advanced land cons, ~10 T1 air cons, 5-6 advanced air cons); it opens an air plant. `expect.py` "eco seat hands are turrets" is RED. Open, partly his call (the T2-con floor at 1k income).
- 8v8 allies never scale (09-21): the seven non-seat players reach a third of BARb's income by minute 16. Open; the split between lab and eco hands is his to rule on.
- On big 8v8 maps he sees no eco player (09-20, again 10-15). `TUNE_ECO_SEAT_STRICT` off until an A/B.
- The front players of an 8v8 scale past one fusion (09-19). Open.
- At 1,000 m/s no basic converter; at 32k E/s with 5k pulled, advanced converters in numbers. Open until a watched game shows it.
- Idle factories must not exist while the bank is full; an idle gantry never justifies another (four reports). `RedrawFor` built 09-21 (empty lines 46% -> 22%); unverified by him.
- Air labs make longer queues so the line never runs out (09-21). Same fix; unverified.
- No nano turret while the bank is empty, "not so much" (09-20, 09-26): bids on an empty bank 35% -> 6%. Unverified by him.
- Ten fusions before the first advanced fusion (09-26, Omega 3v3). Proposed, awaiting his go: the ETA override only while build power binds.
- Reactors: several at once when affordable, never a gap between them (09-25). Built, unverified.
- At T3 all resources go to the big units: T1 labs make only spam (Pawn, Tick, Grunt), T2 labs only the bigger T2 units (09-25). Built (`OutgrownAtT3`), unverified.
- More anti-nukes as the base grows out from under one (09-25). Built (`UncoveredClusterM`), unverified.
- A dead mex is rebuilt quickly (six reports). Structural; a rebuild preemption would be a rule and needs his say.
- A T2 lab is built by many hands; is T2 at ~4 min and ~27 income what he wants? Gantry timing open.
- A T2 lab is not started while the front is being lost. Open.
- A pulsar alone at mid-map mexes with 79 nanos and nothing else: *"if you're gonna commit so goddamn hard, at least build more defensive turrets around there."* The guns of a second base where the economy commits are not built.
- Guarding a constructor ends when the job no longer needs the hands. Built 09-13/14, unverified.
- Constructors do not walk out alone onto ground where the last one died; lost mexes are not passively conceded. First half built; the army retaking the mexes is open.

## Base layout and defence

- Allies block each other's walkways: one lane system for the whole team (09-21). Built 10-08, unverified.
- Grid snapping, raised three times: same-size buildings line up exactly, nanos form blocks, tight packing with room only for units (09-16). Built (census 55% -> 100% aligned), unverified by him.
- Big builds go where the nano turrets are. Built, unverified.
- Factories to one side of an eco base; two or three bodies so one blast does not take everything. Not built.
- Dragon's teeth obsolete past ~100 m/s should be reclaimed. Not built (teeth are off at his call 10-14).
- The eco seat's guns stand inside its base with walk gaps; two gantries starve for nanos with a full bank; LRPCs belong on hills. Recorded, not built.
- Shields only where they can be shelled; one jammer per location (09-16). Built, unverified.
- We make far less defence than BARb and no LRPCs: *"we need to do better"* (09-20). Defence ~3x at 16-24 min after three fixes, still a third of BARb's share. Open.
- Outer mexes get guns; pushing our mexes must cost the enemy. Built 09-15, one seed.
- T2/T3 defence and jammers when the enemy closes on a T2 base: *"a life/death situation."* Open.
- Jammer logic *"still needs improvement"* (09-09), no detail: ask what he sees before changing anything.
- Flak spread round the base, not clustered at the nano block. Open.
- With most of the army away the base buys extra defence; army at home counts as cover. Built 09-20, nearly inert until the cover reach is his.
- Team games under scarcity: grow ballistic only when intelligent, concentrate spending, and *"understand our potential untapped mex economy."* Built 09-16 (in-flight cap from income), unverified.

## Army

- Multiple groups coordinate an attack, across allies too (10-07: six of ours probed a 37k tower line one 4k squad at a time). Team push built; the MASS vs NORMAL A/B is open.
- Break a defended line: mass T3, missiles, banked nukes together, LRPCs/Starfall, combined air and ground on one point, one shared gantry in an 8v8. Built as plan options; a gantry where nanos already stand is open.
- Games should END: decisiveness, sooner when possible.
- Reach units never arrive in numbers (0.04-0.07 of army metal against a 0.35 target); five pricing changes failed.
- Raids hit their energy first, then metal, then build power; scouts find it. The raid director finds a target in 1-3% of asks. Open.
- Bots almost always; on vehicle maps we underperform. Put the line's army worth where the opening plant and the T2 plant are chosen. Open.
- When an enemy outranges us with high dps, the T2 lab answers with longer range; the draw drew Sharpshooter 0 of 22. Sharpening it is his call.
- Fight orders are used too freely (08-31). Unattributed.
- Are we more cautious than BARb? Yes on `thr_mod` (neutral vs stock hard's 0.6-0.8 / 0.3-0.5); the JSON A/B is not run.
- Titans are never walked or parked home (built 09-20, unverified). His to rule: solo beeline, or the group together as BARb's (*"walk them through the ocean, come up the side and win"*).
- Escorts are for workers outside the base; late, cheap units die forward as spam; air cons get fighters. Built 09-13, not seen in a game of his.
- All-terrain units never squad with units that cannot climb (09-26). Built, unverified.

## Air and water

- Transports are good but not active enough (10-07): move busy nano turrets to higher-value work, carry groups past hard pathing. Drop fixes landed (61% -> 75%); moving busy turrets is open.
- Bombers, not only gunships (09-26): bombers would have demolished their base. The first scored run no longer replaces the model; unverified. Gunships rarely go for economy or the base.
- Air: be braver about the economy (09-30). Built, unmeasured.
- The seat, once military, sends devastating bombing raids; late game is LRPC and nukes. Open until a game of his shows a raid.
- A wave over the enemy base commits (09-20). Built in the DLL, unverified.
- Junos spread out like nukes (09-30). Built.
- On a small map where an LRPC reaches their base, build a ton of them (09-30). Built; artillery in the army is not.
- Composition follows where the enemy is: an enemy on water demands ships, seaplanes or advanced air. Not built.
- A naval player contests water mexes; the advanced construction sub never elects. Open.
- Legion in water made 90% constructors and rez subs. Partly fixed.

## Rez bots and the commander

- Wrecks on our side of a big map are an army: reclaim and resurrect them (10-04). Bots now leave base; residue in ISSUES.
- Rez bots 4-5 by minute 12, productive between jobs, behind our units. Residues in ISSUES.
- The commander: mid early with the army, well protected; home from T2; turrets, not chases (09-25). Chases fixed; the turret answer to raiders is not there yet.
- The commander's D-gun must not kill our own buildings behind the target.
- T1 attacking the base is the commander's to kill (09-20). Built, unverified in a team game.

## Performance

- No AI operation may pause the game; hosting an 8v8 must not lag the host (0.417 ms/AI/frame). Open until an hour-scale 8v8 shows no emergency collect.

## How he works

- Watching beats measuring: deploy and hand him a windowed run first, measure alongside.
- Fix mechanisms, not win rate; validate outcomes (the structure, the metal, the mex), never log lines; work through his whole list.
- He watches Greenest Fields 2v2/8v8 and Carrot/Isthmus 8v8, same faction both sides; match player count to map size.
- He reverts behaviours freely, including ones he asked for, and keeps build rules.
- Visualisation: what the AI believes, drawn as persistent lines on the map, never pings.
- Longer term: surprising strategies against humans, cooperation between allied Apex AIs, water and mixed maps. Multiplayer is host-side only.
