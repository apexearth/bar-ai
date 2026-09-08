# Silent failure modes — the full evidence

`CLAUDE.md` carries a one-line checklist of these. This file carries the proof:
the mechanism, the date it was measured, and what the wrong conclusion was. Read
the checklist every session; read an entry here when you are about to act on the
hazard it names, or when you want to know whether it still applies.

Every entry shares one shape: **the thing didn't work, and nothing said so.**

---

## S1 — Multiplayer silently runs stock BARb unless the variant has its own shortName

The lobby protocol's `ADDBOT` carries a single `aiLib` field and no version.
Chobby's `AddAi` sends `concat("ADDBOT", aiName, battleStatus, teamColor, aiLib)`
and `_OnAddBot` sets only `status.aiLib`. So a hosted game's start script has
**`Version` empty**, and `AILibraryManager::FittingSkirmishAIKeys` filters on
version only "if one is specified i.e. non-empty"; `ResolveSkirmishAIKey` then
takes the highest by `VersionCompare`, and `"apex" < "stable"`.

A version-only variant therefore loads stock BARb in every multiplayer game,
with no error anywhere. Single-player is unaffected: `interface_skirmish.lua`
writes the script locally and does pass `Version = data.aiVersion`, which is why
this only ever showed up when hosting.

Reproduce with `run_match.py --drop-ai-version`.

## S2 — A plain 1v1 used to run stock on purpose (REMOVED 2026-08-14)

`world.as`'s `ApexActive()` latched false whenever the AI's own ally team had no
teammates (`mates.length() <= 1`), so `Builder::MakeTaskInner` and five other
call sites fell through to stock CircuitAI logic for the whole game — measured
2026-08-14 as zero `apex:` log lines over 4628 frames in a watched 1v1.

apexearth judged that measurement stale against everything fixed since and had
the gate removed outright. `ApexActive()` now unconditionally returns `true`, the
`apex_solo_stock` tunable is gone, and apex runs its own logic in every game
regardless of ally count.

## S3 — An AngelScript compile error disables the variant and the match still runs

It plays as near-stock and reports a normal result. A 12-minute "the rush never
fires" investigation was really a one-line syntax error.

**Do NOT anchor the grep on a filename.** AngelScript treats warnings as errors,
and that failure prints as ` (0, 0) : ERR : Warnings are treated as errors by the
application` with no file — a filename-anchored grep reads a variant that never
compiled as a clean run. Cost a full round of false "validated" reports
2026-08-20 (a `uint`/`int` compare in `maketask.as`).

## S4 — AngelScript has no forward declarations

`CCircuitDef@ Foo();` parses as a *global property* and yields `Name conflict`.
The module sees all its own functions regardless of order — just call it.
Globals and types *do* need to be declared before use.

## S5 — Asking a unit to build something no constructor of ours can build is a no-op

Forcing `coravp` while owning only a bot lab produced 33 dropped requests and
zero errors. Constructor build options are per-unit: `corck` builds only
`coralab`, `corcv` only `coravp`. Check the unit's `.lua` def.

## S6 — `aiMilitaryMgr.quota.attack` caps units SENT to attack, not units BUILT

Setting it to suppress army production does nothing; the factory keeps going.

## S7 — Engine callbacks can be silently dead

Every `Game_getTeamResource*` call was measured returning -1 for all teams,
including the AI's own.

**The mechanism previously recorded in CLAUDE.md was wrong**: it said
`AI_TEAM_IDS` in `rts/ExternalAI/SSkirmishAICallbackImpl.cpp` is "declared
`= {{-1}}` and never assigned", but in `recoil_2026.07.04` it *is* assigned, at
line 5535 (`AI_TEAM_IDS[ai->GetSkirmishAIID()] = ai->GetTeamId()`), and the -1
comes out of `aiGetTeamResource`'s `AlliedTeams` gate. The observation has not
been re-measured on this engine — treat both the reading and the explanation as
unverified.

Before building logic on a binding, log its raw return once and confirm it is
real data. Route around via a synced gadget publishing a game rules param
(`Game_getRulesParamFloat` is not gated); see
`game-patches/gadgets/dev_team_income.lua`.

## S8 — Deploying the AI is NOT deploying the gadget

`deploy_ai.py deploy <variant>` ships `tunables.as`; only `deploy_ai.py gadgets`
ships `dev_tunables.lua`, and that gadget is the only thing that republishes
`--modoption apex_*` as rules params. Add a tunable to the repo's list, deploy
the AI, and every arm of your sweep runs the compiled default — with no error
anywhere.

Measured 2026-08-31: a four-arm sweep of `apex_army_eco_s` was reported as a
curve, was four runs of one configuration, and produced a confident "the target
does not control army share" that was withdrawn an hour later.

Verify with `grep -c apex_yourname "$BAR_SDD/luarules/gadgets/dev_tunables.lua"`.

## S9 — `ai.GetBuilderThreatAt(pos)` crashes off-map and reads zero almost everywhere

`CThreatMap::GetBuilderThreatAt` bounds-checks with an `assert` — compiled out in
release — then indexes `surfThreat` unchecked. Sampling a ring of radius 1500
around a base near the map edge read off-map memory and killed the engine at
frame 3 (0xc0000005).

Guard every position with `OnMap()` (`script/world.as`);
`AiTerrainWidth()`/`AiTerrainHeight()` are bound. Even so, the value is 3%
nonzero across ten games, which is why the old commander retreat never fired —
do not build a trigger on it.

## S10 — Never answer a unit question from a filename search

A `glob legasy.lua` returning nothing was read as "Legion has no advanced
shipyard" and written into a code comment as fact. Legion's advanced shipyard is
`corasy`, which `legnavyconship`/`legcs`/`legch` list in `buildoptions`.

Unit defs sit in arbitrary faction subdirectories, display names live in
`language/en/units.json`, and what a faction can *build* is neither — it is the
buildoptions of its constructors. One search answers none of those three
questions. Use `tools/unitdef.py`.

## S11 — "This unit does not exist" is always a claim about ONE tree

`BAR.sdd` is pinned at 2025-11-28 and `vendor/bar` tracks master, so absence in
one proves nothing about the other — `legadvshipyard` is upstream-only.
`tools/unitdef.py` reads both and labels every answer with its source; a unit
found only upstream gets a loud "do not use it in AI code", because the AI runs
against the pinned tree.

## S12 — A duplicate `RegisterObjectMethod` kills the AI at init

Registering a binding that already exists returns `asALREADY_REGISTERED (-13)`,
the `ASSERT` fires, and the AI never initialises. The engine runs to completion,
`result.json` says `crashed: true` with an EMPTY stats array, and the only real
evidence is one line in the infolog: `Failed in call to function
'RegisterObjectMethod'`.

Measured 2026-08-12: `SetRetreat` was bound 14 lines below where a second copy
was added, and the "surface listing" that said it was missing had been truncated
with `head -30` — absence again, from an incomplete search.

## S13 — An order is NOT applied when issued; reading the unit back returns the prior state

`CAICallback::GiveOrder` (`rts/ExternalAI/AICallback.cpp:369`) never touches the
unit — it does `clientNet->Send(SendAICommand(...))`, and the command lands when
that message is consumed.

**The lag scales with sim speed.** Measured 2026-08-12: a factory read
`CountQueued == 0` for 45 consecutive `AiUpdate`s at the benchmark's default
speed cap (~37x realtime) and then took all 56 queued orders in one tick; at
`--speed 3` the same code read 2-9 throughout.

Any loop of the form "read what the unit has, top it up" will issue one order per
tick for the whole lag window. Keep a count of what was SENT and use the read
only to confirm it. This is also a benchmark trap: a headless run at max speed
can exercise a completely different code path from the game apexearth watches.

See the `async-sim-orders` skill.

## S14 — `AiMakeTask` is a RE-ELECTION, not a request for new work

`IBuilderTask::Reevaluate` (`task/builder/BuilderTask.cpp:447`) calls
`manager->MakeTask(unit)` on every task update for every builder not yet in build
range, and only reassigns if the answer has a *different* build type.

So any rule that `Enqueue`s before returning enqueues **once per update**, and
every enqueue after the first is an orphan nobody will ever work. Measured: 15
front-defence tasks in 3 minutes, `picked=0/15`. Return an existing task, or
remember the one already placed for that builder.

## S15 — A watch game's infolog reaches the match dir only at game END

Mid-game reads of `matches/_engine*/infolog.txt` can be DAYS stale. Analyzing a
live game via the engine dir produced a full false diagnosis 2026-08-21 (a "dead
facqueue" CRITICAL retracted hours later — the log was from Aug 10).

Check the file's mtime against the game being discussed before reading ONE line
of it.

## S16 — `result.json`'s `teams[].team` is the SPEC index, not a game team

`'a'=0, 'b'=1`. In a per-side game spec b's players are teams N..2N-1, so
anchoring a side split on `ally_of[teams[apex].team]` reads the ENEMY's side
whenever Apex is spec b — every side-swapped tournament game.

This inverted a full 6-game tournament read 2026-08-21 into a false "we out-scale
stock 2x" (the reported dominance was stock's own scaling); the corrected medians
said the opposite. Each spec's players share the allyteam equal to its spec
index — anchor on that. `tools/scaling.py` does it right; check any new tool
against a side-swapped game before believing it.

## S17 — Aggregate over the right unit

The T2 rush was reported as "not firing" from a median first-T2 of 14.9 min. That
was the median across ALL FOUR players, dominated by followers who tech late by
design. The rusher's own time — `min(techStart)` per side — was 6.3 min, under 10
in 20 of 20 games.

A team strategy that deliberately treats one player differently cannot be judged
by a team-wide average.

## S18 — `str.replace` anchors that don't match do nothing, quietly

This has eaten edits at least five times. Always `assert old in s` before
replacing.

The EOL half of this warning is now **narrower than it used to be**: as of
2026-09-04 every tracked file under `ai/Unstable/` is LF, so the ordinary `Edit`
tool works there directly. `cpp/`, `changes/` and a handful of root `.md` files
still contain CR — check before anchoring in those. `tools/normalize_eol.py`
reports and fixes.

## S19 — The deployed script can change under a running sweep

An A/B run by editing the deployed tree had two of five control games silently
run the treatment; something re-synced that tree mid-sweep. Classify every game
from its OWN log — here the control formula forced `req == uncovered/assets`
exactly — never from the file you edited.

## S20 — A latch-once cache is a decision about WHEN

`Market::CacheSpots()` fills a global on first call and latches. A new periodic
pass called it, moving when the map's spot list was taken from `want_mex`'s
first ask to frame 1. No error, right length, metal built 8,775 → 3,150. Read
such a global if its owner has filled it; never trigger the fill from a new
caller.

Its status line fired only where it found something, so "no line" could not tell
*nothing to do* from *never reached*. A status line must fire on every path,
including the one where the feature declines to act.

## S21 — `pathlib.read_text()/write_text()` on Windows silently transcodes

They default to the locale encoding (cp1252 here), so a round-trip through them
rewrites every non-ASCII character in a UTF-8 file. Used to edit four docs this
session; it put an invalid byte in `dashboard_guide.py` and, on a second pass,
rewrote 52 bytes of `docs/25` that the edit never touched. `git diff --stat`
showing far more changed lines than you wrote is the tell. Use the `Edit` tool,
or pass `encoding="utf-8"` explicitly.

---

# The 2026-08-01 composition finding — "the path fires" is not evidence

Firing proves a change is *wired up*. It says nothing about what it
**displaced**, and in this AI almost everything worth adding displaces
something.

Measured 2026-08-01, four 8-game tournaments, same map, seeds, settings and DLL:

| | session start | after twelve changes |
|---|---|---|
| head to head | 2-2 | **0-8** |
| metal produced | 140,940 | **32,648** |
| mex upgrades | 11 | **2** |
| army share | 18.3% | 4.1% |

Twelve changes went in over one session. **Every one was confirmed firing** —
that was the acceptance test — and each looked reasonable alone: dig-in towers
when a constructor keeps getting shot, flak when the enemy flies, a converter
when energy is wasted, the next fusion before it is needed. Together they cut
metal production by 4.3x, because every one of them spends **constructor time**,
and constructor time is the economy. They all run ahead of `DefaultMakeTask`,
which is where mex upgrades live, so the AI answered every threat and never grew.

Tuning the constants afterwards moved metal 39,233 -> 32,648, i.e. the wrong way.
The problem was never the constants.

Watching a replay tells you a behaviour looks smart. It cannot tell you what it
cost. The dig-in fortresses looked excellent on screen and were among the most
expensive things here.

---

# The 2026-08-30 inert-change finding — instrument first

apexearth: *"I see it terribly often that you make changes which have little or
no effect."* Four changes went in that day and every one failed to bite:

- a tier discount that scaled EVERY member of the tier equally, so it could never
  change which member was chosen;
- a jammer spacing fix built on a dead-binding theory, when the binding was alive
  (`GetJammerRadius=360`) — counts rose on both seeds;
- a defence repricing that helped one seed and hurt the other;
- a serialization gate placed on a code path that carries no traffic
  (`moho-pass: 0` — mex upgrades never reach the Requests chokepoint).

Each is the same mistake: **the code was changed before the path was proven to
carry the decision.** The one diagnosis that survived came from reading the path
first — `apex: exec ... protect:armguard` plus `defplace ... wall=1 gain=0.00`
found the real mechanism in a single step.

## Three ways a measurement lies here, all of them paid for

- **A sampled log is not a census.** `defrank` is rate-limited per builder-def
  per 60s. It was read as a complete record and produced a wrong conclusion. Say
  in the log line whether it is a sample.
- **A metric that cannot distinguish the two states you care about is not
  evidence.** "Zero RAID fight-type elections across 11 matches" was used to
  prove we never raid. But stock enqueues raiders as `Defend(promote=RAID)` —
  fight type DEFEND — and the promotion happens in C++ without passing through
  `AiMakeTask`, so the metric cannot separate the raid pool from the massing
  pool. It was evidence of nothing.
- **Two seeds cannot resolve a change.** Matched pairs disagreed in sign on the
  same change the same day. If you have two runs, you have an anecdote.

---

# The 2026-08-31 frame budget finding

Three violations measured on Supreme Isthmus v2.1, 1v1 cortex, +100%, 32 min:

- **`facqueue` filled a factory's whole queue window in one call** — up to 16
  `ConOrderFor` passes at 2.1 ms each, peaking at 8.9 ms. 16 x 8.9 = ~142 ms, and
  the measured worst frame was 137.8 ms. Now time-sliced against
  `BATCH_SLICE_US` (4 ms), resuming next election; the window is measured in
  build SECONDS, so finishing a few frames later is invisible.
- **`DefSiteFill`'s per-frame cap exempted uncached defs** — `(gDsAt[d] > 0) &&
  (gDsFillN >= 2)`, so a def that had never filled bypassed the throttle. Every
  new candidate filled on the same frame at ~6 ms each. The exemption's stated
  reason ("it could never enter at all") was false: elections run every frame.
- **A bulk pass that got BIGGER without its throttle being revisited.** The
  team-wide defence catalogue took the candidate list from ~3 defs to 8-14 and
  tripled the per-election site walk. A throttle sized for the old N is not a
  throttle.

Result: worst frame 137.8 -> 34.1 ms, ms/frame at minute 31 9.60 -> 4.92,
`want.protect` total 13,044 -> 4,260 ms, `hk.maketask.factory` max 101.4 -> 7.8.

---

# The 2026-08-30 tunable census

**404 tunables declared, 316 read at exactly one call site, and 360 never
overridden in a single recorded run.** They are not experiments; they are
constants wearing an experiment's clothing, and each costs four registration
sites (`tunables.as`, `dev_tunables.lua`, `dashboard_guide.py`, the audit
waiver) plus a line of apexearth's attention on the dashboard.

`python tools/dashboard_audit.py --stale` lists every tunable never overridden in
a run; that list is a cull list, and folding one back into a constant is always a
welcome change.

---

# Why four doc sets were deleted 2026-08-31

**`ai-economy`, `ai-build-arbitration`, `ai-factory-brain` and `barb-tuning`
skills.** They described the pre-overhaul AI — ordered first-match ladders, the
`AlwaysEco` floor, `RushReady` T2 gates, JSON build ratios — all of which
`docs/20-brain-overhaul.md` records as killed. Every file they cited still
existed, so `tools/docs_audit.py` could not catch them; only the MODEL was stale,
which is the kind of rot no checker finds. A cold-read agent that hit
`ai-build-arbitration` first concluded the AI decides by ladder position, the
opposite of how it works. Deleted rather than repaired because a deletion cannot
be subtly wrong.

**The thirteen `.claude/agents/*.md` domain owners.** Written 2026-08-08 to
08-12, they taught the ordered `AiMakeTask` ladder, `Factory::ComputePhase`,
income-tier tables in `factory.json`/`economy.json`, and `GANTRY_MAX` /
`T3_METAL_INCOME = 100` as tuned settings — every one of which
`docs/23-the-plan.md` names as a thing this AI does not do. Ten of them addressed
paths that have not existed since the rename
(`ai/apex/game-side/script/hard_aggressive/`). The extra reason is that the
fleet-of-agents workflow they served was measured worse and scrapped, so they
were teaching a dead model to a dead workflow.

Do not restore any of them. Domain knowledge lives in the `ai-*` skills, which
are maintained.

## S22 — A lane NAMED on the deploy line shipped a stale snapshot

`deploy_ai.py deploy` with no variant re-materialises the active lane from
`ai/Unstable/` before shipping. `deploy lane-energy2` (a lane named explicitly,
because the active lane was busy with a battery) shipped `ai/lane-energy2/` as
it stood at the last unnamed deploy and printed `Deployed 'lane-energy2'`
all the same. 2026-09-08: four 12-game Isthmus batteries and two watched games
ran one identical tree while the working tree carried three further changes;
the batteries spread 17.2–27.0% stalled at minute 14 — which is the noise floor
of n=12 on that map, not any effect. Fixed in `deploy_ai.py` (a named lane is
materialised too). The check that would have caught it in one line:
`grep -c <new symbol> <game-side script dir>/…` after every deploy, or
`deploy_ai.py status`, whose `repo`/`live` digest reads the lane's snapshot,
not `ai/Unstable/`, so it said "in sync" throughout.

## S23 — A named-lane deploy shipped the ACTIVE lane's DLL, mid-link

`deploy_ai.py deploy lane-energy2` took `SkirmishAI.dll` from `_lane.artifact()`
— the checkout's active lane (`.barai-lane`, another session's `comm`) — not
from `build-energy2`. That session was linking at the time, so the copy was
truncated (205,325,976 of 210,730,409 bytes), printed `(local build)`, and the
engine logged `Skirmish AI Apexenergy2-lane-energy2 not found!` and seated
nothing. 36 Isthmus games ran to a normal-looking end; `run_match.py` reported
no crash and `review.py` gate 1 passed. Read in `ecoscale`: our arm at minute
14 had 2 metal/s and 0 mexes. Fixed: the artifact comes from the lane being
deployed, a copy whose size moved is refused, and `not found!` is a crash in
both tools. The one-line check remains: md5 of the deployed DLL against its
build output.
