namespace Military {

int gNextFenceCapLog = 0;
int gNextCrowdLog = 0;

string armanni("armanni");
string cordoom("cordoom");
string legbastion("legbastion");

CCircuitDef@ BigGun()
{
	return SideDef3(armanni, cordoom, legbastion);
}

// The big gun used to hang off the T3 gantry's build chain, so it was placed
// beside whichever base owned the gantry -- a back-line player walling its own
// empty base while the front player got nothing. Same unit, same trigger, but
// put it where the fighting is.
const float BIGGUN_INCOME = 18.f;
bool gBigGunPlaced = false;

void UpdateFrontGun()
{
	if (gBigGunPlaced || !Factory::gHaveT3)
		return;
	if (aiEconomyMgr.metal.income <= BIGGUN_INCOME)
		return;
	CCircuitDef@ gun = BigGun();
	if (gun is null)
		return;
	AIFloat3 front;
	if (!BorderPos(front, 0) && !FrontLinePos(front))
		return;
	gBigGunPlaced = true;
	AiLog(Factory::T() + "apex: big gun " + gun.GetName() + " at the territory edge");
	// BUNKER takes only a def and a position -- no target, no spot id.
	Requests::Take(null, gun, Task::BuildType::BUNKER,
			Task::Priority::NORMAL, front, 0.f, 0.f);
}

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
	return m + Builder::OutstandingFrontCost();
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
	const float tuned = ai.GetTunable("apex_aid_reach", -1.f);
	const float reach = (tuned > 0.f) ? tuned : ((sep > 0.f) ? sep : 6000.f);
	const float least = ai.GetTunable("apex_aid_min_loss", 300.f);
	const float fresh = ai.GetTunable("apex_aid_fresh", 60.f) * float(SECOND);
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

// THE ONE ANSWER TO "MAY A TOWER GO HERE".
//
// Placement used to happen in three other places that never consulted the
// defence policy -- MexGuard on every extractor, Fortify wherever a constructor
// was shot, build_chain.json on every factory -- so the income budget and the
// front/rear shares only ever applied to a minority of what was actually built.
// Every placement now asks this first, in order: is defence already over its
// budget share, is this the rear and has the rear had its share, is the ground
// already covered (unless what we are placing is better than what covers it).
//
// The crowd check's radius is the placed turret's own weapon range
// (Brain::TowerReach / CCircuitDef::GetMaxRange, clamped), so a Beamer line and
// a Pulsar line are each judged at their own spacing. The tier exemption keeps
// the crowd check from being a ceiling: a better turret may always go in at any
// density, so density only stops the SAME turret repeating, never the defence
// climbing with the economy.
//
// `def` null means the caller does not know what will be placed. Unknown can
// never be "higher tier", so it is a refusal on crowded ground -- which is why
// AiMakeDefence, the path that places most of our towers, asks with LadderDef()
// rather than with null.
bool CrowdAllows(const AIFloat3& in pos, CCircuitDef@ def)
{
	// apexearth's number, not a derived one.
	const float most = ai.GetTunable("apex_fence_crowd", 6.f);
	if (most <= 0.f)
		return true;
	// A def with no surface gun -- anti-air, a jammer -- is bounded by its own
	// rule instead (Brain::AACoverNear).
	if ((def !is null) && (def.GetSurfThreat() <= 0.f))
		return true;
	float span = (def is null) ? Brain::LightTowerRange() : Brain::TowerReach(def);
	if (span < 200.f)
		span = 200.f;

	float standTop = 0.f;
	float orderTop = 0.f;
	const uint standing = FenceGunsNear(pos, span, standTop);
	const uint ordered = Builder::DefenceOrdersNear(pos, span, orderTop);
	if (float(standing + ordered) < most)
		return true;

	const float top = (standTop > orderTop) ? standTop : orderTop;
	const bool better = (def !is null) && (def.costM > top);
	if (!better && (ai.frame >= gNextCrowdLog)) {
		gNextCrowdLog = ai.frame + 30 * SECOND;
		string wanted = "?";
		if (def !is null)
			wanted = def.GetName();
		AiLog(Factory::T() + "apex: crowded " + (standing + ordered)
			+ " within " + int(span)
			+ " (" + ordered + " on order), best=" + formatFloat(top, "", 0, 0)
			+ ", want=" + wanted
			+ ((OnBorder(pos) || NearFront(pos)) ? " front" : " rear"));
	}
	return better;
}

// WHAT THE ENGINE'S OWN LADDER WOULD PUT HERE.
//
// AiMakeDefence has no def to offer the crowd cap -- DefaultMakeDefence chooses
// inside C++, after we have already answered -- so without this the tier
// exemption could never fire on the path that places most of our towers.
//
// Mirrors build_chain.json's porcupine "land" ladder [0, 3, 5, 4, 8, 12] and
// walks it the way CMilitaryManager::DefaultMakeDefence does -- cumulative cost
// against an income-derived maxCost -- returning the dearest rung that still
// fits. LADDER_AMOUNT and ecoFactor are approximated from the config, both in
// the direction of under-claiming (refusing rather than wrongly exempting).
const float LADDER_AMOUNT = 32.f;

CCircuitDef@ LadderDef()
{
	array<CCircuitDef@> rungs = {
		SideDef3("armllt",    "corllt",  "leglht"),
		SideDef3("armbeamer", "corhllt", "legmg"),
		SideDef3("armclaw",   "cormaw",  "legdtr"),
		SideDef3("armhlt",    "corhlt",  "leghive"),
		SideDef3("armpb",     "corvipe", "legapopupdef"),
		SideDef3("armanni",   "cordoom", "legbastion")
	};
	const float inc = (aiEconomyMgr.metal.income < aiEconomyMgr.energy.income)
			? aiEconomyMgr.metal.income : aiEconomyMgr.energy.income;
	const float maxCost = LADDER_AMOUNT * inc;
	CCircuitDef@ best = null;
	float total = 0.f;
	for (uint i = 0; i < rungs.length(); ++i) {
		CCircuitDef@ d = rungs[i];
		if ((d is null) || !d.IsAvailable(ai.frame))
			continue;
		total += d.costM;
		if (total >= maxCost)
			break;
		@best = d;
	}
	return best;
}

bool DefenceAllowedAt(const AIFloat3& in pos, CCircuitDef@ def = null)
{
	if (!CrowdAllows(pos, def))
		return false;

	// Being attacked raises the budget; it does not remove it -- returning true
	// outright while contested switched the gate off almost the whole game
	// (contested reads true for most of it), so pressure now only multiplies the
	// allowance, and the rear share still has to hold.
	//
	// pressureAllow used to also apply BudgetMult(DEFENCE) (target/have), which
	// is circular against a share test: the further below target we are, the
	// more we are allowed to build, cancelling the bound. Dropped; BudgetMult
	// still ranks defence against other categories in Brain.
	float pressureAllow = (gTurtle || BaseContested()) ? 2.f : 1.f;
	// A lead buys less defence, never none -- its metal is wanted for the plant
	// and T2 mexes, but a role changes how much, never whether.
	if (Factory::IsDesignatedLead() && !gPorcArmed && !gTurtle && !LosingGround())
		pressureAllow *= ai.GetTunable("apex_lead_defence", 0.35f);
	const float per = ai.GetTunable("apex_fence_per_income", 0.8f) * pressureAllow;
	const float budget = 1.f + aiEconomyMgr.metal.income * per;

	// Two jobs, two allowances: holding the line and guarding an extractor used
	// to share one budget, so numerous nearby mex guards spent it and the front
	// request was refused for being over it -- the front line's size depended on
	// how many mexes we owned. Each job now counts only its own standing towers
	// against its own share, from targets.as DEF_FRONT / DEF_LOCAL.
	//
	// Nothing behind our own base: the gate only ever asked "is this forward?"
	// and treated everything else as local work worth an allowance, lumping a
	// rear-mex tower in with one behind our own start position. Ground the
	// enemy can only reach by walking through everything else we own does not
	// need a turret -- except when they are actually standing on it.
	if ((ForwardFraction(pos) < 0.f) && !gTurtle && !BaseContested())
		return false;

	const float fShare = Targets::At(Targets::DEF_FRONT);
	const float lShare = Targets::At(Targets::DEF_LOCAL);
	const float total = (fShare + lShare > 0.f) ? (fShare + lShare) : 1.f;
	const bool forward = OnBorder(pos) || NearFront(pos);

	uint local = 0;
	for (uint i = 0; i < gFencePos.length(); ++i) {
		if (!OnBorder(gFencePos[i]) && !NearFront(gFencePos[i]))
			++local;
	}
	if (forward) {
		// THE FRONT LINE'S BUDGET IS A SHARE OF THE TEAM'S METAL, NOT A NUMBER OF
		// TOWERS. Counting towers against income made every tower cost the same:
		// an 85-metal Sentry and a 3,000-metal Pulsar each spent one unit of the
		// allowance, so opening the ladder to T2/T3 turrets multiplied the actual
		// spend without moving the count that was supposed to bound it. Both sides
		// of this comparison are metal, and both are the TEAM's -- one line, one
		// budget, however many of us are holding it.
		//
		// Ordered work is included through OwnFrontMetal: a bound that counts only
		// finished towers cannot bind on a line where nothing finishes.
		const float teamFrontM = TeamSum(TV_FMETAL, OwnFrontMetal());
		const float teamSpend = TeamSum(TV_MSPEND, Brain::gSpentTotal);
		if (teamSpend <= 1.f)
			return true;   // nothing built yet: the share is undefined, not exceeded
		const float want = Brain::TargetShare(Brain::DEFENCE)
				* pressureAllow * (fShare / total);
		return (teamFrontM / teamSpend) < want;
	}
	// Local work stays local: a mex guard defends OUR extractor with OUR metal.
	return float(local) < budget * (lShare / total);
}

void AiMakeDefence(int cluster, const AIFloat3& in pos)
{
	if (!ApexActive()) {
		aiMilitaryMgr.DefaultMakeDefence(cluster, pos);
		return;
	}

	NoteSite(cluster, pos);

	// Radar is not porc. Every early return below skips DefaultMakeDefence, and the
	// sensor block sits at its end, so a cluster we decline to WALL also gets no
	// EYES. Coverage is bounded in C++ by the same two things it always was: any
	// friendly radar (ours or an ally's) already within range, and the income-derived
	// maxCost.
	aiMilitaryMgr.DefaultMakeSensors(cluster, pos);

	if (gTurtle) {
		aiMilitaryMgr.DefaultMakeDefence(cluster, pos);  // porc hard while holding
		return;
	}

	const float armyFloor = EnemyArmyFloor();
	const float threat = aiEnemyMgr.mobileThreat;
	if (gPorcArmed ? (threat < armyFloor * PORC_RELEASE) : (threat >= armyFloor)) {
		gPorcArmed = !gPorcArmed;
		AiLog(Factory::T() + "apex: porc " + (gPorcArmed ? "ON" : "OFF") + " frame=" + ai.frame
			+ " mobileThreat=" + formatFloat(threat, "", 0, 1)
			+ "/" + formatFloat(armyFloor, "", 0, 1)
			+ " enemies=" + ai.GetEnemyTeamSize());
	}

	// Something to defend against. The opening bypasses this test: before either
	// side has an army, a single known raider still justifies one tower. A site
	// on the team's defence line is worth building regardless of the global
	// threat gate -- that is where attacks land, and a tower there that arrives
	// late arrives never.
	//
	// The tech lead's reticence toward defence is a smaller budget (see
	// DefenceAllowedAt), not a refusal -- its job is the plant, advanced cons and
	// T2 mexes, but threat still overrides since staying alive is its one early
	// job too.

	// The edge of what we hold, with the gadget front kept as a second opinion
	// where it exists.
	const bool onLine = OnBorder(pos) || NearFront(pos);

	const bool early = (ai.frame <= 5 * MINUTE) && (threat > 0.f);
	// A back-line cluster needs more than "the enemy owns an army somewhere":
	// gPorcArmed alone let every quiet rear mex through while the front had
	// nothing. Border sites bypass this -- that is where the fighting is. The
	// rear is allowed only while the defence budget is genuinely unspent, so a
	// raider that pierces the front still meets something without going back to
	// walling quiet mexes.
	if (!onLine && !early && !Brain::UnderBudget("fence"))
		return;

	// Something to pay with. Unchanged from the old gate, including the way that
	// same opening clause bypassed the income requirement outright.
	if ((ai.frame <= 5 * MINUTE) && (aiEconomyMgr.metal.income <= 10.f)
		&& !early && !onLine)
		return;

	// A front-line cluster still needs an enemy army to be worth walling: on a
	// small map almost every cluster reads as on-line, so `onLine` alone would
	// approve the whole map and DefaultMakeDefence would tower every point.
	if (!gPorcArmed && !gTurtle && !LosingGround() && !early)
		return;

	// One policy, asked the same way every other placement asks it -- and asked
	// WITH a def, so the crowd cap's tier exemption can see an upgrade coming.
	if (!DefenceAllowedAt(pos, LadderDef())) {
		if (ai.frame >= gNextFenceCapLog) {
			gNextFenceCapLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: defence refused here -- "
				+ gFenceId.length() + " standing, "
				+ (OnBorder(pos) ? "front" : "rear"));
		}
		return;
	}

	aiMilitaryMgr.DefaultMakeDefence(cluster, pos);
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
