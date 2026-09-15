# Defence plan — one front the enemy cannot go around

2026-09-15. Why our static defence loses, read from the code and from games,
and the order of work to fix it. Each step names the number that proves it.

## The principle

A defensive line wins by overwhelming the attack; a scattered defence is
overwhelmed piece by piece, because the attacker picks where to hit. So the
value of a gun is not what it protects — it is how much it raises the
**weakest** approach into our territory. A perimeter with one heavy cluster
and an open flank is worth its open flank. That is not 360-degree cover of
one base: a bearing the enemy cannot walk (cliff, water, map edge, an ally's
territory) is already closed and earns nothing.

Facts the plan rests on:

- Nano turrets behind a tower repair it while it fights, so it survives an
  attack it would otherwise lose; they also rebuild what falls.
- Cheap things in front of the mains (dragon's teeth, light towers) absorb the
  first volleys and split the attacker's fire; the mains behind them do the
  killing. Long-range guns behind the line hit the attacker before it hits
  the line.
- Shields in the line stop tank shells; against a tank army the line holds
  with shields and does not without.
- A line built on the base hull leaves no room to expand. The line stands at
  the frontier; the base grows behind it, and the old line is reclaimed when
  a new one stands further out.
- Choke points are where a line is short and cannot be flanked; a line
  across open ground is only as strong as its longest unheld stretch.

## What the code does today (`manager/brain/market/protect_*.as`)

1. **Every player defends itself.** The wall is the hull of OUR OWN buildings
   pushed out by half a light-tower range (`protect_wall.as`, `WallPrep`),
   and any slot closer to an ally's home than to ours is dropped as "theirs".
   The one team-aware site is a single "ally-front post" in front of the
   ally nearest the enemy (`protect_fill.as`). A player behind an ally
   therefore rings its own base, inside the team's territory, and that ring
   is useless until the front ally is dead.
2. **Guns go where we were hit, not where we are open.** A slot's price is
   prevented loss: threat × stake × cover shortfall, with threat read from
   sightings and our own loss field. A bearing with no loss and no sighting
   reads threat ≈ 0 and is gated out (`GATE_SITE_THREAT`); only the budget
   pull floors it to 1. The election takes the argmax, so the hot bearing
   gets gun after gun and the quiet flank gets none — the enemy walks around.
3. **The line hugs the base.** Wall radius = building rim + standoff, capped
   at 2.5 × the RMS spread of the buildings; the front line stands at the
   furthest capped mex, bounded by halfway. Both are one player's numbers.
4. **No layers.** Every defence def competes for the same slot with the same
   price; nothing puts cheap in front of strong, nothing puts nanos behind
   the line, teeth are placed only at an already-defended gate
   (`protect_teeth.as`). Shields are not in the defence catalogue at all.
5. **Chokes are the engine's** (`ai.GetChoke*`, `Front::GateChokes`) and only
   the chokes between one player's home and the enemy count.

Measured (`tools/wall_check.py --ally 0`, the whole team's buildings as one
hull, 24 bearings, a bearing "held" when a gun stands within the wall band
of the team's edge):

| game | our guns | inside the team hull | bearings held | enemy-facing arc |
|---|---|---|---|---|
| Greenest Fields 8v8, 28 min (`def8/greenest-D0-s21`) | 104 | 79% | 11 of 24 | bearing 23 ±3: five of seven held, by two players; 20 empty |
| Supreme Isthmus 8v8, 32 min (`seat8/isthmus-B19-s4arm`) | 62 | 65% | 13 of 24 | bearing 8 ±1: **all three empty**; the rear (map-edge) arc 15–23 held by the seat |

Four fifths of the metal spent on defence stands inside the team's own
territory — each player's ring around its own base — and on Isthmus the
three bearings the enemy actually comes from are the open ones. Per player
(`defence_pos.py`): median gun position 0.04 of the way to the enemy on
Greenest, −0.02 on Isthmus, 0% beyond a quarter; on Isthmus our front
players ended with 0–8 defence buildings each against BARb's 21–49.

## Status 2026-09-15 (commit 9690d580)

Built: steps 0, 1, 2, 5 and the front/support layers of 4; step 3's
frontier (team's furthest capped mex, then as far forward as ground the
front-line model calls OURS, up to halfway). `apex: gaps` is the live
instrument; `wall_check.py --ally N` the post-game one. Greenest 8v8 +100%,
four seeds: 4/4 wins at 14-21 min (baseline: BARb ahead at the 30-min cap),
median gun position 0.14-0.15 of the way to them (was 0.04), static
defence 4% of spend (was 11%, most of it interior rings), army 23% (was
10%). Team closure is still 0.17-0.33: the defence target is not met in
either build (def=2775/10463 at 20 min) -- the auction spends on army and
economy first, and the wins say that is not wrong on this map. Open: the
shield and support-row nano fired rarely (lines short-lived); reclaim of
interior rings not observed; teeth are a preference gain, not a price.

## The plan, in order

Every step is measured on 4–6 Greenest Fields 8v8 games (+100%, 30 min)
with `tools/wall_check.py --ally N` (team closure = share of walkable
bearings held), `tools/defence_pos.py` (where the guns stand), and
`tools/deaths.py` (which bearing the killers came through). Baseline is
`def8/greenest-D0-s21`; then one step at a time.

### 0. Instrument: the team front

`wall_check.py --ally` reads the team hull from the position gadget after
the fact. The AI needs the same thing live: publish each player's building
hull to the blackboard (the `homex/homez` channel already exists) and read
the **team hull** — the union of every ally's rim — in `protect_wall.as`.
Log per player which team bearings its guns cover. This is the number the
whole plan moves.

### 1. One front for the team

Derive the wall from the team hull instead of the player's own. Slots on
the team frontier are offered to every player; the walk term already
prefers the nearest builder, and a slot in flight by an ally is not offered
twice (blackboard claim by slot id). A rear player's guns then stand on the
team's edge, which is exactly the "defences for our allies" request. The
defence budget stays a share of each player's own assets + army, so the
seat funds the front as it grows (its 1k-income ramp already lifts
`DefenceTarget`).

Proves itself when: `defence_pos` median for rear players moves from ≈ 0 to
≈ the front players' value, and team closure rises with no fall in the
front players' own count.

### 2. Closure is the price

For wall slots, replace argmax-of-prevented-loss with the weakest-bearing
rule. Each walkable bearing into the team hull carries the stake an army
entering there reaches before it meets fire (walk the bearing inward until
`CoverAt` ≥ the wave; sum the assets passed). A slot's value is how much it
lowers the **maximum** over bearings of that reachable stake — the gun that
closes the worst gap wins, whether or not we have been hit there. The loss
field stays as urgency (it scales the wave the bearing must stop), never as
the gate.

Proves itself when: closure rises toward 1 on walkable bearings while the
total defence metal is unchanged; `deaths.py` shows fewer kills by units
that entered through an unheld bearing.

### 3. The line stands at the frontier, with room behind it

The line's radius is the team's frontier — the furthest of the team's capped
mexes on that bearing, the choke on that lane, or halfway — not the
building hull. The base-hull ring survives only as the rear fallback with a
lower stake (it shields nothing the frontier does not). When the frontier
steps out a full quantum, the old row is offered to reclaim (the stranded
retirement in `want_reclaim.as` already does this for towers the wall has
grown past; extend it to rows).

Proves itself when: median defence position moves toward 0.3–0.5 and
`build_timeline` shows eco structures landing inside the line, not around
the guns.

### 4. Layers

Three bands from the front inward, placed from the line's own geometry the
way the two rows are today:

| band | what | priced by |
|---|---|---|
| teeth | dragon's teeth, light towers, a light-tower reach ahead of the mains | the attacker's fire it absorbs: its HP against the wave's DPS = seconds the mains fire for free |
| mains | HLT / Guardian / Pulsar class, later Annihilator / DDM; long-range artillery a row behind | prevented loss as now |
| support | nano turrets within nano range behind the mains; shields when the enemy census is tank-heavy; radar/jammer per line segment | repair rate × mains' HP at risk; shield: tank share of their army × mains behind it |

Shields enter the defence catalogue (`ProtClassOf`) so the census can price
them. Nanos at the line are the same lathe the base uses; they also rebuild
the line without a con walking out.

Proves itself when: the line's composition per band matches the table and a
line that is attacked loses less metal per enemy metal than before
(`fight1v1.py` trade ratio at the line).

### 5. Chokes and walkable approaches

Replace "chokes between my home and their base" with "walkable approaches
into the team hull": for each bearing of the team hull, test ground
pathability at the hull edge (the engine's path tools; the ally-lane and
off-map tests already close bearings). A choke on an approach shortens the
line to the choke's width; an approach with no choke gets the full row.

Proves itself when: on Isthmus and Greenest the number of held approaches
equals the number of walkable ones and no slot stands on a cliff bearing.

### 6. Old items this absorbs

Defences for allies past 500 income (step 1), outer-mex guns (step 2 —
a mex outside the line is a bearing with stake), commander pen placement
(step 3 — the pen is inside the line), fighter escorts and AA ride on the
same bands (support row).

## Not in the plan

- No 360-degree ring around a rear base. A rear player's guns go to the team
  front; a raid on the rear is the army's and the AA's job.
- No count of towers per player, no "defence at N income". The budget stays
  a share of what we own; the plan changes only where and in what order it
  is spent.
