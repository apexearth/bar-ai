namespace Factory {

string armawac("armawac");  string corawac("corawac");  string legwhisper("legwhisper");

CCircuitDef@ RadarPlaneDef()
{
	return SideDef3(armawac, corawac, legwhisper);
}

// A bot lab is worth having early for one reason above all others: it is the
// ONLY source of a resurrection bot. armrectr/cornecro/legrezbot are 130 metal
// and no other factory in the game can make them.
const int BOTLAB_FROM = 8 * MINUTE;

// Rez bots to keep once we own a lab. Resurrection returns the UNIT, not
// scrap, which is worth more than reclaim metal. Named directly rather than by
// role: BuilderManager routes these via UseAs::REZZER, but the config ROLES
// disagree across factions ("support" for Armada/Legion, "rezzer" for Cortex),
// so GetRoleDef isn't reliable here.
const float REZ_METAL_PER_BOT = 500.f;
// Per 100 metal/s of income -- the unit every other standing count in this
// file is derived in.
const float REZ_PER_INCOME = 0.1f;
const int REZ_SPACING  = 20 * SECOND;
// One assist bot per this long while the bank is full. Short, because the
// condition is self-limiting -- when the build power catches up with income the
// bank stops being full and this stops firing.
const int ASSIST_BOT_SPACING = 15 * SECOND;
int gNextAssistBot = 0;
int gNextRez = 0;
int gNextRezDiag = 0;  // temporary diagnostic, see the rez-bot armed check below
int gNextFactoryDiag = 0;  // temporary diagnostic, see the AiMakeTask entry log below
int gNextT2GateBlockLog = 0;  // temporary diagnostic, see AiIsSwitchAllowed's FollowerEconomyReady check

// HaveT1BotLab() only clears once count increments at the nanoframe, not when
// the build order is issued -- so while a constructor walks to place one,
// every other idle constructor also reads !HaveT1BotLab() and requests a
// duplicate. This cooldown closes that gap independent of HaveT1BotLab(),
// short enough to not delay a genuine rebuild after a real loss.
const int BOTLAB_REQUEST_COOLDOWN = 45 * SECOND;
int gNextBotLabRequest = 0;
string armrectr("armrectr"); string cornecro("cornecro"); string legrezbot("legrezbot");

CCircuitDef@ RezBotDef()
{
	return SideDef3(armrectr, cornecro, legrezbot);
}

// The two terms combine with max(), never min(): the reclaim term is what the
// field is offering right now, the income term is what the economy can always
// afford to keep standing, and the larger one is the answer. Below ~10 m/s the
// income term is zero, which keeps "not important at t zero" true.
int RezBotsWanted()
{
	const int byIncome = int(SteadyIncome()
			* ai.GetTunable("apex_rez_per_income", TUNE_REZ_PER_INCOME));
	const int byReclaim = int(Builder::WreckSeenValue() / REZ_METAL_PER_BOT);
	return (byIncome > byReclaim) ? byIncome : byReclaim;
}

// False once the pooling strategy has been given up on (Military::RUSH_GIVEUP).
// The rush branch below returns null rather than producing army, so a lead that
// never reaches T2 would otherwise sit out the entire game building nothing.
bool RushWindowOpen()
{
	return ai.frame <= Military::RUSH_GIVEUP;
}

// Re-read at most once a second. Un-cached, this ran a string concatenation and
// an engine callback on EVERY IsTechLead() -- 15 call sites, several on hot
// paths -- including from inside Builder::AiUnitAdded, which ai.GiveUnits
// invokes re-entrantly while it is transferring a unit. A second is far shorter
// than any takeover deadline, so the role still moves promptly.
int gLeadCheckedAt = -1000;

}  // namespace Factory
