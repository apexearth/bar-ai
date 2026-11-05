# Issues: what is wrong now

One file per issue in `issues/`, one line per file here. When an issue's fix is measured, delete its file and its
line, and put the measurement in the commit message. A new issue gets a file (what is wrong, the evidence, what was
tried) and a line here. The fight layer is stock BARb since 2026-09-07 (`7a1a9895`).

**Validation list**: [`issues/validation.md`](issues/validation.md), every fix for one of his issues that no game
has proven yet, grouped by status: 1 trial running, 12 broken or inert, 35 never measured, 37 firing but
unproven. `python tools/trial_report.py` after his games.

| Issue | Since | In one line |
|---|---|---|
| [cons-flee-to-map-edge](issues/cons-flee-to-map-edge.md) | 11-04 | constructors run to the map edge when threat covers the whole map, and idle there |
| [off-switches](issues/off-switches.md) | 11-03 | 56 deleted 11-04; left: 26 of his asks awaiting his test-or-delete call |
| [glacier-pass-plus0](issues/glacier-pass-plus0.md) | 11-03 | too many sites at once; energy short after the opening; slow to finish |
| [8v8-first-gantry-late](issues/8v8-first-gantry-late.md) | 10-31 | the team's first T3 lab 22-26 min vs BARb's 14-18; waiting on his ruling on who hosts and pays |
| [lrpc-orders-die](issues/lrpc-orders-die.md) | 10-24 | ~90% of long-range gun tasks never finish at forward sites; risk model reads them 0.44-0.50 |
| [turret-knot](issues/turret-knot.md) | 10-24 | the knot rule piles turrets at one site; his call: leave for now, watch |
| [static-defence-fear](issues/static-defence-fear.md) | 10-23 | a player says we fear towers; scenarios pass; needs what the player saw |
| [gunships-hover-in-aa](issues/gunships-hover-in-aa.md) | 10-23 | the air net picks GO over WAIT; next is targeted training on scored runs |
| [army-order-volume](issues/army-order-volume.md) | 10-22 | ~33 commands per army unit a minute; units re-path every ~2 s |
| [eco-half-his-curve](issues/eco-half-his-curve.md) | 10-22 | energy and build power behind his curve from minute 2; what was measured and removed |
| [performance](issues/performance.md) | 10-31 | 16-AI budget fails 1.7x in v0.5.01; his seats 2-3.5 ms; scav 8v8 4x; LatheSiteRaw spikes |
| [site-moved-after-pricing](issues/site-moved-after-pricing.md) | 10-15 | the defence-site net moves a priced site 4,450 elmos; the commander leash misses it |
| [t3-switch-army-aa](issues/t3-switch-army-aa.md) | 10-10 | forward AA dies unbuilt; queued T3 counted at nameplate; cons as costly as T2 army |
| [mex-losses-vs-barb](issues/mex-losses-vs-barb.md) | 10-10 | fewer claims by m5; the raider that kills our mex lives; small DEFEND pools never detach |
| [defence-funnel](issues/defence-funnel.md) | 10-09 | 68% of ground-gun attempts refused; T2 guns late and the slow kinds |
| [code-review-2026-10-08](issues/code-review-2026-10-08.md) | 10-08 | ten unfixed silent bugs from the 10-08 review, file and line each |
| [base-edge-leaks](issues/base-edge-leaks.md) | 10-08 | enemy ground kills 2.86M of economy at the base rim over 121 games |
| [home-siege-prior](issues/home-siege-prior.md) | 10-07 | the siege prior discounts home ground; his ruling says it must not |
| [exceptions-to-price](issues/exceptions-to-price.md) | 10-04 | four rule exceptions still to become prices (valuation job) |

Entries dated before 10-15 were measured on code that has changed a great deal since; re-measure before acting.
The September findings (pre-policy-net) were dropped 2026-11-03: `git show 2aefc570:ISSUES.md`.
