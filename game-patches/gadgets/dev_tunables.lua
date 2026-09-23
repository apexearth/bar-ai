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
-- in tools/dashboard_audit.py. Twelve are read by the DLL and three by AngelScript;
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
	"apex_ord_retry_s",     -- BuilderTask.cpp: seconds a builder's command queue must be empty under a live task before the task re-issues (3; 0 off)
	"apex_catalog_dump",
	"apex_decide_log",
	"apex_elec_frame_us",
	"apex_eta_log",
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
	"apex_stock_army",
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
	"apex_energy_growth_arrive",   -- want_energy.as: charge the energy growth premium only on income that lands inside the plan's horizon (0 off)
	"apex_e_waste_worth",
	"apex_m_realize",
	"apex_m_waste_worth",
	"apex_dgun_ff",
	"apex_con_escort",
	"apex_escort_max_cost",
	"apex_mex_cover_floor",
	"apex_mex_growth",
	"apex_range_worth",
	"apex_medic_frac",
	"apex_auction_diag",
	"apex_efloor_diag",
	"apex_task_trace",
	"apex_eco_only",
	"apex_comm_rules",
	"apex_allow_juno",
	"apex_allow_tacmissile",
	"apex_conv_horizon",
	"apex_tech_survival",
	"apex_lava",
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
	"apex_lathe_obsolete",
	"apex_nano_shift_idle",
	"apex_expose_r",
	"apex_exposed_loss_s",
	"apex_enemy_prior",
	"apex_match_ratio",
	"apex_ally_share",
	"apex_army_fill_s",
	"apex_rez_horizon",
	"apex_eco_rear_margin",
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
	"apex_t1_tower_late",
	"apex_plant_copy",
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
	"apex_def_off",
	"apex_army_eco_s",
	"apex_eco_target_base",
	"apex_eco_target_base8",
	"apex_air_eco_base",
	"apex_line_terrain",
	"apex_line_quality",
	"apex_plant_unlock",
	"apex_cover_leaves",
	"apex_cover_by_raid",
	"apex_screen_gap",
	"apex_team_line",
	"apex_def_dominance",
	"apex_def_afford_s",
	"apex_conv_afford_s",
	"apex_attack_share",
	"apex_raid_first",
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
	"apex_hz_approach",
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
	"apex_site_bt_per_worker",
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
	"apex_t2_army_floor", -- army.as: army target while the T2 switch is on; 0 = the hard zero, 1 = hold the defensive need
	"apex_bp_travel", -- production.as: discount a hand's build power by its speed against the quickest builder we own (0 = off)
	"apex_bp_vs_lathe", -- production.as: price a constructor's build-power capture against the best lathe per metal (0 = off, 1 = full)
	"apex_eta_commit_bonus", -- want_energy.as: share of the extra fleet-time a bigger reactor commits, credited to the ladder's smaller pick in the tie-break (0 = off)
	"apex_retreat_scale", -- posture.as: scale every def's retreat hp threshold (1 = config value; lower fights longer before pulling out)
	"apex_budget_after", -- decide.as: apply the budget correction to the draw ticket instead of the value the draw sharpens (0 = off)
	"apex_budget_max", -- budget.as: ceiling on the budget corrector (2 = stock; higher lets a starved row actually catch up)
	"apex_army_rich_balance", -- production.as: offer the spare-metal army floor only as far as army is under its budget target (0 = off, 1 = full)
	"apex_army_budget_damp", -- production.as: damp the spare-metal army floor by the ARMY row budget multiplier (0 = off)
	"apex_keep_job_peel", -- decide.as: keep-job tests OUR removals (peel) not crew membership (0 = the dead crew test)
	"apex_keep_walk_paid", -- decide.as: fraction of the walk already paid that keeps a job at a hot site (0 = off)
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
	"apex_intercept",
	"apex_guard_posts",      -- DefendTask.cpp: idle pool members stand at script-assigned posts (1)
	"apex_dgun_log",         -- DGunAction.cpp: sampled trace of the D-gun gates (0)
	"apex_defend_home_odds",
	"apex_defend_towers",
	"apex_home_muster",
	"apex_dgun_close_mult",
	"apex_dgun_close_worth",
	"apex_escort_standoff",
	"apex_con_energy_reclaim",
	"apex_ally_aggregate",
	"apex_support_radius",
	"apex_ally_converge",
	"apex_defend_aid",     -- DefendTask.cpp: a guard pool elects the fight an ally is already in (1)
	-- Army splitting: read in the fight C++ but never published, so S8 applied --
	-- they ran their defaults with no error and could not be switched off.
	-- The constructor floor (2.7 + income/44). Read in production.as but never
	-- published, so it could not be swept: apexearth 2026-09-08 "i suspect we
	-- arent making enough cons and fail to expand properly".
	"apex_con_base",
	"apex_t1_air_con_min",
	"apex_con_per_m",
	"apex_t2_con_base",
	"apex_t2_con_per_m",
	"apex_army_split",
	"apex_split_cd",
	"apex_split_hold",
	"apex_split_margin",
	"apex_split_min_dist",
	"apex_wall_commit",
	"apex_static_plain_attack",
	"apex_medic_share",
	"apex_medic_r",
	"apex_rez_flee_s",
	"apex_rez_scan_s",
	"apex_rez_react_s",
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
	"apex_defend_leash",
	"apex_hold_committed",
	"apex_wrap_edge",
	"apex_wrap_min_w",
	"apex_wrap_over",
	"apex_brawl_stand",
	"apex_wrap_arc",      -- withdraw.as: forward fraction past which a DEFEND unit on enemy ground is recalled (0.55)
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
	"apex_def_ring",          -- want_protect.as: 1 = every open closure-ring bearing (flanks, rear) is a defence-site candidate, 0 = asset/gate/front only
	"apex_wave_conc",         -- want_protect.as: 1 = a site prices vs the enemy's whole fielded army capped by the stake behind it, 0 = per-site share only
	"apex_wall",              -- protect_wall.as: 1 = ground defence sites are wall slots on the base rim (replaces asset/front/ring candidates), 0 = old candidate set
	"apex_wall_standoff",     -- protect_wall.as: wall stands this fraction of light-tower range outside the outermost building per bearing (0.5)
	"apex_wall_pitch",        -- protect_wall.as: arc spacing between wall slots, fraction of light-tower range (1.2; <=2 keeps adjacent fields overlapping)
	"apex_wall_cluster",      -- protect_wall.as: guns per wall cluster; the saved space becomes a gap before the next cluster (3; 1 = the old even spread)
	"apex_wall_cluster_tight",-- protect_wall.as: how tightly a cluster packs, fraction of the pitch (0.5)
	"apex_wall_reach",        -- protect_wall.as: per-bearing wall radius cap, multiple of the worth-weighted RMS radius of what we own (2.5)
	"apex_wall_rear",         -- want_protect.as: share of the wall pull a directly-rear slot keeps; enemy-facing slots get full pull, tapering by bearing (0.2)
	"apex_wall_line_w",       -- want_protect.as: the front line's pull relative to the ring -- completing the line outbids deepening it (2.0)
	"apex_rez_util",          -- production.as: share of a rez bot's work rate actually delivered; the fleet saturates when have x buildPower x this covers the wreck stream (0.25)
	"apex_leak_screen_m",     -- want_protect.as: fielded army value at which the mobile screen takes over leak defence; below it every mex carries the full cover floor (800)
	"apex_air_aa_split",      -- air/state.as: 1 = strike sizes vs enemy AA divided by their base count (one raid, one base), 0 = whole-map AA census
	"apex_gate_depth",       -- want_protect.as: gate threat floor as a multiple of the arriving wave (2)
	"apex_teeth",            -- want_protect.as: 1 = teeth line across defended gates
	"apex_guard_forward",     -- protect_field.as: asset guard sites stand this fraction of tower reach enemy-ward of the assets (0.5)
	"apex_con_scratch_gate",  -- BuilderTask.cpp: 1 = a scratched builder above the stand floor retreats only where danger is read, 0 = always
	"apex_t1_def_late",
	"apex_def_dps_linear",   -- protect_field.as: 1 = tower cover priced on linear surface DPS, 0 = the engine's sqrt(dps) threat (1)
	"apex_line_alloc",       -- production.as: 1 = draw within the line class the team owes most metal (1)
	"apex_wall_efficient",   -- want_protect.as: 1 = wall slots rank towers by cover per metal, not absolute power (1)
	"apex_raider_massing",   -- hooks.as: 1 = raiders become line army at T2, 0 = they raid all game like stock (0)
	"apex_spam_raiders",     -- hooks.as: 1 = cheap raiders spot as solo scouts after T2, 0 = they keep raiding (0)
	"apex_def_outrange",     -- protect_field.as: kill power lifted by the share of attackers a tower outranges (1)
	"apex_def_kill_cap",     -- protect_field.as: 1 = a defence site's stake is capped by what the tower can kill in the exposure window
	"apex_radar_overlap",    -- want_protect.as: fraction of a standing radar's radius that blocks a new mast (0.45; was hardcoded 0.8)       -- want_protect.as: a T1 tower's gain multiplier once a standing T2 builder can make defence (0.15)
	"apex_behemoth_threat",   -- main.as: threat multiplier on corjugg so everything keeps its distance (2)
	"apex_charge_threat_mod", -- AttackTask.cpp: charge-path threat weight; bends the route around Behemoths only (0.1)
	"apex_retreat_threat_mod",-- RetreatTask.cpp: threat weight on a wounded unit's path home (4; attack squads use 2)
	"apex_kite_foe_pad",      -- SquadTask.cpp: margin over the closing enemy's range that triggers the backstep (120)
	"apex_extra_plant_army",  -- choose.as: fraction of the army budget target extras must see fed (0.85)
	"apex_eta",               -- eta.as: 0 shadow-log the ETA ladder, 1 let it re-rank the economic categories
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
	"apex_air_cover", -- air/cover.as: held fighters guard every scout, radar plane and bomber sent out (1)
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
	"apex_eco_force",
	"apex_role_share",
	"apex_t2_fusion_pull", -- market/decide.as: while the T2 switch is on and no advanced generator stands, take the fusion instead of drawing it (0 = off)
	"apex_role_tau",
	"apex_flank_deep_pct",    -- AttackTask: share of flanking squads whose via sits at the MAP EDGE (35)
	"apex_def_setback",
	"apex_gantry_insure",
	"apex_offense_def_floor",
	"apex_gantry_host_inc",
	"apex_shield_cover_frac",
	"apex_shield_urgency",
	"apex_local_edge",
	"apex_local_edge_on",
	"apex_local_edge_r",
	"apex_front_band",
	"apex_front_setback",
	"apex_draw_front",
	"apex_hold_release",
	"apex_budget",
	"apex_budget_lever", -- market/decide.as: whether the budget multiplier actually scales wants (0 = logged only)
	"apex_floor_yield", -- market/decide.as: a floor stands down while its category is over target (0 = off)
	"apex_deathwalk_price", -- want_mex.as: price a hot-road spot through TripRisk instead of refusing it (0 = off)
	"apex_com_stay_forward", -- market/floor.as: a forward commander takes work around him rather than walking home (1 = since 3bb47630)
	"apex_nosite_diag", -- protect_want.as: log WHY a defence site scored zero gain (0 = off)
	"apex_fill_firstpass", -- protect_fill.as: a never-filled defence def gets one extra site-fill slot per frame (0 = off)
	"apex_com_mex_price", -- want_mex.as: what a mex spot outside the commander's leash is worth to him, 0..1 (0 = the veto)
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
	"apex_record_bite", -- market/worth.as: a type's measured damage/health record discounts its price (1)
	"apex_evidence_shrink", -- market/worth.as: how hard a def outside its class's spread with no record is priced back to that class (0 = off)
	"apex_record_prior", -- CircuitAI.cpp: units of "justified" the record starts from (10)
	"apex_record_window", -- CircuitAI.cpp: the moving average spans this many deaths (40)
	"apex_line_abs",
	"apex_line_range_exp",
	"apex_line_median",
	"apex_aim_miss",
	-- CircuitUnit.cpp: 1 = drop a move order that is bit-identical to the one
	-- this unit is already executing. Counted either way in `apex: orders`, so
	-- a run with it off says what turning it on would buy (0).
	"apex_order_dedupe",
	"apex_order_trace",
	-- RaidTask: how much a raid party flatters its CURRENT target's distance.
	-- 1.0 = no commitment (what the nulled-out form was effectively doing).
	"apex_raid_sticky",
	-- RaidTask: multiplies how far a raid party may look for a target. 1.0 is
	-- the leader's own weapon-or-sight radius +200, i.e. only what is already
	-- in its face -- which is why 97% of target picks chose nothing.
	"apex_raid_reach",
	-- The order arbiter: a centre ranked below the one whose decision the unit
	-- is still carrying out may not overwrite it. 0 restores last-writer-wins.
	"apex_order_arbiter",
	"apex_intent_hold",
	-- SquadTask.cpp: 1 = the arc-end DISTANCE tiebreak stops reversing a row's
	-- slot assignment once it has picked a side; a real threat asymmetry still
	-- re-decides. Counted either way in `apex: order-src` (arcflip=churn/held).
	"apex_arc_sticky",
	-- SquadTask.cpp: seconds between standoff-ring re-issues (1 = shipped).
	-- Every re-issue is a forced engine re-path; this prices that against
	-- ms/frame. See docs/27-tunable-rationale.md.
	"apex_standoff_s",
	-- SquadTask::HoldGoal: 1 = a squad keeps the destination it is still
	-- closing on unless something is actually THERE. 0 restores the old
	-- re-elect-from-scratch behaviour, for the A/B only.
	"apex_goal_hold",
	-- CircuitUnit::IsForceUpdate: 1 = a wake armed by taking damage no longer
	-- re-opens the squad's destination question (the reaction to the hit is
	-- handled inline in OnUnitDamaged either way). 0 restores the old
	-- everything-wakes-everything signal.
	"apex_wake_split",
	-- protect_want.as: 1 = the team-best-tower discount ranks a light tower
	-- against the strongest tower we could BUY now, not the strongest that
	-- exists in any builder's list. 0 restores the old behaviour, which held
	-- the winning defence candidate at xTeamPow=0.352 all game while defHave
	-- sat at 85 against a defTarget of 3,356.
	"apex_def_teampow_afford",
	-- coverage.as: weight on MOBILE cover (posted guards) when reading how
	-- covered a place is. 1 = a guard counts like a turret (his ruling);
	-- 0 removes it, to measure whether an arriving escort is what cancels the
	-- tower the builder was already walking to.
	"apex_unit_cover",
	-- stuck.as: seconds of no movement AND no progress before the watchdog
	-- aborts a builder's task. 0 disables it. Never published until now, so
	-- every earlier "sweep" of it silently ran the 30s default (S8).
	"apex_stuck_secs",
	-- BuilderTask.cpp: 1 = a builder only skips pathing when it can already
	-- reach the site. 0 restores the in-base shortcut, which excused pathing
	-- for any build inside a 1,120-elmo radius and left builders standing up
	-- to 1,952 elmos from a job with a 112 build range.
	"apex_inbase_path",
	-- production.as: 1 = the 0.05 portfolio floor on a role's weight is NOT
	-- applied to a role whose target is zero. AA is a pure counter and is
	-- refused a baseline share by RoleTarget; the floor put it back, and the
	-- draw bought 1,500 metal of AA against an empty sky. 0 restores the floor.
	"apex_role_floor_zero",
}

local pending = {}
for _, k in ipairs(NAMES) do
	local raw = modOptions[k]
	if raw ~= nil and raw ~= "" then
		local n = tonumber(raw)
		if n then
			pending[k] = n
		else
			BARAI_Echo("[BARAI_TUNABLE] ignoring non-numeric " .. k .. "=" .. tostring(raw))
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
			BARAI_Echo("[BARAI_TUNABLE] ignoring non-numeric " .. k .. "=" .. tostring(raw))
		end
	end
end

local enabled = next(pending) ~= nil

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
		BARAI_Echo(string.format("[BARAI_TUNABLE] %s=%s", k, tostring(v)))
	end
end
