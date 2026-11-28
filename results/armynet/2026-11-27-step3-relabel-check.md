# Step 3 check: do player orders map to an objective by hindsight?

Plan: `todo/armynet-objectives.md` step 3, the check before any objective model. Tool:
`tools/armynet/relabel_check.py` (definitions in its docstring). One click per group, its first unit. Objectives at the
click from the side's own view: enemy building clusters (2,000-metal floor), lone buildings, metal spots in their
half with nothing of ours, the presumed base, moving enemies seen in the last 30 s, our buildings with a fresh enemy
within 1,000 (threat), other armed units of ours (join). Hindsight label: the class the unit spends the most of the
next 3 minutes within reach of (weapon range + 200; at least 10 s; join only when nothing else holds it), else hold
(moved under 300) or unmapped. Baseline (`--shuffle`): the same click's objectives scored on a random other click's
track from the same side.

## Results (one click in three)

| | clicks | mapped | cluster | lone | spot | base | army | threat | join | hold | unmapped |
|---|---|---|---|---|---|---|---|---|---|---|---|
| top-quartile winners (23 games) | 5,988 | .816 | .020 | .033 | .289 | .009 | .207 | .158 | .099 | .048 | .137 |
| same, shuffled tracks | 5,989 | .728 | .025 | .046 | .292 | .005 | .167 | .099 | .094 | .064 | .208 |
| all players (40 games) | 40,784 | .819 | .040 | .047 | .243 | .007 | .185 | .184 | .115 | .056 | .124 |

By kind (top-quartile winners): move is .967 of clicks and maps like the whole; fight .024 (army .217, threat .189,
unmapped .280); attack .006 (spot .314, army .229, threat .229).

## Read

1. **The list covers the map.** A random track maps .728; the real ones .816. As specified, the objective set is so
   dense (metal spots in their half alone take .29 either way) that "reached by hindsight" says little about intent.
   The signal is in army (+.04), threat (+.06) and unmapped (-.07): players do go to enemy groups and to our
   threatened buildings more than chance.
2. **Clusters and bases are rare destinations for players' clicks** (.020 + .009 for top-quartile winners): most of
   what a player sends goes to spots, enemy groups and defence. A pointer trained on these labels would rarely
   choose a cluster, which is the step-2 gap.
3. Before training on it, the label needs to be tighter. Candidates to test against the same baseline: (a) the
   click's own target must lie within reach of the labelled objective (intent and outcome agree); (b) spots only
   when the unit then stands there (it takes or holds it), not when it passes; (c) dwell weighted by time in
   contact (fought there) rather than presence.

<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "Step 3 check: player orders mapped to an objective by hindsight", "games": 0, "W": 0, "L": 0, "w": 0, "l": 0, "verdict": "Offline. Top-quartile winners .816 mapped vs .728 on shuffled tracks: the objective list covers the map; hindsight dwell alone is a weak label. Clusters/bases are .03 of player clicks. Tighten the label (click target within reach of the objective, contact-weighted dwell) before training."} -->
