# Gunship wings hover in AA (2026-10-23)

His watch: a 40-gunship wing lingered over their base under AA and never committed. Measured with
tools/scenarios/gunship_aa_hidden (12 Brawlers vs 6 light AA + a flak). Two causes: the unseen-base guess was our
start mirrored (wrong on asymmetric maps), and a committed raid refused every target under AA and stayed.
Built 74cc5616 (apex_gun_refuse, apex_aa_dwell, the start-box guess; validation #73): 24 1v1 +50 games vs v0.3.9
12-11, no measured gain. Tried and removed: never recalling a committed wing (apex_gun_commit), 7 Brawlers lost
for 440 m killed.

Open: the release's air net picks GO over the rule's WAIT (GO weight 0.90-0.98). His call: the net keeps
deciding; next is targeted training on scored gunship runs (`gun run scored`).
