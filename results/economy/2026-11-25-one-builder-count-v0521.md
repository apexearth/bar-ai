# One builder count, on v0.5.21 (Mac, 6+6 games)

**Purpose:** in his 11-25 full-tech games every seat led with air plants that mostly built constructors. Cause: once
a plant offered flying constructors, the builder counts (ConsOwnedAny, ConsInFlightAny, CeilingConsOwned,
CeilingConsInFlight) counted flyers only, so the air plant refilled the seat's whole builder quota while 10-27
ground constructors stood. His ruling 11-25: one count for every builder; the kind of a new one by build power per
metal with the walk taken out (HandValue/HandBest); the fixed ten-air-con floor removed.
Patch: henry-outbox/one-con-count.patch (production.as; 14 hunks applied to v0.5.21 with offsets only).

**Settings:** full tech, Carrot Mountains 4v4, Apex v0.5.21 vs BARb hard +100, 25 min, speed 20, seeds 1-6 per arm,
Mac v0.5.21 dylib (base 0ef36267 + v0.5.21-cpp.patch + ArmyNetBridge.inc + arm64 fixes). Patched scripts a3692d3cfd49,
current 703fe232d5e5, 0 AS errors.

| | patched | current |
|---|---|---|
| W/T/L | 0/5/1 | 0/3/3 |
| air cons built | T1 22 + T2 1 | T1 171 + T2 2 |
| air-plant con orders | con floor 21, priced 4, t2 floor 1 | con floor 178, t1-air-con floor 17, t2 floor 2, other 1 |
| air-plant output con/armed per game | 6/198, 0/51, 5/139, 1/60, 6/117, 5/46 | 44/45, 28/35, 23/13, 26/21, 28/52, 24/49 |
| T1 air plants per seat; seats with one | 1.42; 22/24 | 1.17; 21/24 |
| first air plant, mean min (seats before 8 min) | 9.8 (12) | 10.3 (10) |
| T2 air plants | 1/24 seats | 10/24 seats |
| T2 land lab: seats, first minute | 20/24, 13.8 | 19/24, 12.4 |
| side armed ground metal 10/15/20 min | 5.5k / 12.9k / 12.5k | 7.2k / 12.0k / 9.1k |
| side builders standing 5/10/15 (air) | 19.8 / 42.8 / 63.2 (0 / 1.0 / 2.2) | 19.5 / 47.5 / 58.8 (0 / 5.0 / 5.5) |
| side metal income at 10 | 123 | 136 |
| side metal income at 20, per seed | 159: 269/105/245/109/146/81 | 83: 106/21/75/24/184/89 |

cfHand (floor asks left to a plant with a better hand), seats summed per game: 39/26/31/17/44/20.

**Verdict:** the change hits its aim. The air-con sink is gone (171 -> 22 T1 air cons), the air plants make armed
planes, income at 20 nearly doubles (4 of 6 seeds higher), the 20-min ground army is up 37%, 1 loss vs 3. Not fixed:
the early air plant itself (9.8 min, half the seats before 8 min) and a T2 land lab 1.4 min later. Ground army at 10
is lower (5.5k vs 7.2k). Kept in source; seeds 7-12 running to firm it up, and the air plant's purchase traced.

## 12 seeds (Mac, seeds 7-12 added; henry-inbox/onecon-seeds7-12.txt)
W/T/L 0/10/2 vs 0/6/6; paired by seed patched better in 5, worse in 1. T1 air cons 68 vs 330. T2 air plants 4/48
seats vs 17/48. T2 land lab 40/48 vs 36/48 seats, done 13.3 vs 12.3 min. Side ground army 10/15/20: 5.9/12.0/11.7k vs
7.2/12.3/10.5k. Income at 20: 125 vs 93, higher in 7/12. The losses hold (2 vs 6); the income gain is on average
only. The later T2 lab is fewer hands at its site (3-5 fewer builders standing at 10 min), not a later decision
(ordered 9.1 vs 9.7 min; henry-inbox/airplant-trace.txt).

The early air plant (40 seats, mean 8.8 min, 19 before 8 min) is a plain market draw (why=draw 37), at a median 3.6x
its runner-up. Before 8 min its air yield is led by the look (the air scout's worth, mean 9.0) and strike (3.3);
after 8 min by strike (9.0). Current v0.5.21 has the same shape.

## Air vs ground spend, same 24 games (Mac, BARAI_PROD finished units by metal; vendor/v0521/air-spend.txt)
No seat is air-primary in either arm: armed air > armed ground at 15 min 0/48 (current) and 3/48 (patched), at 25 min
1/48 and 2/48; counting constructors 0-1/48. Per-seat means at 10/15/20/25, current then patched: armed air
79/506/938/1132 and 305/1125/2182/2848; armed ground 2003/4383/6645/7626 and 1679/4207/6847/8675; air cons
154/444/707/791 and 14/103/146/188; ground cons 1322/2731/3951/4277 and 1362/2633/3925/4796. Side totals at 25:
armed air 4.5k vs 11.4k, armed ground 30.5k vs 34.7k. The fix turns air-con metal into armed air (2.5x) and ground
spend also rises. His air-primary 4v3 (Otago, drones + build turret lobby) is not reproduced on Carrot without them.
