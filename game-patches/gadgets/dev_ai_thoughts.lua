--------------------------------------------------------------------------------
-- dev_ai_thoughts.lua -- one panel per Apex AI seat: what it is thinking and doing.
--
-- His 10-24: "a UI widget which showed everything about what the AI is thinking/doing to help in realtime visual
-- debugging". With apex_verbose=1 each seat sends `ai_think:<team>\n<line>\n<line>...` every 3 s through CallRules
-- (ai.SendToLua): its plan, phase and threat modifier, the armies, the plan prices, and its last events. Chat could
-- not do this: an AI's SendTextMessage never reached a spectator.
--
-- RecvSkirmishAIMessage is always unsynced, so this is the unsynced half of a LuaRules gadget, like
-- dev_ai_threat_overlay.lua. Dev only: it draws nothing until an AI sends, which only apex_verbose does.
--------------------------------------------------------------------------------

function gadget:GetInfo()
	return {
		name    = "Dev AI Thoughts",
		desc    = "Draws each Apex AI seat's plan, phase, threat modifier and recent decisions (apex_verbose=1).",
		author  = "apex",
		date    = "2026-10-24",
		license = "GPL v2 or later",
		layer   = 0,
		enabled = true,
	}
end

-- The engine calls the global RecvSkirmishAIMessage in the active Lua state, which a headless test showed is not
-- reliably the unsynced one (the AI sent, the unsynced half heard nothing): the synced half relays to the unsynced.
-- Only apex_verbose sends, and a hosted game never sets it.
if gadgetHandler:IsSyncedCode() then
	function gadget:RecvSkirmishAIMessage(aiTeam, msg)
		if type(msg) == "string" and msg:sub(1, 9) == "ai_think:" then
			SendToUnsynced("ai_think_relay", aiTeam, msg)
		end
	end
	return
end

local seats = {}      -- team -> { lines = {...}, at = frame }
local order = {}      -- teams in the order they first spoke
local FONT = 13
local PAD = 6
local WIDTH = 720
local STALE = 30 * 30 -- frames: a seat silent for 30 s is dropped

function gadget:RecvSkirmishAIMessage(aiTeam, msg)
	if type(msg) ~= "string" or msg:sub(1, 9) ~= "ai_think:" then
		return
	end
	local body = msg:sub(10)
	local lines = {}
	for line in body:gmatch("[^\n]+") do
		lines[#lines + 1] = line
	end
	local team = tonumber(lines[1]) or aiTeam
	table.remove(lines, 1)
	if not seats[team] then
		order[#order + 1] = team
		Spring.Echo("[ai-thoughts] first message from seat " .. tostring(team) .. ": " .. tostring(lines[1]))
	end
	seats[team] = { lines = lines, at = Spring.GetGameFrame() }
	-- the widget draws it, scaled to the screen (dev_ai_thoughts_panel.lua)
	if Script.LuaUI("AiThoughts") then
		Script.LuaUI.AiThoughts(team, msg)
	end
end

function gadget:Initialize()
	gadgetHandler:AddSyncAction("ai_think_relay", function(_, aiTeam, msg)
		gadget:RecvSkirmishAIMessage(aiTeam, msg)
	end)
end

function gadget:Shutdown()
	gadgetHandler:RemoveSyncAction("ai_think_relay")
end

function gadget:DrawScreen_unused()
	if #order == 0 then
		return
	end
	local vsx, vsy = gadgetHandler:GetViewSizes()
	local now = Spring.GetGameFrame()
	local x = 12
	local y = vsy - 140
	for _, team in ipairs(order) do
		local s = seats[team]
		if s and (now - s.at) < STALE then
			local h = (#s.lines + 1) * (FONT + 3) + 2 * PAD
			gl.Color(0, 0, 0, 0.55)
			gl.Rect(x, y - h, x + WIDTH, y)
			local r, g, b = Spring.GetTeamColor(team)
			gl.Color(r or 1, g or 1, b or 1, 1)
			gl.Rect(x, y - 3, x + WIDTH, y)
			local ty = y - PAD - FONT
			gl.Text("Apex seat " .. team, x + PAD, ty, FONT + 1, "o")
			ty = ty - (FONT + 3)
			for i, line in ipairs(s.lines) do
				-- state lines bright, events dimmer
				gl.Color(1, 1, 1, (i <= 3) and 1.0 or 0.8)
				gl.Text(line, x + PAD, ty, FONT, "o")
				ty = ty - (FONT + 3)
			end
			y = y - h - 8
			if y < 120 then
				x = x + WIDTH + 12
				y = vsy - 140
			end
		end
	end
	gl.Color(1, 1, 1, 1)
end
