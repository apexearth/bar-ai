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
	"apex_aa_min_noscout",
	"apex_aa_vs_air",
	"apex_adv_air_income",
	"apex_advsol_pack_cost",
	"apex_advsol_pack_r",
	"apex_advsol_stop",
	"apex_afloat_land_pct",
	"apex_afloat_near",
	"apex_afloat_seen",
	"apex_afloat_streak",
	"apex_afloat_sub_cost",
	"apex_aggr_defence",
	"apex_aggr_from",
	"apex_aggr_max",
	"apex_aid_fresh",
	"apex_aid_min_loss",
	"apex_aid_reach",
	"apex_air_mandatory_income",
	"apex_air_recycle",
	"apex_air_spread",
	"apex_air_station_near",
	"apex_airscout_map_per",
	"apex_airscout_per",
	"apex_anti_burst_secs",
	"apex_anti_pad",
	"apex_anti_reload",
	"apex_antinuke_income",
	"apex_antisub_per",
	"apex_army_pressure_mod",
	"apex_assist_army_frac",
	"apex_assist_line",
	"apex_assist_line_mult",
	"apex_assist_line_share",
	"apex_assist_spare_frac",
	"apex_attack_edge",
	"apex_base_attack_infl",
	"apex_big_per_popup",
	"apex_bomb_dist_scale",
	"apex_bomb_min_value",
	"apex_bomber_per",
	"apex_build_threat_bar",
	"apex_burst_bank_frac",
	"apex_chase_min_ratio",
	"apex_choke_back",
	"apex_choke_defence",
	"apex_comm_cloak_share",
	"apex_comm_retreat_ticks",
	"apex_comm_spacing",
	"apex_comm_stuck",
	"apex_con_budget_floor",
	"apex_con_empty_mult",
	"apex_con_full_mult",
	"apex_con_min",
	"apex_con_outmassed",
	"apex_con_tasks_each",
	"apex_conservative_hold",
	"apex_conv_new_pct",
	"apex_conv_pack",
	"apex_conv_per_spare",
	"apex_coward_rear_mod",
	"apex_decide_per_frame",
	"apex_def_asset_ref",
	"apex_def_loss_weight",
	"apex_def_reach_cap",
	"apex_def_share",
	"apex_def_t2_income",
	"apex_def_t3_income",
	"apex_defend_home",
	"apex_dive_eco_cost",
	"apex_eco_budget_floor",
	"apex_eco_defer_min_cost",
	"apex_eco_lead_holds",
	"apex_eco_overrun",
	"apex_elect_rich_income",
	"apex_energy_cover",
	"apex_energy_cover_frac",
	"apex_energy_panic_income",
	"apex_escort_per_squad",
	"apex_escort_squad_value",
	"apex_fac_ahead",
	"apex_fac_queue",
	"apex_fac_queue_brain",
	"apex_feed_static_w",
	"apex_fence_crowd",
	"apex_fence_loss_memory",
	"apex_fighter_per",
	"apex_first_fusion_mohos",
	"apex_flak_floor_income",
	"apex_flak_per",
	"apex_fodder_cost",
	"apex_front_band_frac",
	"apex_front_crew_bias",
	"apex_front_flak_income",
	"apex_front_min_reach",
	"apex_front_now",
	"apex_front_overlap",
	"apex_front_pb",
	"apex_front_reach",
	"apex_front_rear_arc",
	"apex_front_safe_edge",
	"apex_front_site_frac",
	"apex_front_t3_income",
	"apex_front_t3_per",
	"apex_fusion_income",
	"apex_fusion_prefer_income",
	"apex_geo_min_income",
	"apex_afford_secs",
	"apex_afford_e_secs",
	"apex_greed_cons",
	"apex_hold_front",
	"apex_hot_radius",
	"apex_idle_assist",
	"apex_idle_assist_range",
	"apex_idle_backoff",
	"apex_idle_backoff_maxmult",
	"apex_incoming_answer_frac",
	"apex_incoming_closing",
	"apex_incoming_cost",
	"apex_incoming_danger_cost",
	"apex_incoming_danger_pad",
	"apex_incoming_notice_r",
	"apex_incoming_stand",
	"apex_intel_air_income",
	"apex_jammer_energy_share",
	"apex_jammer_ring",
	"apex_kill_edge",
	"apex_kill_floor",
	"apex_kite_frac",
	"apex_kite_min_range",
	"apex_lane_behind_guns",
	"apex_lane_forward",
	"apex_lane_sticky",
	"apex_late_attack_quota",
	"apex_line_on_spare",
	"apex_line_spare_frac",
	"apex_local_def_share",
	"apex_mass_cap",
	"apex_mass_cap_mult",
	"apex_mass_commit_frac",
	"apex_mass_hold_ratio",
	"apex_mass_meet_frac",
	"apex_mass_no_commit_ratio",
	"apex_mass_per_army",
	"apex_maw_cloak_walls",
	"apex_max_detour",
	"apex_max_risk",
	"apex_mex_chain_home",
	"apex_mex_chain_r",
	"apex_mex_sentry",
	"apex_mex_starved_mult",
	"apex_mex_threat",
	"apex_mexup_monopoly_income",
	"apex_nano_tidy_batch",
	"apex_nano_tidy_period",
	"apex_nearmiss_merge",
	"apex_nuke_army_min",
	"apex_nuke_assume_antis",
	"apex_nuke_assume_from",
	"apex_nuke_home_weight",
	"apex_nuke_trade",
	"apex_obsolete_retry",
	"apex_oneshot_bomber_scale",
	"apex_opening_energy_gate",
	"apex_opening_failsafe",
	"apex_opening_gate",
	"apex_opening_metal_gate",
	"apex_opening_mex_reach",
	"apex_overflow_build_frac",
	"apex_perf",
	"apex_plant_ask_fuse",
	"apex_plant_ask_ttl",
	"apex_porc_obsolete_ratio",
	"apex_porc_obsolete_secs",
	"apex_pulsar_block",
	"apex_pulsar_block_fwd",
	"apex_pulsar_block_r",
	"apex_push_boost",
	"apex_push_keep",
	"apex_push_min_army",
	"apex_push_quota",
	"apex_push_team_ratio",
	"apex_quota_leggob",
	"apex_quota_leglob",
	"apex_quota_ref_cost",
	"apex_quota_t1_after_t2",
	"apex_quota_t1_after_t3",
	"apex_quota_t2_after_t3",
	"apex_raid_min_early",
	"apex_raid_tau",
	"apex_reactor_batch",
	"apex_reactor_rear",
	"apex_reactor_rear_dist",
	"apex_reactor_serial",
	"apex_reactor_spacing",
	"apex_reactor_tight",
	"apex_reclaim_gen_e",
	"apex_reclaim_solar_e",
	"apex_reinforce_frac",
	"apex_request_drain",
	"apex_rez_per_income",
	"apex_rez_floor_frac",
	"apex_rez_log_knee",
	"apex_rush_team_defend",
	"apex_scout_blind_mult",
	"apex_share_airdef",
	"apex_shield_draw_margin",
	"apex_shield_flight_per",
	"apex_shield_income_secs",
	"apex_siege",
	"apex_siege_soft",
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
	"apex_t1_commit_area",
	"apex_t1_commit_plants",
	"apex_t1_core_min",
	"apex_t1_core_per_income",
	"apex_t1_plateau_grow",
	"apex_t1_plateau_secs",
	"apex_t1_push_edge",
	"apex_t1_push_off",
	"apex_t2_army_hold",
	"apex_t2_army_per_income",
	"apex_t2_core_min",
	"apex_t2_core_per_income",
	"apex_t2_energy",
	"apex_t2_energy_reactor",
	"apex_t2_hold_boost",
	"apex_t2_rear",
	"apex_t2_rear_dist",
	"apex_take_front_offer",
	"apex_take_mex_offer",
	"apex_take_passing_mex",
	"apex_unseen_hold",
	"apex_value_norm",
	"apex_walls_obsolete_income",
	"apex_withdraw_ally_r",
	"apex_withdraw_behind",
	"apex_withdraw_infl",
	"apex_withdraw_near",
	"apex_withdraw_reissue",
	"apex_squad_spacing",
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
	"apex_always_eco_per",
	"apex_spam_per_income",
	"apex_brain_thoughts",
	"apex_con_energy_reclaim",
	"apex_front_def_mult",
	"apex_fence_depth",
	"apex_ally_aggregate",
	"apex_wall_commit",
	"apex_arty_per_wall",
	"apex_pun_wall",
	"apex_static_plain_attack",
	"apex_t2_safety",
	"apex_medic_share",
	"apex_medic_r",
	"apex_engage_margin",
	"apex_trade_margin_max",
	"apex_continue_margin",
	"apex_attack_minpower_threat",
	"apex_encircle_penalty",
	"apex_comm_flee_influence",
	"apex_static_no_continue",
	"apex_t2_metal",
	"apex_reclaim_energy_dist",
	"apex_air_threat_mod",
	"apex_scout_threat",
	"apex_wind_per_metal",
	-- Economy-first targeting and group sizing (2026-08-09). The first three of
	-- the fighter tunables above no longer have a reader; the fighter delta was
	-- reverted to upstream. These do.
	-- Formation-coherence A/B (2026-08-16): the per-row fragility pushback
	-- and standoff modifiers suspected of scattering the fight shape.
	"apex_fragile_standoff_scale",
	"apex_fragile_cap",
	"apex_static_commit",
	"apex_eco_target",
	"apex_eco_unseen",
	"apex_mass_vs_army",
	"apex_mass_hold_secs",
	"apex_mass_floor",
	"apex_unseen_parity",     -- massing.as: pre-T2 enemy-army parity floor (1.2)
	"apex_press_health",      -- AttackTask: squad HP fraction below which it stops pressing (0.6)
	"apex_persona",           -- persona.as: -1 roll freely, 0..5 force a Kind
	"apex_fac_demand",        -- buildpower.as: factories request lathes (default off)
	"apex_withdraw_odds",     -- withdraw.as: enemy-threat/our-power ratio that pulls a unit back (1.5)
	"apex_withdraw",          -- withdraw.as: master switch (1)
	"apex_defend_leash",      -- withdraw.as: forward fraction past which a DEFEND unit on enemy ground is recalled (0.55)
	"apex_recall_home",       -- withdraw.as: master switch, ATTACK/RAID squads come home while base is under attack and no killing blow is armed (1)
	"apex_recall_home_fwd",   -- withdraw.as: forward fraction past which an ATTACK/RAID squad is recalled home (0.5)
	"apex_t1_commit",         -- techlead.as: duel small-map T1-commit experiment (0)
	"apex_t1_release_cost",   -- techlead.as: enemy mobile cost that confirms T2 and releases the commit (450)
	"apex_t1_commit_income",  -- techlead.as: own income that expires the commit (80)
	"apex_assemble",          -- AttackTask.cpp: pre-contact assembly gate master switch (1)
	"apex_assemble_secs",     -- AttackTask.cpp: max seconds to wait for stragglers (8)
	"apex_siege_fear_frac",   -- SquadTask.cpp: siege row's fear radius as a share of its own range (0.9)
	"apex_raid_pack",         -- posture.as: base raid-pack promotion power pre-T2 (8)
	"apex_raid_per_income",   -- posture.as: raid pack grows by this per metal income (0.2)
	"apex_stance",            -- stance.as: master switch for stance budget/scout effects (1)
	"apex_retreat_cost_secs", -- posture.as: cost-vs-income no-retreat bar, 0 = off
	"apex_bleed_engage",      -- deathledger.as: caution gain per forward-bleed fraction (2)
	"apex_bleed_cap",         -- deathledger.as: caution ceiling (1.6)
	"apex_pulsar_conc_full",  -- statics.as: concurrent pulsars while metal-full (4)
	"apex_pulsar_full_mult",  -- brain.as: pulsar want value mult while metal-full (2)
	"apex_t1_late_share",     -- facqueue.as: post-T2 share of the T1 core count (0.34)
	"apex_brain_roulette",    -- brain.as: 1 = score-proportional draw, 0 = argmax
	"apex_air_home_wave",     -- air: non-lead aircraft mass at home, strike as a wave (1)
	"apex_bomb_defend_aa",    -- air: enemy AA metal below which home defense may bomb armies (1000)
	"apex_counter_t3_norm",   -- brain/statics: enemy heavy+super metal per doubling of pulsar/gantry wants (20000)
	"apex_bomb_fat_mobile",   -- BombTask: heavy-role mobile above this metal is always bombable (4000)
	"apex_brain_nuke",        -- 1 = script nuke director owns silo targeting, 0 = C++ auto-fire
	"apex_anti_cover",        -- nukes.as: antinuke coverage radius counted at a target (2500)
	"apex_nuke_per_anti",     -- nukes.as: extra missiles saved per covering antinuke (8)
	"apex_nuke_min_value",    -- nukes.as: cluster metal below which no warhead is spent (10000)
	"apex_nuke_spread",       -- nukes.as: step between volley aim points on the spread line (450)
	"apex_nuke_def_bias",     -- nukes.as: score multiplier for armies on our side of midfield (2)
	"apex_nuke_def_minfwd",   -- nukes.as: forward fraction below which a strike hits our own base (0.12)
	"apex_nuke_missile_cost", -- nukes.as: metal per stockpiled missile, for the payoff floor (1500)
	"apex_nuke_payoff",       -- nukes.as: missiles' worth an attacking army must exceed to qualify (3)
	"apex_nuke_value_per",    -- nukes.as: army metal per extra missile in a defensive volley (12000)
	"apex_nuke_def_window",   -- nukes.as: seconds a defensive volley tracks before retargeting (25)
	"apex_nuke_ally_max",     -- nukes.as: ally influence at the target above which we refuse to fire (0)
	"apex_trade_vol",         -- deathledger.as: seconds of income lost before the trade is judged (20)
	"apex_trade_bad",         -- deathledger.as: kill/loss ratio below which posture turns defensive (0.6)
	"apex_loss_army",         -- deathledger.as: army budget tilt per unit of net loss pressure (2)
	"apex_loss_army_cap",     -- deathledger.as: ceiling on the loss-driven army budget tilt (1.7)
	"apex_lane_defensive",    -- posture.as: home->enemy fraction the army holds at while trading badly (0.15)
	"apex_lane_back_step",    -- posture.as: elmos per step the anchor retreats off enemy-held ground (300)
	"apex_lane_muster",       -- posture.as: army power as multiple of promote quota before the anchor goes forward, vs enemy per-player threat (0.5)
	"apex_push_notice_r",     -- basedefence.as: distance from home inside which an approach is tracked (4500)
	"apex_push_cost",         -- basedefence.as: enemy group metal below which an approach is ignored (2500)
	"apex_push_closing",      -- basedefence.as: elmos closed per 5s sample that reads as pushing (150)
	"apex_push_answer_frac",  -- statics.as: defence metal wanted as fraction of incoming push metal (0.4)
	"apex_push_stand",        -- statics.as: how far out the answering towers stand (1100)
	"apex_push_danger_pad",   -- basedefence.as: margin added to a group's weapon range for the reach alarm (500)
	"apex_push_danger_cost",  -- basedefence.as: group metal below which the reach alarm ignores it (800)
	"apex_def_afford_secs",   -- statics.as: seconds of income a push-answer tower may cost (20)
	"apex_outgrown_mult",     -- obsolete.as: heir cost multiple that outgrows a small tower (3)
	"apex_outgrown_fwd",      -- obsolete.as: forward-fraction lead the heir needs to outgrow it (0.08)
	"apex_mexup_home_r",      -- mexwork.as: radius around home whose T1 mexes gate the fusion lane (1200)
	"apex_impact_ref",        -- brain.as: income at which eco-want relative-impact scaling is neutral (30)
	"apex_charger_strike",    -- hooks.as: 1 = T3 chargers take solo base-strike tasks, 0 = massing pool
	"apex_behemoth_threat",   -- main.as: threat multiplier on corjugg so everything keeps its distance (2)
	"apex_charge_threat_mod", -- AttackTask.cpp: charge-path threat weight; bends the route around Behemoths only (0.1)
	"apex_shield_value",      -- brain.as: shield want value per LRPC firing + shield lost (8)
	"apex_shield_loss_memory",-- statics.as: seconds a broken shield keeps escalating the want (240)
	"apex_shield_per",        -- statics/brain: extra guns-or-broken-shields per additional dome (3)
	"apex_retreat_threat_mod",-- RetreatTask.cpp: threat weight on a wounded unit's path home (4; attack squads use 2)
	"apex_kite_foe_pad",      -- SquadTask.cpp: margin over the closing enemy's range that triggers the backstep (120)
	"apex_t2_stuck_secs",     -- choose.as: seconds a blocked pre-T2 transition waits before re-opening the plant order (240)
	"apex_extra_plant_army",  -- choose.as: fraction of the army budget target extras must see fed (0.85)
	"apex_advsol_energy",     -- fusion.as: energy income before advanced solars start (100, was 250)
	"apex_energy_headroom",   -- maketask.as: energy income target as multiple of current pull (1.35)
	"apex_t2_energy_floor",   -- maketask.as: pre-T2 energy income the pipeline builds toward (700)
	"apex_t2_energy_from",    -- maketask.as: metal income from which the T2 energy floor applies (12)
	"apex_flank_pct",         -- AttackTask.cpp: percent of attack squads that route around a side (35)
	"apex_flank_frac",        -- AttackTask.cpp: lateral offset as fraction of the approach distance (0.45)
	"apex_flank_min_dist",    -- AttackTask.cpp: approach length below which flanking is pointless (1200)
	"apex_gantry_answer",     -- brain.as: gantry want multiplier while enemy fields T3 and we own no gantry (3)
	"apex_pulsar_answer",     -- brain.as: pulsar want multiplier while enemy fields T3 and we own no gantry (3)
	"apex_merge_threat",      -- SquadTask.cpp: merge-line threat ceiling as fraction of combined squad power (0.5)
	"apex_merge_every",       -- SquadTask.cpp: task updates between merge attempts (8, was 32)
	"apex_attack_break",      -- AttackTask.cpp: power fraction of task peak below which the attack aborts (0.4)
	"apex_mass_vs_enemy",     -- massing.as: outmatched hold bar as share of ENEMY army power (0.5)
	"apex_conv_dry_mult",     -- brain.as: convert-want discount while energy is not overflowing (0.25)
	"apex_front_from_min",    -- brain.as: game-minutes before proactive front-line spend starts (5)
	"apex_conv_drain",        -- mexguard.as: energy/s one converter eats (70)
	"apex_conv_reserve",      -- mexguard.as: spare energy flow kept above the new converter drain (50)
	"apex_assist_debounce",   -- assist.as: seconds between fallback offers per bot (5)
	"apex_nuke_resight_r",    -- nukes.as: radius marked unseen at volley commit (1600)
	"apex_nuke_repeat_decay", -- nukes.as: target value multiplier per prior volley on the same ground (0.5)
	"apex_mex_none_ttl",      -- brain.as: seconds a no-open-mex answer holds (5)
	"apex_elect_ms",         -- maketask.as: election time budget per frame in ms (6)
	"apex_fighter_per_bomber",-- facqueue.as: fighter cap per standing bomber (2, +4 base)
	"apex_ghost_purge_secs",  -- CircuitAI: seconds a VISION-CONFIRMED-absent ghost survives (90)
	"apex_ghost_stale_min",   -- CircuitAI: minutes a never-re-viewed ghost survives (15)
	"apex_seen_cap_mult",     -- massing.as: enemy estimate ceiling as multiple of peak-seen-at-once (2.5)
	"apex_pulsar_per_income", -- statics.as: metal/s per pulsar allowed (40)
	"apex_pulsar_nano_fwd",   -- statics.as: nano-cluster fwd fraction to site the gun there (0.15)
	"apex_nano_site_min",     -- nano.as: min build cost that attracts a nano beside it (1500)
	"apex_nano_pack_r",      -- nano.as: tight search radius packing turrets against the block (180)
	"apex_nano_snap_r",      -- nano.as: neighbour distance that triggers grid-snap placement (200)
	"apex_nano_grid_pitch",  -- nano.as: cardinal snap pitch, one 3x3 footprint (24)
	"apex_nano_form_grace",  -- obsolete.as: seconds before a turret group with only turrets in reach is reclaimed (120)
	"apex_nano_work_min",    -- nano.as: reachable non-turret structure value required to place a turret (400)
	"apex_conv_grid_pitch",  -- converter.as: cardinal tiling pitch for converter packs (32)
	"apex_t3_income",        -- factorydefs.as: metal income where T3 becomes worthwhile (60)
	"apex_t3_urgent",        -- factorydefs.as: metal income where T3 skips the army-ratio veto (110)
	"apex_gantry_per_energy", -- factorydefs.as: energy income per gantry allowed (3000)
	"apex_assist_per_income", -- obsolete.as: metal income per assist bot allowed (10)
	"apex_intercept_r",      -- air/update.as: radius of the home air-raid sensor (1400)
	"apex_intercept_min",    -- air/update.as: enemy air value that summons the pool (500)
	"apex_intercept_min_fighters", -- air/update.as: fighters held before we answer an ally (4)
	"apex_comm_flee_hp",
	"apex_comm_hot_secs",
	"apex_comm_hot_infl",
	"apex_air_dominance_aa",
	"apex_air_dominance_army",
	"apex_draw_defzone",
	"apex_defzone_dynamic",
	"apex_defzone_pad",     -- rules_commander.as: health below which the commander is hand-steered away (0.55)
	"apex_bigeco_income",    -- obsolete.as: metal income where cleanup mode engages (500)
	"apex_lag_speed",        -- perf.as: measured sim speed below which the host counts as lagging (0.98)
	"apex_cleanup_per",      -- obsolete.as: income per concurrent cleanup reclaim in cleanup mode (150)
	"apex_stuck_retry",      -- unblock.as: seconds before a terrain-penned unit may be re-asked for reclaim (120)
	"apex_lag_step",         -- perf.as: severity gained per still-lagging 3s window (0.34)
	"apex_cleanup_max_picks", -- obsolete.as: per-sweep bound on cleanup picks, a perf bound not policy (5)
	"apex_guard_per_income",  -- assist.as: income per extra shadow on one lead (60)
	"apex_guard_reelect",    -- maketask.as: seconds between a guard's full re-elections (10)
	"apex_idle_patrol_period", -- maketask.as: seconds between idle-builder patrol re-issues (45)
	"apex_attack_threat_mod",
	"apex_edge_band",
	"apex_edge_bonus",
	"apex_unblock",
	"apex_unblock_still",
	"apex_unblock_period",
	"apex_kill_quota",
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
	"apex_always_eco",
	"apex_comm_heavy_frac",
	"apex_comm_mass_mult",
	"apex_comm_fwd_cap",
	"apex_comm_flee_ring",
	"apex_con_mex_floor",
	"apex_reclaim_pad",
	"apex_mex_walk_cap",
	"apex_nuke_emergency",
	"apex_nuke_base_value",
	"apex_assist_nano",
	"apex_dup_bank",
	"apex_advsol_serial",
	"apex_raid_mexline",
	"apex_estor",
	"apex_roam_front",
	"apex_roam_r",
	"apex_e_per_metal",
	"apex_fusion_min_energy",
	"apex_super_self_frac",
	"apex_aca_per_income",
	"apex_advsol_home_r",
	"apex_def_panic",
	"apex_shield_income",
	"apex_local_edge",
	"apex_local_edge_on",
	"apex_local_edge_r",
	"apex_phase_expand_income",
	"apex_phase_buildup_income",
	"apex_phase_pret3_income",
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
