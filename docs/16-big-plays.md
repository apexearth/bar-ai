# Big plays — the late game should produce moments, not attrition

apexearth, after a 58-minute 8v8 that the AI played respectably:

> "It was a fun game and a lot of nukes went out. It was challenging enough for
> people, but it wasn't so crazy that anyone was too wowed or surprised. I don't
> remember anyone getting dramatically air raided, and once we had anti nuke up
> the nukes weren't dangerous. AI should be saving up for launching like 15 nukes
> all at once into one of the player bases... that would be the sort of thing
> humans would fail against. And mass bomber raids would be great too. Sudden
> HUGE actions are what make late game fun."

This is a **different objective from winning**, and the existing measurements do
not capture it. A steady drip of nukes and a win on attrition scores the same as
a salvo that deletes a base, and only one of them is worth playing against.

Note what this de-prioritises: in a game this long, mex count and the late
economy stop mattering. Do not spend this stage of work on them.

## What actually happened, from the 2026-08-09 hosted game

Read from the live infolog (no dev gadgets in a hosted game, so these are the
AI's own log lines):

| line | count |
|---|---|
| `super fire armsilo stock` | 427 |
| `super fire corsilo stock` | 260 |
| `super idle corsilo stock` | 224 |
| `super fire corint stock` | 533 |
| `super fire armbrtha stock` | 507 |

**`stock` is the tell: every one of those fired under stock CircuitAI
behaviour** — `CSuperTask` launches the moment a missile is ready, at whatever
target scores best at that instant. Nukes therefore arrive one at a time, spread
over an hour, which is precisely the pattern a single anti-nuke absorbs
indefinitely.

## The arithmetic that makes a salvo work

Read from the weapon defs in the pinned game tree, 2026-08-09. apexearth
supplied the mechanism; the numbers confirm it.

| | armsilo (Armageddon) | armamd (Citadel, anti-nuke) |
|---|---|---|
| metal / energy | 8,100 / 90,000 | 1,500 / 38,000 |
| **reloadtime** | **30 s** | **2 s** |
| stockpile time | 120 s | 90 s |
| stockpile limit | 10 | 20 |
| weapon velocity | 1,600 | 6,000 |
| coverage | | 2,000 |

**Launch CADENCE decides this, not the stockpile.** A silo reloads in 30 s, so
one silo physically cannot salvo: ten stockpiled missiles leave one every thirty
seconds. The interceptor re-fires every **2 s**. Against a 30-second drip an
anti-nuke gets fifteen re-fires between arrivals and stops everything forever,
which is exactly the game apexearth just played.

So the requirement is **fifteen separate silos firing at once**, not one silo
that saved up. Fifteen missiles arriving inside a few seconds outpace a
2-second re-fire outright: the anti-nuke manages two or three interceptions and
the rest land. Holding fire matters only to SYNCHRONISE the launch, never to
accumulate missiles.

That reprices the feature. 15 x 8,100 = **121,500 metal** and 1.35M energy in
silos; across an eight-player team, about two silos each, which at the 500
metal/second observed in the hosted game is affordable. But it is a BUILD ORDER
before it is a firing tweak, and the silos have to exist before anything else
here matters.

Concentration still matters for a second reason: coverage is radius 2,000, so
aiming everything at one base puts one anti-nuke in range rather than several.

The team dimension is now the core of it rather than a multiplier -- fifteen
silos is a team's worth. The blackboard already exists for exactly this kind of
coordination (`PublishTeamValue` / `ReadTeamValue`, a plain in-process map, and
sync-safe; see `.claude/skills/desync-check`).

## Stage plan

**One behaviour change at a time, composition after each.** The 2026-08-01
finding applies with full force here: every rule below spends something, and a
salvo that never launches because the AI could not afford the silos is worse
than the drip it replaced.

### Stage 0 — build the silos

Fifteen simultaneous launches need fifteen launchers, so this comes first and
everything after it is worthless without it. Find what currently decides a silo
gets built (`build_chain.json`, and whoever claims the constructor) and raise it
to a per-player count that reaches ~2 across the team. Watch what it displaces:
90,000 energy each is a fusion's worth per silo.

Acceptance: silo count per player over time, and `composition.py` against a
control.

### Stage 1 — hold fire, to SYNCHRONISE rather than accumulate

Stop `CSuperTask` firing the moment a missile is ready; wait for the others. Needs a gate on the
nuke branch specifically — `corint`/`armbrtha` (long-range guns) must keep
firing continuously, they are not part of this.

- Where: `CSuperTask` is C++ (`task/static/SuperTask.cpp`). Check first whether
  an AngelScript hook can veto a launch; if not, this is a layer-3 change and a
  tunable (`apex_nuke_hold`) to A/B it.
- Acceptance: `super fire armsilo` drops toward zero while silos sit loaded,
  then a burst of launches inside one second.
- Risk: a loaded silo that dies is pure waste, and ONE missile held in each of
  fifteen silos is both the cheapest hold and the only one that salvos. Holding
  ten deep in a single silo is stock's failure mode with extra steps.

### Stage 2 — the trigger and the target

Fire everything when the count crosses a threshold, at ONE base.

- Count READY SILOS, not missiles, across ours and then the team's.
- Target: the enemy player with the most structure value inside one anti-nuke
  coverage radius (2,000), preferring one whose anti-nuke stock we have reason
  to think is low. Reuse whatever the existing eco-target scoring gives us.
- Acceptance: a log line naming the salvo — how many missiles, at which team,
  within how many seconds. Then watch a replay and see a base disappear.
- Threshold: apexearth said 15 launchers. The salvo is capped by silo count, so
  this trigger and Stage 0's target are the same number. Tunable.

### Stage 3 — mass bomber raid

Same shape, different weapon: accumulate bombers, strike once, together.

**Known obstacle before designing anything:** there is a C++ constant that
prevents air squads from grouping (recorded in memory as "Air squads cannot
group"). Confirm it still exists and what it is, because if bombers cannot be
held in one task then Stage 3 is a C++ change and not a script one. Do that
check before estimating this stage.

- Acceptance: N bombers arriving within one window at one target, and a
  before/after of enemy structure value in that window.

### Stage 4 — make the two land together

A nuke salvo that removes the anti-nuke and the defences, with the bombers
arriving in the same thirty seconds, is the thing that no human recovers from.
Only attempt after 1-3 each work alone.

## How to judge any of it

Win rate will not show this and should not be the gate. Measure the **moment**:

- **Peak simultaneous launches** — the maximum nukes in flight in one 10-second
  window, per game. This is the headline number; it was 1 in the game above.
- **Structure value destroyed in the 30 s after a strike**, versus the game's
  running average.
- **Time from first silo finished to first salvo.** A hold that never triggers is
  a silo that did nothing all game, which is strictly worse than stock.
- **What it displaced** — `composition.py` against a matched control, every time.
  Silos are 8,100 metal and 90,000 energy each.

And the standing gate from 2026-08-09: **anything that touches an engine call
must pass `tools/run_netmatch.py` before it is played in multiplayer.** Target
selection that asks the engine a question is exactly the shape of the bug that
desynced two hosted games.

## Workflow for this stage

1. Deploy and hand apexearth a windowed game FIRST, so he is watching while the
   slow work runs (`docs`/CLAUDE.md standing order).
2. One change, one measurement, one composition check.
3. Netmatch after any change that reaches the engine.
4. Watch the replay of the moment. This objective is aesthetic as much as
   numerical — "did that look devastating" is a real acceptance test here, and
   apexearth is the instrument.
