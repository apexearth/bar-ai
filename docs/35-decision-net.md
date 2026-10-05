# A value net trained on our own decisions

His idea (2026-10-04): feed a network the game state at the moment a decision
is made, and train it on the outcomes that say whether we got better or worse.
The net then tells us what a decision is worth in that moment. His examples:
energy and metal fill, metal income against its maximum as inputs; income
growth, damage efficiency, mex count change, energy status and e-stall as
outputs.

Why decisions and not games: a net on the 42 ecoclimb tunables could not beat
"the knobs do nothing" on held-out rounds (`tools/surrogate.py`, held-out R^2
<= 0). The knob effect is below per-game noise (sd 0.14 vs NullAI). One game
holds ~850 builder decisions per AI, each with its own state and outcome.

His calls, 2026-10-04: **constructors first** (factory production later). The
net is a **modifier**, never the decider: the market still proposes concrete
options from the unit defs; the net says what to want more or less of (more
anti-nuke, fewer T1 labs, walk matters less now) by reweighting the draw. It
must **learn while games run** and show it live on the dashboard; all running
games feed one net (his "merge"). Enemy damage must not be blamed on a sound
decision: losses are split near/far from the chosen site and the state carries
the threat, so a predictable raid is in the baseline.

## The record

`manager/brain/market/nnlog.as`, riding `apex_decide_log` (on by default).
One `apex: nn` line per EXECUTED builder election (the `apex: exec` point in
`Decide`), so coverage is checked as nn/exec per team. An `apex: nn-schema v4`
line names the fields once per game (and `explore=1` on a discovery game);
parse by name, never by position. The 10-04 field list came from three
codebase sweeps (economy, enemy/risk, high-level decisions); the ones left out
were too costly per decision (`ReachSlack`, `CoverAt` alone) or need a
restructure (enemy economy estimate).

- state (`NnState`, 68): incomes, banks, pull, surplus AND the energy actually
  binned, economic power, slack, e-stall, feed, metal starved/wasting, hands
  vs feed, idle nanos, claimable spots, upgrade demand, backlog, tier; our and
  seen-enemy army (ghost-discounted and pessimistic), stance, trade, loss
  pressure, loss rates by killer class, OUR STRUCTURES DYING (`BleedM` -- the
  others count army), enemy air now/peak, incoming push, raid pressure, time
  since the last raid, intel freshness (is foeArmy=0 safe or blind), silos,
  team and map size; holdings off the commitment ledger (labs, nano BP --
  nanos are not IsBuilder, the census test is used -- converters, armed
  structures, anti-nukes, stockpilers); budget shares and targets. No map
  coordinates: they let a net memorise maps.
- options (`NnOpt`): the top 8 of `ranked` -- kind, def, MARKET value (net and
  discovery multipliers taken back out via `nm`), gain, costs, build time,
  walk, risk, seconds to the ETA target if built first (`EtaOfWant`, capped),
  the power it adds (`DPowerOf`), how many we own, tier, forward fraction,
  recent losses at the site, the persona multiplier, and **p**.
- `apex: nnfac` (production.as): every factory order with all candidates and
  their roulette odds. `apex: nnair` (air/update.as): every bomber launch and
  a 30 s heartbeat while a wing is held. Logged, not yet trained on.

## The table

`python tools/decisions.py <match|tournament> --out rows.jsonl` joins each
record to the gadget lines, for the deciding team, at +1/+3/+5 minutes: dMInc,
dEInc, mWaste, eWaste, dMex, lnD, kill, lost (enemy kills only) split into
lostNear (within 600 elmos of the chosen site: the decision's own exposure)
and lostFar (the enemy's doing), and by KILLER CLASS (lostAir / lostStatic /
lostMobile, from the killer's unit def), dEco (economic power incl. energy),
reclaim. Plus `done`/`buildS`, `survived`, and `lostPre` -- enemy kills in
the 5 minutes BEFORE the decision, a check that the state saw the pressure.

## Discovery games (`apex_nn_explore`, 0.1)

His call: some games play with the net "tweaked randomly" against
overfitting and for discovery. Once per game, in a build that carries trained
weights (so other lanes' experiments and his slot are never randomised by
accident), 10% of games give every want kind a lognormal multiplier
(sigma 0.4) for the whole game and put noise on the net's output layer. The
roll is logged (`apex: nn-explore`, and `explore=1` in the schema line).
Multipliers live in `nnMult`, outside the logged market value.

The trainer archives (never deletes) the net when the record's layout or its
own outputs change: `runtime/nn-archive/<stamp>/`.

## Live training (Net tab)

`tools/nntrain.py`, started from the Net tab. Every 5 s it reads each RUNNING
game's own files (write dirs `matches/_engine*`, `runtime/engine-w*`: the
gadget log plus each AI's `apex-t*.log`, flushed every frame). A decision is
trainable once its 5 minutes have been played; at 150 matured decisions the
batch is predicted first (the accuracy point, always unseen data), then trained
on, each minibatch mixed with as many old rows (replay, so it does not drift
toward the loudest game). Finished games give their remainder; a game is keyed
by its first records, so nothing counts twice. Dropout 0.1; every 40 batches a
partial reset (weights x0.8 + fresh x0.2) keeps it able to learn. Two nets:
FULL (state + decision) and STATE (state only); full minus state is the
evidence that decisions carry learnable value. A live game is re-read at most
once a minute; logs without the v3 schema (his own build) are skipped after one
look. State in `runtime/nn/`.

## The net plays (`apex_nn_blend`)

Every ~800 learned decisions the trainer writes the FULL net as `nnweights.as`
into the deployed copies named in `runtime/nn/targets.json` (default the
`nnlog` lane, both engine- and game-side). The repo copy is the empty net, and
a deploy restores it, so the trainer re-exports whenever it finds a target
empty. Every game loads the latest weights at start; they are fixed within a
game (host-side, no desync).

`NnScore` (in `Decide`, right after `OppTimeReprice`) scores the top 8 options,
folds the outputs through OBJECTIVE into one number in units of each outcome's
spread, and multiplies each value by exp(blend x (score - mean)), clamped to
+-3 spreads; the whole list is re-sorted because `DrawWeights` takes the first
of each category. OBJECTIVE (nntrain.py) is a stated default until he picks
one: +5 min economic power 1.0, metal and energy income 0.25 each, damage trade
0.5, losses near the site -0.5, finished 0.25, survived 0.25. `apex: nn-score`
(60 s) proves it fires: scored count, how often it changed the top option,
perf as `dec.nn` (recording as `dec.nnrec`). NNW_GAMES counts training
batches, not games.

## Review 2026-10-04 (Fable, read-only) and what changed

Confirmed correct: train/serve feature parity, weight layout, no label
leakage, nnMult never compounds, the maturity rule. Fixed: live training was
dead (the trainer looked for schema v3); 22% of rows were FORCED wants
(escort/panic/join) inserted after the net looked, with placeholder values --
now flagged (`forced`, `Want.nnPriced`), excluded from the field's best and
value-masked, and the with-vs-without headline uses only rows chosen on value;
accuracy is scored only on a game's FIRST batch (later live batches overlap
99% of their label windows); games are keyed per team; a live row waits for
its survival label; survived counts enemy kills only (a moho finishing kills
its T1 mex); finishes match the decision's site (`[BARAI_BUILD]` now carries
x,z); target spread floored at 0.1; lostPre is a diagnostic, not an output;
retries on Windows file locks and a loop that survives errors; NnState once
per frame, each option's inputs computed once per election, int one-hot, full
weight-shape check. Open: the logged propensity p is exact only for drawn
rows (fallthrough picks read p=0); per-election cost still unmeasured at 8v8.

## What the first game showed (12 min, Comet Catcher, vs BARb hard)

123/123 executions recorded. **Only 3 of 123 came from the draw**; 103 were
fixed (roles, panics, pushes), 17 by the ETA ladder, and 41 fell past a refused
winner (pick > 0). The draw is where the net acts, so most decisions are still
outside its reach; opening them up is his call.

## Next

1. A tournament of logger games with the trainer running: does FULL beat STATE?
2. Blend A/B (0 vs 1) head to head, judged on minutes.py, not on the net's chart.
3. Randomized-net games for discovery (his idea): each game plays a perturbed
   net and records the perturbation.
4. Reload weights mid-game (needs a DLL file-read binding).
