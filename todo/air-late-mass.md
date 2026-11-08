# Late-game air that grows with the economy

His 11-07: "mid-game air attacks are fantastic ... but our late-game air tends to disappear and become very
irrelevant"; "100 bombers attacking the enemy, that would be a very big delight to see"; "you get more and more
wealthy, you attack with more and more air, you just keep going bigger and bigger"; "if the enemy has lots of AA we
can specifically target the AA. once we kill it we are more free to dominate. can also use emp launchers and
similar".

Measured 11-07 (scratchpad airtime.py, per game, our two seats):
- 60 min at +0: bombers built 2.5 / 7.3 / 12.8 / 10.0 / 9.1 per 10-minute block from minute 10; strikes of median
  2-3 bombers (max 28); from minute 20 the air loses about twice what it kills.
- 30 min at +50: 31 bombers built in minutes 10-20, 20 in 20-30 while income roughly doubles; median strike 3;
  minutes 20-30 kill 14.6k for 17.7k lost.

His 11-07 on the airframes: bombers release before they reach the target and deal burst damage gunships often
cannot; the heavy gunships (Dragon, Tyrannus) are genuinely very strong but cost ~20x a bomber. Measured the same
day: the advanced air plant buys Ape gunships (priced ~114k on its list) and almost no Hurricanes, while the air
module wants 13-23 bombers and holds 0-3 all game.

His 11-07 on flak: aircraft bunched into a tight ball take huge splash damage from flak; ground units never pack
that tight. A massed wave must fly and drop spread out, not as one ball (C++ CBombTask::PlanSpread already gives
each bomber of a focused wave its own aim at the drop -- the flight in is the open question).

His 11-07 on routing: dodging their AA funnels our planes into a tight corridor, and they fly it piecemeal, not
together -- if flak sits on that corridor they die one by one. Past a point the AA is too thick to route around at
all, and the only option is to kill it.

Fighters too (his 11-07: "ensure we have enough fighters too"): the same heartbeat reads fighters 0-1 held against
8-15 wanted all game -- the same starved production, and the bombers' escort and air control depend on them.

His 11-07: "strikes against anti-air can unlock much more valuable strikes later on." The strike price today
(nnair.as NaEval: kill of what is in the cell, loss on the path) is one strike deep: killing AA earns only the AA's
own metal, never the cheaper path it opens to the prize behind it. An AA cell's worth should carry the later
strikes it unlocks -- the drop in path AA to the best cells behind it, times what those strikes then net.

His 11-07: "killing enemy eco is a win far greater than just what that eco cost". NaPrizeOf already prices a
dead eco building at its metal plus its output until a constructor walks out and rebuilds it; it misses the
compounding our own eco pricing charges (the growth premium apex_mex_growth / apex_energy_growth on the same
stream). Their eco should be priced with the premium we put on ours.

What it wants:
- the wing sized to beat their AA where it strikes (mass until the wave saturates it), and production that grows
  with income rather than falling;
- their AA as a target in its own right when it is what stands between the wing and the base -- bombers on the AA
  first, or EMP launchers / tactical missiles / artillery on it -- then the wing has the sky;
- ties to [frontline-hold](frontline-hold.md) (the coordinated break uses the same strike pieces).

Measured 11-07 (40-minute games at +50, scratchpad bomberfate.py): ~58 bombers built a game to minute 40, ~52
die, 80-86% over their half, 94-98% to a killer we never saw. Holding the net's early GOs (apex_wing_rule) and
building the wing (apex_wing_build) together scored -0.49 (t -1.2): the rule itself approves small strikes because
NaEval prices only the AA it has SEEN (cellAA). The strike price needs the AA it cannot see -- what stood there when
last seen, where our strikes died, their AA spend we have not located.

His 11-07: "it's complicated, sometimes the bombing might break a front line and unlock an army attack or an eco raid,
it's never simple." A strike's worth is what it opens, not only what it kills: the AA unlock (NaAACands) is one
case; a front line broken ahead of a team push (the existing air-breach cell, his 10-07) and an army or defence that
blocks an eco raid are the others. The same with/without pricing on the follow-up (push, raid, next strike).
