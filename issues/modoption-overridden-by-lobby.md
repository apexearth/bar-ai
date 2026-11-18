# A lobby option's default overrode the same --modoption (10-07 .. 11-18)

A bot's own option outranks the game-wide rules param (`GetOwnTunable`, 2e7411fd 09-22), and the engine fills every
option AIOptions.lua lists with its default. From e21e6692 (10-07) AIOptions listed `apex_nn_blend` (def 1),
`apex_plan_explore`, `apex_plan_force`, `apex_persona_force`, so a `--modoption` of those names did nothing:
`nneval.py`'s rules-only arm (`--modoption apex_nn_blend=0`) very likely played with the nets on. Results that rest on
that arm (nets vs rules, 10-15 "nets near-inert" if it used blend 0) need a recheck; one `-b0` game's log showing
`apex_nn_blend` read as 1 settles it.

The 11-18 lobby trim removed those four, so their modoptions work again. Still listed, still overriding:
`apex_persona`, `apex_eco_force` (and `cheating`, `ally_base`, `disabledunits`): set them per bot with `--ai-option`.
