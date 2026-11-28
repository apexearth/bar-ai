# In-contact data from the rules army: what exists, and what the unit heads can name

Plan: the Fable session (11-27), roadmap item 3 moved to the front, scoped to in-contact behaviour: learn the small
details of a fight from the AI's own fight logic. Step (1), the inventory. No games.
`tools/armynet/contact_inventory.py` (new): per built game, the rules side's recorded orders by its armed mobile units,
in contact when an armed enemy unit is within the unit's weapon range + 200 at the 10-s sample at or before the order
(ground truth); attacks resolved to a target when an enemy unit or building stands within 64 of the order's point
at that sample.

## Rules-army side-games built with their orders

| set | rules side-games | armed-unit orders | in contact | attacks on a building / unit / unresolved |
|---|---|---|---|---|
| mvr-a | 6 | 49,556 | 14,319 | 546 / 61 / 133 |
| mvr-a2 | 1 | 11,158 | 2,145 | 56 / 16 / 44 |
| mvr-b | 6 | 69,249 | 21,165 | 639 / 154 / 246 |
| mvr-cabs | 6 | 67,659 | 20,890 | 578 / 205 / 272 |
| mvr-cctl | 6 | 61,137 | 18,842 | 450 / 125 / 353 |
| mvr-e1 | 6 | 67,727 | 19,226 | 760 / 302 / 400 |
| mvr-e2 | 6 | 43,910 | 12,217 | 292 / 182 / 240 |
| mvr-e3 | 6 | 67,140 | 18,461 | 588 / 317 / 240 |
| mvr-g0 | 6 | 77,940 | 19,925 | 848 / 275 / 408 |
| mvr-g1 | 12 | 130,483 | 31,010 | 945 / 356 / 437 |
| mvr-g2 | 12 | 110,759 | 33,551 | 632 / 176 / 375 |
| mvr-t (seeds 1-2) | 2 | 24,078 | 8,311 | 111 / 83 / 218 |
| mvr-tb (built so far) | 4 | 39,373 | 10,985 | 245 / 34 / 91 |
| rules-r2 (rules on both sides) | 12 | 132,476 | 36,547 | 591 / 163 / 307 |
| **total** | **91** | **952,645** | **267,594** (.28) | **7,281 / 2,449 / 3,764** |

The H sets (mvm-h1, mvm-h2) have no rules side. mvr-tb's last 6 and every later model-vs-rules set add a rules side
each game.

In contact the rules army's orders are moves .81-.83, fights .13-.15, attacks .03-.05, patrol under .01 (mvr-a,
mvr-cabs, mvr-g2, rules-r2): the small details are mostly where each unit stands and steps to, with an attack order
now and then. Its 13,494 in-contact attack orders are 7,281 on a building, 2,449 on a unit and 3,764 unresolved (the
target moved off the 10-s sample).

## What the unit heads can name today

Only a place. The unit heads give act, kind (stop / move / fight / attack / fight / patrol) and a cell of the 64 x 64
grid with an offset inside it (`model.py`: `query` over the map cells, `offset`). The unit already attends over the
enemy tokens (`cross_e`), but no head points at one. In serve an attack becomes an attack on the visible enemy nearest
the chosen point (within 400; else a fight order), which is why the model's at-cluster attacks land on the nearest
building (`2026-11-27-at-cluster-orders.md`). The bridge already takes an attack on a named enemy (`uid,20,enemyId`).

**Smallest head that adds a target:** a pointer over the enemy tokens the model already embeds: `t_query =
Linear(d, d)`, logits = t_query(h) . e_emb / sqrt(d) over the visible enemy tokens plus the existing `e_none` (no
target); about 66k parameters at d = 256. It is trained on in-contact attack orders whose target resolves (about 9,700
now; the label is the target's token index) and asked only when the kind head says attack; serve then sends
`uid,20,<that enemy>` instead of the nearest. Moves (.81 of in-contact orders) need no new head: the cell and offset
heads already express them.

<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "In-contact data from the rules army: inventory and what the unit heads can name", "games": 0, "W": 0, "L": 0, "w": 0, "l": 0, "verdict": "No games. 91 rules side-games built with orders: 952,645 armed-unit orders, 267,594 in contact (moves .81-.83, fights .13-.15, attacks .03-.05); 7,281 in-contact attacks on a building, 2,449 on a unit. The unit heads name only a cell; serve attacks the visible enemy nearest it. Smallest addition: a pointer over the embedded enemy tokens (~66k parameters)."} -->
