#include "../../define.as"


namespace Economy {

// To not reset army requirement on factory switch, @see Factory::AiIsSwitchAllowed
bool isSwitchAssist = false;

// The economy half of the UseAs enum arrives here, not in Builder's hook --
// CEconomyManager owns the extractor handlers.
void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	Brain::NoteSpend(unit, usage);
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
}

void AiLoad(IStream& istream)
{
}

void AiSave(OStream& ostream)
{
}

/*
 * struct SResourceInfo {
 *   const float current;
 *   const float storage;
 *   const float pull;
 *   const float income;
 * }
 */
int gNextEnergyLog = 0;

void AiUpdateEconomy()
{
	const SResourceInfo@ metal = aiEconomyMgr.metal;
	const SResourceInfo@ energy = aiEconomyMgr.energy;
	aiEconomyMgr.isMetalEmpty = metal.current < metal.storage * 0.2f;
	aiEconomyMgr.isMetalFull = metal.current > metal.storage * 0.8f;
	aiEconomyMgr.isEnergyEmpty = energy.current < energy.storage * 0.2f;
	if (aiEconomyMgr.isMetalEmpty) {
		aiEconomyMgr.isEnergyStalling = aiEconomyMgr.isEnergyEmpty
			|| ((energy.income < energy.pull) && (energy.current < energy.storage * 0.6f));
	} else {
		aiEconomyMgr.isEnergyStalling = aiEconomyMgr.isEnergyEmpty
			|| ((energy.income < energy.pull) && (energy.current < energy.storage * 0.7f));
	}
	// NOTE: Default energy-to-metal conversion TeamRulesParam "mmLevel" = 0.75
	aiEconomyMgr.isEnergyFull = energy.current > energy.storage * 0.88f;

	// The energy ledger, verbatim from the engine. eFull read 0 for a whole
	// game whose owner watched 27k e/s binned -- before believing any gate
	// built on these four numbers, read what they actually said.
	if (ai.frame >= gNextEnergyLog) {
		gNextEnergyLog = ai.frame + 30 * SECOND;
		AiLog(Factory::T() + "apex: energy cur=" + formatFloat(energy.current, "", 0, 0)
			+ "/" + formatFloat(energy.storage, "", 0, 0)
			+ " inc=" + formatFloat(energy.income, "", 0, 0)
			+ " pull=" + formatFloat(energy.pull, "", 0, 0)
			+ " eFull=" + (aiEconomyMgr.isEnergyFull ? "1" : "0")
			+ " wasting=" + (Builder::EnergyWasting() ? "1" : "0"));
	}

	isSwitchAssist = isSwitchAssist && aiFactoryMgr.isAssistRequired;
	aiFactoryMgr.isAssistRequired = isSwitchAssist
		|| ((metal.current > metal.storage * 0.2f) && !aiEconomyMgr.isEnergyStalling);
}

}  // namespace Economy
