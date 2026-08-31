# 04 — JSON config reference

**There is no official schema.** CircuitAI's `doc/` has only `Profile.md`; the
authority is the C++ parsers (`setup/SetupManager.cpp`, `module/*Manager.cpp`,
`task/builder/BuildChain.cpp`, `setup/DefenceData.cpp`). Treat this as a map, not
a spec — and check the parser before relying on an edge case.

The parser tolerates `//` comments and is lenient about trailing commas, so you
can annotate your edits.

Layering: `config/<profile>/x.json` is tried first, then `config/x.json`. Faction
variants are sibling files: `*_leg.json` (Legion), `behaviour_extra_units.json`,
`behaviour_scav_units.json`. Which of them load is decided in `init.as` — the
`data.profile` array is the list of JSON basenames, so **adding your own config
file means adding its name there**, and the load is logged (`Ignoring Legion`,
`Ignoring Scav Units`, `Ignoring Extra Units`).

## Read this first: most of these files no longer decide anything

The 2026-08-22 Brain overhaul (`docs/20-brain-overhaul.md`) moved every building
and production decision into the Want market. apexearth's ruling, §6: *"No JSON
build proportions. factory.json / response.json-style unit and factory
proportion tables are dead — production choices are priced Wants, not config
weights."*

| File | Status |
|---|---|
| `behaviour.json` | **Live.** Per-unit `role`, `attribute`, `threat`, `power`, `build_speed`; plus the `quota`, `retreat` and `defence` roots. See `docs/17-behaviour-config.md`. |
| `block_map.json` | **Live.** Building footprint blocking, used by placement. |
| `commander.json` | **Live.** Commander loadout and name prefixes. |
| `economy.json` | **Partly live.** Scalars the DLL reads (`cluster_range`, `mex_up`, `calc_mex`, `excess`, `buildpower`, `mex` → per-faction extractor names). The `energy` generator ladder is superseded by the energy Want's pricing. |
| `build_chain.json` | **Mostly emptied on purpose.** The `porcupine` def lists survive as a def table; the ladder and `build_chain` hubs are empty because the DLL walks them on cluster events, **bypassing every script gate** — measured 2026-08-23 as 28 dragon claws on the eco specialist while the market's defence wants all refused. |
| `factory.json` | **Weight tables dead.** The `select` block and the per-tier `unit` weight rows decide nothing while the facqueue drives a line, which is always. |
| `response.json` | **Empty `{}`.** The whole counter-composition system is gone. |

So: if the AI is building the wrong thing, the answer is in
`manager/brain/market/`, not in a weight. Attribute it to `Market::ConOrderFor`
(production) or the defence want (`protect_*.as`) before touching any JSON. The
`ai-factory-brain` and `ai-auction` skills are the entry points.

## behaviour.json — the one that still matters

```jsonc
"armcom": {
    "role":      ["builder"],
    "attribute": ["commander"],
    "build_speed": 10.0,
    "threat":  { "air": 0.3, "surf": 1.0, "water": 0.1, "default": 1.0,
                 "vs": { "artillery": 0.5, "assault": 0.8 } },
    "power":   0.8,
    "retreat": 0.6
}
```

- **`role`** places the unit in the task system. Engine-side roles: `builder`,
  `assault`, `skirmish`, `raider`, `riot`, `scout`, `artillery`, `anti_air`,
  `anti_sub`, `sub`, `anti_heavy`, `heavy`, `bomber`, `support`, `mine`,
  `transport`, `air`, `static`, `super`, `commander`. Script can add its own with
  `AiAddRole(name, baseRole)` — see `docs/05-angelscript-api.md`.
- **`attribute`** is a tag set (`commander`, `base`, and the `T2`/`T3` tags
  `main.as` assigns at runtime).
- **`threat`** feeds the threat map — how dangerous this unit is considered
  against each domain, with `vs` overrides per enemy role.
- **`power`** is the unit's contribution to a squad's power sum, which is what
  every attack quota is denominated in.
- **`retreat`** is the health fraction at which the unit disengages.

The `quota`, `retreat` and `defence` roots are documented knob-by-knob in
`docs/17-behaviour-config.md`.

## The limit of config-only work

From BAR's own `config/easy/easy_ai_readme.txt`, the closest thing to design
notes anywhere:

> *stalling/overflowing metal, e => difficult to achieve that with config cause
> regulation of ressources is in the core program*

That was the honest boundary before the overhaul, and the overhaul moved the
boundary further: resource regulation, task scheduling and threat evaluation are
C++, and everything above them is now AngelScript rather than JSON.

## Working method

1. `python tools/deploy_ai.py status` — confirm repo and live agree.
2. Edit under `ai/Unstable/game-side/config/standard/`.
3. `python tools/check.py` — catches bad JSON and dead unit names.
4. `python tools/deploy_ai.py deploy Unstable`, and verify it succeeded before
   running anything against it.
