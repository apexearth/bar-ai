# Step 3, the label's unit: force episodes labelled by contact (players / rules army / model)

Plan: `todo/armynet-objectives.md` step 3; the Fable session's 11-27 read of the
[click-level check](2026-11-27-step3-relabel-check.md): the click is the wrong unit, players steer with many small
moves. Tool: `tools/armynet/episodes.py` (definitions in its docstring). Each armed unit's track every 10 s is cut
into trips: a run of movement and the hold after it (a pause under 30 s is part of the trip; a unit that only stood
has none). Unit trips that start in the same step within 600 elmos are one force episode. Label (hindsight, ground
truth allowed): what the force fought, metal-weighted damage dealt and taken (enemy buildings in a 2,000-metal
cluster, lone buildings, enemy units near our buildings = threat, other enemy units = army); with no contact, a spot
only when it held there and something of ours rose or theirs fell there, a base when it held within 1,500 of an
enemy start, join when it held beside other armed units of ours. Aligned: the trip's heading within 60 degrees of
the labelled place. Baseline (`--shuffle`): each episode's heading replaced by a random other episode's.

## Results

| column | games (sides) | episodes per side-game | median length | cluster | lone | army | threat | spot | base | join | none |
|---|---|---|---|---|---|---|---|---|---|---|---|
| top-quartile winning players | 23 (23) | 119 | 80 s | .017 | .020 | .277 | .243 | .015 | .013 | .372 | .043 |
| rules army, vs itself | 6 (12) | 260 | 60 s | **.106** | .049 | .232 | .264 | .022 | .014 | .234 | .079 |
| rules army, vs the model (A) | 6 (6) | 185 | 70 s | .067 | .044 | .329 | .194 | .027 | .052 | .212 | .075 |
| model, vs the rules army (A) | 6 (6) | 145 | 70 s | .064 | .059 | .282 | .286 | .023 | .009 | .195 | .082 |

Cluster + base: players .030, rules army .120 (vs itself) / .119 (vs the model), model .073.

| aligned (heading agrees with the labelled place) | real | shuffled headings |
|---|---|---|
| players | .953 | .643 |
| rules army, vs itself | .949 | .690 |
| rules army, vs the model | .960 | .714 |
| model | .946 | .650 |

By label, real vs shuffled, the cluster class aligns .82-.97 vs .75-.85 (clusters lie along the base axis, so a
random heading often points at one); army and threat .89-.98 vs .60-.80; spot and join near 1.0 vs .43-.60.

## Read

1. **The rules army's episodes name clusters and bases four times as often as player episodes** (.120 vs .030), as
   the Fable session expected; the model sits between (.073). The rules army is the label source for "go take that
   base" (step 4); players' episodes are mostly fights with armies (.277) and defence (.243) and grouping (.372).
2. **Contact labels are real, not chance:** the label comes from what the force fought, and the heading agrees with
   it .95 of the time against .64-.71 for a random heading. The cluster class carries the least heading information
   (its baseline is highest), so a cluster pointer must learn more than the direction.
3. **Decisions per game:** a top player's side makes about 120 force trips in a game (one per 80 s median), the
   rules army 185-260 and the model 145. An objective model deciding at episode boundaries decides a few times a
   minute per force, not every step.
4. Players' "join" .372: much of what players send is regrouping without a fight; the objective list needs join /
   gather as a first-class choice, as planned.

<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "Step 3: force episodes labelled by contact (players / rules army / model)", "games": 0, "W": 0, "L": 0, "w": 0, "l": 0, "verdict": "Offline. Cluster+base share of episodes: rules army .120, model .073, top players .030; heading agrees .95 vs .64-.71 shuffled. Episodes per side-game: players 119 (80 s), rules 185-260, model 145. The rules army is the first label source for clusters (step 4)."} -->
