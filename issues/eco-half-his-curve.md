# Eco at half his curve (2026-10-22)

Target since 10-22: 750+ m/s at minute 20, reliably. His own +0 air game, replayed (matches/_replay-his0): 869 m/s
at 20:02, 4,100 at 30.

At +50 like for like (8 seeds, b50-base-s3100..3107): minute 4 we stand 11-13 extractors, 3-4 basic solars,
0 turrets to his 15 / 11 / 7; T2 at 8.0-9.3 to his 6; 0 mohos at minute 8 to his 6; 0-2 mohos and 8-23 turrets at
minute 10 to his 15 and 62; 531-879 m/s at minute 16 to his 1,570. Extractors are close throughout -- the gap is
energy and build power from minute 2 (his: "focusing too much on metal extractors, not enough on energy and build
power"). The T2 plant is built by one hand for ~220 s (seed 2913: ordered 4.0, standing 7.75, cap 11).

His replay against ours: level to minute 10 (we waste 14-18 m/s at minutes 6-8, he none); from minute 12 he
stops small eco at 53 extractors / 11 solars / 18 advanced solars and builds only mohos, AFUS, advanced converters
and turrets -- minute 20: 10 AFUS, 2 fusions, 48 converters, 238 turrets to our 0 / 12 / 6 / 141. Where the metal
goes (median of 24 base games): by minute 10 both made 23.3k; he spent 20.4k and wasted 0, we spent 16.0k and
wasted 3.8k (bank full from ~5.5 min). His T2 air plant at 8.34 (ours 9.25), a T2 constructor every ~18 s from
8.64 (ours every 24-36 s from 9.78): 8 mohos at 12 to our 2.

Run-to-run noise: identical settings and seeds read -20.4% and +6.3% (6 seeds). Score on the mean of minutes 16-20
over 24 paired seeds. Measured and removed (each moved its decision; none moved income; commit messages have the
detail): zone stack -16.8% (12; deleted, his rectangles are a UI aid); eco turret energy density +1.0% (12); bot
opening +0.3% (24); stall race counting energy payback ~0 (24); spend-capped ETA ladder with turret steps -10.7%
(24); forced canon pattern (solars only on short energy) stalled the economy; ETA energy output at the bills'
rate -4.9% (24); a big generator's crew from current capacity plus the room price -0.5% (24); a big generator
priced with its turret ring (fusion won 51/51); turret demand from the ladder's lathe/feed ratio -35.1% (24:
turrets at his count, but extractors 38 to 55 and mohos 6 to 20 at 16). The ladder's tBuild/tFeed reads 4-12x
all game because P counts unconverted energy as metal; it is not a turret signal as it stands. The C++ zone hooks
(ZoneRefuses, ReserveZone/ClearZones) are inert and left for the next DLL build to drop.
