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

-- Named explicitly rather than discovered by iterating the modoptions table:
-- pairs() over it yields nothing here even though direct key access works, so a
-- prefix scan silently found no options and the gadget disabled itself.
local NAMES = {
	"apex_orbit_rate",
	"apex_squad_spacing",
	"apex_range_mod",
	"apex_engage_margin",
	"apex_trade_margin_max",
	"apex_continue_margin",
	"apex_attack_minpower_threat",
	"apex_encircle_penalty",
	"apex_comm_flee_influence",
	"apex_static_no_continue",
	"apex_rush_min_metal",
	"apex_reclaim_energy_dist",
	"apex_air_threat_mod",
	"apex_scout_threat",
	"apex_wind_per_metal",
}

local pending = {}
for _, k in ipairs(NAMES) do
	local raw = modOptions[k]
	if raw ~= nil and raw ~= "" then
		local n = tonumber(raw)
		if n then
			pending[k] = n
		else
			Spring.Echo("[BARAI_TUNABLE] ignoring non-numeric " .. k .. "=" .. tostring(raw))
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
