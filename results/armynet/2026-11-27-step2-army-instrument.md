# Step 2 instrument: what the army does with its orders (model / rules / players), offline

Plan: `todo/armynet-objectives.md` step 2 (11-27, led by the Fable session). Tool:
`tools/armynet/objectives_army.py` (the per-unit view; `objectives_offline.py` is the per-order view, superseded for
these questions). Reads the recorded games' unit samples (every unit every 10 frames with its standing command and
target), so the three columns are read the same way. Labels use the side's own view (data.Game memory); ground truth
only for ghosts, live clusters and kills. Cluster floor fixed at 2,000 metal (Otsu on log cluster metal: model 2,070,
players 1,310, rules 3,227).

Columns:
- **model**: 38 self-play games without exploration (aa1, gate1a/b, gate2a-d; model vs model, Red Comet 1v1 +50).
- **rules**: 6 games of v0.5.21 vs itself, army model off (matches/rules-r2-s1..6, Red Comet 1v1 +50, mirrored
  factions, 40 min, speed 20).
- **players**: 23 games, top-quartile skill, winning side (first 80 public recordings).

## Commitment: share of army metal-time, by standing order

| | cluster/base | lone bld | enemy army | own asset | other | idle at target | idle home | idle fwd |
|---|---|---|---|---|---|---|---|---|
| model | .247 | .073 | .045 | .050 | .019 | **.286** | .145 | .134 |
| rules | .272 | .073 | .060 | .099 | .047 | .231 | .182 | .037 |
| players | .254 | .111 | .095 | .043 | .105 | .122 | .219 | .051 |

Random-target baseline (`--shuffle`, same states): model cluster .165, own .126; rules cluster .208, own .153 (6 games). The
idle split does not change under shuffle (it is position, not target).

## Their half: why gate 1 said 0.15-0.25 and this said .476

Same units (the in-game army log and this tool both take armed mobile units). The gate pages count **units** over
**5-15 and 15-25 min**; the first read here weighed **metal** over the **whole game**. Late, heavy units stand
forward; early, cheap ones do not.

| | 5-15 units | 5-15 metal | 15-25 units | 15-25 metal | 25+ units | 25+ metal | all units | all metal |
|---|---|---|---|---|---|---|---|---|
| model | .253 | .228 | .364 | .415 | .433 | .515 | .377 | .476 |
| rules | .221 | .188 | .309 | .342 | .368 | .409 | .302 | .364 |
| players | .299 | .322 | .220 | .235 | .290 | .459 | .279 | .382 |

What a viewer sees as "the army" is closer to the unit count in a window; the metal share says where the weight
stands. Both belong on the page, per window.

## Ghosts: standing at a cluster with nothing alive there

| | at a known cluster (of metal-time) | of it with no living enemy building in reach |
|---|---|---|
| model | .485 | **.703** |
| rules | .368 | .547 |
| players | .190 | .437 |

**Cause found on the way (an input defect, not fixed: no model change yet):** both training (`data.py`
`Game._memory`) and the live server (`fold_history` / `history_rows`) remember every enemy building for the whole game
from its last sample, **including buildings the side watched die**. A player sees a building go when it dies in
view. So the model's own input can show a destroyed cluster as standing, and the army walks there and stands.
Proper fix (for when model changes open): forget a remembered building that vanished while in sight, and one whose
spot is inside our current sight with no sample there; same code in training and serve (parity.py proves it).

## Finishing: standing at a live enemy cluster

| | at a live cluster | bld metal killed per 1,000 army metal-min there | stints cleared / left / died / open | median to clear | after clearing: deeper / sideways / back / none |
|---|---|---|---|---|---|
| model | .144 | **396** | .204 / .346 / .359 / .091 | 10 s | .187 / .059 / .103 / **.651** |
| rules | .166 | **846** | .183 / .364 / .406 / .047 | 20 s | .361 / .066 / .209 / .364 |
| players | .107 | 475 | .096 / .305 / .560 / .039 | 10 s | **.563** / .057 / .007 / .373 |

**Order kinds at a live cluster (F, added 11-27 after the paired A/B page):** share of army metal-time there by
standing order, move / attack / fight / none, and the share with an enemy building inside true weapon range.

| | move | attack | fight | none | in weapon range | kill rate |
|---|---|---|---|---|---|---|
| model vs rules (A, model side) | .798 | .174 | .003 | .025 | .556 | 405 |
| rules vs model (A, rules side) | .410 | .386 | .131 | .073 | .516 | 1,253 |
| rules vs rules (6 games) | .459 | .373 | .099 | .068 | .533 | 846 |
| players, top-quartile winners (23) | .766 | .191 | .004 | .039 | .613 | 475 |
| players, all (80 games) | .797 | .074 | .037 | .092 | .619 | 669 |

Players stand at a live cluster under move orders as much as the model does, and still kill more there. The
attack-order habit is the rules army's, not the players'; imitating players will not teach it. A player's units on
a move order fire as they go; how often players re-click there is not read yet (11-24, vs BARb: 25 orders per
in-contact unit-minute for the rules army, 8.7 for the model).

## Funnel: orders aimed at enemy buildings or base, by mass

| | arrived | replaced fwd | sideways | back | died | stood | open | covered/asked | stood short |
|---|---|---|---|---|---|---|---|---|---|
| model | .640 | .199 | .020 | .015 | .040 | .062 | .024 | .32 | 1,013 |
| rules | .599 | .202 | .038 | .031 | .044 | .065 | .021 | .27 | 1,054 |
| players | .475 | .334 | .025 | .011 | .091 | .035 | .030 | .40 | 747 |

## Flips: direction reversals per unit-minute, metal-weighted, no new enemy in view

model .200, rules .284, players .152.

## Read

1. **Idle at its target is the model's gap.** .286 of model army metal-time stands where it was sent, against
   .231 rules and .122 players. Players keep orders live (other .105, army .095); the model's order ends and it stays.
2. **Ghosts.** At a known cluster the model stands on nothing alive .703 of the time (rules .547, players .437), and
   its own input remembers buildings it saw die (above). The two fit: it holds ground its memory says is a base.
3. **It finishes poorly.** At a live cluster the model kills 396 building metal per 1,000 army metal-minutes; rules
   846, players 475. After clearing, the model gives no order .651 (rules .364, players .373); players go deeper .563.
4. **Getting there is not the problem.** The model's orders at enemy buildings arrive .640 (rules .599, players
   .475) and it reverses direction least of the AIs (.200 vs rules .284).
5. **Caveat:** the model column is model vs model; rules is rules vs rules. Their-half numbers are only comparable
   inside a column. A paired model-vs-rules set (same seeds, both sides recorded) is the next instrument run.
<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "Step 2 instrument: what the army does with its orders (model / rules / players), offline", "games": 0, "W": 0, "L": 0, "w": 0, "l": 0, "verdict": "Offline, 38 model + 6 rules + 23 player games. Model idle at its target .286 (rules .231, players .122); ghosts at clusters .703 (.547, .437); kill rate at a live cluster 396 (846, 475); training and serve memory kept buildings seen to die."} -->
