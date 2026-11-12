# Air routes around stale AA

His 11-11 (watching): "we pretty much always try to attack from the edges of the map with air ... the anti-air is
actually lighter in the middle, but for some reason we're never trying it ... maybe we haven't seen it? Maybe we're
not sending out scouts."

Mechanism (code, not yet measured in a log): bombers path with the pathfinder over the threat map
(cpp BombTask.cpp CreatePathSingleQuery with GetThreatMap). An enemy out of sight keeps its threat drawn at its
last-seen spot until our vision covers that ground and finds it gone (MapManager::HostileInLOS -> SetHidden) or the
long purge fuse (EnemyManager.cpp two-tier timeout). Mobile AA seen once in the middle with an army stays there as a
ghost; nothing scouts the middle again; the path hugs the edges, where nothing was ever seen.

Plan:
- A mobile unit's out-of-sight threat fades by the chance it is still there: time since seen against the time it
  needs to leave its own reach (range / speed). Static AA keeps its weight until vision proves it gone.
- Before a strike whose cheap path is cheap because of stale ghosts, the look scout (air/update.as LookRoute) flies
  the shorter route first.

Measure: bomber route bearings vs enemy AA actually standing there (replay or log), strike losses per run, before
and after.
