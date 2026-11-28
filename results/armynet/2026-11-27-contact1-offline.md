# contact1: the model fine-tuned on the rules army's in-contact orders, with a target pointer (offline)

Plan: roadmap item 3 at the front (the Fable session 11-27, his ask: learn the small details of a fight from the AI's
own fight logic). No games. Data `tools/armynet/contact_data.py`; inventory [here](2026-11-27-contact-inventory.md).
- **contact1**: init C (enemy1-absent, md5 2c0819b4), `BARAI_ABSENT=1`, 3,000 steps OneCycle, batch 32, `--mirror --late
  --rounds`, player batches as C's recipe, plus in-contact batches at a 0.3 share: the rules sides of 14 sets (85
  games, 91 sides), labels at the AI's own order times, only armed units in contact as predictions, unit heads only.
  New head: the target pointer (`model.py t_query` over the embedded enemy tokens, 0 = none; c_tgt), alone for its
  first 300 steps.
- **control**: the same run with no in-contact batches (to tell the fine-tune's own drift from the data's).
- Held out: seeds 6 and 12 of every set (15 games), read with `tools/armynet/contact_bar.py`.

## The offline bar (15 held-out rules games, the same moments for every row)

| | most metal | weakest | nearest | pull-out: the order's place | pull-out: probability on away places |
|---|---|---|---|---|---|
| **rules army** (its labels; 485 attacks on a building with 2+ in reach, 42,011 in-contact orders) | .126 | .227 | .344 | .429 | |
| C (serve's rule: the visible enemy nearest the place) | .012 | .010 | .062 | .234 | .484 |
| **contact1 (the pointer)** | **.087** | **.171** | **.291** | .205 | .454 |

## Held-out player play (train.py's evaluation, the same games)

| | act log-loss | kind acc | force place error | unit place error | retreat recall | member acc | result acc | judge AUC |
|---|---|---|---|---|---|---|---|---|
| C | .317 | .950 | 384 | 413 | .359 | .844 | .680 | .621 |
| control (fine-tune, no in-contact) | .316 | .946 | 404 | 429 | .291 | .847 | .666 | .599 |
| contact1 | .343 | .949 | 404 | 436 | .297 | .846 | .681 | .657 |

## Read

1. **Target choice moved most of the way:** of the rules army's in-contact attacks on a building, contact1 picks
   the most valuable .087 and the weakest .171 (the rules army .126 / .227), from C's .012 / .010. Two thirds to three
   quarters of the way, not yet matching.
2. **Pull-out was never the gap offline:** C already puts .48 of its probability on places that pull away from their
   army, contact1 .45, against the rules army's .43 of orders. Its single best place pulls out less (.21-.23), and
   serve plays unit heads direction first by that mass, so in games the difference is whether the unit heads are
   asked in contact at all (`--unit-contact`), not what they know.
3. **The cost on player play is the fine-tune's, not the data's,** except one: the control drifts the same way (force
   place 404 vs 384, retreat recall .29 vs .36), and the in-contact data adds only a higher act log-loss (.343 vs
   .316). A lower rate or a shorter run is the fix if the games say it matters.
4. Next, in games (queued after his game, `runtime/armynet/queue_u.sh`): contact1 on G2's flags with
   `--unit-contact --pointer` in place of `--hybrid-cluster`, vs the rules army on the 12 seeds (set mvr-u1); seed 1
   plays alone first and the bridge cost of per-unit orders in contact is checked before the other 11. It has to
   match G1 there without the release. `--pointer` (serve.py): an attack goes to the visible enemy at the token the
   pointer picks, falling back to the nearest; counted per minute.

<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "contact1: fine-tuned on the rules army's in-contact orders, with a target pointer (offline)", "games": 0, "W": 0, "L": 0, "w": 0, "l": 0, "verdict": "No games. On 15 held-out rules games, the pointer picks the most valuable building .087 and the weakest .171 (rules army .126 / .227; C .012 / .010). Pull-out probability already at the rules army's level (C .48, contact1 .45, rules .43). Player-play cost is the fine-tune's own (control drifts alike); the in-contact data adds act log-loss .343 vs .316."} -->
