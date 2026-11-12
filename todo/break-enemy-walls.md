# Break enemy walls

His 11-11: "If the enemy is using walls. Have our rezbots run up and reclaim those walls if they can do so without
dying. Also we can just flat out shoot at the walls to get rid of them sometimes from safety."

Nothing handles enemy walls today (the only wall code raises our own: catalog.as WallDefFor).

Plan:
- Bindings (C++, InitScript.cpp): reclaim an enemy unit by id; attack an enemy unit by id. `CmdReclaimUnit` takes
  only our own units and only `CmdAttackGround` exists.
- Recognise their wall pieces by stats, as WallDefFor recognises ours (unarmed, immobile, blocking).
- Rez bots: a priced reclaim want on a wall the bot can reach and work outside their tower and army threat (the
  builders' risk model), worth the path it opens and the metal it returns.
- Shooting: a wall that blocks the army's path or a siege target is attacked by units that reach it from outside
  tower range -- the ranged and artillery line first.

Measure: games against a walling opponent (or a scenario with a wall line): walls removed, our losses doing it.
