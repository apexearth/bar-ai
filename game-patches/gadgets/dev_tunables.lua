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
	"apex_adv_air_income",
	"apex_afloat_land_pct",
	"apex_afloat_near",
	"apex_afloat_seen",
	"apex_afloat_streak",
	"apex_afloat_sub_cost",
	"apex_aid_fresh",
	"apex_aid_min_loss",
	"apex_aid_reach",
	"apex_air_mandatory_income",
	"apex_air_recycle",
	"apex_air_spread",
	"apex_air_station_near",
	"apex_antinuke_income",
	"apex_attack_edge",
	"apex_base_attack_infl",
	"apex_bomb_dist_scale",
	"apex_bomb_min_value",
	"apex_bomb_eco_h",       -- BombTask.cpp: seconds of a generator's energy stream added to its bomb value (300)
	"apex_build_threat_bar",
	"apex_catalog_dump",
	"apex_protect_field_s",
	"apex_stall_answer_s",
	"apex_stall_answer_max_e",
	"apex_unprot_discount",
	"apex_def_alpha_w",
	"apex_spot_m",
	"apex_plant_pipe",
	"apex_plant_income_per",
	"apex_pipe_latency_h",
	"apex_tech_pipe",
	"apex_e_response",
	"apex_e_bill_share",
	"apex_stall_solar_e",
	"apex_space_m",
	"apex_bp_headroom",
	"apex_assist_share",
	"apex_e_stall_boost",
	"apex_bp_lookahead",
	"apex_fly_short",
	"apex_farm_back",
	"apex_e_lookahead",
	"apex_e_headroom",
	"apex_e_realize",
	"apex_e_waste_worth",
	"apex_con_escort",
	"apex_escort_max_cost",
	"apex_mex_cover_floor",
	"apex_mex_growth",
	"apex_range_worth",
	"apex_medic_frac",
	"apex_auction_diag",
	"apex_efloor_diag",
	"apex_comm_rules",
	"apex_allow_juno",
	"apex_allow_tacmissile",
	"apex_conv_horizon",
	"apex_tech_survival",
	"apex_bp_backlog_s",
	"apex_front_line",
	"apex_standoff_cover",
	"apex_cover_push",
	"apex_comm_fight",
	"apex_speed_worth",
	"apex_los_worth",
	"apex_screen_worth",
	"apex_threat_gradient",
	"apex_reclaim_amort",
	"apex_mobile_bp_eff",
	"apex_insure_rate",
	"apex_nuke_risk",
	"apex_targfac_want",
	"apex_obsolete_ratio",
	"apex_expose_r",
	"apex_exposed_loss_s",
	"apex_guard_rate",
	"apex_enemy_prior",
	"apex_match_ratio",
	"apex_ally_share",
	"apex_army_fill_s",
	"apex_rez_horizon",
	"apex_eco_rear_margin",
	"apex_eco_army_mul",
	"apex_eco_safe_r",
	"apex_eco_aa_mult",
	"apex_eco_danger_m",
	"apex_line_floor",
	"apex_eco_con_keep",
	"apex_eco_leash",
	"apex_join_min_m",
	"apex_gift_army",
	"apex_line_pull",
	"apex_nano_sink_bank",
	"apex_squad_m",
	"apex_intel_rate",
	"apex_water_pct",
	"apex_big_e",
	"apex_nano_sink_m",
	"apex_fus_back",
	"apex_reclaim_age_s",
	"apex_front_n",
	"apex_eco_reach_frac",
	"apex_eco_army_min_m",
	"apex_aa_match",
	"apex_retreat_cost_scale",
	"apex_retreat_floor",
	"apex_stake_weight",
	"apex_static_guard",
	"apex_wave_meet",
	"apex_chase_min_ratio",
	"apex_comm_cloak_share",
	"apex_con_outmassed",
	"apex_conservative_hold",
	"apex_coward_rear_mod",
	"apex_def_reach_cap",
	"apex_def_site_walk",
	"apex_def_eco_s",
	"apex_dup_bp_subst",
	"apex_replant_discount",
	"apex_replant_window_s",
	"apex_e_committed",
	"apex_e_parallel",
	"apex_plant_inflight",
	"apex_cover_push_s",
	"apex_mexup_boost",
	"apex_foe_tier_fade",
	"apex_own_tier_fade",
	"apex_spam_cost",
	"apex_stock_stall_abort",
	"apex_stock_stall_wait",
	"apex_def_ttd_h",
	"apex_defend_home",
	"apex_dive_eco_cost",
	"apex_colossus_prey_frac",
	"apex_colossus_chaff_pen",
	"apex_dodge",
	"apex_dodge_cd",
	"apex_counter_battery",
	"apex_counter_cd",
	"apex_counter_sprint",
	"apex_standoff",
	"apex_standoff_frac",
	"apex_attack_ceiling",
	"apex_attack_threat_mod",
	"apex_dodge_sec",
	"apex_elect_rich_income",
	"apex_escort_squad_value",
	"apex_fac_queue",
	"apex_fac_queue_brain",
	"apex_feed_static_w",
	"apex_fence_loss_memory",
	"apex_flak_floor_income",
	"apex_flak_per",
	"apex_fodder_cost",
	"apex_frame_risk",
	"apex_front_band_frac",
	"apex_front_min_reach",
	"apex_front_rear_arc",
	"apex_front_safe_edge",
	"apex_greed_cons",
	"apex_hot_radius",
	"apex_incoming_closing",
	"apex_incoming_cost",
	"apex_incoming_danger_cost",
	"apex_incoming_danger_pad",
	"apex_incoming_notice_r",
	"apex_intel_air_income",
	"apex_kill_edge",
	"apex_kill_off_frac",    -- killingblow.as: disarm fraction of KILL_EDGE; wide band survives the retreat-zeroing dip (0.35)
	"apex_focus_finish",     -- SquadTask.cpp: 1 = rows set-target the lowest-HP enemy in reach (finish the wounded)
	"apex_brawl_pass",       -- SquadTask.cpp: 1 = rows without a range edge hand the brawl to engine auto-fight
	"apex_arc_span",         -- SquadTask.cpp: ring arc width as a fraction of pi; small = the squad fights as a fist (0.9)
	"apex_line_adapt",       -- army.as: enemy static share bends the reach composition target up (1)
	"apex_mex_expose",       -- want_protect.as: per-mex floor grows with forwardness, floor*(1+fwd*this) (1.5)
	"apex_rezzer_fwd",       -- rules_rezzer.as: idle rezzer past this forward fraction retires to the haven (0.25)
	"apex_consolidate_r",    -- withdraw.as: tracked-pack distance that starts pre-contact consolidation (2000)
	"apex_consolidate_edge", -- withdraw.as: local ally metal must meet pack metal times this or fall back (1)
	"apex_kill_from",
	"apex_seen_halflife",
	"apex_budget_live",
	"apex_commit_bail",
	"apex_retreat_behind",
	"apex_con_stand_heal",
	"apex_con_stand_floor",
	"apex_retreat_healed",
	"apex_retreat_stand",
	"apex_medic_setback",
	"apex_mex_nearest",
	"apex_draw_lane",
	"apex_draw_heal",
	"apex_retreat_log",
	"apex_kill_floor",
	"apex_kite_frac",
	"apex_kite_min_range",
	"apex_lane_behind_guns",
	"apex_lane_forward",
	"apex_lane_sticky",
	"apex_mass_cap",
	"apex_mass_cap_mult",
	"apex_mass_commit_frac",
	"apex_mass_hold_ratio",
	"apex_mass_meet_frac",
	"apex_mass_no_commit_ratio",
	"apex_mass_per_army",
	"apex_max_detour",
	"apex_max_risk",
	"apex_nearmiss_merge",
	"apex_nuke_army_min",
	"apex_nuke_home_weight",
	"apex_nuke_trade",
	"apex_oneshot_bomber_scale",
	"apex_perf",
	"apex_porc_obsolete_ratio",
	"apex_porc_obsolete_secs",
	"apex_push_boost",
	"apex_push_keep",
	"apex_push_min_army",
	"apex_push_quota",
	"apex_push_team_ratio",
	"apex_raid_min_early",
	"apex_raid_tau",
	"apex_reclaim_gen_e",
	"apex_reclaim_solar_e",
	"apex_reinforce_frac",
	"apex_request_drain",
	"apex_path_infl_margin",
	"apex_scout_blind_mult",
	"apex_share_airdef",
	"apex_siege",
	"apex_site_cost_per_worker",
	"apex_spam_suicidal",
	"apex_squad_retreat",
	"apex_home_stand_ratio",
	"apex_stance_aggro_army",
	"apex_stance_aggro_def",
	"apex_stance_aggro_eco",
	"apex_stance_greed_army",
	"apex_stance_greed_eco",
	"apex_stance_pressure",
	"apex_stance_rival",
	"apex_stance_seen_hi",
	"apex_stance_seen_lo",
	"apex_stance_seen_min",
	"apex_static_defense_weight",
	"apex_t1_push_edge",
	"apex_t1_push_off",
	"apex_t2_army_hold",
	"apex_t2_energy",
	"apex_t2_energy_reactor",
	"apex_t2_hold_boost",
	"apex_unseen_hold",
	"apex_withdraw_ally_r",
	"apex_withdraw_behind",
	"apex_withdraw_infl",
	"apex_trade_window",      -- withdraw.as: seconds the local-trade death ledger remembers (15)
	"apex_losing_trade",      -- withdraw.as: pull back when our combat metal dead nearby > theirs times this (3)
	"apex_losing_floor",      -- withdraw.as: our combat metal that must die nearby before the trade trigger speaks (250)
	"apex_fight_abort",       -- withdraw.as: 1 = abort losing attack/raid tasks (measured worse; experiment arm, default 0)
	"apex_withdraw_near",
	"apex_withdraw_reissue",
	"apex_range_mod",
	"apex_los_standoff",
	"apex_prefer_target",
	"apex_siege_fight",
	"apex_fight_travel",
	"apex_defend_engage_margin",
	"apex_defend_muster",
	"apex_defend_solo_deep",
	"apex_defend_post",
	"apex_defend_home_odds",
	"apex_escort_standoff",
	"apex_con_energy_reclaim",
	"apex_ally_aggregate",
	"apex_support_radius",
	"apex_ally_converge",
	"apex_wall_commit",
	"apex_static_plain_attack",
	"apex_medic_share",
	"apex_medic_r",
	"apex_rez_flee_s",
	"apex_rez_scan_s",
	"apex_t2_metal",
	"apex_reclaim_energy_dist",
	-- Economy-first targeting and group sizing (2026-08-09). The first three of
	-- the fighter tunables above no longer have a reader; the fighter delta was
	-- reverted to upstream. These do.
	-- Formation-coherence A/B (2026-08-16): the per-row fragility pushback
	-- and standoff modifiers suspected of scattering the fight shape.
	"apex_fragile_standoff_scale",
	"apex_fragile_cap",
	"apex_static_commit",
	"apex_eco_unseen",
	"apex_mass_vs_army",
	"apex_mass_hold_secs",
	"apex_mass_floor",
	"apex_unseen_parity",     -- massing.as: pre-T2 enemy-army parity floor (1.2)
	"apex_press_health",      -- AttackTask: squad HP fraction below which it stops pressing (0.6)
	"apex_persona",           -- persona.as: -1 roll freely, 0..5 force a Kind
	"apex_withdraw_odds",     -- withdraw.as: enemy-threat/our-power ratio that pulls a unit back (1.5)
	"apex_withdraw",          -- withdraw.as: master switch (1)
	"apex_defend_leash",      -- withdraw.as: forward fraction past which a DEFEND unit on enemy ground is recalled (0.55)
	"apex_recall_home",       -- withdraw.as: master switch, ATTACK/RAID squads come home while base is under attack and no killing blow is armed (1)
	"apex_recall_home_fwd",   -- withdraw.as: forward fraction past which an ATTACK/RAID squad is recalled home (0.5)
	"apex_assemble",          -- AttackTask.cpp: pre-contact assembly gate master switch (1)
	"apex_assemble_secs",     -- AttackTask.cpp: max seconds to wait for stragglers (8)
	"apex_siege_fear_frac",   -- SquadTask.cpp: siege row's fear radius as a share of its own range (0.9)
	"apex_raid_pack",         -- posture.as: base raid-pack promotion power pre-T2 (8)
	"apex_raid_per_income",   -- posture.as: raid pack grows by this per metal income (0.2)
	"apex_stance",            -- stance.as: master switch for stance budget/scout effects (1)
	"apex_retreat_cost_secs", -- posture.as: cost-vs-income no-retreat bar, 0 = off
	"apex_bleed_engage",      -- deathledger.as: caution gain per forward-bleed fraction (2)
	"apex_bleed_cap",         -- deathledger.as: caution ceiling (1.6)
	"apex_air_home_wave",     -- air: non-lead aircraft mass at home, strike as a wave (1)
	"apex_bomb_defend_aa",    -- air: enemy AA metal below which home defense may bomb armies (1000)
	"apex_bomb_fat_mobile",   -- BombTask: heavy-role mobile above this metal is always bombable (4000)
	"apex_bomb_revisit_s",    -- BombTask: seconds a committed target stays discounted for other squads (90)
	"apex_bomb_revisit_disc", -- BombTask: score multiplier at 0s since commit, fading to 1 (0.2)
	"apex_coward_hp",         -- FighterTask: hp fraction where a squad member takes the rear ring (0.6; 0=sliver only)
	"apex_squad_fall_hp",     -- SquadTask: squad falls back together when its power-weighted TOTAL hp drops under this (0.5; 0=off)
	"apex_nano_space_reclaim", -- C++: idle nanos area-reclaim features and the static reclaim task survives a full bank (1=on, 0=stock emergency-only)
	"apex_brain_nuke",        -- 1 = script nuke director owns silo targeting, 0 = C++ auto-fire
	"apex_trade_vol",         -- deathledger.as: seconds of income lost before the trade is judged (20)
	"apex_trade_bad",         -- deathledger.as: kill/loss ratio below which posture turns defensive (0.6)
	"apex_loss_army",         -- deathledger.as: army budget tilt per unit of net loss pressure (2)
	"apex_loss_army_cap",     -- deathledger.as: ceiling on the loss-driven army budget tilt (1.7)
	"apex_lane_defensive",    -- posture.as: home->enemy fraction the army holds at while trading badly (0.15)
	"apex_lane_back_step",    -- posture.as: elmos per step the anchor retreats off enemy-held ground (300)
	"apex_push_notice_r",     -- basedefence.as: distance from home inside which an approach is tracked (4500)
	"apex_charger_strike",    -- hooks.as: 1 = T3 chargers take solo base-strike tasks, 0 = massing pool
	"apex_arty_mass",         -- hooks.as: 1 = mobile artillery masses into squads as the back row, 0 = solo ArtilleryTask
	"apex_choke_gates",       -- want_protect.as: 1 = every gate of our territory is a defence-site candidate, 0 = near-anchor choke only
	"apex_gate_depth",       -- want_protect.as: gate threat floor as a multiple of the arriving wave (2)
	"apex_teeth",            -- want_protect.as: 1 = teeth line across defended gates
	"apex_teeth_gain",       -- want_protect.as: one tooth's gain (2)
	"apex_guard_forward",     -- protect_field.as: asset guard sites stand this fraction of tower reach enemy-ward of the assets (0.5)
	"apex_con_scratch_gate",  -- BuilderTask.cpp: 1 = a scratched builder above the stand floor retreats only where danger is read, 0 = always
	"apex_t1_def_late",
	"apex_radar_overlap",    -- want_protect.as: fraction of a standing radar's radius that blocks a new mast (0.45; was hardcoded 0.8)       -- want_protect.as: a T1 tower's gain multiplier once a standing T2 builder can make defence (0.15)
	"apex_behemoth_threat",   -- main.as: threat multiplier on corjugg so everything keeps its distance (2)
	"apex_charge_threat_mod", -- AttackTask.cpp: charge-path threat weight; bends the route around Behemoths only (0.1)
	"apex_retreat_threat_mod",-- RetreatTask.cpp: threat weight on a wounded unit's path home (4; attack squads use 2)
	"apex_kite_foe_pad",      -- SquadTask.cpp: margin over the closing enemy's range that triggers the backstep (120)
	"apex_extra_plant_army",  -- choose.as: fraction of the army budget target extras must see fed (0.85)
	"apex_energy_headroom",   -- maketask.as: energy income target as multiple of current pull (1.35)
	"apex_t2_energy_from",    -- maketask.as: metal income from which the T2 energy floor applies (12)
	"apex_flank_pct",         -- AttackTask.cpp: percent of attack squads that route around a side (35)
	"apex_flank_frac",        -- AttackTask.cpp: lateral offset as fraction of the approach distance (0.45)
	"apex_flank_min_dist",    -- AttackTask.cpp: extra floor on the flank's approach length; 0 = the squad's own weapon range rules (0)
	"apex_merge_threat",      -- SquadTask.cpp: merge-line threat ceiling as fraction of combined squad power (0.5)
	"apex_merge_every",       -- SquadTask.cpp: task updates between merge attempts (8, was 32)
	"apex_attack_break",      -- AttackTask.cpp: power fraction of task peak below which the attack aborts (0.4)
	"apex_mass_vs_enemy",     -- massing.as: outmatched hold bar as share of ENEMY army power (0.5)
	"apex_assist_release",    -- rules_hold.as: surplus assisters re-enter the auction (1=on)
	"apex_peel_eco_keep",
	"apex_nano_fed_s",     -- requests.as: eco builds keep this multiple of the ETA crew before peeling (2.0)
	"apex_ghost_purge_secs",  -- CircuitAI: seconds a VISION-CONFIRMED-absent ghost survives (90)
	"apex_ghost_stale_min",   -- CircuitAI: minutes a never-re-viewed ghost survives (15)
	"apex_seen_cap_mult",     -- massing.as: enemy estimate ceiling as multiple of peak-seen-at-once (2.5)
	"apex_intercept_r",      -- air/update.as: radius of the home air-raid sensor (1400)
	"apex_intercept_min",    -- air/update.as: enemy air value that summons the pool (500)
	"apex_intercept_min_fighters", -- air/update.as: fighters held before we answer an ally (4)
	"apex_air_dominance_aa",
	"apex_air_dominance_army",
	"apex_draw_defzone",
	"apex_defzone_dynamic",
	"apex_defzone_pad",     -- rules_commander.as: health below which the commander is hand-steered away (0.55)
	"apex_lag_speed",        -- perf.as: measured sim speed below which the host counts as lagging (0.98)
	"apex_stuck_retry",      -- unblock.as: seconds before a terrain-penned unit may be re-asked for reclaim (120)
	"apex_lag_step",         -- perf.as: severity gained per still-lagging 3s window (0.34)
	"apex_unblock",
	"apex_unblock_still",
	"apex_unblock_period",
	"apex_kill_quota",
	"apex_con_log_t1_a",
	"apex_con_log_t1_b",
	"apex_con_log_t2_a",
	"apex_con_log_t2_b",
	"apex_reclaim_pad",
	"apex_dup_bank",
	"apex_advsol_serial",
	"apex_raid_mexline",
	"apex_roam_front",
	"apex_roam_r",
	"apex_e_per_metal",
	"apex_fusion_min_energy",
	"apex_super_self_frac",
	"apex_gantry_afford_s",
	"apex_super_flight_per",
	"apex_copy_overflow_m",
	"apex_blast_aisle",
	"apex_con_feed_headroom",
	"apex_unit_afford_s",
	"apex_aid_respond",
	"apex_scout_over_s",
	"apex_eco_role",
	"apex_flank_deep_pct",    -- AttackTask: share of flanking squads whose via sits at the MAP EDGE (35)
	"apex_def_setback",
	"apex_gantry_insure",
	"apex_offense_def_floor",
	"apex_gantry_host_inc",
	"apex_shield_income",
	"apex_local_edge",
	"apex_local_edge_on",
	"apex_local_edge_r",
	"apex_front_band",
	"apex_front_setback",
	"apex_draw_front",
	"apex_hold_release",
	"apex_budget",
	"apex_share_army",
	"apex_share_defence",
	"apex_share_economy",
	"apex_share_buildpower",
	"apex_unblock_test_wait",
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
	-- Both default OFF in the script so nothing draws in a hosted game; these
	-- are how a dev run turns the overlay back on.
	"apex_ping",
	-- How much a never-re-seen enemy unit still counts for. 1.0 = the old
	-- behaviour, where our picture of the enemy never expires.
	"apex_ghost_weight",
	-- The golden-metric exponents (manager/brain/market/worth.as).
	"apex_worth_dps",
	"apex_worth_alpha",
	"apex_worth_hp",
	"apex_worth_range",
	"apex_worth_aoe",
	"apex_worth_cost",
	"apex_worth_diag",
	"apex_line_abs",
	"apex_line_range_exp",
	"apex_line_median",
	"apex_aim_miss",
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

-- apex_worth_<unitname>: a per-def worth multiplier, one name per unit in the
-- game, so NAMES cannot enumerate them. It does not have to -- only pairs() over
-- the modoptions table is broken here (see the note above NAMES); direct key
-- access works, and UnitDefs gives us every key worth asking for.
for _, ud in pairs(UnitDefs) do
	local k = "apex_worth_" .. ud.name
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
