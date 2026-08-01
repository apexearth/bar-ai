# Unit names that do not resolve, and why

A request for a unit def that does not exist is a **no-op**: no error, no log
line, the request is dropped. The same is true of a def that exists but that
nothing we field can build. Both look identical from the outside — the AI simply
never does the thing.

Two tools cover this, and they cover different files:

```bash
python tools/check.py              # JSON configs -- names that are not defs
python tools/check_unit_refs.py --builders   # script/**.as -- names AND reachability
```

`check_unit_refs.py` exists because the configs were checked and the AngelScript
was not, and that is where the costly mistakes have been.

## Reachability is a closure, not a lookup

The interesting failure is not a typo. It is a **real** unit that nothing we can
field builds.

`armfmkr` is a real def, so no name check objects to it. It is built by
commanders, ship constructors and hover constructors — never by `armck`/`armcv`/
`armack`/`armacv`, which are the constructors this AI hands build tasks to. The
ground constructors carry `armmakr` instead. Referencing `armfmkr` produced 95
build requests, zero converters, and one player wasting 1.34M energy.

Two wrong models were tried before the right one:

- **Union over every def in the game** — passes `armfmkr`, because *something*
  builds it. Useless.
- **Our ground constructors only** — flags `armflea` (built by a lab, not a
  constructor) and `armaap` (built by an *air* constructor). Drowns in noise.

The correct model is a **transitive closure**: start from our constructors,
commanders and the factories `factory.json` configures, then repeatedly absorb
anything reachable that can itself build. Our air plant builds an air
constructor, which builds the advanced air plant — so `armaap` is reachable in
two hops and is *not* a defect. A one-hop check reports it as broken and is
wrong.

## The eight stock references that do not resolve

Inherited unchanged from stock BARb, all in config rather than our own work.
Harmless — they are dropped silently — but they are not typos, and it is worth
knowing which is which. Resolved against the installed game (`units/*.lua` and
`language/en/units.json`) rather than from memory.

| name | verdict |
|---|---|
| `armthovr`, `corthovr` | **Removed from the game.** BAR still ships the display string "Heavy Transport Hovercraft" in `language/en/units.json`, but no def. The language entry outliving the unit is the tell. |
| `corintr` | **Removed.** Display string "Amphibious Heavy Assault Transport" survives; no def. |
| `armuwmex`, `coruwmex` | **Concept removed.** No underwater or naval mex def ships at all — the ordinary extractor covers underwater spots now. |
| `legmmkrt3` | **Faction gap.** `armmmkrt3` and `cormmkrt3` exist; Legion has no T3 metal maker. |
| `legamsub`, `legplat` | **Faction gap.** Legion borrows the Cortex navy; its own naval roster is not implemented, so `armamsub`/`coramsub` exist and the Legion equivalents do not. |

The pattern is worth remembering: a `leg*` name that does not resolve is usually
Legion's roster being incomplete rather than a mistake, and an `arm*`/`cor*` name
that does not resolve is usually a unit BAR deleted. Neither is fixed by
correcting a spelling.

## Sources

- Installed game: `BAR.sdd/units/**/*.lua`, `BAR.sdd/language/en/units.json` —
  authoritative for what ships, and the only thing that matters at runtime.
- Legion navy status: <https://www.crdhq.com/articles/bar-settings-notes-from-main-0564>
