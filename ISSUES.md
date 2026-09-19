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
