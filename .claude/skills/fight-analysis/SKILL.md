---
name: fight-analysis
description: Deep-dive a single BAR 1v1 match to understand why units died, which fights were taken at bad odds, whether retreats were attempted, and how tightly squads held together. Use when diagnosing combat losses, army trading, engagement decisions, or any "why did we lose that game" question — instead of running a tournament.
---

# Fight analysis — reconstruct the battles of one game

Aggregate K/D says the army trades badly; it cannot say WHICH fights were bad.
This workflow reads one game closely instead of averaging many. A tournament is
for confirming a mechanism already found here, not for finding one.

## The data pipeline

Two gadgets emit everything (installed by `deploy_ai.py gadgets`, enabled by
`run_match.py` automatically via `dev_stats=1` / `dev_combatlog=1`):

- `dev_stats_export.lua` → `[BARAI_STATS]` per-team aggregates every 2 min,
  `[BARAI_BUILD]` per finished unit, `[BARAI_COMMLOST]`, `[BARAI_T2START]`.
- `dev_combat_log.lua` → `[BARAI_DEATH]` every unit death for BOTH teams with
  position, velocity at death, and attacker (team/def/position);
  `[BARAI_ARMY]` snapshot of every mobile armed unit (id, def, x, z, hp%)
  every 10 game-seconds; `[BARAI_START]` team start positions.
- The apex AI itself logs `apex: unit-destroyed ... curTask=... fwd=...
  fhist=[f2@1234;W@5678]` — the task at death, forward fraction, and the fight
  history: `fN` = elected to fight type N (index into deaths.py's FIGHT list),
  `W` = withdraw.as ordered it back behind our guns.

## The workflow

1. **Run one game** (~45 s wall for 25 game-minutes):
   `python tools/run_match.py --a Apex:Unstable:standard --b BARb:stable:hard --map "Comet Catcher" --minutes 30 --seed N`
2. **Gate it** — before believing anything (each has produced a false
   conclusion before):
   - `grep -oiE "\(?[0-9]+, [0-9]+\) : ERR|Fix compilation errors" infolog.txt`
     (a compile error runs near-stock and reports a normal result; do NOT
     anchor on a filename)
   - `grep -c "apex:" infolog.txt` — nonzero proves apex logic ran
   - `grep -c BARAI_DEATH infolog.txt` — nonzero proves the combat gadget ran
3. **Reconstruct** — `python tools/battles.py <match-dir>` gives:
   - battle list: time window, location, whose territory, both sides' losses
     (units + metal, top defs), what did the killing, and each dying side's
     movement direction (home / enemy / lateral / still) — the retreat evidence
   - forces-at-start per battle from the nearest snapshot: the odds the fight
     was ACCEPTED at (costs come from the full unit-def table, so enemy
     commanders count their real value)
   - a summary of battles lost while outgunned-at-start
   - squad tightness timeline: field units, group count, biggest group,
     singletons — streaming reinforcements and scattered armies show here
   - the last battle is usually tagged ENDGAME WIPE; ignore it for combat
     judgement
4. **Cross-examine the AI's beliefs** for the worst battle:
   - `python tools/deaths.py <dir> --team N` — metal lost by task-at-death
   - grep the death lines of the units in that battle: `curTask` says what the
     engine had them doing, `fhist` says what apex elected them into and
     whether a withdraw (`W`) was ever ordered, the gadget's velocity says what
     they physically did
   - `grep "apex: withdraw" infolog.txt` — when the pull-back fired and at
     what odds
   - `grep "army-census" infolog.txt` — every 60s: tracked combat units by
     task (fN buckets = deaths.py FIGHT list; zero f5 ever = the army never
     attacks), plus the factory tier inputs: incM/incE pick the factory.json
     tier row (boundaries 2/25/35/50/100 on min of the two), and foeAir>0
     with no AA of ours flips labs to their `air` composition table
   - `grep "mix-diag" infolog.txt` — which roles the current tier row can
     actually build; `r2:ok` with the rest null means the lab is config-locked
     to raider spam regardless of what the Brain wants
   - macro context: the paired timeline (metalProduced / armyReal / mex per
     2-min sample from result.json stats) shows whether the fight loss caused
     the economic divergence or followed it
   - `metalExcess` in the final stats row: an economy lead that ends the game
     unspent (measured 2026-08-20: 18.2k excess on a 77k economy, vs stock's
     1.9k on 40k) is a spending failure, not a fighting one — that lead never
     became army, which is why a 2x economy could not finish
5. **Attribute before fixing.** Name the mechanism (file:line) that took the
   bad fight or failed to leave it, land ONE change, rerun the same seed plus
   at least one other seed, and compare the same battle report. Single runs
   are noisy — a changed outcome on one seed is a smell, not a proof; what you
   are looking for is the mechanism's log line behaving differently.

## Reading the battle report — patterns that matter

- **"moving: still" while dying at midfield** = the squad held ground under
  fire (raw fight orders), no retreat physics regardless of what curTask says.
  A unit can be on the engine RETREAT task and still die standing still.
- **Losses at forces-ratio worse than ~1.5x** = the fight was accepted
  outgunned; look at what sent them (fhist election frames spread over minutes
  = streamed in one at a time, not a group commit).
- **Enemy commander in the forces list** = D-gun zone; light raiders feeding
  into it is a known loss shape.
- **Tightness: many singletons for us, one big ball for stock** = we fight
  1vN everywhere; the army exists but never as a fist.
- Losses in OUR territory battle after battle = the front collapsed earlier;
  find the battle that lost the field, not the ones that lost the base.

## A/B-ing a tunable

Tunables (`ai.GetTunable`) are runtime-settable without redeploying:
`dev_tunables.lua` republishes any `apex_*` modoption as a game rules param —
but ONLY names on its explicit list; add the tunable there and re-run
`deploy_ai.py gadgets` first. Then run paired arms with shared seeds:

    FIGHT_SEEDS="31 32 33" bash tools/fight1v1_ab.sh myfix-off
    FIGHT_SEEDS="31 32 33" bash tools/fight1v1_ab.sh myfix-on --modoption apex_myfix=1

Score with `python tools/fight1v1.py matches/ab-myfix-*`. Never deploy while
an arm is running. A one-seed delta decided nothing here twice; use ≥6 seeds
and judge the mechanism's own log lines alongside the K/D.

## Known measurement traps

- **Verify the deploy by hash, every time, before the first game.** A deploy
  refused because a match is still running prints its refusal and exits, and
  ANY pipe after it (`| tail`, `| grep`) can mask that into a green chain —
  three consecutive batches on 2026-08-20 measured a stale build this way.
  The rule: after deploying, `deploy_ai.py status` must say `apex in sync`
  (repo hash == live hash) or nothing runs.

- **Pin the persona when measuring.** Each game rolls a persona (STANDARD,
  BERSERKER, TURTLE, GREEDY, AIRBOSS, SILOIST + adaptive REARM switches) and
  they dominate 1v1 variance: 2026-08-20, AIRBOSS rolls explained the "air
  plants while losing the ground war" games and SILOIST sank 6k+ into silos
  that never fire inside a 35m cap. Add `--modoption apex_persona=0` to every
  A/B and seed batch; roll freely only in games meant to be watched.
  `grep "persona ->" infolog.txt` says what a game actually rolled.

- Costs for units that never die/build come from `tools/.unit_costs.json`
  (regenerate by deleting it; reads BAR.sdd unit defs).
- `armyReal` in BARAI_STATS excludes units under spamCost (120) — an all-Flash
  army reads as zero army. Check `cheapBuilt` before concluding "no army".
- `GetUnitLimit` reads ~15750 in a 1v1 (BAR's dynamic-maxunits gadget
  redistributes Gaia's pool uncapped) — quota wants sized off it are fiction.
- FixedRNGSeed does NOT make runs reproducible (multithreaded DLL).
