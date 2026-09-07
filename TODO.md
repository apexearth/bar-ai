# Strategies and behaviours he has asked for, not yet built

This file is the third list, and the narrowest. `ISSUES.md` is what is wrong
now; `USER-FEEDBACK.md` is the standing brief of what he wants; this is the
sketchbook -- named plays and unbuilt behaviours in his own words, kept because
nothing else records them.

Same lifecycle as the other two: **an entry is DELETED when it is built and
measured, never marked done.**

Read `docs/23-the-plan.md` before coding anything here. Where one of these is
phrased as a bar ("at 150 metal/s, build a gantry"), that is him reporting a
symptom at the income he happened to be watching -- it is not a number to code.
The AI reaches a play when the arithmetic says the play is the fastest path,
and the earlier "# Issues" list in this file was deleted on 2026-08-31 for
being mostly such numbers, on top of duplicating the other two lists.

# Strategies

## Abuse the BARb AI the way humans do -- the standing doctrine

apexearth 2026-09-01, offered as frame of mind rather than a spec:

  "I want to see this AI abuse the Barb AI the same we humans do :-P
   - make them attack us when they're more powerful
   - eat their wrecks
   - keep making more military
   - don't waste it
   - grow
   - overwhelm the enemy
   - use cheeky strategies/squads like i mentioned
   - stand at enemy border and siege them long range
   - let them come at our army while we stand still and defend, using rezbots,
     twitchers, etc to heal our tanks."

These are one doctrine, not eight wishes, and it is the answer to the number
that matters: 122 games against BARb hard, zero wins, army trade 0.48 against
their 0.93. Every item is a way of NOT walking into their guns.

  hold, do not charge   they attack us; we fight on our ground at our range
  heal in place         rezbots and twitchers repair the screen mid-fight, so
                        the same metal fights several times
  eat the wrecks        their dead army funds ours; the battlefield is the
                        richest reclaim on the map and it is where we already
                        are
  never idle production the line keeps running while the ball holds
  siege the border      the anchored range ladder, parked at their edge

WHAT ALREADY EXISTS: the screen standoff (2026-09-01), squad rows by range,
rezbot rules (rules_rezzer.as, including the fallen-commander rescue), and
reclaim wants. WHAT IS MISSING: the POSTURE that ties them together -- a
deliberate "hold and let them come" mode distinct from attack, with the healers
inside the ball rather than following it, and battlefield reclaim treated as a
first-class income stream after a won fight rather than as idle-time work.

Note the tension to resolve rather than ignore: "make them attack us when
they're more powerful" is a bait, and this AI currently has no way to express
"I am deliberately not attacking because their coming to me is worth more than
my going to them."

## Two squad doctrines: the siege screen, and the deep raid

apexearth 2026-09-01, on what a short-range unit should do in a squad that has
artillery behind it:

  "the tanks should just stand around in front of the sheldons. They'll take
  hits if they have to, but they won't walk up to enemies to shoot at them.
  They're just protecting the ranged units. If they walk closer they'll take a
  lot more damage. They are there as a shield. This is how all our units should
  behave when in a squad with ranged units. The squad should seek to remain at
  max range, tanks should try not to get hit but still protect their ranged
  units. It's a bit of a siege mentality really."

  "But that's not the only option we have. We can also just YOLO attack deep
  into the enemy. The goal can be to just blast through the front line and make
  it into unguarded economy in the backlines and then run around dealing free
  damage."

### A. SIEGE SCREEN -- and the change is one line's worth of intent

CSquadTask already groups the squad into ROWS BY RANGE and holds each row at
its own range (`rowRange = kv.first`), with one exception already carved out on
his earlier ruling: a weaponless escort (radar/jammer) keys row 0 and holds at
`highestRange + apex_escort_standoff`, BEHIND the squad, because "stand at your
own range" told a sensor to stand on the target.

The screen is the same exception with the sign flipped. A short-range row in a
squad whose damage comes from a longer row should NOT hold at its own range --
holding at 230 (Incisor) or 380 (Thug) is what walks it into the enemy. It
should hold just in FRONT of the carry row, i.e. derived from the carry range,
and fight only what comes to it:

    escort (no weapon):  hold at  highestRange + standoff     [exists]
    carry  (longest):    hold at  ownRange                    [exists]
    screen (shorter):    hold at  carryRange - screenGap      [MISSING]

So the squad as a whole sits at the carry row's range, which is his "the squad
should seek to remain at max range", and the screen is between the enemy and
the guns rather than out ahead of them.

Consequence for pricing, not just movement: a short-range unit in a mixed squad
is being bought as a SHIELD, so what it is worth there is absorbing HP and body
size, not its own dps -- which is the range-ladder valuation in the entry below.

### B. DEEP RAID -- blast through and eat the backline

A different task, not a tuning of the first: break the front line, get into
unguarded economy, and stay mobile dealing free damage. CRaidTask exists and
already logs its route shape (`apex: raid path walked/direct/detour`), so the
machinery is partly there; what is missing is the DECISION to spend a squad
this way rather than on the front, and the target choice once through.

Both are C++ (task/fighter/SquadTask.cpp, RaidTask.cpp). He knows: "These
changes would require some updates to our C++ code. We should keep working on
this though as fixing our military composition is very important."

## The anchored range ladder -- one Mammoth, everyone guards it

apexearth 2026-09-01: "I can take 1 mammoth, 1 radar, jammer, 10 sheldons, 5
arbiters... and have everyone guard the mammoth, and then give the mammoth a
fight order towards the enemy base. This army can literally take out the entire
enemy base."

And why it works, in his words: "It just happens that the mammoth range keeps it
far enough away from enemies that usually only the mammoth is seen. The rest of
the army behind it stays hidden but can still shoot at enemies up front. The
jammer keeps them off radar. The radar gives LOS/radar. Arbiters give the extra
anti-building damage. It really works. If the AI doesn't actually form a squad
like this then its much less valuable. And when the mammoth dies well the whole
squad breaks down fast."

THE NUMBERS (pinned tree):

    corsumo  Mammoth  2,200m  15,600hp  spd 22.5  range   650
    cormort  Sheldon    410m     940hp  spd 50.4  range   850
    corhrk   Arbiter    600m     610hp  spd 54    range 1,210

One Mammoth + 10 Sheldons + 5 Arbiters = 9,300 metal, 76% of it long-range,
anchored on one 15,600hp body.

THE MECHANISM IS A RANGE LADDER, and it is computable. Each rank stands behind
the one in front and still reaches the enemy, because its range is LONGER than
the anchor's: 650 < 850 < 1210. Only the anchor is inside the enemy's range, so
only the anchor is shot at. A reach unit is protected when an anchor with a
SHORTER range and enough hit points stands in front of it -- not when the army
happens to contain a given metal fraction of "meat".

That is the correction this play forces on ShieldShare(), which is currently
(tankM + midM) / totalM. His ball scores 0.24 on that and would have its reach
units priced at a quarter strength, while a homogeneous Thug ball scores ~1.0
and is rated fully shielded -- yet two Thugs at the same range protect nothing
from each other, and one Mammoth protects fifteen units costing four times its
price. Metal share is the wrong currency; the right test is "is there an anchor
in front of me, with a shorter range and enough HP to absorb what is incoming".

WHAT IS ALREADY THERE: squads pace to lowestSpeed (SetPath(pPath, lowestSpeed)
in AttackTask/AntiAir/AntiHeavy), so the engine does NOT refuse to mix a 22.5
Mammoth with 50-speed Sheldons. The composition is reachable; we simply never
build it, and never form it.

WHAT IS MISSING:
  1. The range-ladder valuation above (reach is worth what the anchor in front
     of it buys, measured in range order and absorbing HP, not metal share).
  2. The FORMATION: everyone guards the anchor, the anchor gets the fight order.
     Travelling at lowestSpeed is not the same as guarding -- guarding is what
     keeps the ladder in range order instead of letting the fast units drift
     ahead of the anchor and get shot.
  3. Radar and jammer as squad MEMBERS rather than base structures -- the play
     needs both moving with the ball.
  4. Anchor fragility: "when the mammoth dies the whole squad breaks down fast."
     His answer, asked directly: "just add more mammoths to the squad :-P" --
     so this needs no special mechanism, only the right quantity. The anchor
     requirement is absorbing HP against what is incoming, so it scales with
     the squad: a bigger ball wants MORE anchors, not a tougher one, and the
     redundancy falls out of the same arithmetic. Do not build a
     single-point-of-failure rule for it.


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

Bugs found in the same pass are in changes/CHANGES.md under "found while refactoring,
NOT fixed" — they are deliberately still there.

# Unbuilt behaviours (2026-08-09)

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

## A basemap: defend territory, not a plethora of buildings

apexearth 2026-09-05, on being asked whether the defence target should stay
1.82x the army target:

  "Just like we have a threatmap we need a basemap or something like that.
   Instead of coding towards a whole plethora of buildings we can instead code
   towards what we consider our base or friendly territory which we want to
   defend. Should reduce the complexity I'd say. If we use our army to defend
   structures then we don't need as much defense - and if we make more defense
   on our structures then we don't need as much army there. It should be a
   balance between the two - and a choice - mobility vs concentrated power."

He did NOT answer the TUNE_DEF_ECO_S 120 vs TUNE_ARMY_ECO_S 66 question; he
rejected its framing. Two separate targets arguing over the same ground is the
complexity he is pointing at. The replacement is one territory to hold, and
defence vs army as two ways of buying the same hold -- substitutes in one
balance, priced against each other, not two independent obligations.

## Dedicated energy builders (apexearth 2026-09-07)

> "Too low on energy. Maybe we need to dedicate certain units to focus just on
> energy so that the job is properly focused on."

Not a priority tweak -- an ASSIGNMENT. Today every constructor re-elects over
the whole market each time, so energy is one want among many for all of them
and no one owns it. His proposal is that some constructors hold energy as their
job, so the work is continuous rather than whoever happens to draw it.

Open: how many, chosen how, and whether they are released when energy is ahead.
