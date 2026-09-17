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

## S24 — At full sim speed a tail of builder orders lands late, and the stuck watch kills them

Retracted 2026-09-08 (evening) and re-measured. The first version of this entry
said the engine held no order for a builder in 57% of task-holder samples at
the harness's default speed. That was sample-weighted (one task waiting long
contributes many samples) and apexearth did not believe it: "we run inline with
the game execution ... I bet all your commands are making it in." He was right
about the substance. Same tree, same seed, `apex_task_trace=1`, sent-to-applied
lag per order (`exec=1` to the first `q>0`):

| | orders | applied >90 frames late | >300 | never seen | stuck-watch kills |
|---|---|---|---|---|---|
| `--speed 5` | 1,391 | 4 (0.3%) | 2 | 6 | 0 |
| default (MinSpeed 9999) | 757 | 30 (4%) | 14 | 14 | 17 |

Over 98% of orders arrive at either speed. `CAICallback::GiveOrder` sends the
command as a net message and the unit receives it when the client reads the
echo back; the tail is ~13x more frequent at full speed (three engines shared
the CPU in both runs). It is NOT a late echo: a DLL patch that re-sent any
order still unapplied after a second made 343 re-sends at full speed and 0 at
speed 5, and every re-sent order vanished within a frame (kills 30, curve no
better) -- something clears or refuses those orders on receipt, and the
commander's live build order was cleared mid-walk 700 elmos from its site.
`allowOrders` is never false, engine move-failed events are not speed
dependent (177 at speed 5, 34-44 at full), and no exception is logged. The
cause is not identified; the patch was reverted as inert.
The damage is ours: `stuck.as` kills a task holding no engine order after
`3 x` the largest lag it has seen, and it can only learn lags shorter than
that wait, so the tail is killed and re-elected every time -- 19 kills in the
first four minutes of the full-speed canon, 4 standing mexes at minute 4
against 17, income at 20 halved (315 vs 736 m/s). Until the watch re-issues
instead of killing, eco-only canon runs go at `--speed 5`; a battery at the
default speed compares two arms that both suffer it.

## S25 — `.barai-lane` is ONE file per checkout, so every session shares the "active" lane

`lane.py init <name>` writes the repo-root `.barai-lane`, and every tool reads
it. Four sessions on 2026-09-08 all read `comm`: an unnamed `deploy`, `build_dll`,
`sync_cpp.py pull` and the live-log write dir all followed whichever session
had run `init` last, and two sessions believed they held the same lane. One
session's AngelScript edits were overwritten in the shared tree and survived
only in a lane snapshot; a mirror pull from a stale lane reverted committed
C++ (bar-ai-be, bar-ai-19). The isolation docs/28 describes is per lane, not
per session, and the file cannot tell sessions apart. It happened once more
the same evening: a session with no claim ran `sync_cpp.py apply` into
`BARb-hz` and `deploy Unstable` into `lane-energy2`. **Fixed 2026-09-08:**
claims live in `.barai-lanes` keyed by `CLAUDE_CODE_SESSION_ID`, a session
with no claim is refused by every writing tool, and `BARAI_LANE=shared` is
the only way a session reaches his slot (`docs/28`).

## S27 — The engine DISCARDS a build order whose square is blocked, silently

`CBuilderCAI::GiveCommandReal` (`BuilderCAI.cpp`) tests `IsBuildPosBlocked` and
`return`s **before queueing** when a finished building or an unreclaimable
feature stands on the square. There is no queue entry, no error, no
`AllowCommand` refusal to see -- and because the builder never left idle, no
`UnitIdle` event either. Both of CircuitAI's routes back to an order need that
event (`IBuilderTask::OnUnitIdle` needs the engine to say idle,
`IBuilderTask::traveled` needs a travel to end), so the builder stands with an
empty command queue holding a live task while `Reevaluate` re-elects, is handed
the same buildType, and returns.

This is a SECOND cause of the S24 signature and it is speed-independent: S24's
lost order is late delivery scaling with sim speed, this one is a refusal that
happens at speed 1 too, which is why apexearth sees the commander stand around
in a watched game. The commander is worst hit because an in-base build skips
pathing (`apex_inbase_path`) and so ends its travel at once -- after that single
`Execute` nothing else in the task can ever issue him an order.

The diagnosis path, for the next time: `Market::CommWatch` (`safety.as`) samples
the commander once a game-second and logs `apex: com-still ... q=0 site=X,Z@d
act=...`; `CCircuitUnit::NoteAct` now also marks `dgn` (a D-gun order) and `hld`
(an order dropped by the D-gun hold, which is the other silent dropper -- every
`Cmd*` early-returns on `IsDGunHeld` and nothing retries). A stall reads as
`q=0` for tens of seconds with a valid `bp` and a site hundreds of elmos away.

**Do not read an idle percentage off a battery**: measured 43.7% of commander
samples idle on Geyser Plains at harness speed, single stalls to 183 s -- S24
says that figure is inflated by sim speed and the honest one needs `--speed 1`,
which has NOT been run. The recovery is `stuck.as`'s `gStuckDeadAt` /
`gOrderLagMax` (6318a09e), which sizes its wait to the lag it measures in the
game it is in; a fixed-second wait is the trap S24 names.

## S26 — The checked-in DLL is a stale snapshot; a deploy without a build shipped it silently

`deploy_ai.py deploy` fell back to `ai/Unstable/engine-side/SkirmishAI.dll`
(a 7 MB stripped copy from 2026-09-06) whenever the lane had no local build,
printing `(repo copy)` and nothing else. By 2026-09-08 the script called
`GetEnemyStructCostAt`, which that DLL does not bind: `raid.as (122, 34) : ERR`,
the variant compiled nowhere and played near-stock -- S3 again, reachable by a
fresh checkout, a fresh lane, or a dashboard deploy with no build (bar-ai-be).
`deploy` now refuses the fallback unless `--repo-dll` is passed. The snapshot
should be refreshed only from a tree that matches the cpp mirror.

## S28 — `GetEnemyCostAt` returns a COUNT of visible units, and two things priced it as metal

`CCircuitAI::GetEnemyCostAt` is `CountEnemyUnitsIn` (CircuitAI.cpp:2937 --
the comment on the raid director already says so). `Air::EcoDensity()` read
it as "metal in their base" and fed it to `StrikeWorth`, which compared it
against the wing's metal bill times `apex_air_payoff`: a few dozen visible
units against thousands of metal, so the air lead logged `NOT armed` for 25
minutes in his 2026-09-11 game whatever stood behind their 7.6k of AA, and
`SettleStrike` scored a run's "damage" as a difference of unit counts, which
priced the next bombers to nothing. `GetEnemyStructCostAt` is the metal-valued
call; the strike target scan (`air/state.as`) uses it now. Any other reader of
`GetEnemyCostAt` that adds, multiplies or compares it with metal is wrong the
same way -- `ThreatFor`'s fallback in `sitesafety.as` treats it as a count on
purpose. Not audited (2026-09-11): the readers in `army.as`, `coverage.as`,
`guards.as`, `protect_fill.as`, `protect_senseprice.as` (`< 200.f` at line
161 reads like metal), `safety.as`, `want_mex.as`.

## S29 — An uncapped battery measures the CPU, not the tree

`ab.py` control arm, Greenest Fields 2v2 +100%, 2026-09-11: 838k metal by
minute 55 and 59 fusions with three engines on the machine; the same lane,
same map, lost to BARb by minute 30 with 41k metal and six fusions once
another session's four engines joined. BARb is not sliced against the wall
clock and we are, so under contention only our side degrades, and a change
measured across a load change reads as a huge effect in whichever direction
the load moved. `ab.py --speed 6` pins the sim; the wall time per game is then
fixed and the AI gets the same budget in every game of the set.

## S30 — `byUs` on an enemy death is "attacker still alive and ours", and a bomb's plane is usually dead

`EVENT_ENEMY_DESTROYED` carries an attacker id only when the killer is an
allied unit that still exists; a bomb landing after its plane died reports
-1, and so do chained explosions. `Air::NoteEnemyDeath` gated the strike
ledger on `byUs`, so a 10-Blizzard run on Greenest Fields (2026-09-12,
`tournaments/20260912-102411-bombstrike/greenestfi-B-s1`) that the death log
shows killing a Big Bertha, an antinuke, an air plant and twenty nano turrets
inside its cell -- ~11k -- scored `dmg/bomber=155`: the four kills whose
plane outlived its bomb. Below the 345 bar, that verdict stopped Blizzard
buying, threw the survivors out in the "wing at its worth" branch six at a
time, and moved the wing's spend to the one bomber def with no measurement
yet (two Liches). Any per-unit outcome ledger keyed on `byUs` undercounts
every delayed-effect weapon the same way; the strike ledger now counts static
deaths in the run's cell during its window whoever is credited.

## S31 — A hitch the AI's own clock cannot see: every console line runs through `gui_chat.lua`, quadratically

apexearth watched a 2v2 on Sulphur Springs (2026-09-12, `matches/_engine`)
freeze for ~1.5 s every 10 game-seconds from minute 22. `frametime.py` read
the game as clean: no AI frame over 36 ms, every C++ scheduler job under 4 ms.
The wall gaps in the infolog sat on frames `% 300 == 0`, exactly where
`dev_combat_log.lua` echoes its `[BARAI_ARMY]` census, one line per team with
every armed unit in it -- 25 KB by minute 30. BAR's `string.lines`, which
`gui_chat.lua` runs on every console line, is `gsub("(.-)\r?\n", ...)`: on a
line with no newline the lazy `.-` rescans to the end from every position, so
the cost is the square of the line's length (25 KB² ≈ 3·10⁸ pattern steps ≈
1.5 s). LuaUI loads in headless too (`barwidgets.lua` printed its 1.2 GB
emergency-GC warning in the 8v8 benchmark), so the harness had the same stall
and never showed it in any per-section number. Matched pair, same seed: census
on, stall 0.09 → 0.64 s over minutes 12-29; `dev_combatlog=0`, 0.03-0.06 s
flat. Two lessons: a wall-gap scan of the infolog (`[t=` between consecutive
lines) is the instrument for a hitch the sections do not own; and nothing
long ever goes through `Spring.Echo`. The census now ships in 10-unit lines,
and the AI's own log no longer goes through the engine at all: it writes
`apex-t<team>.log` and `run_match` merges it back by frame (`tools/apexlog.py`).

## S32 — An emergency whose exit is a growing target is a standing rule, and it was measured by its firing

Commit 87a39d68 (2026-09-09) widened the home-defence hoist: sensor from
`LossRateAt(home)` to `BleedM()` (anywhere), exit from "any tower coming" to
`DefenceValue()+DefenceInFlightM() < DefenceTarget()`. Its own message
measured "panic lines 0 -> 45-51 per game, ~60 defence elections won per
game" and shipped with "outcome NOT resolved". Both halves are unbounded:
the loss field decays geometrically so `BleedM() > 0` is "a structure has
ever died", and `DefenceTarget()` is a share of holdings, which grows faster
than 70-metal towers at a commander's lathe can fill it. Supreme Isthmus 8v8
+100% he watched 2026-09-14 (`matches/20260914-224733-*`): 515 panic
elections across eight seats, 287 of them at v<0.5 and 478 overriding a
better-priced want; one Legion commander bought 72 Pharos at v=0.00 over a
mex at v=1.19, on a bleed of 0.28 m/s. The hoist's job was "0 defense" (his
words); the target shortfall is the priced market's, and the loss field
already prices it (`coverage.as` ThreatAt/HazardWith) at the sites that are
dying. Now bounded to the first tower; `audit.py def-panic-bounded` reads it.

## S33 — A subclass override skipped the chokepoint, and the chokepoint's own log said it fired

The lattice snap and the ring walk live in `IBuilderTask::Execute`, and every
farm type was said to go through them: `apex: tiling flush=` read 72-76%,
the walk's log lines fired, and the placement work was called done
(2026-09-14). `CBNanoTask::Execute` overrode the base and ran its own
square-by-square search inside the turret's build distance — no snap, no
walk — so every nano turret whose packed cell was taken stood one build
square off the block. That is the "one space away" he watched, and the
census (`tools/tiling.py`, 2026-09-16) read it as 7 of 12 turrets
misaligned while the tiling line called the same base 76% flush: its FLUSH
bar accepts a neighbour a whole square off. Two lessons: (1) when a
mechanism is a chokepoint, `grep -l "::Execute(" task/builder/*.cpp` — a
subclass with its own copy is outside it; (2) an instrument whose pass bar
is wider than the complaint cannot see the complaint. The census asks the
exact question (both axis offsets a whole number of pitches).

## S34 — a full-speed headless game on a hilly map stalls BOTH AIs (2026-09-17)

`run_match` at unbounded sim speed on Altored Divide (~27x realtime) left
both our AI and BARb hard with 2-4 extractors and a metal bank pinned at
100% for ten minutes: 3,400-4,400 metal built by minute 8 against 7,000-
10,000 in his watched game and in the same seed at `--speed 5`, `10` or
`15`. Every conclusion drawn from a day of full-speed Altored runs -- game
lengths, T2 timings, "we lost at 14 min" -- was drawn from two stalled
economies. Comet Catcher had not shown it. The mechanism is not pinned
(pathing or order latency at that speed on complex terrain are the
suspects); the rule is: on a map that is not flat, cap the speed (`--speed
10` costs 90 s wall for 12 game-minutes) and check `ecotimeline.py`'s
metal bank -- a bank pinned at 100% from minute 2 is a stalled run, not an
economy. `run_match` now carries Altored's boxes (lr 0.25, his dashboard's).
