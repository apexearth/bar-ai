# The middle from 4 to 12 minutes: A-12, G1, G2, model and rules side

Plan: `todo/armynet-objectives.md`, the Fable session's ask after [L](2026-11-27-loss-census-G.md). No new games: the
replays of A-12 (mvr-a + mvr-g0), [G1 and G2](2026-11-27-model-vs-rules-G.md), 12 games each, read with
`tools/armynet/objectives_army.py --mvr-log ... --side model|rules` (its new "middle" lines, ground truth).
- **Middle third**: metal spots and units at depth 1/3 to 2/3 on the start-to-start axis.
- **Held**: a finished building within 48 of the spot (its extractor).
- **Within reach**: the unit's weapon range + 200 of the nearest middle spot.
- **Alone at death**: none of our armed units within 1,000 at the last sample before the extractor or builder was gone.
- **A raid**: enemy armed metal of 200 or more in the middle third, from its entry until ours within 1,000 of its
  centre matches it (matched), it falls under 200 (left unmatched), or 12 min (open). One raid per presence: after a
  match, a new one starts only once their metal in the middle has fallen under 200.

## The tables (12 games each; the rules column of each pair is the target)

| | A-12 model | A-12 rules | G1 model | G1 rules | G2 model | G2 rules |
|---|---|---|---|---|---|---|
| **(a) middle extractors held, ours / theirs: 6 min** | 0.9 / 0.8 | 0.8 / 0.9 | 0.8 / 1.3 | 1.3 / 0.8 | 0.9 / 0.7 | 0.7 / 0.9 |
| 9 min | 1.4 / 3.1 | 3.1 / 1.4 | 2.2 / 3.2 | 3.2 / 2.2 | **3.1 / 1.3** | 1.3 / 3.1 |
| 12 min | 1.6 / 4.3 | 4.3 / 1.6 | 2.4 / 3.2 | 3.2 / 2.4 | **3.6 / 2.0** | 2.0 / 3.6 |
| **(b) army metal-time at 4-12 min within reach of a middle spot: ours** | .064 | .107 | .072 | .110 | **.109** | .084 |
| theirs | .009 | .008 | .016 | .006 | .005 | .010 |
| empty | .219 | .298 | .288 | .325 | .279 | .295 |
| away from every middle spot | .708 | .586 | .624 | .559 | .606 | .610 |
| **(c) our middle extractors killed before 12 min / alone** | 30 / .17 | 39 / .21 | 43 / .33 | 52 / .17 | 43 / .14 | 31 / .32 |
| our middle builders killed before 12 min / alone | 27 / .15 | 56 / .14 | 36 / .17 | 22 / .18 | 20 / .15 | 23 / .09 |
| **(d) raids into the middle at 4-12 min** | 22 | 39 | 21 | 35 | 26 | 32 |
| matched / within 60 s | .36 / .27 | .74 / .59 | .52 / .33 | .66 / .57 | .42 / .38 | .56 / .44 |
| median seconds to match | 20 | 0 | 10 | 20 | 10 | 0 |
| left unmatched / open at 12 | .36 / .27 | .26 / .00 | .24 / .24 | .31 / .03 | .38 / .19 | .38 / .06 |

## Read

1. **The middle is decided between 6 and 9 minutes.** At 6 min every arm stands level (about one extractor a side).
   By 9 min the rules army has two to one against A (3.1 vs 1.4) and against G1 (3.2 vs 2.2); G2 has it the other
   way (3.1 vs 1.3) and keeps it at 12 (3.6 vs 2.0). G2 is the only model arm to hold the middle on average; its
   losses are still the games where it did not (L: 13 vs 47 in the losses).
2. **(b) is the lever's shape:** against A and G1 the rules army spends .107-.110 of its army metal-time at 4-12 min beside middle
   spots it holds and .30-.33 beside empty ones; A spends .064 and .219, and 71% of its time away from every middle
   spot. G2 matches the rules army here (.109 beside held spots), G1 does not (.072). Nobody stands beside spots the
   enemy holds (under .02): armies stand where their own builders are, or will be.
3. **(c) does not separate:** extractors and builders lost alone are a sixth to a third in every column, the
   model's no worse than the rules army's. Losing the middle is not unguarded builders being picked off.
4. **(d) does:** the rules army matches a raid into the middle .56-.74 of the time, within a minute .44-.59, and
   leaves almost none open at 12 min (.00-.06); the model matches .36-.52, within a minute .27-.38, and a fifth to
   a quarter are still open at 12 (.19-.27), G2 included. The model meets fewer raids too (21-26 vs 32-39): it enters the middle less.
5. Small counts (20-56 deaths, 21-39 raids a column). The direction is the same in all three pairs except where G2
   leads.

<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "The middle from 4 to 12 minutes: A-12, G1, G2, model and rules side", "games": 36, "W": 9, "L": 25, "w": 2, "l": 0, "verdict": "No new games. Middle extractors level at 6 min, decided by 9 (A 1.4 vs 3.1, G1 2.2 vs 3.2, G2 3.1 vs 1.3). Army near our held middle spots at 4-12: rules .107-.110, A .064, G1 .072, G2 .109. Raids into the middle matched: rules .66-.74, model .36-.52. Builders and extractors lost alone do not separate."} -->
