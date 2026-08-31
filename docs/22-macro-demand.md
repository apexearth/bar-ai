# Macro demand: stop letting the little guy decide

apexearth, 2026-08-30, on why Agitators keep appearing after a day of pricing
fixes: *"THERE IS THE ROOT OF THE PROBLEM — you thinking only in terms of that
one constructor instead of macro-thinking about what defense you want. You let
an inferior builder decide what IT wants. You don't want an Agitator — why are
you letting the little guy make the decision?"*

## The architecture, confirmed

Every proposer in the market takes a constructor. All nineteen:

```
ProposeAirDef  ProposeAssist  ProposeConvert  ProposeEnergy  ProposeGeo
ProposeMex     ProposeMexUp   ProposeNano     ProposePlant   ProposeProtect
ProposeProtectHalf            ProposeReclaimBlocker          ProposeReclaimObsolete
ProposeReclaimPenned          ProposeSense    ProposeStore   ProposeSuper
ProposeTech    ProposeTeeth
```

`Want@ Propose*(CCircuitUnit@ unit)` — the unit is the SUBJECT of every
decision. Nothing anywhere asks "what does this base need?". The AI asks "what
is the best thing THIS constructor can build", once per constructor, and spends
the answers.

## What it causes

Measured on 2026-08-30, all four from the same root:

- **The Agitator.** `apex: defwhy ... priced=1 RUNNERUP none`. Every discount
  applied (`xT1late=0.020`, `xWallEff=0.031`, `xTeamPow=0.139`, driving `val` to
  0.0000) and it won anyway, because a T1 con's shortlist had ONE item on it.
  The cheaper towers were dropped at `site.nostop` — their ground already
  covered — while a 1245-elmo gun still found open ground. **No multiplier can
  lose an auction of one.**
- **T1 rocket bots after T2.** The T1 lab decides what the ARMY needs.
- **No T2 defence.** Nothing ever says "we need a Cerberus". A T2 con is never
  told to go build one; it is asked what it fancies, and answers energy.
- **reach 0.08 against a 0.35 target.** Nobody owns the composition; each
  factory picks locally and the shares are an emergent accident.

## Half the multipliers exist only to fake macro judgement

`docs/21-simplification.md` measured twelve multiplicative terms on a defence
price and found three that can never order a choice. The deeper reading is
worse: **`mine/team` (TeamBestTowerPower), `apex_t1_def_late`,
`apex_wall_efficient` and `TargetFill` do not price anything real.** They are
all attempts to smuggle team-level knowledge into a per-builder decision. That
is why each measured as inert or perverse:

- `xT1late` scales every T1 tower equally -> cannot order two T1 towers.
- `xTeamPow` compares this def to the team's best -> a global fact, applied as a
  local discount, which then cannot stop the local list being wrong.
- `xWallEff` ranks by cover per metal -> aimed at Agitators, hit Cerberuses.
- `xFill` is def-independent -> pure volume.

Under macro demand every one of them is deletable, because the comparison they
approximate happens for real. **This is the simplification the term-count
analysis was looking for and could not find.**

## The inversion

Today:

    for each builder: what should YOU build?  ->  spend

Wanted:

    what does the TEAM need most?  ->  who can build it?  ->  send them

Demand first, assignment second. A want stops being "a thing this con chose"
and becomes "a thing the base needs, with a hand attached". A constructor that
cannot fulfil the standing demand does something else — it does not get to
substitute its own inferior idea and have that spent.

This is also already his ruling from 2026-08-27, quoted in the code and then
implemented as a multiplier rather than as routing: *"if our defence want is for
T3 we should not be routing it through T1 cons. It should only get to the cons
which could potentially fulfill it."*

## Smallest first step

**Status 2026-08-30: steps 1 and 2 have landed.** `TeamDefenceDefs()`
(`market/protect_census.as`) is the candidate set the defence want ranks over,
and `GATE_DEF_ROUTE` refuses a builder that cannot make the winner instead of
discounting it. Step 3 has NOT been done — `xTeamPow`, `xT1late` and `xWallEff`
are still in the price. The gate census retired `Requests::Redirect`,
`Requests::Allowed` and a dead Moho gate as proven-dead.

Do NOT rewrite nineteen proposers. Start with the one class where the failure is
proven and the instrument already exists:

1. **Team-wide defence candidates.** Rank the defence auction over every
   defence def ANY owned builder can make, not over `Catalog::BuildsOf(unit)`.
   The enumeration already exists — `TeamBestTowerPower()` walks exactly that
   set. `apex: defwhy` will then show `priced=N` with a real runner-up, and the
   Agitator loses to the Cerberus on cover per metal (0.017 vs 0.283) instead of
   winning a list of one.
2. **Route, do not discount.** If the winner is not buildable by the asking
   unit, that unit proposes NO defence want and spends its time elsewhere. The
   want waits for a hand that can fulfil it.
3. **Then delete** `xTeamPow`, `xT1late` and `xWallEff` and re-measure. If the
   ranking is genuinely team-wide, all three are redundant by construction.

Only after defence proves the shape should army composition and energy follow.
