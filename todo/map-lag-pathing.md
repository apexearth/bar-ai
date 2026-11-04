# Find the lag on particular maps (his 10-19)

Pathfinding is one of the big issues: units that are stuck or cannot reach their destination should back off, or the
ground a unit type cannot reach should be blacklisted. Measured so far: in the 16-AI benchmark the engine is 75-85% of
the late frame (34-51 ms a frame at ~3,000 units) and our path queries 98 s of worker CPU (317k); reclaim refused for
threat now backs off (1dfb106f) and radar sites an ally covers are no longer chosen. `tools/maplag.py` compares maps;
not yet run across maps. Current performance state: `issues/performance.md`.
