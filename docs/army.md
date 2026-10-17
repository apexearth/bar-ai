# The army layer (design, 2026-10-16)

Why the army has resisted months of fixes, and the shape that replaces it. Every change to army
control follows this document; where code disagrees, the code is the bug.

## Why it kept failing

1. **No single owner.** Raid nets, hunts, strikes, team pushes, the fight estimate, gather, focus
   fire, withdraw and the C++ tasks each ordered the same units and undid each other.
2. **No visible state.** No log said why a unit walked in, so fixes chased symptoms.
3. **Slow, noisy verification.** Twenty-game batches judged changes by averages; an inert fix
   survived for hours.
4. **Big-bang changes.** Each layer arrived large, untested, on top of the others.

## The shape

- **One owner.** `Army` owns every combat unit from the moment it is built. Only a `Squad` issues
  commands to its members. Nothing else in the AI may command a combat unit; a static check
  enforces it.
- **The army decides what, the squad decides how.** The army hands each squad an intent (hold here,
  take this area, defend this place). The squad turns it into moves, fights and targets on its own
  update.
- **One assessment.** `assess(at, radius)` returns their strength and ours that can be there,
  calibrated against fight outcomes. Every decision that weighs a fight calls it; nothing keeps a
  private estimate.
- **A small, explicit state machine per squad**, each transition logged with its reason:
  `forming -> moving -> engaged -> {winning: continue | losing: falling_back} -> regrouping -> forming`.
  Membership is open only in `forming` and `regrouping`.
- **Air squads** are the same type with a different `update` (search, strike, return).

## How changes are made

- **Scenario tests first.** A behaviour is written against a short scripted scenario (a few
  minutes, fixed units: a squad meets an LLT with a Centurion beside it; a raid meets their army; a
  commander walks into our base). The scenario passes or fails on a counter in a minute, before
  any full game.
- **Then three or four games** against BARb. A landslide decides; only a close result earns more.
- **Counters before scores**: units that died alone, standing still, joined after commit, or
  walked into armed reach they could not beat. A change that does not move its counter did
  nothing, whatever the score says.
- **One behaviour per change**, small enough to read in one sitting.

## Order of work

1. `TUNE_STOCK_ARMY`: our economy with stock BARb army control -- the floor and the census of
   every layer that must go quiet.
2. The skeleton: `Army`, `Squad`, `assess`, the state machine and its log, owning units under one
   switch, with the simplest behaviours (guard home, form, advance together, fall back whole).
3. Behaviours one at a time, each with its scenario: defend, raid the flanks, focus fire,
   matchups, air.
