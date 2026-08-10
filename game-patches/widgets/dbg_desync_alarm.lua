--------------------------------------------------------------------------------
-- dbg_desync_alarm.lua -- make a desync impossible to miss.
--
-- A sync error is silent in the client: the engine writes
-- "Sync error for <name> in frame <n>" to the infolog and the game carries on
-- looking normal, so the first sign is usually that the replay disagrees with
-- what you watched. This paints it across the screen instead.
--
-- Unsynced widget, local only. It reads the console and draws; it issues no
-- commands and touches no game state, so it cannot itself affect a game.
--
-- Install: <writedir>/LuaUI/Widgets/dbg_desync_alarm.lua
--   python tools/deploy_ai.py widgets
--------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name    = "Desync Alarm",
		desc    = "Flashes a full-screen warning when the engine reports a sync error.",
		author  = "bar-ai",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 1000,
		enabled = true,
	}
end

local firstFrame, firstWho, count = nil, nil, 0
local lastSeen = 0

local glColor       = gl.Color
local glRect        = gl.Rect
local glText        = gl.Text
local spGetGameFrame = Spring.GetGameFrame
local spGetViewGeometry = Spring.GetViewGeometry

-- The engine's own wording, from CGameServer. Matched loosely on purpose: the
-- name can be anything, and a pattern that stops matching after an engine
-- update would fail exactly the way this widget exists to prevent.
local SYNC_PATTERN = "Sync error for (.+) in frame (%d+)"

function widget:AddConsoleLine(line)
	local who, frame = string.match(line or "", SYNC_PATTERN)
	if not who then
		return
	end
	count = count + 1
	lastSeen = spGetGameFrame()
	if not firstFrame then
		firstFrame, firstWho = tonumber(frame), who
		Spring.Echo(string.format(
			"DESYNC: %s diverged at frame %d. This game is no longer trustworthy.",
			who, firstFrame))
		Spring.PlaySoundFile("sounds/ui/mappoint.wav", 1.0, "ui")
	end
end

function widget:DrawScreen()
	if not firstFrame then
		return
	end
	local vsx, vsy = spGetViewGeometry()

	-- Solid band rather than a fading toast: this must still be on screen when
	-- you look up two minutes later.
	local pulse = 0.35 + 0.25 * math.abs(math.sin(os.clock() * 3))
	glColor(0.6, 0, 0, pulse)
	glRect(0, vsy * 0.86, vsx, vsy * 0.96)

	glColor(1, 1, 1, 1)
	glText(string.format("\255\255\60\60DESYNC -- %s diverged at frame %d (%.1f min)",
		firstWho, firstFrame, firstFrame / 1800),
		vsx * 0.5, vsy * 0.915, 26, "cn")
	glText(string.format("\255\255\200\200%d sync errors so far; last at frame %d",
		count, lastSeen),
		vsx * 0.5, vsy * 0.878, 16, "cn")
	glColor(1, 1, 1, 1)
end
