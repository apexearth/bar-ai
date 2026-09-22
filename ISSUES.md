# Open issues — what is wrong with this AI right now

Each entry: what is wrong, the evidence (one run, one number), what was tried.
An entry is DELETED when its fix is measured; the measurement goes in the
commit message. `USER-FEEDBACK.md` is what he asked for, `TODO.md` the named
plays. `git log -p -- ISSUES.md` has every deleted entry with its provenance.

Pruned 2026-09-15 from 3,634 lines. Every 2026-09-08..09-10 economy-session
narrative is gone (stage 1 of price-is-delta-ETA shipped 09-11; what is still
open from those sessions is under ECONOMY LADDER). Every entry about the custom
C++ fight layer (guard posts, leash, intercept dispatcher, arc tiebreak,
SafeStandoff) is gone: that code was reverted to stock BARb on 2026-09-07
(`7a1a9895`, `docs/30-fight-revert-plan.md`).

The fight layer is stock since 09-07; "unverified" below means a fix landed
and no game since has been read for it.

## ARMY

### ARMY SHARE: we put ~10% of metal into army, BARb 23-32%, and that decides the team games (2026-09-06, re-read 09-15)

`tournaments/20260906-123343-fixes-on` vs `-123756-fixes-off`, Comet 1v1 vs
BARb hard, 8+8: both arms 0-8; army 10.0% / 9.7% of spend against BARb's
22.8% / 17.2%, static defence 2.2% against 24%. Nine behaviour fixes changed
nothing because none changed what we buy. Defence is now 16% (docs/32); the
army share is not: `f4017fe5` reads Isthmus 8v8 seed 4 and Frozen Ford 2v2
still BARb-led at army 10% vs 32%. In team games our trade is 0.4-0.6 at
16-20 min in every format (TEAM GAMES below) -- we win only where we
out-produce. The army target (`ArmyTarget`, `RichArmyGapM`, the escort
conscription fixed 09-13) is the term to read; docs/32 says "the target's
question, not the line's".
2026-09-19 night, Comet Catcher 1v1 seed 3 at --speed 20, after the opening
fixes: 7-11 mexes to their 5-6 at minute 4, income 42-54 to 26-31 -- and
250-350 metal of army to their 1,500 at minute 5. The one T1 lab made six
cons in its first five minutes (con floor need=4 at 42 m/s, plus the
UnspentByHands term while the bank sat full) and three combat units; its
lathe is the army's only supplier. Zero nanos stood by minute 8 in one
game and one by minute 7 in the other (frames killed by the minute-5 flash
raid; `apex: nano-hot refused` now stops the re-election churn). Whether
the lab's minutes go to cons or to army at 40 m/s is his call
(USER-FEEDBACK: apex_con_per_m).

### CLOSING: a 25-50% lead at 30 minutes marches in waves of 240 into 17k of static and never ends the game (2026-09-13)

`tournaments/*rd3hold2*/carrotmoun-B-s2`: standing army 16k vs their 7.6k
mobile + 17.5k static, 231k built / 79k lost, timed out. `apex: mass want=240
floor=239 enemyArmy=-2375` -- the wave is sized by MassWant against their
MOBILE army (negative until floored 09-13), so each pool marched at ~240 into
towers. `rd3air/carrotmoun-A-s1`: 751k built vs 291k, killing blow on from
15 min, base standing at 30; `deaths.py`: 498 of ~730 army deaths were
`mov>mov>mov` oscillation between the squad's forward order and the retreat's
homeward one, dying in the open at fwd 0.8-1.3. Same shape 2026-08-29: a 3.5x
mex lead went 2-6 on Comet with the commander dying at home. The ending wave
has to be sized against what STANDS at the target (their static plus arrivals),
the killing-blow's question, not the massing law's. `apex: tgthold hold=31
rel=85` reads a target hold releasing far more than it holds.

### WE ENGAGE AT WORSE ODDS THAN STOCK: thr_mod attack [1,1] / defence [1,1] vs stock hard [0.6,0.8] / [0.3,0.5] (2026-09-20)

His question: are we more cautious than BARb, less likely to take ground.
Audited (commit `TBD`, agent report in its message): the C++ squad core is
stock since 09-07, but `behaviour.json` `quota/thr_mod` is the one knob the
stock engage test multiplies (`MilitaryManager.cpp:716`, `AttackTask.cpp:273`,
`DefendTask.cpp:228`): ours gives attack powerMod 0.8 and defence 1.0 where
stock hard rolls 1.0-1.33 and 2.0-3.3. The comment at `behaviour.json:13` says
the neutral value is offset by `TradeScaledMargin` -- deleted in the revert.
Second: `withdraw.as:142/561` orders a unit off enemy-influenced ground with
no gun on it (62 orders + 304 in-contact holds in one 1v1). Third: the MELEE
hold pool (`hooks.as`, `massing.as:369`) never marches while the base reads
"under attack" (4669 ticks in that game). Not tried: the JSON A/B is one line,
no rebuild -- run it on the battery before any script change.

### ONE FACTORY ORDER COSTS 8-28 ms (2026-09-20)

`apex: facqueue short ... stop=slice us=8086` avg over 327 elections, max
28 ms, in a 2v2: `ConOrderFor` alone exceeds the 4 ms batch slice every
time. The line is fed again after a second now instead of idling to the next
window (empty-line samples 28% -> 2%), but the per-order cost is the thing;
`hk.maketask.factory` avg 3-4 ms, max 28 ms, on a FAIL frame budget.

### check.py reports 'from' as a reserved word at lines that do not contain it (2026-09-20)

`sites.as:682/738` carry no `from`; the variant compiled (review gate 1, the
lathe-site line prints). The identifier was renamed anyway; the check's regex
matches comment text and the line numbers are wrong.

### The attack bar is per-pool, so we rarely attack (2026-09-06)

Stock `CMilitaryManager::UpdateDefenceTasks` (MilitaryManager.cpp:1578) rewrites
every pool's bar to `max(minAttackers, GetPreMaxGroupThreat())` -- the enemy's
second-largest group -- every 5 s. 8v8 census: 42% of pools held 1-2 units,
3% of 507 readings reached the bar, the army attacked 1.6% of its time against
63% defending; losing raises the bar. His ruling 2026-09-06: "we should be able
to coordinate attacks with multiple groups" -- odds judged on what commits
together, pools stay separate. Not built.

### RAIDS: the director produces a real target in 1-3% of asks; we run almost no scouts (2026-09-06)

8 baseline Comet games: 4 real targets in 365 `raid.as` asks; after the prize
fix 6 in 176 (refusal 98.9% -> 96.6%). The binding is only as good as what we
have scouted, and `quota.scout: 2` in `behaviour.json` caps scouting at two
tasks whatever the map -- a flat number. The route ("skirting around the front
lines", docs/24) is `CRaidTask::FindTarget`, stock C++, no binding hands it a
target. `TUNE_SPAM_RAIDERS` on since 09-13: unmeasured.

### The squad arc is capped in ANGLE, so frontage shrinks with range (2026-09-06)

Stock `SquadTask.cpp:431`, `maxDelta = M_PI*0.9/n`: a Pawn row at 162 standoff
gets ~458 elmos of frontage for any n; past ~15 units the row is shoulder to
shoulder under one shell. `apex: squadsize own avg=19.8 max=57`. Converting
to a frontage needs a separation in elmos -- his doctrine number.

### Set-targets do not land (2026-09-06)

1,357,207 `CmdSetTarget` in a 60-minute 16-AI game (31% of order volume);
`apex: tgthold` samp=1800 hold=25 -- 1.2% of own units hold one at any
instant. Free (the gadget intercepts it, 0.03% of a frame), but the doctrine
"move within range and use set target" is not doing what he expects.
`apex_prefer_target` is still 1. ~22% of fight/attack orders never reach
`AllowCommand` (1,034,609 sent vs 804,251 seen).

### Small residues, one line each

- `Military::ForwardFraction` runs from the territory centre to the NEAREST
  enemy (`GetEnemyPos`), so a raider in the base shrinks its span to the
  raider's distance and every point in the base reads +-1 (gate f791769d
  s5: the start at -1.3, a point 400 elmo from it at -0.9). 37 call sites
  read it as "0 home, 1 their base" -- the commander chase's 0.5 bar, the
  defplace fwd, the caution cap. The commander leash left it 2026-09-15; the
  rest still read it.
- Amphibious units "act very cowardly" (2026-08-29 arena): retreat threshold
  ruled out; no amph gate in fight logic; the standoff suspect is stock code
  now. Unattributed.
- The commander's D-gun still kills our own units behind the raider it shoots
  (1-18 own kills per game after the ray-past-target check, 2026-09-05 seed 20:
  9 converters, 5 winds, 4 nanos). Splash, moving targets or the death blast.
- A retreating commander whose haven lies inside enemy influence stands still
  and dies (seed 18, `com-retreat-hold infl 36-78 vs pw 6.5`). The retreat
  destination re-check went back to stock on his ruling (docs/30); not
  re-measured since.
- `behaviour.json` "power" overrides written for THREAT reading leak into
  production worth via `PowerMod` (22 defs; armvader x100, armstil x0.05,
  corbw x0.1). Survey open since 2026-08-29.

## DEFENCE

### DEFENCE SHARE: 2-6% of metal against BARb's 15-18%; the target is 90% unmet from minute 10 (2026-09-20)

His ask: "we're pretty much always making a lot less [defence] than the
barbarian stable AI is... we should be making the long range plasma cannons
as well." Frozen Ford 1v1 +100% (his 20:57 game and `matches/def-ctl-ff-s3`):
static defence 3.8% of spend vs BARb 17.7%; `apex: targets` def=85-765
against a target of 5-30k from minute 10; per 5-min bucket we spent
85/190/0/0/0 on defence from 5 to 30 min while BARb spent 885/1865/2560/1210/
14440. Found and fixed 09-20 (commit message has the numbers):
- `apex: roles` read `defence=0.00+0.90:0/3` for 17 minutes: the gap earned
  the quota and `RoleWorthDoing` (09-16) re-judged it by the draw's ticket.
  A gap-earned quota now stands when the category's best want is a turret;
  teeth and anything else in the category are judged as the draw would (the
  first cut hoisted 153 dragon's-teeth elections at v=0.06 -- the eco-seat
  Bulwark again).
- `PfSurfDps` inverted the engine threat with behaviour.json's threat-map
  mods inside it (Pulsar surf 0.5, Pit Bull 1.5, squared): Pulsar kill 567
  vs Pit Bull 1341 at real dps 1091 vs 422, and `PfKillCapM` in those units
  capped every stake at ~1 metal, so the threat-priced arm of the gain was
  inert. Real dps now; `defwhy` prints `cap=`.
- The LRPC's "worth what it reaches" read `ai.GetEnemyCostAt`, a count of
  enemies visible now: `inReach=0.00` in every reading. Reads remembered
  structure metal now (`apex: lrpc` line).
Open after the fixes: the quota is still 0/4-0/6 on Frozen Ford at 13-25
min. Only T2 hands can propose a turret (his 09-19 no-basic-tower rule), the
first takes no role, and a roled T2 hand's Pulsar order is repeatedly pulled
off by the e-stall hoist (`why=estall role=defence`, 6-15 a game) -- 13
Pulsar executions, 1 placed in `defB/frozenford-B-s2`. The e-stall is the
energy side's problem; the defence hole is its shadow. Also unread as metal:
`ThreatAt` (coverage.as), `foeHere` (protect_fill.as), the shield-far gate,
gift.as and HoldNeedM all read the same visible-unit count as metal; each
has a floor that hides it. Not changed.

### THE 10-20 MINUTE HOLE: T1 hands are routed out, the T2 hand's gun loses to eco (2026-09-18)

His watch of `matches/20260918-055500`: five LLTs and a beamer die at
15-17 min to the first T2 wave and nothing replaces them until minute 20.
Read from the log: the defence target asked for 2,400-4,200 metal of guns
from minute 6 (`defTarget=2413..4204 defHave=740..1185`) and no defence
election won between 5 and 20 min -- never even runner-up. Two prices
under it, both fixed 09-18 (wall slots price the whole shortfall over the
army's fill time; the T1 discount keys on a T2 hand, not the lab), and the
window still reads 0-2 towers in four treated games (seeds 33-36): the
remaining mechanism is `def.route=411/411` -- once the team-wide winner is
a T2 gun, every T1 hand proposes nothing (his 08-27/08-30 ruling), and the
one T2 constructor prices its Pulsar at `v=1.26-3.83` against a mex-up at
5.9-8.9 (`t=2321` of walk, build and displaced eco) until the cover/role
hoists lift it at 15-19 min. His 09-18 ruling: T1 hands fill the shortfall with their best gun
(`def.ownfill`), the pull's slot shape no longer scales the demand, the
T1 discount keys on the asking hand's own options. Defence metal placed in
minutes 10-20: control 92/1092/3440/184, his game 180; treated (seeds
41-44) 190/1692/9500/9160. Two of four still thin -- open until his watch.

### BIG FRAMES STILL LEAVE THE TURRET RING AT THE COMMIT (2026-09-18)

His watch (8-player Glacier Pass, eco seat): every AFUS in one rear column
with 2-14 turrets in reach while base spots had 40-52; "a gantry with all
advanced converters behind it". `audit.py` now says it per game
(`tN-big-builds-at-the-lathe`, `tN-converters-off-the-plant-ring`;
expect.py `big builds stand at the lathe`). Fixed 09-18: reactors sited by
LatheSite (fit-scored), converter yards at the core's rear edge, LatticeFit
and the LatheSite cache ask the DLL's own `CanPlaceCell`, a big frame's cell
is reserved in the blocking map at request time (S36). The audit still reads
RED on the last four seeds (72-75: 12/17, 4/6, 1/2, 2/7 starved). What the
`apex: cell-refused` line shows is left: (1) a second AFUS request asks the
cell where an AFUS frame ALREADY STANDS (asked and refused 0.1 min after the
first was placed there; `Take`'s cover/`JoinBigEnergy` should have folded
it); (2) an old task re-executed at 28-31 min for a cell a fusion took at
18 min (its position is not in any `energy-site` line of the last ten
minutes), so every adopting hand walks it to bare ground. Read those two
before touching the siting again; the siting itself now answers the ring.

### THE FRONT-LINE CONTRACT HAS BEEN FAILING UNREAD (2026-09-18)

`frontline_check.py` and three other `[BARAI_POS]` readers matched
`n=(\d+) (\S*)` after the census started shipping `part=a/b` (31eca356),
so `test_frontline.py` scored zero mexes and zero towers for every team
since then. Readers fixed 09-18; the first honest runs: control (his tree,
`fl-ctl`) guard 2/6, line unscored; treated (`fl-defgap`) guard 1/6, line
2/5 -- both FAIL the 75% contract. Nobody has looked at this instrument's
verdict since it broke; the contract needs re-reading before it is trusted
either way (expect.py's thresholds date from a different placement model).


### THE LINE (team front, docs/32): built through step 5; what is open (2026-09-15)

Status and numbers: `docs/32-defence-plan.md`. Open there: the shield and
support-row nano fire rarely; defence is 16% of spend against BARb's 8% now
that the target is met (the target's question). Residues folded in from older
entries, none re-measured under the team front:

- **Half of defence builds died before framing** (2026-09-07, 12 Comet games:
  33 of 67 and 39 of 73 wins; `armllt done=2 abort=8`, aborts with
  `workers=1 builderToSite=398`). Defence lost on the walk, not in the
  auction -- S14 re-election mid-walk is the suspect; the abort's caller was
  never traced.
- **Reach is paid as area.** `PfStakeIn` buckets our economy at the candidate's
  own range (protect_field.as:337/501), so a 1220-reach gun is credited 6.5x a
  480-reach one; a turret shoots one thing at a time.
- **The post-T2 line stays T1** (2026-09-02): `xT1late` 0.02 x
  `apex_wall_efficient` on the only candidate left; T2 hands price their own
  gun through `xWallEff=0.141`. Both discounts still in `protect_want.as`.
- **`stopped` prices a single tower at ~0 against an army** (his T2 con's
  Cerberus at threat 6180 read `val=0.0000`, 2026-08-30). The front row is now
  soak-valued and a slot's stake is the team metal behind its gap; whether the
  mains row still zeroes on contested ground is unread.
- **Early defence on a quiet map.** `TUNE_RISK_FLOOR` is 0 since 09-11 (the
  blind prior is the siege prior alone). Setting it to 0 measured Greenest
  +44% and Isthmus -27% (3 seeds, minute-30 metal) because the first Isthmus
  raid lands at minute 5 with nothing standing; not re-measured under the
  wave prior on walkable bearings.

### LEGION CONFIG: every Legion tower carries zero threat (2026-09-12)

`config/standard/behaviour_leg.json` (stock stub): `threat: {air:0, surf:0,
water:0, default:0}` on 40 defs -- `legmg`, `legrl`, `legbastion`, `leglrpc`,
every T2 Legion defence. The DLL applies it as `ModSurfThreat(0)`: an enemy
Legion tower is walked into as harmless and our own reads as no cover. The
navy stub was removed 09-12; the towers were not. `legnavyfrigate` /
`legnavysub` still read water-only (`badtargetcategory NOTSUB` stripped by
`CircuitDef.cpp`), so the shipyard never orders the frigate.

## EXPANSION AND THE OPENING

### 2v2 GLACIER PASS +100% (his regime): 1-19 at HEAD, 8-15 after the opening and commander fixes; the game is now lost at 16-24 min (2026-09-21, night)

His ask: beat BARb stable hard reliably in his 2v2 (Armada both, +100%
both, 0.2 lr boxes). Control `tournaments/20260921-202615-ctl2v2-gp` 0-8
and `20260921-200959-*` 1-11 (0.38 boxes). Three agents read the losses
independently; the census and their corrections:

- Fixed in 64fcb121 (measured per arm in its message): one commander had no
  plant for 2-7 min in 7 of 11 losses; the commander walked out and died in
  3 of the 4 shortest losses (engagements at 2-33x his strength, a leash
  along a base axis that ran perpendicular to the enemy, a retreat hold on
  the influence field); the ladder's spot claim lost the draw nine times in
  ten. After: second plant 0.0 min, first commander death median ~10 -> ~29
  min, income and army lead at 16 min (126 vs 93, 10.9k vs 8.8k over 16
  games, `20260921-212544-t4b-ladder-claim-16`).
- OPEN, the 16-24 window: their income doubles (93 -> 236 at 24) on 4.0
  advanced converters and 2.4 fusions per side to our 0.3 / 0.3 while our
  energy bank is full and 300-959 e/s spill (`convwhy wasted=959`,
  `convprice armmmkr v=4.86 gain=9.55` losing to metal v=14 and the
  metalfirst assist v=1000). The ETA ladder carries energy at the
  conversion anchor and has no conversion rung, so it buys fusions and
  never the converter. A conversion rung (spill less in-flight capacity)
  is written and deployed to the winrate lane, unmeasured.
- OPEN, the spot gap is FORWARD spots only: home band 5.2 vs 5.0, forward
  1.3 vs 6.0 at 12 min. It forms in the 10-12 window: they finish 23 mexes
  to our 8 while we finish 13 mohos to their 4 (we tech first: T2DONE 8.2
  vs 11.5 min). "Our mexes die 4x" was wrong -- `atk=?` deaths at home are
  moho upgrades; raider kills are ~2x ours early, parity after 12 min.
- OPEN, where the army stands: ours at front 0.18 (60% of units under
  0.2), theirs 0.23 -> 0.38 with a quarter past the midpoint. The regroup
  anchor is pulled back behind our forward-most tower
  (`TUNE_LANE_BEHIND_GUNS`) and our towers stand on the base rim, so the
  forward band -- where all the spot gap is and 45% of our losses fall --
  is theirs uncontested. Patch (the pull-back skipped when the lane is our
  own perimeter) in the session scratchpad, unmeasured.
- OPEN, the fights: trades are even through 18 min and 2.3:1 after. Our
  damage efficiency is >= 1.0 ([BARAI_DMG]) yet the same T1 types trade
  ~3x worse in our hands (pw 0.54 vs 1.47, ham 0.48 vs 2.01, fido 0.72 vs
  2.84); our Hounds die from >450 elmo to Bulldogs, Mannis, Snipers and
  Fatboys at 660-760. Damage does not convert to kills (they absorb 10-12
  damage per metal lost, we 7.6-8.7). The track record reads Hound 1.19-1.46
  by damage dealt, blind to damage repaired away.
- WHERE THE DEFENCE SHARE ACTUALLY GOES, measured per 6-minute bucket per
  side (t12, 16 games): light towers, us 4.31 / 0.38 / 0.06 / 0.06 against
  BARb's 8.88 / 4.81 / 1.69 / 3.00. Ours stop dead the moment an advanced
  hand exists -- that is `T1Tower(d) && CeilingConsOwned() > 0` in
  protect_want.as:492, HIS 2026-09-19 rule ("no basic tower at all once an
  advanced hand exists"). BARb keeps building 85-metal LLTs all game and
  its mexes are 78% covered to our 45%. We answer with Beamers (2.9 in
  minutes 6-12) and then nothing until Ambushers at 12-18. THIS is the
  defence-share gap, it is a rule and not a defect, and it is his to
  revisit -- the price fix above proves the auction is not what stops us.
  ...AND THE RULE IS EXONERATED: put behind `apex_t1_tower_late` (default
  1 = his behaviour) and measured with it off, light towers moved only
  4.31/0.38/0.06/0.06 -> 4.56/0.56/0.19/0.25 per 6-min bucket against
  BARb's 9.31/3.75/2.00/3.62, mexes lost before 24 min were unchanged
  (19.9 vs their 19.4) and the arm read 2-14. Neither the price nor the
  rule holds the towers down. What is left is the SITES and the HANDS:
  `slot.nopull` refuses 44-66% of wall slots and `site.interior` 33-49%,
  and the two uncounted `continue`s at protect_want.as:475-495 hide 320
  of 418 candidates a game. That is the next thing to instrument.
  INSTRUMENTED (c0497d3e + the two new gates, `def.obsolete` and
  `def.t1late`, six-game probe `t22-defgates-probe`, cumulative over both
  our players): the defence funnel is
    cand.class   7526/11278 (67%)   -- the def is not this line class
    cand.avail   1510/12788 (12%)
    cand.half     2599/3752 (69%)
    def.obsolete  1693/3517 (48%)   -- dominated on reach AND kill by
                                       something affordable now
    def.nosite    2091/5608 (37%)
    def.t1late     355/1824 (19%)   -- his rule, the smallest of them
    slot.nopull  45397/120004 (37%) -- wall slots with no pull
    fill.framecap 3482/4825 (72%)   -- the per-frame work cap
    def.targetfill/teampower/zerogain  0 refused
  So nothing downstream of the price refuses anything (targetfill,
  teampower and zerogain are all 0/1469-3630), and the biggest single
  defence-side refusal is `def.obsolete` at 48%: a tower is dropped when
  something we can afford RIGHT NOW dominates it on reach and kill --
  which on this map is the Beamer and then the Ambusher, i.e. the rule
  that makes us buy few expensive guns instead of many cheap ones. That,
  plus `fill.framecap` at 72%, is where the next work goes.
  TESTED: comparing the two towers PER METAL instead of absolutely (a
  Beamer outkills an LLT and costs 2.2x; two LLTs guard two mexes) does
  what it says -- light towers per game 4.8 -> 9.6, beamers 5.2, the
  whole tower count roughly doubled -- and it does NOT close the gap:
  BARb still fields 20.3 LLTs to our 9.6 and 40 towers to our 18, mex
  coverage 31% to our 18%, arm 2-14. Reverted. The refusals are real but
  the binding constraint is further up: we do not have the HANDS or the
  METAL at the time the towers are wanted (def spend 629/644/1312 per
  4-min bucket from 8 to 16 min against their 815/1601/4141), which is
  the same opening deficit every other arm of the night ran into.
- DEFENCE IS PRICED THE OPPOSITE WAY TO ARMY, and fixing that does not
  help here. The army want multiplies a unit's price by `1 + deficit *
  (assets+army)/target * apex_stake_weight` capped at 8 (production.as
  stakeMul), so being below target makes army dearer; defence had only
  `TargetFill`, bounded at 1, so 96% unmet priced within 5% of met. Given
  the army's own formula (same tunable, same cap) the multiplier fires
  hard -- `defwhy ... xFill=5.10`, gain 18.2 where it was 1-4 -- and the
  realised defence row does NOT move: 0.11 of a 0.29 target against the
  control's 0.13 of 0.27, and the arm reads 1-15. So the defence row is
  not held down by its price: the towers win their own auction and the
  metal still goes elsewhere, which points at the executor and the hands
  (`defsite`/`site.*` gates, DefObsoleteOnArrival and the T1-tower refusal
  at protect_want.as:475-495 are uncounted `continue`s), not at pricing.
  Reverted.
- THE MINUTE 2-4 STALL IS THE COMMANDER'S LEASH, and it is mine: after
  the radial half-leash (e72b8775) `apex: mexdiag` reads comFar=63 refused
  spot claims per sample in minutes 2-4, more than every other mex
  refusal combined (priced 7.1, noOpen 2.9, claimed 2.2, deathWalk 1.5),
  and our claims in that window are 0.29 a player against BARb's 2.8.
  He is the biggest lathe we own there. Widening the WORK radius back to
  the full leash (the chase keeps its own 0.5-leash bound in safety.as)
  ran 3 of 16 games before the batch was stopped for system memory:
  mexes at 8 min 6.1 -> 7.7 and at 12 min 6.1 -> 9.3, army at 4 min 1974
  against their 1817 (ahead for the first time all night), and 0-3 with
  9.3k of losses in the 8-12 bucket. RE-RUN over 16 games (t27b, four
  workers): 2-14, mexes at 8 min 5.4 and at 12 min 5.7 -- no better than
  the tree with the tight leash -- and comFar still refuses 47.2 claims a
  sample, because most of them are the RIM test, not the radius. The
  three-game signal was noise. The leash is not the stall either; what
  refuses the claims is `PfCoreRimDist > 400` plus the forward-fraction
  test on ground the hull has not reached, i.e. the commander may not
  claim anything past his own buildings. Reverted.
- NOR IN THE ELECTION MIX. The `metalfirst` assist hoist takes 29% of
  constructor elections and sits above the draw, so it also outranks the
  ladder's spot claim; letting the claim win when the ladder's own first
  move is a claim moved the opening a little (mexes at 4 min 3.9 -> 4.2,
  at 12 min 6.1 with their lead down from 11.9 to 11.0) and the game not
  at all (2-14). Reverted. Three separate ways of spending the opening on
  spots -- the ladder claim (kept, it was the 4-4 arm), mex-before-plant,
  and claim-over-assist -- all land in the same place: we can move WHICH
  of our 4,300 metal by minute 4 goes where, and BARb still arrives with
  5.4 mexes and 2,450 of army to our 4.2 and 1,220 because it finishes
  3,639 metal in that window against our 4,286 AND has more of it on the
  map. The remaining difference is not allocation, it is that a third of
  our opening metal is still in flight when theirs is standing.
- THE OPENING IS NOT LOST IN THE ENERGY MIX EITHER, though the mix is
  lopsided: by 4 min we finish 1,683 metal of generators (6.7 solars, 9.1
  winds) to BARb's 782 (15.6 winds, 0.9 solars) -- on Glacier Pass wind is
  40 metal for 11 E/s and solar 155 for 20, so wind pays 2.1x per metal.
  Most of ours come from his rule `apex_stall_solar_e` (300): while hard
  e-stalled under 300 E/s the want is restricted to zero-energy-cost
  generators, and at +100% we do not pass 300 E/s until minute 6-8, so
  162 of 168 stall generators were solars. Swept to 0 (16 games): solars
  by 4 min 8.0 -> 6.7, generator metal 2,964 -> 1,683, and the game did
  not move (3-13, income at 4 min 23 vs their 32). The rule costs ~900
  metal of opening and buying it back is not what we are missing.
- THE BASELINE, measured at the same setting as everything else and not
  before (2026-09-22, `c3-pre-session-s5-16`): 287a6e73, the tree that was
  on his slot when the night began, reads 1-15 at pinned --speed 5 with
  six workers. The night's committed tree (e72b8775) reads 6-10 there.
  That is the only honest comparison of the two, and it is the one that
  says the session bought something: 4-min army 472 -> 1250, 8-min mexes
  6.2 -> 6.6 against their 9-10, 12-min income 62 -> 75.
- THE SIM SPEED IS PART OF THE RESULT. One worker runs ~15x, eight ~5.6x,
  pinned `--speed 5` with six ~4.4x. BARb's opening is far stronger at
  honest speed (2.1k army and 9.4 mexes at 8 min vs 5.2k/6.9 at 15x); his
  games run at 1x. The same tree read 9-7 at 15x and 4-12 at 4.4x. Every
  number below is at pinned speed 5 unless said otherwise.
- Standing after the night (e72b8775, on his slot): at 4.4x rung+anchor
  6-10 vs rung-only 4-12 vs 64fcb121 (no rung) 3-13 at 15x; at 15x
  rung 9-7 vs 3-13. Not the >50% he asked for at honest speed.
- Measured inert and reverted: the plant-assist want carrying the unmet
  army share (`drain * TargetFill(ArmyValue, ArmyTargetFull)`): 3-13,
  hands on the plant 0.00 -> 0.03 of samples (BARb 0.28-0.31). The
  assist is a transient order the next election replaces, and the estall
  hoist pulls the commander to solars in minutes 1-3 (two labs plus his
  lathe outrun the early energy). What would move it: the assist held as
  a job across elections while the army is short, and energy that keeps
  pace with the plant instead of stalling behind it.
- Also inert (2-14, hands on the plant 0.05): the same term with the guard
  held for gap/drain seconds instead of ten. The gate is upstream:
  `isAssistRequired` (economy.as, BARb's rule: metal > 20% storage AND not
  energy-stalling) is false through most of our opening at honest speed
  because the energy stalls from minute 1 -- 4 facguard bids in three
  minutes. BARb's cons put up ~9 winds per player by 8 min (ours 2.8 winds
  + 4.2 solars) while its commander lathes the factory. The opening lever
  is energy that keeps pace with two labs, then the assist gate opens by
  itself.
- Third try, also inert (4-12, hands on the plant 0.05): the guard's own
  `CountQueued <= 0` gate refused a working lab (the read lags sends and
  the line orders one unit at a time; fixed to read the line's pending
  ledger), and with gain + held stint restored the commander's guard still
  never bid in minutes 1-3 -- `isAssistRequired` is false while the energy
  stalls, and that gate is right (build power on an E-starved lab makes
  nothing). What decides the 4-min army (2.1k vs 1.2k) is the lab's
  effective build rate: 28% of BARb's con-time is on its factory, 5% of
  ours, and our con floor spends the lab's first 600 metal on three cons
  that then go to nanos, mexes and towers. The lever is the opening energy
  (the stall hoist fires at 1.0, 1.2, 2.1 min every game) and cons that
  lathe the lab before they leave it -- BARb's opener interleaves builder,
  raider, builder, raider.
- The 4-minute army, measured to the unit (a2db9356): cons per lab are
  equal (2.9 vs 3.0 per factory-sample), nanos per plant are equal once
  the caretaker gate is stock's, energy income is equal; the labs' output
  is ~5.4 m/s of units to their ~6.8, and a quarter of ours is rez bots
  (1.3-2 per player by minute 4, before any wreck) plus fleas. Their bot
  lab's queue is 64% combat; ours 45%. The early rez bots are the medic
  share of the squad doctrine bought ahead of any army; that and the lab
  rate (energy pacing) are the two remaining levers, both his.
- The medic share without the round-up (the next rez bot only when 12% of
  the army covers it) was inert too (3-13, 4-min army 1107). What is left
  is one number: at 4 min their labs have each produced 14.7 units to our
  9.4, with equal cons, equal nanos on average and equal energy income; a
  100-BP lab cannot make 14.7 units in 240 s after three constructors, so
  theirs runs at 2-3x nameplate in minutes 0-4 and ours at nameplate. The
  next step is an instrument, not a change: per-lab units and buildtime
  per minute, both sides, from [BARAI_DUTY]/[BARAI_ARMY], to say whether
  it is nano timing, con time on the factory or the resource throttle.
- The instrument is `tools/labrate.py` (buildtime produced per
  factory-sample, both sides, per 2 min). It says the opening gap is the
  LINE'S RATE, not what the line chooses: 0-2 min BARb 46.5 to our 14.1,
  4 min 71 to 41, 8 min 75 to 58. But the same read on the arm that won
  its regime (t5-conv-rung, 9-7 at one worker) is 20.0 to 2.4 at 2 min and
  17.5 to 15.8 at 4 -- a WIDER early gap on the winning arm, so the
  2-minute rate does not decide the game either.
- Putting the commander's 300 BP on the plant while the army is short:
  0-16, the worst arm of the night. The rate moved as intended (14.1 ->
  16.5 at 2 min, 40.7 -> 43.8 at 4) and everything else collapsed with it
  (mexes 5.8 vs 12.0 at 16 min, income 113 vs 174): the commander's
  lathe-seconds in minutes 1-4 are worth more as mexes and energy than as
  units, which is the market's own answer and it was right.
- So the ranking of causes for the loss at 4.4x, on fourteen 16-game arms:
  nothing in the opening PRODUCTION is the lever -- cons, nanos, medics,
  the plant guard, the con floor's spare reading and the lab's rate were
  each moved and each lost ground or nothing. The two things that did move
  the win count are the CONVERSION rung (+6 games at one worker) and the
  commander's survival (median first death 10 -> 29 min). What is still
  untried: the army's own quality after 16 min (same T1 types trade ~3x
  worse in our hands; the record credits damage dealt, theirs is repaired
  away) and the forward spots (we hold 5.8 to their 12.0 at 16 min while
  losing 2x the metal to raids).
- WHAT THE 12-24 MINUTE METAL BUYS, per side (t12, 16 games): we spend
  12.2k on army+defence structures to their 21.9k, and 35% of ours is
  Ambushers to their 14%; they put 20% into a Shipyard-class gantry
  (armshltx) and 22% into Annihilators. Our mobile losses in the same
  window are 531k: Hounds 17%, Hammers 11%, Pawns 10% -- 21% of the Hound
  losses to Fatboys (1400 metal, outranges a 285-metal Hound) and 19% to
  Snipers. We are answering their T2 heavies with T1 and light T2 while
  they build the heavies; the record's class bar cannot see it because it
  ranks a Hound against other Hounds.
- THE RECORD CANNOT BITE, and two arms proved it. (a) Settling the matrix
  METAL FOR METAL ON DEATHS instead of on damage -- his 09-16 ruling taken
  literally, and the defect it answers is real (the record read Hound
  1.19-1.46 while the tournament exchange was 0.72, because damage a
  repair pad undoes was still credited): 5-11, every type's multiplier
  still inside 0.85-1.27, trade 1.72:1 against us. (b) The reason: the
  prior is `apex_record_prior` (10) times the unit's COST IN METAL on both
  sides of the ratio -- 2,850 metal for a Hound -- which swamps a game's
  real exchange, so every multiplier sits at ~1.00 all game. Dropping it
  to 2 spread them only to 0.82-0.94 and read 2-14, trade 1.94:1. Both
  reverted. If the record is meant to steer composition it needs a prior
  in the units of the evidence (a few fights), not ten unit-costs.
- So the 12-24 minute trade is NOT fixable through the unit-worth model as
  it stands. What is left untried: the plants themselves (we build 1.94
  T2 bot labs and 0.25 vehicle plants per game, they 1.19 and 1.12, and
  their Fatboys/Bulldogs are what kill our Hounds), and static defence
  (they spend 21.9k to our 12.2k on army+defence structures 12-24 min,
  22% of theirs on Annihilators).
- THE PLANT PRICE IS ONE-SIDED, and the fix is a tunable that already
  exists. `TUNE_LINE_TERRAIN` is 1 and `TUNE_LINE_QUALITY` is 0
  (tunables.as:1858, :1884), so a plant's price carries the map-coverage
  penalty against vehicles (armavp reads 57.6% of the map to armalab's
  83.5, `apex: line-terrain`) with nothing speaking for what the line
  FIELDS -- while the disabled census says the vehicle line is the better
  one here (`line-quality armavp=0.69(q1.00 t0.58) armalab=0.40(q0.40
  t0.84)`). Coverage is `percentOfMap` of the largest connected component
  for the move class (InitScript.cpp:629-644), every cell counted the
  same, corners included.
  Turning it on (the documented 09-12 control arm) IS wired -- plantcand
  reads `line0.90` for armvp against armlab's 1.00 -- and moves the
  opening: T1 vehicle plants 0.25 -> 0.81 per game, and the 12-24 minute
  mobile trade from 1.72-1.94:1 against us to 1.37:1, the best of the
  night. The win count did not follow (2-13): the vehicle line arrives
  but the T2 vehicle plant still does not (armavp 0.12 vs their 1.19),
  because our T2 bot con cannot build it -- `unitdef.py armavp` lists
  armacv/armbeaver/armch/armcv/armhacv/armsacv, not armck, so the T2
  vehicle plant is reachable only through a T1 vehicle plant we rarely
  keep. That is the next defect, and it is upstream of every unit-mix
  question.
- HANDS ARE NOT FUNGIBLE, and the con floor (ConsNeedAny) treats them as
  one pool, so a vehicle plant never makes a vehicle hand once bot hands
  stand. Built as a capability floor -- a hand that is the only way to
  reach a plant no owned hand can build is worth one of itself, the shape
  of the existing air-con floor (production.as, `opens a plant no hand of
  ours can build`, fired 74 times in 16 games). It WORKS mechanically:
  advanced vehicle plants 0.12 -> 0.44 a game and T1 vehicle plants 0.81
  -> 1.44. The win count did not follow (3-13) and the 12-24 trade went
  BACK to 1.91:1 from the 1.37:1 that line-quality alone bought -- the
  second plant and its hands are paid for out of the same opening, and on
  this map that opening is already the thing we are losing. Kept in the
  tree only if a later arm shows it pays; reverted for now.
- Towers: LLTs 10.1 vs 2.6 per side at 16 min; their mexes 78% covered by a
  tower within 350, ours 45%. Tower orders do land near spots (58/130
  beamer orders within 350 of a spot) but the standing set at 12 min is 11%
  near a mex vs their 24%.

### THE T2 TRANSITION IN 2v2: ahead at 8 min, tripled at 12 (2026-09-19, evening)

Red Comet seed 5 after the day's fixes: at 8 min army 6.2k to their 4.8k,
income 73 to 81; at 12 min 4.9k to 13.2k and 72 to 185. Their T2 units
(snipers, Bulls) and mohos arrive at 10-12; our T1 lab keeps 68 of 92
units decided 9-16 min (6.8k of 18.5k metal) and its pawns die at home
4:1, the army gap grows, the market answers the gap with more T1, and
eco spend halves (2,912 -> 1,859 per 4 min) while theirs rises (3,425 ->
4,150). His doctrine: defending at home takes near parity, "we need
time to build the army to match rather than continuously letting units
die". docs/33 8 (cohesion 0.11 vs 0.44) is the same finding from the
other side. Not a wrong number; the next campaign. Tried the same
evening: an attack group containing a static gun always faces the power
test (no influence exemption) in CAttackTask::FindTarget -- metal lost to
towers on the same seed 1,230 -> 1,160, the deaths moved to home against
Bulls at 10-12 min; reverted. The turn is their T2 vehicles at 10 min
against our T1 line, not the wall.

### OPENING MEXES in 2v2: 10 to their 15 at minute 4, then no growth to minute 8 (2026-09-19, night)

Red Comet 2v2 seed 5, +100 vs BARb hard, one game per change at --speed 20
(uncapped, two games in a row crippled BOTH AIs to 1 mex at 4 min -- run
capped). Before: 7-8 mexes to their 13-15 at minute 4 in every 2v2 today;
the commander's claim was refused by ComFar 4-11 times before minute 5 (the
core rim is three buildings at minute one) and each refusal's eco fallback
bought a solar or converter; a scout car in the base set the risk axis so
every home spot read risk 0.78; the nano floor took two cons at 13 m/s.
After the six fixes in the 2026-09-19 night commit: 10 to 15 at minute 4.
Still open: from minute 4 the sweep reads 9-16 of 40 spots hot (their army
sits on the middle) and cand=0-1, so we stay at 10 while they reach 22 by
minute 8; and the cons build 4-5 basic converters by minute 4 (E surplus off
five solars) where BARb's commander alone claims six mexes. Instrument:
`apex: mexprice` (sampled 10 s, every factor of the top rung) and
`mexdiag ... comFar= ... sweep Nhot`.

### OPENING in 2v2: their army is 1.4x ours by minute 4-6 and the middle is theirs (2026-09-19)

2026-09-19 night, Red Comet 2v2 seed 5 after the opening fixes: armies at
parity by minute 5-6 (2,319 to 2,565; 2,671 to 3,259) and mexes 11 to 13
at minute 4 -- and our army front stays 0.20-0.32 while theirs holds 0.50
over its cons, so the middle is theirs by minute 8 (7 mexes to 26). Read:
`mass want=48-64` against `own=12-19` at 5-6 min (the floor's meet term
is the enemy's group power over AllyCount, above one player's whole army,
so no pool promotes until minute 7); capping the want at the player's own
power (tried, one game) promoted the pools but the front did not move --
`hold ... attack=` counts BaseUnderAttack true almost continuously with a
scout in the base, and recall-home reads the same. The 2v2 posture --
two allied pools that never combine, a hold that a 23-metal flea can arm
-- is the next campaign; docs/33 section 8.

story.py on 2v2 x8 per arm (Comet Catcher Remake + Glacier Pass, +100 vs
BARb hard): our combat metal over theirs at 4 min reads 0.69-0.96 by arm,
and by minute 6 their army stands at front 0.50 while ours stays at
0.22-0.27; they hold the mid mexes from minute 6 and the income lead flips
by minute 8-10. Equal lab busy (92%) and lab power; our two labs' first
four minutes are ~22% non-combat (cons, rez, scouts) and the rest pawns,
theirs 21 combat units from one lab with the cons assisting it. Our
commander's first five minutes: energy x127, mex x39, converters x37,
towers x23 over eight games. The army target reads 2,090 against 110
standing at 2.4 min -- the gap is known; the lab is its only supplier.
Tried and measured the same day: holding the mid mexes at parity (inert,
never at parity); screen axis off (no change); rez bots priced on the
core ratio (early rez 23 -> 4, ratio @4 0.69 -> 0.96, kept); the
commander assisting the lab on the army gap (assists 1 -> 29, ratio @4
0.96 -> 0.73, 0-6-2, reverted -- the commander's mexes and solars are
what feeds the lab). Open: what the lab should make in the first four
minutes (a con floor of 2.7 fires at t=0) and whether the T1 con walks
to a solar or stands at the lab; test_earlyfight.py is the harness.

### T2 IN 8v8 COMES AT 9-17 MIN: the ETA ladder keeps choosing mexes the cons die reaching (2026-09-19)

Isthmus 8v8 replays (seed 5, +100): our T2 starts 8.9-16.5 min against
BARb's 4.4-11.7; `apex: eta` for a late player reads the mex rung ahead of
the T2 lab every sample from minute 5 to 14 (mex 459-711 s, tech 684-938)
while the market's cons walk 5,000 elmo to those spots and die (his game:
25 T1 cons of one player). The mex rung's survival is TechSurvival(home),
so a far spot prices as safe as the base. Tried: a spot-hazard survival
for the mex rungs (HazardAt(spot) with the unscouted prior) -- inert, the
ladder still read mex 711 against tech 938 at 8 min, because the risk
field knows nothing about ground no unit of ours has seen. Reverted. The
death count at those spots is the evidence the field lacks (deaths.py /
story.py have it); the ladder does not read it.

### OPENING: the first factory comes late in half the games (2026-09-11, 09-15)

Comet 1v1 vs BARb hard, six games per build (`tournaments/20260915-081342-
ctl7f26-Comet`, `*trt-d9b6-Comet`): three of six have the first constructor at
5-13 min and 4-14k built at 25 against 25-50k -- same rate before and after
the team front. Worst case: the commander's lab task aborted by the stuck
watch three times (`held corlab progress=0.00 toSite=700 ... no engine
order`, `latency corlab dropped=10`), then mex-claiming across the map with
no factory until minute 12; in others `firstplant=3.2m` is simply late.
Greenest 2v2 batteries (09-11): 5 of 20 player-games with the first factory
after minute 19, the same `armcom held armlab progress=0.00 ... no engine
order, re-electing` loop 50 times. A known corner on Comet (start 1460,2976;
site x 2450-3000, z 1750-2350) has the commander in range of his own site
and not building for minutes (seeds 2 and 6 of `fl-*`). The stuck watch was
rewritten 09-15 (`ccf28df7`: reach + approach, not nearness + wiggle; Ford
2v2: no unreached-site stall over 75 s) -- the Comet rate is not re-measured
on it. Read the engine-order drop first (S13, S27: the engine discards a
build order on a blocked square with no idle event) before the election.

### 1v1 vs BARb HARD: 3-15 and 1-18, outbuilt 2-3x by minute 15 (2026-09-18)

Tournaments, four maps x 6, +100 both, 30 min: HEAD 3-15 (6 timeouts), his
slot 1-18. Every decided game ends on a commander kill at 12-23 min with
our metal built at a third to a half of theirs (Comet 32k vs 112k, Glacier
11k vs 41k). Constructors held at peak 9 vs 33 (T1) and 6 vs 16 (T2), mex
upgrades 8 vs 15, army (real) 10.6% of spend vs 30.3%, static defence 7.6%
vs 15.6%. Read from the Glacier 1v1s:
- A walking constructor was re-elected every 3 s with a fresh draw; the
  DLL hides its assignment so the script's hold never saw it (S14). Fixed
  09-18: the incumbent job is kept while en route unless an emergency
  hoist fires or a drawn challenger beats its value (`apex: keep-job`,
  70-104 keeps per 20-minute game). `why=nanofloor` alone had pulled cons
  off their walks 61 times a game.
- The constructor is never bought by the auction: v=0.12-1.3 (x1000)
  against a Pawn at 9,000-1,000,000 -- the army side's ppc carries
  quality x line-bite x speed x coverage multipliers (p=15 for a pawn)
  that no economic gain has. Only the con FLOOR (apex_con_base +
  income/44) produces builders: 5-7 T1 cons a game to BARb's 16-22. The
  feed-room gate zeroed even the floor's excess (room=0 all game once a
  few turrets stood; fixed: a con's claim value is not gated on room, and
  overflow floors the room whatever the target). What a constructor is
  worth against a pawn in one currency is his call: the plan says seconds
  off the target, and a claimed mex streams for the game while a pawn
  closes 55 metal of a gap once.
  09-19: the multipliers are measured (`prodrank ... p,pc`): a pawn's
  core is pc=0.8 of the line's best and its final p=46; the whole excess
  is the SCREEN axis (sight x dash / cost against the tree-wide mean
  cost, so a 35-metal unit reads 40x). Normalised to the line's best it
  read p=3 -- and lost 1-7 where the same tree without it won 6-2 (every
  1v1 ends on a commander kill; ours at 9.4-9.6 min in two). Reverted;
  docs/27 TUNE_SCREEN_WORTH. The pawn flood is what wins the opening, so
  the con currency cannot be fixed by deflating the army side alone.
- Mex tasks die at arrival: `unreach armmex gap=16 range=154 threat=1.7/
  0.0` -- the DLL's CanReachAtSafe refuses a fixed site the script's
  MexHeat accepted, on a threat reading barely above the 1.0 floor; 3-15
  per game on Comet, `nopath` 100+ on Carrot (cliffs).

### 1v1 ON SMALL MAPS: 4-43 across three handicaps, lost in the first eight minutes (2026-09-21)

Eight small maps (Altair, Avalanche, Geyser Plains, Hotstepper, Wanderlust,
Red Comet, Copper Hill, TitanDuel) x 2 sides, BARb hard, 40 min, `--speed 8`:
+0 0-16, +50 3-12 (1 draw), +100 1-15 (`tournaments/20260921-17*-wr-h*`).
Hotstepper is lava and not data (both commanders die to the map). At minute
4 we hold 4.4 mexes to 6.2 and 5.6 armed units to 12.6; at minute 8, 4.8 to
10.3 and 12.7 to 28.1 (+0 means; +50/+100 the same shape with the mexes level
at 4 and half theirs at 8). Read per mechanism (`tools/opening_ab.py <tournament> 4,8`, `tools/fallthrough.py`,
`tools/comm_engage.py` are the census scripts):
- LAB THROUGHPUT, not the lab's timing. BARb has MORE constructors than us
  at minute 4 (4.2 to 2.2 at +0, 7.6 to 5.3 at +100) and twice the army:
  its commander guards the lab between builds (stock
  CheckMobileAssistRequired), so the lab runs at 300-450 BP to our 150.
  Our factory-guard floor (`ProposeFactoryGuard`, his "OK" of 09-11) priced
  at v~1 against mexes at 10-30 and fired 5 times in 16 games before minute
  5. Repriced 09-21 at the overflow rate while the bank is pinned (the nano
  want's own law): +50 armed at 8 min 24.5 -> 31.8 (theirs 32.2), win rate
  unchanged (1-15). `apex: facguard` is the instrument; bids are rare
  because `isAssistRequired` needs bank > 20% and no e-stall.
- THE CON FLOOR TAKES THE LAB'S FIRST TWO MINUTES: 3.6 constructors per game
  from the first lab before minute 5 (60% of its lathe) while the commander
  never assists it. `need=2..3` from `apex_con_base + inc/25 + HandsShort`,
  and HandsShort keeps asking because the bank is full -- but the bank is
  full because the lab is the bottleneck, not the hands (+100: bank 87-100%
  from minute 2 to 8). A con from the lab is the slowest lathe there is
  (34 s of lab time for 80 BP); a nano is 200 BP for none. The con-vs-army
  currency is his call (see 1v1 vs BARb HARD above), unchanged.
- THE COMMANDER WALKS INTO T1 GROUPS OF 2-35x HIS STRENGTH: 6 of 43 losses
  end on `commander engaging -- T1 x9..13 ... str 0.09-0.24 vs his 0.01-0.02`
  (Geyser +0 4.5x, Altair +50 2.0x at 5.5 min, Wanderlust +50 24x and 35x).
  His 09-20 ruling made T1 at the base his to kill with no strength gate;
  the stake in those cases was 155-842 metal, not the base. Ruled 09-21:
  the LAST commander on the side is careful, a commander with allied
  commanders standing may be spent. Built (safety.as `LastCommander`,
  allies publish `comalive`; an ally that never publishes counts as
  holding one): the last commander keeps the T2 bar's strength and health
  halves against T1. 8 games +50: every engagement tagged `last`, no
  fatal engagement above parity, 0-7 -- the base is overrun at 15-27 min
  either way. `tools/comm_engage.py` is the instrument.
- THE RISK MODEL CEDES THE MIDDLE: Avalanche +50, 19 spots, we hold 4-7 all
  game to their 11-16; `mexdiag` reads 11 of 19 risky by minute 5, then
  `deathWalk=140` refusals at minute 10, while their army stands on the
  spots (front 0.3-0.47 to our 0.22). Expansion is army-gated and the army
  is at home.
- FIXED 09-21, measured inert on the outcome: the mex-guard gun the executor
  refuses as interior was proposed and cover-pushed every election, and the
  fallthrough bought converters and wind (19 refusals and 15 fallthroughs
  per game before minute 10 -> 1.6 and 8.4; converters before 10 min 6.0 ->
  3.9; +0 mexes at 8 min 4.8 -> 6.1, 0-16 -> 0-16). A crewless first-plant
  frame counted as in flight and deferred the only ask that re-adopts it
  (TitanDuel +50: 96% built at 2.0 min, rotted to 3.6, no lab until 4.9).
  The stall interrupt's "cheaper to finish" test was two ANDed currencies
  and every T1 generator's 0 E made it never hold. The first nano of the
  game went to the wall whatever bought it and stood idle (`idle=17.5`
  from minute 4, +100 Wanderlust).

### NUKES FIRE AT GROUND NOBODY REMEMBERS (2026-09-18)

His 3x-economy game, won late by one nuke: the silo log reads `nuke ground
confirmed -- forgot 0 remembered enemies at the impact` x30 and `nuke intel
spent -- 0 remembered enemies need re-sighting` x23 against 5+4 launches
that forgot 2-4 remembered enemies. Most warheads went to ground with no
remembered enemy on it; the one that won hit their base. `nukes saving 0/1
for a target worth 30000 behind 1 antinukes` x7: one silo, stock 0. His
lens: what a human would do is mass nukes on scouted targets. The reads:
ai-nukes (target memory and the antinuke count), the scout task (eyes kept
alive over their base), and a second silo at that economy.

### THE COMMANDER FIGHTS T2 (2026-09-18)

His watch: "the commander is still being frontline rambo when enemy is
attacking with T2 -- he can't compete with that". In that game's log the
commander's samples read fwd=-0.3..-1.2, home=700-2400, far=0 -- behind
the anchor and inside his leash -- so the fight was the raid reaching him,
not him reaching the front: the DLL's commander fight/D-gun behaviour
engages whatever comes in range regardless of its tier. The ai-commander
skill and the StrRatio ruling ("Strength, not metal") are the reads; the
question is what he does when the strength ratio says he loses.

### ALTORED 1v1: the commander dies claiming outer mexes (2026-09-18)

Altored Divide +100 vs BARb hard, `--speed 10`, seeds 21-24: three of four
games end on a commander death at 7.6, 16.4 and 24.0 min (`unit-destroyed
armcom ... at=2622,1071 thr=22.76`, `at=708,2926 thr=46.62`, `at=575,624`).
Every game, his three of 09-18 included, elects the commander to mexes at
x=2288-3056 on an 8192-wide map (`exec armcom mex:armmex at=2656,1008`,
walk charged `t=904` and still `v=7.11` over a radar at 3.26); in his it
walked back alive, in mine the retreat started at hp=0.60 with `walk=2016`
and lost the race. The mex-guard ruling (guns on the mexes outside the
base, more the further out) and `con-retreat`'s trigger are the two reads
to make before pricing the commander's walk any differently: a mex claim
two thousand elmo out is worth its income only if the claimer comes home.

### COMET 8v8: level at minute 8, then the mexes go to T1 raids and the army trades 1:3 -- no eco decision moved it (2026-09-16/17)

Comet Catcher Remake 8v8 +100% vs BARb hard, seed 1, four runs of the
same seed. Control (0ace8c67): mexes 29 -> 18 -> 9 at 8/16/24 min against
32 -> 45 -> 55; metal 418k vs 856k; K/D 0.38 vs 1.54. Three eco variants
on top (converters hoisted above the draw + no generator while wasting;
that plus the honest ladder ticket; the ticket alone): 339k / 335k metal,
mexes 5 / 3 at 24 min, K/D 0.24-0.29 -- none better, one seed each. Our
mexes die from minute 8 to peewees and hammers (`BARAI_DEATH atk=armpw`),
54 a game; our T1 army dies 3-4 to 1. His watched 4v4 on the same map had
the same curve (29 -> 6). The eco market is not the binding constraint on
this map; holding the mexes past minute 8 is (docs/32 frontier, ARMY
SHARE, RAIDS). The converter hoist experiment is recorded in docs/27
(`apex_convert_push` -- not built as a tunable; the flag is a constant).

### SCARCITY: at no resource bonus an 8v8 is lost outright -- 122k metal to their 416k, 48 mexes to 128, every seat wiped (2026-09-16)

His hypothesis ("we do really good when we are wealthy, but as soon as
there's a limitation in resources we do much worse") measured on Supreme
Isthmus v2.1 8v8 vs BARb hard, seed 1, lane gridsnap at 6ff77c96:

| | +100% both (32 min) | +0 (30 min) |
|---|---|---|
| metal produced, ours / theirs | 1,909k / 2,426k | 122k / 416k |
| mexes held at end, ours / theirs | 88 / 136 | 48 / 128 |
| T2 mexes | 32 / 57 | 5 / 31 |
| per-seat metal, ours | 58k .. 793k (one seat 41%) | 5k .. 26k |
| per-seat metal, theirs | 161k .. 434k | 34k .. 82k |
| outcome | no winner at cap, 1 seat wiped | all 8 seats wiped |

By minute 14 the two sides are level (7-15k per seat each); the collapse
is minutes 14-30, where they keep claiming and we do not. It is INCOME, not
spend: at +0 the whole team averaged 8 m/s per seat. Three mechanisms read
off the +0 log (`matches/20260916-222751-*`):

1. **Elections go to insurance, not income.** Team-wide: energy 772, airdef
   556, sense 327, metal 275, buildpower 262, defence 100. A 100-metal AA
   tower priced v=12-38 (gain 11-16 m/s of "cover" against the 63
   Bladewings BARb flew) over a mex at v=4-10 in 101 head-to-heads; 212
   times over energy at v=1. At 8 m/s income the insurance rate outbids the
   only thing that raises income.
2. **Most of those elections are churn.** 556 AA wins became 167
   executions, 29 new requests, 26 towers; the same site executed 52, 34,
   21 times. A hand whose election the executor refuses is idle again next
   tick and elects the same want (the livelock shape, memory
   `election-livelock`). Under scarcity the hands' time is the scarce
   thing and it goes here.
3. **Mex tasks die.** 135 `task-die cormex` (110 with a crew and no build
   failure) against 53 finished; 54 mexes destroyed. The claim-to-mex
   conversion problem of TEAM GAMES below, now with the bonus off.

Later 09-16, three changes measured on the same seed (one seed: a
progression, not a proof), metal ours/theirs and outcome:
122k/416k wiped -> 159k/320k lost (TOTAL in-flight cap: past what the
income feeds, a new site is not opened, the asker helps finish one; per DEF
it had licensed 2 of everything) -> 215k/355k no winner (orphans first in
that fold: the first plant sat unmanned 322 s) -> 257k/343k no winner (a
spot hotter than our guns' influence is not offered -- the executor's own
bar asked at choice time; 3,995 spots refused, mex task deaths 213 still).
`tools/mexeco.py` reads the shape that remains: our extractor count PEAKS
AT MINUTE 8-12 (33-35) and falls to 11-16 by minute 28 while theirs climbs
28 -> 64-77; three front seats hold zero mexes from minute 16 and lose their
commanders at 15-26 min. We build half their constructors and a sixth of
their rez bots (40 vs 244 necros; reclaim 267 vs 1,055). His 09-16 read:
in 8v8 there are too few spots per player for mex-led income; the
economy (energy, converters) has to carry it, and we make army instead.
At +100 the converters do carry us (1,118 m/s at 32 min vs their 893); at
+0 there is no energy to convert. The next lever is the frontier: the
seats that lose their spots are the ones the wall (docs/32) should be
standing in front of.

Also the +100 game's own shape: one seat made 41% of the team's metal (the
eco seat, 793k) while three front seats made 58-90k in 32 minutes with 4-8
mexes each -- the bonus hides that the front is starved. The lever is the
price of income under scarcity against the insurance rates (AA, energy
ladder, sense), and the executor refusing an election it cannot site; the
army share (ARMY SHARE above) is downstream of both.

### TEAM GAMES: per-player expansion collapses with player count (2026-09-13)

Twelve harness games 09-12/13, all +100% both sides: 1v1 Comet 27 mexes at
8 min vs BARb 13; 4v4 Comet 7/8/12/6 per player vs 8/12/8/10; claims that
became mexes by minute 16: 1v1 55-90%, 4v4 12-37%, 8v8 7-37%. Two causes:

1. **The chooser and the executor disagreed.** `PickSpot` priced a contested
   spot with a threat ceiling of 99; `IBuilderTask::UpdatePath` killed the task
   when threat at the spot exceeded the builder's power (~0), so every
   `unreach armmex` read `threat=0.1..5.4/0.0` (106 mex tasks dead in the
   Comet 4v4). CHANGED 09-15 (`f4017fe5`): an economy site's bar is our own
   guns' influence there (`GetAllyDefendInflAt`, floored at THREAT_MIN).
   Frozen Ford 2v2 seed 5: spots held 3-8 -> 12, refusals 91 -> 47. Not
   re-measured on the Comet 4v4.
2. **Allies do not see each other's claims until the mex STANDS**
   (`MetalManager::SetOpenSpot` runs from the finished-unit scan; `IsZoneAlly`
   marks only ground next to an ally building): 16 of 39 spots in the Comet
   4v4 opening were claimed by two or more of our own players. Open.

Also: pre-contact `FoeAnchor` is the mirror of home (1900 elmo off on
Geyser Plains); the enemy start BOX centre is the honest anchor and needs a
binding (`CSetupData` has the boxes). Runs that decide it:

    python tools/run_tournament.py --a Apex:Unstable:standard --b BARb:stable:hard \
        --maps "Comet Catcher Remake" --games 6 --per-side 4 --minutes 16 --handicap 100
    # claim->mex conversion and `unreach armmex` per player vs the 09-13 numbers

### A dead mex is not rebuilt quickly (his sixth report 2026-09-05)

`tools/rebuild_lag.py`, six 6-game arms on Geyser Plains: median lag 0.4-1.2
min, never-rebuilt 3-15 of 24-43, no ordering by arm; n=6 cannot resolve it.
The price is consistent now (units count as cover, survival over delivery
time); what remains is structural -- a v=4 mex gets one ticket in three
against energy/sense/buildpower and every con is busy 20-60 s. A
"rebuild what just died" hoist was tried and REVERTED (took a contested v=2
mex over a v=13 generator, one spot rebuilt and lost three times). A
preemption is a rule -- his call.

## ECONOMY AND BUILDERS

### BAR's builder priority cannot carry the split: the shipped gadget barely throttles (2026-09-21)

His proposal for the scarcity split: "everybody building this thing gets
high priority, and the other people set themselves to low priority" -- the
game's own `unit_builder_priority.lua` (CMD 34571, 0 = low). Built and
measured: `CmdBARPriority(float)` bound to the script (kept), a pass that set
every builder's flag from what it builds (economy frames high; towers,
sensors, the labs and the nanos on them low), and `passive=`/`passiveBusy=`
on `[BARAI_STATS]` (kept). The flag took (labs read passive) and the split
did not move (Isthmus 8v8 seed 1: army 278k vs 280k, eco 82k vs 70k at 24 min),
because the passive builders kept lathing: 17 of 26, 26 of 35 busy with the
bank at 8-46 metal and pull at or over income. The gadget in game 2026.07.04
computes the metal a passive builder may draw as `cur - max(inc*0.2,
stor*0.01) - 1 + interval*(nonPassiveExpense + inc + rec - sent)/simSpeed`
-- the non-passive builders' expense is ADDED as if it were income -- so a
passive builder pauses only when the bank is under a fifth of a second of
income. Synced Lua, so not ours to fix (multiplayer is the target). The pass
was removed; the C++ stock toggle is back as it was. The split still has no
lever but build-power pull.

### The 8v8 allies' mohos are metal-bound, not hand-bound (2026-09-21)

Allies stand 2.4 mohos to BARb's 5.0 at minute 16 (live Isthmus 8v8). The
role census gave metal no target gap (`CatGapFrac` reads 0 for CAT_METAL) so
the defence gap (0.89-0.95 on every ally) took the roled hands, T2 cons
included: 6% of their decisions a moho, `role=defence` the reason. Giving
metal the ladder's gap (spots + servable upgrades over the growth still owed)
moved the decision -- metal gap 0.00 -> 0.32, quota 0.7 -> 1.5, T2-con
first picks airdef -> mexup -- and moved nothing else: mohos per ally at 16
2.5/1.7/2.9 -> 2.9/1.6/2.4, at 24 4.0/2.0/3.3 -> 4.0/3.2/3.4, starts
69 -> 65, ally income unchanged (3 seeds, `tournaments/*-roles8`). Reverted.
A moho takes 48-78 s of a 620-metal bill at 40-60 income with the bank at
zero: the T2 con already starts them; the lab's pull (its own 300 BP plus
the nanos) takes the metal first. The constraint is the army/eco split under
scarcity, not who holds the role.

Same game, the defence side of it (his 09-21 report: their mexes are always
better defended, ours lightly): towers per player at 16 min 9.2 (a third of
them AA) to BARb's 15.9, defence metal 2.0k to 6.3k, no HLT to their 2.1.
The defence role held quota 8-27 of the roled hands with 0-1 filled
(`fell=59-125`: the protect want refused at execution, the role released,
re-assigned next tick) -- so the hands stood roled to towers that were not
placed while the mohos waited. Why the protect executions fall is the next
instrument (`apex: prot-exec` streaks, `defsite` trace).

### The walled-plant move fired on a gantry 11% enclosed (2026-09-21)

His Isthmus 8v8 (`matches/_engine`, 01:35): the seat's gantry #25347 stood
`enc=0.11` -- its least-filled side 11% full, i.e. open -- and the rule of
09-17 ("a plant the core has swallowed moves to the rim, new one first") bought
a twin at 23.3m and reclaimed it at 29.5m (`apex: plant-walled ... reclaim
v=0.038 best=0.000`). He watched it: "our gantry get reclaimed... we made an
AFUS instead." The reclaim's gain counted the plant's own 7,900 metal as a
gain (removed 09-21, `want_reclaim.as`: a transfer, not a gain), but the move
still prices positive at any enclosure because `room` is linear in `enc` and a
seat's cell is worth thousands, and it wins whenever nothing else on the seat
prices at all. OPEN, his call: what counts as swallowed -- the doorway (the
side units leave by) closed, or every side?

### A crewless frame is only re-adopted by a same-def ask; it should be a priced want (2026-09-20)

His Ring Atoll game `matches/20260921-045243`: a fusion emptied at 95% by the
nano-fed peel, then during the e-stall at 25.3m both T2 cons founded a NEW
fusion 150 elmos from it (`request new armfus inFlight=2`). The peel no longer
empties a site (the founder stays, `peel.as`), and `Requests::Take` now hands a
crewless frame of the asked def to the asker (`adopt-empty`). What is still
missing: a frame nobody asks for by def -- an advanced solar rotting while
the market elects fusions, a converter frame while it elects mexups -- competes
in no election. Lane run `20260921-051803` (interim build): armadvsol at
1376,6016 emptied at 96% decayed to 81% over 80 s, `adopt-empty` 0, because no
con asked for an advsol in that window; `IdleFloor` would take it only when
nothing else prices above the floor. The right shape is a finish want: the
def's own gain over the REMAINING bill, so a 95% fusion is the cheapest energy
on the map. `ValueOf` prices a def from scratch and would need a remaining
fraction; not built. `apex: frame-stalled` and audit `no frame left to rot` are
the instrument.


### THE OPENING ON ALTORED: T2 lab done a minute after BARb's, four fewer mexes at minute 4 (2026-09-17)

Measured at --speed 10 (full speed stalls this map, docs/25 S34), +100, six
seeds, 14 min, against BARb hard, after 8de2c695 and the assist/ladder
repricing that followed it. Where we stand versus the control (his slot at
816cd437): mexes at minute 8 7.8 -> 10.0-10.8 (BARb 10.3-10.7), metal/s at
minute 8 44.8 -> 57-71, army at minute 12 14.2k -> 16.6k. What is left:
- The T2 lab starts at 6.8-6.9 and stands at 8.9-9.0; BARb's stands at 7-8.
  The ETA ladder picks it when its ETA beats the best eco rung; giving the
  tier's rungs the fleet's assist share did not move the pick (6.8/8.9 with,
  6.9/9.0 without). The start-to-stand gap is ~2 min of which the walk is
  most (latency start=25-98 s) -- the asker is whichever hand won the draw,
  not the nearest.
- The gantry stands at 25-27 min against BARb's 15.5-17.8 (30-min games,
  seeds 11-12). Its want first appears at 16-19.5 min: the host income gate
  `apex_gantry_host_inc` = 150 m/s of STRUCTURAL income (reclaim rate
  subtracted, 60-s EMA) is his 2026-08-30 ruling ("push back to 150 or
  later"), and his 09-17 brief ("take a really long time to even start the
  gantry") pulls the other way -- his call. Once wanted, the frame took
  522 s on one hand while 83 turrets went to the lines beside it: the sink
  branch life-scaled a plant's frame like a converter's; fixed (a plant's
  frame is its ring), 57-203 s after.
- Minute 4: 5.3-5.5 mexes against BARb's 7-8. The commander's LLT at 0.5-
  0.8 min (his mex-guard ruling) and the nano floor's turret at 1.7-2.1 min
  (his 09-11 ruling) sit in the window; the next open spots are a 60-100 s
  walk; the roulette still draws v=1-4 winds over v=5-9 mexes one election
  in three.

### ECO SEAT GANTRIES: two gantries, a full bank, 1,300 m/s of idle nano lathe, and the turrets went to the line and to towers (2026-09-16)

His watched Supreme Isthmus 8v8 (`matches/_engine`, seat t7 at 10150,597):
at 32 min `nanowant ... idle=1347-1662 bank=4966/5000`, both gantries at
`depth 2+2/592s`, `facqueue idle coraap/corap: no-candidate`. The seat's nano
executions: 122 at the team line 3,669 elmos away (`nano-to-line`), then
`nano-to-sink` cordoom 101, cormmkr 87, corfmd 48, corfus 29 -- the gantries
(`corgant` at 10124,682 and 12080,384) are not sinks in that list and the
cells within 300 of them saw 10-36 attempts. He: "two gantries and only a
small number of nano turrets around them... good income, not able to produce
units. This is an issue that we have very often." NeediestLine read the
gantry line at 0-58 m/s of need while its queue held 592 s of work; a
gantry's line should be the hungriest thing on the seat.

Found 09-16 (later): `LineUnserved` subtracted the lathe standing at a
working line from its share of the FREE flow -- but busy lathe is already
inside the pull that FreeMetalFlow nets off, so the line's need read zero
whenever its standing lathe exceeded the unspent flow's share, however much
overflowed. Removed (sites.as). One 32-min 8v8 seed: the eco seat's line
term moved 0-5 -> 11-59 m/s at 15-25 min and its turret count 113 -> 176,
but waste at the seat was 10-116 either way; no gantry stood on that seat
in either run, so the gantry case itself is still unmeasured. Its labs
make constructors, and a con line is not nano demand by his 09-14 ruling,
so the remaining waste is the seat's factory capacity (plant-glut, TODO
"never an idle factory"), not its lathe.

Found 09-17 (eco-only Altored): a turret handed a reclaim by the pile-on
(`NanoReclaimAssist`) stood IDLE afterwards for the rest of the game -- its
patrol was the one command in its queue and the reclaim replaced it. Fixed
(re-patrolled when its queue empties); the "lots of idle nano turrets" he
saw at the eco seat may have been partly this. Unmeasured at the seat.

Found 09-17 (1v1, Altored): the pack walk's 96-cell slice ran out inside a
full block before reaching a free cell -- the gantry asked 318 turrets over
66 walks, got 95, 49 walks out of budget -- and every walk restarted from
the same rings. PackSlots now resumes where the last slice stopped
(`PackResume`); after, 48/48 and 0 walks out. The eco-seat 8v8 case is
still unmeasured with it.

### ECO SEAT DEFENCES: bought late, inside the base, with walk gaps that block the farm (2026-09-16)

Same game: t7's Bulwarks (`cordoom`) executed 20 times within 1,000 elmos of
its anchor and 30 claws (`cormaw`) within 1,000, i.e. inside the eco block,
with the 6-cell `_default_` yard around each (dropped to flush in ad3aa4bc).
He: they "block useful construction of a lot of other things". The eco seat's
guns belong on its rim (defence-wall paradigm), not in its rows.

Found 09-16 (later): two buyers. (1) The DEFENCE role hoist took the seat's
best defence want whatever its price -- `why=role role=defence` at v=0.09
over assist at v=52; in a 32-min 8v8, 211 of 338 defence-role hoists were
under a tenth of the alternative. Fixed (roles.as `RoleWorthDoing`): a role
holds only while the category's sharpened draw ticket would win at least
one of the R roled elections; after: 0 hoists under a tenth, 5 under half.
(2) `why=draw over nothing`: a hand whose only candidate is a ~0-valued claw
or Bulwark on the home hull takes it -- 108 such elections on the eco seat
in one game, 11 guns within 1,000 of its anchor. Whether an idle hand should
build a worthless gun rather than wait is his call; not changed.

### LATTICE RESIDUE: 4-6% of nano turrets stand off the lattice, hugging a fixed site; mixed pitches leave 1-3 square strips (2026-09-16)

`tools/tiling.py` on the eco-only board (`matches/20260916-082921-*`,
`-083637-*`): 641/667 and 623/660 aligned, every miss a nano. The ring walk
(8 rings / 200 probes) finds nothing in a full block; the wide search then
returns a hole that is not a lattice cell (`apex: off-lattice ... taken=25`),
which is a hole beside a mex, tower or radar -- fixed sites are not on the
turret's lattice. Those turrets are flush with what they hug, so this may be
what he wants; if not, the walk should resume from ring 8 on the next
Execute instead of falling to the square search. Separately FOREIGN gaps of
1-3 squares (20-30% of structures) are where two defs of different pitch
meet: on one global lattice a solar (80) and a converter (48) share an edge
line only every 240 elmos. Flush everywhere would need a per-neighbour
placement (a cell chosen against the neighbour's edge), not a lattice.

### SEAT CORNERS: a farm past a cliff still kills an eco seat; a full yard falls to the probe ring (2026-09-14)

Supreme Isthmus seeds 3 and 5 (Armada): the rear seat's farm rear point and
lattice rings sit past a cliff; reach marks cut `unreach` 1,751 -> 40-100 on
seed 4 but seeds 3/5 still read 700-1,100 and the seat is overrun by minute
24 with income under 40. `FarmSlot`'s rear point walks back toward the anchor
until reachable (sites.as `EcoSiteFor`); the yards and lattice rings do not --
FarmSlot should test reach from home the way `CanDefReach` does. Separately a
full converter yard has one ask refused 20-40 times at the same point and
`ProbedSite` puts it on the 700-elmo ring: `audit.py ring-scatter` 14-28% on
the seat, 2-7% on Carrot; the yard should step to the next block
(`GroupAnchor` already knows it) before the ring places it.

### CONVERTERS: the T2 hands do not ask for the advanced converter, so the basics cannot retire (2026-09-12, still true 09-15)

Greenest 2v2 seed 10 (`tournaments/probe-reclobs2/3-greenest-s10`): T2 cons
elected 42 wants in 30 min, ZERO converters, 77-85 basics beside 1-3
advanced, waste 10-25%. Still the shape today: `def8/ford-D10-s5` t1 at 24
min `convwhy surplus=-63 excess=0 ema=536 inflight=600 standing=2870
bank%=96 v=0.000`. `eSurplus` carries the fleet's potential ask (the same
contamination the reclaim gate had) and reads negative while the bank is
pinned; the pinned branch prices the next advanced converter at
`capacity - ConvCapInFlight()` = 0 while one crawls. Tried: pricing at the
engine's measured excess (09-11, lost on both maps, reverted); T1 converters
retired by ratio (`TUNE_OBSOLETE_RATIO`, reverted for starving conversion at
the T2 transition); the reclaim gate now demands the denser hands FREE to
convert (`DenserHandsCover`, 09-14, unmeasured). `ConvUpDemand` reads zero
once the basic fleet's capacity covers income (want_energy.as:809), so on a
no-mex map nothing asks for the advanced plant; counting outclassed energy
measured worse on both maps. The seat's 13k E/s wasted with 84 cloakable
fusions and no converters (09-13) and "two Legion players at 59 advanced
solars" are this entry. `apex: convprice` prints the terms.

### REACTORS: no advanced fusion in an 8v8 at 733 income (2026-09-13)

His Carrot 8v8: fusions 5-16 per player, zero AFUS in 34 minutes. `ebig
mkt=legafus eta=legfus`: the ETA re-ranks on build power for a never-built
def taken as the class mean; recency-weighted 09-13 and "AFUS when the pool
has grown" (`2b4a838c`) landed -- no 8v8 read since. If it still never comes,
price the AFUS on the crew it would GET (`CostCrew` x con BP + nano lathe in
reach), which is what the market side already does.

### BUILD POWER: hands are still bought while hands stand idle (2026-09-11, changed 09-14)

His Greenest 2v2 (`matches/_engine`, 58 min): 482 mobile constructors, 14
factories, `bpgap gap=515 tgt=2425 cap=6745 net=-4319 blog=515 rawM=30936
bank%=94`. The backlog term (`blTerm = rawBl / apex_bp_backlog_s`,
want_energy.as:1077) still reads ordered-not-framed rows as a hands
shortage. `feedRoom` is lathe-based since 09-14 (`45403a65`); the seat's
~120 T2 cons now come from the T2-con FLOOR `2 + income/25` (his 2026-08-23
"at 100 m/s at least 5", scaled) -- `expect.py` "eco seat hands are turrets"
is RED on the con count; whether the ratio holds at 1k income is his call.
`Utilization()` (army.as:1439) counts busy constructors and never a factory;
the plant copy waiver was fixed separately (09-13), the term is still wrong.
`want_assist.as` bounds a hand's drain by `FreeMetalFlow()` (:125, :246) --
unspent income -- so with every metal committed the assist dies and a big
build runs at one lathe; `WorthJoiningSite` (09-11) joins by time saved, and
the T2 lab's crew has not been read since ("we get to T2 behind our
enemies", 09-08: 3.8 min at ~11 m/s with 12 cons alive).

### GANTRIES idle at 1,000 m/s; basic converters at 1,000 m/s (his 2026-09-12/13 reports)

Team 7 of his Carrot 8v8: five gantries 80% idle, bank pinned at 13.5k for
four minutes, every T3 candidate `gap0` because 245 Pawns + 140 Favs built
for escort duty filled the army target; a queued Korgoth + Juggernaut (49k)
booked as army held; 163 basic converters finished in minutes 24-28 beside
11 fusions. Fixes 09-12/13 (`PendArmyMWithin`, `RichArmyGapM` live again,
escorts by risk, copy waiver needs every line working, hands verdict) --
unverified in a watched game. `FacYardWatch` (`apex: facyard jammed`) reads
a blocked plant; nothing yet says what blocked HIS gantry.

Third report 2026-09-16, Isthmus 8v8: the eco player stood ~10 advanced air
labs, often idle, while spending about half of income. His infolog from that
game is unread; the first thing to read from it is what the auction offered
those labs per minute.

### ECONOMY LADDER: what stage 1 left open (2026-09-11)

Stage 1 (the generator chosen by the ladder, the tech want asking the
simulator, measured effective lathe per def) shipped 09-11 and moved both
maps up. Open, in the order the game says it costs:

- The tech want's PLANT choice and the mex/nano/plant proposers still use the
  market's def pick; only energy asks the simulator per def.
- Stage 2: the target carries holdings shares (his N%) and army in strength.
  This is where "a T2 lab while the front is being lost" (seed 17: `tech:
  armalab` drawn at 8.5 and 11.4 min with `leash need=38-58 sent_pw=29-35`)
  enters -- the tech price carries no army-share term.
- Two ladder reorders (build time in the key; the measured 17 s
  decision-to-ground wait in the key) each gave Isthmus +23-47% and Greenest
  -17..-35% through the constructor count. Which of `LadderRun`,
  `EtaEcoPick`, `EtaHandsShare` starves the no-mex map is the open question;
  until answered no ladder reorder is shippable.
- Greenest still ends on ~92 basic converters and 12 advanced solars against
  BARb's 8 advsol (CONVERTERS above).
- HOME READS LIKE THE FRONT once their army dwarfs ours: the siege term
  is foe/(foe+ourArmy+cover)/tau x shortfall, and at 10x it saturates to
  1/tau everywhere, so only local cover separates a mex behind the start
  from one at the wall's foot (0.545 flat, gate games 2026-09-15; p25 of
  home readings 0.545 in every loss band). The interior-as-worst-hole rule
  (gGapShort) helps only when every walkable bearing carries guns. What is
  missing is DEPTH: the rate at which a siege reaches a point should fall
  with the ground of ours it must cross first (the raid gradient against
  the line's own gradient), not with the guns beside the point.
- The base ETA is NOISY at the scale of its own decisions: his Comet 1v1
  (2026-09-15, 15.1-16.4 min) read `base=545, 7119, 1333, 7839, 9300, 1875`
  at P=178-247 -- a 17x swing inside 80 s with the same pool -- and a fusion
  was drawn at v=1.33 over a mexup at v=13.36 because the ladder read the
  moho as SLOWER than doing nothing (9315 vs base 9300). Which input jumps
  (bank, eAvail, the pool's `n`, StepSec at a dry feed) is unread; until it
  is, the merged eco ticket is a lottery on noise.
- Two rules from those sessions: an eco change measured only on the canon
  board is not measured (the board rewards not building infrastructure);
  the canon at `--speed 5` is not deterministic (700/771/845 m/s at minute
  20 for one tree) -- four runs per arm is the floor.

### ROOM: the crowding measure falls as the base fills (2026-09-09)

`PfCrowd()` is footprint over the area inside the rim, and the rim is the
furthest thing we own per bearing, so it read 0.01 from minute 7 while he
could see the base squeezed; every `apex_room_worth` charge (generator,
converter, reclaim; want_energy.as:1242, protect_want.as:193) is inert late.
`PfCrowdAt(pos, r)` reads 0.17 against 0.02 at minute 25 but feeding it in at
the old weight was a regression (299k -> 175k produced): the charge has to
be bounded by what the ground is worth to the next building. Not derived.

### ROLES and SENSE: a role is released when its category is refused, and sense is refused most (2026-09-08, mitigated 09-14)

`roles-h100-t`: 2,775 sense wins, 84 executed, `corarad done=3 abort=21`;
his 09-13 8v8 team 7: 2,459 sense wins, 32 builds. Each refusal drops the
hand's role and the draw re-elects it into sense (`fell=2718..4799` against
`roled=3..11`). Since 09-14 a fallen category is not handed out for 30 s
(roles.as:27); `def8/ford-D10-s5` at 24 min reads `exec-refused sense=170`
-- smaller, not read at 8v8. Couplings law 3 stands: the sense want passes
`GATE_RADAR_GAP/_FRONT/_HOT` on a site the request layer refuses; read
`Requests::gLastWhat` on the refusal before pricing anything.

### REZ: the fleet is sized to a stream it does not convert (2026-09-06, 09-13)

16-AI hour `matches/20260906-105022`: 35 bots per AI at minute 54, nominal 83
m/s, realised `mReclaim` 0.45 m/s; `unmet = stream - have x cap` has no
realised-output term and lowering `TUNE_REZ_UTIL` demands MORE bots. Rez
priced on the unmet wreck/retire stream where the army form is zero (09-13)
-- unverified. Rez BOATS: the stream is map-wide (`Military::WreckRateM`,
deathledger.as:141), so a shipyard buys rez boats off land wrecks and no
navy (his 09-13 report); split by movetype domain unbuilt. Early fleet 2.7
at 12 min against his 4-5 (`RezWorkM` pricing). The back-away envelope reads
only enemies we SEE (`GetEnemyReachSlack` skips hidden ones).
09-19, his Isthmus 1v1 (`matches/20260919-055126`): 14,716 `apex: nopath ?
by armrectr` and 3,160 `unreach ? bt=16` -- the rez chain hands land bots
reclaim tasks up to 6,965 elmo away across water, the DLL aborts each at the
path test, 6 a second for 40 minutes. `EnqueueWreckReclaim` tests
`NearBlocked` and threat but never `ReachableBy`; the RezzerChain path is
unchecked. Con-idle samples count these bots, so the 43% idle figure is
partly them.

### NAVY: no bot con can reach a shipyard from the Isthmus start; the T2 con sub never elects (2026-08-31, 09-12)

Legion 1v1 Isthmus seeds 1-2: every wet site is 260 elmos from ground a
`legck` stands on against 182 reach (`apex: unreach legsy gap=260`,
`wet-unreach` every minute); the shipyard is elected by the first air con
(18.7 min) or never. The commander (amphibious) could at minute 5;
`ProposePlant` refuses it for water plants by his 2026-08-28 ruling -- whether
the naval LEAD's commander may is his call. Downstream (Nine Metal Islands
4v4, 08-31): the advanced construction sub is produced and never takes a
job -- `acsub` appears only as a shipyard producing one, `uwmme` elected zero
times. Find where a submerged builder falls out of the builder market
(`gWorkers`, `OnMap`/reach guards, an execute path with no water case)
before pricing anything. Not re-read since.

## AIR

### A T3 nuclear bomber reaches the base (2026-09-15)

His 1v1 (54 min, lost to a Ragnarok): one enemy nuclear bomber got through
at ~33 min and took 43 nano turrets and a share of the eco with it
(`unit-destroyed armnanotc` 43 in 30-35 min; workers 40 -> 15). What the
AA layer reads against a T3 flyer, and whether the air-defence want prices
one plane's payload against the base it flies over, is unread. The army
then went passive on the massing law (`stance -> passive`, foeMass 188k
against ours 73k) -- outmassed 2.5:1 at +100%, which is the ARMY SHARE
issue, not timidity.

### BOMBERS: the wing flies at the deadline into the AA and dies whole; the seat's bombing output is unread (2026-09-12, 09-14)

`tournaments/20260912-141649-scouts2`, Greenest 2v2: every strike died to the
last plane -- `deadline bombers=12 fighters=8 enemyAA=10200` then `run scored
sent=11 home=0 surv=0.00 dmg/bomber=0`; "deadline" is a clock
(`AIR_DEADLINE`, `DeadlineBombBar` 12) overruling a model that says the run
will not pay. "Wing at its worth" re-released six times in five minutes as
each wave died (`A-s4`). Since then: the bomber bids in the army's currency
(`a13edb2f`; wings of 10-17 mass, `sent=17 home=17 dmg/bomber=412`), the
wing is weighed by cost (`9abf16ae`: nine Tyrannus counted as nine of a bar
of 22), the losing-ground hold-off is gone (`7f2649c1`), the ex-seat is a
second assassin. His ask stands until a watched game shows the raids: read
`apex: wing` and `facqueue` for the seat after it turns. The non-lead
`apex_air_home_wave` bar (update.as:510) was never given the frozen snapshot
the lead's has.

2026-09-20, his Frozen Ford game (`matches/_engine`, t0) and lane seed 1: a
run ends before it arrives. `ReArm` ends the run when what was built since
is the bigger force (`held <= have` fails), and a four-plane wave has that
the moment one plane finishes at home -- `air strike -- deadline bombers=4`
at 28.2m, `air strike over -- 2 of the wave home, 3 built since` at 28.8m,
36 seconds later, planes still en route; `RecallWave`'s move is then
overridden by the bomb task they already hold, and they died at the map's
far edge one by one (the Liche among them, at 29.1m). The rule needs the
wave to have ARRIVED before "the bigger force is at home" can be read.

## INSTRUMENTS, PERF, TREE

### PERF: 16 AIs hold 1x to ~5,600 units; order volume unread since the revert (2026-09-06)

8v8 Isthmus seed 1 on a 5800X3D: 32.5 ms/frame at 5,492 units, breaks at
5,869, 47.7 ms at 6,998 (minute 59); the AI is 18-19% of the frame, 0.567
ms/AI against the 0.417 target; the engine alone crosses 33 ms at ~6,400
units, so the late minutes are simulation cost. `apex: order-src` read
~4,400 orders/min for 276 units (one per unit every 3.8 s; escort
contradicting itself 99% of repeats) BEFORE the 09-07 fight revert;
`tools/orders.py --unit N --pairs` (`apex_order_trace=1`) has never been
pointed at a game. `ai-performance` skill owns the procedure.

### CONSOLE: the log leaves the chat; the hour-scale effect is unverified (2026-09-12)

The AI writes `apex-t<team>.log` and `run_match` merges it back
(`tools/apexlog.py`). Not verified: that a 60-minute 8v8 no longer reaches
LuaUI's emergency collect (`grep "Emergency garbage"` in the next long
infolog; the 09-12 benchmark hit 606 ms/frame at minute 58).

### Cull not done: `policy.as` is 16 dead accessors and 26 unread tunables (2026-08-31)

One call site tree-wide (`Policy::AntinukeIncome`, want_super.as:504); the
other 16 accessors, their `TUNE_` constants and `dev_tunables.lua` entries
are live modoptions wired to nothing. `python tools/as_scope.py --dead` lists
them and 91 unreachable functions. `TUNE_CON_LOG_*` are drawn by the
dashboard and `apex_t2_metal` lives on as `T2_BAR = 30` in `audit.py:848` --
both his call. The one real issue under it: `want_super.as` stacks an income
floor on the antinuke because `afford` rewards being cheap by construction.

### Tools still blind to units under 120 metal (2026-09-05)

`dev_stats_export.lua` diverts defs cheaper than `SPAM_COST=120` into
`cheapBuilt=`; `tools/army_mix.py` reads `top=` only (the top four),
`tools/expected_units.py:117` reads `allBuilt=` only. `composition.py` was
fixed; the other two produced the false "Cortex builds no rocket bots"
finding (corstorm is 110 metal, armrock 120).

### The repo DLL is the 2026-09-06 build (S3 family)

`ai/Unstable/engine-side/SkirmishAI.dll` was last committed `af2a266e`
(09-06); every C++ binding since (`GroundConnected`, `GetAllyDefences`,
`GetThreatAt`, `GetAllyDefendInflAt`, `KeepsExit`, `NoteUnsafeSite`) exists
only in lane/vendor builds. `deploy_ai.py` prefers the local build when one
exists and says "(repo copy -- no local build in vendor/)" otherwise -- a
deploy from a fresh checkout ships a script that cannot compile against it.

### `ExecuteWant` throws inside `CmdMoveTo` on a condemned reclaim target, intermittently (2026-09-06)

execute.as:418, the WK_RECLAIM branch: `tgt` is null-checked and its def
read, so the throw is inside the binding -- the target dying between the
check and the order (S13). 1x and 4x in two 16-AI hours, absent in four
others. The exception aborts the election, so the reclaim silently does not
happen.
