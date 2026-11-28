# Learn army control from replays (his 11-18)

Replace BARb's fight logic with a model of how strong human players move military and radar/jammer
units. Input: what one team could see (its own units, enemies in its line of sight and radar). Output:
the order each group gets. Labels are the orders stored in replays. Each order is weighted by the player's
rating (OS) and by what it led to: metal killed minus metal lost by the ordered units over the next
30-60 s, with the game result as a smaller term. The better the player, the more the move counts;
a move followed by a heavy loss counts against itself.

## Step 0 (11-18): orders come through in a replay

- `tools/replay_orders.py <demo> <out> [minutes]` records every order and a 5 s position sample;
  `tools/replay_orders_stats.py` summarises them. An 8v8 replays 10 game minutes in 66 s of wall time.
- Local demos (450): 428 have humans, but only one has humans on both sides. Nearly all are
  co-op games, humans against Apex/BARb, median 27.5 minutes. 1v1 human duels come from the public
  archive (`api.bar-rts.com/replays`, filter by OS; WR's `run/replays/pick.py` + `fetch.py` do this,
  including fetching each demo's game version).
- One co-op game (Coastlines, 10 min): human orders to army/air/radar/jammer were 5,190 positional
  orders, 87% `move` by right-click; 74% given to 5+ units in one frame (so the groups come from
  the data). 82% re-target the same unit within 1 s, 3-6 frames apart, 30-400 elmos away: repeated
  clicking while steering. Treating a unit's orders within 1.5 s as one decision leaves 787 decisions
  in 10 minutes for 8 players (~10 per player-minute). 20-45% of a team's army gets a positional
  order in any 30 s window. The AI teams issue 4x as many orders.

## How players move armies (his 11-18)

Players pick a line or a piece of ground to hold and draw their units along it: to defend it, or
to push it forward. This is strongest early and in the middle game; late game differs. A raid or a
specific attack is a different shape: a concentration that punches through their line, which is
usually where their army is massed. The model learns what players do relative to what is around
them (ground, their own buildings, the enemy they can see), with no fixed list of moves imposed
on it.

Measured on the step-0 game (`tools/replay_orders_shapes.py`, one co-op game against bots, 10 min):
of 445 human orders to 5+ units at once, 74% are lines (median 250 elmos long), 26% send all to
one spot, almost none a spread blob. 52% of the lines stand across the direction to the nearest
enemy mass, against 33% for a random facing.

So the output has to be able to express a shape: where each unit of a group should stand (a line's
place, length and facing; a concentrated point), not a choice from a fixed menu. Kinds of move are
found afterwards by clustering what the players did, if they are wanted at all.

## The model (his 11-18)

One model of our own, trained on these replays: all our state in, a short typed answer out, like
WR's use of Jev (TypeSafe's general model, asked over a text picture of the game) but trained for
this game, on numbers rather than words.

- **In:** every army unit of ours (type, health, position, current order); a map grid of the ground,
  our buildings, the enemy in sight and on radar, where enemy units were last seen and how long
  ago, and their threat (weapon reach and damage); a few totals (game time, income, army value).
  Only what that team could see.
- **Out, typed:** for each unit, keep its order or take a new one; a new order is its kind (move,
  fight, attack...) and where, as a point on the map grid (or, for an attack, which enemy unit).
  Each unit gets its own point, so lines and concentrations come out of the answer; units sent
  the same way form the group. Kind and place are separate parts of the answer, not one choice
  per place (WR's Jev notes, K-jev-split-vote: a choice among many near-equal places split its
  vote and lost to a single alternative).
- **Shape:** a convolutional network over the map grid plus attention over our units, each unit
  reading the map around it. To be priced before it runs in a game: in the DLL, CPU, every 1-2 s,
  spread across frames (the 16-AI budget, `ai-performance`).
- **Trained** to copy the players' decisions, each weighted by rating and by what it led to. It can be
  judged offline, before any game, on held-out replays: did it send units where the player did?

## Within Reason's findings: hypotheses to test, not settled (reference/within-reason)

- **Their moves are verb + target.** Their hands pick one move per group a second from a fixed list (stay, hold,
  gather, go, fight to, attack, shell, send N, join, follow, scout), aimed at a named thing
  (`docs/design/2026-10-01-hands-rebuild.md`). That list is their choice, and it has no way to express
  a held line; we do not adopt it.
- **Fitting rules to their model's picks** (1.5M samples, whole games held out) recovered *whether*
  an enemy group needed answering, not *which move* (bots/distilled/README.md). Check the "which"
  offline against a plain rule before trusting it.
- **Carrying the order out matters as much as choosing it.** "Told to attack is not attacking": an attack
  must keep re-aiming at the moving target; joiners must take the group's order.
- **Formations won.** Ranks, an advance that halts until all are in reach, and a marched retreat went
  15-8-25 against Apex v0.5.04 vs the loose body's 5-12-23. Cost: 1.6-1.8 s engine time a minute at 20:00.
- **Footwork stays fast and in code** (kite, step out of fire, spread from a D-gun) at 10 Hz under
  the decision layer.
- **In public duels the higher-OS player won 22 of 29**: OS is a usable quality weight.

## Target: v0.6.00 (his 11-18)

Every decision is judged from seconds out to minutes (his 11-18): tactical gains (did the units win
the fight they walked into) and strategic ones (was the ground held, did the push pay, the game).
The model predicts those outcomes too, so in play it weighs one against the other.

## Built (11-18)

- `tools/replay_orders.py batch`: every local demo with a human seat, on the demo's own engine
  (the header names it; 2026.06.12, .07.04 and .09.03 are installed), its own port (two replays on
  8452 kill each other), 3 at once, pausing while his game runs and stopping a replay the moment his
  game starts. Out: `G:\bar-ai-archive\replay-orders\<demo>\orders.txt.gz` (format in the docstring)
  and `desync.txt`. 10 game minutes of an 8v8 in ~65 s.
- `tools/replay_dataset.py`: decisions (orders collapsed per unit within 1.5 s, groups by issue
  frame) and outcomes at 5 s, 15 s, 60 s, 3 min, 10 min: the group's damage dealt minus taken, kills
  minus losses within 1,000 of the target, the whole side's kills minus losses; the game result;
  each team's rating from the start script. On one Comet game the own-damage horizons correlate
  0.79 (5 s vs 15 s) down to 0.37 (5 s vs 10 min): the horizons see different things.
- BAR's widget handler passes widgets no attacker for damage (and refuses user widgets the
  handler); `Spring.GetUnitLastAttacker` inside the callback names it: 97% of damage on the test
  game. The rest is credited offline to the enemies with the victim in reach that second, by their
  damage a second. Kills carry their real killer. Three recordings made before this were renamed
  `orders.no-attacker.txt.gz` and are recorded again by the next batch run.
- Demo file names are UTC. His 11-18 00:31 PST Coastlines 8v8 replays out of sync from frame
  13,680 (every recorded player agrees with the others, not with us); four other demos played 15
  minutes clean. Outcomes past a recording's first desync frame are NaN. If the batch shows it
  is common: replay with no widgets at all, then an engine built with sync debugging on.

- `tools/public_replays.py pick|fetch|record|status`: BAR's replay service, games with every
  player at OS 30+, no AIs, no tweaks, ended normally; demos, maps and missing game versions go to
  `G:\bar-ai-archive\public-replays` (its own `data/` folder, read beside his install; his install
  is never written: a version fetched there moves the byar:test tag his lobby uses). About 1 in 5
  recent duels has both players at 30+. Recent duels run engine 2026.09.03 and test-31992, which
  his install has.
- `tools/armynet/`: `data.py` (one example = one human side at one second: an 18-channel 64x64
  grid of its view -- ground, spots, ours, allies, enemy in sight / on radar / remembered with a
  60 s fade, buildings remembered all game, ground and air threat, our damage reach, sight, radar
  -- plus one token per own army/air/radar/jammer unit; labels per unit: keep, or the new order's
  kind, cell and offset; weights: rating x exp(0.5 x outcome score), the score the mean of z-scored
  own 5/15/60 s, area 3/10 min, side 10 min, plus the result), `model.py` (a small U-Net over the
  grid, attention across our units, each unit reading the map where it stands, a cell score per
  unit), `train.py` (whole games held out; pauses while his game runs). The smoke run works end
  to end. The bar to beat: "keep the current target or stand" is a median 357 elmos from the
  player's point; about 10% of unit-seconds get a new order.

## Watch games (11-18)

`python tools/armynet/watch.py [--model ...]`: lane `armynet` (`Apexarmynet:lane-armynet`) on both sides; side A's
finished army/air/radar/jammer units are marked `disableAiControl` by `game-patches/gadgets/dev_armynet.lua`, which
also sets the game rules param `barai_handsoff`; only then does `CCircuitAI::Update` read the mark live and give the
unit a player task (our AI still owns and counts it; `apex: handsoff` lines). The gadget writes the side's view each
game second and applies `tools/armynet/serve.py`'s orders. Headless check 11-18: 26 units marked, 966 orders applied
by 12:00, side A's stock census `units=22 tasks=[t1=22]`. The first watch (a NullAI holder took the units, 5-minute
model): lost at 17:16, the army never left home (front 0.27 all game), 7 home mexes lost by 10:00. `dev_arena`'s
no-control mode sets `barai_handsoff` too; before this change its mark was read only on a save load.

## His second watch (11-18, 10-minute model on 100 duels, lane AI both sides)

Lost at 23:15 (first watch 17:16). Better: it defended its base and won trades there (14-18 min, ~15k metal of
theirs for ~10k of ours). Wrong, in his words: units stop chasing as soon as an enemy leaves sight without radar
("it should know the direction that units were traveling so that it can predict where they're heading"), and the
army only stayed in its base (front 0.03-0.22 against 0.4; 9-15 extractors against 60-80). Contract checks:
`raider repeat kills /10min` (new; side A 20.0 and 21.9 against 4.5 and 1.9) and `ground given up share` (0.48
against 0.08). Built: three map layers -- enemy heading (metal-weighted velocity per cell, x and z) and where each
remembered mover would be now (last position + velocity x min(age, 20 s)); the evaluation's `forward_*` (0 our
buildings, 1 theirs) of the model's places against the players'.

## Rating rule (his 11-18)

"Assume the player choices are reasonable unless specifically bad": each measure is scaled by its spread in the
game but measured from zero, so a move where nothing happened rates 1 (neutral); the mean counts against an order
only past one spread of loss; a win adds 0.5, a loss takes nothing away. On 80 duels: 2.5% of orders marked
down, 34.8% neutral. Before (z from the game mean, losers -0.5): a home order averaged 0.98, one past 0.8 of the
way to their base 1.35 -- forward was already favoured (players go forward when winning), so the weighting did
not keep the armies home; undertraining did (the step-14000 model matches players offline: forward 0.48 vs 0.50,
place 557 elmos from the player's against 604 for "keep the current target"). Not in the rating yet: economy
and ground gained by holding the middle without a fight (`tools/armynet/weight_by_front.py`).

Map control (his 11-18: "one 'pro' can be measured in increasing the map control we have"): `replay_dataset.py`
adds two measures from the whole-game view (labels only): on a 32x32 grid a cell is a side's when its buildings and
armed ground units outweigh the other's in metal; `control` = the change in the side's share of owned cells,
`near` = the change in (ours - theirs) among the cells within 1,500 of the target. In the rating: near 3 and 10
min, control 10 min. One duel: near-10-min against kills-near-10-min r=0.80 (new information beyond kills).

## Campaign (his 11-18)

`python tools/armynet/campaign.py --every 10000 [--init model.pt]`: one open-ended training run (constant rate,
the game list re-read every 10 minutes) and a watch game for each numbered checkpoint; results in
`runtime/armynet/campaign-*/campaign.log`.

Third watch (campaign step 10000, ~24k steps on ~150 duels, before map control): lost at 26:39 (17:16, 23:15
before). He: "a very big improvement from where we were and really makes me confident that we can do this."
Even to 12:00 (army 2,297 vs 1,444 at 8:00; 32 vs 39 mexes, income 150 vs 192 at 16:00 against 9 vs 59 last
time); still home (front 0.08-0.22 vs 0.46) and lost the mid-game fights to a much bigger army (lost 25.6k for
6.8k, 16-20 min). Contract: raider repeats 34.2 vs 1.2, ground given up 0.74 vs 0.15 (the collapse inflates both).
11-18 the trainer's workers died of Windows commit exhaustion (error 1455; his ComfyUI held 14 GB): the campaign
now runs 4 workers, recording 2 engines gated on 20 GB of free commit (`replay_orders.free_commit_gb`).

Radar on the model's side (his 11-18: "We no longer seem to be making radar in the early game which makes it hard
to deal with raiders"; "its not an issue with this model, but if you could fix it that would be good"): in his own
MP games our first radar stood at a median 2.6-3.7 min (11-16..18, 44 seats, `tools/armynet/radar_history.py`); in
the watch games side B built it at 4-6 min and the model's side none or after 9 min (`radar_builds.py`). No gate
refused it; the sense want was simply priced low (in 3 decisions at v 26-62 against side B's 153 at 35-129):
`ArmyCoverSample` counted every combat unit near home as guard cover, and the model's army sat at home, so the
base read as covered. Units on a PLAYER task (hands-off) no longer count as cover (guardposts.as); no unit has that
task in a normal game. To check on the next watch: the model side's first radar against side B's.
Watch games run one faction both sides (his standing 11-05 ask, repeated 11-18) and verbose.

## Raiding (his 11-19: "we're still not raiding well at all so they are hurting our economy but we are never
hurting their economy")

Gaps found and closed: (1) a queued route was labelled at its first leg (`queued_routes.py`, 40 duels: 4.7% of
bursts; the end a median 1,259 elmos further, forward 0.81 vs 0.63; 1,281 of 3,592 deep routes labelled shallow) --
the decision's target is now the route's last waypoint (decision column 9 = 1); (2) the rating did not see economic
damage -- `eco_near`/`eco_side`: economy buildings (by name: mex, moho, solar, wind, tide, fusion, geo, makers)
destroyed, theirs minus ours, near the target 3/10 min and side-wide 10 min; (3) the model could not see an
extractor beside a plant (one metal-weighted building layer) -- two count layers, their economy buildings as last
seen and ours (25 channels); (4) nothing measured raids -- `deep_recall` (of the players' orders past 0.7 of the
way to their base, the share the model also sends there) and `deep_model`/`deep_player`. Also: the campaign's held
2e-4 rate let the held-out place error drift 668 -> 680 -> 701 over 30k steps; it now decays as 1/sqrt past 5k.
Open: the model plays its single most likely place; a raid is a minority choice for any one unit.

## Headless games and the gap report (his 11-19: "stop the watch games for now ... run some on your own and
figure out where the gaps in our training are"; "do this periodically")

`campaign.py --headless 2`: two windowless games per 10k-step checkpoint (factions alternate by seed);
`tools/armynet/gaps.py [campaign dir]` reports per game: result, extractors/income/army at 6/10/14 min both sides,
their extractors each side killed, raider repeats, ground given up, first radar, and the model's forward/deep share
in play (serve.log, per minute) beside the held-out eval's. An hourly check runs it (session cron).
Previous campaign's four games: their extractors killed by 10 min A 0-3 vs B 2-12, in all 15-20 vs 52-71; first
radar A 9-17 min or never vs B 4-6; at 10 min A's army was bigger in two of four. Held-out (raid-fix run, 2k-8k
steps): the model sends 31-33% of orders past 0.7 (players 34%), deep_recall 0.72-0.74 -- so offline it raids
as often as players; the open question is what happens in play.

## Overnight hourly checks (11-19)

01:26. Health: campaign-20261119-0052 at step 24k, ~12 steps/s, no errors; first headless game done; recording
328/1616; free commit 19.8 GB. Game (step 10k, Armada): lost at 38:54, the longest yet; their mexes killed in all
57 vs 83 (15-20 vs 52-71 before), ground given up 0.47 vs 0.37; but by 10 min 1 vs 4, first radar 17.3 vs 4.6.
Biggest gap: orders deep in play 1.7% against 31.6% on held-out player states (players 33.7%). Not a train/play
mismatch: `parity.py` (14 moments, 3 duels) gives identical inputs and identical best cells on both paths. Not
composition: side A's army is faster than players' (100-126 vs 83-95 elmos/s metal-weighted, `army_speed.py`,
`players_by_minute.py`). Not lateness: players go deep from the start (29-36% at minutes 0-5; 21-26% all game),
the model's forward median in play was 0.04 at minute 2, 0.17 at 5. Next: serve.log now logs the probability the
model puts on deep places (`deep mass`); if that is real while its best place is never deep, sample the place
(at least for fast units) instead of taking the best.
Performance (`bench.py`): bf16 115 vs fp32 112 ms/step, channels_last 109 -- no gain; batch 32/64/128 = 112/237/456
ms, linear, so the GPU is busy, not idle on overhead; data workers keep up (2.4-4 ms per example). The cost is the
full-resolution 64x64 layers (memory-bound on this card). Candidate, needs a fresh training and his say: slimmer
full-resolution layers. Nothing changed in the running campaign.

02:26. Health: step 70.6k, ~12.6 steps/s, 10 game results, recording 391/1616, free commit 22.7 GB. Games at
10k-50k (5 pairs, all lost, 15-40 min): deep orders in play rose to 3-21% (1.7% at 10k); the deep probability
mass is about the same (10-29%), so the best-place rule is not hiding raids -- sampling ruled out. Their mexes by 10
min A 0-5 vs B 3-12; radar still late on A (10-17 min vs mostly 4-7). Biggest gap (`trades.py`): fights. Mobile
metal killed per lost at 10 min: A 0.44-0.82 in all 11 games, B 1.25-3.31, with armies about level. Likely cause:
87% of player orders are plain moves and players steer fights by re-clicking a fraction of a second apart, which
the 1.5 s collapse removes; the model's units walk into fights on a move. Test: `serve.py --engage` (a move toward
their side becomes a fight order; a move back toward ours stays a move), step-60k checkpoint, seeds 12 and 13,
against the campaign's own games on those seeds. Held-out place error still above keep-or-stand (675 vs 580 at
70k; rate now ~0.17 of peak).

03:26. FIRST WIN: campaign step 60k, seed 13, Cortex (armynet-watch-20261119-022655): won at 31:36 -- 44% of orders
deep, their mexes killed 87 vs 34 (8 vs 1 by 10 min), side B gave up 0.91 of its ground, mobile kill/loss at the
end 1.10 vs 0.21. (campaign.log filed it under the engage test's match: two runs overlapped and "the newest new
folder" took the other's; campaign.py now reads the folder from watch.py's own write-dir line.) `--engage` lost on
both seeds (10-min trades 0.15 vs 0.64; seed 13 a loss instead of the win) and is deleted. Later checkpoints
(70k-110k, 10 games): all lost, 19-40 min; early fights sometimes won (A 0.92-1.32 at 10 min in four), late ones
lost. Overfitting: held-out place error 597 (2k) -> 680-730 (50k-114k) while the training place loss fell
5.8 -> 4.4; act log-loss flat. Fix: `--mirror`, each training example mirrored left-right and/or top-bottom at
random (positions, headings, targets and place labels follow; `mirror_check.py`: exact on 161 labelled examples x 3
flips); the campaign restarted from the step-60k checkpoint that won (kept as runtime/armynet/best-won-060000.pt)
on 409 duels, 51 held out (a new held-out set: compare within the run).

04:26. Mirroring works: held-out place error 624 -> 583-601 (keep-or-stand 590), falling where the last run rose;
deep 31-33%; 13.2 steps/s (no cost), GPU 87%. Games 10k-30k (6, all lost, 23-39 min): fights still lost at 10 min
in 5 of 6; A's income at 10 min lower in 5 of 6 (49-63 vs 75-122 on Armada); A's first radar 13.8-14.9 min in every
game. `early_builds.py`: radar wins no decision on either side in minutes 2-10; side A builds about twice the
defence (42-67 vs 19-51 decisions) and less energy -- the same before the 11-18 cover change, so not that change:
A's AI buys turrets because raiders reach its base. Offline the model does answer raids (`response_recall` 0.87:
of player orders aimed at an enemy within 1,200 of our buildings, the model aims there too) and its order chance
there is 0.25/s; but the order chance barely separates units the player ordered (0.21) from those left alone
(0.13), and each unit is drawn alone in play while 74% of players' orders go to 5+ units in one frame -- the army
gets its orders one unit at a time and reaches fights piecemeal. Test: `serve.py --group-act` (units within 400
elmos share one draw), step-40k checkpoint, seeds 8 and 9, against the campaign's own games on those seeds.

05:26. Two more wins: the paired test's plain arm, step-40k mirror checkpoint, seed 30 (won 31:12), and the mirror
campaign's step 60k, seed 13 (won 30:48; seed 13 also gave the first win, so that map seed may suit it; that
checkpoint kept as runtime/armynet/best-won-mirror-060000.pt). Mirror-run early fights often won or level (A's
kill/loss at 10 min 0.39-1.67; the paired test's plain arm averaged 1.09) but ends lost (0.22-0.41). `--group-act`
lost (`paired.py ga2`: worse in 3 of 4 pairs, turned the seed-30 win into a 23:48 loss) and is deleted. Late game:
players' orders thin out after minute 18 (70,860 at 9-11 min vs 9,320 at 21-23, 5,684 at 24-26) while our games run
25-40 min; held-out place error trails keep-or-stand by 37 elmos before minute 18 (5,096 orders) and by 76 from
minute 18 (789 orders; evaluation now reports `dist_early`/`dist_late`). Fix: `--late`, moments at minute 18+
sampled by how much rarer their band is than the peak (2.9x at 18-20, capped 4x from 21). Campaign restarted from
model-090000.pt (start step 158000) with --mirror --late, on 517 duels, 61 held out. Speed unchanged (12.6 steps/s).

06:26. `--late` works offline: held-out (61 duels) place error before minute 18 539-566 vs keep-or-stand 584, from
minute 18 427-483 vs 558 -- the model now beats keep-or-stand in both phases (a new held-out set; compare within
the run). Fourth win: step 30k of this run, seed 6, Armada, won at 11:06 (47% of orders deep, 8 of their mexes by
10 min vs 6). Losses unchanged in kind: 10-min trades 0.23-0.91 vs 1.3-3.9, A's army often smaller at 10 min,
first radar 15-19 min. No change this hour (let --late train); 13 steps/s; recording 628, commit at the gate.

07:26. The report tools called a game with no winner "lost"; 40-minute games that hit the cap are draws (fixed in
trades.py, gaps.py, gaps_table.py). By run: plain 0 won / 1 draw / 20 lost (its real seed-13 win filed under the
engage match), mirror 1/0/13, mirror+late 1/4/7. The step-70k mirror+late draw on Armada: A's 10-min trade 3.86 vs
0.96 and income 131 vs 69. Held-out early 552-559 vs 584, late 430-541 vs 558. Draws hide the result, so the
campaign's games now run to 60 min; restarted from model-090000.pt (start step 248000) on 627 duels, 78 held out.

08:26. Run 0727 (mirror+late, 60-min games, from 0528's 90k): six games, all lost, 12.6-44.4 min; on the same
seeds 6 and 7 the previous run won / drew. 10-min trades 0.30-1.02 vs 1.02-3.75; A's army at 10 min smaller in
all four of the newest (955 vs 3,750; 705 vs 1,665). Held-out sets differ per run (the game list grows), so
"getting worse with more steps" cannot be read off the evals: five checkpoints (the two winners, the step-70k draw,
0727's 30k and its latest) are being scored on one held-out set (runtime/armynet/fixed-eval-0826.txt). If later
checkpoints score worse on it, play the best-scoring one and stop the decay of the rate from running down.

Fixed held-out comparison (one set, fixed-eval-0826.txt): place error (keep-or-stand 649 / early 702 / late 443)
-- mirror 60k winner 601 (645 / 394), 0528 30k winner 615 (664 / 408), 0528 70k draw 617 (664 / 427), 0727 30k 591
(631 / 411), 0727 latest 585 (619 / 415). No checkpoint got worse offline; the most accurate one loses games the
less accurate ones won. Imitation accuracy does not rank checkpoints by play, and two games per checkpoint cannot
either. For him: choose checkpoints by a larger set of games, and add learning from game outcomes on top of the
imitation.

09:26. Fifth win: run 0727 step 50k, seed 11, won at 40:42 after losing the early fights 0.30 vs 5.35 at 10 min (a
comeback). 60-min games resolve the long ones (losses at 45:30 and 37:12). Run 0727: 1 win in 11; the night: 5
wins. Healthy (step 92.8k, recording 843, commit 23.8 GB). No change: next steps wait on his choice (checkpoint by
games; outcome learning).

10:26. Run 0727 checkpoints 70k-130k: 8 games, all lost (20.5-53.4 min), 10-min trades 0.31-0.90 vs 1.1-5.1. Run
total 1 win in 19. More imitation steps at a rate now ~0.08 of peak are not turning into wins; the winners are
kept (best-won-060000.pt, best-won-mirror-060000.pt, 0528/model-030000.pt, 0727/model-050000.pt). Healthy (step
140k, recording 914, commit 19.2 GB at the gate). No change, pending his call.

11:00 watch (his, 0528/model-030000, Armada, seed 6): lost at 14:52; no orders deep (deep mass 0.029), their mexes
by 10 min 0 vs 17, income 44 vs 147, army 640 vs 4,385, trades 0.23 vs 6.75. He: "we pretty much aren't raiding at
all and its a huge problem for us, they slow us down but we don't slow them down, we chase their raiders with more
than we need to"; "its possible that the way humans play against each other is NOT good for playing against AI".
Players (80 duels, `responses.py`): answers to raids near their buildings send a median 0.79x the raiders' metal (3
units, q75 10); raids go in groups of 2 (q75 6) at speed ~85. Cause of over-chasing: every unit draws its order
alone and none sees what the others were just given. Options put to him: train on his human-vs-AI replays
(weighted to human wins), round-by-round decisions (later units see earlier units' new orders), and learning from
the model's own games against our AI.

11:26. Run 0727 checkpoints 130k-170k: 8 more games, all lost (12.6-40.3 min, mostly under 26), 10-min trades
0.19-0.91 vs 1.08-6.25 -- later checkpoints keep getting shorter losses; the run is past its useful point (step
186k, rate ~0.07 of peak). Free commit 14.2 GB (his ComfyUI 13.9 GB, vmmem 8.2 GB, ours ~20 GB); the recorder's gate
holds new replays. Recording 981/1616. Waiting on his choice of data/outcome learning.

## Traced-back credit (his 11-19)

He: 1v1 players raid each other constantly, so the raiding is in the data and training misses it; "trace that
back. You need to work backwards and understand all the steps that it took to get them there not just the immediate
action that was taken to kill a metal extractor, but all the work that was done to make it across the map ... all
the planning and all the foresight that goes into the final victory of an action". Built: `eco_traced` (outcome
column 7) -- each hit a unit lands on an enemy economy building credits every order that unit was given before it,
halving per HALF (the time to cross the map's mean side at players' median raid speed 85 elmos/s, ~84 s on Comet
Catcher), out to 3 x HALF, summed over the order's group; in the rating as one more measure. One duel: 1,210 of
3,384 orders credited, 590 of them approach orders the near-the-target measures gave nothing; credited orders
weigh 1.54 on average against 1.13. Whether the opponent is an AI is known in play (the start script marks AI
seats) but the duel data is all human, so it is not an input yet. Old campaign (0727) stopped past its useful point;
datasets rebuilt with the trace, campaign restarted from 0528/model-030000 (the run with the best record) with
--mirror --late, 60-min games.

## Tasks (his 11-19)

He: "the same set of units are continuously being moved so you kind of know, like, 'All right, those units are on a
task together.' And there may be a moment where all of a sudden those units are broken off or they start getting
used separately ... definitely need work on that macro vision"; and 10-30k steps were already about as good as now,
so fix what training teaches rather than train longer. Built (`tools/armynet/tasks.py`): a group is one moment's
orders of one kind whose targets lie within 600 elmos (lines are ~250); a group continues the task holding at least
half its units, else starts one; units go with their latest group (so tasks split and merge); a task ends after 120
s without an order. Players (2 duels): 85-90% of unit orders sit in tasks of 3+ units and 3+ groups, typically
10-11 units and ~15 groups. Uses: decisions column 10 = task, `task_starts` per game; `eco_traced` now credits the
whole task's later economy hits (decoys and escorts share a raid's credit); eight unit inputs (columns 28-35: in a
task, size, age, travel since it formed x/z, task-mates' centre x/z, time since own last order), from orders before
the moment only; serve.py builds tasks from the model's own orders by the same rules (`parity.py` still identical);
mirroring flips the new x/z inputs (`mirror_check.py`: exact; 98% of units in a task). replay_dataset.py `--jobs N`
rebuilds in parallel. Rebuilding all, then the campaign restarts from 0528/model-030000 (unit input widened 28 -> 36,
new weights zero).

12:26. Parallel rebuild (--jobs 6): ~1,000 games in ~20 min, no failures. Campaign 1155 (tasks + traced credit,
mirror, late, from 0528/30k): 901 duels, 98 held out; held-out place error 674-701 vs keep-or-stand 744; deep
30-32%; 12 steps/s, GPU 72%. First two games (step 10k): lost 27:42 and 36:42, but deep orders in play 29-34% (the
offline 31%; earlier games 0-21%); Armada game A ahead at 10 min (33 vs 18 mexes, income 104 vs 68); serve.log
tracks ~15 live tasks. Their mexes killed over the game still A 23 / 50 vs B 95 / 88; A's first radar 9.8-12.6 min
vs 3-3.9. No change; next results at 20k.

13:26. Tasks campaign 1155, 7 games: a win (step 30k, Cortex, 38:24: 41% of orders deep, their mexes 101 vs 42,
end trade 1.13 vs 0.31; kept as runtime/armynet/best-won-tasks-030000.pt); A's income at 10 min level or ahead in 4
of 7. Still: A loses 78-168 mexes over a game -- over-chasing raids, as he said. Built rounds: training `reveal`
shows a random share (uniform 0-1) of the units the player ordered that second as already decided (columns 36-38:
ordered, target dx/dz from the unit /2000) and leaves them out of the loss (`lossmask`); serve.py `--rounds` decides
a random third, shows those orders to the rest, then the next third (three forward passes a second); mirroring flips
37/38; `model.load_state_dict` replaced by `load_widened` everywhere (old checkpoints load, new inputs zero). Smoke:
100 steps, then a 6-min headless game with --rounds, no errors, 9-10 live tasks. Campaign 1331 (tasks + traced +
rounds + mirror + late, 60-min games) from the tasks winner, 1,019 duels, 107 held out.

## His watch 11-19 13:48 (rounds campaign 1331 step 10k, Cortex, seed 41): lost at 24:13

His notes while watching: the first raid killed an extractor "and then it just stayed still ... it had nowhere to
go after that it didn't understand like oh I should probably just continue and do more raiding"; the second move
went "straight up attack right into the center ... meeting their army we ended up losing"; "when I see us fighting
we looked better than them"; "we have lost most of our army because we kept engaging when we probably should have
stopped engaging"; income 81 vs 208 at ~18 min, "they have this way of pushing us at many different areas ... and
then we don't push them so we lose like a mex here and a mex there"; "I only saw that first raid"; "one mammoth is
... just kind of walking around on his own"; two Dragons, "we make no preemptive kind of AI really"; "we just take too
many hits to our economy and we don't dish them out". Numbers: 10-min trades 0.41 vs 3.90; their mexes killed A 21
vs B 51 (2 vs 3 by 10 min); deep orders 19%; A's first radar 8.0 min vs 13.7.
Training causes: (1) raiders idle in their territory after a kill are a state players almost never leave units in,
so the model's chance to act there may be low -- to measure (players' and the model's time from a kill to the
killer's next order); (2) the rating scores what follows an order in absolute terms, so a retreat out of a losing
fight still looks bad and is marked down -- rate the change in the units' trade instead (after minus before).

Measured after his watch: (2) did not hold -- `retreat_check.py` on 3 duels, 348 retreats out of fights: mean
weight 1.36 -> 1.33, 1.31 -> 1.30, 1.22 -> 1.22 with the after-minus-before trade (measure 8, now in the rating in
place of the absolute 5/15/60 s trade; kept as more correct, not as the fix). The real gap (eval `retreat_recall`,
rounds model 10k): when players pulled a unit back out of a fight (target 0.1+ back toward their buildings, enemy
weapons reaching its cell), the model sent it back 32% of the time (raid answers 74%, deep 73%); its order chance
there 0.127, no higher than for any ordered unit. The model had no view of a fight turning. Built: unit inputs 39-41
(health now minus 5 s ago; log enemy army metal in sight within 800 minus log ours; log our metal within 800 at -10 s
now gone), computed from the unit samples (no rebuild), same in play (`parity.py` identical, `mirror_check.py`
exact). `fight_signal_check.py`: retreats vs other orders -- health change -0.035 vs -0.006, enemy-minus-ours -3.17
vs -4.54, recent losses 1.80 vs 1.31. Campaign 1358 restarted from the rounds model at 18k with the three inputs.

## Incoming fire, and the packed-hit bug (his 11-19)

He: players "might not see enemy artillery that's hitting them or defensive emplacements that are hitting them, but
they certainly see the shots". Built: map layers 25 (metal value of hits on our side's units over the last 10 s,
where they land) and 26 (where those shots came from, smeared 300 elmos: a shot's trail shows its direction, not
the shooter's exact spot) -- CHANNELS 27; datasets keep every hit (`hits`); the gadget's synced half sums hits on
our side each second and the state file carries them as X lines; serve.py keeps 10 s of them (`parity.py` with
hits: identical). Found while checking it: the recorder (and the first gadget version) packed each hit as one
number, attacker * 2^20 + victim, and Lua's float32 rounded the victim's low bits away once attackers were known
(the 11-18 19:14 last-attacker fix): every recording since then has wrong victims on its known-attacker hits, so
the units' own trade, its change and the traced economy credit worked mostly from the hits without an attacker.
Fixed in the widget and gadget (by attacker, then victim). Recovery for the recordings (`recover_victims`): the
victim is the enemy unit sampled that second within one rounding step of the recorded id, nearest the attacker
within its range + 500 -- 3 duels: 70-80% of known-attacker hits recovered (a third of those ambiguous, chose the
nearest), the rest dropped. All rebuilt with it; the 1,168 affected recordings renamed orders.packed.txt.gz
(`requeue_packed.py`) so the recorder records them again cleanly, newest first. Campaign restarted from the
fight-input run's 6k checkpoint.

14:26. Rebuild with recovered victims at 441 games; campaign waits on it (chained), so no new games this hour.
Self-review: `recover_victims` looked up each attacker's type by scanning the whole unit table per hit (the slow
rebuild); now a per-game table (same result, ~1 s a game). Recording 1,183; commit 29.3 GB.

15:26. Rebuild with recovered victims done (1,170, none failed); 1,175 recordings requeued, re-recording under way
(87); campaign 1504 (everything + fire layers, from fight-latest 6k) at 11k steps. One held-out set for three
models: retreat recall 21.7% (rounds 18k), 19.2% (+ fight inputs 6k), 17.8% (+ fire layers) -- the fight inputs
did not fix retreats by themselves; the earlier 32% was another held-out set. But the model knows: when players
retreated it put 31.5% of its probability behind the unit (`retreat_mass`), 10.7% when they did not; its single
best cell was nearly always forward (two answers, push on or pull back; pull back spread over many cells). Test:
serve.py `--region-sample` -- choose back / hold / forward by the model's own probability on each, then its best
cell there; paired against the plain best cell, step-10k checkpoint, seeds 50-53 (`paired.py rs`).

16:26. `--region-sample` paired test, 3 of 4 seeds (step-10k checkpoint of 1504, rounds on): 10-min trades plain
0.29 vs region 0.62, 20-min 0.50 vs 0.61, end 0.25 vs 0.32, length 24.6 vs 31.4 min; per seed 0.24/0.43, 0.39/0.29,
0.36/1.14 at 10 min; all lost. Adopt if seed 53 does not reverse it. Campaign 1504 at 28k: 4 games, all lost
(20-24 min), 10-min trades 0.19-0.77. Re-recording 131/1,175; commit 17.1 GB (recorder holds at the gate).

Direction first ADOPTED (paired, 4 seeds 50-53, step-10k checkpoint of 1504): 10-min trades 0.57 vs 0.29 for the
single best cell, 20-min 0.61 vs 0.50, end 0.32 vs 0.25, games 32.8 vs 24.6 min (longer in 3 of 4); no wins either
way. Now serve.py's only way to choose a place (no switch); the campaign's games and watch games use it.

## Seeing why a game was lost (his 11-19)

He: "break down into some more detail, like how much building/army metal is lost/killed, a 3d view (time as 3rd
dimension) ... I won't always be around to understand why we fail"; then "a render of the map over time ... you
know best of your own capabilities". I read still images, not video, and a 3D plot of 37 minutes overlaps into
nothing (tried, dropped). Built instead: `game_report.py` (report.md: metal lost by kind per 4 min, extractors /
income / army by minute, battles and how many A entered outnumbered, killers by unit type, reach = map squares the
army stood on and the other side's extractors it came within 800 of) and `timelapse.py` (lane.png: every army unit
at every 10-s snapshot by its place on the A-B line over time, deaths, metal lost per minute, army and income;
film-N.png: the map each minute with 60-s trails; timelapse.gif for him). The campaign runs both after every game;
`reports_summary.py --campaign <dir>` gives one line a game.

First reading, 7 games (campaign 1504 + the direction-first test game), all lost:
- B's army stands on 11.5-12.8 of 16 map squares, A's on 4.0-9.3; B comes near A's extractors 1.3-6.7x as often;
  A loses 3-36x the economy metal B does. The lane diagram shows why: A's army is one blob that parks (flat
  streaks) at 0.15-0.45 of the line; B sends streams out and wide. The filmstrip: B's east half, with dozens of
  extractors, never sees a blue unit.
- B's top killers include bombers (armthund, corshad) in 4 of 7 games: air raids on A's economy.
- The 37-min game ended with a nuke (corsilo 140k of A's metal, the commander) after gunships killed A's anti-nuke
  while it was being built: not a ground-fight loss at all.

Metal spots as raid points (his 11-19: "are we aware of how often the units in training are going near a mex spot
or geo? those are general POI areas for raiding"). `poi_rate.py`: share of ground-army time within 500 of a metal
spot past the middle, 3-10 / 10-20 / 20+ min. Players who won (143 duels) 22.7 / 27.7 / 26.8%, their orders to such
spots 35 / 43 / 54%; players who lost 16.4 / 15.7 / 8.6%; the model (6 campaign games) 6.5 / 3.0 / 0.3%; our AI's
army against it 21 / 50 / 61%. The data is full of it; the model does a quarter of it even before it is pinned.
Geo vents are in neither the recordings nor the inputs. Inputs page for him: https://claude.ai/artifact/2UskqTZ7hqDCYqFKJC6KM5
Offline the model HAS it (train.py eval `far_spot_*`, campaign 1504 model): of players' new orders 43.1% go within
500 of a metal spot past the middle, the model's 42.2%; it puts 70% of its probability there when players did, 22%
when not. So the gap is in play. Found: serve.py reads only the newest state, so at 10x it skips every game second a
decision takes longer than 0.1 s real -- its 10-s log line fired for 40% (game 1642) and 81% (1623) of the 10-s
marks, i.e. it decided on that share of seconds, each time with the one-second chance of a new order: units got
40-80% of the orders the act head means. Fixed: a decision after k seconds acts with 1 - (1 - p)^k; serve logs
decisions per minute, the mean gap and compute time. Seed 60 (15 min, alone on the machine): every second decided,
0.06-0.14 s each, so the skipping comes with load and army size; the fix covers it when it happens. Its orders went
deep (36-76% past 0.7 in minutes 6-12) and A killed some of B's buildings at 0.75-0.9, but A's army stayed small
(2-3k vs B's 5-10k): A's economy fell behind before any losses. `spend.py` + stats by minute 8: A built defence
2,515 vs B 1,590, economy 2,237 vs 5,202, build power 1,890 vs 3,280, having lost 190. Suspect: my 11-18
guardposts.as change counts model-held units as away (`theirs`), so A's AI reads its base as uncovered whenever the
model moves out and prices defence up and economy down. Not the only cause (he saw "economically behind" before it).
Next: paired games with and without it, between campaign games (deploying mid-game changes running games).
REVERTED 17:21 (he: "It is easy to have one seemingly benign change have a dramatically negative effect"): it was
never measured and did not fix the radar it was for; smoke ok. Check: A's defence and economy built by minute 8
against B's in the next campaign games, against the 17:06 game's 2,515 / 2,237 vs 1,590 / 5,202.

Unmeasured changes now in play (each needs its measurement): serve.py skipped-second compensation (17:00; check:
orders per unit-minute in play vs players), movement inputs (below).

## Leaving fights and the worth of economy damage (his 11-19)

He: "lack of recognition of EXITING a fight - moving away from enemies - and preserving army/health"; "eco damage is
one of the best forms of damage we could possibly rate"; "making the enemy take damage while taking not so much
damage yourself is like Huge"; an extractor lost for a minute costs "the 50 metal of it dying plus maybe 2 to 3 metal
times 60 ... and then the builder who remakes that has to be redirected into doing that work, so the cost ripples".
- `retreat_scores.py` (120 duels, 7,558 orders with enemy army within 800): outnumbered 1.5x+, players pull back on
  57% of orders, yet those score 0.30 vs 0.35 for pressing on (trade over 60 s -582 vs +299): the rating measures
  what happened, not what staying would have cost, and press-on cases are fights judged winnable. own_change (after
  minus before) does not fix it. The rating pushes against leaving. Fix to build: score against what units in the
  same situation got (a baseline by fight state), so a retreat earns the loss it avoided.
- Economy kills valued by income lost (`economy.py`: extractsmetal x 2000, energy / 60, converters; `eco_values` in
  replay_dataset.py): price + income x time until the owner has a finished economy building within 150 again (or the
  game ends), up to 600 s; hits on economy buildings scaled by that def's mean value / price. Not yet counted: the
  rebuilding builder's lost work (the ripple).
- Found a label bug while checking it: about half of extractor removals and most other economy removals have no
  attacker (upgrades to moho, reclaimed solars) and every measure counted them as losses (eco_near/eco_side/area/
  team). Now only enemy kills count: a known enemy attacker, or none recorded with enemy hits in the last 10 s.
  Extractor kills then come out at a median 4.5-6.6x price (down ~2-4 min) in 3 of 4 test games.
- Not rebuilt yet: three agents (his ask: his directives, game mechanics (Fable), the training method) are reviewing
  first so the changes go into one rebuild.

## The reviews and the third-of-a-second rebuild (his 11-19, evening)

He asked for agents ("using agents to come up with new ideas just in case you've missed something ... one fable"):
three reviewed his directives, game mechanics (Fable) and the training method. All three put first that model-held
units have no footwork: their PlayerTask is empty, and training merged clicks within 1.5 s and decided once a second.
`click_rate.py` (15 duels, 160k re-orders): in fights players re-order a unit every 0.23 s median (57% within
0.33 s, 77% within 1 s); out of fights 0.40 s. He: "I'm thinking we should really be using complete movement
learnings from players, and use NO BARb fight logic"; "under 500 milliseconds". Built for the overnight run:
- Decisions every STEP = 10 frames (replay_dataset.py, data.py): a click per unit per step, shift-queued waypoints
  still one route. One duel: 3,579 decisions -> 10,209; another 66,515.
- Recorder samples mobile units and hits every 10 frames (replay_orders_widget.lua); all recordings to be
  re-recorded (`requeue_rate.py` keeps the old ones as orders.1hz.txt.gz; the builder falls back to them). Until
  then, steps between once-a-second samples are filled by moving each unit along its recorded velocity
  (Game._fill_steps; the past only, no look at the next sample).
- Gadget writes state and hits every 10 frames; serve counts catch-up in steps. A decision took 225 ms at the new
  rate; vectorising (radar sighting, ally lookup, region choice) and folding history (`fold_history`: every sample
  for RECENT_S = 20 s, older ones only as memory reads them) brought it to ~60-80 ms with 3 rounds -- fits about 4x
  game speed, not 10x (campaign `--speed`, default 4).
- Fixed, found by the reviews: serve forgot enemy buildings after 5 min (training remembers them all game: by
  minute 18, 57% of remembered building metal); health/loss inputs read 0 when serve skipped seconds (`rows_near`);
  hidden information -- attack targets among unseen enemies, unseen shooters' true positions in the fire layer (now
  500 elmos toward them), radar blips carrying their true type (now only after a sighting). parity.py had tested
  only early frames with a plain window; it now uses serve's own fold and frames across the game: identical.
- Rating: each measure against the same side's orders in the same 30 s; no winner bonus; side-wide 10-min columns
  dropped (`rating_check.py`, 40 duels: variance explained by side x window 85% -> 10%, winners' / losers' mean
  weight 1.58 / 1.00 -> 1.09 / 1.08). Own trade now against units that stayed in the same odds band (`stays`,
  `dec_odds` in each dataset; `_stay_baseline`). The act loss counts each sampled quiet step 1 / neg_share times
  (the order rate was 2.4x players').
- Inputs: enemy air layer (27), our anti-air reach (28), our income and theirs as last seen (scalars 6-7, from
  `economy.py` via a defs column).
Retreat check on 40 duels rebuilt with all of it (31,194 orders in fights): side x window explains 16% of the score,
winners' / losers' weight 1.11 / 1.10. Pulling back while outnumbered still scores a little below pressing on (0.186 vs
0.226; weights 1.10 vs 1.12), also with the baseline matched on being under fire (dec_hit / stays column 7). Per
measure (`retreat_scores.py` prints them) the gap is in the own trade itself (+0.12/+0.10/+0.07 vs +0.20/+0.20/+0.12)
and economy kills near the target (pressing on reaches economy): players who press on "outnumbered" know what the
odds bands do not (the enemy hurt, out of range); those who pull back are worse off than the band says. Buckets
cannot separate it; a learned value of the state (a value head, advantage = outcome - value) can. Next after the
overnight run. The rating no longer pushes meaningfully against leaving (2% weight); the step-rate footwork data
is the larger change for it.
Still open, named by the reviews: the act head weighted by outcome; on-policy fine-tuning (his call, pending);
the rebuilding builder's lost work in the economy value; per-group token weighting; split held-out by player.

11-20 03:21 check. Overnight run (`overnight_step.sh`) started ~02:55: gadget deployed, 335 recordings requeued at
the step rate (the ~1,175 packed ones were already waiting), rebuild 511 of ~1,510 (none failed), campaign waits on
it. Found: two recorders running (the first, stopped attempt's nohup'd `follow` outlived TaskStop), six engines at
below-normal priority starved by the six rebuild jobs (25 min on replays that take 1-4), 0 recordings in an hour,
commit down to 10.6 GB (gate 20). Stopped both (by process id; the guard forbids killing engines by name) -> 28.4
GB; the recorder now starts on its own when the rebuild ends. Lesson: a script's nohup children survive TaskStop --
stop by command line. Parity on a dataset from this rebuild: identical across the game.

04:20 check. Rebuild done (1,270, none failed); campaign 0407 started (from move-init, widened 27 -> 29 layers and
6 -> 8 scalars), step 3,800, no errors, 4.9 steps/s, GPU 72% (examples 8.0 ms; GPU-bound, not data). The recorder
never started: my waiter looked for 'replay_dataset.py' in command lines and matched its own check. Started
`follow --workers 3` directly. No games yet.
~04:50: the trainer died at step 10,200 -- PermissionError renaming model-010000.tmp into place while the test
game's serve had the file open (Windows). train.py `save_atomic` now retries for a minute. Campaign restarted from
model-010000.pt with --start-step 30000; the old campaign finishes its one step-10k game.

05:20 check. First games at the step rate (campaign 0407, step 10k, both lost at 21.5 / 25.5 min): 10-min trades
A 2.15 / 0.90 against B 0.72 / 0.88 -- the first time the model wins or ties the opening fights (last night A
0.2-0.9, B 1.4-6.6); 20 min 1.29 / 1.40 vs 0.73 / 1.40; army metal lost about even (11.7k vs 11.9k, 15.5k vs 12.2k).
Lost on economy instead: A lost 9.4k / 20.9k of economy against B's 2.2k / 1.3k, B gained 20+ extractors on A in the
4 min to minute 20-24, A's army sat at 0.16-0.18 of the way in the second half (B 0.24-0.36); a nuke in game 2.
Biggest gap now: protecting and taking economy in the middle game, not fighting. Too early to read training causes
off 2 games at step 10k. Serve at 4x: a decision every 1.43 / 1.46 steps, 0.13-0.16 s each; mean p 0.014-0.020 per
unit per step (players ~0.026 per step; with the catch-up ~0.02-0.03). Campaign 0447 at 8k, no errors, ~4.2 steps/s
with games running; recorder 25 re-recorded, commit 18.7 GB (it waits at the gate).
~05:35: the trainer died at step 10,800 of campaign 0447 -- MemoryError in a data worker: two test games plus
three recorder replays (each engine ~4.5 GB) took the commit; the recorder checks memory only before a launch and
engines grow after. Recorder now one worker while training runs; campaign restarted from 0447's model-010000.pt
(--start-step 40000; two runs of 10k steps so far, each from the last checkpoint).

06:20 check. Campaign 0557 at 8k (overall ~28k at the step rate), no errors, 5.8 steps/s; GPU 5% at the moment of
sampling (the step-8000 evaluation runs then). Commit 34.3 GB with one recorder engine; 60 re-recorded. No games
since the restart (next at 10k).

07:20 check. Campaign 0557's step-10k and 20k games: B won all 4 (19-29 min), A lost 10-45k of economy vs B's
0.7-3k, and A's opening far-spot share fell with training: 0.143 (0407), 0.093 (0447), 0.031 (0557). The model went
quiet: live mean p 0.010-0.016 at minutes 0-5 falling to 0.000-0.004 after minute 10. Cause found offline
(since_check.py, held-out games): players order a unit in 5.1% of steps, the model's chance was 1.05%. `reveal()`
(rounds) showed only units the player DID order, so "nobody shown" nearly always meant a quiet step and taught a 0.63%
rate (reveal check: 0.0063 none shown, 0.168 some shown); serve's first round shows nobody. Fix: a random share of ALL
units is shown, new unit input 47 = decided this step (serve marks the earlier rounds' units the same), TOKEN_F 48,
the old weights kept and the new input zero. Parity identical. Restarted as campaign 0726 from 0557's last checkpoint.
Measure: since_check.py on its 10k checkpoint (model chance vs the players' 5.1%, per age bucket), live mean p by
minute (p_by_min), far-spot share and the 4 games' economy lost, against 0557's step-20k numbers above.

08:20 check. Campaign 0726 at 19.6k, no errors, 6 steps/s, GPU 81%, commit 34.2 GB. Step-10k games after the reveal
fix: live mean p 0.05-0.07 in minutes 0-10 (0557: 0.010-0.026), 0.01-0.06 later (0557: 0.000-0.018); far-spot share
3-10 min 0.142 (0557 0.031), 10-20 min 0.196 (0.014). Offline model chance 1.05% -> 1.77% of unit-steps against the
players' 6.6% in the same sample; most of the shortfall is units ordered in the last 6 s (players 15.2%, model 3.4%:
re-clicks, kiting), so the act head is still catching up; judged again at 20k. Both games still lost (31 and 27 min,
economy lost 38k and 17k vs 2.8k and 4.0k); in 080419 A had 420 army metal at minute 8 vs B's 1,130, and spent 2.7k
on defence by minute 10 vs B's 1.3k. Serve: 1.02 steps between decisions, 0.09 s each.

08:45 his watch (084245, Comet Catcher, Armada mirror, the 0726 model at ~26k, 4x), closed at 17 min. What he saw:
no radar, so the army never knew where to be; outlying extractors with no turret, and one enemy Tick ran through the
base killing them while our units chased it and could not catch it (one LLT would have ended it; we make no Ticks);
B's towers stood because B was never harassed; a flank came from the side while our army sat mid-map, it killed
extractors on the way and we never reacted; our units spread out, no front line, no concentration of power; not
aggressive, the first enemy extractors killed at 15 min; then standing in range of their long-range defence; then
bombers, B at more than double our income. Radar: the 11-18 cover change left with the guardposts revert, and it had
not moved A's first radar while it was in. In this game A's first radar was at 15.2 min (B 4.7). The sense want
won 4 decisions in the game (B at 4.1 and 13.5 min, A at 14.9). It is priced low on both sides: the radar's best value
in the once-a-minute samples was 0.1-75, against extractors at 50-1,800. A's value was no lower than B's; A's turret
and extractor wants beat it because raiders were in A's base (LLT 1,175 at 4 min).

09:20. His question: is our side running correctly? The lane's game scripts and economy net are byte-identical to
v0.5.17; the C++ adds only the hand-off. The hand-off blinds our economy AI: A ran no scout task (B 4), saw 21
metal of their army at 6 min (B 628), and sized its army to that (736 vs 1,468; 1,474 vs 2,781 at 8). It made 0
Ticks and 0 Rovers against B's 57 and 19, and B's script never chose one, so they came from production outside
the script. His ruling: our AI keeps the scouts (and possibly escorts). Built: watch.py reads the scout-role types
from the deployed behaviour.json (armflea armfav armspy armpeep armawac armpt armsh and the Cortex ones), and
passes them as dev_armynet_keep to the gadget (not marked hands-off) and as --keep to serve (never ordered).
Escorts are a task, not a type: keeping them needs the AI to tell the gadget which units it holds; not built.
Measure on seed 6 against 084245 (same checkpoint): Ticks and Rovers built, their army seen at 6 min (armyest
theirs), our army at 6 and 8 min, first radar; then the campaign's games (restarted from 0850's 10.6k at step
87000).

09:27 his second watch (092652, same seed and checkpoint, scouts kept by our AI). The hand-back works: once it had
Ticks our AI ran scout tasks (1 at 9 min, 4 at 12). But our first Tick came at 8.3 min (theirs 1.1), so at 6 min
we had still seen 21 metal of their army (they 736). Their 1.1-min Tick appears in both seed-6 games; on other
seeds the first Tick is at 5-10 min on both sides, so early scouting is weak on both, not a side artifact (his
point: the Tick comes before any sighting). Their 1.1-min Tick is not a script decision; its source is not yet
found. Our army at 6/8 min was 1,094/2,208 (084245: 736/1,474). No radar on our side before the 22.7-min end
(they 4.1).
What he saw (his words, 11-20):
- units shot by their Fatboys (long range, big area) neither back off nor attack; they stand under fire from
  a unit they cannot see (the model has hit and shot-origin inputs, layers 25-26, and does not react);
- two constructors died deep, past four extractors we KNEW were theirs, walking to spots further back that we
  had not seen and so assumed free (economy AI: unseen spots behind known enemy ones priced as free and safe);
- constructors run from a Tick that the pair of them could reclaim faster than it kills one (the con-retreat
  path, BuilderTask.cpp, never weighs reclaiming the attacker);
- "we do not attack. The enemy attacks us but we do not attack them and thus we can't win."

10:25. Design (his three levels: strategy split / per-force operation / unit tactics; Fable review: right problem,
build the cheap form first). His ruling: orders go out as a player clicks them, a line drag, and we may do better
than players by putting the short-range units on the line and the long-range ones behind. Facts first
(group_orders.py, 40 games): 90% of player unit orders are clicks of 3+ units (median 7); a click sends the group a
median 650 elmos; 60% are line drags (median 415-502 long, a median 65 deg from the enemy direction, i.e. mostly
across it); players do not layer by range (correlation 0.00). Today's 14 losses: army at minute 8 even (within 15%)
in 5, ahead in 2, behind in 7; all lost, so size is not the cause. Built:
1. serve --forces: one draw per force (live task, or free units grouped by position as training groups clicks) on
   the members' mean chance; one kind and place from their summed distributions; a line across the enemy direction,
   64 apart. --layer (its own arm): shortest-range armed units on the line, each longer-range one set back by its
   extra range, unarmed behind. Air and ground are separate forces. Fable's review caught three bugs before the
   test (unarmed units at the front pushing everyone back by their range; layering along travel not toward the
   enemy; spread measured on tasks the line itself split), all fixed. Paired test running: 6 seeds x (unit, forces,
   forces+layer), checkpoint step-086600, 20 min at 4x. Instruments per minute in serve.log: task spread, nearest
   own unit, tasks and their size, new/split/merge.
2. Force heads (model.forces): per force, from its members' mean and max: click, kind, place + offset, point or
   line, the line's length and angle to the enemy direction, and the 60-s hindsight goal. Labels in data.py
   (_force_labels, force = tasks.forces_at, identical live; parity: grid, tokens and forces same). Reveal masks a
   force with a shown member; mirror flips cells, offsets, goal and the angle's sign. --fresh-steps N trains the new
   heads alone first (30 unfrozen steps raised the unit act loss 0.06 -> 0.23). serve --learned uses them.
   Held-out baselines before training: players click a force in 6.2% of force-steps; staying at the force centre
   misses the click target by 798 and the 60-s position by 1,268 (the heads must beat these). Also measured: the
   per-unit place head misses by 383 against 325 for keep-or-stand, i.e. its places are worse than not moving.
Housekeeping: watch.py folders now carry the runner's pid (two games launched in one second shared a folder and
crashed serve); two stopped test loops had kept launching seeds and were killed by process tree.

10:23 check. No training on purpose (the next run is the force heads, after the paired test; free commit 21.4 GB
with his ComfyUI at 14 GB). Paired test seed 11: the per-unit arm at minute 12 (one task of 68 units, spread 847,
nearest own unit 180; serve 1.01 steps between decisions, 0.08 s); the two force arms started late on the memory
gate and are at minute 1. No tracebacks. Recorder recording (Cirolata, 1,368 s). Parity incl. forces identical.

11:15. Paired force test done (paired_summary.py runtime/armynet/paired-forces-b.log; 6 seeds x unit / forces /
forces+layer, step-086600, 20 min at 4x; 15 of 18 hit the limit, 3 ended early, no wins). Means (force-unit, seeds
better):
- nearest own unit, min 5-15: 326 / 220 / 268 (forces tighter in 5 of 6)
- our army lost by 12 min: 2,669 / 1,117 / 2,531 (forces lower in 6 of 6); army killed by 12: 2,748 / 1,780 / 2,647
- army A/B at 8 min: 0.64 / 1.08 / 0.89; at 12: 0.60 / 0.77 / 1.11
- trade at 20 min: 0.61 / 0.65 / 0.80 (layer better in 5 of 6); their economy killed by 20: 1,091 / 1,253 / 1,475;
  ours lost: 4,866 / 3,622 / 3,500
- army centre at 12 min: 0.24 / 0.15 / 0.17: no arm goes forward.
Reading: forces keep the army together and alive; layering gives the best trade; neither attacks, because where to
go still comes from the per-unit place head (worse than keep-or-stand offline). Six seeds is a direction read.
Next: the force heads learn where players sent a group. Training started 11:18 from step-086600, --fresh-steps
3000, 60k steps, out runtime/armynet/force-heads-20261120 (5.4 steps/s). Judge: held-out f_rate_model vs players'
6.2%, d_f_cell_model under 798 (stay), d_f_goal_model under 1,268; then serve --forces --learned (with and without
--layer) paired against these arms.

11:22. Fable's review of the force heads; the first run (to step 2,000) was stopped and restarted with fixes:
- reveal() now shows whole forces: showing single units masked any force with one shown member, so a 7-unit force
  kept its label 1 time in 8, biased to singletons. Now 51% of force labels survive, whatever the size.
- a click spanning two forces masks the force that did not win it (it was clicked: a false "no click").
- the 60-s goal counts dead members where they fell (survivors only taught "attacks end where the cowards stood");
  new label and head f_alive: share of the force's metal alive at +60 s (mean 0.78 in a 229-example sample).
- goal and alive losses weighted 0.3 (the 4,096-cell goal CE was the largest term and would steer the trunk).
- serve --sample-place: the learned force place drawn from the force's own distribution instead of the
  back/hold/forward band (the hold band is ~600-900 elmos, players' median click is 650: the likely reason no arm
  moved forward). To test as its own arm.
Open from the review, not built: feed each force's last click (target, age, kind) back as an input so persistence
is learned; live force sizes vs players' 7; unit act/cell loss down-weighted for force-clicked units; air/ground
split in the learned path. Run: runtime/armynet/force-heads-20261120b.log (from step-086600, --fresh-steps 3000).

11:24 check. force-heads-b at step 400 (restarted 11:22), no traceback, ~5.5 steps/s, GPU 62%, free commit 46.9 GB,
recorder recording. No test games running. First held-out force eval at step 2,000.

12:21 check. force-heads-b at step 20,200, no traceback, ~5.8 steps/s, free commit 54 GB, recorder up (1,628 demos,
203 recorded). Held-out force heads at step 20,000 (flat since ~4,000): click target 385 elmos off vs 798 stay-put;
60-s position 979 vs 1,087 stay-put (the survivorship fix moved that baseline from 1,268); point-or-line 69% right
(players draw lines 60%); click rate 3.7-5.1% vs players' 6.2% (low; catch-up raises it live). Trunk unhurt:
act logloss 0.400 vs base 0.452, unit place 347 vs keep-or-stand 325 (was 383). Started paired_arms.sh on
model-020000: unit / hand forces / learned / learned+layer, seeds 11-16, 3 engines (recorder the 4th);
log runtime/armynet/paired-learned-a.log. Measured by paired_summary.py against the unit arm.

13:21 check. force-heads-b at step 35,000, no traceback; held-out force heads flat (cell 384 vs 798, goal 950 vs
1,087, click 4-5%). Free commit 27 GB with 3 test engines + training; recorder up. paired_summary.py now takes the
arms from the log. Interim, 19 of 24 games (paired vs unit, 4-5 seeds): learned forces keep units together
(nearest own 153 vs 331, 0/5 above unit) and kill more army by 20 min (+3,780, 5/5) but lose more economy
(+3,539) and stand further back (orders forward 0.42 vs 0.68, centre16 0.13 vs 0.25, their extractors reached
6.8 vs 13.4). Layer on top: army lost -1,668 vs unit, otherwise the same. No wins in any arm (all time limit).
Reading (unmeasured): the force heads learned cohesion, not advance. Two suspects: direction-first placement
(its hold band is about one click long, so "forward" rarely wins), or the click target averaging over players'
regroup clicks. --sample-place tests the first directly; then the force last-click input.

13:50 why learned forces sit back (his "figure out why and fix it", no more steps). Both suspects wrong: on 30
replays the force head aims as far forward as players (clicked forces, axis step median +0.05 dirfirst / +0.04
sampled / +0.04 players). The live gap is idleness: army metal that moved <100 elmos in 60 s (minutes 8-18) is 40%
for learned vs 17% unit / 23% hand forces; 19% stood at home (idle_share.py). Cause: players almost never click a
lone unit (0.5% a step) or a force at home (1.0%) -- their new units leave by the factory's rally, which is not a
unit order -- so the head learned not to; live our factories have no rally and new units pile up at home. Also the
head clicks below players' rate at every size (4-8 units 3.2% vs 5.7%). Built in serve.py: --rally (a never-ordered
unit moves to the main force's last click, main = at least half the biggest force) and --fbias (logit bias; 0.39
matches players' held-out rate). Per-minute "forces:" line logs click p, idle forces and order kinds. Arms rally and
rallylayer (both --fbias 0.39) appended to paired-learned-a.log, same seeds and checkpoint, so they pair with all
four earlier arms. Measured by idle_share.py (still share) and paired_summary.py.
Full 24-game batch: learned still share 0.45 (unit 0.17), army killed by 20 min +3,875 vs unit (6/6), own economy
lost +2,545. First rally game: nobody idle at home, but lone arrivals stood at the rally (idle forces size 1.5, axis
0.45-0.73, click p 0.005): players box-select such a unit with the blob, the tracker cannot know that. Added: when a
force of 2+ is clicked, rallied units within GROUP_R join the click (and so its task). Restarted both rally arms
(13:44). Trap: TaskStop on paired_arms.sh leaves its subshells launching games; kill its tree (taskkill /T).

## Navy and where units can go (his 11-19)

He: "for army what about navy? hope we'll work there too, and understand which units can move on land vs water vs
both". Ships were already model-controlled (class army) but it saw only their stats. `movement.py` reads the game's
own movedefs.lua and unit files: per unit land / water surface / under water / slope / wade (ships and subs water
only; hovers, including the Pelican (AHOVER2), land and water; commanders and amphibious units the sea floor).
Unit columns 42-46 (TOKEN_F 47), from the unit's name on both paths (replay_dataset defs columns 12-16, serve's
static D lines): parity identical, mirror ok. All datasets rebuilt; campaign restarted from campaign 1504's model.pt
(about step 289k overall, new columns at zero weight). `navy_share.py` counts the naval data once rebuilt.

17:38 check. Found in self-review: the movement rebuild covered only 180 of 1,170 games -- the 1,175 recordings
queued for re-recording had their orders.txt.gz renamed, so the builder skipped them and their datasets kept the old
format (no movement columns; data.py read them as zeros, so most of training would not have seen movement at all).
Fixed: replay_dataset.py builds from orders.packed.txt.gz (victims recovered) until the new recording arrives.
Rebuild restarted, then navy_share, then the campaign. No training ran this hour (stopped for the rebuild), so no
games or performance numbers; recorder alive (176 re-recorded); commit 20.3 GB.

18:26 check. Rebuild with movement on every recording: public part done, local part running (1,265 built, none
failed); campaign starts after it (`campaign-20261119-1740` is an empty start from the stopped chain, never
trained). No games or training this hour either. Stopped two leftover monitor greps. Recorder 216; commit 23.9 GB.

19:26 check. Rebuild done (1,274, none failed); campaign 1830 (movement inputs, from 1504's model) at 21.6k, no
errors. Navy in the data (`navy_share.py`): 101 of 1,274 duels (8%) have ships or subs; finished army metal ship 1.4%,
sub 0.4%, hover 0.3%, amphibious 9.1%, land 51%, air 38% -- duels teach little navy; water-map replays would.
Games at 10k: both lost (24.9, 38.3 min); B near A's extractors 2.0x / 1.4x as often as A near B's. Minute-8 build
after the guardposts revert: A economy 4,064 / 3,612 vs B 5,016 / 3,544, defence 1,940 / 2,725 vs 1,105 / 2,070 (A
had already lost 1,745 / 920) -- the 17:06 game's 2,237 vs 5,202 economy gap is gone in both. Serve gap mean 1.17 /
1.14 s (max 5-6), 0.11-0.16 s a decision. Performance: 6.0 steps/s, GPU ~20%: data-bound. An example costs 9.6 ms
(`profile_example.py`; splat_disk, fire layers, fight features, task features the largest), but the machine is at
100% of 16 cores with ~11 on engines (test game, two replays recording at full speed). Trying the recorder at one
worker (re-recording takes longer); kept only if training clearly speeds up.
Result: 7.2 steps/s (from 6.0), GPU 86% (from ~20%), over 2,200 steps each; a test game ran during part of both
windows. Kept: +20% training for re-recording at half speed (~960 left, about two days instead of one; the recovered
hits stand in meanwhile).

20:26 check. Campaign 1830 at 45k, no errors; 8 games (steps 10k-40k), all lost in 23-38 min. Far metal-spot time
(`poi_rate.py`), 3-10 / 10-20 / 20+ min: the model 18.2 / 5.1 / 8.4% (campaign 1504: 6.5 / 3.0 / 0.3%; B 17.8 / 45 /
56%; winning players 22.7 / 27.7 / 26.8%). The opening now raids like players (serve's skipped-second fix and the
movement inputs both came in between; not separated). The gap moved to the middle game, and the cause shows in the
trades: at 10 min A kills 0.21-0.87 metal per metal lost, B 1.44-6.61 -- the raids go out and lose their fights, so
by 10-20 min A is behind and held at home. Biggest gap: early fight outcomes.
Performance: one replay engine alone takes ~10.6 of 16 cores (uncapped, multithreaded), so cutting the recorder to
one worker barely helped (6.1 steps/s, GPU 19% this hour). Lowered replay engines to below-normal priority: 7.4
steps/s, GPU 87% (one engine changed by hand). Now in replay_orders.py (creationflags); recorder restarted at two
workers to see if training keeps its speed with both low-priority. Result: 8.5 steps/s over 1,800 steps (from 6.1
with one normal-priority worker), engines confirmed BelowNormal. Kept: two low-priority workers.

## Duels first (his 11-18)

The first models train on duels. Team games often play very differently, so they come later and the
model is told which it is in (players per side, allies' units already in its view); judge a duel-trained
model on duels, and check team games apart before mixing them in.

## Engine route (his 11-18)

If the model needs data a widget cannot reach (which weapon fired, projectiles), an engine built
for replays only, that logs and never touches the simulation, is allowed.

## Next

1. Record the public games once the local batch is done; build their datasets.
2. Train long on everything; judge on held-out games against the plain rules.
3. Add outcome heads (predict each horizon's outcome for a move) so play can weigh micro against
   strategy; then price it in the DLL and put it behind one switch for scenarios and games.
3. Offline: predict where each unit of a group is sent, from the map, our units and the enemy we can
   see around it; compare with a plain rule on held-out games.
4. Behind one switch, as the source of squad intents in `military/army/`; `army.md` scenarios, then
   games against BARb.

Dated entries from 11-19 to 11-24: results/armynet/log-2026-11.md.

- 11-25 00:15 HIS LAG (live 8v8, 6 Apex seats, model t21): game ran ~0.92x real time over 3 min; an ally lagged too, so host sim, not network. Per seat per game-minute AiUpdate ~0.5 s (avg 8-9.7 ms, max 18.5), AiMakeTask 0.6-0.9 s; bldIdle 0.6-0.9 s is the biggest job (perf session's next target). Perf session's AiFrame at minute 21: t21 (model seat) 4.19 s vs others 1.60-2.44: the bridge state write is the likely cause (every 10 frames, every friendly unit of the ally team, ~6 engine callbacks + GetCurrentCommands each). Perf session times it with STimed("anet.write"/"anet.read") after his game; fix is mine (armynet lane), parity with training in mind.
- 11-25 00:20 hourly: HIS GAMES. Game 5 Carrot Mountains (23:17-23:33, ended at 13.4 min, Apex t10/t12/t13/t14/t17/t19, model t19, 548 orders): t19 had the biggest army of the six at the end (10.3k home / 7.9k away; others 0.6-14.3k). Logs saved to his-games/1124-2333-carrot. Game 6 Hellas Basin running (23:38, model t21; the lag game). No engines or builds of mine; free commit 40 GB. Mac: hBARb2 running. Perf session: timers for the bridge after his games; the write fix is mine.
- 11-25 00:40 HIS ISSUE (Hellas Basin, live): an AI hit the unit cap (800), its slots fighters and boats, no ground army, killed on land easily. Upkeep (TUNE_UNIT_UPKEEP) prices slots only under lag, counts mobile bodies only, and reads the lobby maxunits (2000 default), not the per-player limit. Live: speed 0.63-0.65 at 39-40 min; our seats' mobile bodies at most 378, so the 800 includes buildings. issues/unit-cap-filled-air-boats.md; next after his games: replay census by class per seat, a contract check, then the pricing fix.
- 11-25 00:50 HIS FOLLOW-UP: "they just stopped making certain things eventually". Live prodrank ~40 min: t16 eco seat orders nothing (all army ecoseat-excluded; target 107k vs 0.7k standing; 88 cons); t14 air plant + shipyard only, boats+air meet the army target so gap 0 and no ground unit is asked; t21 on a hover plant with gap 0. In issues/unit-cap-filled-air-boats.md; replay census per seat by class after his games.
- 11-25 01:05 CAUSE of "stopped making things" (his: "the target is always a spend %"): production.as split the WHOLE army target (standing + flow) by NavyShare (0.75 without water control): yards targeted 75% of the standing land+air army, land plants 25% minus their own standing army -> gap <= 0, labs idle, hulls to the cap. Fixed in Unstable (navy and land each keep what stands and take their share of the owed flow; WaterArmyGap and the blind sub budget the same). Not deployed (his game), not measured; as_scope clean on army.as (production.as one pre-existing LC_N finding at 3577). Test: water-map A/B (land idle at gap 0, ground army at 30/40, navy share, unit count).
- 11-25 01:20 hBARb2 (hybrid v2, Mac 12 games): 3/8/1, .638 (best model arm), trade 0.92; paired vs eBARb +.090 (6/5), vs uBARb +.075 (7/5), vs ctrl -.264 (1/9); commander deaths 1; k/cmm 1.54 (uBARb 1.50, ctrl 1.90); structure losses 1,078 (lowest; ctrl 1,177); in-contact orders 28.5, hurt pull-backs 18.4 (players 13.8-16.4, ctrl 19.1); released 17% of army unit-min, AI attack tasks 10%: the model keeps 83-90%; army in their half 20.5%, mean axis .35 (ctrl 37%/.41). Deaths while released 204 per 100 unit-min (eBARb contact 232). Candidate kept; within noise. Biggest gap now: where the army stands (the model's decision). Next on the Mac: navy-flow-split A/B on Hellas Basin (henry-outbox/navy-flow-split.patch), then army_where on players for the front-line target.
- 11-25 01:40 FRONT-LINE TARGET (Mac, front_players.py, minutes 10-25, ground army in their half / mean axis): players by skill quartile Q1 <32 17.2%/.31, Q2 27.1%/.36, Q3 30.1%/.38, Q4 30.3%/.39 (8192x6144 maps: 22.4/32.4/28.7/36.3%); ctrl 36.9%/.41, uBARb 22.9%/.36, hBARb2 20.5%/.35, eBARb 18.3%/.33: the model stands like the bottom quartile. BUILT (AlphaStar MMR conditioning): data.py scalars + [skill known, skill/50] (SCALARS 10; AIs and unrated 0,0); serve --skill X for the sides it commands (default unknown; the old 35.0 was unused); netrun slices scal for older ONNX graphs; train.py eval BARAI_EVAL_SKILL. enemy1 widened: act diff 0.0 with the skill changed. Not trained (his game; GPU). Plan: scratchpad skill1.sh (enemy1 init, 10k), held-out at 48/20/data, then Mac gate skill1 + hybrid v2 + --skill 48 read by front_players. Not against his 11-21 no-rating-weight ruling: every player still weighs the same; skill is an input, not a weight.
- 11-25 02:00 HIS REMARK (Carrot, T1 only): late game our AIs went all air, no new ground army. Hellas logs agree: land labs gone mid-game and not replaced (t15 armlab last ordered at 14.5 min, then only armap; plant choices price only a copy of the air plant or a nano). Every seat ranks only air plants and yards after ~25 min. Added to issues/unit-cap-filled-air-boats.md; replay read after his games.
- 11-25 01:25 HIS DIRECTION: performance work is the Hot Script to C++ session's; I stay on the army model and his issues (eco seat never makes army in T1-only games; late-game ground army stops). Bridge cost fix finished and handed over: STimed timers (anet.hold/write/read), finished buildings written only at frame % 300 (as the recorder; own buildings still read health for hits), orders file read only when its time/size changed. Lane built (434 s) and deployed; served smoke 1v1 Comet 14 min (matches/smoke-bridge3): 262 orders applied, serve gap 1.78; anet.write 123-161 ms per game-minute, anet.read 383-462 (applying the orders), anet.hold 1.5. No before-number in this setup: the perf session owns the 8v8 before/after.
- 11-25 01:50 HIS ISSUES (eco seat never makes army in T1-only; late game no ground army). Causes found in his logs: (a) T1-only (unit_restrictions_notech2) unknown to the market: 160+ T2 lab elections in the Carrot game, and every seat held spare metal for a T2 lab (richBal needs TopOwnPlantTier >= 2); (b) eco seat target 500 unreachable at T1 (P 430-490 for 25 min, bank full 2,000, growing, army 0; strict seat factories build hands only); (c) a lost land lab never replaced: the plant price caps production at metal no line spends, and the air plant spends it all. Fixes built (issues/unit-cap-filled-air-boats.md), scope-checked, lane deployed; no engine slot here (perf session 3 + my recorder), so the A/B goes to the Mac after its navy run (henry-outbox/t1-ground-army.patch, Carrot 4v4 T1-only, 6 seeds). Bridge cost fix handed to the perf session at his word.
- 11-25 01:31 hourly (clock check: the entry labelled 01:50 above was written at about 01:28). His game off (break). Free commit 10.8 GB, under the 20 GB gate: the perf session runs 3 headless engines and his ComfyUI is up (GPU 35%, 10.5 GB); my replay recorder has 1 engine and waits on commit for its second; nothing else of mine runs (no serve, no training: skill1 waits for memory and his say). Changes this hour, each with its measure: bridge cost fix (handed to the perf session; served smoke OK), the four production fixes (Mac A/B queued: Carrot 4v4 T1-only), skill input (training pending).
- 11-25 01:40 NAVY FLOW SPLIT LOST (Mac, Hellas 1v1 vs BARb hard, seeds 1-8): off 4W/2L/2T, on 1W/7L, our commander dead 7/8 vs 2/8; symptom moved (land idle lines 181 -> 44) but army at 30 min 19.5k vs 46.1k, 117 vs 367 units, opening hover -> vehicle in 4/8. Reverted (git apply -R); scripts redeployed. T1 patch rebuilt without it (henry-outbox/t1-ground-army-v2.patch, 13 hunks); Mac runs it next with score and commander deaths first.
- 11-25 02:25 hourly: his game off. skill1 TRAINING started (enemy1 init, 10k steps, own 0.25, 1 data worker: 3 workers took free commit 26 -> 17 GB, restarted at 1 -> 18.6 GB with the perf session's 3 engines and my recorder's 1; the recorder self-gates and launches nothing more). Recorder: tonight's Carrot (08-38) recorded (2,508 s), the rest waiting on commit. Mac: T1 patch v2 A/B running (Carrot 4v4 T1-only, 6 seeds). Navy split reverted (measured loser). Bridge read cost now the perf session's (it asked for and got the served-run command).
- 11-25 02:40 T1 v2 A/B (Mac, Carrot 4v4 notech2 vs BARb hard, 6 seeds, 40 min): off 6/6 W, on 6/6 W (on games 25-34 min vs 25-39), our commander deaths 0 both; T2 tech elections 470 -> 0, plant:*alab 77 -> 19 but plant:*aap 169 -> 430 (ProposePlant had no block); a lost lab replaced once on (seed 1), never off (0/2); ground army at 30 min 14.5k -> 22.8k (air 15.3k -> 14.9k), at 20 min 31.7k -> 33.8k. No eco seat in a 4v4, so ecowaste untested. v3: TechModBlocked in ProposePlant's loop (henry-outbox/t1-ground-army-v3.patch, 14 hunks); lane redeployed. Next Mac A/B: Kings Assault 6v6 T1-only, 4 seeds, to exercise the eco seat.
- 11-25 03:25 hourly: his game off. skill1 at 1 worker ran 0.86 steps/s (GPU 3%, data-bound; 2,800 steps in 54 min): restarted from scratch at 3 workers now that free commit is 45 GB -> 1.34 steps/s (10k in ~2.1 h), free commit 29.9 GB. Recorder: Carrot (08-38) and Aethermoor (06-37) recorded, the rest in progress. Mac: Carrot 6v6 T1-only eco-seat A/B (eco seat seated, team 4, target 250 in a 6v6). Self-review: the navy split was reverted on its measured loss; the T1 fixes measured no-harm in 4v4 and wait on the 6v6 for the eco seat.
- 11-25 04:45 hourly: his game off. skill1 7,400/10,000 steps at 1.8 steps/s (done ~05:10, then the three skill evals), free commit 42.8 GB; recorder up (583 recorded; tonight's Ice Scream, Altored, Pyroclast, Aethermoor, Hellas, both Carrots in). His T1-only ask, read from the replays: our seats lost their only land lab at minute 11-15 (Carrot 8 of 10 seats) and did not rebuild it; after that every plant was a T1 air plant, so ground share of new army fell to 31-38% (Carrot) and 4-6% (Hellas, boats and air) while the humans stayed 63-97% ground; T2 games kept 54-94%. Added contract check "minutes without a land lab" (tested: runs, 0 on two BARb matches); sent to the Mac to report on both arms of the Carrot 6v6 T1-only A/B. Detail in issues/unit-cap-filled-air-boats.md. Self-review: no AI change this hour; the measurement for v3 is that A/B (score, commander deaths, then minutes without a land lab and ground share at 30/40).
- 11-25 05:00 T1 v3 A/B LOST ITS AIM (Mac, Carrot 6v6 notech2 vs BARb hard, seeds 1-4, 45 min): off 1W/3T, on 0W/4T; enemy commanders killed 21 -> 9 (per seed 5/5/5/6 vs 3/3/1/2); ours lost 1 -> 0; T2 elections 1441 -> 0; our ground/air at 30 min 52.5k/15.0k -> 37.7k/18.1k, at 40 36.2k/15.9k -> 34.5k/18.4k; eco seat (t4, target 250) P at 40 65 -> 78, its army about equal, ecowaste lines 0 -> 25; land plants 1 a seat, none lost in either arm (BARb never killed one, so the rebuild hunk was not exercised). Reverted on the PC (git apply -R henry-outbox/t1-ground-army-v3.patch). Bisect sent to the Mac: arm A = the T2-election filter only, arm B = A + spare-metal/eco-seat hunks, against the same off games.
- 11-25 05:10 Land-lab story from the Mac: vs BARb in the Carrot 6v6 no seat lost a land lab (minutes without a land lab 0.00 both arms). In the Carrot 4v4 v2 A/B games: off lost 2 land labs (13.2, 15.1 min), never rebuilt; v2 lost 2 (14.3 rebuilt 17.8; 25.0 not rebuilt, game over at 31); minutes without a land lab per seat 1.74 off vs 0.35 on, only 2 events per arm. Arm C added to the bisect: the land-rebuild hunks alone, Carrot 4v4 notech2, 6 seeds.
- 11-25 05:30 hourly: his game off (play_online.py + serve --find enemy1 waiting, no engine). skill1 DONE (10k steps) and evaluated on held-out: vs enemy1 act logloss .3168 -> .3156, force goal distance 405 -> 384 (-5%), contact p .153 -> .142, spread acc .721 -> .734. The skill input is near-inert: at skill 48 vs 20 force goals behind the line .392 vs .398 (players .499), far-spot .413 vs .412, act logloss .3161 vs .3152; the AlphaStar MMR lever does not move the front line by itself (target was 30-36% of army in their half, we sit at 18-23%). skill1 is a small held-out gain worth a Mac gate after the T1 bisect (A, B, C queued there); no Mac gate with --skill 48 since the knob does nothing measurable. Recorder: tonight's batch of his games finished 04:21 (all recorded); the public follow stays stopped as he asked (perf session). No AI change this hour; measurement pending = Mac arms A/B/C.
- 11-25 06:30 hourly: his game off since 01:06, PC idle (free commit 60 GB), so arm C runs on the PC (Mac told to drop it): henry-outbox/t1-land-rebuild-only.patch (want_plant land-rebuild hunks only) vs today's Unstable, Carrot 4v4 notech2 vs BARb hard, seeds 1-6, 40 min, +50 both, speed 20, 3 engines at a time, paused while spring.exe runs (scratchpad armc.sh; matches/armc-{off,on}-s*). Read: score, enemy commanders killed, minutes without a land lab, labs lost/rebuilt, ground/air at 30/40. Mac on arm A (T2-election filter) then B.
- 11-25 06:45 Mac bisect, Carrot 6v6 notech2, seeds 1-4: A (T2-election filter alone) 0W/4T, enemy coms 18, ground/air at 30 32.6k/21.6k, eco seat bank 1.5k (metal unspent) -> A alone hurts. B (A + spare-metal + eco-seat hunks) 2W/2T, enemy coms 24 vs off 21, ground/air at 30 49.3k/15.2k vs off 52.5k/15.0k, eco seat army 6.0k vs 4.5k at 20; seed 2 lost 3 land plants at 13-15 min, none rebuilt (minutes without a land lab B 2.64). Too few seeds to call B vs off: Mac runs B and off on seeds 5-8 after its arm C (kept, as a replication on v0.5.18; the PC's arm C runs on today's Unstable).
- 11-25 06:50 PC arm C, off half done: today's Unstable won 6/6 vs BARb hard (Carrot 4v4 notech2, +50 both), games over at 20-23 min; minutes without a land lab 0.24 per seat, bare-hands 0.00. Little lab loss to fix in this setup, so the on half mainly checks for harm. On half deployed (patch in the lane slot only; Unstable source verified unpatched), running.
- 11-25 07:00 Mac arm C (rebuild hunks alone on v0.5.18, Carrot 4v4, 6 seeds): 6W both, enemy coms 25 vs 24, ground/air at 30 20.7k/6.2k vs off 14.5k/15.3k; 2 labs lost in each arm, none rebuilt: after the loss C's seats elected only the disabled advanced lab (armalab x10, x5) and air plants. So the rebuild needs the T2 filter (A), and A needs B's spare-metal hunks: the candidate is full v3. Queued: Mac 6v6 seeds 5-8 off / B / v3 (12 games); PC full v3 on the Carrot 4v4 vs the armc off games after the armc on half (armd.sh, lane slot only).
- 11-25 07:20 PC arm C (rebuild hunks alone, today's Unstable, Carrot 4v4 notech2, +50, seeds 1-6): off 6/6 W, on 6/6 W; game length mean 22.3 vs 23.8 min (on slower 4 of 6); enemy coms 24 vs 25; minutes without a land lab 0.24 vs 0.00; on seats still made 132 elections for disabled advanced plants (the filter is needed, as on the Mac). No harm beyond slightly longer wins; not kept alone. Full v3 now running on the PC vs these off games (armd-v3-s*). (scratchpad armsum.py army columns are wrong -- team mapping -- ignore them.)
- 11-25 07:50 PC full v3 (lane slot only; Unstable source verified unpatched) vs the armc off games, Carrot 4v4 notech2 +50 seeds 1-6: 6/6 W both, enemy coms 24 both, game length mean 21.4 vs 22.3 min (v3 sooner on 4 of 6 seeds); disabled advanced-plant elections 0 (C alone: 132); minutes without a land lab 0.00 vs 0.24. No harm here, but these games end at minute 20-23, before his late-game failure, so this setup cannot show the ground-army fix. The Mac 6v6 seeds 5-8 (off/B/v3) is the remaining read; a longer game is needed (6v6 45 min or a harder opponent) to see the late game.
- 11-25 07:25 hourly (clock: the entries labelled 06:45-07:50 above were written between about 06:30 and 07:20). His game off since 01:06, free commit 62 GB, no engines before launch; recorder batch done, public follow stays off as he asked; skill1 finished (near-inert skill input, see 05:30). New PC run arme.sh: off vs full v3, Carrot 4v4 notech2 vs BARb hard with BARb +100 and us +0 so games reach the late stage his failure lives in, 45 min, seeds 1-4 (lane slot only). Read: score, length, our ground/air at 20/30/40 (scratchpad armsum.py, team mapping fixed), labs lost/rebuilt, minutes without a land lab. Mac: 6v6 seeds 5-8 off/B/v3 running.
- 11-25 08:15 LATE-GAME T1 TEST (PC, Carrot 4v4 notech2, BARb hard +100 / us +0, 45 min, seeds 1-4): off 2/4 W, enemy coms 14, ours lost 3; v3 3/4 W, coms 15, lost 2; minutes without a land lab off 3.03, v3 3.64. His failure reproduces in BOTH arms: at 40 min our ground/air off s2 3.4k/15.4k, s3 3.9k/23.6k; v3 s4 2.6k/12.4k. v3 does not fix it. Lab loss is not the main driver: seats with their land lab standing and busy kept buying T1 air plants (v3 s1 t0: armap x7 by minute 30), elected 'draw over nothing' at v=2-5 when nothing else priced positive, while every land-lab copy read plant-choice copy>nano (gCopy 6-9 vs gNano 2-3, mul 1.00) yet was never elected. Land copy's ProposePlant price is not logged once a factory stands, so: armf.sh reruns seeds 2-3 with the plantcand line on (lane slot only, henry-outbox/plantcand-always.patch; Unstable source verified unpatched).
- 11-25 08:50 CAUSE FOUND for the T1-only ground collapse: ProposePlant's 'one T1 line until T2' (his 10-03) skips every second T1 plant until an advanced plant stands, except the air lead's air plant; with T2 disabled it never lifts, so air plants are the only extra line and a land lab lost beside an air plant is never offered again (why v3's rebuild failed). Instrumented games (plantcand log, seeds 2-3) showed land labs absent from late pricing. v4 = v3 + '&& !T2Disabled()' on that rule; running on the PC, late-game setup, seeds 1-4, vs the arme off/v3 games (lane slot only; Unstable source verified unpatched). Measure: ground/air at 30/40, score, coms, minutes without a land lab.
- 11-25 08:25 hourly: his game off; free commit 48 GB; 2 engines (v4 late-game seeds 3-4); build loop fine; recorder batch done, public follow off as he asked. v4 first 2 seeds: s1 lost (45 min, ground/air at 40 5.1k/20.3k), s2 won at 37.8 (30 min 18.6k/7.9k); second land plants now appear (armlab rebuilt at 11.0, armvp at 12-16 on 4 seats) but air plants still multiply (one seat 7 armap by 38 min, elected 'draw over nothing' at value ~0.005): the focus rule was one blocker, not the whole story. Waiting for seeds 3-4 before judging.
- 11-25 08:50 v4 late game seeds 1-4 (PC): 2/4 W (off 2/4, v3 3/4), enemy coms 15 (off 14), ours lost 2 (off 3); our ground at 30 min mean 14.6k (off 11.0k, v3 10.1k), air 12.2k (off 12.3k, v3 18.2k); minutes without a land lab 7.89 (off 3.03): seat t2 (the crushed front seat at +0 vs +100) lost its armlab at 4-8 min in every game and never rebuilt it under v4 (off rebuilt once); its elections after the loss were eco (mex 16, makers 8) with one plant:armlab at v 1.3. Second land plants now appear on other seats; air plants still multiply late. Not conclusive on 4 seeds: armh.sh runs seeds 5-8 off vs v4, both with the plant candidate log, to read the rebuild price.
- 11-25 09:05 v4 seeds 5-8 (PC, same late-game setup): off 4/4 W, coms 16, lost 1; v4 4/4 W, coms 17, lost 1. Over 8 seeds: wins 6/8 both, enemy coms off 30 / v4 32, ours lost 4 / 3; our ground at 30 min mean off 13.2k (7 seeds) vs v4 18.3k (8), higher on 5 of 7 paired; air 13.9k vs 14.3k. Lab rebuilds happen in both arms on seeds 5-8. Contract fix: 'minutes without a land lab' now ends at the seat's last decision (a dead seat kept reporting stats): off 3.03/2.98, v4 5.40/2.64 (seeds 1-4 / 5-8), the v4 excess being the crushed front seat t2 (lab lost at 3-8 min). v4 held out of Unstable until the Mac's 6v6 (eco seat present) on seeds 1-8; sent.
- 11-25 09:40 MOVE JUDGE (his 11-25 'let the model propose'; memory and outcome weighting were already built 11-19/21 -- I had pitched them as new, corrected): model.py f_judgeq + f_judge_b, a per-cell head scoring how a force's click to that cell would rate (target f_raw, the order's rating vs the side's other orders in the same window; real clicks only), loss 0.3 x smooth L1 at the chosen cell; eval judge_r (corr with the rating at the chosen cell) and judge_auc (better-rated click judged above worse-rated, 0.5 = none). Smoke ok (30 steps: r .013, auc .48, n 985 held-out clicks). judge1: skill1 init, 5k steps, then eval-judge1.txt. Pass bar before using it in play: auc clearly above .5 (aim .6+) with the copying metrics no worse than skill1. Next: serve proposes top-k cells + 'push into the broken line' candidates, the judge picks; then enemy prediction.
- 11-25 09:22 hourly (clock: the MOVE JUDGE entry labelled 09:40 was written at about 09:12). His game off; no engines; free commit 55 GB; judge1 training started ~09:12, no step line yet, no Traceback, GPU 36% (ComfyUI shares it). Mac: 6v6 off seeds 5-8, then v4 1-8. Self-review: the only change this hour is the judge head (model.py, train.py; old checkpoints load with the head fresh, measured in judge1's eval); the v4 AI patch stays out of Unstable.
- 11-25 10:05 JUDGE PASSES its offline bar: judge1 (skill1 + judge head, 5k steps) held-out judge_auc .646 (better-rated click judged above worse-rated), judge_r .237 (n 985 clicks); copying metrics vs skill1: act logloss .3174/.3156, place error 384/384, goal error 911/922, spread acc .735/.734, kind acc .953/.948, value result acc .709/.689. Wired for play: export_onnx.py + netrun.py carry a 'judge' force output (ONNX parity 0.0, +~1 ms CPU per forces call; older graphs unchanged); serve.py --judge K: of the place head's top K cells per force the judge picks one (minute line 'judge: N judged, M differ'). Caveat: the judge only ever saw places players chose, so its read of other places is extrapolation; the game gate is the test. Asked the Mac for hBARb2's exact flags to run judge-on vs judge-off (same judge1 model) on the PC.
- 11-25 10:20 JUDGE GATE started on the PC (gate_judge.sh): judge1, hBARb2's flags from the Mac (--forces --learned --rally --fbias -0.19 --arc --hybrid vs BARb hard, 40 min, speed 4, watch.py default map), arms jon (--judge 5) vs joff (same model, judge off), seeds 89-100, 3 at a time, waits for his game; log runtime/armynet/gate-judge.log; lane deployed with plain Unstable (no v4). Found: the PC's watch.py never passed --hybrid/--unit-contact/--gather to serve (added, with --judge); asked the Mac whether its copy does, since otherwise hBARb2 ran without the hybrid. Read: paired score, k/cmm, army in their half, breakthrough follow-through.
- 11-25 10:25 hourly: his game off; 3 engines (judge gate), free commit 36.5 GB; build loop stopped (recorder off, nothing to build; Cleanup asked), share kept for the Mac. Judge gate 3 of 24 games done: seed 89 jon lost at 27.6, joff lost at 35.4; seed 90 jon 40-min time-out. In jon the judge overrides the place head's best in 82% of force-steps (seed 89: 45,754 of 55,935), a far bigger change to play than a tie-break: if jon trails, next arm is K=3 or judge + place log-chance. Hybrid confirmed active (8,993 releases by minute 26). report.md per game is game_report.py, to run at the end for paired_summary. Changed this hour: watch.py pass-through (--hybrid/--unit-contact/--gather/--judge; Mac copy already had them), todo split (11-19..11-24 log to results/armynet/log-2026-11.md).
- 11-25 10:50 MAC v4 6v6 (Carrot notech2, 45 min, seeds 1-8, vs plain v0.5.18): off 3W/5T coms 47, v4 1W/7T coms 27; ours lost 1 vs 0; ground/air at 30 48.8k/17.0k vs 51.9k/22.9k, at 40 38.6k/21.7k vs 46.9k/15.8k; second land plants 5.9 -> 7.8 a side; minutes without a land lab 0.75 -> 0.23 (v4 rebuilt a lost armlab; off never); eco seat t4 army 4.2/4.3/3.8k -> 6.3/7.3/5.0k, no second land plant, its extra plant votes went to T1 air. v4 REJECTED in 6v6 (coms -43%). With v3 1-4 (coms 9 vs 21) and B 1-4 (24 vs 21), the land-rebuild hunks (prodTermLand: no spare-metal cap on a new land line whenever none stands, which includes the opening) are the likely harm. Next on the Mac: B 5-8, then v5 = B + the focus-rule line only (henry-outbox/t1-ground-army-v5.patch), seeds 1-8, plus each seat's first lab and its minute.
- 11-25 11:15 HIS T1 REPLAY (Tundra V2, Apex v0.5.18, notech2: two seats with no converters at 44 min). Cause: units the lobby disables stay in our catalog (BAR sets only customparams.modoption_blocked); the disabled T2 converter makes the basic 'obsolete on arrival' all game -> plot reclaim eats one -> NoteDefRetired latch -> RetiredDefMul 0 forever. Our T1 tests: after a seat's first converter reclaim, 0/0/0/0/1 more built (5 seats). FIX (his idea): C++ CircuitDef sets maxThisUnit 0 for modoption_blocked defs (lane CircuitDef.cpp, mirrored to cpp/ as that one file); lane DLL built 11:09 (OK, 108 s), deployed after the judge gate by armk.sh: T1-only late game seeds 1-8 vs the arme/armh off games. Contract: 'minutes without a converter' added (off 0.99 / 0.90). This supersedes the hand T2 filter (A); A alone banked metal, so read the bank and ground too.
- 11-25 11:20 MAC B over 8 seeds (Carrot 6v6 notech2 vs off): 4W/4T vs 3W/5T, enemy coms 42 vs 47, ours lost 2 vs 1, ground at 30/40 45.4k/30.6k vs 48.8k/38.6k, eco seat bank at 40 132 vs 593 and army +1.4k; minutes without a land lab 2.18 vs 0.75. A wash: not kept. Mac running v5 (B + focus line) seeds 1-8, then the C++ blocked-unit fix alone (plain v0.5.18 scripts + rebuilt dylib) vs off on the 6v6.
- 11-25 11:30 MAC opening read: first plant finishes at the same minute in every arm (mean 1.30-1.32 min; t2 latest at 2.1-2.3). The land-rebuild hunks change WHICH plant opens: off/B t5 lab 8/8, t1 vp 6-7/8; v4 t5 vp 6/8, t1 lab 6/8 (v3 1-4 the same); t0/t2/t3/t4 unchanged. So prodTermLand (uncapped with no land plant standing, i.e. at the opening) swaps bot/vehicle openers on two seats -- a candidate cause of v3/v4's lost commander kills, beside the extra second land plants.
- 11-25 11:25 hourly: his game off (his replay viewing paused the gate ~10:45-11:05); 3 engines; free commit 40 GB. Judge gate 16/24 (seeds 89-96 both arms): jon 0W/3L/5T, joff 0W/5L/3T; paired: jon better on 4 seeds (90, 91, 93 survived to 40 where joff lost; 92 lost later), worse on 2 (89 lost sooner, 96 lost vs a draw), even on 2. Too early; seeds 97-100 to come, then game_report + paired_summary for trade, army in their half. Queued after it: armk (blocked-unit DLL, T1-only). Changed this hour: C++ CircuitDef blocked-unit fix (lane DLL built, not deployed), contract 'minutes without a converter'.
- 11-25 11:50 MAC v5 (B + T1-line line) 6v6 seeds 1-8: 2W/6T vs off 3W/5T, enemy coms 30 vs 47, ours lost 0 vs 1, ground 42.1/46.2/37.8k vs 42.3/48.8/38.6k, air 25.5k vs 21.7k at 40; no land plant lost, second land plant only once (the T1-line line barely fires in this setup); minutes without a converter 0.05 vs 0.06 (the converter loss hardly shows on this map vs BARb). Openings match off except t1 on 2 seeds. v5 builds what off builds yet kills 30 vs 47: commander kills over 8 seeds are noise at this size, so v3/v4's 'kill losses' may be too. Asked the Mac for an A/A (off again, seeds 1-8) after the blocked-unit dylib arm, to measure the spread before ruling.
- 11-25 12:15 JUDGE GATE DONE (PC, judge1, hBARb2 flags, seeds 89-100): jon 0W/5L/7T vs joff 0W/7L/5T. Paired vs joff: trade at 12 min .53 vs .31 (11/12 better), army killed by 12 +909 (10/12), army lost by 12 -1,240 (11/12 lower), army ratio at 12 1.18 vs .60 (9/12); trade at 20 .52 vs .42 (8/12). Orders LESS forward (.38 vs .49, 10/12) and units nearer their own (228 vs 307): the judge buys better fights, not a more forward line. First clear model gain in days. Page: results/armynet/2026-11-25-move-judge-on-vs-off-*.md (contract FAIL table there: release baseline). Next: judge vs enemy1's hBARb2 settings on the same PC seeds (is judge1+judge above the old best?), the breakthrough read on these games, then 'push into the broken line' candidates.
- 11-25 12:25 hourly + BLOCKED-UNIT DLL RESULT (PC, T1-only late game, Carrot 4v4 notech2, BARb +100, seeds 1-8, vs arme/armh off): wins 5/8 vs 6/8, enemy coms 28 vs 30, ours lost 5 vs 4; converters built per game 91-123 (s1-s3) vs 40-73, minutes without a converter 0.28 vs 0.95 -> the converter bug is fixed; disabled-T2 elections and assists gone (off s1: 71 tech:armalab, 46 tech:armaap, 40 plant:armaap, 292 assists to them). But ground at 30 min mean 9.1k vs 13.2k and air 16.5k vs 13.9k; minutes without a land lab 5.49 vs 3.01: the freed builder time goes to air, as with the hand T2 filter (A). Read: the converter fix is right and stays the candidate; the T1 air bias (air lead's air-plant exemption, 'draw over nothing' air plants) is the next cause to fix. Mac running the same DLL on the 6v6, then an A/A. His game off; free commit 62 GB; no engines now. Waiting on his OK for: clear set-target on model orders, split-defs + hybrid-off game test.
- 11-25 12:40 MAC blk dylib (6v6 notech2 seeds 1-8, plain v0.5.18 scripts): 1W/7T vs 3W/5T, coms 31 vs 47, lost 3 vs 1; T2 elections 2642 -> 0 with no script change (A redundant); converters standing per seat at 30/40 31.0/48.6 vs 14.0/15.1 (eco seat t4 160-213 at 40); eco seat bank 1049/1253/1324 vs 644/722/593, its army lower; our ground 32.5/35.7/36.9k vs 42.3/48.8/38.6k, air at 40 30.0k vs 21.7k. Same shape as the PC: converters fixed, freed metal banks or goes to converters and air, not ground. Next on the Mac after off2 (A/A): blk + henry-outbox/t1-spare-metal-only.patch (T2Disabled def + ecoseat/production spare-metal hunks).
- 11-25 13:00 HIS GO on step 1 (stop the air drift). Built: worth.as AdvancedPlantAvailable() (any available T2/T3 plant in the catalog, which the blocked-unit DLL now trims); the 'one T1 line until T2' rule and production's richBal 'held until a T2 lab stands' both wait for T2 only when T2 exists. Patch henry-outbox/t1-step1.patch (kept out of the shared source while unmeasured). Test armm: blk DLL + step1 + plantcand log, T1-only late game seeds 1-8, vs armk blk. Air-plant elections in blk: 258, 86 'over nothing'; plantcand showed the air plant priced on its con half (air constructors), prod 0: next step after this read is the default-purchase air plant. His 11-25 aim behind it: committed, surprising switches (todo/team-strategies.md 'The timing', unbuilt); the drift kills the surprise.
- 11-25 13:20 MAC A/A (off2 vs off, 6v6 seeds 1-8): wins 5W vs 3W (wins swing 2 between identical arms), enemy coms 45 vs 47; per-seed paired SD ~4.3 -> an 8-seed total carries ~+-12. v4 27, v5 30, blk 31 sit 16-20 under both off runs (1.3-1.7x the noise): leaning real. Common factor of all three: the disabled-T2 elections are gone (off ~2,600). Reading with the PC: those elections wasted builder time harmlessly; freed, the builders buy air plants, converters and bank (blk PC: ground at 30 9.1k vs 13.2k, air up). So removing the waste exposes the air drift, and step 1's second half (no default air plant) is the fix to test on top. Eco seat bank swings ~400 at 20 min between identical arms. 40-min army unusable on the 6v6 (games end 36-40).
- 11-25 13:45 STEP 1 RESULT (PC, blk DLL + t1-step1.patch, T1-only late game seeds 1-8): 8/8 W vs blk 5/8 / off 6/8; enemy coms 35 vs 28/30; ours lost 4 vs 5/4; ground at 30 mean 21.8k vs 9.1k/13.2k, air 18.0k vs 16.5k/13.9k; minutes without a land lab 2.69 vs 5.49/3.01; air-plant elections 196 vs 258 (still the most-elected plant). Ledger page under results/armynet. Mac: after spm, blk + step 1 on the 6v6. Next here: the default-purchase air plant (second half of step 1).
- 11-25 13:15 BACKLOG DIAGNOSIS (PC, blk + step 1 + backlog-detail log, T1-only late game seeds 1 and 7, after minute 20, 145 lines): mean backlog 3,574 m. By metal: armguard 24.5% (1 row, being built: 5% no worker), armmex 22.7% but 16.9 rows at a time, 91% ordered and never started, 47% with no worker, oldest ~5 min; armcir 13%, armadvsol 9%, nanos 5%. So the backlog behind BPGap (and the air plants bought as constructor factories) is mostly real work, plus a standing pile of ~17 mex orders nobody starts. Likely far or contested spots: a safety problem read as a hands shortage. Next: log those mex orders' side of the map / threat before changing the gap.
- 11-25 13:22 hourly (clock: the entries labelled 13:20-13:45 above were written between about 12:45 and 13:05; the backlog entry is relabelled 13:15). His game off; PC idle, free commit 62 GB; shared Unstable source unpatched (step 1, backlog log and plantcand stay patches). Mac: spm (blk + spare-metal) running, then step 1 on the 6v6. Today's measured candidates: blocked-unit DLL (converters fixed; exposes the air drift), step 1 (T1-only 4v4 late: 8/8 W, ground at 30 21.8k vs 13.2k off), move judge (trade at 12 min .53 vs .31, 11/12). Open for him: stale mex orders read as a hands shortage (next), and the model deep dive (topic 2).
- 11-25 13:35 MAC spm (blk + spare-metal hunks, 6v6 seeds 1-8): 3W/5T, enemy coms 39 (blk 31, off/off2 47/45; inside +-12), lost 1; eco seat army 5.3/10.7/15.4k vs blk 3.5/3.3/5.6k (bank 506/987/1099 vs 1049/1253/1324); our ground 37.0/44.6/44.6k vs blk 32.5/35.7/36.9k, off 42.3/48.8/38.6k; air 32.1k at 40. Spare-metal turns the eco seat's bank into army and recovers most of blk's ground. Merged with step 1 (same richBal intent) into henry-outbox/t1-combo.patch (5 hunks, no T2Disabled); Mac runs blk + combo after step1.
- 11-25 14:05 BACKLOG FRONT READ (seeds 2-3, blk + step 1 + extended log, after min 20): mex orders 16.3 at a time, 91% never started, 54% no worker, 47% PAST OUR FRONT, and ExpectedLossAt reads 0% for every row (the danger model sees nothing there). Fix built: BacklogM skips never-started orders past our front (army's ground, not a hands shortage) -> henry-outbox/backlog-front.patch. Test armq: blk + step 1 + backlog-front, T1-only late game seeds 1-8, vs armm step 1 alone. Read: air-plant elections and air plants per seat, ground/air at 30, score, coms.
- 11-25 14:20 MAC step1 alone (blk + t1-step1, 6v6 seeds 1-8): 2W/6T, enemy coms 37 (off/off2 47/45; inside +-12), lost 0; ground 34.1/36.3/34.0k (blk level, below off and spm); air 38.5k at 40, the most of any arm; eco seat banks like blk (1575 at 40); no second land lab appeared. On the 6v6 the spare-metal hunks carry the gain; step 1 alone does not. Queued on the Mac: combo (running), then combo + backlog-front, leading with air.
- 11-25 14:30 MAC air-plant baseline (6v6, T1 air plants finished by our side per game at 20/30/40 min): off 6.5/7.2/9.9, off2 6.5/6.8/9.1; blk 10.6/17.4/26.1, step1 11.1/18.6/27.4, spm 8.9/15.4/23.2, v5 8.1/12.9/18.6. Per seat over 8 games off 8-18 vs blk 27-58 (eco seat lowest in every arm). The blocked-unit DLL roughly triples air plants: the ~2,600 disabled-T2 elections used to absorb those builder votes. cbf (blk + combo + backlog-front) leads with this measure.
- 11-25 15:00 BACKLOG-FRONT RESULT (PC, blk + step 1 + backlog-front, T1 late game seeds 1-8, vs step 1 alone): 7/8 W vs 8/8, coms 33 vs 35, lost 3 vs 4; air plants finished 104 vs 102, air-plant elections 178 vs 196, land plants 52 vs 57; minutes without a land lab 4.77 vs 2.69. No effect on the air plants: the backlog was not their driver. Their hands value is Air::EvHandsTerm = max(OverflowM x pipe, BPGap term) under TUNE_AIR_EVERY (on since 10-16): an overflowing bank prices an air plant as the sink for air constructors, and the blocked-unit DLL's converters make more overflow. Test armr: step 1 with --modoption apex_air_every=0 (old one-seat air pricing), seeds 1-8, vs armm. Told the Mac backlog-front is a likely null.
- 11-25 14:22 hourly: his game off; 3 engines (armr: step 1 + apex_air_every=0, 1/8 done; 'airevery-stat ... on=0' confirms the setting reached the AI, though the gadget echoes no [BARAI_TUNABLE] line here); free commit 41.6 GB. Mac: combo 4/8, then ae0 on the 6v6. His 11-25 ruling saved (memory no-tier-special-cases): no T2 rules; tier from the build tree (TreeTier, already so); disabled units gone everywhere (the blocked-unit DLL); waits/sequences keyed on tier (~95 tier references across 20 files) to become prices. Proposed audit by file (production.as, want_plant.as first), each batch shown to him before changes; awaiting his yes.
- 11-25 15:00 MAC combo (blk + t1-combo, 6v6 seeds 1-8): 4W/4T, enemy coms 46 (off/off2 47/45, spm 39, step1 37), lost 0; air plants per game 9.6/17.8/24.8 (off 6.5/7.2/9.9, blk 10.6/17.4/26.1); ground 35.0/45.5k at 20/30 (off 42.3/48.8); eco seat army 5.0/10.3/9.4k (off ~4k), bank 635/772/884; converters fixed; 0 T2 elections. First arm not behind off: blocked-unit DLL + combo is the current candidate; air plants still ~2.5x off. ae0 (air_every=0) running on the Mac (on=0 confirmed via airevery-stat; the gadget's [BARAI_TUNABLE] echo is missing on both machines -- a logging gap, not a setting gap). Tier audit batch 1 (production.as + want_plant.as: 4 waits, 4 vetoes, 4 tier boosts, 3 tier-in-price kept) shown to him.
- 11-25 15:20 AIR_EVERY=0, both machines: PC T1 4v4 late (step 1 + ae0, seeds 1-8): air plants 55 vs 102, but 5/8 W vs 8/8, coms 30 vs 35, lost 6 vs 4, ground at 30 15.6k vs 21.8k. Mac 6v6 (blk + combo + ae0): air plants per game 6.2/6.6/7.6 vs combo 9.6/17.8/24.8 (air-every IS the plant driver; air army the same from a third of the plants), ground at 30 50.3k (best dylib arm), eco seat army 15.6k at 40; but coms 32 vs 46 (-14 vs off, just past +-12) and 4 of our commanders dead, 3 before 14 min. Verdict: keep air-every (the T1 air does real work: likely scouting and fighters covering the commander); the plant count gets fixed through the tier audit. Mac checking what killed the early commanders.
- 11-25 15:35 MAC early commander deaths in ae0 (com_death.py): 3 of 4 died ALONE mid-map at 11-14 min (5.6k-6.8k from x-start 470-2400) to T1 ground raids (stumpies, warriors, rocko), 1 to 10 gunships; no fighters or AA near any. Our fighters at 12 min ae0 12/3/12 vs combo 19/18/28. Read: the T1 air protects the commander mostly by seeing raids early; the underlying fault is a commander walking forward alone at 11-14 min (a commander-safety issue of its own, for the commander skill / contract 'com minutes on their half').
- 11-25 15:21 hourly (clock: the entries labelled 15:00-15:35 above were written between about 14:45 and 15:15). His game off; no engines; free commit 60.5 GB; shared source holds none of today's patches (blocked-unit DLL in the armynet lane, combo / step 1 / backlog / plantcand as henry-outbox patches). Both machines idle, waiting on his answer to tier-audit batch 1 (12 rules: 4 waits, 4 vetoes, 4 tier boosts). Current candidate: blocked-unit DLL + t1-combo (6v6: coms 46 vs off 47/45, eco-seat army 2-3x; air plants still ~2.5x off). Judge (trade at 12 .53 vs .31) waits on his OK for set-target clearing, split-defs and hybrid-off.
- 11-25 16:20 HIS GO: tier audit items 1-12 and the three army-model changes. ARMY: C++ cancel-target (CMD_UNIT_CANCEL_TARGET 34924) when a unit becomes model-held (gadget handsoff path in CircuitAI.cpp, bridge ArmyNetHold); lane DLL rebuilt 16:19 (blk + cancel), cpp/ mirrored file by file. Gate 2 on the PC (gate_judge2.sh): judge1 --judge 5 in all arms: jh (+hybrid) / jnh (no hybrid) / jsd (no hybrid + split-defs), seeds 89-100. TIER AUDIT batch 1 (henry-outbox/tier-audit-1.patch; with spm's eco hunks tier-audit-1-spm.patch, 11 hunks): (1) richBal no longer waits for a T2 lab; (2) 'one T1 line until T2' removed; (3) 'one advanced plant at a time' removed; (4) spam line = land lab with the lowest FacBestPPC below another's; (5) air mute by FacBestPPC, not T2 attr; (6) Outgrown veto dropped (OwnTierMul prices it); (7) lag: non-best ground lines lose spare/cover, T1 army no longer zeroed; (9) RushMul on every plant by cost (his: 'too expensive right now'); (12) t3Sink -> BestGroundLine (his: 'extra metal goes to your best things'). Kept (11, his call): gantry better than lower labs in the yield. Deferred to batch 2: (8) outclassed reclaim beyond T1 and (10) copies for any plant, both with a usage-based reclaim of unused plants (his: 'reclaim things we don't want or use anymore'). Mac: T1-only 6v6 and normal 6v6, seeds 1-8. He plays tonight.
- 11-25 16:24 hourly: his game off; 3 engines (army gate 2 started ~16:21, no game finished yet); free commit 36.6 GB; Mac on tier-audit-1-spm (T1-only and normal 6v6). Clock: relabelled the 16:40 entry to 16:20 (written then); time each entry from 'date', not from memory.
- 11-25 17:21 hourly: his game off; 3 engines (army gate 2: 16/36 games, seeds 89-94); free commit 38.4 GB. So far jh 1W/3T/2L, jnh 1W/3T/1L (a win at 18 min), jsd 0W/4T/1L; 5-seed paired (base jh): trade at 12 jh .59 / jnh .61 / jsd .34, at 20 .44 / .36 / .52; army ratio at 12 1.22 / .61 / .54; forward orders .42 all. First wins of the model in these tests (cancel-target DLL). Mac on tier-audit-1-spm, partial read due ~18:00. Plan for his evening: decide ~18:20-19:00, install by ~19:30; fallback ready (blk + combo + current model).
- 11-25 17:25 HEAD-TO-HEAD (his 11-25: pit our armynet versions against each other; small maps, Red Comet; speed-run). scratchpad h2h.sh: one game at a time, both sides Apexarmynet lane with armynet=1 (DLL bridge), a serve.py per side (--dir armynet-t0/t1, waits for a fresh static file), versions swap sides each seed, both +50, 40 min, speed 4. tools/armynet/h2h_report.py: per side trade (mKillMobile/mLostMobile) and army at 8/12/16/20/30, buildings killed, share of army units in their half (5-15, 15-25 min), commander death minute; paired per game. First pairing newcur: new = judge1 --judge 5 --hybrid (+gate flags) vs cur = enemy1 with his online flags, seeds 1-8; both servers confirmed live in seed 1 (t1 'judge: 443 judged').
- 11-25 17:25 MAC tier-audit-1 partial: (a) notech2 seeds 1-6: air plants per game 10.5/18.2/26.3 (combo 9.6/17.8/24.8; the audit does not cut them), ground at 20/30 33.1/35.9k (combo 35.0/45.5), 3W/3T, coms 28 vs combo 32 / off 39 on the same seeds, lost 1. (b) full tech, audit 1-6 vs off 1-4: all ties at 45; coms 5 vs 4; ground 18.8/36.3/101.1k vs 20.9/40.3/104.1k; first T2 land lab 6.8 vs 7.4 min; T1 share once T2 stands .43/.10/.05 vs .48/.11/.02 ('fewer stronger units' unchanged); air plants 6.8 vs 7.2. No harm, no gain: audit 1 is not tonight's. Tonight's candidate stays blk + t1-combo; the Mac now runs combo in full tech (never tested there) for no-harm before he plays. Air plants in T1 are still driven by air-every's overflow pricing (EvHandsTerm), next to fix.
- 11-25 18:04 MAC combo in FULL TECH (6v6 Carrot, no notech2; blk + t1-combo seeds 1-6 vs plain off 1-8): all ties at 45; enemy coms 4 vs 5 on seeds 1-6, ours lost 2 vs 2; ground (no commanders) 21.1/48.4/136.0k vs 19.8/37.7/104.2k at 20/30/40 (paired ahead 4/6 at 30, 5/6 at 40; +28% at 40); air 51.5k vs 45.9k at 40; eco seat army at 40 38.0k vs 30.7k, bank 232 vs 1470 at 30; first T2 land lab 7.7 vs 7.3 min; T1 share once T2 stands unchanged (.48/.10/.02 vs .47/.12/.04); plants per seat similar. No harm in full tech, more ground. Combo cleared for tonight.
- 11-25 18:21 hourly: his game off; 1 engine (head-to-head), free commit 47 GB. H2H newcur 5 games (Red Comet 1v1, seeds 3+ on combo+evfix scripts both sides): cur 3 W, new 2 W; trade at 12 min cur 1.31 vs new 0.76 (cur better 5/5), at 20 .96 vs .77 (3/5); buildings killed by 20 6.6k vs 4.7k; their half 5-15 .18 vs .20, 15-25 .26 vs .16. Against BARb the judge looked better; head-to-head the current model out-trades the new one in every game: tonight he plays the current model (enemy1, online flags). Evfix FAILED (air plants 61 vs 56 on seeds 1-4, 2/4 W vs 4/4). v0.5.21 built (lane rel521 = v0.5.20 C++ + blocked-unit + cancel-target + today's bridge + idBuf; scripts v0.5.20 + t1-combo + LagCleanup removed); deploy refused for no contract PASS; asked him (--allow-red or a 1-h contract batch); fresh reviewer agent running on the diff.
- 11-25 18:28 REVIEWER (fresh agent on the v0.5.20->v0.5.21 diff): one real bug -- AdvancedPlantAvailable counted the gantry, which 'Disable Tech 2' leaves unblocked (techlevel 3; his Tundra lobby: notech2=1, notech3=0), so step 1's waits still waited: step 1 was INERT in every notech2 test (consistent with the Mac's 'no second land lab'; the PC's 8/8 was noise). Fix (his build-tree principle): reachability BFS from the commander over available defs; an advanced plant counts only if reached; logs 'apex: adv-reach'. Put into ai/v0.5.21 worth.as and henry-outbox/t1-combo-reach.patch; test armu (3 T1-only late games) running. Other reviewer notes: auto-launch (ArmyNetLaunch) is live in the bridge but no launch file exists; buildings written every 10 s; cancel-target skips CountCmd; no crash risks found. Head-to-head loop stopped (5 seeds: current model out-trades the judge model); he plays the current model tonight.
- 11-25 18:42 v0.5.21 READY, not installed: the reachability check now counts a plant advanced only if reached from the commander over available defs AND its best unit beats the directly-built plants' best per metal (notech2 put armamsub/armplat at depth 2). Checks (4-min Carrot 4v4): notech2 'adv-reach ... advPlants=0 available=0', full tech 'advPlants=9 available=1' (T2 labs, gantries, adv air/ships), 0 script errors. ai/v0.5.21 worth.as updated; henry-outbox/t1-combo-reach.patch. Install with --allow-red was blocked by the permission classifier (his call): he runs it.
- 11-25 18:44 v0.5.21 INSTALLED by him (--allow-red): DLL byte-identical to build-rel521; game-side scripts carry the reachability check; smoke.py ok (compiled and loaded, 2 min Ancient Vault). Settings diff vs repo: TUNE_ECO_DANGER_FORCE absent (v0.5.20 base has no eco-danger work), TUNE_LAG_GC left as an unused constant. Army model tonight: enemy1 via play_online.py (his online flags).
- 11-25 19:21 hourly: HIS GAME RUNNING (v0.5.21, T1-only lobby notech2=1, his play_online + serve --find with enemy1; no orphan servers). No engines or builds of mine. Live log t10: 'adv-reach ... reached=83 advPlants=0 available=0' = correct for notech2 (the normal-game check gave available=1 at frames 1-2, so no timing issue); 730 decisions, armynet active. Free commit 42 GB. Waiting for his game; after it: replay read of this game (air plants per seat, land labs, ground/air share) as the first T1 check of v0.5.21.
- 11-25 20:20 hourly: HIS SECOND GAME RUNNING (v0.5.21, T1-only, seats t8-t13 at ~1 min; serve --find restarted 20:13 with enemy1). Game 1 ran to ~25.5 min (frame 46000); every seat of both games logs adv-reach advPlants=0 available=0 (correct). First glance at game 1's plant elections: air still wins many (t5 29 air vs 18 land, t7 10 vs 1, t8 10 vs 1); elections are not builds, the replay read after his session counts what was built. Nothing of mine running; free commit 40 GB.
- 11-25 21:24 hourly: HIS THIRD GAME RUNNING (v0.5.21, full tech, 4v3; our seats t4-t6 at 18.7 min; serve --find with enemy1). Nothing of mine on the PC; free commit 39 GB. He reported live that every seat of ours went T2 air. Logs: all three seats built lab -> air plant -> T2 air plant, no T2 land lab; production led by air constructors (t6: 36 corca ordered, 41 air cons standing) and Firefly rez planes (t4 35); t4 and t6 army-stat squads=0 (no ground army). Same cause as the T1 air drift: the air plant is bought as a constructor source (TUNE_AIR_EVERY on, "air constructors' build power and spilled metal"), and air cons then build the T2 air plant first. Mac: opening A/B (aa-armed-only.patch) and self-play round 0 (A/A, then rounds with --explore) sent; no reply yet. serve.py --explore added (default off).
- 11-25 22:20 hourly: he finished playing at ~21:35; the PC runs the army-model work now (lane armynet). A/A head-to-head (enemy1 vs enemy1, Red Comet 1v1, +50, speed 4, replays kept) at seed 6 of 6; first 3 read: 1 win each and a draw, single-game trade swings to 0.33 vs 2.85, so 20-game win counts are the gate, not 3-game means. Built, not yet deployed (waits for the A/A to end): armynet lane DLL whose armynet line adds heldAir=held/all armed air and focusNotHeld, to see whether the model or the air layer holds the planes. serve.py --explore added (default off). Source changes this evening, each with its measurement: aa-armed-only (Mac, measured, kept); one builder count + HandBest + ten-air-con floor removed (he approved; smoke ok; Mac A/B on v0.5.21 next); air-defend-home interim patch reverted. No campaign or recorder runs (the overnight step-rate run is over); his play_online serve waits idle. Free commit 49 GB, 1 engine.
- 11-25 23:20 hourly: self-play round 1 at 6 of 12 games (two lanes, armynet + rel521, both sides enemy1 + --explore 1.0). The new bridge line answers the Dragon question: the model holds nearly every armed aircraft (heldAir 126/132, 48/49, 26/26, 24/27, 18/19, 96/99), so parked planes are the model's own choice, not the air layer's; air quality is a model matter for self-play. Bug found and fixed: replay_orders.py with a relative --out resolved the engine's write dir inside itself, so the recording widget never loaded (his Otago replay and the 4 A/A builds wrote no orders); out is now resolved to an absolute path, builder restarted. Mac: one-con-count measured on v0.5.21 (air cons 173 -> 23, income at 20 83 -> 159, losses 3 -> 1; kept); opening forced picks each off (results/opening/...); seeds 7-12, air-plant trace and the lobby-hands opening test queued. Free commit 30 GB, 3 engines.
- 11-26 00:20 hourly: self-play round 1 done (12 games, two lanes, both sides enemy1 + --explore 1.0): lane a 2/2/2 (wins x / wins y / draws), lane b 1/1/4. Training files: 11 of 12 built (s13's playback died at 6 s, likely a start clash between the two builders) + the 6 A/A games = 17 own games in runtime/armynet/own-games/selfplay-r1. sp1 TRAINING started 00:2x: init enemy1 model-010000, --own selfplay-r1 --own-share 0.5, 8,000 steps, 1 worker, cuda (1,331 player games train / 141 held out; init widened scal 8 -> 10, judge head fresh). Next: held-out eval vs enemy1, then the gate: sp1 vs enemy1, 20 games head-to-head on both lanes, promote at >= 60% of 20, a 40-min draw counted for the side ahead on army + economy value at the cap (half the self-play games were draws). Mac idle after the air/ground spend read (no seat air-primary on Carrot 4v4; his Otago air-primary game not reproduced). Free commit 56 GB, 0 engines.
- 11-26 01:20 hourly: sp1 training at step 3,200/8,000, no Traceback, 0.95 steps/s; GPU 7% (9.5 GB, ComfyUI resident): data-bound on 1 worker. Not restarted mid-run (model.pt saved 00:55 holds no optimizer state, a resume would be a different run). Next round: 3 data workers while no engines run (free commit 40 GB now), measured as steps/s against this 0.95. ETA ~02:45, then held-out eval vs enemy1 and the 20-game gate on both lanes. No engines; Mac idle; the perf session reads his three v0.5.21 games as its lag baseline (max behind 1.7 s).
- 11-26 02:20 hourly: sp1 at step 6,800/8,000 (0.95 steps/s, no Traceback); training loss on the click place f_cell 5.5 -> 5.0 since step 1,000 (training batches, not held-out). Done ~02:45; then held-out eval vs enemy1 (eval-only) and the gate: sp1 vs enemy1, seeds 31-40 on lane armynet and 41-50 on lane rel521, no exploration, both +50 Red Comet. No engines, free commit 32 GB, Mac idle.
- 11-26 02:50 C: FULL at ~02:37: sp1's final save failed ("file write failed"; model.tmp partial). The repo grew ~17 GB in the last 30 h (engine lanes, hotcpp runs, own-games); the rest of the drive was already near full. Fixed by the standing answer: tools/archive_old.py --apply --days 3 moved 50 GB of 3-day-old match folders to G:\bar-ai-archive; C: free 0 -> 83 GB. Candidate = sp1's step-6,000 save (02:08; trainer saves every 2,000), frozen as runtime/armynet/sp1/model-006000.pt. GATE 1 started 02:50: sp1 vs enemy1, seeds 31-40 lane armynet + 41-50 lane rel521, no explore, Red Comet +50; held-out eval (--eval-only) running beside it.
- 11-26 03:05 sp1 held-out (141 player games, same data version as eval-enemy1-skillbase): vs enemy1, act logloss .3191 vs .3168, place error 428 vs 415 elmos, force click rate .036 vs .042 (players .044), goal 950 vs 941, deep .400 vs .397 (players .402), judge_auc .627. Slightly worse at imitating players, as expected with half its data from our own games; not the yardstick. Gate 1 (20 h2h games) decides.
- 11-26 03:20 hourly: GATE 1 at 6 of 20 (sp1 vs enemy1): enemy1 3, sp1 2, draw 1 (s33 enemy1 by commander kill at 12.2 min; s43 sp1 at 9.5). Free commit 7.8 GB, under the 20 GB bar: the PC's largest users are not ours (a vite dev server from the gin-verify work at 19.7 GB, his ComfyUI 9.5, WSL/Docker vmmem 8.8 from DLL builds); ours: 2 engines 5.4 GB each + 4 servers 2.2 each. run_match waits on memory before each launch, so the gate slows rather than overcommits. C: 82 GB free.
- 11-26 04:20 hourly: GATE 1 at 18 of 20: sp1 8 wins, enemy1 6, draws 4 (lane a e1 4 / sp1 3 / 2 draws; lane b sp1 5 / e1 2 / 2 draws). The last two games (s40, s50) are running; nothing more launches. Draws get decided by army + economy value at the 40-min cap once all are in. Free commit 3.0 GB (others' vite 19.7 GB, ComfyUI, vmmem); ours ~20 GB until the last two end. C: 81 GB free.
- 11-26 04:50 GATE 1 DONE: sp1 vs enemy1 10-10 (sp1 9 decided + 1 at cap, enemy1 7 + 3), bar 12/20: NOT PROMOTED, no improvement. Paired measures all near even; sp1 army at 8 min larger in 16/20, more in their half. Page: results/armynet/2026-11-26-gate1-selfplay-round1.md. Round 2: the 20 gate games join own-games (37 files with round 1), train from enemy1 the full 8,000 steps with 3 data workers (measure steps/s vs 0.95), then gate 2. Playbacks one at a time while free commit stays low (5.6 GB; others' vite + ComfyUI + vmmem).
- 11-26 10:15 resumed after a session restart. Overnight: the gate-1 games' playbacks built 17 of 20 (3 stopped by the recorder's yield-to-his-game check); own-games selfplay-r1 now 34 files. Nothing of ours crashed after the 02:37 disk-full (our sp1 final save was the casualty; the topic notes another session's vitest ENOSPC at the same time). Disk 72 GB free, free commit 70.7 GB, no engines. sp2 TRAINING started 10:15: init enemy1, --own selfplay-r1 (34) --own-share 0.5, 8,000 steps, 3 data workers (speed vs sp1's 0.95 steps/s to be read), then gate 2.
- 11-26 10:20 hourly: sp2 at step 800/8,000, 1.91 steps/s with 3 data workers vs sp1's 0.95 on 1 (measured: 2.0x; GPU 14%, still data-bound but kept). No Traceback; done ~11:25, then gate 2 (sp2 vs enemy1, 20 games on both lanes). His game off (newest bot log 21:34 last night). No engines; C: 72 GB free; free commit 60 GB. Mac idle.
- 11-26 11:20 hourly: sp2 at step 6,200/8,000 (1.6 steps/s overall since 10:15, slower than the first 800 steps' 1.9), no Traceback, done ~11:40. Gate 2 then splits across both machines: PC seeds 81-90 (two lanes), Mac seeds 51-60; the Mac has the full tool set (armynet-tools.tgz) and enemy1 (same md5) and builds round-3 self-play data (seeds 61-72) first. C: 122 GB free after the cleanup session's work; free commit 44 GB; no engines.
- 11-26 11:45 sp2 DONE (8,000 steps, 4,944 s = 1.62 steps/s with 3 workers; sp1 0.95 on 1). Frozen as runtime/armynet/sp2/model-008000.pt (md5 84bb5f05...). Held-out vs enemy1 / sp1: act logloss .3222 / .3168 / .3191, place 424 / 415 / 428, click rate .039 / .042 / .036 (players .044), goal 923 / 941 / 950 (better), deep .406 / .397 / .400 (players .402), judge_auc .648 (sp1 .627). GATE 2 started 11:45: PC seeds 81-85 lane armynet + 86-90 lane rel521; Mac seeds 51-60 (sent split in henry-outbox/sp2/).
- 11-26 12:20 hourly: GATE 2, PC half at 9 of 10 (s90 running): sp2 6 (5 decided + 1 at cap), enemy1 3 (all decided); results valid (gameover, no crash). Two sp2 wins by commander kill at 12-13 min (s82, s83). Mac half (seeds 51-60) starting after its job-A game. Bar 12/20 overall. C: 120 GB free, free commit 45 GB, 1 engine, his game off.
- 11-26 13:00 GATE 2 PC half DONE: sp2 7 (5 decided + 2 at cap, 231k vs 127k and 311k vs 151k standing metal) vs enemy1 3 (decided), seeds 81-90. Needs 5 of the Mac's 10 (seeds 51-60) to reach 12/20. PC meanwhile plays round-3 self-play: sp2 vs enemy1, both --explore 1.0, seeds 91-102 on both lanes (data for round 3 whatever the gate says).
- 11-26 13:20 hourly: gate 2 rebalanced. The Mac ran one game at a time (my handover never set up parallel lanes; he says it can run 4+); asked it for 4 lanes, gate seeds 51-55 there, the PC took 56-60: s59 done, s56 and s60 running (4 servers, 2 engines). The two round-3 self-play games whose runners I stopped finished and are in the ladders (s91, s97). Free commit 29 GB, C: 121 GB free. Waiting on the Mac's reply and its half.
- 11-26 13:35 (label corrected; was written as 14:05) GATE 2 DONE: sp2 vs enemy1 10-10 (PC 81-90 7-3, Mac 51-57 3-4, PC 58-60 0-3), NOT PROMOTED; all games incl. PC duplicates of 56/57: 10-12. Page: results/armynet/2026-11-26-gate2-selfplay-round2.md. Two rounds, two ties: more of the same data does not move it. Round 3 changes what is learned (outcome weighting on own games), from sp2.
- 11-26 13:50 (label corrected; was written as 14:20) ROUND 3 SET UP. Diagnosis of two ties: own games were nearly pure imitation (f_w = exp(0.5 x positive part of the rating): middle 80% of clicks weighted 1.00-1.18; push-down only below -1: 2.7% of clicks; f_unlike ~0.001 in the training log), so the model mostly copied itself. New, own games only and off by default: BARAI_OWN_RATE_K (data.py _force_labels): f_w = exp(K x raw rating) both ways and f_neg = raw < -0.5. Checked on h2h-sp1a-s11 (479 clicks): K=0 f_w 0.63-2.72 (p10-p90 1.00-1.18), neg 2.7%; K=1 0.14-7.39 (0.63-1.40), neg 9.2%. 40-step smoke run OK. Player data and serve untouched (the path test reads "own-games"). Data for round 3: PC self-play sp3 (sp2 vs enemy1, both --explore 1.0) seeds 91, 97 done + 92-96 and 98-102 running; gate-2 PC replays (15) building into own-games/selfplay-r2; Mac 61-72. Plan: sp3 = from sp2, K=1, own-share 0.5 over selfplay-r1 + r2, 8,000 steps, 3 workers; gate 3 vs enemy1.
- 11-26 14:20 hourly: round-3 data. PC self-play sp3 7 of 12 done (lanes a and b, 2 at once); gate-2 playbacks 6 of 15 built into selfplay-r2; Mac round-3 set (12 npz, md5 checked) unpacked into own-games/selfplay-r3; Mac playing 24 more (seeds 111-134, selfplay-r4). The perf session swapped in a faster data.py (1.45x per worker, batches proven bit-identical incl. the live path and BARAI_OWN_RATE_K on/off); its train_np.py transport change (2.2x loader) waits for a 600-step benchmark when engines are down. Free commit 14.5 GB (ours 3 engines ~16 + servers ~9; ComfyUI 9.5, vmmem 8.8): new launches wait in run_match's memory gate. C: 117 GB free.
- 11-26 15:20 hourly: round-3 PC data done: self-play sp3 12 games (sp2 vs enemy1, both exploring) and the 15 gate-2 playbacks built (own-games/selfplay-r2). Engines 0: the benchmark window for the perf session's train_np.py (600 steps old vs new) is open now; the sp3 self-play playbacks and round-3 training wait for it. Free commit 21 GB, C: 114 GB free. Mac: 24 self-play games (111-134) running.
- 11-26 15:50 Perf session's benchmark: data.py swap gives 2.27-2.30 steps/s at 3 workers (was 1.6; 8,000 steps ~58 min instead of ~83); the array transport only pays at 5-6 workers, which drop free commit under 3 GB while ComfyUI + vmmem are resident: stay at 3. train.py now has the array transport (identical tensors) and --own as a comma list. Mac r4 set: 24 npz (md5 a461015b) unpacked into own-games/selfplay-r4. Own games now: r1 34, r2 15, r3 12, r4 24, + PC sp3 12 building into selfplay-pc3 = 97. Mac playing 24 more (selfplay-r5, seeds 141-164).
- 11-26 16:21 hourly: PC sp3 playbacks all built (12, own-games/selfplay-pc3): own games now 97. Round-3 training NOT started: free commit 4.6 GB with no engines of ours. Two vite dev servers from C:\Users\apexe\gin-verify (ux-discover port 5194: 24 GB, ux-d2 port 5195: 22.3 GB) + ComfyUI 9.5 + vmmem 8.8. Training needs ~8 GB (main + 3 workers). Not ours to stop; asked him. Mac: r5 self-play (141-164) running.
- 11-26 16:30 he stopped the two runaway vite servers (46 GB); free commit 4.6 -> 55 GB. sp3 TRAINING started: init sp2, --own selfplay-r1,r2,r3,r4,pc3 (97 own games) --own-share 0.5, BARAI_OWN_RATE_K=1.0, 8,000 steps, 5 workers (commit room allows; perf session's loader test said 5-6 pay with the array transport). First 200 steps 97 s incl. warm-up; free commit 43 GB with it running.
- 11-26 17:20 hourly: HIS GAME STARTED 17:17 (spring.exe). sp3 at step 5,200/8,000, 2.6 steps/s with 5 workers (GPU 40%), no Traceback, ~18 min left; its 6 processes set to BelowNormal priority so his frames come first. No PC engines while he plays: gate 3 goes to the Mac (all 20 games) when sp3 is done. Mac: serve-setting gates A (arc off), B (--commit 0.8), C (--unit-contact) running, 20 games each. C: 129 GB free, free commit 32.5 GB.
- 11-26 17:55 his game (17:17) has ended; sp3's priority back to Normal (it fell to ~0.5 steps/s while BelowNormal beside his game; step 6,200/8,000). Prepared for him, not run: tools/armynet/watch_blitz.sh, a windowed watch game with the Battle Blitz full-set tweaks (gameconfigforbar/barbattleblitz @66da6339, tweakdefs + tweakunits..tweakunits9; tweakunits5 plain, not the evotiming-relative variant), our AI + model on the DLL bridge vs BARb hard, both +50, Comet Catcher, speed 4. run_match.py: --modoption K=@file (the tweaks total ~140 KB, over the Windows command line). tweakunits9 was rate-limited by GitLab; the launcher fetches any missing file. Values passed unpadded as the lobby does (tweakdefs, tweakunits8 lack one '=').
- 11-26 18:05 sp3 DONE (8,000 steps, 4,446 s incl. the BelowNormal stretch beside his game). Frozen runtime/armynet/sp3/model-008000.pt (md5 69a89c4f...). Held-out vs enemy1 / sp2: act logloss .3155 / .3168 / .3222 (best of the three), place 416 / 415 / 424, click rate .041 / .042 / .039 (players .044), goal 927 / 941 / 923, deep .392 / .397 / .406, judge_auc .651. Unlike sp1/sp2 it lost nothing on imitation. GATE 3: all 20 games on the Mac (seeds 301-320, sp3 vs enemy1); the PC stays idle, he has guests.
- 11-26 18:20 hourly: PC idle by design (he has guests): 0 engines, no servers, no training; C: 127 GB free, free commit 55 GB. Mac: gate 3 (sp3 vs enemy1, seeds 301-320) on 4 lanes, ~1 h; then serve gates B (--commit 0.8) and C (--unit-contact) resume. Serve gate A done: arc on 11 vs off 9, no measurable difference (results/armynet/2026-11-26-serve-arc-off.md). Watch launcher for him ready (tools/armynet/watch_blitz.sh), not run.
- 11-26 19:20 hourly: PC idle by design (guests): 0 engines; C: 124 GB free, free commit 55 GB. Gate 3 on the Mac (started ~18:10, ~1 h at 4 lanes): no result yet, asked for its tally.
- 11-26 19:35 GATE 3 DONE (Mac): enemy1 14 vs sp3 6, NOT PROMOTED, worse. Three rounds: ties at 10-10 twice, then a loss once the per-decision rating was weighted hard. The rating (trade vs the side's other orders in the window) does not track winning; amplifying it amplifies its error. Found: all head-to-heads were Armada t0 vs Cortex t1, t0 won 42/65; selfplay.sh now mirrors factions, alternating every 2 seeds. Page results/armynet/2026-11-26-gate3-outcome-weighted.md. Next: rethink the signal before another round (below, in the report to him).
- 11-26 19:50 RATING VS RESULT (64 decided own games): the side with the higher mean per-decision rating WON 12/64 (19%); fewer orders rated under -0.5 won 40/64 (62%); winners' mean 0.026 vs losers' 0.077. The rating is anti-aligned with winning (likely local trade favours a side fighting back near its own guns), which explains gate 3. Do not weight imitation by this rating. Next round: imitate the winning side of each own game (game result), and the rating needs a redesign (map control / territory, not local trade) before it trains anything.
- 11-26 20:30 hourly + ROUND 4 started. New in data.py, own games only, off by default: BARAI_OWN_WINNER=1 learns only the team that won the game (result 1; capped draws give nothing) with flat click weights (f_w 1, f_neg 0). Checked on gate1a-s33: default examples from teams 0 and 1 (2,261, f_w 1.00-2.57); winner mode team 0 only (1,087, f_w 1.00). sp4 TRAINING 20:30: init enemy1 (the champion), all 5 own sets, --own-share 0.5, BARAI_OWN_WINNER=1, 8,000 steps, 5 workers. Mac: gate C (--unit-contact) running. Gate B done 10-10 (results/armynet/2026-11-26-serve-commit.md). His notes added to the rating redesign: score what is not lost (eco damage and territory loss prevented). PC: no engines, free commit 55 GB.
- 11-26 21:20 sp4 DONE (8,000 steps in 2,628 s = 3.0 steps/s, 5 workers). Frozen runtime/armynet/sp4/model-008000.pt (md5 4387de3c...). Held-out vs enemy1: act logloss .3193 vs .3168, place 411 vs 415 (better), goal 911 vs 941 (best so far), click rate .041 vs .042, deep .396 vs .397, judge_auc .641. GATE 4 started: PC seeds 501-505 lane armynet + 506-510 lane rel521 with mirror factions (s501 Armada both sides, checked); Mac 511-520 after its r6 games. Serve gate C done: unit-contact 7 vs base 13, not adopted (results/armynet/2026-11-26-serve-unit-contact.md).
- 11-26 21:20 hourly: gate 4 PC half at 2 of 10 (s501 enemy1, s506 sp4, both decided), mirror factions; 2 engines + 4 servers; Mac 511-520 queued behind its r6 games. C: 119 GB free, free commit 36 GB. No training running.
- 11-26 21:45 he may play later tonight and asked to work optimistically. Plan: tonight's model = sp4 if gate 4 ends at least even, else sp2 (10-10, best held-out signs); never sp3 (6-14). v0.5.22 being prepared from today's source (aa-armed-only, one builder count, lobby-hands opening, the perf session's lag stretch): lane armynet already runs exactly it (no AI script or cpp change since its 11-25 22:36 deploy). Release batch queued (runtime/rel522/release_batch.sh): lane-armynet vs Apex:v0.5.21, +50, speed 20, 30 min, Red Comet / Comet Catcher / Carrot x 4 seeds, sides and factions swapped, army model off both; starts when the gate-4 runners end. Then contract.py --record, snapshot ai/v0.5.22 (AIOptions armynet def=true as in v0.5.21), reviewer pass, deploy.
- 11-26 22:15 GATE 4 DONE (approx; s510 last): sp4 8 vs enemy1 11 of 19 counted (Mac 6-4, PC 2-7): not promoted; the halves disagree, possibly the bases (Mac v0.5.21+patches vs PC Unstable lane). Tonight's model: sp2 (play_online --model runtime/armynet/sp2/model-008000.pt). v0.5.22: release batch vs v0.5.21 PASSED the contract (12 games, won/ahead 0.67) but could not be recorded (the bar must be the newest committed release, v0.5.18). The diff review then found v0.5.21's T1 changes (t1-combo + reachability) were never in the shared source, so a v0.5.22 from Unstable would drop them: henry-outbox/t1-combo-reach.patch applied to ai/Unstable (clean) and to the ai/v0.5.22 snapshot; the Mac's measurements of tonight's fixes were on v0.5.21, i.e. with these changes, so this is the measured combination. Lane armynet redeployed, smoke ok; release batch vs v0.5.18 rerunning (matches/rel522c-*).
- 11-26 22:18 (label corrected; was written as 22:35) v0.5.22 snapshot: ai/v0.5.22 = ai/Unstable (now incl. t1-combo-reach) + AIInfo version v0.5.22 + AIOptions armynet def=true (as v0.5.21) + v0.5.21's trained nnweights.as (contract's tree hash skips AIInfo/nnweights/policydata). Caveat: the PC release batch's lane played Unstable's EMPTY net (NN_TRUST_KIND 0), not the trained one; the Mac's measurements of the three fixes were on v0.5.21, i.e. with the trained net. Real C++ diff vs v0.5.21 reconstructed (fork base + v0.5.21-cpp.patch, line endings normalized): runtime/rel522/cpp.diff, 158 lines, 8 files. Fresh reviewer agent running on scripts/engine-side/cpp diffs. Release batch vs v0.5.18 running (matches/rel522c-*).
- 11-26 22:20 hourly: release batch vs v0.5.18 at 2 of 12 games, 4 engines (the PC's limit); reviewer agent running. C: 114 GB free, free commit 34.5 GB. Mac: r6 self-play 413-424 then its npz build. From now on every entry's time comes from `date`.
- 11-26 22:27 release batch c ran only 4 games: once ai/v0.5.22 existed, run_match refused the lane (it played Unstable's empty net, not the newest release's). Lane redeployed (installs v0.5.22's = v0.5.21's trained net, checked byte-identical); batch rerunning in full as rel522d-* (12 games vs v0.5.18), so the pass covers the net he will play. The earlier caveat is gone.
- 11-26 22:37 REVIEWER (fresh agent) on the v0.5.22 diff. Fixed: (1) HandBest could pick minelayers (armmlv/cormlv score above armcv): a hand must now build an extractor (BuildsExtractor; the claim-extractor test would have dropped Armada's T2 con, which builds only armmoho) and its pool must not be full (also fixes the floor deadlock, finding 5); each def's value is cached in the same 5-s refresh as the best (finding 4). (2) Today's cpp/ had lost four things v0.5.21's DLL had (my 11-25 lane sync from cpp/ overwrote them): isArmyNet default true, the id-based nano scan in FactoryManager, the c.site/c.siteNear/c.nanoScan timers, asprof TOP 150; v0.5.21's six files restored into cpp/ (the comment there no longer quotes him); cpp/ now differs from v0.5.21 only by InitScript (GetCustomParam) and ArmyNetBridge (heldAir); lane DLL rebuilt (contains c.nanoScan, c.siteNear, GetCustomParam). (8) ai/v0.5.22/engine-side/SkirmishAI.dll was the stale October copy: replaced with this build. Open: (3) TUNE_ECO_DANGER_FORCE=1 ships the eco-seat danger change another session left on (unmeasured, eco seats only); (6) unset lobby keys fall back to the old opening + replan; (7) assist drones count as hands. Batch rerunning as rel522e-* (the d run was stopped: wrong code).
- 11-26 22:40 OWN MISTAKE, caught at 6 engines (limit 4): TaskStop on the background shell left its release_batch loop running, and my sed retag of the running script made that loop launch rel522e games beside the new run. All loops and lane engines stopped; fresh script release_batch_f.sh, started once (rel522f-*). Rule for myself: never edit a running script; check for leftover loops (bash.exe ... release_batch) after any stop.
- 11-26 22:55 HIS WATCH GAME running (he asked): tools/armynet/watch_blitz.sh with sp2, Battle Blitz full set (tweakdefs + tweakunits..9 all loaded, 145 unit tweaks per the infolog), lane armynet's final v0.5.22 build, our AI + model on the DLL bridge vs BARb hard, both +50, Comet Catcher, speed 4; model server ordering. The release batch was stopped for it (0 engines beside his window) and reruns after. Fix: the launcher passes absolute tweak paths (run_match runs elsewhere).
- 11-26 23:06 BATTLE BLITZ support started (he asked; its creator likes our AI). Their tweaks give the commander (53 options) and some constructors (legaceb 61, corprinter 54) combat units, and 10 units EMP weapons. Built: WK_UNIT (17) want, want_unit.as: the builder's best armed mobile unit by UnitPPC, gain = army flow min(bp x unit metal / build time, army gap / fill / (1 + lines), spare metal), CAT_PRODUCE, election step 10 (was a duplicate metal-reclaim call), executed as Requests::Take(..., RECRUIT) (the C++ generic task; its builder RECRUIT case is a stub). All kind-indexed arrays are bounds-guarded; the policy net one-hot simply has no slot for it. Parked (runtime/rel522/builder-unit.patch + want_unit.as.parked) until v0.5.22's contract is recorded, since the record hashes ai/Unstable. EMP pricing next (needs a C++ binding for paralyzer damage). A/B ready: runtime/rel522/blitz_ab.sh (Red Comet, Blitz tweaks, vs BARb hard, 4 seeds per arm). Waiting for his watch game to end.
- 11-26 23:15 v0.5.22 candidate vs v0.5.18: contract FAIL (won or ahead 2 of 12; ground given up 0.32 vs 0.19) -> NOT released (results/release-gate/2026-11-26-v0522-candidate-vs-v0518.md). He plays v0.5.21 tonight. Next session: v0.5.21 vs v0.5.18 on the same 12, then bisect today's changes. Battle Blitz: builder-units reapplied to ai/Unstable; lane rel521 synced to cpp/ and rebuilt, deployed, smoke ok; A/B running (matches/blitz-A/B-s1..4, he said not to wait for his watch game).
- 11-26 23:22 BLITZ A/B (Red Comet, full Blitz tweaks, vs BARb hard, +50, 15 min, 4 seeds): the builder-unit want WORKS mechanically: B-s1 offered 23, won 11, 12 corcan build tasks done by the commander, 0 aborted. But it rarely wins: B-s2/s3/s4 offered 6/13/5, won 0/1/0 (its gain is capped at the army gap's share per line, demand/(1+lines), small with labs up). Army built at 15 min: A 5.8/23.3/14.9/36.3k, B 24.2/14.4/11.4/10.6k; results A 4 time-capped, B 3 capped + 1 loss: 4-seed noise dominates (B-s2/s4 made no builder units yet differ from A). Instrument gap: BARAI_PROD logs only factory output, so builder-made units are invisible there; count them from task-gone. Next: price review (should a builder's unit share the gap with labs at all, when a builder IS the line in this mode?), log builder-made finishes, more seeds; then EMP.
- 11-27 00:12 v0.5.21 vs v0.5.18 (same 12-game setup, model off): PASS, won or ahead 6/12; so v0.5.22's 2/12 comes from today's changes. Release games do register lag at speed 20 (severity 1-3 at times in both builds), and the lag stretch then runs only every 2nd-4th update chunk: suspect 1. BISECT running vs v0.5.18, 12 games each: arm S (lane armynet) = v0.5.22 minus the lag stretch (v0.5.21's main/perf/decide); arm C (lane rel521) = v0.5.22 minus the one builder count (v0.5.21's production.as + TUNE_T1_AIR_CON_MIN restored in the lane only). ai/Unstable restored to v0.5.22 after each deploy (checked); Blitz edits parked in runtime/rel522/. He's not playing tonight; the Fable session will send army-model orders.
- 11-27 00:20 hourly: bisect at arm S 4/12, arm C 5/12 (2 engines running between pairs; limit 4). C: 109 GB free, free commit 44 GB. No message from the Fable session yet.
- 11-27 00:42 NEW PLAN (todo/armynet-objectives.md, his 11-27, led by the Fable session): self-play rounds, serve-flag gates and model-vs-model gates STOPPED (told the Mac too). Step 2 instrument started: tools/armynet/objectives_offline.py (advance / aimless / flips from recorded npz, order mass, with a --shuffle random-target baseline). First read: model self-play advance 0.90 (rand 0.52), aimless 0.024 (0.061), flips 0.077 (0.50); top-quartile winning players 0.52 (0.39), 0.10 (0.19), 0.16 (0.59). Definitions likely too loose (any known building counts; memory covers the map); sent to Fable with a proposal. Rules-army column: games with replays after the bisect (my first launch overlapped the bisect's next pair = 5 engines for ~2 min; killed mine; launch only after the bisect ends).
- 11-27 00:49 BISECT vs v0.5.18 (12 games each, same setup, same trained net 43aa9603): arm S (v0.5.22 minus the lag stretch) PASS, won/ahead 8/12, lost per killed 0.97 vs 2.67; arm C (v0.5.22 minus the one builder count) PASS, 8/12, lost per killed 1.72 vs 1.34 (noise). Full v0.5.22 was 2/12. Either removal restores it, so either the two only hurt together or the 2/12 was bad luck: RERUN of v0.5.22 unchanged on the same 12 running (matches/rerun22-*, lane armynet, 2 at a time) alongside 6 rules-army games with replays (matches/rules-r2-*, lane rel521, 2 at a time) = 4 engines.
- 11-27 01:13 Fable's per-army definitions built: tools/armynet/objectives_army.py (commitment by army metal-time from the 10-frame unit samples' standing cmd/target, the order funnel, axis flips per unit-minute; --shuffle baseline; Otsu cluster floor). Model (38 no-explore self-play games): idle .565, cluster .246, their half .476; rules (2 of 6): idle .432, cluster .202, half .411; top-q winning players (23): idle .392, cluster .262, half .382. Funnel arrived .64/.59/.48. Flips/unit-min .20/.28/.15. Biggest gap: model army idle (no order or sitting at its target). Model-vs-rules games with replays needed next (none recorded here). Sent to Fable.
- 11-27 01:21 hourly: v0.5.22 RERUN vs v0.5.18 PASS 6/12 (first batch 2/12; bisect arms 8/12 each): the 2/12 reads as noise, no regression shown; pooled v0.5.22 8/24. Pages in results/release-gate/2026-11-27-*. Not recorded or released (pooled number and his call). Step-2 instrument: objectives_army.py now reports idle split, their half by window x unit/metal (reconciles gate 1's 0.15-0.25 with .476), ghosts, finishing; found the training + serve memory keeps buildings seen to die (input defect, reported, not fixed). Rules column 5/6 built. The overnight-step/campaign items in this check are from the ended 11-19 run; nothing of it runs. C: 112 GB free.
- 11-27 01:23 Step-2 page done: results/armynet/2026-11-27-step2-army-instrument.md (model 38 / rules 6 / players 23). Model gap: idle at its target .286 (rules .231, players .122), ghost clusters .703 (.547/.437), building kills at a live cluster 396 per 1k metal-min (846/475), no order after clearing .651 (.364/.373). Cause candidate: memory keeps buildings seen to die (train + serve). Sent to Fable; next the paired model-vs-rules recorded set.
- 11-27 01:39 Fable opened model changes A-D. A: paired model-vs-rules set running (tools/armynet/model_vs_rules.sh, enemy1 + his online flags vs our rules army, Red Comet 1v1 +50, seeds 1-6, model side by seed parity, same faction both sides, replays -> own-games/mvr-a; lanes armynet + rel521 both v0.5.22). B built, OFF by default (BARAI_ABSENT=1): data.absence_marks, one function for training (Game._memory) and serve (fold_history store marks -> Game.live absent=): a remembered building is forgotten once one of our units had its spot inside 0.7 x sight after its last sighting with nothing there; keyed by id AND position (the engine reuses ids: the first parity diff was a dead building's id reused). parity.py on 4 games (rules, two player recordings, gate1a): 24/24 identical with it on and off; on a rules game it remembers 119 vs 160 buildings late. D: objectives_army.py finishing adds weapon-range contact and the order kind (rules: in range .533; move .459 / attack .373). contract.py: new "army idle on dead enemy ground" (infolog only: standing, not firing, within 500 of an enemy building death >= 30 s old; first reads 0-0.10 per seat). A's seed 2 serve started 01:28:18 during the data.py edits (before the gate): to be replayed.
- 11-27 02:20 hourly: A done (model 1-5 vs rules; page results/armynet/2026-11-27-model-vs-rules-A-B.md: at a live cluster the model kills buildings at 405 vs 1,253 per 1k army metal-min, standing under MOVE .80 vs .41 / attack .17 vs .39, in weapon range as often). B's 6 games played (every server logged absent=1), A's seed 2 replayed; playbacks building (2 engines). C: enemy1's recipe is the Mac's (w40-40k init, own-fix1 0.25, 10k OneCycle) -- to agree with Fable. C: 110 GB free, free commit 40 GB.
- 11-27 02:22 A + B DONE: results/armynet/2026-11-27-model-vs-rules-A-B.md (indexed). B (BARAI_ABSENT=1 on serve only): model 2/6 vs A 1/6 (0/6 with s2's replay); live-cluster kill rate 304 vs rules 885 (A 405 vs 1,253); move .63 vs .45 at a live cluster. The memory defect is real but not the main gap vs the rules army; order kind at a cluster is. C awaits Fable (Mac recipe vs fine-tune here). Engines 0.
- 11-27 02:33 Fable's decisions: C on the Mac (enemy1 recipe exactly + BARAI_ABSENT=1; sent to Workhorse with the code paths and a parity check first); E serve-only tests. Reported first: --kind-mode fightnear was gated 11-24 vs BARb (-.127 paired, force orders halved because a fight order rarely arrives); E1 is narrower (fight only for orders aimed at a known cluster / presumed base). Built, off by default: serve --cluster-fight (E1) and --force-idle (E2: still + at its target or orderless -> pf 1, forced answer logged same/deeper/sideways/back), minute line "objectives-E"; cluster_near tested on a synthetic grid. F: players at a live cluster stand under MOVE too (top-q winners .766, all .797; attack .191/.074) yet kill 475-669 vs the model's 405: the attack habit is the rules army's. Step-3 relabel check: tools/armynet/relabel_check.py (dwell-time hindsight over 3 min, join only as fallback); 4 games: 0.81 mapped, unmapped .14; full runs going. Holding E until Fable says go.
- 11-27 02:36 Step-3 relabel check: results/armynet/2026-11-27-step3-relabel-check.md. Top-q winners .816 mapped vs .728 on shuffled tracks: the specified objective list covers the map (spots in their half .29 either way); signal only in army/threat/unmapped. Clusters + base .03 of player clicks. Label needs tightening before training (click target within reach of the objective; contact-weighted dwell). E still held for Fable's go.
- 11-27 02:39 E RUNNING (Fable's go): enemy1 + his flags vs our rules army, seeds 1-6 as A. E1 --cluster-fight (lane armynet), E2 = E1 + --force-idle (lane rel521), then E3 = E2 + --hybrid-cluster (new, serve-only: a ground unit with a building in sight within reach at a known cluster goes to the AI's own attack via the existing release line, until none is in view; no C++), seeds 1-3 on armynet, 4-6 on rel521. Sets own-games/mvr-e1/e2/e3. objectives_army.py now logs orders per unit-minute at a live cluster: A model 42.2 vs rules 25.8 (recorded orders, any issuer) -- the order rate is not the gap here (the 11-24 read was in-contact vs BARb). First minutes: E1 turned 1 of 138 moves into fight by minute 6; E2 forced 93 answers by minute 5 (same 29, deeper 44, sideways 4, back 16).
- 11-27 02:44 Step-3 EPISODES (Fable's relabel by trip): tools/armynet/episodes.py, page results/armynet/2026-11-27-step3-episodes.md. Cluster+base share of force episodes: rules army .120 (vs itself and vs the model), model .073, top players .030; heading agrees with the contact place .95 vs .64-.71 shuffled; episodes per side-game players 119 (median 80 s), rules 185-260, model 145. E still running (E1/E2 at game minute ~17 of seed 1 at 02:42).
- 11-27 02:44 C on the Mac: enemy1-absent training since ~01:15 (run_enemy1.sh's exact args, w40-40k init, game set frozen to enemy1's 1338+96 = 1299/135, mps 2.5 steps/s, ~70 min; parity clean on 2 recordings, ABSENT=1 holds 105 vs 136 enemies late). Today's code also widens scal 8->10 and adds fresh judge heads, so a control enemy1-ctrl (same code, ABSENT=0) follows (approved). Both to be played vs the rules army on A's seeds.
- 11-27 03:20 hourly (the last run of this cron; it has ended): E1 5/6 games played, E2 6/6 played (building), E3 next on both lanes. C on the Mac (enemy1-absent then enemy1-ctrl, ~2 h). train.py --device from the Mac applied. 2 engines, C: 108 GB free, free commit 38 GB.
- 11-27 03:44 E1/E2 READ (page results/armynet/2026-11-27-model-vs-rules-E.md, E3 + C pending): live-cluster kill rate A 405 -> E1 361 -> E2 1,157 (rules sides 1,253 / 923 / 655); attack share there .17 -> .62 -> .65; orders per unit-minute there 42 -> 12 -> 15 (fight orders cut re-deciding, as 11-24; E2's forced decision restores the kill). After clearing "none" .635 -> .620 -> .602 (target well under .6: not yet). Results model A 1/5, E1 1/4/1 cap behind, E2 2/4 (two commander deaths at 9-10 min). E2 forced answers: deeper .46, same .40, back .12. C model (enemy1-absent, md5 ok) queued vs rules after E3 (runtime/armynet/queue_c.sh, set mvr-cabs, BARAI_ABSENT=1); enemy1-ctrl still training on the Mac.
- 11-27 04:38 C pair received (md5 ok): enemy1-absent (2c0819b4) and enemy1-ctrl (7d0c3114, same code and set, ABSENT=0). Held-out, each in its own mode: absent better on the force heads (f_act .1010 vs .1032, f_kind .2028 vs .2109, f_cell 4.887 vs 4.913, d_f_cell 322 vs 336), worse on value (.2955 vs .2847) and b_eco (.3584 vs .3459); ctrl below 11-23's enemy1 on f_cell (4.913 vs 4.897: code drift). Games queued: mvr-cabs (absent, serve ABSENT=1) after E3's builds, then mvr-cctl (ctrl, ABSENT=0). E3 6/6 played, building.
- 11-27 04:44 E DONE: results/armynet/2026-11-27-model-vs-rules-E.md (indexed). E3 (E2 + release to the AI's attack at a live cluster): 3-3 vs rules, kill 999 (rules 824), none after clearing .564, forced answers deeper .54. C-absent read on 6 games (seed 5's playback died at 6 s in a start clash, rebuilt alone): kill 1,326, none .359, their half .24 at 5-15 min, 2-4. Control (mvr-cctl) playing.
- 11-27 05:01 Fable's next: (3) added to objectives_army.py and read for all arms (E page section): lost per killed at a live cluster A 1.85, E1 2.29, E2 0.83, E3 0.71 (rules sides 0.46-1.00), C 1.16; "none after clearing" in E2/E3 is the model answering "stay" (.86/.90), ghosts .09/.04 (C .20: the fix forgets seen deaths, not unseen ones). G queued after the control set (runtime/armynet/queue_g.sh): G1 C model + E3 flags seeds 1-12, G0 A on seeds 7-12, G2 C model + E2 flags seeds 1-12; replays kept for every game (C: 105 GB free, ~0.25 GB a game). His online flags and model untouched.
- 11-27 05:14 C vs control read: results/armynet/2026-11-27-model-vs-rules-C.md. Fix trained in (code drift equal): live-cluster kill 1,326 vs 551, none after clearing .359 vs .773, lost per killed 1.16 vs 1.40, their half .24 vs .23; results 2-4 vs 1-4 (+1 ahead). G now running (queue_g.sh).
- 11-27 07:45 G DONE: results/armynet/2026-11-27-model-vs-rules-G.md (indexed), 30 games, all replays built (own-games/mvr-g0, -g1, -g2). Model side on the same 12 seeds: A-12 1-11 (0-6 on the new seeds 7-12), G1 C+E3 4-8, G2 C+E2 4-6 + 2 ahead at the cap. G1 trades best at a live cluster (kill 651, lost per killed 0.79 vs A 3.62); G2 stands furthest forward (their half .28/.36/.45 at 5-15/15-25/25+ min vs A .21/.21/.20). His online model and flags untouched; the recommendation is Fable's to take to him.
- 11-27 07:54 L DONE: results/armynet/2026-11-27-loss-census-G.md (indexed, no new games). 10 of 14 G losses lost the middle by 12 min and were out-expanded (middle extractors at 12: 13 vs 47 in losses, 33 vs 7 in wins); raids equal in wins and losses (~14 of ours, ~12 of theirs by 16); the model's front at the turn .28 vs theirs .36 (wins .32 vs .22); 1 out-expanded later, 1 army lost in one fight at 22-24, 2 commanders walked into a turret. H (head-to-head vs enemy1 as played: tools/armynet/model_vs_model.sh, runtime/armynet/queue_h.sh) running, G2's arm first.
- 11-27 08:20 Middle measures (objectives_army.py 'middle' lines: held middle extractors at 6/9/12, army near middle spots by holder, middle extractors/builders lost alone, raids into the middle matched): results/armynet/2026-11-27-middle-measures.md. Level at 6 min, decided by 9 (A 1.4 vs 3.1, G1 2.2 vs 3.2, G2 3.1 vs 1.3); army near our held middle spots rules .107-.110 vs A .064, G1 .072, G2 .109; raids matched rules .56-.74 vs model .36-.52; lost-alone does not separate. H running.
- 11-27 09:01 H first arm DONE: results/armynet/2026-11-27-head-to-head-H2.md (indexed; tools/armynet/model_vs_model.sh and trade_by_minute.py new). G2 (C + E2 flags) vs enemy1 as played: 5-3, caps 2 ahead / 2 behind; army trade even every bucket, buildings killed 69,694 vs 51,381 by 40 min, live-cluster kill 792 vs 437; middle level (3.7 vs 3.1 at 12). H1 (C + E3) now playing; then mvr-t (C + E2 + --force-threat vs rules, queue_t.sh).
- 11-27 09:31 G2 is the online default (his decision via the Fable session): tools/armynet/play_online.py now serves enemy1-absent/model-010000.pt (md5 2c0819b4) with --forces --learned --rally --arc --fbias -0.19 --cluster-fight --force-idle --absent (serve.py --absent = BARAI_ABSENT=1 for launches without an environment). One step back: play_online.py --previous (enemy1/model-010000.pt, --forces --learned --rally --arc --fbias -0.19). parity.py with absent on: 18/18 frames identical. Bridge cost (perf jobs, per served game-minute): A-12 read 437 ms write 97, G2 read 466 write 101 (A's own halves 529 / 374). Smoke game queued on lane armynet after H1 (runtime/armynet/smoke_g2.sh).
- 11-27 10:17 H second arm DONE: results/armynet/2026-11-27-head-to-head-H1.md (indexed). G1 (C + E3 flags) vs enemy1 as played: 7-1, caps 2 ahead / 2 behind (G2's arm 5-3); buildings killed 84,302 vs 47,777 by 40 min; lost per killed at a live cluster 0.90 vs 2.56; raids into the middle matched .76 vs .50. He plays G2 now: G1 has to beat G2 head-to-head to be kept; E3's release to the AI attack is his call (via Fable).
- 11-27 10:31 His G2 watch game (matches/watch-g2, lost at 29.5 min); his read: the army went in while outgunned and did not preserve itself. Measured (objectives_army.py 'odds' lines): results/armynet/2026-11-27-odds-in-contact.md. Army metal lost outgunned model .47 vs rules .23 in his game (A-12 .44 vs .24; G2 vs rules .33 vs .32); G2 goes toward the enemy while outgunned .23 vs rules .16 (.36 head-to-head vs enemy1 .17). V1 (--force-fire) tests whether the model holds an opinion on pulling back.
- 11-27 10:33 contract.py: new check 'army lost outgunned' (share of army metal lost where our army within 1,000 of the death was under 2/3 of theirs at the last snapshots; needs both sides' BARAI_ARMY, so our AI on both sides). Watch game model .56 vs rules .25; A s1-6 .46 vs .29; A s7-12 .30 vs .15; G2 vs rules .32 vs .25; H2 G2 .25 vs enemy1 .28. Agrees in direction with the replay measure (objectives_army 'odds').
- 11-27 10:44 At-cluster orders (objectives_army.py 'at-cluster' lines): results/armynet/2026-11-27-at-cluster-orders.md. The AI's fight logic attacks the most metal building in reach .46-.55 and the weakest .35-.45; the model (G2 vs rules) .16 / .14 (blind .25), nearest .66; model attacks units at a cluster more (.34 vs .14-.21), pulls out less (.15 vs .24). Labels for step 3: which building, when to leave. H3 (G1 vs G2 head-to-head) queued behind mvr-tb (runtime/armynet/queue_h3.sh), then the --previous smoke, V1, V2.
- 11-27 11:10 Fights in pieces (his read of the watch game via Fable): results/armynet/2026-11-27-fights-in-pieces.md. At first contact rules army has .53 of the fight's 70-s metal in place, top players .50, G2 .32 (brings .63 over the next minute vs .40); G2 loses .30 at local odds under 0.7 vs rules .21. contract.py: new 'army joins fights late'; FIXED the BARAI_ARMY parse (comma-separated units; it saw one unit per snapshot), which changes 'army idle on dead enemy ground' and 'army lost outgunned'. serve.py prints 'objectives-E2 by force' (size, place, new/old, answer) for (f); H3 carries it.
- 11-27 11:14 Item 3 moved to the front (Fable, his ask: learn the fight details from the AI's own fight logic). (1) inventory: results/armynet/2026-11-27-contact-inventory.md (tools/armynet/contact_inventory.py new). 91 rules side-games with orders, 952,645 armed-unit orders, 267,594 in contact (moves .81-.83, fights .13-.15, attacks .03-.05); 7,281 in-contact attacks on a building, 2,449 on a unit. Unit heads name only a cell; proposed a pointer head over the embedded enemy tokens (~66k params).
- 11-27 11:22 (2) in-contact dataset built: tools/armynet/contact_data.py (rules sides of every mvr set + rules-r2; examples at the rules side's order seconds; only armed units in contact are predictions via the 'revealed' loss mask; force/value/economy labels dropped; plain imitation weights; ttgt = attack target's enemy-token index). 85 games / 91 sides, seeds 6 and 12 of every set held out (14 games). train.py: --contact <sets> --contact-share s mixes in-contact batches (unit losses only, logged c_*). Smoke 200 steps from C: runs, c_act .28 c_kind .22 c_cell 3.17. Pointer head proposed, not built (waiting on the Fable session).
- 11-27 11:27 Lost fights / out-ranged deaths / computable corrections (item 8a): results/armynet/2026-11-27-lost-fights-outranged.md. Per game 2-3 outgunned entries with a larger force of ours within 2,000 (all columns); 16-25 out-ranged deaths (players 6), .09-.16 of model army losses, .21 for players. Arena (dev_arena.lua) spawns def rosters on mirrored lines at full health: not seedable from a recorded fight as is.
- 11-27 11:28 His air-off watch game (matches/_engine-watchair, launched by another session) opened at 11:26 while our H3 seed 3 (lane armynet, 11:22) was playing: stopped that engine; both queues wait while spring.exe runs (model_vs_* check before each game). H3 seed 3 was the one stopped (19.5 min, reason unknown in result.json): replay it before reading H3.
- 11-27 11:38 Pointer head built (model.py t_query over the embedded enemy tokens, index 0 none; train.py c_tgt loss on contact_data ttgt; collate pads ttgt). Labels at the AI's own order time: attacks resolve 37/37 on two games (vs 30/32 at the 10-s sample). Tags per token: c_air, c_outr (out-ranges the nearest armed enemy). Offline bar tool tools/armynet/contact_bar.py; C on 14 held-out rules games at a sparse sample: pull-out rules .43 vs model .24 (target picks too few at that sample; full run going). Training contact1 started: init C, BARAI_ABSENT=1, 3000 steps OneCycle, batch 32, --mirror --late --rounds, contact share 0.3 over all 14 rules sets (seeds 6/12 held out), pointer alone for the first 300 steps.
- 11-27 12:12 His observation (army group in a far corner off the line): issues/army-off-axis-corner.md + ISSUES.md line; contract 'army off the line' (contract.py; Seat.start from the commander's first snapshot). Page results/armynet/2026-11-27-army-off-axis.md (tools/armynet/army_where.py, mirror_serve_check.py new): Comet Catcher top-left G2 .01, 11-20 model .05, rules .00, players .04-.22; corner time mostly no order beside our buildings (.69); serve-time mirror .68/.70 vs training's .66/.72, no lean: follows the map. Per-order source logging proposed, not built.
- 11-27 12:37 Off-axis page updated with his two Comet Catcher watch games apart (air-off: model top-left .09, far off the line .105 vs rules .031, fighting over buildings there; air-on .01) and his six hosted team games per seat (AI seats far off the line .18 vs humans .15, beside our own buildings/spots); not refuted, tied to join/late arrival. serve.py: order-source logging (SRC_LOG, 'objectives-S' per minute: orders by source roll/unit/force/idle/threat/fire/seen/rally and turned-frame aimed cell), on when the bridge folder is under matches/, off in his installs; army_where.py --per-team.
- 11-27 13:41 His online game started 13:40:50 (he runs play_online.py): stopped our two headless engines (16200, 42036); queues wait on it; training control + offline bar at idle priority. Stopped games: V1 seed 11 and V2 seed 2 (replay both before reading V1 / V2).
- 11-27 13:56 contact1 offline page: results/armynet/2026-11-27-contact1-offline.md. Pointer picks most metal .087 / weakest .171 (rules .126 / .227; C .012 / .010); pull-out probability C .48, contact1 .45, rules .43; player cost is the fine-tune's own (control contact1-ctrl drifts alike), in-contact data adds act log-loss .343 vs .316. serve.py --pointer built; netrun passes tgt (torch only). Old queues stopped while waiting on his game; runtime/armynet/queue_u.sh queued: U1 seed 1 alone, then waits on runtime/armynet/u1-go (bridge cost check), U1 rest, H3 s3 replay, V1 s11-12 (mvr-v1b), V2 s2-12 (mvr-v2b), builds of V1 7-10 and V2 s1, rules-r3.
