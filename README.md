# Apex, an AI for Beyond All Reason

Apex is a skirmish AI for [Beyond All Reason](https://www.beyondallreason.info/) (BAR), the RTS on
the Recoil engine. It started as a fork of BARb, the AI that ships with the game, and has since
replaced most of how BARb decides what to build and when. This repo is its source, its test
harness and its notes.

If you only want to play against it, skip to [Play against it](#play-against-it).

## What is different about it

### One question behind every decision

Most RTS AIs are a build order plus a pile of rules: "after 4 extractors build a factory", "keep 6
defenders at home", "go T2 at 20 metal income". Apex has none of those on purpose. Every decision
answers one question: **what is the fastest path to the state we are trying to reach?** The AI
names a target (this much army, or that much army with a fusion reactor behind it) and takes the
move that gets there soonest.

So order, counts and limits come out of the arithmetic. They are never typed in. When a hand-written
threshold, cap or build order turns up in this code, it is treated as a bug: it means the pricing
behind it is wrong somewhere, and the fix belongs there.

### Everything is a price

When a constructor is free, it holds an election. About twenty proposers each put forward their
best job: an extractor, a solar, a converter, a nano turret, a defence, a reclaim run, an
extractor upgrade. Each job is priced as gain over cost, and cost includes metal, build time, the
walk to the site and the chance of dying on the way. The constructor takes the best one.

A judgement never forbids an option outright. If a tower is badly placed it gets a bad price, but
it can still win when nothing better exists, so the AI can still try it and learn from it. Only
true impossibilities (the ground is taken, the unit cannot reach) rule an option out.

### Economy all game

The core tenet comes from the player who directs this AI: always be making economy. Metal spots
are few and fixed, so economy also means energy, generators and converters (about 60 energy buys
one metal). Some hands are always on economy, and army and defence are held at their share of the
economy we have built.

### Neural nets adjust the prices

Two nets sit on top of the market. A policy network reads about 70 facts about the game (incomes,
army sizes on both sides, threats, what is standing) plus each option's own numbers, and scales
that option's value up or down. Small heads each set one number a hand-written rule would
otherwise set, such as how hard to expand, how many constructors to make, or how strong an escort
should be. With every output at zero the nets leave the prices alone, and the hand-written prices
and rules play on their own.

Training is being rebuilt. The nets in current releases came from a search over many games, and
measurement showed it could not tell a good net from a lucky one. Learning from whether the game
was won fails for a similar reason: one builder's choice is drowned out by everything else the
team does. Two things replace it. The prices are being made sound, each one checked against what
actually happened to each building: did it survive, how long it really took to build, what it
produced. And the net now learns from its own choices. In training games every output is pushed a
little off what the net would play, and each push is credited with how our position (economy,
army, trades) moved in the next two minutes. Credit tied to the decision itself, such as whether
an extractor got built or its constructor died, comes next.

Every training game draws its setup at random (map, team sizes, factions, resource bonus, length)
so the net cannot learn one map's game. Training never uses games against people, and lobby games
never explore. A new net ships only if it beats the current one over 24 or more games.

### Written to a player's directions

[`docs/doctrine.md`](docs/doctrine.md) is one experienced BAR player's account of how the AI should
play: what to do, what never to do, and facts of the game. It is the spec. Code that breaks a line
under **Never** is a bug. A **Do** line is a default the nets may overrule where games show it
loses.

The order of goals in that file is worth knowing. **Fun to play against comes first**: surprise,
challenge, and interaction all game. A huge economy followed by one overwhelming army is called out
as the boring arc. After fun come beating BARb in more than 80% of even games (a goal it has not
reached yet), ending games when they can be ended, and making them worth watching: bombing raids,
nuke salvos, long-range plasma.

### Plays fair, plays as a team

- It only uses what a player could see. Hidden enemy units are not read; the "see the whole map"
  cheat is an explicit lobby option, off by default.
- It runs entirely on the host. Nothing is added to the game's synced code, so it works in normal
  multiplayer lobbies with no mod.
- Apex players on one team share a team board. They agree on one team strategy per game (mass T3,
  nukes and missiles, long-range artillery, mass air, rush, greed, turtle, or normal), co-build one
  experimental gantry, share extractor upgrades, and give advanced constructors to allies who have
  none. This team play is experimental: the strategies run, but whether each one plays well has
  not been measured.

### Measured, not guessed

Changes are tested in headless AI-vs-AI games, mostly against stock BARb, and judged on what the
games show rather than on whether the new code ran. [`docs/versions.md`](docs/versions.md) logs
results per release, including the changes that made it worse.

## Play against it

You need Windows and BAR, started at least once so it has downloaded its engine.

1. Download the latest `Apex-v*.zip` from
   [Releases](https://github.com/apexearth/bar-ai/releases/latest).
2. Close BAR.
3. Right-click the zip, **Extract All**, and double-click `Install.bat` in the extracted folder.
   It finds your BAR install, copies the AI into the engine folder, and turns off the lobby's
   "Simple AI list", which would otherwise hide it.
4. Start BAR. In a skirmish or a hosted lobby, **Add AI** and pick **Apex** with its version.

Only the player hosting the game needs it installed. Everyone else just joins.

Some things to know:

- **Engine version.** Each zip is built for one BAR engine, named in the zip and on the release
  page (for example `recoil_2026.07.04`). On a different engine the AI fails to load without a
  useful error. The installer warns you if yours does not match.
- **BAR updates.** An engine update wipes the AI folder. Run `Install.bat` again, or get the
  release built for the new engine.
- **Keep one version installed.** A hosted lobby does not send which version you picked, so the
  engine loads the highest Apex version installed. Delete old ones from
  `<BAR install>\data\engine\<engine>\AI\Skirmish\Apex\`.
- **Manual install.** `INSTALL.txt` in the zip has the steps if the installer cannot find BAR.
- **Uninstall.** Delete the `Apex` folder above.

### Lobby options

Each Apex bot in a lobby has its own options. The defaults are what gets tested. The forced team
strategies, the economy player and "Try strategies" are experimental, so expect odd games when you
change them.

| Option | What it does |
|---|---|
| Team strategy | Let the AI choose (default), or force one: Normal, Mass T3, Nukes and missiles, Long-range artillery, Mass and push, Mass air, Rush, Greed, Deep greed, Turtle. |
| Economy player | Makes this bot its team's economy player: economy first, army and defence once its base is threatened. 0 is off, 1 is a full economy phase. |
| Neural net influence | 1 lets the trained nets steer (default). 0 plays the hand-written rules alone, if the nets misbehave. |
| Try strategies | Picks the team strategy at random instead of letting the AI choose. Use on one bot per team. |
| Advanced | Map-wide vision (a cheat), keeping out of allied bases, units this bot never builds, and a few more. |

## Run it from source

You need Windows 10 or 11, BAR, git and Python 3.13 (the tools use the standard library only).
Docker Desktop is needed only to rebuild the C++ part.

```bash
git clone https://github.com/apexearth/bar-ai
cd bar-ai
python tools/bar_env.py                          # prints the BAR install and engine it found
python tools/deploy_ai.py deploy Unstable --repo-dll
python tools/deploy_ai.py status
```

`tools/bar_env.py` finds BAR on its own. If your install is somewhere unusual, set `BAR_ROOT`,
`BAR_DATA` or `BAR_ENGINE`. `--repo-dll` ships the DLL checked into the repo instead of one you
built; it can lag behind `cpp/`, and if the AI's script then fails to compile, build the DLL
(below). After deploying, the lobby lists **Apex Unstable**. Uninstall any release while you test
it, or a hosted game will load the release instead.

### Headless matches

The harness plays AI-vs-AI games with no window, much faster than real time, and writes each one
to `matches/` or `tournaments/`.

```bash
python tools/sync_game.py           # build the harness's copy of the game from your lobby's version
python tools/deploy_ai.py gadgets   # install the autoquit and result gadgets into it

python tools/run_match.py --a Apex:Unstable:standard --b BARb:stable:hard \
    --map "Comet Catcher" --minutes 30 --seed 1 --speed 20
python tools/run_tournament.py --a Apex:Unstable:standard --b BARb:stable:hard \
    --maps "Comet Catcher,Supreme Isthmus" --games 10 --speed 20
python tools/run_tournament.py --report

python tools/review.py <run>        # judge a run: did it compile, run, and what happened
python tools/story.py <match>       # why a game was won or lost
python tools/dashboard.py           # a local web UI for runs, launching, deploying and tunables
```

Always pass `--speed`. An uncapped headless game runs so fast that commanders stall, and the
results stop meaning anything. Each engine uses 5 to 6 GB of memory, so count before launching
several. [`docs/working.md`](docs/working.md) has every command and the rules for testing a
change.

### Changing the AI

The AI has three layers. You edit them under `ai/Unstable/`, and `deploy_ai.py deploy` copies them
into BAR.

| Layer | Where | Build | What it decides |
|---|---|---|---|
| JSON config | `ai/Unstable/game-side/config/` | none | unit roles, threat, retreat thresholds |
| AngelScript | `ai/Unstable/game-side/script/` | none | everything built and produced, army use, the commander, air, nukes, the nets |
| C++ | `cpp/` | Docker | squad movement and fights, threat maps, placement, the script bindings |

Most work happens in AngelScript, and the builder election lives in
`script/standard/manager/brain/market/`. Every default the AI plays with is one line in
`script/standard/tunables.as`, and [`docs/tunables.md`](docs/tunables.md) says why each is what it
is. `python tools/check.py` runs the static checks, including the one that fails any spending
outside the market.

The C++ builds in Docker against the Recoil engine source: `python tools/bootstrap_sources.py
engine`, then `python tools/build_dll.py --deploy`. See "Building the DLL" in
[`docs/working.md`](docs/working.md). Releases are built by
[`.github/workflows/release.yml`](.github/workflows/release.yml) from the pins in
`.github/release.env`.

## Layout

```
ai/Unstable/        the AI, source of truth; ai/v*/ are frozen releases
cpp/                the C++ source of the DLL (a fork of CircuitAI)
game-patches/       changes to shared BAR files, and the dev gadgets the harness uses
tools/              deploy, the headless harness, analysis, the dashboard
docs/               the documents below
reference/          stock BARb, for diffing (read-only)
matches/ tournaments/ runtime/ vendor/   game output and upstream clones (gitignored)
```

## Docs

| | |
|---|---|
| [`docs/doctrine.md`](docs/doctrine.md) | how the AI should play: goals, Do, Never |
| [`docs/how-it-works.md`](docs/how-it-works.md) | how each part decides, from the current code |
| [`docs/army.md`](docs/army.md) | the army layer and how army changes are tested |
| [`docs/working.md`](docs/working.md) | commands, testing, building, releasing |
| [`docs/traps.md`](docs/traps.md) | silent failure modes, each with its check |
| [`docs/tunables.md`](docs/tunables.md) | why each default is what it is |
| [`docs/versions.md`](docs/versions.md) | releases and their measured record |

`ISSUES.md` is what is wrong now, `TODO.md` holds plays not yet built, and `USER-FEEDBACK.md` the
owner's open requests.

Most of the code here is written with [Claude Code](https://claude.com/claude-code), directed and
play-tested by the owner. `CLAUDE.md` is its index to the repo. If you send a change upstream to
BAR or CircuitAI, their `AI_POLICY.md` asks you to disclose AI-assisted code and to have a human
verify it.

## Credits

Apex is built on [CircuitAI](https://github.com/rlcevg/CircuitAI) by rlcevg (its `barbarian`
branch is BARb), [Beyond All Reason](https://github.com/beyond-all-reason/Beyond-All-Reason) and
the [Recoil engine](https://github.com/beyond-all-reason/RecoilEngine). The BAR Discord is where
their developers are.
