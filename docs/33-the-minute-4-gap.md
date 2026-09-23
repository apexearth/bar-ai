# The minute-4 gap

*2026-09-22. Glacier Pass 2v2, Armada both, +100% both, 0.2 lr boxes, vs
BARb stable hard — his benchmark. Everything here is measured with
`tools/openloop.py` (8-minute games at speed 20, 96 games in ~20 minutes)
and `tools/mex4.py`; the noise floor is ±0.9 mex at n=8 and ±0.4 at n=96,
and the same seed does not reproduce, so pairing does not help.*

## What decides the game

Pooled over 96 full-length games from six arms, at **minute 4**:

| | n | win rate |
|---|---|---|
| we lead on extractors | 36 | **44%** |
| we are behind | 60 | **5%** |

In the games we win our opening is level; in the games we lose we are 2-6
spots behind before either side has lost anything worth counting. The
12-24 minute story (trade ratios, defence share, plant mix, the unit track
record) is downstream: if we are losing we make less metal *because* we are
losing. Read one win and one loss with `tools/perminute.py` before
believing any batch-wide average.

## The gap itself, both sides, same games

Finished by minute 4, per team, on the current tree:

| | us | them |
|---|---|---|
| total metal | 2,033 | 1,737 |
| solar + advanced solar | 663 | 169 |
| wind | 117 | 266 |
| extractors | 166 | 187 |
| nano turrets | 287 | 328 |
| second plant | — | 295 |

We finish **more** metal and stand on **fewer** extractors. The surplus is
energy: 780 metal to their 435, for less energy per metal (solar is 155 for
20 E/s, wind 40 for 11).

## What has been excluded, at n=96 unless noted

- **The commander's leash**, both halves. Radial half-leash vs full leash:
  +0.00 mex (se 0.21), churn unchanged. The rim test: 3-13 at full length.
- **Commander walk distance.** `tools/comwalk.py`: ours walks 3,098 elmo by
  minute 4 to end 416 from its start (churn 7.4); BARb's walks 2,727 to end
  1,257 out (churn 2.2). Widening the leash does not change the churn.
- **The energy mix.** `apex_stall_solar_e=0` (his rule off): -0.49 mex,
  worse. The rule is exonerated.
- **The caretaker floor.** The old income gate instead of `isAssistRequired`:
  -0.74 mex, worse. The nano floor outbids spot claims in minutes 2-4 (65
  of 265 lost elections, the largest single competitor) and pays for it.
- **Claims over the metalfirst assist**: -0.27 (se 0.22), flat-to-worse.
- **The walk price** (assist charged at `Wage`, a claim at `WalkRateWith`,
  13x for the same second): equalising them is flat.
- **Army size** (`apex_army_eco_s` 66 -> 120 -> 180) and the budget's army
  share (inert by design, budget.as:13): no change to the minute-4 army.
- **Harassment.** The raid director refused 128 of 130 asks for want of a
  remembered enemy structure; given a geometric target it asks 50 times and
  forms packs of 1-3 units, which is neutral at n=96. Scout demand from the
  intel gap: flat, reverted.
- **Energy and converter losses**: at parity full-length (1,464 vs 1,544).

## What helped

`3bb47630` — a commander already outside the leash takes the best job
within 600 elmo of **himself** rather than the best job near home. Two
independent 96-game runs: minute-4 gap -1.5 -> -1.0 and -1.1, our
extractors killed by minute 4 down 42% (0.45 -> 0.26 per side), their units
killed up 23%, our metal lost down 188, army up 472. The mechanism is not
the one intended: churn is unchanged, so he commutes as much as before —
he simply stays at the extractor he just capped, and his own guns defend
it. The extra extractors are ones that did not die, not ones we built.

Full length it reads 4-12, inside the 3-13..6-10 band every arm of the
session produced.

## What is left

One extractor of the original 1.5 at minute 4. Spots are open (`mexdiag`
noOpen 1.4 per sample of 19) and priced (4.8 per sample); they lose their
elections to the nano floor, the energy stall and the cover push, each of
which has now been measured to be worth more than the spot it displaces.
So the remaining gap is not a gate, a price, a leash or a rule that can be
switched off: it is that BARb converts the same opening into a second
plant and more extractors while we convert it into energy and towers.
