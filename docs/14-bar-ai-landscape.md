# 14 — The wider BAR AI landscape

Survey of BAR / Spring-Recoil AI development *outside* this repo, done 2026-08-08.
Companion to [02 — The AI landscape in BAR](02-ai-landscape.md), which covers the
*mechanisms* (interfaces, layers, dead ends). This document covers **who is
actually building what, and what the community knows.**

`docs/13-other-ais.md` covers `Felnious/Skirmish` specifically; this document
deliberately does not.

## How to read the confidence markers

- **[VERIFIED]** — read directly from source, a repo tree, or a game file on
  this machine. Reproducible from the cited URL/path.
- **[REPORTED]** — a claim made by an identifiable author in a PR, issue or
  config file. The author believed it; it is not independently measured here.
- **[OPINION]** — marketing copy, tooltips, video titles, hearsay. Weight
  accordingly.
- **[UNKNOWN]** — looked for, did not find. Recorded so the next session does
  not repeat the search.

---

## 1. What people actually play against

### 1.1 The shipped roster

Read from `vendor/bar/luaai.lua` and
[`BYAR-Chobby/…/byar/aiSimpleName.lua`](https://raw.githubusercontent.com/beyond-all-reason/BYAR-Chobby/master/LuaMenu/configs/gameConfig/byar/aiSimpleName.lua). **[VERIFIED]**

| Lobby entry | What it is | Layer | Status |
|---|---|---|---|
| **BARb stable** ("BARbarian AI") | CircuitAI, `rlcevg/CircuitAI` branch `barbarian` | C++ + AngelScript + JSON | **Actively maintained**, commits within days of this survey |
| SimpleAI | `luarules/gadgets/ai_simpleai.lua`, 690 lines | Lua gadget | Shipped, low activity |
| SimpleDefenderAI | same gadget, branch on `luaAI` string | Lua gadget | same file |
| SimpleConstructorAI | same gadget, branch on `luaAI` string | Lua gadget | same file |
| NullAI 0.1 | engine template, "literally does nothing" | C | test fixture |
| ScavengersAI / RaptorsAI | **PvE game modes, not opponents** | Lua spawner gadgets | actively developed as *game modes* |

**Scavengers and Raptors are confirmed not skirmish AIs. [VERIFIED]** They are
`luarules/gadgets/raptor_spawner_defense.lua` and `scav_spawner_defense.lua` —
wave spawners that occupy a lobby slot via `luaai.lua`. They have no economy, no
build order and no notion of winning a skirmish. Chobby's own tooltip says
"This is a PvE game mode… Only add 1 per game." Do not benchmark against them and
do not read their code as an AI reference.

The three `Simple*` AIs are one 690-line gadget that switches on the `luaAI`
string. It does closest-mex selection, a fixed build-order table and a random
construction-project chooser. It is a beginner opponent, not a competitor.
**[VERIFIED]**

### 1.2 Only one BARb profile is actually reachable

`aiCustomData.lua` on Chobby master declares five BARb profiles and then
**blacklists four of them**:

```lua
local blacklistProfiles = {
    ['BARb'] = { dev = true, hard = true, medium = true, easy = true },
}
```

So the only BARb profile a player can pick in the lobby today is
**`hard_aggressive`** — "Difficulty: Hard | Playstyle: Aggressive | Made by
Flaka, tweaked by Corosus". **[VERIFIED]**

This independently vindicates this repo's decision to ship exactly one profile
(`hard_aggressive`) and delete the easy/medium/hard/rush trees: upstream reached
the same conclusion by hiding them. Note the mechanism differs — Chobby hides
them, upstream still *ships* them.

Corollary worth recording: the "BARb has 8 difficulty levels" claim that
circulates in search results is wrong (already flagged in
[09 — Resources](09-resources.md)). The real number reachable in the lobby is
**one**. **[VERIFIED]**

### 1.3 CircuitAI branch status

From [github.com/rlcevg/CircuitAI/branches/all](https://github.com/rlcevg/CircuitAI/branches/all): **[VERIFIED]**

| Branch | Last updated | What |
|---|---|---|
| `barbarian` | 2026-07-31 | BAR — this is BARb |
| `barb5` | 2026-07-31 | same tip commits as `barbarian` |
| `master` | 2026-06-02 | generic |
| `zk` | 2026-06-04 | Zero-K |
| `barb5_bwta2` | 2022-02-04 | dead |
| `zk-fix` | 2021-12-23 | dead |
| `barb3_old` | 2021-07-09 | dead |

`barb5` and `barbarian` showed identical top-three commits on the day surveyed
("Fix CRegion having improper copy constructor", 2026-07-31). Whether `barb5` is
an alias, a staging branch, or a genuine fork that happens to be in sync is
**[UNKNOWN]** — do not assume.

The project is small and effectively single-maintainer: 29 stars, 30 forks,
19 open issues, 659 commits on master.

### 1.4 Named humans working on BARb

Identified from PR/commit authorship. **[VERIFIED]** as authorship; their roles
are inferred.

- **rlcevg / "Lamer"** — author of CircuitAI itself, listed on the BAR team page
  as ["Lead BARbarian AI"](https://www.beyondallreason.info/team/lamer).
- **Flaka** — credited in `aiCustomData.lua` as author of the `hard` and
  `hard_aggressive` profiles.
- **Corosus / Corosauce** — "tweaked by Corosus" in `aiCustomData.lua`; authored
  [CircuitAI PR #135](https://github.com/rlcevg/CircuitAI/pull/135) (merged).
  Also holds a CircuitAI fork.
- **veez-e** — [BAR PR #7062](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/7062),
  factory egress lanes.

This is a **very small field**. That is itself a finding: there is no large body
of BAR AI expertise to draw on, which is why sections 3 and 4 below are thin.

### 1.5 Independent BAR AI projects

Found via the GitHub search API (the web search UI returns nothing useful for
these terms). All are BARb/CircuitAI derivatives — **no one has written a BAR AI
from scratch that this survey could find. [VERIFIED]** for what was found;
absence is **[UNKNOWN]**, see the CLAUDE.md warning about absence findings.

| Repo | Last push | What it is |
|---|---|---|
| [Noodles98/Azmodious](https://github.com/Noodles98/Azmodious) | **2026-08-09** | Full BARb variant, `Azmo:dious`. Very active. See §1.6 |
| [AnonymoScoot/BAR_AI](https://github.com/AnonymoScoot/BAR_AI) | 2026-07-28 | `testingAI:stable`. 2 commits; a deployment snapshot, ships `libSkirmishAI.so` |
| [derekShaheen/Metal-BAR-AI](https://github.com/derekShaheen/Metal-BAR-AI) | 2025-11-30 | `Metal-BARb:stable`. 2 commits, near-stock config dump |
| [erik-moedt/bargandhi](https://github.com/erik-moedt/bargandhi) | 2026-06-04 | CircuitAI fork, description "more fun" |
| [benbreen/CircuitAI](https://github.com/benbreen/CircuitAI) | 2026-07-24 | CircuitAI fork for Apple Silicon builds |
| [Felnious/BeyondAllReasonFelxAI](https://github.com/Felnious/BeyondAllReasonFelxAI) | 2025-01-29 | Same author as `Felnious/Skirmish`; see doc 13 |

`Metal-BAR-AI` and `BAR_AI` are essentially what this repo's `deploy_ai.py`
produces — a copied AI folder with light edits, committed. They are structurally
the same idea as `ai/apex/`, at an earlier stage. Nothing to learn from them
beyond confirming the pattern is common.

Legacy Spring AIs (`spring/AAI` last touched 2022, `spring/RAI` 2019,
`hoijui/GAI` 2011, `arnehilmann/tccai` in Elixir, 2017) are dead and do not build
on Recoil. Confirms [02](02-ai-landscape.md). **[VERIFIED]**

### 1.6 Azmodious — the peer project that matters

`Noodles98/Azmodious`, shortName `Azmo`, version `dious`. **Committing daily**
(25 commits in the six days before this survey, most recent 2026-08-09).
**[VERIFIED]**

This is the closest thing to a peer for this repo, and it has gone further in
several directions. Its
[`MAINTENANCE.md`](https://raw.githubusercontent.com/Noodles98/Azmodious/main/Azmo/dious/MAINTENANCE.md)
is a genuinely good architecture document. What it has that we do not:

- **Per-map profiles with per-start-spot roles.**
  `script/hard/helper/maps/profiles/*.as` carry hand-curated and generated data
  for named maps. A start spot declares `preferredRole` and `landLocked`.
- **Team roles: AIR / TECH / SEA / FRONT.** Resolved from the map profile, then
  driving factory restrictions, economy tuning, defence policy and constructor
  counts (AIR 6, TECH 4, FRONT 2, SEA 2 base constructors).
- **Lane assignment across allied AIs.** `lane.as` mixes the start-spot index
  with `teamId`/`skirmishAIId` "so allied AIs do not all converge on the same
  tactical lane."
- **Frontline anchors.** `frontline_cluster.as` tracks up to two confirmed
  pressure anchors per AI, learned from *observed ground-combat pressure*, and
  uses them to place defence and to position attack tasks.
- **Three separate reclaim helpers**: `energy_space_reclaim.as` (clear obsolete
  T1 wind/solar to make room), `factory_exit_reclaim.as` (reclaim own buildings
  sitting in a factory's exit strip), `t1_factory_reclaim.as` (reclaim surplus
  T1 factories once on T2/T3).
- **Per-faction config split.** `ArmadaBehaviour.json` / `CortexBehaviour.json` /
  `LegionBehaviour.json` rather than one shared file — a structural answer to the
  faction-parity trap CLAUDE.md describes.
- **Income-gated factory caps.** First T1 and first T2 factory free; each
  additional T1 needs 15 metal income, each additional T2 needs 20.
- **A Lua→AI terrain bridge**, format
  `TERRAIN_HINT:build_pct=<int>;path_pct=<int>;ally_zone=<int>;water_map=<0|1>`.

**Two cautions, both verified by reading their actual code rather than their
docs:**

1. `script/hard/helper/resource_bonus.as` **is entirely commented out.** Every
   line, including the `namespace` declaration. Yet `MAINTENANCE.md` instructs
   maintainers to "use `ResourceBonus::GetPlanningMetalIncome()` instead of raw
   `aiEconomyMgr.metal.income`". **[VERIFIED]** The documented API does not
   exist.
2. `MAINTENANCE.md` says "Native DLL bindings for unit-positioned fight tasks
   are available (`SFightTask.hasPosition`/`position`)". Grepping their
   `military_task.as` and `task.as` finds **no use of `hasPosition`**.
   **[VERIFIED]** Aspiration, not implementation.

So: read Azmodious's code, not its documentation. It has the same failure mode
CLAUDE.md warns about — a claim written into a doc, then believed.

### 1.7 Azmodious ships a custom-built DLL with extra AngelScript bindings

This is the most directly actionable finding in the survey.

`factory_exit_reclaim.as` line 185 calls `factory.GetBuildingFacing()` on a
`CCircuitUnit`. Grepping `vendor/circuitai/src/circuit/script/` (branch
`barbarian`, HEAD `1d9952f`, 2026-07-27) finds **no `GetBuildingFacing` binding
at all**. The `SFightTask` registration in `MilitaryScript.cpp` exposes exactly
`type`, `check`, `promote`, `power`, `vip` — no `position`. **[VERIFIED]**

Their `SkirmishAI.dll` is 4,411,392 bytes against stock BARb's 6,963,325
(`recoil_2026.06.12`). Different build; size alone proves nothing, but combined
with the binding evidence the conclusion is solid:

> **Someone outside rlcevg is compiling CircuitAI with added AngelScript
> bindings and shipping the DLL inside their AI folder.**

That is the wall this repo keeps hitting — "we keep needing things only
reachable in C++" — and it turns out the wall is routinely crossed by at least
one other person. `docs/06-building-the-dll.md` describes the toolchain; this is
evidence the payoff is real and that adding a binding is the normal move rather
than an exotic one.

Caveat: shipping a custom DLL means the variant no longer tracks engine BARb
updates automatically, which is the exact breakage this repo's derive-from-BARb
deploy was built to avoid. Trade-off, not a free win.

---

## 2. The approaches, compared

[02 — The AI landscape](02-ai-landscape.md) already documents the interfaces.
What this survey adds is **what each layer costs in practice**, based on who is
actually using it.

| | Native C++ (CircuitAI) | AngelScript in the game archive | JSON config | Lua gadget AI |
|---|---|---|---|---|
| Who uses it | rlcevg; Azmodious (custom build); nobody else found | this repo, Azmodious, Felnious, BAR upstream | everyone | BAR's Simple* AIs only |
| Build step | cross-compile toolchain | none | none | none |
| Sees | everything: threat map, terrain analysis, pathing, enemy tracking | ~405 bindings, whatever C++ chose to expose | declarative tables only | full `Spring.*`, but on the sim thread |
| Survives engine update | no — must rebuild | yes | yes | yes |
| Multiplayer | needs its own shortName | needs its own shortName | needs its own shortName | whole archive must match |

Observations that are not in doc 02:

- **The AngelScript layer is where all the interesting third-party work is
  happening.** Azmodious, Felnious and this repo are all overwhelmingly
  AngelScript + JSON. That is where the community's effort sits.
- **The binding surface is the real constraint, and it is negotiable.** The
  practical difference between "reachable" and "not reachable" is a
  `RegisterObjectMethod` line in `src/circuit/script/*.cpp`. rlcevg's recent
  commit history is described as "many of them adding AngelScript bindings"
  (doc 02), and Azmodious added its own. Treat a missing binding as a small C++
  task, not a hard boundary.
- **Nobody found is doing ML/RL, an external-process AI, or a from-scratch
  native AI for BAR.** **[UNKNOWN]** rather than [VERIFIED] — this is an absence
  finding and absence is unreliable. But four independent searches
  (GitHub repo search, GitHub code-adjacent search, general web, forks of
  CircuitAI) surfaced nothing. See [08 — ML and RL](08-ml-and-rl.md).
- **Scripted build orders as a standalone approach do not exist in BAR.** The
  closest thing is `commander.as`-style opener definitions inside a BARb
  variant, and the `Simple*` Lua gadget's fixed build table.

---

## 3. Community knowledge about what makes a BAR AI good or bad

**This is the thinnest part of the survey and the honest headline is: very
little useful public information exists.**

There is no BAR AI forum, no wiki page on AI design, no ladder for AIs, and no
tournament. `docs/09-resources.md` already records that there is no dedicated AI
community and AI talk happens in general Discord dev channels — which are not
indexed and were not reachable here. Reddit is not crawlable by this agent
(`reddit.com` is blocked to our user agent). Web search on every phrasing tried
returned YouTube thumbnails and unrelated Steam threads.

**What exists instead is the issue trackers.** They are the only substantive
public record of what is wrong with BAR AIs, and they are worth more than the
absent forum posts.

### 3.1 Our list, checked against the trackers

Taking the four problems from `USER-FEEDBACK.md` / the task brief:

**a) Armies that posture instead of engaging — UNIVERSAL, with a diagnosed root
cause and a merged fix.**

[CircuitAI PR #135](https://github.com/rlcevg/CircuitAI/pull/135), by Corosus,
merged 2025-12-07, titled *"Fixing the late game / large army AI engagement
issues for hard difficulty AI"*. Quoting the body **[REPORTED — the author's
own account]**:

> the observed problem of BARb stable hard profile AI not attacking enough in
> large enemy / late games, where they just build up armies but not attack as
> much as they should, aka: seeing a large no mans land between armies where
> they don't engage eachothers armies and just posture

The diagnosed causes were **not tactical logic** — they were **threat-map
perception**:

1. Weapon data misread from the JSONs. The AI valued `armthor`'s missile at
   80,000 damage every 3 seconds (its reload time) when the real damage is 0 and
   the real cadence is a 65-second stockpile build. Result: the AI saw a Thor as
   ~10x more threatening than it is and hid in base on sight of a group.
2. Threat areas around enemy units were too large. The fix shrinks perceived
   threat *range* by up to 60% as detected enemy count rises, affecting both
   target selection and pathing around threat.

The author flags his own fix's weakness **[REPORTED]**: enemy *count* is a poor
metric because it counts passive units and buildings, so flying over a base
inflates it; he suggests absolute threat values would be better.

**This is directly relevant to us.** Our complaint is the mirror image — armies
walking *into* defended positions rather than raiding economy. Both are threat-map
problems, and PR #135 establishes that (i) the threat map is the lever, (ii) it
is driven by JSON weapon data that can be wrong, and (iii) it is tunable without
touching tactical code. Before writing new targeting logic, check what the threat
map thinks. **We have not verified whether this fix is in the DLL we run.**

**b) Base sprawl and never reclaiming old buildings — UNIVERSAL, partially
solved, two independent approaches.**

- [BAR PR #7062](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/7062)
  by veez-e, merged 2026-03-12, *"BARb: widen hard-profile factory egress
  lanes"*. **[REPORTED]** the symptom: *"BARb ground units can exit factories,
  but later get trapped inside the AI base once the base becomes dense… units
  are not stuck inside the lab, they lose a reliable corridor after leaving
  it."* The fix is pure `block_map.json` — widen `fac_land_t1` yard from
  `[0,30]` to `[8,30]` and `fac_land_t2` from `[12,20]` to `[16,20]`. The author
  explicitly notes placement is delegated to native code so `block_map.json` is
  the only game-side lever.
- Azmodious attacks the same problem from the other end with
  `factory_exit_reclaim.as` (reclaim your own buildings out of the exit strip,
  rotated by `GetBuildingFacing()`), `energy_space_reclaim.as` (clear obsolete
  T1 energy to make room) and `t1_factory_reclaim.as`.

So: **the "AI base becomes an impassable maze" problem is well known and has two
known families of solution** — prevent it with spacing config, or fix it with
reclaim tasks. We should check `block_map.json` spacing *first*, because it is
the cheap one; CLAUDE.md's own warning applies here, since reclaim tasks spend
constructor time and spacing does not.

**c) No coordination between allied AIs — RECOGNISED, minimally addressed.**

- CircuitAI issue *"Make expansion limit take allyteam expansion into account"*
  (closed) — allied AIs over-expanding into each other.
- CircuitAI issue *"[BAR] Do not build in player bases"* (closed) — became the
  `ally_base` AI option, which is `def = true` in the shipped `AIOptions.lua`.
  **[VERIFIED]** in Azmodious's copy of `AIOptions.lua`.
- Azmodious's `lane.as` mixes `teamId`/`skirmishAIId` into lane choice
  specifically "so allied AIs do not all converge on the same tactical lane".

This is the weakest-covered of the four. There is **no shared plan, no target
handoff, no combined attack timing** anywhere found. The existing work is all
*de-confliction* (stay out of each other's way), not *coordination*.

**d) Poor expansion — RECOGNISED, older and vaguer.**

Open/older CircuitAI issues **[VERIFIED as existing]**:
*"[BAR] Testing AI fails to build any metal maker spots and even builds energy
converter in the metal"*, *"Circuit AI places three mexes on one spot"*,
*"[BAR] Testing AI seems to fail most of the time on smaller maps"*,
*"A Novice circuit started the game with a redundant factory"*. Several date from
2023 and may well be fixed; none were re-tested here.

### 3.2 Other known problems worth knowing about

- *"barbarian does not reclaim nor resurrect Thors or Titans"* (open, 2023-04-30)
  — wreck reclaim is weak generally.
- *"Medium BARb commander gets stuck while building"*
  ([BAR issue #7494](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/7494),
  open, 2026-04-20). Azmodious has `commander_mex_travel.as` addressing a related
  symptom — a commander that idles chasing a distant mex before the first
  factory.
- *"barb arm can't build t3 gantry"*
  ([BAR issue #4533](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/4533),
  open since 2025-03-18). Relevant to this repo's T3 work: there may be a
  **faction-specific plumbing bug** on Armada T3 independent of the economics
  argument in CLAUDE.md. Worth checking directly before more T3 tuning.
- *"[BAR] Testing AI fails to move back and allows itself to be destroyed"*
  (open) — retreat logic.
- Crashes are a recurring theme across the whole tracker history, including
  *"Guaranteed crash when hosting a multiplayer game with 'Random faction' Barb
  AI"* and multiple Legion-profile crashes through mid-2025.

### 3.3 What is NOT in the public record

Recorded so it is not searched for again. **[UNKNOWN]**, not "does not exist":

- Any design discussion of BAR AI architecture outside `CircuitAI/doc/Profile.md`.
- Any measured comparison between BARb versions.
- Any AI-vs-AI tournament, ladder or leaderboard.
- Any discussion of allied-AI cooperation as a design goal.
- Discord content. This is very likely where the real discussion is, and it is
  the single biggest gap in this survey. Someone with Discord access should
  search `#ai-dev`-adjacent channels; it would probably outproduce everything
  above.

---

## 4. AI versus human performance

**There is no measured public data. Everything below is opinion or inference.**

### 4.1 What is actually claimed

Chobby's tooltip for BARb, verbatim **[VERIFIED as the text; OPINION as the
claim]**:

> "The recommended excellent performance, adjustable difficulty, **non-cheating**
> AI. Add as many as you wish!"

That is marketing copy in a config file. Its one load-bearing factual content is
**non-cheating**: BARb by default gets no resource bonus and no global vision.
This is corroborated by `AIOptions.lua`, where `cheating` ("Enable global sight")
is `def = false`. **[VERIFIED]**

The frequently-quoted line that BARbarian is "equivalent to an average/good
player" and has "8 difficulty levels" surfaced in search-engine summaries during
this survey but **could not be traced to any primary source**. The BAR team page
for Lamer says only "Author of the amazing BARbarian AI". The 8-difficulty claim
is demonstrably false (see §1.2). **Treat the whole quote as unreliable.**
`docs/09-resources.md` already flags DeepWiki as wrong about BARb; this appears
to be more of the same.

### 4.2 The only usable signal: what people record themselves doing

YouTube titles are weak evidence, but they are consistent and they are the only
public signal found. **[OPINION / weak inference]**

- "1 vs 3 Barbarian AI", "1 vs 4", "1v5", "1v6 Barbarian AI | Winning"
  ([1v5](https://www.youtube.com/watch?v=0MfgK0SYl5U),
  [1v3](https://www.youtube.com/watch?v=b7-BeRsTvbU),
  [1v4](https://www.youtube.com/watch?v=euToV7Q0tUs),
  [1v6](https://www.youtube.com/watch?v=xPAqtQhkaCU))
- "1v2 Barb AI with 100% Bonus Resource"
  ([link](https://www.youtube.com/watch?v=s5YJCguMR5w))
- "How To Beat the Hard BARbarian AI",
  "How to Beat The Cheater AI Hard Barbarians"

The rough inference: **a competent single human expects to beat BARb at
somewhere between 3-to-1 and 6-to-1 odds, unhandicapped.** A separate creator
needed a **100% resource bonus** to make a 1v2 interesting. Content creators
select for impressive outcomes, so read these as an *upper* bound on human
advantage rather than a measurement.

The "Cheater AI" phrasing in one title refers to the **host-applied resource
bonus**, not to BARb itself. Worth keeping straight: BARb is non-cheating; the
lobby lets a host hand it a bonus, and CLAUDE.md records +40% as normal in
hosted games and a player observed at 398 metal/second.

### 4.3 What this means for us

- **There is no benchmark to beat and no scoreboard to enter.** Nobody is
  measuring BAR AI strength publicly. This repo's `run_tournament.py` +
  `composition.py` discipline is, as far as this survey can tell, **more
  rigorous than anything else in the BAR AI space.** That is worth knowing both
  as reassurance and as a warning: there is no external check on our numbers.
- **"Beat BARb" is a low bar and a moving one.** BARb is actively developed
  (commits 2026-07-31) and the merged PR #135 made it materially more
  aggressive. A control run against `BARb:stable` is a control against a target
  that moved in December 2025.
- **The interesting comparison is Azmodious, not BARb.** It is the only other
  project doing sustained, structured work at our layer.

---

## 5. Summary — what to do with this

### The approaches most different from ours

1. **Azmodious's map-profile + role system.** Per-map, per-start-spot data
   assigns each AI a role (AIR/TECH/SEA/FRONT) and a lane, and everything —
   factories, economy constants, defence gating, constructor counts — hangs off
   that. We tune one global policy; they tune four role policies and select by
   map position. This buys per-map and per-slot appropriateness we currently
   have no mechanism for, and it is the only found answer to "naval players go
   idle" (a `SEA` role) and to allied AIs stacking up (lane by `skirmishAIId`).
   Cost: hand-curated map data that goes stale.
2. **Shipping a custom-built CircuitAI DLL with extra AngelScript bindings.**
   Azmodious does this. It converts our hardest constraint — "only reachable in
   C++" — into a build-toolchain problem we already have documented. Cost:
   loses the derive-from-installed-BARb property that makes our variant survive
   engine updates.
3. **Fixing perception rather than behaviour** (CircuitAI PR #135). Instead of
   writing tactical rules, correct what the threat map believes about enemy
   weapons and shrink threat radii. One JSON-adjacent change altered engagement
   behaviour across the whole AI. This is the cheapest lever found anywhere in
   the survey and it is the opposite of the "twelve behaviour rules that each
   spend constructor time" failure CLAUDE.md documents.

### Problems on our list that are universal, with known solutions

- **Armies posturing / not engaging correctly** — universal. Root cause is the
  threat map misreading JSON weapon data (stockpile and paralyser weapons in
  particular), fixed in CircuitAI PR #135. Check whether our DLL has it.
- **Base sprawl blocking movement** — universal. Two known solutions: widen
  `block_map.json` factory yards (BAR PR #7062, free), or add reclaim tasks
  (Azmodious, costs constructor time). Try the spacing config first.
- **Not reclaiming old buildings** — Azmodious has three separate helpers for
  this; upstream has an open issue about not reclaiming Thor/Titan wrecks.
  Recognised, not solved upstream.
- **Poor expansion** — recognised in old CircuitAI issues, vaguely.

### Where we may be solving a problem nobody else has

- **Allied-AI coordination.** Everyone else treats this as *de-confliction*
  (`ally_base` option, allyteam expansion limits, lane separation). Nobody found
  is attempting shared targets, combined attack timing, or a team plan. Two
  readings, and this survey cannot distinguish them: either it is genuinely
  unexplored ground, or it is a bad idea that others tried and dropped without
  writing it down. Given CLAUDE.md's record on inferred-from-nothing changes,
  treat the second as live until evidence says otherwise.
- **Our benchmark rigour.** Nobody else appears to run controlled tournaments
  with composition analysis. This is probably genuinely better practice — but
  CLAUDE.md already records that the standard benchmark's economics (4-9 metal/s
  per team) do not reproduce hosted games (12-41/s), so being the most rigorous
  measurer of the wrong thing remains possible.
- **Nothing else on our list appears unique.** Poor expansion, sprawl, and
  army-positioning are all in someone else's tracker.

### One process warning

Azmodious's `MAINTENANCE.md` documents two features that do not exist in its
code (`resource_bonus.as` fully commented out; `SFightTask.hasPosition` never
called). This survey caught both only by reading the source after reading the
doc. It is the exact failure CLAUDE.md's comment rules are written against, seen
in another project. **Read other people's code, not their docs.**

---

## Sources

**Verified from source or local files**

- https://github.com/rlcevg/CircuitAI · [branches](https://github.com/rlcevg/CircuitAI/branches/all) · [barbarian commits](https://github.com/rlcevg/CircuitAI/commits/barbarian)
- https://github.com/rlcevg/CircuitAI/pull/135 — late-game engagement fix
- https://github.com/beyond-all-reason/Beyond-All-Reason/pull/7062 — factory egress lanes
- https://github.com/beyond-all-reason/Beyond-All-Reason/issues/7494 · [#4533](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/4533) · [#5281](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/5281)
- https://github.com/Noodles98/Azmodious — and its [MAINTENANCE.md](https://raw.githubusercontent.com/Noodles98/Azmodious/main/Azmo/dious/MAINTENANCE.md)
- https://github.com/AnonymoScoot/BAR_AI · https://github.com/derekShaheen/Metal-BAR-AI · https://github.com/erik-moedt/bargandhi
- [BYAR-Chobby aiCustomData.lua](https://raw.githubusercontent.com/beyond-all-reason/BYAR-Chobby/master/LuaMenu/configs/gameConfig/byar/aiCustomData.lua) · [aiSimpleName.lua](https://raw.githubusercontent.com/beyond-all-reason/BYAR-Chobby/master/LuaMenu/configs/gameConfig/byar/aiSimpleName.lua)
- Local: `vendor/bar/luaai.lua`, `vendor/bar/luarules/gadgets/ai_simpleai.lua`,
  `vendor/circuitai/src/circuit/script/MilitaryScript.cpp` (HEAD `1d9952f`, 2026-07-27)

**Opinion / weak**

- https://www.beyondallreason.info/team/lamer
- YouTube: [1v5](https://www.youtube.com/watch?v=0MfgK0SYl5U) · [1v3](https://www.youtube.com/watch?v=b7-BeRsTvbU) · [1v4](https://www.youtube.com/watch?v=euToV7Q0tUs) · [1v6](https://www.youtube.com/watch?v=xPAqtQhkaCU) · [1v2 +100% bonus](https://www.youtube.com/watch?v=s5YJCguMR5w)

**Could not reach**

- reddit.com (blocked to this agent's user agent)
- BAR Discord (not indexed) — **the biggest gap in this survey**
