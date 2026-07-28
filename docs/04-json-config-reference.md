# 04 — JSON config reference

**There is no official schema.** CircuitAI's `doc/` has only `Profile.md`; the
authority is the C++ parsers (`setup/SetupManager.cpp`, `module/*Manager.cpp`,
`task/builder/BuildChain.cpp`, `setup/DefenceData.cpp`). Everything below was
read off the shipped `hard` profile in `reference/barb-stable/game-side/config/`;
field *meanings* are inferred from names, values and observed behaviour unless
stated otherwise. Treat it as a map, not a spec — and check the parser before
relying on an edge case.

The parser tolerates `//` comments and is lenient about trailing commas, so you
can annotate your edits. The existing `apex` work does exactly that.

Layering: `config/<profile>/x.json` is tried first, then `config/x.json`. A
profile only needs the files it changes. Faction variants are sibling files:
`*_leg.json` (Legion), `behaviour_extra_units.json`, `behaviour_scav_units.json`.

## The seven files

| File | Root keys | Governs |
|---|---|---|
| `behaviour.json` | `quota`, `retreat`, `defence`, `behaviour` | per-unit roles/threat, retreat thresholds, squad quotas |
| `factory.json` | `select`, `warn_probability`, `factory` | which factories to build and what they produce |
| `economy.json` | `economy` | energy build order, mex handling, buildpower pacing |
| `build_chain.json` | `porcupine`, `build_chain` | static defence sets and build prerequisites |
| `response.json` | `response` | counter-composition: what to build against what |
| `block_map.json` | `building` | base layout / footprint blocking |
| `commander.json` | `commander` | commander loadout, name prefixes |

`behaviour.json` (42K) and `factory.json` (28K) are where the interesting knobs
are.

## factory.json — build composition

This is the highest-leverage file and the one the existing `apex` variant tunes.

```jsonc
"armlab": {
    "importance":     [1.0, 0.2],
    "require_energy": false,
    "income_tier":    [2, 25, 35, 50, 100],
    "unit":           ["armck", "armpw", "armrectr", "armrock", "armham", ...],
    "land": {
        "tier0": [0.25, 0.70, 0.05, 0.00, 0.20, ...],
        "tier1": [0.25, 0.70, 0.10, 0.00, 0.00, ...],
        ...
    },
    "air":   { "tier0": [...], ... },
    "water": { "tier0": [...], ... },
    "caretaker": 6
}
```

- **`unit`** is an ordered list; every `tierN` row is a parallel array of weights
  positionally matching it. Add a unit → add a column to *every* row, or the
  alignment silently shifts.
- **`income_tier`** is the metal-income ladder. `[2, 25, 35, 50, 100]` means
  `tier0` applies below income 2, `tier1` from 2, `tier2` from 25, and so on —
  **N thresholds select among N+1 tier rows**. Extending the ladder is how the
  `apex` variant added late-game behaviour: `[1,30,60,80]` → `[1,30,60,80,120,180]`
  plus new `tier5`/`tier6` rows.
- **`land` / `air` / `water`** select a weight table by map type, not by unit
  domain.
- Weights are relative within a row, not normalised.
- **`caretaker`** — number of assist/nano structures to attach.
- **`require_energy`** — gate construction on energy income.
- **`select`** (file root) picks *which* factory to build: `air_map`, `offset`,
  `speed`, `map`, `no_air`, `min_land`.

## behaviour.json — unit roles and thresholds

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

- **`role`** places the unit in the task system. Roles referenced across the
  configs: `builder`, `assault`, `skirmish`, `raider`, `riot`, `scout`,
  `artillery`, `anti_air`, `anti_sub`, `sub`, `anti_heavy`, `heavy`.
- **`attribute`** is a tag set (`commander`, `base`, and the `T2`/`T3` tags that
  `main.as` assigns at runtime).
- **`threat`** feeds the threat map — how dangerous this unit is considered
  against each domain, with `vs` overrides per enemy role.
- **`retreat`** is the health fraction at which the unit disengages.

Roots alongside it:

- **`retreat`** — global thresholds as `[low, high]` bands:
  `builder [0.85, 1.0]`, `fighter [0.5, 1.0]`, `shield [0.25, 0.275]`.
- **`defence`** — `infl_rad`, `base_rad`, `comm_rad`, `escort`.
- **`quota`** — squad sizing and threat modifiers: `scout`, `raid`, `attack`,
  `thr_mod`, `aa_threat`, `slack_mod`, `num_batch`, `anti_cap`.

## response.json — counter-composition

```jsonc
"assault": {
    "vs":          ["static", "skirmish", "riot"],
    "ratio":       [0.3, 0.4, 0.4],
    "importance":  [5.0, 5.0, 5.0],
    "max_percent": 0.8,
    "eps_step":    0.075
}
```

Read as: when the enemy fields `static`/`skirmish`/`riot`, respond with
`assault` at these ratios and priorities, capped at 80% of the army.
`_weight_` (0.1) and `_importance_mod_` scale the whole table.

## economy.json

```jsonc
"energy": {
    "land": {
        "armsolar":  [12, 14, 0,   0,    0.03],
        "armadvsol": [20, 30, 12,  220,  0.2 ],
        "armfus":    [ 3,  4, 50,  900,  1.9 ]
    }
}
```

Per generator, a positional tuple. From the value patterns the fields read as
`[min count, max count, income threshold, metal cost gate, weight]` — **inferred,
not confirmed**; verify in `module/EconomyManager.cpp` before leaning on it.

Scalars: `cluster_range` 1500, `mex_up` 4, `calc_mex` false, `goal_exec` 50.0,
`build_mod` 1000.0, `eps_step` 0.2, `buildpower` 1.2, `excess` -1.0,
`mex` → per-faction extractor unit names.

## build_chain.json

`porcupine` defines static-defence sets (`unit`, `land`, `water`, `prevent`,
`amount`, `point_range`, `base`, `superweapon`, `default`). `build_chain`
expresses prerequisite ordering.

## Known limits of config-only work

From BAR's own `config/easy/easy_ai_readme.txt`, which is the closest thing to
design notes anywhere:

> *stalling/overflowing metal, e => difficult to achieve that with config cause
> regulation of ressources is in the core program*

That's the honest boundary. Resource regulation, task scheduling and threat
evaluation are C++. Config sets the inputs; it can't change the algorithm.
When you hit that wall, go to [AngelScript](05-angelscript-api.md).

## Working method

1. `python tools/deploy_ai.py status` — confirm repo and live agree.
2. Edit under `ai/<variant>/game-side/config/`.
3. `python tools/deploy_ai.py deploy <variant>`.
4. `python tools/run_tournament.py --a <variant> --b BARb:stable:hard --games 10`.
5. Diff against the baseline to keep changes reviewable:
   `diff -u reference/barb-stable/game-side/config/hard_aggressive/factory.json \
        ai/apex/game-side/config/hard_aggressive/factory.json`

One config change per benchmark run. BARb-vs-BARb outcomes are noisy — ten games
with side swapping is a weak signal, not a verdict.
