namespace Military {

int gNextFenceCapLog = 0;
int gNextCrowdLog = 0;

// Near the front line, in metres rather than as a fraction -- for callers that
// think in map distance.
//
// This used to read the gadget-published position (ai_frontx_<team>, from
// dev_team_income.lua) and so answered FALSE in every hosted game while being
// permissive on the bench: measured, it passed towers sitting at -0.17 along the
// home->enemy axis as "near the front". Both halves of that were wrong, and in
// opposite directions. It is the influence crossing now, same as OnBorder, so
// the bench and a real game agree.
const float FRONT_RADIUS = 1600.f;

bool NearFront(const AIFloat3& in pos)
{
	AIFloat3 f;
	if (!FrontLinePos(f))
		return false;
	const float dx = pos.x - f.x;
	const float dz = pos.z - f.z;
	return (dx * dx + dz * dz) < (FRONT_RADIUS * FRONT_RADIUS);
}

// THE FRONT LINE IS A TEAM OBJECT, SO ITS BUDGET IS A TEAM BUDGET.
//
// Factory::ElectorTeamId always picks the same (lowest id) player for the lead
// roles, so a per-player defence budget landed entirely on whichever slots the
// election never picks. The line in front of our bases is one object shared by
// the team, so its budget is published per player and summed here, the same
// mechanism the killing blow already uses for army value.
const string TV_FFENCE = "ffence";
const string TV_MINC   = "minc";
// Reclaim-netted structural income (Market::StructuralIncomeEma) -- the lane
// team-purse anchors read (the gantry budget), so a teammate's wreck feast
// does not license a lab. TV_MINC stays raw for the front budget and the
// census share: reclaimed metal really does buy units.
const string TV_MINC_NET = "mincnet";
// 1 while this player is the rear specialist still growing: the allies'
// answer shares and the air-lead election leave it out (it fields nothing).
const string TV_ECOSEAT = "ecoseat";
const string TV_SHELTERED = "sheltered";   // a teammate's base stands between ours and theirs

// Some teammate stands behind another's base: the team has a rear to fly from.
bool TeamHasSheltered()
{
	array<Id>@ mates = ai.GetTeamIds();
	for (uint i = 0; (mates !is null) && (i < mates.length()); ++i) {
		if (ai.ReadTeamValue(int(mates[i]), TV_SHELTERED, 0.f) > 0.5f)
			return true;
	}
	return false;
}
// The player's standing ECONOMIC assets (Market::EconAssetsM) -- what a
// teammate's forward guard post is protecting when a back player buys
// defence at the front ally's door instead of its own (the ally-front
// candidate in want_protect.as reads this as the site's stake).
const string TV_ASSETM = "assetm";
// A budget denominated in towers cannot bound a share of metal: it let the same
// allowance buy a Sentry and a Pulsar. These two carry the front line's METAL
// and the player's TOTAL metal spend, so the bound is a share, as targets.as
// states it elsewhere.
const string TV_FMETAL = "fmetal";
const string TV_MSPEND = "mspend";
// ANTI-AIR IS ONE TEAM ANSWER TO ONE TEAM'S AIRCRAFT.
//
// GetEnemyCost(AIR) is the WHOLE ENEMY TEAM'S air value, while CCircuitDef::count
// is only our OWN turrets, so each player independently sized its answer against
// all enemy aircraft while counting none of its allies' turrets -- the AA piled
// onto whichever slot the election gives spare constructor time.
const string TV_AA = "aa";

// Own names rather than Builder's: main.as includes military before builder, and
// a global is only visible after the line that declares it (functions are not).
string aaCheapArm("armrl");
string aaCheapCor("corrl");
string aaCheapLeg("legrl");
string aaHeavyArm("armferret");
string aaHeavyCor("cormadsam");
string aaHeavyLeg("legflak");

// Every static AA turret we hold, cheap and heavy: what the team is asked to
// count against the enemy's air.
uint OwnStaticAA()
{
	uint n = 0;
	CCircuitDef@ cheap = SideDef3(aaCheapArm, aaCheapCor, aaCheapLeg);
	if (cheap !is null)
		n += cheap.count;
	CCircuitDef@ heavy = SideDef3(aaHeavyArm, aaHeavyCor, aaHeavyLeg);
	if (heavy !is null)
		n += heavy.count;
	return n;
}

// The front-line count and the front-line metal are the same classification of
// the same array, and OnBorder/NearFront only move when the front does -- so
// classify each tower once per front rebuild, not twice a second.
int gFenceFrontStamp = -30000;
int gFenceFrontLen = -1;
uint gFenceFrontN = 0;
float gFenceFrontM = 0.f;

void FenceFrontRefresh()
{
	RebuildFront();
	if ((gFenceFrontStamp == gFrontStamp) && (gFenceFrontLen == int(gFencePos.length())))
		return;
	gFenceFrontStamp = gFrontStamp;
	gFenceFrontLen = int(gFencePos.length());
	uint n = 0;
	float m = 0.f;
	for (uint i = 0; i < gFencePos.length(); ++i) {
		if (!OnBorder(gFencePos[i]) && !NearFront(gFencePos[i]))
			continue;
		++n;
		if (i >= gFenceDef.length())
			continue;
		const CCircuitDef@ d = gFenceDef[i];
		if (d !is null)
			m += d.costM;
	}
	gFenceFrontN = n;
	gFenceFrontM = m;
}

// What this player has put into the front line, in metal: every standing tower
// out there plus the ones already ordered. An order has claimed the constructor
// time it will cost whether or not it ever finishes, which is the whole reason
// the count-based budget could not bind (see Builder::OutstandingFrontTasks).
float OwnFrontMetal()
{
	FenceFrontRefresh();
	return gFenceFrontM;
}

// post.pubdef is 2.5% of all script time in an hour-long sixteen-AI game and it
// runs once a second with a ~250us floor from minute three -- a floor that does
// not grow with the base, so it is one of these calls and not the walk. Split
// so the next run says which; the sections cost a timestamp each.
void PublishDefence()
{
	{ double _t = Perf::T0(); FenceFrontRefresh(); Perf::Add("pubdef.fence", _t); }
	{
		double _t = Perf::T0();
		ai.PublishTeamValue(TV_FFENCE, float(gFenceFrontN));
		ai.PublishTeamValue(TV_MINC, Eco::MInc());
		ai.PublishTeamValue(TV_MINC_NET, Market::StructuralIncomeEma());
		ai.PublishTeamValue(TV_ECOSEAT, Market::EcoRoleGrowing() ? 1.f : 0.f);
		{
			AIFloat3 mh;
			ai.PublishTeamValue(TV_SHELTERED, (Market::ShelterMate(mh) >= 0) ? 1.f : 0.f);
		}
		ai.PublishTeamValue(TV_ASSETM, Market::EconAssetsM());
		Perf::Add("pubdef.write", _t);
	}
	{ double _t = Perf::T0(); Market::NavalPublish(); Perf::Add("pubdef.naval", _t); }
	{
		double _t = Perf::T0();
		ai.PublishTeamValue(TV_FMETAL, OwnFrontMetal());
		ai.PublishTeamValue(TV_MSPEND, Brain::gSpentTotal);
		ai.PublishTeamValue(TV_AA, float(OwnStaticAA()));
		Perf::Add("pubdef.write2", _t);
	}
}


float TeamSum(const string& in key, float own)
{
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() == 0))
		return own;
	float total = 0.f;
	for (uint i = 0; i < mates.length(); ++i)
		total += ai.ReadTeamValue(int(mates[i]), key, 0.f);
	return (total > own) ? total : own;
}

// Static AA the whole side holds, against an enemy air value that is also the
// whole side's. Both halves of the comparison have to describe the same team or
// the answer is multiplied by however many of us there are.
float TeamAA()
{
	return TeamSum(TV_AA, float(OwnStaticAA()));
}

// KILL PHASE (docs/20-brain-overhaul.md): the engine consults this hook for
// every threatened cluster; a MISSING function would fall through to the
// DLL's native DefaultMakeDefence -- a spender -- so the stub must exist and
// spend nothing. Sensors are structures too, so DefaultMakeSensors is not
// called either. Territory bookkeeping stays: NoteSite is a sense.
void AiMakeDefence(int cluster, const AIFloat3& in pos)
{
	NoteSite(cluster, pos);
}

//------------------------------------------------------------------------------
// Anti-air, sized to the enemy's actual ground-vs-air mix.
//
// Static and mobile AA are counted separately and need separate levers: only
// mobile units reach CMilitaryManager::AddResponse, so the response table's
// figures are mobile-only. Static AA is bounded through CCircuitDef::maxThisUnit,
// which IsAvailable() gates on in every path that can place one -- build chain
// hubs, DefaultMakeDefence, base defence, factory. Neither lever exists in
// build_chain.json, whose conditions are sampled once when the parent finishes
// and never re-checked.
//
// GetEnemyCost(AIR) is not "enemy aircraft". Air constructors and scouts carry
// ["builder", "air"] / ["scout", "air"] in behaviour.json, and CFactoryManager
// gives the AIR enemy role to every def that IsAbleToFly. Two enemy air
// constructors read as 680 metal of "air".
//------------------------------------------------------------------------------
// Enemy air value below which we build no AA at all beyond the cheap tiers.
// One Armada air constructor is 340 metal, one Cortex 360.
const float AA_IGNORE    = 500.f;
// Air share at which we answer their air at full stock strength. Below it, scale
// down; scale is never above 1, so this only ever builds less AA than stock.
const float AA_SHARE_REF = 0.25f;
const float AA_SCALE_MIN = 0.10f;
// Ceiling on AA as a share of our own army. response.json's own max_percent.
const float AA_MAX_PCT   = 0.50f;
// Enemy air metal, scaled, that buys one heavy AA turret (armflak/armcir
// 820/750, corflak/corerad 850/800, legflak 820).
const float AA_HEAVY_PER = 1500.f;
// No ceiling: heavy AA is already proportional to the enemy's observed air
// value through AA_HEAVY_PER.

// Air is over-counted and ground under-counted by simple visibility: aircraft
// fly over us constantly, ground sits in fog. Weight ground up, and average both
// so a single overflight does not swing the answer.
const float GROUND_UNSEEN  = 3.0f;
const float AIR_AVG_SECONDS = 240.f;
// Enemy air builders and scouts are counted as AIR. They cannot be separated
// from ground ones by role, so discount by the most that could plausibly be air.
const float SOFT_AIR_WEIGHT = 0.10f;
// Cap the discount: enemy builders+scouts include ground ones, so an uncapped
// subtraction erases a real bomber fleet. ~7 air constructors' worth.
const float SOFT_AIR_CAP = 2500.f;
float gAirAvg    = -1.f;
float gGroundAvg = -1.f;
// Unsmoothed reading from the same tick gAirAvg is fed from. gAirAvg's 240s
// time constant means a raid that starts and finishes well inside that window
// reads near-zero on the average for most of its length -- this is what let a
// bombing run climb airRaw 150 -> 4924 metal over ~10 minutes while the
// smoothed gate never crossed AA_IGNORE until 2 minutes before the match
// ended. Presence should react to what is happening now; only the COUNT built
// should stay smoothed against a blip.
float gAirRaw    = -1.f;

}  // namespace Military
