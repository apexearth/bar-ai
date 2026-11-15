# A big gunship wing never flies

His game, 11-13 night (v0.5.12, Cortex seat t3): 80-103 gunships (29.6k metal of the wing priced, Dragons among
them) held at home from minute ~15 to 43; `nnair-stat goG=0`, ~74 WAIT decisions. "Despite having a ton of dragons
they were too scared to use them ... probably coulda hurt us a lot."

The best cell's price (nnair.as NaEval), from the decision row at 43 min: n=80, hp 124.8k, dps 8.9k; target v=12.5k,
hp 3.8k; AA over it 12.2k + their fighters 17.1k; path AA 5.9M (value x distance). Lost on the way in ~24 of 80; the
dwell term (`apex_aa_dwell`: the cell's whole AA charged against the wing for 2 x reach / speed) took the rest:
lossN=80, killF=0, net=-29.6k.

What the model does that a big wing breaks: attrition is linear (A/h planes a second, as if every AA gun keeps a full
kill rate until the wing is gone) and the dwell charge does not shrink as the wing kills the AA.

Scored runs, predicted vs actual (launched runs only, so the optimistic side; 512b-h head-to-heads, 11-13):

| wing | runs | predicted lost share | actual | predicted net/run | actual |
|---|---|---|---|---|---|
| 1-2 | 940 | 0.26 | 0.31 | 202 | 843 |
| 3-5 | 281 | 0.22 | 0.19 | 257 | 1,049 |
| 6-10 | 68 | 0.31 | 0.17 | 636 | 749 |
| 11-25 | 21 | 0.22 | 0.16 | 1,600 | 172 |
| 26+ | 1 | 0.13 | 0.00 | 2,625 | 0 |

Losses run ~2x high from 6 planes up; nothing is known past 25, because a wing that big is never launched.

Next: measure a big wing on purpose (a scenario: 60-100 gunships against 10-40k metal of AA, priced loss vs real),
then fix the race so AA dies while it shoots (both sides attrit), instead of a launch override.
