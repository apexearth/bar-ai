--------------------------------------------------------------------------------
-- dev_engine_profile.lua -- the engine's own section timers, logged per window.
--
-- His 10-19: the game runs normally and then lags all at once, for every player. Our AI's
-- timers and worker pool stay flat through those minutes, and 16 BARb with none of ours spike
-- the same way, so the cost is inside the engine. CTimeProfiler times every SCOPED_TIMER in a
-- normal build (Sim::Path*, Sim::Unit::MoveType::*, Sim::Los, Sim::Features, Lua, ...) once the
-- debug view enables it. This turns that on and logs, every WINDOW game frames, the wall time the
-- window took and the sections that took most of it:
--   ENGPROF f=4500 wallMs=812 Sim=640.2 Sim::Path=410.7 Sim::Unit::MoveType::1::UpdateTraversalPlan=...
-- Self-disables unless the start script sets modoption apex_engine_profile=1. Unsynced: reads only.
--------------------------------------------------------------------------------

function gadget:GetInfo()
	return {
		name    = "Dev Engine Profile",
		desc    = "Logs the engine profiler's top sections per window (apex_engine_profile=1).",
		author  = "bar-ai",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 1004,
		enabled = true,
	}
end

if gadgetHandler:IsSyncedCode() then
	return
end

local WINDOW = 150
local TOP = 14

local last = {}
local timer = nil
local started = false

function gadget:Initialize()
	local mo = Spring.GetModOptions() or {}
	if tostring(mo.apex_engine_profile or "0") ~= "1" then
		gadgetHandler:RemoveGadget(self)
		return
	end
end

function gadget:GameFrame(n)
	if not started then
		started = true
		Spring.SendCommands("debug")
		timer = Spring.GetTimer()
		return
	end
	if (n % WINDOW) ~= 0 then
		return
	end
	local now = Spring.GetTimer()
	local wallMs = Spring.DiffTimers(now, timer, true)
	timer = now
	local names = Spring.GetProfilerRecordNames() or {}
	local rows = {}
	for i = 1, #names do
		local name = names[i]
		local total = Spring.GetProfilerTimeRecord(name, false) or 0
		local d = total - (last[name] or total)
		last[name] = total
		if (d > 0.5) and not name:find("^Misc::Profiler") then
			rows[#rows + 1] = { name, d }
		end
	end
	table.sort(rows, function(a, b) return a[2] > b[2] end)
	local parts = { string.format("ENGPROF f=%d wallMs=%.0f", n, wallMs) }
	local ais = { string.format("ENGPROF-AI f=%d", n) }
	local shown = 0
	for i = 1, #rows do
		local name = rows[i][1]
		if name:find("^AI::{") then
			-- every AI each window: the top-N cut hid most of them from the per-AI totals
			ais[#ais + 1] = string.format("%s=%.1f", name:gsub(" ", "_"), rows[i][2])
		elseif shown < TOP then
			parts[#parts + 1] = string.format("%s=%.1f", name, rows[i][2])
			shown = shown + 1
		end
	end
	Spring.Echo(table.concat(parts, " "))
	if #ais > 1 then
		Spring.Echo(table.concat(ais, " "))
	end
end
