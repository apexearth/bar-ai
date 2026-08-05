# Benchmark results — apex vs stock BARb

A running ledger of tournament results tied to the exact commit tested, so
"how good is the current code" is answerable without re-deriving it from
`tournaments/`. Every row here is `BARbApex:apex:hard_aggressive` vs
`BARb:stable:hard_aggressive`, Comet Catcher 4v4, +25% handicap both sides,
unless the row says otherwise. **Games** is decided games only (ties/timeouts
excluded from the win% denominator, per the tool's own convention).

**Clean** = run alone, no concurrent `run_tournament.py` process (see
`notes/open-issues.md` #37 — concurrent runs corrupt each other's results via
a shared write-dir; fixed in commit `e05fabe`, but every run before that fix
needs the "solo?" column checked before trusting it).

**Read this table with `notes/open-issues.md` #45–47 in hand**: this
benchmark's noise floor is wide — repeat runs of *identical* code have swung
12–19 points on both Armada and Legion. A single row is not a confirmed
result. Only trust a claim once multiple independent rows on the same commit
agree, and check whether anyone actually did that pooling (search
`open-issues.md` for the tournament name).

## Current HEAD state (as of `b9fad08`, 2026-08-05)

| faction | rows available | picture |
|---|---|---|
| **Cortex** | 4 clean batches, 75–88% each | reference faction; only one this session with a large, repeated, trustworthy margin over 50% |
| **Armada** | 6 clean batches on the fully-fixed code (n=160 pooled), 57.3–81.2% | `build_speed` fixes (armlab/armvp/armnanotct2) are real, traced mechanisms, kept deployed — but **definitively show no win-rate or combat-outcome effect** once a 96-game batch gave this real power (pooled post-fix 64.4% vs pre-fix 65.6%, z=-0.13; see `open-issues.md` #51). Do not cite the early 75–81% reads as representative. |
| **Legion** | 7 clean batches (n=128 pooled baseline) | **DEFINITIVE: ~25.8% win rate (z=-3.99, p<0.0001), significantly below 50% and below both other factions.** All 4 fixes tried this session (constructor weights, `T1_FAC`, `legvflak` role tag, `leggant` build_speed) failed to move this number; current code == original pre-session baseline. Best lead for next session: damage-ratio/game-length analysis (`open-issues.md` #48–49). |

## Cortex, Cortex — reference faction

| date | tournament | commit | games | result | win% | solo? | notes |
|---|---|---|---|---|---|---|---|
| 2026-08-04 | `factorycap-16` | (pre-session, see summary) | 16 | 11-0 | 100% | ? | cited in prior-session summary, not independently re-verified this session |
| 2026-08-04 | `factorycap-confirm-16` | (pre-session) | 16 | 9-0 | 100% | ? | ″ |
| 2026-08-04 | `racefix-t2con-16` | (pre-session, ~d20592b) | 16 | 6-1 | 85.7% | ? | ″ |
| 2026-08-04 | `corck-revert-confirm-8` | `1984ecc` | 8 | 5-2 | 71.4% | **NO** | half of a corrupted concurrent pair (with `armada-mirror-armck-8`) — do not trust the exact number, direction is consistent with other Cortex rows |
| 2026-08-05 | `cortex-clean-reconfirm-16` | ~`420864f` state | 16 | 12-4 | **75.0%** | **yes** | CI 51–90%, excludes 50% |

## Armada, Armada

| date | tournament | commit | games | result | win% | solo? | notes |
|---|---|---|---|---|---|---|---|
| 2026-08-04 | `armada-mirror-armck-8` | `1984ecc` | 8 | 4-4 | 50% | **NO** | corrupted pair |
| 2026-08-05 | `armada-t2con-16` | `d2f147a` | 16 | 9-6 | 60% | **NO** | corrupted pair (with `legion-t2con-16`) |
| 2026-08-05 | `armada-armaca-fix-16` | `970f62d` | 16 | 7-7 | 50% | **NO** | corrupted pair |
| 2026-08-05 | `armada-armaca-clean-16` | `970f62d` | 16 | 10-6 | **62.5%** | **yes** | this session's clean Armada baseline reference |
| 2026-08-05 | `armada-support-attr-16` | `09ba614` | 16 | 10-6 | 62.5% | **yes** | identical to baseline — `support` attribute fix is neutral |
| 2026-08-05 | `armada-buildspeed-16` | `5fe2254` | 16 | 13-3 | 81.2% | **yes** | +`armlab` build_speed fix only |
| 2026-08-05 | `armada-buildspeed-vp-16` | `d80220c` | 16 | 12-4 | 75.0% | **yes** | +`armvp` build_speed fix (cumulative w/ armlab) |
| 2026-08-05 | `armada-buildspeed-nano-16` | `de1cc99` | 16 | 13-3 | 81.2% | **yes** | +`armnanotct2` build_speed fix (all 3 fixes, "final" state) |
| 2026-08-05 | `armada-buildspeed-stability-check-16` | `de1cc99` (re-run, no changes) | 16 | 10-6 | 62.5% | **yes** | same code as the row above — 18.7pp swing with zero changes |
| 2026-08-05 | `armada-prefix-baseline2-16` | `09ba614` (build_speed reverted back to pre-fix for this test) | 16 | 11-5 | 68.8% | **yes** | second independent pre-fix read |
| 2026-08-05 | `armada-buildspeed-postfix-large96` | `de1cc99` (full 3-fix state) | **96** | 55-41 | **57.3%** | **yes** | large batch — CI 47-67%, includes 50%; damage ratio 0.996, fraction-favorable exactly 50% |

**DEFINITIVE, see `open-issues.md` #51**: pooling ALL post-fix batches
(5 batches, n=160) vs both pre-fix batches (n=32): win rate 64.4% vs
65.6% (z=-0.13); fraction-favorable 58.1% vs 56.3% (z=-0.20). **Both
essentially zero difference.** The four smaller post-fix batches that
looked promising (81.2/75.0/81.2/62.5%) were a run of favorable draws,
not a real effect — the single 96-game batch alone outweighs all four of
them combined and reads close to a coin flip. **The `build_speed` fix is
kept deployed (real, correctly-traced mechanism, not harmful) but is NOT
a confirmed win-rate improvement.** Do not cite the earlier 75-81% numbers
as representative without this context.

## Legion, Legion

| date | tournament | commit | games | result | win% | solo? | notes |
|---|---|---|---|---|---|---|---|
| 2026-08-05 | `legion-t2con-16` | `d2f147a` | 16 | 7-8 | 43.8% | **NO** | corrupted pair |
| 2026-08-05 | `legion-bomber-fix-16` | `57cbadd` | 16 | 5-11 | 31.2% | **yes** | `legkam`→`legmos` swap — reverted (stockpile weapon issue) |
| 2026-08-05 | `legion-bomber-revert-confirm-16` | `56aff15` | 16 | 4-10 | 25.0% | **NO** | corrupted pair (with `armada-armaca-fix-16`) |
| 2026-08-05 | `legion-bomber-revert-clean-16` | `56aff15` | 16 | 5-10 | 31.2% | **yes** | clean re-run of the revert |
| 2026-08-05 | `legion-pre-issue35-baseline-16` | `1984ecc` state | 16 | 7-9 | 43.8% | **yes** | true pre-issue-35 baseline (temp checkout) |
| 2026-08-05 | `legion-t1fac-only-16` | `b02916f` | 16 | 2-14 | 12.5% | **yes** | `T1_FAC`/`T2_FAC` alone — CI excludes 50% |
| 2026-08-05 | `legion-vflak-role-16` | `6e41b6e` | 16 | 4-12 | 25.0% | **yes** | `legvflak` anti_air tag — CI excludes 50% |
| 2026-08-05 | `legion-gant-buildspeed-16` | `d373de1` | 16 | 3-13 | 18.8% | **yes** | `leggant` build_speed — CI excludes 50%, worst single read |
| 2026-08-05 | `legion-baseline-stability-check-16` | `0fabb8f` state (baseline, unchanged) | 16 | 5-11 | 31.2% | **yes** | re-run of the SAME baseline code as `legion-pre-issue35-baseline-16` — 12.6pp swing, zero changes |
| 2026-08-05 | `legion-t1fac-retest-16` | `04aaeb4` (T1_FAC re-added) | 16 | 6-10 | 37.5% | **yes** | second independent T1_FAC read |
| 2026-08-05 | `legion-baseline-large96` | current HEAD (baseline, unchanged) | **96** | 21-75 | **21.9%** | **yes** | large batch — CI 15-31% (i.e. stable 69-85%), **excludes 50%: a real, significant result on its own** |

**Pooled T1_FAC** (two identical-fix runs): (2+6)/32 = 25%. z = -1.08 vs
the small-batch baseline, **not significant** — closes that investigation
with no confirmed effect either direction. `legvflak` and `leggant` were
each only read once; not pooled. See `open-issues.md` #45, #47.

**DEFINITIVE baseline, see `open-issues.md` #52**: pooling all THREE
baseline reads (both 16-game batches + the 96-game one): 33/128 = **25.8%**,
z=-3.99 vs 50% (p<0.0001). **This is Legion's real win rate against stock
BARb on this benchmark** — genuinely, significantly below 50%, not an
artifact of small-sample noise the way it looked mid-session. Every
earlier noisy 16-game read (43.8%, 31.2%) was a real draw from this same
~26% distribution, not evidence of instability.

| date | tournament | commit | games | result | win% | solo? | notes |
|---|---|---|---|---|---|---|---|
| 2026-08-05 | `legion-squadspeed-fix-large96` | `455d1b4` (C++ `SQUAD_SPEED_RATIO` 2.5->3.5) | **96** | 25-70 | 26.0% | **yes** | z=0.09 vs pooled baseline — no effect |
| 2026-08-05 | `legion-hovercraft-fix-large96` | `bfe5f91` (+`legehovertank`/`leghp` config fixes, no `CheapAA` yet) | 79 decided | 14-65 | **17.7%** | **yes** | CI 72-89% for stable, excludes 50%. NOT isolated from `SQUAD_SPEED_RATIO` — z vs squadspeed-only run = -1.35, not significant alone. Ran in the background past the point apexearth said to stop watching it; real data, flagged not overclaimed. See `open-issues.md` #55. |
| 2026-08-05 | `legion-cheapaa-carveout-8` | `a8fbfe3` (+`CheapAA` phase-gate carve-out, issue 54) | 8 | 5-3 | 62.5% | **yes** | **MISLABELED — actually Cortex vs Cortex** (forgot `--sides Legion,Legion`; `run_tournament.py` defaults to alternating Armada/Cortex). Not a valid read on anything Legion. `enemyAir(cost)=0.0` for all 8 games confirms the benchmark-opponent-never-builds-air gotcha, but on Cortex, not Legion. See `open-issues.md` #55–56. |

**Nothing tried this session moved this number, with the AA fix's status
still open.** Five real, mostly well-evidenced win-rate attempts, all
resolved to "no confirmed win-rate effect" once properly powered:
constructor weight bundle, `T1_FAC`/`T2_FAC`, `legvflak` role tag,
`leggant` build_speed, and `SQUAD_SPEED_RATIO` (a C++ fix verified against
real cross-faction unit-speed data). `legehovertank`/`leghp` (hovercraft
units getting built on land maps with no water) are correctness fixes
independent of the win-rate question, deployed from apexearth live-
watching two games — but the one large-sample read available for that
code state (17.7%, bundled with `SQUAD_SPEED_RATIO`) trends the worst of
any Legion result this session and is not yet isolated or explained.
`CheapAA`'s phase-gate fix (issue 54) is a confirmed-correct mechanism —
verified by direct log inspection that it now fires pre-T2 — but this
benchmark's opponent doesn't build air in this matchup, so it cannot be
win-rate tested here at all; needs a live-watched game or a different
benchmark opponent to confirm.

## Cross-faction (not directly comparable to the tables above)

| date | tournament | commit | matchup | games | result | win% | solo? | notes |
|---|---|---|---|---|---|---|---|
| 2026-08-04 | `armada-vs-cortex-8` | `d2f147a` | apex=Armada vs stock=Cortex | 8 | 2-6 | 25% | **NO** | conflates untested cross-faction asymmetry with the fix under test; not a clean read on anything |

## What's NOT in this table

`tournaments/` holds 100+ runs from 2026-08-01 through 2026-08-03 (investigating
phase gates, fusion concurrency, air strikes, eco-lead tuning, and more) that
predate this table and are not catalogued here. If a future session needs
one of those, `python tools/run_tournament.py --report <run-dir>` re-prints
its summary from `ledger.jsonl`; the corresponding commit can usually be
found by matching the run's timestamp against `git log --since=... --until=...`.
Consider backfilling the highest-value ones (anything CHANGES.md cites) if a
complete history is ever needed — this table's scope is deliberately just
"clean, commit-tied results from the 2026-08-05 session" for now.

## Maps

Every row above is **Comet Catcher (4v4, +25% handicap)** — this project's
standard benchmark map (see `bar-ai-map-selection` memory: reclaim/water/
asymmetric maps are not valid data here; Comet Catcher is deliberately the
only one used for faction-comparison work). No other map has been tested
against any of the commits in this table.
