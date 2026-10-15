# Traps

Every trap here has the same shape: the thing did not work, and nothing said so. One line each:
the mechanism, then the check. The S numbers are cited by CLAUDE.md, tools and code comments, so
they never change; the evidence behind each is in git (`git log -p docs/25-silent-failures.md`).

## Method

- **The path fires is not evidence.** Firing proves a change is wired up, not what it displaced: twelve individually firing changes took head-to-head 2-2 to 0-8 and metal 141k to 33k. Judge on `composition.py`, one change at a time.
- **Instrument first.** Prove the path carries the decision before changing it; if the instrument shows the decision did not move, say so.
- **A sampled log is not a census**; a metric that cannot tell the two states apart is no evidence; two seeds cannot resolve a change.
- **Absence is the least reliable finding**: not finding a file, unit or call proves the search failed.
- **A rule that can decline to act counts how often it was asked** (a denominator beside an action term), or `deadcheck.py` cannot see it never fired.
- **Capture what you compare against before mutating it** (a target cleared 82 lines above the test that read it).

## The S list

- **S1** A variant that is only a *version* of BARb loads stock BARb in every hosted game (lobby sends no version). Check: own shortName; `run_match.py --drop-ai-version` reproduces.
- **S2** (removed) `ApexActive()` once ran stock logic in a plain 1v1; it now always returns true.
- **S3** An AngelScript compile error disables the variant and the match still runs near-stock. Check: grep the infolog for `ERR` and `Fix compilation errors`, never anchored on a filename (warnings-as-errors print with no file); `review.py` gate 1.
- **S4** AngelScript has no forward declarations: `Foo();` at global scope is a property and a `Name conflict`. Just call it; only a global's initializer depends on order (`as_scope.py`).
- **S5** A unit asked to build what its own def does not list is a silent no-op. Check: `unitdef.py <unit> --builds`.
- **S6** `aiMilitaryMgr.quota.attack` caps units sent to attack, not units built.
- **S7** An engine callback can be silently dead (`Game_getTeamResource*` read -1). Check: log the raw return once before building on it; route round via a gadget rules param.
- **S8** Deploying the AI is not deploying the gadget: an unpublished `apex_*` modoption runs the compiled default with no error. Check: `deploy_ai.py gadgets`, then grep the name in the deployed `dev_tunables.lua`.
- **S9** `GetBuilderThreatAt` reads off-map memory (crash at frame 3) and is zero almost everywhere. Guard with `OnMap()`; never trigger on it.
- **S10** Never answer a unit question from a filename search: defs sit in arbitrary folders and buildability is the constructors' buildoptions. Use `unitdef.py`.
- **S11** "This unit does not exist" is a claim about one tree: `BAR.sdd` is pinned, `vendor/bar` tracks master. `unitdef.py` labels the source.
- **S12** A duplicate `RegisterObjectMethod` kills the AI at init; `result.json` shows `crashed` with empty stats. Check the infolog for `Failed in call to function 'RegisterObjectMethod'`.
- **S13** An order is not applied when issued, and the lag grows with sim speed: "read and top up" loops issue an order per tick. Keep a ledger of what was sent; read only to confirm (`async-sim-orders`).
- **S14** `AiMakeTask` is a re-election on every task update: a rule that enqueues before returning orphans all but the first. Return the existing task.
- **S15** A watch game's infolog reaches the match dir only at game end; mid-game reads can be days old. Check the mtime first.
- **S16** `result.json` `teams[].team` is the spec index, not the engine team. Anchor sides on the spec's allyteam; test any new tool on a side-swapped game.
- **S17** Aggregate over the right unit: a team-wide median hid that the one rusher techs at 6 min.
- **S18** A `str.replace` / edit anchor that does not match does nothing. Assert it exists; mind CR in `cpp/` and some root files (`normalize_eol.py`).
- **S19** The deployed script can change under a running sweep. Classify each game from its own log, not from the file you edited.
- **S20** A latch-once cache is a decision about when: triggering its fill from a new caller changed the spot list (metal 8,775 to 3,150). Read such a global only once its owner filled it; a status line fires on every path, including declining.
- **S21** `pathlib.read_text()/write_text()` on Windows transcode to cp1252 and CRLF. Use `Edit`, or `encoding="utf-8"` and `write_bytes`; a `git diff --stat` larger than your edit is the tell.
- **S22** A named-lane deploy once shipped a stale lane snapshot (fixed). Check: grep a new symbol in the deployed tree after every deploy.
- **S23** A named-lane deploy once shipped the active lane's half-linked DLL and the engine seated nothing (fixed; `not found!` is now a crash). Check: md5 of the deployed DLL against its build output.
- **S24** At full sim speed a tail of builder orders lands late or never, and the stuck watch kills those tasks. Eco runs go at a capped `--speed`; both arms of a battery suffer it equally.
- **S25** `.barai-lane` was one file per checkout, so sessions shared a lane (fixed: claims keyed by session id; a session with no claim is refused by writing tools).
- **S26** A deploy with no local build once shipped the stale checked-in DLL, which lacked bindings (S3). `deploy` now refuses without `--repo-dll`.
- **S27** The engine discards a build order on a blocked square before queueing it: no error, no idle event, the builder stands holding a live task. `apex: com-still ... q=0` is the instrument; never read idle % off a full-speed battery.
- **S28** `GetEnemyCostAt` returns a count of visible units, not metal. Use `GetEnemyStructCostAt` for metal; audit any reader that compares it with metal.
- **S29** An uncapped battery measures the CPU: we are sliced against the wall clock and BARb is not. Every batch passes `--speed`.
- **S30** `byUs` on an enemy death is "attacker alive and ours": a bomb whose plane died reads -1. Count deaths in the strike's cell and window, whoever is credited.
- **S31** A hitch the AI's clock cannot see: a long console line costs `gui_chat.lua` quadratic time. Nothing long goes through `Spring.Echo`; `hitch.py` reads the infolog's wall gaps.
- **S32** An emergency whose exit is a growing target is a standing rule (a "panic" hoist that never ends). Bound the emergency; measure its outcome, not its firing.
- **S33** A subclass override can skip the chokepoint while the chokepoint's own log says it fired. `grep -l "::Execute(" task/builder/*.cpp`; an instrument's pass bar must be tighter than the complaint.
- **S34** A full-speed headless game on hilly maps stalls both AIs' economies. Cap the speed and check `ecotimeline.py`: a bank pinned at 100% from minute 2 is a stalled run.
- **S35** A refusal memory keyed only by position bans the ground for every def. Key refusals by what was refused.
- **S36** The script's "this cell fits" and the DLL's commit asked different questions. A site proved by one predicate and committed by another is not proved; log the commit's reason (`cell-refused`).
- **S37** An election that hands back the task the hand was just taken off makes the peel a no-op. A task remembered per unit is the unit's only while `GetUnits()` says so.
- **S38** An order to a unit that holds a DLL task is a suggestion: turrets told to reclaim were re-tasked to repair the same thing. Count what the unit is doing seconds later.
- **S39** Deploy once overwrote the trained nets with the repo stub. A file another process owns in a deployed tree must be named in the copy, not only in the checksum.
- **S40** Training rows keyed by decision frames repeat on clocked decisions every game. A "seen" key must contain something unique to the game.
- **S41** A field saved every batch and never loaded (trust pairs). For every field a save writes, find the line that reads it back.
- **S42** A strength test weighing one seat against the whole enemy side (fixed three times). In a team game "ours" is the side; `check.py` fails a `StrRatio` caller that does not count allies unless marked `// seat-local: <why>`.
- **S43** A field appended to a logged line broke its parser silently. When you append to a log line, grep `tools/` for its parser and run it on a fresh game.
- **S44** A comment named a guard that no longer existed; a `fightTasks` set holds freed tasks. Grep a guard's name before trusting a comment; scan `updateTasks` for live tasks.

## Engine and binding facts that bite

- **S45** A recruit task's `Finish()` wipes the factory's whole build queue, so a line is ours or CircuitAI's, never both.
- **S46** SHIFT multiplies a factory build order by 5 and CTRL by 20; use `CMD_INSERT`.
- **S47** `cast<IBuilderTask@>` does not compile; call `GetBuildType`/`GetBuildPos`/`buildDef` on the `IUnitTask@`.
- **S48** `CCircuitUnit::GetHealthPercent()` is a 0..1 fraction.
- **S49** `aiMilitaryMgr.Enqueue(TaskF::Common(ATTACK))` crashes the DLL; change the quota and let the manager form the task.
- **S50** `aiEnemyMgr.GetEnemyPos()` is ZeroVector while no enemy group is known; enemy group data is LOS-only.
- **S51** AngelScript and JSON load at AI init: there is no hot reload, a new match is needed.
- **S52** `FixedRNGSeed` does not make runs reproducible (the DLL is multithreaded); a fixed seed also lets a search overfit one game.
- **S53** A lane name with a leading underscore deploys cleanly and the engine never finds it (the scan skips `_` directories).
- **S54** A failed ninja leaves the old DLL in place and deploy still says `(local build)`; piping ninja through grep hides its exit code. Build with `tools/build_dll.py`.
- **S55** `behaviour.json` names do not say what they do: `quota.thr_mod` is a divisor (lower = braver), `quota.attack` is overwritten at runtime by the massing code and by the C++ promotion bar, and a `retreat` list's length changes its meaning. Check the parser before an A/B of a config value.
- **S56** A unit name that resolves can still be a no-op: a real def nothing we field can build (`armfmkr` from ground constructors) gets requests and no buildings. Reachability is a closure from our constructors and factories (`check_unit_refs.py --builders`).
