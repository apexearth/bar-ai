---
name: barb-tuning
description: Change how BARb plays by editing its JSON config or AngelScript, for Beyond All Reason AI work. Use when adjusting build order, unit composition, economy pacing, aggression, defence placement, factory choice, or task selection - and to decide which of the three layers (JSON, AngelScript, C++) a given change belongs in.
---

# Changing BARb's behaviour

Pick the cheapest layer that can express the change. Both of the first two live
in the game archive and need no compiler.

| Want to change | Layer | File |
|---|---|---|
| unit ratios, build order, income pacing | JSON | `game-side/config/<profile>/*.json` |
| unit roles, retreat thresholds, threat weights | JSON | `behaviour.json` |
| which counter-units get built | JSON | `response.json` |
| *when* to do something / conditional logic | AngelScript | `game-side/script/<profile>/` |
| which factory to build | AngelScript | `manager/factory.as` → `AiGetFactoryToBuild` |
| what a unit does next | AngelScript | `manager/*.as` → `AiMakeTask` |
| defence placement policy | AngelScript | `manager/military.as` → `AiMakeDefence` |
| periodic custom logic | AngelScript | `main.as` → `AiUpdate` (every 30 frames, empty in stock) |
| a new *kind* of task, new map analysis | C++ | see `docs/06-building-the-dll.md` |

Full references: `docs/04-json-config-reference.md`,
`docs/05-angelscript-api.md`.

## The loop

```bash
python tools/deploy_ai.py status          # confirm clean start
# edit under ai/<variant>/game-side/
python tools/deploy_ai.py deploy <variant>
python tools/run_tournament.py --a BARb:<variant>:<profile> --b BARb:stable:<profile> --games 10
```

Neither JSON nor AngelScript hot-reloads — both are read at AI init, so every
test is a fresh match. That's what makes the headless harness the primary tool
rather than the game client.

If you edited configs directly inside `BAR.sdd` while playing, run
`python tools/deploy_ai.py pull <variant>` first or the next deploy discards them.

## JSON gotchas

- `factory.json`'s `unit` list and every `tierN` row are **positional parallel
  arrays**. Adding a unit means adding a column to every row in every domain
  (`land`/`air`/`water`) or the weights silently shift onto the wrong units.
- `income_tier` has N thresholds selecting among **N+1** tier rows. Extending the
  ladder means adding a matching `tierN` row.
- The parser accepts `//` comments — annotate your edits, the existing `apex`
  work does.
- Weights are relative within a row, not normalised.
- A profile only needs the files it changes; lookup falls back to the version
  root.

Keep changes reviewable by diffing against the baseline:

```bash
diff -u reference/barb-stable/game-side/config/<profile>/factory.json \
        ai/<variant>/game-side/config/<profile>/factory.json
```

## AngelScript gotchas

- Every hook has a C++ default. The safe pattern is to inspect state and
  conditionally delegate:
  ```angelscript
  void AiMakeDefence(int cluster, const AIFloat3& in pos) {
      if (ai.frame > 5 * MINUTE || aiEconomyMgr.metal.income > 10.f)
          aiMilitaryMgr.DefaultMakeDefence(cluster, pos);
  }
  ```
- `ai.frame` is sim frames; `SECOND` = 30, `MINUTE` = 1800.
- `@` is the handle sigil; test with `!is null`.
- Compile errors land in the infolog at AI init, prefixed with the AI's display
  name. Run a 3-minute headless match and grep rather than launching the client.
- `AiLog(string)` is your print statement.
- Scripts are per-profile — editing `hard_aggressive/` does not touch `hard/`.
- Adding a new JSON file also requires adding its basename to `data.profile` in
  that profile's `init.as`.
- You can define new unit roles from script with
  `AiAddRole("name", BASE.type)`, then use the name in `behaviour.json`.

## Where config can't reach

From BAR's own notes in `config/easy/easy_ai_readme.txt`:

> *stalling/overflowing metal, e => difficult to achieve that with config cause
> regulation of ressources is in the core program*

Resource regulation, task scheduling and threat evaluation are C++. Config sets
inputs; AngelScript chooses among existing behaviours; only C++ adds new
mechanisms. When a change keeps not sticking, check you aren't fighting that
boundary.

## Judging the result

Benchmark against **the same profile** in stock BARb, or you're comparing
profiles rather than your change. Ten games with side swapping is a weak signal;
say so rather than declaring victory. See the `bar-benchmark` skill.
