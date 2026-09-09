# bar-ai — working notes for Claude

AI development for **Beyond All Reason**, the RTS on the **Recoil** engine (a
Spring fork). This repo is the source of truth for a custom AI; the live game
install is a deploy target. `tools/bar_env.py` resolves every path at runtime —
never hardcode one. `BAR-GUIDE.md` covers game mechanics.

**This file is an index, not a manual.** It carries the intent, the rules that
govern a session, and a router. Everything else is one lookup away, and the
linked file is authoritative where it disagrees with a summary here.

## The one idea

Every decision answers one question: **what is the fastest path to the state we
are trying to reach?** The AI names a target — so much army, or that much army
with a fusion behind it — and takes whichever move makes it arrive soonest, under
one standing obligation: army and defence stay at their proper share of the
economy we have built.

The consequence: **order, numbers and limits are OUTPUTS.** A threshold, a build
order or a cap in this AI is a bug in the model wearing a fix's clothing. Read
`docs/23-the-plan.md` (2 pages) before anything else; `value-paradigm` is the
operational skill. Where a doc, skill or comment still argues from "above N
metal/s", the plan wins and the doc is stale.

`docs/24-how-units-fight.md` is the combat counterpart — apexearth's directives
and ONLY his. A session may add to it from something he said, never from its own
ideas. Where code disagrees with it, the code is stale.

## How to work here

- **Instrument first.** *"I see it terribly often that you make changes which
  have little or no effect."* Prove the code executes (find the log line), prove
  its output is what decides the outcome, then change it — and if the instrument
  shows the decision did not move, SAY SO. Four inert changes in one day:
  `docs/25-silent-failures.md`.
- **Ask before inventing policy.** Caps, exclusivity, switching a behaviour off,
  thresholds from the air — these are decisions about what the AI is *allowed* to
  do, and they are his. Derive it from the economy, or ask; a tunable is the last
  resort, not the safe middle (404 declared, 360 never once overridden).
  `docs/26-working-rules.md`.
- **"The path fires" is not evidence.** Firing proves a change is wired up, not
  that it was worth what it displaced. Twelve individually-confirmed-firing
  changes took head-to-head 2-2 → **0-8** and metal 140,940 → **32,648**. Judge
  on `composition.py`, one change at a time.
- **Two seeds cannot resolve a change.** If you have two runs, you have an
  anecdote. A sampled log is not a census.
- **Spread work across frames, never batch it.** A periodic pass over N things is
  N/frames per frame. Lowering the frequency makes a spike rarer, not smaller.
  A section whose `maxMs` is many times its `avgUs` is batching, and that is the
  bug (`apex_perf=1` + `frametime.py`).
- **Write far fewer comments than feels natural.** One line: what looks wrong
  otherwise, and why. Never a finding, a measurement or a session transcript —
  those go in the commit message or `ISSUES.md`. `docs/26-working-rules.md`.
- **Work directly; delegate only when asked.** The fleet-of-agents workflow was
  measured worse and scrapped. The one case an agent saves context: a broad
  search whose file dumps you don't need.

### Context discipline

Measured 2026-09-04 over 20 sessions: **2.05M tokens of conversation, 1.77M of it
Bash (86%)** — 3,860 calls, 535k of command text *sent* plus 1,236k returned. The
average call was 138 tok in / 323 out, so the cost is **volume**, not big dumps.
`Read` was 87k across 57 calls.

| habit | cost / 20 sessions | do this instead |
|---|---|---|
| inline `python - <<'PY'` to edit | **356k** (302k of it command text) | `Edit`. `ai/Unstable/` is all LF — the CRLF reason is gone |
| ad-hoc grep/sed over `*.as` | **478k** | load the owning skill, then `grep -n` one symbol and `sed -n` a window |
| hand-rolled infolog greps | **270k** | `review.py` / `trace.py` / `diagnose.py` |
| `cat` of a whole file | **148k** | `grep -n`, then `sed -n 'A,Bp'` |

- The Bash **cwd persists** — 1,128 of 3,860 calls opened with a redundant `cd`.
- **Batch independent probes into one call**; each round trip costs a turn.
- **Ask for the answer, not the corpus**: `grep -c`, `| sort | uniq -c`, `| head`.
- **Exclude `vendor/`, `matches/`, `changes/`, `reference/`** from any repo-wide
  search; they are upstream or history, never the answer.
- **Load the owning skill instead of reading the source tree.** That is what they
  are for and it is the cheapest path to a correct answer.

## Before you do X, read Y

The router. Left column is what you are about to do; **S**n is
`docs/25-silent-failures.md`, which carries the mechanism, the date and the wrong
conclusion each one produced.

| About to… | Read first |
|---|---|
| **judge any run** | `review.py <run>` — gate 1 IS the compile/crash/did-it-run check. `bar-benchmark` skill |
| **believe a match result** | **S3** compile error → variant silently near-stock · **S12** duplicate binding → empty stats · **S15** infolog may be days stale · **S16** `teams[].team` is the spec index · **S17** aggregate over the right unit · **S19** the deployed script can change mid-sweep — classify each game from its own log |
| **run a sweep of a tunable** | **S8** — deploying the AI does NOT deploy the gadget; unpublished modoptions run the default with no error |
| **launch or kill a run** | `docs/26-working-rules.md` — one match per write-dir, `pgrep`/`pkill` are dead here, `-u` when logging |
| **start a session when another may be running** | `python tools/lane.py init <name>` — `docs/28-parallel-sessions.md`. Claims are per session; a session with none is refused by every writing tool, because `Apex:Unstable` is HIS slot (the dashboard, his games). `BARAI_LANE=shared` names it on purpose |
| **touch army / fighting** | `docs/24-how-units-fight.md` first, then `ai-military`, `ai-army-composition` |
| **touch what gets built** | `ai-auction`, `ai-eco-pricing`, `docs/22-macro-demand.md`. Composition is decided in `manager/brain/market/`, **not** in `factory.json` — `docs/04-json-config-reference.md` |
| **touch where buildings land** | `ai-placement`, `ai-risk-model` |
| **touch builders / crews** | `ai-builder-crew` · **S14** `AiMakeTask` is a RE-ELECTION, so enqueuing in a rule orphans all but the first |
| **read a unit's cost or buildoptions** | `tools/unitdef.py`. **S10** never glob for a unit file · **S11** the two game trees disagree |
| **add a gate, target, prior or role rule** | `ai-couplings` — then reread "Ask before inventing policy" |
| **add a tunable or a want kind** | `dashboard-ui` — it is not finished until the dashboard shows it. One line in `tunables.as`; the reasoning goes in `docs/27-tunable-rationale.md` |
| **change a default, or ask why it is what it is** | `docs/27-tunable-rationale.md` — keyed by `TUNE_` name. Several defaults are measured-and-left-off; the A/B is recorded there |
| **count factories, tasks or in-flight builds** | `async-sim-orders` · **S13** an order is not applied when issued, and the lag scales with sim speed |
| **write AngelScript** | `docs/05-angelscript-api.md` · **S4** no forward declarations · **S5** a unit can only build what its own def lists · `tools/as_scope.py` |
| **edit any `.as` file** | **S18** an anchor that does not match does nothing, quietly. Assert it exists |
| **commit a change that touched comments** | `comment_audit.py` — a run report belongs in the commit message, a negative result in `docs/27` keyed by symbol. The rule alone failed for three weeks; this is the check |
| **touch C++** | `cpp-dll` skill, `docs/06-building-the-dll.md` |
| **build the DLL** | `python tools/build_dll.py` — a failed ninja leaves the OLD dll and deploy still says `(local build)` |
| **judge whether a rule DOES anything** | `python tools/deadcheck.py <run>` — the silent no-op is this repo's only real bug class; `docs/26` has the counting convention |
| **build on an engine binding** | **S7** callbacks can be silently dead — log the raw return once · **S9** `GetBuilderThreatAt` crashes off-map and reads zero anyway |
| **create or rename a variant** | **S1** without its own shortName it loads stock BARb in every multiplayer game · `docs/03-barb-architecture.md` |
| **reason about the economy or T3** | `docs/10-bar-game-concepts.md`, `eta-objective`. The same unit is unaffordable at 40 metal/s and trivial at 398 |
| **work on nukes / air / the commander** | `ai-nukes` · `ai-air` · `ai-commander` |
| **diagnose why we lost a fight** | `fight-analysis` skill, `tools/deaths.py` |
| **check a game against his complaints** | `game-audit` skill |
| **investigate a desync** | `desync-check` skill |
| **find a path or an engine version** | `python tools/bar_env.py`, `docs/01-local-environment.md` |

## Commands

Verified 2026-09-04, with output size — do not re-derive these as pipelines.

```bash
python tools/review.py <run> [--control <run>]  # 45 lines. THE way to judge a run
python tools/trace.py latest --filter=decide    # apex: lines for one tag, minute-stamped.
                                                # tags: decide defplace fronttowers targets
                                                #       posts eta defprice defsite
python tools/diagnose.py <run>                  # 3 lines when clean
python tools/check.py 2>&1 | tail -15           # 126 lines unpiped -- always tail it
python tools/deadcheck.py <run>                 # rules that never fired
python tools/build_dll.py [--deploy]            # build that cannot lie about succeeding
python tools/as_scope.py                        # 2 lines
python tools/comment_audit.py                   # run reports + essays in YOUR diff
python tools/context_size.py --since            # what the repo costs to read
python tools/unitdef.py <unit> [--builders|--builds|--trees]   # 8 lines
python tools/deploy_ai.py status|deploy Unstable|pull Unstable|gadgets|patches
python tools/lane.py init <name>|status|list|drop <name>   # private build/deploy/run slot
python tools/dashboard.py                       # his UI: runs, launch, deploy, tunables
python tools/run_match.py --a Apex:Unstable:standard --b BARb:stable:hard \
    --map "Comet Catcher" --minutes 60 --seed 1     # add --per-side 8 --watch to watch
python tools/battery.py                         # the regression instrument after a behaviour session
python tools/composition.py <tournament>        # where the metal actually went
python tools/ecotimeline.py <tournament|match>  # energy + metal minute by minute per arm;
                                                # bank pinned at 0 = e-stall, pinned full = waste
python tools/frametime.py <run>                 # per-section maxMs + the 16-AI verdict.
                                                # apex_perf=1; the harness passes it now
python tools/test_raid.py | test_earlyfight.py | test_frontline.py
python tools/run_tournament.py --a … --b … --maps … --games 10   # then --report
```

Also: `tl.py` (paired timeline), `fight1v1.py` (trade efficiency in metal),
`trace_flow.py` (did pooling work), `unitsync.py` (map display names),
`normalize_eol.py`, `dashboard_audit.py --stale`. Batch output lands in
`tournaments/<stamp>-<slug>/`. A 27 game-minute match takes ~44 s wall (~37×
realtime) warm.

## The four lists

- **Commit message** — what changed and what was measured, next to the diff.
- **`ISSUES.md`** — what is wrong, with evidence, not yet fixed. Add here rather
  than re-deriving the same complaint next session.
- **`USER-FEEDBACK.md`** — the standing brief of what apexearth wants, unresolved
  items marked. **Read before starting work.** Several entries have been raised
  three or four times without being fixed. Git history says what was done; this
  says what was asked for.
- **`TODO.md`** — named plays and unbuilt behaviours in his own words. Nothing
  else records them.

An entry is deleted when it is built and measured — not marked FIXED forever.
**`changes/CHANGES.md` is FROZEN** (2026-08-27): history only, do not read it for current
behaviour and do not append.

## Layout, in one place

| | |
|---|---|
| live AI | `ai/Unstable/{engine-side,game-side}` — the only tree you edit |
| three layers | JSON config → AngelScript → C++. The first two are hot-swappable; prefer them |
| shims | every `manager/<name>.as` is a table of contents `#include`ing `manager/<name>/`. Edit the parts |
| paths, engine, game trees | `python tools/bar_env.py` · `docs/01-local-environment.md` |
| repo tree | `README.md` |

Four skills and thirteen agent files were deleted 2026-08-31 for teaching a model
this AI no longer uses. Do not restore them (`docs/25-silent-failures.md`).
