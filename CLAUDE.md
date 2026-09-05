# bar-ai — working notes for Claude

AI development for **Beyond All Reason** (BAR), the RTS on the **Recoil** engine
(a fork of Spring RTS). This repo is the source of truth for a custom AI; the
live game install is a deploy target.

Paths verified on this machine 2026-08-09 unless marked otherwise. Re-verify
before relying on them — engine versions change. `BAR-GUIDE.md` covers game
mechanics.

## Context discipline — read this first, it is measured

Measured 2026-09-04 over the last 20 sessions in this repo: **2.05M tokens of
conversation content, of which Bash accounted for 1.77M (86%)** — 3,860 calls,
535k tokens of *command text sent* and 1,236k tokens of *output returned*. No
single dump was the problem; the average call was 138 tokens in and 323 out. The
cost is **volume**. `Read` over the same span was 87k tokens across 57 calls.

So the lever is fewer, tighter shell calls — not shorter files.

- **The Bash cwd persists between calls. Stop re-`cd`ing.** 1,128 of 3,860 calls
  opened with `cd /c/Users/apexe/WebstormProjects/bar-ai`; the tool already
  starts there. Use repo-relative paths.
- **Batch independent probes into one call.** Three greps that don't depend on
  each other are one call with three `echo`-labelled sections, not three round
  trips. Each round trip costs a full assistant turn on top of its output.
- **Ask for the answer, not the corpus.** `grep -c`, `grep -o | sort | uniq -c`,
  `| head -20`, `wc -l` — a count settles most questions and a 400-line paste
  settles none of them better. Never `cat` a file over ~200 lines; `sed -n
  'A,Bp'` the part you need.
- **Use `Edit`, not a shell heredoc, to change a file.** The old
  `python - <<'PYEOF' ... io.open(newline='') ...` pattern cost 300-800 tokens of
  command text per edit and was written to survive CRLF. **As of 2026-09-04 every
  tracked file under `ai/Unstable/` is LF**, so `Edit` works there directly. CR
  still exists in `cpp/`, `changes/` and some root `.md` — check those before
  anchoring (`tools/normalize_eol.py` reports and fixes). The old hazard note
  survives as S18.
- **Search `ai/Unstable/`, not `ai/`.** `ai/ord`, `ai/ctl` and `ai/stk` are
  frozen measurement fixtures (see "This repo"), not live code, and they inflate
  a repo-wide grep — `AiMakeTask` hits 56 files across `ai/`, 16 under
  `Unstable`. Same for `vendor/`, `matches/`, `tournaments/`, `changes/` and
  `CHANGES.md`: exclude them unless they are the subject.
- **Grep before you Read.** These files are large by design (`tunables.as` is
  161KB, `army.as` 52KB). Locate the line, then `sed -n` a window around it.
- **Don't re-derive what a tool already prints.** `unitdef.py`, `review.py`,
  `composition.py`, `audit.py`, `frametime.py` and `dashboard_audit.py` exist so
  that a question is one call. Reaching past them into raw infologs is how a
  1,000-token answer becomes a 20,000-token one.
- **A long-running command belongs in the background, and its log belongs
  tailed.** `nohup python -u ... > log 2>&1 &`, then `tail -5 log` — not a
  foreground run whose whole output lands in context.
- **Write findings down before the context ends** — commit message for what
  changed and what was measured, `ISSUES.md` for what is wrong and not yet fixed.
  A finding left in a transcript is one you will pay to rediscover.

### Where the 1.77M actually went, and the recipe that replaces it

Four habits accounted for most of it. Each already has a tool; the cost was
re-deriving a shell pipeline instead of calling it.

| habit | cost / 20 sessions | do this instead |
|---|---|---|
| inline `python - <<'PY'` to edit a file | **356k** (302k of it command text) | `Edit`. `ai/Unstable/` is all LF — the CRLF reason is gone |
| ad-hoc `grep`/`sed` over `*.as` | **478k** | load the owning `ai-*` skill; then `grep -n` for one symbol and `sed -n` a window |
| hand-rolled infolog greps | **270k** | `trace.py`, `review.py`, `diagnose.py` (below) |
| `cat` of a whole file | **148k** | `grep -n` then `sed -n 'A,Bp'` |

**Canonical commands — verified 2026-09-04, with their output size. Do not
re-derive these.**

```bash
python tools/review.py <run>                 # 45 lines. Gate 1 IS the compile-error
                                             # + crash + "did it run" check. One call
                                             # replaces the 4-6 greps that were used
                                             # 84 times in 20 sessions.
python tools/trace.py latest --filter=decide # the apex: lines for one tag, minute-stamped.
                                             # Tags seen most: decide, defplace, fronttowers,
                                             # targets, posts, eta, defprice, defsite.
                                             # `latest` resolves the newest matches/ run,
                                             # so no `ls -td matches/2026* | head -1`.
python tools/diagnose.py <run>               # 3 lines when clean. What went wrong,
                                             # without being told what to look for.
python tools/check.py 2>&1 | tail -15        # 126 lines unpiped -- always tail it.
python tools/as_scope.py                     # 2 lines. AngelScript scope check.
python tools/unitdef.py <unit>               # 8 lines. NEVER glob for a unit file (S10).
python tools/deploy_ai.py status              # 22 lines.
```

Only when a tool genuinely cannot answer it should you open the infolog by hand —
and then check its mtime first (**S15**).

## Read `docs/23-the-plan.md` first — it is what the AI is trying to do

Two paragraphs, and the source of intent for everything below. Every decision is
an answer to one question: **what is the fastest path to the state we are trying
to reach?** The AI names a target — so much army, or that much army with a fusion
behind it — and takes whichever move makes it arrive soonest, under one standing
obligation: army and defence stay at their proper share of the economy we have
built.

The consequence that matters when reading the rest of this file: **order, numbers
and limits are OUTPUTS.** Mexes before tech, upgrades after tech, a constructor
rather than another building — all of it falls out of the arithmetic, so a
threshold, a build order or a cap in this AI is a bug in the model wearing a
fix's clothing. `value-paradigm` carries the operational detail; the plan carries
the intent, and where a doc, a skill or a comment still argues from "above N
metal/s", the plan wins and the doc is stale.

**`docs/24-how-units-fight.md` is the combat counterpart**: apexearth's
directives for how the army fights, and ONLY his — a session may add to it from
something he said, never from its own ideas. Read it before touching any C++
fighter task or `manager/military/`; where code disagrees with it, the code is
stale.

## Local layout

| What | Path |
|---|---|
| Launcher install | `C:\Users\apexe\AppData\Local\Programs\Beyond-All-Reason` |
| Spring data / write dir | `…\Beyond-All-Reason\data` |
| Active engine | `…\data\engine\recoil_2026.07.04` (from `launcher_cfg.json` → `config.json`) |
| Game (harness) | `…\data\games\BAR.sdd` — git clone of `beyond-all-reason/Beyond-All-Reason`, branch `apex`, pinned 2025-11-28 |
| Game (reference) | `vendor/bar` — the same repo at upstream `master`, for looking things up |
| Engine-side AIs | `…\data\engine\<ver>\AI\Skirmish\{BARb,Apex,ApexCtl,ApexStk,CircuitAI,NullAI}\<version>\` |
| Game-side AI config | `BAR.sdd\luarules\configs\<shortName>\<version>\{config,script}` |

`tools/bar_env.py` resolves all of this at runtime. Never hardcode these paths in
new code — import `bar_env`. Override with `BAR_ROOT` / `BAR_DATA` /
`BAR_ENGINE` / `BAR_GAME_SDD`.

**There are two game trees and they are different versions.** `BAR.sdd` is pinned
at 2025-11-28 and is what every match runs against — it is also the only one the
dev gadgets can live in, and those gadgets produce *all* telemetry (`aaT1`,
`metalProduced`, `top`, and the game-over winner). `vendor/bar` tracks upstream
`master`. Never answer a unit question by picking one: run `tools/unitdef.py`,
which reads both and shouts when they disagree — `legadvshipyard` exists upstream
and not in the game we test, and `corasy` costs 3100 here against 2800 upstream.

**The game itself does not use `BAR.sdd`.** Chobby plays the rapid-downloaded
`.sdp` packages in `data/packages`/`data/pool`; `BAR.sdd` is an extra entry the
engine picks up by scanning `data/games/`, used only by this harness. That is why
it sat eight months stale without anyone noticing, and why deleting it would cost
the telemetry rather than break the game.

**Read `docs/10-bar-game-concepts.md` before diagnosing anything.** Reasoning
about this AI from telemetry without the game model has repeatedly produced
confident nonsense. The economic thresholds there are real numbers from someone
who plays the game.

## The three layers you can work at

BAR's shipped AI, **BARb** ("BARbarIAn"), *is* CircuitAI: `rlcevg/CircuitAI`
branch `barbarian`, vendored into `beyond-all-reason/RecoilEngine` as the
submodule `AI/Skirmish/BARb`, compiled into `SkirmishAI.dll` and shipped inside
the engine archive.

1. **JSON config** — `config/*.json`. Build ratios, income tiers, unit roles,
   response tables. No build step.
2. **AngelScript** — `script/**/*.as`. Real decision logic: `AiMakeTask`,
   `AiMakeDefence`, `AiMain`, and a per-30-frame `AiUpdate` hook, over `ai`,
   `aiEconomyMgr`, `aiMilitaryMgr`, `aiFactoryMgr`, `aiBuilderMgr`, `aiEnemyMgr`,
   `aiTerrainMgr`. ~405 bindings. No build step.
3. **C++** — CircuitAI's core. New task types, new map analysis, new bindings.
   Needs a cross-compile toolchain; see `docs/06-building-the-dll.md` and the
   `cpp-dll` skill.

Layers 1 and 2 both live in the **game archive** and are hot-swappable. Prefer
them. Reach for C++ only when you need a mechanism that doesn't exist yet.

## Three axes — do not confuse them

- **shortName** → the AI's identity. **This is the only one multiplayer keeps.**
  `AI/Skirmish/<shortName>/<version>/`. Ours is `Apex`, so the harness spec is
  `Apex:Unstable`, not `BARb:Unstable`. (It was `BARbApex` until 2026-08; nothing
  validates a shortName, so an old command silently produces `unknown skirmish
  AI`.)
- **AI version** → a variant within one shortName. `AIInfo.lua`'s `version` value
  must equal the folder name.
- **profile** → a difficulty/playstyle within one version, chosen by the
  `profile` AI option in that version's `AIOptions.lua`. `config/<profile>/*.json`
  + `script/<profile>/*.as`. **`Unstable` ships exactly one: `standard`.** The
  stock easy/medium/hard/rush trees were deleted — they carried none of this AI's
  work, so every change either had to be made four more times or silently did not
  exist there. Do not add a profile back without a reason that is not
  "difficulty".

**A variant must never be just a version of `BARb`** — it would load stock BARb
in every multiplayer game with no error anywhere. Mechanism and repro: **S1** in
`docs/25-silent-failures.md`.

Config lookup falls back: `config/<profile>/x.json` → `config/x.json`. Confirmed
at runtime: `Load script: LuaRules\Configs\Apex\Unstable\script\standard\init.as`.
Corresponding C++ (CircuitAI `util/FileSystem.h`): `"LuaRules/Configs/" +
shortName + "/" + version + "/" + subdir + "/"`, gated on the `game_config` AI
option (default **true**).

## This repo

```
ai/<variant>/engine-side/   AIInfo.lua, AIOptions.lua        -> engine AI/Skirmish/<shortName>/<variant>/
ai/<variant>/game-side/     config/*.json, script/**/*.as    -> BAR.sdd/luarules/configs/<shortName>/<variant>/
reference/barb-stable/      pristine BARb stable, for diffing (do not edit)
game-patches/               patches + dev gadgets applied to BAR.sdd
tools/                      python harness (see below)
docs/                       the reference material
matches/                    harness output, gitignored
vendor/                     upstream clones (circuitai, engine, bar), gitignored
```

`ai/Unstable` is the live AI. **`ai/ord`, `ai/ctl` and `ai/stk` are frozen
measurement fixtures** — the pre-overhaul leaf-era tree, a self-play control, and
stock-config-on-our-DLL. Do not edit them, do not fix them, and exclude them from
searches; `tools/docs_audit.py` already skips them.

Deploy derives the engine-side folder from the engine's own `BARb/stable` on
every run, so the bundled `SkirmishAI.dll` always matches the installed engine.
This is what makes the variant survive BAR engine updates.

### How the AngelScript is laid out

Every `manager/<name>.as` is a SHIM: a table of contents that `#include`s the
real code from `manager/<name>/`. Edit the parts, not the shim — except to add a
part, which means adding a line to the shim.

**The include order in a shim is load-bearing, but narrowly.** `CScriptBuilder`
adds a section before walking that section's own includes, depth-first in listed
order. What actually breaks is only a **global's INITIALIZER expression** reading
a symbol declared in a later file. AngelScript registers every type and global
across all sections before compiling any function, so functions, parameter types
and ordinary reads inside function bodies are order-independent — this tree
proves it and runs (`market/want_super.as` reads `Base::gAnchor` from a namespace
included four lines later). An earlier checker that enforced the stricter rule
produced 250 false positives. `python tools/as_scope.py` reproduces the real walk
and reports the two failures that do bite: a global initializer reading a later
symbol, and a local read outside its declaring block.

Both `AiMakeTask`s are pipelines: `builder/maketask.as` and `factory/maketask.as`
are short ordered lists of named rules that live in the sibling `rules_*.as`. A
rule returns null to pass. **Where a new rule goes in that list is the design
decision** — see "The path fires" below.

`script/side.as` holds `SideDef3`/`SideName3`, outside every namespace, which is
how an Armada/Cortex/Legion triple gets resolved. Use it rather than writing
another `if (side == "cortex")` chain.

Files are kept under ~600 lines deliberately: above that, work degenerates into
grep-an-anchor-and-blind-replace, and an anchor that does not match fails
silently. That has eaten edits here at least five times.

**Component ownership lives in the `ai-*` skills**: `ai-military`, `ai-placement`,
`ai-nukes`, `ai-commander`, `ai-air`, `ai-auction`, `ai-eco-pricing`,
`ai-risk-model`, `ai-army-composition`, `ai-builder-crew`, `ai-couplings`. Each
answers: what owns which decision, the decision chain, the log lines that expose
it, and its tunables. **Load the skill instead of reading the source tree** —
that is what they are for, and it is the cheapest path to a correct answer.

Four skills and thirteen agent files were deleted 2026-08-31 for teaching a model
this AI no longer uses. Do not restore them; the reasons are in
`docs/25-silent-failures.md`. Current model: `docs/23-the-plan.md`,
`value-paradigm`, `docs/21-simplification.md`, `docs/22-macro-demand.md`.

**A new tunable or mechanism is not finished until the dashboard shows it.**
`tools/dashboard.py` is apexearth's interface to this AI — he does not run the
CLI tools — so a knob that exists only in `tunables.as` is a knob he cannot
reach, and a modoption missing from `dev_tunables.lua` is silently ignored in
game. Load the **`dashboard-ui`** skill before adding one. `check.py` runs
`tools/dashboard_audit.py`, which reports any tunable the guided view has never
seen, any it names that no longer exists, and any it offers that nothing reads.

### The four lists, and what goes in each

- **Commit message** — what changed and what was measured, next to the diff.
- **`ISSUES.md`** — what is wrong, with evidence, and not yet fixed. Add here
  rather than re-deriving the same complaint next session.
- **`USER-FEEDBACK.md`** — the standing brief of what apexearth actually wants,
  with unresolved items marked. **Read it before starting work.** Several entries
  have been raised three or four times without being fixed — base sprawl, never
  reclaiming old buildings, army not on the front line, naval players idle.
  Git history says what was done; this says what was asked for.
- **`TODO.md`** — named plays and unbuilt behaviours in his own words: the
  tick-spam distraction, the surprise air-eco raid, the saved-up nuke salvo,
  rezbots eating what the squad kills. Nothing else records them.

An entry is deleted when it is built and measured — not marked FIXED forever.

**`CHANGES.md` is FROZEN** (apexearth 2026-08-27: "stop putting changes in
CHANGES.md... you can instead look at git history"). It remains as history for
everything before 2026-08-28. Do not read it for current behaviour and do not
append to it.

## Commands

```bash
python tools/dashboard.py                    # local web UI: browse runs, launch, deploy, tunables
python tools/bar_env.py                      # show resolved paths
python tools/deploy_ai.py status             # what is deployed, and is it in sync
python tools/deploy_ai.py deploy Unstable    # repo -> live install
python tools/deploy_ai.py pull Unstable      # live install -> repo (after in-place edits)
python tools/deploy_ai.py gadgets            # install dev gadgets into BAR.sdd
python tools/deploy_ai.py patches            # apply game-patches/*.patch to BAR.sdd

python tools/unitsync.py maps comet          # resolve map display names
python tools/unitdef.py corasy --builders    # cost, display name, who can build it
python tools/unitdef.py legsy --builds       # what it builds
python tools/unitdef.py --trees              # both game trees and their dates

python tools/run_match.py --a Apex:Unstable:standard --b BARb:stable:hard \
    --map "Comet Catcher" --minutes 60 --seed 1
python tools/run_match.py ... --per-side 8 --watch   # windowed, real time, watchable

python tools/review.py <run> --control <run>  # THE way to judge a run
python tools/battery.py                       # the regression instrument after a behaviour session
python tools/test_raid.py                     # early defence: scripted raids, no turrets, pass/fail
python tools/test_earlyfight.py --baseline <set>
python tools/test_frontline.py                # the line + per-mex guns contract
python tools/check.py                         # pre-deploy: bad JSON, dead unit names, audits
python tools/composition.py <tournament>      # where the metal actually went
python tools/frametime.py <run>               # per-section maxMs; needs apex_perf=1
python tools/tl.py tournaments/<run>          # paired timeline by game minute
python tools/fight1v1.py <run-dir>            # army trade efficiency, in metal
python tools/trace_flow.py <run>              # did the pooling strategy actually work
python tools/run_tournament.py --a Apex:Unstable:standard --b BARb:stable:hard \
    --maps "Comet Catcher" --games 10
python tools/run_tournament.py --report
```

Batch output lands in `tournaments/<stamp>-<slug>/`, not `matches/`. A 27
game-minute match completes in ~44 s wall (~37× realtime) with a warm archive
cache; a cold cache adds ~35 s.

`python tools/review.py <run> --control <run>` runs the full checklist and
withholds a verdict when a gate fails — see the `bar-benchmark` skill for the
nine-step breakdown and why each step is there.

## Failure modes that are SILENT — the checklist

Every one of these produced a confident, wrong conclusion here. They share a
shape: **the thing didn't work, and nothing said so.** One line each; the
mechanism, the date and the wrong conclusion are in
**`docs/25-silent-failures.md`**, keyed by these IDs. Read an entry before acting
on the hazard it names.

- **S1** A variant without its own shortName loads stock BARb in every
  multiplayer game. Test with `run_match.py --drop-ai-version`.
- **S2** `ApexActive()` used to latch false in a solo 1v1 and fall through to
  stock — removed 2026-08-14, now always `true`. Confirm apex ran with
  `grep "apex:" infolog.txt`.
- **S3** An AngelScript compile error disables the variant and the match still
  reports a normal result. **Always** grep after a run:
  `grep -oiE "\(?[0-9]+, [0-9]+\) : ERR|Fix compilation errors" infolog.txt` —
  and **never anchor on a filename**, because the warnings-as-errors failure
  prints with no file.
- **S4** AngelScript has no forward declarations; `CCircuitDef@ Foo();` parses as
  a global property. Just call the function.
- **S5** Asking a unit to build something no constructor of ours can build is a
  silent no-op. Build options are per-unit — check the unit's `.lua` def.
- **S6** `aiMilitaryMgr.quota.attack` caps units SENT to attack, not units BUILT.
- **S7** Engine callbacks can be dead — every `Game_getTeamResource*` read -1.
  Log a binding's raw return once before building logic on it. Route around via a
  synced gadget publishing a rules param.
- **S8** `deploy_ai.py deploy` does NOT ship the gadget; a modoption
  `dev_tunables.lua` does not publish is silently ignored, so every arm of a
  sweep runs the default. Verify: `grep -c apex_yourname
  "$BAR_SDD/luarules/gadgets/dev_tunables.lua"`.
- **S9** `ai.GetBuilderThreatAt(pos)` crashes on an off-map position and reads
  zero 97% of the time. Guard with `OnMap()`; do not build a trigger on it.
- **S10** Never answer a unit question from a filename search. Use
  `tools/unitdef.py`.
- **S11** "This unit does not exist" is always a claim about ONE tree. The pinned
  `BAR.sdd` and upstream `vendor/bar` disagree.
- **S12** A duplicate `RegisterObjectMethod` kills the AI at init;
  `result.json` says `crashed: true` with empty stats. Grep
  `asALREADY_REGISTERED`.
- **S13** An order is not applied when issued, and the lag scales with sim speed.
  Count what was SENT; use the read only to confirm. See `async-sim-orders`.
- **S14** `AiMakeTask` is a RE-ELECTION, called on every task update. A rule that
  `Enqueue`s before returning enqueues once per update and orphans all but the
  first.
- **S15** A watch game's infolog reaches the match dir only at game END. Check
  mtime before reading one line of `matches/_engine*/infolog.txt`.
- **S16** `result.json`'s `teams[].team` is the SPEC index, not a game team —
  anchoring on it inverts every side-swapped game.
- **S17** Aggregate over the right unit. A team strategy that treats one player
  differently cannot be judged by a team-wide average.
- **S18** `str.replace`/`sed` anchors that don't match do nothing, quietly.
  Assert the anchor exists first. `ai/Unstable/` is all LF as of 2026-09-04;
  `cpp/`, `changes/` and some root `.md` still have CR.

## Other gotchas that cost time

- **`MinSpeed`, not `MaxSpeed`, speeds up a headless run.**
  `GameServer::UserSpeedChange` clamps the starting speed into
  `[MinSpeed, MaxSpeed]`.
- **`GameType=Beyond All Reason $VERSION;`** — `$VERSION` is *literal*. CI
  substitutes it when packing for rapid; a raw `.sdd` checkout never does. That
  same string is what flips BAR's internal dev mode on (`luarules/gadgets.lua`
  greps `Game.gameVersion` for it).
- **`FixedRNGSeed`**, not `RandomSeed` — and it does **not** make runs
  reproducible; the DLL is multithreaded (first-T2 at 5.2, 6.9, 9.1, 9.8 min on
  one seed). Never read a single-run delta as an effect.
- **Map names in start scripts are display names** ("Comet Catcher Remake 1.8"),
  not filenames. Use `tools/unitsync.py`.
- **On Windows the AI binary is `SkirmishAI.dll`** — the `lib` prefix is Linux
  only.
- Delete `<writedir>/LuaUI/Config` between headless runs. The harness does this.
- Custom AI versions are **not** in Chobby's `aiCustomData.lua`, so the lobby
  shows them uncurated. Any profile you want selectable must be declared in your
  own `AIOptions.lua`; `ai/Unstable/engine-side/AIOptions.lua` declares the single
  `standard` entry.
- Engine dirs are wiped on BAR update. Re-run `deploy_ai.py deploy` afterwards.

## The Brain drives the factories — `factory.json` is mostly NOT in the loop

`Market::ConOrderFor` (`brain/market/production.as`) is the only path to what a
factory builds. While the Brain drives a line, `factory.json` tier tables and
`response.json` decide nothing. Days were spent tuning factory.json weights to
fix "only Hounds get built" when the composition was decided elsewhere entirely.
**Attribute a composition problem to the producing code before touching any
config table** — read `apex: decide ... -> produce:`, `apex: worth` and
`apex: lineclass`.

## build_chain.json evaluates in ways the config does not suggest

Hubs fire on parent completion, conditions are sampled once and never re-checked,
and `prevent` caps preventive defence. The `land` ladder is deliberately EMPTY
and `AiMakeDefence` only calls `NoteSite`, so this file spends nothing on ground
defence — the market owns it. Verified 2026-07-29 against `BuildChain.cpp`,
`BuilderTask.cpp`, `BuilderManager.cpp`.

## T3 affordability is a statement about INCOME, not about the AI

Real costs from the unit defs: **corgant 8400, corshiva 1550, corcat 4900,
armbanth 13500, corjugg 20000, corkorg 29000**. At the 40 metal/s benchmark T3 is
two or three units a game; in a hosted +40% game a player was observed at **398
metal/second**, where a gantry is 21 seconds of income — so the same unit is
unaffordable in one game and trivial in another. What inverts the argument is the
RATIO of cost to income and whether cheaper growth is still available, not a line
on the income axis. **Read the actual income before calling T3 unaffordable or
broken** — and note that stock BARb out-T3s us by default on a bonused economy.

## "The path fires" is not evidence that the change is good

Firing proves a change is *wired up*. It says nothing about what it
**displaced**, and here almost everything worth adding displaces something.
Twelve individually-reasonable, individually-confirmed-firing changes in one
session took head-to-head from 2-2 to **0-8** and metal produced from 140,940 to
**32,648**, because every one spent constructor time and constructor time is the
economy. Tuning the constants afterwards moved it the wrong way. Full table and
the list of twelve: `docs/25-silent-failures.md`.

So:

- **Judge a behaviour change on composition, not on its log line.**
  `python tools/composition.py <tournament>` reports where the metal went.
  `mex upgrades 2 vs 8` is the same answer in every game; who won 8 games is a
  coin flip.
- **One behaviour change at a time**, with composition after each. A batch tells
  you the batch is bad and nothing about which member.
- **Separate rules that SPEND from fixes that STOP something.** Removing a
  deadlock, a stampede or a permanently-on tower costs no build power and is
  near-free to re-apply. A new rule that enqueues work is never free, however
  cheap the unit.
- **Watching a replay tells you a behaviour looks smart. It cannot tell you what
  it cost.**

See `docs/20-brain-overhaul.md` for the design that addresses this — rules
propose Wants and one arbiter ranks them, instead of the first rule in an ordered
list winning. `docs/17-behaviour-config.md` traces every behaviour.json knob to
the line that consumes it. `docs/21-simplification.md` and
`docs/22-macro-demand.md`: a price built from twelve multiplicative terms cannot
be steered by changing one of them, and a decision asked of a single constructor
cannot express what the base needs.

## Instrument first. This is the rule that matters most.

apexearth, 2026-08-30: *"I see it terribly often that you make changes which have
little or no effect."* He was right — four changes that day, every one inert. The
list, and the three ways a measurement lies here, are in
`docs/25-silent-failures.md`.

Before changing a rule:

1. **Prove it executes.** Find the log line, or add a counter, that says this
   code ran in a real game. A gate nothing reaches is dead code.
2. **Prove it decides.** Show that its output is what selects the outcome, not
   one of eleven other multipliers.
3. **Then change it** — and if the instrument shows the decision did not move,
   SAY SO. Shipping an inert edit is worse than shipping nothing, because it
   spends his review and hides the real cause.

Three standing cautions: a **sampled log is not a census** (say so in the line);
a **metric that cannot distinguish the two states you care about is not
evidence**; **two seeds cannot resolve a change** — if you have two runs, you
have an anecdote.

## Ask before inventing policy

apexearth, after a hard cap of 4 was added to something he had twice said should
scale with the economy: *"damn you have me worried about whatever other bad ideas
you may randomly add. You should update claude.md so you ask more questions
before just making decisions like that."*

The failure is not being wrong once. It is deciding a POLICY question — what the
AI is allowed to do — as if it were an implementation detail, and burying the
answer in a constant. These four keep happening:

- **Hard caps and ceilings.** He has said twice that nothing should have a hard
  cap; everything scales with economy and progression. If something is built too
  often, fix its VALUE relative to alternatives, not the eleventh one.
- **Exclusivity.** "Only the eco lead may build reactors." This shipped for weeks
  and made a solo player never build a reactor at all. A role may change how
  OFTEN or how MUCH; it must not decide WHETHER.
- **Turning a behaviour off** to fix a symptom, rather than finding what starves
  it. Front-line nanos got defaulted off after one arm; he wanted them on and
  tuned.
- **Thresholds pulled out of the air.** A gate at "60 metal/s" is a claim about
  the game. Derive it, measure it, or ask — and say which of the three it was.

`docs/23-the-plan.md` says why all four are the same mistake: **order, numbers
and limits are OUTPUTS of the ETA arithmetic.**

What to do instead, in order of preference:

1. **Derive it from the economy** — income, bank, what the thing costs, what it
   returns, and how much sooner it makes the target arrive. That is the answer he
   gives every time he is asked.
2. **Ask.** One sentence: "should X be capped, or scale with income?" He answers
   in seconds and the answer is usually "scale".
3. **A named constant**, with the derivation in the commit message.

**A TUNABLE IS THE LAST RESORT, NOT THE SAFE MIDDLE.** It used to be listed as
option 2, and being cheapest it was chosen almost every time: measured 2026-08-30,
**404 declared, 316 read at exactly one call site, 360 never overridden in a
single recorded run.** Each costs four registration sites plus a line of
apexearth's attention. Create one ONLY if you will sweep it this session and
report the sweep; otherwise use a named constant. `python tools/dashboard_audit.py
--stale` is a cull list, and folding one back into a constant is always welcome.

Not every choice needs a question — fixing a null deref, wiring a rule that
already exists, following a stated preference. The trigger is: *am I deciding
what the AI is ALLOWED to do, rather than how to do what it was already meant to
do?* If yes, ask.

## The frame budget: spread work, never batch it

This is game development and the sim frame is the hard constraint. apexearth,
2026-08-31: *"If we have any operations which happen every five seconds or
something along those lines, we need to make sure that we spread out that
operation across every frame... if we have five hundred builders, and we want
them to do a thing every five seconds, then we should calculate how many frames
happen in five seconds and spread out the processing unit by unit throughout the
frames. So we do not do a big operation in a single frame."*

**A periodic operation over N things is N/frames of work per frame, not N work
every period.** Lowering the FREQUENCY of a bulk pass does not fix a spike; it
makes the spike rarer. Slice it, keep a cursor, resume next frame.

Before adding any periodic pass: how many things does it touch, how does that
grow with base size, and what is the per-frame slice? `apex_perf=1` plus `python
tools/frametime.py <run>` gives `maxMs` per section — **a section whose `maxMs` is
many times its `avgUs` is batching, and that is the bug.** Three measured
violations and what fixing them bought (worst frame 137.8 → 34.1 ms) are in
`docs/25-silent-failures.md`.

## Delegate only when asked, and keep agents short-lived

The fleet-of-agents workflow was tried and **measured worse**: single agents
reached 345k, 337k and 328k tokens and drove usage UP, because continuing an
agent replays its whole transcript. apexearth: *"You're wasting a lot of
tokens/usage by doing it like this. Prefer to NOT have long running agents."*

Work directly by default. Spawn agents when he asks, or for genuinely parallel
work with **disjoint file ownership** — two agents editing one file is a merge
conflict you will pay for twice. Give each a fresh, bounded task with the three
facts it needs in the PROMPT; two or three exchanges is the ceiling.
Investigation can be parallel; implementation is serial and measured.

The one case where an agent *saves* context: a broad search whose file dumps you
do not need, where you only want the conclusion. Bound it to that.

## apexearth is faster than the benchmark — ask him first

His standing requests live in `USER-FEEDBACK.md`; this is only about workflow.

A watched game returns useful feedback in about **five minutes**. A tournament
with a matched control takes **twenty to thirty**, and on the standard benchmark
it frequently cannot answer the question at all: per-team income there is
4-9 metal/s against 12-41 in a hosted game, so anything gated on income never
fires, and win rate has swung 60% → 10% on an unchanged AI.

So the default order is:

1. **Deploy and hand him a windowed run** (`--watch --speed 5`) — but only when
   he has asked for one, or the work plainly needs his eyes. Do it FIRST, before
   any measuring, so he is watching while other work continues.
2. Act on what he reports. Every diagnosis that has actually landed came from him
   watching: "two v six battles", "Commando as the first unit out of the T2 lab",
   "cons at the front making mexes", "that's a 4v4 map".
3. Use a tournament to **confirm** a mechanism he has already identified, or to
   catch a regression. Not to go looking for one.

Corollary: never leave him idle while a control runs. Launch the watch run, then
do the slow measuring alongside it.

## Harness discipline

- **Never run two matches on one engine write-dir.** Both engines write the same
  `infolog.txt` and config tree; measured 2026-08-15, a watch game beside a soak
  run broke the watch game's AI outright. `run_match.py` pidfile-guards
  `matches/_engine` and auto-suffixes a busy dir, but a hand-launched engine
  bypasses that — check `engine.pid` first.
- **Never edit a file a running tournament uses.** Editing `run_match.py` mid-run
  killed 17 matches with an `AttributeError`. The repo `ai/<variant>/` tree is
  safe to edit while running; deploying is what swaps live files.
- **Kill the waiter with the run.** Killing a tournament has twice left
  `until ...; sleep; done` shells polling forever. Stop the background task, not
  just the processes.
- **`pgrep` DOES NOT EXIST in this Git Bash, and a wait loop that uses it exits
  INSTANTLY.** `pgrep -f foo` returns 127, so `until <done> || ! pgrep -f foo`
  has a condition that is immediately TRUE — the wait never waits and whatever
  is read next is stale. Wait on an ARTIFACT (`until [ -f out/result.json ]`) or
  check processes with PowerShell `Get-Process`.
- **`pkill -f` silently does nothing on Windows.** Use `powershell -NoProfile
  -Command "Get-Process python,spring-headless -ErrorAction SilentlyContinue |
  Stop-Process -Force"`, then verify the count is zero.
- **Run Python with `-u` when redirecting to a log.** Without it the log stays
  empty for the whole run and looks exactly like a dead process.
- **Deploy in the foreground, then background the run.** Deploy → background run
  → keep coding is sanctioned (apexearth 2026-08-27). The one rule inside it: the
  deploy's success must be VERIFIED before the run leans on it — a backgrounded
  `deploy && run &` hides a failed deploy and `FetchSkirmishAILibrary: unknown
  skirmish AI` reads in telemetry as a catastrophic regression that is not one.
- **Deploying while BAR is open fails with `WinError 5`** and leaves the AI folder
  half-written. Check for `spring.exe` / `Beyond-All-Reason.exe` first. A running
  game that blocks a deploy may be killed.
- **Confirm the AI under test is actually running**, via `Load script:
  LuaRules\Configs\Apex\<variant>\...` in the infolog. A replay cannot tell you
  this — in a replay AIs are "remote", `AiLog` output does not appear, and
  `Spring.GetAIInfo` reports `SYNCED_NOSHORTNAME`.

## Conventions

- Python 3.13, standard library only. No new dependencies without a reason.
- Tools import `bar_env`; they never hardcode install paths.
- Treat `reference/barb-stable/` as read-only — it's the diff baseline.
- Keep `ai/<variant>/` as the source of truth. If you edit configs directly inside
  `BAR.sdd` while iterating, run `deploy_ai.py pull <variant>` afterwards or the
  work is lost on the next deploy.
- Line endings are LF (`.gitattributes`). `ai/Unstable/` is fully LF as of
  2026-09-04; `cpp/`, `changes/` and some root `.md` still contain CR. Check
  before anchoring an edit there, or use `tools/normalize_eol.py`.

### Comments — write far fewer than feels natural here

The long "tried X, measured Y, reverted" blocks already in `factory.as` are
load-bearing: they stop a failed experiment being retried. That is not licence to
add more. Four rules, each from a real mistake:

- **A code comment is not a session transcript.** apexearth, 2026-08-14: "quit
  flooding our comments with events of our work, just state a concise 'why' and
  let that be it." One line: what this code does that looks wrong otherwise, and
  the reason.
- **Never state a cause you did not measure.** If it was reasoning, say so or
  leave it out. Wrong comments are worse than none.
- **Don't inline the commit message.** What was tried, what it scored, why it was
  reverted goes in the commit message.
- **Change the code, change the comment.** Re-read every comment attached to a
  line you touch.
- **Never write a finding into a comment.** Measurements, unit costs, timings,
  "X never happens", "Y does not exist" are all findings — they belong in the
  commit message, or `ISSUES.md` while unresolved, or nowhere. A comment saying
  "Legion has legsy but no advanced shipyard" was written from a single failed
  glob, was false, and sat in the code asserting it as fact.

  What may stay is a **mechanism you can see in the code being read** — an engine
  gate that returns early, an index shared between two files, a parser quirk. Not
  evidence for a decision; the reason a line cannot be deleted.

  Corollary: **absence is the least reliable finding of all.** Not finding a file,
  a unit or a call proves the search failed, not that the thing is missing. Never
  record "does not exist" on one search.

Default to none. Three lines is a lot; ten needs a reason.

## If contributing upstream

Split by layer: game-side configs → `beyond-all-reason/Beyond-All-Reason`
(`luarules/configs/BARb/`); C++ or AngelScript-binding changes →
`rlcevg/CircuitAI` branch `barbarian`.

BAR's `AI_POLICY.md` requires **explicit disclosure of AI-assisted code in the
PR**, and human verification of it. Undisclosed use gets the PR closed.
