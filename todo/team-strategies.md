# Team strategies that shift (his 10-24, 11-02)

The whole team runs one cooperative plan and acts on it in unison, and the plan CHANGES -- *"imagine we are doing
normal and then we suddenly switch to air"*. The plan is *"based on what they think will work"*, from what they can
see; *"timing is so important on a lot of these and the context/ability in the game is important"*. His list:
vehicle rush; bot rush; massive air (*"a build up of air and then sudden massive attack surprising and overwhelming
the enemy"*, *"good to follow up next with a massive bot or vehicle attack, confusing the enemy who just spent a lot
of money on AA"*); nuke rush; T3; longer-range T2 massing; greed; mass stealth units through gaps in their front.
NOT turtle: *"a bad strategy, boring game for humans, we should avoid"*. Never announced in chat.

His 11-02: a team strategy is exclusive, committed and timed, done by the whole team with overwhelming force (air
strike: everyone stops ground, masses air, hits the front or the eco at once). *"If you put 20% into all these ideas
you won't get anywhere."* Personality is per seat and not exclusive.

Older plays of the same kind:
- **Surprise air eco attack** (by 09-01): 20+ fighters and 20+ T2 bombers, or T3 Dragons, go round their army
  (*"don't retreat!!!!"*) and hit constructors, economy and build power until dead.
- **Nuke spam** (by 09-01): before the enemy is ready the team goes nukes, saves several, launches them all on
  different bases around minute 18, reclaims the launchers and plays on. Prefer a docile enemy.
- **Allies agree a timing** (10-22): *"the AI could suggest to each other that at a certain time they'll all go air
  and do a massive air attack, things like that would be crazy and fun."*

Built: every plan priced and logged (576ceb60, `plan-price`); one team plan (plannet.as) that follows the team style
(a9ec1ac7); styles drawn by what their key investment costs the team (f8444866); seat personalities by position
(persona.as; off by default, lobby switch since v0.5.03); the RUSH plan as open -> produce -> strike
(apex_strike_phases, off); the team op MASS -> GO (plannet.as).

Not built:
- **The commander leads the rush** (11-09): *"Send the commander in, have him destroy the army, have him support his
  own army, repair his own units ... It can be a team together."* The rush as built (11-09: strike launches every
  pool, escort and squad as one; commander and hands assist the lab in the build-up; two strikes traded down end it)
  keeps the commander home.
- **The timing.** A plan is build-up (quiet, gathered out of sight) -> strike (every seat on one signal, when the
  gathered force beats what we have seen of theirs) -> follow-up (their answer, e.g. the AA they buy after an air
  strike, raises the counter-plan's value and the team switches whole and sudden). Each plan priced from the seen
  state with its own timing window; a plan the enemy has adapted to is worth less, so repetition prices itself out.
- **One pick across hosts**: the same team pick on every host, derived from what all hosts see alike.
- A stealth personality dial (air, tech, aggression, fast, scout, turtle exist).
