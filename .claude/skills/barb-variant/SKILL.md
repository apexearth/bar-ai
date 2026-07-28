---
name: barb-variant
description: Create, deploy, or repair a custom BARb AI variant for Beyond All Reason. Use when adding a new AI variant or difficulty profile, when a variant stops appearing in the lobby AI list, after a BAR engine update, or when config/script edits do not seem to take effect.
---

# Working with BARb variants

A BARb variant has **two halves that must agree on the same version string**.
Most problems are one half missing.

```
engine/<ver>/AI/Skirmish/BARb/<variant>/     AIInfo.lua (version='<variant>'), AIOptions.lua, SkirmishAI.dll
BAR.sdd/luarules/configs/BARb/<variant>/     config/*.json, script/**/*.as
```

Never hand-copy these. `tools/deploy_ai.py` regenerates the engine-side half from
the current engine's `BARb/stable` on every deploy, which is what keeps a variant
alive across BAR engine updates.

## Always start here

```bash
python tools/deploy_ai.py status
```

It prints the resolved paths, the active engine, which variants the engine sees,
and whether repo and live content match. Read its diagnosis before doing
anything:

| Output | Meaning | Fix |
|---|---|---|
| `NOT DEPLOYED` | neither half present | `deploy_ai.py deploy <v>` |
| `game-side only (engine-side missing …)` | engine updated and wiped it | `deploy_ai.py deploy <v>` |
| `engine-side only (no game config …)` | AI runs on engine defaults | `deploy_ai.py deploy <v>` |
| `DRIFTED (repo != live)` | someone edited one side | `deploy` (repo wins) or `pull` (live wins) |

`DRIFTED` is a decision, not an error. If the edits were made in `BAR.sdd` while
iterating in-game, `pull` first or they are lost.

## Adding a new variant

1. `cp -r ai/apex ai/<name>` (or copy `reference/barb-stable/game-side` for a
   clean base).
2. Edit `ai/<name>/engine-side/AIInfo.lua`:
   - `version` **must** equal the folder name — deploy hard-fails otherwise.
   - give `name` something distinct; that's the lobby label.
3. Edit `ai/<name>/engine-side/AIOptions.lua` to list your profiles. Custom
   variants are not in Chobby's `aiCustomData.lua`, so the dropdown shows only
   what this file declares. Stock ships most profile entries commented out.
4. `python tools/deploy_ai.py deploy <name>`
5. Verify without launching the game:
   ```bash
   python tools/unitsync.py ais
   ```
6. Restart the BAR client — the AI list is built at startup.

## Adding a profile inside a variant

A profile is a difficulty/playstyle, not a separate lobby entry.

1. Create `game-side/config/<profile>/` and `game-side/script/<profile>/`.
   Only include files you change; lookup falls back to the version root
   (`config/<profile>/x.json` → `config/x.json`).
2. `script/<profile>/init.as` lists the JSON basenames to load in `data.profile`.
3. Register the key in `engine-side/AIOptions.lua` under the `profile` list.
4. Deploy.

Upstream's guide:
https://github.com/rlcevg/CircuitAI/blob/barbarian/doc/Profile.md

## Diagnosing "my AI isn't there / isn't changing"

Work down this list:

1. `python tools/unitsync.py ais` — does the engine see it at all? If not, the
   engine-side half is missing or `AIInfo.lua`'s `version` disagrees with the
   folder name.
2. Run a short headless match and grep the infolog:
   ```bash
   python tools/run_match.py --a BARb:<v>:<profile> --b BARb:stable:hard --map "Comet Catcher" --minutes 3
   grep -a "Skirmish AI" matches/<latest>/infolog.txt | head -20
   ```
   You want a line like:
   `Load script: LuaRules\Configs\BARb\<v>\script\<profile>\init.as`
   If it names a different variant or profile, the start script or the `profile`
   option is wrong. If it loads from the engine dir instead, `game_config` is off.
3. AngelScript compile errors appear in the same log, prefixed with the AI name.
4. If config edits do nothing, confirm you edited the profile actually in use —
   `AIOptions.lua`'s `def` sets the default and the lobby/start script can
   override it.

## Rules

- `ai/<variant>/` is the source of truth. `BAR.sdd` is a deploy target.
- Treat `reference/barb-stable/` as read-only; it's the diff baseline.
- Re-deploy after every BAR engine update.
- Changes to shared BAR files (anything outside `luarules/configs/BARb/`) belong
  in `game-patches/` as a patch, not as a copied file — that way an upstream
  change to the same file conflicts loudly instead of being silently reverted.
