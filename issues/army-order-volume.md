# Army order volume: who re-paths every ~2 s (2026-10-22)

His 10-22: "one thing that lags me is probably all the con turrets... throttle it so APM doesn't go out of control."
Measured with `apex: cmds` (2v2 vs BARb hard, Comet/Isthmus, 30 min), commands per minute per AI at the peak:
turrets 32-52, constructors 326-560, army 700-1,012 (moves). Turrets are NOT the flood; the army is, ~33 commands
per army unit per minute. Idle-job cost: facIdle 0.031 ms/AI/frame (cheap), bldIdle 0.34-0.41 (nearly the 0.417
budget alone).

Traced (apex_order_trace, 20-min 2v2): 20,125 route changes, builders 55%, retreats 15%, scouts 13%, raids 9%;
70-90% moved the goal under 64 elmos. apex_keep_route (keep the walked route when the new one ends within 64 of it)
cut army commands per unit-minute to 16-20 from 25-33, but went 6-13 on Starwatcher vs v0.3.5; deleted 11-04, never played. Measured and left off or reverted: apex_order_dedupe (<1%), apex_travel_step 2 (-6%),
apex_travel_samestep (noise). What is left is mostly units near enemies, which the lean path re-orders every second.
Next: hold a unit's order while its goal has not moved enough to change its route.
