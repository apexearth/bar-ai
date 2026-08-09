# Issues
- Constructors in late game seem to value creating mexes a lot when once we've got afus + advanced energy converts the mexes are no longer important. This seems to make it so that we aren't building enough defenses and shields and other important things because they're too busy trying to make mexes. Meanwhile they're just suiciding constantly if its a losing battle.
- Very much need to create a team-wide defensive line against the enemies, including shields, jammers, T3 defense (lots) when the late game is reached. Late game is usually 25 minutes + into the game, but you can gauge late game based on if we have things like fusions or afus... thats when we'd expect to see some really big attacks coming in which considerable defenses would be needed to protect from. The way that AI attack logic works often leaves bases open to flanking attacks. So we still need to have some base defenses to protect our flanks.
- If we are at 150 metal or more per second and do not have an experimental gantry then it should be a very high priority to create one. I watched game and for a very long time no gantries were being made - except for the first one. 
- I didn't see mobile jammers being created by our AI and we were punished really hard by enemy long range units. We really lacked any of our own good long range capabilities combined with radar and jammer. I think we should download a good doc/guide describing all the units in the game (including the optional extra units which are sometimes enabled) to know what we should be making. Ideally if the AI could understand unit specs then we could just choose to make units based on the quality/stats of the units, rather than relying on a build config. With something like that we could just build balanced armies totally based on unit stats.
- We tend to have a lot more energy excess than stable barb. Basically we don't make as many energy converters as they do proportionally to our energy generation.
  - CAUSE FOUND (2026-08-02): the converter rule gates on `energy.income - energy.pull`, which is not the amount being wasted. Measured over 8 games, the eco lead binned 46.7% of all energy it produced while that expression read 72-216. Pull counts demand met from storage, so a base that is spilling shows almost no "spare". `isEnergyFull` (88% of storage) is the honest signal; switching the eco lead's block to it took its waste to 1.2% in a smoke game. The GENERIC converter rule still uses the old metric.
- on super high income games the AI fills up its sectors with tons of metal storage, it can't possibly use all the resource it gets, we need a cap on metal storage
- Once we have a fusion we can start reclaiming our wind. We don't need wind any more at that point.
- NO TORPEDO BOMBERS, EVER. apexearth watched a game where one AI took the water and the other the ground, and it could not be finished: "no torpedo bombers were being made, so it just turned really slow to wrapping it up". They exist in all three factions and nothing in this repo references any of them — `armlance` (Cormorant, 400 metal, T2 air plant), `cortitan`, `legatorpbomber`, plus the seaplane platforms `armseap`/`corseap`. A ground army cannot touch what sits in the water, so a split map stalemates.
- KILLING BLOW. Measured, 16 games on Quicksilver at a 50-minute cap: apex out-produced stock 1,183,263 metal to 261,349, out-T3'd it 142,309 to 4,053 and out-armied it 359,961 to 42,543 -- and ELEVEN OF SIXTEEN games still hit the time limit undecided (4-1 in the five that finished). Total dominance that does not convert. apexearth: "we are often winning but we're very slow to kill enemies ... we need some sort of switch which says ok now go for the killing blow" -- mass a huge army and send it all in, and attack from map edges more often.
- Packing eco tightly has a real downside: it can all blow up at once. apexearth: "if you place too much of all this stuff exactly next to each other, it can all blow up at the same time ... usually, if I'm a little bit worried, I might create two separate areas." Not done yet, and deliberately so — the eco lead currently builds ONE band (turret rows + fusion lanes + converter block). A second, separate site is the fix if chain detonation ever shows up in a replay.
- We shouldn't build too much T3 defence very early. Backline players are making T3 defence when they don't need it — it belongs where the fighting is, and later.

# Strategies

## Surprise Air Eco attack! (special temporary strategy to swap to in the middle of a game)

Surprise the enemy by building up a force of 20+ fighters and 20+ bombers (T2), or T3 Dragons, invade enemy territory by ***avoiding*** enemy army (go around them, don't retreat!!!!) and attack constructors, economy, and keep going until dead. This is a suicide attack strategy for the units involved and the goal is to inflict maximum damage on their economy and build power.

## Tick Spam! (late game additive strategy)

In late game, like 20-30m+ in time, when theres lots of big bois or annoying long range units attacking you, you can distract them very well by spamming ticks at the enemy. Alternatives are grunts, pawns, rascals, wheelies, the cheap but fast units - we don't care about grouping up these units. They go straight to the front and run as far into the enemy base as they can. Their purpose is to provide vision and to be a distraction. These shouldn't get swept up into groups, or treated like normal army - they are fodder.

## Nuke Spam!

- prefer a docile enemy, likely wait until we have a rush to T2 and based on observed enemy strength *maybe* enable this strategy
- not a good strategy versus aggressive enemies

Before the enemy is ready, have the entire team go straight for nukes. Build up and SAVE multiple nukes and then at around 18m in launch all the nukes we've got on all the different enemy bases. Spread them out. After this reclaim all the nuke launchers and turn off the strategy to play normally or with a different strategy.

# Tips

- Sometimes AI gets a huge +100% bonus given to them. In order to take advantage of this properly they need to make an increased amount of build power. If above ~50% metal then we can keep making construction turrets. Sometimes making ~4 more at a time is more efficient.
- Prefer to create organized bases using geometric shapes like rectangles, squares, fitting efficiently into grid patterns.
- in late game take advantage of air constructors - they allow you to scale everything much faster, because ground cons move slowly. HOWEVER - air cons are easily shot down near the front line - this requires intelligence so that air cons aren't used when enemy AA is nearby. You have to hook this into their behavior, choice of where to build, AND whether they even get constructed. Complex.
- AI should hover under a jammer and stay cloaked, when enemy T3 comes and attacks it should try to do surprise D-guns to kill all the T3 without dying itself.

# Refactor candidates left undone (2026-08-09)

The AngelScript was split into modules and both `AiMakeTask`s became rule
pipelines; the C++ delta was deliberately left alone, because every change there
needs a Docker rebuild and a fresh measurement and this pass was required not to
change behaviour. What a C++ pass should take first, in order of how much
confusion each one causes:

- `CAttackTask::FindTarget` is ~230 lines with TWO margin tests (`groupMargin`,
  `nearMargin`) computed from overlapping but not identical rules, both calling
  `TradeScaledMargin` and both checking `isHome`/`prevTarget`. It is the hardest
  place in the delta to reason about.
- The squad-join relaxation is copy-pasted three times with three different
  magic pairs: `AttackTask.cpp` (3.5, 3000), `AntiAirTask.cpp` (1.5, 4000),
  `BombTask.cpp` (1.5, 4000). Changing one will not find the others.
- The perpendicular line-offset maths is written four times (`SquadTask::LinePos`,
  `SquadTask::ActivePath`, `RetreatTask`'s retreat line, `MoveAction::offsetPos`),
  three of them with the same O(n) "find my index in `units`" loop. One
  `LineSlot(index, count, spacing, dir)` covers all four.
- Two independent "sticky target" implementations, both using 1.4, one as a
  multiplier on `prio` and one as a divisor on `sqDist` — same constant, same
  intent, different algebra and different units.
- Three constants now mean "fraction of weapon range to stand at":
  `RANGE_MOD` 0.8, `ATTACK_RANGE_MOD` 0.95, and the `apex_range_mod` tunable
  that overrides only some uses of the second.
- Path-detour logging is duplicated verbatim between `AttackTask` and `RaidTask`,
  down to the rate limit and the message shape.
- Constants are `#define` in headers rather than `constexpr` in the class.

Bugs found in the same pass are in CHANGES.md under "found while refactoring,
NOT fixed" — they are deliberately still there.
