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
// WHERE EACH OF US IS BEING HURT.
//
// CCircuitAI::GetAttackHotspot is the heaviest cost-weighted decaying spot where
// WE have lost units, and it is per-AI (NoteLossAt only accumulates our own
// losses), so a player cannot see an ally being overrun. Published as three
// floats and read back the same way the front budget and AA count already are;
// nothing coordinates the response beyond that -- each player picks the
// heaviest reachable fight and goes.
const string TV_AIDX = "aidx";
const string TV_AIDZ = "aidz";
const string TV_AIDW = "aidw";
// teamValues is never erased and GetTeamIds() is a static roster, so a player
// that dies keeps its last published weight -- its largest ever -- forever.
// A frame stamp is what tells a live publisher from a dead one.
const string TV_AIDF = "aidf";

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

// What this player has put into the front line, in metal: every standing tower
// out there plus the ones already ordered. An order has claimed the constructor
// time it will cost whether or not it ever finishes, which is the whole reason
// the count-based budget could not bind (see Builder::OutstandingFrontTasks).
float OwnFrontMetal()
{
	float m = 0.f;
	for (uint i = 0; i < gFencePos.length(); ++i) {
		if (!OnBorder(gFencePos[i]) && !NearFront(gFencePos[i]))
			continue;
		if (i >= gFenceDef.length())
			continue;
		const CCircuitDef@ d = gFenceDef[i];
		if (d !is null)
			m += d.costM;
	}
	return m;
}

void PublishDefence()
{
	uint front = 0;
	for (uint i = 0; i < gFencePos.length(); ++i) {
		if (OnBorder(gFencePos[i]) || NearFront(gFencePos[i]))
			++front;
	}
	ai.PublishTeamValue(TV_FFENCE, float(front));
	ai.PublishTeamValue(TV_MINC, aiEconomyMgr.metal.income);
	ai.PublishTeamValue(TV_MINC_NET, Market::StructuralIncomeEma());
	ai.PublishTeamValue(TV_ASSETM, Market::EconAssetsM());
	Market::NavalPublish();
	ai.PublishTeamValue(TV_FMETAL, OwnFrontMetal());
	ai.PublishTeamValue(TV_MSPEND, Brain::gSpentTotal);
	ai.PublishTeamValue(TV_AA, float(OwnStaticAA()));
	ai.PublishTeamValue(TV_AIDF, float(ai.frame));

	AIFloat3 hot;
	float hotW = 0.f;
	if (ai.GetAttackHotspot(hot, hotW) && OnMap(hot)) {
		ai.PublishTeamValue(TV_AIDX, hot.x);
		ai.PublishTeamValue(TV_AIDZ, hot.z);
		ai.PublishTeamValue(TV_AIDW, hotW);
	} else {
		ai.PublishTeamValue(TV_AIDW, 0.f);
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
// Our home to theirs, so the aid reach is a measurement of this map rather than
// a distance typed in here.
float BaseSeparation()
{
	if (!Builder::gHomeSet)
		return 0.f;
	const AIFloat3 foe = aiEnemyMgr.GetEnemyPos();
	if (!OnMap(foe))
		return 0.f;
	return Builder::gHomePos.distance2D(foe);
}

// The worst fight an ALLY is losing that we could actually reach. Weight is
// metal lost there, so "worst" means most expensive, bounded by reach.
bool AllyAidPos(const AIFloat3& in from, AIFloat3& out at, float& out weight, int& out who)
{
	who = -1;
	weight = 0.f;
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() == 0))
		return false;
	// GetTunable caches on first call, so a computed default would freeze at
	// whatever the separation was the first time this ran -- 0, before the home
	// position is set. Sentinel instead: unset follows the measurement live.
	const float sep = BaseSeparation();
	const float tuned = ai.GetTunable("apex_aid_reach", TUNE_AID_REACH);
	const float reach = (tuned > 0.f) ? tuned : ((sep > 0.f) ? sep : 6000.f);
	const float least = ai.GetTunable("apex_aid_min_loss", TUNE_AID_MIN_LOSS);
	const float fresh = ai.GetTunable("apex_aid_fresh", TUNE_AID_FRESH) * float(SECOND);
	bool have = false;
	float best = 0.f;
	for (uint i = 0; i < mates.length(); ++i) {
		const int id = int(mates[i]);
		if (id == ai.teamId)
			continue;   // our own fight is not aid; see GetGuardAnchor
		const float when = ai.ReadTeamValue(id, TV_AIDF, -1.f);
		if ((when < 0.f) || (float(ai.frame) - when > fresh))
			continue;   // dead or never published: its weight is frozen, not current
		const float w = ai.ReadTeamValue(id, TV_AIDW, 0.f);
		if (w < least)
			continue;
		AIFloat3 p = AIFloat3(ai.ReadTeamValue(id, TV_AIDX, 0.f), 0.f,
				ai.ReadTeamValue(id, TV_AIDZ, 0.f));
		if (!OnMap(p) || (from.distance2D(p) > reach))
			continue;
		if (!have || (w > best)) {
			best = w;
			at = p;
			who = id;
			have = true;
		}
	}
	weight = best;
	return have;
}

// As far toward an ally in trouble as ground is still contested: bisect the
// segment from our end to theirs and stop at the influence zero crossing, so
// we reach survivors and sit on the attacker's flank instead of walking into
// ground already lost.
bool AidClampToContested(const AIFloat3& in from, const AIFloat3& in to, AIFloat3& out at)
{
	if (!OnMap(from) || !OnMap(to))
		return false;
	if (ai.GetNetInflAt(to) >= 0.f) {
		at = to;
		return true;
	}
	if (ai.GetNetInflAt(from) < 0.f)
		return false;   // we do not hold our own end either
	AIFloat3 good = from;
	AIFloat3 bad = to;
	for (int i = 0; i < 8; ++i) {   // 8 halvings resolve a base separation to ~1%
		AIFloat3 mid = (good + bad) * 0.5f;
		if (!OnMap(mid))
			break;
		if (ai.GetNetInflAt(mid) >= 0.f)
			good = mid;
		else
			bad = mid;
	}
	at = good;
	return true;
}

// READ-ONLY. Issues no order and enqueues nothing: it reports what an aid
// response WOULD do, because the response itself cannot be built at this layer
// (see CHANGES.md -- one anchor serves every DEFEND task).
int gNextAidLog = 0;

void LogAidState()
{
	if (ai.frame < gNextAidLog)
		return;
	AIFloat3 aid;
	float aidW = 0.f;
	int who = -1;
	if (!Builder::gHomeSet || !AllyAidPos(Builder::gHomePos, aid, aidW, who))
		return;
	gNextAidLog = ai.frame + 20 * SECOND;

	AIFloat3 own;
	float ownW = 0.f;
	if (!ai.GetAttackHotspot(own, ownW))
		ownW = 0.f;
	// Same measured quantity on both sides: one player's decaying loss weight.
	const float frac = aidW / (aidW + ownW);

	AIFloat3 go;
	string dest = " go=none";
	if (AidClampToContested(Builder::gHomePos, aid, go)) {
		dest = " go=" + int(go.x) + "," + int(go.z)
			+ " clamped=" + int(go.distance2D(aid));
	}
	AiLog(Factory::T() + "apexaid: team " + who
		+ " hurt=" + formatFloat(aidW, "", 0, 0)
		+ " ours=" + formatFloat(ownW, "", 0, 0)
		+ " frac=" + formatFloat(frac, "", 0, 2)
		+ " army=" + formatFloat(aiMilitaryMgr.armyCost, "", 0, 0)
		+ " dist=" + int(Builder::gHomePos.distance2D(aid))
		+ dest);
}

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
// bombing run climb airRaw 150 -> 4924 metal over ~10 minutes while the smoothed
// gate never crossed AA_IGNORE until 2 minutes before the match ended (measured
// 2026-08-14, matches/20260814-222654-...). Presence should react to what is
// happening now; only the COUNT built should stay smoothed against a blip.
float gAirRaw    = -1.f;

}  // namespace Military
