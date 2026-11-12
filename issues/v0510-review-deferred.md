# v0.5.10 pre-ship review: findings deferred to the next version

The third pre-ship review (11-12) found nothing blocking. Three findings were fixed before the gates: the retreating
commander's cloak, AA stepping by air range, and the mex-push fix limited to metal-field maps. The open race's end was
also fixed, after the gates showed zero opening fighters. It now ends once the raid is met, and for good past the
race horizon (900 s from the lab). A fourth review showed the "never more of ours than theirs" rule for emergency
nukes vetoed the strike his 08-21 ruling is about, an army inside our base. Our stake there outweighs their army, so
that change was reverted. These were left for the next version:

0. **Emergency nukes ignore our own losses entirely** (`nukes.as`, `TUNE_NUKE_EMERGENCY` 5000). Any defensive army
   worth 5k+ can be struck on top of our own mohos and towers. The right test weighs what the army would destroy if
   left alone, not only what the blast kills of it.

1. **Metal-field sites are not checked for metal** (`MetalManager.cpp` DetectMetalField, `want_mex.as`
   ProposeFieldMex). Any map over 20% metal coverage turns the spot path off and places every extractor like a
   converter, priced at the median spot. A partly metal map whose bases sit off the metal would build extractors
   that yield nothing. Fix: read the metal under the footprint (C++ binding) and skip a bare site.
2. **Readers of ArmyTargetFull grow with the bank** (`want_tech.as` tech funding; the `protect_field.as` and
   `protect_want.as` defence waves). The full target now includes spare×fill, so saving for a T2 lab raises the
   army it waits for. Fix: give these readers the share-only flow. (This was also deferred at review #2, together
   with T2DefenceArmy, decide.as's commander lab stint, rezPays, EvSeatCaution and the tower-wave prior.)
3. **The open race's "raid met" test counts only what is in view** (`openrace.as`, `A >= gSmhSeen`). The race
   ends once their raid is here and our team army stands at least the enemy army seen. A trickle of first raiders
   smaller than our army ends it, and then the rest arrive (11-12 arm510k t006: race over on 2 seats, 1.4k lost at
   home by minute 4). The race's own forecast (`gSmhArrive`) adds the enemy commander's strength times the number
   of foes. That would keep the race open long into a 4v4, which is his raider-spam game, so the fix needs a
   measured rule, not a swap.
4. **WalkingDrainM runs every frame** (`sites.as`). It walks every live task's crew. Refresh it about every 15
   frames.
5. **Field extractors share lattice ledger rows** (`census.as`). When one dies, the row is cleared while the
   others still stand. With FieldMexOn, keep every extractor in gFieldMexId and leave the ledger alone.

Answered, not changed: reclaiming duplicate T1 labs while the bank spills is intended. His 11-11 ruling:
"sometimes the space savings is worth the reclaim even if a bank spills".
