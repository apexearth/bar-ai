# At the unit cap, the slots are fighters and boats, and the ground army is gone

His 11-25 hosted game (Hellas Basin, v0.5.20, 6 Apex seats): an AI ran out of units at the cap (800 in that game),
the slots full of fighters and boats, so it had no ground army and was killed on land easily.

## What the AI knows today

- `market/upkeep.as` (`TUNE_UNIT_UPKEEP` = 1) prices a mobile body's slot as
  `lag * (team mobile metal / team mobile bodies) / (1 - team bodies / team cap)`. It is zero while the game runs at
  its set speed, counts mobile bodies only (buildings take cap slots too), and the cap is the lobby's `maxunits`
  modoption (2000 when absent), not the limit the dynamic-maxunits gadget sets for each player.
- So at full speed nothing tells production that the last slots should go to what the seat lacks (here a ground
  army) rather than to cheap fighters and hulls; slots are spent per metal, not per slot.
- Live upkeep-stat in this game: lag 0.33, speed 0.63-0.65 at 39-40 min; mobile bodies per seat at most 378 (t21 at
  15 min), so the 800 counts buildings, or the seat was another.

## Next (after his games; the replay needs an engine)

1. Record the replay; per Apex seat, units over time by class (buildings, ground army, air, boats, builders) and
   when each hit its limit (the dynamic-maxunits gadget's per-team value).
2. A `tools/contract.py` check in his words: a seat at its unit cap holds a ground army (ground army share of its
   slots at the cap, ours against the release seats).
3. The fix in pricing: the real per-seat limit (all units, the gadget's value) in the slot price, so a slot's price
   rises with scarcity at any game speed, and a want is worth its value per slot near the cap.

## His follow-up (11-25): "they just stopped making certain things eventually, we should prevent this"

Live prodrank/facqueue at ~40 min, same game:
- t16 (eco seat): air plant ranks nothing (every army type `ecoseat`-excluded) while its army target reads 107k
  against 0.7k standing; 88 constructors; facqueue `idle ... nothing ordered: no-candidate`.
- t14: an air plant and a shipyard only; army value (64-68k, boats and air) meets the army target, so gap 0 and no
  ground unit is asked for: the target does not ask what KIND of army stands.
- t21: moved to a hover plant (corfhp) with gap 0 as its target fell from 132k to 49k.
Next: per seat, what each factory built per 5 minutes by class from the replay, then a contract check (a seat with a
land front keeps a ground army) before any fix.

## Cause found (11-25), his "the target is always a spend %"

The army target is the spend ruling (ArmyTargetFull = army standing + military flow x fill), but the navy split in
production.as multiplied that WHOLE target by the navy share: a yard's target = 75% of (all army standing + flow)
(NavyShare 0.75 while we hold no water), a land plant's = 25% of it against its own standing army. With a big land and
air army the land lines read gap <= 0 and stopped, and the yards kept building to 75% of everything: hulls to the
cap. WaterArmyGap and the blind sub budget had the same form. Fixed in Unstable (not deployed, not measured): each side
keeps what stands and takes its share of the flow still owed. Measure on a water map with navy (Hellas Basin-like,
mixed land/sea): land plants' idle minutes at gap 0, ground army metal at 30/40 min, navy share of army, unit count.

## His 11-25 (Carrot Mountains, T1 only): late in the game our AIs went to air and made no new ground army

Hellas Basin logs (his-games/1125-0034-hellas) show the same: the land labs are gone mid-game and never replaced.
t15: armlab #6420 produced until 14.5 min, then the seat has one line (armap #380) to the end; its plant decisions
price only a copy of the air plant or a nano (`plant-choice t=15 armap ... gNano gCopy`, `plantdup armap ...
forwarded-to-nano`). Ranked factories after ~25 min, every seat: air plants and yards (t14 corap/corsy, t15 armap,
t16 armap, t17 corap after its corlab at 27.9 min, t20 armap/armsy, t21 corap/corsy then corfhp). Also 22 lines of
`adv-plant defer ... an advanced plant is already in flight:` with an empty name on t15 in a game with no T2.
Next: from the replay, when and how each seat's land labs died (killed or reclaimed) and what plant was built after;
a contract check "a seat that loses its land lab with a land front rebuilds one".

## Fixes built 11-25 (Unstable; not measured; henry-outbox/t1-ground-army.patch for the Mac A/B)

1. Navy split on the flow only (production.as, army.as WaterArmyGap, the blind sub budget).
2. A lobby "Disable Tech 2/3" is read (persona_style.as T2Disabled/TechModBlocked): no T2 lab elections (Carrot T1:
   tech:legalab 84, armalab 41, coralab 41, legaap 44), and spare metal is not held for a T2 lab (production.as).
3. The eco seat's wasted metal goes to army while it grows (production.as "ecowaste", ecoseat.as EcoSeatFacKeeps):
   Hellas t16 sat at P 430-490 under its 500 target for 25 min, bank 2,000, army 0.
4. No land plant standing: a new land lab's production half is not capped at the metal the air plants spend
   (want_plant.as prodTermLand; the mirror of his 11-05 air-plant rule).
Plus the plant-any defer line now names the plant in flight (want_super.as).

## Navy flow split: MEASURED LOSER, reverted (11-25)

Mac A/B, Hellas Basin 1v1 vs BARb hard, 40 min, seeds 1-8: off 4W/2L/2T, on 1W/7L; our commander dead in 7/8 on vs
2/8 off. The symptom moved (land prodrank gap<=0 75% -> 48%, land idle lines 181 -> 44) but at 30 min on held ground
4.3k / navy 13.0k / air 2.2k and 117 units vs off 17.3k / 25.1k / 3.7k and 367; the opening moved from a hover plant
(8/8) to a vehicle plant (4/8 on), so the old split carried the water strategy those games depend on. The cap issue
needs a different fix: slot pricing at the real cap, not the target split.

## Replays of his T1-only games (11-25 04:40): the land lab dies and is never rebuilt
Recorded replays (G:/bar-ai-archive/replay-orders), our seats' plants finished (F) and lost (X) by minute:
Carrot 08-38, 10 AI seats: 8 lost their only land lab at minute 11-12; one rebuilt it (lost again a minute later);
after it every plant bought was a T1 air plant (2-7 a seat). Hellas 07-38: land labs lost at 11-15, one rebuilt at 22
(lost at 23); the rest of the spend went to air plants and shipyards. Army metal finished, our side vs the humans:
Carrot 08-38 ground 71% -> 38% -> 31% by 10-minute window (humans 85/63/97%); Hellas ground 41% -> 20% -> 4% -> 6%
(humans 70-84%); Carrot 07-17 56% -> 36%. Games with T2 kept 54-94% ground. So "stops making ground" is a lost lab
that is not replaced, not a preference: the land copy is priced only while a land line works (PlantChoiceMul), and
with no land line its production term was capped at spare metal (the v3 patch lifts that cap). Contract check
`minutes without a land lab` (tools/contract.py) added; the Mac Carrot 6v6 T1-only A/B reports it on both arms.
Readers: scratchpad army_mix.py and plants.py (one-off).

## v3 measured (11-25 05:00): reverted
Carrot 6v6 notech2 vs BARb, seeds 1-4: ground army at 30 min 52.5k -> 37.7k, enemy commanders killed 21 -> 9; no land
lab died in either arm. Reverted; the Mac bisects the T2-election filter (A) and the spare-metal / eco-seat hunks (B).
The land-rebuild hunk needs games where a land lab dies (his games, or a harder opponent).

## Real cause of the T1-only ground collapse (11-25 08:50)
Late-game PC test (Carrot 4v4 notech2, BARb hard +100, us +0, seeds 1-4) reproduced it in both arms: our ground/air
at 40 min 3.4k/15.4k, 3.9k/23.6k (off), 2.6k/12.4k (v3); v3 did not fix it. With the plant candidate log on, the land
lab never reached pricing late. ProposePlant's "ONE T1 LINE UNTIL T2" (his 10-03) skips every second T1 plant until we
own an advanced plant, except the air lead's air line. With T2 disabled that day never comes: the air lead kept buying
T1 air plants (7 by minute 30 on one seat, "draw over nothing"), no seat was offered a second land lab, and a seat that
lost its land lab while an air plant stood was never offered a new one (gFacUnits > 0), which is why v3's rebuild hunk
could not work. v4 = v3 + `&& !T2Disabled()` on that rule (henry-outbox/t1-ground-army-v4.patch); a second T1 plant is
then priced by the market like any copy (PlantChoiceMul against nanos). Under test, late-game setup, seeds 1-4.

## T1-only: no energy converters late (his 11-25, a sent replay: Apex v0.5.18, notech2, 44 min, two seats with none)
Cause: the catalog counts units the lobby disabled as buildable. BAR's unit_restrictions_* set only
customparams.modoption_blocked, which the script cannot read, so the disabled T2 converter (37.5 e/s per cell against
the basic's 7.8, 4.8x, over apex_obsolete_ratio 4) made the basic converter "obsolete on arrival" for the whole game. Its
output then counts zero in the plot reclaim (ProposeReclaimObsolete / PlotVictim), the seat reclaims one, NoteDefRetired
latches it, and RetiredDefMul returns 0 for as long as it stays "obsolete": forever. Our T1-only test games: after a
seat's first converter reclaim it built 0, 0, 0, 0 and 1 more (5 seats). Fix (his idea, at the root): C++ CCircuitDef
reads customparams.modoption_blocked and sets maxThisUnit 0, so every blocked unit is unavailable to C++ and to the
script catalog (gAvailable = maxThisUnit > 0) -- converters, T2 labs, tech, every lobby restriction. Lane DLL built
11:09; test armk (T1-only late game, 8 seeds) vs the arme/armh off games. It supersedes the hand-written T2 filter.

## The builder-shortage signal counted orders past our front (11-25)
T1 late games (blk + step 1): after minute 20 the backlog behind BPGap held ~16 mex orders at a time, 91% never
started, 54% with no worker, 47% past our front (Builder::PastFront), and ExpectedLossAt read 0% for every row. BPGap
read them as a hands shortage and ProposePlant bought air plants for their constructors (the air plant's price was all
con half, prod 0). Fix under test: BacklogM skips never-started orders past our front (henry-outbox/backlog-front.patch).
Open, separate: ExpectedLossAt reads zero past our front, so every placement priced through it reads those sites safe.
