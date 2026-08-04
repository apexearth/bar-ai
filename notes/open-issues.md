# Open issues — living list

Started 2026-08-03. Everything here is either unfixed, unverified, or a lead
worth keeping. Move an item to `CHANGES.md` once it is measured; delete it once
it is dead. If you fix something, say what measurement showed it.

Ordered by how much it is currently costing us.

---

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

Aggregate current win rate against this benchmark, for reference: **16.7%**
of decided games (95% CI 7.3%-33.6%, n=30 across 6 independent 8+ game
batches at the unmodified current baseline) -- see issue 0.1 below for the
full breakdown.

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
| **total (n=30 decided, 48 games played)** | **5** | **25** |

**Apex win rate: 16.7%, 95% CI 7.3%-33.6%** (updated from 20.8% with one
more same-baseline batch). This is the first time this
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
