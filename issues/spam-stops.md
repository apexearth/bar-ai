# Spam stops (or never starts)

Reported 11-25: spam stops partway through a game; seen in the eco test and noted by other players.

## How it works now
`Market::SpamLineDef` (production.as) and `Military::SpamSend` (hooks.as): in the spam phase the seat's FIRST T1 land
plant (lowest unit id) makes its fastest fodder per metal, and each one gets one move order at their base.

## What the logs show
- **T1-only games never spam.** The spam phase is `Factory::gHaveT2`, and the line also needs a T2 land plant
  (`TopOwnLandPlantTier() < 2`). Two v0.5.21 T1-only games of his: 0 spam-line / spam-send lines in all 20 seats. A tier
  special case (his ruling: no-tier-special-cases).
- **Spam ends when that one plant dies.** h2h-newcur s4/s5 (Red Comet 1v1, 30 min): the spam plant died at 22, 24, 26
  and 30 min. Sends then stop for good. No other T1 land plant stands past T2, and none is rebuilt.
- **The spam plant mostly makes other things.** Orders after the spam line started (scratchpad spamlab.py), 4 seats:
  rez bots 26/9/30/35 (the "rez bot or constructor keeps the order" exception), AA bots by the aa-threat hoist
  7/18/0/62, constructors 10/8/18/8. Spam sent over 9-14 min: 17, 35, 8, 3 units.
- The eco test had none because `EcoOnly()` turns spam off (his 11-22 ruling).

## Instruments
`apex: spam-line`, `apex: spam-send ... sent=` (once a minute while sending); scratchpad spamlong.py (send minutes,
last send vs plant death), spamlab.py (what the spam plant ordered).
