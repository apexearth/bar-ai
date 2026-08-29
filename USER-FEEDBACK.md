# What apexearth wants from this AI

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

## DONE 2026-08-28 (validated on 6 games) — Lab-timing audit on reclaim-corrected income

"Update the audit script so we ensure we make our labs at the appropriate
times. Make sure we aren't tricked by reclaim events which temporarily
boost our income. Work until fixed." Landed: `check_lab_timing` in
audit.py (t2-under-its-own-bar / t2-too-late / gantry-host-too-poor /
gantry-too-late / adv-plant-overlap), all on (dMetalProduced - dMReclaim)
per stats window, every flag printing corrected-vs-raw. Validated: flags
his 17:13 game (gantry 24.2m against team-211-with-fed-host by 14m, plant
overlaps) and passes the fixed build (netinc-s24). AI side hardened too:
dev_team_income publishes cumulative apexReclaimM; TrackIncome nets the
reclaim rate before its EMA, so every income anchor (T2 gate, gantry
budget/host floor, antinuke floor) is structural income; the gantry team
budget reads the new TV_MINC_NET lane. Move to feedback/ archive once he
confirms live.

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

## One player builds no eco — fusion pipeline wedge (FIXED 2026-08-17, verify)

2026-08-17, watching live, second game in a row: "blue is not making any
fusions. I think there is a bug that makes 1 of our guys make no good eco."
Real, reproduced in the same day's 4v4 telemetry (t3: 46-55 m/s income,
asked=1, fusCount=0 for the last 10+ minutes). Mechanism: a reactor ask whose
task died without ever producing a nanoframe never returned its
`gFusionsAsked` count, wedging `ReactorPipelineOpen()` closed for the rest of
the game. Fixed in `events.as` (`apex: reactor ask returned` log line).
**UNRESOLVED until a watched game shows every player reaching fusions.**

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
  `apex_adv_air_income` 150, fighter floor `apex_fighter_per` 40.)
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
