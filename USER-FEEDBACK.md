# What apexearth wants from this AI

My understanding of the feedback he has given, in my words. This is a standing
brief, not a changelog — `CHANGES.md` records what was done and measured, this
records what he actually asked for and why.

Items marked **UNRESOLVED** have been raised and not fixed. Several have been
raised repeatedly, which is itself the point: re-reading this before starting
work is cheaper than being told the same thing a fourth time.

---

## The Brain owns (nearly) all building — standing architecture goal

2026-08-15, watching: "We should have almost all our building going through
the brain... the brain should 'want' economic expansion. It should want this
pretty much always. Only time to stop wanting that is when it believes we're
a lot more powerful than the enemy and at that point we can just dedicate to
attacking."

So: a standing **economic-expansion want** in the Brain, near-always on, whose
value falls only when our power clearly dominates the enemy's (the killing-blow
signal already measures this) — at which point spending shifts to the attack.
Migration direction: the maketask-ladder spenders (EcoFusion, mex upgrades,
expansion) become Brain wants under the ratio-value scoring he specified
("values 4 and 7 → a 4:7 spend ratio"). **UNRESOLVED** — ratio scoring landed
2026-08-15 (`cd6cf75`); the ladder-to-Brain migration has not started.

**Corollary, 2026-08-16: "We need to make sure our AI logic does not compete
with itself. If our designs are not good enough then we consider changing
them."** Multiple systems claiming the same builders/metal for conflicting
goals is a design smell to be fixed at the design level, not patched around.
When a ladder rule and a Brain want fight over the same resource, that is a
mandate to move the rule into the Brain (or delete one of the two), not to add
a guard condition.

---

## Current priority (2026-08-08)

He set this explicitly after a session that added many features at once:

> "it hurt, but i don't care... I want to get these features in and many of them
> are done poorly so none of the 'has it helped or hurt' matters until things are
> working correctly."

So: **do not spend time on control tournaments or win-rate comparisons yet.** The
features are half-built; measuring whether a broken feature helps is noise. The
bar right now is "does this actually do the thing it claims to do", validated by
watching and by counting real outcomes (structures built, mexes held) rather than
by score.

Ordered work he named:

1. **Base layout and reclaim.** Sprawl, wasted space, never reclaiming old
   buildings, no room to tech up. One problem, not several -- there is no layout
   model at all, only a position plus a shake radius, which can trade sprawl
   against self-walling but cannot solve either.
2. **Front line, consistently.** Army AND defences positioned on the front, every
   game, not occasionally. He cares about both halves: the line existing, and
   units actually being on it.

## How he wants me to work

- **Watching beats measuring.** He returns useful feedback in ~5 minutes; a
  tournament takes 20-30 and often cannot answer the question at all. Deploy and
  hand him a windowed run FIRST, then do slow measuring alongside. Every
  diagnosis that has actually landed came from him watching.
- **Do not re-explain the noise floor.** He knows single runs are noisy and that
  seeds do not make this AI reproducible. He established it. Report what was
  measured; if something needs a control, say so once, briefly, or just run it.
- **Fix things properly, don't chase wins.** "Don't worry about losing matches,
  focus on us doing proper bug-free implementations."
- **Work through the whole list, not a few at a time.** When he gives several
  observations he wants them all addressed, validated, retried. "don't give up."
- **Own regressions plainly.** Several problems this session were mine. He
  responds fine to that and badly to hedging.
- **Validate outcomes, not log lines.** A `porc+` line is a REQUEST. Count the
  structure, the metal, the mex — not the message. This has burned us more than
  once.
- **Local test matches can run while he plays.** Deploys cannot — deploying
  while BAR is open half-writes the AI folder. Test freely, deploy only when the
  machine is clear.

## Testing setup he expects

- **Multiplayer AIs always have a resource bonus** — watch runs should be at
  **+50%**, both sides. `--watch` now defaults to this.
- **Match player count to map size.** Comet Catcher is a 4v4 map (16x12);
  running it at 8v8 starves everyone and invalidates the economy.
- Box orientations he has specified: Isthmus top-right vs bottom-left, Glitters
  top vs bottom, Jade top-left vs bottom-right at ~60% size.
- Maps he has asked to test: Comet Catcher, Jade Empress, Glacial Gap.

---

## Front lines and territory

The thing he asked for first and has pushed hardest on.

- **A front line is where OUR territory ends and the ENEMY'S begins.** Not the
  edge of our base, not a lane, not a geometric border.
- **It should wrap all our territory**, and be distinguished from a **back line**
  — the fog behind us that is a danger zone but not a front.
- **At game start the front is unknown**, and should say so rather than guess.
- **The front must be near the enemy.** Enemy-facing is not enough; the far flank
  of a big territory faces them too and is nowhere near the fighting.
- **Start-box geometry gives the opening answer** — midpoint between our start
  centre and theirs. (The engine already computes a per-player version of this
  as `lanePos`.)
- **The goal of a front line is that no enemy can go around it** and hit our
  bases from the rear. It needs to be tough, and to include jammers,
  construction turrets for repair, and long-range artillery defence, T1 and T2.
- **90% of a human's defences sit on the front line.**

## Holding ground, and leaks

- **UNRESOLVED (partly): we attack too much and hold too little.** Enemy raiders
  walk into our base and kill mexes freely; we never do it to them. He believes
  — and the data agrees — this is the main reason we hold fewer mexes.
- **Defend the deep interior mexes**, not only the border. Leaks happen behind
  the line.
- **Defences arrive far too late.** At 17 minutes there is not much, and not in
  the areas where leaks actually happen.
- **Do not cap front-line defence.** "if theres a frontline we should build
  defenses there regardless of any cap."
- **Never send a constructor to build a tower in a dangerous place.** "what is
  the point in trying to make a tower that can never be built? You go to some
  really dangerous place and are like, oh, I'm just gonna take a minute and build
  this. It's dumb." Build behind the line, not on it.
- **UNRESOLVED: dragon's teeth scattered across the map (2026-08-16).** "We
  scatter the map with 'dragons teeth' which become obsolete once we have over
  100 metal per second." Two halves: stop scattering them, and treat existing
  ones as obsolete (reclaim candidates) once income passes ~100 metal/s.
- **UNRESOLVED: we need T3-grade defence and jammers.** Once T3 is on the field
  the older defences die and there is nothing credible left. Eventually only T3
  units — Titans, Behemoths, Sol, Juggernauts — can hold a broken front.
  Re-raised 2026-08-16 after a Korgoth walked into the base and ended a game we
  were winning: "we should have built more T3 defenses." That game: our static
  defence 11,085 metal vs stock's 38,475 (stock's spend included a 15k
  Doomsday); our T3 fielded 0 vs their 54,100.

## Army behaviour

- **UNRESOLVED (largest): units are not positioned on the front line.** "thats
  the huge issue here." Squads move like blobs with no responsibility for any
  area. Humans form a line of army that holds a region and stays there.
- **Cut off enemy reinforcements** where possible; understand which pathways lead
  into our territory.
- **Breakthrough doctrine:** punch through the front line, then stay in the back
  lines killing bases. **Commitment** is the key — do not regroup mid-push.
- **Coordinate air raids with the land engagement** on the same front, at the
  same time.
- **Penetrate deeper** into places we believe are empty, to kill mexes and bases.
- **No flat move order may override common sense (2026-08-16, with screenshot):
  a fragile unit must never blind-walk into enemy fire.** A Sharpshooter walked
  deep into the enemy army on a plain move order, unable to stop and shoot
  things well inside its own range. "This is just basic 'well duh of course'
  logic." Travel for any unit must respect what it can shoot and what can shoot
  it — halting to fire, standing off, or routing around are all acceptable;
  walking blind is not.
- **FIXED 2026-08-16 (measured once): we did not mass as hard as the enemy.**
  "They usually have a really big mass and kill our smaller masses one by one.
  We don't know how big they are until its too late because we can't see them
  all." Mechanism (massing.as): ratio-based group sizing was OFF by default,
  the flat cap of 48 sat below the army-scaled floor past ~14k army, and the
  sizing estimate discounted unseen enemies to 0.3x and omitted heavy/super
  entirely. Fixed `e2fefcb`: raw full-field estimate (unknown must not read
  as "small army", the air-doctrine rule), ratio sizing on, cap 2.5x floor,
  group share ~35% of standing army. Same-day A/B, 24 games/side: decided
  games 7-4 -> 14-2, pooled army K/D ours 0.739 -> 0.834 while stock's fell
  0.897 -> 0.833 (trading at 0.82x of stock -> parity); legion alone 5-0
  with the CI excluding 50%.
- **NEW 2026-08-16: units should WANT to stand within their squad's jammer**
  when the squad has one. Escorts (jammer/radar per squad) are already bought;
  the positioning half — members, especially fragile ones like snipers,
  staying inside the jam radius — is squad-movement logic, likely C++
  (SupportTask/attach). Not started.
- **Sniper deaths diagnosed 2026-08-16 (live game):** every armsnipe death in
  the watched game died on a RETREAT task (t4) at fwd 0.07-0.48 — the retreat
  fires, then they die running. behaviour.json retreat raised 0.6 → 0.95 (a
  680-metal glass cannon leaves on the first scratch, not at 60% hp). The
  deeper fix — standoff so damage never starts, and jammer cover above — is
  still open.
- Stop entire armies chasing a few light units off the front line.
- Do not walk 20x the necessary distance around enemy defences.
- **Making this kind of strategic logic easy to express is itself a goal.**

## Economy and expansion

- **RESOLVED 2026-08-08 (unmeasured): we never harass their economy while they
  constantly harass ours.** apexearth: "We have an enemy that is constantly
  harassing our economy, and we never harass their economy." Cause found in
  `factory.json`: apex had zeroed the RAIDER out of the T1 bot lab. `armpw`
  (Pawn) share against stock's -- tier1 0.15 vs **0.70**, tier2 **0.00** vs 0.70,
  tier3 **0.00** vs 0.30 -- replaced by `armham` (assault) at 0.58-0.65. Stock's
  bot lab is a raiding factory; ours was an assault factory. Restored to 0.40 /
  0.30 / 0.25 with `armham` reduced to match. Cortex and Legion NOT yet checked
  for the same gap -- the recurring faction-parity trap.

- **The enemy takes map-wide mexes far faster than we do.** Untaken mexes matter
  more than reclaim.
- **Constructors should not be reclaiming.** Rez bots exist for that.
- **Never reclaim for energy above ~20% energy bank.** Constructors chewing trees
  while the enemy takes the map is the specific thing he saw.
- **UNRESOLVED: buildings are too spread out and waste space.** Raised many
  times, never fixed. Sprawl eventually means there is **no room to tech up**.
- **Nano turrets should be placed right next to each other.** Tight, not spread.
- **UNRESOLVED: we do not reclaim our old buildings.** Nothing reclaims a
  structure for being in the way or stranded — only for being an outdated tier,
  and even that arrived late.
- **UNRESOLVED: never build two of the same expensive plant.** Two T2 shipyards
  in one game. If you want more build power, make nano turrets or more
  constructors assisting — not another 3,100-metal factory.
- **UNRESOLVED: build expensive structures ONE AT A TIME, assisted.** Five LRPCs
  at once in one base. Serialise them and you have a working one far sooner.
  **Refined 2026-08-16: parallelism scales with wealth.** "We should be willing
  to make more than 1 of any building at one time if we are wealthy enough and
  have a strong enough desire for it" — advanced energy converters, nanos, T3
  defences. The one-at-a-time rule was about a poor economy starting five LRPCs
  it could not feed; a rich economy with a strong want should run several in
  parallel. Concurrency is a function of income and desire, not a constant.

## Naval

- **UNRESOLVED: react to WHERE the enemy actually is (2026-08-16).** "If the
  enemy is only in the water then we need to make water or make advanced air
  or seaplanes to attack the enemy in the water." Composition must follow the
  observed enemy domain, not the map type — an enemy living on water demands
  ships, seaplanes, or advanced air, even from a land start.
- **UNRESOLVED: water performance is bad overall.**
- We die to enemy subs; not enough torpedo launchers or destroyers at T1.
- **Destroyers and subs are both strong** in late T1 and stay relevant much
  later. Massed subs can win an entire water battle unless the enemy has T3
  hovers.
- **UNRESOLVED: a naval player walls himself in with nano turrets.**
- **UNRESOLVED: a naval player goes braindead** — defends himself, otherwise does
  nothing, contests no water mexes.
- **Question worth answering: is there even a land path to the enemy?** If not,
  building land units is pointless. The engine has this (per-movetype areas +
  `CanMoveToPos`); it is not exposed to script.

## Air

- **AIR DOCTRINE, stated plainly 2026-08-08. Three rules:**
  1. **Assume the enemy army is escorted by AA, and only engage it with air when
     AA is observed ABSENT.** Not a prohibition -- a presumption. "you can attack
     army with air. But, usually, there's a lot of AA there. you almost have to
     assume that there's going to be aa there. And then if for some reason there
     isn't, then you can harass them." Also: "The enemy ground army would
     annihilate our air really fast."
     Note the shape: unknown must read as "AA present", never as "no AA" -- the
     same failure that made the team push fire on ignorance, where an unscouted
     enemy army read as 90 metal. `Air::EnemyAACost()` already exists, and like
     `GetEnemyCost` it only accumulates on EnemyEnterLOS, so a zero from it means
     "not looked", not "not there".
  2. **Air IS for defending against raiders.** Interception at home is a real
     job for it.
  3. **Air is for harassing economy.** "i never see us doing useful things with
     Air, like attacking enemy mexes and stuff."
  Measured in the game that prompted this: air units WERE built (armhawk 2660,
  armthund 2465, armkam 2295) and the only air log line all game was
  `air assassin holding off -- losing the ground war`, 31 times. So this is a
  targeting problem, not a production one -- and the hold-off is circular: we are
  behind on the ground, so air stands down, so we stay behind. Raiding economy is
  what a losing side should do with air.

- **UNRESOLVED: we never have more than ~10 fighters.** He wants ~30 over the
  base for defence, always avoiding enemy AA. A standing garrison, not a reaction
  to enemy air.
- Do not run air-assassin strategies while clearly losing the ground war.
- One T1 air lab in the T1 phase, not two. More only once the economy is strong.
- Late game should include heavy air and large T3.
- **An air lab is MANDATORY once income reaches 100s of metal/second**, and an
  advanced air plant is "absolutely needed late in game", with plenty of fighter
  coverage (2026-08-16). Air cons and advanced air cons are the efficient way to
  build at that stage — prefer them. (Wired: `apex_air_mandatory_income` 100,
  `apex_adv_air_income` 150, fighter floor `apex_fighter_per` 40.)
- More shields late game — enemy LRPC becomes the problem, and air handles the
  late game better generally (2026-08-16).
- **Don't limit advanced air plants to one when rich** — count scales with
  income, one per `apex_adv_air_income` (150) of metal/s (2026-08-16).
- **UNRESOLVED: sometimes no advanced air plant at all in a long game
  (2026-08-16).** Despite the `apex_adv_air_income` wiring above, long games
  still finish without one. The trigger exists but does not reliably fire —
  find why (gate never reached? displaced? no builder picks it up?).

## Efficiency

- **Wasted metal and energy is a valuable metric** (2026-08-16): "everything in
  this game is about balancing economic expansion with the military." Wired:
  `dev_team_income.lua` accumulates the engine's overflow (`resPrevExcess`) and
  `audit.py` reports metal-wasted / energy-wasted shares per game.

## Tech and unit choice

- **Going T2 matters** — T2 dominates T1, and losing our T2 with nobody else
  teching is a game-loser.
- Legion built too many Pharos (T1 LLT) instead of T1.5 defences.
- Juggernauts should walk straight into the enemy base — they explode on death.
- With no commander left, prefer resurrection.

## Visualisation

- He wants to see what the AI believes, on screen, while watching.
- **Lines, not pings.** Map points fire alerts and minimap flashes; unusable at
  any density.
- Drawn markers must persist and update as things move.
- (Two hard limits found: the server silently drops map-draw commands after 25
  in a row under 50ms apart, and BAR's auto-eraser widget deletes every mark
  after 60 seconds.)

## Longer-term ambitions

Stated as direction, not immediate work:

- Surprising strategies and unpredictability against humans.
- Distinct personalities per AI instance.
- Real cooperation between allied Apex AIs.
- Late-game heavy air plus large T3.
- Water and mixed-map support, including building water units properly.
- Multiplayer is the real target: host-side only, no archive changes, no synced
  Lua.
