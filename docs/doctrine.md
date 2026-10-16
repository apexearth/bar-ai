# Doctrine

apexearth's directives for how this AI plays, and only his (a fact marked verified was checked
in source). A session adds a line here only from something he said, never from its own idea; dated quotes and incidents live in git
(`git log -p docs/24-how-units-fight.md` holds the old dated form). Code that breaks a line
under **Never** is a bug. A **Do** line is a default the nets may overrule where training shows
it loses; a number here is his, carried as the default, never as a threshold to code.

## Goals

- Fun to play against comes first: surprise and challenge, and interaction all game. A huge economy followed by one overpowering army is the boring arc.
- Beat BARb in even games more than 80% of the time, and end a game when it can be ended.
- Win by killing them: going hard on offence is the only way a game is won.
- The base never dies: army and defence at home can absorb their whole army arriving as one body.
- Make the game worth watching: bombing raids, nuke salvos, long-range plasma; sudden huge actions.
- Multiplayer on the host is the target; live decisions use only what a player could see.
- Judge a fight by damage efficiency (dealt over received) plus the wrecks: our loss is their reclaim.
- Lag is a cost: tiny units and a big army parked at home lag every player.

## How decisions are made

- Every decision answers: what is the fastest path to the state we are trying to reach. Order, numbers and limits are outputs.
- Derive a quantity from the economy (income, bank, cost, return); if it cannot be derived, ask him.
- A role changes how much or how often, never whether.
- Balances are the nets' to discover; the nets always decide, exploring by small nudges around what they would play.
- A quantity is a continuous value over a generous range, never a few bins; an integer count is a real value the game rounds up.
- Only a true impossibility vetoes an option; every judgement is a price, so the option can still be tried and learned.
- Proportional draws, not argmax, where weights mean ratios.
- AI work is spread across frames; slower orders beat a hitch.

## Do

**Economy**
- Always be making economy: some hands are always on generators and converters, and converters grow with the energy that feeds them. Scaling the economy matters all game, unless a special strategy will end the game early.
- Metal first: build the extractors, upgrade them, then protect them.
- A T2 constructor upgrades extractors before anything else it could do there, allies' extractors included; one hand per extractor.
- One T2 constructor stays on the fusion with T1 help; the rest go out and upgrade every extractor, the outer ones too.
- Start fusions soon, alongside the upgrade walk; move on to advanced fusion in time, several reactors at once when affordable, no gap between them.
- Advanced fusion before the Epic reactor.
- Answer an early energy stall with a solar: it costs no energy to build.
- Spare metal goes to the economy while the enemy out-earns us, to army only once we out-earn them.
- Concentrate spending under scarcity: few sites at once, finished; parallel expansion is licensed by income.
- Support a plant before multiplying it (assisting a factory beats building more of them, less so as we grow rich, and units still need time to leave the pad): nanos in reach before any second factory, enough to spend our income through it (about income / gantries / 8.3 m/s per turret; at least BARb's T1 2, T2 4, T3 9).
- Nano turrets stand fully adjacent to labs and gantries, in blocks.
- A factory may pull every nano that can reach its unit off a building and onto its production.
- Gantries scale with wealth, each heavily supported; in a team game allies share one nearby gantry; every player has one by about 38 minutes of an 8v8.
- The gantry comes when the economy can carry it, before a second T2 lab and before the enemy's T3 arrives.
- Upgrade allies' extractors too, and give a T2 constructor to an ally that has none.
- In a team game one seat goes T2 a little sooner and hands out T2 constructors as allies' extractors need them; the others stay T1 with a strong army, upgrade their extractors with the handouts, and build their own advanced lab later, not never.
- When the enemy can reach us soon (small or crowded maps), army comes before tech: build the economy and a strong T1 army first, then the T2 lab.
- Spilling metal and short of hands: an air plant and many air constructors; lots of T1 air constructors is fine, late too.
- An air constructor starts a safe big build; a front-line site belongs to the ground crew.
- Builders work near where they are.
- Rebuild a lost extractor quickly, at home too.
- Reclaim obsolete buildings (old energy, converters, defences, T1 construction turrets once T2 ones exist) once the replacement stands.
- Reclaim and resurrect the battlefield's wrecks: the field on our side is an army.
- Escort constructors that leave the base, air constructors with fighters; an escort is sized to the threat and must be able to win.
- Tit for tat: if our constructors get harassed, we harass theirs.
- The eco seat (8v8) does economy only until about 1,000 m/s (scaled by the bonus): middle back, never a corner, many nanos, few T2 ground constructors, no defence while growing, no gantry until it means army.
- Same-size buildings line up exactly on one lattice; packing is tight with room only for units to move; one walkway system for the whole team, as wide as the biggest unit its plants make.
- Big builds go where the nano turrets are; an advanced lab goes near our extractors.
- Spread the economy by the share we can afford to lose at once: fusions explode together.
- Transports move nano turrets to where they are worth most, carry army past hard pathing or round a flank, fly towers forward, sneak a constructor behind their lines.
- On a crowded map, fewer and stronger seats of ours.

**Defence**
- Defences are the fallback: metal goes to army first, and the army kills theirs before it reaches the towers.
- A seat's defence follows its danger: some seats sit in the enemy's path and invest far more; in 1v1 every seat is in the path.
- Strong defence every game, standing at every angle the enemy can come from.
- Keep them out with room to grow: the ring stands on the alliance's outer edge, bigger than the base, and gaps are found and closed continuously.
- Every extractor outside the base gets a gun, more the sooner the enemy can reach it; guns stand just outside the base, inside only as an extractor's only cover.
- Refill defences where they just fell: the enemy comes back through the hole.
- Guard the flanks and the map edge: answer raiders that go round the towers and stand guards where no tower covers the economy.
- Where one gun stands, more belong; where nanos mass, fortify and shield it.
- Against a blob: beamers and HLTs, a jammer over them, construction turrets behind to repair and rebuild, cheap things in front.
- When the enemy closes on a T2 base, T2 or T3 defence, decided while they are still walking; seriously behind, lean into T3 defence.
- Shields answer long-range plasma fire; jammers go over a defence taking long-range fire.
- AA follows the air we have seen; later in the economy, flak spreads round the base regardless.
- With most of the army away, the base buys extra defence; army at home counts as cover.
- Anti-nukes cover where the base actually is, more as it grows out; about three late.
- When our attacks keep dying to their defences: LRPCs in range of them, or Paralyzer/Catalyst missiles.

**What to build**
- Military exists early; the first units out are light and fast, and early on we field twice their raiders.
- Make enough fast interceptors: Pawns and Centurions for Armada, Grunts for Cortex; riot units hold a post.
- The line follows the map (vehicles where vehicles are stronger) and the enemy (on water: ships, hovers, seaplanes).
- Facing a high-dps unit that outranges us, the T2 lab builds a longer-range answer.
- Splash against massed T1; the Behemoth when they are encroaching and winning.
- Rez bots early and enough, travelling with the army, healing mid-fight, eating wrecks in front of it.
- Get to T3 fast; by about 30 minutes spend on economy and T3; T2 air is the exception.
- Past a gantry, T1 labs make only fodder and T2 labs only the bigger units.
- The late game is won by gantry units, nukes, heavy air and LRPCs; a nuke silo before an early Basilica.
- Late, cheap fast fodder runs straight at their base ungrouped, for vision and distraction; scouts attack while the army attacks.
- A unit justifies itself when it deals its own health in damage; fodder and fighters are never judged.
- Strategy is drawn per game (LRPCs, nuke salvos, mass air, T3 rush, early all-in, greed against a passive enemy), never a hidden random roll.
- Nuke salvos: many silos fire at once on one base; bombers mass and strike together.
- LRPCs on high ground; on a small map where they reach their base, many of them.
- Siege a fortification on purpose: decide on the emplacement, build units that outrange it, give them a squad for it alone.
- Transports only as many as are used.

**Formation and movement**
- Curves and lines, never a ball: cross the T, every unit fires as they come in.
- Enter the fight together, spread before contact; move at the slowest unit's speed; a joining unit joins the squad.
- A T2 army is a tanky screen in front, long range behind, at most two radars and two jammers per squad behind, rez bots healing; units stay under the jammer.
- The screen holds its rank in front of the guns, even out of its own reach.
- Fragile units stand further out, screened; hurt units (under 60%) move to the back and keep firing.
- The squad falls back together when its total health is low; in contact it fights or leaves as one.
- Fight at about 90% of maximum range and keep moving; kite where the firing arc allows.
- A unit that dies to one hit backs off when the enemy is within 90% of its own range.
- Long-range units hold maximum range and fire, with vision; siege units siege bases with scouts showing targets.
- Outrange a D-gun-like weapon from outside its reach; only fodder closes in.
- Flank: attack round the side; while our body holds their front, a second group takes their ball from the side; big units flank too.
- To kill a sniper, dive in; inside indirect fire, keep moving.
- Of two equal positions, take the safer angle; through a turret's reach only to kill it.
- All-terrain units squad apart from units that cannot climb.
- Air flies spread out against splash.

**Targets**
- Focus the lowest-HP enemies in lethal doses; finish what is nearly dead.
- Kill long-range units and artillery first.
- Big T3 units go for bases and economy; near their base, dive for advanced converters and fusions.
- Economy priority: energy, then metal, then build power.
- A tower we cannot kill is being repaired: kill the repairers first.
- A defended building: a scout gauges it, just enough units are called, they group out of sight, then strike.
- Prefer targets near our base and on our side; weigh their walk to us against ours to them.

**When to fight**
- Push by default: with no significant threat in sight the army keeps going toward their base, even blind; there is no cooldown.
- Army is worth only what it does: an army that is not fighting or taking ground is waste. Use it as soon as a group can win somewhere, against the target it can beat now, not the one it might beat later.
- Decide once whether to fight a defended point: commit with enough to win, or keep out of its reach. Re-decide only when something real changes.
- A unit never fights what kills it in one hit or what its class loses to; the units that win that matchup fight it, and production answers the army they field.
- Split a group by matchup: units that beat a threat fight it, units it counters go around it to their economy.
- Concentrate: meet their main army with ours whole, never in pieces, and destroy their separated groups one at a time with overwhelming force.
- Focus fire: a committed group shoots together, killing whatever deals the most damage first, armed targets before structures that do not shoot.
- A raid is a group that goes around their army to their economy: gather to the size the target needs, launch whole, and strike their flanks -- targets their army cannot reach before the work is done, along a path that skirts it. Units never trickle in after it.
- Some of the army is always on their half, and we want them chasing us on their side.
- Default: attack their economy and defend against their army; sometimes seek out their army, destroy it and eat the wrecks.
- Go in only with enough power in the area, judged on real health; after losses demand better odds and build more army.
- Size the enemy from the most seen at one time; unknown does not mean small.
- Mass as hard as they do: one big, simple army that moves and fights together.
- In a team game "ours" is the side: weigh a fight with every allied army near it.
- When the base is pushed, meet that army and destroy it (about 1.2x parity at home).
- When they are stronger, hold and let them come: bleed them on our ground at our range and reclaim their metal.
- A committed push punches through and stays in their back lines killing bases: commit to the base or come home.
- On the way to a target, shoot on the move and keep going.
- Join a fight only if we arrive while it still rages.
- Be the aggressor when we built for it; if they turtle, scale and scout; if the front moves back into us, build army and push it back.
- The front line holds where our ground ends, at a narrow place, inside nano range; from the border it sieges them and keeps growing.
- Retreat to chokes and the front, concentrated opposite their army; a squad waiting to gather waits closer to the enemy.
- A squad in a fight it clearly cannot win turns at once, under our towers if any are near.
- Under lag, all in: no holds except a base actually under attack.

**Raids**
- Raiders raid all game; defending only is losing slowly.
- A raid deals the most economic damage it can and is often a suicide mission; once chosen it commits, walks past small things and takes damage to reach the economy.
- After hitting extractors, go further; a held-up raid calls air or a nuke to clear a hole.
- Run the map edge and pop converters; raiders go around the line, deeper into ground believed empty.
- Higher-level knowledge may call a raid on undefended ground with units pulled from anywhere.

**Air**
- Air superiority first: against heavy air, mass fighters to at least their count and hunt theirs.
- Bombers mass, then strike the economy at once; plants keep building them while a strike is held; scouts are bought so the wing knows where to hit.
- Air hits the home base's economy, varies targets, and coordinates with the land fight on the same front; fighters first, then bombers, gunships and atomics on one point.
- A wave over its target commits; a raid past the point of no return commits.
- Dragons and gunships go for converters and fusions, not defences; a gunship's role follows their AA.
- An early atomic bomber flies round the AA through the gap scouts found.
- Pool aircraft on the ally who holds most; any player may buy bombers.
- A push about to break off calls the air wing instead of turning home.

**Water**
- Navy early: whoever takes the water first holds it more easily.
- Where water splits the map everyone goes water and the economy stays on land; shipyard first.
- Torpedo launchers and floating radar defend our water; someone builds a shipyard in any large water with extractors.
- Against heavy water, hover tanks; hovers plus air win the water back; water lost means air, torpedo bombers, shore defence and shields.
- Commanders may build water plants.

**The commander**
- Survival is paramount, and the base matters more: T1 attackers on the base are his to kill, with the D-gun spammed while energy lasts.
- Early he leads to mid with the army, well protected; from T2 he stays home and is careful.
- He takes the most dangerous extractors; in danger from T1 he builds towers round himself.
- He values himself and enemies by power (hp, range, dps, speed), not metal.
- When only he can save the base he fights as a trap: cloaked where the attack is coming, D-gun from inside. In a team game only if he can win; hopeless, he runs.
- Against enemy T3 he can wait cloaked under a jammer and surprise it.
- With respawning commanders, the Effigy is what must survive.

## Never

**Decisions**
- A threshold, build order, cap, floor or exclusivity written by hand; a constant wearing a tunable's clothing.
- Overturning a ruling of his without asking him.

**Economy and base**
- An idle factory beside unspent metal, or an idle line as a reason to buy another.
- A plant built with no wanted output; capacity bought where it cannot serve anything.
- A copy of an owned plant while its nanos are short. Never waived.
- Nano turrets ordered faster than metal can feed them.
- A seat with no new fusion for minutes; one eco player carrying the team.
- Reclaiming economy before its replacement stands, or rebuilding what was just reclaimed as obsolete.
- Basic converters once T2 hands can convert the surplus; a pile of basic towers inside the base.
- T1 hovers on maps without water use, or past T2.
- A builder walking halfway across the map for a job; a whole crew converging on one extractor.
- Too many ground constructors idle or walking (prefer air constructors).
- A T2 lab started while visibly losing the front line.
- All the energy in one ball.
- Escorts as a late-game posture, or massed on one constructor while the rest go bare.
- Allies blocking each other's walkways; units penned by openings narrower than the plants' units.

**Defence**
- Defences heaped in the middle while a flank is raided.
- One gun called a defence.
- Defences squeezed inside our little base.
- Radar eating a tenth of the constructors' time.
- Shields where nothing can shell them; a second jammer beside the first; flak clustered at the nano block.

**Army**
- A big army that never attacks, or parked at home.
- T1 army once a T2 plant stands (scouts and fodder exempt).
- Probing for the weakest spot and switching each time it gets backup.
- A T3 army walking back and forth across the field.
- A Titan walked home, or parked at home because shells are landing.
- Our army spread all over the map while they bring one ball.
- Pulling the army out of a base under attack, or keeping distance from an army wrecking our base when we have more.
- Leaving the base after losing a big fight, before rebuilding.
- Retreating to the home base, or splitting the army to walk home.
- A committed push regrouping somewhere safe, or roaming.
- The whole army chasing one Pawn; chasing light units off the front; turning for small spam (ignore enemies under half our strength unless defending home).
- Cowardice against a base we could take; an enormous army orbiting a doomsday gun's range ring.
- Every ally picking the same target.
- Unarmed scouts into a fighter wall; going in with fewer fighters than theirs.
- Gunships trading with defences.
- Bombing a building under construction when the finished one beside it is what explodes.
- Drone carriers and Epic Tumbleweeds.
- Amphibious tanks acting cowardly, or engaging a fleet.

**Orders and unit control** (correctness, never overruled)
- A fragile unit walking blind into enemy fire on any order.
- A target the unit cannot hit, out of range or in the air.
- Attack orders where move plus set-target works (snipers take only those); a fight order to a unit that wants spacing or to run; a fight order to a single point.
- Order priority other than survival, then firing position, then commitment, then formation, then station (retreat over dodge over standoff over guard).
- A task changing its mind every few seconds; a squad turning circles in fire; an order re-issued before the unit can arrive.
- New destinations handed out constantly, orders to unreachable places, units left stuck: each is a path search.
- A standoff, dodge or retreat move into a new threat.
- Trickling into a fight one unit at a time.
- Hovering just outside a tower's range unable to shoot: commit or leave.
- A retreating unit counted as power for the units still fighting.
- A long-range unit's standoff taken from the squad's range instead of its own; a long gun leaving the line; brawlers walked up into the enemy; a stronger unit running from a longer-ranged weaker one.
- Walking many times the needed distance round enemy defences.
- The commander trading laser for laser with the D-gun ready; a D-gun that kills our own buildings.
- The commander chasing scouts he cannot catch, or anything into the sunset; running to end up the last one standing.
- A bomb retreating; rolling bombs grouped or arriving together; a nuclear rolling bomb dying at home.
- A wave over its target refusing a target for threat.
- A transport holding cargo after a drop.
- Rez bots in front of our units or slow to react.
- The commander reclaimed as a stuck unit.
- AA units joining ground pushes.

## Facts of the game

- (Verified in the engine source.) Flanking: damage x (1.5 - 0.5 x dot(dirToAttacker, front)), 1.0-2.0; the first hit sets the front, which regrows slowly once the unit stops being hit.
- A dead unit leaves a wreck worth about half its metal; whoever holds the ground reclaims it. Reclaim yields metal; resurrection spends it.
- Converters turn about 60 energy into 1 metal; converters and fusions are explosive and fragile.
- Extractor spots are fixed and few, so late income is energy and conversion; upgrading an extractor is worth most when income is small.
- Unit stats misprice units: projectile speed and accuracy do not show in them.
- Starlight fires only in its forward 180°; snipers fire all round and are much better than Recluse spiders.
- Thugs and Maces beat rocket bots despite the range; a rocket bot (475) outranges a basic LLT (430).
- Arbiters have very long range and are very vulnerable up close; an Ambassador outranges many T2 turrets.
- Rascal is a scout car; Incisor a light tank (one cannot kill an LLT, two can).
- The Behemoth is extremely defensive; Juggernauts explode when they die.
- A single T2 tank can kill a commander: it outranges and outruns him.
- LRPCs outrange even a Pulsar.
- A bomb that lands after its plane died still counts.
- A tower being repaired can heal faster than we damage it.
- (Verified from the weapon defs.) A silo reloads in 30 s and an anti-nuke in 2 s, so a salvo needs many silos firing at once, not one silo's stockpile.
- On water: torpedo launchers hit ships and subs, not hovers; subs hit anything in the water, not hovers; destroyers hit subs, most boats cannot; amphibious walkers underwater mostly cannot shoot.
- Most boats fire plasma, which shields stop; once a side holds the water, the other cannot build a shipyard.
- The enemy base is in their start box; humans jam aggressively, so not seeing them is normal.
- Humans attack round the ends of a line and the map edges, slowly over time.
- The commander is the main early builder and usually the game; he often dies to the last long-range shots while already retreating, so health is the honest danger signal.
- A game that reaches T3 often runs 45+ minutes.

## Open questions, his to rule

- Titans: each beelines alone, or a group goes together as BARb's do?
- Does a gunship finished mid-strike join the wave; is a strike ever recalled because home outgrew it?
- When does seeking out their army pay: a rule, or a decision priced on their army destroyed plus reclaim against our losses?
