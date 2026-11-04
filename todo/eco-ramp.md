# The economy ramp (his 10-20, watching the +0 eco test)

Run `python tools/ecotest.py` (+0, NullAI, eco only; `--ai-option apex_first_lab=3` opens with air). His notes from
the air-first watch game: "sometimes we choose to make fusion plants where we have no nanos nearby, also we spread
ourselves out on too many mex upgrades at once, restrict to fewer and assisting more would cascade the progress
better, also anticipating future nanoturret needs ahead of time would allow us to scale more properly." And earlier:
"eventually reclaim the T2 bot lab if you need the metal for fusion or the T2 air lab, then go into air cons"; no
hover lab in an eco game (0 economic benefit); the T2 lab beside the turret block.

- [ ] Fewer mex upgrades at once, more hands on each: a new upgrade is charged for the ones it slows.
- [ ] Turrets bought ahead of the work that will need them.
- [ ] The T2 bot lab reclaimed once the T2 air lab stands and its metal is wanted.
- [ ] The commander stays home on the plant and home work; every slow hand pays its share of the walk home. In a war
  game, field defence counts as field work too.
- [ ] T1 air cons keep coming while metal overflows.
- [ ] Build near idle turret rings; while overflowing, idle ring sites take whatever is needed most; more frames at
  once while turrets idle.
- [ ] Transports move idle turrets to the work (lift.as flies them, TUNE_LIFT_TURRETS off; in eco no plane is priced,
  and the sink is "outside every turret circle", which a big base never has).
- [ ] Anticipate needs: converters before the AFUS finishes; the same look-ahead for turrets, storage and the next
  generator.
- [ ] Tight packing (his 10-20: "snapping to nearby same-size buildings"). Each def has its own lattice at its
  footprint pitch, so a 3-cell turret block meeting a 5-cell fusion block leaves 1-4 square strips (his watch game:
  191 such gaps against 555 flush). His layout is blocks of one kind scaling in one direction; that is a placement
  redesign, mostly in the C++ cell choice -- ask him first.

Tried 10-20 as switches, one per symptom, and deleted: paired eco games found none better (future job, smoothed
fullness, reach once, cons as lathe raisers, idle-ring siting, lift sink, converter anticipation: -5%, se 11%, at 28
min as a set; turret energy cost -31%; assist energy feed -27%; lab order gain -12%/-3%; realize-to-capacity -30%).
Numbers in 26b63ab1, ce756327 and the one after; find the shared cause (memory no-switch-bloat). What was measured
since: `issues/eco-half-his-curve.md`.
