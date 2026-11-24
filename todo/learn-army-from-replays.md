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

14:15 rally arms, 6 seeds each, paired vs unit (same checkpoint and seeds as the four arms above):
still share 0.15 rally / 0.15 rallylayer (learned 0.45, unit 0.17); still at home 0.03 (learned 0.21). Rally vs
unit: own economy lost by 20 min -660 (learned was +2,545), army killed +1,674 (4/6), army ratio at 8 min 0.95 vs
0.79 (4/6), centre at 12 min 0.28 vs 0.22 (4/6), but army ratio at 16 min 0.58 vs 0.90 and centre16 0.19 vs 0.24.
Results: rally 1 win 1 loss 4 draws (first model-side win in these tests); rallylayer 0-3-3 (army lost halved,
their economy killed -633, 0/6); unit, learned, learnlayer 0-0-6; hand forces 0-1-5. Live click p for forces of 4+
averages 0.134 a step with the bias (players 0.057-0.084 off replays), so big forces are not under-clicked. Keep
rally + fbias; layering on top measured worse. Still short: the late push (centre16, extractors reached 9.8 vs 12.2).

14:21 check. force-heads-b at step 51,000 of 60,000 (~4.8 steps/s with 3 test engines), no traceback; held-out
force heads flat since ~4,000 (cell 384 vs 798 stay, goal 932 vs 1,087, click 4.5% vs 6.2% before the live bias).
Free commit 26.6 GB, recorder up (214 recorded), his game off. Changed this hour: serve.py --rally/--fbias/box-select
and the per-minute forces line (measured above: still share 0.45 -> 0.15); paired_summary.py takes arms from the log.
Input parity untouched (rally orders enter the tracker as any order does, as players' clicks do in training).
Confirm run: rally vs unit seeds 17-22 -> runtime/armynet/paired-rally-b.log. Biggest gap: the late push (army ratio
and centre at 16 min).

14:40 his 11-20: a time-limit game is a soft W or soft L by who was doing better, never "draw". game_report.py now
writes "soft W / even / soft L (A's share x)": A's mean share of end income, army and extractors and of metal killed,
> 0.55 / < 0.45. Re-scored every game today: unit W0 even2 softL7 L1 (share 0.36); hand forces softL5 L1 (0.30);
learned softL6 (0.31); learnlayer softL6 (0.30); rally W1 even1 softL6 L1 (0.35); rallylayer softL3 L3 (0.32). Every
arm ends with about a third of the game: the model side loses nearly every game to our AI's own army control.

15:05 radar (his 11-20: "we suck at making radar"; "radar should be up before the commander leaves the home base").
Measured: side A's first radar median minute 14 (B 5-9) across all arms (radar_builds.py); radar gates pass on both
sides (defgates radar.nogap 0/37 by minute 5) -- the want loses on price: gNew 0.3-0.9 in the first 5 minutes
(gOld 2-3). Fight census: side A loses ~16,000 of buildings/builders/defence a game in home fights vs B's ~5,400.
Change (protect_senseprice.as, deployed to lane armynet): while no radar watches home, a home mast's gain is at least
gAssetsM / fill + surprise. First try (surprise alone) did nothing (surprise ~0 before armies exist: A first mast
still minute 14.2, seed 17). Second: seed 17 A first mast 4.9 (B 4.4). Running seeds 17-22 -> paired-radar-c.log;
pairs with paired-rally-b.log's rally games (same seeds, old AI). Measure: first-mast minute, home-fight losses, share.

15:30 check. force-heads-b finished (step 60,000, no traceback; held-out flat to the end, final click rate 5.4% vs
players' 6.2%); GPU left idle on purpose (his: no more steps). Free commit 57.7 GB, recorder up (237 recorded), his
game off, no stray engines. Radar result (seeds 17-22, same games, old vs new home price): A first mast 15.3 -> 6.0
min, B 8.8 -> 4.1 (both sides run the AI, so A-vs-B share cannot show it: 0.44 -> 0.39, noise); home losses not
lower. Kept on the lane only; needs a test against a different opponent before it stays.
Home-fight timing (home_response.py, every lost fight on A's half, all arms, ~800 fights): their force (~1,000-1,300
metal) is there a few seconds before the first death; at that moment A has 150-520 metal within 900 but 7,000-9,500
within 2,500 -- seven times their force a short walk away -- and in a third of the fights A never matches them
locally. Same for every arm, unit included. Biggest gap: the army does not converge on a raid in its own base. Next:
players' response to raids near their buildings in replays (time to order nearby units at it) against ours live.

16:20 check. Health: training idle (done), free commit 57.6 GB, recorder up (277 recorded), his game off, no engines.
Home raids, players vs ours, measured the same way (scratchpad raid_answer.py: every 5 s, >=500 enemy army metal
within 900 of a point inside a home, 0.35 of the start distance; mobile army only). 150 replay duels, 680 raids:
raid 1,074 metal; defender within 900 447, within 2,500 1,976; never matched in 90 s 25%, else 15 s; defender's local
share 0.47 at 30 s. Ours, rally arm A (12 games, 138 raids): raid 2,194; within 900 529, within 2,500 10,331 (40% of
that is the commanders and units our AI keeps); never matched 28%, else 10 s; share 0.35 at 30 s, 0.57 at 60 s. On par
with players. learned / rallylayer arms worse (never 46%, share 0.17 / 0.02 at 30 s). The head at players' raids
(raid_head.py, 80 replays, force-heads-b 20k): click per step for forces within 900 0.065 vs players 0.053, 900-2,500
0.025 vs 0.022; place mass at the raid 0.22 vs players' 12% of clicks there. Training copied the players' answer; the
earlier "seven times their force a short walk away" was mostly commanders, kept units and the rest of a home-bound
army. What differs is the opponent: our rules side raids A's home 11 times a game with 2x the players' raid size (A
raids B 3 times a game, players ~2 a side), and B answers with a held home pool (share 0.84 at 60 s). Not a training
gap; no change made.

16:50 plan (his: more steps will not fix it; link actions together, more interconnection, to discover value without
labels). Today each click is learned alone: imitation, weighted mildly by its own rating (f_w = exp(0.5 * score),
0.37-2.7) plus a 60-s hindsight goal. Plan, in order, each measured before the next:
1. A value head: from the state, predict our side's trade and eco share at 10 s, 60 s, 3 min, 10 min (ground truth
   only as labels). Measure: held-out error against a constant.
2. Chain credit: a click's advantage = value after it minus value before, carried back along the same force's chain of
   clicks and the clicks of other forces within the window (TD-lambda), so a set-up move gets the credit for the
   payoff two clicks later. Measure: does the advantage rank players' clicks the way their trade 60 s on does.
3. Advantage-weighted imitation in place of f_w (exp(A / beta)). Measure: paired games vs the current head.
4. Inputs that connect the model's own actions: each force's last click and the recent orders of every force.
Opponent batch running meanwhile: paired-opp-d.log, seeds 23-28, model vs our rules army, against BARb hard and
WRDistilled 0.4 (watch.py --nomodel is the rules control).

17:20 his "factory waypoints might be a widget thing", "keep going, enhance the model". Found: factories do get
rally orders in the replays (10 games: 1,546 move/fight orders to factories), but a new unit takes them inside the
engine with no order of its own, so the dataset had none: the players never sent a new unit anywhere. In the
Fallendell sample most new units step out and stand (first 20 s: exit move, idle, later a click), rallies on 2 of
the factories. replay_dataset.py now (a) adds one decision per new army unit toward the last waypoint of its
factory's rally (factory_rallies), (b) parses order lines on single spaces (an order with no modifier keys lost its
target before), (c) writes `sides`, each side's lost / standing / army metal and map share every 10 s.
data.py: value_labels (per VALUE_H 10 s / 60 s / 3 min / 10 min: trade over both sides' standing metal, map-share
change; then the result), model.py v_head on the pooled units + map, train.py value_loss + held-out v_r2_* (share of
variance explained; 0 = the mean) and v_result_acc vs the base rate; --fresh-prefix picks the heads that learn alone.
Smoke: 40 steps on one game run end to end. Full rebuild running (runtime/armynet/rebuild-rally.log, 6 jobs).
Next: fine-tune from force-heads-b 20k (v_ fresh 2,000 steps, 12,000 total); measure v_r2 held-out, refit fbias
(players' click rate changes with the rallies), then live arms with and without the hand rally.

17:30 check. Health: his game off, free commit 35.7 GB (3 batch engines + rebuild), recorder up (316 recorded), no
training running. Opponent batch (paired-opp-d.log): seed 23 done for 3 of 4 arms, ~30 min a round of 3 at 4x with
the rebuild sharing the CPU, so ~3.5 h for all 24. Rebuild was 139/1,628 in 35 min (~6.5 h): profiled, 1/3 of a
build was where() scanning every sample of a unit for the nearest frame; now a bisect (earlier sample on a tie, as
before). One 10-frame game 15.7 s -> 3.9 s, every array byte-identical (scratchpad npz_same.py). Rebuild restarted
(--force, 6 jobs). Self-review: serve processes launched after the model/data edits load the checkpoint with a fresh
v_head (unused live, NaN labels in Game.live), 0 tracebacks in 4 newest serve logs; the policy path is unchanged.

18:25 WHY THE GROUP WENT BOTTOM-RIGHT AND SAT (his watch game vs WRDistilled 0.4, seed 31, Cortex; his: "record why
... get to the bottom of it, not guess"). Demo re-recorded (scratchpad watchrec/g, no desync), dataset built, the
live checkpoint (force-heads-b 20k, bias 0.39) run on every 10 s of the stretch (scratchpad idle_trace.py,
model_view.py). Facts:
1. Min 5.8: one move order sends 7 units (corak x4, corthud x3) to 7099,4368, 108 from a metal spot in the
   bottom-right cluster (6 spots within 1,100). Empty then: no enemy unit within 1,500 at min 6.
2. They stand 132-158 s (min 6.0-8.6). Our economy never builds there: 0 of our buildings within 1,000 all stretch.
3. From min 7.5 WRDistilled builds there: corcv x2, cormex at 763 then 599, corllt at 1,109. Sight bits for our
   ally on every one of those samples: 0. Our units' sight does not reach 600; no radar of ours anywhere (first mast
   never built that game). The model's view had 0 enemy cells within 1,500 at every step: correct, it was blind.
4. The model's outputs every 10 s: order chance 0.0007-0.0023 per step (2-7% per 10 s); kind move 0.99; place:
   25% of the mass within 400 of where they stand and the single best cell their own spot. Re-deciding more often
   would have re-ordered "stay": the cadence fix I proposed at 18:10 was a guess, dropped.
Why: (a) the army claimed an expansion the economy never took, so it guarded nothing; (b) blind, it could not see
the enemy take it; (c) nothing in training scores a position: an order whose units then stand 2.6 min trading
nothing, guarding nothing and seeing nothing is rated neutral (dec_score 0, weight 1), the same as a good one.
Radar: home mast now offered at home ahead of the gap search, the commander counted in its stake (deployed to the
lane): seed 31 vs WRD, first mast min 2.25 (was never); 15 offers in 7 min. One game; needs the paired check.
Opponent batch (paired-opp-d, 6 seeds each): vs BARb model 0.50 (2 soft W, 2 even, 1 soft L, 1 L) vs rules 0.53;
vs WRDistilled model 0.31 (2 soft L, 4 L) vs rules 0.55 (2 soft W, 1 even, 3 L).

18:50 check (health: his game off, free 53 GB, recorder up 334, opponent batch done, nothing training).
Digging further into the parked group (correcting 18:25):
- 18:25's "0.1% per step" came from a replay build without our side's orders (replay_dataset drops AI teams; the
  task and since-last-order columns were blank). BARAI_ALL_TEAMS=1 now keeps them for our own games. Re-run:
  walking out p 3-5% per step; parked from min 6.2 0.16-0.6% per step; place still the own spot. Blind confirmed.
- Players in the same state (parked_rate.py, 60 replays: standing, no enemy seen within 1,500, nothing of ours
  within 1,000): click per step 0.021 at 0-30 s since the last order, 0.008 at 30-90 s, 0.000 past 90 s (n 311);
  the head 0.022 / 0.006 / 0.002. The head copies players there: players leave such a guard alone too.
- Worthless rule (Game.worthless_groups: 30-90 s after the order standing, no new order, nothing of ours within
  1,000, no enemy seen within 1,500, own trade 0 at 60 s and 3 min) fires on 13 of 47,842 player order groups
  (20 replays): a penalty on players' worthless clicks would change nothing. Kept as a measure, not wired in.
- How training rates that exact order (order_rating.py): weight 1.13, above this side's mean, from area@600s +3,082
  and eco_near@600s +2,620: our later raid killed their extractors there around min 9-15, and the 10-minute
  area measures credit any order aimed near that spot, though these units traded 0 at 5/15/60 s.
- Where: 7,000,4,300 is their half (their start 6,512,624; ours 1,289,5,413). Our extractors reached x 4,208 by
  min 9.4; our economy was never going there.
So the cause: the head learned "park a guard at an expansion" from players, whose own builders follow; ours do not,
it is blind there, and the rating credits the parking for kills other units made later. Next: area / eco_near
credit only for an order whose units took part (own trade nonzero at that horizon, or the units within the area when
the kills land), measured by re-rating this order and the share of player orders whose weight moves.

19:05 Credit by span and chain (his: "webbing actions together"; the parked order was rated 1.13 for a later raid).
replay_dataset.py: per decision `span_s` (until half its units have a newer order) and `outcome_span` (own, area,
near, eco_near over the span only). data.py: area / near / eco_near ratings read the span outcome; then _chain: an
order group's score + exp(-gap to the next order of its task / 60 s) x the discounted mean of the later orders'
scores (a mean: fights re-order a task several times a second). First try (zero area credit when own trade 0 over
the horizon) left the order at 1.11: its units traded later, under later orders; reverted. The parked order (watch
game, BARAI_ALL_TEAMS=1 rebuild): span 3.4 s, span measures 0, score 0.00 -> weight 1.00 (was 1.13). Neutral, not
penalized: players park like that in 0.03% of orders, so a penalty needs our own games in training.
Workhorse (MacBook, ChristosMBP2025) asked by henry_message to build our CircuitAI fork for macOS arm64 and run
headless games; brief in henry-outbox/workhorse/. Waiting on its answer.
Next: measure how many player order weights the span + chain change (and the held-out rating check), then an idle
cost for our own games (army metal x seconds standing with no trade, nothing of ours to guard, no enemy seen).

19:30 Idle cost (his "penalize such a position hard"). replay_dataset idle_cost -> `idle_m` per decision: over the
order's span (<= 3 min), each 10 s the group stands (centre moved < 100), trades 0, has nothing of ours within 1,000
and sees no enemy within 1,500 costs its metal x 10 s (metal-minutes). Watch game: the parking order (min 5.85,
span 165 s) 1,184 metal-min, our worst order of the game; our side 747 order groups all game vs WRDistilled 21,613.
Fallendell (players): ~2% of order groups carry any, the worst 144. data.py: score -= min(idle minutes, 3) before
the chain; force label f_neg = share of the force's decisions scored under -1; train.py f_unlike = -log(1 - p(place))
on those clicks. The parking order now -1.19 (weight 0.55, place pushed down); was +0.25 (1.13). Smoke: 30 steps
train cleanly (eval needs a human-side game). Full rebuild with span + idle running (rebuild-span.log).
Open: training takes examples only from human sides; our own games need our side's examples for this to bite.

19:55 Rebuild with span + idle done (1,265 games, 0 failed). His game on: no training, no engines (trainer pauses
anyway); CPU checks only. Rating shift on players (rating_shift.py, 30 games, 39,104 order groups): weight moves >0.1
for 37% (mostly the chain), old/new score correlation 0.55, under -1 0.08% -> 0.26%, idle cost on 1.0% of groups.
Does the rating follow player strength (rating_skill.py, 120 games, 237 players, skill not an input; bootstrap 90%):
old 0.123 (0.03..0.23); span 0.123; idle 0.125; chain 0.110; span+idle 0.127; all three 0.165 (0.06..0.27), minus
old +0.041 (-0.05..+0.13). No part separable from the old rating on this instrument (it is weak: 0.12). Kept on the
logic (the parked order was credited for others' raid) with the game test to decide; data.RATING_PARTS switches them.

20:00 Workhorse (MacBook M4 Pro, 14 cores, 48 GB, 282 GB free) passes steps 1-4: our fork + hands-off patch built
for arm64 and deployed as Apexarmynet:lane-armynet; BAR.sdd from byar:test with our gadgets; --nomodel smoke 8 min
in 58 s (0 AngelScript errors, BARAI lines present); model smoke (serve on CPU) 'minute N forces' lines, no
Traceback, 'apex: handsoff' x7. Three Mac fixes in the fork (const SPullMtoS operators = upstream f4a6ca3; arm64
.S stub in CMakeLists; AngelScript arm64 bug: a stack-spilled reference sized as its pointee, truncating a 9th
pointer argument, TerritoryRay segfault at frame 18) and a tools port (bar_env, unitsync, lane, deploy_ai,
run_match, sync_game, train --device), all uncommitted in its worktree; report fetched to henry-inbox/workhorse/.
Its smoke ran on "Comet Catcher Remake" (not 1.8): the 1.8 map sent in 5 pieces (henry-outbox/workhorse/map).
Step 5 (train speed, MPS vs CPU) on 20 sample npz (npz-sample.txt) with the 19:55 code (armynet-code-1955.tgz).
The full set (1,224 of 1,265 npz under 10 MB, 2.6 GB) is too many fetches: asking him for a share.

20:20 check. His game on (GPU 91% his): no training, no engines here; recorder up (353 recorded), free 52.1 GB, one
engine (the recorder's). Self-review: parity.py on a rebuilt game (Mariposa, 6 moments): grid, tokens and forces
identical train vs live, act max diff 0, best cell 100%: the evening's data changes (value labels, f_neg, span /
idle / chain rating, factory rallies) touch labels only. Waiting on Workhorse's MPS benchmark and his answer on a
share for the full set; fine-tune and the paired games (new radar + new data) queued for when the PC or the Mac is
free.

20:30 He is off the PC ("you can use this one too"). Started: (1) fine-tune runtime/armynet/value-rally-20261120
from force-heads-b 20k on the rebuilt set (factory rallies, sides/value labels, span + idle + chain rating, f_unlike):
v_ alone 2,000 steps, 12,000 total, eval every 2,000 (v_r2_*, f_rate, place errors), first 200 steps 47 s, value
loss 0.334, f_unlike 0.000 while heads are frozen. Measure: held-out place error and click rate against
force-heads-b's (no worse), v_r2 above 0, then paired games. (2) paired-opp-e.log: the opponent batch again, seeds
23-28, 4 arms, with the home radar change; pairs with paired-opp-d (old radar). Measure: first-radar minute, end
share and commander deaths per arm. Workhorse: Mac batch-ready on the 1.8 map; parallel count and reserve asked of
him; MPS benchmark pending.
20:40 The first paired-opp-e launch failed every game at once: "'Comet Catcher' is ambiguous" (a second map,
comet_catcher_remake.sd7, was installed in his maps at 18:20 for the Mac replay check). Two batch loops were
running (a backgrounded `&` launch survived its shell): both killed, their log kept as paired-opp-e-mapfail.log.
watch.py's default map is now the exact "Comet Catcher Remake 1.8"; every earlier game played that (checked:
radar-home-check 1-2 and his watch game). Relaunched: 3 games running, training at step 1,200 (4.6 steps/s with them).

21:20 check. Health: his game off, free 29.1 GB (training + 3 games), 4 engines (3 batch + recorder), recorder 357,
no Traceback. Fine-tune at step 11,400 of 12,000 (3,067 s; ~3.7 steps/s beside 3 games, 6 alone). paired-opp-e
15 of 24 games. Value head (held-out, step 10,000): trades explain nothing (v_r2_trade60 -0.001, 180 -0.014, 600
-0.015; trade10 -0.44, worse than the mean), map share barely (share180 0.030), result 0.615 vs base 0.522. So it
does not yet give a usable baseline for crediting clicks; the chain credit stays on realized outcomes. Policy evals
not comparable with force-heads-b's (labels changed: players' force click rate 0.062 -> 0.053 with the rally orders
and rebuilt groups); force-heads-b to be evaluated on the new set (--eval-only) when the run ends.

21:45 value-rally-20261120 done (12,000 steps, no Traceback). Same held-out set, force-heads-b 20k vs new 12k:
force place error 384 -> 362, 60-s goal 1,065 -> 1,045, retreat recall 0.26 -> 0.38, deep raids 0.316 -> 0.334
(players 0.327), far spots 0.413 -> 0.431 (0.432), unit act logloss 0.403 -> 0.402, force click rate 0.037 -> 0.036
(players 0.053); refit bias 0.371 (was 0.39). On the parked group (watch game, min 6.3-8.3): place mass at its own
spot 0.17-0.25 -> 0.09-0.14, but its best cell is still that spot and its click chance per step 0.0012-0.0050: it
would still sit. As expected: players almost never park so, so their data cannot penalize it.
Own games into training: headless test games kept no replay (run_match RecordDemo=0 unless --watch/--replay);
watch.py --headless now passes --replay (games from 21:45 on record one). data._pick_examples takes every side of a
game under an "own-games" folder (built with BARAI_ALL_TEAMS=1). Next: record the radar batch's replays, build
own-games datasets, fine-tune on players + own games, measure the parked-group moments and paired games.

22:15 Radar batch (paired-opp-e, home radar priced ahead of the gap search, commander in its stake) vs paired-opp-d
(old radar), same seeds 23-28, 4 arms (scratchpad paired_score.py; score = 1 won, 0 lost, else end share):
first radar of ours, median: mBARb 8.4 -> 2.9, rBARb 4.7 -> 2.3, mWRD 14.2 -> 2.8, rWRD 6.9 -> 3.0 min (theirs
2.7-4.4). Commander deaths (L) 8 -> 3 (rWRD 3 -> 0, mWRD 4 -> 3, mBARb 1 -> 0). Score per seed: mWRD +0.035 (up 2
down 1), rBARb -0.057 (2/4), mBARb +0.063 (3/3), rWRD +0.107 (3/3): 10 up, 11 down, no clear share change. The
time-limit-only mean (shares.py) read lower because losses became soft losses. Radars standing at 16 not higher
(rBARb A 4.7 -> 1.7): the early mast does not add later coverage; worth a look. Kept on the lane, not released.
22:25 Batch f (new value-rally 12k at bias 0.37 vs force-heads-b 20k at 0.39, both with the rally rule, vs BARb hard
and WRDistilled 0.4): seeds 29-31 on the PC (paired-model-f.log), 32-34 sent to the Mac (batch-f.txt). Every game
records its replay, for the own-games training set. paired_arms.sh: an arm's --model now wins (flags first).
Measure: paired score per seed (paired_score.py), commander deaths, and the parked-group check on the new model's
games (idle_m per order from the rebuilt replays).
22:55 Mac batch f, BARb arms, seeds 32-34 (6 games, all to time, ~312 s wall each at speed 4, 3 at once, clean):
old 0.44 / 0.44 / 0.35, new 0.33 / 0.46 / 0.32 (mean -0.04). Fetched report.md + .sdfz into matches-mac/batch-f/
(paired-model-f.local.log points there). WRDistilled for the Mac: its own Rust build (within-reason 7e10ec2,
bots/distilled, run/bot_payload.sh); Workhorse told. PC half 3 of 12 done.
23:20 He took the PC for an online game: batch f stopped (seed 29 all 4, seed 30 oBARb/nBARb done here); the loop's
subshells kept launching games after TaskStop and kill (twice), so the watch.py trees were force-stopped from
PowerShell; 0 engines, 0 game processes. The replay recorder (public_replays follow) does NOT pause for his game:
stopped too; restart after his game: `python -u tools/public_replays.py follow --workers 1 >> G:/bar-ai-archive/
public-replays/follow.log 2>&1`. The Mac runs the rest: WRD 32-34, seed 30 WRD, seed 31 all four.

00:20 (11-21) check. He has the PC (online game said; not detected this minute): 0 engines, recorder off, nothing
training here; free 59.3 GB. Workhorse working on batch f's remaining 12 games (WRD 32-34, seed 30 WRD, seed 31
all four). No code changed this hour. Next when results land: paired_score over all 6 seeds x 4 arms; build the
own-games set from the batch's replays (Mac 6 fetched, 5 from paired-opp-e, the watch game) and fine-tune on
players + own games.

00:45 Batch f, 9 pairs scored (PC seeds 29 + 30 BARb, Mac 32-34; split_arms.py + paired_score.py): new
value-rally 12k vs force-heads-b 20k. BARb 5 seeds: old 0.46 0.46 0.44 0.44 0.35, new 0.38 0.46 0.33 0.46 0.32,
mean -0.040 (1 up, 3 down). WRDistilled 4 seeds: old 0.36 L 0.31 0.26, new L L 0.45 L, mean -0.120, commander deaths
1 -> 3. The fine-tune is not better and probably worse: NOT deployed (no-change-is-benign); force-heads-b stays the
live model. Its held-out gains (place 384 -> 362, retreats 0.26 -> 0.38) did not reach the games. Mac finishing
seed 30 WRD and 31.
01:05 Batch f complete, 6 seeds x 4 arms (PC 29 + 30 BARb, Mac the rest, 18 games, all clean). New vs old:
BARb -0.008 (2 up, 3 down); WRDistilled +0.037 (3 up, 2 down); commander deaths vs WRD 3 of 6 each. Corrects 00:45's
"probably worse": no difference. Still not deployed (no measured gain); force-heads-b stays live.

01:20 check. His game on (detected): PC idle, 0 engines, recorder off, free 47.5 GB. Batch f final (01:05): new
model level with the old one, not deployed. Mac asked to build the own-games set: batch f's 18 replays ->
replay_orders.py one -> BARAI_ALL_TEAMS=1 replay_dataset.py -> npz (idle_m, span_s, outcome_span) for fetching.
No code changed here this hour.

01:45 Own-games set: Mac recorded and built batch f's 18 replays (BARAI_ALL_TEAMS=1, idle_m/span_s/outcome_span,
all desync.txt empty), fetched to runtime/armynet/own-games/ (0.9-10 MB each). Our side there: 0.5-2% of order
groups idle-costed, the worst 1,624 metal-min. But f_neg marks only 0.33% of our clicked forces: an idle stretch is
one bad click then minutes of no-click steps, which self-imitation would copy as right. data._wake_idle (own games
only): a non-clicked force whose units' latest order is idle-costed and 30 s+ into its span is labelled clicked, for
the click head only (f_cell -1; train.py's place/kind/shape mask now needs f_cell >= 0). Our side in own games:
4,126 force-steps sampled, 299 real clicks, 108 woken (2.6%); opponents 0. train.py --own <root> --own-share
(default 0.25): own games drawn at that share. Parity unchanged (Mariposa, 6 moments identical). The watch game
moved to runtime/armynet/own-holdout/ (the parked-group check must not train on it).
Next when the PC is free: fine-tune from force-heads-b 20k with --own runtime/armynet/own-games --own-share 0.25;
measure the parked moments (p/step and hold), held-out player evals (no worse), then a paired batch on the Mac.

02:20 check. His game on: PC idle (0 engines, recorder off, free 45.1 GB). The own-games fine-tune waits for the PC:
the Mac has only 20 player npz, too narrow to fine-tune on beside 18 own games (the full set still needs a share
or a drive). No code changed this hour.

02:55 His "that workhorse can work on hard training and learning to get this AI working better". The Mac is now
the training machine. Player set packed for fetching: G:/bar-ai-archive/workhorse-shards/ (357 files under 10 MB:
275 tars + 82 parts of 36 big tars; 1,265 games, 2.69 GB; FETCH.txt, INDEX.txt). Code armynet-code-0030.tgz
(data/model/train/watch/paired_arms/replay_dataset + tools-0030 analysis scripts); the held-out watch game in 2 parts.
Brief: henry-outbox/workhorse/TRAINING.md (own-games fine-tune from force-heads-b 20k at --own-share 0.25, 8,000
steps on MPS; kept only if held-out players no worse, the parked group gets an order, and paired games on seeds
41+ vs BARb and WRDistilled beat the live model; then loop each batch's replays into own-games). The PC session
decides what goes live.

03:10 Workhorse found a threshold bug: dec_score is stored remapped (raw < -1 -> raw + 1, else max(raw, 0)), so
f_neg's `dec_score < -1` meant raw < -2 (own games: 144 of 547,714 decisions vs 5,393 under raw -1). Fixed:
f_neg = mean(dec_score < 0) (data.py; the only such test). Also corrects 19:30/19:55's "-1.19" and "under -1"
counts: those were stored values (raw -2.19; raw under -2). own-a (the bug) runs as the control; own-b with the fix
as its own arm, both through the three checks.
03:40 Mac own-a (players + 18 own games at 0.25, from force-heads-b 20k, 8,000 steps, 1,064 s on MPS; f_neg still
the old threshold): gate 1 (118 held-out players) PASS: place error 389 -> 385, force click rate 0.038 -> 0.054
(players 0.056), act logloss 0.443 -> 0.422, retreat recall 0.30 -> 0.33, goal 1,101 -> 1,056, deep 0.327 -> 0.315
(players 0.335). Gate 2 FAIL: the parked group's click chance 0.0015-0.0026 per step from min 6.8 (live
0.0018-0.0019), best cell still its own spot. Not taken to games. own-b (f_neg below raw -1) running; if it fails
gate 2 too: own-c, a heavier wake label (5x in f_act, which f_w does not reach) or own share 0.5, one at a time.

03:20 (local 00:20) check. PC: his game not detected this minute, but he has not said he is done: kept idle (0
engines, recorder off, free 41.2 GB). The Mac is the training machine: own-a done (gate 2 fail), own-b (f_neg
fixed) running. The only code change this hour: f_neg's threshold (a label; inputs untouched, parity unaffected).
04:00 Mac own-b (f_neg fixed: our side 19 of 288 clicked forces flagged, woken idle 98 of 4,039): gate 1 place 384,
click rate 0.045 (players 0.056), act logloss 0.455 (live 0.443: 0.012 worse), retreat 0.36, deep 0.339 (0.335);
gate 2 FAIL: parked click chance 0.0020-0.0032 per step (live 0.0018-0.0019), best cell still its own spot.
Workhorse's reading, agreed: f_unlike on a 0.02-0.03 cell has a gradient of about p, while the copy term still
pulls there. Next: own-c (own share 0.5, running); own-d = own-b + f_w 0 for f_neg orders + woken idle steps 5x
in the f_act loss; meanwhile the Mac grows own-games with the live model vs BARb / WRD on seeds 41-46.
04:30 Mac own-c (own share 0.5): gate 1 PASS level (place 384, click rate 0.056 = players', act logloss +0.001,
retreat 0.34, deep 0.337 vs 0.335); gate 2 half: the parked group's click chance 3-5x (0.0056-0.0158 per step, 16-25%
per 10 s), but its best cell still its own spot (0.06-0.09) and 26-40% of its place mass within 400: an order would
keep it there. Gate 3 as a measurement, not a release: batch g, seeds 41-46, live (bias 0.39) vs own-c (bias -0.129,
fitted on the rebuilt data; the live model's fit there is 0.298 vs its played 0.39, a data-version difference
most likely), vs BARb and WRD; its 24 replays grow own-games. Place is the bottleneck now: the click head can be
taught "act" but nothing teaches where. Next: own-d (f_w 0 for f_neg, wake 5x), then a place teacher for parked
moments if needed.

04:20 (local 01:20) check. PC idle (0 engines, recorder off, free 45.6 GB; he has not said he is done). Mac: batch g
(live vs own-c, seeds 41-46) running; own-d queued behind it. New here, for the place bottleneck: a hindsight place
teacher, BARAI_WAKE_PLACE=1 (data._needed_at; own games only, on woken idle steps): where our side was in the fight
over the next 60 s (hits our units/buildings took or dealt, at the victim's spot, within 4,000 of the force; the
heaviest 1,000-elmo square's weighted centre, at least 200), as a fight order (kind 2) with a place. Own games: 83
of 98 woken steps get a place. The parked group (teacher_view.py, holdout): min 6.3-7.3 none (no fight in reach),
min 7.8 -> 7120,3776 (597 away), 8.3 -> 7274,3614 (782): the enemy expansion built beside it. Labels only (parity
untouched). Sent to the Mac as its own arm after own-d.

04:55 Mac batch g (gate 3; live at 0.39 vs own-c at -0.129, seeds 41-46): own-c FAILS. BARb -0.048 (3 up, 3 down),
WRD -0.058 (2 up, 2 down); outright losses live 2, own-c 4 (incl. BARb 41 at 10.3 min). A model that clicks more is
no better and loses the commander more: asked the Mac to trace nBARb-41's commander death (army near it in the 60 s
before, the model's last orders there). own-d then own-e train next on own-games + batch g's 24.
05:20 own-c's BARb-41 commander death (Mac trace): our commander chased raiders east alone (D-gunning, 4 corraid
killed), our metal within 1,500 0-43 for a minute against theirs 360 -> 4,080 (26 raiders); own-c's 2-3x more orders
sent the army west (targets ~3,400 from it), swinging back only in the last 20 s. Live arm's seed 41: 1,128-1,950 of
ours near the commander. Does the head react to a commander under fire (com_guard.py, 80 replays, live model)?
Players aim 23% of nearby forces' clicks within 700 of their commander when it was hit in the last 10 s (4% when
not); the head puts 0.14 of its place mass there (0.21 at the moments players clicked; 0.05 when not hit). It reacts,
somewhat less than players; the commander is seen only as metal on the builders layer (no health). Not the main gap.
The gap is our commander roaming alone and the army not covering it.
05:40 Mac: commander deaths in batch g's other 5 losses (com-losses.txt). A lone commander (ours within 1,500 under
~200, army targets 2,500+ away) in 1 of 4 own-c losses (BARb 41) and 1 of 2 live losses (WRD 44): with both models,
so not the higher click rate. The other 4 are lost wars against WRDistilled: ours 3-4k vs theirs 12-13k within
1,500 (nWRD-43); our whole army 150-600 metal vs 21-25k (nWRD-44, 46); ours 0.75-5.1k vs 6.5-9k (oWRD-42).
WRDistilled out-builds us 3-5x in army by minutes 15-19. Two separate problems for the PC side: (1) the commander
roams off alone (the commander module, not the model): its own look, ai-commander; (2) against WRDistilled the army
is out-produced, an economy/production gap the army model cannot close.

05:20 (local 02:20) check. PC idle (0 engines, recorder off, free 48.6 GB). Mac: own-d training, own-e next.
Production gap vs WRDistilled (where_lost.py on paired-opp-e, 6 games an arm; A ours, B theirs):
  min 8:  income ours 54-57 vs 68-76; extractors 16-17 vs 22; army 1.1-1.2k vs 2.3k
  min 12: income 74-110 vs 119-130; extractors 28-31 vs 39-40; army 1.6-2.5k vs 9.6-12.5k
  min 16: income 94-105 vs 149-194; extractors 35-41 vs 55-58; army 5.1-5.6k vs 25-33k
  economy lost to them: 7.0-7.8k a game (theirs to us 0.9-2.8k).
WRDistilled out-expands from minute 8 and holds ~80-100 s of income as army at 12 min against our ~20-25 s. Against
BARb our income and extractors lead (16 min: 107-173 vs 133-143) but the army trails (6-7k vs 8k). These are
economy/army-share questions (his rulings: army is a share of spend), outside the army model; raised with him.
06:00 Mac own-d (wake 5x, no copy of f_neg orders) and own-e (place teacher) on 42 own games: gate 1 own-d FAIL
(act logloss +0.017, place 392, response 0.933), own-e borderline (act +0.012, rest level); gate 2: own-d's parked
click chance 0.03-0.08 per step (62-92% per 10 s) but place unchanged; own-e learned the kind (fight 0.59 at 8.3)
but not the place (mass near the teacher's 7120,3776 at 7.8: live 0.101, own-c 0.191, own-d 0.123, own-e 0.104);
the best cell is still their own spot for every model. ~88 placed labels cannot outpull the copied clicks. Next:
own-f = own-e + weight 5 on placed wakes (cell/offset/kind) and on all wakes' act; and more own games (live only,
seeds 47-58) to grow the placed labels.
06:35 Mac own-f (heavy teacher: placed wakes 5x on cell/offset/kind, all wakes 5x on act): gate 1 act logloss 0.421
(best), but place error 389 -> 404 and click rate 0.073 (players 0.056): FAIL. Gate 2: it acts (87-98% per 10 s) and
fights (0.77-0.94), hold down to 0.17-0.21, but the place spreads: best cell still the own spot at 0.04-0.06, mass
near the teacher's spot 0.064 (live 0.101). 88 placed moments from a few episodes cannot teach a place; weight
smears it. No more weight arms. The Mac now loops: 24 live-model games per cycle into own-games, retrain own-e's
setup (teacher on, weights 1, share 0.5) from the live model, gates 1-2 per cycle in workhorse-outbox/loop.txt;
gate 3 only when the parked best cell leaves its spot or target mass passes 0.2; if placed moments per cycle are
under ~50, stop and rethink the teacher.

06:20 (local 03:20) check. PC idle (0 engines, recorder off, free 48.7 GB). Mac: batch h (live only, seeds 47-58)
running, the loop starts after it (loop.txt not written yet). No code changed here this hour. Open with him: the
economy / army-share gap against WRDistilled (05:20).
06:45 Mac batch h (live model only, seeds 47-58, 24 games, 0 desyncs) recorded: own-games 66. Teacher moments per 24
games: batch h ~10,100 woken / ~8,200 placed force-steps, 103 distinct placed (team, minute), 21 of 24 games
(the live model parks a lot); batch g ~2,350 placed, 38 minutes, 11 games. Standing loop running on the Mac:
c1 = own-e's setup on 66 games, then 24 fresh live games per cycle (seeds 59+), recount, retrain, gates 1-2,
table workhorse-outbox/loop.txt; stops on a gate-3 trigger, a failure or after c10; messages only then.

07:20 (local 04:20) check. PC idle (0 engines, recorder off, free 48.8 GB). Mac loop: loop.txt exists, empty (c1
training/gating on 66 games, started ~35 min ago). If still empty next hour, ask Workhorse. No code changed here.

08:20 (local 05:20) check. PC idle (0 engines, recorder off, free 48.8 GB). Mac loop c1 done (66 own games):
held-out act_logloss 0.4428 -> 0.4302, d_f_cell 389 -> 384; parked group at 7.8 p/step 0.0018 -> 0.0025, target
mass 0.101 -> 0.128, best cell still the spot they stand on (7104,4368), kind move 0.99 -> 0.54. Right direction,
small; no gate-3 trigger (mass < 0.2, best cell unchanged). c2 is playing its 24 games. No code changed here.

09:20 (local 06:20) check. PC idle (0 engines, recorder off, free 48.9 GB). Mac loop c2 (90 own games): act_logloss
0.4313, d_f_cell 384; parked group p/step 0.0025 -> 0.0035 (clicks keep rising with games), target mass 0.128 ->
0.125 (flat), best cell still their own spot. More own games raise "act" but not "where". If c3's mass is flat
too, the place is not a data-count problem: stop the loop there and look at why the place teacher's target loses
to the stand-still cell (its weight vs the players' place labels for the same moment). No code changed here.

10:20 (local 07:20) check. PC idle (0 engines, recorder off, free 48.9 GB). Mac loop c3 (114 own games): act_logloss
0.4296, d_f_cell 384, p/step 0.0044, target mass 0.078 (below live 0.101), best cell still their own spot, kind now
fight 0.52; placed moments 4,650 vs ~8,200. Stop rule met (mass flat then down while clicks rise). Asked Workhorse to
stop the loop and run a no-training diagnostic (workhorse-outbox/place-diag.txt): teacher place loss on train own
games vs the held-out parked moments across live/c1-c3, and log p of teacher vs stand cell at 7.8, to tell
generalization from optimization; plus which model played each cycle and why c3 placed fewer. No code changed here.

Workhorse place-diag (after c3): OUTWEIGHED, not generalization. Teacher place = 1.0% of f_cell weight per batch
(0.37 labels/batch, w 0.09, vs own clicks 11.9 w 3.25 and player clicks 5.2 w 7.63; 79% of batches have none).
Train-side teacher CE 8.1-8.5 (live) -> 7.3-7.5 (c1), flat to c3 (uniform 8.32). watch-wrd-31 at 7.8 log p
teacher/stand cell: live -5.76/-3.22, c3 -6.01/-3.03. All cycles were played by the live model; c3's fewer placed
moments = BARb-arm seed spread. Open before the next arm: own-f (heavy teacher) smeared the place, so asked
for (1) own-f's train teacher CE (learnable?), (2) players' cell CE on the same scale + teacher target jump
between steps (label noise?), (3) own clicks by side (ours/BARb/WRD) and their rating (self-imitation anchoring
the stand cell?). -> place-diag2.txt.

place-diag2: the teacher is learnable only a little. own-f (heavy weight) gets 6.7 on its own games and 7.0 on unseen ones,
against the players' place CE of 5.2 on held-out players. On watch-wrd-31 it is worse (6.23) and keeps the stand cell
(-6.18 / -3.00). The target is steady (median jump 34 elmos per 10 s; 7% jump 2,000+). Shares of the f_cell weight:
players 70%, BARb + WRD orders from own games 23%, our own orders 6%, teacher 1%. Reading: a blind group can't
predict the next fight (hidden information), so the future-fight teacher is not a usable place label. Checking
it with place-diag3 (teacher CE, seen vs blind targets). Next arm waits on his answer: what a parked group's place
should be learned from, and whether own games should teach the place from the opponents' orders at all.

place-diag3 (1,568 teacher-placed forces; teacher CE live / c3 / own-f): blind target 27%: 8.20 / 8.19 / 7.72
(near uniform); in sight, no enemy showing 61%: 8.52 / 7.27 / 6.91; in sight with an enemy showing 12%:
7.36 / 5.63 / 4.89 (players 5.2). Correction to my hidden-information reading: blindness explains only the blind
quarter; mostly the label asks for a fight that has not arrived yet. Learnable part = an enemy already showing
(13% of teacher moments). Still waiting on his answer: what a parked group's place is learned from (my proposal:
what is visible now, i.e. cover our assets in reach or scout the nearest blind area), and BARb/WRD orders in own games.

11:20 (local 08:20) check. PC idle (0 engines, recorder off). Mac loop stopped after c3, no arm running: waiting on
his answer on the parked group's place label and BARb/WRD orders in own games. No code changed.

12:20 (local 09:20) check. PC idle, Mac idle (loop stopped after c3). Still waiting on his two answers. No code changed.

11-21 his direction on the parked group: two jobs, block their army from our base and hurt their base, economy
first; assume where they are (start known, spots around it held), scout, then harass. Measured (scratchpad
spot_belief.py, start_guess.py; 300 players' 1v1s): at minute 8, 98% of enemy extractors are out of our sight, 78%
within 1,500 of their start, 96% within 3,000. Out-of-sight spots held by the enemy, by how far forward (our start 0,
theirs 1) at minute 8: 0.00 / 0.01 / 0.04 / 0.17 / 0.39 (0.8-1.2). The enemy start vs the mirror of ours: median
800 elmos (best of three mirrors: median 330, 63% under 1,000). The model has no enemy-start input; its only enemy
eco input is what it has seen (channel 23), which is ~2% of it.
Plan: (A) belief head: predict where enemy extractors stand now, label from the replay's ground truth (all players'
games), inputs unchanged; measure held-out against the seen-only channel. (B) after his go: the place label for a
group with no fight = between their army and our base when it is heading in, else their believed economy.
Built (A), on the PC: data.py label b_eco (enemy finished eco per cell, truth; mirror + collate), model.py b_eco
head (1x1 conv on u64), train.py 10*BCE + belief_eval (unseen cells: top-k share for the head vs a mirror rule vs
layer 23). No input changed, so serve/parity are untouched. CPU smoke passed (belief_smoke.py: label, mirror, grad,
eval). Sent to Workhorse as henry-outbox/workhorse/belief-1/ (players only, from live, 8k steps). Measure: b_top_model
clearly above b_top_rule and b_top_seen, gate 1 no worse. (B) waits on that and his go.
His 11-21 follow-up: a player assumes the enemy does about what he does (a commander rush is the rare risk play).
Measured (mirror_belief.py, 120 players' 1v1s, top-k share of unseen enemy eco cells; minutes 0-6 / 6-12 / 12+):
spot rule 0.242 / 0.278 / 0.245, mirror of our own economy 0.257 / 0.279 / 0.245, last seen 0.194 / 0.182 / 0.276.
Mirroring our layout finds their economy no better than "spots on their side"; so no mirrored input channel for
now. The learned head has to beat both. belief_eval now reports b_top_mirror too (train.py re-sent to belief-1/).
His OK (11-21) on the plan: belief head first; then the place for a group with no fight (between their army and our
base when it comes in, else their believed economy). Step B starts once belief-1's held-out numbers pass.
BARb/WRD orders in own games: not answered yet.

belief-1 (Mac, 8k, players only): held-out unseen enemy-eco cells found in top k: model 0.316, rule 0.256, near
rule 0.262, seen 0.245; m3-6 0.300 vs 0.237, m6-12 0.292 vs 0.285 (barely), m12+ 0.353 vs 0.257/0.277. Still rising
(6k 0.292). Gate 1 level or better (act 0.4197 vs 0.4428, d_f_cell 365 vs 389), response_recall 0.934 vs 0.948.
Continuing to 16k as belief-1b, with a within-one-cell measure.
Built (B): data._job_target + BARAI_WAKE_PLACE=jobs. Block = the incoming enemy ground army seen or remembered in
the last 20 s, worth min(its metal, ours), placed where we arrive first on its line to our base. Hit = their true
economy outside static guns, the square with the most metal per second of travel. The bigger metal wins. On
watch-wrd-31 the parked group (minutes 5-8.3) gets "hit" at about 6,700,750, 3,600 away, 550-1,750 metal. Over 18
own games, 501/506 woken forces are placed: block 40% (stakes small, median 92 vs 50), hit 60% (median 720). Sent as
henry-outbox/workhorse/jobs-1/ (arms a default / b heavy weight, from belief-1b).
Open: block wins on tiny stakes (two scouts heading in); watch whether it drags groups after raiders (11-16 ruling).

13:20 (local 10:20) check. PC idle (0 engines). Mac: belief-1b (16k) running, no report yet; jobs-1 queued behind it.
No code changed this hour beyond the jobs-1 package.

belief-1b (16k): exact-cell top k 0.335 (m6-12 0.318 vs mirror 0.282), flattening; gate 1 fine (act 0.4142,
response 0.957). But within one cell the ranking reverses: belief-1b 0.493 vs rule 0.641 / mirror 0.655 / seen
0.409. The head's top k is one smooth blob, so its picks are redundant, while the rules' picks spread over separate
spots. NOT passed. Asked for NMS top-k (suppress the 8 neighbours after each pick, one-cell tolerance) for every
method. jobs-1a (place w 1) and jobs-1b (place w 5, wake w 5) are running from belief-1b 8k, own 114 at 0.25; the
unseen set is c4's 8 games. On the Mac's own games the jobs label is block 9% / hit 91% (PC 18 games: 40/60).
NMS belief (fair: picks spread, one-cell tolerance), all / m3-6 / m6-12 / m12+: belief-1b 0.707 / 0.647 / 0.677 /
0.770; mirror of our economy 0.660 / 0.682 / 0.661 / 0.655; rule 0.648 / 0.649 / 0.650 / 0.652; seen 0.409 /
0.277 / 0.361 / 0.524; belief-1 0.655 / 0.564 / 0.620 / 0.739. belief-1b is ahead overall (+0.047), behind the
mirror early (-0.035), level-ish at 6-12 (+0.016), well ahead late (+0.115). Training flattened by 16k, so no more
steps. Next candidate (after jobs-1, one change at a time): our economy mirrored through the centre as an input
layer, his "they do what you do", since the mirror beats the head early. Measure: NMS m3-6 at or above the mirror,
the rest not lower.

14:20 (local 11:20) check. PC idle (0 engines). Mac: jobs-1a/1b training, no report yet. No code changed.

jobs-1 (Mac, from belief-1b, own 114 at 0.25): the job label's cell CE (unseen c4 / watch-wrd-31 parked): live
11.28 / 9.65, jobs-1a (w1) 8.67 / 7.44, jobs-1b (w5) 5.66 / 4.81. Hit learns and generalizes (unseen 5.52); block
stays hard (8.3-10.9). Block is 24% of labels. Weight share 0.6% (w1) and 2.4% (w5). GATE 2 PASSES for jobs-1b:
at 7.8 the best cell is 6976,624, 362 from the job target (live: the stand spot); mass within 400 = 0.237 (live
0.101 by the old target); fight 0.89; p/step 0.0173 (live 0.0022); mass 0.118 -> 0.250 over 6.3-8.3. Gate 1
jobs-1b / belief-1b / live: act 0.4223 / 0.4142 / 0.4428, d_f_cell 362 / 384 / 389, f_rate 0.0514 / 0.0529 /
0.0384 (player 0.0555), retreat 0.323 / 0.353 / 0.296, response 0.952 / 0.957 / 0.948. Belief held (NMS 0.743).
Gate 3 running: live (fbias 0.39) vs jobs-1b (0.026), BARb hard + WRD 0.4, seeds 89-100, 48 games.
His 11-21 (to Workhorse): 20-minute games are too short, so run ~40. jobs-1b's gate 3 restarted at 40 minutes
(same arms, seeds 89-100, 48 games, Mac runtime/armynet/paired-jobs40.log, ~3 h). Earlier 20-minute results and
the 114 own games don't compare directly with it.
11-21: his replay of jobs-1b vs BARb (seed 89, 40 min) is open on the PC, but the PC's BAR.sdd is stale: test-31578
from 10-12, while the Mac and the lobby (sync_game --dry-run) are on test-32018-ad135b9. The playback may drift.
All Mac games are on the right build. To do once he closes the replay: sync_game.py on the PC, then deploy_ai
gadgets + patches + the armynet lane.
11-21 ~11:50: the replay hung loading LuaUI (watchdog) on the stale build, so I closed it (my process; his lobby
kept). sync_game.py ran: BAR.sdd = test-32018-ad135b9, old tree in data/games-old/BAR-20261121-1151.sdd.
deploy_ai gadgets done. deploy_ai patches REFUSED ("BAR.sdd is not a git checkout"). Not done yet: the patches
question and the armynet lane deploy. He started playing online, so everything waits for his game to end.

15:20 (local 12:20) check. His online game is running (infolog live, 8 Apex v0.5.17 seats), so the PC does
nothing: no engines, no deploys. Pending for after: the patches refusal, the armynet lane deploy, and a live
watch game of jobs-1b instead of a replay (his ask). Mac: jobs-1b's 40-min gate 3 is running. No code changed.

16:20 (local 13:20) check. His game has ended (lobby closed, infolog 13 min old). The patches refusal is
not a blocker: 0001-ai_namer-variant-prefix.patch no longer matches upstream's ai_namer.lua, it was not
applied on the 10-12 tree either (git apply --reverse --check fails on both), so that step has done
nothing since 10-12 and every harness game since ran without it. Left as is; to raise with him. Lane
armynet deployed on test-32018 (DLL local build, dev_armynet.lua present); smoke.py passed (compiled,
2 min). Recorder restarted (follow --workers 1). Asked Workhorse for the jobs-1b checkpoint path and
gate 3 progress, for the live watch game (watch.py --watch --model <jobs-1b> --forces --learned --rally
--fbias 0.026). No code changed.
13:45 local: jobs-1b fetched (runtime/armynet/jobs-1b/model-008000.pt, 7,988,805 bytes; model.py sha1 equal to
the Mac's). Live watch game launched for him: watch.py --forces --learned --rally --fbias 0.026, seed 89, 40 min,
dir matches/watch-armynet-engine-20261121-134440-32248. Past loading on the new build; serve deciding (frame 1860).
Gate 3 on the Mac: 37/48 done, about 1 h left.

11-21 ~14:20 local, his live watch of jobs-1b (seed 89, Cortex mirror, lost at 32.5). His read: the army
preserves itself well (about level army at half their economy), but where the front line stands is crude, it
always draws one straight line at an odd angle; he wants curves, several lines, which units in front or behind
(T2), and maybe a deeper net. He says the loss was air and the nuke, not the army. The game's facts:
- Air: their Shadows from 11.3 (33 built, 34 Vengeance); our first Vengeance at 17.1, 6 in all; our first
  corrl at 12.7. airanswer showed want 0 until 13. Shadows killed 3,853 m at home in 12-16 (advsol, nanos, mexes).
- Nuke: our anti-nuke (corfmd, 21.4) was killed at 26.1 by Termites inside our base (Termites took 3,655 m of
  our buildings in 24-26.5); their nuke landed at 26.5, 26 s later. So the army's block job missed a raid that
  opened the base to the nuke.
- Line angle: serve's line faces base_axis (the base-to-base field) turned by the learned angle; it never
  faces the enemy actually in front of it. The shape is one point or one straight line; data.py's f_shape keeps
  only length and angle (the principal axis of the click's targets).
- Players (scratchpad drag_shapes.py / click_layers.py, 60 games): 20,742 drags of 6+ units, 92% one straight
  row, 2% curved, 3% two or more rows. 542 pairs of near clicks within 5 s: longer range further back 52% (67),
  costlier further back 46% (48). Players don't layer by click; depth likely comes from each unit stopping at
  its own range on a fight order. So curves and layers can't be copied from replays; they need a design (to
  propose to him).
- Capacity: jobs-1b has 1.99 M parameters. The place CE sits near uniform even on train (place-diag), so a
  wider/deeper test on the Mac shows whether capacity or the label limits it: train CE falling = capacity.

Gate 3 for jobs-1b (Mac, 48 games at 40 min, seeds 89-100) FAILS. vs BARb: up 3 / down 7 / even 2, W/T/L live
0/7/5 vs 0/5/7, commander deaths 4 -> 7, trade 0.68 -> 0.46. vs WRD 0.4: up 9 / down 3, survival 21.9 -> 26.7
min, trade 0.87 -> 1.18, one win (seed 92). p/step 0.036 -> 0.103 (BARb), idle p about 10x. Live stays
force-heads-20261120b. New at 40 min: live loses 5 of 12 vs BARb, all at 29.8-33.3 (0 losses in 36 at 20 min).
Raider-chasing check, corrected: block metal = min(raid, our group), so the Mac's "83% under 300" was our groups
being small. PC own games (40, job_rate.py now logs group metal, raw raid metal, distance from base): block
raids under 300 metal 11%, sent group / raid median 0.1, block place a median 0 elmos from our base (slow groups
lose the intercept race and go home). Tried and reverted, both measured: (a) one blocker per step, sized to the
raid: blocks 33% -> 21%, answering a problem the data doesn't show; (b) outweighed groups go home: identical
output (already true). data.py: _job_target returns a dict and _wake_idle applies it (same labels, more log).
Open: hit is 67% of jobs (minute median 7.2, ~120-metal groups at a median 800 metal of their economy); maybe
where the BARb losses come from, not checked. Asked Workhorse: commander deaths, army lost by job, and what
ends the live model's 30-min losses.
Workhorse deaths.py on gate 3: all 12 commander deaths vs BARb (live 5, jobs-1b 7; the earlier table said 4)
happen at home, 28-38 min, to T3/experimental ground (armthor x6, armmanni, corkorg, corkarg, corcat); none
out with a force. Army metal lost vs BARb, live / jobs-1b: home 11.8k / 24.9k, mid 63.0k / 66.2k, enemy side
31.0k / 4.2k. So "hit groups thrown away" is refuted: jobs-1b loses less deep and twice as much at home. Live's
5 BARb losses end with Thor / Razorback / Manni / Korgoth / Juggernaut / Karganeth taking our base. At 40 min
the gap is BARb's T3 push at ~30 min, in both arms. Asked: T3 metal by 25/30, income at 20/25/30, army home
vs away at the first T3 arrival.
Workhorse late_loss.py (24 BARb games): T3 (gantry-built) metal by 25 is 0 in 23 of 24 games (BARb has T3 by 25
in 10 of 12 seeds per arm, 12-38k). By 30 ours is non-zero in only 5 games. Income us:BARb at 20 / 24 / 28: live
217:246, 323:319, 418:403; jobs-1b 192:277, 256:379, 287:500. Every live loss is behind at 28, and so is every
jobs-1b loss. First enemy T3 in our third comes at ~17-21 min against 2-3k army at home. So the 40-min gap is
production and eco (no T3, behind by 28), not where the army stands. jobs-1b's eco is worse than live's from
20; whether that's the cause isn't checked. Asked for a --nomodel control at 40 min (6 seeds) to split "our AI
doesn't tech" from "the model's hands-off suppresses the tech".
(c) in full: at the first enemy T3 in our third (17-28.7 min) our whole army is 0.7-13.7k, and in live's losses
3.4-7.9k, less than one Thor (9.0k) even all at home. jobs-1b's army is mostly home (away 0 in 3 of 7) and
still loses. In live's 3 games with no T3 arrival, BARb's T3 by 30 was 0-11.8k and we led at 28 (680:295,
679:227, 472:229). The --nomodel control is running on the Mac (seeds 89-94, 40 min, nomodel40.log).

17:20 (local 14:20) check. PC: no engines, his game not running (infolog 74 min old), recorder alive
(recorded 358 -> 397), free commit 48.6 GB. No PC campaign (the Mac trains). Since the last check: gate 3
failed for jobs-1b (live stays); the 40-min gap vs BARb is no T3 and eco behind by 28, not army placement;
two label changes tried and reverted on measurement (data.py labels unchanged, more logging). The --nomodel
40-min control is running on the Mac. Waiting on his yes/no for range arcs.
--nomodel control vs BARb hard, 40 min, seeds 89-94 (Mac): ctrl 3 W / 3 T / 0 L, live 0 W / 4 T / 2 L, ctrl better
on 4 seeds and even on 2. T3 by 25: ctrl 0 in 5 of 6, live 0 in 6 of 6 (neither techs by 25: the production
side, for him). T3 by 30: ctrl non-zero in 5 of 6, live in 2 of 6. Income at 20: ctrl 267 vs live 219; at 28
ctrl ahead in all 5 games still running, live behind in 3 of 6. At the first enemy T3 in our third ctrl's army
is 12-84k (arriving 25.8-31.7) vs live's 3.4-8.4k (20.2-27.5). So against BARb at 40 min the model's army costs
us: a smaller army, lower eco, later tech. Asked: army lost by zone and minute, trade, and army produced, ctrl vs
live, to split losses in trades from lower production.
Army flow ctrl vs live (6 BARb seeds, army_flow.py on the Mac): the "4-10x bigger army" was a timing artefact. At
the same minute the armies match (min 20 mean 12.6k both). Produced by 20: 27.4k / 25.8k; by 28: 80.4k / 72.0k
(live out-produces ctrl in its 4 non-loss seeds, e.g. 103k vs 90k). Lost by zone: home 1.4k / 15.0k, mid 52.3k
/ 54.0k, deep 32.5k / 49.3k; by band 20-30 38.7k / 51.1k, 30+ 30.8k / 51.7k. Killed per lost by 28: 0.41 / 0.46;
whole game 1.03 / 0.57. So the model costs nothing measurable up to 20. The gap is two collapsing seeds (s90,
s92; s92 production a third of ctrl's by 20) and late fights. Asked: what took s90/s92's production down, and
live's biggest late army-loss minutes.
late_fights.py (Mac): live s92 lost 4.7k of eco by 20 to Rover/Flash raids into the base from minute 2 (ctrl
2.6k, mostly mid), with our army there and still losing it; too small alone for income 113 vs 337 (mex builds
not counted). s90 stalls after 20 (ctrl lost more eco before 20). The biggest late army losses in live: at home
at 29 to T3/Vanguard (s90 17.6k, s91 23.7k), and deep into guns (s89 min 27: 27.7k of ours vs 14.7k + 16.6k of
guns incl. cortoast). Six seeds can't separate the model from bad games, so I asked for the control on all 12
seeds in both matchups (BARb 95-100 added, WRD 89-100), scored ctrl vs live with gate3_score.py.

18:20 (local 15:20) check. PC: his game not running (infolog 2.2 h old); one engine, the recorder's (recorded
397 -> 446); free commit 43.7 GB. No PC campaign. Mac: the --nomodel control's remaining 18 games (WRD 89-100,
BARb 95-100) are running, ~1.5 h. No code changed this hour.

11-21 ~15:50 local. His "rely less on me and more on your intuition": I built both formation changes without
waiting. (1) face-1: data.face_dir, the line's facing = toward the enemy near it (seen ch 7 > remembered
buildings ch 8 > remembered ground guns ch 11, within 2,500, 1/d weighted, else the base axis). Used by the
f_shape label and by serve with --face. Players' lines within 20 deg of facing the reference: axis 27%,
face_dir 34% (chance 22%; unit movement 28%), 886 lines in 60 games, label mean cos2a -0.132 -> -0.203. Needs
retraining (sent to Workhorse: fine-tune live with the new label, gate 1, gate 3 at 40 min). (2) Range arcs:
serve --arc (arc_slots). The front arc goes through the model's place around what the line faces; units step
back by their range over the shortest; unarmed units go behind. Checked on a synthetic force. Smoke: by
minute 12, point 158 / line 7 / arc 83, compute 0.024 -> 0.033 s. Gate after face-1, as its own arm. serve.log
minute lines now log shapes. Without the flags serve is unchanged.

THE ANSWER FOR v0.6 SO FAR (11-21, Mac, all 12 seeds, 40 min): our AI's own army (--nomodel) beats the live
model clearly. vs BARb hard: ctrl 6/4/2 W/T/L, trade 1.46, 2 commander deaths; live 0/7/5, 0.68, 5. vs WRD 0.4:
ctrl 6/0/6, trade 1.62, 6 commander deaths; live 0/1/11, 0.87, 11. ctrl vs live up 8 / down 3 / even 1 in both.
Up to minute 20 the two match (army_flow); the model falls behind after that. Likely training cause (measured,
late_data.py, 422 recordings): players' 1v1s run median 13.0 min, only 9% past 25 and 4% past 30; 15% of orders
come after minute 20, 8% after 25, 4% after 30. The model has barely seen the T3 era. From now on the bar for
an army model is our own army (--nomodel), not the live model. gate3_score's commander column is wrong for
ctrl (report.md shows 0); cmd_deaths.py (BARAI_DEATH) is right.
Late-game data: public_replays.record now records longest first (the old order was manifest order). pick of
duels 25+ min over 150 pages added 20 games. The kept list has 150 games over 25 min and 75 over 30, out of
1,648. 1,773 long games were turned away for OS below 30; lowering the rating floor would bring them in, a
data-quality trade not made. Recorder restarted (follow --workers 1). Measure: late_data.py share of orders
after 25 / 30 (8% / 4% now) on the recordings as they land.
His 11-21: learn from his own games against our AI too, and less from players who perform poorly. Found: train.py
ROOTS already reads G:/bar-ai-archive/replay-orders (his demos), but only 9 of 471 were ever recorded. His
demos (his_demo_scan.py): 471 games, median 26.4 min, 252 over 25 and 202 over 30. Mostly humans vs Apex (8v8
161); he played 314. replay_dataset keeps human teams' decisions only, and their skill goes into w_rating.
Started: replay_orders.py batch --workers 2 (447 to record, newest first, waits while he plays). Performance: the
skill weight already exists (w_r = clip((OS-15)/20, 0.25, 2): 0.25 at 20, 1.0 at 35, 2.0 at 55, applied to the
force losses), so weaker players teach less. Lowered the public floor for long games only: over 25 min keeps
down to OS 20 (public_replays judge, LONG_MIN/LONG_OS), and the manifest re-judge kept 196 such games (177
duels; floor 25 would have given 62, floor 15 582, all at the 0.25 minimum). Measure: late_data.py share of orders
after 25 / 30 (now 8% / 4%) once these land; then a model trained with them vs our own army at 40 min.
His 11-21 follow-up: "even good players play bad sometimes, and bad players good, so it depends on the
performance in particular games, we want to learn from the best moments". Measured (moments.py, 120 public
games, 970,598 orders, 240 player-games): the rating explains 1% of the spread in a player-game's mean 60-s
trade (99% within rating bands, corr -0.05). Top-10% orders by 60-s trade by band: 30-35 22% of them, 35-40 12%,
40-45 22%, 45+ 44%, about each band's share of orders. But the old weight gave a best moment 0.99 at 30-35 and
2.38 at 45+. Change: data.py w_rating = 1.0 (no rating weight); the moment's own score (f_w from dec_score)
weighs it. Noted: dec_score correlates only 0.10 with the raw 60-s trade (top-10% mean score 0.50 vs 0.13), so
how well it finds "the best moments" is the next thing to check. The recorder's OS floor (30; 20 for 25+ min)
stays for now, for throughput. Next candidate late-1: his games + long games + no rating weight, gated vs our
own army at 40 min. Two changes in one candidate because a cycle takes hours; ablate if it wins.

19:20 (local 16:20) check. He opened the lobby (spring.exe --menu, 16:09) while three of our recording engines
ran. I stopped both recorders and their engines, then found he was only browsing battles (infolog f=-000001,
no game frames), which the rule allows. Gap found and fixed: his_game_running only saw lobby games through our
bot logs, so a game of his with no Apex seat went unseen. mp_archive.his_game_running now also returns true
when the install's infolog is fresh (<120 s) with game frames in its last 8 KB. Checked: False in the lobby
now; the pattern matches a real game's lines. Both recorders restarted (public follow 1 worker, his demos 2).
Free commit 24.8 GB (gate 20). No Mac report this hour; face-1 and the data questions are with Workhorse.
~17:00 local: npz build for new recordings done, no errors: 127 built since the snapshot (npz-sent-1120.txt,
the 1,274 the Mac has), but only 12 over 25 min, so packing waits for the long games and his demos.
tools/armynet/pack_npz.py written (tars <= 9.5 MB, .partNN splits built in memory, FETCH.txt, two roots).
Two recorder engines launched at 16:57 while he played: the gate passed before his game, then the
memory/commit waits ran past its start with no re-check. I killed them, which left two partial recordings
read as done (run() keeps whatever orders exist unless it stopped the engine itself). Fixes in
replay_orders.py: (a) batch_list repeats every gate after any wait, and re-checks his game just before
launch; (b) run() keeps orders only with a clean shutdown (SpringApp::Kill in stdout; 479 of 480 public
recordings have it). The two cut ones were renamed orders.cut.txt.gz, so they're redone. Lesson: don't kill
recorder engines by hand; run() stops them itself within 30 s of his game starting and keeps nothing.
Recorders restarted on the fixed code.
face-1 gate 3 (Mac, 40 min, seeds 89-100): vs BARb up 6 / down 6 (W/T/L 1/7/4 vs live 0/7/5, commander deaths 4
vs 5, trade 0.61 vs 0.68); vs WRD up 5 / down 5 / even 2 (0/0/12 vs 0/1/11). Not passed: level, and gate 1
showed the angle wasn't learned. Not kept: the f_shape label goes back to the axis reference after the arc
gate (which runs on face-1 --face, so it's left in place until then); face_dir stays only if the arc wins.
The arc gate (face-1 --face --arc vs face-1 --face) is running, ~2 h. Both still far below our own army.

20:20 (local 17:20) check. He's in a game (Into Battle Redux, started 17:06), but three recorder engines
launched at 17:19: his_game_running read False. The infolog had been quiet for 288 s mid-game (frame 19040),
past the 120-s freshness window. Fixed: mp_archive.his_game_running also returns true for a zero-byte demo
under 3 h old (created at game start, written at its end); it reads True now. The only other zero-byte demo is
from 10-23, outside the window. Recorders stopped, then their engines; cut_check shows no partial recordings
(run() drops unclean ends). Both restarted and waiting; 0 headless engines. Free commit 18.9 GB, below the 20
gate; the recorders hold on it too. Mac: the arc gate is running. Data: 1 of his 447 demos recorded so far
(his playing keeps the recorder waiting).

His 11-21 design talk (ranks; risk and advantage; land value; a planner; strategy inferred from watching;
late data from his bot games and 8v8 online). Written up as todo/army-command-levels.md (TODO.md line).
Built step 2 of it: data.py channels 29 (enemy reach) and 30 (our reach). Each is armed mobile metal weighted
by exp(-travel time / REACH_S=60 s) to each cell: the enemy's from this side's memory (seen now or remembered,
fading), ours from friendly armed mobiles. CHANNELS 29 -> 31. Live builds the same example, so parity holds by
construction. Smoke (reach_smoke.py): non-zero in 18-19 of 20 moments; per-example time 4.2 -> 4.6 ms on a
public 1v1, 9.4 -> 22.2 ms on an own game. load_widened takes the live checkpoint to 31 inputs with zero
weights (plays as before). Not trained yet. Plan: one late-game candidate (late-1 = his games + long public
games + no rating weight + reach fields) once the data lands, gated vs our own army at 40 min, ablated if it
wins. Before that the capacity test (3 sizes). Long public team games: pick --preset team --min-minutes 25
running.
Long public team games: pick --preset team --pages 40 --min-minutes 25 judged 2,803, kept 53 (42 long). One
weak player of 16 turned most away, so long team games are now judged by their median player (OS 20+; judge()
and rejudge_team.py): 419 more kept, 472 team games kept in all (kept total 2,285). Size: his 8v8 npz median
13.6 MB (max 43.6) vs public 1v1 2.4 MB, so the late data is ~12-15 GB, about 1,400 fetches at 10 MB. Asked
Workhorse for a faster path before packing; failing that, his games and the long duels go first. Disk: G: 3.9
TB free, C: 60 GB.
His 11-21: "it is fine to share a folder from this PC, just for this stuff". tools/armynet/npz_share.py:
read-only HTTP on port 8765, only .npz under the two recording roots plus /list. Answers 192.168.0.0/16,
Tailscale 100.64.0.0/10 and localhost only; logs to G:/bar-ai-archive/npz-share.log. Local test: list 1,276
files, traversal and non-npz paths 404, a 48.5 MB file whole over 192.168.50.98. Workhorse asked to try LAN /
Tailscale. If it reaches, pack_npz.py isn't needed. Running in the background (restart after a reboot by hand).

21:20 (local 18:20) check. The share works: the Mac (192.168.50.49) listed 4 times and pulled 136 npz (126
public, 10 his), all 200, 18:12-18:14. No packing needed. Started overnight.py --build-only: npz from new
recordings every 10 min, paused during his games. Recorders: 3 headless engines (public 1, his demos 2; limit 4),
his game not running, free commit 25.3 GB. His demos 8 of 447 recorded (8v8 orders 30-110 MB, up to 20 min
wall each). Public recorded 483. Mac: arc gate, then the capacity test. No model code changed this hour.
Mac side of the share (Workhorse): tools-0030/npz_pull.py mirrors it into vendor/npz-share/<root>/ every 15 min.
It pulls files that are missing, differ in size or have a newer mtime, written .part then renamed. First pass
63 s: 136 pulled (0.7 GB, ~11 MB/s), 1,140 hard-linked from the old copy. vendor/player-recordings stays frozen
for the capacity test and gate-1 comparisons. late-1 trains on --roots vendor/npz-share/recordings,
vendor/npz-share/replay-orders. The held-out split hashes file names, so it doesn't depend on the root.
Arc gate 3 (Mac, face-1 --face --arc vs face-1 --face, 40 min, seeds 89-100): vs BARb up 7 / down 5, W/T/L 1/8/3
vs 1/7/4, commander deaths 3 vs 4, trade 0.71 vs 0.61; vs WRD up 7 / down 5, 0/0/12 both, trade 0.97 vs 0.91.
Shapes at game end: arcs 227-304 vs lines 10-32 vs points 544-635. Passes by the letter, weak (one seed's
swing). Kept: serve --arc, which uses face_dir's point. face-1 dropped: the f_shape label is back on the axis
reference, and serve/watch --face is removed. Checked exact: the pre-change data.py gives the same label on
today's files (916 lines, mean cos2a -0.213; the earlier -0.132 was on files since rebuilt). Both arms still far
below our own army (ctrl 6/4/2 vs BARb). The capacity test is running on the Mac.
late-1 files to Workhorse (henry-outbox/workhorse/late-1/): data.py feb50684, serve.py 20c060aa, watch.py e24ed2a2,
model.py bfb16085. No own games (as live). Order: capacity test first on the GPU (running, ~4-5 h; no CPU
training), then late-1 from live on the two share roots. Gate 3: live+--arc vs late-1+--arc, plus --nomodel,
40 min, seeds 89-100.

22:20 (local 19:20) check. Recorders: 3 headless engines (limit 4), his game not running, free commit 26.3 GB.
His demos 24 of 447 recorded, public 493. The Mac pulls every 15 min (last 19:16). Self-review: parity.py on 2
games, 12 moments, with the new 31-channel data.py: no grid channel differs (reach 29/30 included), tokens and
forces the same. Mac: capacity test running; late-1 queued after it (8k, +8k if late-game held-out loss still
falls >1% from 6k to 8k; data-count.txt logs the share past minute 20/25/30 per root). No code changed this hour.

23:25 (local 20:25) check. He is in a live game (Archsimkats Valley, 48 min, zero-byte demo + infolog frames): the
recorders wait, 0 headless engines, free commit 33.9 GB. His demos 24 of 447, public 498. The Mac pulled at 20:16.
Best moments (scratchpad moments2.py, 40 public games, 343,710 orders, idle priority): corr(dec_score, raw 60-s
trade) 0.20, with window-centred 60-s trade 0.14. Only the 3 trade columns (h0-2, measure 8) track trade (0.10,
0.16, 0.28); the 7 near-target/map columns at h3-4 don't (-0.01..0.04), as meant. The weight barely separates:
mean exp(0.5 score) is 1.26 on the best 10% (centred trade), 1.04 on the worst 10%, 1.08 the rest; the best 10%
carry 11.6% of the weight (10% = none). score<0 on 2% of orders. So "learn from the best moments" is weak in
training now. Candidate moments-1 (after late-1, one change): temperature 1.0 instead of 0.5 in f_w and the
unit weight, judged by gate 1 held-out and gate 3 vs the live model. No code changed this hour.
Capacity test, first two sizes (Mac 20:21, held-out f_cell / f_act / kind, 20k OneCycle from scratch): base
128,64,3 (7.2 st/s) 8k 6.039/.2139/.1251, 20k 5.664/.1990/.1165; deep 128,64,6 (6.7 st/s) 8k 6.022/.2172/.1297,
20k 5.780/.1948/.1177. Deeper is no better: place 2% worse, act 2% better, kind 1% worse; both fall at the same
rate. Wide 256,96,4 at 3k (4.3 st/s). Asked for train losses at 8k/20k to tell data-limited from label-limited;
no 40k rerun unless wide beats base on held-out f_cell by >1%. late-1 about 21:35.

00:20 (local 21:20) check. He is in a second live game (Plains and Passes since 20:40, zero-byte demo + infolog
frames): recorders wait, 0 headless engines, free commit 31.2 GB. His demos 26 of 447, public 498. The Mac pulled
at 21:16. Mac: wide size finishing, late-1 at about 21:35; the full capacity table (train and held-out at 8k/20k)
comes after wide. No code changed this hour.
Capacity test done (Mac, 20k OneCycle fresh, fixed batches; f_cell/f_act/kind train | held-out at 20k): base
128,64,3 5.728/.1708/.1334 | 5.664/.1990/.1206; deep 128,64,6 5.803/.1688/.1328 | 5.780/.1948/.1221; wide
256,96,4 (7.42 M, 4.3 st/s) 5.617/.1680/.1305 | 5.552/.1940/.1179; held-out b_eco/value wide .2025/.2721 vs base
.2083/.2766. Train and held-out fall together (~6% on f_cell 8k->20k for every size): not overfitting, not
data-limited at this size, still undertrained at 20k. Width helps (place -2.0%, act -2.5%, all heads better);
depth doesn't. Next: wide fresh 40k after late-1's gate-3 games (not beside them: inference shares the machine),
scored on the same batches against the live model, then serve's time per decision on one short game.
arch-1 to Workhorse: model.py c83ac9ca adds arch_of(path) (d, c, layers from the checkpoint's shapes); serve.py
7a3bc46a builds ArmyNet(*arch_of(--model)) so the wide model loads. Checked: live checkpoint -> (128,64,3), the same
model as before; a saved 256,96,4 reads back and loads at 7.42 M. Installed on the Mac after late-1's gate games.

01:20 (local 22:20) check. He is in a third live game (Forge since 22:15): recorders wait, 0 headless engines, free
commit 30.3 GB. His demos 26 of 447, public 498. The Mac pulled at 22:16. Mac: late-1 training (then gate 1, fbias,
gate 3), wide 40k queued behind it with arch-1 staged. No code changed this hour.

02:20 (local 23:20) check. He is in a fifth live game (Pyroclast since 22:55): recorders wait, 0 headless engines,
free commit 28.4 GB. His demos 26 of 447, public 498. The Mac pulled at 23:16; late-1 training there. His question
"did something get messed up in v0.5.17": tonight's 5 games all ran v0.5.17 (nets=16318, script 2026-11-18 15:41,
files unchanged since the release), +50, no script errors. Side finding, old (c8ba1826, 09-19): every hosted game
logs "tweakunits7 is set (tweaked stats)" though the demo's tweakunits7 is empty, so hosted games never load or save
the matchup record (no AI/Skirmish/apex-record.txt in his install). Offered him the fix. No code changed this hour.
late-1 (Mac): share data 1,280 public games 2.03 M examples, 12.3/7.5/4.5% past min 20/25/30; his 32 games 143k,
33.0/24.8/17.5% (old player-recordings 10.2/5.6/3.0%). Late held-out past min 20 (31 games) f_cell/f_act/kind: live
5.418/.0514/.3531, l8 5.377/.0509/.3568 (-0.8% place, kind worse); 6k->8k under 1%, no 16k. fbias 0.188. Gate 3
late-1 vs live, both --arc: BARb up 6/down 5/even 1, W/T/L 0/7/5 vs 0/3/9, cmd deaths 5 vs 9, trade .65 vs .39; WRD
up 4/down 5/even 3, 0/0/12 both, trade .94 vs .79. Fails vs WRD; not adopted. The live arm was worse than in
paired-jobs40 (0/3/9 vs 0/7/5, cmd deaths 8-9 vs 4-5, p/step .045 vs .036), commanders dying mid-map alone (seeds 91,
93 at 10.7-11.6 min; 95/96/99/100) where before all died at home. Only play-side change for live: --arc (reach
channels zero-weighted). Suspect: arc_slots puts the shortest range in the front row, and the commander is short-
ranged. Asked the Mac for the counts from existing logs (ordered in the last 60 s before death; by an arc).
Correction: the arc hypothesis is wrong; dev_armynet.lua line 28 never hands the commander to the model, so neither
arcs nor any model order moves it. Asked instead for our vs enemy armed metal within 1,000 of the commander at each
mid-map death and its last commander-logic line: did it walk out with the army that then left, or alone?
Commander deaths (Mac com_out.py): it walked out alone. Our armed metal within 1,000 at death <= 720 in all 16
mid-map deaths; 60 s before, ours > 0 in 5. Early ones (min 10-11) are its own mex trips into mid; the late ones
follow an assist/plant at home, then it moves 2-3k forward with curTask t4 = RETREAT (UnitTask.h). Count by arm vs
BARb / WRD: live --arc 6/3, late-1 --arc 1/5, face-1 --face --arc 0/3, face-1 --face 1/6, live no arc (jobs40) 0/1,
jobs-1b 0/3. Suspect: RetreatTask's com-evade (a held commander steps 400 to the lowest threat every 5 s on a threat
map that reads ~0 almost everywhere). Asked for com-evade/retreat-dest/heal-post counts before each death, and in
the --nomodel control.
com_evade.py (Mac), 12 BARb games per arm, games with any com-evade / evade lines / com-retreat-hold lines: ctrl
--nomodel 1/12, 9, 5; live no arc (jobs40) 3/12, 22, 15; live --arc (late40) 10/12, 39, 113; late-1 --arc 6/12, 24,
17. heal-post 0 everywhere. Evade isn't the whole move: s99/s100 were held (30+ hold lines, no evade) and s96/s97
died 1.1-1.5k past their last evade point. Reading: with the model the army leaves the commander exposed, so it
retreats far more; then the retreat goes out. Stock endPos = repairer, else GetClosestHaven (nearest factory, can
be a forward plant: s99 built corvp at 4272,5444, died at 4099,5789). Asked for distances death->nearest factory,
death->start, start->factory, and any repairer.
Correction (Mac): s97 had no evade in the 120 s, so only s96 died past its last evade point (~1.5k); s95 died ~800
from its last evade.
com_haven.py (Mac): the haven idea is wrong. Where a factory was alive at the death it was the home one (<= 1.5k
from start) and the commander died farther out, so GetClosestHaven would have pulled it home. In 6 of 16 every
factory had died first (s96: shltx, vp, ap, alab, aap at m31.5-32.5, commander m33.6); s99's corvp was an
unfinished plant exec after the base fell. So the late deaths follow a lost base, and the early ones (m10-11) are
lone mex trips with no army near. No commander-code change. The gap is the army's: it doesn't hold home or cover
the expansions (commander retreat/evade in 10/12 games with live --arc vs 1/12 under --nomodel). Closed.

03:20 (local 00:20) check. He is in a sixth live game (Talus since 23:42): recorders wait, 0 headless engines, free
commit 27.3 GB. His demos 26 of 447, public 498. The Mac pulled at 00:17. Mac: wide 40k training (ends ~02:45, then
fixed-set scores and the timing game, ~03:15). Self-review: the commander investigation closed with no code change
(the gap is the army not holding home); late-1 not adopted. No code changed this hour.

00:55 he stopped playing (8 games tonight); his_game_running now false, the recorders resume on their next poll.
His "games seemed easier" (scratchpad mp_eco.py over the install's v0.5.17 logs and runtime/mpgames back to
v0.5.13, games grouped by log mtime, so seat counts are partial): median seat metal income at minute 15 tonight
50, 50, 60, 221, 212 (SpeedMetal at +100 aside) vs 35-153 for v0.5.13-16; air 32-43% of units ordered vs 17-54%;
T3 0-3% of units in nearly every game since 11-15. Nothing points to a v0.5.17 regression.
His 11-22: the release is easier than it should be mainly for lack of T3, but the army net comes first. T3 waits.

04:20 (local 01:20) check. He stopped at 00:55; the recorders resumed: 3 headless engines (limit 4), free commit
23.5 GB. His demos 31 of 447 recorded (+5 since he stopped), public 500; build loop 1,282 public games with datasets,
the Mac pulling new ones (00:17-01:17). Mac: wide 40k training, results ~03:15. No code changed this hour.

05:20 (local 02:20) check. 3 headless engines (limit 4), free commit 30.8 GB, no Tracebacks in the recorder, demo or build-loop logs. His demos 35 recorded (+4 this hour), public 508 (+8); build loop 1,286 public games with datasets (+4). Mac: wide 40k training, results ~03:15. No code changed this hour.

05:40 wide 40k (Mac, 256/96/4, from scratch, 9,830 s at 4.1 st/s). Held-out, 60 games x 40, f_cell / f_act / kind / cell / act: live 5.389/.1400/.1232/5.135/.2354; late-1 5.335/.1375/.1202/5.086/.2331; w40-40k 5.350/.1227/.1175/5.241/.2141 (32k 5.408, still falling). Ties live on f_cell, 12% better on f_act, better kind; unit cell 2% worse (force heads are what play under --forces). Next: the 15-min timing game on seed 89 (compute mean and click rate; fbias re-matched to live's click rate if off by >15%), then gate 3 vs live, both --arc.
06:00 timing game (seed 89 vs BARb, speed 4, both --arc): 1.00 steps between decisions for both, nothing skipped; compute per decision live 0.012-0.023 s, w40-40k 0.015-0.031 s (1.3-1.4x). Fast enough. Gate 3 sent: w40-40k vs live, fbias matched to live's click rate if off by >15%.
06:20 click rate on the timing game, per-step p over minutes 0-12: live 0.0353 at fbias 0.39, w40 0.0605 (1.71x; peak .113-.158 at m3-5 vs live .029-.097). Matched by shift: w40 at fbias -0.19 (rough, from per-minute means). Gate 3 running on the Mac (paired-wide40.log): live --arc 0.39 vs w40-40k --arc -0.19, seeds 89-100, BARb and WRD, 40 min, JOBS 3.

06:20 (local 03:20) check. 3 headless engines, free commit 31.1 GB, no Tracebacks. His demos 40 recorded (+5), public 516 (+8), build loop 1,292 with datasets (+6). Mac: gate 3 w40-40k vs live running since 02:55. Self-review: fbias 0.39 was set to match the players' held-out click rate, while w40's -0.19 matches live's in-game rate, so the gate is a same-rate comparison. Asked the Mac for w40's players-matched bias on the fixed held-out set after the gate; if far from -0.19 it is the next arm. No code changed.
07:20 (local 04:20) check. 3 headless engines, free commit 32.8 GB, no Tracebacks. His demos 42 recorded (+2), public 531 (+15), build loop 1,307 with datasets (+15). Mac: gate 3 w40-40k vs live still running (started 02:55). No code changed.
08:00 gate 3 w40-40k (fbias -0.19) vs live (0.39), both --arc, seeds 89-100, 40 min. BARb: up 10 / down 2, W/T/L 1/9/2 vs 0/3/9, cmd deaths 2 vs 9, trade 0.75 vs 0.29, passes. WRD: up 5 / down 7, 0/0/12 both, trade 0.83 vs 0.95, fails. vs --nomodel ctrl: BARb up 4 / down 7, WRD up 1 / down 9, both models well behind stock fight logic. In-game p/step w40 .022/.038 vs live .041/.086 (BARb/WRD): the seed-89 rate match didn't hold. fbias_fit.py on the fixed held-out set (17,306 force-steps): players click 0.0854; live 0.0366 at 0.39 (players-matched bias 1.64), w40 0.0386 at 0 (matched 1.37). 0.39 was fit on the old recordings; both models click under half the players' rate. Next arm (one change): w40 at fbias 1.37, paired with this gate's games on the same seeds. Then continue w40 from 40k, 20k more steps.
08:20 (local 05:20) check. 2 headless engines, free commit 42.3 GB, no Tracebacks. His demos 51 recorded (+9), public 537 (+6), build loop 1,313 with datasets (+6). Mac: paired-wideb40 (w40 at fbias 1.37) running, then w40 continued to 60k. No code changed.

13:25 (local 10:25) check, catching up the missed hours. 3 headless engines, his game off, free commit 32.8 GB, no Tracebacks. His demos 78 recorded, public 548, build loop 1,324 with datasets.
Arm w40 at fbias 1.37 (paired-wideb40), seeds 89-100, 40 min. BARb: vs w40 -0.19 up 3 / down 8, vs live 9/3, vs ctrl 3/8; W/T/L 0/7/5; cmd deaths 5; trade 0.71. WRD: vs w40 -0.19 8/4, vs live 5/6, vs ctrl 3/9; 0/0/12. In game it clicked .20-.66 a step (players' held-out 0.085; -0.19 arm .013-.073), idle-force p .13-.20. Held-out calibration doesn't carry to game states: our forces in game are not distributed like the players' (more of them idle), a gap of its own. 1.37 dropped; -0.19 stays.
w40 continued to 60k (20k steps, fresh OneCycle, 5,447 s). Fixed set redrawn (the roots grew), f_cell / f_act / kind / cell / act: w40-40k 5.254/.1143/.1755/5.196/.1941; w60-60k 5.099/.1123/.1840/5.032/.1921; live 5.261/.1334/.1771/5.065/.2158. w60 better on f_cell (2.9%), f_act and now unit cell; kind 4.8% worse. Next (one change, the checkpoint): gate w60-60k at -0.19, paired with paired-wide40's games.
13:45 w60's kind loss is two games, not broad: fixed set 59 recordings + 1 replay-orders game; per game w60 worse on 30, better on 30; Eternal Consequence 11-04 (2.41 -> 2.70) and SpeedMetal 11-11 (1.58 -> 1.91) carry it, both w40's worst already; without them w60 is .002 better. f_cell and act better on both roots. Gate w60-60k at -0.19 running on the Mac (paired-w60.log). The fixed set has only 1 replay-orders game: too few to judge the public/his-demo root.
14:05 fixed-set redraw: the held_out name hash holds only 6 of 69 replay-orders games (recordings 128 of 1,325), so 30 per root would score models on games they trained on. Chosen: all 6 held replay-orders games at 200 examples each + 30 recordings games at 40, in a list file, reported per root (6 games: only a large difference there means anything). Open: a split holding out more replay-orders games, adopted only at the next from-scratch training.
14:20 (local 11:20) check. 3 headless engines, his game off, free commit 35.2 GB, no Tracebacks. His demos 81 recorded (+3), public 550 (+2), build loop 1,326 with datasets. Mac: gate w60-60k at -0.19 running (paired-w60.log). No code changed.
14:40 gate w60-60k at -0.19 (paired-w60.log). BARb: 0/4/8 (w40 1/9/2, live 0/3/9, ctrl 6/4/2); vs w40 up 0 / down 10, vs live 6/6, vs ctrl 2/10; cmd deaths 8; trade 0.35. WRD: 0/1/11; vs w40 5/4, vs live 4/6, vs ctrl 2/10; cmd 11; trade 0.93. In game w60 clicked at 55-60% of w40's rate at the same bias (game mean BARb .0126 vs .0219), under half from minute 10, so the gate mixes weights with click rate. Across arms vs BARb the best is w40 -0.19 (.022 a step); both higher (live .04, w40 1.37 .27) and lower (w60 .013) did worse. Better held-out imitation scores did not give better games. Next: w60 at the bias matching w40 -0.19's in-game rate (fit on all 24 paired-w60 games), gated. Best arm for a watch game: w40-40k at -0.19.
15:00 heldout-fixed-1 (runtime/armynet/heldout-fixed-1.json on the Mac: 30 of 128 held recordings games x 40 steps + all 6 held replay-orders games x 200, the sampled steps listed; scorer heldout_fixed.py). Recordings, live / w40 / w60: f_cell 5.182/5.153/4.998, f_act .1277/.1087/.1051, kind .1312/.1378/.1286, cell 4.882/4.962/4.853. Replay-orders (6 games): f_cell 4.676/4.273/3.990, f_act .0739/.0765/.0723, kind .4475/.4230/.4125. w60 best on every measure on both roots; in game it lost to w40 (at a lower click rate). The rate-matched w60 arm decides whether the weights or the rate cost it.
15:20 rate fit from all 24 paired-w60 games (shift_fit.py): one logit shift +0.538 for both opponents, so w60 at fbias +0.35 (BARb .0212 vs target .0219, WRD .0391 vs .0378). Gate running on the Mac: w60-60k at 0.35, paired-w60b.log, paired with w40 -0.19, live, w60 -0.19 and ctrl. w40-40k (sha256 be8a2cac...) being sent in parts for a watch game on the PC.
15:55 (local) w40-40k fetched in 4 parts and joined: runtime/armynet/cap-wide40/model-040000.pt, sha256 be8a2cac... equal to the Mac's. Live watch game launched for him: watch.py --model cap-wide40/model-040000.pt --forces --learned --rally --arc --fbias -0.19, seed 89, 40 min (out G:/bar-ai-archive/watch-w40.out).
16:20 (local) his read of the w40-40k watch game (seed 89): the biggest improvement will come from why our units sit idle; many idle with no good reason. Ranked first. serve.log of this game (matches/watch-armynet-engine-20261122-115318-41556): forces idle 60 s+ are almost all single units (size 1.0-1.2), 0-31% of forces a minute, and get click p .003-.021, below every other group (all forces .004-.049, size>=4 .020-.154). Every order kind logged is kind 1.
16:45 (local 12:45) force dump (serve.py --dumpforces, watch.py passes it; instrument only, no play change: every 5 s each unit's force, task, place, time since its last order, its force's click p). Headless game w40-40k at -0.19, seed 89, speed 4, matches/watch-armynet-engine-20261122-120205-47472, scratchpad force_split.py. 56% of clumps of 3+ units standing within 400 of each other are cut into 2+ forces (118 clumps, 66 cut): typically one force of 7-11 plus 1-2 units holding their own task (a separate order within the last 120 s), each a force of 1 that is clicked at p .0065 a step, so it stays when the main force moves. And big forces sit too: 20% of unit-dumps are 30 s+ since the last order (407 of 1,991; 11 never ordered), most in forces of 9-17 at minutes 6-12, click p .014 a step. Two causes to measure against players: (a) a straggler holding its own one-unit task is scored alone, while a player's box drag takes it with the force beside it; (b) idle big forces clicked too rarely.
17:05 his read, cont.: in big fights some of our units stand "afk" nearby; the opposing AI is constantly moving and re-deciding, and slow decisions can't keep up. Decision speed is not the limit (a decision every step, 0.03 s compute); the model chooses not to act. players_idle.py (scratchpad), 2 held-out games vs the dump game: clumps cut into 2+ forces players 18% / ours 60%; army unit-samples standing with no order 30 s+ players 4.4% / ours 16.0%, 60 s+ 1.6% / 4.2%; players' cut-clump neighbours ride along with the big force's click 0 of 10, so our split groups come from our own one-unit orders. 20-game run going.
17:20 correction: over 20 held-out player games the plain idle share is not ours alone: clumps cut into 2+ forces players 33% / ours 60%; standing with no order 30 s+ players 17.6% / ours 16.0%, 60 s+ 9.7% / 4.2% (players park units at home and on spots). The 2-game "3-4x" was wrong. His complaint is idle while a fight is near, so the measure is now that: a unit not fighting itself, an own unit within 1,500 hurt in the last 5 s or losses within 800 in 10 s (tok 39, 41), standing, no order 10 s+ / 30 s+. Dump extended with tok 39 and 41; dump game seed 90 then the 20-game comparison running.
17:30 his second case: a raiding force in position that sits still for a minute: time is the opportunity, the longer it waits the stronger they get and the weaker the raid. Measure to add beside the fight one: units in the forward part of the map (nearer their start than ours), not fighting, standing with no order 10 s+ / 30 s+, players vs ours.
17:50 fight measure, first read (20 held-out player games, any size, vs one dump game seed 90): not fighting with an own unit hurt within 1,500: standing players 19.0% / ours 14.3%, standing no order 10 s+ 16.5% / 13.3%, 30 s+ 10.4% / 8.2%; clumps cut players 33% / ours 33% this game (60% seed 89). Forward past the middle, not fighting, standing no order 10 s+ players 27.8%, 30 s+ 17.0%, 60 s+ 7.7% (ours pending, seed 91). So this measure does not show what he sees; not trusted yet: the player set mixes team games, "fighting" is only being hurt (a unit firing unhurt counts as idle), and ours is one game of 938 samples. Next: duels only (running), then check flagged moments by eye before believing either side.
18:20 afk.py (scratchpad): one measure for players and our recorded games (ours built BARAI_ALL_TEAMS=1 into G:/bar-ai-archive/own-games, not a training root), ground army every 5 s from minute 3, engaged = an enemy ground unit or commander within its range + 150. The watched game (seed 89), side 0: engaged 19.4%; near a fight (an engaged friend within 1,500) and not in it 26.4% of unit-samples, of them standing 23.0%, no order 10 s+ 21.5%, 30 s+ 16.6%; forward past the middle with no enemy within 1,500, standing no order 10 s+ 36.3%, 30 s+ 28.6%, 60 s+ 16.0%. Players' duels (60 held-out) running; the three headless dump games being recorded and built. Hourly (local 12:20): 4 headless engines (3 recorders + 1 recording), his game off, free commit 27.0 GB, no Tracebacks; his demos 85, public 553, datasets 1,328. Changed: serve.py/watch.py --dumpforces (instrument only, off by default; no play change).
18:30 afk.py players, 60 held-out duels (509,807 unit-samples) vs ours (seed 89, 2,789): engaged 13.0% / 19.4%; near a fight and not in it 18.3% / 26.4% of all; of those standing 17.9% / 23.0%, no order 10 s+ 14.9% / 21.5%, 30 s+ 8.8% / 16.6% (1.9x). Forward with no enemy within 1,500, standing no order 10 s+ 26.6% / 36.3%, 30 s+ 18.6% / 28.6%, 60 s+ 9.6% / 16.0% (1.7x). The long waits are where we differ; players stand too, briefly. One game of ours: three more being built.
19:10 afk.py over 4 of our games (seed 89 watched + 89/90/91 headless, 9,156 unit-samples) vs 60 player duels: near a fight and not in it 28.7% / 18.3% of all; of those standing no order 10 s+ 24.8% / 14.9%, 30 s+ 14.9% / 8.8%; forward with no enemy within 1,500 standing no order 10 s+ 37.4% / 26.6%, 30 s+ 29.1% / 18.6%, 60 s+ 15.6% / 9.6%. Confirmed, ~1.6-1.7x.
Why, per state (players_hazard.py on 20 duels, model_hazard.py on 2 dumps; per-step click chance by force's median time since last order): no fight near, players / model 0-5 s .099/.146, 5-10 .023/.018, 10-30 .015/.008, 30-60 .007/.005, 60-120 .0035/.0048, 120+ .0055/.0037; a fight near and the force unhurt, 0-5 .034/.020, 10-30 .0035/.0040, 30-60 .0010/.0025. The model's click chance in each state is about the players'. Order kinds match too (kinds.py: players 97% move per order, ours 98%). So the model imitates how often players click an idle force, and players' average idle force near a fight is often idle on purpose (artillery, reserves, held lines) -- imitation cannot tell the purposeful wait from ours. Our forces also end up near-but-out-of fights more often (28.7% vs 18.3%), a placement gap. The fix has to come from outcome, not imitation: our own games labelled (the existing _wake_idle relabel extended to standing 10 s+ with a fight within 1,500, and forward waits), or the dec_score credit for the click.
19:40 afk wake built (measure: afk.py near-fight standing no order 10 s+, ours 24.8% vs players 14.9%; then gate 3). replay_dataset.py: afk_m per decision, over the order's span on the 10-s grid, the group standing (centre under 100) and trading nothing while a unit of its side (army, air, commander) within 1,500 dealt or took damage in those 10 s (fighters cached per team and 10 s); a separate array, so players' order ratings are unchanged. data.py: our own games' _wake_idle also labels a force clicked from 10 s into an order with afk_m > 0. Rebuilt the watched game (15 s; G:/bar-ai-archive/own-games-afk): afk_m > 0 on 41 of 13,133 decisions, woken force-steps 6.15% -> 13.63% (wake_check.py). Sent to the Mac as afk-1 (replay_dataset a4e0963b, data 2978bf0f, afk.py 8d3e0167). Plan: record+build its gate games as own games; fine-tune w40-40k with --own --own-share 0.25, arm afk1 (new data.py) and arm idle1 (afk rule off); afk.py and gate 3 on each.
19:55 gate w60-60k at fbias 0.35 (paired-w60b): the rate overshot (game mean BARb .0332 vs target .0219, WRD .0679 vs .0378; the per-minute shift underestimates a per-step one). vs BARb 1/7/4; vs w40 up 5 / down 5, vs live 10/1, vs w60 -0.19 9/2, vs ctrl 4/8; cmd deaths 4; trade 0.80. vs WRD 0/0/12; vs w40 3/7, vs ctrl 0/10. w60 not shown better than w40 at either rate; w40-40k stays the base for afk-1. Mac: afk-1 fetched (shas match), recording 96 gate games as own games.
20:10 his idea (11-22): the arena (dev_arena.lua: identical armies spawned for both sides, mirrored, rounds repeat, sides swap) as a fight-only test and training ground -- raw army-vs-army fighting, aim the best damage efficiency; then run it against all the AIs and train the nets in those games on repeat. Built: watch.py --mod k=v passes modoptions (dev_arena=1, dev_arena_pure=1, dev_arena_random=1). Smoke test running: w40-40k at -0.19 vs our AI's own fight logic, seed 92, 8 min, speed 4, scored by tools/arena.py. Loop to build if it works: per round both sides' orders recorded as own games (every side learns, rated by outcome), opponents BARb, WRDistilled, our AI's own army and earlier models; fine-tune, re-measure by arena efficiency (metal killed / lost per round, spawn-swapped) against the fixed opponents, gate 3 now and then for full games.
20:20 (local 13:20) check. 3 headless engines + the arena smoke starting, his game off, free commit 35.7 GB, no Tracebacks (the build loop now runs the afk_m replay_dataset; datasets 1,330, no errors). His demos 89, public 555. Changed this hour: replay_dataset afk_m + data.py afk wake (own games only; measure afk.py then gate 3, on the Mac), watch.py --mod passthrough (arena). Mac: recording 96 gate games as own games.
20:40 arena smoke (w40-40k -0.19 vs our AI's own fight logic, pure, random rosters, seed 92, 8 min; matches/watch-armynet-engine-20261122-132047-39920): works mechanically (the model takes the spawned units and orders them), but only 4 rounds in 8 min, all ended "apart" (mutual disengagement, arena.py counts draws): round 1 alive 12 vs 33 (metal 26,400 vs 45,930), round 2 5 vs 15, round 3 (a Volcano roster) 180 frames. Random rosters drew artillery and a super-gun, too noisy for a first read. In the arena the model's per-step click p ran .28-.44 (vs ~.02 in games: everything reads "at home", out of the training distribution); compute 0.12 s, gap 1.5. Next: fixed T1 roster armpw*12,armham*6,armrock*6,armwar*4, Armada, 10 min, model vs a --nomodel control (our AI on both sides), arena.py.
20:55 arena, fixed roster armpw*12,armham*6,armrock*6,armwar*4 (3,228 metal a side), Armada, pure, seed 93, 10 min: every round ran to the 3-min cap (5,400 frames) with both sides alive, 3 rounds a game. Metal lost per round (side 0 / side 1): model vs our AI's fight logic 648/162, 1,838/864, 1,768/1,690 = 4,254 / 2,716, killed/lost 0.64; control (our AI both sides) 942/1,190, 802/974, 1,550/1,340 = 3,294 / 3,504, 1.06. A clear fight-only signal: the model trades at about 0.6 of our AI's fight logic. arena.py's win/draw view reads it all as draws; the measure is metal killed / lost per round, spawn-swapped.
21:05 Mac step 1: 96 gate games recorded and built as own games (BARAI_ALL_TEAMS=1, runtime/armynet/own/own-games/), 3.7 s wall per game-minute, 4 at a time (41 min for the batch). afk_m>0 decisions per game ours 59.5 (0.3% of 22,845) / theirs 42.6; a flagged decision wakes every step of its standing span, so the dose is counted in woken force-steps (asked: idle-only vs afk on 3-4 games) before step 2 (afk1, then idle1).
21:30 afk label fixed (the Mac's dose: afk-1 took own-game force-steps to ~20% clicked, players 8.5%): afk-1 woke every step from 10 s into a flagged order to its span end, even when the stand beside the fight was one 10-s window of it. afk-2: replay_dataset saves afk_w (first and last frame of the stand on the 10-s grid), data.py wakes only from 10 s into the stand to its end. Dose on 3 rebuilt games (wake_check.py, side 0, idle rule alone / with afk): 6.15 -> 7.44%, 9.08 -> 13.19%, 6.26 -> 8.75%. Sent as afk-2; afk1 stopped, the 96 to be rebuilt.
21:20 (local 14:20) check. 2 headless engines (+1 arena game vs BARb:stable:hard, same fixed roster, 16 min), his game off, free commit 39.3 GB, no Tracebacks. His demos 92, public 557, datasets 1,332. Changed: afk-2 (afk_w window; labels only, own games only; serve's inputs untouched). Mac: idle1 training (w40-40k + own games, afk off); afk-2 rebuild of the 96 into own-afk2/ next, dose re-count, then afk1.
21:45 arena vs BARb:stable:hard (same roster, seed 94, 16 min, 5 rounds; matches/watch-armynet-engine-20261122-142054-1252): metal lost ours / theirs 2,968/1,970, 54/54, 648/432, 648/0, 648/794 = 4,966 / 3,250, killed/lost 0.65 (vs our AI's fight logic 0.64). Rounds 3-5 we lost exactly 648 each = the 12 Pawns (54 each), round 4 for nothing: likely the fastest units run ahead of the force and die alone. To check by the round's orders.
22:20 Pawn run-ahead hypothesis refuted (arena dump vs BARb, seed 94, matches/watch-armynet-engine-20261122-143621-20488; pawn_runs.py): Pawns stood a median 63 from their force's slow members' centre (p90 214), and all 28 that died were within 300 of a slow unit of the same force. Round 2 was a full wipe (0 vs 10 alive). The real structural gap (click_cover.py, 15 held-out duels): in a fight, a player's click on a force of 10+ orders a median 62% of its members (mean 59%, all of them only 18% of clicks); forces of 8: 75%, 23%. Out of a fight, 10+: 70%, 32%. data._force_labels marks the force clicked when it holds most of a click, and serve moves every member on a click: the model cannot split a force in a fight (send part, hold part, pull back the hurt) the way players do every few seconds. Fix: a per-member head, which members a force's click takes (label: the members the player ordered), used in serve to pick the click's members.
22:50 member head built (measure: held-out f_member_acc vs take-all, arena trade vs w40, gate 3). model.py f_member (MLP on [member h, force fh]); data.py per-unit label f_member (1 ordered by the click, 0 left by it, -1 no label); train.py BCE weighted by the click's rating, held-out f_member_acc / f_member_all, ArmyNet built from arch_of(--init); serve.py samples a click's members by the head when the checkpoint has it (else every member, as before), logs "minute N members:". PC smoke 30 steps from w40 (fresh f_member only): f_member_acc 0.714 vs take-all 0.668; a 4-min arena game took 0.74-0.78 of a force per click. Sent as member-1; on the Mac after idle1 and afk1 as arm mem1 (afk1 + member head).
23:20 idle1 (Mac: w40-40k + 96 own games at --own-share 0.25, late-1 data.py, 10k steps, 3,115 s). heldout-fixed-1, w40 -> idle1, all 36: f_cell 5.006 -> 4.912, f_act .1033 -> .1035, kind .1853 -> .1816; recordings f_cell 5.153 -> 5.084; replay-orders f_cell 4.273 -> 4.054. Own games cost nothing on players' held-out. Next: afk-2 rebuild + dose, afk1, mem1, then all three arms' games together (afk.py, arena x2 opponents x3 seeds, gate 3).
23:40 afk-2 dose on the Mac's 96 rebuilt own games (no wake / idle alone / with afk, side 0): 1.99/2.68/6.97%, 5.27/14.02/14.92%, 2.46/6.88/11.51%, 5.09/5.09/9.55% (afk-1 had added 7-19 points; afk-2 adds 1-5). afk1 training (idle1's recipe + afk-2 data.py, own-afk2 root).
22:20 (local 15:20) check. 3 headless engines, his game off, free commit 33.9 GB, no Tracebacks. His demos 102 (+10), public 558, datasets 1,334. Changed this hour: member head (model/data/train/serve; serve's inputs untouched, the head is an extra output read only by a checkpoint that has it; measure f_member_acc, arena trade, gate 3). Mac: afk1 training, then mem1; then arena for all three arms, gate 3 for the best.
23:55 he raised T3 (ruling of 11-22 morning lifted): humans expect our air, buy AA, then their T3 kills us after our air takes one or two of them. Plus the switch (todo/team-strategies.md, his 11-22). T3 work on the PC beside the army net on the Mac. First facts: his last game (Talus, 11-22 00:23 log): 3 of 6 seats ordered T3, first at 16.8-20.9 min, gantries logged "facqueue idle ... no-candidate" 31 times; recording his last 4 online demos to count what both sides actually finished.
00:15 t3_compare.py (scratchpad; finished units from his recorded online games, by kind). Forge 8v8 (11-21 16:22 local): AI seats finished 1,355k metal, humans 2,781k (2.05x); AI T3 19% (257k), humans 28% (~780k, 3x ours); AI's first T3 units at min 19.0-23.4 on 5 of 8 seats, humans' at 27.0-32.6 on 7 of 8. In this game we were not late to T3; we were half their economy, so their T3 was 3x ours. The last 4 games being recorded.
00:25 his read on the 2x economy gap: humans pack buildings into efficient patterns, no small gaps in the build grid; we spread out and leave unusable gaps ("not even halfway there"). Next: measure packing, humans vs our seats, from the same recordings (building footprints from the game files; gap and density per team), then the placement work (ai-placement; tools/tiling.py exists for our side).
00:50 tools/base_audit.py (new; per seat, from a replay recording: finished metal by kind, first T3, and at minutes 20/30 the nearest-building gap, open ground in the main base, energy and conversion per build square). Forge 8v8 (11-21): best human seat 669k finished vs our best 273k (2.45x; side medians 336k / 179k). At minute 30: humans flush 71-94% of buildings, ours 32-62%; small 1-2 square gaps humans 0-17% (most 0-5%), ours 10-21%; open ground in the main base humans 35-75% (median ~47%), ours 61-80%; energy per square humans 5.8-74 (best seats 40-74, advanced fusions), ours 0.8-55 (most under 11, advanced solars). His read holds in this game on all three: gaps, open ground, land value. The last 4 online games still recording.
01:05 his point: no off-by-one placements at all; one building a square off makes every neighbour compensate, and even 10% off ripples into a lot of unused ground. tools/tiling.py on his last game's seats (Talus, apex-t10..13.log): ALIGNED (nearest same-def kin a whole pitch off) 67%, 87%, 75%, 78%; PHASE (share of a def on its dominant lattice residue) 48%, 60%, 52%, 60%; off-lattice placements 61, 6, 47, 21; foreign-def edge gaps of 1-2 squares 46, 7, 32, 45 per seat. So 13-33% of buildings miss their kin's lattice and 40-52% sit off their def's main phase: clusters that can never grow into each other, his ripple, at 2-5x the share he calls too much.
01:10 afk1 (Mac) on heldout-fixed-1, w40 / idle1 / afk1: f_cell 5.006/4.912/4.903, f_act .1033/.1035/.1030; level with idle1 on players' held-out, as intended. mem1 training; then click check, arena (30 games: 4 models + control x 2 opponents x 3 seeds), numbers before any gate.
01:30 placement read (cpp BuilderTask.cpp, the build-site search): two rules mixed. First apex_flush_place (his 10-18 "build up down left right off one of the existing types"): candidates flush against one of our buildings' edges, aligned to that building's corner, the nearest to the ask wins (FLUSH_PROBES under FLUSH_REACH); then the def's own lattice rings; then the wide search snapped back (else "off-lattice": 61 a seat). Off-lattice misses of his last game: 90 of 130 are nano turrets, and 96 of 130 sit exactly one build square off (residue 16). The flush pick takes the nearest flush slot with no look at what it does to the ground around it: flush on one side, a 1-2 square sliver on another, and the next building of that def a square off its kin. Humans fill concavities (flush on two sides). Plan: score the flush candidates by contact (edge length shared with our buildings) and refuse slivers (a 1-2 square gap to any building), candidates also from two buildings' corners (the L-shaped corner), distance to the ask as the tie-break. Measure: base_audit flush / gap1-2 / open ground and tiling, paired games before/after, plus metal income at 20 min.
01:45 his practice: grid on; extractors placed in a third of his larger grid cell so the advanced energy converters later tile the rest of the area exactly -- planning, from the first minutes, for the buildings that come much later. Footprints (build squares): mex/moho 4x4, adv converter 4x4, adv solar 4x4, converter 3x3, wind 3x3, nano 3x3, solar 5x5, fusion 6x5, adv fusion 6x6, lab 6x6. So the placement fix has two layers: (1) now, contact scoring with no slivers (no off-by-one); (2) the plan: the base laid out for its end state (blocks for advanced fusions and advanced converters, extractors and early solars/winds placed so their ground frees into those blocks), the cheap early buildings placed inside that plan rather than wherever is nearest.
01:55 his module: a 12x12 block, which nine 4x4s (extractor, moho, adv converter, adv solar) fill exactly if the layout is not spoiled. 12 is also 16 3x3s (wind, converter, nano) and 4 6x6s (adv fusion, lab); 5x5 solar and 6x5 fusion do not divide it. Our per-def lattices are phased from the map corner, so 3-, 4- and 6-pitch lattices already meet every 12 squares; what spoils it: (a) extractors sit wherever the spot puts them, off the 4-lattice, and the flush rule then lines converters up on the extractor, a square off everything else -- his exact point; (b) flush placement off the lattice in general; (c) 5x5 solars and 6x5 fusions in the core. Fix order: flush only onto lattice cells (contact score, no slivers); extractors shifted on their spot onto the 4-lattice when the extraction cost is small (measure the cost); then the 12-block plan.
02:30 base_audit on his two newest games. Talus 7v7 (39 min): human seat 2 finished 1,505k (50% T3, first T3 28.9; at min 30 flush 98%, gaps 1%, open ground 33%, 89 E/sq) against our best 725k (open 79%, 19.6 E/sq); side medians human 278k / AI 387k -- his "one human goes crazy powerful" exactly. SpeedMetal 3v3 (22 min): humans 1,217k (60% T3, first T3 at 14.8 min) and 1,080k (80% air) against our best 483k; our open ground 83-87% against 44-74%. Across all three games our seats' main bases are 75-90% open ground; the best humans' 33-47%. New placement (apex_flush_place=2) built into the armynet lane DLL, deployed; first eco watch game for him running (Comet Catcher vs NullAI, eco only, +50, 10x).
03:20 his +0 eco watch: the grid decision looks to be working; spam still made (~2k metal) in the eco version: SpamLineDef (the first T1 land lab makes Fleas once a T2 land plant stands) never checked EcoOnly; now returns null in eco-only (production.as; deploy after his game). His next ask: land-value reclaim by site, "if I remove these 9 con turrets I can fit one more AFUS here". Today RetireGain prices each building alone, its successor's upside scaled by the local crowd (75-90% open ground reads as no crowd), so no single occupant's retirement pays and the core keeps its T1 eco. To build: a replace want that prices a whole footprint site -- the big def's yield there minus the occupants' output, plus their refund, against the same def on the nearest open lattice site -- and claims every occupant and the site together.
03:45 his +0 eco watch (ecotest settings, Comet Catcher vs NullAI, seed 8, new placement with near-first tiers; matches/eco-watch-pack0-1122): metal produced per s m10 71, m14 192, m16 343, m18 456, m20 639, m22 780, m24 933 -- under his 750 target at 20 (his own 869). The +50 watch (seed 7): m20 1,340. His next ask: lanes kept where not needed; a street matters only for a ground plant that must get out of the base, and an air plant needs none -- removing them packs much denser. Lanes today: a fixed street grid (LANE_PITCH 720, both axes, forward of the anchor, half-width from the widest hull fielded), applied in reserve.as/spot.as/grid.as/nanopack.as and C++ LatticePoint/IsInBaseLane; ground plants' exits are separately kept by C++ KeepsExits and the script's doorway test.
04:30 built and deployed in the armynet lane (smoke ok): apex_streets 2 (his 11-22: a street only for a ground plant that must get out; block-aligned so it does not put the blocks beside it off by one): script grid.as LanePitch 768 (4 blocks) / LaneOrigin = the anchor snapped to a block centre / LaneHalf whole blocks (96 per half) / StreetNeeded (forward of one of our PC_LAND plants, within a pitch of its column) / InStreet used by reserve, spot and nanopack; the bands keep every column under mode 2; C++ CircuitAI::StreetNeededAt gates LatticePoint's lane push and IsInBaseLane (FactoryManager::GroundPlantPositions: plants with a mobile non-flying build option); published via SetBaseGrid(LaneOrigin, ..., LanePitch). Mode 1 identical to before (origin = anchor, pitch 720, StreetNeeded true). Spam off in eco-only (SpamLineDef). dev_tunables gadget redeployed (apex_streets in NAMES). His watch of the full new layout running (+0 eco, seed 8, flush 2 + streets 2). Then the paired eco A/B: old (1/1) vs new (2/2), same seeds, +0, minutes 16-20 income, base_audit open/gaps on our own recorded games.
05:10 AFUS value plots written (his 11-22 "if i remove these 9 con turrets I can fit in one more AFUS here"), off by default (TUNE_VALUE_PLOT 0, apex_value_plot; dev_tunables NAMES): on the existing plot machinery (plot.as: a reserved site + C++ zone, the occupants eaten by turrets and cons via PlotVictim, LatheSite answering the cleared site first), which until now fired only when an important building fit nowhere (NoteNoRoom). Now LatheSiteRaw also notes a big reactor/converter that found a legal site (NoteValuePlot: that site, its standing BP, the con's BP); the plot scan searches it when no no-room plot waits, scoring each clearable site by ValuePlotNet = (build time at the legal site's BP - at this site's ring BP less the turrets cleared, each plus the con's) x the building's output in metal/s + (ExpectedLossAt legal - here) - the occupants' output until a con rebuilds them (build time / con BP, at most the reclaim horizon); the best positive net becomes a plot (log apex: plot-value ... net= sooner= occLoss=; apex: plot-value-none when none pays). as_scope.py: 0 findings. Not deployed: the eco A/B (old vs new layout, 8 seeds) is running on this lane. Measure: plot-value count and outcome (plot-built), eco income 16-20, base_audit E/sq and open ground.
05:20 his ask: a 40-minute eco game, new layout against the old way. Running: seed 21, +0 ecotest settings, 40 min, old (flush 1, streets 1) and new (flush 2, streets 2), matches/eco-40-1122. His-demo recorder (replay_orders batch, 2 workers) paused for the engine slots; restart after (it skips recorded demos).
05:40 his watch (new layout + w40-40k at -0.19 vs v0.5.17, Comet Catcher, seed 23): "we're just so bad, it's embarrassing ... enemies attacking our base, and we just have an army off to the side, sitting there doing nothing ... a really long way to go". The same failure as the morning's watch, at its worst: the base under attack and the army idle beside it. Every model version so far trails the --nomodel control (stock fight logic) in gate 3; imitation of players has not taught defending. Plan stays outcome-based: own games labelled (afk wake), the arena loop; this game's replay recorded as a test case for the afk measure.
05:50 his plan: v0.5.18 once the eco test against v0.5.17 is done and (maybe) the T3 logic fixed. Steps: (1) eco A/B lane-new vs v0.5.17 itself (ecotest --spec Apex:v0.5.17:standard), +0, paired seeds; (2) T3: why our gantries idle ("facqueue idle ... no-candidate") and why T3 comes late relative to income; (3) layout defaults to 2/2, the old modes deleted once proven; (4) release gate: 12+ games vs v0.5.17 at his settings, vs BARb, contract PASS, a fresh reviewer agent on the diff, stock fight logic (no army model).
06:00 afk.py on his watch vs v0.5.17 (seed 23, own-games/watch-armynet-engine-20261122-170824-26620): engaged 6.4% of ground army unit-samples (players' duels 13.0%, our earlier 4 games 20.1%); near a fight and not in it, standing 31.4% (players 17.9%), standing no order 10 s+ 28.7% (14.9%), 30 s+ 14.6% (8.8%). A test case for the afk1/mem1 arms.
06:30 T3, from his last two online games' logs (t3_seat.py, scratchpad). Talus (7v7): 3 of 6 seats reached T3 (gantry chosen 14.6/15.9/17.7 min, first T3 order 17.4/16.8/20.9); once it stands the gantry takes 79-88% of everything ordered, but it stood idle "no-candidate" 130-180 s on two seats, the army gap reading 0 (prodrank gap median 0): the army target (66 s of economic power) was met, so no unit had positive value. SpeedMetal (3v3, metal map): no T3 at all. Seat 4 asked for the gantry 59 times from 12.6 min and never placed it: 43 site-fail, 47 task-die, lathe-site bp=-1, plot-none cand=55 ground=55 -- every plot candidate failed the ground test, likely the metal field read as reserved spots (PlotReserved) or the street grid. Three causes: (a) the army budget caps T3 production while the economy has more to spend; (b) a big plant cannot be sited on a metal map; (c) half the Talus seats never chose a gantry.
07:20 (local 17:20) check. 3 headless engines (eco A/B 12 of 16 started, the 40-min pair running), his game off, free commit 33.3 GB, no Tracebacks; public 560, datasets 1,336; his-demo recorder paused for the tests (restart after). Changed this hour: nothing deployed (value plots written, waiting for the A/B to end); T3 findings recorded.
07:30 40-min eco pair, seed 21, +0 (matches/eco-40-1122), metal produced per s, old (flush 1, streets 1) / new (2/2): m10 78/74, m12 171/101, m14 263/144, m16 355/194, m20 658/474, m24 1031/830, m30 1574/1314, m36 2513/2014, m40 3587/3013. The new layout is behind from minute 12 on this seed, by ~30% at 20 and ~16% at 40. One seed (noise runs -20%/+6%); the 8-seed A/B decides, but this is a warning, not a win. The AI logs of these concurrent games share the lane's apex-t0.log, so the cause can't be read from them; a diagnostic pair run one at a time, its log kept, comes next.
07:50 his ruling: extra income always goes into more T3 production (rulings.md). Built (not deployed: the eco A/B holds the lane): production.as t3Sink -- a T3 ground line takes RichArmyGapM (the smoothed spare metal flow x the fill window) as its army gap whether or not the bank is spilling, and past the ovfHands guard; prodrank src=t3sink; TUNE_T3_SINK 1 (apex_t3_sink, in dev_tunables NAMES). as_scope 0 findings. Measure: gantry idle lines and T3 share of ordered metal after the gantry stands, paired games vs BARb at +50 (on/off). Next: the metal-map gantry siting (SpeedMetal: plot-none cand=55 ground=55), reproduced locally on SpeedMetal BAR V2.
His question on the draws: each decision, each force draws u ~ U(0,1) and is ordered when u < p (p its click chance this step, ~0.01-0.02); a fair draw, one per force per step (3 a second); at p = 0.015 an idle force waits a median ~15 s for its order. The draws are not the limit; the per-step chance is, and it is the players' rate for that state.
08:00 Mac click check (seed 89 vs BARb, 15 min, one game per arm, -0.19), per-step p over 0-10 min: w40 .0282, idle1 .0122 (-57%), afk1 .0305 (+8%), mem1 .0210 (-26%); mem1 logs members (min 14: 18 clicks, mean share taken .77). Arena smoke on the Mac: w40 vs our AI 0.61 (PC 0.64). Arena batch running (w40, idle1, afk1, mem1, ctrl x seeds 89-91 x our AI/BARb, 30 games). Told it arena click rates are not game rates (arena p .28-.44); re-fit from game seeds.
08:10 mem1 held-out (train eval): f_member_acc .8245 vs take-all .6455 (+.18): the member head predicts which units a player's click takes far better than "all of them"; f_rate model/player .0391/.0444.
08:30 SpeedMetal dropped (his: "a really weird map"). Built serve.py --wake P (his 11-22 "make the random draws situation smarter"): the click head learned a player's per-step chance, a human's attention spread over every group; a force with most members unordered 5 s+, standing (mean speed under 5 elmos/s), while one of our other units within 1,500 is fighting (tok 39 hurt in 5 s, or tok 41 ours lost near it) clicks at least at P a decision (0.34: within about a second); place, kind and shape stay the model's; "minute N wake:" counts it; watch.py passes --wake. Paired test running: w40 -0.19, seeds 31-34 x base/wake 0.34, 20 min vs our AI (runtime/armynet/wake-ab); measure afk.py (near a fight, standing 10 s+) on the recorded games, mobile kill/loss, wake counts.
08:40 his hypothesis: after all the training, the biggest problem may be how we use the army net -- use it more intelligently. The evidence agrees: held-out scores improved model after model (w40 -> w60, idle1, afk1, mem1) while games did not; the click head's per-state chance equals the players'; so the gap sits in serve: (a) attention: the human click rate applied to every force (the --wake test running); (b) churn: a just-ordered force re-clicked at ~2x the players' rate (0-5 s: model .15-.24 vs players .099), damp it; (c) the net as an evaluator, not only an imitator: sample several candidate orders for a force and keep the one the value head rates best (check first that the value head moves with the revealed-order columns 36-38); (d) forces decided one by one with no coordination around one fight. Each measured on the arena (trade) and afk.py, one at a time.
08:55 eco A/B done (8 seeds 11-18, +0 ecotest, matches/eco-ab-1122), mean of m16/m18/m20 metal produced per s, old -> new: 395->392, 348->358, 405->278, 392->456, 501->427, 479->393, 409->460, 448->415; mean 422 -> 397 (-6%), new better on 3 of 8, t ~ -1: no gain, likely a small loss. A clear early signature: at minute 4 the new layout makes 9-10 m/s on 5 of 8 seeds against 18-19 old (the other 3 seeds 18, equal) -- the opening breaks in the new mode. Not made the default. Next: one diagnostic new-mode game alone, its log kept, the first 4 minutes read (refused off-lattice, packed distances, the commander's first builds).
09:05 his call: keep the new layout (he expects its ceiling to be higher); the opening dip still to fix. Deployed the lane scripts: T3 sink (on), value plots (off), spam off in eco, plus the streets/flush script side; gadgets redeployed. The wake test's seed 32 pair straddles this deploy (base-32 before, wake-32 after): rerun base-32. His watch running: always-order (fbias 20, every force clicked every decision; place, kind, shape from the model), new layout, vs v0.5.17, seed 23, Comet Catcher, +50, 10x.
09:30 his watch of always-order (fbias 20, w40, new layout, vs v0.5.17, seed 23): "already obviously much better than before"; still: walks to the top left where there is nothing to do and drifts back to the centre, economy slow next to the opponent's, no straight push, "too much hesitant behavior ... lack of conviction to attack and kill"; asks whether the AI is told "this is what you're currently doing, would you change it?", and then: "our issue is closer to how random our orders are generated ... rely on armynet to generate orders more". Cause found in serve: each order drew a region (back / forward / hold) by the place head's mass, then the best cell in it, and a point-or-line by a draw on the spread head; at every decision that zigzags. Built serve.py --commit A (watch.py passes it): keep the force's current order while the place head's mass around its destination (3x3 cells) is at least A x the mass around its best cell; otherwise order the best cell itself; line or point by spread_p >= 0.5; "commit {kept, changed}" in the forces: line. The model already sees each unit's current command and target (tok 15-23) and time since its last order (35); only serve ignored it. Next watch: fbias 20 + commit 0.5.
09:40 his catch (and he is right that it should have been mine): ground and air forces took one order -- the learned branch never split them (only the old hand branch did), so flyers and tanks were sent as one group at very different speeds. serve.py: before the force heads run, a force's air members become a force of their own (model.forces on the split index; the heads decide it alone). Self-check from now on before a watch: per-force speed spread and class mix in the dump, orders to air vs ground, the commit and wake counters.
09:55 his watch, always-order + commit 0.5 + air split (w40, new layout, vs v0.5.17, seed 23): lost at 13.75 min (gameover, v0.5.17 won); commit kept 3,976 / changed 1,200 over the game. Next serve fix ready: a force with no standing order counts its own place as its current one (no re-send to where it already is).
10:05 Mac arena (old serve, -0.19; trade = their lost / our lost over rounds, seeds 89/90/91): vs our AI w40 0.62, idle1 0.59, afk1 0.52, mem1 0.60, ctrl 0.83; vs BARb w40 0.82, idle1 0.81, afk1 0.91, mem1 0.81, ctrl 3.62 (our AI's own fight logic crushes BARb's in the arena). No arm beats w40 under the old serve. Not gated. Sent serve-2 (commit, air split, wake/dump; serve 6b59af9d): arena re-run with --fbias 20 --commit 0.5 for w40 and mem1 and ctrl, then gate 3 for whichever beats old-serve w40.
10:30 his watch (commit fix, seed 24 vs v0.5.17): "we seem to sort of be winning" but in fights more than half the army is out of range: Centurions in front, Thugs and Rocket bots so far back they only watch. Cause (serve.py arc_slots, his 11-21 range arcs): each unit stepped back by (its range - the shortest) from the model's chosen place, which may itself stand off, so the long-range rows land beyond their range. Fixed: a unit's radius from what it faces is max(front, min(front + step, 0.95 x its range)); counter "arc in range {slots, in_range, in_range_old}" per minute (old = where the previous rule would have put them).
10:40 his read: formations end up 7-8 lines deep, as if purely by unit type -- no concentrated fire. Cause: arc_slots made a row per distinct range step (round(depth / LINE_GAP)). Now at most ARC_ROWS = 3 rows of equal count, cut by wanted depth, each row at the shallowest depth its units want (so all stay in range), one LINE_GAP behind the row before at least, rows wider (unit gap 40 min); counter "arc rows {forces, rows}" per minute. Both formation fixes (range clamp, row cap) in serve.py for the next watch; mirror to the Mac as serve-3.
10:50 T3 sink test inconclusive: 3v3 vs BARb hard on Talus, +50, 35 min, seed 41 (matches/t3sink-1122): sink-on seats chose the gantry at 33.9 and 32.6 min (one never), no T3 unit ordered by 35 min, so the sink never had a gantry to feed; the off game's AI logs were not found in its side-stepped write dir. Here T3 itself comes late (min 33 vs 15-18 in his online games). Needs a longer test (50 min) or a richer setup to measure the sink.
11:00 his read: "our air seems to mostly just act defensively, they aren't trying to attack the enemy base ... we do have a lot of it". Under the model every flyer is a model force; after the air split each gets the force heads' decision alone, and the heads (trained mostly on ground forces' clicks) hold them near home. Built watch.py --keep-air: every flying def (runtime/armynet/air_defs.txt, 119 from the unit files' canfly, constructors aside) goes into dev_armynet_keep, so our AI's own air layer (strikes on their economy) flies them and the model commands the ground army. Measure: air kills of their economy and air metal lost, keep-air vs model air, paired.
11:10 his read: fighters, bombers, gunships and EMP bombers grouped together; group by class/type/def. serve.py: flyers split by def (each air def of a force its own force; an all-air force keeps its index for the first). With --keep-air our AI's air layer flies them anyway (bombers and gunships priced apart in NaDecide, fighters stationed). Mirror serve to the Mac as serve-3 with the formation fixes.
11:25 his conclusion: the biggest problems are in how we use the net; keep iterating there. Self-check game before his watch (seed 25, 14 min, always+commit, dump): decisions every 1.01 steps, 0.064 s; commit kept 9,566 / changed 798; arc units within their range of what they face 818 of 1,457 (56%; the old rule would have had 570, 39%); arc rows 2.1 per formation; no force mixing air with ground or two air defs (after the split). His watch with all of it (+ --keep-air) vs v0.5.17, seed 24. serve-3 staged for the Mac (serve, watch, air_defs.txt).
11:20 (local 18:20) check. 1 headless engine (public follow), his game off, free commit 42.8 GB, no Tracebacks; public 561, datasets 1,337. His-demo recorder restarted (batch, 2 workers). Changed this hour: serve.py formation fixes (range clamp, 3 rows), air split by def, commit own-spot; watch.py --keep-air; each measured on the self-check game and his watch; serve-3 to the Mac for the arena.
11:30 his watch with all serve fixes + keep-air vs v0.5.17 (seed 24): lost at 22.0 min (v0.5.17 won); his earlier seed-24 watch (commit, before the formation fixes) he read as "sort of winning" -- this one ran 22 min.
11:50 his direction: a spread of usage strategies, "a ton of A/B testing, some hill climbing, some annealing", and "dumb luck ... 100,000 potential good options ... some sort of binary search". Built: serve.py --arc-rows, --range-frac, --standoff F (the arc's front no further than F x the shortest armed range from what it faces), a usage line printed at start; watch.py passes them. tools/armynet/usage_search.py: a config = fbias {-0.19, 0.5, 1.5, 20}, commit {0..0.9}, wake {0, .34, .7}, arc, rows 1-4, range share .7-1, standoff {0, .6, .8, .95}, place draw, keep-air (38,400 configs); an evaluation = two 10-min arena games (90-s rounds, fixed roster, pure, sides swapping) at a fresh seed, vs our AI and vs BARb, score = mean log(their lost / ours); successive halving over --n random configs (baseline and current among them), then annealed hill climbing with every 4th evaluation a leader's re-test; ledger runtime/armynet/usage-search/ledger.jsonl. Smoke (2 configs, 3-min rounds): baseline trade self 0.67; current (always+commit+keep-air) self 0.65 -- one game each, noise. His-demo recorder paused again for the engine slots.
12:05 usage search started (8 h; 32 configs halving then hill climbing; 2 evaluations at a time = 4 engines): runtime/armynet/usage-search.out, ledger runtime/armynet/usage-search/ledger.jsonl. Both replay recorders stopped for the slots (public follow and his-demo batch): restart them when the search ends. Smoke (3 evaluations): fbias 1.5 + 1 row 0.83, baseline 0.82, current 0.73 -- single games, noise.
12:15 his ask: run the search on the Mac at the same time. usage_search.py gains --seed0 (Mac 500000, PC 1000); search-1 staged for the Mac (serve c7e4324c, watch 2651fc78, usage_search dd33fe87, air_defs); the Mac runs it after its serve-2/3 arena re-run, same model (w40-40k) so the two ledgers merge.
12:40 Mac arena with serve-3 (--fbias 20 --commit 0.5 --keep-air; 18 games): vs our AI w40 0.50, mem1 0.40, ctrl 0.81; vs BARb w40 0.84, mem1 0.80, ctrl 2.30. Side by side vs our AI / vs BARb: w40 old 0.62/0.82, serve-2 0.60/0.85, serve-3 0.50/0.84. So in the pure arena serve-3 is no better (worse vs our AI); commit kept ~2,780 and changed 10-28 a game: in arena fights it almost never re-targets -- commit 0.5 with the own spot as the current order freezes forces once placed. His watches judged whole games (where the army goes); the arena scores the fight alone. The search spans commit 0-0.9 and fbias; its top configs get whole games before anything is kept. Mac search started (seeds from 500000).
12:20 (local 19:20) check. 4 headless engines (the usage search, 2 evaluations at a time), his game off, free commit 30.9 GB; both replay recorders paused for the search (by choice, not dead). Search: 23 of 32 first-stage evaluations in 45 min, no failures; leader so far (one evaluation) arc off, always-order (fbias 20), commit 0.7, range 0.8, keep-air: self 0.80, BARb 1.04. Changed this hour: usage_search.py darwin engine count (the Mac's run).
12:25 (local 19:25) search update: 25 of 32 first-stage evaluations, no failures; leader (once) no arcs + always-order + commit 0.7 + wake .34 + keep-air x0.91; baseline x0.72, current x0.78 (once each). Mac search starting.
13:00 two more usage settings, his ideas: --arc-inrange (arcs whose front stands within RANGE_FRAC of the shortest armed range and no row pushed past its units' range -- rows share an arc instead) and --kind-mode model|fight|fightnear (a fight order moves units as close as they need to fire; fightnear only while a fight is on within 1,500, a plain move otherwise, for the dodgers). Both off by default, so the running search is untouched; in SPACE for the next run (norm() reads older rows as off). Inject file runtime/armynet/usage-inject-1.jsonl: the leader with arc-inrange, with fight, with fightnear, and arc-inrange + fightnear; queued at the PC search's restart after its halving.
12:55 (local 19:55) search update: 40 evaluations, halving stage 2 (16 left); leader holds over 2 plays x0.83 (first x0.91); next x0.77, x0.74 (2 plays each); baseline x0.72 (1), current x0.67 (2); no failures.
13:20 (local 20:20) check. 4 headless engines (the search), his game off, free commit 34.0 GB, replay recorders paused for the search. Search: 54 evaluations, halving stage 3 (8 left), no failures. Changed this hour: serve --arc-inrange and --kind-mode, search SPACE + --inject (off in the running search).
13:30 combined PC+Mac (96 evaluations, 62 configs): top x0.80 (2 plays; no arcs, human rate -0.19, commit 0.9), x0.78 (3; no arcs, always, commit .7, wake .34, keep-air), x0.78 (3), x0.75 (2; one-row arcs), ...; baseline x0.69 over 4 (rank 14), current x0.68 over 3 (rank 24). All of the top six use no arcs or one-row arcs: deep formations cost the trade.
13:25 search update (20:24): 97 combined evaluations, PC at halving stage 3 (8 left), standings unchanged since 13:30's merge; no failures.
13:40 Mac stage 3 (48 evals): its baseline x0.79 over 2 is 2nd there; its stage-1 leader fell to x0.75 on a second seed -- per-evaluation noise about the spread between configs. Pooled: PC leader x0.79 over 4, baseline x0.69 over 4. Next runs: usage_search.py plays a whole halving stage on one seed (configs compared on the same games; log names carry a counter).
13:55 his question: how do we know more training won't help, and will new ways of using the model call for training differently? Answer recorded: under the old serve, training gains could not show (dice discarded what the net knew); once the search has a winner, re-run w60, idle1, afk1, mem1 under it. Usage implies training: (1) always-order reads the place head every decision but it learned only clicked steps -- built serve --place goal (the 60-s hindsight goal head, learned on every force at every step) as a search setting, injected with the two leaders; (2) commit asks "would you change it" -- a trainable head: label = the player's next order sends the force meaningfully elsewhere than its current target (not built).
13:55 (local 20:54) search update: 126 combined evaluations; PC halving finished (winner x0.76), now hill climbing; the best tested config x0.77 over 6 (no arcs, fbias 0.5, commit .3, wake .7, place drawn); baseline x0.71 over 5, current x0.67 over 4: ~8% over the old way in the arena, inside the noise of 1-2-play results; the earlier leaders shrank on re-tests (0.91 -> 0.79 -> ~0.76). No failures.
14:10 arena search ended (PC stopped in hill climbing; Mac at its last stages): in pure fights the usage settings differ by ~8% at most, inside the noise (the Mac's baseline holds 1st at x0.77 over 3; PC best-tested x0.77 over 6 vs baseline x0.71 over 5). The arena scores fighting only; his watches judged whole games. usage_search.py --mode game: an evaluation = two 20-min 1v1s on Comet Catcher at +50 with the new layout, vs Apex:v0.5.17 and vs BARb hard; score = log((killed + 200) / (lost + 200)) of mobile metal + 0.5 a win / -0.5 a loss; --inject configs join the first stage. Started 8 h, --n 16: baseline, current, the arena's top five, the six new-idea configs (arc-inrange, fight / fightnear, place goal), 3 random. Out runtime/armynet/usage-search-game.
14:30 his watch (leading settings: no arcs, always, commit .7, wake .34, keep-air, vs v0.5.17 seed 24): "we keep ALL our army in one line. Even the short range guys and the long range guys. We should have each unit type a member of its own group or subgroup ... not properly thinking about where each unit should be based on its own strengths/weaknesses". Built serve --split-defs: a force's ground members split by def (as flyers already are), each subgroup decided by the force heads alone, on its own members' range/speed/health; watch passes it; split_defs in the search SPACE (off in the running game search). Self-check before his next watch.
14:50 his: release v0.5.18 with the eco/building fixes (+ the T3 fix only if it works), then the army-net work on the Mac; he wants to play on this PC with v0.5.18. All army-net testing stopped on both machines (his: worthless until the model sees enemy units and full unit stats). Candidate: TUNE_FLUSH_PLACE 2 and TUNE_STREETS 2 (script) with C++ defaults 2 (BuilderTask, CircuitAI), TUNE_T3_SINK 0 (unverified: the test never reached a gantry), TUNE_VALUE_PLOT 0. Lane DLL rebuilt, deployed, smoke ok. Release games running: 24 x 2v2, +50, 30 min, speed 20, Comet Catcher / Carrot Mountains / Red Comet, Armada and Cortex, seeds 1801-1802, vs Apex:v0.5.17 (12) and vs BARb hard (12), matches/rg518-*. Reviewer agent on the v0.5.17 -> candidate diff (scratchpad v0518.diff, 825 lines). Defs dump widget written (tools/defs_dump_widget.lua) for the army-net fix after the release.
14:20 (local 21:20) check. 4 headless (release games, 5 of 24 started, 1 done) + his Carrot Mountains watch; free commit 22.2 GB (near the 20 GB gate; run_match waits on memory); army-net training and testing stopped on both machines by his call; replay recorders paused. Changed this hour: release defaults (flush 2, streets 2, T3 sink 0), defs dump widget.
14:45 search updates cancelled (cron 825f9edb): both searches stopped by his call until the army net sees enemy units and full stats.
15:20 his read of the Carrot 1v1 watch (candidate + T3 sink vs v0.5.17): half their eco "and there is no good reason for it". From his game's logs: income m12 137/173, m16 177/389, m20 223/426; constructors 48 at 16 then flat vs 88 -> 122; no placement failures. Reproduced on the same seed (matches/ecogap, kept write dirs, ecogap.py): ours/theirs income at 20 -- t3on 273/370 (cons 45/130, our con orders m8-12 14 and 8 vs 26 and 36, our reclaim elections 0 vs 127), ship (T3 sink off) 486/282 (cons 78/54), oldgrid (flush 1, streets 1) 330/191. The T3 sink never fired (0 t3sink lines: no gantry by 22 min). So the same seed swings both ways by up to 2x between runs: a fight-driven 1v1 economy, not a reproducible deficit of the candidate; the 12-game release batch vs v0.5.17 (income at 20 per game) is the measure. Reviewer findings fixed: sites.as null mover guard; allies' streets under mode 2 masked by their own published ground plants (STeamLane.plants/plantsSet, StreetForLane). Measured in the release batch: off-lattice refused / site-fail counts.
15:35 control on the same seed: v0.5.17 vs v0.5.17 ended 457 vs 306 at minute 20 -- a 1.5x gap with identical code, so one 1v1 says nothing about a deficit. Release batch restarted on the fixed candidate (reviewer fixes; smoke ok): 24 x 2v2, +50, 30 min, speed 20, three maps, both factions, seeds 1811-1812, vs v0.5.17 (12) and BARb hard (12), matches/rg518b-*. Then contract.py --record on the 12 vs v0.5.17.
16:10 v0.5.18 candidate FAILS the contract vs v0.5.17 (11 games of rg518b): games won or ahead 0.36 vs 0.50; t2 -> 4th moho 7.52 vs 4.78 min; raider repeat kills /10min 14.27 vs 7.40; lost per killed 2.40 vs 1.38; income at 20 lower within noise. Not shipped. Differences from v0.5.17 active in normal games: (1) flush placement mode 2, (2) streets mode 2 (+ allies' streets), (3) the home-radar clause (an older uncommitted change, now TUNE_HOME_RADAR / apex_home_radar, default 1). Bisection running on the same 12 seeds vs v0.5.17 (matches/bis518-*): lay0 (flush 1 + streets 1), rad0 (home radar off), ctrl (v0.5.17 vs v0.5.17), both0 (all three off); contract.py on each arm. Eco variance tool built: tools/eco_variance.py (first read on 10 games: builders at minutes 8-12 predict income at 20, within-game rho ~0.9; early metal lost next).
15:20 (local 22:20) check. 4 headless (bisection: 10 of 48 started, 4 done), his game off, free commit 31.1 GB; army-net work stopped on both machines (his call); replay recorders paused. Changed this hour: apex_home_radar switch (TUNE_HOME_RADAR 1) for the bisection; tools/eco_variance.py.
17:10 bisection (12 games each, same seeds vs v0.5.17): lay0 (layout off, radar on) contract FAIL, won or ahead 0.33, lost per killed 2.03 vs 1.24; rad0 (layout on, radar off) PASS, won or ahead 0.75, lost per killed 1.10 vs 2.36, t2->4th moho level. The layout is fine; the home-radar clause (protect_senseprice.as, an older unmeasured change) is the loser. Mechanism, his question ("radar is so cheap ... some behavioral mechanism"): it is the timing, not the information. With the clause the first mast goes up at a median 3.1 min (11 of 24 seats before 3:00) against 10.2 without (1 of 24): its price, (assets + the commander's 2,700) / fill, tops the opening's elections from the first seconds (radar-home at assets=500), so 630 energy and a builder leave the opening build. By minute 10 (24 seats each, medians, on / off): T2 lab started 10.4 / 9.6 min, finished 13.5 / 11.8; builders 23.5 / 28; eco metal 3,555 / 3,985; army 5,696 / 6,157. Weaker sign of more retreats with home radar (radar_diff.py), unproven. Plan: v0.5.18 with apex_home_radar 0; the radar itself kept but priced by when an enemy could first reach home, so it lands when it can save something.
18:05 radar mechanism, from the logs (his "logs should show this"; his point: an aggressive human would trigger it too). Pooled minutes 2-10, radar on (24 games) / off (12): the danger model's live enemy army near home 1,033 / 556 metal (dgtrace liveM), nearest arrival 6.2 / 11.2 s, unknown radar contacts counted 2.1 / 0.8; the T2 lab's time saving etaSave 0.02 / 0.30 (tech-diag), eta-tech wins before min 8 0.9 / 3.8 per seat, T2 started 10.4 / 9.6 and done 13.5 / 11.8 min. The chain: TechHomeRisk = HazardAt(home) x ShortfallAt(home) (want_tech.as) reads the enemy we SEE near home; TechSurvival = 1/(1 + risk x build time) discounts every T2 plan in the ETA ladder; more seen near home = T2 priced as unsurvivable. Seeing more costs us tech -- the same response an aggressive player provokes. TechHomeRisk is not logged; next: log it in tech-diag and test radar on with apex_tech_survival=0. Separately, both arms: the rush rule (rush.as) prices T2 at 0.04-0.06 of its value at minute ~1-3 with no enemy army seen (Tc=21 s from dist=1558 at the prior speed).
23:22 hourly: 4 headless (bisection both0 arm, 0 of 12 done); army-net work stopped (his call); recorders paused. This hour: radar mechanism traced to TechHomeRisk/TechSurvival (seen enemy near home discounts T2), entry above.
23:55 his doubt ("we just got outscaled", post-T2, not losing much) checked. (1) The control arm (v0.5.17 vs itself, same 12 seeds) shows the same outscaling with identical code: side A income at 21/30 min 110/235 vs side B 134/319; candidate vs v0.5.17 at 30: 212 vs 278 (A/B 0.76, control 0.74). The radar is not needed to explain what he watched; its contract result is weaker evidence than it looked. (2) 184 seats, 53 games, split within each game by income at 24 (top 243 vs bottom 115 m/s): even at 4-6 min; builders 21/18 at 8, 42/31 at 12, 64/41 at 16 -- from 12 to 16 the bottom half adds 3 T1 constructors to the top's 10; same eco share of spend (~20%) but each metal of eco buys less growth (+40 m/s from 4,276 vs +17 from 2,964); energy income 1,514 vs 1,153 at 12; kills 9,668 vs 6,680 mobile metal by 16. Labs skip constructors as `armck:conidle` while ours stand idle. Tools: tools/eco_variance.py (outcome minute must be even: stats every 2 min), scratchpad halves.py / side_mix.py. Next: what the laggard's idle builders wait on, and why its eco returns less.
00:20 his question: do idle T1 cons block T2 cons? No -- ConStandsIdle is per tier (an idle T2 hand blocks T1 orders, not the reverse); conidle on T2 labs 24 times in minutes 12-20 over 53 games. The T2 constructor shortage is elsewhere: in minutes 12-20 the t2-con floor wants 13.4 on average against 3.0 owned, and skips 1,694 times, nearly all with pend=1 (ceilOpen = no T2 con pending/in flight: they are ordered strictly ONE AT A TIME); 572 ordered in all (~2.7 per seat in 8 min). In the lab's own ranking the T2 con (`:b`) prices 8-40k against army 200-560k, so between floor orders the lab makes army. Seats at 16 min: 4 T2 cons (richer half) vs 2 (poorer). Same code in v0.5.17. Candidate fix: let the floor fill toward its need while the metal holds, not one at a time; measure T2 cons at 16 and income at 24 on paired games.
00:45 his "cons walk forward into danger, nobody home to make a fusion" -- checked, minutes 12-24 over 58 games (216 seats): T2 constructors die 3.0 per seat (about as many as a seat owns at once, ~3), median 2,203 from home (quartiles 1,133 / 3,502); 38% of their jobs are metal (moho upgrades 33%), whose mohos finish a median 1,632-1,798 from home, against fusions at 663-741 and converters ~500. The learned job risk (risk.as) prices pBuilder at a mean 0.038 per job. Built TUNE_T2CON_FILL / apex_t2con_fill (default 0, identical off): the t2-con floor orders in parallel toward CeilingConsNeed instead of one pending at a time. Test: matches/t2fill-* = rad0's 12 seeds with apex_home_radar=0 + apex_t2con_fill=1 vs v0.5.17; compare per game with bis518-rad0-*: T2 cons at 16, T2 con deaths, income at 24, contract.
01:05 bisection last arm both0 (layout, streets, home radar all off = v0.5.17 behaviour on the candidate build) vs v0.5.17: contract PASS, won or ahead 0.58, lost per killed 1.55 vs 1.27 within noise. Arms on the same 12 seeds, won or ahead: candidate 0.36, lay0 0.33, rad0 0.75, both0 0.58 -- the two radar-on arms lowest, but the control shows side/seed swings of ~25% income, so the radar finding stays tentative.
01:50 T2 con fill (apex_t2con_fill=1) on rad0's 12 seeds, paired: T2 cons at 16 4.2 vs 3.6, at 20 8.5 vs 7.5; T2 con deaths 12-24 4.0 vs 3.0 per seat (median 2,168 from home); income at 24 200 vs 225 (higher in 4 of 12); lost by 20 24,043 vs 18,855; killed 11,385 vs 14,900; contract PASS (won or ahead 0.50). A loser: the extra constructors die forward and cost army. Deleted (switch, tunable, gadget name). Next: the learned builder risk vs real T2-con deaths on forward moho trips.
00:20 hourly: 0 headless (T2-con test done, its switch deleted as a loser); army-net work stopped (his call); recorders paused. Lane scripts changed since the last deploy (switch removed) -- redeploy before the next test.
00:55 his theory (luck: every T2 con off on far mohos, nobody home ramping energy; mohos are linear, energy compounds) -- measured, minutes 12-20, 276 seats split by income at 24: time with NO T2 con on an energy job 42% (richer) vs 68% (poorer); T2-con minutes 32 vs 14; metal-job share 48% vs 51%, energy 20% vs 15%; growth 16->24 x2.38 vs x1.77. By that one measure (thirds): 23% -> x2.39, income 246; 97% -> x1.74, income 101. Realized builder death per T2-con job (24,080 jobs, 72 games): new-spot moho 22-23%, LRPC 15-16%, T2 towers 14%, moho upgrade 5-5.5%, fusion 1.5-2%, converter 3.5-4%; the price stakes only the con's 430 metal (scale ~0.96 at pB 0.22). Built TUNE_HAND_WORTH / apex_hand_worth (default 0, identical off): an advanced hand stakes its metal + its build rate on the job's def x the measured seconds between our advanced-hand arrivals (EMA, at least the time since the last; prior build time / plant BP); log `apex: hand-worth`. Test matches/hworth-* on rad0's 12 seeds (radar 0, hand worth 1) vs v0.5.17; compare with bis518-rad0-*: no-energy-T2 time, T2 con deaths, income at 24, contract.
02:30 hand worth (apex_hand_worth=1) on rad0's 12 seeds, paired: measured gap between T2-con arrivals 44 s (mean of 334 lines), so the added worth was small; T2 cons at 16/20 3.0/5.2 vs 3.6/7.5; income at 24 166 vs 225 (higher in 3 of 12); T2 con deaths 3.27 vs 3.02 per seat; time with no T2 con on energy, poorer half 82% vs 59%; contract FAIL (raider repeat kills 12.9 vs 8.3). A loser; deleted (code, tunable, gadget name). Pricing the builder's stake does not keep T2 cons home.
01:35 hourly + next lead. T2-con elections minutes 12-20 (6,044, all seats, 37 games): metal over energy 864 at a median value ratio x3.87; energy over metal 504 at x0.94; metal picks by reason: role 696, upfirst 472, draw 348, field 225. UpgradesFirst (want_mex.as) hoists a moho upgrade over every want for a T2 hand whenever ANOTHER T2 hand is on a home energy/conversion job (OutForUpgrades) -- one hand home, the rest out: his "nobody home" as a rule, and a forced move against his pricing-only ruling. Switch TUNE_UPFIRST / apex_upfirst (default 1). Test matches/upf0-* on rad0's 12 seeds (radar 0, upfirst 0) vs v0.5.17; compare with bis518-rad0-*: time with no T2 con on energy, T2 con deaths, income at 24, contract. Roles (TUNE_ROLE_SHARE 0.5, 696 metal picks) next if this moves.
01:55 his advice (11-23): cut the variables -- no air, no nukes -- and do not be fooled by bombing. Structure metal lost by minute 24 (312 seats, 61 games, split by income at 24): to air 1,998 (richer) vs 5,147 (poorer), seats hit by air >500: 109 vs 132 of 156; ground 15,003 vs 18,980; nukes/LRPC 173 vs 348; unseen attacker ~10k both. Queued after upf0: land-only series (unit_restrictions_noair/nonukes/notacnukes=1), same 12 seeds vs v0.5.17, three arms interleaved per seed: Lrad0 (home radar 0), Lrad1 (home radar 1), Lupf0 (radar 0, upfirst 0); matches/land-*.
03:40 upf0 (upgrades-first off, radar 0) on rad0's 12 seeds, paired: income at 24 194 vs 225 (higher in 4 of 12; v0.5.17 in the same games 197 vs 175); T2 cons at 20 6.6 vs 7.5; T2 con deaths 3.71/seat; time with no T2 con on energy, poorer half 63% vs 59% (did not move); contract PASS, won or ahead 0.67, lost per killed 1.35 vs 1.61. Inconclusive: the behaviour it targets did not change. Kept as a switch (default 1) for the land-only retest (Lupf0).
03:20 hourly: 4 headless (land-only series, 14 of 36 started, 10 done); air confirmed off in land games (no air plant built, no kills by aircraft; script carries unit_restrictions_noair/nonukes/notacnukes=1); his game off; free commit 32 GB; army-net work and recorders paused.
05:10 land-only series (no air, no nukes; same 12 seeds vs v0.5.17): Lrad0 (home radar off) contract FAIL -- won or ahead 0.42, raider repeat kills 11.4 vs 7.6; Lrad1 (radar ON) PASS -- won or ahead 0.58, lost per killed 1.16 vs 1.40; Lupf0 FAIL on income at 20 (within the noise elsewhere), won or ahead 0.58. Paired radar on vs off: income at 24 250 vs 206 (on higher in 8 of 12), killed by 20 15,020 vs 13,497. This REVERSES the air-on bisection (rad0 0.75 vs candidate 0.36): the same config (radar off, layout on) went from PASS 0.75 to FAIL 0.42 between regimes. 12-game sets cannot resolve these effects; the radar finding was noise or an air interaction. Time with no T2 con on energy, poorer half, land: 42-57% (vs 59-82% with air). Next: a large normal-settings batch, radar on vs off, new seeds 1813-1818 (36 games per arm, interleaved), launches held while his game runs.
03:20 hourly: big radar batch 4 of 72 started, 0 done; his game off; army-net work and recorders paused.
04:30 hourly + finding: big batch 35 of 72 done (17 radar-on, 18 off). Radar ON: won or ahead 0.29 vs 0.78 (contract FAIL vs PASS); income at 24 lower in 14 of 17 paired games (153 vs 204). The gap opens at minute 2: from the 8th structure every build lands ~40 s late, in the land-only set too (so its reversal was noise). Mechanism: the comescort hoist (decide.as ~2898, commander assists the lab 60 s whenever the top want is not a mex) fired 34 times before minute 4 with radar on vs 13 off, 31 of them over the home radar want; commander lab-assist time 57 vs 20 s/seat by minute 4. The radar outranks the mex and unlocks the hoist. Next: same 18 seeds, comescort off (apex_com_escort=0, added to the gadget, deploy after the batch) with radar on (Esc1) and off (Esc0), plan matches/esc/plan.txt. His game off; free commit 40 GB.
05:20 hourly: big batch 69 of 72 done. Radar ON (34 games) won or ahead 0.32, contract FAIL; OFF (35) 0.66, PASS. Paired 35: income at 20 112 vs 137 (radar-on higher in 9 of 35), at 24 152 vs 187 (11 of 35); T2 cons at 20 5.9 vs 7.0. Comescort test (matches/esc/plan.txt) starts when the batch ends. His game off; free commit 42 GB; army-net work and recorders paused.
06:20 hourly: comescort-off test 28 of 40 launched (4 first cc-1813 runs void: gadget not deployed -- deploy_ai.py deploy does not install gadgets, deploy_ai.py gadgets does; rerun as Esc0b/Esc1b; switch verified: 0 comescort vs 64 in the matching big game). Interim, 12 paired seeds (same seeds' radar games alongside): income at 20, radar on/off with comescort off 148 vs 133; with it on 92 vs 127. Won or ahead: Esc1 0.33, Esc0 0.50, Brad1 0.17, Brad0 0.75 -- too few games to say whether comescort itself pays. His game off; free commit 32 GB.
07:20 comescort-off test done (18 pairs, cc-1813 reruns). Comescort removes the opening lag (builds on time, radar done at 114 s) but radar ON still loses income later: at 20 129 vs 154, at 24 182 vs 246 (3 of 15 higher); won or ahead 0.44 vs 0.67. So comescort was half the story. Comescort itself, radar off: 0.67 vs 0.78 won/ahead, income at 24 245 vs 218 -- unresolved. Next lead: tech-diag etaSave 0.08 (radar on) vs 0.29 (off), minutes 6-16 -- the T2 ETA term is cut when the radar sees more.
08:20 hourly (no engines; his game off). Radar's later cost, comescort off, 18 pairs: everything level to minute 14 (builders, mEco, army 9 of 18 each); from 14 T2 cons fall behind (at 18 4.7 vs 7.0, on higher in 2 of 16; at 22 6.8 vs 11.0), then eco and army. T2 bot-lab con orders before 20: 170 vs 250 -- both the t2-con floor (89 vs 122) and the con floor (80 vs 122) fire a third less; T2 air cons 102 vs 95, T2 air plants 23 vs 19. Radar shows more enemy air: airanswer raid 1235 vs 823, fighter gain 1.95 vs 1.05; ftrOwed in 20% of t2floor-skips vs 9%. Energy elections to 20: 111 vs 131/seat (advsol 84 vs 107). Next: log why the floors do not fire (armyBehind parts, ceilOpen parts) as a time share, then rerun.
- 2026-11-23 09:20 hourly (army model paused; his game off). Radar's later cost, comescort off, 18 pairs: the T2-con floor's skip sample shows ftrOwed rising with radar on (14-20 22% vs 11%, 20-26 47% vs 20%) while static AA is lower (16: 530 vs 892) and air army higher (16-18: 1,109/1,805 vs 756/1,329): radar turns the air answer into fighters from the air plant, which then makes no T2 air cons while the ground lab yields its T2-con floor to it. Extractors already trail from 12 (14.1 vs 15.3), mohos at 20 4.8 vs 6.8. Test running: the same 18 pairs with apex_air_answer=0 (matches/aans-Aan0/1-*); if the radar gap closes there, the air answer is the coupling.
  - aans check: on=0 confirmed in the log, but modoptions reach the opponent too: v0.5.17 also runs with its air answer off (it reads apex_com_escort as well, so the esc batch's opponent had comescort off in both arms). The radar on/off comparison inside the batch stays paired; its win rates are not comparable with earlier batches.
- 2026-11-23 10:20 hourly (army model paused; his game off; 4 engines on matches/aans). Air answer off, 14 of 18 pairs in: radar still costs as much or more -- income at 20 98 vs 128 (on higher 3 of 14), at 24 119 vs 186; T2 cons at 18 3.9 vs 5.6; air army LOWER with radar on (18: 576 vs 1,318). So the fighter answer is not the coupling; the 09:20 hypothesis is refuted. Here the gap starts early: builders at 8-10 17.3/23.5 vs 19.3/27.6 (on higher 3 of 14), extractors at 14 13.9 vs 16.5. Next, when the batch ends: open_split/first_builds on all 18 pairs, and what radar's sight changes in pricing (exposure charge on far extractors, seen-enemy terms).
  - aans done, 18 pairs (air answer off, both sides): radar still costs -- won/ahead 0.28 on vs 0.39 off, income at 20 102 vs 129 (on higher 4 of 18). Common to all three batches (big, esc, aans): the con floor yields to "army behind" about twice as often with radar on (cumulative by minute 10: 2.8/1.5, 3.3/1.4, 3.2/1.4), and the con floor orders 2-3 fewer constructors per seat between minutes 4 and 10. Not ArmyShortOfFoe (its 30-s line fires equally in both arms) and not early losses (equal). Logging-only change in the lane: spothands now carries yFoe/yFtr/yShare (which armyBehind term yielded), outEarn and earn ours/theirs, and army share vs target; smoke ok. Running: matches/cfy-*, the 18 pairs at 14 minutes, comescort off.
  - cfy done, 18 pairs at 14 min: the extra yield is the foeOutguns term (yFoe by 10: 1.56 on vs 1.06 off; by 12: 2.11 vs 1.36); the share term is equal (0.42/0.47) and ftrOwed small. ArmyShortOfFoe is equal across arms, so the gate radar moves is WeOutEarnThem (true in 46% of half-minute samples on vs 40% off). The yield explains ~0.7 of the 1.8 fewer constructors at 10. Second logging-only change (behaviour identical: the con-floor && chain split into nested ifs in the same order): spothands adds their extractors counted / radar-only, earn x1000, and why a floor with need did not fire (cfCap/cfUpk/cfHold) and asks with need 0 (cfAsk/cfNoNeed). Smoke ok; running matches/cfz-*.
- 2026-11-23 10:20 hourly (army model paused; his game off). cfz, 16 of 18 pairs at 14 min: constructors level to 10 this time (20.3 vs 19.9), gap from 12 (25.5 vs 28.0, on higher 3 of 15). WeOutEarnThem reversed (true 41% on vs 50% off; cfy had 46/40): noise, not the mechanism. Enemy extractors counted equal (20.9 vs 19.8 at 10, radar-only 1.2 vs 0.6). Con-floor gates: budget hold blocks most asks in both arms (12.1 vs 13.1 by 10), upkeep 0.8 vs 3.0, cap 0; yFoe 3.6 vs 2.0 by 12. Commander activity equal (build/assist/idle/move). armrad has no energy upkeep. So far no single rule carries radar's cost; it appears from minutes 8-12 as a little fewer constructors and extractors and compounds. Robust result across three batches: radar on loses (won/ahead 0.31/0.67, 0.44/0.67, 0.28/0.39). Next idea: an arm that pays for the radar (want, commander trip, 60 m/630 E) but never completes it, to split cost from sight.
  - Cost-vs-sight arm built in the lane: apex_home_radar=2 prices, sites and builds the home mast exactly as 1, self-destructs it the moment it stands (radar-home-paid line) and treats home as watched from then. Check game (cm-A1813, 6 min): both seats' masts died ~6 s after finishing (2.0, 2.5 min), no rebuild. Running matches/hrp-Hrp2-*, the 18 seeds at 30 min, comescort off; controls are Esc0 (off) / Esc1 (on). If Hrp2 tracks Esc1, the cost is the build; if it tracks Esc0, it is what the mast shows. Behaviour under 0 and 1 is unchanged.
- 2026-11-23 cost-vs-sight result (results/home-radar, three new pages: air answer off, con-floor yield counters, cost without sight). Cost-only (mast built then self-destructed) is the worst arm: won/ahead 0.17 vs on 0.44 vs off 0.67. Its blast killed our own early eco in 24 of 36 seats (3,368 m; Carrot, Red Comet), so only Comet Catcher is clean: income at 24 113 cost-only vs 198 on vs 230 off (cost-only higher 0-1 of 6). Radars per seat over the game 8-11 in every arm (off builds the most); before 12 min 1.9 / 1.5 / 1.4. So the arms differ only in the EARLY home mast: its sight helps (on >> cost-only), its price at minute 1.5-2 (60 m, 630 E -- ~40 s of opening energy -- and the commander's trip) hurts more. Candidate (needs his say, it touches his 11-20 "radar up before the commander leaves home"): time the home mast to when a raid can first arrive (the open race's tR), not price the commander's whole stake from minute 1. Recommendation for v0.5.18 unchanged: home radar off.
- 2026-11-23 11:20 hourly (army model paused; his game off; radar question with him). Idle engines put on the other unresolved release switch, comescort (radar off: won/ahead 0.67 off vs 0.78 on, income at 24 245 vs 218 -- mixed): matches/esc-Esc0-*-1816..1818, 18 games, pairs with big-Brad0 (comescort on) for 36 pairs in all.
- 2026-11-23 midday (he is back). comescort settled: 36 pairs, radar off, no difference in our income (20: 139 off vs 138 on, off higher 21 of 34; 24: 225 vs 216) -> keep as v0.5.17 ships it (on). Radar mechanism, behaviour side by side (esc E1/E0, big B1/B0): commander time equal; con losses lower with radar on; no con vetoes; factory orders equal; T2 lab elected at the same time (11.9 vs 12.5) but builds twice as long (finish 17.0 vs 15.0; big 17.8 vs 15.2, later in 15 of 18) under energy stall 54% vs 40% of the build (big 79% vs 62%); t1 cons finish fewer jobs from 10 (44 vs 52 at 10-12) with equal numbers; energy jobs 14-16 12 vs 18; metal makers draw more energy (armada at 12: 213 vs 140). Stall already higher at 6-8 (on higher 12 of 18). Next: one matched pair, minutes 4-10 job by job, to find the first divergence.
- 2026-11-23 hourly (he is back; no engines). Log-kind census radar on vs off (tagcmp.py, minutes 2-14): consistent in both batches -- the commander's base-going-down logic (comship) fires 1.5-2.3x (com-ship 10.2 vs 4.3 per seat; big 9.4 vs 6.1), with its cloak (com-ship-cloak 2.0 vs 0.3; big 4.8 vs 1.2), hold-fire, withdraw/retreat. Cloaked time to 14 min: big 30 s vs 0.8 s per seat, to 20: 70 vs 6 (esc to 20: 24 vs 7). BUG: IsCommCloakWanted's comship branch prices the STANDING cloak (100 e/s) while the commander steps in, i.e. walks (moving cloak 1,000 e/s; the log line itself says cost=1000), so it cloaks into an energy stall and flips. Radar keeps their raiders visible at home, so comship (and the cloak) runs longer. Candidate fix (C++, needs a DLL build): price the moving cost while he moves; then rerun radar on/off.
- 2026-11-23 13:20 hourly (his goal: radar on early as good as off; army model paused). Fix 1 built and deployed in the lane (C++ IsCommCloakWanted: the comship cloak prices the moving cost while he walks): cloaked time with radar on 0.8 s per seat to 20 min vs 24-70 s before. matches/ckf-* (radar 1/0, comescort default on, cloak fix in both): 16 of 36 done, 8 pairs: radar on still lower at 12 (58 vs 69, 0 of 7), 20 (114 vs 151). Fix 2 written, not deployed (no deploy mid-batch): decide.as comescort does not pull the commander off a top-ranked home mast (it did at 1.4 min, 1.5 pulls per seat over it vs 0.3). Next: deploy fix 2 when ckf ends, rerun radar 1/0.
- 2026-11-23 14:30 (his radar goal). Fix 2 deployed (comescort leaves a top-ranked home mast alone). Stance traced as a radar coupling: AGGRESSIVE share 54% vs 27% at 10-12 (ckf), passive (eco x1.3) 59 vs 80% at 6-8 (esc); AGGRESSIVE's army/defence multipliers are 1.0, so it only removes greed. His definition (11-23: a few raiders are not aggressive, 10 pawns are; aggressive = the army we see highly outclasses ours; the stance exists to strengthen before a superior army kills us) built as apex_stance_unheld (lane, default 0): AGGRESSIVE iff the live seen army outclasses our side's ground army (StrRatio > ANSWER_PARITY), or a ground group at home outweighs the guns reaching it plus our side's army, or raid pressure; contact/contested/raided alone read nothing. A local-only first form read one 54 m pawn as AGGRESSIVE; fixed. Check game cm-A1814: passive 3.5-12 min. fx2 batch stopped at 8 games (he chose to test this first). Running matches/stu-Stu1/0-*, radar on/off, all three changes in both arms.
- 2026-11-23 14:27 hourly (army model paused, his radar goal active; his game off). 4 engines on matches/stu (radar 1/0 with apex_stance_unheld=1 + cloak fix + comescort-over-mast fix), 0 of 36 done.
- 2026-11-23 15:20 hourly (army model paused; his game off). matches/stu 24 of 36, 12 pairs (radar 1/0, apex_stance_unheld=1, cloak + mast fixes): income at 20 131 on vs 129 off (on higher 7 of 12), at 24 199 vs 188 (6 of 12); at 12 58 vs 60 (4 of 12). First batch where radar on is level.
- 2026-11-23 15:50 v0.5.18 (his: release first, then see whether the armynet gains from these changes). stu result (18 pairs, seeds 1813-1815): radar on with the three changes beats off -- won/ahead 0.72 vs 0.56, income at 20 137 vs 128, first moho 16.0 vs 17.4; results/home-radar page. Candidate = lane defaults: TUNE_HOME_RADAR 1, TUNE_STANCE_UNHELD 1 (new default, docs/tunables.md), cloak + mast fixes, earlier eco/layout changes, upfirst 1, comescort 1. Release batch running: matches/rel518c-R (defaults, the contract record) and -R0 (radar off, the replication control), seeds 1816-1818 vs v0.5.17. Fresh reviewer agent on the v0.5.17 -> candidate diff (scratchpad v0518c.diff + v0518c-cpp.diff). Release copy must take v0.5.17's nnweights.as (Unstable's differs; risk.as differs in line endings only). Then: shared DLL build, contract --record, deploy v0.5.18, smoke, 12 vs BARb.
- 2026-11-23 16:00 reviewer findings on the v0.5.18 candidate, fixed: (1) StrRatio(x, 0) = 1e6 read AGGRESSIVE with no army -- rival now needs our side's army > 1; the home-force answer counts the commander at his strength in the group's metal per strength (comship's conversion); (2) the home-force answer counted every ally's whole army (8v8: no base raid ever unheld) -- now our own ground army + allies' army near the group + guns reaching it; (6) the comescort mast exemption pinned to the sense want sited exactly at home, with gHomeSet; (7) home radar clause guarded by gHomeSet; mode 2 (self-destruct test arm) deleted. Left: "highly outclasses" = ANSWER_PARITY 1.2 (his call), cloak velocity no hysteresis (low), flush/streets mode-2 placement edge cases (low; layout measured fine in the 11-22 bisection, lay0 vs rad0). Check game cm-A1814 on lane defaults: no AGGRESSIVE, passive from 7.3 min, home mast at 1.9 min. Release batch restarted as matches/rel518d-R / -R0 (seeds 1816-1818); the Mac (Workhorse) runs candidate vs BARb and v0.5.17 vs BARb, seeds 1816-1817.
- 2026-11-23 hourly (army model paused; his game off). v0.5.18 gate in progress: PC rel518d (candidate vs v0.5.17, radar on/off arms), Mac (Workhorse) candidate and v0.5.17 vs BARb hard, 16/24 done at last report, --handicap 50 every AI.
- 2026-11-23 16:35 his: ship v0.5.18 once the head-to-head passes. Mac BARb leg (Workhorse, 24 games, --handicap 50 all AIs, seeds 1816-1817): candidate 7/4/1 vs BARb hard, v0.5.17 7/4/1 (matches-mac/v0518-barb/results.zip). ai/v0.5.18 staged from Unstable (v0.5.17 nnweights/policydata, AIInfo v0.5.18). After rel518d: contract --record on the R arm, shared DLL build, BARAI_LANE=shared deploy v0.5.18, smoke.
- 2026-11-23 17:05 his: T3 sink was left out only because of the radar problem; see if it can be included. Our radar-on 30-min games: 14 of 37 build a gantry, first at 26.5 min mean -- too short. Mac (Workhorse) runs rel18 lane vs v0.5.17, 45 min, seeds 1816-1818, arms T3on (apex_t3_sink=1) / T3off, 36 games. CHANGELOG.md added (his 11-23), v0.5.18 headline = the grid change (his pride); docs/versions.md now points to it; release step in docs/working.md adds the entry.
- 2026-11-23 17:40 RADAR GOAL MET. rel518d (seeds 1816-1818): arm R (candidate as shipped) contract PASS vs v0.5.17, won/ahead 0.50 vs 0.50, recorded for AI code 927ff16c17-db260d789aa3; radar on vs off even on these seeds. Both radar batches combined, 36 pairs: won/ahead 0.61 on vs 0.53 off, lost per killed 1.32 vs 1.47, income at 20 134 vs 127 (on higher 21 of 36), at 24 191 vs 197 (before the fixes: 0.31 vs 0.67). Results page written; CHANGELOG v0.5.18 numbers updated. v0.5.18 held for the T3 sink test on the Mac (his call).
- 2026-11-23 17:20 hourly (army model paused; his game off). Speculative release batch with T3 sink on, so a T3 win ships without a 2 h wait: TUNE_T3_SINK set to 1 in Unstable, lane deployed, smoke ok; matches/rel518t-R-* (18 games, 45 min, seeds 1816-1818, vs v0.5.17, no modoptions). If the Mac's T3 test says no, TUNE_T3_SINK goes back to 0 and the tree is again the recorded PASS (927ff16c17-db260d789aa3). Mac T3 test: 2 of 36 done, the switch acts (src=t3sink after the gantry in T3on only).
- 2026-11-23 18:05 v0.5.18 RELEASED (his OK: without T3). T3 sink stopped at ~half: Mac 16 of 36 games, T3on 2/1/6 vs T3off 3/1/3, sink acted on 4 of 40 gantry prodrank lines (3 of 5 T3on games with a gantry); PC rel518t (T3 on, 45 min) 8 games, contract won/ahead 0.25 FAIL. TUNE_T3_SINK back to 0; ai/v0.5.18 tree 59d090bb143c1c59 = the recorded PASS 927ff16c17-db260d789aa3 (rel518d-R, 18 games). Shared DLL rebuilt from cpp/ (sync_cpp apply + build_dll), BARAI_LANE=shared deploy v0.5.18 (contract PASS line), smoke ok, 4-min game vs BARb: 'apex: version t=0 v0.5.18 nets=16318', '/say ... is Apex v0.5.18', no AI errors. Installed Apex: v0.5.14-v0.5.18 (highest loads in hosted games). Not committed (ask him). Next: armynet on top of these changes (his ask); T3 as a stronger sink (spare metal to the gantry while the army target is open), tested on the Mac in long games; his hypothesis that one aggressive human made every AI read aggressive -- the new stance rule should help, check in his next hosted game.
- 2026-11-23 18:15 Mac T3 final (stopped at his call, 9 games per arm): T3on 2/1/6 (gantry in 5, mean 26.8 min), T3off 3/1/5 (gantry in 6, 27.7); sink acted on 4 of 40 gantry prodrank lines. matches-mac/v0518-t3/t3_report.txt. CHANGELOG T3 line corrected.
