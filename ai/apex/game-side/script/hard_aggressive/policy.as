// ECONOMY POLICY, IN ONE PLACE.
//
// apexearth 2026-08-21, on the solar-reclaim oscillation: "All of this sort
// of logic should exist within a central config of some sort." targets.as is
// that place for build RATIOS; this file is it for eco THRESHOLDS -- the
// numbers that decide when energy is short, when a generator is obsolete,
// when a constructor is worth buying. Every knob wraps ai.GetTunable, so a
// dev game can override any of them live (dev_tunables.lua) while the
// defaults -- the shipped policy -- sit here and nowhere else.
//
// Rules must read these through Policy:: rather than re-stating a default at
// the call site: two call sites with two defaults is how the same policy
// silently forks.

namespace Policy {

// -- Energy supply ----------------------------------------------------------

// Build energy while income < pull * this. The padding that keeps the grid
// ahead of demand rather than chasing it.
float EnergyHeadroom() { return ai.GetTunable("apex_energy_headroom", TUNE_ENERGY_HEADROOM); }

// Energy per metal: the grid target follows METAL income (energy.pull is
// throttled demand and self-reports "fine" while starving -- see the energy
// lane). BAR runs ~15-25 energy per metal across the eras apexearth has
// quoted (T2 at 800e on ~35m, reclaim bars at 500-2000); 20 is the middle.
float EPerMetal() { return ai.GetTunable("apex_e_per_metal", TUNE_E_PER_METAL); }

float T2EnergyFrom()   { return ai.GetTunable("apex_t2_energy_from", TUNE_T2_ENERGY_FROM); }

// Energy income required before starting T2 (techlead.as RushReady), and the
// lower bar once a reactor already stands.
float T2Energy()        { return ai.GetTunable("apex_t2_energy", TUNE_T2_ENERGY); }
float T2Metal()         { return ai.GetTunable("apex_t2_metal", TUNE_T2_METAL); }
float T2EnergyReactor() { return ai.GetTunable("apex_t2_energy_reactor", TUNE_T2_ENERGY_REACTOR); }

// A fusion costs ~21,000 ENERGY to construct: starting one on a small grid
// drains it -- the lathe plus a producing T2 lab stalls everything, fusion
// included (apexearth 2026-08-21, watching one at ~500 e/s: "It is
// STUPID"; then, setting the number: "no fusion if we have <1000 energy.
// adv solar or wind instead"). Below the bar the advsol/wind ladder keeps
// climbing, which is what raises the grid; at the bar the fusion starts
// and gets blitzed.
float FusionMinEnergy() { return ai.GetTunable("apex_fusion_min_energy", TUNE_FUSION_MIN_ENERGY); }

// -- Reclaiming our own generators ------------------------------------------

// Income cliffs below which a generator tier is never eaten (apexearth
// 2026-08-15: solars ~500, wind/advsol ~2000, wind scaled by map quality).
float ReclaimSolarE()  { return ai.GetTunable("apex_reclaim_solar_e", TUNE_RECLAIM_SOLAR_E); }
float ReclaimGenE()    { return ai.GetTunable("apex_reclaim_gen_e", TUNE_RECLAIM_GEN_E); }

// PADDING: a victim is only eligible while the grid AFTER eating it still
// clears pull by this factor. The cliff alone reads income NOW -- it let one
// advanced solar make every panel eligible at 520 income against 480 pull,
// the reclaim dipped the grid, and the base panic-rebuilt the same solars
// (apexearth, watching Prismatic 2026-08-21: "our energy dips and suddenly
// we're making more basic solars -- need padding here"). Higher than
// EnergyHeadroom on purpose: a sweep enqueues several victims against the
// same income reading, and the margin has to absorb the batch.
float ReclaimPad() { return ai.GetTunable("apex_reclaim_pad", TUNE_RECLAIM_PAD); }

// -- Constructors -----------------------------------------------------------

// The income->constructor curves (share.as ConsWantedTier).
float ConLogT1A() { return ai.GetTunable("apex_con_log_t1_a", TUNE_CON_LOG_T1_A); }
float ConLogT1B() { return ai.GetTunable("apex_con_log_t1_b", TUNE_CON_LOG_T1_B); }
float ConLogT2A() { return ai.GetTunable("apex_con_log_t2_a", TUNE_CON_LOG_T2_A); }
float ConLogT2B() { return ai.GetTunable("apex_con_log_t2_b", TUNE_CON_LOG_T2_B); }

// A PASSIVE read of the enemy licenses a bigger builder fleet.
float GreedCons() { return ai.GetTunable("apex_greed_cons", TUNE_GREED_CONS); }

// -- Insurance structures ---------------------------------------------------

// Antinukes and shield domes are INSURANCE: real once the threat class
// exists, premature at eco-opening scale (apexearth 2026-08-21: "We are
// making two anti nukes too early, we are also making a shield too early...
// we need to scale harder on the economy early on"). A SEEN enemy silo
// always overrides the antinuke bar -- being poor does not make the warhead
// cheaper.
float AntinukeIncome() { return ai.GetTunable("apex_antinuke_income", TUNE_ANTINUKE_INCOME); }
float ShieldIncome()   { return ai.GetTunable("apex_shield_income", TUNE_SHIELD_INCOME); }

}  // namespace Policy
