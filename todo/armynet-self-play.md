# Army model: learn from our own games (11-25)

11-25: days of work without a better model; he approved learning from our own games. Since 11-24 no model beat the one he plays (enemy1 model-010000): every change was judged on
BARb gates or imitation loss, and the judge model that won its BARb test lost head-to-head, out-traded 5/5.

## The one measure
A candidate is better only if it beats the champion head-to-head: Red Comet 1v1, both +50, same AI both sides, sides
swapped each seed, **20 games, >= 60% wins**, read per side with `tools/armynet/h2h_report.py` (trade at 8/12/20,
army in their half, buildings killed, commander deaths). BARb and his games are sanity checks, never the yardstick.

## The loop (one round ~2-3 h)
1. **Play**: champion vs itself and vs the pool, with exploration (place sampled at a temperature, the judge's top-k
   picked at random 1 time in 5), so the games hold decisions the champion would not make.
2. **Record**: every served decision with its inputs, written by serve.py, plus the game's outcomes (the existing
   per-decision rating: trade at 10/60/180 s against the side's other orders in the same window).
3. **Train**: fine-tune the champion on these games, decisions weighted by how they turned out (better than the
   side's average up, clearly bad down), mixed with player replays so it stays grounded. The judge head learns from
   the explored decisions, so it finally sees places players did not choose.
4. **Gate**: candidate vs champion, 20 games. Promote at >= 60%; keep every past champion in the pool, and a new one
   must also beat the pool (no rock-paper-scissors cycles).

## Build order (runs on the Mac from 11-25; the PC stays free for his games)
- [ ] Head-to-head on the Mac: both sides on the model, 3-4 games at once; a ladder file with every result; an A/A
      (enemy1 vs enemy1, 6 seeds) first for the noise of every h2h_report number.
- [x] Recording: already built (11-20/21). run_match `--replay` keeps the demo; replay_orders.py `one` makes
      orders.txt; the dataset is built with BARAI_ALL_TEAMS=1 under a folder named `own-games`, where data.py learns
      every side with the usual ratings (f_raw, f_neg, idle cost). No serve `--record` needed.
- [x] serve.py `--explore T` (`--explore-p` 0.2, `--explore-k` 8): a share of force-steps take a place sampled
      at temperature T among the head's top K; minute line "explore: ...". Self-play only, never his games.
- [ ] train.py from the champion: `--own <own-games> --own-share` exists. Was tried 11-21 (own-a..own-d) on our
      games vs BARb with no exploration, judged by BARb gates: failed (own-c lost more commanders). New now: the
      games are self-play with exploration, the judge head learns the explored places, h2h is the gate.
- [ ] The loop runner: play -> record -> train -> gate -> promote, one round at a time, logged in results/armynet/.
- [ ] After two promoted rounds: the breakthrough as a candidate action (push into a line we just broke),
      judged by a head trained on self-play outcomes.

## Alongside
- One close game review a day with his commentary (the method that worked).
- Each round reported plainly: champion unchanged = "no improvement".

## His 11-26 notes on how a force's place is chosen (to test as serve settings, no retraining)
- In a fight a strong player orders each unit several times a second, early game most of all; less late game. Our
  fight orders are per force at the force click rate. Test `--unit-contact` (units within 600 of a visible enemy
  follow the unit heads every step) head-to-head.
- `--arc` spreads armed units on range arcs: where to stand in a fight should be the model's, which learned from
  players when to stand off and when to dive in and accept damage (an overwhelming army flooding their base). Test
  arc off head-to-head.
- No zigzag: the random back / hold / forward band draw can flip a force between bands each decision. Test
  `--commit` (keep the current order while its place rates close to the best) or the plain best cell.
- The 64x64 grid worries him on big maps; check place quality on a big map before relying on it.
- Flank / intercept is a big gap. The model does see enemy movement (each enemy token carries position and
  velocity), so it can see an army coming; whether it reacts is learned. Self-play with outcome weighting is the
  first fix; if rounds 3-4 do not move it, a hindsight teacher on our own games: where the enemy group struck in the
  next 60 s, as the place for our forces that were elsewhere.

## The rating redesign (11-26: the per-decision rating ran against winning, 12 of 64)
Score a move on what wins, both ways:
- Gained: map control / territory taken near the target, their economy destroyed, their army killed where it matters.
- Not lost (his 11-26): our economy damage prevented and our territory loss prevented. "Prevented" needs a baseline,
  read from what a player could see then: enemy armed metal heading for our buildings that died or turned back
  before doing damage; our buildings within enemy reach that still stand at the horizon; ground we held near the
  target over the horizon against ground lost.
- Check before training on it: across our own games, the side with the better mean rating must be the side that won
  (the old one: 19%).
