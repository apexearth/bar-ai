--------------------------------------------------------------------------------
-- dev_tunables.lua -- let a match command line override AI combat constants.
--
-- The combat constants in CircuitAI are #defines, so testing a value meant a
-- Docker rebuild. The arena resolves a 2v2 matchup in about a minute, so the
-- build, not the measurement, was setting the pace of the experiment.
--
-- Any modoption whose name starts with apex_ is republished as a game rules
-- param of the same name. CCircuitAI::GetTunable reads it once and falls back to
-- the compiled default when the param is absent, which is every game that does
-- not set the modoption -- so this changes nothing off the bench, and nothing
-- ships to multiplayer.
--
--   python tools/run_match.py ... --modoption apex_orbit_rate=0
--
-- Currently read by the DLL:
--   apex_orbit_rate     rate the standoff ring precesses      (default 0.18)
--   apex_squad_spacing  lateral spacing of a travelling line  (default 96)
--   apex_range_mod      standoff as a fraction of weapon range (default 0.95)
--------------------------------------------------------------------------------

local modOptions = Spring.GetModOptions() or {}

local pending = {}
for k, v in pairs(modOptions) do
	if type(k) == "string" and k:sub(1, 5) == "apex_" then
		local n = tonumber(v)
		if n then
			pending[k] = n
		else
			Spring.Echo("[BARAI_TUNABLE] ignoring non-numeric " .. k .. "=" .. tostring(v))
		end
	end
end

local enabled = next(pending) ~= nil

function gadget:GetInfo()
	return {
		name    = "Dev Tunables",
		desc    = "Republishes apex_* modoptions as game rules params for the AI.",
		author  = "bar-ai",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		-- Ahead of the AI's first frame; rules params must exist before the DLL
		-- caches them.
		layer   = -1000,
		enabled = enabled,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

function gadget:Initialize()
	for k, v in pairs(pending) do
		Spring.SetGameRulesParam(k, v)
		Spring.Echo(string.format("[BARAI_TUNABLE] %s=%s", k, tostring(v)))
	end
end
