# Leaks: enemy ground units kill our economy at the base edge (2026-10-08)

`tools/leaks.py` over the 2v2 vs BARb batch (20261008-054849, 121 games): 2.86M metal of generators/converters/
nanos/labs killed by enemy ground units inside our hull or within 250 of its edge, 61% of it outside a loss's final
5 min. Median per game: wins 4.5k, losses 8.8k, time-capped draws 22k. Almost all at the RIM (80%); front 51%,
flank 35%, rear 13%. 66% fell with at most one gun of the team within 600. Killers: raiders (<400 m) 40%, heavies
(>1200 m) 39%; it grows with the game (min 0-10: 35k, 30+: 1.4M). `apex: leak-stat` is the live census; heads
defamt/defsite record against it. Unfixed until a trained head or a rule moves these numbers.
