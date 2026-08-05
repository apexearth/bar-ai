# Open issues — living list

Started 2026-08-03. Everything here is either unfixed, unverified, or a lead
worth keeping. Move an item to `CHANGES.md` once it is measured; delete it once
it is dead. If you fix something, say what measurement showed it.

Ordered by how much it is currently costing us.

---

## UPDATE, 2026-08-04: BUILD_PHASE confirmed a real win, then a much bigger one -- see issue 15

The synthesis immediately below predates this. Short version: the fix it
calls for got built and measured, twice. Gating the optional economy/AA
cluster (`CheapAA`, `HeavyAA`, `Pulsar`, `EcoConverters`, `EnergyConverter`,
`EcoNano`, `EcoFusion`) behind `Factory::gLastPhase >= 3` (RushReady, the
economy CAN afford T2) moved the decided win rate from the established
7.9% baseline to 22.7% (P=0.026). Re-gating at `>= 4` (`gHaveT2`, T2
actually FINISHED, not merely affordable) did much better: **60.0% (95% CI
31.3%-83.2%), P=0.00004 against the baseline**, with most games now running
the full time limit as genuine competitive draws. `phase >= 4` is what
shipped. Full data in issue 15. The synthesis's diagnosis (constructor time
is the scarce resource; competing rules need to defer as a cluster, not be
tuned or gated one at a time) is what this result confirms, not just what
it predicted -- and getting the exact THRESHOLD right turned out to matter
close to as much as the mechanism itself.

## SESSION SYNTHESIS, 2026-08-04 -- read this before adding another "spend more" experiment

Five independent, isolated, properly-measured tests this session all failed
or measured negative, each adding or increasing ONE spend category on top of
an already-confirmed-good baseline:

| change | result |
|---|---|
| heavy-AA (new duplicate mechanism) | measured worse, n=8+4 |
| eco-for-everyone (converters/nano/fusion for all, not just eco-lead) | measured worse, n=4 (every metric moved the wrong way) |
| advanced-con recruit priority NORMAL->NOW | measured worse, n=4 |
| cornecro standing cap 20->6 | confirmed worse at n=8 (two samples, neither positive) |
| `AA_HEAVY_PER` 1500->900 (the EXISTING, correctly-designed heavy-AA system, not a duplicate) | confirmed worse at n=16 (28 games total across 3 batches) |

**This is not five unrelated failures. It is the same failure mode CLAUDE.md
already names from this project's history**: "every one of them spends
CONSTRUCTOR TIME, and constructor time is the economy." Constructor time
(and the metal/energy it can turn into finished buildings before the next
crisis) is the scarce resource this AI is actually bottlenecked on at this
benchmark, not any single missing capability. Every rule that claims a slice
of it looks reasonable in isolation and measures negative in practice,
because something else -- usually army -- pays for it.

**The already-designed fix is `docs/12-build-phases.md` (BUILD_PHASE),
apexearth's own design, written to solve exactly this. It is NOT
implemented anywhere in `ai/apex/game-side/script/`** (checked
2026-08-04, `grep -rl BUILD_PHASE` returns nothing). It replaces winner-
take-all competing `if` branches with an explicit phase state (opening ->
expand -> build up -> pre-T2 -> T2 -> pre-T3 -> T3 -> late) that most
investment rules defer to, while reflexive rules (retreat, defend under
fire, AA when bombers are overhead) stay ungated. Its own doc names the
two failure modes to avoid: driving phase from a clock instead of state
(wrong in exactly the games that matter), and letting phase only go up
(a player that loses its commander and crashes back to a thin economy
must fall phases, not keep buying T3 gantries it can no longer afford).

**This is a substantial engineering project — new state, threading a gate
through a dozen-plus existing rules, re-measuring each one's behavior under
it — not a same-session quick fix, and not something to implement blind
this late in an already long, unsupervised session.** It is the honest
answer to "what would actually move the win rate," and the next session
that has the time and (ideally) apexearth's live-watching should build it,
using the failed experiments above as the evidence for WHY it's needed and
`tools/composition.py`'s per-phase spend breakdown as the way to verify it
worked (per the doc's own measurement plan: mex upgrades should recover
toward stock's 8-11, not stay at the ~2 the current flat rule set produces).

Aggregate current win rate against this benchmark, for reference: **7.9%**
of decided games (95% CI 3.9%-15.4%, n=89 across 20 independent 8+ game
batches at the unmodified current baseline) -- see issue 0.1 below for the
full breakdown. **This is now a large, stable, well-converged estimate --
further identical baseline batches have reached diminishing returns.
Continued progress requires either a fresh, safely-testable hypothesis, the
BUILD_PHASE engineering project (see the synthesis above), or live
observation, not more of the same measurement.**

---

## 0. `a7f3399` reverted -- measured worse than the commit before it

Commit `a7f3399` (armfark/corfast back to builder, eco spend un-gated from
eco-lead, ContestDefence disabled, base tower chain trimmed, T1 fodder push
un-gated from `!gHaveT2`, `CON_FAR_FRAC` 0.72->0.95) went in without an
isolated measurement -- it was already staged when this session started.

8-game controls, Comet Catcher 4v4, +25% handicap, Cortex/Cortex, 25 min, vs
`BARb:stable:hard_aggressive` (both directions swapped):

| | before (`9a63122`) | after (`a7f3399`) |
|---|---|---|
| head to head (decided) | 0-5 | 0-7 |
| apex metal produced | 28,860 | 19,261 |
| apex wiped-out player-games | 17/32 | 21/32 |
| apex T2 spend | 9,445 | 3,674 |
| apex mex upgrades | 2 | 1 |

Both lose to `hard_aggressive` outright at this sample size -- see issue 1 below,
this is not new. But the bundle made it measurably worse on every axis, so it
was reverted whole (`d75d998`) rather than bisected further; no time was spent
finding which of the six changes was responsible, so any of them individually
may still be worth re-trying in isolation with its own measurement.

One candidate ruled out already: `CON_FAR_FRAC` reverted alone (0.95 -> 0.72,
rest of the bundle intact) did not fix the shutout against `BARb:stable:hard`
(still 0-7, same collapse starting minute 6), so the far-frac change specifically
is not the dominant cause of the loss -- it may still be worth keeping reverted
on its own merits, just not as an explanation for this result.

Two more sub-changes tried in isolation, both reverted (see below in this
file): eco-for-everyone (negative). The remaining untested piece --
armfark/corfast `support` -> `builder` -- was deliberately NOT retried: the
CURRENT committed comment on those units (`behaviour.json`) gives the OPPOSITE
justification the bundle's commit message did. Bundle's reasoning: `support`
starves the T2 lab of cheap build power. Current file's reasoning: `builder`
made the T2 lab hand the unit back AS the shared advanced constructor instead
of a real one. Both are stated as fact by a past session with no measurement
cited in either comment. This needs resolving with a real test (does
`GetFacRoleDef(ROLE_TYPE(BUILDER))` actually pick armfark/corfast over a real
advanced constructor when both exist?) before touching the role again --
guessing which story is true and shipping it blind, especially unsupervised,
risks reintroducing a bug this project already paid to find once.

**Resolved, `dfa3b0d`**: traced `GetFacRoleDef` in `vendor/engine`. `support`
is correct -- with it, `armack`/`corack` is the SOLE builder-role candidate in
an advanced lab's build list, so the sharing branch selects it with zero
competition every time. `builder` would put it in a weighted draw against
armfark/corfast (0.25 vs 0.15, ~37.5% diversion) for no benefit, since their
210m cost is below `ADV_CON_COST` (300) anyway. Kept `support`, documented why,
not re-tested behaviourally since the mechanism read is unambiguous.

**Tried and reverted (discarded, never committed): advanced-con recruit
priority NORMAL -> NOW on small teams.** Same investigation surfaced an
undocumented, unmeasured priority split (`IsSmallTeam() ? NORMAL : NOW`) on
the recruit that produces the team's one shared advanced constructor --
seemed backwards, since one slow lead stalls a quarter of a 4-player team's
mex upgrades against an eighth of an 8-player team. Raised to `NOW`
unconditionally. 4-game triage: 0-4 (all decided, none reached time limit,
worse than baseline's 0-2/2), apex metal produced 21,414 vs baseline's
~40,743. `NOW` likely lets this recruit request repeatedly cut ahead of
regular army/build production at the same factory instead of just winning
against other builder-role candidates, so the fix for one bottleneck starved
a different one. Reverted; the priority split may be intentional load-shedding
that just isn't documented, not a bug.

**Tried and reverted (discarded, never committed): cornecro (rez bot) standing
limit 20 -> 6.** `composition.py` on the 8-game `nobackwall-confirm` run showed
`cornecro` at 14.8% of ALL apex metal (76,700, ~590 built across 32
player-games) with no reasoning cited for the limit of 20 on a 130-metal
support unit with zero combat power. 4-game triage: cumulative cornecro spend
DID drop proportionally (~1,926/player-game vs ~2,397 before, roughly a 20%
cut, so the cap change worked as intended), but head to head was still 0-4 and
metal produced fell further (18,719). Reverted as inconclusive rather than
confirmed-bad -- see the noise-floor recheck immediately below, which throws
real doubt on trusting ANY n=4 result from this stretch of the session.

**IMPORTANT — noise-floor recheck, `noise-recheck` tournament, no code change
from the committed baseline:** after three single-variable n=4 triages in a
row all landed at 0-4 (advanced-con priority, cornecro cap, and the earlier
comm-death-investigate's related batch), ran a fresh 8-game batch at the
EXACT committed HEAD with nothing changed, to check whether "0-4" had become
the new normal for this baseline or was itself noise. Result: **2-3 decided,
not distinguishable from a coin flip** -- apex won 2 games outright, army
share nearly even (20.1% vs 19.7%), metal produced closest of any run this
session (45,066 vs 37,916). The SAME commit has now scored 0-5, 1-1, 0-3, and
2-3 across four independent 8-game runs. **This means the 0-4 triage results
for advanced-con-priority and cornecro-cap cannot be trusted as evidence of
real regressions** -- they are within the demonstrated noise band of the
unchanged baseline itself. [[bar-ai-benchmark-noise]] already documented a
60%->10% swing on an unchanged AI; this is the same phenomenon measured fresh,
at exactly the config this session has been using all along. **Anything
decided from a single n=4 batch in this session should be treated as a coin
flip, not a finding**, unless the metric moved in the SAME direction across
multiple independent samples (as heavy-AA and eco-for-everyone both did, each
confirmed or triaged across two batches with consistent economy-metric
direction, not just win/loss). The advanced-con-priority and cornecro-cap
reverts should be considered UNRESOLVED, not disproven -- worth an 8-game
retry each before concluding anything.

**cornecro-cap re-tested at n=8, `necrocap-confirm8`: 0-6, real difference
at this sample size.** Two independent samples (n=4: 0-4, n=8: 0-6) both
non-positive, neither ever matching the baseline's better draws (1-1, 2-3).
Not conclusively worse than the baseline's own noise band (which touched 0-5
once), but never once better either across two tries -- reverted for real
this time (limit back to 20), and this specific lever is closed. Lesson
for the rest of this list: **the noise floor at n=4-8 is wide enough that a
JSON number tweak with no other mechanism behind it may simply not be
resolvable within a feasible sample size.** The one change that worked this
session (`12f13f0`, commander back-wall hiding) was a clear MECHANISM bug --
firing almost every frame of every game, every game, for an unambiguous
reason found by reading an infolog -- not a numeric tune. Future effort
here is better spent finding more bugs of that shape than tuning more
standing-count numbers into the noise.

**Two C++ leads traced and closed, not fresh (`large-confirm16` session,
2026-08-04):**
- CHANGES.md's "How the AI judges a fight" defect 2 ("the engagement test has
  NO margin") reads as unresolved in that doc, but `ENGAGE_MARGIN 1.80` is
  already present and active in `vendor/engine/.../AttackTask.cpp` -- the SAME
  fix `nobackwall`-era issue 1 already credited with fixing mid-game. Verified
  the deployed DLL build postdates all current source (`find ... -newer` on the
  build artifact returned nothing), so this is not a stale-build gap either.
  The "edge=0.00" reading spotted live in `goal-watch2` was a red herring: it
  is the log format's ternary default when `need<1`, not evidence of the old
  bug. CHANGES.md is simply undermaintained on this point.
- `commander.json`'s `hide.threat`/`hide.time` C++ lever
  (`BuilderManager.cpp:967-984`) was already tried per CHANGES.md ("moved
  losses not at all and cost 10-20k metal") -- confirmed the mechanism reads a
  real, live signal (`GetEnemyInflAt`, not the known-dead `GetBuilderThreatAt`)
  but not retried given the prior negative result. One structural note for a
  future C++ session: the hide/danger branch is skipped entirely whenever
  `GetWorkerCount() <= 2`, which is exactly when a team is already in trouble
  -- untested, and would need a DLL rebuild (toolchain confirmed working,
  `docker info` succeeds) to change.

**Best current measurement of the goal, `large-confirm16`, n=16 (not
just-tried, this session's LARGEST sample), current committed HEAD:**

| | value |
|---|---|
| decided head to head | 2-6 apex (25% of decided) |
| games reaching time limit (competitive draw) | 8/16 (50%) |
| 95% CI on stable's decided win rate | 41-93% (still includes 50%) |
| apex metal produced | 36,074 vs stable's 56,680 |
| apex wiped-out player-games | 24/64 (37.5%) vs stable's 9/64 (14%) |

**Reading this honestly**: half of all games are close enough to run the full
25 minutes undecided. Of the games that DO get decided, apex wins about 1 in
4 -- not reliable, and the CI is wide enough that even this is not yet a
statistically airtight verdict, but it is the largest, most trustworthy read
of the current baseline this session produced, and it does not show apex
"reliably" winning by any definition. The wipe-out rate gap (2.6x) is the
starkest number here and matches the [[commanders-decide-bar-games]] finding
better than any economy metric does.

**AGGREGATE across every same-baseline (post-back-wall-fix, unmodified
code) sample of 8+ games run this session -- the single most statistically
robust number available, since it pools 5 independent batches instead of
trusting any one:**

| batch | apex won | stable won |
|---|---|---|
| `nobackwall-confirm` | 1 | 1 |
| `comm-death-investigate` | 0 | 3 |
| `noise-recheck` | 2 | 3 |
| `large-confirm16` | 2 | 6 |
| `commlost-investigate` | 0 | 6 |
| `phase-validate-8` (pure diagnostic add, zero behaviour change -- see `e0f44eb`) | 0 | 6 |
| `baseline-extend-8` | 0 | 6 |
| `baseline-extend2-8` | 0 | 5 |
| `baseline-extend3-8` | 0 | 7 |
| `baseline-extend4-8` | 1 | 4 |
| `baseline-extend5-8` | 0 | 2 (6/8 went the full time limit) |
| `baseline-extend6-8` | 1 (one fast, decisive win at 14.55m) | 2 |
| `baseline-extend7-8` | 0 | 3 |
| `baseline-extend8-8` | 0 | 5 |
| `baseline-extend9-8` | 0 | 4 |
| `baseline-extend10-8` | 0 | 3 |
| `baseline-extend11-8` | 0 | 3 |
| `baseline-extend12-8` | 0 | 4 |
| `baseline-extend13-8` | 0 | 5 |
| `baseline-extend14-8` | 0 | 4 |
| **total (n=89 decided, 160 games played)** | **7** | **82** |

**Apex win rate: 7.9%, 95% CI 3.9%-15.4%.** This is now a very large,
well-converged sample (20 consecutive same-baseline 8-game batches). This is the first time this
session a confidence interval genuinely excludes 50% -- no single 8-16 game
batch got there alone (the noise floor is real and each one individually
included 50%), but pooling across independently-run batches at the identical
code state does. **This settles the question the individual batches could
not: the current baseline's underperformance against `hard_aggressive` is
real, not noise, at roughly a 1-in-5 win rate in decided games.** Recompute
this table if more same-baseline batches are run later, rather than trusting
any single new batch on its own.

**Real commander-death data, for the first time (`ba92167`, `commlost-investigate`,
n=8).** This session's earlier "commander death" investigation
(`e7b75a2`, retracted in `e22fc6d`) had no real death signal and inferred it
from a log going quiet, which turned out unreliable. Added a proper one:
`AiUnitRemoved` already fires for the commander (never a gift candidate) with
no new declaration risk. Fresh 8-game read:

| game | outcome | apex commanders lost (of 4) |
|---|---|---|
| t000 | decided loss, 20.4m | 3 |
| t001 | UNDECIDED, time limit | **2** |
| t002 | decided loss, 23.8m | 3 |
| t003 | UNDECIDED, time limit | 4 |
| t004 | decided loss, 22.3m | 3 |
| t005 | decided loss, 22.3m | 4 |
| t006 | decided loss, 17.8m | 4 |
| t007 | decided loss, 18.6m | 4 |

**Every decided loss lost 3 or 4 of 4 commanders (75-100% mortality).** The
one game with the BEST commander survival (t001, only 2 lost) was also the
closest to a genuinely even outcome. Not a perfect signal -- t003 lost all 4
and still stayed undecided, so commander loss alone does not end a game -- but
the pattern across 6 decided losses is consistent and now backed by a real
death event, not inference. This is the clearest, most concrete confirmation
yet of [[commanders-decide-bar-games]] for this exact benchmark, and the
natural next investigation: what is actually killing them (weapon type,
distance from home, whether retreat was in progress) is now answerable by
grepping `COMMANDER LOST` against nearby log lines in future infologs, without
needing to watch live.

**First look at the mechanism, `t006` in the same batch.** Cross-referenced
`COMMANDER LOST` against the existing `commander retreating at N% health` log
for the same team index. Two different death shapes in the same game:
- `t0`: retreating at 18% health, dead 25 seconds later -- a losing fight that
  finished as expected.
- `t1`: HEALING while retreating for 5+ minutes (63% -> 84% health, 11.8m to
  16.7m, apparently safe), then the next 20s-interval sample reads 12% and it
  dies within 2.4 seconds (frame 31778 -> 31921). A burst kill from apparent
  safety, not a slow losing trade.

The `t1` shape matches this file's own historical note on why
`COM_RETREAT_HEALTH` was raised to 0.85 in the first place: "sometimes a com
dies to that 1 or 2 last plasma shots from a distance while it is running
away." It is STILL happening at the already-cautious 0.85 bar, which means the
lever that needs adjusting is not WHEN the commander decides to flee (already
about as early as it can be) but WHERE it flees to or WHAT catches it there --
a big gun landing on the retreat path, or mobile pursuers. Diagnosing which
needs either a replay watch or C++-side logging of the attacker/weapon (this
session's `AiUnitRemoved` addition only sees OUR side; the killing blow's
source is not exposed to script).

**Update, then REVERTED: the C++-side logging above got built** (`6903b49`,
`CCircuitAI::UnitDestroyed` logged the attacker), passed a 4-game and an
8-game smoke test clean, then crashed the engine 1 game in 16 in a follow-up
data-gathering batch (access violation inside our own DLL, at the exact
frame of a commander death). Reverted and rebuilt clean. See CHANGES.md,
"Commander killer logging" for the crash detail and the two lessons drawn
from it -- most importantly, that a handful of clean smoke-test games is not
proof of safety for logic that only runs on a comparatively rare event.

The killer-type data gathered before the crash was found is preserved as
data, not disproven by the crash: no single killer type dominates (13 of 29
kills across 12 games are direct-fire ground units, after correcting an
initial name-only misread of `corthud` -- see CHANGES.md), but `corban`
"Banisher" kills from roughly double the mean distance of the direct-fire
units, consistent with the burst-death pattern above. **Still a handoff, not
a fix** -- confirming it needs either a safer reattempt at the C++ logging
(with the attacker's def null-checked before every dereference) or
apexearth watching a game where `corban` lands the kill.

**Positive confirmation, `baseline-extend6-8` t001, 2026-08-04.** This
session's fastest, cleanest apex win (14.55 min, `gameover`) has ZERO
`COMMANDER LOST` entries in apex's own log for the whole game -- all four
commanders survived start to finish. The thesis this section has been
building (commander survival predicts the winner) holds in the positive
direction too, not just as an explanation for losses.

## 0.1 apex currently loses to STOCK BARb outright at this benchmark config

Not previously documented at this precision. 8-game controls at commit
`9a63122`, Comet Catcher 4v4, +25%, Cortex/Cortex, 25 min:

| opponent profile | decided h2h | apex win% (undecided=loss) |
|---|---|---|
| `BARb:stable:hard` | 0-6 (2 timelimit) | 0% |
| `BARb:stable:hard_aggressive` | 0-5 (3 timelimit) | 0% |

This contradicts the K/D 0.97-at-25min figure logged earlier in issue 1 below --
that number came from a different opponent/config combination that was not
re-verified here. `hard` and `hard_aggressive` are both real stock BARb
profiles (confirmed: `reference/barb-stable/game-side/config/{hard,hard_aggressive}`
both exist), not a config-fallback artifact.

**Next step, per the project's own doctrine**: stop reading telemetry blind and
get a `--watch` run in front of apexearth. Every diagnosis that has actually
landed on this AI came from him watching, not from aggregate stats.

**Resolved, partially** -- see `12f13f0` (commander back-wall hiding disabled).
A `--watch` run plus the infolog it produced found the mechanism: the
commander was spending its early build time on a false "under attack" signal
that reads true almost permanently on this map (see CHANGES.md, "Known not
done" -> commander retreat). After the fix: 8-game control vs
`hard_aggressive`, same config, went from 0-5 decided to 1-1, paired K/D
log-ratio t from -13..-17 to -0.87 (not significant). **Still not "reliable"**
-- the goal is not met, this is progress on issue 0.1's shutout, not a win.
Next candidate to chase: apex still produces ~40k metal to stable's ~64k
in the same 8-game run, so the economy gap (not just the commander's early
diversion) is still open.

**Tried and reverted (disabled, not deleted): heavy-AA escalation, `d3bb0e2`.**
apexearth watched a game and reported light AA (corrl, 80m, deterrence-only,
capped at 12) doing nothing against ~10 T2 gunships. Added a second tier
(cormadsam/armferret/legflak) gated on real enemy air investment and income.
Measured WORSE against the back-wall-fix baseline: head to head 1-1 -> 0-5,
apex metal 40,743 -> 27,382, static defence share 10.6% -> 11.5%, wiped-out
9/32 -> 13/32 -- a smaller version of the flak-tower mistake already on
record in this file. One trial-run game won outright on economy and K/D
(265,925 metal, K/D 1.13), so this is not obviously dead; a narrower version
(higher income floor, lower cap, or gated on SUSTAINED rather than one-shot
enemy air) may be worth a later isolated retry. `AA_HEAVY_ON = false`.

**Next candidate, found from the `nobackwall-confirm` infologs (not a watch --
apexearth went to bed, so this is stats-plus-mechanism per** [[mechanism-over-aggregates]]
**style, cross-checking a log line rather than trusting an aggregate alone):**
one player's `conbranch` instrumentation (a 30s heartbeat tied to that unit's
constructor decisions) stops dead at 13-19 minutes in most of the 8 games,
while the other three players' logs run to the full 25-minute cap. The
stopped player's own log shows why in `t000`: "commander retreating at 61%,
70%, 75%, 81% health" between 12.2 and 13.2 minutes, then nothing further from
that instance. In the two games where NO player's log stops early, both went
the full 25 minutes as competitive, undecided matches; in every game where one
(sometimes two) did stop early, apex lost decisively. This lines up with the
standing project finding [[commanders-decide-bar-games]]: commander survival
predicts the winner, and three prior attempts at commander retreat logic
(`commander.json` levers, `GetEnemyCostAt`, `GetBuilderThreatAt`) all failed to
fix it (see CHANGES.md "Known not done"). `COM_RETREAT_HEALTH` (0.85, health-
based) is the one thing in this file that reliably fires, and it still isn't
enough to keep a commander alive under sustained pressure once retreat itself
does not equal safety (no ally cover, no safe retreat lane, or simply
outranged while fleeing). Worth a dedicated session: instrument WHY a
retreating commander still dies (position at death vs. nearest ally, whether
allied fire support existed) rather than tuning the health bar again blind --
tuning that bar with a NUMBER has been tried and burned time before.

**Update, does NOT clearly replicate** -- added `comm threat=... hp=...`
logging (`56a4c66`) and re-ran 8 fresh games (`comm-death-investigate`) to test
the theory above with real HP data instead of inferring death from silence.
Result: in this batch's 3 decisive losses, ALL FOUR players' last log line
clusters tightly around the match's own end time (within ~1 minute of the
reported game length) and most read 77-100% HP at that last line -- not the
staggered "one player's log goes quiet 7-10 minutes before the others, at
declining health" pattern the `nobackwall-confirm` game showed. That pattern
looks more like a synchronized team-wide loss once already behind (consistent
with issue 0.1's economy gap) than an individual early commander death
triggering a cascade. **The log-silence method itself is the problem**: this
script has no `AiUnitDestroyed` hook (engine warns it is missing at every
match start; confirmed no working example anywhere in `reference/barb-stable/`
or `vendor/` either, so implementing one blind is a real crash risk given this
file's own history of unsafe-binding aborts -- see CHANGES.md). Absence of a
log line proves the unit stopped needing `AiMakeTask` calls, which is also
true of a commander settled into a long build with nothing to reevaluate.
**Do not treat this as a confirmed lead** -- it needs an actual death event to
investigate further, not more inference from a 30s heartbeat.

**Tried and reverted (discarded, never committed): eco-for-everyone, isolated
retry.** T2GATE data from `comm-death-investigate` showed followers crossing
`FOLLOWER_TECH_ENERGY` (600) only around minute 13 of 25 -- late, matching the
low cons-T2/mex-upgrade counts. Un-gated `EcoConverters`/`EcoNano`/`EcoFusion`
from `Factory::EcoLeadActive()` (every player builds some energy
infrastructure, eco lead at double cadence via `EcoPeriod()`) as an ISOLATED
retry of one piece of the `a7f3399` bundle, on top of the confirmed-good
back-wall fix. 4-game triage against the current baseline: energy wasted
24,829 vs baseline ~10,142 (2.4x), cons T2 1 vs ~3, mex upgrades 2 vs ~4, metal
produced 30,821 vs ~40,743 -- moved the WRONG way on every metric, not just
noisy. Matches a failure mode already on record in this file:
`FollowerEconomyReady`'s own comment cites an 8v8 where every follower teching
on a clock (not a mechanism this change resembles, but the same "spread
economy investment across more players" shape) cut army share to 19.3% against
stock's 31.7%. The bottleneck is real (followers ARE gated on energy pace) but
"more players build energy" is the wrong lever -- reverted without an 8-game
confirmation, since the 4-game signal was directionally consistent and
mechanistic, not just a coin-flip win/loss. Next angle, if pursued: raise the
energy the LEAD alone produces/converts (already fast at `EcoPeriod` full
speed) rather than recruiting followers into the same job.

## 1. The late game collapses, and it is a SEPARATE failure

Measured, 8-game pairs on Comet Catcher 4v4 +25%:

| | 10 min | 25 min | 40 min |
|---|---|---|---|
| apex K/D | 0.76 | 0.97 | **0.56** |
| stable K/D | 0.76 | 0.64 | 1.15 |

The opening is fine. `ENGAGE_MARGIN 1.80` genuinely fixes mid-game. Something
else breaks between 25 and 40 minutes and it is not a weaker version of the
same problem — the sign flips.

ARMY-only K/D at 40 min is **0.66 against stable's 1.40**, while kills by static
defence are within 5% of each other. The army is the whole gap.

**Not yet investigated**: what changes at ~25 min. Candidates: T3 arriving,
squads outgrowing the merge radius, enemy siege artillery, our own T2 mix.
Use `tools/kd_curve.py` on a 40-minute tournament and find the minute it turns.

## 2. Reclaim cannot see the bodies

apexearth: "theres 1000+ metal in front of us and we don't even care".

The rule exists (interrupt a build for a 400+ metal field within 1400 elmos,
`WRECK_RICH` in `builder.as`) and never fires. 97 probe samples over 16 min:
`ai.GetWreckValueAt` read 0 at BOTH 1400 and 4000 radius, and the established
`ai.GetBestWreckPos` also found nothing at 4000 with a 55-metal floor.

Two independent bindings agree. So either `callback->GetFeaturesIn` needs LOS,
or our constructors are never within 4000 elmos of a corpse.

**Next step**: run on a reclaim-heavy map (All That Glitters). Nonzero there =
the binding works and the Comet Catcher zeros mean constructors are simply far
from the fighting. Still zero = the callback is LOS-gated or broken.
**Do not tune the threshold before answering this.**

## 3. Factory tier weights are nearly inert

`FactoryManager.cpp`: `prob = RoleProbability(bd) * (probs[i] + reWeight)` with
`reWeight = 30` (stock). So a weight of 0.40 vs 0.22 is 30.40 vs 30.22 — a 0.6%
difference. **The doctrine reweight moved the numbers and not the behaviour.**

What DOES work: zero-to-nonzero, because `if (probs[i] > 0.f)` is a hard gate.
That is why enabling mobile AA mattered.

**The real lever is `response.json` role ratios.** Untouched. Note our `assault`
entry has `ratio: 5.0` against enemy `static` — likely why Tigers dominate,
since stock builds many towers.

## 4. Units we barely build that we probably should

- **`cortrem`** (Tremor, 1850m, range **1470**) — the ONLY thing we own that
  outranges enemy siege (`cortrem` 1470, `corvroc` 1310). Weight raised to
  0.04/0.08 but see issue 3: probably inert.
- **`corban`** (Banisher, 800 range) is role `skirmish`, so it joins normal
  squads and walks to 80% of its range with them. Probably belongs on the
  artillery path — but that pulls a 1000-metal unit out of assault squads, so
  it is a composition change and needs its own measurement.
- **`corsumo`** (Mammoth) is gated by `coralab`'s `income_tier: [40]` — below
  40 m/s it sits at 0.01 weight. Most of our players are below 40.

## 5. Verified-built but unverified-useful

- **Mobile AA** (`corcrash`, `corsent`, `armyork`, `armaak`, `armjeth`) was
  weight 0.00 = structurally unbuildable. Now enabled. Never confirmed that the
  `anti_air` response actually elects them.
- **`corpun`** (1245 range) enabled via `"on": true` and added as the last rung
  of the porc ladder, gated on 800 metal of enemy artillery. Its `sightdistance`
  is **455**, so it needs someone else's radar to shoot at range. Unverified.
- **Fighter massing** (`AA_MASS_RATIO` in `AntiAirTask`) — holds fighters until
  their cost matches enemy air. Never observed working.
- **Jammers on the line** — confirmed placed (`jamT` reaches 2+). Whether they
  actually stop sieges is unmeasured. We field 24 to stable's 48.

## 6. Reverted on noise, therefore UNTESTED not disproven

`Builder::NeedsAdvCon()` — advanced constructors scaling with income instead of
being capped at exactly one per player. Reverted after army share fell, but a
control run later showed army share swings 5+ points between identical runs.
`NeedsAdvCon()` and `gAdvConCount` are still in `builder.as`, unused. Either
re-test it properly or delete the dead code.

## 7. Faction parity gaps

- **Legion has no ~190-metal mid tower.** Its ladder is `leglht` (70) then
  `legmg` (420) — no equivalent of Beamer/Twin Guard, so the `PORC_MIN_BUDGET`
  floor buys it nothing.
- **Legion has no naval fusion or naval advanced converter** in the pinned tree
  (`leganavalfusion`/`leganavaleconv` are upstream-only). Its naval path runs
  through Cortex hulls: `legcs` -> `corasy` -> `coracsub` -> `coruwfus`.
- Armada/Legion doctrine weights were applied but are subject to issue 3.

## 8. Ideas not built

- **Rally-to-squad** (apexearth): let a unit be ASSIGNED to a distant squad and
  walk to it, instead of the hard 3000-elmo `CanAssignTo` cutoff. This is the
  generalisation of the join-radius fix that took median squad size 2 -> 5.
- **`attackMod` is one value read by SCOUT/RAID/ATTACK/BOMB/ARTY/AA.** Raising
  it for caution tripled losses because it made raids passive too. Splitting it
  would let attacks be cautious while raids stay willing to trade.
- **Counter-battery behaviour.** We have no answer to an artillery blob beyond
  target preference; artillery is the thing that beats a massed army without
  ever being engaged.

## 9. Method notes that keep mattering

- **This benchmark cannot resolve small changes.** Two identical-code control
  pairs moved further than any change did: army share 21.0% vs 15.7% (16 games
  each), T2 spend 36,812 vs 23,515 (32 games each). Head-to-head across seven
  tournaments: 9-6, 5-8, 6-7, 7-7, 13-16, 16-13, 11-19 — every CI includes 50%.
- **Composition metrics with ~1000 in-game samples ARE reliable** (squad size,
  engagement decisions, kill splits). Between-game aggregates are not.
- **Dead bindings are the recurring trap.** Confirmed dead: `GetBuilderThreatAt`
  (0 in 121 samples), `CThreatMap::GetThreatAt` at target positions (0 in 14/15),
  `Game_getTeamResource*` (-1 always), the published front outside BAR.sdd.
  Log a binding's raw value once before building logic on it.

---

## 10. Task displacement — investigated, guard added, NO measured gain

apexearth: "buildings getting started and then canceled... maybe you have some
logic that isn't checking if there's already a task and you are replacing tasks."

The mechanism is real: `AiMakeTask` is called by `IBuilderTask::Reevaluate` on
every task update while a builder is away from its build position, and the engine
swaps the unit's task whenever the returned task differs in BUILD TYPE. Every
optional rule (AA, Pulsar, converters, nanos, fusions, dig-ins) returned early
without checking whether the unit was already mid-build.

A guard now returns the held task when it survives the veto. Measured over 8
games at 25 min against the previous build:

| | no guard | guard |
|---|---|---|
| ARMY K/D | 1.06 | 1.04 |
| metal ratio | 1.16 | 1.09 |
| mex ratio | 1.08 | 1.03 |

**No gain; slightly down, within noise.** Kept because it stops a behaviour that
was directly observed, not because it measures better.

**Caveat that matters**: the "60 live MEX tasks, 60 unworked" measurement which
motivated this was taken WITH a rear-mex rule I had added, which fired every 2
seconds on a GLOBAL timer and enqueued a fresh mex task each time — displacing
whatever the constructor held. That rule probably manufactured the orphan pile.
It has been removed, along with its logging, so whether orphaned mex tasks still
occur is now UNKNOWN. Re-add the `live=/unworked=` counter before concluding
anything about task orphaning.

## 11. `FindOpenMexSpot` excludes ally zones — and that is CORRECT

Checked because it looked like the cause of "no open spot". `IsZoneAlly` is
`(allyCount > 0) && (ownCount == 0)` — a TEAMMATE's zone and not our own. It
prevents stealing a teammate's spots and does not exclude our own base. Not a
bug. Do not "fix" it.

The remaining candidate for `mex-none` is `IsAllyOpenMexSpot` — the spot is
already claimed by a live task. See issue 10.

## 12. Static defence stops scaling early — already tuned, not a fresh lever

Live infologs show `UpdateBaseDefence` (military.as) placing exactly 2
`corhllt` towers per player around minute 4-6 and then never firing again for
the rest of a 20-25 minute game, regardless of how the enemy's army grows.
Looked like a live bug -- `PORC_ADD_CAP = 2` is a hard, permanent cap on
front-line tower placement for the WHOLE game.

**Already measured, not fresh**: the comment at `military.as` (the
`DefaultMakeDefence` gate above it) records that halving this exact constant
(`PORC_ADD_CAP 4 -> 2`) moved aggregate static-defence spend 16.4% -> 16.8%,
i.e. not at all, because the dominant spender is
`aiMilitaryMgr.DefaultMakeDefence(cluster, pos)` -- the C++ engine's own
per-cluster defence call, gated separately (`gPorcArmed`, `gTurtle`,
`LosingGround()`, `early`) -- not this AngelScript addition. Raising
`PORC_ADD_CAP` back up is very unlikely to change the aggregate outcome for
the same reason it didn't the first time it was tried. The `porcupine.prevent`
JSON knob (build_chain.json) was also already tried raised (to 5) and
reverted for walling quiet rear mexes wastefully -- its own comment names the
correct fix ("cannot express the front") as still unbuilt: a per-cluster
prevent count that is higher at the front and lower at the rear, which
requires knowing which cluster IS the front. The `"at-border"` text in the
`porc+` log line is NOT a computed flag -- it is a hardcoded label, always
printed regardless of the cluster's real position. Building the real
distinction is a genuine, well-scoped project (the front-position helpers
`BorderPos`/`FrontPos` already exist and are used elsewhere in this file),
just not a quick JSON tune.

## 13. Heavy AA threshold (`AA_HEAVY_PER`) -- tried lower, CONFIRMED WORSE, reverted for good

Found the REAL heavy-AA system: `Military::UpdateAirThreat()` already
properly discounts scout/constructor contamination (`softAir`) and smooths
over 240s (`gAirAvg`) -- a much better-designed mechanism than the crude
duplicate attempted earlier this session (`AA_HEAVY_ON` in builder.as,
already reverted). Confirmed via `apexaa:` logs that this existing system
sat at `heavy=0/0` for an ENTIRE 24-minute sample game even once the
corrected air metric reached a meaningful level -- `AA_HEAVY_PER=1500` was
simply too high a bar to ever cross in a normal game.

Lowered to 900 and tested: 4-game triage (1-2 decided, apex won one, low
12.5% wipe-out both sides) looked promising; 8-game confirm came back 0-3
decided (5/8 to time limit) with wipe-out back up to 31.25% and static
defence share creeping to 11.1% while army share stayed low at 15.3% -- the
same crowding-out shape as the original heavy-AA failure, just milder.
Combined across both batches: 1-5 decided (16.7%), not clearly better than
the aggregate 20.8% baseline (issue 0.1). Reverted as INCONCLUSIVE, not
confirmed-bad -- the mechanism now genuinely fires (confirmed via `heavy=`
readings changing from always-0 to 1-6), which the crude duplicate attempt
never achieved, so this is a more promising direction than that one was.
Worth a larger (16+ game) retry before ruling it out, given how close the
triage result looked; not worth it immediately given the session's already
extensive investment and the mixed 8-game signal.

**Update: re-tested at n=16, `heavyaaper-large16` -- 1-7 decided, a real
difference at this sample size (95% CI 53-98% for stable, excludes 50%).**
Combined across all three batches at this value (n=4+8+16=28 games, 14
decided): apex 2, stable 12 -- 14.3%, worse than the 20.8% aggregate
baseline. **Settled, not just reverted**: `AA_HEAVY_PER=900` is confirmed
worse, not merely inconclusive. The mechanistic reasoning (existing,
correctly-designed system, previously never firing) was sound, but firing
more readily still cost more than it gained -- likely the same crowding-out
effect visible in the mixed batch's static-defence/army-share numbers,
just confirmed at scale. `AA_HEAVY_PER` stays at 1500. If this system is
revisited, the next lever to try is probably NOT more heavy AA sooner, but
whether the crowding-out itself (static defence competing with army for the
same constructor time) can be addressed directly -- which is the same
open question issue 12 already raises for the front-line tower cap.

**Third and final attempt on this specific lever: the SAME `AA_HEAVY_PER=900`,
this time gated on `Factory::gLastPhase >= 4` (T2 established) using the new
BUILD_PHASE diagnostic -- a direct test of whether phase-awareness itself was
the missing piece.** 4-game triage: 0-3 decided, one unusually fast collapse
(13.97 min). Not encouraging, and given two prior confirmed-negative results
for closely related versions of this same mechanism, this is the third data
point pointing the same direction -- reverted without spending an 8-game
batch on a fourth variation of the same idea. **This specific lever
(heavy AA, in any of its three tested forms) is now closed for this
session.** It does not mean BUILD_PHASE itself is disproven -- gating ONE
already-marginal rule behind phase is a much weaker test of the thesis than
the doc's own design, which expects the payoff to come from resolving
competition across MANY rules at once, not validating or invalidating the
approach through a single gated rule. Treat this as "heavy AA specifically
is not the rule to prove the concept with," not as evidence against
BUILD_PHASE as a whole.

## 14. Team-0 vs team-1 win rate asymmetry -- suggestive, NOT statistically confirmed

Pooled every decided game across this session's baseline batches
(nobackwall-confirm, comm-death-investigate, noise-recheck, large-confirm16,
commlost-investigate, baseline-extend-8 through -7): apex won 2/30 (6.7%) as
team 0 against 5/25 (20.0%) as team 1 -- a 3x difference in raw win rate.

**z = 1.48 (p ~ 0.14) -- not significant at conventional 95% confidence.**
Flagging, not concluding: the effect size is large enough to be worth a
larger, purpose-built sample (pool team-0-only and team-1-only tournaments
separately, at n=30+ decided each, rather than reading it off pooled data
collected for other purposes) before trusting it.

No obvious mechanism found on a first look: the AI's positional logic
(`CON_FAR_FRAC`, `BorderPos`, `gHomePos - aiEnemyMgr.GetEnemyPos()`) is built
from relative vectors, not absolute map coordinates, so there is no a priori
reason team identity should matter to OUR code. If real, the more likely
explanation is a genuine map-side asymmetry on Comet Catcher itself (terrain,
mex layout, start-position distance) that both AIs experience but only one
learns to exploit -- which `tools/run_tournament.py`'s own side-swap design is
meant to average out across a matched pair, but would NOT cancel if it
affects team 0 and team 1 differently regardless of which AI occupies them.
Worth checking: does STABLE also show a team-0/1 split in the same data (its
own win rate by side, not just apex's)? That would distinguish "map asymmetry
affecting both AIs" from "something apex-specific about occupying team 0."

**Checked: yes, stable shows the SAME direction.** As team 0, stable wins
20/25 (80.0%); as team 1, stable wins 28/30 (93.3%) -- team 1 is the stronger
side for BOTH AIs, whichever one occupies it (the two counts are
complementary by construction, so the z-statistic is numerically identical,
1.48, but the DIRECTION matching across two independent AIs is real
evidence). **This points to a genuine Comet Catcher team-1 positional
advantage** (start position, terrain, mex layout, or the `boxes: lr` box
assignment itself) rather than anything apex-specific -- not something to
"fix" in the AI at all if confirmed, though it does mean an apex-only
tournament with an unlucky side distribution (more team-0 assignments than
team-1) would read as artificially worse than the AI's true skill gap,
which may be part of why this session's per-batch win rate bounced around
before the aggregate settled. Still not statistically confirmed at n=55 --
a dedicated stock-vs-stock (mirror-match) tournament, side-locked, would
settle it cleanly without any AI-skill confound at all.

**Attempted the side-locked test, invalidated by a methodology error.**
Launched 8 `run_match.py` instances directly with unrestricted background
parallelism (`&` with no worker cap), instead of going through
`run_tournament.py`'s `--workers`-limited queue. Result: one match (`g4`)
never produced a `result.json` at all (resource exhaustion, likely RAM --
each headless instance needs ~4.4 GB), and 5 of the remaining 7 showed an
IDENTICAL game length (21.55 min) across different seeds, which
`FixedRNGSeed does not make runs reproducible` (this project's own verified
finding) says should not happen -- a strong sign of contention corrupting
the runs' independence, not real seed-driven variation. Discarded the whole
batch rather than draw any conclusion from it. If this test is retried, use
`run_tournament.py`'s worker-limited pool (or run individual `run_match.py`
calls sequentially, not backgrounded together) -- this needed no new
tooling, just the discipline this project already documents.

**Retried properly (sequential, no contention), n=4: all 4 went the full
time limit, 0 decided.** Too small a sample to compare win rates against,
but a 4/4 (100%) undecided rate is notably higher than this session's
typical undecided fraction (roughly 30-50% across the baseline batches),
mildly consistent with team 1 being the stronger side -- games are more
often held to a draw rather than lost outright. Sequential execution is
slow (4 games took comparable wall-clock to an 8-game parallel batch), so
this was not pushed further this session. A proper confirmation needs
`run_tournament.py`-scale parallelism with one side forced, which the tool
does not currently support (it always auto-swaps) -- worth a small
`--force-side` flag if this is worth settling properly.

**UPDATE, 2026-08-04: re-checked at n=259 decided games (all 55 tournaments
dated 2026-08-04, every code state pooled together) -- REFUTED at this
scale, closing this issue.** Pooling every decided Comet Catcher game from
the whole day's tournaments (not just the earlier baseline batches this
issue was originally built from) gives team-0 119 wins / team-1 140 wins
out of 259 -- 45.9% vs 54.1%, an 8.1-point gap in the same direction as
before, but **z = -1.30, two-sided p ~ 0.19**, weaker than the original
n=55 sample's z=1.48 despite ~5x the data. A true effect this size should
have gotten MORE significant with more data, not less; the original
"~3x split" (6.7% vs 20.0%) does not replicate at scale and reads in
hindsight as a small-sample fluctuation that regressed toward 50/50.
Pooling across every code state is deliberate here, not sloppy: the
hypothesis under test is a property of the map/team-slot, not of any
particular AI build, and the original write-up above already confirmed
the same direction held for both apex and stable independently. **Verdict:
no actionable Comet Catcher team-0/1 asymmetry detectable at n=259.**
This does not rule out a true small effect (e.g. 52/48) hiding under the
noise, but there is nothing here to build a `--force-side` flag or any
other fix around. Read-only analysis, no files or code changed for this
check.

## 15. Multi-rule BUILD_PHASE gate -- phase>=2 failed, phase>=3 CONFIRMED a real win

The genuine test the earlier single-rule heavy-AA gate could not be:
gated the WHOLE optional economy/AA cluster (`CheapAA`, `HeavyAA`, `Pulsar`,
`EcoConverters`, `EnergyConverter`, `EcoNano`, `EcoFusion`) behind
`Factory::gLastPhase >= 2` (build up, reached once mex >= 4) in `builder.as`'s
`AiMakeTask`, using the new `ComputePhase()` diagnostic. This is the SAME
block `docs/12-build-phases.md`'s own comment already names as the historical
danger ("Twelve rules pre-empting here... cut metal production 4.3x").
Reflexive `RepairNear` (con-heal) stayed ungated, per the doc's own
phase-gated-vs-reflexive split. Caught and fixed a real bug while
implementing it: an early draft inverted the `RepairNear` condition polarity
(would have swapped which branch handled repair vs economy) -- fixed before
any test ran, via careful re-reading against the original code rather than
trusting the refactor.

**Result across three batches (smoke n=4, confirm n=8, large16 n=16 -- total
28 games, 13 decided): 0 apex wins.** `P(0 wins | true rate is the 7.9%
baseline) = 0.34` -- NOT statistically distinguishable from the unchanged
baseline at this sample size, so this is not confirmed worse. But it is also
clearly not a win, and economy metrics did not show the improvement the
design doc's own measurement plan predicts (mex upgrades did not recover
toward stock's 8-11; metal produced and army share were unremarkable, in the
same range as the baseline). Reverted rather than push a 4th batch, matching
this session's established discipline (revert after multiple non-positive
samples).

**What this does and does not mean for BUILD_PHASE:**
- It does NOT disprove the design. The gate threshold (`phase >= 2`, i.e.
  mex >= 4) may simply be wrong -- too late to matter (constructors are
  already past the critical early-expansion window by the time mex hits 4)
  or too early (the economy still can't spare the constructor even at mex 4).
  The doc's own "hardest part" section already flags transition conditions,
  not the phase concept, as the hard part.
- It DOES mean this specific implementation, with this specific threshold,
  is not the quick win it might have looked like from the mechanism alone.
  getting it right needs calibrated transition conditions read off real
  telemetry (per the doc's own instruction), not a single guessed threshold
  tested once.
- The `ComputePhase()`/`gLastPhase` diagnostic infrastructure itself is
  unaffected and stays in place (it is pure logging, committed separately) --
  only the NEW gating added on top of it in this attempt was reverted.

**UPDATE, CONFIRMED WIN: retried at `phase >= 3` (`RushReady()`, the economy
has proven it can afford to tech) instead of `phase >= 2` (`mex >= 4`).**
Same gated cluster, same reflexive/investment split, one number changed.
Three batches (triage n=8, large16 n=16, confirm2 n=16 -- 40 games played,
12 decided):

| batch | apex won | stable won |
|---|---|---|
| `phasegate3-triage` | 0 | 1 (7/8 went the full time limit) |
| `phasegate3-large16` | 2 | 5 |
| `phasegate3-confirm2-16` | 2 | 2 (12/16 went the full time limit) |
| **total** | **4** | **8** |

**Apex win rate: 33.3% (95% CI 13.8%-60.9%), against the established 7.9%
baseline (issue 0.1). `P(>=4 wins in 12 | baseline true rate 7.9%) =
0.0115`** -- below the conventional 5% significance threshold, a real,
statistically confirmed improvement, not noise. Games also ran to the full
25-minute time limit far more often (~70% across these batches vs the
baseline's typical 30-50%), a second independent signal in the same
direction: apex is surviving to compete, not just occasionally winning.

**Committed.** This validates BUILD_PHASE's core claim directly: the fix
was never any ONE of the five previously-failed spend-more experiments,
it was deferring the whole competing CLUSTER together until the economy
proves it can afford the spend. `phase >= 2` (mex >= 4) tried the same
mechanism one threshold too early and measured nothing; `phase >= 3`
(RushReady) is where it actually pays off. See CHANGES.md for the summary
kept alongside the other confirmed fixes.

**Still open**: whether an even different threshold does better still,
whether `ConDugIn`/`Fortify` belong in the gated cluster too, and whether
this holds on other maps/handicaps/factions -- this session tested Comet
Catcher 4v4 +25% Cortex only, per the goal's own scope.

**UPDATE, extended with a 4th batch (`phasegate3-extend-16`, n=16): 1-9
decided** -- notably weaker than the first two batches, pulling the
running aggregate down. **Combined across all 4 batches (56 games played,
22 decided): apex 5, stable 17 -- 22.7% (95% CI 10.1%-43.4%).**
`P(>=5 wins in 22 | baseline true rate 7.9%) = 0.0260` -- still below
conventional significance, so this remains a real, durable improvement
over the 7.9% baseline, just more modest than the initial 33.3% read
suggested. This is exactly the lesson this session already learned about
trusting small samples (see the noise-floor recheck in issue 0.1) applied
to a positive result instead of a negative one: the first two batches were
on the better end of the true distribution, not the whole story. 22.7%,
not 33.3%, is the number to cite going forward -- still a genuine,
statistically real ~3x improvement over baseline, not yet "reliable."

**UPDATE, BEST RESULT: `phase >= 4` (`gHaveT2`, an advanced factory
actually FINISHED) instead of `phase >= 3` (`RushReady()`, merely able to
afford one).** Two batches (`phasegate4-test-16`: 5-3 decided, 8/16 to time
limit; `phasegate4-confirm-16`: 1-1 decided, 14/16 -- 87.5% -- to time
limit):

| batch | apex won | stable won | to time limit |
|---|---|---|---|
| `phasegate4-test-16` | 5 | 3 | 8/16 |
| `phasegate4-confirm-16` | 1 | 1 | 14/16 |
| **total (n=32 played, 10 decided)** | **6** | **4** | **22/32 (69%)** |

**Apex win rate: 60.0% (95% CI 31.3%-83.2%). `P(>=6 wins in 10 | baseline
true rate 7.9%) = 0.00004`** -- extraordinarily significant, and P against
even the already-confirmed phase>=3 rate (22.7%) is also low. Composition
data from the first batch: apex wipe-out rate (13/64, 20.3%) actually LOWER
than stable's (19/64, 29.7%) for the first time all session; metal produced
(45,917) within 8% of stable's (49,676), the closest economic parity
measured all session.

**Why phase>=4 beats phase>=3**: "the economy could afford to tech"
(RushReady, phase 3) is not the same test as "it actually has" (gHaveT2,
phase 4). Under phase>=3, CheapAA/HeavyAA/Pulsar/the eco block were still
competing with the SAME mex-upgrade and factory-building work that gets a
player to T2 in the first place -- the gate opened before the thing it was
meant to protect had finished. Gating until the advanced factory is
actually standing removes that competition at the point that matters.

**Shipped as the new gate value** (`Factory::gLastPhase >= 4`). Still
technically not proven "reliable" at n=10 (95% CI's lower bound 31.3%, not
a guarantee) -- worth a larger confirmation batch before calling 60% settled,
but this is by a wide margin the strongest result this entire session
produced, on both the win-rate axis and the survivability/economy axes
independently.

**Methodology correction from apexearth, watching a game live**: "I don't
think in these games, like, at the twenty minute mark or the thirty minute
mark, if one side has a third of the resources as the other or half the
resources as the other, it's not going to turn around. The game has
already decided." This means treating "games reaching the time limit" as
evidence of competitiveness on its own is wrong -- a lopsided game that
never triggers a formal `gameover` still reads as "undecided" in this
harness's output. Checked directly against `analyze_stats.py`'s metal
totals for `phasegate4-test-16`'s 8 undecided games: two (rows 7, 8) were
genuinely lopsided (1.8x-2.4x metal) and should count as effectively
decided; one (row 12) was actually apex ahead 1.7x; the other five were
within ~1.2-1.4x, genuinely close. Reclassifying by this rule doesn't
meaningfully change that batch's picture, but the CHECK matters more than
this one clean result -- read the resource ratio directly for future
batches rather than trusting the decided/undecided split as a
competitiveness signal.

**UPDATE, third batch (`phasegate4-extend2-16`, n=16): 4-5 decided
(44.4%), 7/16 to time limit.** Combined across all three phase>=4 batches
(48 games played, 19 decided):

| batch | apex won | stable won |
|---|---|---|
| `phasegate4-test-16` | 5 | 3 |
| `phasegate4-confirm-16` | 1 | 1 |
| `phasegate4-extend2-16` | 4 | 5 |
| **total** | **10** | **9** |

**Apex win rate: 52.6% (95% CI 31.7%-72.7%). `P(>=10 wins in 19 |
baseline true rate 7.9%) < 0.000001`.** The confidence interval now
straddles 50% -- apex is genuinely, statistically indistinguishable from
an even matchup against `BARb:stable:hard_aggressive` at this benchmark
config, a complete reversal from the 7.9% (CI 3.9%-15.4%) baseline this
session started measuring. This is the largest, most trustworthy read of
the `phase >= 4` gate's true strength -- cite 52.6%, not the earlier
single-batch reads of 60% or 33.3%, going forward.

**This is real, substantial progress toward the goal, though "beats
reliably" would still need the CI's lower bound to clearly exceed 50%,
not merely straddle it.** Worth continuing to extend this sample.

**UPDATE, fourth batch (`phasegate4-extend3-16`, n=16): 2-2 decided
(50.0%), 12/16 to time limit.** Combined across all four phase>=4 batches
(64 games played, 23 decided):

| batch | apex won | stable won |
|---|---|---|
| `phasegate4-test-16` | 5 | 3 |
| `phasegate4-confirm-16` | 1 | 1 |
| `phasegate4-extend2-16` | 4 | 5 |
| `phasegate4-extend3-16` | 2 | 2 |
| **total** | **12** | **11** |

**Apex win rate: 52.2% (95% CI 32.6%-71.3%). `P(>=12 wins in 23 |
baseline true rate 7.9%) < 0.000001`.** This batch landed almost exactly
on the running average (50.0% vs. 52.6%) rather than pulling it further
toward or away from 50% -- the estimate is stabilizing, not still
swinging batch to batch the way the noise-floor section (issue 0.1)
warned it could. Read as confirmation, not a new finding: `phase >= 4` is
a real, large, statistically solid improvement over the 7.9% baseline
(p < 1e-6 either way it's cut), and it is genuinely a coin flip against
`BARb:stable:hard_aggressive` at this benchmark config -- not yet
"reliably beats." The CI has now narrowed (was 31.7%-72.7% at n=19, now
32.6%-71.3% at n=23) without moving off center. Getting the lower bound
past 50% from here needs either a much larger sample or an actual further
improvement, not just more of the same games.

**UPDATE, fifth batch (`phasegate4-extend4-16`, n=16): 0-4 decided (0%),
12/16 to time limit.** The first batch since this gate shipped to land
clearly on the bad side rather than near the running average. Combined
across all five phase>=4 batches (80 games played, 27 decided):

| batch | apex won | stable won |
|---|---|---|
| `phasegate4-test-16` | 5 | 3 |
| `phasegate4-confirm-16` | 1 | 1 |
| `phasegate4-extend2-16` | 4 | 5 |
| `phasegate4-extend3-16` | 2 | 2 |
| `phasegate4-extend4-16` | 0 | 4 |
| **total** | **12** | **15** |

**Apex win rate: 44.4% (95% CI ~27.6%-62.7%). `P(>=12 wins in 27 |
baseline true rate 7.9%) < 0.000001`.** Still an enormous, statistically
solid improvement over the 7.9% baseline -- that conclusion does not
change. But the point estimate has now crossed below 50% for the first
time, and the last three extension batches (44.4%, 50.0%, 0%) show real
batch-to-batch spread rather than the settling this note previously
called out after extend3. Read this as the honest current state, not as
a reason to chase a sixth extend batch immediately: **`phase >= 4` is not
confirmed to reliably beat `BARb:stable:hard_aggressive` at this
benchmark config** -- the CI still comfortably straddles 50%, and if
anything the recent trend leans at or under it. The mechanism (deferring
the optional economy/AA cluster until T2 actually finishes) remains the
right fix for the crowding-out failure mode this session diagnosed and
should stay shipped, but "beats reliably" needs either a real further
improvement or a much larger sample before it can be called met.

**UPDATE, first batch AFTER `6efc955`'s four live-diagnosed bug fixes
(landlock stall, reactive air, late-fighter hold, rez-bot flee-on-hit):
`postfix-16` (n=16): 2-6 decided (25.0%), 8/16 to time limit.** Tracked
separately from the table above -- this is a different code state, not a
sixth sample of the same one. Do NOT merge into the 44.4%/n=27 figure.

This one batch does not say the fixes hurt: three of the four (landlock,
reactive air, late-fighter hold) are mostly 8v8-relevant and barely apply
on a 4v4 map, the rez-bot fix is a pure bug fix (a bot that used to die
uselessly now flees -- structurally can't make things worse), and this
session's own noise-floor finding (issue 0.1) is that single 8-16 game
batches on UNCHANGED code have swung 0%-75%+ before. One bad batch right
after a change is exactly the situation that finding warns against
over-reading. Needs a second `postfix` batch before concluding anything
about this code state specifically; until then the honest read is
unchanged from the note above -- `phase >= 4` (now plus these four fixes)
is a large, real win over the original 7.9% baseline and not yet
confirmed to reliably beat `BARb:stable:hard_aggressive` at this
benchmark config.

**UPDATE, `872473c` gates `earlyReaction`/`stalled` to `!IsSmallTeam()`,
confirmation batch `gated-16` (n=16): 2-2 decided (50.0%), 12/16 to time
limit.** Back in line with the pre-fix 44.4%/n=27 aggregate and clear of
the two ungated-postfix batches' 31.2%/n=16. Consistent with the
mechanism (two new unconditional, un-phase-gated spend triggers were
costing the 4v4 benchmark) but n=4 decided alone is far too small to call
this confirmed on its own -- treat as supporting evidence, not proof, and
fold future Comet Catcher 4v4 batches on this code state into a fresh
running aggregate starting from `872473c` rather than either of the two
prior tables (pre-fix `phase>=4`-only, or ungated-postfix).

**UPDATE, second gated batch (`gated2-16`, n=16): 1-6 decided (14.3%),
9/16 to time limit.** Retracts the "back in line" read above -- that was
n=4 decided, far too small to have meant anything on its own, and this
batch pulls it back down hard. Combined `gated-16` + `gated2-16` on the
`872473c` code state: **3 apex, 8 stable, 11 decided = 27.3% (95% CI
~9.7%-56.6%)**. The CI is enormous at this n and still straddles 50%, so
this does NOT confirm the gating fix failed either -- but two batches in
a row below the pre-fix 44.4% aggregate, after one batch that looked like
a clean recovery, is exactly the noise-floor pattern issue 0.1 already
documented (0%-75%+ swings on code that never changed at all). Read the
`872473c` code state as genuinely unresolved, not as "recovered" or
"regressed" -- there isn't yet enough signal in either direction.

**UPDATE, `gated-big-32` (n=32, real statistical power instead of another
small batch): 2-8 decided (20.0%).** Combined across all three
`872473c`-state batches (`gated-16` + `gated2-16` + `gated-big-32`, 64
games played, 21 decided): **5 apex, 16 stable = 23.8% (95% CI
~10.6%-45.1%)**. This CI does NOT include 50% -- the first time in this
whole session a CI on a shipped code state has cleanly excluded parity on
the wrong side. Not noise; a real regression from the pre-fix
44.4%/n=27 aggregate.

**Root-caused and fixed, `9a1b249`**: `HoldsLateFighter()` was scoped
wider than its own justification. `LateGame()` goes true off EITHER the
25-minute clock OR any fusion existing, and the AA-role match covers
EVERY unit of that role, not just the freshly-recruited screen floor --
so once any player had a fusion (plausible before the 25-min cap, given
the phase-gated economy now techs faster), every AA-role aircraft on the
team got benched to idle, including ones already usefully mid-fight.
Gated to `!IsSmallTeam()`, matching how `earlyReaction`/`stalled` were
already restricted for the identical reason.

**Confirmation, `isolate-latefighter-16` (n=16, testing `9a1b249` alone,
without also touching the rez-bot fix): 5-4 decided (55.6%, 95% CI
27-81%).** First batch on any shipped code state to land above 50% since
before the `872473c` regression. One batch is not proof -- the CI still
straddles 50% and this project's noise floor is real -- but it's
consistent with the diagnosis and is the strongest single post-fix
result so far. A second confirmation batch is queued before trusting it.

**Where this leaves the overall goal**: from the 7.9% baseline this
session started at, through `phase >= 4`, four live-diagnosed bug fixes,
and now a fix to one of those fixes' own scope, the current best estimate
is a genuine, large improvement over baseline that has NOT yet settled
into a confirmed "reliably beats" state -- but `isolate-latefighter-16`
is the first result actually pointing that direction rather than just
toward "large but uncertain." Worth one more confirmation batch before
either declaring this resolved or going back to look for what else in
the 872473c/9a1b249 line might still be costing the benchmark.

**UPDATE, second confirmation (`isolate-latefighter2-16`, n=16): 2-6
decided (25.0%).** Combined across both `9a1b249` batches: **7 apex, 10
stable = 41.2% (95% CI ~21.6%-64.0%)**, wide and back to straddling 50%.
Read together with the first batch's 55.6%: a 30-point swing between two
back-to-back batches on the IDENTICAL code state is the noise floor this
session already documented (issue 0.1: 0%-75%+ on truly unchanged code),
not a further regression. **Conclusion: `9a1b249` is not further
measurable at this sample size, but the combined 41.2% is squarely back
in the same 40-50% band the pre-`872473c` aggregate (44.4%/n=27)
occupied, clear of the 23.8%/n=21 regression window. The fix did what it
was meant to do -- undo the regression -- without demonstrating a NEW
improvement beyond where this session already stood.**

**Stopping the batch-grinding loop here.** Six 16-32 game batches in a
row on various shipped states have now landed in overlapping, wide CIs
that all include 50% -- the exact "diminishing returns" pattern the
SESSION SYNTHESIS section already named for the original 89-game
baseline. Current honest state of the overall goal: **from a measured
7.9% baseline, this session's changes (phase-gated economy spending,
four live-diagnosed bug fixes, and the fix to one of those fixes' own
scope) land the AI somewhere in a 40-50% decided win rate band against
`BARb:stable:hard_aggressive` on Comet Catcher 4v4 at +25% handicap --
an enormous, statistically overwhelming improvement, and still not
confirmed as "reliably beats."** Per this session's own repeated
finding, closing that gap further needs either a genuinely new
mechanism or apexearth's own live observation to surface the next one,
not more batches of the same kind.

## 16. Players boxed onto an island barely expand, tech, or spend -- fix built, NOT YET MEASURED

apexearth, watching an 8v8 live: a player started on a small strip of land,
chose bots, and stood doing nothing once local mexes ran out, with an ocean
it could not build ships on (no shipyard, bots-only) and mexes on a nearby
hill it could not reach (no air con). Reported symptom set: no T2, minimal
economy building, unused map space, no willingness to try water or a
different factory.

**Root cause found by reading the gates, not by guessing:** T2
(`MayPursueT2`/`RushReady`/`FollowerEconomyReady`) and every eco-spend
cluster gated on `Factory::gLastPhase` (issue 15) key off metal/energy
INCOME, not mex count directly. A boxed player's income plateaus low because
it cannot add mexes -- so it never clears the T2/eco income bars, and every
downstream symptom (no T2, thin eco, nothing new gets built) follows from
that one number staying flat. There is no engine-script binding for "am I
geometrically landlocked" (checked `vendor/engine/.../InitScript.cpp` --
nothing registered), so the fix targets the SYMPTOM (mex count not growing
for a long time past the opening) rather than the geometric cause, in
`factory.as`:

- `ExpansionStalled()` -- true once `gPeakMex >= STALL_MIN_MEX` (2, i.e. a
  normal opening happened) and `STALL_DURATION` (3 min) has passed with no
  new mex.
- `AiGetFactoryToBuild` now treats a stalled player the same as
  `IsMixedWaterMap()`: it will build a T1 shipyard and start contesting the
  water, even on a map whose LAND-AVERAGE reads as fine, because the map
  average was never the boxed player's problem.
- Found and fixed during this same pass, before any run: the naval-rescue
  branch was gated on `aiEconomyMgr.metal.income >= NAVY_MIN_INCOME` (15/s)
  -- the same bar a genuinely boxed player can never clear precisely because
  it cannot expand, which would have made the rescue path unreachable by the
  exact players it exists for. Split into a separate, lower
  `NAVY_MIN_INCOME_STALLED` (6/s): enough to not build the yard into
  bankruptcy, not so high the escape valve requires the outcome it produces.

**What this does NOT fix, left for later:** a player boxed by CLIFFS/HILLS
with no adjacent water at all (`IsWaterAVoid()` true, or water present but
unreachable) has no rescue here -- that needs either a real terrain query
bound to script, or a hover/air-con expansion path, neither built this pass.
`aiTerrainMgr.IsWaterAVoid()` gates the fallback off entirely in that case.

**Unmeasured.** No watch run and no tournament have been done against this
change -- per session instruction, do your best without running the harness.
Before trusting this: watch one game where a player visibly stalls (the
`AiLog` line is `"expansion stalled -- building <yard> to contest the
water"`), confirm it fires, and confirm play actually resumes (mex count,
income, and eventually `gLastPhase` climbing again) rather than just a
shipyard sitting idle. `python tools/composition.py` before trusting a win
rate off this.

---

## 17. H1c: rez-bot fix isolation test -- NOT confirmed, code reverted-then-restored (2026-08-04)

Tested `notes/next-session-hypotheses.md` section 1's H1c: temporarily
disabled the rez-bot flee-on-hit block (`builder.as`, the `IsRezzer(unit))
{ ConDugIn(unit); if (gConHits[...] > 0) { ... EnqueueRetreat ... } }` block
added in `6efc955`), redeployed, ran one 16-game Comet Catcher 4v4 batch
(`tournaments/20260804-143915-h1c-revert-16`), and compared composition
against the pre-fix and post-fix baselines from section 1's table.

| batch | cornecro share | apex wipeout rate |
|---|---|---|
| pre-fix baseline (`phasegate4-extend3-16`) | 8.8% | 7.3% (9/124) |
| post-fix average (3 batches) | ~15% | ~31% |
| **h1c-revert-16 (fix OFF)** | **17.3%** | **37.5% (24/64)** |

Both numbers went the WRONG way for H1c: with the rez-bot flee logic fully
disabled, cornecro's metal share and apex's wipeout rate were *higher* than
the post-fix average, not lower, and further from the pre-fix baseline than
every post-fix batch already measured. This is a single 16-game batch (9
decided games: apex 3, stable 6, 7 hit the 25-min time limit undecided) so
it cannot rule out noise on its own, but it is a clean directional result
in the opposite direction from what H1a/H1b predicted, on top of composition
swings this session already knows can be large batch-to-batch. **H1c is not
confirmed** -- the rez-bot fix is not shown to be driving the cornecro-share
or wipeout-rate growth.

Also notable this batch: apex's own economy was down across the board
relative to stable in the same games (metal produced 32.5k vs 52.8k, T2
spend 10.1k vs 28.2k, T3 spend 0 vs 302) -- consistent with the standing
finding that a collapsing economy buys cheap passive stuff (cornecro,
coradvsol, cornanotc are apex's top 3 sinks here) and dies before any
payoff, i.e. the composition shift may be a symptom of losing rather than
a cause of it, same as flagged as a possibility in section 1's original
writeup.

**Action taken**: the revert was temporary. `builder.as` has been restored
to exactly the pre-test state (`git status` clean, `git diff` empty against
HEAD after restoring) -- the rez-bot flee-on-hit fix is back in, unchanged.
Redeployed and smoke-tested clean (0 compile errors) both with the fix
removed and after restoring it.

**Recommendation for next session**: do not keep chasing H1a/H1b (retuning
the rez-bot trigger) off this result -- the one batch available argues
against the rez-bot fix being the driver, if anything. Move to section 2
(`coradvsol` vs `corfus` gate investigation) per the priority order at the
bottom of `notes/next-session-hypotheses.md`, and/or section 0 (watch a live
Comet Catcher 4v4), which nobody has done all session and every actually-
confirmed mechanism this session traces back to a live watch rather than a
statistics-only diagnosis.

---

## 18. `coradvsol` vs `corfus` — the eco-lead gate hypothesis was WRONG; the real cause is the already-known, already-reverted `economy.json` fusion threshold (2026-08-04)

Tested `notes/next-session-hypotheses.md` section 2. Added one throttled
diagnostic `AiLog` at the top of `EcoFusion()` in `builder.as` (before any of
its own early returns), logging `lead` (`Factory::EcoLeadActive()`), `haveT2`,
metal income, bank vs the `FUSION_MIN_BANK` bar, `EnergyWasting()`, and the
standing count of advsol vs fusion defs. Deployed clean (0 compile errors),
smoke-tested, then ran one 16-game Comet Catcher 4v4 batch
(`tournaments/20260804-150421-solar-fusion-diagnostic-16`) and grepped all 8
apex instances' infologs for the new line: **470 samples, 16 games.**

**Result: `lead=0` in all 470 samples, zero exceptions.** Cross-checked
against the role's own announcement lines
(`"ECO LEAD -- no army, economy only"` / `"eco lead standing down"` / `"eco
lead held off"`) — **zero of any of them appear anywhere in the batch.** The
eco-lead role never activates even once across 16 full 25-minute 4v4 games.

**Root cause, read from the code, not guessed:**

```
const bool ECO_ON_SMALL_TEAMS = false;   // factory.as:688

bool IsEcoLead()
{
	if (IsSmallTeam() && !ECO_ON_SMALL_TEAMS)
		return false;
	...
}
```

`IsSmallTeam()` is `mates.length() < BIG_TEAM` (`BIG_TEAM = 6`). Comet Catcher
4v4 has 4 mates per side, so `IsSmallTeam()` is unconditionally true on this
benchmark, `IsEcoLead()` always returns `false`, `gEcoActive` never becomes
`true`, and every rule gated on `Factory::EcoLeadActive()` — `EcoFusion()`,
`EcoNano()`, and the eco lead's carve-out in `Pulsar()` — is **entirely
unreachable on the map this whole session has been testing on.** This is not
a bug: the comment above `ECO_ON_SMALL_TEAMS` records it as a deliberate,
already-measured decision from 2026-08-02 (re-tested: OFF went 2-1 on
904k/166k metal/army, ON went 0-4 on 517k/81k and died sooner) — a 4-player
team can't afford to field zero army from one of its four players. **Section
2's hypothesis, as written, does not apply to this benchmark: there is no
live eco-lead fusion gate to be too conservative, because the eco lead itself
never exists here.**

**So where does apex's 15-17% `coradvsol` actually come from?** Composition
this batch: apex `coradvsol` 15.2% (#2 sink), `corfus` 8.1% (#6); stable
`corfus` 17.1% (#1 sink), `coradvsol` 3.2%. Since the eco-lead script path is
dead on this map, 100% of that spend — for every ordinary constructor on both
sides — comes from the plain engine-side task selection reading
`config/hard_aggressive/economy.json`'s `"land"` block, walked in list order
(`armsolar → armadvsol → armfus`, score-sorted, per `CEconomyManager::Update
EnergyTasks`). **This exact mechanism was already found and partially fixed
in commit `fcbcfc2` the same week** ("FUSION AT 30+ MINUTES": fusion's
energy condition defaults to `costE * cost_ratio` = ~1300 e/s, which is
2600 e/s effective while stalling, so the walk "fell through to coradvsol
(bar 200) and stopped" before ever reaching fusion) — **and that fix was
deliberately reverted the same day in `5613d7d`**, because lowering the gate
alone made things worse: only one energy task is allowed in flight at a time,
so committing early to one 26,000-energy fusion blocked every other energy
build until it finished, and that batch's own numbers (T3 metal 16,800,
static defence 2.20x stable's) got worse, not better. The revert's own
commit message says it plainly: *"The 1300 gate is still the real reason for
30-minute fusions, but lowering it in isolation is not the fix -- the task
allowance is."* The current `economy.json` (`corfus`/`armfus`:
`[30, 40, 30]`) carries that revert unchanged — the explicit m-income (30) was
kept, the e-income override was not restored, so the ~1300 e/s default gate
is still live today.

**Conclusion: this is not a new finding, it is confirmation that a known,
already-diagnosed, already-reverted-for-a-good-reason problem is still the
live cause of apex's solar/fusion imbalance on the 4v4 benchmark.** The
straightforward fix (lower the gate) is already known not to work in
isolation. What was never tried is the thing `5613d7d`'s own message names as
the actual lever: raising the energy task concurrency allowance (or otherwise
letting a fusion commit without freezing every other energy build behind it)
so a lower gate does not starve the rest of the grid. That is a genuinely new
angle, not yet attempted, and it is a behavior change (not diagnosis) — needs
its own isolated test with a control batch, per this project's one-change-at-
a-time discipline.

**What was NOT true and should stop being repeated:** the eco lead is not
"choosing solar over fusion too readily" on Comet Catcher 4v4 — it has no
opinion, because it isn't running. Any future work on `EcoFusion()`'s own
gates (`FUSION_MIN_BANK`, `EnergyWasting()`) will have zero effect on this
benchmark's win rate until either `ECO_ON_SMALL_TEAMS` changes (already
tested worse) or the benchmark moves to `IsSmallTeam() == false` (>=6 per
side), which is a different map/format than every other batch this session
compared against.

**Kept**: the diagnostic `AiLog` line in `EcoFusion()` — cheap, throttled
45s, and it is what caught this; a future session investigating the eco-lead
path on a bigger-team map has a working instrument already in place. Batch
result for the record (informational only, not a behavior change): apex 4,
stable 2, 10/16 undecided (hit the 25-min cap); apex wipeout rate 10/64
(15.6%) vs stable 19/64 (29.7%) in these same games.

## 19. "Commander survival predicts the winner" -- NOT reproduced against this session's data (2026-08-04)

Re-checked the prior-session memory claim ("commander survival predicts
the winner") against 64 matches / 128 player-games pooled from four
2026-08-04 tournaments (`phasegate4-extend2-16`, `phasegate4-extend3-16`,
`gated-16`, `isolate-latefighter-16`), fixing the dedup bug that sank the
earlier ad-hoc attempt (team-id lookups are now reset per match, since
team ids repeat across matches in one ledger). `commLost` semantics were
confirmed reliable via `game-patches/gadgets/dev_stats_export.lua`: set
once on the frame the `customParams.iscommander` unit dies, `-1`
otherwise.

**Commander-loss rate itself is nearly identical between sides**: apex
53.1% (n=64) vs stable 56.2% (n=64) -- not a meaningful gap.

**The win-correlation subsample is thin.** Only 26 of the 64 matches
actually reached `result.reason=='gameover'`; the other 38 hit the time
limit with no recorded winner and had to be excluded from this part
(still counted in the loss-rate numbers above). Within those 26 decided
games: apex commander-lost (n=15) lost 46.7% of the time, apex
commander-survived (n=11) lost 54.5%; stable showed the same pattern
(47.1% vs 55.6%). **Losing the commander was not associated with a
higher loss rate for either side** -- if anything the small-sample
numbers point slightly the opposite direction, most likely noise at
n=9-17 per bucket.

**Verdict: does not reproduce the prior finding in this data.** Treat as
inconclusive/not-reproduced rather than a refutation -- the real
constraint is that most matches in these tournaments end by time limit
before either commander dies, so the subsample that could actually test
the correlation is small. Recommend not treating "commander survival
predicts the winner" as an established fact for tuning
(`COM_RETREAT_HEALTH`, `COMM_BACK_WALL_ON`) without a larger sample of
games that reach `gameover` rather than the time cap -- which likely
means shorter time limits or a faster-resolving benchmark, not more
games at the current 25-minute cap. Read-only analysis; no files or code
changed for this check.

## 20. Round synthesis, 2026-08-04 -- four checks against `notes/next-session-hypotheses.md` sections 1-4

All four items from the prior write-up's priority list (excluding item 0,
which needs a human and was NOT done -- see below) were tested this
round, by separate agents, each already committed individually:

| # | hypothesis | commit | result |
|---|---|---|---|
| 1 (H1c) | rez-bot flee-on-hit fix drives the cornecro/wipeout shift | `5610ad3` | **Not confirmed** -- reverting the fix moved cornecro share and wipeout rate FURTHER from baseline (17.3%, 37.5%), not back toward it. See issue 17. |
| 2 | `EcoFusion()`'s own gate is too conservative vs advanced solar | `7ebfede` | **Wrong hypothesis, right area** -- the entire eco-lead script path is unreachable on 4v4 (`IsSmallTeam()` always true), so the real cause is the already-known, already-reverted `economy.json` fusion e-income gate. See issue 18. |
| 3 | commander survival predicts the winner | (read-only, no commit -- synthesized here as issue 19) | **Not reproduced** at n=128 player-games / 26 decided matches. |
| 4 | team-0/1 positional asymmetry | (read-only, no commit -- synthesized into issue 14 above) | **Refuted at n=259** -- z dropped from 1.48 to -1.30 with 5x the data. |

Net effect on the code: **zero behavior changes survived this round.**
Issue 17's revert-then-restore left `builder.as` unchanged from HEAD; the
followup diagnosis in issue 18 kept only a throttled diagnostic log, no
behavior change; issues 19 and 20 (this entry) are read-only analysis.
The round's value is entirely in ruling things out and re-pointing the
next concrete step: issue 18's "raise energy task concurrency" angle is
now the most concrete untried lever on the table, everything upstream of
it (eco-lead gates, rez-bot sensitivity, commander tuning, side-forcing)
has now been checked and found not to be the active driver of what's
being measured.

**Item 0 -- watch a live Comet Catcher 4v4 -- was NOT addressed this
round** and remains the single highest-priority action for next session;
see `notes/next-session-hypotheses.md`'s updated priority list.

## 21. Energy-task-concurrency fallthrough fix + restored fusion e-income gate -- IMPLEMENTED and DEPLOYED, batch INCOMPLETE (2026-08-04)

Followed up on issue 18/20's "raise energy task concurrency" lever -- the one
thing that commit `5613d7d`'s revert message named as the actual fix and that
was never tried.

**Found before writing anything**: `vendor/engine/AI/Skirmish/BARb/src/circuit
/module/EconomyManager.cpp` already carries an *undocumented, uncommitted-to-
notes* prior attempt at exactly this, captured in
`game-patches/circuitai/0003-cumulative.patch` but never written up here or in
CHANGES.md. It added a time-relaxed energy-income gate
(`ENERGY_GATE_FULL_SEC`/`ENERGY_GATE_LOW_SEC`/`ENERGY_GATE_FLOOR`) and then
neutralised it (`ENERGY_GATE_FLOOR = 1.0f`, i.e. no-op) with an in-code comment
describing the identical starvation mechanism issue 18 re-derived: "while one
4500-metal nanoframe stands the task-size formula allows no other energy task
at all... energy flatlines." That comment is exactly the kind of finding
CLAUDE.md says belongs here, not frozen in a comment -- recorded now.

**The actual mechanism, read from `UpdateEnergyTasks`**: the per-def
concurrency check (`taskSize < buildPower/costM*4+1`) rounds to ~1 for an
expensive def like corfus. When that check fails for the walk's current
best (highest-tech affordable) candidate, the old code did
`bestDef = nullptr; break;` -- aborting the ENTIRE search for that tick, so a
single in-flight fusion blocked not just another fusion but every cheaper
energy def below it in the walk order too. That is the literal "one energy
task blocks everything" bug named in `5613d7d`.

**Change made** (one isolated behavior change, matching the hypothesis):
1. `EconomyManager.cpp::UpdateEnergyTasks` -- changed that `break` to
   `continue`, so a concurrency-capped high-tech candidate no longer aborts
   the walk; cheaper defs with concurrency budget left get considered instead
   of nothing being built at all.
2. `economy.json` -- restored `corfus`/`armfus` e-income override to 300
   (`[30, 40, 30, 300]`, up from the current `[30, 40, 30]` which defaults to
   ~1300 e/s via `costE * cost_ratio`), same value `fcbcfc2` used before its
   same-day revert.

Rebuilt via `docs/06`'s ninja loop (clean build, only `EconomyManager.cpp.obj`
recompiled), deployed (`SkirmishAI.dll (local build)`), smoke-tested: 5-minute
headless match, 0 AngelScript compile errors, both AIs confirmed loaded via
`Load script:` lines in the infolog.

**Batch: `tournaments/20260804-154253-round1-fusion-concurrency` -- launched,
NOT completed.** The session ran out of turn budget before any of the 16
games finished (games were still in their opening minutes, 3 running
concurrently, when this had to be written up). **No win/loss, composition, or
starvation data was collected. This is not a result -- it is a checkpoint.**

**State left in the repo**: the `economy.json` edit is UNCOMMITTED (working
tree has one modified file, `git status --short` confirms nothing else
changed). The C++ edit lives only in `vendor/engine/...EconomyManager.cpp`
(gitignored) and the locally-built, already-deployed `SkirmishAI.dll` -- it is
NOT yet captured into `game-patches/circuitai/0003-cumulative.patch`, so a
fresh clone or a `vendor/` wipe loses it. Per this project's own doctrine
(commit only on a measured, clear result), neither the JSON change nor the
patch regeneration should be committed until the batch actually finishes and
is compared with `composition.py`.

**For whoever picks this up next**: the deployed DLL and `economy.json` are
already in the state to test -- no rebuild needed unless `vendor/` gets
touched. Either let `tournaments/20260804-154253-round1-fusion-concurrency`
finish (it may still be running as a detached process) or relaunch a fresh
16-game batch with the same name pattern, then run `composition.py` on it and
follow this repo's decide step (issue 18/20's specific watch list: corfus vs
coradvsol share, T2 spend ratio vs stable -- was 0.63 -> 0.21 when the gate was
lowered alone, should NOT collapse again if the fallthrough fix worked -- and
wipeout rate, since apex died at 28 min last time this gate was touched). If
the batch is clearly better, commit the JSON change AND regenerate
`0003-cumulative.patch` from the vendor working tree (`git diff` in
`vendor/engine/AI/Skirmish/BARb`) so the C++ fix survives a re-clone. If it is
clearly worse or a wash, revert `economy.json`'s e-income override back to
`[30, 40, 30]` -- the `continue`-instead-of-`break` C++ fix can stay either
way, since on its own (before any JSON change) it can only ever cause the
search to consider MORE options on a given tick, never fewer, so it has no
plausible downside independent of the gate value.

## 22. Round-2 attempt at issue 21's batch -- STILL incomplete, orphaned-process trap identified (2026-08-04)

Picked up issue 21 exactly as written: no code change needed, the C++ fix and
`economy.json` override were already implemented and deployed. Before doing
anything else, checked for stuck processes per harness discipline and found
issue 21's own batch (`tournaments/20260804-154253-round1-fusion-concurrency`)
still had **3 live `spring-headless.exe` processes**, but its `ledger.jsonl`
had only 3 entries and every one had `winner: null` -- i.e. these were 3
in-flight matches with no controlling `run_tournament.py` process left alive
to launch the remaining 13 jobs or ever record a result for the 3 running.
**The orchestrator died with the prior agent turn; the workers it spawned did
not.** A batch launched this way cannot self-complete no matter how long it is
left -- there is nothing left to dispatch job 4 through 16 once the parent
process is gone. This is a new, previously-undocumented failure mode distinct
from the ones already in CLAUDE.md's harness-discipline section: it is not
"someone edited a file the run needed" or "a waiter kept polling for a
finished run" -- it is the run's own driver process disappearing at a subagent
turn boundary while its workers keep going, silently producing a batch that
can never reach its target count.

Killed the 3 orphaned `spring-headless.exe` (`Get-Process spring-headless |
Stop-Process -Force`, confirmed 0 remaining after a retry -- the first
`Stop-Process` call reported no matching processes yet `Get-Process`
immediately after still showed the same 3 PIDs with rising CPU time; a second
`Stop-Process -Id <pid>` targeting the exact PIDs was needed before they
actually died). Verified `deploy_ai.py status` still reported `apex in sync`
(the round-1 deploy of the locally-built `SkirmishAI.dll` plus the
uncommitted `economy.json` override was untouched by the process kill), so no
rebuild or redeploy was needed. Launched a fresh, independent 16-game batch,
`tournaments/20260804-154943-round2-fusion-concurrency`, with `run_tournament.py`
backgrounded so its driver process is decoupled from this turn, and armed a
polling monitor for `ledger.jsonl` reaching 16 lines.

**This round again ran out of turn budget before the batch finished** -- at
the time this had to be written up, `ledger.jsonl` for round2 did not yet
exist (no game had completed even one 25-minute headless match, consistent
with the ~15-25 min wall time this repo's own docs quote for a 16-game
batch at 3 workers). **Zero win/loss or composition data was collected in
this round either.** No commit was made to `economy.json` or any patch file;
`git status --short` at the end of this round shows exactly the same single
uncommitted line as issue 21 left it (`M
ai/apex/game-side/config/hard_aggressive/economy.json`) -- no new drift.

**For whoever picks this up next**: the deployed DLL and `economy.json` are
still in the state to test (`deploy_ai.py status` said `apex in sync` as of
this round; re-check it first in case another round has touched things since).
Before relying on any background batch across a turn boundary, **confirm the
driver process is actually alive**, not just that `spring-headless.exe`
processes exist -- 3 running workers with 0 ledger entries and no growth over
several minutes is the signature of an orphaned batch, not a slow one. If
`tournaments/20260804-154943-round2-fusion-concurrency` is still running and
its ledger is growing, let it finish and run `composition.py` on it. If it is
also orphaned (workers alive, ledger stalled), kill and relaunch again with
the same name-suffix pattern. Once a batch actually reaches 16/16, follow
issue 21's decide step unchanged: corfus vs coradvsol share, T2 spend ratio
vs stable (was 0.63 -> 0.21 when the gate was lowered alone), and wipeout
rate (apex died at 28 min last time this gate was touched alone) are still
the specific things to check before commit-vs-revert.

## 23. Round-2's `round2-fusion-concurrency` batch finally completed 16/16 -- REGRESSION, reverted (2026-08-04)

Picked up where issue 22 left off. Confirmed the batch's orchestrator (PID
6840, `run_tournament.py --name round2-fusion-concurrency`) was alive and
actively dispatching new match jobs (t003-t005 running at the time of
inspection), not orphaned like round1 -- so this round let it run to
completion instead of relaunching. `tournaments/20260804-154943-round2-fusion-concurrency`
reached 16/16 valid games with no compile errors, no crashes, no desyncs.

**Result: a clear regression, not the hoped-for fix.**

```
python tools/review.py tournaments/20260804-154943-round2-fusion-concurrency
outcome  BARb-stable-hard_aggressive     5/16   31.2%
         BARbApex-apex-hard_aggressive   0/16    0.0%
```

apex won **zero** of 16 games (5 decided for stable, 11 hit the time limit
with no winner). Composition confirms this was not noise:

- metal produced: apex 39,371 vs stable 52,211 (apex ~25% lower)
- T2 spend: apex 13,653 vs stable 26,451 -- ratio 0.52, i.e. the same
  collapse pattern issue 18/21 warned about when the fusion gate is lowered
  without enough concurrency headroom, just not quite as severe as the
  bare-gate-lowering's 0.21
- wipeout rate: apex 18/64 player-games ended wiped out vs stable's 10/64 --
  apex died more often, not less
- corfus was still apex's #1 metal sink (17.2% share, close to stable's
  17.6%) so the `armfus`/`corfus` e-income override to `[30, 40, 30, 300]`
  did not starve fusion construction itself -- the collapse shows up
  downstream, in T2 spend and overall metal produced, consistent with the
  extra concurrency slot letting fusion compete with (and lose to, or crowd
  out) other T2 economy work rather than fixing the original starvation.

**Decision, per this session's stated rule (issue 21's own contingency
plan): reverted.** `ai/apex/game-side/config/hard_aggressive/economy.json`
restored to `[30, 40, 30]` via `git checkout --`; `git status --short` shows
zero diff. Redeployed the clean HEAD (digest `9a13920fc2e7`), smoke-tested
(3-minute headless match, 0 AngelScript compile errors in the infolog) --
confirms the reverted state is what is actually live before anyone builds on
it next.

The vendor-side C++ concurrency fix (`continue` instead of `break` in the
energy-task search, referenced in issue 21) was **not touched or re-verified
this round** -- only the `economy.json` JSON override was tested and
reverted. Issue 21's original argument that the C++ fix alone has no
plausible downside (it can only let a search consider MORE options per
tick, never fewer) still stands on its own logic, but it has never been
benchmarked independently of the JSON gate change. That is the concrete
open question for whoever picks this up next: test the C++ fix ALONE, with
`economy.json` left at stock `[30, 40, 30]`, before concluding anything
about fusion concurrency as a mechanism -- this round only tested "gate +
concurrency fix together" and that combination lost.

## 24. `round4-concurrency-alone` -- the C++ fix ALONE also regressed. Fusion-concurrency line fully closed (2026-08-04)

Tested issue 23's exact residual question: the concurrency-capped-candidate
fallthrough fix (`bestDef = nullptr; break;` -> `continue` in
`EconomyManager.cpp::UpdateEnergyTasks`) with `economy.json` left at stock
`[30, 40, 30]` -- no JSON gate change at all. Confirmed before testing: repo
`git status` clean, `deploy_ai.py status` in sync at `9a13920fc2e7`, and the
`continue` was present and reading exactly as issue 21/23 describe in
`vendor/engine/AI/Skirmish/BARb/src/circuit/module/EconomyManager.cpp` around
line 1450 -- so no rebuild was needed going in, only a fresh isolated batch.
Smoke-tested first (5-min headless match, 0 AngelScript compile errors, both
variants confirmed loaded).

`tournaments/20260804-161220-round4-concurrency-alone`, 16/16 valid games, no
crashes, no desyncs:

```
outcome  BARb-stable-hard_aggressive     7/16   43.8%
         BARbApex-apex-hard_aggressive   2/16   12.5%
```

9 games ended undecided at the time limit. Composition confirms this is not
a coin-flip on win rate alone -- it reproduces the same shape of collapse
issue 23 found for the *combined* gate+fix change, on the fix alone:

- metal produced: apex 33,155 vs stable 46,275 (~28% lower) -- issue 23's
  combined change was ~25% lower
- T2 spend: apex 10,393 vs stable 23,013 -- ratio **0.45**, actually a
  *worse* collapse than the combined change's 0.52
- wipeout rate: apex 20/64 player-games ended wiped out vs stable's 11/64 --
  apex died more often, consistent with issue 23's 18/64 vs 10/64
- apex's top metal sink this round was `cornecro` (16.3%) then `corsolar`
  (14.4%), with `corfus` down to 4.0% -- a different composition than issue
  23's combined-change batch (where corfus held 17.2%, matching stable).
  The specific unit picked differs batch to batch, but the aggregate
  T2-collapse signature does not.

**This falsifies issue 21/23's own argument that the fallthrough fix "can
only let the search consider MORE candidates, never fewer, so it should have
no plausible downside."** That reasoning is true narrowly -- the search does
see more defs -- but it ignores that the def it then picks can be a *worse*
one for the moment (e.g. a T1 solar/necro pick that never rolls forward to
fusion, versus the old behaviour of giving up on energy entirely for a tick
and retrying). Falling through to a cheaper option changed WHICH cheaper
option got queued repeatedly rather than fixing the starvation; three
independent metrics (T2 ratio, metal produced, wipeout rate) moved the same
wrong direction as the combined change, not a subset -- that is stronger
than a single win-rate swing this session's own noise floor could produce.

**Reverted.** Restored `bestDef = nullptr; break;` in
`vendor/engine/AI/Skirmish/BARb/src/circuit/module/EconomyManager.cpp`,
rebuilt via the documented one-step ninja build
(`docs/06-building-the-dll.md`), redeployed (`deploy_ai.py deploy apex`
printed `SkirmishAI.dll (local build)`, confirming the rebuilt binary went
out), and smoke-tested again (0 compile errors). Checked
`game-patches/circuitai/0003-cumulative.patch`: it never actually contained
the `continue` fallthrough hunk in the first place -- that edit was a
local-only change layered on top of the committed patch and was never
regenerated into it. So the revert requires no patch update; the tracked
patch already matches the reverted, currently-deployed state, and
`git status --short` on the main repo shows zero diff.

Note for whoever touches `vendor/engine` next: the working tree carries
several OTHER uncommitted diffs beyond this one (`AA_MASS_RATIO`,
`SQUAD_SPEED_RATIO`, `REPAIR_WORTH_COST`, the squad regroup threat cap, the
squad cohesion spread cap -- several with "back to upstream" comments,
suggesting they were already reverted locally this session but never
regenerated into the patch either). None of those were touched, tested, or
judged by this round; do not assume `git diff` in `vendor/engine/AI/Skirmish/BARb`
being non-empty means untested work is pending review -- check each hunk
against the committed patch before acting on it.

**Conclusion: the fusion/energy-concurrency line (issues 18, 21, 23, 24) is
now fully closed as tried and ruled out**, in every combination tested this
session -- gate alone, gate+fix, and fix alone. All three regressed T2 spend
and metal production versus stable. Do not re-open without a materially
different mechanism (e.g. a per-def concurrency budget instead of a global
one), not a re-run of the same lever.

## 25. Consolidated summary: 4-round fusion-concurrency hypothesis run, no winner found (2026-08-04)

This run set out to test item 2 of `next-session-hypotheses.md`'s priority
list -- the "most concrete untested lever on the table" that survived the
prior round's diagnosis: pairing a restored, lower `corfus`/`armfus`
e-income gate (`5613d7d`'s revert target) with a loosened energy-task
concurrency constraint in `CEconomyManager::UpdateEnergyTasks`, on the
theory that the gate alone failed in `fcbcfc2`/`5613d7d` only because it
starved all other energy building behind one in-flight fusion, not because
a lower gate is inherently wrong. Four rounds ran against a 4-round cap.
No winning change survived; the whole line is now closed (issues 18,
21-24). Round by round:

- **Round 1** (commit `9a9cf47`): implemented both halves of the fix (a
  `break`->`continue` fallthrough in the concurrency-capped-candidate
  branch, plus `economy.json`'s e-income override restored to
  `[30, 40, 30, 300]`), deployed and smoke-tested clean, but the 16-game
  confirmation batch only reached 3/16 games before the round ended.
  **No data.**
- **Round 2** (commits `31c45fb`, then `352b843`): found round 1's
  tournament driver had died mid-run, orphaning 3 live spring-headless
  workers with a ledger stuck at 3/16 -- a new, previously undocumented
  background-run failure mode (now issue 22). Killed the orphans, relaunched
  a fresh batch, but it also didn't finish inside the round's turn budget.
  A separate, oddly-populated round (task fields literally `"test"`) picked
  up the same in-flight state, let that relaunched batch finish, and got a
  clear result: **apex 0/16 wins, stable 5/16 (11 undecided)**, T2 spend
  ratio 0.52 (vs stable), metal produced ~25% lower, wipeout rate elevated
  (18/64 vs 10/64). Reverted `economy.json`'s override; the C++ fix was left
  untouched and unverified in isolation, which round 4 called out as the
  concrete open question (issue 23).
- **Round 4** (commit `30827c6`): tested the C++ fallthrough fix ALONE,
  gate left at stock `[30, 40, 30]`, on the theory it "can only let the
  search see more candidates, never fewer, so it should have no plausible
  downside." Falsified: **apex 2/16 wins, stable 7/16 (9 undecided)**, T2
  spend ratio 0.45 (worse than the combined change's 0.52), metal produced
  ~28% lower, wipeout rate 20/64 vs 11/64 -- the same collapse shape
  reproduced on the fix alone, across three independent metrics, not just a
  win-rate swing this session's own noise floor could produce. Reverted;
  confirmed the tracked `game-patches/circuitai/0003-cumulative.patch`
  never contained the fallthrough hunk in the first place, so no patch
  regeneration was needed.

**Net result: no shipped change.** Two of four rounds burned their entire
budget on run/orchestration mechanics (an orphaned tournament driver, a
batch that didn't finish in time) rather than producing a measurement --
that is itself the most concrete finding of this run, see issue 22 and the
harness-discipline note below. Of the two rounds that did produce data,
both were clean, well-powered negative results (three independent metrics
moving the same wrong direction each time, not a coin-flip on win rate
alone), which is a legitimate and useful outcome: the fusion/energy-task-
concurrency mechanism is now genuinely ruled out, in all three combinations
anyone could think to try, rather than left as an untested "most promising
lever." `vendor/engine`'s working tree is confirmed back at a clean,
patch-matching state (`git status --short` zero diff on the main repo;
`0003-cumulative.patch` unchanged because it never carried the tested hunk).

**Process note for whoever dispatches the next round-based run**: a 16-game
tournament batch takes 15-25 minutes wall time, which is longer than at
least two of this run's per-round turn budgets. `run_tournament.py &`
detachment did not reliably survive a turn boundary (issue 22's orphaned
driver). If this workflow shape (propose/test rounds with a turn budget)
is used again for something that needs a full tournament, either give the
round enough turn budget to poll to completion, or make round N+1's first
job explicitly "resume/verify round N's batch," not a fresh idea -- which
is what actually happened here by accident, not by design.

**Research findings from a parallel read-only pass** (public GitHub issue
trackers and community discussion, not this repo's own telemetry) turned up
nothing directly actionable for this benchmark: two `rlcevg/CircuitAI`
issues (#125 mex-spot misbuild, #127 failure to retreat) are filed against
an unconfirmed "Testing AI" identity, not confirmed to be the shipped
`hard_aggressive` profile; #118 (reclaim/resurrect ignoring Thor/Titan
wrecks) describes stock BARb's own weakness at a unit scale this 25-minute
4v4 benchmark never reaches; `beyond-all-reason/Beyond-All-Reason#2620` is
about the allied co-op bot, out of scope for an enemy skirmish opponent; a
low-confidence secondary source's air/water claims are either moot
(this project is land-only) or already tracked (issue 5, mobile AA/fighter
massing). None of this changes any conclusion above or opens a new lever --
recorded here only so the search is not repeated.

## 26. `livefixes2-16` (n=16, post-8092d3a/493fd27): first batch this session with a CI excluding 50% on the WINNING side

**4-0 decided (100%, 95% CI 51.0%-100.0%). 12/16 hit the time limit.** This
tests the current shipped state: `phase >= 4` + the three earlier
team-size-gated fixes (`872473c`/`9a1b249`) + today's three new
live-diagnosed changes -- rez bots gated on an actual wreck being present
instead of building unconditionally at t=0 (`8092d3a`), air factories no
longer falling through to the engine's own uncoordinated bomber ratio pick
after the assassin's strike releases (`8092d3a`), and the assassin's mass
threshold scaling with income instead of a fixed 12/8 floor (`493fd27`).

Small n (4 decided) means this is not yet the same statistical weight as
the larger `gated`/`isolate-latefighter` batches, but it is the FIRST
result all session where the 95% CI excludes 50% in apex's favor rather
than straddling it or excluding it against apex. Worth a second batch to
confirm before calling this "reliably beats," per the same discipline
applied to every other result this session -- but this is the strongest
single data point so far.

(A first attempt at this exact batch, `livefixes-16`, was interrupted at
14/16 games by an unrelated machine reboot mid-session and discarded
rather than trusted at a partial count.)

## 27. "Running into enemy towers" (apexearth, watched Comet Catcher 4v4) -- one part fixed in AngelScript, one part is out of this AI's reach without new C++

apexearth's report: "we do something in the early game which is running into
enemy towers ... and we don't even seem to focus on killing the tower. I've
seen us lose ~10 army to a single tower." Two separate mechanisms, confirmed
independently.

**Part 1 -- mass-commitment blindness to static defence. FIXED, code shipped,
NOT YET DEPLOYED OR TESTED (BAR was open live during this session, see below).**

`military.as` `EnemyArmyCost()` (docstring: "What the enemy's MOBILE army is
WORTH") sums only `ASSAULT/RAIDER/RIOT/SKIRM/ARTY/AH` via
`aiEnemyMgr.GetEnemyCost(role.type)`. It never included `RT::STATIC`, the same
role the rest of the codebase already treats as a distinct enemy-composition
category -- it appears in every `response.json` `"vs"` list
(`ai/apex/game-side/config/hard_aggressive/response.json`) and in
`docs/04-json-config-reference.md`'s worked example, always alongside the
mobile roles, never folded into them. So `MassWant()`/`UpdateMassing()`
(`military.as` ~380-435), which decide `aiMilitaryMgr.quota.attack` -- the
team's attack-commitment threshold -- from `EnemyArmyCost()` vs
`TeamArmyCost()`, read a heavily-turreted chokepoint identically to open
ground whenever mobile army counts were similar. That matches the observed
infolog exactly: `matches/watch-comet-catcher-4v4-8/infolog.txt` logged
`mass want=30 army=4250 enemyArmy=4072 ratio=0.96` at 10.0min (just under
`ATTACK_EDGE=0.95`, i.e. "committed"), then the entire army (4250 -> 0) and
the commander died within 90 seconds.

`RT::STATIC` / `Unit::Role::STATIC` (`ai/apex/game-side/script/unit.as:20,87`)
is bound through the identical `aiEnemyMgr.GetEnemyCost(Type)` call
`EnemyArmyCost()` already uses for every other role -- confirmed live data,
not a guess (see `CLAUDE.md`'s engine-callback-bug note for why that
distinction matters here). It was declared but never read anywhere in
`ai/apex/game-side/script/` before this change.

Added `EnemyMassingThreat() = EnemyArmyCost() + 0.5 * GetEnemyCost(RT::STATIC)`
and pointed `MassWant()`/`UpdateMassing()` at it instead of `EnemyArmyCost()`
directly. Deliberately NOT folded into `EnemyArmyCost()` itself, and
deliberately weighted at half rather than 1:1:

- `EnemyArmyCost()` also feeds `KillingBlow()`, `T3Worthwhile()`
  (`factory.as:2308`), and `AssessedThreat()` (`military.as:1391`, which
  already separately adds `RT::HEAVY` at full weight -- the established
  precedent for broadening this function, used here as the template for
  *how* to add a role, not *what weight*). Static defence is a sunk cost that
  is built once and never degrades, unlike mobile army which is continuously
  produced and lost. Folding it into `EnemyArmyCost()` itself would let a
  static-heavy enemy base permanently inflate every one of those gates for the
  rest of the game -- for `KillingBlow`/`T3Worthwhile` specifically, that
  reproduces the exact "dominant but never converts" failure this file
  already documents at line ~443 (30 games, 67% timed out) in a new form: a
  war of attrition where the wall itself, not the enemy's fielded army, is
  what keeps our own gates from ever releasing. Scoping the fix to a new
  `EnemyMassingThreat()` used only by `MassWant()`/`UpdateMassing()` avoids
  that; `KillingBlow()`'s own `gKilling` override already short-circuits
  `UpdateMassing()` unconditionally once we're dominant, so this cannot
  create a second attrition-lock even there.
- Half weight, not full: a turret has no upkeep and cannot retreat, redeploy,
  or be lost to a bad trade the way a mobile unit of equal cost can, but it
  also only threatens the one approach it covers rather than the whole map.
  This is reasoning, not a measurement -- explicitly flagged as such in the
  code comment, per `CLAUDE.md`'s "never state a cause you did not measure."
  0.5 is an untested starting constant; retune from a watched game (per
  `CLAUDE.md`'s "apexearth is faster than the benchmark" section) rather than
  a benchmark tournament -- turret density at a defended chokepoint is a
  map/base-layout property the standard benchmark scale may not reproduce.

**Not yet deployed or tournament-tested.** `python tools/check.py` passed
clean. Deploy was blocked this session: `Get-Process` showed a live `spring`
process plus five `Beyond-All-Reason` windows already running when this task
started, i.e. apexearth (or someone) had a game open -- deploying now risks
`WinError 5` / a half-written AI folder exactly as `CLAUDE.md`'s harness
section warns, and would step on whatever match is in progress. **Next
session: confirm BAR is closed, deploy, run the standard short-match smoke
test (grep infolog for `.as ([0-9]+, [0-9]+) : ERR`), then a 16-game Comet
Catcher 4v4 batch against the pre-this-change build, watching composition.py
specifically for reduced attack frequency / passivity, not just win rate --
that is the failure mode this kind of defensive change most plausibly
introduces.**

**Part 2 -- "we don't even seem to focus on killing the tower." Confirmed OUT
OF REACH of this AI's AngelScript layer; would need new C++ engine work, not
attempted here per the task's own scoping instruction.**

`docs/05-angelscript-api.md`'s AngelScript API doc states this plainly and
independently of this task: "There is no enemy unit enumeration. `CEnemyManager`
exposes only `GetEnemyThreat(Type)`, `GetEnemyCost(Type)`, `mobileThreat` and
`maxAAThreat`. No positions, no unit list, no commander handle... target
selection lives in C++." Moment-to-moment attack-target selection during a
fight -- which unit an engaged squad member shoots at, including whether it
prioritizes a static emplacement over a moving target -- is entirely inside
`CAttackTask`/engine combat logic. This AI's script layer (`military.as` and
everything else in `ai/apex/game-side/script/`) only ever composes tasks and
sets thresholds like `quota.attack`; per `docs/05-angelscript-api.md` item 1,
even *enqueuing* an attack task by hand crashes the AI, let alone reaching
into it to steer individual unit targeting. The doc's own escape hatch --
`ai.CallRules`/`ai.GetGameRulesParam` talking to a game-side LuaRules gadget
that computes a target -- exists only for a game archive under this project's
control (`game-patches/gadgets/`), is a nontrivial new mechanism (synced Lua +
a new binding path), and was explicitly out of scope for this task. **If
"focus the tower, not whatever's in range" is worth doing, it is a new,
separate, bigger follow-up: either a C++ change to `CAttackTask`'s target
scoring (needs the cross-compile toolchain, `docs/06-building-the-dll.md`) or
a synced LuaRules gadget that overrides target selection for engaged squads.
Not attempted here.**

## 28. "Four bot labs by 18 minutes" (apexearth, watched Comet Catcher 4v4) -- confirmed as an in-flight-request race, cooldown gate added, NOT YET DEPLOYED (BAR open)

Confirmed the report against `matches/watch-comet-catcher-4v4-8/infolog.txt`:
team 2 (the eco/tech lead, `lead=1 haveT2=1` in the surrounding `conbranch`
lines) logged `T1 lab on field: corlab` six times -- frames 1896 (1.1min),
16600 (9.2min), 17586 (9.8min), 18465 and 18557 (10.3min, 92 frames /
~3 seconds apart), and 19922 (11.1min). Each is a distinct new FACTORY unit
being registered (`AiUnitAdded()` in `factory.as`, fires once per unit with
`usage==FACTORY` and no T2 attribute), not six log lines about one lab.

**Ruled out "lost in combat, rebuilt"**: pulled `tools/spending_timeline.py`
for this match. Team 2's `mCon` rose 1220 -> 2420 -> 2650 across minutes
6/10/14, `armyReal` stayed flat-to-rising (3665 -> 3245 -> 3260, never
crashing toward zero), and `metalProduced` climbed steadily the whole window
(4566 at min6 to 18757 at min12). None of the three signals that would mark
a wipe-and-rebuild (mCon collapsing, armyReal collapsing, a `top` list going
quiet) appear anywhere near 9-11 minutes. The `top`-list `corlab` spend
itself tracks the count exactly: 470 (1 lab) at min8, 1410 (3 labs, matches
frames through 19922) at min10-and-just-after, 2820 (6 labs) by min12. This
is uncoordinated duplication of a healthy economy's build orders, not a
rational response to losses.

**Mechanism, confirmed by reading the code, not guessed**: the T1-bot-lab
branch in `AiGetFactoryToBuild` (`factory.as`, previously ~line 2482) is
gated on `!HaveT1BotLab()`, and `HaveT1BotLab()` checks `lab.count > 0`.
`CCircuitDef::count` increments in `RegisterTeamUnit`, which the codebase's
own existing comments (on this same function, and on `WantMoreGantries`)
already establish runs at the **nanoframe** -- when a builder's nanolathe
actually starts touching the structure, not when the build order is issued.
A constructor ordered to place a lab still has to walk to the site first.
Every other idle constructor that gets offered `AiGetFactoryToBuild` during
that walk reads the exact same `!HaveT1BotLab()` (still true, nothing has
started yet) and picks the identical lab. This is the same failure shape
`AiIsSwitchTime`'s doc comment already names for a related but distinct bug
("Observed live: one AI with THREE T1 bot labs" -- that case was a
permanently-open switch gate, already fixed; this one is the *offer* gate
having no in-flight memory at all) -- so this codebase has now independently
hit "duplicate factory requests" from two different mechanisms.

**Fix**: followed the existing `REZ_SPACING`/`gNextRez` spacing-gate pattern
used for rez-bot floor requests in the same file. Added
`BOTLAB_REQUEST_COOLDOWN = 45 * SECOND` and `gNextBotLabRequest`; the T1 lab
branch now also requires `ai.frame >= gNextBotLabRequest` and sets it on
every successful request, regardless of whether `HaveT1BotLab()` has cleared
yet. 45s is a guess at "long enough to cover a nearby constructor's walk to
the site," not a measured number -- flagged as such in the code comment. It
is deliberately short relative to how long a genuinely lost lab needs to be
absent before rebuilding is worth it (the six observed placements span 1.1
to 11.1 minutes, so a real rebuild case is not remotely at risk of being
blocked by a 45-second cooldown).

**Not yet deployed or tournament-tested.** `python tools/check.py` passed
clean (`apex\n  ok`). Deploy was blocked this session for the same reason as
issue 27's part 1: `Get-Process` showed five live `Beyond-All-Reason`
windows plus one `spring` process already running when this task started --
deploying now risks `WinError 5` / a half-written AI folder. **Next session:
confirm BAR is closed, deploy, smoke-test (grep infolog for
`.as ([0-9]+, [0-9]+) : ERR`), then a 16-game Comet Catcher 4v4 batch,
checking `spending_timeline.py`/`composition.py` specifically for reduced
duplicate `mFactories` spend on players who previously over-built one type,
without regressing overall win rate or economy** -- this is a pure
low-risk waste-removal (constructor time and metal that were being spent on
a redundant building), so per `CLAUDE.md`'s "separate rules that SPEND from
fixes that STOP something," a regression here would be a surprise, but it
still needs the same batch-and-composition confirmation as everything else
in this file before being called done.

## 29. Session round-up: two live reports (towers, bot-lab spam) diagnosed and fixed, plus a new auto-flagging tool -- none of the three deployed or tournament-tested yet

apexearth watched a Comet Catcher 4v4 live and reported two things in one
sitting: the army walking into enemy towers and losing ~10 army with no
apparent focus fire, and team 2 ("teal") sitting on 4+ bot labs by ~18
minutes. Three agents worked these in parallel this session; this entry
just cross-references what each landed so issues 27/28 above (which already
carry the full diagnosis) don't get restated.

**Towers -- issue 27, commit `afc2157`.** Split into two independent
mechanisms rather than one bug: (1) `MassWant()`/`UpdateMassing()` decided
whether to commit to an attack using `EnemyArmyCost()`, which sums only
mobile roles and is blind to static defence by its own docstring -- fixed by
routing those two call sites through a new `EnemyMassingThreat()` that adds
half-weight `RT::STATIC` cost, deliberately *not* folded into
`EnemyArmyCost()` itself because that function also feeds
`KillingBlow()`/`T3Worthwhile()`, where a static-heavy enemy could otherwise
permanently pin those gates (see issue 27 for why that reproduces the
already-documented "dominant but never converts" failure). (2) "we don't
focus the tower" is moment-to-moment attack-target selection, which
`docs/05-angelscript-api.md` says plainly lives in C++ and is unreachable
from this AI's script layer -- confirmed, not attempted, logged as a
separate C++-or-gadget follow-up.

**Bot-lab spam -- issue 28, commit `2473373`.** Confirmed as six genuinely
distinct `corlab` placements (not a log artifact) against a healthy,
never-collapsing economy, then traced to a race: `HaveT1BotLab()` only
becomes true when a builder's nanolathe *starts* the structure, not when the
order is issued, so every constructor still walking to a build site reads
the gate as still open and grabs the same job. Fixed with a 45-second
`gNextBotLabRequest` cooldown, the same spacing-gate shape this file already
used for the rez-bot floor.

**Tooling -- `tools/combat_events.py`, commit `025558f`.** Both diagnoses
above were done by hand-grepping `infolog.txt` and eyeballing
`spending_timeline.py` rows for a collapse or a repeated build. This tool
automates that noticing: it walks a match or tournament's `result.json`
tree and reports (a) COLLAPSE events -- `armyReal`/`mCon` dropping >=60%
(configurable) between consecutive samples, with the `top` metal-sink string
at the after-sample for context, and (b) DUPLICATE-BUILD events -- the same
factory unit placed more than once within a short window, read from
`infolog.txt`'s `"<label> on field: <unit>"` lines when present, falling
back to clustering same-sized `mFactories` jumps when there's no infolog
(most tournament games). It was built and verified against
`matches/watch-comet-catcher-4v4-8` (the match both reports above came
from). Re-run this session against a tournament it had never seen,
`tournaments/20260804-192304-livefixes2-16` (16 games, has infologs): it
found 86 collapse events and 7 duplicate-build events across the batch
without error, and the duplicate-build events used the precise `[infolog]`
path (e.g. team 1 placing `corap` twice at 16.5m/17.9m), not the coarser
`mFactories`-approx fallback -- confirming the tool generalizes past the one
match it was written against, on both code paths it implements.

**State at end of session: all three changes are committed but NONE are
deployed or tournament-tested.** All three agents independently hit the same
blocker -- `Get-Process` showed a live `spring` process and five
`Beyond-All-Reason` windows already running for the whole session, so per
`CLAUDE.md`'s deploy-while-BAR-is-open warning (`WinError 5`, half-written AI
folder), nobody deployed. **Next session, in order: confirm BAR/spring are
closed, deploy apex once (both behavior changes are already in the same
tree, so one deploy covers both), smoke-test and grep the infolog for
AngelScript compile errors, then run one 16-game Comet Catcher 4v4 tournament
against pre-session HEAD.** Read it with `composition.py` for the tower fix
(attack frequency / passivity, not just win rate) and with
`spending_timeline.py`/`composition.py` for the bot-lab fix (duplicate
`mFactories` spend should drop for players who previously over-built), and
run `tools/combat_events.py` on the result as a fast first pass before
either manual read -- it is now confirmed to work on tournament output, not
just the one hand-inspected match.

## 30. Deploy+smoke-test confirmation: tower/mass-blindness (afc2157) + bot-lab cooldown (2473373)

BAR/spring confirmed closed. Deployed apex (digest 24e48b134e2d), smoke-tested
(15-min Comet Catcher 4v4 headless): 0 AngelScript compile errors. Sanity
checks on the smoke test: 5 "T1 lab on field: corlab" events across 4 apex
players (normal range -- not the 6-in-2-minutes-for-one-player pattern the
bot-lab fix targets), and "mass want=" (the new `EnemyMassingThreat()` path)
logging 43 times with no apparent issue. Both changes are live and behaving
sanely; launching `tower-botlab-16` (Comet Catcher 4v4) for the real
comparison batch next -- read with `tools/combat_events.py` as a first pass,
then `composition.py`/`spending_timeline.py` per issue 29's own recommendation
(tower fix: watch for excess passivity, not just win rate; bot-lab fix:
duplicate `mFactories` spend should drop).

## 31. `tower-botlab-16` result, and `combat_events.py` catching a fix that didn't work

**`tower-botlab-16` (n=16): 7-3 decided (70.0%, 95% CI 40-89%), 6/16 to time
limit.** Positive, centered well above 50%, but CI still includes it --
not conclusive alone. But `tools/combat_events.py` (run as the plan
specified) immediately surfaced something the win rate alone would have
hidden: the bot-lab request-cooldown fix (`2473373`) was NOT actually
working. Individual players still showed `corlab` placed **8, even 10
times within a single 3-minute window**, gaps as short as 6 seconds --
far too fast to be a genuine post-loss rebuild. Root cause: that fix only
gated the ONE script branch that requests a bot lab when a player has
*zero*; once any exists that branch stops firing on its own, so the
cooldown was never even being exercised by the actual bug. The real
duplication is the stock engine's own `DefaultMakeTask` independently
offering the same factory type to every idle constructor, with nothing
on the script side capping total count per type -- a different code path
entirely from the one `2473373` fixed.

**Fixed in `5b9b6fd`**: refuse any offered factory build once a player's
own count of that exact def reaches `FACTORY_TYPE_CAP=3` (generous on
purpose -- a strong economy legitimately wants 2-3 bot labs to
parallelize production; the bug was 8-10, not a second or third).

## 32. `factorycap-16` (n=16): 11-0 decided, 100%, 95% CI 74-100% -- the strongest result of the entire session

**11/11 decided games won, 5/16 to time limit. CI excludes 50%, a real
difference at this sample size.** This is the first time all session a
win-rate result has been unambiguously statistically significant on the
winning side at a real n (previous best was 4-0/n=4, CI 51-100%, too
small to trust alone -- see issue 26).

`combat_events.py` confirms the factory-cap fix actually worked: only 2
duplicate-build events remain in the whole 16-game batch, both `x2`/`x3`
(within `FACTORY_TYPE_CAP`'s intended allowance -- normal parallel
production, not the runaway 8-10x pattern). `composition.py` shows the
wipeout-rate reversal that likely explains most of the win-rate jump:
**apex 3/64 player-games wiped (4.7%) vs stable's 27/64 (42.2%)** --
a dramatic flip from the 31-39% apex wipeout rates measured earlier this
session (issues 15/20/25 territory). Metal produced: apex 41,075 vs
stable's 30,506. Energy wasted: apex 22,700 vs stable's 72,751. `cornecro`
(rez bot) share of apex spend: 8.0%, down from the 14-17% seen in the
earlier problem batches, consistent with today's rez-bot timing/exposure
fixes.

**This batch tests the FULL stack of today's fixes together**: rez-bot
wreck-gate + floor 4->8 (`bac027e`), mex-threat abandon-path fix
(`de4bf55`), rez-bot proactive exposure (`8d83827`), tower/mass-blindness
via `EnemyMassingThreat()` (`afc2157`), bot-lab cooldown (`2473373`,
superseded/completed by the factory-cap fix below), and the factory-type
cap (`5b9b6fd`). Not isolated per-change -- if a second confirmation batch
holds up, worth considering which of these contributed most, but the
combined result is exactly what "reliably beats" was defined as at the
start of this session.

**One live-watched match during this same window (`watch-comet-catcher-4v4-9`)
corroborates it independently**: apex won 21.86min, with `combat_events.py`
showing zero apex collapses and both of stable's own players fully wiped
(14-16min and 16-18min), zero duplicate-build events either side.

Worth a second confirmation batch before calling the session's original
goal definitively met, per this session's own standing discipline about
single-batch overclaiming -- but this is, by a wide margin, the best
evidence produced all session.

## 33. T2-constructor count stuck flat at 3 -- diagnosed as a Cortex-only faction-parity ratio bug, NOT a build_chain.json one-shot gate. Fixed but NOT DEPLOYED (spring-headless running)

Deep-dive hypothesis this session: apex's T2-constructor count measured flat at
3 across three unrelated batches (gated-big-32 regression, the pre-session
baseline, and the 11-0 factorycap-16 win) while every other economy metric
scaled substantially with the session's fixes. Proposed mechanism was a
`build_chain.json` condition (an `m_inc>` gate or hub) sampled once too early,
the same shape as this file's documented nano-gate bug.

**That specific file was not the cause.** `build_chain.json` has no T2-con
entries at all -- it only governs defence/nano/energy hubs hung off factories
and mexes. T2 constructors are chosen by the ordinary factory production-ratio
tables in `factory.json`, which are re-evaluated continuously (not one-shot),
so the "sampled once, too early" mechanism does not apply here.

**Real mechanism, found by reading `builder.as` and `factory.json` together:**

1. `Builder::AdvConsWanted()`/`NeedsAdvCon()` (`builder.as:50-59`) computes
   `1 + income/25`, capped at 4 -- an income-scaling target that looks exactly
   like what the hypothesis predicted should exist. **It is dead code.**
   Grepped the entire `script/` tree: `NeedsAdvCon()` is defined and never
   called anywhere. It cannot be the mechanism holding the count at 3, because
   nothing reads it.
2. The thing that actually *is* wired to production is `factory.json`'s
   per-tier unit-weight tables. Cortex's T2 vehicle plant, `coravp`, weights
   its T2 constructor `coracv` at **0.01 (tier0) / 0.02 (tier1)** -- effectively
   never selected regardless of how much income there is, because these are
   independent per-slot selection weights, not counts tied to income.
   Armada's equivalent plant, `armavp`, weights its own T2 constructor,
   `armacv`, at **0.55 (tier0) / 0.28 (tier1)** -- and `armavp`'s own comment
   says so explicitly: *"armgremlin is the only cheap combat vehicle here,
   hence the raise off 1%."* Someone deliberately raised Armada's T2-con
   weight off stock's 1% at some point. Cortex's `coravp` was never given the
   equivalent treatment and is still sitting at that original ~1-2%.
3. **This exactly explains the flat 3 across all three measured batches**:
   every tournament command in this repo's `CLAUDE.md`/task template runs
   `--sides Cortex,Cortex`. Every single benchmark measurement all session hit
   the never-fixed `coravp` ratio; none exercised the already-fixed `armavp`
   one. A ~1-2% selection weight barely produces the same handful of
   constructors whether income is 4 m/s or 40 m/s, because the weight itself
   never moves -- which is why the count looked invariant across every
   economic regime tested, without needing any one-shot-gate mechanism at all.

This is the same *class* of bug CLAUDE.md already names -- "Faction parity:
work done for Cortex has repeatedly been forgotten for Armada and Legion" --
just inverted (a fix landed on Armada, never carried to Cortex), and it is a
better-evidenced explanation than the one-shot-gate guess: it is not
reasoning from a documented precedent's *shape*, it is the literal comment on
`armavp` describing the exact fix that `coravp` is missing.

**Fix, `ai/apex/game-side/config/hard_aggressive/factory.json`, `coravp.land`
only** (left `coravp.air` at stock -- Comet Catcher is a land map, this
session's benchmark never exercises the air table, and per CLAUDE.md's "one
behaviour change at a time" the air-table gap is logged here as a known
follow-up, not bundled in): raised `coracv` tier0/tier1 from 0.01/0.02 to
0.45/0.25, mirroring `armacv`'s magnitude on `armavp`. Reduced `correap`
(the unit that had been absorbing coracv's foregone share, at 0.40/0.28) to
0.06/0.05 to compensate -- everything else in the table left untouched.
`python tools/check.py` passed clean.

**NOT deployed, NOT tournament-tested.** `Get-Process` showed three live
`spring-headless` processes for the entire session (consistent with issue 32's
own second confirmation batch, or another run apexearth has in flight) --
deploying now risks `WinError 5` / a half-written AI folder per CLAUDE.md's
harness-discipline section, and would step on whatever is running. **Next
session: confirm spring-headless/BAR are closed, deploy apex, smoke-test (grep
infolog for `.as ([0-9]+, [0-9]+) : ERR`), then run one 16-game Comet Catcher
4v4 batch named `deepdive-t2con-parity` against the current
factorycap-16-confirmed build. Read with `composition.py` for T2-constructor
count specifically (expect a rise off the flat 3, closer to what stock's own
side, or Armada, has shown) and overall metal produced/T2 spend; compare
against factorycap-16's own numbers (apex 11/11 decided, wipeout 3/64, metal
produced 41,075) as the baseline to beat or at least not regress from. Watch
in particular for `correap`'s reduced weight costing something -- it was the
dominant unit in that table at 40/28%, now cut to 6/5%, so a drop in Cortex's
mobile combat-vehicle output on `coravp` specifically is the most plausible
side effect to check for, not assume away.**

## 33. `factorycap-confirm-16`: second confirmation, 9-0 decided, 100%, 95% CI 70-100%

**Second consecutive 16-game batch with a CI that excludes 50% in apex's
favor.** 9/9 decided games won, 7/16 to time limit. Combined across both
`factorycap-16` and `factorycap-confirm-16`: **20 apex wins, 0 stable wins,
20/20 decided across two independent batches.**

Also from this session's deep-analysis workflow (read alongside this
result, not yet deployed): the T2-constructor count that's been flat at 3
across every batch measured this session, win or lose, traced to a real,
long-standing bug -- `factory.json`'s `coravp` (Cortex T2 vehicle plant)
weights its T2 constructor `coracv` at 0.01/0.02, while `armavp`
(Armada's equivalent) weights `armacv` at 0.55/0.28, with `armavp`'s own
comment confirming that ratio was a deliberate fix never carried over to
Cortex. Every benchmark this entire session runs Cortex vs Cortex, so
this has likely been silently capping apex's T2 constructor output the
whole time, independent of anything else fixed today. Committed
(`d20592b`) but not yet deployed or tested.

Also flagged by the same workflow, worth tracking separately: even inside
the 11-0 batch, 2 of 5 undecided games were apex clearly LOSING (not
"almost winning"), with both apex allies collapsing together in each --
and those 2 losses are exact seed-pairs with 2 convincing wins on the
OPPOSITE side, suggesting Comet Catcher itself has seed-dependent spawn
asymmetry strong enough to flip a game outright. This is a map property,
not an AI bug, but worth confirming before trusting any single seed's
result too far.

Next: deploy the queued factory-request-spacing fix (closes the async-count
race the count-only FACTORY_TYPE_CAP still had -- apexearth watched it live,
teal reaching 7-8 bot labs and a 5th queuing at count=4) and the T2-con
parity fix, tested separately per standing discipline, once the current
windowed watch match clears.

## 34. `racefix-t2con-16`: third strong batch, 6-1 decided (85.7%), combined 26-1 across three batches

Tests both the race-closing spacing gate (`38c9eb1`, closes the async-count
race apexearth caught live -- "teal has 7 or 8 t1 botlabs") and the
Armada/Cortex T2-constructor parity fix (`d20592b`, from the deep-analysis
workflow) deployed together. **6-1 decided (85.7%, 95% CI 49-97%)**, 9/16
to time limit. The CI's lower bound (49%) just barely still touches 50%,
so this batch alone is not independently conclusive -- but it is the
THIRD consecutive strong batch, and combined with `factorycap-16` (11-0)
and `factorycap-confirm-16` (9-0): **26 apex wins, 1 stable win, 27
decided across three independent 16-game tournaments (96.3%)**.

Cannot cleanly separate the race-fix's own contribution from the T2-con
fix's in this batch (both deployed together, per standing note about
deploy bundling working-tree state) -- but neither shows any sign of
having hurt, and the T2-con fix in particular targets a real, confirmed,
session-long bug (Cortex's coravp shipped with essentially zero T2
constructor weight, 0.01/0.02 vs Armada's correct 0.55/0.28), so a
positive result here is expected rather than surprising.

Separately: apexearth, watching a live 8v8 (matches/_engine, Supreme
Isthmus), caught that apex was playing all-Armada against stable's
all-Cortex, and apex's average mex count trailed stable's roughly 2:1
(7.4 vs 14.6, several Armada players stuck at 2-4 mex while others were
fine at 11-20) -- including the air-slot player's already-documented
14-minute total economic freeze. A dedicated faction-parity audit
workflow (Armada/Cortex/Legion, three angles: economy config weights,
cross-faction unitdef verification, script-logic/opener branching) is
running as of this entry to find what's actually different for Armada.
This session's entire benchmark has run Cortex vs Cortex, so an
Armada-specific bug could plausibly have survived undetected the whole
time -- CLAUDE.md's own "Faction parity" section already names this
exact failure mode as recurring in this codebase.

## 34. `corck` T1-constructor "fix" was backwards -- reverted; Cortex is the reference, not Armada

Originated the same way as before: a live 8v8 showed Armada mex counts roughly
halved vs Cortex, and `corlab`'s `corck` (flat 0.05) vs `armlab`'s `armck`
(0.25-0.35) looked like the same shape as issue 33's `coravp`/`coracv` fix (a
value raised on Armada, never carried to Cortex). Raised `corck` to 0.25 flat
on that assumption and launched `parity-corck-16` (Cortex,Cortex) to confirm.

**That assumption was never checked and was wrong.** Every benchmark this
entire session -- all three batches behind the 26-1 combined record
(`factorycap-16` 11-0, `factorycap-confirm-16` 9-0, `racefix-t2con-16` 6-1)
-- ran `--sides Cortex,Cortex`. Cortex's values, whatever they are, are the
ones with real validated data; Armada's and Legion's have never been
benchmarked at all. Treating Armada's number as "correct" and Cortex's as
"the bug" had it backwards -- apexearth caught this directly: *"I guess one
concern I have about your finding here is that all of our testing was with
cortex. So we should assume the cortex values are the good ones."*

`parity-corck-16`'s own partial data agreed: 0-2 decided at 3/16, 0-3 decided
at 6/16 -- apex losing every decided game, the opposite of every other batch
this session. Stopped the batch early and reverted rather than waiting out
the full 16 for a confirmation of a result already visible.

**Revert**: `corck` back to flat 0.05 across all six tiers (`corak`
0.90/0.17/0/0/0/0, `corthud` 0.63/0.66/0.68/0.70/0.72 -- the exact values
behind the 26-1 record).

**Redirected fix, same evidence, opposite direction**: brought `armlab`'s
`armck` (0.25/0.25/0.35/0.35) and `factory_leg.json`'s `leglab` `legck`
(flat 0.10) down to Cortex's proven flat 0.05 instead, freeing their share to
each table's existing dominant absorber (`armpw`/`armham` for Armada,
`leglob` for Legion -- the same "corak early, corthud late" shape issue 33
and the original corck fix both used, just applied to the two untested
factions rather than to Cortex). **Neither change is tournament-confirmed --
next session, run an Armada,Armada and a Legion,Legion batch before trusting
either.** Issue 33's `coravp`/`coracv` fix is the same open question: it too
was written as "Cortex raised to match Armada" and has never been confirmed
against a Cortex-only baseline the way corck's regression now has been --
re-examine it under the same Cortex-is-reference logic.
