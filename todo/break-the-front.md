# Break a front line we cannot beat (his 11-12)

**The fun problem.** A big attack landing is the fun moment for a human ("brace yourself"). Humans answer by
building defences until every attack is futile. From then the human wins with time, because the AI does not adapt
or change strategy. An AI that seems to do nothing is not fun.

**The rule he wants: notice failure and pivot.** Remember what has not worked. If the last few minutes of
attacks (air or ground) bought no progress, change the approach: "you have to make some progress". Air that keeps
dying to the same stuff should stop flying past it and kill it instead.

**Ways through, his list:**
- **EMP launchers** stun a whole stretch of the front, then attack it.
- **Junos** stop their jammers.
- **Over-nuking** (we already do some of this).
- **Bombing the front line itself**: the AA first, or fly straight over it, depending.
- **LRPCs.**
- **Starfall.** It needs a huge amount of energy, so build energy storage for it to fire.
- **Shooting past the front** at the economy in the back, to see what is there.
- **Defences opposite theirs**, as a held line to work from.

**Coordination.** One coordinated breakthrough beats air and ground each attacking on their own somewhere else.
His sequence: put up defences opposite theirs, bring EMP launchers and Junos, stun their stuff and stop their
jammers, then a bombing rush on the stunned front (kill the AA, or overfly it). Pick one place on the front line
and destroy it.

**Variety.** We almost always make bots and generally no vehicles; the unit mix needs more variance.

Related: [one-target-late-game](one-target-late-game.md) (everything on one target, switch suddenly),
[air-late-mass](air-late-mass.md) (kill their AA first; EMP), [lrpc-volley](lrpc-volley.md),
[break-enemy-walls](break-enemy-walls.md), [frontline-hold](frontline-hold.md),
[team-strategies](team-strategies.md); memory `goal-fun`, `one-opponent-is-not-strength`.

## Measured before building (11-12, turtle pilot)

Turtle opponent: v0.5.11 with `apex_share_army=2 apex_share_defence=12 apex_share_airdef=4` per AI. 2v2, +50, 45 min,
4 games (`matches/turtle-base-s700*`, scratchpad `turtleread.py`).

- 1 lost at minute 10 (Red Comet); 3 timed out.
- In s7004 we held 3x their army and 2-4x their income from minute 25, and still lost metal on the trade in almost
  every 5-minute window (up to -41k). Their defences reached 180k. We built no EMP launchers, no Junos and no super
  artillery. We had one LRPC. The nukes went at armies.
- Their spare metal still becomes army, so in s7001 and s7003 the "turtle" outgrew us late.

## Plan (v0.5.12), each step with its counter

1. **Siege state with memory.** From the death ledger (losses to static guns vs kills where they die), a front is
   "not breaking" when attacks into it lose. Record each breach site (`TurretTarget`) and what was tried there;
   log `apex: siege`. Counter: metal lost to static guns per minute.
2. **Stop feeding the wall.** While a site is not breaking, the army does not walk into its reach. It holds outside
   it until the site is softened. Counter: losses to static guns drop.
3. **Break tools priced by the siege.** LRPC (exists), EMP launchers, Junos against their jammers, and super
   artillery with the energy storage it needs, all valued by the defence metal in reach of the breach site.
   Counter: defence metal killed at the site.
4. **One target.** Nukes, LRPC, tactical missiles and bombers (AA at the site first) all on the breach site. The
   army goes in when the site's standing defence has fallen, or right after an EMP volley.
5. **Pivot.** A site that does not fall after a full try gets marked as failed, and the next try picks another
   site or another tool.
6. **Vehicles** in the mix (separate change).

Gate: the turtle opponent, both factions, plus the usual v0.5.11 head-to-head and BARb, judged by the worst
matchup.

## Built 11-12/13, measured, removed (results/release-gate/2026-11-13-*, results/README.md; code in results/patches/c494a6f08c-f1deeac46b34.patch)

Steps 1, 2, 3, a part of 4 (warheads at the site) and 5 were built as `military/breach.as` and deleted on 11-13.

- **No trigger told a fortress from a few towers.** Four were tried; each either fired in ordinary games or never
  fired against a real wall. Losing on their ground: on in 34 of 48 seats vs v0.5.11 (a lost army fight named the
  nearest tower a wall). Wall seen bigger than our army: on before any try. Wall bigger than the army we build: never
  on against a live turtle (rich income makes that army huge). Paid the wall's worth to its guns: on in 29% of
  ordinary-game readings. The site is the gun cluster where our units died: median 1.4k metal in ordinary games,
  3.5k inside a 74-138k fortress, so its size cannot separate them either.
- **Holding the army out of the wall's reach (step 2) is wrong.** Against the live turtle the army is what broke the
  wall when it broke (seed 22: 46k and 38k of wall killed with the breach off; 2k with the keep-out holding 7-18
  attack groups out).
- **The tools did not do the cracking.** Against the live turtle both arms built 1-3 LRPCs, Junos, EMP launchers and
  4-6 nuke silos (income topped up); wall killed by minute 25 stayed 1-12k in most games either way. Silos make one
  warhead at a time, and the warheads went to the biggest building cluster, not the gun line.
- **Ordinary games paid for it:** vs v0.5.11 at +50, same seeds: breach on 4 W 9 L; off 10 W 8 L; later versions
  6 W 10 L and 6 W 13 L.

What stays: the live-turtle test (`tools/scenarios/fortress3_{arm,cor}.json`: the wall belongs to the test turtle,
which rebuilds and adds guns; `apex_test_turtle=1` makes a seat's plants build constructors only; deathmode
neverend; scored by wall killed by minute 25). Its outcome is all-or-nothing (the same seed killed 46k of wall in one
run, 660 in the next), so a change needs many seeds there.

Next attempt, if any: start from the army (mass and commit at one weak point, which is what broke the wall), not from
the tools; the trigger needs a measure of the whole fortification, not the cluster where units died.
