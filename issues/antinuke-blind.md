# Nuke the guessed base in volleys: BARb builds one anti-nuke (his 11-05)

His words, about BARb: it is "extremely easy to beat because they only ever make like one anti-nuclear": guess where
the enemy base is, aim every nuke there, a few volleys, dead -- no scouting needed. (Ours are not the issue: we build
more than one anti-nuke.)

## Our director today (ai-nukes skill, nukes.as)

- The guess exists: the mirrored base is always a candidate (`apex_nuke_base_value`, 30k), scored with an assumed
  anti past minute 30 (`apex_nuke_assume_from`).
- The volley does not: the SALVO is sized on SIGHTED antis only (`1 + sighted x apex_nuke_per_anti`). An unscouted
  base gets one missile at a time, and one anti stops one missile per reload -- so every shot at a base defended by
  a single unseen anti is wasted. Repeat strikes on base ground also decay x0.5 each.

## Next

At the guessed base, fire what beats the antis a player would assume (one, from the minute the director already
assumes it), in volleys that land together, and keep the repeat decay from walking away from a base still standing.
Measure in games vs BARb with silos: missiles fired at the mirrored base, intercepted vs landed, metal killed per
missile, minute the enemy dies.
