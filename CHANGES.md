# What this AI does that stock BARb does not

Two variants, both built on BARb (CircuitAI). Everything here is a deliberate
difference from `BARb/stable`; anything not listed behaves as stock.

| variant | intent | best measured result |
|---|---|---|
| **apex** | stock BARb plus a team T2 rush | **16-0 vs medium on all three factions; 8-0 vs hard at 8v8** (2026-08-07) |
| **apexdef** | hold ground, out-eco, finish with T3 | 4-3 over 10 clean games |

## 2026-08-08: the gantry cap WAS the T3 constraint

Single-variable change from the arm below -- `GANTRY_PER_INCOME` 150 -> 100 and
`GANTRY_MAX` 4 -> 6 -- measured the same way, 6 games, 8v8, Handicap 50.

| metric | gantry cap 100/6 | cap 150/4 | delta |
|---|---|---|---|
| **T3 plants built** | **16 gantries / 6 games** | 5 / 6 games | **3.2x** |
| T3 spend | 11,715 | 6,804 | +72% |
| corcat spend | 132,300 | 53,900 | +145% |
| metal built | 131,581 | 122,279 | +7.6% |
| **army share** | **14.6%** | 11.2% | **+30%** |
| **energy wasted** | **142,723** | 299,662 | **-52%** |
| T2 spend | 76,193 | 68,434 | +11.3% |
| mex upgrades | 5 | 4 | +25% |
| player-games wiped | 18/48 | 17/48 | ~same |

Total build normalised to the opponent is unchanged (61.3% vs 61.5%) -- this did
not make us build MORE, it changed WHAT we build, out of banked metal and wasted
energy and into T3 and army. Halving energy waste is the same story: T3 plants
and their units are where that energy goes.

"Building T3 gantry" decisions actually FELL, 50 -> 36, because the requests now
land: `WantMoreGantries` counts nanoframes, so a gantry that completes stops the
re-request. Fewer decisions, three times the plants.

### Cumulative, session start to now

| metric | ctl (session start) | apex (now) |
|---|---|---|
| metal built | 110,738 | **131,581** (+18.8%) |
| T3 spend | 3,483 | **11,715** (+236%) |
| army share | 12.5% | **14.6%** |
| energy wasted | 338,317 | **142,723** (-58%) |
| cons T2 held | 7 | **10** |
| player-games wiped | 24/48 | **18/48** (-25%) |

Still a long way behind stock, which fields 45% army on 214,826 metal built.

## 2026-08-08: measured -- the six changes are a net win

Paired tournaments, 6 games each arm, 8v8 Ascendancy, Handicap 50, same seeds and
settings. Control is `ctl` regenerated to session-start HEAD (the old frozen
`ctl` was several commits stale and would have measured the wrong thing).

| metric | apex (new) | ctl (control) | delta |
|---|---|---|---|
| metal produced | 150,240 | 138,252 | +8.7% |
| **metal built** | **122,279** | **110,738** | **+10.4%** |
| T2 spend | 68,434 | 62,309 | +9.8% |
| **T3 spend** | **6,804** | **3,483** | **+95%** |
| cons T1 (peak) | 22 | 22 | 0% |
| cons T2 (peak) | 9 | 7 | +29% |
| energy wasted | 299,662 | 338,317 | -11.4% |
| army share | 11.2% | 12.5% | -10.4% |
| **player-games wiped out** | **17/48** | **24/48** | **-29%** |

Normalised to each arm's own BARb opponent, because stock itself varied ~9%
between arms: metal built went from **51.4% -> 61.5%** of the opponent, and T3
spend from **9.8% -> 16.2%**.

Win rate says nothing, as expected -- 5 of 6 and 4 of 6 games hit the time limit,
and both decided-game CIs include 50%.

**The feared constructor sink did not happen.** 1,763 reclaims across 6 games
looked like a constructor time sink, but peak T1 constructors is identical (22 vs
22), peak T2 constructors is UP (9 vs 7), and metal built is up 10%. Clearing
obsolete buildings pays for its own constructor time.

The one regression is army share, 11.2% against 12.5%, and it is small. The gap
to stock remains the real story: stock fields 43.7%.

## 2026-08-08: the constraint is build power, not space

apexearth, watching an 8v8 on Ascendancy live: "we losing because we werent
making t3 enough even tho our economy was matched", and earlier "we're failing
to use all of the resources we make... i see them building [gantries] now at 36m
but i'd say that was too slow."

`composition.py` on that game says he was right on both halves, and identifies
which one is causal:

| per player | apex | stock BARb |
|---|---|---|
| metal produced | 240,298 | 258,209 |
| **metal built** | **177,462** | **243,352** |
| T3 spend | 10,215 | **51,334** |
| army share | 16.1% | **44.8%** |
| cons T1 (peak) | 35 | **61** |
| cons T2 (peak) | 6 | **15** |

The economy WAS matched -- we produced 93% of stock's metal. We then **built only
73% of what we produced**, against stock's 94%. Roughly 63,000 metal per player
was made and never turned into anything, and the shortfall lands hardest on the
most build-power-hungry thing on the board: stock spent **5x** more on T3.

Peak constructors held is where it comes from: 35 vs 61 at T1 and **6 vs 15 at
T2**. This is not a placement problem and not an affordability problem -- income
was 312-516 metal/second, far above the ~250 where CLAUDE.md notes the
affordability argument inverts, and 16 gantry requests went out. There was
nothing to build the requests with.

Note this contradicts the natural reading of the base-layout work below. Sprawl
is real and worth fixing, but on this evidence it is not what stopped the T3.

### "No room to tech up" did not happen in these games

Six-game 8v8 tournament, Handicap 50, 1,907 `techroom` samples:
**`techroom=-1` occurred ZERO times.** There was always a site for an advanced
lab within 1800 elmos of the base anchor, at every minute of every game, and the
distances cluster at 200-700 elmos -- i.e. close in, not out at the edge of the
probe. `blocked=1` appeared in 7 samples out of 1,907.

So on this evidence sprawl is **not** what stopped the gantries, and the base
layout work should not be credited with fixing T3. Walkability, self-walling and
density are still real problems worth solving; "no room to tech up" was not the
mechanism here.

**Caveat on this measurement**: the probe lives in `baseplan.as`, which only the
treatment variant has, so there is no before/after comparison -- only "after is
fine". A pre-change baseline would need the probe added to the control too. Worth
doing before this is treated as settled.

### Where the T3 actually went: 2 gantries against stock's 7

Same watched game, unit by unit from `allBuilt`:

| | apex | stock BARb |
|---|---|---|
| total built | 1,419,697 | 1,946,820 |
| **T3 share** | **3.9%** (54,800) | **26.7%** (520,600) |
| T3 plants | armshltx 15,800 = **2** | armshltx + corgant = **7** |
| T3 units | banth 1, thor 1, vang 1 | Sumo, Juggernaut, Catapult, Korgoth |
| armfark built | **0** | 5,460 |

apex's first T3 metal appears **after minute 26** and totals 42,050. Stock poured
429,000 into T3 units.

Two gantries is not an accident, it is the configured answer:
`GANTRY_PER_INCOME = 150` with `GANTRY_MAX = 4`, so a player at 400 metal/second
wants `400/150 = 2`. The comment above that constant records fixing a worse bug
(`gHaveT3` latched the AI to exactly ONE gantry per game), but the replacement
still caps throughput far below what stock reaches by having no T3 logic at all.

The other half is completion, not intent: **16 "building T3 gantry" decisions
were logged and 2 gantries exist.** `AiGetFactoryToBuild` returns the gantry and
the request dies downstream. Which of the two -- the cap or the completion rate --
dominates is not yet established, and is the next thing to measure rather than
guess.

apex also built ~66 `armack` (27,090 metal) to stock's ~10, while holding fewer
T2 constructors at peak (6 vs 15). We are buying advanced constructors and losing
them.

### armfark/corfast promoted to builder once an advanced con is held

`behaviour.json` parks armfark (Butler, 210m, 140 build power) and corfast
(Twitcher, 210m) as role **support**, not builder, with a documented reason:
`CFactoryManager::GetFacRoleDef` filters the recruit draw on `GetMainRole`, so at
builder weight they take a share of the draw away from armack and delay the
team's single shared advanced constructor -- which gates T2 mex upgrades.

That reason is entirely about the RACE for the first one, and it expires. Once
`gHaveAdvCon` is true there is nothing left to delay, and 210 metal for 140 build
power is the cheapest build power in the game. `Builder::PromoteAssistBots` now
calls `SetMainRole(RT::BUILDER)` at that moment, once.

Legion needs no equivalent: `legaceb` (Proteus, 310m) is already role builder in
`behaviour_leg.json`. Checked rather than assumed -- `legfast` does not exist in
either tree, and the faction-parity trap is the recurring one here.

### T1 towers are no longer offered past their tier

apexearth at 25 minutes on 130 metal/second: "i still see some of our cons
retreating from front line to build a light laser turret, the t1 super crappy
turret... at this point we shouldn't be making those anymore."

`ContestTower` chose the tower from the **constructor's** cost and nothing else --
`costM >= ADV_CON_COST` got corvipe/armpb/legapopupdef, everything else got
corllt/armllt/leglht. A T1 constructor was therefore offered a light laser at
minute 25 exactly as at minute 3. It now returns null past T1 tier, so the
constructor falls through instead of walking home. This STOPS work rather than
redirecting it, which is why it is safe to add on its own.

### Why obsolete reclaim "fired twice in thirty minutes"

Not the gates -- the queue position. `ObsoleteReclaim` sits at line 2762, near
the END of `AiMakeTask`, so a constructor is offered mexes, defence, converters,
nanos, fusions and wreck reclaim first and only ever reaches the tidy-up if every
one of those declines.

`ObsoleteUrgent` now runs it **ahead of the economy offers** -- the cheapest
constructor time in the file -- gated on being past T1 tier AND 6+ T1 structures
standing. Deliberately NOT moved above mex expansion: that is the documented way
this repo previously cut its own metal production 4.3x.

`ReclaimOwnDef` also now chooses WHICH copy to eat by geometry rather than
whichever the engine listed first -- one standing in a walkway scores above one
stranded outside the footprint, which scores above a tidy one in a row.

## 2026-08-08: one base layout, replacing position-plus-shake

apexearth: "every placement is (position, shakeRadius) and the engine slides the
site anywhere in that radius. There's no footprint, no rows, no lanes. That's why
tuning the radius trades sprawl against self-walling and never fixes either."

That was exactly right, and there was more of it than expected. Three separate
lattices existed -- `BandSpot` (nano rows plus eco flanks), `ConvSpot` (the
converter block) and `RearPos` -- each re-deriving its own axis from `gHomePos`
and the enemy centroid, none aware of the others, and **none asking whether
anything could stand where it pointed**. Everything else went out with the
default shake of 256 elmos.

New `manager/baseplan.as`, namespace `Base`: one anchor (the first factory,
latched), one axis (toward the front via `Front::FrontNear`, which falls back to
the start-box lane so it is stable from frame 0), and walkways defined in **world
offsets** rather than column indices, at a 720-elmo pitch, so bands on different
pitches leave their gaps in the same places and the gaps line up into an actual
corridor. Cells are validated through `ai.FindBuildSiteNear` before being handed
out, then enqueued with **shake 0**.

### The rules this first governed were all switched off on the benchmark

Measured: `placed=0` across an 8-minute and a 25-minute 4v4. Every rule put on
the grid first -- nanos, fusions, the converter block, the generic converter --
is eco-lead-only, and `ECO_ON_SMALL_TEAMS = false` with `BIG_TEAM = 6`, so at
4-per-side the eco lead never activates. Comet Catcher is a 4v4 map, so on the
standard benchmark the whole subsystem is inert. This is the CLAUDE.md
benchmark-economics trap in a new place: not income this time, but team size.

### So the grid is applied in C++, to every placement

`IBuilderTask::Execute` did `pos = (shake > 0) ? get_near_pos(position, shake)
: position`. It now snaps to a grid published from script
(`ai.SetBaseGrid(anchor, fwd, cell, lanePitch, laneHalf, range)`, the same
mechanism `SetFrontPos` uses), falling back to the old jitter when there is no
grid -- so stock BARb and the `ctl` control are unaffected and remain a valid
baseline.

Excluded by build type, for two different reasons. MEX/MEXUP/GEO/GEOUP/DEFENCE/
BUNKER/BIG_GUN/PYLON/TERRAFORM have to stand on a particular piece of ground and
would be ruined by being moved. **FACTORY is excluded for the opposite reason**:
packing labs into the lattice is what leaves no room to tech up, and keeping that
room free is what the lattice is for.

Cell 72, lane pitch 720, lane half-width 72, range 2200. Every band pitch and
band depth in `baseplan.as` is a whole multiple of the cell -- load-bearing,
because the C++ snap applies to the script's own placements too, and a band on
some other pitch would have its own cells moved off it.

### Measurement for the criterion apexearth named

"Can we still place a T2 lab at minute 30" was previously invisible -- it only
showed up as a build that quietly never happened. `Base::Update` now probes it
directly each minute via `FindBuildSiteNear` on the side's advanced lab and logs
how far out it had to go:

    apex: base area=<elmos^2> width= depth= placed= noroom= blocked= techroom=

`techroom=-1` means no site within 1800 elmos of the anchor. Base bounding-box
area and blocked-placement count are on the same line.

**Not yet measured for effect.** Compiles, loads, latches a sane frame
(`cols nano=26 eco=18 heavy=10`), zero AngelScript errors over two runs. What it
does to composition is unknown, and by the rule that firing is not evidence, that
is the number that decides it.

## 2026-08-07: naval response was switched off entirely

apexearth: "we suffer lots from enemy subs, we don't make enough torp launchers
or destroyers at t1... the destroyer is one of the best units to build along
with the submarine... if you spam a whole ton of subs, you can win an entire
water battle unless the enemy has T3 hovers."

`response.json` explains it. `anti_sub` was zeroed on every field:

    "anti_sub": { "vs": ["sub"], "ratio": [0.0], "importance": [0.0],
                  "max_percent": 0.00, "eps_step": 0.00 }

against stock BARb's `ratio 0.8, importance 5.0, max_percent 0.30`. And the
`"sub"` entry stock ships was **absent from our config altogether**. So the AI
had no response to enemy subs and no reason to build subs of its own. This dates
to the original apex import (`9d04b5a`), not a recent regression -- it has been
off the whole time.

The roles exist and are wired: `armroy` (Corsair, T1 destroyer, 880 metal) is
`anti_sub`, `armsubk` is `anti_sub`+`sub`, with Legion equivalents in
`behaviour_leg.json`. `response.json` is shared across all three factions, so
one fix covers faction parity.

Now `anti_sub` ratio 0.9 / importance 500 / max_percent 0.45, and `sub` restored
at ratio 0.6 / importance 300 / max_percent 0.6 -- above stock's 5.0 importance
because both units stay relevant well past T1.

Both are demand-driven (`vs` gates on enemy roles present), so neither can fire
on a land map. Unmeasured beyond "no config errors, no script errors".

### The overlay vanished because BAR erases map marks after 60 seconds

`luaui/Widgets/map_auto_mapmark_eraser.lua` ships with `eraseTime = 60` and
deletes every mark 60 seconds after it appears. So the previous commit's
"draw chokepoints once" was exactly backwards -- the layer disappeared a minute
in, which is precisely what was reported. Chokepoints are redrawn every pass
again. That widget also means marks CANNOT accumulate, so the 21,000-stale-lines
worry in that commit was wrong; the erase bookkeeping is now belt and braces.

The front lines were missing for a different reason: `Draw` only draws FRONT
cells, and FRONT requires `gFoeKnown`. Each AI's influence map holds only what
that AI knows, so if the single drawing AI is a rear player that never sees
anyone, the overlay is empty all game. The enemy bearing is now pooled across
the team over the blackboard (`apexFoeX/Z/W`), weighted by sighting count, so a
forward teammate's contact gives everyone behind them a real front.

## 2026-08-07: front vs back, and the front starts UNKNOWN

apexearth on the undirected perimeter: "the perceived frontline is behind us,
not even facing the enemy, its also too small so we have obvious gaps... the
front line is really where our territory ends and the enemy's territory is about
to begin... you might say in the beginning of a game the frontline is completely
unset / unknown."

Two errors, both fixed:

- **Too small, with gaps.** Territory was thresholded at 15% of peak ally
  influence, which selects the dense CORE. Its edge therefore sat behind our own
  army. Territory is now 3% (~15 against a ~520 peak) -- everything we
  meaningfully hold. Perimeter went from ~30 patchy cells to ~100 wrapping the
  whole territory.
- **Behind us.** A ring has no direction; half of any ring faces our own rear.
  The ring is now split against the bearing from our territory centroid to the
  enemy centroid: FRONT faces them, BACK is the fog behind us. Measured on Jade
  8v8: ~53 front / ~47 back of ~100.

Enemy position is REMEMBERED, not sampled (`gFoeSeen`, +1 per sighting, 0.995
decay per scan). Enemy influence only holds units currently known, so a raid
that passes through vanishes seconds later -- but the fact their territory lies
that way does not stop being true. Without the memory the bearing flickered.

**The front is UNKNOWN until an enemy has been seen**, and says so rather than
guessing: 240 of 673 samples in one game had foeKnown=0 (early game, and rear
players who never see anyone). `Front::IsFrontKnown()` exposes it; `FrontNear`
returns false rather than inventing a direction.

Overlay draws map LINES, not points. Points are pings -- each one fires an alert
and a minimap flash, unreadable at this density.

### Deploys keep failing silently while a game runs

Three deploys this session did nothing because a watch game held the files;
`cp` said "Device or resource busy" and the game-side script kept old code. Two
headless runs then reported on stale files. The deploy step now aborts if a
spring/Beyond-All-Reason process exists, and the deployed FILE is grepped for
the change rather than trusting deploy's exit.

Also walked into two documented traps again: a `str.replace` without an assert
silently did nothing, and `out` is a reserved AngelScript keyword (32 compile
errors, which disable the whole variant while the match still reports normally).

## 2026-08-07: the front is our own perimeter, not a seam

Three definitions of "front line", each killed by measurement, in order:

1. **Cells where both sides are present.** Found nothing. One Jade 8v8 scan had
   339 ally cells and 56 enemy cells and **zero** holding both -- where one side
   is strong the other reads ~0, so the fields are effectively disjoint and an
   overlap test only fires where both are so faint it means nothing.
2. **Cells on the boundary between the two fields.** Found 2-3 cells. Enemy
   influence counts only KNOWN enemy units, so it is far too sparse to draw a
   line with.
3. **The outer edge of our own influence region.** 102-112 cells spanning
   x3072-12492, z1843-7987 -- a real perimeter across the map. Needs no vision,
   exists from minute one, and is what a player means by their front: the edge
   of what we hold. Perimeter cells adjacent to known enemy influence are marked
   HOT; the rest is quiet flank that still has to be held.

**The two fields are not on the same scale.** Ally influence counts everything
we own and peaks around 520; enemy influence counts only what we have seen and
peaks under 33 in the same scan. An absolute presence floor of 5 erased the
enemy field completely -- every AI read cFoe=0 for an entire game -- so the
front vanished instead of moving. The floor is now 1.0 and the per-side
fraction does the work.

**Deploys fail silently while a game is running.** Two deploys during a watch
game did nothing; `cp` of the DLL reported "Device or resource busy" and the
game-side script kept the old code. Two headless runs then "tested" stale files
and produced results I nearly believed. Always confirm the deployed file
contains the change, not just that deploy exited.

Also: a `str.replace` without an `assert` silently did nothing, again, which is
what put a call to the non-existent `ai.GetTeamPos()` into a file that then
appeared to deploy fine.

## 2026-08-07: the front line is not at the chokepoints

Step 2 of the front-line work: classify each chokepoint ours/contested/theirs
against the influence map. It produced a result that invalidates the plan it was
part of.

Influence is now bound to script (`GetAllyInflAt`, `GetEnemyInflAt`,
`GetNetInflAt`), bounds-guarded -- `CInfluenceMap::PosToXZ` does NO bounds check
and indexes `enemyInfl[z * width + x]` straight from the raw position, the same
unchecked pattern that made `GetBuilderThreatAt` kill the engine at frame 3.

**Classify on ally and enemy separately, never on the difference.** Net influence
reads 77 beside our base and exactly 0 on ground nobody has been near, so a
difference-based test calls both "balanced" -- and most of the map is the second
kind. A seam requires BOTH sides present.

**Terrain chokepoints are not where the fighting is.** Jade Empress 8v8, 63
usable chokepoints:

| | |
|---|---|
| chokepoints ours | 23-36 |
| chokepoints contested | **0** |
| chokepoints theirs | **0** |
| influence-grid cells with BOTH sides present | **55-77** |

The contest is real and none of it lands on a chokepoint. BWEM chokepoints on
these maps are base entrances and interior pockets; the fighting happens in open
ground. Comet Catcher is the same story -- its 8 chokepoints sit at 6584,392 and
1048,4632, i.e. the two start corners.

So holding chokepoints would mean turtling at our own base entrance, which is
the opposite of a forward line. The front line is now read off the influence
field directly (`Front::SeamNear`), with chokepoints kept as a SECONDARY filter:
`Front::SeamChoke` returns a seam cell that also sits in a corridor, which is
the best metal-per-tower on the map when it exists, and returns false when the
front is in open ground -- the common case.

**Each AI has its own influence map.** Same game, same moment, on Jade: forward
teams read 72-82 enemy cells and a 55-77 cell seam; rear teams read cFoe=0 and
no seam at all. A rear player computing this alone concludes there is no front
line. Anything consuming the seam must share it across the team via
PublishTeamValue/ReadTeamValue rather than trust the local read. This cost an
hour of chasing a "seam=0" that was really a sampling artifact -- an `awk`
stride that happened to lock onto one rear team.

Also bound: `DrawPoint`/`DrawLine`/`DrawErase`, which place ordinary in-game map
markers via the already-present `springai::Drawer`. `Front::DRAW` is currently
**on**, drawing every chokepoint with its ownership and every seam cell as
FRONT. Allies and spectators see these -- turn it off before multiplayer.

No behaviour change yet: nothing consumes the seam.

## 2026-08-07: BWEM chokepoints exist, and were unreachable

CircuitAI vendors a full BWEM (Brood War Easy Map) implementation in
`circuit/map/GridAnalyzer.cpp`: every game it decomposes the map into areas
joined by chokepoints, with geometry, width and area adjacency. **Nothing could
read it.**

`CDefenceData::Init` pushes every chokepoint into `defPoints`:

    for (bwem::CChokePoint* ch : terrainMgr->GetTAChokePoints())
        defPoints.push_back({ch->GetCenter(), .0f});

but every consumer selects through `GetDefIndices(clusterIndex)` ->
`clusterInfos[k].idxPoints`, which is populated ONLY by the metal-cluster loop.
No cluster ever references a chokepoint index. The one path that could have
reached them -- a `knnSearch` over the whole `defPoints` tree -- is commented out
in `CDefenceData::GetDefPoint` behind `FIXME: Re-work cluster-only points into
search-tree`. `MilitaryManager.cpp:753` holds a second, also commented-out,
chokepoint block. Upstream built the analysis and left it unwired.

**Consequence: every defence position this AI has ever placed was anchored to a
metal cluster.** That is why defence reads as "towers around bases and mexes"
and never as a front line, and it is the likeliest reason ~9 attempts at
geometric wall/front-line placement all failed -- they were interpolating lines
with `BorderPos`/`FrontPos` while the real corridor topology sat unused.

Exposed read-only to script (no behaviour change): `GetChokePointCount`,
`GetChokePointPos`, `GetChokePointWidth`, `GetChokePointEnds`,
`GetChokePointArea`. Width is recomputed as `|end1 - end2|` because
`CChokePoint::size` is private and only `IsSmall()` (< 300) is public.

Verified returning real data, not the `Game_getTeamResource*` failure mode:

| map | chokepoints | usable (200-2000 wide) |
|---|---|---|
| Comet Catcher Remake (16x12) | 8 | 5 |
| Jade Empress 1.41 (32x32) | 100 | -- |

Jade's widths run 22 to 2806; most of the 100 are sub-200-elmo slivers between
interior areas, so the raw count is not the usable count. Area ids form a real
graph (1/2, 1/3, 5/6, 11/12, ...), which is what a "which corridor do enemy
reinforcements flow through" query would run over.

Not yet used by any behaviour. Next: classify each chokepoint ours/contested/
theirs against the influence map, then anchor defence to contested ones, then a
hold task that does not promote itself into an attack.

## 2026-08-07: constructors no longer pre-empt themselves into reclaim

`AiMakeTask`'s tail handed EVERY idle non-commander builder a wreck reclaim
before returning. Per the code's own `REZ_WRECK_PERIOD` comment, ordinary
constructors already get a RECLAIM offer from `DefaultMakeTask` (isResurrect is
false for them), so this path never ADDED reclaim -- it jumped the queue ahead of
the mex expansion that lives in `DefaultMakeTask`. Now rez-bot only; they still
need the pre-empt because for them the engine's offer is a 300s RESURRECT.

Motivating measurement, one 8v8 on Jade Empress 1.41 (32 min, no control):

| | Apex | BARb hard |
|---|---|---|
| mexes | 233 | **394** |
| T2 mexes | 25 | **44** |
| metal produced | 293k | **485k** |
| metal reclaimed | **13.8k** | 8.9k |
| killed / lost | 60k / 122k | 106k / 86k |
| PEAK constructor metal | 17,770 | **59,275** |

We were already out-reclaiming BARb 1.5x while falling 161 mexes behind. Mex
counts are level to minute 8 (83 vs 87) and diverge from 14 on (133/151, 186/248,
217/319, 233/394) -- we do not lose the expansion race early, we stop expanding.
A 0.49 trade ratio on 60% of the enemy's economy is about what the economy alone
predicts, so this is a candidate root cause for the long-standing K/D deficit
rather than a separate problem.

One game, no control. Unverified as an improvement -- the change is a REMOVAL,
which per the "path fires" section is the cheap kind to try and revert.

## 2026-08-07: RESULTS BELOW WERE VOID -- read this first

**Every tournament result in the section below was measured against a BARb with
no AI script, and is meaningless.** Kept, struck through, because the failure
mode is worth more than the numbers were.

Cause: `deploy_ai.py`'s stale-cleanup deletes `BARb/<variant>` to remove old
version-style deploys. `variant` is also the VERSION, so deploying a variant
named `stable` resolved that to `BARb/stable` -- the baseline -- in BOTH halves:
the engine-side folder AND `BAR.sdd/luarules/configs/BARb/stable`. The
engine-side half was noticed and restored from `files.md5.gz`. The GAME-SIDE
half was not, and that is where stock BARb's `hard`/`medium`/`easy` profile
scripts live. Engine-side ships only the `dev` profile.

So from that point on, `BARb:stable:hard` and `:medium` loaded, logged
`Game-side script: 'LuaRules\Configs\BARb\stable\script\hard\init.as' is
missing!`, and then did nothing. Commanders stood still all game.

**This reads exactly like a triumph.** 16-0 on every faction, 8-0 at 8v8 on the
configuration that had gone 0-8 hours earlier, games "won" in 19 minutes instead
of 40. Every one of those numbers is an artifact. The 19-minute games were not
fast wins, they were walkovers against a corpse.

What survived:
- The **0-8** 8v8 result from BEFORE the deletion is real.
- Both self-play A/Bs (`Apex` vs `ApexCtl`) are unaffected, since both sides are
  ours -- and both said the new strategic work does NOT help: 11-13 and 9-11.
- With BARb restored and verified (0 missing-script errors, 363 AI log lines vs
  12, army 18,470 vs 17,790 over a full 20 min), we are roughly EVEN with BARb
  hard, not dominant.

Detection: an AI that loads but never acts logs almost nothing. BARb produced 12
lines across a whole game against apex's 851. `tools/feature_audit.py` reports
per-game coverage and would have caught this instantly had it been pointed at
the OPPONENT rather than only at us. Check the opponent is alive before believing
a win rate -- a walkover and a triumph are the same number.

## 2026-08-07: the aggression session (RESULTS VOID, SEE ABOVE)

Measured after the night's batch, all on engine `recoil_2026.07.04`:

| test | result |
|---|---|
| 4v4 vs `BARb:stable:medium`, Cortex | **16-0** |
| 4v4 vs `BARb:stable:medium`, Armada | **16-0** |
| 4v4 vs `BARb:stable:medium`, Legion | **16-0** |
| 8v8 vs `BARb:stable:hard`, Supreme Isthmus +40% | **8-0** |

The 8v8 number is the one that matters: **the identical configuration went 0-8
earlier the same day**, and games now end around 19 minutes instead of running
to the 60-minute cap. Legion, historically the weak faction at ~40%, is level
with the others.

Two causes, both found by reading a real multiplayer game's infolog rather than
the benchmark:

- `ENGAGE_MARGIN` was 1.80, i.e. we demanded 80% more power than whatever
  defended a target. In one live game: 492 engage decisions, **3,973 candidate
  groups refused as too strong**, and `edge=0.00` on every sample -- meaning the
  target finally accepted had no defenders at all. The AI was refusing every
  real fight and attacking empty ground. Now 1.35.
- `quota.attack` was restored to stock BARb's value after the rush window --
  **15**. From mid-game on, only fifteen units per player could ever attack, and
  slots filled first-come so a T3 unit finished later never got one. Now
  `LATE_ATTACK_QUOTA = 200`, so the odds test decides who fights instead of an
  arbitrary cap.

**Do not read these as "the AI is solved".** Every one of these games is against
another AI. The whole reason this batch exists is apexearth's observation that
BARb is not the right measure, because humans punish timidity in ways BARb never
does. A 16-0 against medium mostly says the build is not broken.

### Self-play A/B, and what it does NOT show

`ai/ctl` is a frozen copy of the build above, deployed as shortName `ApexCtl`,
so later changes can be A/B'd by self-play instead of against a win rate already
saturated at 100%. First use, 12 games Cortex 4v4, new build (juggernaut charge
+ `AIR_FROM` 11 min) against it: **9-3, 75%** -- but the 95% CI is 47-91%, which
includes 50%. That is suggestive and **not** a demonstrated improvement. Twelve
games cannot resolve an effect this size; it needs ~40 to separate from noise.

### The juggernaut charge is UNVALIDATED, and the benchmark cannot validate it

Built, compiles, and has a log line (`apex: juggernaut charge`) specifically so
it can be observed. Across 8 games of 8v8 vs hard it fired **zero** times -- for
a reason that is not a bug: **no juggernaut-class unit was ever built**. Two
gantries total, and a 19.1 min median game length. A corjugg is 20,000 metal;
the games end long before one exists, *because the AI now wins quickly*.

So this feature is unreachable in the current benchmark, and no amount of
running it will say anything. Validating it needs a scenario with a much longer
game or a pre-seeded T3 force. **Do not tune it from benchmark results** -- there
are none, and there will not be any.

### Feature coverage, measured

`tools/feature_audit.py` reports which strategies actually fired. Every feature
that can fire under some condition has now been seen firing in at least one:
eco lead (8/8 at 8v8 only -- it is off under 6 per side by design), air strike
(8/8 at 8v8, 14/16 Legion, 7/16 Cortex -- it needs game length to mass), T3
gantry (11/16 Legion), rich-wreck reclaim (8/8 at 8v8), tech-lead handover (3/8,
72 fires -- a behaviour that did not exist before the latch fix).

Two remain unvalidatable here and are annotated in the tool: `cheap AA` (BARb
medium builds no air at all -- confirmed, every air unit in those 16 games was
ours) and `commander retreat` (nothing ever threatened our commander; **zero**
commanders lost across the 8 games vs hard).

Status column below: **measured** = validated in a clean run; **unmeasured** =
implemented and smoke-tested only; **suspect** = measured under conditions later
found invalid.

---

## C++ / SkirmishAI.dll

New bindings in `vendor/engine/AI/Skirmish/BARb/src/circuit/`. The DLL is rebuilt
from source and stripped; see `docs/06-building-the-dll.md`.

| binding | purpose | status |
|---|---|---|
| `ai.SendResources(m, e, team)` | give metal to an ally — makes slinging possible at all | measured |
| `ai.GetTeamMetalIncome(team)` | ally income, for ranking the tech lead | measured |
| `ai.GetBestWreckPos(pos, r, min)` | richest wreck nearby, so reclaim is *valued* | measured |
| `ai.GetBuilderThreatAt(pos)` | per-position danger from the engine's `CThreatMap` | drives the constructor build-site veto; **unmeasured** |
| `CCircuitUnit::CmdMoveTo(pos)` | raw move order, outside the task system | **not called** |
| `ai.GetEnemyCostAt(pos, r)` | enemy count in radius | **not called — unsafe** |
| `aiEconomyMgr.FindOpenMexSpot(unit, pos)` | nearest open metal spot, using the guards `UpdateMetalTasks` applies | measured |
| `aiEconomyMgr.GetMexSpotPos(spotId)` | validated spot position, `-RgtVector` when invalid | measured |
| `aiEconomyMgr.EnqueueMexAt(unit, spotId)` | the only MEX enqueue carrying a real `spotId` | measured |

**measured**: 46 `con-reroute spot` events in one 40-minute 4v4, each moving a
constructor off a vetoed site onto a spot the threat map read at 0.

### `SQUAD_SPEED_RATIO` 2.5 -> 3.5 — `AttackTask.cpp` — tuned on one Cortex pair, verified to fail for Legion

2026-08-05. `CAttackTask::CanAssignTo` gates squad merging on
`speedSlower * SQUAD_SPEED_RATIO >= speedFaster`; below that, the slower unit
is refused and fights alone. The constant was 2.5, chosen to just admit one
specific Cortex pair (Banisher 54 / Mammoth 22.5 = 2.4) -- faction-specific by
construction, since it was never checked against the other two factions.

Checked directly: Legion's comparably-common T2 pair, `legstr` (84 speed) and
`leginc` (24 speed, weighted up to 0.38 of `legalab`'s build share at some
income tiers -- not a rare unit), has a natural ratio of 3.5 and failed the
old 2.5 gate outright. `leginc` could never merge into a squad with its own
faction's fast T2 escort and fought alone every game, in exactly the T2-tier
window (~minute 14+) where a separate data-driven finding this session showed
Legion's combat trade starts eroding.

**Fix**: raised to 3.5, the minimum that admits the Legion pair, chosen after
checking it doesn't also swallow the genuine outliers this constant is meant
to exclude (Cortex's T3 superheavies at ~16.5 speed need 3.3+ and sit right at
the new boundary; scouts like `legscout` at 160 speed need ~6.7 and stay
excluded regardless).

Rebuilt (`ninja -C build-amd64-windows BARb`), smoke-tested clean on all three
factions (0 compile errors, correct script loaded, no crash). **Not yet
confirmed by tournament** -- this needs a large (64-96 game) solo batch per
faction before trusting a win-rate effect, per this session's own
hard-learned lesson about this benchmark's noise floor (see
`notes/open-issues.md` #45-52). Patch captured in
`game-patches/circuitai/0003-cumulative.patch`.

### Commander killer logging — `CCircuitAI::UnitDestroyed` — REVERTED, crashed

2026-08-04. This session had no way to see WHAT kills a commander -- the
AngelScript-side `AiUnitRemoved` hook (added the same session, see
`ba92167`) can log THAT and WHEN, but the attacker (`CEnemyInfo*`) is only
available in C++ and is not exposed to script. Added four lines in
`CircuitAI::UnitDestroyed`: if the destroyed unit `IsRoleComm()`, log the
attacker's unit name and 2D distance (or "UNKNOWN (no attacker)" if none --
env damage, self-destruct, capture).

**REVERTED.** A 4-game and an 8-game smoke test both came back clean
(`exit_code=0`, `crashed=false` on every game), which is why this was
believed safe and committed. A follow-up 16-game batch, collected purely for
more diagnostic data with no further code change, hit a real crash: access
violation (0xc0000005) inside `SkirmishAI.dll`, at the exact frame of a
`[BARAI_COMMLOST]` event -- 1 game in 16 (6.25%). Stack trace frames 0-2 are
inside our own DLL. Most likely cause: `attacker->GetCircuitDef()->GetDef()`
returning null in some circumstance this session did not characterise (a
simultaneous-death edge case, or a `CEnemyInfo` whose def was never fully
resolved), then `->GetName()` on that null pointer. Not root-caused with
confidence, and every further test costs a rebuild + multi-game batch to
even have a chance of reproducing the specific edge case, so the change was
fully reverted rather than patched blind. Source reverted in
`vendor/engine/` (gitignored, not visible as a diff here), DLL rebuilt from
the reverted source and redeployed, confirmed crash-free again over 4 games.

**Two lessons for a future attempt at this exact idea:**
1. **A handful of clean smoke-test games is not proof of safety for an event
   that only fires on death of a specific unit type.** A commander death is
   comparatively rare per game (this session's own data: roughly 2-4 per
   game), so a 4-8 game sample may simply not hit whatever specific
   circumstance triggers the crash. This is the same lesson `docs/`/CLAUDE.md
   already states for the AngelScript layer ("An AngelScript compile error
   disables the whole variant, and the match still runs") applied to C++:
   absence of an observed failure in a small sample is not absence of a bug.
2. **Null-check every pointer in the chain before dereferencing**, even ones
   that look like they should always be valid from the call site's contract
   (`attacker != nullptr` was checked; `attacker->GetCircuitDef()` and
   `->GetDef()` were not).

The killer-type data collected before the crash was found is preserved below
since it remains real data from real games (just from a build later proven
unstable in a way unrelated to the LOG call's own correctness under normal
conditions) -- read it as suggestive, not as settled.

**CORRECTED below -- the first read named `corthud` as artillery from the
name alone, the exact mistake `docs/`/CLAUDE.md warns about. Verified with
`tools/unitdef.py` before writing this version.**

**Read across two batches (4-game smoke + 8-game confirm, n=29 kills, 12
games total) — grep `apex: commander killed by`:**

| killer | count | mean distance | what it is |
|---|---|---|---|
| `corthud` "Thug" | 8 | 307 | Light Plasma Bot -- direct fire, medium range |
| `corban` "Banisher" | 7 | 575 | Heavy Missile Tank -- real ranged skirmisher |
| `corraid` "Brute" | 4 | 236 | Medium Assault Tank -- direct fire, close range |
| `corsumo` "Mammoth" | 3 | 498 | Heavily Armored Assault Bot |
| `corape` "Wasp" | 2 | -- | Gunship (air) |
| `corstorm`/`cormist`/`corllt`/`corlevlr`/`corcan` | 1 each | -- | mixed |

No single cause. Regular direct-combat units (`corthud`, `corraid`, `corcan`)
account for 13 of 29 kills (45%), a mixed group of ranged/heavier units
another chunk, and 2 kills came from the air -- not something the commander's
ground-based retreat logic can out-walk regardless of health threshold. The
one real pattern: `corban`'s mean kill distance (575) is roughly double
`corthud`'s (307) and `corraid`'s (236), consistent with it landing the
finishing hit from beyond where the commander perceived itself as clear of
the fight, which fits the burst-death pattern already found in
`notes/open-issues.md` issue 0.1 (a commander healing steadily at 84% health
dying within 2.4 seconds of the next sample). But this is one plausible
contributor among several causes, not a single dominant one -- do not act on
"cap corban's range" or similar as if it were the whole answer.

**This C++ source change lives in `vendor/engine/` only, which is
gitignored** (`.gitignore:2`). It is not visible as a diff in this repo's
history -- only the resulting `ai/apex/engine-side/SkirmishAI.dll` binary is
committed. A future session reading git log for this DLL's C++ provenance
will not find it there; this note is the record. The local
`vendor/engine/` clone is itself persistent on this machine (per
`docs/06-building-the-dll.md`, "the tree is already cloned, patched and
configured"), so the actual source edit does survive across sessions here,
just not in git.

### Mex-spot indexing was an out-of-bounds write

`CBMexTask`'s constructor calls `SetOpenMexSpot(spotId, false)`, which indexed
`mexSpots[spotId]` with no bounds check, and `TaskB::Common` leaves that field at
`-1` (it aliases `pointId` in a union). Script could not safely enqueue a MEX
task at all. `mexSpots` is also sized in a deferred `Init()`, so before that runs
every id is out of range.

Guarded at the leaves — `CEconomyManager`'s mex/geo spot accessors and
`CMetalManager::IsOpenSpot`/`SetOpenSpot`/`GetCluster` — rather than at the call
sites, so the hazard closes for every caller. `SetOpenSpot` separately indexed
`clusterInfos[clusterId]` with a `clusterId` that is `-1` until clusterization
assigns it; that write is now guarded too.

Upstream bug found in the same pass: `CBMexTask::Reevaluate` set `spotId = 0` to
"prevent spot opening on Cancel", but `Cancel` guards on `spotId >= 0`, so `0`
passed and re-opened spot 0. Now `-1`.

### `FindFacing` orients on the enemy, not the map centre

`IBuilderTask::FindFacing` picked facing purely geometrically, facing the centre
of the map. `BuildPos` rotates `build_chain.json`'s `front` offset by that
facing, so every front-offset placement — flak, defences, nanos — pointed at the
map centre regardless of where the threat was. It now uses
`CEnemyManager::GetEnemyPos()`.

`enemyPos` initialises to the terrain centre, so before an enemy is located the
new code reproduces the old behaviour exactly. **unmeasured** — it compiles and
runs clean for 40 game-minutes on a hot path, but no placement outcome has been
measured against stock.

`ai.GetTeamMetalFill` also exists but returns nothing useful; see the engine bug
note in `CLAUDE.md`.

**Do not call** the last two. `GetEnemyCostAt` crashed the AI, and commander
retreat via `CmdMoveTo` correlated with the engine aborting 14-17 games per
20-game run. Both are registered but unreferenced.

## AngelScript (`script/hard_aggressive/`)

### BUILD_PHASE gate on the optional economy/AA cluster — measured, confirmed

2026-08-04. `docs/12-build-phases.md` (apexearth's design) diagnosed the
recurring failure behind a long run of negative isolated-spend experiments
this session (heavy AA in three forms, eco-for-everyone, advanced-con
priority, cornecro cap — all measured worse or neutral, see
`notes/open-issues.md` "SESSION SYNTHESIS"): every one of them claims
constructor time, which is the actual scarce resource, and something else
— usually army — pays for it. `Factory::ComputePhase()` (a diagnostic added
the same session, driven from state — mex count, `gHaveT2`, fusion count,
gantry presence, `RushReady()` — never a clock, so it falls back down on
its own if a signal drops) made it possible to test the design's own fix
directly: defer a CLUSTER of optional investment rules together, rather
than one at a time.

`AiMakeTask` (`builder.as`) now gates `CheapAA`, `HeavyAA`, `Pulsar`,
`EcoConverters`, `EnergyConverter`, `EcoNano` and `EcoFusion` — the exact
block a standing comment in this file already named as the historical
danger ("Twelve rules pre-empting here... cut metal production 4.3x") —
behind a `Factory::gLastPhase` threshold. The reflexive `RepairNear`
(con-heal) rule stays ungated, per the design's own phase-gated-investment
vs never-gated-reflexive split.

Three thresholds tried, each against the established 7.9% baseline
(95% CI 3.9%-15.4%, n=89):

| threshold | meaning | decided win rate | games run to the full time limit |
|---|---|---|---|
| `phase >= 2` | `mex >= 4` | 0% (0/13) — reverted | typical |
| `phase >= 3` | `RushReady()`, economy can afford to tech | 22.7% (5/22), P=0.0260 | ~70% |
| `phase >= 4` | `gHaveT2`, an advanced factory actually finished | **60.0% (6/10), P=0.00004** | **~87%** |

**`phase >= 4` is what shipped.** `mex >= 4` was too early to matter;
"the economy could afford to tech" (phase 3) still isn't the same test as
"it actually has" (phase 4) — CheapAA/HeavyAA/Pulsar/the eco block were
still competing with the mex-upgrade and factory-building work that gets a
player TO T2 in the first place, right up until phase 3's bar. Gating
until the advanced factory is actually standing removed that competition
at exactly the point that mattered. Most games under this gate now run the
full 25-minute time limit as genuinely competitive draws rather than being
decided either way — a second, independent signal alongside the win rate
itself.

This validates the design's core claim directly: resolving competition
across a CLUSTER of rules together, not tuning or gating any one of them
alone (five prior isolated-spend experiments this session all failed for
exactly that reason), is what moves the outcome — and getting the
THRESHOLD right, per the design doc's own "hardest part" section, mattered
as much as the mechanism itself. **Still not statistically proven
"reliable"** at n=10 (the 95% CI's lower bound, 31.3%, is real progress but
not yet a guarantee) — worth a larger confirmation batch before treating
60% as settled.

**Not yet fully explored**: whether an even higher or lower threshold does
better, whether more rules (`ConDugIn`/`Fortify`) belong in the gated
cluster, and whether the same pattern holds on other maps/handicaps. The
design doc's own "hardest part" section (calibrated transition conditions,
not the phase concept) remains the open work.

### Team tech coordination — the core of both variants
- **One designated tech lead**, chosen by **commitment**: whoever is building an
  advanced plant, and when two are, whichever plant is nearest done. Nanoframes
  count and the fractional build progress is the tie-break. Stock has no team
  coordination at all — each instance decides alone.
  **The election runs in the AI, over an in-process blackboard** — not in synced
  Lua, and not on income. Synced Lua cannot ship to a hosted multiplayer game;
  every AI the host adds shares one process, so the instances read each other via
  `PublishTeamValue`/`ReadTeamValue`. **measured**: with the released archive and
  no gadget present, all four instances elected the same lead within four frames
  and it never flapped across 20 minutes.
  It once ran per-instance on the assumption that identical synced inputs give
  identical answers; they do, but the *read instants* differ (SlowUpdate is
  offset by `skirmishAIId`), and 1 archived match in 533 elected two leads. The
  property that fixed it is kept — **one writer**: the lowest team id in the ally
  roster elects and publishes, everyone else only reads that slot.
- **The lead is replaced if it loses its plant**, and the title stops moving
  entirely past `RUSH_GIVEUP`, so the lead stays tech lead after sharing ends.
- **The commitment rule deadlocks against the follower gate unless the gate is
  conditioned on a lead existing.** The gate forbids any non-lead from starting a
  T2 factory before `FOLLOWER_TECH_FRAME`; if the lead *is* whoever started one,
  nobody may start, so nobody leads, so nobody may start. **measured**: first
  election at 10.5 min in two runs — the exact frame the gate opens — against a
  5.7 min baseline; gating on `LeadIsDesignated()` moved it to 6.9 min.
- **Slinging**: followers send 450-metal lumps to the lead, keeping 220, from
  5 min until they receive their own advanced constructor.
- **The whole strategy is abandoned at 15 min** (`Military::RUSH_GIVEUP`).
  Pooling is a bet -- the team runs poor and the lead runs armyless -- so if T2
  has not landed by then it has lost, and continuing compounds it. Slinging, the
  rusher's factory pre-emption, the T1-lab reclaim and both suppressed attack
  quotas all stop, and play reverts to stock. **measured**: all release paths fire
  at 15.0m and restore quota.attack to the stock 15.
- **The lead techs on zero bank**: stock requires `0.5 x plant cost` banked,
  which is never reachable. It places the plant and pours income in.
- **Followers get the same no-bank switch** once past 13 min — and **only one
  advanced plant each**.
- **Advanced plant matches the opening factory**: T1 bot lab → T2 bot lab,
  vehicle → vehicle. Stock forced a vehicle plant a bot lab cannot build.
- **The lead reclaims its own T1 lab** into the plant it replaces.
- **Advanced constructors are shared**, one per teammate. Big teams pre-empt the
  factory line to do it; small teams do not (measured: pre-empting cost 3-13).
- **The tech lead never opens air**, and on teams under 6 **nobody** does.

### Killing blow — dominance that actually ends the game
Measured baseline: across 30 games on 8 maps, **20 (67%) hit the time limit
undecided**, and on Quicksilver we finished 16 games holding 4.5x stock's metal,
35x its T3 and 8.5x its army with ELEVEN unresolved. apexearth: "we are often
winning but we're very slow to kill enemies ... we need some sort of switch which
says ok now go for the killing blow."

Past 15 minutes, once OUR TEAM's army is worth 1.8x the enemy's, the attack
minimum drops to 10, any turtle hold is released, and both massing and turtling
are stopped from re-engaging. Hysteresis at 1.5x so one lost fight does not flip
it mid-push. The eco lead is exempt -- it holds no army by design.

`quota.attack` is a MINIMUM before the engine forms an attack, and UpdateMassing
walks it to MASS_CAP and pins it there whenever the enemy out-values us. Once far
ahead that gate is pure delay: we sit on an army several times their size waiting
for a bigger one.

**measured**: undecided games **67% -> 17%**, records of 4-2, 5-0 and 3-2 across
three 6-game 4v4 sets; one watched game on Supreme Isthmus won at 28.9 min where
both baseline games there ran out the 50-minute clock undecided.

Two bugs on the way, both worth remembering:
- The first version compared `aiMilitaryMgr.armyCost` (ONE player) against
  `EnemyArmyCost()` (the WHOLE enemy side) -- "is one of us worth more than all
  eight of them", which read 3.6 AGAINST us in a game we were dominating. Team
  army is now pooled over the blackboard. Same shape as `LosingGround()` being
  permanently true for a player with no army.
- At 2.5x it first became true at 36.8 minutes of a 50-minute game. A switch that
  only flips once the win is overwhelming does not address winning slowly.

### Air eco-assassination — it never once fired before this
The strategy was written, armed, committed, and built **0 bombers and launched 0
strikes** across every measured game. apexearth: "I only saw something akin to it
once in dozens of games." Four separate breaks, each invisible in the numbers:

- **Its factory request sat LAST in `AiGetFactoryToBuild`**, below the bot lab,
  gantry, tech rush and navy branches, all of which return first. 133 of 134
  status samples read `plants=0,0 cons=0 want=corap` -- it asked every time and
  was never reached. Moved above them.
- **Nothing built the air constructor.** `MakeFactoryTask` answered only for the
  ADVANCED plant, but `FactoryToBuild` will not ask for that plant until an air
  constructor exists -- and the only plant we owned was never told to build one.
- **The income bar was self-defeating.** Elected at 63 and 81 metal/s, by which
  point enemy anti-air was over the ceiling, so it never armed. The premise is
  surprise; waiting for a bigger income waits for the enemy to build the counter.
  60 -> 40.
- **Both defs were advanced-tier**, so the force could not start until a plant
  that rarely finished. The basic tier is a third of the price -- armthund 145
  and armfig 73 against armpnix 230 -- and `Bombers()`/`Fighters()` now count
  both tiers.

**measured**: chain completes 6/6 and the strike **releases in 6/6 games**, at
enemy anti-air of 0-2,351, with one stand-down. Aircraft are genuinely held:
`HoldsUnit` makes `Military::AiMakeTask` return null for them, leaving them idle
where built until Release, which then grants ANTI_STAT (target economy, skip
army) and SetRetreat(0).

**Still open**: strikes release on the DEADLINE path at exactly the half-mass
floor -- 6 bombers and 4 fighters -- because the deadline passes before
production reaches it, so the floor becomes the ceiling. `Priority::NOW`, a
second plant, assist while massing and batch-6 orders did NOT move it (still 6/4
in 6/6 games), because the advanced plant rarely completes and the second-plant
branch was gated on it.

### Resurrection — stock was rebuilding its army and we were scrapping ours
apexearth spotted it and named the confound himself: winners hold rez bots
BECAUSE they won. The timeline settles direction, and it was not survivorship.

**measured**: over 6 games stock spent 21,460 metal a game resurrecting to our
10,396; in one watched 8v8 it was **32,890 to our 436**, one stock player's
single largest sink of any kind was `cornecro` at 17,940, and `armrectr` appears
**zero times** in our entire log. Meanwhile we out-RECLAIM them 2:1 -- we win the
metal accounting and they win the units back.

Rez bots come only from a bot lab (`armrectr`/`cornecro`/`legrezbot`, 130 metal);
the vehicle plant and advanced plant cannot build them, and our side ran about
four vehicle plants per bot lab. Bot labs now come at 8 minutes rather than
waiting for T2 or 13 minutes, and a floor of 4 rez bots is built ahead of
anything else that lab would make. Requested BY NAME: these route through
`UseAs::REZZER` but their config roles disagree across factions ("support" for
Armada and Legion, "rezzer" for Cortex), so `GetRoleDef` is not reliable.

**measured**: rez spend **10,396 -> 18,053**, against stock's 12,104 -- reversed.

### Reading a game: `tools/report.py`
One command, fixed order: script errors, did-it-fire counts, a 2-minute timeline
per side with divergence points, then the outcome. It exists because three
verdicts in one session came from the wrong slice -- a team effect called at 6 of
8 games that reversed at 8; a cause read off the FINAL snapshot of a collapsing
side when the timeline showed the sides level on mexes until minute 12; and a
feature reported "never fired" from a regex that did not match the log line, in
the tool built to prevent exactly that. When a feature reads 0/N, grep the source
for the log string before believing it.

### Eco lead — one player builds economy and nothing else
apexearth: "one player who focuses mostly on building up a strong eco so that
they can reach the late game as soon as possible. They don't make army unless
endangered or our allies are dying." It **is** one of the tech leads: the primary
slot holder, so there is no second election and it is already the sling target.
Teams of 6+ only — on a 4v4 one player fielding no army is a quarter of the army
missing, which is the same arithmetic that already restricts the constructor
monopoly and the air opening.

While the role is active that player builds constructors from its factory up to
10 and then **nothing at all** — the idle line is the point, so income goes to
mexes, energy and the T2/T3 economy — keeps `quota.attack` at 400 for the whole
game rather than to `RUSH_GIVEUP`, and skips the Pulsar and the dig-in fortify.
Cheap AA and the energy converter are kept: an economy with no army is what air
goes looking for.

Released when it is losing its **own** extractors (under 70% of its own peak),
or when any ally is under 50% of theirs. Each player publishes its share of peak
extractors as `mexhold`.

**status: the role does what it says; whether the ROLE caused it is unproven.**
20 games, 8v8 Quicksilver at +40%, 30-min cap. The eco player against its own
seven teammates, mean per game: metal produced **60,800 vs 35,548 (+71%)**, mex
upgrades **5 vs 3**, T2 spend **29,530 vs 12,616 (+134%)**, energy produced
**+66%**, standing army **5,768 vs 6,127 (-6%)**. That is the intended shape --
far more economy, no more army. Role active a median of ~15 of 30 minutes.

**The confound is not small and is not resolved.** The eco lead IS the primary
tech lead, elected on `RushReady()` -- i.e. a player that already had the economy
to afford teching -- and it is the sling target every teammate donates to. A
selection effect plus seven donors would produce a similar table with no role at
all. Separating them needs the same variant with the role off, which has not been
run.

Two more things the same 20 games say:
- **T3 never happens** (eco lead 0, teammates 60), so "reach the late game
  sooner", the stated point of the role, is unevidenced at this scale.
- **The eco player holds FEWER T1 constructors than its teammates (8 vs 11)**,
  though `ECO_CON_CAP` is 10 and the idle-line log shows it sitting at 4-6. Build
  power is what compounds, so the one thing the role does buy is the thing it is
  short of. The cap is not what is binding.

**The 6+ team gate was re-tested and holds.** Six 4v4 games each way, three maps,
same seeds, only `ECO_ON_SMALL_TEAMS` differing: off went **2-1** on 904,267
metal and 166,643 army; on went **0-4** on 516,702 metal and 80,671 army, with
games ending *sooner* (41 min against 48). Everything below -- 28 constructors,
the turret band, the converter block, air constructors -- does not buy back the
quarter of a four-player team that stops fighting.

**One map is not a benchmark.** Every eco-lead number in this section came from
Quicksilver, where apex beats stock 4-1 on 4.5x the metal and 35x the T3. Across
eight maps, 30 games, the same build goes **4-6 with 20 games (67%) undecided**,
metal 1,374,971 vs 951,248 and **T3 136,557 vs 141,280 -- stock matches us**. On
five of the seven other maps stock out-T3s us heavily (Throne 497,825 to 2,850).
The "stock fields no T3" note elsewhere in this file is a benchmark artefact and
this is what it looks like when the bonused economy runs long.

**Build power, not willpower, was the whole problem.** Three arms of 8 games,
8v8 Quicksilver at +40%, 60-minute cap, identical settings. A = the role as first
written (ground constructor cap 10). B = cap 28, faster refill. C = B plus air
constructors, the nano rectangle, fusions in the band, and aid.

Eco player against its own teammates, mean per game:

| | A | B | C |
|---|---|---|---|
| metal produced | +24% | +59% | **+114%** |
| energy produced | -2% | +56% | **+82%** |
| T2 mex upgrades | +34% | +91% | +91% |
| advanced constructors | -45% | +75% | **+129%** |
| metal built | -41% | -18% | **-22%** |
| T3 spend | -94% | -84% | **-67%** |

Whole apex side, per game:

| | A | B | C |
|---|---|---|---|
| team metal produced | 1,367,701 | 1,301,770 | **1,773,612** |
| team metal built | 1,235,176 | 1,154,838 | **1,413,394** |
| team T3, MEDIAN | 66,300 | 82,950 | **221,325** |

Median, not mean, for T3: per-game values run 0 to over 1,000,000, so the mean
tracks whichever arm caught the runaway game and reverses sign between samples.
An interim read of B at n=6 was reported as "team T3 -69%" and did not survive
the last two games -- at n=8 the mean says -26% and the median says +25%. At
n=8 per arm the team-level differences between A and B are noise; C is the first
arm that moves the median several-fold.

Not controlled: the arms ran sequentially, not paired on seed, and win rate
separates none of them (A 7/8 decided, B and C 4/5).

Four bugs found by smoke-testing C before measuring it, every one of which would
have been invisible in the numbers:
- `IsAirFactory(CCircuitDef@)` refused `unit.circuitDef`, which is a CONST
  handle. An AngelScript compile error disables the whole variant and the match
  still runs and reports a normal result.
- **`aiBuilderMgr.GetWorkerCount()` counts nano turrets as workers.** The eco
  lead logged `cons=25` against a mobile-constructor cap of 16 while standing on
  eleven turrets, so the rectangle was eating the engineer budget.
- Turret orders reached `asked=40` against `standing=11`: the cap tests FINISHED
  units and Enqueue does not dedup. Bounded to 4 outstanding, with a resync so a
  destroyed turret cannot wedge the rule shut forever.
- **The air plant was unreachable.** The "no T1 bot lab" branch returns above it;
  the eco lead asked for `armlab` three times in one 40-minute game and never
  reached the air plant. Moved above it -- a bot lab builds the spam units this
  player does not build.

A single 8v8 on **Comet Catcher** went the other way: the eco player was overrun
(extractor share 0.43), stood down at 12.6 min, and the pre-existing catch-up
push then converted it into **29,450 metal of `armbull`** -- over half its
production -- because a player that deliberately built no army is maximally
`LosingGround()`. Standing the role down hands that player straight to the rule
this AI already records as its worst spender.

Three findings from getting it to run, each of which silently disabled it:
- **"Being dismantled" cannot be read off metal or energy income.** apexearth:
  reclaim gives a temporary income boost that later falls, and wind energy rises
  and falls on its own. A peak set by a reclaim burst reads the return to normal
  as death. Standing extractor count against that player's own peak moves in one
  direction for one reason.
- **`Military::gTurtle` is unusable as a gate for an armyless role**, exactly as
  `LosingGround()` is. The hold fires when our own army *shrinks*; a player that
  builds none can neither avoid it nor recover from it. Measured: HOLD at 8.7 min
  on army 1897 → 1266, RESUME only at 15.0 min on army 110 — the six-minute
  maximum hold expiring rather than recovering. It removed the role from the game.
- **"Any ally below 70% of peak mexes" is true essentially all the time** with
  seven allies. First 8v8: elected at 7.6 min, activated zero times. Self and ally
  now use different bars (70% / 50%).
- **The primary tech-lead slot flaps second to second**, because the election
  keeps an incumbent only while `RushReady()` holds and that reads energy income,
  which swings with the wind. Measured: slot moved 5 → lost → 5 → 3 → 5 inside
  two minutes, so the role never ran longer than six seconds. The eco role now
  keeps the title for 45s after losing the slot; **the underlying flapping is not
  fixed and affects the tech rush too.**

### Combat posture
- **Acting on enemy bearing did NOT work, and the machinery is gone.** The
  gadget used to publish the opposing start-position centroid as
  `ai_enemyx_/ai_enemyz_<teamId>` and `Military::BearingOffFromEnemy()` turned it
  into degrees off the line of attack. Skipping defence sites >90° off the line,
  and skipping them again while ahead on `mobileThreat/armyCost`, lost to an
  otherwise identical control over 12 paired 8v8 games: real K/D log-ratio
  −0.156 (t=−1.12) in the control's favour, metal a coin flip. Both the param and
  the helper have since been deleted — nothing in the script computes bearing
  today. `CEnemyManager::GetEnemyPos()` still exists in C++, unbound, if the idea
  is ever retried. **suspect — do not rebuild without a fresh A/B**
- **Mass before attacking**: attack quota grows 36 at 14 min → +3.5/min → cap 48.
  Stock attacks with whatever is to hand. Start/cap were raised from 30/36 on a
  request for a more cautious army; 140 and 80 both stalled the army entirely
  once the quota became enforceable (below), so the useful range is narrow and
  is being walked up rather than jumped. **unmeasured — not isolated from the
  AA change it shipped alongside.**
- **The attack quota did nothing until the promote shortcut was closed.**
  `CDefendTask::Update` promotes on
  `(attackPower >= maxPower) || !GetTasks(check).empty()`, and `DefaultMakeTask`
  builds the task with `check == ATTACK`. So the instant one attack task existed,
  every DEFEND task handed its units over on the next tick holding one unit or
  twenty — no value of `quota.attack` could close that. `Military::AiMakeTask`
  now enqueues `TaskF::Defend(MELEE, ATTACK, quota.attack)` for the units stock
  would route into the default branch; `MELEE` is a declared FightType nothing in
  CircuitAI ever enqueues, so `GetTasks(MELEE)` is permanently empty and only the
  mass test remains. Riot units with a live guard task, and support, keep stock
  routing. **unmeasured — and it makes `TURTLE_ATTACK`/`MASS_CAP` load-bearing
  for the first time, so those constants need a fresh read before they are
  trusted.**
- **Refuse bad trades** now compares metal to metal. It read
  `aiEnemyMgr.mobileThreat` against `armyCost`, which are different units; across
  eight 4v4 infologs that ratio logged **0.02–0.14** and never approached the 0.95
  threshold, so the clause had never fired. It now uses `EnemyArmyCost()`, the
  same `GetEnemyCost` sum `LosingGround()` already used. **unmeasured**
- **Reactive turtling**: hold when our army value drops 18% in 20 s, resume at
  85% of the pre-collapse peak, max 6 min, not before 5 min (apexdef).
  The hold itself fires and releases correctly — 7–22 HOLD/RESUME pairs per 40-min
  4v4 — it simply had no grip on dispatch until the item above.
- **Fodder is never grouped, and is bought while behind.** Cheap scout/raider
  units (`costM < 100`: Tick 21, Rascal 26, Wheelie/Goblin 25, Rover 31, Grunt 42,
  Pawn 54) skip the massing path entirely; cheap raiders also skip the
  `Defend(RAID, quota.raid[0])` staging and go straight to a RAID task. Every
  third "behind on the field" catch-up push now buys the cheapest body the
  factory can make instead of the assault mainstay — about 7% of the metal, since
  a Tick is 21 and a Hammer 130. Motivation, measured over the same eight
  infologs: apex's standing cheap-unit value ran **3–6× below stock BARb's from
  minute 14 on** (851 vs 3,727 at minute 18) while total army value was
  comparable. **unmeasured**

### Anti-air sized to the enemy's ground-vs-air mix
`Military::UpdateAirThreat()`, run every `AiUpdate`. Stock decides AA from raw
`GetEnemyCost(AIR)`, and nothing in the JSON layer can re-decide: build-chain
conditions are evaluated once, when the parent finishes.
- **`GetEnemyCost(AIR)` counts air constructors and scouts.** They carry
  `["builder", "air"]` / `["scout", "air"]` in `behaviour.json`, and
  `CFactoryManager`'s constructor adds the AIR *enemy* role to every def that
  `IsAbleToFly`. Two enemy air cons are 680 metal of "air" with no aircraft on
  the field. That is the input every AA path was reacting to.
- **`share = enemyAir / (enemyAir + enemyGround)`** drives one `scale` in
  `[0.1, 1]`, full strength at a quarter of their army flying. `scale` never
  exceeds 1, so this only ever builds *less* AA than stock.
- **Mobile AA**: `GetResponseInfo(AA).factor /= scale` and `.maxPercent = share`.
  `factor`, not `maxPercent`, is what binds while their air is small —
  `RoleProbability` builds AA while `enemyAir * ratio >= aaCost * factor`, so
  `aaCost` tops out at `ratio/factor * enemyAir` (0.268× on a 4-man team).
  `response.json` itself is untouched and still matches stock.
- **Static AA**: `armflak`/`armcir`, `corflak`/`corerad`, `legflak` get
  `maxThisUnit = count + spare` for `spare = enemyAir * scale / 1500`, capped at
  6 between them. `IsAvailable()` is checked on every path that can place one —
  build-chain hub, `DefaultMakeDefence`, base defence, factory — so one lever
  closes all four, and it gates task *creation* only, so anything already
  building finishes. The cheap tiers (`armrl`/`corrl`/`legrl` at 80 metal,
  `armferret`/`cormadsam`/`legrhapsis`) stay uncapped. `leglupara` is left out:
  it is Legion's superweapon entry as well, and `DiceBigGun` only re-rolls when a
  big gun finishes, so capping a def it had already picked denies Legion any
  superweapon for the rest of the game.
- Grep `apexaa:` for the measurement and the decision, once a minute per player.
- Removed `Military::AiIsAirValid()`: no C++ path looks that hook up (the engine
  reads `CEnemyManager::IsAirValid()` directly in `FactoryManager`/`FactoryData`),
  and `behaviour.json`'s `aa_threat` puts `maxAAThreat` above 100,000, so that
  gate is off in this profile regardless. **unmeasured**

### The factory overrides were land-blind, so water maps got no navy
Every override in `AiGetFactoryToBuild` named a hardcoded land def and runs
*ahead* of the engine's pick, so on a water map each replaced a naval choice with
something that had nowhere to go. The bot-lab branch was the worst: it returns
before every other pick in the function, so once it fired it held the side on
land for the rest of the game. Measured on Silent Sea:

    apex: opening corap -> corvp
    apex: no T1 bot lab -- building corlab   (x2)

and the side finished on `corlab`/`corvp`/`coralab`/`coravp` with no naval
anything, while stock BARb went amphibious.

None of this was the engine. `waterIsAVoid` is only set on harmful-water maps;
`CanBeBuiltAt` is sector-based so a shore-touching start qualifies; and
`T1_FAC`/`T2_FAC` already paired `armsy`->`armasy` and `corsy`->`corasy`.

`Factory::IsWaterMap()` is `!aiTerrainMgr.IsWaterAVoid() &&
aiTerrainMgr.GetLandPercent() < 40`. 40 is `factory.json`'s own
`select.min_land`, the same bar `CFactoryManager::GetRepresenter` uses to choose
a factory's water variant, so this agrees with the engine instead of inventing a
cutoff. Three sites now branch on it: the opening substitutes a shipyard rather
than a vehicle plant, the bot-lab branch is skipped, and `T3Gantry()` returns
`corgantuw`/`armshltxuw`.

**measured**, two 8-game arms, 3v3 Cortex on Silent Sea, same seeds and settings:

| | baseline | with fix |
|---|---|---|
| apex naval spend | **0 (0.0%)** | **63,640 (26.5% of top sinks)** |
| apex metal/game | 66,587 | 62,677 |

Zero naval metal in eight baseline games is the whole bug in one number. With the
fix it opens `corsy`, techs to `corasy`, and fields `corsub`/`corpt`/`corcrus`
with a `coracsub` constructor.

Metal per game is **not** improved: a single match showed 43,410 -> 51,646 and
that did not replicate over 8 games. Stock's own figure swung 62,339 -> 73,385
between the two arms, so the -5.9% here is inside run-to-run variation and no
economic claim should be made either way.

Land maps are unchanged — verified on Comet Catcher, same seed: still
`corap -> corvp`, bot lab x3, zero naval, `IsWaterMap()` false.

**Legion naval, corrected 2026-08-01.** An earlier note here claimed Legion had
no advanced shipyard, from a single failed filename search for `legasy`. That was
wrong. Legion's advanced shipyard is **Cortex's `corasy`** — listed in the
`buildoptions` of `legnavyconship`, `legcs` and `legch`, and named "Advanced
Shipyard" in `language/en/units.json` alongside `legadvshipyard`. Legion borrows
across factions elsewhere too: porcupine index 9 is `coratl` for all three sides.
`legsy` -> `corasy` is now paired in `T1_FAC`/`T2_FAC`, so a Legion shipyard
opening techs. `corasy` appears twice in `T2_FAC`, which is safe —
`AdvCounterpart` returns on the first `T1_FAC` match and `OwnAdvProgress` takes a
max.

`corgantuw` is genuinely Cortex-only (`coracsub`/`corhacs`/`corsacvsub` are its
only builders), so `T3Gantry()` leaves Legion on `leggant`.

**Legion crashes the AI at frame 0, and it is not new.** Reproduced on both a
water and a land map with this branch, and again with `ai/apex` checked out at
`d4ade1b` — the pre-session commit — so it predates every change here. The stack
is inside `SkirmishAI.dll`, not AngelScript, and no `.as` compile errors appear.
**Untriaged**; Legion is unusable until it is found.

Separately, `porcupine.water[1]` referenced index 17 while
`build_chain_leg.json`'s Legion array still ended at 16 — a real out-of-bounds
introduced by the AA fix above, now closed by appending `corfrt` there. It was
not the cause of the crash.

**Still open**: `coralab` remains 8.5% of apex spend on a water map. That is the
engine's own pick, not an override, and may be right where there are islands.
And `corcom` at 25.9% of all metal says the water *economy* is still weak — a
different problem from "we never build shipyards".

### AA at mex clusters — `porcupine.prevent` 1 -> 2
`DefaultMakeDefence` walks `num = isPorc ? defenders.size() : preventCount`, so
at `prevent: 1` an ordinary metal cluster could only ever reach `land[0]`, a
ground-only LLT. The AA tower sits at position 1, which made it **unreachable at
every non-porc cluster for the whole game**, however much air the enemy fielded.
The `CheapAA` rule in `builder.as` was firing but places at the constructor's own
position and caps at 4, so AA existed but never at the mexes being bombed.

Costs nothing while the enemy has no air: the walk `continue`s past any
`IsRoleAA()` def while `GetEnemyCost(AIR) < 1`, and the loop is bounded by
`i < num`, so the slot simply goes unused. `land[1]` is `armrl`/`corrl`/`legrl`
at 80 metal.

`water[1]` was a duplicate of `water[0]`, so `prevent: 2` would have bought a
*second torpedo launcher* rather than AA. Appended `armfrt`/`corfrt` (SeaDefence,
VTOL-only, 90 metal, buildable by commander/`armcs`/`armch`/`armbeaver`) at index
17 and pointed `water[1]` at it. Legion has no floating AA and borrows `corfrt`,
as its array already borrows `coratl`.

**measured**, 8 games 3v3 Cortex on Comet Catcher: T1 AA **37.0 per game vs
stock's 3.1**, with metal produced level (150,714 vs 150,651). Above the 12 that
`CheapAA` alone could produce, so the cluster path is doing the work.

### T3 defence gated on energy, not metal
`Pulsar()` gated only on `PULSAR_MIN_INCOME = 60` *metal* income, which T1 mexes
reach on their own — observed firing at `mInc=65..78`. These are energy monsters,
not metal ones: `cordoom` 37,000E, `legbastion` 58,000E, `armanni` 74,000E,
against 3,000-4,200 metal. So a Doomsday went up at 24.0 min while the fusion did
not arrive until 26.0.

Added `PULSAR_MIN_ENERGY = 1000` (apexearth: "we need at least 1000 energy per
second before we should start thinking about making those" — one fusion is
`armfus` 1000 / `corfus` 1100 / `legfus` 1200 E/s).

`porcupine.base`'s `[12, 1500]` entry is removed. That path has **no income test
of any kind** — `UpdateDefence` enqueues each entry at its frame — so it planted a
T3 gun at 25 min on a pre-fusion economy regardless of any gate on `Pulsar()`.
`Builder::Pulsar` is now the only route to those guns.

**measured**, 8 games against the arm above, same map/seeds/settings:

| | before | after |
|---|---|---|
| `cordoom` spend | 90,000 (18.8%) | **48,000 (10.7%)** |
| `corfus` spend | 13,500 (2.8%) | **31,500 (7.0%)** |
| fusion reaches top sinks | 3 of 8 games, median 30.0 min | **6 of 8 games, median 27.0 min** |

Remaining `cordoom` spend is post-1000 E/s and therefore intended. Army fell
17,586 -> 15,618 per game while stock held flat; that is inside the known
tournament noise floor and is **not** established as an effect.

### Economy
- **Reclaim over resurrect**: rez bots are handed a wreck reclaim before
  `DefaultMakeTask` can give them a resurrect. Resurrecting spends metal;
  reclaiming yields it.
- **Valued corpse reclaim**: idle builders go to the *richest* nearby wreck, not
  the closest. apexdef reaches further (2200) and accepts smaller bodies (55).
- **Reclaim when broke**: a builder standing on metal with an empty bank eats it
  rather than holding an unaffordable build task.
- **T3 gantry** is an explicit tech goal above 100 metal/s (apexdef).

### Constructor survivability
- **Threatened build sites are refused.** `AiMakeTask` reads the threat map at
  the build position of whatever `DefaultMakeTask` hands back, and drops the task
  above `CON_THREAT_VETO` (4.0) for economy and utility builds — mex, mexup,
  energy, geo, convert, store, pylon, radar, sonar, nano, factory. Defence,
  bunkers, big guns, repair and reclaim are deliberately exempt: those belong at
  the front.
  Stock's own check (`BuilderManager::MakeBuilderTask`) needs threat AND negative
  influence AND a powerless buildDef all at once, so contested ground the enemy
  has not yet painted with influence passes it. That is the ground a constructor
  walks into and dies on.
- **Refusal is a ladder, not just a veto**, per apexearth: "when a mex is too
  dangerous to build, they should try to find a safer mex to build instead. And
  if there are none, then they probably should be making some defenses."
  1. *Safer mex.* `Builder::SaferMex` asks `aiEconomyMgr.FindOpenMexSpot` for the
     nearest spot the engine has not claimed, and builds there via
     `EnqueueMexAt`. If no open spot survives the threat bar it falls back to
     trading for the nearest live MEX task the same unit reads as cold, within
     3000 elmos and with no assignee yet. Only from the refuse path — see below.
     Both outcomes are distinguishable in the log (`con-reroute spot` vs
     `con-reroute trade`); in one 40-minute 4v4 the split was 46 spot / 60 trade,
     so the fallback still carries real traffic.
  2. *Defence a distance back.* `Builder::ContestDefence` walks from the hot site
     toward our own start in 160-elmo steps until the threat map reads clear (up
     to 6 steps) and enqueues a tower there. apexearth: "build defenses a safe
     distance from the mex we desire to control." One per 30 s, and never within
     500 elmos of the last one; skipped while energy is stalling, because handing
     a task over directly bypasses `CanAssignTo`, which is where the engine's own
     energy test lives.
     **Only for ground worth holding** — mex, mexup, factory (gantry included),
     energy, geo, geoup. A radar, sonar, store, pylon, nano or convert can be
     rebuilt behind the line and does not justify a tower.
  3. Otherwise the previous behaviour: retreat if walking, wreck reclaim if idle.
- **The two paths differ, and it matters.** From `CIdleTask` the returned task is
  simply assigned, so an alternative mex can be handed over. From
  `IBuilderTask::Reevaluate` the swap happens *only when the returned task
  differs in build type*, so a mex-for-mex trade is silently discarded and the
  unit keeps walking; only the defence post and the retreat take effect there.
- **Tier split on the tower.** T2 constructors share no defence with T1:
  `armack`/`armacv` have neither `armllt` nor `armmex` in their buildoptions.
  Read from the unit defs: T1 gets `armllt`/`corllt`/`leglht`, T2 gets
  `armpb`/`corvipe`/`legapopupdef` (all three are porcupine index 8).
- Commanders are exempt — they have their own health-based retreat, and position
  threat was measured not to predict commander death.
- **Air constructors are covered now.** The site check uses
  `ai.GetUnitThreatAt(unit, pos)`, which picks the threat layer from the unit's
  own movement type; `GetBuilderThreatAt` is the BUILDER-role *surface* layer,
  and `ThreatMap::AddEnemyUnit` routes AA into the air layer, so a pure AA turret
  contributed nothing to it. For a ground constructor the two read the same
  array, so the 4.0 bar is unchanged.
- **Verify with** three greps, each rate limited to one line per 5 s and each
  carrying running totals. **unmeasured** beyond that the paths fire.
  - `grep "apex: con-veto" infolog.txt` — refusals and abandons, with
    `refused= abandoned= rerouted= defended=`.
  - `grep "apex: con-reroute" infolog.txt` — rung 1, tagged `spot` or `trade`,
    with the spot id, the alternative's threat and the distance.
  - `grep "apex: con-defend" infolog.txt` — rung 2, with the tower def and how
    far back it was placed.
- **The reroute's fallback keeps a list of the engine's own MEX tasks.**
  `AiTaskAdded` / `AiTaskRemoved` hold live MEX task handles; `IUnitTask` is
  refcounted and every removal funnels through `ITaskModule::DequeueTask`, which
  calls `AiTaskRemoved`, so the list cannot go stale. A traded task must carry
  the *same* `buildDef` as the refused one — that is the only proof available
  that the unit can build it, since `CCircuitDef` exposes no `CanBuild` binding
  and mex defs are per-constructor (`armck` builds `armmex`, `armack` only
  `armmoho`). The spot query has no such limit: `EnqueueMexAt` picks a def from
  the unit's own build options.

## Config (`config/hard_aggressive/`)

| change | why | status |
|---|---|---|
| `mex_up` 3 → 10 | T2 mexes are 4x metal; upgrade them all | measured |
| Metal storage `since` 300 → 1200 | at 5 min there is nothing to store | unmeasured |
| Fusion gated `m_inc > 28` | ~1000 e/s of economy, per human practice | suspect |
| Advanced fusion added to the fusion hub | it existed only as a hub *key*, so nothing ever built one | unmeasured |
| Nano gates on reachable income (14/22) | old gates of 22-46 produced **zero** nanos | measured |
| T1.5 towers at every advanced plant | plants had four nanos, a fusion, and no defence | unmeasured |
| Jammer towers rehung + `sensor: 900` | parent was porcupine index 12, never built, so `chance` never rolled | unmeasured |
| Commanders get `dg_cost` | stop D-gunning our own lab to kill one raider | unmeasured |
| Spam kept at high tiers (all factions) | cheap units for vision and distraction vs long-range T2 | unmeasured |
| `porcupine.land` index 13 removed, 12 moved ahead of 11 | inert towers were eating the cluster budget before the real guns | unmeasured |

### `porcupine.land` was spending its budget on towers that never fire

`DefaultMakeDefence` walks the list until cost passes a fraction of income, so
anything late in the list is unreachable on a normal budget. Two things were
wasting it.

Flak (index 10) appeared **seven times consecutively** in `rush` — ~5,740 metal
of flak per hot cluster at hosted-game income. Now 2×, matching what
`hard_aggressive` already carried.

Index 13 (`armguard`/`corpun`/`legcluster`) carries `"on": false` in behaviour,
and `SetOn(false)` is issued to the unit when it finishes
(`CircuitAI::UnitFinished`). The only thing that switches such a unit back on is
`CCircuitUnit::Attack`, and only when the def has `ATTR ONOFF` — which
`FactoryManager` sets only if the def declares `slow_target`. None of these do.
So they were built, paid for, and left switched off. Removed from the list.

Index 11 is the same defect for `armamb`/`cortoast` but **not** for Legion:
`legacluster` has no `on` flag and works. One list is shared by all three sides
(`ReadConfig` indexes each side's own `unit` array), so it is reordered rather
than cut — 12 (`armanni`/`cordoom`/`legbastion`, all functional) now precedes 11,
which reaches the working gun first without costing Legion its tower.

## One profile

`easy`, `medium`, `hard` and `rush` are gone — config and script both. They were
stock BARb trees carrying none of this AI's work (zero `apex:` markers between
them), and `AIOptions.lua` had already stopped offering them, so they were
unreachable in the lobby while still needing every change made four more times.
Deleting them also cleared 23 inherited dead-unit-name warnings from
`tools/check.py`.

`hard_aggressive` is the only profile. The shared fallback layer
(`config/*.json`, `script/{common,define,task,unit}.as`) is unchanged.
| Radar + mobile jammer paired | `coreter` beside `corvrad` (Cortex only so far) | unmeasured |
| Gantry `income_tier` 100/200 → 45/90 | unreachable, so a built gantry sat in its last tier | unmeasured |
| Converters moved to their own hub chain | they sat 6th-10th in the fusion/afus chain, so the first one started only after five nano turrets finished — and `~IBuilderTask` deletes `nextTask`, so a nano that failed placement took every converter behind it | unmeasured |
| Converters sized to the generator: fus 2, afus 5 (`legafus` 6) | one adv converter eats 600 e/s; armfus makes 1000, corfus 1100, legfus 1200, arm/corafus 3000, legafus 3300. `legfus` had none at all while armfus/corfus had two | unmeasured |
| `limit: 1` on `armuwadvms`, `armuwms`, `leguwmstore` | the last uncapped metal storages, and `limit` is the only cap there is | unmeasured |
| Advanced-fusion hub: 4 flak → 1, gated `air` (all three factions) | 3,280 metal / 52,000 energy of flak per `armafus`, unconditional and at `now` priority; `legafus` was 2 `legflak` + 2 `leglupara`, and `leglupara` is `anti_air` too | unmeasured |
| `porcupine.land`: flak listed 7× → 2× | `DefaultMakeDefence` walks the list until `totalCost` passes the income cap, so at hosted-game income a hot cluster spent 5,740 metal on flak and never reached indices 11/12 | unmeasured |

Upstream bugs found and worked around: `legbombard` has no builder, `armfmd` is
not a unit def, three `nanotct2` variants are buildable by nobody, several
porcupine entries ship `on: false` and are built inert.

## Energy waste, metal storage, late-game mexes — what was measured

Three late-game complaints from a hosted game, checked against the 8 paired
+40% 40-minute 4v4s in `ab_t*` / `ab_c*` / `run-t3*` (apex ally 0, stock BARb
ally 1) before anything was changed.

**Energy waste is real.** Whole-game `energyExcess/energyProduced` is worthless
here — it tracks who is losing, not which AI — so it was sliced per team per
2-minute sample and bucketed on that slice's own energy income. apex wastes more
than stock in **every** band:

| e/s band | apex waste | stock waste |
|---|---|---|
| 200-500 | 12.4% | 1.9% |
| 500-1000 | 3.3% | 0.8% |
| 1000-2000 | 8.0% | 1.1% |
| 2000-4000 | 3.8% | 2.7% |
| 4000-8000 | 5.3% | 3.4% |
| 8000+ | 2.5% | 1.0% |

BAR's `game_energy_conversion` gadget converts `eCur - eStor * 0.75` per tick,
capped by total converter capacity, so overflow at full storage *is* the measure
of missing converter capacity. Hence the two build-chain changes above.

**Metal storage runaway was not reproduced at benchmark scale** (`armmstor`
never reaches the telemetry's top-4 spend list in any of the 8 games), but the
mechanism is in the source. `CEconomyManager::UpdateStorageTasks` ships with its
`GetMetalStore() > 60 * GetAvgMetalIncome()` cap commented out, leaving
`IsMetalFull()` as the only gate — satisfied almost continuously on a bonused
economy. It also consults exactly one def, `storeMDefs.GetFirstDef()` (best
storage-per-metal, **no** availability filter, no fallback), which is
`armuwadvms` 10000/750 rather than `armmstor` 3000/330 wherever an advanced
constructor exists. `armuwadvms`, `armuwms` and `leguwmstore` carried no
`limit`; their Cortex twins did. Faction parity, again.

**Late-game mex obsession did NOT reproduce, and points the other way.** After
minute 20, apex builds 0.66 extractors/min against stock's 1.13, and sinks 3.9%
of metal produced into extractors against stock's 5.4% (n=32 team-games each).
So no config was changed for it. What is true in the source, at any scale:
`UpdateMetalTasks` enqueues MEX and MEXUP at `Priority::HIGH` and **returns**
before it ever reaches the converter branch, task weight is `1/(priority+1)²` so
a HIGH task beats a NORMAL one at 2.25x the distance, and the mex brake is
`(GetAvgMetalIncome() < 100) || !IsMetalFull()` — an OR, so high income alone
never stops it. `mex_max: [2.0, false]` leaves `mexMax` at `UINT_MAX`, so
concurrent MEX tasks are unbounded; dropping it below 1.0 also switches on the
`ms_pull` expansion rule, which is why it was left alone.

## T3 urgency gate — implemented, NOT shown to work

`T3Worthwhile()` used to refuse a gantry whenever `gTurtle` was set or our army
was smaller than the enemy's, so it only ever allowed T3 from a winning position.
Above `T3_INCOME_URGENT` (150 m/s) both vetoes are skipped. Motivated by a live
hosted game: a player on 398 m/s with enemy T3 in the base built nothing.

**8 paired +40% 40-minute 4v4s say the change is not measurable.** Win rate 2/4
treatment vs 1/4 control (2 draws). apex T3 median 40,265 vs 13,720, but the
ranges are 0-86,810 and 0-205,200 -- the single largest T3 game in the whole set
was a CONTROL run, because the old gate happily builds T3 when winning.

What actually predicts T3 spend is economy scale, not the gate: the four runs
above ~400 m/s peak built 86.8k/205.2k/64.0k/11.8k, the four below ~230 m/s built
0/16.6k/0/15.7k, with both arms on both sides. An earlier 1-vs-1 pair looked
decisive and was luck.

Kept because it only relaxes a veto in a case observed live and costs nothing
otherwise. The case it targets -- big economy AND losing -- is barely sampled by
random games, so testing it needs a scenario, not more matches. **unmeasured**

## Surprise air eco-assassination — implemented, NEVER RUN

`script/hard_aggressive/manager/air.as`, namespace `Air`. One player per ally
team builds a hidden T2 air force and throws all of it at the enemy economy.
**Not one game has been played with this. Every number in it is reasoned from
unit costs and from the C++ it drives.**

What it does:

| piece | mechanism | status |
|---|---|---|
| One air player per ally team | same one-writer blackboard as the tech election: everyone publishes `airinc`, `Factory::ElectorTeamId()` publishes `airlead` once, latched | unmeasured |
| Two-step plant chain | the T2 air plant is buildable by **air constructors only** (`armca`/`armaca` and pairs) — no ground con of any tier has it. So: T1 air plant → its 5-con opener → T2 air plant | unmeasured |
| 20 bombers + 20 fighters | forced from the T2 plant in `Factory::AiMakeTask`, alternating in proportion, 2 s apart | unmeasured |
| Held at home | `Military::AiMakeTask` returns null, which leaves the unit in the idle task with no orders | unmeasured |
| Abort on enemy AA | `GetEnemyCost(anti_air) > 2500` metal before committing; after committing it strikes early if half-massed, else stands down | unmeasured |
| Strike hits economy, not army | `ANTI_STAT` added to the bomber def at release: `CBombTask::FindTarget` then skips every mobile enemy. Per-instance — `CCircuitDef` is owned by each `CCircuitAI` | unmeasured |
| No retreat | `retreat: 0.0` on the six strike aircraft in `behaviour.json`/`behaviour_leg.json`; `IFighterTask::OnUnitDamaged` returns early while `healthPerc > GetRetreat()` | unmeasured |

What it does **not** do, and why:

- **They are not landed, only orderless.** `CmdFindPad` and `CmdWait` exist in
  `CCircuitUnit` but are not registered to AngelScript — only `CmdMoveTo` is. An
  idle aircraft hovers where it was built. Anything that scouts our base sees it,
  so "hidden" here means "off the map", not "invisible".
- **Bombers and fighters strike as two squads, not one.** `ISquadTask` merges
  only within one `fightType`, so bombers form a BOMB squad and fighters an AA
  squad and they travel separately. Combining them needs C++.
- **No edge-of-map routing and no anti-flak spreading.** The path comes from
  `CPathFinder` against the threat map; neither the route nor the formation is
  reachable from script.
- **`retreat: 0.0` is profile-wide, not scoped to the strategy.** There is no
  `SetRetreat` binding, so `armpnix`, `armhawk`, `corhurc`, `corvamp`,
  `legphoenix` and `legvenator` now fight to the death for every player on this
  profile, not just the air assassin.
- The income bar (60 m/s for the air player) is set above what the 4v4 benchmark
  reaches, so **the expected benchmark result is that this never fires**. The
  elector logs "no air assassin, best ally income X/60" once a minute past 15 min
  so that silence can be told apart from a script that failed to compile.

Also found while reading the C++: `Military::AiIsAirValid()` in `military.as` is
dead — no C++ path calls it. The real gate is `CEnemyManager::IsAirValid()`
against `quota.aa_threat`, which this profile sets to `[[8, 99999], [96, 500000]]`,
i.e. effectively disabled.

## Packaging — what makes it load in a hosted game

- **Ships under its own shortName, `BARbApex`**, rather than as version `apex` of
  `BARb`. The lobby's `ADDBOT` carries only `aiLib`, with no version field, so a
  hosted game's start script has `Version` empty; the engine then keeps every key
  matching the shortName and picks the highest by `VersionCompare`, and
  `"apex" < "stable"`. As a version, the variant loaded **stock BARb in every
  multiplayer game** and said nothing. Single-player was unaffected, because
  Chobby writes that start script itself and does pass the version — which is
  why it only appeared when hosting. **measured**: reproduced and fixed under
  `run_match.py --drop-ai-version`, which omits `Version` exactly as a host does.
- **Config and script are deployed engine-side as well**, into
  `AI/Skirmish/BARbApex/apex/`. Other players are on released BAR, which has no
  `LuaRules/Configs/...` for us; CircuitAI logs "Game-side config: missing!" and
  falls back to `LocatePath("config/")` over the AI data dirs. **measured**

## Dev instrumentation (not part of the AI)

`game-patches/gadgets/` — installed into `BAR.sdd`, inert in normal play.
- `dev_stats_export.lua` — value-weighted telemetry: real vs chaff kills, T2
  placement *and* completion, T2 mex count, reclaim, **commander losses**,
  **constructors held (T1/T2) and metal tied up in them**.
- `dev_team_income.lua` — **mostly dead, and deliberately still running.** The AI
  no longer reads its income table or its `ai_lead_` election; both moved
  in-process so they survive a hosted game. The only live reader left is the team
  front (`ai_frontx_`/`ai_frontz_`). Its `[BARAI_LEAD]` echo still fires and no
  longer reflects what the AI believes — read `apex: tech lead` from the AI's own
  log instead. Delete the dead half once the front is ported.
- `tools/trace_flow.py` — reconstructs the pooling sequence (elect → pool →
  rush → tech → share → follow) per ally team from an infolog and names the
  first step that broke. Needs the `[3.9m t2]` team-tagged log prefix.
- `tools/check.py` — pre-deploy gate: invalid JSON, non-existent unit names,
  multi-key `condition` objects, version/profile mismatches. Baseline-aware, so
  it reports our breakage and not the ~31 quirks inherited from stock.
- `ai_namer.lua` patch — prefixes AI names with their variant so replays are
  readable.

---

## Known not done

- **Factory placement in safe ground.** The `"support"` attribute is documented
  as "build in base radius, not on front" and is already set on every factory —
  but there is no `IsAttrSupport` in the source, so it is unclear anything reads
  it. Unsolved.
- **Commander retreat.** Three approaches tried, none worked. `commander.json`
  hide levers moved losses not at all and cost 10-20k metal; `GetEnemyCostAt`
  crashed and returned zeros; `GetBuilderThreatAt` works but **does not predict
  death** — across 10 games, readings within 30 s of a commander dying were
  *lower* than baseline (3% nonzero vs 8%). Commander survival is still the
  strongest outcome correlate measured here, so it is worth pursuing, but not
  through a sampled position-threat signal.
- **A fourth approach — "commander to the back wall" on enemy TEAM CENTROID
  proximity (`BaseUnderAttack`, `COMM_BASE_DANGER`) — measured actively harmful
  and is now disabled (`COMM_BACK_WALL_ON = false`).** On Comet Catcher 4v4 the
  centroid of four spread-out enemies sits under the 2200-elmo bar from ~1
  minute in for the entire game, regardless of whether anyone is attacking, so
  the branch fired roughly every 30s all game and spent the commander's build
  time — normally the fastest builder available early — on repeat back-wall
  solars instead of the opening build. 8-game control vs
  `BARb:stable:hard_aggressive`, same map/handicap/faction: paired K/D
  log-ratio t-stat went from -13..-17 (apex shut out 0-5/0-7 decided) to -0.87
  (not distinguishable from even, 1-1 head to head, one outright apex win). The
  health-based retreat (`COM_RETREAT_HEALTH`) is untouched by this flag and
  still the thing pulling a commander out of real danger.
- **Choosing a metal spot from script.** Nothing in the binding surface can
  enumerate metal spots or clusters — `CMetalManager` and `CMetalData` are not
  registered at all — and `TaskB::Common` leaves `spotId` at -1, which
  `CBMexTask` indexes `mexSpots` with. So the constructor ladder can only reroute
  between MEX tasks the engine has already created, and cannot open a spot the
  engine has not picked. Wanted: `int aiEconomyMgr.FindOpenMexSpot(CCircuitUnit@,
  const AIFloat3& in)` returning a spot id, plus `AIFloat3 GetMexSpotPos(int)`,
  so `TaskB::Spot(MEX, ...)` becomes usable from script.
- **Reachability from script.** `CTerrainManager::CanReachAt(unit, pos, dist)`
  decides whether a builder can path to a position and is used all over
  `MakeBuilderTask`; it is not registered. The reroute is distance-bounded as a
  stand-in for it.
- **Sling guard when under attack.** Followers give away metal with no check on
  their own safety.
- **Nuke bomber massing, progressive scout quotas, all-in timing scaled to T3.**
- **Armada and Legion radar/jammer pairing.**

## Reading results

Check `exit_code` and `reason` in `result.json`, not just the winner. A run where
games end without a winner may be aborting rather than drawing — that mistake
invalidated several days of conclusions here. Clean games are `exit 0` with
`reason=gameover` or `reason=timelimit`.

---

## How the AI judges a fight — four defects found 2026-08-02

All four sit behind one symptom apexearth has reported repeatedly: *"we won a
fight, took that army to the enemy base and lost it all... we keep fighting with
2/3rd or 1/2 their size army... never gaining enough to really fight because we
throw our army away."* They are separate mechanisms and are being fixed one at a
time, with a watched game between each.

### 1. Squad strength is blind to damage — FIXED, unmeasured

`FighterTask.cpp:52` accumulates `attackPower += cdef->GetPower()`. `cdef` is the
`CCircuitDef` — the unit **type** — and `GetPower()` returns a constant field on
it. The value therefore changes only when a unit is added or removed from the
task; `RemoveAssignee` subtracts the same constant on death.

Nothing anywhere reduces it for damage. A squad at 10% health across the board
rates itself exactly as high as a fresh one, so after winning a bloody fight it
still passes the engagement test and pushes on into the enemy base.

The enemy side of that same comparison is **not** paper: `ThreatMap.cpp:290`
weights an enemy by `GetHealth() + shield * SHIELD_MOD`. So the AI rated the
enemy on current health and itself on paper strength — the asymmetry always
favoured attacking.

Fix: `CAttackTask::GetHealthScale()` returns power-weighted mean health across
the squad, and `FindTarget` multiplies `maxPower` by it. Clamped to [0,1] because
`GetHealthPercent()` subtracts `GetCaptureProgress() * 16` and can go negative.
Deliberately local to `CAttackTask` — see defect 3.

### 2. The engagement test has NO margin — not yet fixed

`AttackTask.cpp` `FindTarget`:

```cpp
if ((maxPower <= group.influence * scale) && ...) continue;  // skip target
```

The squad engages the moment its power exceeds enemy influence **by any amount**.
A 1% edge commits the whole army. Any enemy reserve not yet seen flips the
outcome after the commitment is already made, and a slow-turning vehicle squad
pays for the reversal on the way out.

apexearth, watching: *"we consider fighting. But then we discovered that they
actually have more units just behind the ones we see in the fog. And so then we
turn around... it takes a moment to turn around, and so that's enough time for us
to lose one or two."*

### 3. `attackMod` cannot separate raiding from frontal combat

One config value is read by SCOUT, RAID, ATTACK, BOMB, ARTY and AA. Raising
`thr_mod.attack` from [1.0,1.0] to [1.4,1.8] to buy caution **tripled losses**
and was reverted: it made raids cautious too, and a raid unwilling to trade is
just passivity.

This is why defects 1 and 2 are being fixed in `CAttackTask` rather than in
config — that reaches frontal engagements only, leaving raids free to make the
economic trades that are worth losing units for.

### 4. Fog memory is NOT the problem — measured from source

Checked because it was a natural suspect. `EnemyManager.cpp:129` sets
`maxFrame = now - 20 minutes`; an enemy unseen for less than that stays in the
list at its last known position, and line 551 adds `enemy.influence`
**unconditionally**. Threat memory persists for a full twenty minutes.

Only `cost` forgets: line 548 gates `eg.cost += enemy.cost` on
`!IsMobile() || IsInRadarOrLOS()`, so a fogged mobile enemy drops out of `cost`
while still counting in `influence`. The engagement test above uses
`influence`, so it is the remembering one.

Conclusion: units that surprise a committed squad were never seen at all — new
production, or reserves on unscouted ground. Better scouting or longer memory
would not have helped; margin (defect 2) is the answer.

---

## Defence towers were always the cheapest one — FIXED, unmeasured

`PorcToBuild` already picked the heaviest tower it could afford, capped at
`metal.income * 30`. Early income of ~6/s makes that a 180-metal budget, and the
mid-tier tower costs **195** — it missed by 15 metal in every early placement, so
the AI fell back to the basic laser tower indefinitely.

That tower cannot fight the units it is meant to stop. Measured from the unit
defs in the pinned tree:

| unit | metal | range |
|---|---|---|
| `corllt` | 90 | **435** |
| `corstorm` (rocket bot) | 110 | **475** |
| `corhllt` "Twin Guard" | 195 | **480** |
| `corhlt` "Warden" | 480 | 620 |

A rocket bot outranges the basic tower by 40 elmos and kills it without being
fired at. Armada is the same shape (`armllt` 85/430, `armbeamer` 190/480,
`armhlt` 440/620). `corrl` is not an alternative — `onlytargetcategory VTOL`,
it is anti-air only.

Fix: a `PORC_MIN_BUDGET` floor of 200 metal, so the mid tower is always
reachable. apexearth: *"HLTs are even better if we can afford it, but usually you
wanna get those mediums up first, then an HLT once you can afford"* — that
ordering falls out of the existing income term, which only clears 480 at 16
metal/s, by which time the mediums are already placed.

---

## Rez bots died to all-or-nothing resurrects — FIXED, unmeasured

A resurrect pays out only on completion; a bot driven off one has nothing to show
for the time spent. A reclaim credits metal continuously and can be abandoned
part-done. `RezSpotHot()` now forces reclaim when the bot stands on hot ground,
which is what makes "snatch and go" possible.

apexearth: *"we lose too many rezbots due to dangerous rezzing... dangerous
rezzing should turn into reclaiming, which allows for more 'snatch and go' type
behavior."*

---

## Metal converters may be eating the expansion gap — NOT ACTED ON

Measured in one clean 20-minute 4v4: apex held constructor counts **level with or
above** stock through minute 14, yet finished on 11.0 mexes to stock's 15.8.
Same builders, spent differently.

91 converters were built in that game. Build times from the pinned tree:

| unit | metal | buildtime |
|---|---|---|
| `cormakr` (converter) | 1 | **2680** |
| `cormex` | 50 | 1870 |

A converter costs 43% **more constructor time** than a mex while costing
essentially no metal — so it is invisible in a metal-spend audit and expensive in
the resource that actually binds. This is a candidate for the remaining
expansion gap, not a confirmed cause; nothing has been changed.

---

## Gating CDefendTask promotion — TRIED, REVERTED 2026-08-03

**Do not retry this without a different mechanism.** It made every measured axis
worse and it made squads *smaller*, which is the opposite of its purpose.

`CDefendTask::Update` promotes on:

```cpp
if ((attackPower >= maxPower) || !militaryMgr->GetTasks(check).empty()) {
```

The second clause is unconditional once one ATTACK task exists — which is always,
after the opening. Engagement logging showed the consequence: over a 40-minute
8v8, the median attack decision was made by **2 units**, p75 of 4, against a max
of 30. So a floor was added: while an attack is already running, a defend task
had to reach `maxPower * 0.5` before promoting.

Measured on **identical settings** (Comet Catcher, 4v4, +25% handicap), one
variable changed:

| | before | after |
|---|---|---|
| apex eliminated | 23.3 min | **20.0 min** |
| K/D | 0.55 | **0.32** |
| metal produced | 169,601 | **109,901** |
| mexes | 71 | **51** |
| squad size, median | 4 | **3** |
| decisions by <=2 units | 27% | **50%** |

The run was verified valid first: variant loaded 8x, zero AngelScript errors,
zero crashes. Apex simply died sooner.

**Why the model was wrong** (inference, not measured): the promote path
`Enqueue`s a new task, and `GetMergeTask()` on the following update folds it into
an existing squad. So the observed trickle of 1-2 unit promotions was largely the
*reinforcement pipeline*, not units walking off to fight alone — they promote,
then merge into the squad already in the field. Gating promotion blocked
reinforcement, so squads in contact shrank as they took losses with nothing
arriving, and fewer attack tasks existed at all (78 engagement decisions -> 36).

Consequence for future work: **squad size measured at the engagement decision is
not a measure of how many units are in the fight.** A small `units=` count may be
a wave about to merge. Any future attempt at massing has to measure the merged
squad, or work on the merge/assignment path rather than on the promote gate.

---

## Squad join radius 1000 -> 3000 — squad size FIXED, win effect UNPROVEN

`CAttackTask::CanAssignTo` rejected any unit further than 1000 elmos from the
squad leader. That gate governs **merging as well as joining**, because
`CheckMergeTask` calls `candidate->CanAssignTo(leader)` — so it, not the
`MAX_TRAVEL_SEC * speed` budget in the same function (~2700 elmos for a T1 bot),
was the binding limit. `CDefendTask::CanAssignTo` has no distance limit at all,
so units pooled near home, promoted as a group there, and then could never
combine with the squad already fighting 3000-5000 elmos away. The army was
structurally split into "the squad in contact" and "everything built since".

`CAntiAirTask` and `CBombTask` were already raised from the same 1000 to 4000
here; ground attack had been left behind. `CRaidTask` is deliberately still 1000
— raids are meant to be small and independent.

Measured on identical settings (Pinch Point 8v8, left/right, 0.35 boxes):

| | radius 1000 | radius 3000 |
|---|---|---|
| median squad at engagement | 2 | **5** |
| decisions by <=2 units | 52% | **30%** |
| decisions by >=8 units | 15% | **23%** |
| sample | n=1037 | n=806 |

The squad statistic has ~1000 samples inside a single game, so it does not depend
on between-game variance the way win/loss does.

**The same pair got worse on outcome** — apex K/D 1.71 -> 0.62, army peak
117,425 -> 66,011 — and that is NOT attributable. Apex's own metal was flat
(417,548 vs 414,945) while *stable's* doubled (258,443 -> 604,907), which no
change of ours can cause. Between-game variance on this benchmark was measured
the same day at ~50% on metal with the build held constant (89,814 vs 132,833,
and 0 vs 55 attack tasks).

The open question is real though: massing means fewer, larger attacks, therefore
less continuous harassment, therefore an enemy free to expand. Testing that needs
repeated games, and the answer may be that attacks should mass while raids stay
frequent — which is what the single shared `attackMod` prevents expressing.

---

## Naval players built no energy at all — 2026-08-03

`CEconomyManager::ReadConfig` line 431 picks the energy block once for the whole
team: `type = IsWaterMap() ? "water" : "land"`. Being naval is a property of the
START POSITION, not the map, so on a mostly-land map a water starter read the
`land` block, which carried no naval entries.

Absence is not neutral. A def with no entry gets `SEnergyCond::limit = 0`, and
`UpdateEnergyTasks` treats that as a hard stop:

```cpp
if (engy.cdef->GetCount() < engy.data.cond.limit) { ... }
else if (!isEnergyStalling) { bestDef = nullptr; break; }   // aborts the scan
```

Solar and wind sit above the tidal and `continue` out on `CanBeBuiltAtSafe`
(they cannot be placed in the sea), so the walk reached the tidal, evaluated
`0 < 0`, and **broke out of the whole loop**. A naval player therefore enqueued
no energy at all unless it was already stalling.

Same shape as the land-bot-lab bug found the same day: a map-level test standing
in for a per-player condition.

Fixed by adding the naval defs to the `land` block as well. Land players are
unaffected — `CanBeBuiltAtSafe` rejects a tidal at a land position before the
limit is read, and `min_income` drops tidals from the def list entirely on a
tideless map.

### The naval build helpers were handing ships land buildings

`EnergyConverter`, `EcoConverters` and `EcoFusion` in `builder.as` passed
`cormakr`/`corfus` to every builder including ship constructors, which cannot
build them. `EcoFusion` was worse than a silent no-op: the task enqueued
successfully, so a naval eco lead held an unbuildable task every 45 seconds.
Naval builders (`IsFloater() || IsSubmarine()`) now get the naval defs.

### Naval unit facts, verified 2026-08-03 in the pinned tree

| unit | cost | built by |
|---|---|---|
| `armtide`/`cortide`/`legtide` | 90 / 85 / 85 m | T1 con ships, commanders |
| `armfmkr`/`corfmkr`/`legfeconv` | 1 m, 70 e/s | T1 con ships, commanders |
| `armuwmmm`/`coruwmmm` | 380 / 370 m, 600 e/s | `armacsub`/`coracsub` |
| `armuwfus`/`coruwfus` | 5200 / 5400 m, 1200 e/s | `armacsub`/`coracsub` only |

**Legion has no naval fusion and no naval advanced converter in the pinned
tree** — `leganavalfusion`/`leganavaleconv` are upstream-only. Legion's naval
path runs through Cortex: `legcs` builds `corasy`, which yields `coracsub`,
which carries `coruwfus`/`coruwmmm`. Legion does have its own `legtide` and
`legfeconv`. `legcs` is game-tree-only, absent upstream.

## Range: no tower we build can answer enemy artillery

Verified 2026-08-03 from the pinned tree.

| ours | metal | range | | enemy | metal | range |
|---|---|---|---|---|---|---|
| `corhllt` | 195 | 480 | | `cormart` | 400 | **800** |
| `corhlt` | 480 | 620 | | `corban` | 1000 | 800 |
| `corvipe` | 730 | 730 | | `corvroc` | 880 | **1310** |
| `corpun` | 1300 | 1245 | | `cortrem` | 1850 | **1470** |

A 400-metal Pillager outranges our 480-metal heavy tower by 180 elmos and kills
it without being fired at. Repositioning cannot fix a range deficit.

`corpun` (range 1245) is the only static counter we own, and it carries
`"on": false` in `behaviour.json:790` — `CircuitAI.cpp` calls
`SetOn(cdef->IsOn())` when a unit finishes, so it is built switched off.
`armguard` and `cortoast` are the same.

Our own long-range units are correctly handled but barely produced: `cormart`
0.13/0.09, `corvroc` 0.06/0.05, and **`cortrem`, the only thing we own that
outranges enemy siege, 0.01/0.04**. The artillery role routes them to
`CArtilleryTask`, which positions at FULL `GetMaxRange()` — it does not apply the
0.8 `RANGE_MOD` ordinary squads use — and only fires from a position under
`THREAT_MIN`. `corban` is classed `skirmish`, not `artillery`, so it walks to
80% of its 800 range with the main squad.

Ruled out, do not chase: the per-unit `"threat": {all 0.0}` and `"power": 1.0`
on those entries are uniform across every unit including `correap`/`corthud` and
byte-identical to stock.

---

## The army loses; the towers do not carry us — measured 2026-08-03

`dev_stats_export.lua` now splits kills by KILLER type (`mKillStatic`,
`mKillMobile`) and reports mobile losses (`mLostMobile`) and standing jammer
towers (`jamT`). A combined K/D cannot tell "our defences are working" apart
from "our army is winning", and reads healthy while the army loses.

apexearth, watching: "we make them suffer a lot with our defenses, but our
units are still losing the battles."

8 games, Comet Catcher 4v4, +25%, 40 minutes:

| | apex | stable |
|---|---|---|
| combined K/D | 0.56 | 1.15 |
| **ARMY K/D** | **0.66** | **1.40** |
| kills by mobile | 1,141,429 | 1,682,405 |
| kills by static | 182,390 | 174,681 |
| mobile lost | 1,725,762 | 1,197,952 |
| jammer towers | 24 | 48 |

He was right about the army and wrong about the towers: static kills are within
5% of each other, so defences carry NEITHER side. The army is the whole gap.

## ENGAGE_MARGIN works at 25 minutes and not at 40

Matched 8-game pairs, same map and settings, only the constant changed:

| | 1.35 | 1.80 |
|---|---|---|
| apex K/D @25min | 0.82 | **0.97** |
| stable K/D @25min | 0.82 | **0.64** |
| metal ratio @25min | 0.94 | **1.26** |
| apex K/D @40min | — | **0.56** |

So requiring an 80% advantage genuinely improves fighting through mid-game and
then stops holding. The late game is a separate failure, not a weaker version of
the same one. At 10 minutes the two sides are IDENTICAL (0.76 vs 0.76 over 10
games), so nothing is wrong with the opening either.

## Reclaim cannot see the bodies

apexearth: "even once they die all on our doorstep, we're not rushin to reclaim
any of it... theres 1000+ metal in front of us and we don't even care".

Reclaim previously required an empty bank or an idle builder, so a constructor
holding any task walked past a corpse field. A rule was added that interrupts a
build for a rich field, gated on TOTAL nearby value rather than the biggest
single body — a dozen dead T1s is several hundred metal and none of them is
individually large. This needed a new binding, `ai.GetWreckValueAt(pos, radius)`,
since `GetBestWreckPos` only answers "is there one fat corpse here".

**It does not fire, and the cause is upstream of the rule.** Probed over a
16-minute game, 97 samples: `GetWreckValueAt` read 0 at both 1400 and 4000
radius, AND the established `GetBestWreckPos` returned no position at 4000 with
a 55-metal floor. Two independent bindings agree there is nothing reclaimable
within 4000 elmos of our constructors. Either features are not visible to that
callback without LOS, or constructors are never near the wrecks. **Do not tune
the threshold — find out which of those it is first.**

## Three fixes from one live session — 2026-08-06

### Commander wrecks are excluded from reclaim/resurrect targeting — unmeasured

apexearth: "any way we can enhance our reclaim logic to be careful not to fully
reclaim our own dead commander?" `GetBestWreckPos`/`GetWreckValueAt` (see
"Reclaim cannot see the bodies" above) now both skip any wreck whose
`GetResurrectDef()` resolves to a commander-role unit, via a new
`CCircuitAI::IsCommanderWreck(Feature*)`. Deliberately broadened from "our own"
to "any" commander corpse: the `Feature` API exposes no team-ownership
accessor, and BAR lets any allied rez bot resurrect any corpse under its own
control anyway. `GetWreckValueAt` is excluded too, not just `GetBestWreckPos` —
otherwise a commander corpse could still skew the "how rich is this field"
total that gates whether a constructor gets sent there at all.

### The metal-full-fallback was spamming Pharos instead of the T1.5 tower

The fallback added earlier this session (constructors spend idle metal on
defense once every other rule in `AiMakeTask` has had its chance) reused
`ContestTower()`, written for a different, reactive case: an under-fire con
grabbing whatever it can build fastest. `ContestTower`'s T1-vs-T1.5 split keys
on the CALLING CONSTRUCTOR's own cost, so a cheap T1 con (the common case)
always got the cheap turret — confirmed in an infolog, dozens of
`metal-full-fallback legcv -> leglht` lines. apexearth, watching live:
"Legion makes too many Pharos (llt light laser turret), not enough of the T1.5
defenses." New `MetalFullTower()` always prefers the T1.5 popup tower
(`legapopupdef`/`corvipe`/`armpb`) once it is unlocked, since reaching this
fallback at all means the team can afford it; only falls back to the T1 turret
before that tech exists. Smoke-tested all three factions: fallback now builds
`corvipe`/`legapopupdef`/`armpb` instead of `corllt`/`leglht`/`armllt`.

### No living commander now overrides `PreferReclaim()`

apexearth: "if we have no comm anymore then we should prefer to rez."
`PreferReclaim()` gates rez-bot behaviour and previously defaulted to
reclaim-first before T2 and whenever `Military::LosingGround()`. It now checks
`gComm is null` first, ahead of both: `gComm` is set null exactly once, at the
real death event in `AiUnitRemoved` (see the `COMMANDER LOST` log there), and
re-set the moment any commander-role unit is added — resurrected or freshly
built — so this only holds during the actual gap. Unmeasured: no commander died
in the three 8-minute faction smoke tests, so this path compiled and deployed
clean but has not fired live yet.

### Open: army production stalling with a live commander and idle metal

Recurring live report, this session's newest instance: "purple stopped making
army. he has a commander, home base still intact... he just stopped being
productive. our team died full on metal." Pulled that player's own timeline
from `result.json` (not the end-state total — see "Standing counters are not
end-state" in `CLAUDE.md`): `armyReal` frozen at exactly 2700 for 10 straight
minutes (20-30 min mark) while `metalProduced` climbed steadily and
`metalExcess` grew from 345 to 2079, and `mCon` (constructor value) fell to 0
by the same point. Ruled out the eco-lead role as the cause — this was a 4v4,
`IsSmallTeam()` is true, and `ECO_ON_SMALL_TEAMS` is false, so `IsEcoLead()`
cannot fire; no "eco lead" log line appears anywhere in that match's infolog.
**Not yet root-caused.** Added a rate-limited entry log to `AiMakeTask` in
`factory.as` (`apex: factory-diag`, once per 30s) recording income/current/
storage/`isMetalFull`/whether the factory already holds a task — the next time
this is caught live, that log will show whether the function keeps being
called and returning nothing (a decision problem, something below always
declines) or stops being called at all (the factory's task got stuck and the
engine stops re-asking) — the same two-hypothesis split the RECLAIM-abandon fix
resolved earlier this session for constructors, not yet applied to factories.

## Three more, same session, from watching two windowed games back to back

### The commander was thrashing between mex, factory-assist and reclaim

apexearth, watching live: "he'll start a job to build a mex, and then he'll
turn around to try to assist a factory, but then he'll move away, and he'll
follow some reclaim... we have a lot of different bits of logic that are all
kind of competing for control of the same unit... we need some sort of
control pass to compare what he's currently doing with what he's proposed to
do." One instance of exactly this already had a fix: the commander could be
pulled onto another unit's HIGH-priority Reclaim task from clear across the
map (`CBuilderManager::MakeCommPeaceTask`, native, ignores distance against a
HIGH-priority job), and that was vetoed while an open mex spot remained. That
veto only ever compared the incoming task against "is a mex spot still
open" -- it never looked at what the commander already held, so a
factory-assist pick (also handed out by the same native picker) sailed
through unguarded. Generalized: `unit.task` at this point in `AiMakeTask` is
still the OLD task (`IBuilderTask::Reevaluate` only swaps it once this
function returns something of a different build type), so comparing it
against the freshly computed `DefaultMakeTask` proposal is exactly the
"current vs proposed" check requested. Now refuses any proposed swap to a
different recognized build type while the commander holds real, in-progress,
non-dangerous work of its own. Confirmed firing in all three 8-minute faction
smoke tests (4-16 times each) with zero AngelScript compile errors.

### Air factories went permanently dead after the assassin stood down

apexearth, watching live: "blue made 2 t1 air labs, a t2 air lab.. he's not
making any army at 27m in... this is a brutal mistake." Root cause: the
air-assassin election is latched forever ("the role is paid for in
factories, so it never moves" -- `RunElection()`), and `Update()`'s
"STANDING DOWN" branch (enemy AA rose past the ceiling before the strike
ever committed) sets `gAbort = true`, which is never reset anywhere in the
file. `Armed()` checks `gAbort`, so it goes permanently false, and
`factory.as` has a deliberate blanket rule -- added for a different, earlier
bug -- that no air factory may ever reach `DefaultMakeTask`. The two combine
into a one-way trip: an elected lead whose strike aborts before committing
gets every air factory it owns locked out of production for the rest of the
match, with only a late-game 8-fighter floor (`LATE_FIGHTERS`) as a partial
safety net, and no path back since nobody else can ever be elected either.
Confirmed in that match's infolog: exactly one "STANDING DOWN" line, after
which the player's armap/armaap factories kept showing up in the new
factory-diag log with no further Air:: activity for the rest of the game.
Fixed with `Air::RoleAbandoned()` (true only for the standing-down case, not
the post-strike `gStrike` case, which is intentionally quiet) and an
exemption in `factory.as`'s blanket block so an abandoned lead's plants fall
back to ordinary production instead of building nothing.

### Open: a follower stuck at T1 all game despite heavy army spend

apexearth, same session: "purple at 29m in still pumping out TONS of
army... but never went t2... we were almost winning but these issues turned
it into a loss." Pulled from the same match: `mT1=47,500`, `mT2=0`,
`techStart=-1` the whole 30-minute game. This is NOT a fresh bug the way the
two above are -- `FOLLOWER_TECH_ENERGY`'s own comment already names this
exact failure mode as possible and says what to check before touching the
threshold: "Deliberately above what the AI currently reaches [on the
benchmark]... If followers stop teching at all, that is the factor being too
low, not this number being wrong -- check eInc in the T2GATE log before
lowering it." The problem: that log (`T2GATE reached`) only ever fires on
the PASSING path. A player that never once clears the bar leaves no record
of how far short it stayed -- confirmed in this match's own infolog, only 2
`T2GATE reached` lines total, for the two players who DID tech, and nothing
at all for the two who didn't. Added the missing half: `T2GATE blocked
FollowerEconomyReady`, logging the actual eInc/mInc against both thresholds
whenever a non-lead is refused for exactly this reason. **Do not lower
FOLLOWER_TECH_ENERGY from this report alone** -- get an actual blocked-side
reading first.

**Partly resolved same session, from source reasoning, not yet from a
blocked-side eInc reading**: see "The tech-lead election was a one-way
trip" below -- a follower stuck the whole game with `techStart=-1` may
simply have had no lead left to follow, not (only) an unreached energy bar.

## The tech-lead election was a one-way trip past 15 minutes

apexearth, watching a different match live, same session: "If green did
have T2 they must have lost it, and nobody else went and made T2." Found in
`RunElection()`'s incumbent-retention check:

```
if ((ai.frame > Military::RUSH_GIVEUP)
    || (ai.ReadTeamValue(held, TV_ADV, -1.f) > 0.f)
    || (ai.ReadTeamValue(held, TV_READY, 0.f) > 0.f))
```

`Military::RUSH_GIVEUP` is 15 minutes. The `||` meant that past that frame
the incumbent was kept UNCONDITIONALLY, regardless of `TV_ADV` -- which is
`ai.GetDefBuildProgress`, confirmed live (returns -1 the instant we own none
of the def) rather than a one-way ratchet. So a lead who loses their
advanced plant after 15 minutes stays "the lead" for the rest of the game,
the slot never reopens, and `MayPursueT2()`'s only remaining door for
everyone else is `FollowerEconomyReady()` alone -- see the still-open item
above for how high that bar sits. Likely the same root cause behind that
report, not a separate coincidence: a team-wide "stuck at T1" after the
30-minute mark is what "nobody left to designate" and "nobody clears the
follower bar" look like from the outside, together. Removed the frame
clause; retention is now governed purely by whether the incumbent still has
a plant or can still afford one, at any point in the game.

## The metal-full fallback was buying Pit Bulls — 2026-08-07

The idle-constructor fallback added the previous day built a defence tower.
Watched 8v8, Supreme Isthmus, +40%: **191 fires, every one an `armpb`** at
680 metal *and* 14,000 energy — ~130,000 metal and 2.7M energy team-wide.
apexearth, watching: "some of our guys in the back line are just building
tons of t2 small defenses... we have half the economy of our enemy."

It now builds energy (solar 155 / advanced solar 350), skipped entirely while
`EnergyWasting()`. In smoke tests it fires ~1x per 8 minutes instead of
continuously, because that gate holds it shut most of the time.

**A theory this refuted, recorded so it is not retried:** the first fix
claimed energy would unlock followers' T2 via `FOLLOWER_TECH_ENERGY`. The log
says otherwise — `T2GATE blocked` fired **zero** times, and five of eight
players cleared the follower gate and still ended with 5 T2 constructors
against stock's 20. The energy bar is not what holds tech back here.

### Open: the mex-upgrade flat-line is where the 8v8 economy actually goes

Same game, per-4-minute timeline (`analyze_stats.py` on the single match):
apex is level or ahead through minute 12 (113,727 metal vs 113,891, and
*ahead* on T2 at minute 8), then diverges. By minute 40: metal 1,015,506 vs
2,512,456, T2 spend 412,765 vs 1,410,430, T3 4,725 vs 132,509.

The mechanism is visible in one column: **apex mex upgrades go 32, 33, 33 over
the last twelve minutes while stock goes 44, 49, 56.** Apex stops upgrading
mexes around minute 30 and never restarts; stock never stops. Static-defence
*share* is comparable (11.5% vs 10.4%), so this is not simply "we built more
towers" — apex's whole economy is 4x smaller and the towers are part of what
its constructors did instead of expanding. Not yet root-caused: the fallback
fires only after everything above it declines, so something upstream is
declining mex upgrades too. Start there, not at the fallback.

## Commander idling at a haven patrolled back and forth forever

apexearth, watching live: "when a commander has retreated he often ends up
just patrolling back and forth for a very long time." `CRetreatTask::
OnUnitIdle` (C++), once a retreating unit is within range of its haven,
issues `CmdPatrolTo(pos)` to any repair-capable unit -- which includes the
commander. A patrol order to a single point is a there-and-back shuttle
between wherever the unit was when the order was given and `pos`, by engine
design, looping forever until something else takes the unit. Every other
branch in this file already carves the commander out of behaviour meant for
ordinary units (`GetRallyPos`, `GetRearHaven`, the cloak re-decide in the
same function) -- this one hadn't been. Excluded the commander from the
shuffle-to-a-nearby-build-site branch entirely; it now stays put at the
haven and AiMakeTask's own isComm section (build/hide/back-wall) picks it up
from there on the next cycle, same as any other commander idle event.
