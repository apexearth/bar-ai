# After breaking a line, the army turns away instead of seeing what is behind it

His 11-24, from the 11-23/24 online games: the AI was on the verge of breaking through important positions, killed
the whole front line, then could no longer see anything and went to attack another front line. It should know it has
just destroyed a defensive position and go and see what is behind it.

## Evidence so far

`python tools/breakthrough.py <replay-orders dirs>`: a break = 3+ enemy static guns killed by one team within 800 of
each other inside 60 s; that team's army units within 1,200 of the line are followed for 120 s along the line ->
gun owner's start axis. Last night's 10 games (runtime/armynet/breakthrough-1124.txt), the AI seats against the humans
in the same games:

| | breaks | ours >= 2x theirs there | median advance at 120 s, contested | a unit 1,000+ past by 120 s, contested |
|---|---|---|---|---|
| AI | 63 | 3 | -306 | 17% |
| humans | 161 | 46 | -383 | 5% |

In the aggregate the AI does not turn back more than the humans do. What differs: the AI almost never breaks a line
with the ground in its favour (3 of 63 against 46 of 161); a break is usually a few units (often 1-13, a few
thousand metal) against far more enemy army within 1,500. Not yet tied to the moments he saw: the per-break rows give
the game, minute and team, so a remark with a time can be found.

## Next

- His commentary tonight names the moments; read each with this tool and story.py.
- Which controller it was (BARb fight logic or the army model): last night only Canis t8 is known to have run the model.
