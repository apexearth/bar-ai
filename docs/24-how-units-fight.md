# 24 — Doctrine

apexearth's directives for how this AI plays. Every directive here is his;
nothing is Claude's idea except the mechanic marked *verified*. Rewritten
2026-10-08 from the dated notes it grew out of (his request: "reorganize and
completely rewrite... it was pieced together largely through iteration and
commentary"). The dated form, with its quotes, measurements and code
references, is in git: `git show 2be21727:docs/24-how-units-fight.md`.

`docs/23-the-plan.md` says what the economy is for and how a decision is
priced. This file says what the AI is trying to do and how it plays.

## How to read this file

Every rule is one of four kinds, and the kind says how binding it is.

- **Goal** — what winning and playing well mean. Only he changes a goal.
- **Fact** — how the game works. True until the game changes.
- **Contract** — unit-control correctness. Code that breaks a contract is a
  bug, never a strategy.
- **Prior** — a strategic judgement: the default the AI starts from. Since
  2026-10-08 the decision nets may overrule a prior where training shows it
  loses (his words: "Don't assume that my instructions are correct. Now that
  we're using a NN we can let reality through training govern our
  decisions"). A prior he gave a number for carries his number as the
  default.

Where play breaks a contract or a fact, the code is wrong. Where play departs
from a prior, measure before calling either side wrong: the Progress edges
(`tools/progress.py`) and a minute-by-minute read (`tools/minutes.py`) of a
win and a loss.

Section 7 lists where priors pull against each other. Those are the
decisions the nets are for.

---

## 1. Goals

- **Beat BARb, and win decisively.** In even games (the same bonus for both
  sides), above 80%, and end the game when it can be ended.
- **Multiplayer is the target.** The AI runs on the host, in real lobbies,
  beside and against humans.
- **No hidden information.** Live decisions use only what a player could see.
  Ground truth may train the nets; it never steers a game.
- **Use the army; make the game worth watching.** A big army that never
  attacks means nothing happens all game ("just wait for the humans to kill
  me"). The late game should be exciting: bombing raids, nukes, long-range
  plasma.
- **Lag is a cost.** Tiny units are the lag; a big army parked at home lags
  the humans too.
- **Judge a fight by damage efficiency (D%, dealt over received), not
  kills/deaths.** A fight's price is our loss *plus* their gain: our wrecks
  are reclaim for whoever holds the ground.
- **Fighting is gauged without turrets.** With static defence switched off,
  nothing hides a bad army. The first five minutes of fighting are the test:
  damage efficiency, kills against losses, builder interruptions, and
  building damage received against dealt.
- **Instrument everything.** A squad shows what it intends; a death record
  names the action before the retreat, never a bare "retreat"; a rule that
  never fired is a bug; strategic logic should be easy to express.

## 2. Facts

**Damage and wrecks**
- *Flanking (verified: engine `Unit.cpp` GetFlankingDamageBonus/DoDamage,
  BAR `modrules.lua` flankingBonus).* Damage is multiplied by `1.5 - 0.5 ×
  dot(dirToAttacker, flankDir)`, between 1.0 and 2.0. The first hit sets the
  unit's "front" to that attacker, so a second attacker at 90° does 1.5× and
  one directly opposite does 2.0×. The front only regrows slowly
  (0.01 per half second) once the unit stops being hit.
- A dead unit leaves a wreck worth about half its metal. Whoever holds the
  ground reclaims it, so a battlefield is the richest reclaim on the map.
- Converters are explosive and fragile.
- A bomb that lands after its plane has died still counts.
- A tower being repaired can heal faster than we damage it.

**Units** (stats misprice units: projectile speed and accuracy are invisible
to them)
- Starlight (`armmanni`) fires only in its forward 180°; snipers (`armsnipe`,
  `corhrk`) fire all round.
- Snipers are much better than Recluse spiders.
- Thugs and Maces beat rocket bots despite the range.
- Arbiters have very long range and are very vulnerable up close.
- Rascal (`corfav`) is a scout car, not a fighter; Incisor (`corgator`) is a
  light tank. One Incisor cannot kill an LLT; two can, easily.
- The Behemoth (`corjugg`) is extremely defensive.
- Juggernauts explode when they die.
- Drone carriers and Epic Tumbleweeds are not worth their stats; they do not
  hold against Titans and Thors.
- A rolling bomb's death is its weapon; a nuclear one that dies at home
  detonates in our base.
- Long-range plasma cannons out-reach even a Pulsar.
- A single T2 tank can kill a commander: it outranges and outruns him.
- With respawning commanders (`comrespawn`) the Effigy is what must survive;
  evolving commanders (`evocom`) grow very strong, but killing the commander
  is still often the game.

**Water**
- A unit is *on* the water or *in* it, and what can hit what follows.
  Torpedo launchers hit every ship and sub but not hovers. Subs hit anything
  in the water but not hovers. Destroyers hit subs; most boats cannot.
  Amphibious walkers underwater mostly cannot shoot; amphibious tanks have no
  underwater weapons.
- Most boats fire plasma, which shields stop.
- Once a side holds the water completely, a shipyard cannot be built at all.

**The map and the enemy**
- The enemy base is in their start box.
- Humans build jammers aggressively; not seeing the enemy is normal, not a
  sign they are weak.
- Humans attack around the edges of a line, slowly over time. The ends of the
  line and the map edges are the exposed places.

## 3. Contracts

**Orders**
- No order overrides common sense: a fragile unit never walks blind into
  enemy fire. Halting to fire, standing off and routing round are all fine.
- Never give a unit a target it cannot hit, whether it is out of range or in
  the air.
- Use move orders plus set-target, not attack orders. Snipers take only
  those. A unit that wants spacing or wants to run never gets a fight order.
- A fight order to a single point is wrong: a squad is a frontage, not a
  coordinate.
- Order priority: retreat over dodge over standoff over guard. Others follow
  the same principle: survival, then firing position, then commitment, then
  formation, then station.
- A task does not keep changing its own mind. A squad commits to a target; it
  never stands in fire turning in circles.
- Check that an order survives before crediting a movement fix: a unit
  re-ordered every few seconds never reaches its position.

**Movement**
- Standoff, dodge and retreat moves never walk into a new threat.
- Move at the speed of the slowest unit in the group.
- A unit joining a fight joins the squad, not the target; no trickling in one
  at a time.
- A long-range unit's standoff is its own weapon range, not the squad's.
- A tower that cannot fight back is attacked, not orbited. A static cannot
  chase, so a squad hovering just outside a tower's range, unable to shoot,
  is wrong: it commits or leaves.
- A retreating unit adds no power to the units still fighting.

**Specific units**
- The commander uses his D-gun; he never trades laser against laser with the
  D-gun ready.
- A bomb (rolling or otherwise) never retreats. Rolling bombs never join a
  squad: each goes straight at an enemy, keeps away from our own units, and
  they arrive separately from different bearings.
- A wave over its target cell is committed. The AA shapes the approach; once
  inside, nothing is refused for threat.
- After a drop, a transport goes home. It never keeps holding cargo.
- Rez bots react within a second, stand behind our units, and back away
  before enemies come in range.
- Stuck units are reclaimed, never the commander.
- AA units do not join ground pushes.

## 4. Priors: the economy and the base

**Economy** (the arithmetic is `docs/23`; these are his defaults on top)
- Always be making economy: energy and converters, always.
- The opening order is learned, not ruled (2026-10-08). With a high bonus the
  commander's income can carry factory-first; at +0 the factory must not
  come first.
- Factories get at least BARb's support: nanos in reach by tier (T1 2, T2 4,
  T3 9), and idle builders near a recruiting factory assist it.
- Support a plant, don't multiply it. One gantry with heavy nano support
  beats several barely supported. Nanos go fully adjacent to labs and
  gantries, with no side gap. About four advanced air plants with heavy nano
  support, not ten.
- An idle production line is never a reason to buy another; unspent metal is
  army, not a shortage of hands.
- Move from fusion to advanced fusion in time, with converters to match.
- Reclaim obsolete buildings (old energy, converters, defences) quickly, and
  never rebuild what was just reclaimed as obsolete (keep a buffer against
  flip-flopping).
- Too many ground constructors idle or walking means prefer air constructors.
- Builder roles come from target gaps, not from the draw's own shares.
- Don't start a T2 lab while visibly losing the front line.
- One eco player carrying the team is bad.
- **The eco seat (8v8):** one player does economy only until about 1,000
  metal/s (scaled by the bonus). That player sits in the middle back, never a
  corner, with zero defence while growing, and no gantry until it means to
  make army. Putting all build power onto one fusion is that seat's rule, not
  the standard game's.

**Expansion and constructors**
- Rebuild a lost extractor, even at home. Don't behave as if afraid.
- Escort constructors that go out to build extractors or anything outside
  the base. Even air constructors get a little fighter escort.
- An escort must be able to win: it has to beat the raider it catches, not
  just catch it.
- Escorts are not a late-game posture. Late, the cheap units go forward as
  fodder instead of standing in the base.
- Tit for tat: if our constructors get harassed, we harass theirs. Raiders
  raid all game.
- Extractors outside the base get guards. Guards scale with how soon the
  enemy can reach the spot, so a spot nearer their base needs more. Defences
  stand just outside the base; a gun inside the base only when it is an
  extractor's only cover.
- The commander takes the most dangerous extractors so constructors take the
  safe ones. He is safe from T1 raiders (in danger he builds towers around
  himself) but not from T2.
- A safe site is started by whoever gets there first, usually the air
  constructor. A front-line site belongs to the ground crew.

**Defending the base**
- Military exists early. Three constructors before any army was an issue.
- See threats coming. A push is visible long before it reaches the base.
- Size a squad for each threat and hunt it down. Read their path and
  intercept before they reach our buildings.
- Expect raiders from five angles at once, after five different buildings.
- Early on, field twice their raiders (2 against their 1, 10 against 5, his
  ratio).
- Light, fast units are the interceptors, and the first units out of the lab
  are light ones. Riot units hold a post; fast units (Pawns, Grunts) do the
  chasing. Make enough of them: far more Pawns than we do, and Centurions for
  Armada; Cortex sticks to Grunts.
- Keep some of the army near every part of the base, spread enough to react.
  A unit standing by a building is cover for it, like a turret. But attacks
  come at the front of the base, not the back, so the lines face the front.
- The held army leaves: a full cover pool goes on to attack, and cover is
  sized by the raider metal they field, not by our building count.
- Defend the deep interior, not only the border, and cut off reinforcement
  routes.
- Guards answer attacks on nearby parts of the base, and stand as a wall, not
  as a huddle on the best extractor.
- When the enemy is closing on the base at T2, the answer is T2 or T3
  defence. Decide while they are still walking, so the gun stands when they
  arrive.
- Against a big blob: beamers and HLTs to do the damage, a jammer so they
  can't see what they walk into, and construction turrets behind so the guns
  are repaired and rebuilt.
- One gun is not a defence: where one gun stands, more belong. Where nano
  turrets are massed, fortify that ground and put a shield there.
- Don't heap defences in the middle while a flank is being raided. Defend the
  raided side, and the map edge.
- When most of the army is away, the base buys extra defence; the army at home
  counts as cover.
- Answer incoming long-range plasma fire with shields. Remember the sighting,
  and let it fade if nothing shells us.
- AA follows the enemy air we have seen. Later in the game (later by economy,
  not the clock) flak spreads round the base whether or not air has shown up.
- The commander defends the base against T1 attackers and accepts the risk of
  dying for it, and spams the D-gun while he has the energy. He does not chase
  scouts he cannot catch (he builds a turret where he stands instead) or chase
  anything "into the sunset". He values himself and enemies by power (hp,
  range, dps, speed), not metal. How careful he is depends on the game mode:
  in default T2 play, careful. Against enemy T3 he can wait cloaked under a
  jammer and surprise it with the D-gun.
- **Front line:** the army holds a line where our ground ends, at a narrow
  part of the map if there is one, so nothing goes round it. It fights inside
  nano range so it is healed while fighting. When the forward lane is lost,
  it pulls back; while rebuilding, it defends the border instead of trading
  badly outside. From the border it sieges them at long range, and it keeps
  growing: make more military, waste none of it, overwhelm.

## 5. Priors: the army

**What to build**
- The line is chosen for the map: vehicles where vehicles are stronger.
- Facing a high-dps unit that outranges us, build a longer-range answer at the
  T2 lab.
- Splash is worth what it hits: big area damage against massed T1.
- When the enemy is encroaching and winning, build the Behemoth.
- Rez bots, enough of them early. They are worth more with valuable reclaim,
  units to repair and units to resurrect. They travel with the army, heal it
  mid-fight, eat the wrecks in front of it, and move to safety after a job.
  Long-range artillery is not a reason for them to stay home; some dying at
  their work is accepted.
- No T1 ground army once a player's T2 plant stands (scouts are exempt).
- Every player gets a gantry, in an 8v8 by about 38 minutes.
- The late game is won by gantry units, nukes, heavy air and long-range plasma
  cannons. Prefer a nuke silo to an early Basilica, and fewer gantries plus
  more nukes and LRPCs. Late, about three anti-nukes.
- Late game, cheap fast fodder (Ticks, Grunts, Pawns, Rascals) runs straight
  at their base, ungrouped, for vision and distraction. Scouts attack
  constantly while the main army attacks.
- **Water maps:** build navy early; whoever takes the water first holds it
  more easily.
  - Where water splits the map, everyone goes water; the economy stays on
    land.
  - Shipyard first, never a hover or land lab first. Torpedo launchers and
    floating radar defend our water.
  - On mixed maps, someone builds a shipyard in any large water with
    extractors in it.
  - Build for where the enemy is: against heavy water, hover tanks.
  - Hovers plus air win the water back. If the water is lost: air, torpedo
    bombers, shoreline defence and shields.
  - A unit that cannot reach the enemy is worth nothing.
- Transports carry army to raid or flank, fly towers forward, or sneak a
  constructor behind their lines. Build only as many as are used.

**Formation**
- Curves and lines, never a ball. Cross the T on the enemy and form a wall:
  every unit fires as they come in, and nothing leaks through. Units that can
  be D-gunned together spread out. Cohesion is the squad's mean radius.
- Enter the fight together: spread out before contact, not as a column.
- A T2 army is a tanky screen in front, long range behind, radar and jammer
  support, and rez bots healing. The anchored ladder is one Mammoth, a radar,
  a jammer, ten Sheldons and five Arbiters guarding it, with more Mammoths as
  the squad grows.
- The screen shields the guns. It does not need to deal damage and holds its
  rank in front of the guns even when that is outside its own reach.
- Radar and jammer units stay behind their squad, at most two of each per
  squad. Units, especially fragile ones, stay inside the squad's jammer.
- Fragile units stand further out on the line, screened by healthier ones.
  Hurt units (under 60% health, his number) move to the back and keep
  fighting.
- The squad falls back together when its total health is low. Once in
  contact, it fights or leaves as one.

**Range and movement**
- Fight at about 90% of maximum range (his number) and almost always keep
  moving. Kite often, but only units whose firing arc allows it.
- Amphibious tanks do not act cowardly.
- Back up before the enemy can fire back. A unit that dies to one hit moves
  away when the enemy is within 90% of its own range.
- Long-range units stay at maximum range, and don't advance blind: no vision
  or protection, no moving forward. A unit with the range advantage holds and
  *fires*; it does not leave the line.
- Long-range siege units (Starlight, Ambassador, Arbiter) siege enemy bases
  and stay safe while doing it, with scouts showing them targets. An
  Ambassador outranges many T2 turrets. Siege units fear enemies getting
  close.
- Indirect fire is the exception: rocket-style enemies can be stood inside,
  moving.
- A stronger unit doesn't run from a longer-ranged weaker one. Short-range
  brawlers aren't walked up into the enemy. Long guns don't run deep to fight
  close. Low-HP units are more careful than high-HP ones.
- To kill a sniper, dive in.
- Of two equal positions, take the safer angle.
- Through a turret's reach only with the intent to kill it; otherwise route
  round, and route further away when fire comes unexpectedly.
- Don't be flanked; flank them. Attack round the side, not straight up the
  middle. When they form an encirclement, wrap the edge of their line. Big
  slow units go straight.
- Don't walk many times the needed distance round enemy defences, and accept
  more path risk when needed rather than switching the careful logic off.

**Targets**
- Focus the lowest-HP enemies in lethal doses, not everyone on one target.
  Finish what is nearly dead.
- Kill long-range units and artillery first; don't let their artillery pile
  up.
- Big T3 units ignore small ones and go for bases and economy. Near the enemy
  base, dive for the economy: advanced converters and fusions over military
  and towers.
- Economy priority: energy, then metal, then build power. There is no
  commander-hunting doctrine.
- A tower we can't kill is being repaired: kill the repairers first.
- A defended building: a scout gauges it, calls just enough units, pulls back
  out of sight, waits for them to group, then strikes.
- Don't bomb a building under construction when the finished one beside it is
  what explodes.
- Allies don't all pick the same target. Prefer targets near our base and on
  our side. Weigh the enemy's walk to our base against ours to theirs.

**Raids**
- Raiding is not optional, and defending only is losing slowly. We want the
  enemy chasing us on *their* side of the map. Some of the army is always on
  their half, and that share is not just what is left over after guard duty.
- Higher-level knowledge may call a raid on undefended ground and pull units
  from wherever is appropriate.
- After a raid on extractors, go further and take out more; don't walk home.
- Cheeky moves win games: run the map edge and pop converters. Marauders and
  their like are raiders: around the line, not through it. Penetrate deeper
  into ground believed empty.

## 6. Priors: when to fight

**The odds**
- Any fight taken and lost was the wrong fight. Compare our power in the area
  with theirs and go in only if ours is enough. Don't believe we are
  overwhelming something superior. Judge on the squad's real health.
- After losses (a low recent kill/death ratio), demand better odds, build more
  army and use it in defence.
- Unknown does not mean small. Size the enemy from the most seen at one time
  over a window.
- Group size scales with economy and army. The enemy masses big and kills our
  small masses one by one, so mass as hard as they do. The whole army arriving
  matters as much as its shape.
- Ignore enemies under half our strength unless defending home (his number).
  Don't chase light units off the front, and small spam is not worth turning
  for.

**At home**
- If the base is pushed, defence comes first: meet that army and destroy it.
  Don't keep distance from an army wrecking our base when we have more. Don't
  pull the army out of a base under attack to join a squad elsewhere.
- Defending at home takes about 1.2× parity (his number).
- Hold and let them come when they are stronger. Make them bleed on our ground
  at our range, and control where their metal falls so we can reclaim it.
- After losing a big fight with few units left, don't leave the base until
  rebuilt.

**Away**
- Push. With no significant threat in sight, the army keeps going toward their
  base. Pushing is the default, not a reward for being stronger. Attack their
  start box even blind. Mass scouts, launch them together, and let what they
  find decide where to hit.
- On the way to their base, a flank or their economy, don't be distracted by
  their units: shoot them on the move and keep going.
- Be the aggressor only when we have built for it. If we chose economy and they
  chose offence, our army is for holding. If they turtle, scale up and scout.
- If the front moves back into us, build army and push it back. If it shifts
  round a side, defend that flank before the damage.
- A committed push never regroups somewhere safe. Punch through the line and
  stay in their back lines killing bases. The T1 commit is all or nothing.
  Chargers and colossi keep moving. A squad that has just won presses on to
  remembered enemy positions. Either commit to the base or come home; never
  roam.
- Don't be cowardly against a base we could take, or abandon a nearly won
  endgame: an enormous army saturates a doomsday gun, it doesn't orbit its
  range ring.
- When ready, push more. There is no cooldown.
- Under lag, all in: no holds except a base actually under attack, and no
  retreats.

**Their army or their economy**
- The default is to attack their extractors and economy and defend against
  their army. Don't send the army at their wall. A free extractor to kill beats
  walking off to fight army in the middle.
- But sometimes kill their army, and eat it (2026-10-08). If we only ever hit
  fortifications and let our army be picked off bit by bit, they end up with a
  big army and we have very little. Seek out their army when it pays, destroy
  it, and reclaim or resurrect the wrecks so our army grows from theirs.
- A roaming army can't be stopped everywhere, so make it pay. Counterattack
  their base while it attacks ours, or kill it on our ground and reclaim it.

**Retreat**
- In a fight it clearly can't win, a squad turns around immediately and fights
  under our towers if any are near.
- Retreat to the chokepoints and front, not the home base. Concentrate opposite
  their army; never split ours to walk home. Where the only way in is a gap,
  the whole team holds the gap.
- A Titan is never walked home, and never parked at home because shells are
  landing.
- Retreating at very low health is a symptom: look at the action before it.

**Air**
- Air superiority first. Against heavy enemy air, mass fighters to hunt theirs.
  Mass to at least their fighter count before attacking; never go in with one.
- Air hits the home base, not small extractor emplacements, and varies its
  targets. It coordinates with the land fight on the same front.
- Bombers mass, then strike the economy in one mass, and don't wait forever.
  While a strike is being held, the plants make bombers without pause. Scouts
  are bought for the wing so it knows what to hit.
- A raid past the point of no return commits.
- An early atomic bomber is a strike by itself: scouts find the gap in their
  AA, and it flies round the AA, not through it.
- A gunship's role follows the enemy's AA: it fights units under an empty sky
  and acts like a bomber, hitting the economy, under heavy flak.
- Pool aircraft on the ally who has the most, so the next raid launches
  sooner. Any player may buy bombers.

**Turtles**
- A player who sees a big air or nuke attack coming turtles: shields, AA,
  anti-nukes. The answer is weapons that outrange their defences.
- When our attacks keep dying to their defences, build long-range plasma
  cannons in range of them. They shoot buildings and shields, never units.
  The other way in is missiles at the defences: Paralyzer (Armada) and
  Catalyst (Cortex).

## 7. Where priors pull against each other

These are not mistakes to resolve by picking a side. Each depends on the
situation, so each is a decision for a net to learn, with his default as the
rule option.

| Tension | Default today | Decided by |
|---|---|---|
| Push by default vs go in only with a local edge | push; edge judged per fight | C++ squad odds; join-fight net (GO/STAY) |
| Hold and let them come vs pressure on their half | posture from the stance read | posture net (nnpost) |
| Raid their economy vs kill their army | economy | raid net (GO/WAIT); hunt net (NO/HUNT, rule NO) |
| Mass the army vs stay spread to react | mass to their group size | pool size rules; not a net |
| Escorts mass with mass vs each constructor covered | each exposed constructor's floor first, then mass (his 2026-10-08 game: 8 escorts on one, none on the rest) | escort net (LIGHT/MATCH/HEAVY) |
| Army share vs economy share | his share of the economy built (`docs/23`) | team plan net (RUSH/GREED/TURTLE...) |

## 8. Open questions, his to rule

- Titans: each beelines alone (his 2026-08-19 ruling, the code today), or a
  group goes together as BARb's do?
- Does a gunship finished mid-strike join the wave out? Is a strike ever
  recalled because home outgrew it?
- When does seeking out their army pay? (A rule, or a net decision priced on
  their army destroyed plus the reclaim against our expected losses.)
