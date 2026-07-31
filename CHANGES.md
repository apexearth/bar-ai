# What this AI does that stock BARb does not

Two variants, both built on BARb (CircuitAI). Everything here is a deliberate
difference from `BARb/stable`; anything not listed behaves as stock.

| variant | intent | best measured result |
|---|---|---|
| **apex** | stock BARb plus a team T2 rush | T2 at 5.7 min vs stock 13.9; ~45% wins |
| **apexdef** | hold ground, out-eco, finish with T3 | 4-3 over 10 clean games |

Status column below: **measured** = validated in a clean run; **unmeasured** =
implemented and smoke-tested only; **suspect** = measured under conditions later
found invalid.

---

## C++ / SkirmishAI.dll

New bindings in `vendor/engine/AI/Skirmish/BARb/src/circuit/`. The DLL is rebuilt
from source and stripped; see `docs/06-building-the-dll.md`.

| binding | purpose | status |
|---|---|---|
| `ai.SendResources(m, e, team)` | give metal to an ally — makes slinging possible at all | measured |
| `ai.GetTeamMetalIncome(team)` | ally income, for ranking the tech lead | measured |
| `ai.GetBestWreckPos(pos, r, min)` | richest wreck nearby, so reclaim is *valued* | measured |
| `ai.GetBuilderThreatAt(pos)` | per-position danger from the engine's `CThreatMap` | diagnostic only |
| `CCircuitUnit::CmdMoveTo(pos)` | raw move order, outside the task system | **not called** |
| `ai.GetEnemyCostAt(pos, r)` | enemy count in radius | **not called — unsafe** |

`ai.GetTeamMetalFill` also exists but returns nothing useful; see the engine bug
note in `CLAUDE.md`.

**Do not call** the last two. `GetEnemyCostAt` crashed the AI, and commander
retreat via `CmdMoveTo` correlated with the engine aborting 14-17 games per
20-game run. Both are registered but unreferenced.

## AngelScript (`script/hard_aggressive/`)

### Team tech coordination — the core of both variants
- **One designated tech lead**, chosen by **commitment**: whoever is building an
  advanced plant, and when two are, whichever plant is nearest done. Nanoframes
  count and the fractional build progress is the tie-break. Stock has no team
  coordination at all — each instance decides alone.
  **The election runs in the AI, over an in-process blackboard** — not in synced
  Lua, and not on income. Synced Lua cannot ship to a hosted multiplayer game;
  every AI the host adds shares one process, so the instances read each other via
  `PublishTeamValue`/`ReadTeamValue`. **measured**: with the released archive and
  no gadget present, all four instances elected the same lead within four frames
  and it never flapped across 20 minutes.
  It once ran per-instance on the assumption that identical synced inputs give
  identical answers; they do, but the *read instants* differ (SlowUpdate is
  offset by `skirmishAIId`), and 1 archived match in 533 elected two leads. The
  property that fixed it is kept — **one writer**: the lowest team id in the ally
  roster elects and publishes, everyone else only reads that slot.
- **The lead is replaced if it loses its plant**, and the title stops moving
  entirely past `RUSH_GIVEUP`, so the lead stays tech lead after sharing ends.
- **The commitment rule deadlocks against the follower gate unless the gate is
  conditioned on a lead existing.** The gate forbids any non-lead from starting a
  T2 factory before `FOLLOWER_TECH_FRAME`; if the lead *is* whoever started one,
  nobody may start, so nobody leads, so nobody may start. **measured**: first
  election at 10.5 min in two runs — the exact frame the gate opens — against a
  5.7 min baseline; gating on `LeadIsDesignated()` moved it to 6.9 min.
- **Slinging**: followers send 450-metal lumps to the lead, keeping 220, from
  5 min until they receive their own advanced constructor.
- **The whole strategy is abandoned at 15 min** (`Military::RUSH_GIVEUP`).
  Pooling is a bet -- the team runs poor and the lead runs armyless -- so if T2
  has not landed by then it has lost, and continuing compounds it. Slinging, the
  rusher's factory pre-emption, the T1-lab reclaim and both suppressed attack
  quotas all stop, and play reverts to stock. **measured**: all release paths fire
  at 15.0m and restore quota.attack to the stock 15.
- **The lead techs on zero bank**: stock requires `0.5 x plant cost` banked,
  which is never reachable. It places the plant and pours income in.
- **Followers get the same no-bank switch** once past 13 min — and **only one
  advanced plant each**.
- **Advanced plant matches the opening factory**: T1 bot lab → T2 bot lab,
  vehicle → vehicle. Stock forced a vehicle plant a bot lab cannot build.
- **The lead reclaims its own T1 lab** into the plant it replaces.
- **Advanced constructors are shared**, one per teammate. Big teams pre-empt the
  factory line to do it; small teams do not (measured: pre-empting cost 3-13).
- **The tech lead never opens air**, and on teams under 6 **nobody** does.

### Combat posture
- **Acting on enemy bearing did NOT work, and the machinery is gone.** The
  gadget used to publish the opposing start-position centroid as
  `ai_enemyx_/ai_enemyz_<teamId>` and `Military::BearingOffFromEnemy()` turned it
  into degrees off the line of attack. Skipping defence sites >90° off the line,
  and skipping them again while ahead on `mobileThreat/armyCost`, lost to an
  otherwise identical control over 12 paired 8v8 games: real K/D log-ratio
  −0.156 (t=−1.12) in the control's favour, metal a coin flip. Both the param and
  the helper have since been deleted — nothing in the script computes bearing
  today. `CEnemyManager::GetEnemyPos()` still exists in C++, unbound, if the idea
  is ever retried. **suspect — do not rebuild without a fresh A/B**
- **Mass before attacking**: attack quota grows 30 at 8 min → +3.5/min → cap 80.
  Stock attacks with whatever is to hand.
- **Refuse bad trades**: hold when enemy threat exceeds 0.95x our army cost.
  Calibrated from live ratios, not invented.
- **Reactive turtling**: hold when our army value drops 18% in 20 s, resume at
  85% of the pre-collapse peak, max 6 min, not before 5 min (apexdef).

### Economy
- **Reclaim over resurrect**: rez bots are handed a wreck reclaim before
  `DefaultMakeTask` can give them a resurrect. Resurrecting spends metal;
  reclaiming yields it.
- **Valued corpse reclaim**: idle builders go to the *richest* nearby wreck, not
  the closest. apexdef reaches further (2200) and accepts smaller bodies (55).
- **Reclaim when broke**: a builder standing on metal with an empty bank eats it
  rather than holding an unaffordable build task.
- **T3 gantry** is an explicit tech goal above 100 metal/s (apexdef).

## Config (`config/hard_aggressive/`)

| change | why | status |
|---|---|---|
| `mex_up` 3 → 10 | T2 mexes are 4x metal; upgrade them all | measured |
| Metal storage `since` 300 → 1200 | at 5 min there is nothing to store | unmeasured |
| Fusion gated `m_inc > 28` | ~1000 e/s of economy, per human practice | suspect |
| Advanced fusion added to the fusion hub | it existed only as a hub *key*, so nothing ever built one | unmeasured |
| Nano gates on reachable income (14/22) | old gates of 22-46 produced **zero** nanos | measured |
| T1.5 towers at every advanced plant | plants had four nanos, a fusion, and no defence | unmeasured |
| Jammer towers rehung + `sensor: 900` | parent was porcupine index 12, never built, so `chance` never rolled | unmeasured |
| Commanders get `dg_cost` | stop D-gunning our own lab to kill one raider | unmeasured |
| Spam kept at high tiers (all factions) | cheap units for vision and distraction vs long-range T2 | unmeasured |
| Radar + mobile jammer paired | `coreter` beside `corvrad` (Cortex only so far) | unmeasured |
| Gantry `income_tier` 100/200 → 45/90 | unreachable, so a built gantry sat in its last tier | unmeasured |

Upstream bugs found and worked around: `legbombard` has no builder, `armfmd` is
not a unit def, three `nanotct2` variants are buildable by nobody, several
porcupine entries ship `on: false` and are built inert.

## T3 urgency gate — implemented, NOT shown to work

`T3Worthwhile()` used to refuse a gantry whenever `gTurtle` was set or our army
was smaller than the enemy's, so it only ever allowed T3 from a winning position.
Above `T3_INCOME_URGENT` (150 m/s) both vetoes are skipped. Motivated by a live
hosted game: a player on 398 m/s with enemy T3 in the base built nothing.

**8 paired +40% 40-minute 4v4s say the change is not measurable.** Win rate 2/4
treatment vs 1/4 control (2 draws). apex T3 median 40,265 vs 13,720, but the
ranges are 0-86,810 and 0-205,200 -- the single largest T3 game in the whole set
was a CONTROL run, because the old gate happily builds T3 when winning.

What actually predicts T3 spend is economy scale, not the gate: the four runs
above ~400 m/s peak built 86.8k/205.2k/64.0k/11.8k, the four below ~230 m/s built
0/16.6k/0/15.7k, with both arms on both sides. An earlier 1-vs-1 pair looked
decisive and was luck.

Kept because it only relaxes a veto in a case observed live and costs nothing
otherwise. The case it targets -- big economy AND losing -- is barely sampled by
random games, so testing it needs a scenario, not more matches. **unmeasured**

## Surprise air eco-assassination — implemented, NEVER RUN

`script/hard_aggressive/manager/air.as`, namespace `Air`. One player per ally
team builds a hidden T2 air force and throws all of it at the enemy economy.
**Not one game has been played with this. Every number in it is reasoned from
unit costs and from the C++ it drives.**

What it does:

| piece | mechanism | status |
|---|---|---|
| One air player per ally team | same one-writer blackboard as the tech election: everyone publishes `airinc`, `Factory::ElectorTeamId()` publishes `airlead` once, latched | unmeasured |
| Two-step plant chain | the T2 air plant is buildable by **air constructors only** (`armca`/`armaca` and pairs) — no ground con of any tier has it. So: T1 air plant → its 5-con opener → T2 air plant | unmeasured |
| 20 bombers + 20 fighters | forced from the T2 plant in `Factory::AiMakeTask`, alternating in proportion, 2 s apart | unmeasured |
| Held at home | `Military::AiMakeTask` returns null, which leaves the unit in the idle task with no orders | unmeasured |
| Abort on enemy AA | `GetEnemyCost(anti_air) > 2500` metal before committing; after committing it strikes early if half-massed, else stands down | unmeasured |
| Strike hits economy, not army | `ANTI_STAT` added to the bomber def at release: `CBombTask::FindTarget` then skips every mobile enemy. Per-instance — `CCircuitDef` is owned by each `CCircuitAI` | unmeasured |
| No retreat | `retreat: 0.0` on the six strike aircraft in `behaviour.json`/`behaviour_leg.json`; `IFighterTask::OnUnitDamaged` returns early while `healthPerc > GetRetreat()` | unmeasured |

What it does **not** do, and why:

- **They are not landed, only orderless.** `CmdFindPad` and `CmdWait` exist in
  `CCircuitUnit` but are not registered to AngelScript — only `CmdMoveTo` is. An
  idle aircraft hovers where it was built. Anything that scouts our base sees it,
  so "hidden" here means "off the map", not "invisible".
- **Bombers and fighters strike as two squads, not one.** `ISquadTask` merges
  only within one `fightType`, so bombers form a BOMB squad and fighters an AA
  squad and they travel separately. Combining them needs C++.
- **No edge-of-map routing and no anti-flak spreading.** The path comes from
  `CPathFinder` against the threat map; neither the route nor the formation is
  reachable from script.
- **`retreat: 0.0` is profile-wide, not scoped to the strategy.** There is no
  `SetRetreat` binding, so `armpnix`, `armhawk`, `corhurc`, `corvamp`,
  `legphoenix` and `legvenator` now fight to the death for every player on this
  profile, not just the air assassin.
- The income bar (60 m/s for the air player) is set above what the 4v4 benchmark
  reaches, so **the expected benchmark result is that this never fires**. The
  elector logs "no air assassin, best ally income X/60" once a minute past 15 min
  so that silence can be told apart from a script that failed to compile.

Also found while reading the C++: `Military::AiIsAirValid()` in `military.as` is
dead — no C++ path calls it. The real gate is `CEnemyManager::IsAirValid()`
against `quota.aa_threat`, which this profile sets to `[[8, 99999], [96, 500000]]`,
i.e. effectively disabled.

## Packaging — what makes it load in a hosted game

- **Ships under its own shortName, `BARbApex`**, rather than as version `apex` of
  `BARb`. The lobby's `ADDBOT` carries only `aiLib`, with no version field, so a
  hosted game's start script has `Version` empty; the engine then keeps every key
  matching the shortName and picks the highest by `VersionCompare`, and
  `"apex" < "stable"`. As a version, the variant loaded **stock BARb in every
  multiplayer game** and said nothing. Single-player was unaffected, because
  Chobby writes that start script itself and does pass the version — which is
  why it only appeared when hosting. **measured**: reproduced and fixed under
  `run_match.py --drop-ai-version`, which omits `Version` exactly as a host does.
- **Config and script are deployed engine-side as well**, into
  `AI/Skirmish/BARbApex/apex/`. Other players are on released BAR, which has no
  `LuaRules/Configs/...` for us; CircuitAI logs "Game-side config: missing!" and
  falls back to `LocatePath("config/")` over the AI data dirs. **measured**

## Dev instrumentation (not part of the AI)

`game-patches/gadgets/` — installed into `BAR.sdd`, inert in normal play.
- `dev_stats_export.lua` — value-weighted telemetry: real vs chaff kills, T2
  placement *and* completion, T2 mex count, reclaim, **commander losses**,
  **constructors held (T1/T2) and metal tied up in them**.
- `dev_team_income.lua` — **mostly dead, and deliberately still running.** The AI
  no longer reads its income table or its `ai_lead_` election; both moved
  in-process so they survive a hosted game. The only live reader left is the team
  front (`ai_frontx_`/`ai_frontz_`). Its `[BARAI_LEAD]` echo still fires and no
  longer reflects what the AI believes — read `apex: tech lead` from the AI's own
  log instead. Delete the dead half once the front is ported.
- `tools/trace_flow.py` — reconstructs the pooling sequence (elect → pool →
  rush → tech → share → follow) per ally team from an infolog and names the
  first step that broke. Needs the `[3.9m t2]` team-tagged log prefix.
- `tools/check.py` — pre-deploy gate: invalid JSON, non-existent unit names,
  multi-key `condition` objects, version/profile mismatches. Baseline-aware, so
  it reports our breakage and not the ~31 quirks inherited from stock.
- `ai_namer.lua` patch — prefixes AI names with their variant so replays are
  readable.

---

## Known not done

- **Factory placement in safe ground.** The `"support"` attribute is documented
  as "build in base radius, not on front" and is already set on every factory —
  but there is no `IsAttrSupport` in the source, so it is unclear anything reads
  it. Unsolved.
- **Commander retreat.** Three approaches tried, none worked. `commander.json`
  hide levers moved losses not at all and cost 10-20k metal; `GetEnemyCostAt`
  crashed and returned zeros; `GetBuilderThreatAt` works but **does not predict
  death** — across 10 games, readings within 30 s of a commander dying were
  *lower* than baseline (3% nonzero vs 8%). Commander survival is still the
  strongest outcome correlate measured here, so it is worth pursuing, but not
  through a sampled position-threat signal.
- **Sling guard when under attack.** Followers give away metal with no check on
  their own safety.
- **Nuke bomber massing, progressive scout quotas, all-in timing scaled to T3.**
- **Armada and Legion radar/jammer pairing.**

## Reading results

Check `exit_code` and `reason` in `result.json`, not just the winner. A run where
games end without a winner may be aborting rather than drawing — that mistake
invalidated several days of conclusions here. Clean games are `exit 0` with
`reason=gameover` or `reason=timelimit`.
