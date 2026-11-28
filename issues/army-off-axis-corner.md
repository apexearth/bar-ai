# The army model parks a group in a far corner off the line between the bases (2026-11-27)

His observation, from many games: part of the model's army ends up in the same far corner, away from the line
between the two bases. On Comet Catcher, with the model's base at the bottom-left and the enemy's at the top-right,
a group sits at the top-left. A group there is not defending, not attacking and not holding the middle.

Check: `tools/contract.py` "army off the line": the share of the army's metal-time (the 30-s army snapshots) standing
far off the line between the two starts (more than 0.3 of the start-to-start distance away from that line), so it
reads on any map and either start.

Measure: results/armynet/2026-11-27-army-off-axis.md (where the army stands and where its orders aim, per map and
start corner, model / rules / top players; what holds the model there; whether it follows the map or the frame).
