---
name: ai-air
description: Everything airborne — the air line, wings, T2 air constructors, anti-air (static and mobile), and the air-threat response
---

# Air (`manager/air/` shim `air.as`, plus AA in military/builder)

## Ownership

| Decision | Owner | File |
|---|---|---|
| Air line lifecycle | election (`Armed`, air lead), basic plant → T1 air con → advanced plant chain | `air/election.as`, `air/factory.as` |
| Basic plant output | ONE job first: the T1 air con (only route to the adv plant), then T1 wing batches | `air/factory.as` |
| Advanced plant output | **T2 air constructors FIRST** — one per `apex_aca_per_income` (200, his "by ~200 metal you should definitely be having one") — then the T2 wing | `air/factory.as` |
| Wing composition/behavior | bomber/fighter defs per tier, strike logic, rearm | `air/wing.as`, `air/station.as` |
| Recycling stale T1 air | station recycle (adv standing vs basic count) | `air/station.as` |
| Static AA | `CheapAA` (count-compared vs `AAWantedNow`), `HeavyAAWant` (economy floor at 60 income + seen-based), flak pool-post for incapable askers | `builder/statics.as`, `military/airthreat.as` |
| AA placement exemption | static AA bypasses the behind-base defence veto (air ignores the front line) | `military/defenceline.as` |
| Mobile AA | excluded from massing (can't hit ground; died "for nothing" in pools); stock AA tasks | `military/hooks.as` |

## Standing doctrine (apexearth)

- Late game: flak SPREAD around the base (placement spread still open),
  T2 fighters not T1 ("10 dragons and you'll definitely die"), scouts for
  intel.
- Air cons are exempt from the ground-builder count ceiling — no ground
  hitbox, no crowding argument.

## Known C++ constraint

Air squads cannot group (the C++ constant behind "AI never masses air") —
memory `bar-ai-air-grouping`. Wing behavior works around it, not through it.

## Log lines

`apex: air assassin building <con> to reach the advanced plant` ·
`apex: advanced plant recruits <aca> (n/want)` · station recycle lines ·
`apex: heavy-flak ...`

## Tunables

`apex_aca_per_income` (200) · `apex_flak_floor_income` (60) ·
`apex_flak_per` (60) · air ratios via `factory.json` air_map/no_air blocks
