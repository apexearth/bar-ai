---
name: ai-auction
description: The Market auction — Want records, kinds vs categories, the election flow, the sharpened category roulette, and how to read a decide line
---

# The auction (`manager/brain/market/decide.as`, `market/kinds.as`)

`Market::Decide` is the only thing that gives a mobile builder a job. One
call = one election for one constructor.

## The Want

`Want { kind, def, pos, spotId, gain, mCost, tCost, value }` — `value` is
gain over total cost (metal + time). Fourteen kinds (`WK_*`), each with one
proposer.

## Kinds are proposers; CATEGORIES are the questions

`CategoryOf` folds kinds into eight `CAT_*`. Wants compete as categories so a
question is asked once per election, not once per proposer (four energy kinds
drawing four tickets bought 672 wind turbines against 1 moho).

| Category | Kinds |
|---|---|
| `CAT_METAL` | `WK_MEX`, `WK_MEXUP` — **still share one ticket**: a new spot and a moho are the same purchase, so they argmax and the sequencing falls out of price |
| `CAT_ENERGY` | `WK_ENERGY`, `WK_GEO`, `WK_CONVERT`, `WK_STORE` |
| `CAT_PRODUCE` | `WK_PLANT`, `WK_TECH` |
| `CAT_BP` | `WK_NANO`, `WK_ASSIST` |
| `CAT_DEFENCE` / `CAT_SENSE` / `CAT_AIRDEF` | `WK_PROTECT` / `WK_SENSE` / `WK_AIRDEF` — split out because seeing is not shooting and an LLT stops nothing that flies; both lost every argmax against a turret |
| `CAT_RECLAIM` | `WK_RECLAIM` |

## Election flow (in order)

1. Builder + mobile check; **2s per-unit rate gate** (`gLastDecideAt`).
2. `CommanderSafety` — before the holds, so a comm with progress can still run.
3. **Three commitment holds**, each returns null (keep the task):
   `Requests::Progress > 0.01`; within **600 elmos** of the build pos; still
   closing — `gApproachD`/`gApproachAt` compare distance to the last election
   (stale after 30s). A stalled walker re-elects; a closing one does not.
4. **14 proposers** run, producing the wants array.
5. **Exposure charge**: every immobile non-`WK_PROTECT` want on a real
   on-map pos pays `ExpectedLossAt(pos, costM)` out of its gain, then reprices.
6. Sort by value descending.
7. **AA panic / DEF panic** — zero AA while `Military::AirLossRate() > 0`, or
   zero ground defence while home is losing metal — hoists that want to front
   and **skips the draw entirely**.
8. **Category roulette** (below).
9. Execution fallthrough: `ExecuteWant` down the ranked list, so a want the
   executor refuses (ground taken, request standing, join out of reach) drops
   and the runner-up is tried. Commander skips sites >400 elmos forward of
   the anchor. Nothing positive left → guard a ceiling-reaching con, else
   farm patrol, else idle.

## THE ROULETTE — read this before touching draw behaviour

One ticket per category. The ticket's weight is that category's **argmax want
value**, sharpened: `lead * pow(v / lead, apex_draw_sharp)`.

- Exponent **1** is raw-proportional — the old behaviour. Measured: **34% of
  elections took a lower-valued want**, and a mex valued 594 lost to a wind
  generator valued 99.
- Exponent **2** (default) makes a six-fold gap one election in thirty-six.
- Large exponent → argmax. **Pure argmax was tried and starved every category
  that is never #1** (a T2 lab bid once in 8 minutes and never won). Do not
  "fix" the draw by removing it; move the exponent.

## Log lines

`apex: decide t=<team> <condef> #<id> -> <cat>/<kind>:<def> v=<value*1000>
(gain=.. m=.. t=..) over <cat>/<kind> v=..`

Category shares: `grep -o "decide t=0 .* -> [a-z]*" infolog.txt | grep -o
"[a-z]*$" | sort | uniq -c`. Also `apex: auction ...` (full ranked dump, T2
builders, 30s, needs `apex_auction_diag`), `apex: AA PANIC`, `apex: DEF PANIC`.

## Tunables

`apex_draw_sharp` (2) · `apex_auction_diag` (0)
