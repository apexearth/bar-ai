# Lost fights, out-ranged deaths, and how many have a correction we can compute

Plan: the Fable session (11-27), the lost-fight and out-ranged-death measures, and roadmap item 8(a): count per game
the cases with a correction computable from what the side could see. No new games: his watch game, mvr-g2, mvm-h2,
A-12 (mvr-a + mvr-g0) and 20 top-quartile winners' public games. Ground truth from the replays,
`tools/armynet/objectives_army.py` (new lines under "fights").
- **A fight** starts at a first contact (as on [fights in pieces](2026-11-27-fights-in-pieces.md)); its losses are
  the armed units of each side dying within 1,000 of that point in its 70 s. **Lost**: ours lost over theirs.
- **Entered outgunned, correction computable**: at first contact ours / theirs within 600 under 0.7, and our armed
  metal within 2,000 at least theirs within 600, so a larger force of ours stood near enough to join first, or the
  piece could have held for it.
- **Out-ranged death, correction computable**: one of our armed units died (its killer = the last unit to hit it, known
  for .95-.99 of the metal) when its weapon range was over its killer's by more than 50 and it stood within the
  killer's range + 50: the same move stopped at its own range.

## The table (per game unless marked)

| | his game: G2 | his game: rules | G2 vs rules | rules (same games) | G2 vs enemy1 | enemy1 played | A-12 model | A-12 rules | top players |
|---|---|---|---|---|---|---|---|---|---|
| fights with losses (all games) | 12 | 15 | 138 | 145 | 132 | 149 | 131 | 178 | 336 |
| lost of them | .67 | .73 | .43 | .52 | .55 | .46 | .59 | .47 | .51 |
| our metal lost in lost fights | 1,174 | 6,074 | 1,911 | 3,013 | 3,634 | 4,352 | 2,480 | 3,071 | 11,983 |
| fights entered outgunned | 3.0 | 8.0 | 4.8 | 4.6 | 4.3 | 5.8 | 5.8 | 4.4 | 5.5 |
| **of them with a join / hold correction** | 0.0 | 2.0 | **2.7** | 1.7 | **2.8** | 3.0 | 2.4 | 1.8 | 2.8 |
| **out-ranged deaths (correction: stop at own range)** | 25.0 | 24.0 | **16.0** | 17.7 | 23.6 | 22.3 | 16.9 | 17.7 | 6.2 |
| their share of our army metal lost | .16 | .08 | .11 | .13 | .09 | .12 | .15 | .14 | .21 |

## Read

1. **Corrections we can compute are few per game:** about 2-3 outgunned entries a game had a larger force of ours
   within 2,000 (every column, players included), and 16-25 out-ranged deaths a game (players 6). Item 8(a) has its
   material, a few dozen labelled cases a game, not thousands.
2. **Out-ranged deaths do not single out the model:** they are .09-.16 of our army metal lost for the models, .08-.14
   for the rules army and .21 for top players (fewer deaths, but costly units: artillery caught by what closed on
   it). As a correction it is sound; as a diagnosis of our losses it is not the lever.
3. **Lost fights:** G2 against the rules army loses fewer of its fights (.43 vs .52) and less metal in them; head-to-head
   it loses more (.55 vs .46). The late arrival (fights-in-pieces) is where it pays: the metal arriving after contact
   enters a fight already going.
4. A first count, not a filter: a "fight" here is ground truth around one first contact; overlapping fights share
   losses.

<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "Lost fights, out-ranged deaths, and the cases with a computable correction", "games": 57, "W": 10, "L": 21, "w": 4, "l": 2, "verdict": "No new games. Per game: 2-3 fights entered outgunned with a larger force of ours within 2,000 (every column, players too); 16-25 out-ranged deaths (players 6), .09-.16 of the models' army metal lost, .21 for top players. G2 loses .43 of its fights vs the rules army's .52; head-to-head .55 vs .46."} -->
