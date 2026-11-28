# Slow opening: AA and radar before the third mex

Reported 11-25: the opening is slow. AA and radar go up before the third mex, the lab comes first, and the
extractors a short walk away are not taken at once. His lobby has assist drones (3, flying) and the
commander build turret on (`assistdronesenabled`, `assistdronescount=3`, `commanderbuildersenabled`), so build power is
high and the 1,000 starting energy is gone in seconds. Our test games use neither option.

## Two v0.5.21 games of his, 20 seats (scratchpad opening.py over the apex-t*.log files)
- Mex orders by 3 min: 2-9, median 6.
- AA ordered at 47 s - 2 min in 17 of 20 seats, every one by the AA panic, on "seen 1 metal of enemy air". That
  is the enemy's assist drones: 1 metal each, unarmed. The panic fires on any seen air > 0.
- Radar ordered at 55 s - 2 min in 19 of 20 seats, by the plain draw.
- The stall hoist ran 4-14 times in the first 3 min per seat, mostly over a mex worth 10-50x more.
- Energy is the opening's limit: a mex costs 500 E, a radar 630, an AA tower 900, the lab 950. One radar and one AA
  tower cost the energy of three mexes.

## Done
- MEASURED, kept (results/opening/2026-11-25-aa-armed-only-drone-lobby.md: no panic, first AA 9-11 min instead of 1-2, income level): `Military::UpdateAirThreat` counts armed enemy aircraft only (flyer, mobile, not a builder, power > 1), read per
  unit from the enemy registry. It replaces the role subtraction (builders+scouts at 10%, capped), which also
  took their ground builders off the air count. SOFT_AIR_WEIGHT/SOFT_AIR_CAP deleted.
- Contract checks: "mex done by 3 min (neg)" and "AA panics on unarmed air".

## Next
- Test at his lobby settings (drones + build turret, Red Comet 1v1, +50): mexes by 3 min, first AA, income at 5/8/10,
  per side, before/after.
- Then the radar's energy price in the opening: does the draw charge 630 E at what energy is worth while it is the
  limit? The earlier "early radar hurts" tests had no drones, so drones do not explain them; the same energy cost could.

## The first 3 min, step by step (Mac, 8 drone-lobby games, the same in all 8)
1. The recorded opening order puts the lab first (over a mex at v=80); a drone takes mex 1 at 5 s.
2. The lab and mex 1 empty the 1,000 start bank by 20 s; energy stalls from 20 s to 60 s (90 s once).
3. The stall hoist then sends the commander to 3-4 solars between 12 s and 48 s, each over a mex valued 5-20x more
   (e.g. a solar at v=36 over a mex at v=470); the drones add 1-2 more. 43 such picks in 8 games.
4. Mex 2 is ordered at 21-27 s but, built in the stall, finishes at 54-121 s (96-121 s in 6 of 8).
5. The stall answer overshoots: the bank sits full and capped from about 75 s to 140 s in 7 of 8.
6. In that window the commander builds radar (70-93 s in 6 of 8). Radar's energy is not the problem (the bank stayed
   full); its time is: the commander's own first mex order comes at 99-168 s.
7. From about 105 s the cover-push hoist puts light towers over mexes (one at v=13 over a mex at v=1504).
Mex 3 finished at 64-148 s. The radar hypothesis is out; the three forced picks (opening order, stall hoist, cover
push) are what cost the extractors. Next: a test with each switched off by itself (henry-outbox/open-arm-*.patch),
drone and normal lobbies; each rule came from an earlier ruling of his, so the numbers go to him before any change.

## Measured 11-25
- Each forced pick off alone: results/opening/2026-11-25-opening-forced-picks-off.md.
- The opening counts the hands the lobby sends (lobby drones + build turret, re-decided if more arrive): KEPT,
  results/opening/2026-11-25-opening-counts-lobby-hands.md. Drone lobby income at 12: 73 -> 111, lab at 47 s; normal
  lobby unchanged.
- 8-seed confirmation: income at 12 in the drone lobby 67 -> 137, no losses. The stall hoist stays (off: no more income, worse trade). Open: the cover push.
