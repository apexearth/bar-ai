// INSURANCE POLICY. Every knob wraps ai.GetTunable, so a dev game can override it live
// (dev_tunables.lua); rules read it through Policy:: rather than re-stating a default.

namespace Policy {

// Antinukes and shield domes are INSURANCE: real once the threat class
// exists, premature at eco-opening scale (apexearth 2026-08-21: "We are
// making two anti nukes too early, we are also making a shield too early...
// we need to scale harder on the economy early on"). A SEEN enemy silo
// always overrides the antinuke bar -- being poor does not make the warhead
// cheaper.
float AntinukeIncome() { return ai.GetTunable("apex_antinuke_income", TUNE_ANTINUKE_INCOME); }

}  // namespace Policy
