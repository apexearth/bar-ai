# Next

## 0. Deploy the merge
`apexdef` was merged into `apex` and removed. Not yet deployed.
`python tools/deploy_ai.py deploy apex`, confirm `unitsync.py ais` lists only
`apex` and `stable`, then one smoke match for script errors.

## 1. Unit-production diagnostics
`dev_stats_export.lua` caps `builtTop` at 4 units by metal, which hides the mix.
Emit full per-unit counts + metal per team. Without this, "too many cons",
"too many radars", "why a commando" are all guesses.

## 2. Radar/jammer clumping
`behaviour.json` has `"solo"` — cannot share a task with another unit carrying
the same attribute (`coracv` uses it). Add to mobile radar and jammer defs, all
three factions. Observed: 4 radars moving as a blob.

## 3. Anti-air
Nothing builds AA. 1-2 AA towers per base as a deterrent. Check whether the
existing `"air": true` build-chain conditions ever fire before adding new ones.

## 4. Clean up factory.as / military.as comments
~60 lines of accumulated failed-experiment history before the first function,
some self-contradictory. History belongs in git log. Keep only: what the file
owns, why a constant has its value, what breaks if changed. Two recent bugs came
from editing files that were hard to read.

## 5. Sling guard
Followers give away everything above 220 metal with no check on their own
safety. Survival outranks sharing. Add a condition — under attack, or army below
some floor, stop donating.

## 6. Measure
5-10 games each: 4v4 Comet Catcher (`--boxes lr`), 8v8 Glitters (`--boxes tb`,
45 min). Primary metrics: `t2Mex`, con gifts, metal, army. Everything before
commit `48089b9` is void — advanced constructors were never built.

## Open, no known approach
- **Commander safety.** Strongest outcome correlate measured (2.8-3.0 lost when
  we lose vs 0.75-1.0 for stock). Three approaches failed: `commander.json`
  levers (no effect, cost 10-20k metal), `GetEnemyCostAt` (crashed), threat map
  (works, does not predict death — readings at death are *lower* than baseline).
  Untried: event-driven on damage taken.
- **Factory placement.** `"support"` is documented as "build in base radius, not
  on front" and is already set on every factory, but there is no `IsAttrSupport`
  in the source. Unclear anything reads it.
- **T3 as win condition.** Needs >100 metal/s after 1-2 AFUS. Not reachable at
  4v4 scale (~40 metal/s). Reachable at 8v8 — stock does it.

## Do not
- Call `ai.GetEnemyCostAt` or `CCircuitUnit::CmdMoveTo` — registered, unsafe.
- Trust a run without checking `exit_code` and `reason` in `result.json`.
- Use scripted inserts for targeted edits; use `Edit`.
