---
name: ai-nukes
description: The nuke director — multi-volley logistics, target ranking, the mirrored base, antinuke accounting, intel spend
---

# The nuke director (`manager/brain/nukes.as`, ~one file)

## The model

Silos pool per player. Every 5s tick: (1) each LIVE Volley updates
independently — walks its spread line, tracks a defensive army, aborts if our
own army closes on the ground, completes when ITS OWN silos' stock delta
reaches its size; (2) silos not serving a volley form the free pool; (3) the
candidate ranking runs and the best fundable target launches a NEW volley
with only as many silos as its salvo needs. Several separate launches can be
in flight at once (apexearth's "logistics" directive).

## Target classes, one ranking

- BASE targets: enemy groups deep on their ground (fwd ≥ 0.35), value =
  sighted cluster cost, assumed +1 antinuke past 30 min.
- DEFENSIVE targets: an army on OUR side (his directive ×2: "prioritize
  nuking armies which are attacking us"); own-ground veto is overridden for
  armies worth `apex_nuke_emergency` (18k)+ — the catapult case.
- THE MIRRORED BASE: always a candidate at our start reflected across the
  map, value `apex_nuke_base_value` (30k). Exists because group targeting is
  LOS-SLAVED (hostileDatas keeps only units currently in LOS) — the unscouted
  main base can otherwise never win, and warheads chase visible mex fields.

## Accounting rules

- SCORE uses the assumed antinuke; SALVO SIZE uses SIGHTED antis only
  (`1 + sighted × apex_nuke_per_anti(8)`) — an 8-missile tax for an anti
  nobody saw held 7 missiles for 17 minutes once.
- Repeat strikes on base ground decay ×0.5 each; defensive strikes leave no
  mark (each wave is a new army).
- COMMITTING SPENDS THE INTEL: `ForgetEnemiesNear` at launch; ground cannot
  re-qualify until re-sighted. Dedup: candidates inside a live volley's
  re-sight radius are skipped.

## Log lines

`apex: NUKE VOLLEY N missiles in K silo(s) (M needed, V volleys live)` ·
`apex: nukes saving X/Y for a target worth Z behind A antinukes` ·
`apex: defensive volley aborted` · `apex: nuke intel spent` /
`ground confirmed -- forgot N`

## Tunables

`apex_nuke_min_value` (10k, his) · `apex_nuke_payoff` · `apex_nuke_def_bias`
· `apex_nuke_emergency` · `apex_nuke_base_value` · `apex_nuke_per_anti` ·
`apex_nuke_assume_from` (30m, his) · `apex_nuke_spread` · `apex_brain_nuke`
