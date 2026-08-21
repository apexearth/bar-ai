--------------------------------------------------------------------------------
-- dbg_army_value.lua -- army metal per team, live, while you watch.
--
-- "I see us die from the same thing almost every time. Enemy has huge army, we
-- have no army." The infolog knows this after the fact; this puts it on screen
-- while it is happening, so a game can be read as it plays instead of being
-- reconstructed from telemetry afterwards.
--
-- Unsynced widget, local only. It reads unit lists and draws; it issues no
-- commands and touches no game state, so it cannot affect or desync a game.
--
-- Spectating (which is what watching an AI match is) gives full vision and the
-- numbers are exact for every team. As a PLAYER you only see your own side plus
-- whatever is currently in your line of sight, so enemy rows are marked "~" to
-- say so -- that undercount is itself the point, since it is exactly what the
-- AI's own gates can see.
--
-- Install: <writedir>/LuaUI/Widgets/dbg_army_value.lua
--   python tools/deploy_ai.py widgets
--------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name    = "Army Value",
		desc    = "Per-team army metal, with each ally side's total.",
		author  = "bar-ai",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 0,
		enabled = true,
	}
end

local UPDATE_FRAMES = 15          -- twice a second; the sums walk every unit

-- EVERYTHING SCALES WITH THE VIEWPORT. Fixed pixel sizes are unreadable on the
-- 4K display this is actually watched on and oversized on a small window, so the
-- panel is sized as a fraction of screen height and recomputed on resize.
local BASE_H     = 1080           -- the height the sizes below are written for
local HEAD_FONT  = 20
local ROW_FONT   = 18
local LINE_BASE  = 24
local WIDTH_BASE = 300
local MARGIN_BASE = 16

local vsx, vsy = Spring.GetViewGeometry()
local scale, headFont, rowFont, lineH, width, margin

local function rescale()
	scale = math.max(1, vsy / BASE_H)
	headFont = HEAD_FONT * scale
	rowFont  = ROW_FONT * scale
	lineH    = LINE_BASE * scale
	width    = WIDTH_BASE * scale
	margin   = MARGIN_BASE * scale
end
rescale()

local glText  = gl.Text
local glColor = gl.Color
local glRect  = gl.Rect

local spGetTeamList      = Spring.GetTeamList
local spGetTeamUnits     = Spring.GetTeamUnits
local spGetTeamInfo      = Spring.GetTeamInfo
local spGetTeamColor     = Spring.GetTeamColor
local spGetUnitDefID     = Spring.GetUnitDefID
local spGetAllyTeamList  = Spring.GetAllyTeamList
local spGetSpectatingState = Spring.GetSpectatingState

-- Mobile units with a weapon. Buildings are excluded deliberately: the question
-- is what can march at you, which is not what a turret line is worth.
--
-- The COMMANDER is excluded too: it is armed and mobile, but it is the thing the
-- army exists to protect and it is never the army. At ~2,700 metal it also
-- dominates the number in exactly the early game where the comparison matters
-- most. Decoy and scav variants go with it, the same set BAR's own commander
-- widgets test for.
local isArmy = {}
for udid, ud in pairs(UnitDefs) do
	local cp = ud.customParams or {}
	local isComm = cp.iscommander or cp.isdecoycommander
		or cp.isscavcommander or cp.isscavdecoycommander
	isArmy[udid] = (not ud.isBuilding)
		and ud.speed and ud.speed > 0
		and ud.weapons and #ud.weapons > 0
		and not ud.isFactory
		and not isComm
end

local cost = {}
for udid, ud in pairs(UnitDefs) do
	cost[udid] = ud.metalCost or 0
end

local rows = {}        -- { text, r, g, b }
local nextUpdate = 0
local amSpec = false

local function fmt(n)
	if n >= 10000 then
		return string.format("%.0fk", n / 1000)
	end
	return string.format("%d", n)
end

local function rebuild()
	rows = {}
	amSpec = spGetSpectatingState()

	local allyTotals = {}
	local perTeam = {}

	local gaia = Spring.GetGaiaTeamID()
	for _, teamID in ipairs(spGetTeamList()) do
		if teamID ~= gaia then
		local units = spGetTeamUnits(teamID)
		local sum = 0
		if units then
			for i = 1, #units do
				local udid = spGetUnitDefID(units[i])
				-- A unit outside our vision returns a nil defID; it simply does
				-- not count, which is the honest answer rather than a guess.
				if udid and isArmy[udid] then
					sum = sum + (cost[udid] or 0)
				end
			end
		end
		local _, _, _, isAI, _, allyID = spGetTeamInfo(teamID)
		if allyID then
			allyTotals[allyID] = (allyTotals[allyID] or 0) + sum
			perTeam[#perTeam + 1] = { teamID = teamID, allyID = allyID, sum = sum, isAI = isAI }
		end
		end
	end

	-- Ally sides first, then their teams under them, so the comparison that
	-- matters -- our whole side against theirs -- is the top line.
	for _, allyID in ipairs(spGetAllyTeamList()) do
		local total = allyTotals[allyID]
		if total then
			rows[#rows + 1] = {
				string.format("ally %d: %s", allyID, fmt(total)), 1, 1, 1,
			}
			for _, t in ipairs(perTeam) do
				if t.allyID == allyID then
					local r, g, b = spGetTeamColor(t.teamID)
					rows[#rows + 1] = {
						string.format("   team %d  %s", t.teamID, fmt(t.sum)),
						r or 1, g or 1, b or 1,
					}
				end
			end
		end
	end

	if not amSpec then
		rows[#rows + 1] = { "~ enemy rows are LOS-limited", 0.7, 0.7, 0.7 }
	end
end

function widget:GameFrame(n)
	if n >= nextUpdate then
		nextUpdate = n + UPDATE_FRAMES
		rebuild()
	end
end

function widget:ViewResize(x, y)
	vsx, vsy = x, y
	rescale()
end

function widget:DrawScreen()
	if #rows == 0 then
		return
	end
	-- Top right, drawn DOWNWARD from the corner, so the panel grows toward the
	-- middle of the screen as teams are listed instead of walking off the top.
	local x = vsx - width - margin
	local top = vsy - margin
	local h = (#rows + 1) * lineH
	local pad = 8 * scale
	glColor(0, 0, 0, 0.55)
	glRect(x - pad, top - h - pad, vsx - margin + pad, top + pad)
	glColor(1, 1, 1, 1)
	glText("ARMY METAL", x, top - lineH, headFont, "o")
	for i = 1, #rows do
		local row = rows[i]
		glColor(row[2], row[3], row[4], 1)
		glText(row[1], x, top - lineH - (i * lineH), rowFont, "o")
	end
	glColor(1, 1, 1, 1)
end
