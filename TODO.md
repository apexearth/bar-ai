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

# Getting the 1v1 past parity (2026-08-10)

The 1v1 is at 50% against `BARb:stable:hard` over 113 decided games, up from
1/66. Everything that got it there was REMOVING apex's own work; nothing added
today made it better than stock. What is left is the harder half.

Measurement first, because it is what made the rest possible:

- **45-60 minute caps, not 20.** At 20 minutes most games were undecided and the
  win rate did not exist. Median decided length is 31-37 min.
- **40 games per arm, and run the arms CONCURRENTLY.** The same build measured
  8/20 and 3/17 an hour apart. At n=38 the 95% CI is still about +/-16 points,
  so separating 50% from 75% needs roughly that sample and a matched control in
  the same session.
- `python tools/tl.py <run> [shortname]` prints the paired timeline -- it drops
  any sample where one side has stopped reporting, which is what makes late-game
  rows honest.

Candidates, in the order the evidence supports:

1. **Re-land the fighter-task behaviours one at a time.** They are on
   `barbarian-apex` history before the revert. The standoff-and-orbit pair is
   the one with a measured signature: turning it off by modoption scored 14-24
   against a 10-28 control. Everything else in that revert is unmeasured in
   either direction.
2. **Re-derive apex's config deltas on the `hard` base.** The old ones were
   tuned against `hard_aggressive` and are gone. The raider-share fix in
   `factory.json` is the one with a stated cause behind it.
3. **Re-measure 8v8.** Nothing about team play was measured today, and both the
   config base and the fighter tasks moved under it.
4. **`ApexActive()` is all-or-nothing.** It should become per-behaviour, so a
   rule that is good in a 1v1 can run there while the pooling machinery does
   not. Today it buys the floor and forbids the ceiling.

## Rezbots follow the attack group and eat what it kills

apexearth, 2026-08-09, watching an 8v8: "we should have this group followed by
rezbots which will reclaim everything they kill... this is a nice to have, but
would be great, and prevent enemy from just resurrecting all their stuff."

Two payoffs in one behaviour: the metal from a won fight comes back to us, and
the enemy loses the option to resurrect its own losses -- which is otherwise a
free rebuild for them on ground they still hold.

Not built yet. Notes for whoever does:
- The rezzer role already exists (`response.json` "rezzer", and `builder/rules_rezzer.as`
  has RezzerFlee / RezzerFrontSalvage / RezzerEatCorpse), so the unit and its
  task types are in place; what is missing is following a SQUAD rather than
  working from the base outward.
- `reclaim vs resurrect` is already decided by PreferReclaim() -- for this job it
  must be RECLAIM, not resurrect: reclaiming is much faster and denial is the
  point. apexearth previously: "rezzing takes MUCH LONGER than reclaiming... so
  if in a dangerous area you should generally reclaim."
- Needs a leash to the squad, and must not pull rezbots off base reclaim while
  the squad is idle at home.

## Long-range siege units should hold the base line, not walk into the open

apexearth, 2026-08-09: "Starlights, Ambassadors, these really long range units
are great for defense. But I typically see us move them out into open ground and
get destroyed. They should act like defensive turrets and stay home... waiting
around where I have my nano turrets and my own defensive turrets to help add DPS
and heal my units if they get hit. This same thing helps vs players too."

The units, read from the pinned tree:
- `armmanni` Starlight: range 950, 1,200 metal, role `anti_heavy_ass`, attribute `siege`
- `armmerl` Ambassador: range 1,300, 920 metal, role `artillery`, attribute `siege`

Both already carry the `siege` attribute, which today only changes their travel
action (CFightAction instead of CMoveAction in CAttackTask::AddAssignee) -- it
does NOT keep them home. `armmerl` being role `artillery` routes it to
CArtilleryTask, which still moves toward targets rather than holding a line.

What is wanted is a LEASH, not a new behaviour: a long-ranged, fragile, expensive
unit should stay within our own defended area, where static defence adds DPS and
nano turrets repair it, and shoot outward from there. Its range is the whole
point -- it can cover ground it does not stand on.

Candidate implementation: keep units with (long range AND siege AND low speed)
assigned to defence near the front-line position the military layer already
computes (`military/defenceline.as`, `frontline.as`), instead of letting them
join an attack squad. Needs to interact correctly with the killing-blow override,
which deliberately commits everything when far ahead.

Not built. Unmeasured.

## Scout the mex area first, then size the group to what is actually there

apexearth, 2026-08-09: "you can scout with 1 cheap unit first to see what the
enemy has in these areas... then you can build your attack size based on how
strong the mex area is."

This replaces a global quota with a per-target decision, which is the right
shape: `quota.attack` today is ONE number for every attack, so the group forms
to a fixed size and only afterwards looks for something it can beat. Sizing the
group to the target inverts that, and it is what a human does.

Both halves already exist and are not wired together:

- **Seeing the area.** `CMilitaryManager::GetScoutPosition` already sends scouts
  to metal CLUSTERS -- but it only counts a cluster scoutable when some spot
  reads `threat < THREAT_MIN`, so any cluster the enemy holds is excluded and we
  only ever look where they are not. `apex_scout_threat` (built, default off)
  raises that ceiling. It is a prerequisite for everything else here: enemy
  groups are built from `hostileDatas + peaceDatas`, i.e. only enemies we have
  SEEN, so an unscouted extractor is not a low-priority target, it is not a
  candidate at all.
- **Measuring the area.** `CAttackTask::FindTarget` already computes `localInfl`
  -- the summed influence of enemy groups within `NEARBY_ENEMY_DIST` of a
  candidate -- and uses it both to refuse defended targets and (now) to grant
  `FREE_ECO_PRIORITY` only when it is zero. That IS "how strong is this mex
  area", already calculated.

What is missing is using `localInfl` to SET the group size rather than only to
accept or refuse a target: pick the target first, then require a group scaled to
its local defence, instead of forming a fixed-size group and shopping for
something it can beat. Needs care with `CAttackTask`'s `minPower`, which is
fixed at construction and only re-tested in `RemoveAssignee`.

Not built. The scouting half is built but unmeasured at 8v8.

## A single T3 assault unit should raid on its own, around the rim

apexearth, 2026-08-09: "Once we have units like the 'Titan' they can do these
attack orders all on their own. Through the edge of the map they'll be very
good."

Titan is `armbanth`, 13,500 metal; the Cortex equivalent is `corkorg` at 29,000.
Either is worth more than the whole floor-sized group the massing quota asks for,
so waiting to bundle one with a screen of Pawns is spending the wrong resource.

It may already work. `quota.attack` is a POWER sum and `CDefendTask` promotes as
soon as its assignees reach `minPower`, so if one Titan's `GetPower()` already
exceeds `MASS_FLOOR` (30) it fills the quota alone and leaves. That is a fact
about the unit, not a design question, and it has never been read --
`LogUnitPower()` now includes `armbanth`, `corkorg`, `corshiva` and `armmanni`
so the next run prints it. Measure before building anything here.

If the power does clear the floor and a Titan still does not go alone, the gate
is elsewhere (role masks, `IsIgnore`, the factory never building one at all --
T3 output is two or three units a game at benchmark income; see CLAUDE.md).

The "through the edge" half is not target selection, which is now handled
(`EDGE_ECO_BONUS`), but ROUTING: the path a party takes to a rim target still
crosses whatever the threat map lets it. `apex_attack_threat_mod` raises the
price of contested ground and is the existing lever; whether it produces a rim
route or just a slower one has not been looked at.

Not built. Unmeasured.
