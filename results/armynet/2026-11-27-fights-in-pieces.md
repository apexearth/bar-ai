# Fights in pieces: his watch game, G2 against the rules army, G2 against the played model, top players

His read of the G2 watch game (11-27, through the Fable session), stated plainly: the armies looked even, but ours
fought in pieces while theirs gathered first, so we lost the fights and never held a mass. He watched at 6-10x;
this page measures it, no new games: the watch game (`matches/watch-g2`), mvr-g2 (G2 vs our rules army, 12 seeds),
mvm-h2 (G2 vs enemy1 as played, 12 seeds) and 20 top-quartile winners' public games (`--who players --winners
--top-quartile --limit 60`). Ground truth from the replays, `tools/armynet/objectives_army.py` (new "fights" lines)
and `tools/armynet/episodes.py` (new "forward" line).
- **A fight's first contact**: one of our armed units has an armed enemy within its weapon range + 200, and no unit of
  ours was in contact within 1,500 of it in the last 30 s. Ours / theirs = armed metal within 600 of it.
- **Arrivals**: of our armed metal that is within 600 of that point at contact or comes within 600 in the next 70 s,
  the share there at contact, arriving in the first 10 s, and over the next 60 s.
- **Lost outgunned**: our army metal lost within 20 s of a contact whose ours / theirs within 600 was under 0.7, and
  how much of our army stood over 1,500 from the unit then.
- **Forward episode**: a force episode (unit trips starting in the same step within 600) whose heading gains depth on
  the start-to-start axis; its metal as a share of the side's army.

## The table

| | his game: G2 | his game: rules | **G2 vs rules** | **rules (same games)** | G2 vs enemy1 | enemy1 played | top players |
|---|---|---|---|---|---|---|---|
| (a) first contacts | 14 | 17 | 190 | 208 | 198 | 226 | 365 |
| ours / theirs within 600 at contact, median (under 0.7) | 17.0 (.21) | 0.84 (.47) | 2.30 (.31) | 3.13 (.26) | 2.92 (.26) | 2.56 (.31) | 1.26 (.30) |
| that as a share of our army, median (q75) | .090 (.48) | .021 (.05) | .093 (.29) | .091 (.24) | .114 (.30) | .093 (.25) | .126 (.24) |
| **(d) at the fight: there at contact** | .38 | .46 | **.32** | **.53** | .37 | .43 | **.50** |
| arriving in the first 10 s | .02 | .17 | .06 | .07 | .10 | .08 | .11 |
| **arriving over the next 60 s** | .60 | .37 | **.63** | **.40** | .53 | .50 | **.39** |
| **(b) army metal lost at odds under 0.7** | .36 | .21 | **.30** | .21 | .29 | .18 | .21 |
| of our army over 1,500 away then | .54 | .79 | .47 | .44 | .51 | .48 | .81 |
| (c) forward episodes, force share of army, median: 0-8 / 8-16 / 16-24 / 24+ min | .12 / .03 / .03 / .04 | .10 / .02 / .01 / .01 | .11 / .04 / .02 / .02 | .11 / .04 / .03 / .03 | .13 / .04 / .03 / .02 | .14 / .04 / .03 / .01 | .10 / .04 / .02 / .00 |
| (e) join share of episodes | .261 | .295 | .230 | .196 | .304 | .247 | **.376** |
| contract: share of a fight's army that came after it began | .35 | .21 | .26 | .24 | .36 | .32 | (needs the infolog) |

(f) `--force-idle`'s forced answers by force size, place and whether the force is new to the model: not in any log
yet. `serve.py` now prints them every minute ("objectives-E2 by force": size 1-2 / 3-5 / 6-10 / 11+, home / middle /
forward by thirds of the axis, new / old, answers same / deeper / sideways / back). H3 (G1 vs G2, both with
`--force-idle`) is the next set to play and carries it; it follows on its own page. No shuffle baseline applies to
(a)-(e): none of them reads a heading.

## Read

1. **His read holds where it counts: the timing.** At a fight's first contact the rules army has half of what will
   fight there within 70 s already in place (.53), top players the same (.50); G2 has a third (.32) and brings
   almost two thirds (.63) over the following minute. Head-to-head the gap is smaller (.37 vs .43) because the played
   model does it too. That is fighting in pieces: the rest of the force arrives into a fight already going.
2. **It costs units:** G2 loses .30 of its army metal at local odds under 0.7 against the rules army's .21 (top
   players .21; head-to-head .29 vs .18).
3. **It is not a smaller first piece:** at contact the share of the army present (about .09) and the local odds are
   level with the rules army; forward episodes start with the same share of the army everywhere (c). Top players
   keep most of their army away from any one fight (.81 over 1,500) and still lose less there: spreading the army is
   not the fault, arriving late to a fight is.
4. **Joining:** players gather into other forces far more (.376 of episodes; the model .23, the rules army .20). The
   rules army gets its mass by moving as one squad, players by joining first; the model does neither.
5. Contract: `tools/contract.py` "army joins fights late" (the infolog version of (d), from the 30-s army snapshots,
   first contact = a unit that damaged an enemy in the last 10 s) reads the same way: G2 .26 vs rules .24, .36 vs
   .32 head-to-head, his game .35 vs .21. Making it also found that the snapshot parser saw one unit per snapshot
   (units are comma-separated); fixed, which changes "army idle on dead enemy ground" and "army lost outgunned" too.

<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "Fights in pieces: his watch game, G2 vs rules, G2 vs enemy1, top players", "games": 45, "W": 9, "L": 10, "w": 4, "l": 2, "verdict": "No new games. At a fight's first contact the rules army has .53 of the fight's 70-s metal in place, top players .50, G2 .32 (G2 brings .63 over the next minute vs .40). G2 loses .30 of its army at local odds under 0.7 vs rules .21 and top players .21. First pieces and forward-episode shares are level; players join .376 vs model .23."} -->
