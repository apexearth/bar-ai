# Take over dead AI slots

His ask (11-12): when an AI slot on a team has nothing running it, one of our AIs should take control of it. Two
cases cause this: someone in the lobby cloned his Apex onto a machine that doesn't have it installed, or the player
hosting an AI left. He is often a spectator in these games.

## What the engine allows

- A missing AI library makes the engine kill that AI at load ("AI failed to init"). Its team is left with no
  leader and no AI, and the commanders stand idle. BAR's game_end only kill-checks teams that have players.
- BAR's `/take` (luarules `take2`, `cmd_idle_players.lua`) moves an empty team's units to the human who typed it,
  using synced Lua. An AI cannot do that: it can only give away its own units.
- The engine's `/aicontrol <team> <shortName> <version> <name>` starts an AI on an allied team with no leader. An
  AI's `SendTextMessage` that starts with `/` runs as a command of the local player (`CAICallback::SendTextMsg` →
  `ProcessCommandText`), not as chat. The client allows it when the player is allied with the team. A spectator
  counts as team 0 (`CGameSetup::RemapTeams`).
- **The blocker:** the game server refuses `/aicontrol` from every player by default (`aiControlFlags.fill(true)`
  in `CGameServer`). Only the server's `/aictrl <player>` command unblocks one, and the cheat setting does not
  change this. In BAR's online battles the server is the autohost, so this needs BAR or its autohost to grant
  `/aictrl` (for example to the battle's boss), or a synced `/take` variant that hands an empty AI slot's units to
  an allied AI team the issuer hosts.

## Built and parked

`take-over-dead-ai-slots.patch`, against `cpp/src/circuit/CircuitAI.{h,cpp}` at v0.5.10. Once a second, one Apex
per process looks for an `[aiN]` slot from the start script with no AI controller and BAR's
`numActivePlayers` = 0. It sends `/aicontrol` for that slot (3 tries, 10 s apart).

Headless test, 11-12 (`matches/takeover-test1`): 2v2 plus a `GhostAI` slot on our side. The slot was detected,
the client check passed, and the server refused with "player 0 not allowed to use /aicontrol". The client then
reported "an AI being created" for that team, which blocked later tries. Two things to fix before using it:
wait until the dead AI is removed (the first try fired at frame 0, before removal), and retry after a server
refusal.

Next: ask BAR's developers whether the autohost can grant `/aictrl`, or whether `/take` can target an allied AI
team.
