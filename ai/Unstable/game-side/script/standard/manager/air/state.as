namespace Air {


//------------------------------------------------------------------------------
// Surprise air eco-assassination: one player per ally team quietly builds a T2
// air force, holds it at home while it grows, then throws all of it at the
// enemy economy and never brings it back. The value is in hitting before the
// enemy's anti-air exists -- see AIR_AA_CEILING.
//------------------------------------------------------------------------------

// Mid-game only: before this the whole team is pooling metal behind the tech
// lead, and an air plant competes with it. Kept short of the T1->T2 transition
// itself, since that transition IS the pooling window this AI's team strategy
// is built on.
const int   AIR_FROM       = 11 * MINUTE;

// The candidate's OWN metal income, out of reach of the 4v4 benchmark and
// comfortable at hosted-game income. Kept low deliberately: waiting for a
// bigger income is waiting for the enemy to build the anti-air that cancels
// the strategy's whole premise of surprise.
const float AIR_MIN_INCOME = 40.f;

// Enemy anti-air already on the field, in metal, above which we do not start.
// GetEnemyCost sums what we have SEEN, so it is a floor on their AA rather than a
// measurement of it -- which biases this gate towards committing.
const float AIR_AA_CEILING = 2500.f;

// 12 basic bombers is ~1,800 metal, a real strike on economy, with 8 fighters
// as escort rather than a matching wing.
const int   AIR_BOMBERS    = 12;
const int   AIR_FIGHTERS   = 8;

// Scale the strike size with our own economy: AIR_BOMBERS/AIR_FIGHTERS above
// are the floor; a stronger economy affords, and profits more from, a bigger
// strike.
const float AIR_SCALE_INCOME = 30.f;   // extra metal/s per extra bomber above the floor
const int   AIR_BOMBERS_MAX  = 30;

int ScaledBombers()
{
	const int extra = int(aiEconomyMgr.metal.income * Persona::AirEagerness()
			/ AIR_SCALE_INCOME);
	const int want = AIR_BOMBERS + extra;
	const int capped = (want > AIR_BOMBERS_MAX) ? AIR_BOMBERS_MAX : want;
	// A ONE-SHOT basic bomber (Legion's Martyr): each sortie expends the whole
	// wing, so a reusable-bomber count buys one alpha strike and a pile of
	// corpses. Until the reusable advanced bomber exists, want a fraction.
	// apexearth 2026-08-15: "we made too many martyrs... those guys are 1 shot"
	if ((gBomber1 !is null) && (gBomber1.GetName() == "legkam")
		&& (Have(gBomber) == 0))
	{
		const float s = ai.GetTunable("apex_oneshot_bomber_scale", TUNE_ONESHOT_BOMBER_SCALE);
		const int scaled = int(float(capped) * s + 0.99f);
		return (scaled < 1) ? 1 : scaled;
	}
	return capped;
}

int ScaledFighters()
{
	// Same escort ratio as the floor (8 fighters per 12 bombers), scaled
	// with the bomber count rather than income directly.
	return int(float(ScaledBombers()) * float(AIR_FIGHTERS) / float(AIR_BOMBERS));
}

// Enqueue does not dedup and CCircuitDef::count only moves when a unit is
// registered, so back-to-back orders overshoot the target. Same reason
// Factory::RUSH_CON_SPACING exists.
const int   AIR_ORDER_SPACING = 2 * SECOND;

// How many aircraft to queue per order, so the plant never stands idle between
// them. CmdBuild takes one def per call and Spring's CMD_REPEAT is not bound to
// the script; CFactoryManager::DefaultMakeTask picks up queued-but-unassigned
// recruits as the plant frees up, so queue depth substitutes for a repeat flag.
// Overshoot is bounded by the same check that gates a single order: only issued
// while short of ScaledBombers()/ScaledFighters().
const int   AIR_BATCH = 6;

// Massing forever is its own failure. Past this, strike with whatever is built
// provided it is at least half a force.
const int   AIR_DEADLINE   = 4 * MINUTE;

// How far behind on the ground cancels the whole strategy. Above parity by a
// clear margin, so an even fight does not veto it; see the check in Update().
const float GROUND_LOST_RATIO = 1.5f;

// One writer per slot, as with the tech-lead election in factory.as: every
// instance publishes its own income, and only the elector publishes the answer.
const string TV_AIRINC  = "airinc";
const string TV_AIRLEAD = "airlead";
// The team interceptor pool (apexearth 2026-08-18): every player publishes
// enemy AIR value over its own home plus its home coords; players holding
// fighters fly them to the worst-hit ally and re-issue while the raid lasts.
const string TV_AIRRAID = "airraid";
const string TV_HOMEX   = "homex";
const string TV_HOMEZ   = "homez";
int gNextRaidPub = 0;
int gNextInterceptCmd = 0;
int gInterceptTarget = -1;
array<Id>@ gMatesCache = null;

int  gAirLead      = -1;
int  gLeadCheckedAt = -1000;
int  gCommitFrame  = -1;
bool gStrike       = false;
bool gAbort        = false;
int  gNextAirOrder = 0;
int  gNextProbe    = 0;
int  gNextLog      = 0;
int  gNextElectLog = 0;
bool gAnnounced    = false;

bool gDefsResolved = false;
CCircuitDef@ gPlant1  = null;   // T1 air plant
CCircuitDef@ gPlant2  = null;   // T2 air plant
CCircuitDef@ gCon1    = null;   // T1 air constructor
CCircuitDef@ gCon2    = null;   // T2 air constructor
CCircuitDef@ gBomber  = null;   // advanced bomber
CCircuitDef@ gFighter = null;   // advanced fighter
// BASIC tier, built off the T1 plant rather than waiting on the advanced one --
// cheaper, and surprise is cheapest early.
CCircuitDef@ gBomber1  = null;
CCircuitDef@ gFighter1 = null;

}  // namespace Air
