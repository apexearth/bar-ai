# Enemy walls stop our army

Seen 11-25 in a full-tech 4v3: our army stops at enemy walls, though a rez bot could walk up and reclaim them. The only wall logic we have (military/unblock.as) frees a unit penned by OUR OWN buildings. Nothing sees
an enemy wall across the army's way, and nothing sends a rez bot or constructor to reclaim it.

Next: find his game's replay (v0.5.21, 4v3, ~21:00 local) and count our army units standing at enemy walls. Then price
reclaiming the wall the stuck force faces (wall metal + rez bot walk vs the army metal standing still), as the pen
reclaim prices our own.
