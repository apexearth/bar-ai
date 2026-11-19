# A lobby option's default overrode the same --modoption (10-07 .. 11-18)

A bot's own option outranks the game-wide rules param (`GetOwnTunable`, 2e7411fd 09-22), and the engine fills every
option AIOptions.lua lists with its default. From e21e6692 (10-07) AIOptions listed `apex_nn_blend` (def 1),
`apex_plan_explore`, `apex_plan_force`, `apex_persona_force`, so a `--modoption` of those names did nothing:
`nneval.py`'s rules-only arm (`--modoption apex_nn_blend=0`) very likely played with the nets on. Results that rest on
that arm (nets vs rules) need a recheck. **Confirmed 11-18:** `G:\bar-ai-archive\tournaments\20261009-221903-nn-open2v2-b0`
t000: script.txt carries `apex_nn_blend=0`, both seats log `apex: tunable-opt apex_nn_blend=1`. The 10-15 "nets
near-inert" finding is described as nets against each other and a zero-weight net, not blend 0; unverified whether
any of its arms used the modoption. **No rerun (his 11-18):** nets off is known to play much worse from accidental
deployments that shipped without the nets.

The 11-18 lobby trim removed those four, so their modoptions work again. Still listed, still overriding:
`apex_persona`, `apex_eco_force` (and `cheating`, `ally_base`, `disabledunits`): set them per bot with `--ai-option`.
