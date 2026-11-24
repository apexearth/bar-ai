# Changelog

The major changes and improvements in each Apex release, newest first. A hosted game loads the highest Apex version
installed. Each release's full measurements are in its release commit message; the test batches behind them are under
`results/`.

## v0.5.18 (11-23)

**A tight, gridded base.** Every building now lands on one shared grid, nearest free cell first, packed to leave the
fewest unusable slivers and share the most edges with what already stands. A building is never left one square off the
grid, and a stray placement that would spoil a buildable cell is refused. Streets are kept open only in front of our
ground factories (and our allies'), a whole block wide, instead of carving lanes through the entire base. The result
is a compact, tidy base with room left for big buildings. Measured with this layout against v0.5.17 (12 games, home
radar off): games won or ahead 75%, losses per kill 1.10 against 2.36.

**The early radar now helps instead of hurting.** Since 11-20 the AI raises a radar at home before the commander
leaves base. Tested against the same AI without it, that cost a lot: games won or ahead fell from 67% to 31% over 72
games, and income at minute 24 was about a fifth lower. The radar's sight was not the problem. Three behaviours
reacted badly to raiders that radar kept in view near home:

- **What counts as an aggressive enemy.** A few raiders seen near the base, or a building lost to one, used to read
  the enemy as aggressive, and that switched off the economy's growth bonus. Now the enemy is aggressive only when the
  army we see clearly outclasses our side's army, or when a force at our base outweighs the guns, army and commander
  that can answer it. Ten Pawns walking in still counts; two raiders passing a tower does not.
- **The commander's cloak.** Defending the base, the commander cloaked whenever he could afford the cloak standing
  still (100 energy a second), then walked into the fight, which costs 1,000 a second. He drained the energy the T2 lab
  needed. He now cloaks only when the walking cost is affordable.
- **The commander leaving the radar.** When the home radar was his best job, the rule that sends him to help the
  factory pulled him off it at minute 1.4. It now lets him finish the radar.

With all three, radar on is as good as or better than radar off (36 paired games on two seed sets): won or ahead 61%
against 53%, losses per kill 1.32 against 1.47, income at minute 20 134 against 127. Against v0.5.17 it passes every
check of the behaviour contract (18 games), and against BARb hard it does as well as v0.5.17 (7 wins, 4 timeouts,
1 loss each over 12 games).

T3: no change in this release. Putting spare metal into T3 production was tested (45-minute games) and left off: it acted on 4 of 40 gantry decisions, so it barely changed play (9 games each: 2 wins, 1 timeout, 6 losses with it on; 3, 1 and 5 with it off). A stronger version is next.

## v0.5.17 (11-18)

- Constructor escorts use stock BARb's rule, so raiders that stood beside constructors go raiding: income at minute 20
  263 against 228, enemy extractors killed by our raiders after minute 12 37 against 13. The cost: more early
  extractors lost to Ticks and scout cars (2.4 against 1.0 by minute 10), to be fixed with our own fight layer.
- Lobby options cut to the ones a player can understand and that are worth trying: Personalities and Economy player.

## v0.5.16 (11-17)

- Extractors get guards before Ticks arrive: extractors lost to Ticks by minute 10 37 against 70, first turret at 2.7
  against 3.1 minutes, income at minute 20 about 217 against 156 (vs WRDistilled, 16 pairs).
- The resurrection fleet is no longer capped. The raid answer is removed.
- The "is Apex" chat line is sent once per host.

## v0.5.15 (11-16)

- Runs on engine 2026.09.03, the version BAR's launcher moved to (Apex did not show in the lobby before this).
- One chat line at game start names each Apex AI and its version. Play is unchanged from v0.5.14.

## v0.5.14 (11-16)

- Long-range guns may fire on an enemy army on our half of the map, but never where the splash would hit our own line.
- Radars and jammers are spaced out instead of stacked.
- Units on an attack step aside when wrecks block their path.

## v0.5.13 (11-15)

- Factory orders are first in, first out, so older orders no longer starve on a busy lab.
- Gunships stay home when the strike would lose (one game had 100+ gunships hovering for 14 minutes).
- A stream of T1 raiders counts as many arrivals, so defence keeps up with it.

## v0.5.12 (11-15)

- The first T2 constructors upgrade extractors before anything else.
- Bombers press on to the target with their escort instead of turning home early.
- Every release must now pass a behaviour contract against the previous release before it can ship.

## v0.5.11 (11-12)

- Factory nano turrets are sized for the constructors the factories make, not only the army. Armada's air lab (also
  its constructor plant) was starved; Armada income rose about 25% over v0.5.10.

## v0.5.10 (11-12)

- Aircraft no longer count toward the ground army's composition.
- The army is a share of what we spend.
- The opening raider race ends once their raid is met.
- Old T1 labs whose units are all outclassed are reclaimed.
- Metal maps get proper extractor fields.
- Nukes and anti-air aim at the enemy.

## v0.5.09 and v0.5.08

v0.5.08 (danger-fill on, a fix for the all-AA online game, rush launch) was scrapped at his request. v0.5.09 was not
released.

## v0.5.07 (11-08)

- Air plants are priced against the ground war.
- Interceptors chase live air.
- BARb's unit limits no longer apply.

## v0.5.06 (11-07)

- Guards on extractors, BARb's fight settings, and spam units thrown at whatever shells our buildings.
- Against BARb hard (24 games): wins 6-5 became 9-1; income at minute 20 +53; metal produced against BARb at minute 20
  rose from 1.21x to 1.53x.

## v0.5.05 (11-03)

- The Linux build runs.
- v0.5.04's energy charge removed.

## v0.5.04 (11-03)

- The first lab goes up at home, on time, even with no handicap.
- First Linux build.

## v0.5.03 (11-02)

- Builders get their orders within a few frames.
- No nano turrets during an energy stall.
- Personalities off by default, with a lobby switch.

## v0.5.02 (11-01)

- No self-destruct that wrecks neighbours.
- Orders sized for the measured lag.
- A half economy seat, and the team's first gantry.

## v0.5.01 (10-31)

- Fighters owed come before the constructor floors.

## v0.5.0 (10-30)

- Factories keep their exits clear.
- Room is kept for big buildings.
- Converters are sized to the economy.
- Desync-safe in multiplayer.

## v0.4.x (10-24 to 10-26)

- v0.4.09: constructors guard the extractors they leave.
- v0.4.08: resurrection bots are back; the commander walks to each D-gun kill.
- v0.4.07: old buildings are obsolete only within reach of the economic target, and that target sees every generator.
- v0.4.06: the economy player really focuses on economy, two of them on 8-player teams.
- v0.4.05 and v0.4.04: per-seat trials (obsolete pricing, cutting the army when behind).
- v0.4.03: retreats walk the whole way to the medic station; spam does not stall on shores.
- v0.4.02: wounded units pull back to the medic station.
- v0.4.01: spam sent at their bases; no turret piles at the base core.
- v0.4.0: doorways kept clear, gunships do not hover under anti-air, anti-air crossed on the way is priced.

## v0.3.x (10-17 to 10-23)

- v0.3.9 and v0.3.8: air trials per seat.
- v0.3.7: basic extractor defence (18-6 against v0.3.6 over 24 games).
- v0.3.6: 14-9 against v0.3.5 over 24 games.
- v0.3.5: economy pricing reworked (spending as the goal, energy and crew fixes); transports off.
- v0.3.4: a double-click installer that also shows the full AI list.
- v0.3.3: one settings file for script and C++, team tech, anti-nukes sized to survive the worst salvo, fewer and
  stronger units.
- v0.3.2: performance work.
- v0.3.1: no more anti-air bot floods (mobile anti-air bounded by their whole air force).
- v0.3.0: commanders kept off the void, gunships counted as strike air, anti-air where air hurts us, fighters help
  allies, the commander answers air, jammer sight.

## v0.2.x (10-12 to 10-17)

- v0.2.9: air on every seat (fighters answer their air), Bastion priced at its real damage, the gantry beside the guns.
- v0.2.8: economy return, expanding far, lab nanos, our own air control.
- v0.2.7: stock BARb army control with our economy and production (5 wins, 2 draws, 1 loss against BARb on Red Comet).
- v0.2.6: one strict economy player, measured defence, extractor upgrades first.
- v0.2.5 to v0.2.2: defence no longer crowds out the economy's build sites, layout, commander, lab rebuilds, squads,
  raids, towers with splash.

## v0.1.x (10-03 to 10-08)

- The first releases: decision nets packaged with the AI, the commander helps the lab early, escorts for exposed
  constructors, constructors keep claiming outward, no advanced air lab before an advanced ground lab in 1v1.
