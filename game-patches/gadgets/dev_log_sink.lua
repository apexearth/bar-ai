-- The dev gadgets' telemetry, kept off the screen.
--
-- Spring.Echo feeds one stream: the infolog, the in-game console and every
-- widget (S31). apexearth: "I still get a lot of text on my screen when
-- playing, white text at the top. It is the AI output. I don't want to see
-- that." So the synced gadgets hand their lines to GG.BARAI_LOG, this
-- gadget's unsynced half writes them to barai-gadgets.log in the write dir
-- with the engine's own [t=][f=] prefix, and tools/apexlog.py folds the file
-- back into the infolog after the game. A gadget that loads without this one
-- falls back to Spring.Echo (see BARAI_Echo in each).

function gadget:GetInfo()
	return {
		name    = "BARAI dev log sink",
		desc    = "routes [BARAI_*] telemetry to barai-gadgets.log instead of the console",
		author  = "bar-ai",
		date    = "2026-09-12",
		license = "GNU GPL, v2 or later",
		layer   = -1000,   -- before every dev_* gadget, so GG.BARAI_LOG exists when they load
		enabled = true,
	}
end

local FILE = "barai-gadgets.log"

if gadgetHandler:IsSyncedCode() then
	--------------------------------------------------------------------- synced
	function gadget:Initialize()
		GG.BARAI_LOG = function(line)
			SendToUnsynced("baraiLog", Spring.GetGameFrame(), line)
		end
	end

	function gadget:Shutdown()
		GG.BARAI_LOG = nil
	end
else
	------------------------------------------------------------------- unsynced
	local pending = {}
	local t0 = nil
	local ok = false

	local function stamp(frame)
		local s = Spring.DiffTimers(Spring.GetTimer(), t0)
		local hh = math.floor(s / 3600); s = s - hh * 3600
		local mm = math.floor(s / 60); s = s - mm * 60
		local ss = math.floor(s)
		local us = math.floor((s - ss) * 1000000)
		return string.format("[t=%02d:%02d:%02d.%06d][f=%07d] ", hh, mm, ss, us, frame)
	end

	local function onLine(_, frame, line)
		pending[#pending + 1] = stamp(frame) .. line .. "\n"
	end

	local function flush()
		if #pending == 0 then
			return
		end
		local fh = io.open(FILE, "a")
		if fh then
			fh:write(table.concat(pending))
			fh:close()
		end
		pending = {}
	end

	function gadget:Initialize()
		t0 = Spring.GetTimer()
		local fh = io.open(FILE, "w")
		ok = fh ~= nil
		if fh then
			fh:close()
		end
		gadgetHandler:AddSyncAction("baraiLog", onLine)
		if ok then
			Spring.Echo("apex: gadget log file " .. FILE)
		else
			Spring.Echo("[BARAI_LOGSINK] could not open " .. FILE .. "; telemetry stays on the console")
		end
	end

	function gadget:Shutdown()
		flush()
		gadgetHandler:RemoveSyncAction("baraiLog")
	end

	function gadget:GameFrame()
		flush()
	end

	function gadget:GameOver()
		flush()
	end
end
