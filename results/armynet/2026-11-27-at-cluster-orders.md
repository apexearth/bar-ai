# At a live cluster: what the AI's own fight logic orders (E3's release) against what the model orders

Plan: the Fable session (11-27), offline, no games. E3 (`--hybrid-cluster`) hands a ground unit at a live known enemy
cluster to the AI's own attack; G1 and H1 played with it, G2 and H2 without it (the model orders the unit there).
The difference is the label for the model's own behaviour at a cluster, so the release can be retired once the model
does it. Read with `tools/armynet/objectives_army.py` (new "at-cluster" lines, ground truth), ground units within
reach of a live enemy building at a known cluster (2,000 metal within 800):
- **Order**: an attack whose target lies within 64 of a live enemy building (on a building), any other attack (on a
  unit or the ground), fight, move, none; metal-time weighted.
- **Target choice**: of the attacks on a building, the share where it was the nearest, the weakest (lowest health
  now) or the most metal of the live buildings within the unit's reach (the target included). With a median of 4
  in reach, a blind pick is about .25 on each.
- **Re-targets**: changes of the building attacked, per unit-minute at a live cluster. **Pulled out**: stints that
  ended with the unit leaving while a building it had in reach still stood.

The release is decided on the model's own memory and sight; here "at a live cluster" is ground truth, so the G1 / H1
columns are mostly, not only, released units.

| at a live cluster, ground units | G1 (released) vs rules | H1 (released) vs enemy1 | **G2 (model) vs rules** | H2 (model) vs enemy1 | rules army (G1 games) | rules army (G2 games) |
|---|---|---|---|---|---|---|
| order: attack a building | .245 | .136 | .319 | .169 | .137 | .157 |
| attack anything else | .160 | .334 | .339 | .344 | .135 | .214 |
| fight / move / none | .09 / .45 / .06 | .06 / .42 / .05 | .11 / .21 / .02 | .10 / .36 / .03 | .12 / .55 / .06 | .08 / .52 / .03 |
| **target: the nearest** | .70 | .76 | .66 | .83 | .71 | .79 |
| **target: the weakest** | .27 | .37 | **.14** | .34 | .35 | .45 |
| **target: the most metal** | .22 | .36 | **.16** | .42 | .46 | .55 |
| re-targets per unit-minute | 0.35 | 0.29 | 0.29 | 0.24 | 0.34 | 0.31 |
| **pulled out, of stints (median s)** | .18 (10) | .18 (10) | **.15** (10) | .16 (10) | .24 (20) | .24 (10) |
| stints cleared / died | .29 / .42 | .22 / .49 | .14 / .48 | .15 / .63 | .27 / .43 | .20 / .49 |

## Read

1. **Target choice is the difference.** The AI's own fight logic (the rules army, and E3's released units) attacks
   the most valuable building in reach about half the time (.46-.55; released .22-.36) and the weakest .35-.45. The
   model, ordering itself against the rules army (G2), picks the most valuable .16 and the weakest .14, under a blind
   pick: its attacks land on the nearest thing (.66). It orders a place and the attack falls on what stands there;
   it does not choose the building. Head-to-head (H2) its picks are closer to the AI's (.34 / .42), so part of
   this is what it meets, not only how it picks.
2. **It attacks units at a cluster more** (.34 vs .14-.21) and moves less (.21 vs .52-.55): it fights what defends the
   cluster where the AI's logic walks past it to the building it wants.
3. **It pulls out less** (.15 of stints vs .24) and clears fewer (.14 vs .20-.27): it stays until it dies (.48) or
   the game moves on. Re-targeting is level (0.24-0.35 everywhere).
4. So the label for the model at a cluster is two things: which building (the valuable and the weak first, from
   rules-army episodes: the target's metal and health against the others in reach), and when to leave one it cannot
   finish (the rules army leaves a quarter of its stints). Both fit step 3's objective head as at-cluster targets.

<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "At a live cluster: the AI's own fight logic (E3 release) vs the model's orders", "games": 48, "W": 20, "L": 18, "w": 6, "l": 4, "verdict": "No new games. Of attacks on a building in reach, the AI's logic picks the most metal .46-.55 and the weakest .35-.45; the model (G2 vs rules) .16 and .14, under a blind pick (.25), the nearest .66. The model attacks units at a cluster more (.34 vs .14-.21), pulls out less (.15 vs .24 of stints). Re-targets level."} -->
