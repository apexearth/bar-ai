# Multiplayer findings, 2026-08-02

Two hosted games, 12 and 11 apex AI teams. Observations from the live infolog
plus apexearth watching. **Measured** = read off the log. **Hypothesis** = not
yet verified, do not act on it without checking first.

---

## 1. Slinging drowns the tech lead — MEASURED, highest impact

Followers keep feeding the designated lead long past the point it can spend
anything, while starving themselves.

Game 1 (47 min, 12 teams, lead t17). Slinging ran 5.1m -> 14.7m and moved
**~269,000 metal** into one team:

```
t21 105,117   t18 34,804   t20 34,158   t13 25,521   t12 24,262
t19  17,316   t15 11,667   t23  9,031   t22  4,102   t16  3,100   t14 10
```

That is ~450 metal/s of donations into a player whose own income was 32-56/s.
It could not spend it:

```
 8.0m bank=1735/1300 army=0      20.0m bank=10827/1300 army=0
14.0m bank=1847/1300 army=0      22.0m bank=17328/1300 army=0
```

Over storage from minute 8 -> wasting continuously, and **army=0 for fourteen
minutes**. The advanced plant cost 2,800; the other ~266,000 bought nothing.
First gift did not land until 16.8m.

Game 2 reproduces it inside two minutes of slinging starting. At 7.0m the lead
t20 is at **1305/1300 (cap)** while nine feeders sit at 1-40 metal:

```
t14 bank=11   t21 bank=5   t23 bank=11   t24 bank=1   t16 bank=40
```

### Cause

`UpdateSling` has no saturation check. The comment in `military.as` says one
was removed because `ai.GetTeamMetalFill()` returns 1.0 unconditionally — the
check was right, only its data source was broken.

### Fix

The lead already publishes `TV_ADV`, `TV_READY`, `TV_MEX` over
`ai.ReadTeamValue`/`WriteTeamValue`. That channel is AI-to-AI and **works in
multiplayer with no gadget** — the election proved it this game. So:

- publish the lead's metal fill on the same channel;
- stop slinging when the lead is above ~60% storage;
- stop slinging once the lead's plant is *finished*, rather than running to the
  flat `RUSH_GIVEUP` 15-minute clock. Right now it keeps feeding long after the
  thing it was funding exists.

---

## 2. Metal economy is weak even with a +50% bonus — MEASURED

Game 2 at 7.0m, 11 teams, all with +50% resources:

```
mInc per team: 12, 18, 20, 22, 23, 24, 27, 34, 35, 36, 41   (~292/s total)
eInc per team: 338-582                                       (energy is fine)
```

~292/s bonused is ~195/s unbonused across eleven players — under 18/s each.
apexearth: "only slightly above the humans on eco". Energy is healthy, so this
is metal extraction/expansion, not power.

Likely entangled with #1: nine teams holding near-zero banks cannot queue
expansion. Worth re-measuring once slinging is capped, before treating it as a
separate problem.

---

## 3. Air attack breaks off against a single AA building — CAUSE CONFIRMED

apexearth, game 2 at ~7m: an air attack disengaged as soon as one human started
building a single AA building. "We could have crushed his front line if we
committed."

**A nanoframe projects threat it cannot deliver.** In
`map/ThreatMap.cpp` the under-construction check is commented out:

```cpp
float CThreatMap::GetThreatHealth(const CEnemyUnit* e) const
{
//	if (e->IsBeingBuilt()) {
//		return 0.f;
//	}
	const float health = e->GetHealth();
```

and the caller scales threat by it:

```cpp
const float healthMod = sqrtf(health + shieldArray[...] * SHIELD_MOD);
e->SetInfluence(e->GetDefDamage() * healthMod);
```

`GetDefDamage()` is the **finished** tower's damage. Health rises as the
nanoframe builds and the scaling is `sqrt`, so a **25%-built AA tower projects
half of a completed one's threat** while being unable to fire at all. One AA
nanoframe is therefore enough to push local air threat past what the squad will
fly into, and it disengages — exactly the reported behaviour.

`quota.thr_mod.static = 1.2` compounds this by a further 20%, but is not the
root cause and should not be touched first: it affects every unit type.

### Fix

Uncommenting those three lines is the fix, but it is **C++** and needs a DLL
rebuild (`docs/06-building-the-dll.md`, patches in `game-patches/circuitai/`).
There is no script or config lever for per-unit threat, so this cannot be done
at layers 1 or 2.

Worth care: zeroing nanoframe threat outright also means the AI ignores a
half-built nuke or fusion when deciding where to attack, which may be right for
air raids and wrong elsewhere. Scaling by build progress instead of zeroing is
the conservative version.

Note the retreat config (`retreat.fighter = [0.5, 0.55, 1.0]`) is
**health**-based and is not this — the units were not damaged.

---

## 4. T1 lab reclaim fires far too late — MEASURED

Game 1: plant placed 5.1m, `reclaiming T1 lab` at **14.0m**. The point is to
feed the lab into the plant that replaces it; nine minutes later it is pointless.

Correction to an earlier reading of this: the gate is **not** "plant requested".
`UpdateRushReclaim` requires `AdvCounterpart().count > 0`, i.e. the advanced
plant must physically exist — `count` is incremented in `RegisterTeamUnit`,
which runs for the nanoframe. That gate is deliberate and correct: an earlier
version reclaimed the lab on the mere *preference* to build a plant, leaving the
lead with no factory at all, and CircuitAI answered by building a fresh T1 one.

So the 9-minute delay means the nanoframe did not register until ~14.0m, even
though `rusher building advanced plant` logged at 5.1m. The gap between choosing
the plant and actually placing it is the thing to investigate — the same gap
showed up in a benchmark run as "requested 5.1m, BARAI_T2START 8.1m". That
placement latency, not the reclaim, is the real issue.

---

## 5. Multiplayer does not run BAR.sdd — MEASURED, affects all future analysis

Hosted games load from the **engine** folder:

```
AI/Skirmish\BARbApex\apex\config\hard_aggressive\*.json
AI/Skirmish\BARbApex\apex\script\hard_aggressive\*.as
```

not from `BAR.sdd/luarules/configs/`. Chobby plays the rapid `.sdp` packages,
which do not contain our tree. Consequences:

- **No dev gadgets.** `BARAI_LEAD`, `BARAI_STATS`, `BARAI_T2START`,
  `BARAI_COMMLOST` are all zero in a multiplayer log. `tools/trace_flow.py`
  cannot read these games.
- The engine-side folder is what must be current for multiplayer. Note the AI
  is deployed as shortName **`BARbApex`**, while `tools/deploy_ai.py` still has
  `SHORT_NAME = "BARb"` — worth confirming which path a deploy actually
  refreshes before trusting it.
- The lead election survives this because it runs on `ai.ReadTeamValue`, not on
  the gadget. Anything built on a gadget will silently do nothing online.

---

## 6. Trap: the sling log format changed — process note

The message is now `"apex: sent <n> to lead <t> (total <n>)"` — no "metal" —
and is rate-limited to **1 line in 40**. A grep for the old
`"sent .* metal to lead"` returns nothing and reads as "slinging never fired",
when in fact ~269,000 metal had moved. Cost a wrong conclusion this session.
Count `apex: sent .* to lead` and read the running `(total N)`.

## 7. Air raids never reach mass — MEASURED

apexearth: "I'm not seeing much for those big air raids, would be fun to see
that sort of thing... keep the enemy on their toes." Game 2, 36 minutes, 11 AI
teams. **Exactly one air strike happened, at half strength:**

```
[17.0m t17] air  2/12 bombers, 1/8 fighters  plants=1,0 cons=1  enemyAA=1325
[18.0m t17] air  4/12 bombers, 3/8 fighters  plants=1,0 cons=1  enemyAA=1775
[19.0m t17] air  6/12 bombers, 4/8 fighters  plants=1,0 cons=1  enemyAA=1460
[19.0m t17] air strike -- deadline bombers=6 fighters=4 enemyAA=1460
```

That is the only `air strike` line in the game. Three things stack up:

- **One player, one plant.** `plants=1,0` for the whole build-up. Producing
  12 bombers + 8 fighters from a single air plant takes longer than the
  deadline allows, so the quota is effectively unreachable.
- **The strike fired on the deadline, not on readiness** — 6/12 bombers and
  4/8 fighters, i.e. half a squad, into `enemyAA=1460`. That is feeding units
  into AA rather than a raid.
- **It never recurred.** Seventeen minutes after the one strike, nothing.
  Whatever is meant to restart the cycle did not.

### Interaction to be careful about

`MayOpenAir()` allows exactly **one** air opening per ally team
(`AirSlotTeamId()` = highest team id), regardless of team size — that is the
"1 air max on 8v8" rule requested on 2026-07-29 and it is working as asked
(game 2: three teams swapped `armap`/`legap` to ground, "air slot is team 24").

But note the air *assassin* in this game was **t17, not the air-slot team t24** —
so the raid force comes from a later switch, not from the opening. The opening
rule and the raid capacity are separate paths; relaxing one does not
automatically fix the other, and the "1 air max" request was about the opening.

### Directions, none tested

- Scale raid capacity with team size the way `TechLeadQuota()` scales the tech
  lead — on an 11-player team, one air plant is not enough to field 20 aircraft
  in a useful window. More plants for the assassin, or nano assist on the air
  plant, before adding a second air player.
- Make the strike wait for mass, or scale the quota to what is reachable.
  Striking at half quota into 1,460 AA is the worst of both: it spends the
  aircraft and does not threaten anything.
- Find why only one strike occurred in 36 minutes and make raids repeat — the
  stated goal is sustained pressure, not one sortie.
- Relatedly, see #3: the disengage-from-one-AA-building report is probably the
  same subsystem. `enemyAA` here was 1,325-1,775, so AA avoidance and raid
  massing should be looked at together.

---

## 8. When clearly winning, scout for the last commander — FEATURE REQUEST

apexearth: "when we're clearly winning we should make T2 radar planes and find
the last com so we know where to send our armies."

Game 2 was decided by ~25m and ran to 36m+ with no such sweep. Late game the
army has nothing to chase, and a surviving commander can rebuild.

### What exists

- `Factory::LateGame()` already exists — `ai.frame >= LATE_GAME_FRAME` OR a
  fusion standing. A reasonable trigger, though "late game" is not the same as
  "clearly winning" and the request is the latter. A winning test would need
  something like our army/eco versus theirs, which `aiEnemyMgr` can supply.
- **Nothing hunts commanders.** The only commander logic in `military.as` is
  `Commander::UpdateCaution()`, which is about protecting OUR commander.

### Units, checked against the pinned game tree (not guessed)

```
armawac      metal 175   radar 2500   air
corawac      metal 180   radar 2400   air
legwhisper   metal ---   radar 2400   air
```

All three are air radar platforms and all are **cheap** — under 200 metal. A
handful is affordable at any point past the early game, so the cost objection
that rules out most late-game additions does not apply here.

### Notes before building it

- Air scouts die to AA, and #3/#7 say AA handling is already the weak spot. A
  radar plane loitering over a defended base will be shot down; the sweep
  probably wants to skirt rather than overfly.
- "Send our armies there" is a target-selection change, which is a much bigger
  intervention than building the scouts. Worth splitting: (a) field the radar
  planes and get vision, (b) act on what they find. (a) is cheap and safe to
  measure on its own.
- Watch what it displaces. Per CLAUDE.md, every behaviour added here competes
  for constructor time; at 175 metal these do not, but the army retargeting in
  (b) very much could.

---

## 9. The benchmark does not reproduce hosted-game economics — MEASURED, blocks validation

Per-team metal income at 7.0m:

```
hosted game 2 (11 AI):        12 18 20 22 23 24 27 34 35 36 41
benchmark 8v8 Comet Catcher:   4  9  9  9  7  7  5  7
benchmark + ai_incomemultiplier=1.5:  same, 4-9
```

A 3-5x gap, and the bonus modoption did not close it. Follower banks in the
benchmark sit at 0-230; in the hosted game they were the thing overflowing.

Consequences:

- **#1 cannot be validated here.** The sling waste needs an economy rich enough
  to have spare metal. In the benchmark, `spare = current - SLING_KEEP` is
  almost always <= 0, so slinging barely fires at all: HEAD slung **8 metal**
  total on seed 71, against ~269,000 in a hosted game. That is why this waste
  survived every benchmark run.
- **The benchmark control is itself broken** on this map/seed: at unmodified
  HEAD the lead placed at 15.6m, never finished a plant, gifted nothing, and
  apex lost to stable. Any A/B against that baseline measures noise.
- At 4-9 metal/s per team a 2,800-metal plant is minutes of the whole team's
  income, so "lead never finishes a plant" may be a symptom of the map being
  too poor rather than of the strategy.

### Before trusting another benchmark number

Find a map/settings combination whose per-team income at 7 minutes lands in the
hosted 12-41 range, and re-establish a baseline there. Comet Catcher 8v8 is not
that. `tools/run_match.py --modoption K=V` now exists for this (added
2026-08-02); `ai_incomemultiplier` alone is not sufficient, so the map and
player count are probably the bigger levers.

---

## 10. A surrounded player should relocate, not die in place — FEATURE REQUEST

apexearth, watching a 4v4: "green stay in his base while crazy amounts of army
was surrounding him. If he was a real player, he would have left the base. He
would have ran away to an allies' base and reconstructed over there."

Nothing in the AI does this. `Builder::UpdateCommanderSafety()` was written once
and **removed**, not disabled -- it correlated with the engine aborting 14-17
games per 20-game run, and the two bindings it used (`CmdMoveTo` outside a task
context, `GetEnemyCostAt`) are still registered but deliberately uncalled. So a
retreat has to be built on something else, or those have to be isolated and
tested one at a time in a throwaway variant first. See CLAUDE.md "Do not call".

What a relocation actually needs, none of which exists yet:
- a "this base is lost" signal distinct from the existing health-triggered
  commander retreat, which fires on damage rather than on being surrounded;
- somewhere to go -- an ally's base position. `TV_DIST` already publishes each
  team's distance to the enemy centroid, so the machinery for asking allies
  where they are is present;
- a way to move the commander that is not `CmdMoveTo`.

Deferred deliberately. Lower value than #11 and carries known crash history.

---

## 11. Defences are not built when the enemy is visibly closing in — PARTLY FIXED

apexearth: "his T1 con needs to make pretty good defenses in the base when we
see the enemies are encroaching... they're getting closer and closer over four
or five minutes, so you have plenty of time, and no good defenses were being
made."

Cause found. `CMilitaryManager::DefaultMakeDefence` walks
`num = isPorc ? defenders.size() : prevent`, and `isPorc` is true only for a
rich cluster more than 1000 elmos from base, **or** when two nearby clusters
read threat -- and that loop `continue`s over any cluster we have already
finished. Our own base under attack is therefore never "porc", so it took the
`prevent` path, which was **2**: a light laser tower and a rocket launcher.

Raised to 5, reaching corhllt / cormaw / cormadsam -- a real position.

Still open on this:
- **Bounded by income as well.** The walk also stops once total cost exceeds
  `amount.factor * min(metal, energy income)`. At the benchmark's 4-9 metal/s
  that bound may cut the ladder short before 5, so this change will show up in
  hosted games long before it shows in a benchmark.
- **The jammer is a separate path and still missing.** apexearth asked for "a
  jammer, and a shitload of towers". Jammers are not in the porcupine ladder at
  all; they hang off build_chain hubs on armanni/cordoom, which CLAUDE.md
  records as never having been built once in a 30-game sample.
- `prevent` is global, so this is 2.5x the towers wherever `AiMakeDefence` fires,
  not only at a threatened base. Towers are constructor time. Check
  `composition.py` before believing it helped.

---

## 12. Territory grid to place a defensive LINE — DESIGN, blocked on bindings

apexearth: "split the map up into a grid and build controlled territories on
that grid, then form a line on the edge of our controlled territory to block all
enemy movement from crossing into our territory. Typically you're just gonna
have defenses on the mexes and in your bases. But if you had a grid, or some way
of drawing on the map where enemies are gonna get through, that tells you where
to put your defenses."

**The engine already has this map.** `CInfluenceMap` exposes `GetInfluenceAt`,
`GetAllyInflAt` and `GetEnemyInflAt` -- ally influence minus enemy influence per
cell is precisely "controlled territory", and the zero crossing is the border he
wants to fortify. `DefaultMakeDefence` already consults it:
`isPorc |= GetInfluenceAt(pos) < INFL_EPS`.

Two things block using it:

1. **No script bindings.** Nothing on `CCircuitAI` exposes the influence map.
   The script cannot read territory at all.
2. **Unchecked indexing.** `GetInfluenceAt` does `influence[z * width + x]` with
   no bounds test -- the same shape as `CThreatMap::GetBuilderThreatAt`, which
   killed the engine at frame 3 today when sampled off-map (0xc0000005).
   **This is NOT a blocker**, contrary to an earlier version of this note:
   `AiTerrainWidth()`/`AiTerrainHeight()` are bound and `Builder::OnMap()`
   already guards positions for precisely this reason. A grid walk just has to
   use it on every cell. The only real blocker is (1), the missing bindings.

### Routes

- **C++ bindings** (`docs/06-building-the-dll.md`): expose ally/enemy influence
  and the map dimensions, clamping inside the accessor. This is the only route
  that works in a HOSTED game, and hosted games are the target.
- **Synced Lua gadget**, the way the tech-lead election and `FrontPos` went:
  compute the grid and publish border points as rules params. Cheap and safe,
  but `dev_team_income.lua` is not in the rapid package, so it does nothing
  online -- see #5.

### Note on what exists already

`FrontPos()` is a single point at 78% toward the enemy, published by the gadget,
and `UpdateFrontGun` already places the big gun there rather than at base. The
grid is the generalisation of that: a line instead of a point, and derived from
held territory rather than from a fixed fraction.

---

## Suggested order

0. **#9 get a representative benchmark first.** Nothing below can be measured
   until the harness reproduces hosted-game economics. Currently it does not.
1. **#1 sling saturation** — largest measured waste, and the fix is small and
   uses machinery already proven to work online. Implemented 2026-08-02 but
   **UNVALIDATED** — see #9.
2. **#2 re-measure economy** after #1; they are probably the same problem.
3. **#7 air raids** — the stated want ("keep them on their toes") and currently
   one half-strength sortie per game. Start with production capacity, not with
   the strike trigger.
4. **#4 lab reclaim timing** — cheap.
5. **#3 air disengagement** — verify the cause first; `thr_mod.static` affects
   every unit type, not just air. Look at it together with #7, same subsystem.
6. **#11 jammer path** — towers are raised; the jammer half is untouched.
7. **#8 late-game commander sweep** — a feature, not a defect, so it goes after
   the measured waste. Do part (a), the radar planes, on its own first.
8. **#10 relocate a surrounded player** — deferred; carries crash history.
