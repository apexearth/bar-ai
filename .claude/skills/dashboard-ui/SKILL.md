---
name: dashboard-ui
description: The bar-ai dashboard — how the Balance/Games/Launch/Deploy tabs are built, and the rule that every new AI behaviour or tunable must be surfaced there. Load before changing tools/dashboard*, and before finishing any change that adds a tunable, a want kind, or a telemetry line.
---

# The dashboard (`tools/dashboard.py`, `dashboard_ui.html`, `dashboard_guide.py`)

`python tools/dashboard.py` → `http://127.0.0.1:8420`. This is **apexearth's
interface to the AI**: he does not run the CLI tools. A capability that exists
only as a command-line flag effectively does not exist for him — improve the
dashboard rather than teaching a command.

## The files

| File | Holds |
|---|---|
| `tools/dashboard.py` | the HTTP server, every `/api/*` route, the `tunables.as`/`targets.as` parsers, and the file writers |
| `tools/dashboard_ui.html` | the entire client: markup, CSS and one `<script>`. No build step, no dependencies |
| `tools/dashboard_guide.py` | **the curated map** — which knobs steer behaviour, in plain English, plus the goal recipes |
| `tools/dashboard_audit.py` | the ratchet that stops the guide drifting out of step |
| `tools/dashboard_coverage.json` | tunables deliberately *not* on the Balance tab |

`VARIANT` / `PROFILE` at the top of `dashboard.py` pin which AI tree is read.

## The tabs

- **Balance** (default landing) — the guided view. Intent chips → ordered
  recipes; the metal-split / stance / composition / pricing / growth panels; the
  mechanism map. Everything here is editable in place and writes the repo.
- **Games** — run and tournament browser, with the economy/units/intel/brain
  charts per run.
- **Launch** — start a match or tournament; carries the tunable overrides.
- **Deploy** — repo → live install, gadgets, patches.
- **Tunables** — the *full reference*, all 300+. Dead knobs hidden by default.

## Do not reach for a new tunable

This skill's rule -- every tunable must be surfaced here -- is a TAX on creating
one, not an invitation. Measured 2026-08-30: **404 tunables, 316 read at exactly
one call site, 360 never overridden in a single recorded run.** Each costs four
registration sites and a line of apexearth's attention on a page he actually
reads.

A tunable is justified only when you will sweep it in the same session and
report the sweep. Otherwise write a named constant. `python
tools/dashboard_audit.py --stale` lists the never-swept ones; culling from that
list is always welcome.

## Two ways a value reaches a game, and they are different

1. **Edit** — writes `tunables.as` / `targets.as` in the repo. Needs a
   **Deploy**. This is a permanent default change.
2. **Override** — the small box beside a knob. Writes nothing; rides along as
   `--modoption <name>=<value>` on every launch started from the dashboard. This
   is how an A/B is run.

An override only works if the name is in `game-patches/gadgets/dev_tunables.lua`
— that gadget is what republishes modoptions as rules params. A name missing
from it is **silently ignored in game**, so the dashboard colours the box red.
**Adding a tunable means adding it to that list too.**

## THE RULE: a new AI feature is not done until the dashboard shows it

Every one of these is silent — the feature works, and nobody can see or reach
it:

| You added | Also do |
|---|---|
| a `TUNE_` const | add it to `dev_tunables.lua`; then either curate it in `dashboard_guide.py` or waive it via `dashboard_audit.py --accept` |
| a knob a person would actually tune | a `GROUPS` entry with a `raise →` sentence, in the group that owns the decision |
| a knob that answers a complaint apexearth has voiced | a step in the matching `GOALS` recipe — that is the thing he will actually find |
| a new top-level mechanism (a want kind, a market, a spend bucket) | a `PANELS` entry if it is a *balance* (shares, curves, exponents); otherwise a card in `GROUPS` |
| a new `apex:` log line worth reading | a parser in `dashboard.py` and a chart, if it answers "did the change work" |
| a new analysis tool in `tools/` | an entry in `ANALYSIS_TOOLS` so it is a button on a run |

`python tools/check.py` runs the audit and reports:

- **new** — a tunable the guide has never seen. Curate or waive it.
- **missing** — the guide names a `TUNE_` symbol `tunables.as` no longer has.
  Error: the dashboard drops it at runtime, so the knob is absent from the page
  meant to explain it.
- **dead** — the guide offers a knob no `GetTunable` call reads. Error: editing
  it changes nothing, and a guided page must never recommend it. This has
  already happened four times (`TUNE_E_STALL_BOOST`, `TUNE_LINE_PULL`,
  `TUNE_WAVE_MEET`, `TUNE_PORC_OBSOLETE_RATIO`).

The waiver list is the point: the question "should this be on the dashboard?"
gets asked once, when the knob is added, instead of never.

## Writing the plain-English lines

The audience is someone who does not know the codebase. Two rules:

- `up` says **what the AI DOES more of**, not what the number means.
  "more energy per metal of income — a bigger grid for the same economy",
  not "the energy-per-metal ratio".
- Name the trap when the knob has one. `apex_site_cost_per_worker` raised means
  *fewer* workers per site; say so. `apex_worth_cost` is a choice of Lanchester
  law, not a weight; say that too.

A goal recipe is ordered and each step is tried **alone**. The copy says why —
twelve changes in one session cut metal production 4.3×, every one confirmed
firing. Do not write a recipe whose steps are meant to be applied together.

## Editing the client

One file, one `<script>`, plain ES6, no framework. Conventions that matter:

- `setHTML(el, html)` repaints only on change — the pollers used to blow away
  scroll position and focus every few seconds.
- Every `localStorage` read and write is wrapped; it throws outright in some
  contexts.
- `esc()` everything interpolated into markup.
- Element ids must not collide between tabs. Both tabs are in the DOM at once,
  so `#tv-0-3` on Tunables and the same id on Balance would resolve to whichever
  came first. Balance uses its own prefixes (`gv-`, `bs-`, `bcw-`).

**Verify a UI change actually runs.** `node --check` on the extracted script
catches syntax only. The stubbed-DOM harness pattern (a fake `document`,
`fetch` pointed at a live server on another port, then drive `loadBalance()` /
`renderGoals()` / `renderTunables()` and assert no `undefined`/`NaN` reaches the
markup) is what catches the rest — that is how the growth panel's missing curve
knobs and the `restoreTab` regression were both found before shipping.

## Writing to disk

`/api/const` and `/api/target` both re-read the line and refuse if it changed —
a stale tab cannot clobber an edit. Both are anchored on `(file, line, name,
old)`. `set_const` also refuses any path outside the script dir. If you add a
writer, keep that shape: **verify the old value before replacing it**, because a
`str.replace` anchor that does not match does nothing, quietly.
