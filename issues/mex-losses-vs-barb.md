# Mex losses vs BARb: the raider never pays (2026-10-10)

`tools/mexraid.py`, 38 normal 12-min Comet 1v1s (20261010-03..): standing mexes m5/7/9/11 us 4.7/6.8/8.2/9.8, BARb
6.6/8.9/11.0/13.6. We lose 5.1 finished + 1.3 unfinished a game, BARb 3.0 + 0.5. The enemy unit that killed one of
our mexes was alive at the end in 58% of cases (BARb's killers: 33%). raidanswer.as answers part of it; still open:
- **The gap at m5 is claims, not losses**: by m5 we have 2.4-3.5 factory cons, BARb 4.1-5.2; distinct spots claimed
  by m7 6.2-8.2 vs 9-9.8 (see "First constructor up to 5 min late" in `code-review-2026-10-08.md`).
- **35% of our mex losses are army-scale** (>=5 enemy units or >=800 m within 700): 1.7/game vs BARb's 0.8.
- **BARb takes the exposed spots more, not less** (21 games): builds at f>=0.4 76 vs our 40.
- **A small DEFEND pool skips a petty raider and cannot detach for it**: Detach keeps half the pool and one member,
  so a pool of 2-3 facing a raider just under half its power sends nothing (`apex: defend-petty ... sent=0`,
  15/22 games). C++.
