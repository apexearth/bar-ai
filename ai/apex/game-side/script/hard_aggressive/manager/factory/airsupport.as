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

// Rez bots to keep once we own a lab.
//
// Measured, one 8v8: stock's rez spend was 32,890 against our 436, and we never
// built a single rez bot in 27 minutes. Resurrection returns the UNIT, not scrap
// -- an army that gets rebuilt off the field beats one that gets reclaimed for
// metal, which is exactly the kill-exchange gap we keep losing.
//
// By name, not by role: BuilderManager routes these through UseAs::REZZER, but
// the config ROLES disagree across factions ("support" for Armada and Legion,
// "rezzer" for Cortex), so GetRoleDef is not a reliable way to ask for one.
const int REZ_FLOOR    = 8;
// apexearth: "a rezbot costs like what, 130 metal?... so for every 500
// wrecked metal seen make 1 rezbot???" armrectr is 130m; 500 leaves real
// margin (a rez bot earns back multiples of its own cost per wreck it
// actually processes) rather than breaking even on the first pile it finds.
const float REZ_METAL_PER_BOT = 500.f;
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

// HaveT1BotLab() only clears once CCircuitDef::count increments, which happens
// at the nanoframe -- construction actually starting, not the build order
// being issued. A constructor sent to place a lab still has to walk there
// first, and every OTHER idle constructor offered AiGetFactoryToBuild during
// that walk also reads !HaveT1BotLab() and picks the same lab. Observed live,
// team 2 in matches/watch-comet-catcher-4v4-8: six separate corlab placements,
// two of them 92 frames (~3s) apart, while mCon/armyReal/metalProduced were
// all rising the whole time -- not combat replacement, just uncoordinated
// duplicate requests. This cooldown closes the gap the same way REZ_SPACING
// closes the rez-bot one: once a lab request is handed out, no second one
// within BOTLAB_REQUEST_COOLDOWN, whether or not HaveT1BotLab() has cleared
// yet. Short enough to not delay a genuine rebuild after a real loss -- a lab
// destroyed mid-game is gone for many minutes, not 45 seconds.
const int BOTLAB_REQUEST_COOLDOWN = 45 * SECOND;
int gNextBotLabRequest = 0;
string armrectr("armrectr"); string cornecro("cornecro"); string legrezbot("legrezbot");

CCircuitDef@ RezBotDef()
{
	return SideDef3(armrectr, cornecro, legrezbot);
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
