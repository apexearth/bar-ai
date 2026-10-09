---
name: ai-commander
description: The commander — opening, caution vs fielded tech, flee triggers, the clean-until-dead trap
---

# The commander (`misc/commander.as`)

Commanders decide BAR games (memory: survival predicts the winner). The
commander is the main early builder AND the most valuable snipe target.

## Ownership

| Decision | Owner |
|---|---|
| Opening order (plant first or extractors first) | `market/opennet.as`: one recorded draw (`apex: nnopen`, docs/35) whose steps lead his elections until the plant is ordered (`why=open`) |
| Caution posture | `CommCaution`: our T2, fielded HEAVY+SUPER ≥ half his cost, or known T2+ non-raider ground units (`FoeT2Fill`): one that outranges AND outruns him, or their strength ≥ `apex_comm_mass_mult` × his. T1/raider mass alone never (his 2026-10-05) |
| Towers around himself | `ComSelfGun` (safety.as, hoisted in decide.as as `why=comself`): T1 groups in reach and not leaving → light towers at his position, as many as their metal / (tower × `apex_def_trade`), standing or ordered. Log `apex: com-selfgun` |
| WORK / FIGHT / TURRET / RETREAT | `comdecide.as` (`ComAssess` → `ComDecide`, from `CommWatch` once a second): what reaches him before he reaches safety, fight read off catalog dps/hp with his D-gun's kills; RETREAT/FIGHT assigned directly (`ComEnforce`), TURRET through `ComSelfGun`; his claims (`ComRaidF`) use the same fight test. Record `apex: nncom` (docs/35); D-gun walk-in only under FIGHT/peaceful WORK (`SetDGunClose`). Win bar `ComBar`: vs T1 the fight must end above his engine retreat line (`circuitDef.GetRetreat()`, 0.6), hurt or not; vs T2 it keeps 85% of what he brings. `ComStands()` (nothing on him he does not beat) zeroes the net's RETREAT floor and exploration, overrides the T2-far retreat, the influence flee and the <85% hp flee. Counters: `apex: com-cower`, comstat `dgOpp/dgMiss/cower/stood`, audit `commander-cowers` |
| Refusing forward ground | cautious + `ForwardFraction > apex_comm_fwd_cap (0.25)` → Retreat, zero influence needed ("he should run but he doesn't") |
| Flee trigger | enemy influence at his tile (post-T2), widened to a 600-elmo RING when cautious — the tile sample is the measured clean-until-dead trap (threat read 0.00 at hp=100, dead 930 frames later) |
| Flee destination | away from the commander PACK (chained death explosions killed four in one frame once), toward home only if home is safer |
| Retreat task hygiene | `Retreat()` returns the HELD retreat task — a fresh EnqueueRetreat per re-election toggled cloak/fire-state forever |
| Low HP | `COM_RETREAT_HEALTH` branch; deadman throttle in events.as |

## Traps

- `ai.GetBuilderThreatAt` reads 0 nearly everywhere and CRASHES off-map —
  the influence map is the commander's only honest danger sense.
- The commander is excluded from adv-con tiers (`IsAdvConDef` false for COMM)
  because a level-1 comm can't build advanced towers — a silent no-op.
- Commander mex-guarding and repairs sit BELOW the caution/flee rules on
  purpose: staying alive outranks the extractor underfoot.

## Log lines

`apex: commander running -- heavies fielded, fwd=...` ·
`apex: commander leaving, enemy influence ...` ·
`apex: commander spreading from the pack` · `apex: commander accepted <job>` ·
`apex: com-flip left=<guard end>><why>><job> jobs= awayS= back= total=` -- one
line per round trip off a factory assist and back (audit `commander-lab-round-trips`).
The lab assist (`why=comescort`) defers to a metal shortfall and to an energy
stall with his own draw added (`comEscStallSkip` on `elec-slice`): in a stall the
stall interrupt takes the commander first, so the lab was a round trip.

## Tunables

`apex_comm_heavy_frac` (0.5) · `apex_comm_mass_mult` (2) ·
`apex_comm_fwd_cap` (0.25) · `apex_comm_flee_ring` (600) ·
`apex_comm_flee_influence` · `apex_comm_rules` (master)
