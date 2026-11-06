# One anti-nuke against a player who never shows a silo (his 11-05)

His words: the AI "is extremely easy to beat because they only ever make like one anti-nuclear": guess where the
base is, aim every nuke there, a few volleys, dead -- no scouting needed.

## Why (want_super.as SuperWant, read 11-05)

- No enemy silo seen: the anti-nuke want is what we hold, or 1, plus one while a cluster worth more than an anti
  stands outside every umbrella (`UncoveredClusterM > AntiNukeCostM`). A silo we never see adds nothing until it
  fires (a launch counts as proof, Brain::AntisForSalvo) -- by then the volley is in the air.
- Seen silos: one past the silos seen, or the full salvo they could fire at ~6 stopped per anti.
- Our nuke director already assumes THEIR side has an anti past minute 30 (`apex_nuke_assume_from`, his); our
  defence makes no matching assumption about their silos.

## What a player infers without seeing a silo (no hidden information)

Time, their income as seen (scouted economy, the census), what they have fielded (T3 walking means a gantry and the
economy for a silo), and that a silo stockpiles: a player rich enough by minute 25-30 is assumed to have nukes, and
every base worth more than the cost of a volley wants an umbrella, on every seat.

## Next

Price the anti-nuke against the EXPECTED volley: the chance they hold silos (from what is seen, rising with their
economy and time) times the stockpile they could have fired by now, times what each umbrella covers; per seat, so
each base worth it is covered. Offence, his same note: a few volleys at the guessed base works because players also
build too few antis -- our director's mirrored-base candidate is that play; check it fires volleys, not single
missiles, once silos are full.
