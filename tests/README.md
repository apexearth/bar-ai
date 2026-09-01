# End-to-end regression tests

    python tests/run_e2e.py            # the standard suite
    python tests/run_e2e.py --quick    # one scenario, for a fast sanity pass
    python tests/run_e2e.py --update   # re-record the floors from this run

Each scenario runs a real headless match and asserts against
`tests/baselines.json`. A failure names the check, what it saw, and what it
expected.

## What to assert on, and what NOT to — read this before adding a check

This suite exists because a whole class of bug in this AI is **silent**: the
thing did not work, the match still reported a normal result, and nobody knew
for hours. The fusion deadlock (2026-08-31) is the canonical case — two of
sixteen players lost *every* advanced fusion they ever started and finished the
game on a fourteenth of the field's energy income, and the only evidence was one
repeated line in a 33 MB infolog.

**The benchmark's noise floor makes performance assertions worthless.** Measured
2026-08-31: two batches of the *identical* configuration differed by +9.3% and
+13.3% mean `metalProduced`, sd ~20%, with the minute-18 interval excluding
zero. Resolving a 10% change needs ~60 paired games. So:

> **Never assert on a median, a win rate, or a tight band around an income.**
> A test that flakes is a test everybody learns to ignore, and then it protects
> nothing.

Assert instead on the three things that are structurally robust:

1. **Deadlock signatures.** "N of N tasks of one kind died, at one position" is
   not a statistical question. The fusion bug was 21-of-21 at a single spot; the
   fix took it to 5-of-64. No sample size needed to tell those apart.
2. **Zero-counts and dead paths.** "Zero sensors built all game", "zero fusions
   finished", "this gate was never reached". Binary, and this repo's history is
   full of them (twelve 4v4 games with zero sensors of any kind; 960 front
   elections won and 0 towers built).
3. **Floors across players, never averages.** A deadlock hammers the worst
   player while the median barely moves — exactly what the fusion bug did
   (min energy income 1,614 -> 12,312 while the median went 22,330 -> 24,001).
   `min` across teams is the sensitive statistic here; the median is the blind
   one.

Set every floor **generously**, at roughly half what a healthy run produces. The
purpose is to catch a mechanism breaking, not to ratchet performance. If you
want to know whether a change *improved* things, that is the scoreboard
(`ISSUES.md`, "the eco scoreboard"), not this.

## Adding a scenario

Add an entry to `baselines.json` with its match arguments and its checks, then
run `--update` to record the floors. Keep the game short enough that the suite
stays runnable: the current suite is a few minutes per scenario.

A check that starts flaking is a bug in the check, not in the AI. Fix or delete
it the day it flakes.
