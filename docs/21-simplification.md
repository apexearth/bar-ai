# Simplification: why changes here don't bite, and what we are doing about it

apexearth, 2026-08-30: *"I see it terribly often that you make changes which
have little or no effect."* He is right, and it is structural rather than
careless. This document is the diagnosis and the plan.

## The measurement

| | |
|---|---|
| AngelScript | 34,765 lines, 89 files |
| `manager/brain/` | 17,529 lines — half the codebase |
| `want_protect.as` | 2,122 lines (stated ceiling: ~600) |
| `tunables.as` | 2,484 lines |
| Tunables declared | 404 |
| …read at exactly one call site | 316 |
| **…never overridden in any recorded run** | **360** |
| `ISSUES.md` | 2,637 lines |

## Root cause 1: one number, twelve multipliers

A tower's price is a product of at least twelve independent terms before the
auction sees it:

```
stake(capped by kill rate) x hazard x stopped
  x ttdH/(ttdH+buildSec)      time-to-defence
  x apex_t1_def_late          tier discount
  x eff/bestEff               wall efficiency
  x mine/team                 TeamBestTowerPower
  x TargetFill(have,target)
...and inside PfTowerKill:
  PfSurfDps x (1 + w*outrangeFrac) x hp/(hp+alphaRef) x apex_def_trade
```

**With twelve multiplicative terms no single term controls the outcome.** The
DPS term was changed by 4.6x on 2026-08-30 and the Gauntlet still won, because
`stake` moves 6.5x on reach and durability moves 2x and the product absorbed
it. It also explains why matched seeds disagree: a different term is extreme in
each game, so the sign of any change is set by whichever term happens to
dominate that match.

This is the mechanism behind "changes with little or no effect". It is not
fixed by tuning; it is fixed by DELETING terms.

## Root cause 2: the tunable factory has no exit

`CLAUDE.md`'s own rule offers three responses to a policy question — derive it,
**make it a tunable with the measured default**, or ask. The middle one is the
cheapest, so it is chosen almost every time. And nothing ever retires one: there
is no step in any workflow that folds a settled tunable back into a constant.
Growth is therefore monotonic, and each one costs four registration sites
(`tunables.as`, `dev_tunables.lua`, `dashboard_guide.py`, the audit waiver).

360 of 404 have never been overridden in a run. They are constants wearing an
experiment's clothing.

**The rule changes**: a tunable is created ONLY with a sweep already planned,
and `dashboard_audit` reports any tunable that has never been overridden in a
recorded run so the list can be culled. Default to a named constant.

## Root cause 3: nothing tells us a change landed on the decision

Four changes on 2026-08-30 and every one failed to bite:

- `apex_t1_def_late` — structurally incapable: it scales every T1 tower
  equally, so it can never move the choice between two T1 towers.
- jammer spacing — the premise was false. `GetJammerRadius=360`, the binding
  was alive; counts rose on both seeds.
- defence pricing — helped one seed, hurt the other.
- Moho serialization — `moho-pass: 0`. Mex upgrades never traverse the
  Requests chokepoint. The gate was placed on a road with no traffic.

Every one is the same mistake: **the code was changed before the path was
proven to carry the decision.** The one diagnosis that held (`apex: exec ...
protect:armguard` plus `defplace ... wall=1 gain=0.00`) came from reading the
path first.

## The hardships to attack

Each of these cost real time on 2026-08-30 and each is fixable.

1. **Files far past the 600-line ceiling.** `want_protect.as` at 2,122 lines
   produced a `No matching symbol 'bestIsWall'` scope error — the declaration
   was 400 lines from the edit.
2. **Mixed CRLF/LF line endings.** `.gitattributes` says LF; the working tree
   has CRLF in some files. Three `str.replace` anchors failed on this in one
   session.
3. **`check.py` does not compile AngelScript.** A compile error passed every
   static check, deployed, and burned a full validation round — 8 AIs failed
   `EVENT_INIT` and the match still reported normally.
4. **No decomposition instrument.** "Which term dominated" was guessed three
   times running.
5. **Sampled logs read as censuses.** `defrank` is rate-limited per builder-def
   per 60s; it was read as a complete record.
6. **Metrics that cannot distinguish states.** `f4` fight-type was used as
   evidence of "no raiding", but stock's raid pool is enqueued as
   `Defend(promote=RAID)` — fight type DEFEND — and the promotion happens in
   C++ without passing through `AiMakeTask`. The metric cannot separate the
   massing pool from the raid pool.
7. **Dead gates are invisible.** Nothing reports that a gate was never reached.
8. **`ISSUES.md` at 2,637 lines** is not readable as a live list.

## The plan

**Phase 1 — make decisions legible (no behaviour change).**
- One decomposition log per WINNING election: every term's value for the winner
  and the runner-up, so "why this one" is a grep.
- A gate census: every gate counts `seen` and `refused` and reports at game end.
  `seen=0` is dead code, reported as such.
- Fix the fight-type instrument: count live fighter tasks by `GetFightType()`
  from `gSquads`, which already registers them.

**Phase 2 — delete terms.** The decomposition log will show which 3–4 terms
carry the decision. The rest are deletions, not tunings. Each deletion makes the
next change predictable.

**Phase 3 — cull tunables.** Fold every never-overridden, single-read tunable
into a named constant at its call site. Target: under 100 tunables.

**Phase 4 — split files** back under 600 lines, after Phase 2 has removed what
it is going to remove.

**Phase 5 — tooling.** AngelScript compile check in `check.py`/deploy, line
endings normalized, `ISSUES.md` pruned to what is actually open.

## The standing rule this produces

Instrument first. Prove the path carries the decision. Then change it — and if
the instrument shows the decision did not move, say so instead of shipping it.
