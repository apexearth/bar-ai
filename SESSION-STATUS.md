# Overnight status, 2026-08-08

Read this first. `CHANGES.md` has the full detail and the numbers.

## RESULT: the six changes are a net win, measured against a proper control

6 games each arm, 8v8 Ascendancy, Handicap 50, same seeds. Control regenerated to
session-start HEAD (the old frozen `ctl` was stale and would have measured the
wrong thing).

| metric | apex (new) | ctl (control) |
|---|---|---|
| **metal built** | **122,279** | 110,738 (+10.4%) |
| **T3 spend** | **6,804** | 3,483 (+95%) |
| cons T2 held | 9 | 7 (+29%) |
| energy wasted | 299,662 | 338,317 (-11.4%) |
| **player-games wiped out** | **17/48** | **24/48 (-29%)** |
| army share | 11.2% | 12.5% (the one regression) |

Normalised to each arm's own stock opponent (stock itself varied 9% between
arms): metal built **51.4% -> 61.5%**, T3 spend **9.8% -> 16.2%**.

The 1,763 reclaims looked like a constructor sink and are not one -- peak T1
constructors identical, peak T2 UP, metal built up.

## AND the gantry cap was the T3 constraint -- confirmed

Single-variable change (`GANTRY_PER_INCOME` 150 -> 100, `GANTRY_MAX` 4 -> 6),
measured the same way:

**T3 plants: 5 gantries across 6 games -> 16.** Catapult spend 53,900 ->
132,300. Army share 11.2% -> 14.6%. Energy wasted 299,662 -> 142,723.

Total build normalised to the opponent is unchanged (61.3% vs 61.5%) -- this did
not make us build more, it changed WHAT we build, out of banked metal and wasted
energy and into T3 and army. That is precisely what you said was wrong.

Note "building T3 gantry" DECISIONS fell 50 -> 36 while plants tripled: the
requests now land, and a completed gantry stops the re-request.

## Session total, start to now

| metric | session start | now |
|---|---|---|
| metal built | 110,738 | **131,581** (+18.8%) |
| T3 spend | 3,483 | **11,715** (+236%) |
| army share | 12.5% | **14.6%** |
| energy wasted | 338,317 | **142,723** (-58%) |
| player-games wiped out | 24/48 | **18/48** (-25%) |

## The biggest number still on the board

**Army share 14.6% against stock's 45%**, on 61% of stock's total build. Nothing
this session moved that materially, and it is larger than everything that was
fixed. Two leads, neither investigated:

- We build ~66 `armack` to stock's ~10 and hold FEWER T2 constructors at peak.
  We buy advanced constructors and lose them.
- `cornanotc` was the single largest metal sink in the tournament at 14.4% --
  more than any unit. Static build power may be crowding out the army.

Deployed and in sync. `ctl` is now a true session-start control; keep it
regenerated against HEAD before the next comparison or it goes stale again.

## The headline finding

You said "we're losing because we weren't making t3 enough even tho our economy
was matched." `composition.py` on the 8v8 you watched says exactly that, and
says which half is causal:

| per player | apex | stock BARb |
|---|---|---|
| metal produced | 240,298 | 258,209 |
| **metal built** | **177,462** | **243,352** |
| T3 spend | 10,215 | **51,334** |
| army share | 16.1% | **44.8%** |
| cons T2 held (peak) | **6** | **15** |

The economy was matched -- 93% of stock's metal. We then **built only 73% of what
we produced**, against stock's 94%. About 63,000 metal per player was made and
never became anything.

Unit by unit: **we built 2 T3 plants, stock built 7.** Our first T3 metal appears
after minute 26. And **we built 0 armfark; stock built 5,460 worth** -- your
assist-bot instinct was right, and it shows up directly in the data.

## What changed tonight

All deployed. Zero AngelScript errors over three runs; every new path confirmed
firing.

1. **`Base` layout module** (`manager/baseplan.as`) -- one anchor, one axis
   toward the front, walkways in world offsets so bands on different pitches
   leave gaps in the same places. Replaced three separate lattices that each
   derived their own axis and none of which checked buildability.
2. **C++ snap hook** -- `IBuilderTask::Execute` now snaps every non-fixed
   placement onto that grid instead of jittering it by the shake radius. Mexes,
   geo, defence and superweapons excluded (they need specific ground);
   **factories excluded on purpose** -- keeping room for them is the point.
   DLL rebuilt; patch captured in `game-patches/circuitai/0003-cumulative.patch`.
3. **T1 towers no longer offered past their tier** -- the light laser you watched
   a con walk home to build. `ContestTower` chose from the constructor's cost
   alone, so a T1 con got offered one at minute 25 exactly as at minute 3.
4. **Obsolete reclaim promoted** -- it was at line 2762, near the END of
   `AiMakeTask`, which is why it "fired twice in thirty minutes". Now runs ahead
   of the economy offers. **Measured: 2 reclaims -> 59.** Deliberately NOT moved
   above mex expansion.
5. **Reclaim picks by geometry** -- a structure in a walkway outranks one
   stranded outside the footprint, which outranks a tidy one in a row.
6. **armfark/corfast promoted to builder** once we hold an advanced constructor.
   They were parked as "support" for a good documented reason -- they'd steal the
   recruit draw from armack and delay the team's one shared advanced con -- but
   that reason is about the RACE for the first one and expires. Legion needs
   nothing: `legaceb` is already builder.

## New telemetry

    apex: base area= width= depth= placed= noroom= blocked= techroom=
    apex: obsolete junk standing= income= t2= t3=

`techroom` is the criterion you named -- distance to a valid advanced-lab site
near the base, `-1` if none within 1800 elmos. So "can we still tech up at minute
30" is a number now instead of a build that quietly never happens.

## What is running

A paired tournament, 8v8 on Ascendancy, **Handicap=50** -- because the game you
watched ran at 50 and a plain benchmark run produced **4x less metal on both
sides**. That is the single biggest trap here: without the resource bonus this
benchmark cannot reproduce the game you are judging.

- arm 1: `Apex:apex` vs `BARb:stable`
- arm 2: `ApexCtl:ctl` vs `BARb:stable` -- the control, regenerated tonight to be
  exactly session-start HEAD (the old frozen `ctl` was several commits stale)

Six changes went in at once, which is more than this repo's own discipline
allows. Two of them (the tower gate, the reclaim promotion) genuinely displace
constructor time, so the composition comparison is what decides whether they
stay -- not that they fire.

## The next thing, not yet done

**Why 16 gantry decisions produced 2 gantries.** `AiGetFactoryToBuild` returns
the gantry and the request dies downstream. Two candidates and I have not
separated them:

- `GANTRY_PER_INCOME = 150`, `GANTRY_MAX = 4` -- a player at 400 m/s wants only
  2. Stock reaches 7 with no T3 logic at all.
- Completion: the request is made and never lands. If it is placement, the new
  `blocked=` and `techroom=` numbers will now say so.

Worth separating before changing either. Also unexplained: we build ~66 armack to
stock's ~10 while holding fewer T2 constructors at peak -- we buy them and lose
them.

## Strongest open hypothesis: the base grid fails on cramped maps

apexearth: "ive repeatedly seen us perform extra bad on maps where we don't have
a lot of room."

Mechanism, and it is testable. `Base::Spot` lays out straight rows at fixed
depths from a latched anchor, with 1,512 elmos of lateral span and SCAN_MAX=96
cells examined. On tight ground those cells may simply not exist. When Spot
fails, everything downstream fails at once:

- the home crew's economy rule returned null entirely (fixed today with a
  FindBuildSiteNear fallback, but that SCATTERS instead of packing)
- constructors then walk between spread-out sites and look idle
- the base sprawls -- which is what the grid was built to prevent

Measured on Callisto, per player: `placed=0 noroom=119`, `placed=28 noroom=112`,
`placed=217 noroom=6`. The same code, wildly different outcomes by start
position. On a roomy map the grid succeeds and none of this fires, so the AI
looks fine -- which matches the reported pattern exactly.

`noroom` was one combined counter and is now split by cause:
`noroom=N (band=N hot=N terrain=N busy=N)`. THE TEST: run a cramped map and read
which dominates.
- `terrain` dominating => the band geometry does not fit tight ground; the fix
  is a layout that adapts to available space, not a fixed rectangle.
- `band` dominating => genuinely full; note SCAN_MAX=96 cannot even reach the
  back of the ECO band (12 rows x ~18 cols ~= 216 cells), so raise it first.
- `hot` dominating => not a layout problem at all; the base is under threat.

Do not guess between these. The previous reading of the combined counter as "we
are out of room" was an assumption presented as a measurement.

## ANSWERED: the cramped-map hypothesis is confirmed, and half-fixed

Split counter, Callisto 4v4, per player:

    t0  placed=0   band=0  hot=0  terrain=11328
    t1  placed=0   band=0  hot=0  terrain=4896
    t2  placed=13  band=0  hot=0  terrain=6022
    t3  placed=56  band=0  hot=0  terrain=1044

**band=0 and hot=0 on every player.** The base is never full and threat never
blocks it. EVERY failure is the terrain manager refusing the cell. The fixed
rectangle does not fit the ground.

Fixed: SNAP was 48, so a cell was discarded unless a buildable site existed
within 48 elmos of its exact centre. Spot() now retries the whole scan at
SNAP_LOOSE (CELL*2 = 144) before giving up. Measured: t1 0 -> 11 placed,
t2 13 -> 32, no behaviour regressions.

### STILL BROKEN: t0 places NOTHING even at 144 elmos of slack

terrain=16,704 rejections, placed=0 -- but `techroom=440` proves buildable ground
exists near its anchor. So this is NOT rough terrain, it is a bad FRAME: the
bands project backward from the anchor along gFwd, and for that start position
everything behind it is off-map or cliff.

The axis is latched once and never validated. Next step, in order:
1. Log gAnchor and gFwd per player and confirm where t0's bands actually land.
2. If they land off-map/unbuildable, validate the axis at latch time -- try the
   reverse and the two perpendiculars, keep whichever yields buildable cells.
3. Only then consider making the whole layout adaptive.

Do NOT just widen SNAP further; at 144 it is already two cells and the grid stops
being a grid.
