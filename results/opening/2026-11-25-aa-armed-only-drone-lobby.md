# AA counts armed enemy aircraft only, in a drone lobby (Mac, 4+4 games)

**Purpose:** issues/slow-opening.md. With assist drones on, the AA panic fired on the enemy's 1-metal unarmed drones
and an AA tower went up at 1-2 min. The change: `Military::UpdateAirThreat` counts armed enemy aircraft only
(henry-outbox/aa-armed-only.patch; the Mac renamed the loop count to nEnemy, no other change).

**Settings:** Red Comet Remake 1.8 1v1, Apex vs BARb hard, +50 both, 12 min, speed 20, seeds 1-4 (odd Cortex, even
Armada), `assistdronesenabled=enabled assistdronescount=3 assistdronesair=1 commanderbuildersenabled=enabled`, Mac
v0.5.18 + blk dylib. Current vs current + patch. All 8 compiled clean and ran to 12 min.

| per seat, seeds 1-4 | patched | current |
|---|---|---|
| AA PANIC lines | 0 / 0 / 0 / 0 | 1 / 1 / 1 / 1 (on 0-2 metal seen) |
| first AA order | 10.6 corerad, 10.6 armcir, 9.3 corerad, 9.5 armferret | 1.6 corrl, 1.4 armrl, 1.7 corrl, 1.2 armrl |
| mexes done by 3 min | 4 / 4 / 5 / 5 | 5 / 7 / 6 / 4 |
| metal income 5/8/10 min | 37/58/65, 30/70/71, 36/66/82, 37/71/65 | 25/73/78, 31/58/60, 37/69/67, 36/59/68 |
| mean income 5/8/10 | 35 / 66 / 71 | 32 / 65 / 68 |

All 8 games level at 12 min.

**Verdict:** the change hits its aim: no drone panic, the first AA comes at 9-11 min against real air instead of
1-2 min. The opening is no slower (income level or slightly up). Mexes by 3 min did not move, so the slow third mex
has another cause (the stall hoist; radar's 630 E), still open in issues/slow-opening.md. Kept in source.
