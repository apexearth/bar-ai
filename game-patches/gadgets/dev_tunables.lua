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
-- Every name in NAMES below, with its default and where it is read, is listed
-- in docs/15-tunables.md. Twelve are read by the DLL and three by AngelScript;
-- a name missing from NAMES is silently ignored, so add both together.
--------------------------------------------------------------------------------

local modOptions = Spring.GetModOptions() or {}

-- Named explicitly rather than discovered by iterating the modoptions table:
-- pairs() over it yields nothing here even though direct key access works, so a
-- prefix scan silently found no options and the gadget disabled itself.
local NAMES = {
	"apex_orbit_rate",
	"apex_squad_spacing",
	"apex_range_mod",
	"apex_los_standoff",
	"apex_prefer_target",
	"apex_siege_fight",
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
	"apex_solo_stock",
	-- Economy-first targeting and group sizing (2026-08-09). The first three of
	-- the fighter tunables above no longer have a reader; the fighter delta was
	-- reverted to upstream. These do.
	"apex_eco_target",
	"apex_eco_unseen",
	"apex_mass_vs_army",
	"apex_mass_hold_secs",
	"apex_mass_floor",
	"apex_attack_threat_mod",
	"apex_edge_band",
	"apex_edge_bonus",
	"apex_unblock",
	"apex_unblock_still",
	"apex_unblock_period",
	"apex_kill_quota",
	"apex_front_nano",
	"apex_comm_rules",
	"apex_mix",
	"apex_mix_con_income",
	"apex_plants_t1_a",
	"apex_plants_t1_b",
	"apex_plants_t2_a",
	"apex_plants_t2_b",
	"apex_plants_t3_per",
	"apex_con_log_t1_a",
	"apex_con_log_t1_b",
	"apex_con_log_t2_a",
	"apex_con_log_t2_b",
	"apex_mix_counter",
	"apex_mix_scout",
	"apex_mix_scout_per_mex",
	"apex_chaff_mult",
	"apex_advsol_energy",
	"apex_energy_any",
	"apex_fence_per_income",
	"apex_fence_rear_share",
	"apex_front_fraction",
	"apex_front_band",
	"apex_front_setback",
	"apex_draw_front",
	"apex_lead_defence",
	"apex_army_deficit_floor",
	"apex_hold_release",
	"apex_budget",
	"apex_share_army",
	"apex_share_defence",
	"apex_share_economy",
	"apex_share_buildpower",
	"apex_unblock_test_wait",
	"apex_nano_income_gate",
	-- The Brain's mex upgrades (2026-08-10): how many the engine holds open.
	"apex_mexup_per_income",
	"apex_mexup_full_bonus",
	"apex_mexup_first",
	-- T3 heavies hold the defence line (2026-08-09). 0 restores stock routing:
	-- one solo CAttackTask per super, the frame it finishes.
	"apex_super_guard",
	"apex_super_cost",
	-- Reclaim our own cheap buildings to free units walled in by them
	-- (2026-08-09). 0 leaves a penned unit penned.
	"apex_unblock",
	-- Dev aid: one map marker per attack group when it first picks a target.
	"apex_ping_attacks",
	-- Both default OFF in the script so nothing draws in a hosted game; these
	-- are how a dev run turns the overlay back on.
	"apex_ping",
	-- How much a never-re-seen enemy unit still counts for. 1.0 = the old
	-- behaviour, where our picture of the enemy never expires.
	"apex_ghost_weight",
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
