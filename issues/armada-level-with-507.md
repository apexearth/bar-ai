# Armada on ordinary maps is only level with v0.5.07

v0.5.10 shipped (11-12, his call) with Armada 2v2 on ordinary maps level with v0.5.07: 13-14 over 72 games. Metal
income was about x0.9 at minute 20 and about even at minute 30 (bench-arm510j/k/m; +50, Red Comet / Carrot
Mountains / Comet Catcher, sides alternate). Cortex is ahead (x1.10 at 20, 30 of 48 games ahead), and so is Full
Metal Plate 1v1 (8/8).

Armada lost ground between the 11-11 morning build (bench-arm510c: 6-4, x1.16 at 20, x1.55 at 30) and the 22:10
candidate (arm510g). The Armada bisect (6 seeds) cleared five suspects. Reverting each of these did no better than
the build: army-target gap scaling, the walking drain, the race end, flyers in the ground line, and the lab-nano
sizing. The cause is somewhere else in the 11-11 day's changes.

Seen in the losses:
- Early raids by armpw/armflea at minutes 3-6 cost a lab or 1-1.5k metal at home. The race was running and still
  chose the constructor, because its value per cost beat every fighter.
- Mid-game we held about half v0.5.07's army (arm510j t014: 9.9k vs 20.7k at minute 20), with Mavericks lost in
  bulk.
- Lab nano spend is about 30% below the morning build (builtmix.py).

Next: diff the morning build (510c) against the 22:10 candidate, take the changes the bisect did not cover, and
bisect those on Armada. Read the early-raid losses with story.py and minutes.py.
