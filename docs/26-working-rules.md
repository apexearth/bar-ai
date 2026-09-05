# 26 — Working rules

How to work in this repo: the harness traps, the policy line you must not cross
alone, comment discipline, delegation, and apexearth's workflow. `CLAUDE.md`
routes here; this file is the text.

---

## Ask before inventing policy

apexearth, after a hard cap of 4 was added to something he had twice said should
scale with the economy: *"damn you have me worried about whatever other bad ideas
you may randomly add. You should update claude.md so you ask more questions
before just making decisions like that."*

The failure is not being wrong once. It is deciding a POLICY question — what the
AI is allowed to do — as if it were an implementation detail, and burying the
answer in a constant. These four keep happening:

- **Hard caps and ceilings.** "At most 4 of these." He has said twice that
  nothing should have a hard cap; everything scales with economy and progression.
  If something is being built too often, the fix is its VALUE relative to
  alternatives, not a number that forbids the eleventh one.
- **Exclusivity.** "Only the eco lead may build reactors", "only the tech lead
  may go T2". This shipped for weeks and made a solo player never build a reactor
  at all. A role may change how OFTEN or how MUCH; it must not decide WHETHER.
- **Turning a behaviour off** to fix a symptom, rather than finding what starves
  it. Front-line nanos got defaulted off after one arm; he wanted them on and
  tuned.
- **Thresholds pulled out of the air.** A gate at "60 metal/s" is a claim about
  the game. Derive it, measure it, or ask — and say which of the three it was.

`docs/23-the-plan.md` says why all four are the same mistake, and it is not a
style preference: **order, numbers and limits are OUTPUTS of the ETA
arithmetic.** A cap, a sequence or a bar is the model being overridden by hand by
someone who has not checked whether the model already disagrees.

What to do instead, in order of preference:

1. **Derive it from the economy** — income, bank, what the thing costs, what it
   returns, and how much sooner it makes the target arrive. That is the answer he
   gives every time he is asked.
2. **Ask.** One sentence: "should X be capped, or scale with income?" He answers
   these in seconds and the answer is usually "scale".
3. **A named constant**, with the derivation in the commit message.

**A TUNABLE IS THE LAST RESORT, NOT THE SAFE MIDDLE.** This list used to offer
"make it a tunable with the measured default" as option 2, and because it was the
cheapest of the three it was chosen almost every time. Measured 2026-08-30: **404
tunables declared, 316 read at exactly one call site, and 360 never overridden in
a single recorded run.** They are not experiments; they are constants wearing an
experiment's clothing, and each costs four registration sites (`tunables.as`,
`dev_tunables.lua`, `dashboard_guide.py`, the audit waiver) plus a line of
apexearth's attention on the dashboard.

Create a tunable ONLY when you are going to sweep it in this session and will
report the sweep. Otherwise use a named constant. `python
tools/dashboard_audit.py --stale` lists every tunable never overridden in a run;
that list is a cull list, and folding one back into a constant is always a
welcome change.

Not every choice needs a question — fixing a null deref, wiring a rule that
already exists, following a stated preference. The trigger is: *am I deciding
what the AI is ALLOWED to do, rather than how to do what it was already meant to
do?* If yes, ask.

---

## A new tunable or mechanism is not finished until the dashboard shows it

`tools/dashboard.py` is apexearth's interface to this AI — he does not run the
CLI tools — so a knob that exists only in `tunables.as` is a knob he cannot
reach, and a modoption missing from `dev_tunables.lua` is silently ignored in
game (**S8**). Load the **`dashboard-ui`** skill before adding one. `check.py`
runs `tools/dashboard_audit.py`, which reports any tunable the guided view has
never seen, any it names that no longer exists, and any it offers that nothing
reads.

---

## Harness discipline

- **Never run two matches on one engine write-dir.** Both engines write the same
  `infolog.txt` and config tree; measured 2026-08-15, a watch game beside a long
  soak run broke the watch game's AI outright and filled the soak's log with
  interleaved binary garbage. `run_match.py` pidfile-guards `matches/_engine` and
  auto-suffixes a busy dir, but a hand-launched engine bypasses that — check
  `engine.pid` first.
- **Never edit a file a running tournament uses.** Editing `run_match.py` mid-run
  killed 17 matches with an `AttributeError`. The repo `ai/<variant>/` tree is
  safe to edit while running; deploying is what swaps live files.
- **Kill the waiter with the run.** Twice now, killing a tournament has left
  `until ...; sleep; done` shells polling forever for a file that will never be
  written. Stop the background task, not just the processes.
- **`pgrep` DOES NOT EXIST in this Git Bash, and a wait loop that uses it exits
  INSTANTLY.** `pgrep -f foo` returns 127 (command not found), so `until <done>
  || ! pgrep -f foo; do sleep; done` has a condition that is immediately TRUE —
  the wait never waits, and whatever is read next is stale. Cost 2026-09-01: a
  battery run reported as "still running" twice from a log that had stopped
  updating, while the run had in fact finished (apexearth: "I don't think your
  shells are doing anything"). Wait on an ARTIFACT (`until [ -f
  out/result.json ]`, a line count) or check processes with PowerShell
  `Get-Process`; never on `pgrep`.
- **`pkill -f` silently does nothing on Windows.** Use `powershell -NoProfile
  -Command "Get-Process python,spring-headless -ErrorAction SilentlyContinue |
  Stop-Process -Force"`, then verify the count is zero.
- **Run Python with `-u` when redirecting to a log.** Without it the log stays
  empty for the whole run and looks exactly like a dead process.
- **Tournament output lands in `tournaments/<stamp>-<name>/`, not `matches/`.**
- **Deploy in the foreground, then background the run.** Deploy → background run
  → keep coding is the sanctioned workflow (apexearth 2026-08-27: "It should be
  ok to deploy, run a background run to see how that change went, and continue to
  work on the code in the meantime"). The one rule inside it: the deploy's success
  must be VERIFIED before the run leans on it — a backgrounded `deploy && run &`
  hides a failed deploy, the run proceeds against a half-written AI folder, and
  `FetchSkirmishAILibrary: unknown skirmish AI` reads in telemetry as a
  catastrophic regression that is not one. Deploy and check the output (or
  `deploy_ai.py status`), THEN launch the run in the background.
- **Deploying while BAR is open fails with `WinError 5`** and leaves the AI folder
  half-written (`FetchSkirmishAILibrary: unknown skirmish AI`). Check for
  `spring.exe` / `Beyond-All-Reason.exe` first, and redeploy after closing. A
  running game that blocks a deploy may be killed — the write-dir does not tell
  you whose it is.
- **`FixedRNGSeed` does not make runs reproducible.** The AI DLL is
  multithreaded: the same seed produced first-T2 at 5.2, 6.9, 9.1 and 9.8
  minutes. Never read a single-run delta as an effect.
- **Confirm the AI under test is actually the one running**, via `Load script:
  LuaRules\Configs\Apex\<variant>\...` in the infolog. A replay cannot tell you
  this — in a replay AIs are "remote", `AiLog` output does not appear at all, and
  `Spring.GetAIInfo` reports `SYNCED_NOSHORTNAME`.

---

## apexearth is faster than the benchmark — ask him first

His standing requests live in `USER-FEEDBACK.md`; this section is only about the
workflow.

A watched game returns useful feedback in about **five minutes**. A tournament
with a matched control takes **twenty to thirty**, and on the standard benchmark
it frequently cannot answer the question at all: per-team income there is
4-9 metal/s against 12-41 in a hosted game, so anything gated on income never
fires, and win rate has swung 60% → 10% on an unchanged AI.

So the default order is:

1. **Deploy and hand him a windowed run** (`--watch --speed 5`) — but only when
   he has asked for one, or the work plainly needs his eyes; he mostly drives
   from the dashboard. Do it FIRST, before any measuring, so he is watching while
   other work continues.
2. Act on what he reports. Every diagnosis that has actually landed on this
   project came from him watching: "two v six battles", "Commando as the first
   unit out of the T2 lab", "cons at the front making mexes", "that's a 4v4 map".
3. Use a tournament to **confirm** a mechanism he has already identified, or to
   catch a regression. Not to go looking for one.

Corollary: never leave him idle while a control runs. Launch the watch run, then
do the slow measuring alongside it.

---

## Delegate only when asked, and keep agents short-lived

The fleet-of-agents workflow was tried and **measured worse**: single agents
reached 345k, 337k and 328k tokens and drove usage UP, because continuing an
agent replays its whole transcript. apexearth: *"You're wasting a lot of
tokens/usage by doing it like this. Prefer to NOT have long running agents."*

So: work directly by default. Spawn agents when he asks for them, or for
genuinely parallel work with **disjoint file ownership** — two agents editing one
file is a merge conflict you will pay for twice. Give each a fresh, bounded task
with the three facts it needs in the PROMPT; two or three exchanges is the
ceiling. Investigation can be parallel; implementation is serial and measured.

The one case where an agent *saves* context: a broad search whose file dumps you
do not need, where you only want the conclusion. Bound it to that.

**Write the finding down before the agent ends** — commit message for what
changed and what was measured, `ISSUES.md` for what is wrong and not yet fixed. A
finding left in a transcript is one you will pay to rediscover.

---

## Conventions

- Python 3.13, standard library only. No new dependencies without a reason.
- Tools import `bar_env`; they never hardcode install paths.
- Treat `reference/barb-stable/` as read-only — it's the diff baseline.
- Keep `ai/<variant>/` as the source of truth. If you edit configs directly
  inside `BAR.sdd` while iterating, run `deploy_ai.py pull <variant>` afterwards
  or the work will be lost on the next deploy.
- Line endings are LF (`.gitattributes`) so diffs against upstream stay readable.
  `ai/Unstable/` is fully LF as of 2026-09-04; `cpp/`, `changes/` and some root
  `.md` files still contain CR. Check before anchoring an edit there, or use
  `tools/normalize_eol.py`.
- Files are kept under ~600 lines deliberately: above that, work degenerates into
  grep-an-anchor-and-blind-replace, and an anchor that does not match fails
  silently (**S18**). That has eaten edits here at least five times.

### Comments — write far fewer than feels natural here

The long "tried X, measured Y, reverted" blocks already in `factory.as` are
load-bearing: they stop a failed experiment being retried. That is not licence to
add more of them. Four rules, each from a real mistake:

- **A code comment is not a session transcript.** apexearth, 2026-08-14, after a
  comment quoted his own complaint verbatim, listed a measured number, and
  narrated the fix history: "quit flooding our comments with events of our work,
  just state a concise 'why' and let that be it." One line: what this code does
  that looks wrong otherwise, and the reason. Not what was reported, not what was
  measured, not the session's timeline.
- **Never state a cause you did not measure.** A spacing fix was annotated "that
  is how a cap of 6 produced 15-20 constructors" — the cap holding at ≤6 had been
  measured; the claim about the overshoot never was. If it was reasoning, say so
  or leave it out. Wrong comments are worse than none.
- **Don't inline the commit message.** What was tried, what it scored, why it was
  reverted goes in the commit message. A comment earns its place by explaining a
  mechanism that is not visible in the code — a NOCOUNT handle, a jsoncpp parsing
  quirk, an engine gate that returns before the check you are reading.
- **Change the code, change the comment.** A declaration still read "cleared on a
  handover" after the clearing was removed. Re-read every comment attached to a
  line you touch.
- **Never write a finding into a comment. Findings go in the commit message or
  `ISSUES.md`.** A comment saying "Legion has legsy but no advanced shipyard" was
  written from a single failed `glob legasy.lua`. It was false — Legion builds
  `corasy` — and it sat in the code asserting the opposite as fact. This is the
  recurring failure: a conclusion drawn once, frozen in a comment, and then
  believed by the next reader long after it stopped being true. Measurements,
  unit costs, timings, "X never happens", "Y does not exist" are all findings.

  What may stay in a comment is a **mechanism you can see in the code being
  read** — an engine gate that returns early, an index shared between two files,
  a parser quirk. Not evidence for a decision; the reason a line cannot be
  deleted.

  Corollary: **absence is the least reliable finding of all.** Not finding a
  file, a unit or a call proves the search failed, not that the thing is missing.
  Never record "does not exist" anywhere on one search — check who builds it, who
  references it, and the game's own name tables first (**S10**, **S11**).

Default to none. Three lines is a lot; ten needs a reason.

---

## If contributing upstream

Split by layer: game-side configs → `beyond-all-reason/Beyond-All-Reason`
(`luarules/configs/BARb/`); C++ or AngelScript-binding changes →
`rlcevg/CircuitAI` branch `barbarian`.

BAR's `AI_POLICY.md` requires **explicit disclosure of AI-assisted code in the
PR**, and human verification of it. Undisclosed use gets the PR closed. This
applies to work done in this repo with Claude.
