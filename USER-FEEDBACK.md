# What apexearth wants from this AI

---

## HOW THIS FILE WORKS  (read before adding to it)

This is a STANDING BRIEF of what apexearth wants and has not got yet. It is
read by agents, not by him -- he does not have time to review it, which is
exactly why it must stay short enough to be read cold.

Three rules, because it reached 1,090 lines and 54 entries by not having them:

1. **An entry is DELETED when it is done, never marked done.** A fix that is
   measured-confirmed lives in the code and in git history; leaving a
   tombstone here is how the file grew. (Same lifecycle as `ISSUES.md`.)
2. **One entry per thing he wants, not one per conversation.** If he says the
   same thing again, EDIT the existing entry -- a repeat is evidence the entry
   is still open, not a new entry.
3. **His words, the measurement, and what blocks it. Nothing else.** No
   restating, no session narrative, no plan. Those belong in the commit
   message.

Anything already implemented and validated should be gone from here. If you
find such an entry, delete it in the same commit as whatever you were doing.

## 2026-09-08 — CONSTRUCTOR ROLES BY SHARE (his proposal, not built)

Watching the deepening tree: "The defenses appear to be improved. We still
seem to lack nano turrets around Gantry. We have a lot of fragile T1 energy
converters which should be reclaimed to make room for better things."

Then the proposal, verbatim in shape: "it is so terribly hard to balance
wants/needs on these constructors. Thus I wonder if the brain could assign
roles to our constructors by a % based on what it sees as a split of our
needs. Like if we have a lot of obsolete buildings to reclaim we can give an
engineer a special role to do only that job until our brain decides it is no
longer needed. This would help us dedicate some constructors to nanos, some to
defense, some to energy, metal, etc... balancing 'is a nano or defense more
important than making more energy or more metal?' In general I think they
often are all equally important to do but just at different %s."

What it changes against the market as built: the roulette already draws each
election in proportion to value (the % split), but it re-draws EVERY election,
so no hand holds a job -- and re-election is the measured killer (49-53% of
defence wins dead before framing; 56 of 75 nano tasks dead in one game). A
role is persistence: a hand committed to a category until the split says
otherwise. Sized from the same demand the market prices (defence gap, nano
demand, energy shortfall, obsolete stock), it is derived, not a table.
`gEcoRole` is the one role that exists today. Awaiting his go-ahead on the
mechanism before building.

## 2026-09-05 — SELF-PLAY: "how passive our AI is"

*"They haven't attacked each other a single time in 13m. They've also not
scouted or tried to harass each other at all."* And: *"our base has depth and we
spread our army out around both the front AND back of our base... we need to
draw lines of our units towards the frontline."* And, on raids: *"I don't see
why higher level knowledge can't choose to do a raid... pull units from wherever
seems appropriate in order to make a raid happen."*

Three causes found and closed; measured 5-6 seeds, self-play, one map:
cover demand was the whole base's worth (so the raider class was conscripted
forever, with no direction in it) — `gPostReq` is `ThreatM` now; `quota.attack`
exceeded our whole army so no pool could promote — clamped to `armyCost*0.017`;
and raids are now ASKED for (`military/raid.as`). Metal killed 62 -> 707, with 4
of 5 control games ending with zero metal killed by either side. Scout tasks 0
-> ~15 min/game. Raids 4.0 -> 10.8 min/game.

STILL OPEN, and both are his calls:
- **The route.** "Skirting around the front lines" is doctrine in `docs/24`, but
  `CRaidTask::FindTarget` picks the target and no binding can hand it one. C++.
- **Scouts.** `quota.scout: 2` in `behaviour.json` caps scouting at two tasks
  whatever the map or however blind we are — a flat number of the kind the plan
  forbids. Derive it from unscouted ground, or raise it?
- Also still true: first factory past 4 minutes, so no military until minute 6.

## 2026-08-31 — THE OBJECTIVE: fastest path to a target state

*"We're supposed to do things based on math... If you were to calculate out the
ETA to getting your first fusion, then increasing your economy before getting
T2 would show as the right choice... There is theoretically a 'perfect' play to
get to your first fusion the fastest."* The target is a choice and composite --
"a 10,000-metal army", or "5,000 army AND a fusion".

Plus: *"a moho is in fact better than a fusion when we are poor on metal"*;
*"if we upgrade [4 mexes] we increase our metal income by 300%"*; *"mexes are
limited in supply. Once we're out of mex choices, we have to go to energy and
conversion"*; and the survival ruling *"maintain an army and defense ratio
based on our economy... while also finding the shortest path to a larger
economy."*

**The intent is `docs/23-the-plan.md`; the arithmetic and the constraint are in
the `value-paradigm` skill.** Not implemented. Do not restate either here.

## 2026-08-31 — A WHOLE LOSS, WATCHED AT 1x, NO BONUS: "We are doing things we cannot afford."

His running commentary of a 1v1 he lost, in order. This is the most complete
single diagnosis in this file; treat the ordering as causal, because he does.

- **4 min.** Income roughly even. They have a bit more army. We have MORE
  defence. "We seem to use fight orders a bit too much sometimes."
- **9 min.** THE FALLING-BACK PATTERN. "As we lose turrets we seem to make the
  next set of turrets behind a bit... Enemies attack, destroy turrets, then
  they fall back and we have time to build turrets up further once again - and
  we do, but we mix with turrets further back too. So with a lack of
  concentration on turrets up ahead - they don't stand much of a chance."
- **Throughout.** "I see us attacking with some of our units when we have less
  than half the army size of our enemies." And: "Our Army hasn't been able to
  grow at all - we keep sending them out to their deaths... If they were smart
  they'd stand inside their turret defense - but we're not smart."
- **The T2 decision.** We go T2 first; the enemy never does. "We should expect
  our army to be inferior because of where we've been putting our metal."
  Army disparity widens to under 1/3 of theirs.
- **The kill.** First T2 con appears and immediately starts a FUSION. "At an
  income of ~10m/s to build a 4300 metal fusion reactor... yeahhh you do the
  math." The enemy attacks. "The T2 con is oblivious to his impending doom",
  and the commander keeps building the fusion instead of answering the attack.
  A T1 con is starting a solar at the same moment.

**His verdict, verbatim: "I would blame this loss entirely on switching to T2.
The fusion stuff and not doing mexup first wouldn't have even mattered...
Trying to go to T2 at a meager income of 15m/s is dumb. Enemy didn't do it and
they made a massive army compared to what we had and they killed us."**

WHAT IS ACTUALLY IN THE CODE (checked 2026-08-31):

- **There is no T2 gate at all any more.** `RushReady` has ZERO definitions in
  the tree -- only four stale comments in `policy.as` and `tunables.as` still
  refer to it, and `apex_t2_energy` (1200), `apex_t2_energy_from` (12) and
  `apex_t2_energy_reactor` (400) are read by nothing that gates the decision.
  The advanced plant is PRICED by `ProposeTech`, not gated. So "go T2 at 15
  m/s" is not a threshold anybody chose badly -- it is the absence of one, and
  the price is evidently not expressing affordability at low income.
- The same is true of the fusion: expensive energy is priced, and at 10 m/s a
  4,300-metal reactor is ~7 minutes of the entire economy. `docs/22` already
  argues the fix shape -- the decision must be made against what the TEAM can
  afford, not by whichever constructor happens to ask.

NOT YET FIXED. Four distinct items, and he ranks them:
  1. T2/fusion affordability at low income (he blames the loss on this alone).
  2. Army suiciding out instead of holding inside our own turret cover.
     Said again 2026-09-02 after a watched 4v4 (Aethermoor Creek, +50%):
     "We're still not good at fighting. Feels like our armies do not work
     together well - we walk too close into enemy fire, we don't coordinate
     to help each other out, enemy attacks in one massive blob."
     Then, watching the next one (watch-4v4d, same map, lost ~34 min): "That
     was a pretty good front line this game. We lost sadly, didn't scale
     quite well enough... but the line held for a while." Measured: the four
     lines stood from minute 10-12 to 20-24 (up to 4,350 wide); at minute 20
     our four had 107k built to their 145k, and three of ours had 3.4-3.7k
     in economy against their 4.9-12.2k -- the advanced cons spent 268 of
     396 decisions on defence/protect and 14 on mex upgrades. Trade at 20
     min: 35k lost, 9.5k killed.
     MEASURED (watch-4v4c, Aethermoor, +50%, lost at 36 min): at minute 20
     our four players had lost 39,600 metal and killed 9,700 -- army K/D
     0.20 against BARb hard's 2.60 -- on 0.43 of their metal produced. The
     choke line was elected 114 times and never held because the army in
     front of it lost every exchange. This, not the wall, is what decides
     the team games now.
  3. Turret line drifting BACKWARD instead of concentrating forward.
     (T1 half landed 2026-09-02, commit 82061f8, `tools/test_frontline.py`
     is the contract; the post-T2 line is still T1 and thins -- ISSUES.md.)
     Same 4v4: "We were kinda making a front line. It was too close to our
     own base though." The line stands at the furthest capped mex, bounded
     by halfway; with few mexes it hugs the base. Whether it should stand at
     halfway regardless is an open question to him.
  4. Fight orders used too freely.


## 2026-08-30 — ARMY COMPOSITION: reach never arrives

*"We need more range!"* Mammoths and Sumos only; *"sumos will barely even reach
the tzar tanks shooting at it, and the Mammoth is outnumbered."* And the squad
frame: *"what does a mammoth need to be successful? radar, jammer, sheldons,
Arbiters, maybe an AA, maybe a twitcher/rezbot."*

MEASURED: reach holds 0.04-0.07 of army metal against its own 0.35 target,
across every attempt. FIVE pricing changes failed to move it (`apex_range_worth`,
a ShieldShare unwind, a range-scaled hp exponent, a standoff-exposure discount,
the tier fade); one of them took reach to 0.03 and tanks to 0.65. Allocating
the draw to the owed class DID move it (0.06 -> 0.12) but deadlocked
production -- see `apex_line_alloc`, off by default with the measurement beside
it. A share cannot be produced by a nudge when the per-metal spread is ~12x.

Also his: T1 rocket bots are worthless after T2 (FIXED -- one fodder bar), and
spiders are near-worthless on flat maps (NOT implementable: no elevation
binding; `ai.GetPathLength` detour sampling is the available proxy).

## 2026-08-30 — THE FORTIFICATION DOCTRINE (unresolved; nothing implements it)

Said again 2026-09-07, and it names the trigger the model was missing:

> "When enemies are getting closer and closer to our base and we're at T2 we
> really really need to try and making T2 or T3 defense to stop the enemies.
> It becomes a life/death situation."

**Second master blocker, measured 2026-09-07: our own ground reports the FLOOR
hazard while it is being taken apart.** `HazardWith`'s loss term reads what has
already been destroyed here; its presence term is scaled by the gradient toward
their BASE, which is zero at ours by construction. `20260907-175233`, minutes
21-26, four mexes down to one and 1,148 / 2,251 / 2,337 metal of losses per
sample: `home[hazard=1.25/ks]` on every line -- exactly `apex_risk_floor`/120.
Defence gain 0.03; static defence 1.7% of spend against BARb's 15.9%.
`ApproachP` (`coverage.as`, `apex_hz_approach`) closes that blindness and was
MEASURED INERT -- 8 games, docs/27. It lifts hazard 4x on a measured approach
exactly as designed, and defence spend does not move (12.5% -> 13.7%, T2+T3
50.3% -> 49.9%), because on the same log lines `short=1.00->1.00`: one tower
adds no measurable cover against a 2,000+ wave, so `gain = stake x hz x stopped`
is multiplying a zero. **Hazard was not the blocker. `stopped` is** -- the
original master blocker below, still unfixed and now confirmed as the only one
that matters. Left at 0 as an instrument.

His spec, verbatim in shape:

1. **T2 constructors are defended HEAVILY while they work.**
2. They build the strong **T2 defences, then a T3 defence**.
3. Then **T2 radar and T2 jammer**.
4. **T1 cons around that front line build NANO TURRETS** — both to build the
   fortification faster and to **heal the defences when they come under
   attack**.
5. **Only after all that, AA flak.**

The result he is describing is a fortification that survives, instead of the
current pattern: expand well, spend everything on eco and a gantry, be dirt
poor, and meet a thick army with nothing built.

WHAT BLOCKS IT, measured 2026-08-30 in a game he watched:

- **THE MASTER BLOCKER: defence prices to zero exactly where his doctrine
  puts it.** Median defence-want value by threat at the site — 0-500: 0.0163;
  500-2,000: 0.0001; **above 2,000: 0.0000**. `stopped` is the share of local
  threat one tower newly stops, so against an army the denominator is huge and
  any single turret is worth ~nothing. Every element of the doctrine sits on
  contested ground, which is precisely where the price is zero. Nothing else
  on this list matters until this is fixed. A watched example: a T2 con DID
  want a Cerberus at the mid-map cluster and it priced `val=0.0000`
  (`stopped=0.046`, `threat=6180`).
- **Nano turrets carry no repair value and no front-line value.**
  `want_nano.as` prices a nano purely as build power (BPGap,
  UnservedLineSpend). Point 4 of his spec — heal the defences under attack —
  is not modelled at all, and nothing prefers a nano AT the fortification.
- **`apex_wall_efficient` penalises the heavy turret.** Added 2026-08-30 to
  stop Agitators; it ranks wall-slot towers by cover per metal, so it cut the
  3,100-metal Cerberus he wanted to `xWallEff=0.208`. Aimed at one thing, hit
  another.
- **The jammer overlap test uses 0.8x radius.** `GetJammerRadius=360`, so the
  exclusion radius is 288 while the field is 360 — two jammers 300 apart both
  pass and their coverage almost entirely overlaps. 50 built in one game;
  spacing must be a MULTIPLE of the radius, not a fraction.
- **Escorts are not going to the forward T2 con.** The fight census shows
  `guard` is the largest pool by far (1,392 and 1,648 unit-samples in two
  games, against `attack` 20 and 4) — so the army IS on guard duty, just not
  on the constructor that is building the fortification.

Read as VALUES rather than as a build order (the paradigm forbids a sequence):
the ordering he describes should EMERGE from a T2 con at the front being a
high-stake asset, a nano near a damaged tower being worth the repair it
returns, and AA being worth less than the guns until the guns exist.


## RULING (2026-08-30): identical expensive builds are SERIAL — all hands on one

Watching four fusions rise side by side: "if we were to build four fusions
with four constructors, and let's just say that each one took four minutes
to build, then if we took all four of those constructors, and we had them
making just one fusion, then it should take only one minute... Unless
distance is a huge issue, there's no reason we should ever make two
identical, really expensive things right next to each other at the same
time." Landed (commit 2066d91): a banked bill exempts a site from the
income crew clamps (the bank prepays the job), and a duplicate site opens
only when every manned site of the def is worker-saturated. Awaiting his
eyes on a watched game.

## OPEN (2026-08-30): the army stands off while the base dies

"Our army will keep distance from an attacking army that is destroying our
base. We arguably have more than they do... yet we avoid the fight and let
them kill our base." Mechanism attributed (commit 28acfa1): odds-refused
DEFEND pools fell back to FRONT posts — out of the intruder's support
radius, making every other pool's election worse — and the odds sum
counted no towers on our side. Fixed: refused-at-home pools muster at
base; allied static defence joins the odds. Soak trade efficiency
(soak8v8-s1: killed 12.4k vs lost 25.7k with the LARGER army) is the
before-number; his watched games are the test.

## OPEN (2026-08-30): 8v8 is worse than 1v1 — first measured strands

His report. ISSUES 2026-08-30 entry holds the numbers from the first clean
Supreme Isthmus soak: trade 0.48, two players frozen at 2 mexes (a
pastFront-axis fix landed, commit 5918909, but the re-soak shows the
starvation persists -- strand still open), all-8 air plants with zero
bomber damage, defence spend half of stock's and 100% T1.

## RULING (2026-08-29, late): team defence goes in FRONT of the front ally

He refused to host the 8v8 over it: "I find it too embarrassing how all
our AI makes tons of turrets in their own base instead of in front of
their allies base who is in front of them. It looks too stupid." First
half LANDED: a closure-ring bearing whose corridor passes a teammate's
home now counts closed (the ally's base is the wall), so back players
stop ringing themselves. Second half LANDED, awaiting his eyes: the
allyfront candidate sites at the most exposed teammate's door, staked by
that ally's published economy (TV_ASSETM) times AnswerShare, and the
defence census terms now price MY SHARE of the enemy team rather than
all of it (his same-night read: "compensate for the entire enemy team,
not just one eighth"). Validated mechanically on a 4v4: spend split
43.5k/27.6k front vs 13.1k/13.3k back, `apex: allyfront cand` pricing
live. Whether the forward posts WIN often enough to look right on screen
is his watched call.

**2026-08-29 (night, live watch) — confirmed and asked-for-more.** The
wave-concentration defence fix he confirmed live: "We are making more
pulsars now and I'm happy to see that. We need even more :) They're cheap
compared to all these T3 we're making." Standing direction: heavy towers
are cheap relative to T3 army — keep the defence market leaning that way.

**2026-08-29 (arena watching) — encirclement doctrine.** "We tend to push into
enemies which are backing up and forming an encirclement around us. This game
gives a damage bonuses when you encircle your enemies. So if we push in and let
them spread out and go around us, we're going to take more damage. Preferably
we all shift to one side and try to wrap around the edge of their line and then
swallow them." (BAR's flankingBonus is the mechanic: off-facing hits do bonus
damage, so being wrapped multiplies incoming DPS.) Squad engagements should
bias to one END of the enemy line and roll it up, never press the centre of a
spreading line.

## OPEN HINT (2026-08-29): "Remember radar might just be set wrong so you
can tweak it." First instrumentation: builds 10-13 T1 + 1-3 advanced per
game (stock: up to 26 T1), median farthest radar 3,248 elmos from home —
count and reach look sane, BUT we see under half of stock's real army
(foeMass 3-6k vs ~15k actual), and radar-gap sites were among the things
the collapsed PastFront axis vetoed (fixed in FoeAnchor). Re-read the
intel numbers on the winrate4 arms; if still blind, the tweak targets are
RadarSees' one-radar-per-coverage rule (no redundancy — stock builds 2x)
and apex_insure_rate.

## RULING (2026-08-29, evening watch): exposure-scaled mex defence

"The closer our mex is to the enemy and furthest from our army, the
stronger the defenses should be." The per-mex floor stops being flat:
it scales with the spot's exposure (forwardness toward the enemy, beyond
the army's staging reach).

## OPEN (2026-08-29, evening watch): 2 units fought 4 thugs to the death

"I watched 1 mace and 1 rocket bot fight 4 enemy thugs. We didn't run
away, the rocket bot still was firing and not running when it died. This
makes me question our combat logic a lot." Candidate mechanisms, to
attribute from that game's own log: fodder/scout tasks are EXCLUDED from
the withdraw loop entirely; the C++ base-defence ring is
fight-at-any-odds ground; or the W order lost to the task's re-asserted
orders (the known churn). The universal per-unit self-preservation rule
(leave a locally hopeless fight regardless of task) remains unbuilt.

## OPEN (2026-08-29, evening watch): rez bots loiter in danger

"We also have rez bots standing around dangerous areas rather than moving
to safety after they do whatever job they had." An idle rezzer's default
is wherever its last corpse was — battlefield ground. The fallback when
no job wins should be a safe standby (medic setback / behind the front),
not standing in the graveyard.

## RULING (2026-08-29): economy killing is the win path — ENERGY first

Asked whether hunting the enemy commander should be the 1v1 win condition
(stock decides every game that way): "Killing economy is usually a better
way to win. Keep working on the other stuff I mentioned." Then: "Killing
energy economy is even better than metal." So the offense doctrine:
strikes prioritize their ENERGY (fusions, advanced solars, converter
farms — concentrated, chain-explodes, stalls everything they run), then
metal. The eco-dive already ranks fat energy first; the missing half is
DELIVERY — the chronic zero-raids flag means their eco is never touched.
No commander-hunting doctrine.

## RULING (2026-08-29): the concentration doctrine for defence

"So we know they push hard, we can make them pay for it … slow them down
with some walls outside so enemy army is broken up before they get to us.
Have an unusual amount of tower at some spots. Try to deeply cover those
choke points. Easy wins there. Move 8 spread out defenses from mexes into
less choke points which overwhelm the attack. It matches concentration
with concentration…. I do agree we don't want to tower dive so much that
we have no good army left. Rocket bots, artillery… they get free shots
sometimes so we should leverage that. We need to ensure that enemies
cannot walk past our choke points and get a free path to our economy."

Implementation order: (1) gate concentration — the crowd gate must not
refuse depth at a choke gate, and a covered gate keeps deepening until it
overwhelms; (2) the per-mex spread floor shifts its budget into gates;
(3) a teeth line across the choke span ahead of the gate towers;
(4) long-range class leverages free shots at the gates. The static-kite
fix (no tower diving) he endorsed here is measuring in winrate7.

## STANDING PRIORITY (2026-08-29): win 1v1 reliably FIRST

"I suggest you get us winning 1v1 games fairly reliably and then go to
2v2, and then on to larger team games." The campaign order follows: the
1v1 conversion failure (ISSUES.md — retreat deaths, commander dying at
home on a won economy, Glacier's even-eco grind) is the work queue until
1v1 decided results flip; team formats after.

My understanding of the feedback he has given, in my words. This is a standing
brief, not a changelog — `CHANGES.md` records what was done and measured, this
records what he actually asked for and why.

Items marked **UNRESOLVED** have been raised and not fixed. Several have been
raised repeatedly, which is itself the point: re-reading this before starting
work is cheaper than being told the same thing a fourth time.

---

**Archive policy (apexearth, 2026-08-20): this file must not grow forever.**
When an entry is completed (landed + he has seen it work, or confirmed live),
MOVE it to `feedback/<date>.md` — date of the original request. This file
holds only unresolved asks and standing preferences.

## IN PROGRESS — Spend the overflow: keep looking, escalate the ladder (2026-08-28, night)

Watching a 2v2 he won (Archsimkats Valley +100%): "1 of our guys never made
a Gantry... he should keep looking and trying. I actually see a ton of
available spots right near home... We make 600+m/s but only use ~100. If we
aren't going to make gantry then we should be spamming nukes, making tons
of LRPC, end game weapons, etc... Gotta go somewhere - gotta do something."
Rulings attached: "make more nanos around our gantry and if we can't do
that then make another gantry"; "Blue... could certainly afford a second
gantry. They made some LRPC, could just keep going and making more"; "We
need to stop making T1 air army when we have T2 available"; "we need to be
willing to build further outside our base/current location"; "separat[e]
out where we put our economy so it isn't all in one spot. Better if only
half our economy blows up instead of the entire thing."

Status ledger: ISSUES.md "THE OVERFLOW CAMPAIGN" entry. Wave 1 (site probe
ladder, overflow-scaled strategic parallelism, wealth waiver on the copy
laws, T1-air mute) landed with three audits; validation run next, then his
eyes. Eco-cluster split and nano-reclaim C++ still open.

## UNRESOLVED — The 2026-08-29 midday batch (watching Glacier/Isthmus)

1. **No Gauntlets past T2** (LANDED c7bc9df, awaiting measurement): T1
   towers keep apex_t1_def_late (0.15) of their value once a standing T2
   builder can make defence; tier derived (Catalog::gT1Hand), no name
   lists. The audit's t1-towers-after-t2 check scores it — his Isthmus
   game read 27,580 metal into 23 post-T2 T1 towers as the baseline.
2. **Gantry reclaimed** (LANDED 81d8a0a): a plant with no mex-capable
   constructors (reach 0) is outside the lab-retirement law; 7
   reclaim-rebuild loops in the Isthmus game were this.
3. **Flanking** (ATTRIBUTED, his ruling needed — ISSUES.md): the flank
   via exists and fired 13x on Isthmus, zero in his tight games; DEFEND
   fights have no flank concept, and chargers are excluded by his own
   Behemoth ruling, which the Titan wish contradicts.
4. **Feature bloat** (ANSWERED with an instrument): tools/battery.py —
   fixed 3-map battery, structural metrics to tournaments/battery.jsonl,
   run after each behavior session; first baseline row 2026-08-29. Plus
   his same-day ruling on the bisected regression: "Keep all on", costs
   ground down by mechanism, not switches.
5. **Performance spikes** (ATTRIBUTED — ISSUES.md): the builder
   election's protect stack, 126ms worst call on the 43-min game; no new
   candidate generators until it is optimized.
6. **Misstep detection** (LANDED 61e7d1b): audit check
   build-abandoned-army-idle joins the position-carrying con-retreat
   line against army snapshots — his geo example is a permanent flag now.
   Still queued from the same message: pass-guarding on Glacier (the
   choke-gate work is the foundation; watch where towers land).
7. Standing insight: "We survive on these really big maps just because
   we are aggressive with capturing mexes... on maps where it is tighter
   we do much much worse." And: "We were doing quite well at one point
   yesterday, some small bits went wrong along the way."

## UNRESOLVED — The 2026-08-29 watch batch: defence is the loss cause now

He confirmed the long-range fix live (archived, feedback/2026-08-29.md:
"we are losing due to other issues") and named the other issues, watching:

1. **Perimeter, not interior** (LANDED 2fbf491, awaiting his eyes):
   "We make defenses inside of our base instead of at a nice perimeter."
   Escalated live after a lone Pyro gutted the rear eco: "6 turrets all
   clustered in one area near a mex, but nothing was guarding our economy
   in the back - so the enemy just ***walked around*** our defenses...
   i often see us putting the defenses behind what we want to protect
   instead of in front of it." Landed: Front::GateChokes offers every
   doorway of held territory to the defence auction (apex_choke_gates);
   asset-guard sites stand half their reach enemy-ward of the assets
   (apex_guard_forward). Open residue: the 6-in-one-cluster crowding and
   the open-flank (no-choke) rear approach — watch whether gates+forward
   siting redistribute before touching the crowd gate.
2. **T2 transition is a death window** (MEASURED, ruling pending):
   "We're almost always light on units when we transition to T2." 14 of
   17 tech events today started with the enemy's fielded army above ours;
   worst: lab sited at armyOurs=120 armyFoe=700 funded=0.11 — the funded
   discount applied and the lab still won the auction. His direction so
   far: "We should be careful with our army if we're fielding less than
   the enemy" (posture, not necessarily a tech delay). Asked whether to
   harden the gate vs fund army through the window; he answered with the
   defence priority instead — re-ask when defence lands.
3. **Mex encampments undefended; use choke logic** (LANDED with #1):
   "defend chokepoints ahead of where the mexes are. We want to prevent
   the enemy from getting in there."
4. **Squads screen expansion** (OPEN): "when a constructor leaves a base
   to make mexes further away the brain can tell the squad to guard the
   area where that constructor is going."
5. **Standing to die when outnumbered** (LANDED f928ef0, awaiting his
   eyes): "we just stood there while they surrounded us... If we sense
   too many enemies can shoot at us we should immediately back up instead
   of waiting to be hit." Attributed on his Boreal Falls game: (a) the
   withdraw sensors both missed a fight lost 1796:31 — the casualty
   scoreboard (LosingFightHere, trade=lost:killed log tag) now pulls
   squads back on observed local deaths; (b) mayKite forbade a Rocko
   (475) from kiting a Stumpy (350) — outranging now always permits the
   backstep. "Maneuvering / forcing the enemy to move" beyond backstep +
   ring orbit is still open.

Also still queued from the morning ask: "build up these guys [snipers/
hounds/arty] in unit numbers so our army can grow very powerful" —
long-range composition share untouched (ISSUES.md).

## UNRESOLVED (landed, awaiting his eyes) — Exit lanes and pooled advsols (2026-08-28, watching live)

Two observations from the NullAI watch game, both landed same hour:
(1) "we just built a lab with a turret right in front of it - this is a
great example of that bug where labs are built too close behind other
things" — caught in the log (LLT 2480,2880; lab 13s later 114 elmos
behind it). ClearExitLane pushes a plant site back until no own committed
static sits in the lane ahead; OffFactoryExit slides a ground-defence
site sideways out of any factory's doorway. (2) "we have 3 separate T1
cons all starting an advanced solar at the same time. They should each
work on 1 together. They'll see rewards faster and that'll compound" —
the rich-bank `parallel` flag skipped the join fold entirely; it now only
bypasses the site CAP, so hands pool onto an unsaturated site first and a
new site opens only once the crew cap answers "full".

## UNRESOLVED — Building pace, spread, and honest reclaim (2026-08-28, evening)

Four asks and a protocol: (1) "How can we spread our some of out buildings
into smaller groupings so chained exposions/death isn't so huge when it
happens?" — base-layout design work, the lattice's chain-explosion model is
the tool, NOT yet implemented. (2) "When we reclaim obsolete buildings -
we often recreate them in the exact same spot. We should never want to
create obsolete buildings." — LANDED: obsolete-on-arrival law shared
between the ladders and the victim election (GenObsoleteOnArrival /
ConvObsoleteOnArrival). (3) "the buildings we want to reclaim aren't
accessible by ground units so we need to get the ones which are closer" —
LANDED: unreachable victims quarter-price for ground cons
(ReachVictimMul). (4) protocol: "run 1v1 games vs inactive AI to work out
our building and obsolete reclaim" — NullAI 1v1 on Comet Catcher is the
instrument for build/reclaim behavior.

## UNRESOLVED (landed, awaiting his eyes) — Resurrect commanders, never reclaim them (2026-08-28, evening)

"Can we make sure we resurrect our commanders instead of reclaiming them?"
LANDED: (a) C++ ReclaimTask never picks a *com_dead corpse (the burnt
_heap stays edible); (b) a dying commander publishes its corpse position
(comwx/comwz/comwf) and every ally rez bot's TOP rule races to resurrect
it (RezzerComRescue, above the medic, threat-vetoed, 4-min freshness);
an active resurrect already marks the area so area-reclaims steer off.
Logs: `apex: commander fell`, `apex: com rescue`.

## UNRESOLVED — The 2026-08-28 rebalance campaign (his test protocol attached)

"Our balance is generally off now in the game so we need to take a careful
look at some things." Four asks, one instrument:

1. **Army production feels down** — "I think in general we aren't making
   as much army but I'm having a hard time seeing why." Diagnose, don't
   guess: prime suspects are the ally-share census division at 8v8 scale
   (1/8 shares) and T3/gantry displacement.
2. **Gantry too early now** — "We went from making no gantry at 400m/s to
   making it at 80m/s - it is too early now." The team-purse budget scales
   with roster (8 x small = clears at minute ~5); re-anchor on the HOST.
3. **Hover plants are not navy** — "commanders walking all over the place
   to make hover factories on the water... I mentioned we needed to make
   navies in the past and that turned into us making hovers - oops - not
   what I meant. That walk probably kills a lot of the performance of our
   commanders... We really just [need] 1 or 2 teams to make some navy in
   the game... Ensure our economies remain strong." So: no commander
   treks to shore for hover plants; a naval ELECTION (like the air lead)
   picks 1-2 teams to build real shipyards; everyone else stays on land
   economy.
4. **Eco player goes AFK** — "They'll make mexes and some energy and then
   they go AFK. This is seen on Supreme Isthmus 8v8 maps." Diagnose from
   the idle telemetry.

**His test protocol:** "run 10m long supreme isthmus 8v8 games, and then
once we believe we are OK in performance we can start looking at 15m, 20m,
etc..." — 10-minute Supreme Isthmus v2.1 8v8 is THE tell; extend the
horizon only after the short one reads healthy.

## UNRESOLVED (landed, awaiting his eyes) — One advanced plant at a time; gantry host anchor (2026-08-28, late)

Watching his game: "I am seeing Purple in my game make a T2 vehicle plant
and a T2 air lab at the same time. This is a huge 'no no'. I also see
green making a gantry at just 50m/s, that is too early." Landed:
(1) `Market::AdvPlantInFlight()` — the tech lane, the air mandate and the
gantry all defer while THIS player already has any advanced plant in
flight (the two lanes only checked their own defs; the kin division only
sees extract/convert axes, so a T2 air lab was invisible to a T2 vehicle
candidate). Logs `apex: adv-plant defer`. Serializes STARTS only; standing
copies stay wealth-governed per his adv-air ruling. (2) the gantry's gain
scales by (host's own income / apex_gantry_host_inc)^2, anchor 100 — the
team purse makes the case, the host's own feed times it; green at 50 gets
a quarter gain and loses the election.

## UNRESOLVED (landed, awaiting his eyes) — Gantry by ~100 team metal/s (2026-08-28)

"We do not create Gantry buildings soon enough. If the enemy comes at us
with a Behemoth and we do not have one we are in big trouble... I saw a
team with 400m/s income and no gantry - we can have a gantry at like 100
m/s." Reproduced (first corgant ELECTION 27.8-28.6 min on ~400 team m/s,
none finished): the super budget read ONE player's income (needs ~155 m/s
each) and the gain read the share-scaled army gap. Landed: the gantry's
affordability reads TEAM income over apex_gantry_afford_s (100s -- bill
clears at ~100 team m/s), its gap is the TEAM's (full census vs team army),
and apex_gantry_insure (0.5) prices T3 insurance even with no gap on the
books. Close on a watched game with a gantry standing by mid-game wealth.

## UNRESOLVED (landed, awaiting his eyes) — Defence before Basilisk; shields vs LRPC (2026-08-28)

"We consistently make Basilisk before T3 or even T2 defense - we need
better defense esp when we're losing. Also if enemy has LRPC we need to
build shields." (Basilisk = corint, the Cortex LRPC.) Landed: (1) silo and
LRPC gains scale with the defence target's fill (apex_offense_def_floor
0.1) -- an under-defended or losing base all but silences the big gun,
antinuke and gantry untouched; (2) a seen enemy LRPC (derived def set, any
faction) joins the shield want's bombardment basis and waives its
1800-elmo nearness gate, which a cross-map gun never trips. Logs:
`apex: enemy LRPC seen`.

## UNRESOLVED (landed, awaiting his eyes) — Squad falls back together; rear at 60% (2026-08-28)

His clarification of the retreat complaint: "I'd mentioned in the past
pulling to back of the pack when under 60% but I think sometimes our squad
is only a few people and they're all low. Whole squad should fall back if
they're all too low. The goal is to keep people in the fight but maybe
stop them from getting targeted by the enemy by having them move back."
Landed same day in C++: (1) squad members enter the rear ring at
apex_coward_hp (0.6) instead of at the 8-50% retreat threshold — screened
behind healthier squadmates, STILL FIGHTING, rejoining the line when
repaired above ~69%; (2) when EVERY member is under apex_squad_fall_hp
(0.6) the squad leaves together on one retreat task (nobody's individual
threshold ever fired while all hovered at 30-50%, so the squad stood and
was focused down). Committed pushes, dives, charger deliveries and
defended home ground are exempt, same as the existing vote. The
wounded-power vote still counts only sliver-HP units so it does not trip
on a merely scuffed squad.

## UNRESOLVED — Units retreat at a very low HP % (2026-08-28)

"I have noticed in recent games our units tend to retreat on a very low
HP %." Confirmed real: deaths.py shows retreat(auto) switches at 6-10% hp.
The obvious lever is MEASURED BAD (2026-08-28 A/B, 6 seeds/arm, Altair):
raising the floor to 0.18 (`apex_retreat_floor`, now tunable) moved the
switch to ~20% hp as intended and made everything worse -- army K/D ratio
0.202 -> 0.065, metal lost +51%, units still died RETREATING, just with
more HP donated. Both arms' combat deaths are dominated by
`->retreat(auto)` deaths: units die on the way out regardless of when they
start. The real problem is retreat SURVIVAL (where the unit runs, whether
anything covers it -- C++ retreat pathing), or not retreating at all for
cheap units, not the threshold. Default stays 0.08; the knob is on the
dashboard for his own experiments.

## UNRESOLVED (landed, awaiting his eyes) — Air keeps re-bombing the same target (2026-08-28)

"Our air tends to repeatedly try bombing the same thing, need a bit more
variance in targets." Mechanism: `CBombTask::FindTarget` is a
deterministic argmax, so every squad re-elected the same winner. C++ fix
LANDED same day: a target any squad committed to inside
`apex_bomb_revisit_s` (90s) is discounted 5x fading back to full
(`apex_bomb_revisit_disc`), own current target exempt so runs never
swerve. Smoke: 12 commits spread over 9 distinct targets. Observability:
`apex: bomb-commit` log line + the `air-target-fixation` audit check.
Close when he watches a game and the fixation is gone.

## UNRESOLVED — Kill their economy, not just their army (2026-08-27)

Watching, after the ledger campaign ("It works pretty good now"): "we only
were fighting the enemy army and defence. I never saw us specifically try to
take our enemy build power or economy." His priority order, stated: enemy
converters and fusions FIRST, build power (nano turrets) second. Related in
the same breath: "I don't know if I remember seeing us make scouts. Maybe we
didn't know where enemy stuff was (?)" — he connected the intel gap himself.
The audit agrees: `raids-exist` flags zero raid tasks in every recent game.
Three linked halves: scouts get made, intel finds the eco, the army (raids)
spends kills on it in his priority order.

## UNRESOLVED — Mass air before attacking with air (2026-08-27)

"I want to see us massing more air before attacking with air." Note the
standing C++ finding (air-grouping constant, bar-ai-air-grouping memory):
air squads cannot group beyond the DLL's cap, so massing may need the C++
layer, not another ratio.

## UNRESOLVED — Not enough build power on the gantry, again (2026-08-27)

"We had more eco than our enemies, but they kept producing a great many
Titans. We were much slower because we didn't make enough build power around
our gantry. (a recurring theme there which we still need to improve.)"
Same complaint as the 2026-08-27 five-labs-four-nanos finding; the demand
law scaled with income but the T3 line's spend rate is another scale up.

## NICE TO HAVE — Artillery on hilltops (2026-08-27)

"We should build artillery on hilltops to attack enemies below."

## STANDING RULE — Always be expanding the economy (restored 2026-08-21)

His words, 2026-08-21: "Are we generally making sure that we are always
making some economy like energy or converters? This is usually the best
choice." And on being shown it was lost: "That's an old rule I made early
on, always be expanding the economy. We lost it at some point."

It had drifted out: every eco lane became demand-gated (energy on a
forecast shortfall, converters on measurable spare), and at income ~ pull
neither fires — measured 8v8 players going 5-13 minutes with zero eco
completions while stock never passed ~4. Restored as the AlwaysEco ladder
rule (builder/mexguard.as, apex_always_eco): when nothing energy-side is in
flight, build converters if energy spills, else the next generator rung.
Treat any future gate that can silence ALL eco lanes at once as a violation
of this rule.

## UNRESOLVED — Enter fights together: pre-contact assembly, "crossing the T" (2026-08-20)

"When you're about to get into a fight, you need to organize your units so
that all of them enter the fight at about the same time. This means
spreading your units out, crossing the t." The travel wall from his earlier
"wall of fire" feedback exists in the custom C++; the missing pieces are the
pre-contact assembly wait, approach speed-matching, and DEFEND pools
bypassing squad shape entirely. Full spec in ISSUES.md (C++ SPEC entry,
2026-08-20).

## UNRESOLVED remnants of the late-game air doctrine (2026-08-20)

Landed halves archived (feedback/2026-08-20.md). Still open: flak PLACEMENT
is not yet "spread out around your base" (it clusters at the nano block /
front), and scouting COVERAGE has never been measured against the threat
readings it feeds.

## UNRESOLVED — The army-brain campaign: three detectors and a merge fix (2026-08-19)

Four directives from one hosted-play night, all one campaign:

1. **Exploit enemy complacency.** "If enemy is not attacking us but just being
   defensive, we should form our own defense a bit more and take the time to
   scale our army." Needs a passivity detector (near-zero recent losses + base
   uncontested + static front); in that state, greed eco AND scale army on our
   own timeline — today ArmyDeficitMult damps the economy against a passive
   hoarder, the opposite of taking advantage.
2. **Push back when pushed.** "If the front line is moving back into us then we
   need to make more army and push it back." Needs front-position memory: the
   front centroid's distance-to-home, smoothed; sustained shrink raises the
   army budget share and attack quota until the line recovers.
3. **Defend the flank the front is wrapping around.** "One big vulnerability we
   have is enemies attacking through the side. If we know the frontline is
   shifting like that we should work hard to make defense in our base." Same
   detector, second axis: track front BEARING as well as distance — a bearing
   swing means a flank attack forming; base/flank defence goes up before the
   damage, not after.
4. **Squad merging is the root of the suicides.** "We should compare our power
   in the area of the attack zone and only go in if our power is strong enough
   IN THAT AREA" — investigated 2026-08-19: that comparison EXISTS and is live
   (fixed twice in past sessions); what remains is the known ISSUES item that
   fighting groups stay 1-2 units. Bad trades from tiny squads are also what
   latches turtle ("we are probably often going into turtle mode because we
   trade so poorly"). Fix the C++ squad merge first; the odds check is only as
   good as the squad it is computed for. Measure on fight1v1.py trade ratios.

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
- **T2/T3 defences belong at the FRONT of the base, not the back half
  (2026-08-17).** "I see our guys making them in the back half of the base and
  it does nothing to defend us until we're already too far dead." Attributed:
  the corafus/armckfus build_chain hubs placed a Doomsday/Gambit beside the
  reactor — deepest rear ground we own — and were removed (AA hub entries
  stay). Front-line heavies keep coming from Pulsar/FrontFortress line siting.
- **When losing, shift to army; T1 cons are a floor of 3, not a scaling want
  (2026-08-17).** His rule verbatim: "Make T1 cons if we have under 3, or if we
  have extra metal, prefer army always when enemy army seems more powerful than
  ours." Wired as the con-quota clamp in facqueue (apex_con_min=3,
  apex_con_outmassed=1.0); metal-full still boosts cons.
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
- **NEW 2026-08-16: near the enemy base, dive for the economy.** "If we know we
  are near the enemy base, we should dive straight into it and prioritize
  targetting their economy. Don't get distracted by military or towers if an
  advanced converter or afus is in range." Target selection, not massing: once
  inside/near their base, big eco (AFUS, adv converters, fusions) outranks
  military and towers.
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
  680-metal glass cannon leaves on the first scratch, not at 60% hp).
  MEASURED same day (6-game batch): deaths-on-retreat fell 100% → 17%; most
  now die holding DEFEND duty instead. The deeper fix — standoff so damage
  never starts, and jammer cover above — is still open.
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
  `apex_adv_air_income` 150, fighter floor `apex_fighter_per` 40 -- that second
  one is gone from the tree.)
- More shields late game — enemy LRPC becomes the problem, and air handles the
  late game better generally (2026-08-16).
- **Don't limit advanced air plants to one when rich** — count scales with
  income, one per `apex_adv_air_income` (150) of metal/s (2026-08-16).
- **UNRESOLVED: sometimes no advanced air plant at all in a long game
  (2026-08-16).** Despite the `apex_adv_air_income` wiring above, long games
  still finish without one. The trigger exists but does not reliably fire —
  find why (gate never reached? displaced? no builder picks it up?).

## Hosting performance (2026-08-16, from hosted play)

- **UNRESOLVED: our AI causes pathfinding load and the host lags hard.** "When
  i host it i end up just lagging too much... plus our units get stuck and we
  end up stalling hard." Suspects: order churn forcing constant engine
  repathing (DEFEND positions rewritten every pass), sprawled bases making
  units thread their own buildings, raw unit count.
- **UNRESOLVED: when the host lags, the AI goes dumb.** Sim-rate drop delays
  order application (the measured ~45-sim-sec lag class) and AI update cadence;
  degradation compounds. Should improve as the CPU fixes land; re-check.
- **FIXED 2026-08-16 (measured once): idle constructors / idle air labs at a
  full bank.** Root cause: met quotas + no terminal spend rule. `cfa300e`:
  idle-election backoff (CPU), Assist::Fallback made terminal (wide radius,
  adv cons join sites at full bank, factory-guard last leg), facqueue overflow
  may pick combat floors. Long rich validation game: true-idle adv-con samples
  fell to 8 (all during an energy stall) from a baseline where they dominated
  (2,434 in min 30-50 of one hosted session); 69 idle rescues fired; backoff
  visible as 5us elections vs 820-1000us working ones.

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

## OPEN (2026-09-05): a dead mex is not rebuilt quickly

*"When the enemy kills our mexes we don't seem in a rush to rebuild them. We
go for minutes leaving those mexes dead."* and, the same night after the trip
risk model shipped: *"it still seems to be that once our mex dies we have some
rule preventing us from quickly recreating it. I'm quite confident of this
based on what I've been seeing."*

Measured (`tools/rebuild_lag.py`, 1v1 vs BARb hard, no turrets, seed 15):
12 deaths, lags 0.0-8.5 min, quartiles 0.2/0.6/3.5, 5 over two minutes, 1
never. Mechanism: `StreamSurvival` prices a spot by the loss memory
(`LossRateAt`, tau 180 s) times the cover shortfall, and cover read ZERO
with no turrets because posted units were not cover in the risk model.
Six 6-game sets on 2026-09-05 (ISSUES.md, night entry): units now count as
cover and the mex pays survival over its own delivery time like energy, so a
home rebuild prices at surv 0.92 and v 4.3 instead of 0.5 and 2.3 -- but
never-rebuilt stayed at 3-15 of 24-43 and the median lag at 0.4-1.2 min in
every arm. Not shown fixed. What is left is structural: the per-category
draw gives a v=4 mex one ticket in three, and every con is busy 20-60 s.
Blocked on: his call whether a just-died mex should PREEMPT the draw (that
is a rule, not a price).

## OPEN (2026-09-05): the factory is not supported; army count loses games

*"This time we've pretty much died due to lack of army count and we were full
on metal - so we're just not supporting the factory enough."*

Measured (seed 15): bank 100% from 6.5 min, one lab, one nano until 10.4
min; the lab busy 80% of samples yet 32 orders in 9 min, one per ~11 s --
the lab's own 150 BP, so the nano was not lathing the line. Instrument added:
`[BARAI_DUTY] facPow= nanoOnFac=`. Blocked on: reading it.

## OPEN (2026-09-05, seed 17): a T2 lab while the front was being lost

*"We made a T2 lab while losing active frontline fighting which we could
obviously read/see - we never should be doing something like that."*

Measured: `tech:armalab` drawn at 8.5 min (v=5.21 over convert 4.86) and
again at 11.4 min (v=7.91 over energy 6.24) while `apex: leash` read
need=38-58 against sent_pw=29-35 and `tech-diag funded=` 0.62-0.94. The
lab finished and died at 14.5 min (2900 metal). The tech price is
UpDemand + ConvUpDemand + outclass and carries no army-share term; the
plan's standing obligation (docs/23) is not in that market.

## OPEN (2026-09-05, seed 17): no early rezbots

*"We aren't making nearly enough rezbots in the early game (0 in fact where
enemy has 6, is resurrecting and healing, and we lose those fights because
of it)."*

Measured: 0 `produce:armrectr` in 59 lab orders; `apex: prodrank` never
lists armrectr. It is a builder to the catalog, so it prices in the builder
branch on the loss pool alone (no medic term, that lives in the non-builder
branch it never reaches) and is dropped silently at gain <= 0.5.

## OPEN (2026-09-05, seed 17): expansion, army commitment, commander

*"We're fighting a lot and doing pretty good at it but we don't expand quite
so well. So we lose the long game."* · *"Actively engaging in fights with
every army we make instead of saving up our army."* · *"Enemy pawns are able
to distract our commander for minutes."* · *"Our base was being hit but new
units ran away from protecting it to fight on the frontline."* Directives in
docs/24; not yet measured.

Seed 18, 12 min in, with the first rescaled price live: *"I see 1 rezbot, we
need like 4 or 5 at this point (~12m into the game)."* Mechanism found in
that game: armrectr is a NON-builder to the catalog (no build list), so the
first pricing pass (builder branch) was inert; the live price was the old
non-builder block, a raw m/s stream against gap-rate x quality army gains,
one ticket in a thousand. Rescaled 2026-09-05 (rezwant: gap rate x medic
quality); measure produce:armrectr per game by 12 min against his 4-5.
Then his pricing rule: *"rezbots gain value when: there is valuable reclaim
available; there are units that need repairing; there are units available
to resurrect."* Built as `RezWorkM()` (own missing hp in metal + field
wrecks at resurrect or reclaim value); six-changes set: 2-4 rezbots by
12 min, 2-20 by game end, sized to the work.

## OPEN (2026-09-05, seed 19): the commander walks to far jobs

*"Our commander still chases enemies a LOT which causes him to be long-term
distracted and not useful. Enemies won't even have a trajectory towards our
buildings and he chases them 'into the sunset'."*

Measured (seed 19, live): `commander engaging` 0 times; the D-gun action
issues no move orders. His trail is mex and radar jobs 1,500-2,000 elmo
north of the base (472,2424 / 232,1976 / 456,2120), each `pick=1`: the
drawn want (a converter at 736,3968) failed to execute and the next ranked
want was taken instead, and the `com-fwd skip` reads only the axis
(fwd=1,0 east), so a far spot sideways passes. Enemies met on those walks
are fought where they stand.

Seed 19: *"I still see our rezbots standing around doing nothing far more
than they should... There is plenty of resurrection ability here too but I
only seem to see them reclaim."* Mechanism: `PreferReclaim()` returned true
until a T2 factory stood, and the resurrect path only considered wrecks of
900+ metal (`apex_rez_rich_m`), so no T1 wreck was ever resurrected. Both
rules were a previous session's, not his. Replaced 2026-09-05: resurrect
when the army is below target and energy is not stalling, any resurrectable
wreck by the cost of the unit it returns (`GetBestRezPos`); reclaim when the
bank is genuinely empty or ground is being lost. Idle-standing not yet
measured: 20 of 22 rezbots died at the front (fwd ~1.0) in reclaim tasks.

*"We're going to lose because enemy kills our buildings and we don't remake
them so we just starve to death..."* (the fifth time). Seed 19: 14 mex
deaths, 5 never re-ordered, median lag 2.0 min. A mex want at a spot with a
recent loss was hoisted to the front of the draw (`why=rebuild`) -- a RULE,
flagged as one. REVERTED the same day on what the decide lines showed: it
took a contested mex over a generator worth six times more, the commander
walked out to rebuild, and one spot was rebuilt and lost three times. The
6-game score could not order it (the control replicated W4-0-2 then
W0-2-4). UNRESOLVED -- the starve-out is real; the rule was not the fix.

*"Compare strength, work on that T2 lab while losing, if we're bleeding army
we should try to mass more. Ensure the commander's time isn't wasted. Like I
said - if enemy is running away, fine - let them."* (2026-09-05, after the
rez/rebuild sets.) Built the same day, each with its instrument:

- **Compare strength.** The massing law, `Outmassed`, `ConservativeStance`,
  the local-edge read and `CommCaution` now compare strength, via
  `Market::StrRatio` (each side's metal times its strength-per-metal). The
  `apex: mass` line prints `ratio=` (metal) beside `str=`. Measured: str
  runs above ratio in most games (BARb's mix is heavier per metal than our
  pawns), and flipped a hold decision in 3 of 30 lines. TRAP found on the
  way: the commander's raw dps counted his D-gun (111k), so by strength he
  was six pawns and the strength engage rule from the morning never fired
  in 12 games; manual-fire weapons are now excluded (CircuitDef.cpp). His
  strength is still ~6.5 pawns because the DLL's own power for him is what
  it is; `apex: unit strength --` prints the numbers at 30 s.
- **T2 lab while losing.** The lab's army-gap stream is capped by spare
  metal (`want_tech.as`), as the plant price already was. Measured over 24
  games: labs still land at 8-13 min, every one with no enemy seen and
  bleed 1.00 at the decide -- those are not "while losing". OPEN: no game
  in the sets bought one while bleeding, so the cap is untested against
  the case he watched (seed 17, 8.9 min, gain 23.5).
- **Bleeding -> mass more.** Already the law (`BleedCaution`, 1 + 2 x net
  forward loss / income, cap 1.6); it now prints on the mass line and read
  1.14-1.47 in every game with forward losses. Nothing changed.
- **Commander's time.** `apex: com-time` per minute: jobs, empty
  elections, retreats, bounced re-elections, hp, forward fraction. Found
  and fixed: (1) the flee gate left at ANY influence (0.01) and handed him a
  20 s patrol home 11-15 times a minute in a raided base -- it now compares
  the strength near him with his own and holds when he outguns it
  (`commander holding` / `leaving ... near str`); (2) the forward job skip
  measured only along the base axis, so a radar 1300 elmos sideways at 0.8
  of the way to the enemy went through and he died there -- jobs beyond
  `apex_comm_fwd_cap` by forward fraction are refused too. Commander minutes
  spent forward: 10-11 of ~85 per set before, 0 of 76 after.
- **Running away: let them.** He holds position (engine move state 0: he
  shoots what reaches him, never walks after anything; maneuvre chased to
  leash + range, and a move-failed builder used to be switched to roam for
  the rest of the game -- the "into the sunset" walk). The engage rule now
  reads the group's velocity vector and skips anything moving away.

*"The issue I see a lot is our rezbots idling between actions. It takes them
a long time occasionally to decide what they want to do... analyze what
they're doing because it is very wasteful. Also they should always angle
themselves BEHIND our units in combat. Never stand in front of them where
they're likely to become collateral damage."* (seed 20, 2026-09-05)

`apex: rez-time` (maketask.as) now prints per minute what every rez
election came to: which rule handed the job, how many elections came back
empty, how many hit the 2 s gate, how many sites the behind-the-line rule
refused, and the longest stretch a bot went without a job. First 6-game
read (rez-behind set): empty elections 300-1400 per game against 10-150
jobs from any rule, resurrect 0, the worst bot 90-190 s without a job. An
empty election hands the bot to the DLL, which parks it on a patrol -- that
is the standing around. The behind-the-line rule as first built used the
army lane point as "our units" and refused 1600-6700 sites per game, so it
made the idling worse. The instrument then showed the lane point at
0.1-0.3 of the way to the enemy while the refused wrecks lay at
0.6-1.0, so the reference is now where our combat units actually stand
(the forward-most tenth of them, `ArmyFront`), and the medic rule
stations bots behind that unit by their own build reach. rez-front set:
resurrect 0 -> 10-31 per game, medic 0-35 -> 19-88, empty elections
300-1400 -> 0-305, worst no-job stretch 89-215 s -> 35-189 s. What
remains idle is a bot with nothing behind the front and no damaged unit
near it; and 15 rezbots still died at 0.5-1.0 forward in one game,
following the army it now stands behind. OPEN.

*"We also are still extremely slow to rebuild mexes and we once again pretty
much starve to death because of it."* (sixth time, seed 20.) This time the
mechanism was read from the con elections at 16-20 min: 41 of 82 jobs were
`assist` and most of the rest converters, against 10 mexes. The energy bank
was full (pinned), which priced every converter at full capacity -- with
670 e/s of converters ALREADY in flight against a negative surplus. The T2
converter want read 19.9 m/s, the assist want inherited it at a metal cost
of 1, and the cons piled on while 7 dead mexes at v=4-8 were never
re-ordered. Fixed: a pinned bank prices only the capacity not already in
flight (`want_energy.as`); in-flight converters were 0-70 e/s in the next
set against 670. On top of that our own commander's D-gun had killed 9
converters, 5 winds and 4 nanos behind the raiders it shot (seed 20) -- the
ray check stopped at the target; it now checks the rest of the ray for
anything of ours. Own-commander kills of our units are still 8-18 in some
games afterwards, so that is not closed.

*"If an enemy comes at us with a high dps unit that outranges us we need to
make a longer range unit to fight back against it at our T2 lab."* Seed 20:
the enemy fielded Banishers and Golems; the T2 lab's ranking had the
Sharpshooter first at 17.5 min (1010 vs the amphibious tank's 890, the
outrange multiplier is inside its power-per-cost) and second to fourth
before -- and the lab drew amph 9, fido 6, fast 4, sniper 0 in 22 orders.
The production draw is a plain proportional roulette; the con market's
"a commitment is not sampled" sharpening does not apply to it. OPEN, his
call: sharpen the production draw the same way, or leave it proportional.

## OPEN (2026-09-06): the rez bots' reflex

*"Examine how our rezbots behave and look for ways to increase their
efficiency. They need to be productive and have good survival instinct. In
combat they should stand behind allied units away from enemies. They should
back away when enemy units are close to being within range of the rezbots.
They need to be quick to react. Delays of more than a second are
unacceptable."*

Mechanism found first: **a rez bot on a task was never asked anything
again.** Every rule it has runs in `AiMakeTask`, and `AiMakeTask` is only
called for a bot the idle task owns -- so the flee rule could not see an
enemy walking up to a working bot at all, it waited to be shot. On top of
that the election itself was gated to one decision per 2 s, which is his bar
twice over.

Built: a reflex in the DLL (`CBuilderManager::UpdateRezGuard`) on its own
5-frame job, off the election path. It backs a bot away while the nearest
enemy is still `apex_rez_react_s` (1 s) of its own walking short of firing
range -- his latency bar turned into distance -- picks the direction out of
that envelope with the least enemy influence (i.e. behind our own units),
and drops the bot's task, because a builder task re-issues its own path move
every second and would walk it straight back in. The election reads the same
envelope (`EnemyReachSlack`), so reflex and election cannot disagree.

Alongside it, three things that were making them idle: the 2 s election gate
(now 0.5 s, and bypassed entirely while something can shoot the bot); the
front sweep consuming the same scan clock as the resurrect rule whether or
not it found anything (own clock now); and the behind-the-line veto, which
refused a site for being ahead of our units even with no enemy within reach
of it -- it now refuses only what something can actually shoot, which is
what "in front of them IN COMBAT" means. An idle bot with nothing to do now
walks to a station behind our forward-most units instead of standing where
its last job ended.

Measured, 6 games each on Geyser Plains, same seeds, reflex ON vs OFF
(`apex_rez_react_s=-1e5`) on the same binary: **rez bot deaths 8.2 -> 1.4
per game**, metal spent on rez bots 8.3% -> 5.6% of the build for a
similar standing fleet. Against the pre-change set: worst no-job stretch
189 s -> 50 s, mean 20.3 -> 7.2 s, gated elections 817 -> 61 per game.
Head to head 2-2 over the 12 ON games against 0-3 over the 6 OFF ones;
economy differences between arms are inside the run-to-run spread (BARb's
own metal moved 11.7-15.5k across arms).

STILL OPEN, both measured in the same sets:
- the early fleet is still short of the 4-5 he asked for at 12 min (2.7 ON,
  3.7 OFF, 3.0 before -- all noise around 3). That is `RezWorkM` pricing,
  not behaviour.
- empty elections doubled with the envelope on, 63 -> 129 per game: a bot
  refused work near the fighting and with nothing safe behind it still has
  nothing to do. The station walk absorbs some of it, not all.
- the envelope reads only enemies we can SEE, so it is blind exactly when we
  are blind.
