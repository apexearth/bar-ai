# Next session — hypotheses and test plan

Written 2026-08-04, at the end of a session that took the measured win rate
against `BARb:stable:hard_aggressive` on Comet Catcher 4v4 (+25% handicap,
Cortex) from a 7.9% baseline to a 40-50% band via `Factory::gLastPhase >= 4`
plus four live-diagnosed bug fixes (three of which turned out to need
gating back off the 4v4 benchmark — see `notes/open-issues.md` issue 15 for
the full trail). Batch-grinding the same code state hit diminishing returns
(six 16-32 game batches all landing in wide, overlapping, 50%-including
CIs). This file is the next set of concrete, testable ideas, in priority
order, each with the evidence behind it and how to test it.

Follow the same discipline used all last session: one change at a time,
`python tools/check.py` + a headless smoke test + an infolog compile-error
grep before every deploy, a control batch alongside every test, and log
results here or in `notes/open-issues.md` as they come in — not just a
verdict, the numbers.

---

## 0. Do this first: watch a live Comet Catcher 4v4, not another 8v8

**Every live-diagnosed bug this session came from watching 8v8 games**
(Ancient Bastion, Supreme Isthmus, Pinch Point). Three of the four fixes
that came out of those watches had to be walked back specifically because
they didn't transfer to 4v4 — they were new unconditional spend the 4v4
economy couldn't afford. Nobody has watched a live Comet Catcher 4v4 game
this entire session. Every diagnosis on the actual target map has come
from aggregate statistics, never from seeing what's actually happening.

This is the highest-value single action available: a 5-minute windowed
watch of exactly the benchmark configuration the goal is measured on
(`--map "Comet Catcher" --per-side 4 --sides Cortex,Cortex --handicap 25
--watch --speed 5`) would very likely surface something composition.py
can't show directly — a stuck constructor, a bad factory choice, a fight
lost to bad micro, a wasted opening. Per this project's own established
finding: "apexearth is faster than the benchmark — ask him first," and
every mechanism that actually moved the win rate this session (the
commander back-wall fix, BUILD_PHASE itself) traces back to a live
observation, not a statistics-only diagnosis.

**Action**: launch a windowed Comet Catcher 4v4 watch and see what's
actually happening before writing more code from composition tables alone.

---

## 1. Rez-bot metal spend roughly doubled after this session's own fix — investigate before trusting it

**Evidence** (from `tools/composition.py`, TOP METAL SINKS, cornecro =
`cornecro`/rez bot):

| batch | code state | cornecro share of total metal | apex wipeout rate |
|---|---|---|---|
| `phasegate4-extend3-16` | before this session's 4 bug fixes | 8.8% (#3 sink) | 9/124 = 7.3% |
| `gated-big-32` | after `6efc955`+`872473c` | 14.5% (#3 sink) | 45/128 = 35.2% |
| `isolate-latefighter-16` | after `9a1b249` too | 14.1% (#3 sink) | 11/64 = 17.2% |
| `isolate-latefighter2-16` | same | 16.2% (#2 sink) | 25/64 = 39.1% |

Two other economy/passive sinks also grew over the same comparison
(`coradvsol` 8.8%→17%, `cornanotc` 10.4%→14-16%), and **T2 spend roughly
halved** (apex ~16-17k pre-fix vs ~11-13k post-fix, against stable's
consistent ~24-31k) while **metal produced fell** (~43k pre-fix vs
~35-41k post-fix). Wipeout rate roughly quadrupled on average (7.3% →
~31% average of the three post-fix batches).

**The only one of this session's four bug fixes still active,
unconditionally, on a 4v4** is the rez-bot flee-on-hit fix
(`builder.as`, `IsRezzer(unit)` branch) — the other three
(`earlyReaction`, `stalled`, `HoldsLateFighter`) are now all gated to
`!IsSmallTeam()`. This is circumstantial, not proven: the wipeout-rate
increase could equally be a symptom of losing more (a collapsing economy
buys cheap passive stuff and dies before the payoff) rather than a cause.
But cornecro's share nearly doubling specifically, on a fix that changes
exactly how rez bots behave, is a concrete lead worth testing directly
rather than living with.

**Hypotheses, in order of how cheap they are to test:**

- **H1a — the fix is too sensitive.** `gConHits[ConSlot(unit)] > 0` fires
  on a single hit (2% HP drop, `TROUBLE_HP_DROP`). A fled bot may abandon
  a resurrect it would have survived, wasting the partial investment and
  forcing a rebuild elsewhere. Test: raise the trigger to the same
  `TROUBLE_HITS` (3) the rest of `builder.as` already uses for "this is a
  sustained attack, not one stray shot" before treating it as fortify-
  or flee-worthy. One-line change, already scoped in code as a candidate
  during the live session but not tested in isolation.
- **H1b — fleeing bots aren't actually surviving.** `EnqueueRetreat()` is
  assumed safe to re-issue every tick (same assumption the commander
  retreat above it makes) but this was never directly measured for rez
  bots specifically. Test: log rez bot death events (`AiUnitRemoved` for
  `IsRezzer` units) for a batch with the fix on vs off and compare counts
  directly, rather than inferring survival from metal-sink share.
- **H1c — it's a symptom, not a cause.** Run a batch with the rez-bot fix
  fully reverted (temporarily) on the CURRENT code state (with the other
  three fixes still gated off 4v4) and compare wipeout rate and cornecro
  share against `gated-big-32`/`isolate-latefighter-16/2`. If wipeout
  rate and cornecro share both drop back toward the pre-fix baseline,
  that's strong evidence for H1a/H1b. If they don't move, the fix isn't
  the driver and the search moves elsewhere (commander survival, team
  asymmetry — see below).

**Recommended test order**: H1c first (isolates whether the fix matters
at all, one batch), then H1a if H1c implicates it (one line, one more
batch). Keep the log throttle either way — that part is uncontroversial.

---

## 2. `coradvsol` (advanced solar) is apex's #1 metal sink at 17% — check it isn't crowding out fusion

**Evidence**: across all three post-fix batches, `coradvsol` is
consistently the single largest metal sink (16.7-17.1% of everything
built), well above stable's 3.5-3.8% in the same games. `corfus` (fusion)
sits much lower for apex (4.8-9.0%) than for stable (14.8-16.4%) over the
same batches — the opposite ordering from stable, which spends more on
the metal-efficient fusion and less on solar.

**Hypothesis**: `EcoFusion()`/`EnergyConverter()`/the eco-lead's energy
build order (all gated behind `Factory::gLastPhase >= 4`/`EcoLeadActive()`
in `builder.as`) may be picking advanced solar too readily relative to
transitioning to fusion, or fusion's own gate (`EcoFusion`'s income/energy
thresholds) may be set too conservatively for what a 25-minute 4v4 can
actually reach. Advanced solar is metal-cheap but energy-poor per metal
compared to fusion at this scale — over-indexing on it could be quietly
capping the whole team's energy-driven production (converters, nanos,
labs) below what fusion would allow in the same game length.

**Test**: read `EcoFusion()`'s actual gate conditions in `builder.as`
(same investigation style as `docs/12-build-phases.md`'s existing
build_chain findings — log every input once every 30s the way
`conbranch` already does for the advanced-con branch), run one batch, and
check whether the gate is even being reached before the 25-minute cap in
a normal-paced 4v4 game, or whether the eco lead is simply choosing solar
every time it's offered because nothing ever un-picks it once built.

---

## 3. Re-check commander survival correlation with this session's actual data

**Existing finding** (memory, prior session): "commander survival
predicts the winner" in this AI's games — established previously but not
re-verified against this session's specific batches. `commLost` is
already a published stat in the periodic `[BARAI_STATS]` blob
(`ai/apex/.../misc/commander.as`-adjacent gadget). A quick ad-hoc check
this session hit a parsing bug (team-id collisions when deduping periodic
samples across a whole ledger) and was discarded rather than trusted —
this needs a properly written check, not a repeat of that mistake.

**Test**: write a small, careful script (or extend `composition.py`) that
reads `commLost` from the LAST periodic sample **per player-game**
(keyed on `(match, team)`, not just `team`, since team ids repeat across
matches in one ledger file) for a couple of the batches already collected
this session, and correlate commander loss with game outcome and with
wipeout rate. If apex's commander is dying earlier/more often than
stable's in the same batches, that's a second, independent lever
(`COM_RETREAT_HEALTH`, `COMM_BACK_WALL_ON` tuning) worth revisiting on
fresh data rather than the numbers those constants were originally tuned
against.

---

## 4. Team-0 vs team-1 positional asymmetry — still flagged, still unconfirmed

**Existing finding** (`notes/open-issues.md` issue 14, prior session): a
suggestive ~3x split in outcomes by which team-id slot a side draws,
z=1.48 (not significant), confirmed to point the SAME direction for both
AIs (so it reads as a map/box asymmetry, not an apex-specific bug) but
never resolved. If real, this adds pure noise to every batch's CI without
being a property of either AI — which would help explain why six batches
in a row this session landed in wide, overlapping CIs even holding code
constant.

**Test**: pool team-0-vs-team-1 head-to-head splits across ALL of this
session's Comet Catcher batches (there are now well over a dozen, several
hundred games total) for a much larger sample than the z=1.48 check had
access to. If it resolves to something real and significant at this much
larger n, that's worth fixing at the harness level (forcing a fair
side-swap per pair, which `run_tournament.py` may already do — check
first) rather than the AI level, and would tighten every future batch's
CI for free.

---

## Priority order for next session

0. **STILL TOP PRIORITY, STILL NOT DONE: watch a live Comet Catcher
   4v4** (section 0). This requires a human at the keyboard and none of
   this round's agents could do it. Every mechanism that has actually
   moved the win rate this session traces back to a live watch, never to
   statistics alone — do this before writing more code from composition
   tables.
1. ~~**H1c**~~ — **DONE, 2026-08-04, commit `5610ad3`. Not confirmed**:
   reverting the rez-bot fix moved cornecro share and wipeout rate
   further from baseline, not back toward it. Do not pursue H1a/H1b
   (retuning the rez-bot trigger) on this basis. See
   `notes/open-issues.md` issue 17.
2. ~~Advanced solar / fusion gate investigation~~ — **DONE, 2026-08-04,
   commit `7ebfede`. Hypothesis as written was wrong**: the eco-lead
   script path (`EcoFusion`/`EcoNano`) is entirely unreachable on this
   4v4 benchmark (`IsSmallTeam()` gate), so its own thresholds cannot be
   the cause of anything measured here. Real, still-live cause is the
   already-known, already-reverted `economy.json` fusion e-income gate
   (`5613d7d`). **New, untried angle from this diagnosis**: investigate
   raising `CEconomyManager`'s energy-task concurrency (currently caps at
   one energy task in flight at a time) so a lower fusion gate doesn't
   re-create the starvation that caused `5613d7d`'s revert. This is now
   the most concrete untested lever on the table — needs its own
   isolated test with a control batch. See `notes/open-issues.md` issue
   18 for the full mechanism trail.
3. ~~Section 3 (commander survival)~~ — **DONE, 2026-08-04 (read-only,
   no commit). Not reproduced**: at n=128 player-games / 26 decided
   matches, losing the commander was not associated with a higher loss
   rate for either side. The bottleneck is that most matches hit the
   time limit before either commander dies (only 26/64 matches reached
   `gameover`) — a real re-check needs a benchmark that resolves more
   often, not more games at the current settings. See
   `notes/open-issues.md` issue 19.
4. ~~Section 4 (team asymmetry)~~ — **DONE, 2026-08-04 (read-only, no
   commit). Refuted at n=259**: z dropped from 1.48 (n=55) to -1.30
   (n=259) with 5x the data — the original "~3x split" does not
   replicate at scale. Closed; see `notes/open-issues.md` issue 14's
   update.

**Everything in sections 1-4 has now been checked and none of it
produced a code change that survived.** The single concrete next step
with anything left to test is the energy-task-concurrency angle named
under item 2 above. Do not launch another blind 16-game batch on
unchanged code hoping for a different answer — six of those in a row
earlier this session produced nothing but wide, overlapping confidence
intervals, and this round's four checks (also mostly negative results)
extend that pattern. Every batch from here should be attached to a
specific hypothesis, and item 0 (watch a live game) should happen before
starting the energy-task-concurrency work, not after.
