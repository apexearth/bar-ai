---
name: ai-commander
description: The commander — opening, caution vs fielded tech, flee triggers, the clean-until-dead trap
---

# The commander (`manager/builder/rules_commander.as`, `commander-opening` domain)

Commanders decide BAR games (memory: survival predicts the winner). The
commander is the main early builder AND the most valuable snipe target.

## Ownership

| Decision | Owner |
|---|---|
| Opening build (factory path, first energy) | `misc/commander.as` (`isComm` branches) |
| Caution posture | `CommCaution`: fielded HEAVY+SUPER ≥ half his cost, or enemy T2 seen with mobile mass ≥ 2× his cost — all scaled to his own value, no clocks |
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
`apex: commander spreading from the pack` · `apex: commander accepted <job>`

## Tunables

`apex_comm_heavy_frac` (0.5) · `apex_comm_mass_mult` (2) ·
`apex_comm_fwd_cap` (0.25) · `apex_comm_flee_ring` (600) ·
`apex_comm_flee_influence` · `apex_comm_rules` (master)
