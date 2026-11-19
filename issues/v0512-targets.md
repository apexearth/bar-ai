# His v0.5.12 targets and the 11-15/11-16 asks: where each stands

Measured 11-16 on the v0.5.14 code (rc9 + rc10 + na9: 48 games, 88 seats a side, vs v0.5.13, +50, both factions),
`python tools/contract.py "matches/rc9-*" "matches/rc10-*" "matches/na9-*"`. "Aim" is his word made a number; a
check gates a release only against the previous release. Re-run this table after each release gate.

| Target (his words, short) | Check | v0.5.14 | v0.5.13 | Aim | Where it stands |
|---|---|---|---|---|---|
| Validate games; keep known issues out of releases | `tools/contract.py` on every ledger page; `deploy_ai.py` refuses a release without a recorded PASS or his `--allow-red` | - | - | - | built; v0.5.14 shipped on his --allow-red |
| Anomaly detector | `anomalous seats` (tools/anomaly.py, per-release baseline) | 0.00 (rc9) | 0.08 | 0 | built; v0.5.14 baseline to build from its own games |
| Never leave nearly-finished buildings | `near-done /10k built` (per metal since his 11-16) | 0.51 | 0.48 | 0 | level with release, short of aim |
| First T2 con takes mexes 1x->4x in ~3 min | `t2->4th moho (min)` | 5.91 | 6.32 | 3.0 | better, short of aim |
| T2 lab builder must not wander | `lab-job leaves/job` | 0.55 | 0.59 | 0 | level, short of aim |
| Only one T2 con | `lone t2 con minutes`, `oldest plant order min` | 0.51, 3.75 | 0.55, 3.46 | 0 | level |
| Analyse build inefficiencies | `adv plant frame x` (slowbuild), `supers before 4 moho` | 1.93, 2.73 | 1.87, 3.81 | 1.5, 0 | level / better |
| Rebuild after a base loss | `frozen minutes`, `bare-hands minutes`; scenario rebuild_bare | 0.18, 0.16 | 0.75, 0.82 | 0 | 4x better; open ground recovers (lab at 4.2 min); a base under an enemy army is row 114 |
| Bombers go in with escort, never turn back | `wiped bomber runs`, `runs turned back` | 0.39, 0.06 | 0.49, 0.04 | 0 | better / level |
| Bomber escort sized for ~400 fighters | `wiped bomber runs` | 0.39 | 0.49 | 0 | better; no game here had 400 enemy fighters |
| No nukes on mountain tops | `apex: nuke-guess` (logs only when the guess is moved) | 0 moves in 420 volleys | - | - | never needed on the test maps; unproven on his map (validation 103) |
| Tanky ground units hold the front / fight back when pushed | `ground given up share`; raid answer A/B (results/row114) | 0.29 | n/a | 0 | raid answer under the stock army built, measured (vs v0.5.14 28 vs 23 of 44; vs WRDistilled 8 vs 8 of 16) and shipped OFF in v0.5.15 after his watch game fed units into their army; delete or keep: his call |
| Don't send the whole army after small raids (his 11-16) | `raid answer army share` | max 0.31, median 0.05 (ra1+ra2) | n/a | - | built (smallest covering group); off with the answer |
| Stacked radar/jammers | `stacked radar/jammers` | 0.14 | 0.44 | 0 | 3x better |
| Stuck pushes into wrecks | `army stuck /10min/1k army` | 2.01 | 2.52 | 0 | better |
| Constructor blob | `log peak cons per income` | -1.67 | -1.64 | - | level |
| LRPC on encroaching armies | scenarios lrpc_army, lrpc_melee | 4 and 12 Hammers killed; own line spared | 0 and 0 | - | shipped in v0.5.14 |
| Base lost while the pricer read covered | `base lost while 'covered' k` | 6.26 | 4.64 | 0 | FAIL pooled; rc10 alone 4.41 vs 4.40; the release side reads 4.5-8.0 by batch |
| Releases v0.5.12 - v0.5.17 | git tags, GitHub releases | - | - | - | released; v0.5.17 (11-18, 05f05db0): rc19 vs v0.5.16 won or ahead 11 of 20 (rc17, same game code, 17 of 20), contract PASS recorded, fresh review findings fixed, CI green; v0.5.16 (11-17) passed rc16 vs v0.5.15, won or ahead 14 of 20, contract PASS recorded, fresh review clean; v0.5.15 (engine 2026.09.03) checked after shipping: rv2/rv3/rv5/rv6, 80 games vs v0.5.14, won or ahead 0.56 vs 0.50, nothing that repeats |

## The 11-16 asks (vs WRDistilled), as of 11-17

| Ask | Check | Where it stands |
|---|---|---|
| Our AI on BAR's new engine | lobby shows Apex | done: v0.5.14 and v0.5.15 installed and run on recoil_2026.09.03 |
| One chat line naming each Apex AI by its game name | `/say` at 3 s | in v0.5.15; one line per host in v0.5.16 (smoke: "Shellshocker is Apex v0.5.16"); his live game unconfirmed |
| The commander not caught out on their half | `com minutes on their half`, `com lost on their half` | COM_UNSEEN measured and removed; v0.5.15 level with v0.5.14 over 80 games; the extractor-claim walk past the middle is open (validation 117) |
| Extractors not lost to Ticks | `mex lost to ticks by 10 min`, scenario ticks_mexes | v0.5.16: early extractor net lift capped at the guard's, per-mex floor not zeroed before the first raid, bare rate for uncovered guards; vs WRDistilled 16 pairs, lost to Ticks by 10 min 37 vs 70 (t=-4.66). Open: losses where no guard was anticipated (validation 118). v0.5.17's stock escorts raise it vs BARb (2.40 vs 1.00 a game, contract FAIL); his 11-18 call: shipped, deferred to our own fight layer (issues/ticks-flank-extractors.md) |
| Raid their extractors | `their mex killed /10min` | his choice (spam aimed at their economy) built and measured, no effect over 32 pairs (17.2 vs 16.0), removed. v0.5.17: stock escorts free the raiders; vs BARb hard, enemy extractors killed by raiders after minute 12 37 vs 13 (20 seeds), income at 20 263 vs 228 (validation 119) |
| Lobby options a player can understand (his 11-18, after a player's Greed question) | AIOptions.lua | v0.5.17: only Personalities, Economy player and Advanced remain, each described plainly; C++ fallbacks keep the removed ones at their old defaults |
| Heavy-army strategy: medium army behind defences, resbots eat the reclaim, win the trade | `lost per killed`, `reclaimed / killed`, `their army / ours` | resbot cap removed in v0.5.16 on his rule (48 pairs: won or ahead 21 vs 16, lost per killed 1.06 vs 1.25) |
| No swearing in files | grep | done (code, tools, docs reworded) |
| Tests on Comet Catcher 1v1, both +50 | batch lists | done since 11-16 |
| The audit gate | contract per page | his 11-17 OK: a check fails only past noise (90% of game resamples); identical play now passes; the head-to-head stays a point test (beat the previous release) |
