# What apexearth wants from this AI

My understanding of the feedback he has given, in my words. This is a standing
brief, not a changelog — `CHANGES.md` records what was done and measured, this
records what he actually asked for and why.

Items marked **UNRESOLVED** have been raised and not fixed. Several have been
raised repeatedly, which is itself the point: re-reading this before starting
work is cheaper than being told the same thing a fourth time.

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
- **UNRESOLVED: we need T3-grade defence and jammers.** Once T3 is on the field
  the older defences die and there is nothing credible left. Eventually only T3
  units — Titans, Behemoths, Sol, Juggernauts — can hold a broken front.

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
- Stop entire armies chasing a few light units off the front line.
- Do not walk 20x the necessary distance around enemy defences.
- **Making this kind of strategic logic easy to express is itself a goal.**

## Economy and expansion

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

## Naval

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

- **UNRESOLVED: we never have more than ~10 fighters.** He wants ~30 over the
  base for defence, always avoiding enemy AA. A standing garrison, not a reaction
  to enemy air.
- Do not run air-assassin strategies while clearly losing the ground war.
- One T1 air lab in the T1 phase, not two. More only once the economy is strong.
- Late game should include heavy air and large T3.

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
