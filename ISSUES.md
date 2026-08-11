# Open issues — what is wrong with this AI right now

What is broken or missing, with the evidence for it. `CHANGES.md` says what was
done; `USER-FEEDBACK.md` is the standing brief; this file is the live list.

---

## 1. We do not press an advantage. We chip.

**apexearth, 2026-08-09, watching 8v8 vs `BARb:stable:medium` on Ancient Vault:**

> "We are not nearly aggressive enough in our games. We don't get enough
> pressure, we need smart pushes where the pusher doesn't even take damage. This
> is medium AI, this map is not fair with the starting positions you chose, and
> we still aren't killing them. We have 4x the resources but we just chill and
> don't really care to kill them."

**Measured in that same game, from the live infolog:**

| | |
|---|---|
| killing blow flipped ON | **15.0 min** (the earliest it can) |
| team army when it flipped | 46,959 against 22,259 — a 2.1x lead |
| engagements logged | **654** |
| decisions TAKE / SKIP | 653 / 1 |
| median group size | **5 units** |
| groups of 3 units or fewer | **255 (39%)** |
| median power vs need | 129 vs 57 |
| mass quota, all game | 30 (the floor), 110 samples |

So the AI is not passive and it is not refusing fights — it engages constantly,
always at favourable local odds, in packets of five. It holds a 46,000-metal army
and commits it a hundred metal at a time.

**The mechanism is in our own code, and it is backwards.**
`military/posture.as:323` — once the killing blow is on, the attack quota is set
to `KILL_QUOTA = 10` ("attack with what we have, repeatedly",
`military/massing.as:175`). Winning therefore makes the AI attack in SMALLER
groups than the ordinary `MASS_FLOOR` of 30. The one moment it should be forming
a hammer is the moment it disperses.

The floor of 30 was itself deliberate and correct for its purpose — raiding
undefended mexes with ~10 grunts. Killing a player is a different job and wants a
different number.

**Fix to try first:** make the killing-blow quota a concentration, not a
dispersal — one push that outnumbers everything they can field, tunable so it can
be A/B'd (`apex_kill_quota`). Watch for the known trap in the other direction:
raising `minAttackers` globally scored 0-10 historically, so this must stay
gated on `gKilling` (past 15 min, 1.8x army lead) and never touch the raid floor.

**Test map: Ancient Vault v1.4**, 8v8, us top-right, them bottom-left, box size
0.45. apexearth: "perhaps this is a good map for testing/improving our AI's
overall aggression". It is 20x30, area 600, and the biggest map installed with
**no water at all** (min height +300 — `GetMapMinHeight` via unitsync ranks
these; every 28x28-and-larger map here dips below sea level).

    python tools/run_match.py --a Apex:apex:hard_aggressive --b BARb:stable:medium \
        --map "Ancient Vault v1.4" --per-side 8 --sides random --seed 6102 \
        --boxes trbl --box-size 0.45 --minutes 75 --watch --speed 5

---

### 1b. The deeper cause: we buy a fifth of the army they do

Measured 2026-08-09, 6 games, 8v8 Ancient Vault vs `BARb:stable:medium`,
`composition.py`:

| share of metal | apex | BARb medium |
|---|---|---|
| **army (real)** | **22.8%** | **51.9%** |
| static defence | 19.4% | 10.3% |
| constructors | 10.4% | 5.1% |
| factories | 8.1% | 8.4% |

Apex out-produced them — 45,287 metal per player against 35,368 — and still
fielded less than half the army share. It also held 23 T1 constructors per
player to their 7. Top sinks were `coradvsol` 18.5%, `corthud` 14.7%,
`cornecro` 12.8% (rez bots), `corfus` 8.3%; theirs were `corsolar` 12.4%,
`corthud` 12.2%, then four more combat units.

**6 of 48 apex player-games ended wiped out, against 1 of 48 for medium.**

This reframes issue 1. Concentrating the army into bigger pushes worked as a
mechanism (44% of engagements were 15+ units, against 6% before) and changed the
result very little, because the army being concentrated is a fifth of the metal.
Pressure cannot come from spending the enemy's army budget on solars, rez bots
and turrets. The quota was the right lever for the symptom and the wrong one for
the cause.

Do not "fix" this by cutting economy blindly — the 2026-08-01 finding is that
every rule here displaces something. But 19.4% on static defence while losing
players to wipeout says the defence is not buying safety either.

### 1c. Army share does not move. Three arms, three ways, same 23%

6 games each, 8v8 Ancient Vault vs `BARb:stable:medium`, 40 min, +50:

| arm | army share | wiped out | K/D |
|---|---|---|---|
| `kill_quota=300` (concentrate) | 22.8% | 6/48 | 1.14 |
| `kill_quota=10` (chip, control) | 23.9% | 8/48 | 1.09 |
| rez bots cut to stable's 0.05 | 23.6% | 9/48 | — |
| BARb medium, all three arms | ~51% | 1-2/48 | — |

Cutting the rez bot from 0.50/0.30 to 0.05 -- a unit that was 12.8% of all metal
-- moved army share by 0.8 points, i.e. not at all. So the metal did not follow
the ratio into army; it went somewhere else in the same non-army categories.

**That invariance is itself the finding.** Army share sits at 23% however the
factory ratios are set, which says the constraint is not what the factory is told
to build. Candidates, in order of size: the factory is starved of metal because
builder work is spent first (static defence 18.4%, constructors 10.0%, and in a
hosted game 63% of `advcon-idle` samples carried `mEmpty=1`); or factory uptime
itself is the cap.

Next test should measure FACTORY METAL PULL against builder pull, not another
ratio.


### 1d. Benchmark across five team sizes, 2026-08-10

12 games per bracket vs `BARb:stable:medium`, 20 min, +100, size-matched dry maps
(Copper Hill 1v1, Boreal Falls 2v2, Painted Desert 4v4, Adamantium Factory 6v6,
Ancient Vault 8v8). The 1v1 bracket ran with `apex_solo_stock=0` so it measures
OUR rules rather than the stand-aside default.

| bracket | wins | army vs theirs | metal vs theirs | waste | T2 mex | K/D | kill/metal |
|---|---|---|---|---|---|---|---|
| 1v1 | 0 | 0.87x | 1.10x | 12.8% | 12.1% | **0.30** | 0.060 |
| 2v2 | 0 | 0.88x | 1.36x | 9.7% | 24.1% | 0.52 | 0.110 |
| 4v4 | 0 | 0.78x | 1.23x | 1.4% | 11.2% | 0.68 | 0.164 |
| 6v6 | 0 | **0.57x** | 1.27x | 8.2% | 14.7% | 0.52 | 0.112 |
| 8v8 | 0 | 0.85x | **1.76x** | 3.2% | 23.3% | 0.55 | 0.112 |

**Zero wins and zero losses in 60 games.** Every one hit the time limit, so this
format measures economy and trade, not winning.

The shape is identical in every bracket: we out-produce (1.10-1.76x), field less
army (0.57-0.90x) and lose the trade (K/D 0.30-0.68). It is not a team-size
problem. 1v1 is the weakest and has no team machinery in it at all, which makes
it the cleanest test bed for production changes.

Waste tracks nothing sensible -- 1.4% at 4v4 against 12.8% at 1v1 -- which is
what pull-based production predicts: whether metal gets spent depends on whether
some rule happened to fire when a line came free.


## 6. Late game: we do not advance, and our own artillery is part of why

apexearth, watching a 1v1 vs `BARb:stable:hard`, 2026-08-10:

> "We aren't advancing well and these tremors kill our own advancing units just
> as well as the enemies. We are too slow to make Juggernauts and Behemoths.
> Might as well start off with a jugg and walk it straight into the enemy base
> right for their commander."

Three separate things, none fixed:

- **Friendly fire from our own artillery.** A Tremor firing into a contested
  line hits whatever is standing in it, and what is standing in it is usually
  our push. Nothing today asks whether an artillery target has our own units
  near it. `CArtilleryTask` picks by enemy value alone.
- **T3 assault arrives far too late to matter.** The gantry and the heavies are
  gated behind the same phase machinery as everything else, so by the time a
  Juggernaut exists the game is decided. His suggestion is worth taking
  literally: at a high enough economy, a single Juggernaut walked at the enemy
  commander is a better use of 20,000 metal than the same metal in T2.
- **Advancing at all.** Fixed in neither direction -- see issue 1, we chip.

Fixed the same session, from the same game:

- 9 fusions and no advanced fusion: `FusionDef()` only ever returned the plain
  tier, so the ladder had no top rung. Now climbs at 120 metal/s once three
  plain reactors stand.
- ~20 Doomsday towers late. A ceiling of 4 was added and REVERTED the same
  day -- apexearth: "no no no don't you ever do such a thing like limit to 4
  max T3 towers." The count is not the problem; building them instead of
  advancing is. What bounds them is the Brain's per-copy value decay, not a
  number.

## 2. Pushes should not take damage on the way in

**apexearth:** "we need smart pushes where the pusher doesn't even take damage."

Related but distinct from issue 1: not just *bigger* pushes, but pushes that
arrive intact. The pieces that exist and are not being used together:

- `apex_attack_threat_mod` — what an attack party pays for contested ground in
  the path query. Raising it makes the flank the shortest path, the way
  `RaidTask`'s `RAID_ROAM_THREAT_MOD = 8` already does for raid parties. Shipped
  at 1.0, i.e. upstream behaviour, and **never measured**.
- The map-edge preference in `AttackTask.cpp` (`apex_edge_band` / `apex_edge_bonus`)
  already prefers economy on the rim. The routing half of "go around the edge"
  was never built.

---

## 3. Stealth and sight are not used to set up attacks

**apexearth:** "Maybe some better use of the stealth units to provide sight would
help AI be even more cheeky/evil to players."

Nothing today pairs a scout, radar or cloaked unit with an attack party to see
what it is walking into. `apex_scout_threat` exists (how hot a metal cluster may
be and still be scoutable) and has never been enabled or measured at 8v8. The
mobile radar escort (`factory/eyes.as`, 2026-08-09) follows the army for
targeting, not for reconnaissance ahead of a push.

Untouched: cloaked units as spotters, and using vision to pick a target that is
undefended *right now* rather than one that scored well when the task was made.

---

## 4. The late game produces no moments

See `docs/16-big-plays.md` for the full plan. Summary: nukes fire one at a time
the instant they are ready (`super fire armsilo stock`, 427 launches in one
hosted game), which one anti-nuke absorbs forever. Fifteen simultaneous launches
need fifteen silos, because a silo reloads in 30 s and an interceptor re-fires
every 2 s.

Stage 0 of that plan — actually building the silos — has not started.

---

## 5. Unblock's escape direction can pick a lane that stays blocked

From the 2026-08-09 hosted game: `armbeaver #9079` needed **six** clearing
orders, eating a nano turret each time and staying stuck. Detection is right
(9 firings, no false positives, one unit had 86 of our buildings ringed around
it); the direction heuristic picks the thinnest wall by structure count, which is
not the same as the way out.

Also, 86 of our own buildings around one unit is the base-sprawl complaint in
`USER-FEEDBACK.md` showing up as a number.
