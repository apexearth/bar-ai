--------------------------------------------------------------------------------
-- dev_autoquit.lua -- exit the engine when a headless benchmark match finishes.
--
-- Installed by tools/deploy_ai.py into BAR.sdd/luarules/gadgets/. It is inert
-- unless the start script sets the modoptions below, so it cannot affect a
-- normal game even while it sits in the gadget folder.
--
--   dev_autoquit        "1" to enable
--   dev_maxgameminutes  optional game-time cap in minutes; 0/absent = no cap
--
-- Both are set automatically by tools/run_match.py.
--
-- Spring.Quit lives in LuaUnsyncedCtrl, so this must be the unsynced half of
-- the gadget. gadget:GameOver only fires in the synced half, so the synced side
-- relays it across with SendToUnsynced.
--------------------------------------------------------------------------------

local modOptions = Spring.GetModOptions() or {}
local enabled = tostring(modOptions.dev_autoquit or "") == "1"

-- Telemetry goes through the log sink (dev_log_sink.lua), not the console.
local function BARAI_Echo(line)
	if GG and GG.BARAI_LOG then
		GG.BARAI_LOG(line)
	else
		Spring.Echo(line)
	end
end

function gadget:GetInfo()
	return {
		name    = "Dev Autoquit",
		desc    = "Quits the engine on game over. Headless benchmarking only.",
		author  = "bar-ai",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 1000,
		enabled = enabled,
	}
end

local maxFrames = 0
do
	local minutes = tonumber(modOptions.dev_maxgameminutes or 0) or 0
	if minutes > 0 then
		maxFrames = math.floor(minutes * 60 * 30) -- 30 sim frames per second
	end
end

if gadgetHandler:IsSyncedCode() then
	--------------------------------------------------------------------- synced

	local reported = false

	local function report(reason, winners)
		if reported then
			return
		end
		reported = true
		-- Printed to infolog so tools/run_match.py can read the result without
		-- parsing a replay.
		local list = {}
		for _, allyTeamID in ipairs(winners or {}) do
			list[#list + 1] = tostring(allyTeamID)
		end
		BARAI_Echo(string.format(
			"[BARAI_RESULT] reason=%s frame=%d winners=%s",
			reason, Spring.GetGameFrame(), table.concat(list, ",")
		))
		SendToUnsynced("baraiQuit")
	end

	function gadget:GameOver(winningAllyTeams)
		report("gameover", winningAllyTeams)
	end

	function gadget:GameFrame(frame)
		if maxFrames > 0 and frame >= maxFrames then
			report("timelimit", {})
		end
	end
else
	------------------------------------------------------------------- unsynced

	-- Give the engine a moment to flush the demo file and the infolog before
	-- tearing the process down; quitting inside the event itself truncates them.
	-- Counted in sim frames via GameFrame rather than Update, because Update is
	-- tied to the render loop and headless does not render.
	local countdown = nil

	local function onQuit()
		if countdown == nil then
			countdown = 30
		end
	end

	function gadget:Initialize()
		gadgetHandler:AddSyncAction("baraiQuit", onQuit)
	end

	function gadget:Shutdown()
		gadgetHandler:RemoveSyncAction("baraiQuit")
	end

	function gadget:GameFrame()
		if countdown == nil then
			return
		end
		countdown = countdown - 1
		if countdown <= 0 then
			countdown = nil
			BARAI_Echo("[BARAI_RESULT] quitting")
			Spring.Quit()
		end
	end
end
