# Learn from what each decision actually did (his 11-04)

*"I would want to learn from the specific scenarios. And like two minutes is not nearly long enough. And for some
things I don't even know that a time consideration is valuable."*; *"Damage is generally a better metric"* than kills;
*"Right now our training is just very simpleton."*; *"I want you to have all these different aspects of the neural
network built ... highly trainable. There's no point in training if it's not going to be successful."*

## Why the old training could not learn (measured 11-04)

pgloop credited every pushed decision with the 2-minute move of our standing, which every other decision and the enemy
dominate. Step to step its signal did not repeat (per-head t correlated -0.00 between consecutive steps; a |t|>2 signal
kept its sign 54% of the time; 51% in the 10-28 run), and it moved a fixed amount every 24 games anyway, so it
random-walked off a good start (v16-v19 scored worst). One game's setup-adjusted score varies +-1.3 against effects of
~0.1. Stopped (runtime/pg/pg_on.paused).

## The design

Every decision kind gets a **record of what it actually returned** (in metal and damage, over its own life, no fixed
clock), joined to **what the AI knew when it chose** (the 101-feature state + the option's features, `apex: nn` lines).
A **head** per decision kind predicts the return from the situation; the decision's price uses the prediction. Heads
are fitted on thousands of records (low noise), judged on games they never saw, and steer play only after a paired
game test beats the price they replace.

| Head | Decision it serves | Record (label) | Status |
|---|---|---|---|
| H1 job survival | every build want | frame destroyed by the enemy; builder killed on the job | built (risk.as, risknet.py); steering off: first wiring lost income in a 24-pair A/B |
| H2 building return | every build want's gain | lifetime output: economy metal+E/60, tower metal of damage, factory army and its damage, nano build power by target | records being added (BARAI_LIFE) |
| H3 build-power use | nano / assist / which line a hand lathes | factory output per build power assigned; build power by source per building | records being added |
| H4 unit matchups | factory production | per engagement: both sides' traits (health, range, DPS, rate of fire, speed, cost, sustain: rez/repair present) and metal of damage traded | not built: needs engagement records |
| H5 commitment | raid/push: continue, regroup, retreat | the squad's trade and whether it reached its target, by progress % and odds when re-decided | not built |
| H6 aggression | stance / army share | what pressing or holding gained over the next minutes, by map control, army and eco ratios | not built |
| H7 scouting | scout sends | what a look revealed, what production did next, how the next fights went | not built |
| H8 incursions | defence placement | each enemy push: stake exposed, towers/army in reach, share lost | not built |

## Making it trainable (the conditions, each checked)

1. **Labels mean what they say**: each label is checked against the raw logs before a model is fitted on it
   (11-04: 42% of "lost frames" were our own reclaims or abandoned frames decaying, not the enemy).
2. **No leak**: inputs only what the AI had when it chose (11-04: exposure time leaked a failure's outcome).
3. **Counterfactuals need variation**: we only see what we chose. Natural variation across states and a logged
   exploration rate (a small random share of choices among the top few, with the odds logged) let a head compare
   what was not chosen.
4. **Judged on unseen games**, by log-loss / AUC / calibration per head, before any play test.
5. **Steers play only after a paired test** (same seeds and sides, tools/ab_pairs.py) beats the price it replaces.
6. **The loop** (tools/ledgerloop.py) refits on new games and accepts a refit only if it predicts the new games better.

## Tools

tools/ledger.py (records) · tools/ledger_calib.py (price vs outcome) · tools/ledger_risk.py, tools/risknet.py (H1) ·
tools/ledger_returns.py (H2/H3 first view) · tools/ab_pairs.py (paired play tests) · tools/ledgerloop.py (the loop) ·
game-patches/gadgets/dev_combat_log.lua ([BARAI_LIFE]).

First numbers (548 games, 11-04): towers took 2.4 M metal and killed 0.27 per metal; 74-82% of LLT/HLLT/Guardian killed
nothing; 63-70% of T1 extractors destroyed; ~400 jobs a game dropped within seconds; the price expected 6.8% of build
jobs to fail where 22.7% did. Related: `adapt-by-realized-return.md` (within a game), `one-pricing-scale.md`.
