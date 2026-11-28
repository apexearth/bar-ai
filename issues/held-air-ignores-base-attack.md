# Held aircraft hover while the base is shot

Seen 11-25 in a live full-tech 4v3 (our Cortex seat t6): a held Dragon gunship hovered next to enemies shooting our
base and did not attack. The log: nnair WAIT, 16-32 aircraft held at home.

Cause: `Air::Update`'s defend-home release needed BOTH `Military::BaseContested()` (their influence beats ours at the
base centre only) AND `EnemyAACost()` under 1,000. That is the enemy's AA over the whole map, 6,580 in this game.
So the held wing never defends once they own any real AA anywhere.

Done (source only, not measured): defend-home = (BaseContested or Builder::BaseUnderAttack, which counts buildings
dying in the last 45 s) and `HomeEnemyAA()` (enemy units that shoot air within BASE_DANGER_DIST of home, every 2 s)
under the same bar. Risk to measure: BaseUnderAttack's centroid fallback on small 1v1 maps could pin the wing home.
Measure: defend-home frames per game, air losses at home, buildings lost at home, before/after.

Ruling the same evening: proper fixes only, no patches on thresholds. The source change above only makes
an old threshold (apex_bomb_defend_aa, 1,000) read local AA: an interim patch, not sent to test. The proper fix is
that defending the base is a priced target in NaDecide, like any other cell: the prize is our metal the attackers
would kill before they are stopped, the cost is the wing's loss to the AA standing there. The base is then defended
exactly when that beats the best strike, and the bar and the defend-home switch both go.

Same game, later: an enemy army was visibly approaching and no aircraft went to meet it. Cause, the same decision:
NaDecide (nnair.as) prices only their ECONOMY cells as candidates. An enemy army, approaching or already in the base,
is never a candidate, so WAIT keeps the wing home; gunships under WAIT only hunt within 2x apex_air_cluster_r of home.
The proper fix covers both cases at once: their seen army groups become candidates beside the economy cells, each
priced by the same race (our wing's dps against the AA in and around the group). The prize is the group's metal we
kill plus the metal of ours in its path that it would otherwise kill. Bombers keep their economy-only doctrine
outside home defence; gunships take armies wherever the price wins.

Reverted from source the same evening (air goes to the army model instead); the interim patch is kept only as henry-outbox/air-defend-home.patch.
