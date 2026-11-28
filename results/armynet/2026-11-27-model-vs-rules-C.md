# C: the army model retrained with the memory fix, and its control, vs our rules army

Plan: `todo/armynet-objectives.md`, the Fable session's C (11-27). Trained on the Mac (Workhorse): enemy1's recipe
exactly (init w40-40k, arch 256,96,4, own-fix1 share 0.25, 10k steps OneCycle from 40000, the same fresh warm-up,
`--mirror --late --rounds`, batch 32, the game set frozen to enemy1's 1,338 + 96: 1,299 train / 135 held out), on
today's code. The pair differs in one thing:
- **C (enemy1-absent, md5 2c0819b4)**: `BARAI_ABSENT=1` in training, and in serve when it plays (a remembered enemy
  building is forgotten once our sight covers its spot after its last sighting with nothing there; data.py
  absence_marks, parity-clean).
- **control (enemy1-ctrl, md5 7d0c3114)**: the same code and set, `BARAI_ABSENT=0`.
Today's code also widens the scalar inputs 8 -> 10 and adds fresh judge heads, which enemy1 (11-23) did not have; the
control carries that drift too, so C vs control isolates the fix.

Games: as [A](2026-11-27-model-vs-rules-A-B.md) (his online flags, no E flags, Red Comet 1v1 +50, A's six seeds and
sides, same faction both sides), sets mvr-cabs and mvr-cctl. C's seed 5 playback died at 6 s (two playbacks
starting together) and was rebuilt alone.

## Held-out (the Mac, heldout-fixed-1 "all", each model in its own mode)

| | act | kind | f_act | f_kind | f_cell | f_shape | value | b_eco | d_f_cell | v_result_acc |
|---|---|---|---|---|---|---|---|---|---|---|
| C | .1802 | .184 | .1010 | .2028 | 4.887 | .951 | .2955 | .3584 | 322 | .674 |
| control | .1810 | .182 | .1032 | .2109 | 4.913 | .936 | .2847 | .3459 | 336 | .688 |
| enemy1 (11-23) | .1805 | .178 | | | 4.897 | | .2866 | .3461 | 326 | .691 |

## Games (model side; rules side in brackets)

| | A (enemy1) | C | control |
|---|---|---|---|
| won / lost / at the cap | 1 / 5 / - | 2 / 4 / - | 1 / 4 / 1 ahead |
| **building metal killed per 1,000 army metal-min at a live cluster** | 405 (1,253) | **1,326** (1,028) | 551 (618) |
| lost per killed there | 1.85 (0.46) | 1.16 (0.67) | 1.40 (0.71) |
| standing order there move / attack / fight | .80 / .17 / .00 | .66 / .28 / .02 | .51 / .36 / .04 |
| orders per unit-minute there | 42.2 | 25.8 | 21.8 |
| stints cleared / left / died | .13 / .27 / .42 | .17 / .13 / .70 | .22 / .18 / .60 |
| **after clearing: none** | .635 | **.359** | .773 |
| after clearing: deeper / sideways / back | .14 / .23 / .00 | .29 / .25 / .11 | .09 / .04 / .10 |
| none = same / ghost / dead | .60 / .22 / .16 | .62 / .20 / .16 | .91 / .04 / .05 |
| at a known cluster / of it ghosts | .256 / .452 | .257 / .552 | .474 / .460 |
| in their half, units 5-15 / 15-25 min | .258 / .326 | .240 / .279 | .229 / .244 |
| idle at its target | .227 | .191 | .243 |

## Read

1. **The memory fix, trained in, is the larger change at a cluster:** with the code drift held equal, the kill rate
   at a live cluster is 1,326 vs 551, and "no order after clearing" .359 vs .773 (the control's "none" is nearly
   all "stay here", .91). The model that remembers only what it could still believe moves on after a cluster falls
   (deeper .29, sideways .25).
2. It does not stand further forward (their half .24 vs .23 at 5-15 min) and loses as many units there (stints
   died .70); the trade at a cluster is between A's and the rules army's (1.16).
3. Serve-only, the fix did nothing useful (B); trained in, it does. The held-out losses say the same in small:
   better force heads (f_act, f_kind, f_cell, d_f_cell), slightly worse value and economy heads.
4. Results 2 / 1 (+1 ahead at the cap) of 6: no reading. G puts C with E3's and E2's flags on 12 seeds, with A on the
   same 12 as the baseline.

<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "C: the army model retrained with the memory fix, and its control, vs our rules army", "games": 12, "W": 3, "L": 8, "w": 1, "l": 0, "verdict": "Model side counted (C 2-4, control 1-4 + 1 ahead at the cap). Same code and data, the fix trained in vs not: live-cluster kill rate 1,326 vs 551, none after clearing .359 vs .773, lost per killed 1.16 vs 1.40; not further forward (.24 vs .23)."} -->
