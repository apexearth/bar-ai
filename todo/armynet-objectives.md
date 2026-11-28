# Army model: objectives, a floor, and a fast instrument (11-27)

Approved by him 11-27. Replaces the self-play rounds in `todo/armynet-self-play.md` as the current
army-model plan. Led by the session named Fable; built by the army-model session.

## Why the rounds stopped

- A 20-game gate with a 12-win bar passes an identical model 25% of the time and a truly 60% model
  about 60% of the time. Gates 1-4 (10-10, 10-10, 6-14, 8-11) are what noise looks like.
- Every candidate was an 8,000-step fine-tune of the same champion; held-out place error stayed
  411-428 elmos. The candidates were the same model.
- The model was compared with itself while the rules army beat the best model arm (1 of 9 paired,
  -.264). Army in their half: rules 37%, top players 30%, model 18-23%. 8 of 20 games in a typical
  gate reach the 40-minute cap on Red Comet.
- A copied click carries a plan the model cannot see. It learns the average click (~650 elmos), and
  serve.py rolls a chance to act and a random back / hold / forward band each decision: a random
  walk with no lasting intent.
- The per-decision rating ran against winning (12 of 64). Winner-only training had ~50 games for a
  4,096-cell choice per force.
- No measure covered the issues he sees: orders to places with nothing there, and an army that
  does not go to the enemy's base.

## Step 1: stop

No more self-play rounds, serve-flag gates or 20-game model-vs-model gates. enemy1 / sp2 stay as
what he plays until something beats the rules army.

## Step 2: the instrument, before any model change

Offline (no engine, minutes, thousands of states from recorded games):
- **Advance**: states where our army metal is clearly above theirs (seen + remembered) and enemy
  buildings are known or presumed. Share of the model's order mass aimed at enemy buildings, mexes
  or presumed bases. Same number for players (winners, top skill quartile) and for the rules army.
- **Aimless orders**: share of orders whose destination has no enemy seen or remembered, nothing
  of ours to guard, no metal spot and no presumed base within reach. Same three columns.
- **Intent**: how often a force's destination flips between consecutive decisions with no change
  in what it can see.

First numbers, 11-27 (`tools/armynet/objectives_offline.py`, every measure beside a shuffled-target
baseline): per order, the model already aims at enemy buildings when ahead more than top players
do (0.90 vs 0.52; random 0.52 / 0.39). Its orders point forward while its army does not stand
forward, so the measures that matter are per unit of army, not per order:
- **Commitment**: every 10 s, each armed unit's standing order by class (enemy cluster or base,
  extractor or lone building, enemy army, own asset, gather, none) and its depth on the base axis,
  as shares of army metal-seconds, overall and when clearly ahead.
- **Order funnel**: what ended each order aimed at an enemy objective: arrived, replaced before
  arrival (by what), died on the way, stopped short, still walking.
- Advance counts clusters and the presumed base, with lone extractors and turrets as their own
  class; flips are direction reversals per force-minute.

In games (paired, same seed, mirrored factions, vs the rules army, never vs another model):
- time to the kill and share of games decided before the cap
- enemy building metal killed by minute
- army metal-minutes within weapon reach of enemy buildings
- trade, as now

These go into `tools/contract.py` as army checks in plain terms, so every results page shows them.
A candidate is better when the continuous measures move on paired seeds; win count alone is not
read below ~40 games.

## Step 3: the model chooses an objective, not a cell

Each force picks one objective from the real things on the map and holds it until it is resolved
(dead, taken, unreachable, or the odds turned):
- enemy building clusters, seen or remembered
- **enemy metal extractors**, and metal spots they are likely to hold
- **the presumed enemy base**: while their base is unseen, the likely start positions on their side
- enemy army groups, seen or remembered (with heading)
- our buildings and extractors under threat
- another force of ours (join), a gather point, hold here

A pointer over these candidates (tens, not 4,096). Point or line, length and facing stay the
learned heads they are now: this lists targets, not moves. Kind (move / fight / attack) stays learned.

Labels from replays: each player order relabelled to the objective the force actually went on to
reach, fight or guard over the next 1-3 minutes (hindsight), not to the nearest thing to the click.
Check first: what share of player orders map to some objective; the remainder says which
candidates are missing.

Only what the side could see: presumed bases come from the map's start positions and what has been
scouted, never from ground truth.

## Step 4: a floor from the rules army

Train the objective model to reproduce the rules army on our own games (its orders are a function
of visible state, the data is unlimited and in-distribution). Bar: parity with the rules army on
the step-2 measures, paired. Only then mix in player replays and outcomes. This is a starting
point; the target stays play learned from strong players.

## Step 5: rate a move by what it does to winning

The value head calls the result on 71% of held-out states. A move's rating is the change in
predicted win chance over its span, not local trade. Check before training on it: on own games it
must rank the winning side's moves above the losing side's at matched game time, and rank a
committed advance with superior force above standing.

## Step 6: more data, larger net

1,331 player games behind a 128-wide, 3-layer net with the GPU mostly idle. Record more public
duels (top quartile first); grow the net once the data is there. Measured by the step-2 offline
numbers, not held-out logloss.

## Where it stands (11-27) and the standing roadmap

Measured the same day (pages under results/armynet/2026-11-27-*): orders already pointed forward;
the army stood at its target and was never asked again. Three changes moved it, none a new model
design: the memory fix trained in (C), fight orders at enemy clusters, and a forced decision when a
force stands at its target (E2). G2 = C + E2: vs the rules army 4-6 with 2 ahead at the cap (the
played model 1-11), head-to-head vs the played model 5-3 with caps 2-2, more buildings killed.
He switched his online games to G2 on 11-27. Remaining gap from the loss census: the middle of the
map by minute 12, and raids there answered less often than the rules army answers them.

The principle that worked: **the model is asked when something happens, not by a random roll.**
Work continues without waiting for a go between steps; each step is a results page read by the
same tables.

1. Finish H1 (C + E3 head-to-head) and the raid test (`--force-threat`, set mvr-t).
2. Events replace the click roll one at a time, each serve-only first with its forced answers
   logged: arrival, cluster cleared, new threat to our buildings or builders, force under fire,
   force joined or split, a new enemy cluster seen. An event stays when the tables move.
3. Where the forced answers show no opinion or a poor one (today: staying after clearing, and
   raids if mvr-t shows it), teach it: an objective head labelled from rules-army episodes
   (cluster, base, threat, spot, join), fine-tuned from C, deciding at episode boundaries.
4. Train as it is served: decision points in training become the same events, so training and
   serving ask the model at the same moments (parity.py covers it).
5. A second map (Comet Catcher 1v1) for every arm that is kept, so nothing is fitted to Red Comet;
   BARb as a sanity check only.
6. Background, as machine time allows: more public duels recorded, a larger net.
7. Larger public games too (his 11-27): team games are what he hosts. Record them alongside the
   duels; the model is told the game's size (players per side, allies' units in its view). Read
   the step-2 tables on team games apart first (how players' forces behave there against duels),
   then train with them mixed in and check that the duel tables do not get worse.

8. Hindsight corrections (his 11-27 idea): when a move ended badly and the danger was visible or
   remembered at the time, label what the better move would have been and train toward it.
   (a) Computable corrections first: a unit that out-ranges its killer and died inside the
   killer's range -> the same move stopped at its own range; a force that entered a fight
   outgunned -> join the nearest larger force of ours, or hold. (b) Then replayed fights: a lost
   fight respawned as a short scenario with a handful of alternative orders, the engine deciding
   which wins. Never corrected from hidden information.

9. Power maps, security and the scenario gym (his 11-27 design; the main track after the
   in-contact result).
   (a) Maps, one function for training and serving: each side's projected power per cell (what
   its units and defences can hit there), by movement class from unit stats (ground,
   all-terrain, hover, air) over passable ground; a remembered enemy defence stays until seen
   dead or seen gone. Separate layers for what is worth hitting and for where it is safe to stand.
   (b) Two measures from them: security = how much of our power a raid must pass on its easiest
   path from their base to ours, against the raid size they can field; the way in = the same for
   us into them. The weakest cell on our side and the easiest path on theirs become objective
   candidates (hold here, raid along here, shell the strongest spot with long range).
   (c) Check before use, on recorded games: the winning side scores better; a fall in security
   precedes economy losses. Then they are model inputs and the rating of a move.
   (d) Roles from stats, not lists: fast units raid, slow and long-range units hold; the model
   chooses among map-made candidates, no hand planner with thresholds.
   (e) Scenario gym: the arena spawns a set scenario (units, positions, health, a fortification),
   plays it, resets, and the model trains on its own tries as they come in. First scenarios from
   the measured failures: finish a base with a superior force; decline a fight when outgunned and
   regroup; a long-range unit with a spotter; answer a raid on a middle extractor; a fortified
   position with an army that the given force should beat. More scenarios as failures are found.
   (g) One shared network, many games (his 11-27): one learner on the PC's GPU; scenario engines
   on the PC and the Mac are actors. Each actor plays with the newest weights, writes every try
   (inputs, orders, result) as a small file, and reloads weights every few tries; the learner
   pulls the files, trains continuously and publishes weights with a version number. Each try
   records the version it was played with. Actors stop for his games; the learner yields the GPU.
   (f) The 12-seed tables against the rules army are read after every round, so scenario skill
   that does not carry into games is caught.

In-contact behaviour is learned from the rules army first (his 11-27: it is strong in the small
details of a fight); players and outcomes teach the larger decisions.

A candidate is kept when, on 12 paired seeds, it is better than the current one on the tables
against the rules army and not worse head-to-head against the model he plays. A change to what he
plays online is recommended to him first. Bar for the whole effort: level with the rules army,
then past it.

## Order of work

2 first (nothing else is judged without it), then 3 + 4 together, then 5, 6 alongside as machine
time allows. Each step reports its step-2 numbers on a results page.
