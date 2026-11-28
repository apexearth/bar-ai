# H, second arm: G1 (the memory-fix model + E3's flags) head-to-head against enemy1 as he plays it

Plan: `todo/armynet-objectives.md`, the Fable session's H (11-27). Setup as
[H's first arm](2026-11-27-head-to-head-H2.md) (`tools/armynet/model_vs_model.sh`, Red Comet 1v1, both +50, 40 min,
speed 4, same faction both sides, the candidate's team by seed parity, both teams served, replays built in
`runtime/armynet/own-games/mvm-h1`).
- **Candidate**: enemy1-absent (md5 2c0819b4), `BARAI_ABSENT=1`, his flags + `--cluster-fight --force-idle
  --hybrid-cluster` (E3: a ground unit at a live known cluster goes to the AI's own attack until no building is in
  view).
- **Played**: enemy1 model-010000, `BARAI_ABSENT=0`, his online flags (`--forces --learned --rally --arc --fbias -0.19`).

Both servers ran the whole of every game; no errors in any log.

## Results (candidate side)

| seed | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | W / L / cap |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| G1 vs enemy1 | **W** 16.8 | **W** 28.2 | **W** 34.5 | **W** 22.6 | ahead | **W** 34.9 | **W** 26.1 | behind | ahead | behind | **W** 30.3 | L 36.8 | **7 / 1 / 2 ahead, 2 behind** |
| G2 vs enemy1 (first arm) | W | W | behind | ahead | W | W | L | L | behind | L | W | ahead | 5 / 3 / 2 ahead, 2 behind |

Nine of 12 won or ahead at the cap for G1, against seven for G2. Seed by seed G1 did better than G2 on 6 (3, 4, 7,
9, and 8 and 10 as a cap behind against a loss) and worse on 2 (5, a cap ahead against a win; 12).

## The tables (candidate / played, same games)

| | G1 candidate | enemy1 played | (G2 candidate, first arm) |
|---|---|---|---|
| **building metal killed per 1,000 army metal-min at a live cluster** | **817** | 348 | 792 |
| **lost per killed there** | **0.90** | 2.56 | 1.91 |
| standing order there move / attack / fight | .37 / .51 / .07 | .54 / .39 / .02 | .33 / .53 / .10 |
| orders per unit-minute there | 17.5 | 30.4 | 15.1 |
| stints cleared / left / died / open | .22 / .26 / .49 / .04 | .12 / .25 / .61 / .03 | .15 / .15 / .63 / .07 |
| after clearing: none | .521 | .521 | .367 |
| after clearing: deeper / sideways / back | .28 / .13 / .07 | .32 / .07 / .09 | .46 / .11 / .06 |
| at a known cluster / of it ghosts | .436 / .625 | .398 / .584 | .413 / .722 |
| **in their half, units 5-15 / 15-25 / 25+ min** | .23 / **.33** / .23 | .22 / .18 / .15 | .26 / .23 / .28 |
| idle at its target | .299 | .269 | .269 |
| funnel arrived | .711 | .651 | .638 |
| middle extractors held, ours / theirs at 6 / 9 / 12 min | 0.8 / 1.1, 1.4 / 2.2, 3.1 / 3.2 | 1.1 / 0.8, 2.2 / 1.4, 3.2 / 3.1 | 3.7 / 3.1 at 12 |
| army metal-time at 4-12 near our held / empty middle spots | .115 / .338 | .094 / .314 | .084 / .299 |
| **raids into the middle matched / within 60 s / open at 12** | **.76** / .55 / .07 (29) | .50 / .37 / .17 (30) | .64 / .40 / .12 (25) |
| middle extractors / builders lost before 12 min, alone | 36 .17 / 41 .12 | 44 .16 / 44 .11 | 26 .12 / 23 .22 |

## Trade over time (mean per game still running; `tools/armynet/trade_by_minute.py`)

| minutes | games | candidate mobile lost / killed / buildings killed | played mobile lost / killed / buildings killed |
|---|---|---|---|
| 0-4 | 12 | 30 / 33 / 58 | 33 / 30 / 101 |
| 4-8 | 12 | 292 / 400 / 263 | 400 / 292 / 281 |
| 8-12 | 12 | 2,429 / 2,995 / 964 | 2,995 / 2,429 / 940 |
| 12-16 | 12 | 5,297 / 6,095 / 3,215 | 6,095 / 5,297 / 1,710 |
| 16-20 | 12 | 6,094 / 5,966 / 3,858 | 5,966 / 6,094 / 2,547 |
| 20-24 | 11 | 9,684 / 8,697 / 6,739 | 8,697 / 9,684 / 3,698 |
| 24-28 | 10 | 13,837 / 15,569 / 12,487 | 15,569 / 13,837 / 6,720 |
| 28-32 | 9 | 20,126 / 17,736 / 12,015 | 17,736 / 20,126 / 7,815 |
| 32-36 | 7 | 22,415 / 30,778 / 34,134 | 30,778 / 22,415 / 16,638 |
| 36-40 | 5 | 19,385 / 18,799 / 10,569 | 18,799 / 19,385 / 7,328 |
| running sum to 40 | | 99,590 / 107,070 / **84,302** | 107,070 / 99,590 / 47,777 |

## Read

1. **G1 beat what he played 7-1 (caps 2-2), the strongest head-to-head so far** (G2 5-3). It wins the army trade
   early (8-16 min: killed 9,090 for 7,726 lost) and kills buildings at 1.8 times the played model's rate by 40 min
   (84,302 vs 47,777), trading 0.90 lost per building metal killed at a live cluster against the played model's 2.56.
2. **It also answers raids into the middle:** matched .76 (the rules army's level against A was .74), against .50
   for the played model and .64 for G2 in its arm. Releasing units at a cluster to the AI's own attack frees the
   rest of the army to come back.
3. It stands forward mid-game (their half .33 at 15-25 min vs .18), not late; the middle extractors are level with
   the played model (3.1 vs 3.2 at 12).
4. **He now plays G2.** By the keep rule G1 has to beat G2 head-to-head, not enemy1. Against the rules army G1
   traded better than G2 (live-cluster kill 651 vs 440, lost per killed 0.79 vs 1.34) and G2 stood further forward
   with more middle extractors; results 4-8 vs 4-6 with 2 ahead. E3 also hands units at a cluster to the AI's own
   fight logic, which v0.6.00 is meant to replace: whether that is acceptable is his call through the Fable session.

<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "H, second arm: G1 (memory-fix model + E3 flags) head-to-head vs enemy1 as played", "games": 12, "W": 7, "L": 1, "w": 2, "l": 2, "verdict": "Candidate side counted: 7-1, caps 2 ahead / 2 behind (G2's arm 5-3). Buildings killed 84,302 vs 47,777 by 40 min; lost per killed at a live cluster 0.90 vs 2.56; raids into the middle matched .76 vs .50; their half .33 vs .18 at 15-25 min. He plays G2 now: G1 must beat G2 head-to-head to be kept."} -->
