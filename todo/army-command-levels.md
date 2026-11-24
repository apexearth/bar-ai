# Army command levels: general, tactical, squad

His 11-21, after the army model lost 0-12 to our own army in 40-minute games:
- Groups shouldn't decide alone. Armies have ranks, and each rank thinks at a different level: squad,
  tactical, strategic.
- An enemy group coming at our base is a risk: it can destroy so much of our base, and the closer it gets the
  bigger the risk. Advantage is the same thing applied to them.
- We need a planner: a risk-management simulator whose objective is to get bigger and stronger, with a
  healthier economy all game, without losing it or dying. If you take out the enemy you can't lose. If you
  can't, keep them from taking your economy out.
- Land value: the important plots of land. The objective is to control them, until we control the whole map.
- Strategy has to be inferred from watching. Players might punch strong units straight through the defences
  to kill the economy behind, or slow-push and squeeze the land away from the enemy.
- Late-game data: our bot games with humans in them (take the winning behaviours), and online 8v8 team games.
  At +50 our games reach the late game sooner than players' 1v1s.

## What the model has now (11-21)

- ArmyNet, 2.0 M weights: a 3-scale map encoder (64/32/16), units as tokens through 3 attention layers, one
  cross-attention to 16x16 map tokens.
- Forces: each force pools its own members (mean, max) and decides alone (click, kind, place, shape). No force
  sees another force's choice.
- Enemies appear only as grid paint: seen units (7), remembered buildings (8), remembered guns (11/12),
  velocity (20-22).
- No risk, advantage or land-value field. No strategic level. Scalars carry the minute, our army metal,
  seen enemy metal, and both incomes.
- Labels are local (the next click, its place, 60-s goal). Outcome credit goes per order (dec_score). v_head
  predicts trades, map-share changes and the result, but nothing decides with it.

## The design

1. **Fields, as inputs** (same code live and in training):
   - **Land value:** income per cell from metal spots, geos, and eco standing there.
   - **Risk:** for each enemy group, its metal times how soon it can reach that cell (travel time at its
     speed), times our land value there.
   - **Advantage:** the same with the sides swapped.
2. **General** (strategic, every ~30 s): reads the whole state (fields, both economies and their trend, tech,
   army totals). It outputs an allocation map: the share of our army metal that should stand in each 16x16
   region about 2 min from now. That's continuous, never a menu. A punch is the mass concentrated deep at one
   point; a squeeze is a wide front moving forward. Both are shapes of the same map.
   - **Label, observable:** where the player's army metal actually stood 2 min later. That's how we infer the
     strategy from watching without naming it.
   - **Weight:** how that period went for land control, economy and losses, against what was expected from
     that state, so the shapes that worked teach most.
3. **Tactical:** forces attend to each other, to enemy groups as tokens, and to the general's map before each
   picks a place. In training the hindsight map is given (teacher forcing); live it's the general's.
4. **Squad:** the existing footwork (lines, arcs, kiting, retreat).
5. **Planner:** at the general's level, decisions are few, so sample several allocation maps and score each
   with the value head (economy growth and land control minus risk) before choosing. Only after the value
   head is checked on held-out games.

## Data

- His games (471 demos, median 26 min, humans vs Apex): recording, human sides only, weighted by moment.
- Long public duels down to OS 20, and long public team games (pick --preset team --min-minutes 25).
- State over clock: the minute is a scalar input. Under +50 a minute-15 economy looks like a players'
  minute 25. Test: blank the minute and compare held-out loss; drop it if nothing is lost.

## Order, each step measured

1. Data (running).
2. Fields as input channels. Measure held-out place CE and act, then gate 3 vs our own army.
3. General as an auxiliary head. Measure that it predicts the 2-min army map better than baselines (current
   mass, mirror). Then feed it to the forces.
4. Tactical attention (forces + enemy groups).
5. Planner.

Capacity test (3 sizes, same data) is queued on the Mac and tells whether depth matters at all.
