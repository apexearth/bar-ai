# The army in a far corner off the line between the bases: where it stands, why, map or frame

His observation from many games (issues/army-off-axis-corner.md): part of the model's army ends up in the same far
corner off the line between the bases; on Comet Catcher, model at the bottom-left and enemy at the top-right, a group
sits at the top-left. No new games. `tools/armynet/army_where.py` (new): armed mobile metal-time every 10 s from
minute 5 and the standing order's point, on a 3 x 3 grid, in the map frame and turned so our start is bottom-left
and theirs top-right. Rows below are top / middle / bottom, columns left / middle / right.

## (1) Where the army stands and aims, turned frame (ours bottom-left, theirs top-right)

| | games | **top-left (the corner)** | top row | middle row | bottom row | aims, top-left |
|---|---|---|---|---|---|---|
| **Comet Catcher, G2** (his watch game + the switch smoke) | 2 | **.01** | .01 .02 .00 | .11 .22 .01 | .38 .25 .00 | .02 |
| **Comet Catcher, the model of 11-20** (his watch games then) | 18 | **.05** | .05 .02 .00 | .18 .14 .03 | .39 .17 .04 | .02 |
| Comet Catcher, rules army (the same games) | 2 + 18 | .00 / .00 | .00 .04 .06 | .08 .24 .14 | .22 .20 .02 | .01 |
| Comet Catcher, top players (start bottom-right / top-left) | 1 / 3 | .04 / .22 | | | | |
| Red Comet, G2 vs rules (start bottom-left / top-right) | 6 / 6 | .01 / .03 | | | | |
| Red Comet, rules army (same games) | 6 / 6 | .02 / .03 | | | | |
| Red Comet, G2 vs enemy1 / enemy1 played | 12 / 12 | .06 .01 / .05 .03 | | | | |

The full grids, map and turned frame and the order points, are in the tool's output; the turned and map frames are
the same for a side that starts bottom-left.

## (2) What the model's time in that corner is

Comet Catcher, the 18 games of 11-20 (the corner held .052 of its metal-time): **no order, our own buildings near .69**,
no order with nothing near .09, no order with theirs near .07, orders at metal spots .12. Its G2 games (.014):
orders at metal spots .49, open ground .11, enemy buildings .11, no order .23. The group in the corner is mostly
standing without an order beside our own buildings there (an expansion), not sent there by a fresh order.
**Which head sent it** (force place, rally, forced answer, unit head) is not in any recording or log: serve keeps
no per-order source. Proposed, not built: a serve flag logging each order's source and its turned-frame cell once a
minute, off by default so his online games are untouched, on in the next test sets.

## (3) Map or frame

`tools/armynet/mirror_serve_check.py` (new): from his two Comet Catcher G2 games, 6 moments each, serve's live
example (Game.live as parity.py builds it) against the same raw game mirrored left-right or top-bottom and rebuilt
through the same path:
- forces' best place on the mirrored cell (within one cell): left-right .68, top-bottom .70; **training's own mirror
  (data.mirror) gives .66 and .72**, so serve-time inputs are as mirror-true as training's.
- no lean: the forces' mean cell is x 23.4 in the game against 24.2 in the mirrored game mirrored back, z 38.6 against
  39.1 (of 64). **The model follows the map, not the frame**; the third of places that do not mirror is the model's own
  inexactness, unbiased.
- The presumed enemy base is the mirror of ours through the map centre (data.base_axis): top-right for a bottom-left
  start, never the top-left; the rally point is the mean of a large force's last order, so it follows the forces.
  Neither can put a group in that corner by itself.

## Added the same day: his two Comet Catcher watch games apart, the air-off game, and his hosted team games

G2's ".01" above rests on two Comet Catcher games (his watch game and the 15-minute switch smoke); every other G2 game
is on Red Comet. His two watch games read apart (model bottom-left, turned frame = map frame):

| | top-left cell | far off the line (over 0.3 of the start-to-start distance) | what the top-left time is |
|---|---|---|---|
| watch-g2 (air on), model | .01 | .011 | orders at metal spots .51, no order .24 |
| watch-g2, rules | .00 (turned) | .036 | |
| **watch-g2-noair, model** | **.09** | **.105** | **orders at an enemy building with theirs near .41**, at our building .12, open ground .10, spots .15 |
| watch-g2-noair, rules | .01 (turned) | .031 | |

In the air-off game the corner is real: a group of the model's army holds the top-left, fighting over buildings
there (both sides expand into it; the Fable session measured the model's builders taking .31 of their jobs in that
corner at 8-12 min, the rules side's .20). The same "far off the line" share from the contract (infolog) reads it.

His six hosted team games of 11-25 (Ice Scream, Altored Divide, Pyroclast, Aethermoor Creek, Carrot Mountains,
Hellas Basin; replay-orders recordings, the older model), each seat against the line from its own start to the
enemy side's mean start (`army_where.py --per-team`):

| | seats | far off the line, mean | per map (AI / human) |
|---|---|---|---|
| AI seats | 50 | **.184** | Aethermoor .32 / .30, Altored .11 / .06, Carrot .11 / .09, Hellas .25 / .16, Ice .01 / .01, Pyroclast .29 / .20 |
| human seats | 58 | .149 | |

What that off-line time is (mean over seats): AI seats, our own things within 800 .66, orders at our own building .33,
at a metal spot .19, at an enemy building .22, no order .16; human seats, ours near .52, theirs near .44, at an enemy
building .34, no order .36. Off the line, our seats' armies stand beside our own buildings and spots far more than
players' do; players there are mostly fighting at enemy buildings.

(Which seats ran the model in those games is not in the recording; the AI seats are ours, the army model's or our
rules army's.)

## Read

1. **Not refuted; it depends on the game.** In his air-on watch game G2 barely used the corner (.01); in the air-off
   game a group held it (.09 of the army, .105 far off the line vs the rules army's .031). The model of 11-20 held it
   .05 over 18 Comet Catcher games and leaned left all game (left column .62 vs the rules army's .30 turned). In his
   hosted team games our seats stand far off their line more than players do (.18 vs .15, 5 of 6 maps).
2. **What holds a group there is our own economy:** beside our own buildings and spots (11-20 games: no order beside
   our buildings .69; team games: orders at our buildings and spots .52 vs players' .19), or, in the air-off game,
   fighting over the buildings both sides put in that corner. The model goes where our expansion goes and the group
   is not collected afterwards, which ties it to the join / late-arrival finding (players join .376 of episodes, the
   model .23), not to a new rule.
3. The model follows the map (the mirror check), so this is not the frame. Contract "army off the line" (infolog)
   on every page: his air-on watch game .010 vs rules .034, the smoke .024 vs .071, G2 vs rules .046 vs .042, A .097
   vs .041. Serve now logs every order's source and aimed cell in test games ("objectives-S", off in his installs),
   so the next sets say which part of serve sends groups there.

<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "The army in a far corner off the line between the bases: where, why, map or frame", "games": 0, "W": 0, "L": 0, "w": 0, "l": 0, "verdict": "No new games. Not refuted: in his air-off watch game a model group held the top-left (.09; far off the line .105 vs rules .031), in the air-on one .01; team games: our seats far off the line .18 vs players .15, beside our own buildings and spots. Comet Catcher top-left (turned) share: G2 .01 (2 games), the 11-20 model .05 (18), rules .00, top players .04-.22. The model's corner time is mostly standing with no order beside our own buildings (.69). Serve-time mirror: forces on the mirrored cell .68/.70 vs training's .66/.72, no lean: it follows the map, not the frame."} -->
