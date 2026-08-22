---
name: async-sim-orders
description: The async command model - why counts lie during the walk window, which signal is ground truth for in-flight work, and the held-placeholder trap. Load before touching any gate that counts factories, tasks, or in-flight builds.
---

# Orders are async; the task registry is the only synchronous truth

apexearth 2026-08-21: "you have to build expecting commands to be
asynchronous and the things you choose to do not reflecting reality
immediately." This skill is the verified mechanical model. The second-T1-lab
bug shipped ~30 times because each fix read a different LAGGING signal; it
died when both gates were keyed to the one synchronous one.

## The signals, and when each one lies

| Signal | Lies when | Lag |
|---|---|---|
| Unit state reads (`CountQueued`, `unit.task` target) | always, after any order | scales with sim speed — 45 ticks at 37x (CLAUDE.md) |
| `CCircuitDef::count` | before the nanoframe exists | the builder's whole WALK to the site |
| `aiBuilderMgr.GetTaskCountOf(bt)` (the pool) | after assignment — an assigned task LEAVES the pool | walk + build |
| Ask ledger (`gAskDef`, choose.as) | after its TTL, unless something keeps it alive | TTL seconds |
| **`Requests::gLive` (the registry)** | see the one trap below | none — `AiTaskAdded`/`AiTaskRemoved` are synchronous AI-side events |

The registry is populated for EVERY builder task, engine-created ones
included, at creation, and cleared only at real removal. Assignment does not
touch it. This is the "keep a count of what was SENT" discipline from
CLAUDE.md, applied to tasks.

## The walk window (the frame-105 race)

Builder takes a factory task → task leaves the pool → no nanoframe yet →
def counts 0, pool 0. Any gate summing those reads "nothing in flight" for
the entire walk and approves a duplicate. Extra twist: the COMMANDER is
excluded from `Crew::gId` (events.as, `IsRoleAny(COMM.mask)` before
`Enlist`), so the ask sweep's "builders holding factory work" loop never
saw the standard opening's only builder.

## The one registry trap: the held placeholder

`CEconomyManager` parks a HELD, INACTIVE factory task while waiting for
income. It is deliberately kept out of the pool (BuilderManager.cpp:734-740)
— but `AiTaskAdded` fires for it, so it IS in the registry, is never
removed while held, and is unassignable. Counting it as in-flight wedged
every opening: facCount=0 at 10 minutes, ask alive forever, no factory ever
approved (measured, 2 of 3 smokes, 2026-08-21). **`Workers(task) > 0` is
what separates a real walk-and-build from the parked placeholder.** Hence:

    in-flight factories = pool count (unassigned-active)
                        + Requests::FactoryManned() (assigned, walk included)

and never the raw registry count.

## The door (where the invariant lives)

`Requests::Take`'s FACTORY branch (requests.as): any live MANNED factory
task is returned to every asker regardless of distance (a factory is never a
fork — `JoinFor`'s REACH bound is what silently forked labs for months), and
a T1 land plant is refused outright while one stands under the cap.
`SweepPlantAsks` (choose.as) keys ask lifetime on the same two terms. Do not
add another factory entrance; route through `PlantApproved` + this door.

## Verifying a change to any of this

- Smoke 3+ seeds, then per game: `facCount` max in result.json must be >= 1
  by minute 3, and the T1 plants in `allBuilt` must be exactly one def.
- `grep "second T1 plant refused"` — the door announcing a blocked fork.
- The failure is SILENT both ways: zero factories (over-counting in-flight)
  and two labs (under-counting) both play a full, normal-looking game.
