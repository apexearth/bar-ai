# Big plays — the late game should produce moments, not attrition

apexearth, after a 58-minute 8v8 that the AI played respectably:

> "It was a fun game and a lot of nukes went out. It was challenging enough for
> people, but it wasn't so crazy that anyone was too wowed or surprised. I don't
> remember anyone getting dramatically air raided, and once we had anti nuke up
> the nukes weren't dangerous. AI should be saving up for launching like 15 nukes
> all at once into one of the player bases... that would be the sort of thing
> humans would fail against. And mass bomber raids would be great too. Sudden
> HUGE actions are what make late game fun."

This is a **different objective from winning**, and the ordinary measurements do
not capture it. A steady drip of nukes and a win on attrition score the same as
a salvo that deletes a base, and only one of them is worth playing against.

It is not, however, a different KIND of objective. "Fifteen nukes, launched at
once" is a target state, and `docs/23-the-plan.md` is how the AI reaches one:
name it, then take the fastest path to it. That is also the answer to why the
AI holds a stockpile it could be spending — a per-instant price will always
launch the nuke it has, because it cannot see a state that only exists once
fifteen of them are ready. Salvo behaviour is the plan's shape applied to the
military half, not an exception to it.

Note what it de-prioritises: in a game this long, mex count and the late economy
stop mattering. Do not spend this stage of work on them.

## The arithmetic that makes a salvo work

Read from the weapon defs in the pinned game tree; costs re-checked 2026-08-30.

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
seconds. The interceptor re-fires every **2 s**, so against a 30-second drip an
anti-nuke gets fifteen re-fires between arrivals and stops everything forever.
That is the game apexearth played.

So the requirement is **fifteen separate silos firing at once**, not one silo
that saved up. Holding fire matters only to SYNCHRONISE a launch, never to
accumulate missiles — ten missiles held deep in one silo is stock's failure mode
with extra steps.

15 x 8,100 = **121,500 metal** and 1.35M energy in silos: across an eight-player
team, about two each, affordable at the ~500 metal/second observed in that
hosted game. It is a BUILD ORDER before it is a firing tweak.

Concentration matters for a second reason: anti-nuke coverage is radius 2,000, so
aiming everything at one base puts one interceptor in range rather than several.

## How to judge any of it

Win rate will not show this and should not be the gate. Measure the **moment**:

- **Peak simultaneous launches** — the maximum nukes in flight in one 10-second
  window, per game. This is the headline number; it was 1 in the game above.
- **Structure value destroyed in the 30 s after a strike**, versus the game's
  running average.
- **Time from first silo finished to first salvo.** A hold that never triggers is
  a silo that did nothing all game — strictly worse than the drip it replaced.
- **What it displaced** — `composition.py` against a matched control, every time.
- **"Did that look devastating"** is a real acceptance test here, and apexearth
  watching a replay is the instrument.

And the standing gate: **anything that touches an engine call must pass
`tools/run_netmatch.py` before it is played in multiplayer.** Target selection
that asks the engine a question is exactly the shape of the bug that desynced two
hosted games.

## Status

The nuke half is **built** — multi-volley logistics, target ranking, the mirrored
base, antinuke accounting and intel spend all live in `manager/brain/nukes.as`.
The `ai-nukes` skill describes the running system; this file keeps only the
objective and the physics that set the target number. The bomber half (accumulate
bombers, strike once, together) is not built, and the C++ constant recorded as
"air squads cannot group" is the thing to confirm before estimating it.
