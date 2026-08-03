# Overnight tournament rounds — 2026-08-03

All rounds: Comet Catcher, 4v4, +25% handicap, 40 min cap, 16 games, 4 workers,
Cortex vs Cortex, `BARbApex:apex:hard_aggressive` vs `BARb:stable:hard_aggressive`.
Identical settings every round, so rounds are comparable to each other.

**Read composition, not the scoreboard.** At 16 games a 60% win rate has a 95%
CI of roughly 36-80% — it cannot distinguish a real effect from a coin flip.
Category shares repeat every game and can.

---

## Round 1 — baseline for commit 5ef3d8c

Head to head: **apex 9 - 6** (15 decided, 1 undecided). 60%, CI 36-80%,
**not distinguishable from a coin flip**.

Wiped out: apex 14/64 player-games, stable 16/64.

### Where the metal went

| category | stable | apex |
|---|---|---|
| factories | 6.0% | 6.5% |
| **static defence** | **7.0%** | **21.0%** |
| constructors | 7.2% | 7.1% |
| **army (real)** | **26.8%** | **17.0%** |
| army (cheap) | 1.6% | 0.7% |

### Economy reach (mean per player)

| metric | stable | apex |
|---|---|---|
| metal produced | 82,369 | 67,815 |
| T1 spend | 22,490 | **30,853** |
| T2 spend | **43,339** | 31,486 |
| T3 spend | **9,634** | **1,303** |
| mex upgrades | 6 | 6 |
| cons T1 | 16 | **21** |
| cons T2 | **7** | 4 |
| energy wasted | 67,817 | 22,522 |

### Top sinks

- **stable**: `corafus` 11.3%, `corkorg` 11.2%, `corfus` 9.8%, `corsumo` 6.2%
- **apex**: `correap` 18.1%, `cornanotc` 14.6%, `cordoom` 8.4%, `coradvsol` 8.2%

### Reading

Stable buys **fusion and T3**. Apex buys **nano turrets, doom towers and
advanced solars**, stays on T1 longer (T1 spend 30,853 vs 22,490), and arrives
at T2 with fewer advanced constructors (4 vs 7).

Three divergences, largest first:

1. **Static defence 21% vs 7%** — 14 points. The single biggest gap, and the
   one apexearth has reported repeatedly all session ("wasteful defense and then
   we have less army and are losing the overall fight").
2. **Army 17% vs 27%** — the mirror image of the above.
3. **Energy: `coradvsol` 8.2% vs stable's fusion 21%.** Apex substitutes
   advanced solars for fusions. Apex also wastes far LESS energy (22,522 vs
   67,817), which is not obviously good here — it suggests apex is
   energy-poor rather than efficient.

Checked and ruled out as apex additions:

- **Nano turrets are not ours.** Stock `hard_aggressive` has 68 `nanotc` entries
  at `"priority": "now"` with **no condition**; ours has 72 but adds `m_inc>`
  gates. We build them *later* than stock, not more. The 14.6% share reflects a
  smaller denominator, not extra nanos.
- `cordoom` **is** partly ours: 4 entries in our `build_chain` against stock's 2,
  on top of our own `Pulsar()` rule in `builder.as`.

---

## Round 2 — PULSAR_MAX 2 -> 1

One change. `cordoom` is ~4000 metal each and was capped at 2 per player, the
largest single identifiable piece of our static-defence overspend at 8.4%.

Expectation: static defence share falls by roughly 4 points, army share rises.
If defence stays near 21%, the overspend is mostly the porcupine towers and the
`build_chain` `cordoom` hubs rather than the `Pulsar()` rule, and the next change
targets those instead.

### Result — prediction confirmed on composition

Head to head: apex 5 - 8. 61.5% to stable, CI 36-82%, **not distinguishable
from a coin flip** — do not read the flip from round 1 as an effect.

| | round 1 | round 2 |
|---|---|---|
| static defence | 21.0% | **15.5%** |
| army (real) | 17.0% | **21.0%** |
| `cordoom` share | 8.4% | **gone from top 12** |
| `corafus` share | 6.8% | **12.3%** |

Defence fell 5.5 points, army rose 4, and the freed metal visibly went into
fusion. The mechanism is confirmed.

**But wipe-outs rose: apex 14/64 player-games -> 19/64** (stable 16 -> 12). That
is a 64-sample statistic, not a 16-game one, so it carries more weight than the
head-to-head. Static defence was doing real work; this was a trade, not the
removal of pure waste. **Do not cut defence further on the strength of the army
share alone.**

### What round 2 exposed

With defence no longer dominating, the tech gap is the largest remaining
divergence and it is concentrated:

| metric | stable | apex |
|---|---|---|
| T2 spend | 44,060 | 28,451 |
| **cons T2** | **8** | **3** |
| T3 spend | 8,186 | 2,378 |
| T1 spend | 22,412 | 29,861 |

Checked and ruled out:

- **Not the advanced factory ratios.** Both sides are Cortex, and `coravp` is
  byte-identical between our config and stock: `correap` 0.61, constructors not
  in the top five. Armada's `armavp` leads with `armacv` at 0.55 — an upstream
  faction asymmetry, but it applies to both sides equally here.
- **Not runaway metal pooling.** `UpdateSling` already stops on
  `LeadHasPlant`, on `LeadIsSaturated`, once the giver has its own advanced
  constructor, and at `RUSH_GIVEUP`.

---

## Round 3 — advanced constructors scale with income

`factory.as` forced advanced-constructor production only while
`!Builder::gHaveAdvCon`, and the comment stated the intent outright: "a player
that already has one should not build a second." Since `coravp` gives
constructors ~1% by ratio, whatever this rule does not force is not built at
all — hence 3 per player against stock's 8.

Now `Builder::NeedsAdvCon()`: target `1 + income/25`, capped at 4, counted in
`AiUnitFinished` **after** the `ShareAdvCon` check (the lead gifts its extras,
and those are not ours) and decremented in `AiUnitRemoved`.

Expectation: cons T2 rises toward 5-6, T2 spend rises, T1 spend falls. Risk to
watch: advanced constructors are 330-700 metal each and cost build power, so if
metal produced drops this is the "every rule that spends displaces something"
trap again and it should be reverted rather than tuned.

### Result — FAILED, REVERTED

Head to head: apex 6 - 7 (CI 29-77%, coin flip).

| | round 2 | round 3 |
|---|---|---|
| cons T2 | 3 | **4** (target was 5-6) |
| T2 spend | 28,451 | 29,055 |
| T1 spend | 29,861 | **31,235** |
| **army (real)** | **21.0%** | **15.5%** |
| static defence | 15.5% | **18.0%** |
| constructors | 7.1% | 8.0% |
| factories | 6.3% | 7.8% |
| metal produced | 63,723 | 67,857 |

It barely moved the thing it targeted (3 -> 4 advanced constructors) and cost
5.5 points of army share. Army in absolute terms fell from ~12,700 to ~9,700
even though metal produced rose.

**Why**: more constructors means more of everything constructors do, and the
custom defence rules run ahead of `DefaultMakeTask`. Static defence climbed 2.5
points with `PULSAR_MAX` still at 1. Adding build power to this AI adds defence
spending, not economy — the same shape as the twelve-changes session.

My pre-stated revert criterion ("revert if metal produced drops") was **wrong**:
metal rose while army fell. Absolute army, not metal produced, was the right
tripwire. Reverted to `!Builder::gHaveAdvCon`. `NeedsAdvCon()`/`gAdvConCount`
are left in `builder.as` unused-but-harmless; delete if they are still unused
next session.

---

## Round 4 — REPEAT of round 2, no change

Not a new experiment. Round 2's exact configuration, re-run.

Army share moved 17.0 -> 21.0 -> 15.5 across three rounds and each move was
attributed to that round's change. That reasoning assumes composition metrics
are stable between identical runs, which has **never been measured here** —
whereas single-game metal was measured the same day at ~50% run-to-run swing.

If round 4 reproduces round 2 (defence ~15.5%, army ~21%), composition at 64
player-games is trustworthy and the round 1->2 and 2->3 readings stand. If it
lands near round 3 instead, then round-to-round drift is as large as the effects
being chased, and **every composition conclusion in this file needs re-testing
with repeats rather than single rounds.**

### Result — it landed near round 3. Army share is NOT trustworthy.

| metric | R2 | R3 (a change) | R4 (no change, = R2) |
|---|---|---|---|
| **army (real)** | **21.0%** | 15.5% | **15.7%** |
| static defence | 15.5% | 18.0% | 16.4% |
| T2 spend | 28,451 | 29,055 | **28,412** |
| cons T2 | 3 | 4 | **3** |
| metal produced | 63,723 | 67,857 | 67,984 |
| wiped out (apex) | 19/64 | 20/64 | 22/64 |

**Army share swung 5.3 points between two runs of identical code** — the same
size as the move I attributed to round 3's change. Round 3's "failure" is
therefore NOT established, and the revert was made on noise. The revert itself
is harmless (it restores the long-standing behaviour), but the reasoning was
wrong and must not be cited as evidence against advanced constructors.

### Which metrics survive a repeat

**Trustworthy at 16 games / 64 player-games** — near-identical across R2 and R4:

- T2 spend (28,451 vs 28,412)
- cons T2 (3 vs 3)
- static defence share (15.5 vs 16.4, and both far below R1's 21.0 — so the
  `PULSAR_MAX` cut is a REAL, PERSISTENT effect)

**Not trustworthy at this sample** — moves 5+ points between identical runs:

- army share, metal produced, wipe-out counts, head-to-head

Head to head across all four rounds: 9-6, 5-8, 6-7, 7-7. Every CI includes 50%.
**Sixteen games cannot decide anything here.** Round 5 onward uses 32.

### The gaps that hold across ALL FOUR rounds

These are consistent enough to act on, unlike anything above:

| metric | stable | apex |
|---|---|---|
| metal produced | 81,269 - 96,575 | **63,723 - 67,984** |
| T2 spend | 43,339 - 55,424 | **28,412 - 29,055** |
| cons T2 | 7 - 10 | **3 - 4** |
| T3 spend | 7,487 - 9,634 | **720 - 2,378** |
| static defence | 7.0 - 8.1% | **15.5 - 21.0%** |
| mex upgrades | 6 - 9 | **5 - 6** |

apex produces ~30% less metal, spends about half as much on T2, fields a third
of the advanced constructors, and puts roughly twice the share into static
defence. Those four are the real problems; everything argued about in rounds
1-4 was smaller than the noise except the defence share.

---

## Round 5 — PORC_ADD_CAP 4 -> 2, at 32 games

Defence share is the one gap that is both large and reliably measurable, and
`PULSAR_MAX` already showed it responds to a cut and stays cut. This halves the
front-line tower additions instead.

Deliberately NOT reverting `land[0]` to the basic laser tower: apexearth's
reasoning for the mid tower (an LLT at range 435 cannot answer a rocket bot at
475, so it dies without firing) is about unit matchups and holds regardless of
this benchmark. Fewer strong towers respects that; cheaper weak ones contradict
it.

Expectation: defence share falls toward 12-13%. Judge on defence share and T2
spend. **Do not judge on army share, metal produced, or the head-to-head** —
round 4 established those move this much on their own.

### Result — NO EFFECT, and that is the useful part

32 games, 256 player-games. Head to head 13 - 16 (CI 38-72%, coin flip).

| | R4 (cap 4) | R5 (cap 2) |
|---|---|---|
| static defence | 16.4% | **16.8%** |
| T2 spend | 28,412 | 27,574 |
| cons T2 | 3 | 4 |

Halving our own front-line tower rule moved defence share by 0.4 points — inside
the repeat noise. **Our `UpdateBaseDefence` additions are not where the defence
metal goes.** That eliminates a suspect that had been assumed since the rule was
written.

By elimination the spend is `aiMilitaryMgr.DefaultMakeDefence`, which our
`AiMakeDefence` calls once per cluster. That places a tower on every defence
point of every approved cluster, and on a 16x12 map almost every cluster reads
as `NearFront`, so the gate approved essentially the whole map.

`PORC_ADD_CAP` is left at 2. It has no measured effect either way, and fewer
front towers is the intended direction.

---

## Round 6 — cluster defence requires an actual enemy army

`AiMakeDefence` gated REAR clusters on threat but approved any `onLine` cluster
unconditionally. On a small map that is all of them.

Added: `if (!gPorcArmed && !gTurtle && !LosingGround() && !early) return;` — so
even a front cluster needs the enemy to hold an army worth walling against,
using the same `gPorcArmed` hysteresis the rest of the file uses rather than a
new threshold.

Expectation: defence share falls below 13%. This is the last identified lever on
defence spend; if it does not move it either, the remaining spend is the
`build_chain` porcupine hubs and `cordoom` entries, and those are config rather
than script.

Judge on defence share and T2 spend only.

### Result — best round so far, but for a reason I cannot yet explain

32 games. Head to head **apex 16 - 13** (still CI 38-72%, still a coin flip).

| | R5 | **R6** | stable R6 |
|---|---|---|---|
| **T2 spend** | 27,574 | **36,812** | 43,482 |
| cons T2 | 4 | **5** | 8 |
| metal produced | 63,939 | **76,928** | 79,443 |
| T1 spend | 31,498 | 32,841 | 22,553 |
| static defence | 16.8% | **17.8%** | 7.3% |
| army (real) | 18.0% | 19.7% | 24.8% |
| wiped out (apex) | 38/128 | **32/128** | 39/128 |

**T2 spend rose 33% on a metric that had been stable at 27,574-29,055 across
four rounds**, including the identical-code repeat in round 4. That is the
largest move on a trustworthy metric all night. Metal produced closed from ~30%
behind stable to within 3%. Apex was wiped out less often than stable for the
first time.

**The stated prediction still failed: defence share did NOT fall** (16.8% ->
17.8%, and in absolute terms it rose, ~10,200 -> ~12,800 metal). So the change
helped through some path other than the one intended, and the mechanism is
currently unknown. Candidate: the gate defers cluster defence in the first
minutes before `gPorcArmed` latches, and early build power is worth far more
than late build power — but `early` is supposed to exempt exactly that window,
so this does not yet add up.

**Do not write the mechanism into a comment until it is understood.** Round 7
repeats this configuration unchanged to establish whether the gain is real
before anything is built on top of it.

---

## Round 7 — REPEAT of round 6, no change

Applying round 4's lesson: the largest apparent gain of the night is confirmed
with a repeat before it is believed or extended.

If T2 spend lands near 36,000 again, the effect is real and the next question is
*why*, since the intended mechanism demonstrably did not fire. If it falls back
to ~28,000, then T2 spend is not as stable as rounds 2-5 suggested and the
metric list in round 4 needs revising too.

### Result — NOT reproduced. Round 6 was noise.

| | R6 | R7 (identical code) |
|---|---|---|
| T2 spend | 36,812 | **23,515** |
| cons T2 | 5 | **3** |
| metal produced | 76,928 | **57,542** |
| head to head | 16 - 13 | **11 - 19** |
| wiped out (apex) | 32/128 | **47/128** |

T2 spend swung **36% between two runs of identical code at 32 games each**. The
round 4 conclusion that T2 spend was trustworthy is withdrawn — rounds 2-5
happening to land within 28,412-29,055 was luck.

---

# CONCLUSION OF THE OVERNIGHT RUN

## The benchmark cannot resolve the changes being made

Seven tournaments, 176 games. Two pairs of identical-code runs were included as
controls, and both moved further than any change did:

| identical-code pair | metric | run A | run B |
|---|---|---|---|
| R2 / R4 (16 games each) | army share | 21.0% | 15.7% |
| R6 / R7 (32 games each) | T2 spend | 36,812 | 23,515 |
| R6 / R7 | head to head | 16-13 | 11-19 |

Head to head across all seven rounds: 9-6, 5-8, 6-7, 7-7, 13-16, 16-13, 11-19.
**Every confidence interval includes 50%.** Going from 16 to 32 games did not
help enough to matter.

Stop A/B-ing single changes here. What works instead, demonstrated repeatedly on
2026-08-02/03: apexearth watches a game and names the broken behaviour, the
mechanism is then found by reading the code, and the fix is verified by
confirming the mechanism changed — not by a win rate. Every real defect found in
this session came that way (the squared-distance bug in the strength check, the
1000-elmo join radius, the flat AA cap, cloak latched on forever, the commander
retreating to the base centre).

## What IS established, because it holds in all seven rounds

Directions, not magnitudes:

| metric | stable (range) | apex (range) |
|---|---|---|
| static defence | 7.0 - 8.4% | **15.5 - 21.0%** |
| T2 spend | 43,339 - 55,424 | **23,515 - 36,812** |
| cons T2 | 7 - 10 | **3 - 5** |
| T3 spend | 6,313 - 9,634 | **720 - 2,378** |
| T1 spend | 22,412 - 24,945 | **29,946 - 32,841** |
| mex upgrades | 7 - 9 | **5 - 6** |

Apex never once beat stable on any of these, in any round. That consistency is
the evidence — not the size of any single gap.

**One story fits all six**: build power goes into static defence at roughly twice
stock's share, the AI stays on T1 longer, reaches T2 with a third of the
advanced constructors, and therefore never converts to T2/T3 economy. Stock puts
the same metal into fusion and T3.

## Changes left in the tree from this run

- `PULSAR_MAX` 2 -> 1. Defence share was 21.0% before and 15.5-18.0% in all six
  rounds after, so probably real but smaller than round 2 suggested.
- `PORC_ADD_CAP` 4 -> 2. **No measured effect** (16.4 -> 16.8). Kept because
  fewer front towers is the intended direction, not because it was shown to help.
- Cluster defence requires `gPorcArmed || gTurtle || LosingGround() || early`.
  **No measured effect on defence share** (16.8 -> 17.8 -> 16.8). Kept because
  walling a cluster with no enemy army present is wrong on its face.

Reverted: `NeedsAdvCon()` scaling (round 3) — and note the revert was made on a
metric later shown to be noise, so advanced-constructor scaling is **untested**,
not disproven. `NeedsAdvCon()`/`gAdvConCount` remain in `builder.as`, unused.

## What to do next

1. **Do not chase the defence share with more tournaments.** Two suspects were
   eliminated by measurement (our front-tower rule, our cluster gate). The
   remaining spend is `DefaultMakeDefence`'s per-defence-point placement and the
   `build_chain` porcupine/`cordoom` hubs. Reading `mDefence` per unit type in a
   single watched game would identify it in minutes; a tournament will not.
2. **The T1 -> T2 conversion is the real gap** and it is worth a watched game:
   why does a player with T2 build 3 advanced constructors while stock builds 8?
3. apexearth's idea, still unbuilt: let a unit be assigned to a distant squad and
   walk to it, instead of the hard 3000-elmo `CanAssignTo` cutoff. This is the
   generalisation of the join-radius fix that measurably doubled squad size.
