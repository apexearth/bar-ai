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

Read from the pinned game tree, 2026-08-09:

| | armsilo (Armageddon) | armamd (Citadel, anti-nuke) |
|---|---|---|
| metal | 8,100 | 1,500 |
| energy | 90,000 | 38,000 |
| stockpile time | 120 s per missile | 90 s per interceptor |
| stockpile limit | 10 | 20 |
| coverage | — | 2,000 radius |

Three consequences:

1. **One silo can hold ten missiles.** The salvo does not need ten silos; it
   needs one silo that stopped firing for twenty minutes, or a few that stopped
   for less.
2. **An interceptor is consumed per intercept and takes 90 s to replace.** A
   defender who has been fed one nuke at a time sits on a full rack of 20. The
   salvo has to be big enough, and *simultaneous* enough, that the rack empties
   before the last missile lands — 20 interceptors is a real wall, so the target
   selection matters as much as the count.
3. **Coverage is 2,000 radius.** Aiming the salvo at one base means one anti-nuke
   defends it; spreading it across the map means several do, each with a fresh
   rack. Concentration is not a preference, it is the mechanism.

The team dimension multiplies this: eight AI players each holding a silo is
eighty missiles. The blackboard already exists for exactly this kind of
coordination (`PublishTeamValue` / `ReadTeamValue`, a plain in-process map — see
`docs/desync` notes in `.claude/skills/desync-check`, it is sync-safe).

## Stage plan

**One behaviour change at a time, composition after each.** The 2026-08-01
finding applies with full force here: every rule below spends something, and a
salvo that never launches because the AI could not afford the silos is worse
than the drip it replaced.

### Stage 1 — hold fire (the whole feature is in this one)

Stop `CSuperTask` firing on readiness; accumulate instead. Needs a gate on the
nuke branch specifically — `corint`/`armbrtha` (long-range guns) must keep
firing continuously, they are not part of this.

- Where: `CSuperTask` is C++ (`task/static/SuperTask.cpp`). Check first whether
  an AngelScript hook can veto a launch; if not, this is a layer-3 change and a
  tunable (`apex_nuke_hold`) to A/B it.
- Acceptance: `super fire armsilo` count drops toward zero while stockpile rises.
- Risk: missiles sitting in a silo that then dies are pure waste. Cap the hold
  by threat to the silo, not by a clock.

### Stage 2 — the trigger and the target

Fire everything when the count crosses a threshold, at ONE base.

- Count across our own silos first, then across the team via the blackboard.
- Target: the enemy player with the most structure value inside one anti-nuke
  coverage radius (2,000), preferring one whose anti-nuke stock we have reason
  to think is low. Reuse whatever the existing eco-target scoring gives us.
- Acceptance: a log line naming the salvo — how many missiles, at which team,
  within how many seconds. Then watch a replay and see a base disappear.
- Threshold: apexearth said 15. Start there, tunable.

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
